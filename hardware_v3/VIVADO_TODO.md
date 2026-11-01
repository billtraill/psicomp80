# To do: build the bitstream with Vivado

Vivado doesn't run on macOS, so the v3 design has been simulated and synthesised
with open-source tools (Verilator, Icarus Verilog, yosys) but never run through
Vivado. Pick this up on a Linux or Windows machine.

## What's already done

- `sim/`: the machine (`rtl/comp80_machine.v`, a Verilog Z80 and its memory and
  ports) runs LISP, FORTH and BURP sessions with screens identical to the v2 C core
  (`make -C sim test`). The whole system, with the soft processor running its
  firmware, boots and reaches the monitor's READY prompt (`make -C sim boot`). The
  display logic draws correct frames, and every TMDS symbol decodes back to its pixel
  (`sim/video_tb.v`).
- `tools/synth.sh`: yosys synthesises the whole design for the XC7A100T. It comes
  to about 4,100 LUTs (6.5%), 2,240 flip-flops (1.8%) and 49 of 135 block RAMs, plus
  one PLL, one MMCM and eight OSERDESE2. No DSPs.
- `rtl/comp80v3.xdc`: pins, I/O standards, the clock and the bitstream settings,
  generated from the board design (`tools/design.py`), so the two agree.

Nothing has been through Vivado's timing analysis, and no board has been made.

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

That puts TV80, PicoRV32, usb_hid_host and FatFs in `build/`, at the commits the
design was made with.

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

- [ ] **Timing**: `out/timing.txt` must show no negative slack (WNS ≥ 0) on every
  clock: 50 MHz system, 12 MHz USB, 25 MHz pixel, 125 MHz serial.
  - The Z80 (TV80) runs from the 50 MHz clock with a clock enable every 25 (or 12.5)
    cycles. If its paths fail at 50 MHz, they can be given multicycle constraints,
    because nothing in `tv80c`/`tv80_core` changes between enables, for example:
    `set_multicycle_path 12 -setup -from [get_cells -hier -filter {NAME =~ machine/z80/*}] -to [get_cells -hier -filter {NAME =~ machine/z80/*}]`
    and the matching `-hold 11`. Check that the clock enable reaches every register
    first.
  - PicoRV32 at 50 MHz is comfortably inside what it does on an Artix-7.
- [ ] **Utilisation**: about 4,100 LUTs and 49 block RAMs, as yosys found. Far more
  means something has been unrolled. Far fewer usually means a `$readmemh` file
  wasn't found and a memory was optimised away. Check that `firmware.hex` and
  `font.hex` loaded: the synthesis log names them.
- [ ] **Warnings worth reading**:
  - `usb_dp`/`usb_dm` must come out as IOBUFs (usb_hid_host drives them tri-state).
  - The OBUFDS outputs must sit on true pairs: A13/A14, A15/A16, B15/B16 and A18/A19
    are L10, L9, L7 and L17 of bank 16.
  - `clk100` is on B17, a clock-capable (SRCC) pin, so there should be no
    CLOCK_DEDICATED_ROUTE warning.
  - The MMCM (VCO 625 MHz, ×6.25 ÷25 and ÷5) and the PLL (VCO 1200 MHz, ÷24 and ÷100)
    should both be legal for the −1 speed grade.
- [ ] **DRC**: `out/drc.txt`. With `CFGBVS` and `CONFIG_VOLTAGE` set, the usual
  configuration-voltage warning should be gone.

## 4. Program the board

The JTAG header J5 takes Digilent's 6-pin cables (JTAG-HS2, HS3), in the order VREF,
GND, TCK, TDO, TDI, TMS. **Check that against the cable before plugging in.**

- [ ] For a first try, program `out/comp80v3.bit` from the Hardware Manager. It's
  lost at power-off.
- [ ] To keep it, add the configuration memory device `is25lp128f-spi-x1_x2_x4`,
  program `out/comp80v3.mcs`, then press PROG (SW2). The FPGA reloads from the flash.
  DONE (D2) lights when it has.

## 5. Bring-up

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

## Points to review on the board itself

These are judgement calls in `tools/design.py`, worth checking against Xilinx's
documents before a board is ordered:

- **Unused transceivers**: MGTAVCC, MGTAVTT and the receive pins are grounded;
  MGTRREF, the transmit pins and the reference clocks are left open. Check against
  UG482's advice for devices whose transceivers are all unused.
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
