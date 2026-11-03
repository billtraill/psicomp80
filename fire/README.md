# Fire

Flames for the PSI COMP80, in Z80 assembly. Each of the 64 x 32 characters
has a heat from 0 to 63, shown with the six shades the plasma uses: blank,
one quarter, two diagonal quarters, the fine checkerboard, three quarters and
solid.

Every frame, two hidden rows below the screen get random heat, each cell
either 63 or 0 (a bit from a 16-bit LFSR). Then every cell, from the top
down, becomes the average of the three cells below it and the one two below,
less 2 for cooling. The heat drifts up, spreads sideways and dies away, so
the flames flicker up to about half way.

It runs at about 11.5 frames a second in the emulator (the driver runs the
Z80 at 4 MHz; a real 2 MHz COMP80 would manage about 6).

## Running it

    ./c80.sh fire

or in the monitor: load `fire.bin` at 1000h and type `RUN 1000`. Any key
stops it: the program never sits in a HALT, so the monitor's NMI handler
restarts the monitor.

## How it works

- The average and the cooling come from one 256-byte table (1100h): the sum
  of four heats is at most 252, so it fits a byte, and the table gives
  max(0, sum / 4 - 2). A second table (1200h) gives the shade for each heat.
  Both are built at the start.
- The heats are kept at 1400h, 34 rows of 64 with the same layout as the
  screen. IX points at the cell below the one being worked out, so the four
  heats are (IX-1), (IX), (IX+1) and (IX+64) and the new one goes to (IX-64).
  Rows below haven't been changed yet, so it can work in place. About 175
  T-states a character.

## Files

| File | |
|---|---|
| `fire.asm` | source |
| `fire.bin` | assembled program, 1000h-10A7h |
| `test_fire.lua` | MAME test: measures the frame rate, checks the screen holds only the six shades and is hotter at the bottom than the top, takes a snapshot, then checks a key stops it |

## Rebuilding

    z80asm -i fire.asm -o fire.bin

Run the test from the MAME directory:

    FIRE_BIN=~/localdev/psicomp80/fire/fire.bin ./mamed psicomp80 -rompath roms \
      -autoboot_script ~/localdev/psicomp80/fire/test_fire.lua \
      -nothrottle -video none -sound none
