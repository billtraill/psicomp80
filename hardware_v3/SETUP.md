# Setting up a COMP80 v3 board

This is for a built board, from first power-up to the COMP80's READY prompt. To
build the bitstream itself, see `VIVADO_TODO.md`.

## What you need

- The board, and a **5 V USB-C power supply** of at least 2 A for J1, the "USB-C"
  socket at the top left. A phone charger will do: the board asks for plain 5 V. It
  draws about 0.5 A by itself; the keyboard and a USB-C monitor's 5 V add to that.
- A **bitstream**: `vivado/out/comp80v3.bit` and the flash image
  `vivado/out/comp80v3.mcs`, built as `VIVADO_TODO.md` describes.
- A **JTAG cable** with Digilent's 6-pin header: a JTAG-HS2 or HS3 (or a
  compatible FT2232H cable).
- **Software for the cable**, either:
  - Vivado Lab Edition (free, Linux or Windows), or the full Vivado; or
  - [openFPGALoader](https://github.com/trabucayre/openFPGALoader), which also runs
    on macOS (`brew install openfpgaloader`).
- A **display**: an HDMI monitor or TV on J2, or a USB-C monitor that takes
  DisplayPort on J7, the "USB-C VIDEO" socket. Either or both.
- A **USB keyboard** for J3. It must be low speed, which nearly all keyboards are.
  Hubs and keyboards with a built-in hub don't work.
- A **microSD card** (FAT32, up to 32 GB), optional: the board runs BURP without
  one.
- Optional: a 3.3 V USB serial adapter for J6, to read the soft processor's console.

## 1. First power-up, before programming

1. Look the board over: no solder bridges on the FPGA's neighbours, the USB-C
   sockets' pins clean, the JTAG header J5 the right way round.
2. Plug in the power supply and nothing else. Nothing should get warm.
3. Measure the rails against ground (test points, or the bulk capacitors):

   | Rail | Expected | Where |
   |---|---|---|
   | +5V | 4.8 to 5.2 V | C15, beside J1 |
   | +3V3 | 3.28 to 3.36 V | C9 |
   | +1V8 | 1.75 to 1.85 V | C8 |
   | +1V0 | 0.97 to 1.03 V | C7 |
   | +2V5 | 2.45 to 2.55 V | C60 (bank 35, for the DisplayPort AUX channel and the FUSB302's I²C) |
   | +1V2 | 1.17 to 1.23 V | C62 (the transceivers' MGTAVTT) |

   If one is near zero, unplug and look for a short before going on.
4. The DONE LED (D2, green) stays off: the flash is still empty.

## 2. Program the FPGA

Connect the JTAG cable to J5. The pins are, from pin 1 (square pad): VREF, GND, TCK,
TDO, TDI, TMS. Check this against the cable's own label before plugging in: Digilent's
cables are marked on the header. The board must be powered while you program it.

### With Vivado or Vivado Lab

1. Open the Hardware Manager, then **Open Target → Auto Connect**. The
   `xc7a100t_0` should appear.
2. To try a bitstream (lost at power-off): **Program Device**, choose
   `comp80v3.bit`. DONE lights, and the screen comes up within a second.
3. To keep it: right-click the device, **Add Configuration Memory Device**, choose
   `is25lp128f-spi-x1_x2_x4`. Program it with `comp80v3.mcs`, leaving
   "Erase", "Program" and "Verify" ticked. When it finishes, press **PROG** (SW2) or
   power-cycle: the FPGA loads itself from the flash, and DONE lights.

The same from the Tcl console:

```tcl
open_hw_manager; connect_hw_server; open_hw_target
set dev [lindex [get_hw_devices xc7a100t_0] 0]
create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts is25lp128f-spi-x1_x2_x4] 0]
set mem [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.FILES [list out/comp80v3.mcs] $mem
set_property PROGRAM.ADDRESS_RANGE use_file $mem
set_property PROGRAM.BLANK_CHECK 0 $mem
set_property PROGRAM.ERASE 1 $mem
set_property PROGRAM.CFG_PROGRAM 1 $mem
set_property PROGRAM.VERIFY 1 $mem
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
program_hw_cfgmem -hw_cfgmem $mem
```

### With openFPGALoader

```bash
openFPGALoader --detect -c digilent_hs2
```

That should report an `xc7a100t`. Then, to try the bitstream:

```bash
openFPGALoader -c digilent_hs2 vivado/out/comp80v3.bit
```

And to write it to the flash, so it loads at every power-up:

```bash
openFPGALoader -c digilent_hs2 --fpga-part xc7a100tfgg484 -f vivado/out/comp80v3.bit
```

openFPGALoader loads a small bridge into the FPGA to reach the flash, writes the
bitstream, then reloads the FPGA from it. Use `-c digilent_hs3` for an HS3.

## 3. Prepare the microSD card

Format it FAT32 and make this layout:

```
/COMP80/ROMS/     the ROM images: BURP.ROM, LISP.ROM, FORTH.ROM, ...
/COMP80/TAPES/    cassette recordings as .WAV files
/COMP80/COMP80.CFG  written by the board: the chosen ROM, memory, clock and colour
```

The ROM images are this repository's `psicomp80.rom` (the monitor and BURP),
`psicomp80_forth.rom` and `psicomp80_lisp.rom`, the same files as for v2. Copy them
under short names, such as `BURP.ROM`, `FORTH.ROM` and `LISP.ROM`: the card is read
with 8.3 names, and only files ending `.ROM` are listed. A name with FORTH or LISP in
it makes the backspace key send the RUB OUT code those ROMs expect. Without a card, or with no ROMs on it, the board runs the
built-in BURP.

## 4. First run

1. Fit the card in J4, plug a keyboard into J3 and a monitor into J2 or J7, then
   power up.
2. DONE lights. Within a second the screen shows the COMP80 monitor's **READY**.
   The HALT LED (D1, red) is lit while the Z80 waits for a key, as on the original.
3. Type. The keys are the COMP80's, with a few of the PC keyboard's put to use:

   | Key | Does |
   |---|---|
   | F1 | The set-up page: ROM, memory (5K or 32K), clock (2 or 4 MHz), colour |
   | F2 | Tapes: play a .WAV into the COMP80, or record one |
   | F12 | Power on again with the chosen settings (memory is cleared) |
   | Esc | The COMP80's RESET key: the Z80 restarts, memory stays |
   | Backspace | DEL, or RUB OUT under LISP and FORTH |

   On the set-up page, the arrows choose and change, Return selects, and F1 or Esc
   goes back. Choices are saved to `COMP80.CFG` on the card.
4. The **RESET** button (SW1) powers the COMP80 on again, as F12 does. **PROG**
   (SW2) reloads the whole FPGA from the flash.

The 2 MHz clock is the real machine's. Choose 4 MHz to load tapes recorded from MAME
or the web emulator, which run at 4 MHz.

## 5. A USB-C monitor

J7 gives DisplayPort over USB-C (DisplayPort alternate mode), 800 × 600 at 60 Hz on
one lane, with the same screen as HDMI. The monitor must take DisplayPort over its
USB-C input; most USB-C monitors and portable screens do. Use a full-featured USB-C
cable (one rated for video, or "USB 3.1 Gen 1" or better); a charge-only cable has
no high-speed pairs and the monitor stays dark.

When a monitor is plugged in, the board:

1. sees it on one of the CC pins, which tells it which way up the plug is;
2. turns on 5 V to the monitor (VBUS, up to 0.5 A, through U7);
3. agrees a USB Power Delivery contract, then asks the monitor for DisplayPort
   mode and the pin assignment (C, E or D);
4. sets the lanes and the AUX wires for the plug's orientation, and starts the
   DisplayPort link when the monitor reports hot-plug.

It takes a second or two. The serial console shows each step (below). Unplugging and
plugging again starts over. While a tape is playing or recording, the board puts off
noticing a new monitor until the tape stops, so as not to disturb the tape timing.

The board doesn't take power from J7: a monitor that offers to charge its source
gives nothing here. Power always comes from J1.

## 6. The serial console

J6 carries the soft processor's console out at **115200 baud, 8N1, 3.3 V**: pin 1 is
TX, pin 2 ground. Connect pin 1 to the adapter's RX and pin 2 to its ground; leave the
adapter's own TX and power unconnected. At power-up it prints:

```
COMP80 v3
USB-PD: FUSB302 id 91
```

followed by `no microSD card: the built-in BURP ROM` if there's no card. The id is
the FUSB302B's version register: anything from 80 to AF is right. With a USB-C
monitor it goes on:

```
USB-PD: monitor on CC1
USB-PD: DisplayPort mode, pin assignment C, hot-plug 1
```

CC1 or CC2 is the plug's orientation.

## Troubleshooting

| Symptom | Look at |
|---|---|
| DONE never lights | The flash wasn't written, or the wrong flash part was chosen: it's `is25lp128f`. Program the .bit over JTAG to see whether the design itself runs. Check the +1V0 and +1V8 rails. |
| The cable finds no device | J5 the wrong way round, the board not powered, or VREF not connected (the cable needs it). |
| DONE lights but no HDMI picture | Try another monitor: it's 640 × 480 at 60 Hz, which some TVs won't show. The console should still say `COMP80 v3`. |
| The console prints nothing | The adapter's RX on pin 1, and its ground on pin 2; 115200 baud. |
| The picture is there but keys do nothing | A full-speed keyboard, or one behind a hub. Try a plain wired one. |
| The card isn't found | It must be FAT32 (not exFAT, so 32 GB or less) with a `/COMP80` folder. |
| A ROM loads but behaves oddly | Check the memory setting: LISP and FORTH need 32K (the expansion). |
| A tape won't load | The clock: MAME and web-emulator tapes need 4 MHz. |
| USB-C monitor stays dark, console says `no DisplayPort mode` | The monitor's USB-C port doesn't take DisplayPort. |
| USB-C monitor stays dark, console says `no answer` | The monitor didn't answer USB-PD: a charge-only cable, or a monitor that needs more than 5 V. |
| USB-C monitor finds the mode but shows nothing | The link didn't train. Try the plug the other way up: if one way works, the lane order or AUX polarity for the other orientation is wrong (see `VIVADO_TODO.md`). |
| The FUSB302 id reads `00` | The I²C to U6 isn't working: check R27 and R28 (pull-ups to 2.5 V), the +2V5 rail and U6's soldering. |

## Updating

- **A new bitstream**: write it to the flash again as in step 2. The firmware is
  inside the bitstream, so a firmware change means a rebuild (`VIVADO_TODO.md`, last
  section).
- **ROMs and tapes**: just copy them onto the card.
