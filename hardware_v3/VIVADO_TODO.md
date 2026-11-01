# To do: build the bitstream with Vivado

Vivado doesn't run on macOS, so the v3 design was simulated and synthesised with
open-source tools (Verilator, Icarus Verilog, yosys) first. **Steps 1–3 have now been
done** on Windows with Vivado 2026.1 (1 November 2026): the bitstream builds and meets
timing. What's left is a board: steps 4 and 5.

## What's already done

- `sim/`: the machine (`rtl/comp80_machine.v`, a Verilog Z80 and its memory and
  ports) runs LISP, FORTH and BURP sessions with screens identical to the v2 C core
  (`make -C sim test`). The whole system, with the soft processor running its
  firmware, boots and reaches the monitor's READY prompt (`make -C sim boot`). The
  display logic draws correct frames, and every TMDS symbol decodes back to its pixel
  (`sim/video_tb.v`).
- DisplayPort over USB-C (`rtl/dp_out.v`): `sim/dp_tb.v` runs the COMP80 DisplayPort source
  and hamsternz's stream-attribute inserter, and `sim/dp_decode.py` unpacks
  the lane symbols back into an 800 × 600 frame: every pixel matches the screen. The
  transceivers and the AUX channel can't be simulated here (they're Xilinx
  primitives and a monitor), so those are the parts to watch on the bench.
- `tools/synth.sh`: yosys synthesises the whole design for the XC7A100T. It comes
  to about 5,900 LUTs (9%), 3,600 flip-flops (2.8%) and 50 of 135 block RAMs, plus
  one PLL, one MMCM, eight OSERDESE2, and for DisplayPort one GTPE2_COMMON, four
  GTPE2_CHANNEL and an IBUFDS_GTE2. No DSPs.
- `rtl/comp80v3.xdc`: pins, I/O standards, the clock and the bitstream settings,
  generated from the board design (`tools/design.py`), so the two agree.

