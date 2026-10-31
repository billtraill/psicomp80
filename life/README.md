# Game of Life

Conway's Game of Life for the PSI COMP80, in Z80 assembly. The board is
128 x 64 cells: each screen character shows a 2 x 2 block of cells using the
quadrant graphics characters. The edges wrap around.

## Loading from tape

The quickest way: let `autorun.lua` load the tape and start it.

    cd ~/localdev/mame && ./mamed psicomp80 -cass ~/localdev/psicomp80/life/life.wav \
      -autoboot_script ~/localdev/psicomp80/life/autorun.lua

It clears any half-typed command, runs READ (fast-forwarded), checks the loaded
bytes against `life.bin`, retries if they're wrong, then types `RUN 1000`.
Don't touch the keyboard until the board appears.

By hand:

1. Start MAME with the tape mounted:

       cd ~/localdev/mame && ./mamed psicomp80 -cass ~/localdev/psicomp80/life/life.wav

2. Type `READ 1000`, then Tab → Tape Control → Play, then Tab to close the menu.
3. After about 20 seconds, when the tape stops, press any key to end READ.
4. Type `RUN 1000`.

## Keys

| Key | Action |
|---|---|
| R | new random board |
| P | pause (shows PAUSED); P again resumes |
| S | stop, back to the monitor |

Other keys are ignored. A generation takes about 0.65 s in the emulator (the
driver runs the Z80 at 4 MHz; on a real 2 MHz COMP80 it would be about 1.3 s).

## How keys are read while it runs

On the COMP80 a keypress causes an NMI, and the monitor's NMI handler jumps to
0000 (restarting the monitor) unless the CPU was sitting in a HALT. It decides
that by looking at the byte before the return address on the stack.

While the game is running, SP points into ROM (06B8h). The NMI's push is lost
because ROM ignores writes, so the handler reads the ROM word at 06B6h, 1013h,
as the return address. The program puts a HALT opcode (76h) at 1012h, so the
check passes and the handler returns to the key handler at 1013h with the key
in A. Return takes a different path through the ROM that ends at 127Eh, which
holds a jump back into the main loop. Because the stack is ROM, the running code
uses no CALL, PUSH or POP. See the comments at the top of `life.asm`.

## Files

| File | |
|---|---|
| `life.asm` | source |
| `life.bin` | assembled program, 1000h–12DFh |
| `life.wav` | tape (`TAPE 100012E0`) |
| `autorun.lua` | MAME autoboot script: load from tape and run |
| `test_life.lua` | MAME test: checks 10 generations against a reference implementation, then P, Return, R and S |

## Rebuilding

    brew install z80asm
    z80asm -i life.asm -o life.bin

Record the tape with `../pictures/record_tape.lua` (see `../pictures/README.md`),
using `C80_BIN=.../life.bin`. Run the test from the MAME directory:

    LIFE_BIN=~/localdev/psicomp80/life/life.bin ./mamed psicomp80 -rompath roms \
      -autoboot_script ~/localdev/psicomp80/life/test_life.lua \
      -nothrottle -video none -sound none
