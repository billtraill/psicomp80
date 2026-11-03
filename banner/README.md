# Scrolling banner

A message in big letters scrolls from right to left across the middle of the
PSI COMP80's screen, round and round. In Z80 assembly.

The letters are 5 x 7 dots (`font.py` draws them), and each dot is two
characters wide and one tall, 12 x 10 points, so the dots are nearly square
and five letters and a bit fit across. The scroll moves a quarter of a dot,
half a character, at a time: a character can be the right half of one dot and
the left half of the next, with the quadrant graphics characters 49h (left
half) and 46h (right half). At the start speed it does about 39 steps a
second, a letter in about 0.6 s.

## Running it

    ./c80.sh banner

or in the monitor: load `banner.bin` at 1000h and type `RUN 1000`. Any key
stops it: the program never sits in a HALT, so the monitor's NMI handler
restarts the monitor.

## Changing the message

The message is at 1400h, ending with a 00 byte, up to 255 characters. Lower
case is shown as capitals; the letters, digits and signs from space to `_`
all have shapes. In the monitor, before `RUN 1000`:

    LOAD 1400 [HELLO THERE   ]00@

`[` and `]` switch LOAD to typing text and back. LOAD stores letters as the
screen codes 01h-1Ah, which the banner takes as A-Z too, and it keeps the `[`
and `]` themselves (1Bh and 1Dh), which the banner leaves out. Leave a few
spaces at the end so the end of the message doesn't run into its start.

The byte at 1005h is the pause between steps: 12 to start with, 0 for flat
out (about 64 steps a second), FF for very slow.

## How it works

At the start the message is turned into columns of dots, 1500h on: five
bytes from the font for each letter (bit 0 the top row) and an empty column.
The first 34 columns are copied again after the end, so the screen can run
off the end without wrapping round. Each frame then draws the 64 screen
columns: column c shows dot columns (p + 2c) / 4 and (p + 2c + 1) / 4, where
p is the position in quarter dots, and each of the seven rows is one of four
characters, empty, left half, right half or full, looked up in a little
table at 1340h.

## Files

| File | |
|---|---|
| `banner.asm` | source |
| `font.py` | draws the letters; writes `font.inc` |
| `font.inc` | the font, included by `banner.asm` |
| `banner.bin` | assembled program, 1000h-1434h (with the message) |
| `test_banner.lua` | MAME test: measures the speed, checks the letters move left half a character a step, changes the message with LOAD and runs it again, then checks a key stops it |

## Rebuilding

    python3 font.py
    z80asm -i banner.asm -o banner.bin

Run the test from the MAME directory:

    BANNER_BIN=~/localdev/psicomp80/banner/banner.bin ./mamed psicomp80 -rompath roms \
      -autoboot_script ~/localdev/psicomp80/banner/test_banner.lua \
      -nothrottle -video none -sound none
