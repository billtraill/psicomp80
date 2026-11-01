# COMP80 v2 firmware

Runs the unchanged COMP80 ROM images on the RP2350. Core 0 runs the Z80 at its
real speed, 1 ms at a time against the system timer, and feeds the HDMI output's
DMA. Core 1 runs the USB keyboard and redraws the characters that changed.

| File | |
|---|---|
| `src/z80.c` | The Z80, ported from the web emulator's `z80.js` |
| `src/comp80.c` | The memory map, ports, keyboard latch and NMI, after `comp80.js` |
| `src/mm57109.c` | The MM57109 model, as the web emulator and the MAME driver have it. The v3 FPGA's soft processor uses it too |
| `src/tape.c` | WAV tapes on IN 00 and OUT 20, in the MAME driver's format |
| `src/video.c` | HSTX HDMI at 640 × 480, and drawing the character cells |
| `src/keyboard.c` | TinyUSB host on PIO-USB: boot-protocol keyboards |
| `src/sdcard.c`, `src/storage.c` | The card in SPI mode under FatFs; ROMs, tapes and settings |
| `src/menu.c`, `src/main.c` | The set-up screen, start-up, clocks and pacing |
| `src/data.c` | The fonts and the built-in BURP ROM, made by `tools/make_data.py` |
| `host/` | The machine code built for the Mac, and `compare.sh` |
| `comp80v2.uf2` | A build: hold BOOTSEL, press RESET, copy it to the drive that appears |

## The microSD card

```
/COMP80/ROMS/*.ROM      ROM images: 3072 bytes, loaded at 0000
/COMP80/TAPES/*.WAV     tapes
/COMP80/COMP80.CFG      settings: ROM=, MEMORY=5 or 32, CLOCK=2000000 or 4000000, COLOUR=
```

With no card it runs the built-in monitor and BURP ROM. A ROM whose name contains
FORTH or LISP gets Backspace as RS, those ROMs' rub-out.

Keys: F1 set-up, F2 tapes, F12 power on again, Esc RESET, Ctrl+\ FS.

The Z80 runs at 2 MHz like the real machine. The MAME driver and the web emulator
run it at 4 MHz, and tapes recorded there play at twice the baud rate, so set
CLOCK=4000000 to load them. `life/life.wav` is one.

## Building

Pico SDK 2.2 with TinyUSB, and the Arm GNU toolchain. CMake fetches Pico-PIO-USB and
FatFs from GitHub unless `PICO_PIO_USB_PATH` and `FATFS_PATH` point at copies.

```bash
cd hardware_v2/firmware && cmake -B build -DPICO_SDK_PATH=/path/to/pico-sdk && cmake --build build
```

## Testing on a Mac

```bash
cd hardware_v2/firmware/host && make test
```

This runs every LISP, FORTH and BURP test session through `z80.c`, `comp80.c` and
`mm57109.c`, and compares the screens with `web/tools/session.js`; all 13 match.
`./session` also takes `tape=file.wav`, `record=file.wav`, `LOAD=file@addr` and
`CHECK=file@addr`. With those, `life.wav` loads byte for byte at 4 MHz, and a tape
recorded at 2 MHz loads back the same.

The hardware code (HDMI, USB, SD card, clocks) compiles but has not run on a board.