- Vivado 2026.1: `vivado/build.tcl` builds `out/comp80v3.bit` and `out/comp80v3.mcs`
  with every clock meeting timing (see section 3). The first run found that the
  GTPs' own clocks weren't declared, so the DisplayPort symbol domain had gone
  untimed (hamsternz's constraints have the same lines commented out). Declaring them
  showed `dp_comp80_source.v` missing 135 MHz by 64 ps, fixed by registering
  `next_dot`; its symbol output is unchanged, bit for bit, in `sim/dp_tb.v`.

No board has been made.

Vivado 2026.1's ML Standard edition needs a free node-locked licence from AMD's
licensing site; put `Xilinx.lic` in `~/.Xilinx/` (on Windows,
`C:\Users\<you>\.Xilinx\`).

## 1. Set up the machine

- **Vivado ML Standard** (the free edition), 2024.1 or later. It covers the
  XC7A100T. Install Artix-7 device support.
- **git**, to fetch the outside HDL.
- To rebuild the soft processor's firmware (optional, since `firmware/firmware.hex`
  is committed): a RISC-V GCC, such as xPack's `riscv-none-elf-gcc` 15, and GNU make.

```bash
git clone <this repository> && cd psicomp80/hardware_v3
```

```bash
sh tools/fetch.sh
```

That puts TV80, PicoRV32, usb_hid_host, DisplayPort_Verilog and FatFs in `build/`,
at the commits the design was made with.

## 2. Build

```bash
cd vivado && vivado -mode batch -source build.tcl
```

`vivado/build.tcl` is non-project mode. It reads the sources and the XDC, then
synthesises, places, routes, and writes `out/comp80v3.bit` and the flash image
`out/comp80v3.mcs`. It also writes `out/utilisation.txt`, `out/timing.txt` and
`out/drc.txt`. To use the GUI instead, make a project for `xc7a100tfgg484-1` with
the same files, add `font.hex`, `firmware.hex` and `usb_hid_host_rom.hex` as memory
files, and set `top` as the top module.

## 3. Check the results

- [x] **Timing**: `out/timing.txt` must show no negative slack (WNS ≥ 0) on every
  clock: 50 MHz system, 12 MHz USB, 25 MHz pixel, 125 MHz serial, 100 MHz (the
  DisplayPort AUX channel and link management) and the transceivers' 135 MHz symbol
  clock (TXOUTCLK). *Met: worst setup slack 0.46 ns (`dp_symbol`), worst hold 0.065 ns;
  50 MHz has 5.7 ns to spare, so the Z80 needs no multicycle paths. `check_timing`
  shows no unclocked registers; the only unconstrained paths are the slow
  asynchronous I/O pins.*
  - The Z80 (TV80) runs from the 50 MHz clock with a clock enable every 25 (or 12.5)
    cycles. If its paths fail at 50 MHz, they can be given multicycle constraints,
    because nothing in `tv80c`/`tv80_core` changes between enables, for example:
    `set_multicycle_path 12 -setup -from [get_cells -hier -filter {NAME =~ machine/z80/*}] -to [get_cells -hier -filter {NAME =~ machine/z80/*}]`
    and the matching `-hold 11`. Check that the clock enable reaches every register
    first.
  - PicoRV32 at 50 MHz is comfortably inside what it does on an Artix-7.
- [x] **Utilisation**: about 5,900 LUTs and 50 block RAMs, as yosys found. *Vivado:
  5,582 LUTs (8.8%), 3,228 flip-flops, 50.5 block RAMs, no DSPs.* Far more
  means something has been unrolled. Far fewer usually means a `$readmemh` file
  wasn't found and a memory was optimised away. Check that `firmware.hex` and
  `font.hex` loaded: the synthesis log names them.
- [x] **Warnings worth reading** (*all as expected: no critical warnings, no
  CLOCK_DEDICATED_ROUTE, no GTPE2/MMCM/PLL DRC; the USB and AUX pins came out as
  tristate buffers*):
  - `usb_dp`/`usb_dm` must come out as IOBUFs (usb_hid_host drives them tri-state).
  - The OBUFDS outputs must sit on true pairs: A13/A14, A15/A16, B15/B16 and A18/A19
    are L10, L9, L7 and L17 of bank 16.
  - `clk100` is on B17, a clock-capable (SRCC) pin, so there should be no
    CLOCK_DEDICATED_ROUTE warning.
  - The MMCM (VCO 625 MHz, ×6.25 ÷25 and ÷5) and the PLL (VCO 1200 MHz, ÷24 and ÷100)
    should both be legal for the −1 speed grade.
  - The four GTPE2_CHANNELs must land in quad 216, the part's only one, to
    reach pins B4/A4, D5/C5, B6/A6 and D7/C7, and the IBUFDS_GTE2 on F6/E6
    (MGTREFCLK0_216). If Vivado complains that it can't place them, add `LOC`s.
    The channels are taken in reverse, `dp_tx[0]` on D7/C7 and `dp_tx[3]` on
    B4/A4, so that the pairs reach J7 without crossing; any channel can drive
    any pair, since the logic maps lanes onto pairs.
  - The transceiver settings in `rtl/dp_transceivers.v` come from hamsternz's Nexys
    Video design (a 135 MHz reference, the PLL at 2.7 GHz, 20-bit TX data). Vivado
    checks the PLL0 settings against the reference: look for GTPE2 DRC warnings.
  - `dp_aux_p`/`dp_aux_n` must be an IOBUFDS in LVDS_25, on bank 35 at 2.5 V, with
    no internal termination.
  - Warnings that `txdata_for_tx[31:16]` and the upper `txchardisp*` bits have no
    driver are expected: the GTPs run 2-byte (20-bit) TX data, as in the original,
    and the unused upper bits are tied off.
- [x] **DRC**: `out/drc.txt`. With `CFGBVS` and `CONFIG_VOLTAGE` set, the usual
  configuration-voltage warning should be gone. *It is. Left: LVDS-1 (the AUX pair is
  bidirectional LVDS_25, as on hamsternz's boards; it's point to point, so fine) and
  REQP-1839/1840, because TV80's address register has an asynchronous reset and
  drives block RAM addresses. At worst a reset could disturb one byte of memory as it
  happens, which the reset clears anyway.*

## 4. Program the board

The JTAG header J5 takes Digilent's 6-pin cables (JTAG-HS2, HS3), in the order VREF,
GND, TCK, TDO, TDI, TMS. **Check that against the cable before plugging in.**

- [ ] For a first try, program `out/comp80v3.bit` from the Hardware Manager. It's
  lost at power-off.
- [ ] To keep it, add the configuration memory device `is25lp128f-spi-x1_x2_x4`,
  program `out/comp80v3.mcs`, then press PROG (SW2). The FPGA reloads from the flash.
  DONE (D2) lights when it has.

## 5. Bring-up

`SETUP.md` is the full guide for a working board. On a first board:

- [ ] Before fitting the FPGA, or with it fitted but not configured: check the
  rails, 1.0 V, 1.8 V and 3.3 V, and that none is shorted.
- [ ] After configuring, the serial header J6 (115200 baud) prints `COMP80 v3`, then
  says whether it found a microSD card.
- [ ] HDMI shows the monitor's `READY` prompt, and the HALT LED (D1) is lit while it
  waits for a key.
- [ ] A USB keyboard types. Low-speed keyboards only, which is most of them;
  usb_hid_host doesn't do full speed or hubs.
- [ ] The card: put ROMs in `/COMP80/ROMS` and tapes in `/COMP80/TAPES` (as for v2).
  Choose them with F1 and F2.
- [ ] The serial console prints `USB-PD: FUSB302 id 9x` (or 8x, Ax). `00` means
  the I²C to U6 isn't working.
- [ ] A USB-C monitor on J7: the console shows `monitor on CC1` (or CC2), then
  `DisplayPort mode`. The monitor gets 5 V (VBUS) as soon as it's seen: check
  that U7's EN is active high (the firmware drives `vbus_en` high to turn it on) and
  that VBUS at J7 is 5 V.
- [ ] The picture over DisplayPort, **with the plug both ways up**. The lane
  mapping and AUX polarity for each orientation are worked out from the USB-C and
  DisplayPort alt-mode pin tables, not measured; they're the constants `LANES_CC1`,
  `LANES_CC2` and the `aux_invert` choice in `firmware/pd.c`. If one orientation
  trains and the other doesn't, swap that orientation's lane pairs or its AUX
  polarity there. If neither trains, the AUX channel is the first suspect: watch
  SBU1/SBU2 with a scope for the 1 Mb/s Manchester bursts after hot-plug.

## Points to review on the board itself

These are judgement calls in `tools/design.py`, worth checking against Xilinx's
documents before a board is ordered:

- **Transceivers**: MGTAVCC is +1V0_MGT, the 1.0 V rail through ferrite bead FB1,
  and MGTAVTT is a TLV75512 LDO's 1.2 V from 3.3 V. Each is a copper island in an
  inner plane under the BGA's top-left corner. MGTRREF has its 100 Ω to MGTAVTT.
  The receive pins are grounded, as UG482 advises for unused receivers; MGTREFCLK1
  is left open. The four transmit pairs go to J7 through 100 nF capacitors. Check
  UG482's power-supply filtering and the island shapes before ordering.
- **Bank 35 at 2.5 V**: VCCO_35 is a TLV75525's 2.5 V, so that LVDS_25 is legal for
  the AUX channel. Its six balls reach it through an island in the 3.3 V plane under
  the BGA's left columns. The FUSB302 lines on that bank are LVCMOS25, pulled up to 2.5 V.
- **The 135 MHz oscillator** (SiT9121, LVDS) is AC-coupled into MGTREFCLK0 through
  C55 and C56, with the termination inside the GTP.
- **XADC unused**: VCCADC to 1.8 V; GNDADC, VP, VN, VREFP and VREFN grounded.
  **VCCBATT** grounded (no encryption key). DXP and DXN open.
- **Configuration**: M[2:0] = 001 (Master SPI), CFGBVS to 3.3 V, PUDC_B to 3.3 V
  through 1 k (I/O pull-ups off while configuring), PROGRAM_B and INIT_B pulled up
  through 4.7 k, DONE through 330 Ω with its LED.
- **Power**: three TLV62569 bucks. The feedback dividers give 0.999 V, 1.8 V and
  3.32 V. All three start together; Xilinx recommends VCCINT before VCCAUX before
  VCCO for the least inrush, but doesn't require it. Decoupling is UG483's
  recommendation, rounded, on the top side round the BGA. Moving the 0.47 µF ones to
  the bottom, under the balls, would be better.
- **HDMI** is driven straight from TMDS_33 outputs, as Digilent's Artix-7 boards do.
  It carries no sound and no hot-plug or DDC.

## Changing the firmware later

The soft processor's program is the initial contents of its block RAM, so a new
`firmware.hex` means a new bitstream. Re-running `build.tcl` works. Vivado's
`updatemem` can also swap the RAM contents into an existing bitstream without
re-implementing, given the memory map from `write_mem_info`.
