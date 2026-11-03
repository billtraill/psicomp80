# Plasma

A moving plasma for the PSI COMP80, in Z80 assembly. Each of the 64 x 32
characters is the sum of four sine waves (two across, one down, one diagonal),
turned into one of six shades made from the quadrant graphics characters:
blank, one quarter, two diagonal quarters, the fine checkerboard, three
quarters and solid. The waves drift every frame, so the bands of shading flow
across the screen.

It runs at about 21 frames a second in the emulator (the driver runs the Z80
at 4 MHz; a real 2 MHz COMP80 would manage about 10).

## Running it

    ./c80.sh plasma

or in the monitor: load `plasma.bin` at 1000h and type `RUN 1000`.

Any key stops it. A key strobes NMI, and because the program never sits in a
HALT the monitor's NMI handler restarts the monitor, which prints READY on the
top line. The plasma stays on the rest of the screen.

## How it is fast enough

- The sine table (256 bytes, values 0-63) is part of the program, at 1100h, so
  a wave is one table lookup. Four waves add up to at most 252, which fits a
  byte.
- The two across-waves are worked out once a frame for each column (COLS,
  13C0h), and the down-wave once a row, so each character costs one
  diagonal-wave lookup, two additions and a lookup in a 256-byte shade table
  (PAL, 1200h, built at the start).
- The screen pointer lives in the alternate HL (EXX), so the inner loop needs
  no index registers: 89 T-states a character.

## Files

| File | |
|---|---|
| `plasma.asm` | source |
| `plasma.bin` | assembled program, 1000h-11FFh |
| `test_plasma.lua` | MAME test: measures the frame rate, checks the screen holds only the six shades, takes a snapshot, then checks a key stops it |

## Rebuilding

    brew install z80asm
    z80asm -i plasma.asm -o plasma.bin

z80asm has no `high` operator (it reports an error but still writes a file),
so the page numbers are separate `equ`s. Run the test from the MAME directory:

    PLASMA_BIN=~/localdev/psicomp80/plasma/plasma.bin ./mamed psicomp80 -rompath roms \
      -autoboot_script ~/localdev/psicomp80/plasma/test_plasma.lua \
      -nothrottle -video none -sound none
