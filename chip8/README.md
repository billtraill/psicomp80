# COMP80 CHIP-8

[Run CHIP-8 in the web emulator](https://billtraill.github.io/psicomp80/emulator.html#rom=chip8). Each example below has a ▶ link that types it in and runs it there.

A CHIP-8 interpreter for the PSI COMP80 that replaces BURP in the ROM. The
monitor (0000-03FF) is unchanged; the interpreter fills the 2 KB at
0400-0BFF where BURP was. As with BURP, the RS key enters it from the
monitor's READY state, and it runs the CHIP-8 program at 0E00.

CHIP-8 is the virtual machine Joseph Weisbecker wrote for the COSMAC VIP in
1977. Its display is 64 × 32 pixels, which is the COMP80's screen exactly:
each pixel is one character, a solid block or a space.

## Running a program

CHIP-8 memory is 4 KB at 0C00-1BFF: CHIP-8 address *a* is at 0C00 + *a*.
Programs start at CHIP-8 address 200, so they load at **0E00**. Put one
there from the monitor (FS for READY), with `LOAD 0E00` and its bytes in
hex, or from tape, then press RS. With no program at 0E00, RS shows a page
saying how to load one.

While a program runs, RS starts it again from the beginning (memory is
kept, so it is still there), and FS goes back to the monitor.

The 16 CHIP-8 keys are on the left of the keyboard:

    CHIP-8   1 2 3 C        COMP80   1 2 3 4
             4 5 6 D                 Q W E R
             7 8 9 E                 A S D F
             A 0 B F                 Z X C V

The COMP80 keyboard tells the computer when a key goes down but not when
it comes up, so a key counts as held for a third of a second after it is
pressed; a key held down on the host repeats, and keeps it held.

## Example programs

`examples/` has four programs of my own, as source (`.c8`) and assembled
(`.ch8`):

| | |
|---|---|
| `bounce.ch8` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=c8bounce) | A ball bouncing round a box at the edge of the screen, timed with the delay timer. |
| `keys.ch8` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=c8keys) | Press a key and it is shown as a big hex digit, built from the font a bit at a time, with the number of presses in decimal underneath. Shows FX0A, FX29, FX33 and FX65. |
| `dodge.ch8` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=c8dodge) | A game: rocks fall, and A and D steer the ship at the bottom out of their way. Each rock that gets past scores a point, and they fall faster as the score goes up. When a rock hits the ship the score is shown; a key starts again. |
| `kaleido.ch8` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=c8kaleido) | A dot wanders at random, mirrored into all four quarters of the screen; DRW flips the pixels, so the pattern keeps changing. |

`tools/c8asm.py` assembles them (`build.sh` runs it). It takes the
mnemonics of Cowgod's CHIP-8 reference (`LD V0, 5`, `DRW V0, V1, 4`,
`LD B, VE` …), labels, `name = value`, and `DB`/`DW`; binary numbers may use
`.` for 0, so sprites can be drawn: `DB 0b.11.....`.

## How it works

`chip8.asm` is the interpreter; `build.sh` assembles it with z80asm and
puts the monitor in front of it to make `../psicomp80_chip8.rom`.

**Keys while it runs.** Every key is an NMI, and the monitor's NMI handler
goes back to the monitor unless the byte before the address it interrupted
is a HALT. As in `../life/life.asm`, the interpreter runs with the stack
pointer in ROM: the NMI's push is lost, and the handler reads the ROM word
TRAP, which points at the key handler with a HALT in front of it. Return
goes through the monitor's PAD_TO_NEXT_LINE, whose CALL, RST 20h and RET use
the ROM words below TRAP; those all lead back round PAD's loop and out to
KEYCR, so even a second key in the middle of it is taken.

**Starting an instruction again.** Whatever was interrupted is lost (HL, A
and the flags), so every CHIP-8 instruction can be started again. The
CHIP-8 registers are kept twice, at 1D00 and 1D40. An instruction copies
the current set to the other, works on the copy and then makes it current
with one store to CUR; a key before that store loses only the copy. Other
writes are ones that can be done twice: memory written from registers, the
return stack, CLS. DRW first works out the new value of every character it
changes, into a buffer; once that is done PEND says so, and the characters
are written and the registers made current, which is done again from the
start if a key comes in the middle.

**Timing.** The COMP80 has no clock to read, so the interpreter waits a
while before each instruction and the 60 Hz timers count down every 10
instructions. It runs about 600 instructions a second, so the timers run
at about 60 Hz. The wait is set by the byte at 1C00 (44 to start with);
change it with the monitor (a smaller number is faster) and RS keeps it.

There is no sound: the sound timer counts down, but nothing beeps.

**What it does.** All 35 instructions of the original CHIP-8 except 0nnn
(machine code), with these choices where interpreters differ: 8xy6 and
8xyE shift Vx, FX55 and FX65 leave I as it was, sprites are clipped at the
edges of the screen (their position wraps), and Bnnn adds V0.

**Memory.** 0C00-0C4F the hex font, 0E00-1BFF the program, 1C00-1C1F the
interpreter's variables, 1C40-1C5F the return stack (16 deep), 1D00-1D7F
the two register sets, 1D80 where the NMI handler stores keys, 1E00-1F67
the DRW buffer.

## Tests

`tests/` has a session for each example, in the format of
`../forth/tests/*.txt`, with one more line: `#load <file> <address>` copies
a program into memory.

- `bounce.txt`, `keys.txt`, `dodge.txt`, `kaleido.txt`: the examples run,
  with keys typed for `keys` and `dodge`
- `opcodes.txt`: `opcodes.c8` checks the arithmetic, skips, calls, memory
  instructions and DRW collisions; the screen shows 0 if they all passed,
  or the number of the test that failed
