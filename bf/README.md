# COMP80 BF

[Run BF in the web emulator](https://billtraill.github.io/psicomp80/emulator.html#rom=bf). Each example below has a ▶ link that types it in and runs it there.

Brainf\*\*\* for the PSI COMP80, in the 2 KB of ROM (0400–0BFF) where BURP
was, with the monitor (0000–03FF) unchanged. It uses 1656 of the 2048 bytes;
most of what isn't the interpreter shows it working: the program, the tape
and the output on the screen as it runs.

    sh bf/build.sh      # bf/bf.bin and ../psicomp80_bf.rom

Press RS at READY to enter BF. The top line shows BF and the next says how
long the tape is.

## The language

Eight commands; every other character is a comment.

| | |
|---|---|
| `>` `<` | move the data pointer one cell right or left |
| `+` `-` | add 1 to the cell, or take 1 away |
| `.` | print the cell as a character |
| `,` | wait for a key and put it in the cell (Return gives 10) |
| `[` | if the cell is 0, jump past the matching `]` |
| `]` | if the cell isn't 0, jump back to just after the matching `[` |

All eight can be typed on the COMP80 keyboard, so none needed replacing.
Cells are bytes and wrap round (255 + 1 is 0), and so does the tape at its
ends. The tape is 768 cells (1A00–1CFF), or 30000 at 8800 with the 32 KB
expansion. A program can have 511 commands.

Output: 10 starts a new line, 32–95 print as themselves, 96–127 (lower
case) as capitals, and 128 + n prints graphics character n, so 143 is a
solid block. Other values print nothing. A key read by `,` is shown.

## Commands

Programs are typed as numbered lines, as in BASIC; a number on its own
deletes that line. A line without a number runs at once, flat out.

| | |
|---|---|
| `LIST` | the program |
| `NEW` | clear it |
| `RUN` | run it flat out |
| `SHOW` | run it with the program, the tape and the output on the screen, pausing `SPEED` between commands |
| `STEP` | the same, one command a key: Q stops, R runs on as SHOW, any other key does the next command |
| `SPEED n` | SHOW's pause, about 0.8 ms a unit, 0 to 255 (20 to start with) |

`RUN`, `SHOW` and `STEP` first copy the commands out of the program into
CODE, one byte each, and match the brackets with a stack: for every `[`
and `]`, MATCH holds the address of its partner, so a jump takes no
searching. Errors are `NO [`, `NO ]`, `TOO LONG` and `FULL` (the program
text is over 2 KB).

## SHOW and STEP

```
 BF
IP 0003   DP 0000   CELL 02   STEPS 0003        status, in hex
++[>+++<-]>.                                    the commands, 64 a line,
   #                                            the next one marked below
                                                (lines 2-9: 256 commands)
TAPE FROM 0000
 02  00  00  00  00  00  00  00  00  00  ...    16 cells round the pointer
 ##                                             its cell marked
OUTPUT
                                                lines 15-31 scroll
```

IP is the number of the next command, DP the cell, CELL its value and STEPS
the commands run so far. Hello world takes 906 commands: about 6 s at
`SPEED 0` and 20 s at the starting speed.

## Keys

As in FORTH: RS rubs out while typing a line; any key while a program runs
(RUN or SHOW) resets the COMP80 to the monitor, and RS comes back to BF with
the program kept. STEP waits for its key in a HALT, so keys are safe there.

## Memory

| | |
|---|---|
| 0C00 | magic word, end of program, SPEED |
| 0C06–13FF | the program: number (2 bytes), length (1), text, 0 |
| 1400–15FF | CODE, the commands copied out |
| 1600–19FF | MATCH, 2 bytes per command |
| 1A00–1CFF | the tape (8800–FF2F with the expansion) |
| 1D00 | the input line, then BF's variables; the cursor pointer at 1DA0 |

## Examples

`examples/` has six programs, as numbered lines with their comments:

| | |
|---|---|
| `hello.bf` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=bfhello) | Hello world: one loop builds 72, 104, 88 and 32 in four cells, and the letters are made from those. |
| `count.bf` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=bfcount) | The digits 0 to 9: a cell of 48 printed and added to ten times. |
| `add.bf` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=bfadd) | Reads two digits and prints them added up, `3+4=7` (the sum must be below 10). |
| `alpha.bf` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=bfalpha) | The alphabet. |
| `reverse.bf` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=bfreverse) | Type a line and it comes back reversed: the keys go into cells one after another until Return, then are printed walking back to cell 0. |
| `fib.bf` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=bffib) | The Fibonacci numbers 1 to 55 as bars of solid blocks (character 143). |

`tests/` has a session for each, in the format of `web/tools/session.js`,
plus `show.txt` (hello world in SHOW) and `step.txt` (STEP, R, LIST, NEW and
the bracket errors). The JS emulator and MAME (with `bf.bin` patched over
0400–0BFF) end on the same screens for all of them.
