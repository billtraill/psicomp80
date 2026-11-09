# COMP80 BASIC

[Run BASIC in the web emulator](https://billtraill.github.io/psicomp80/emulator.html#rom=basic). Each example below has a ▶ link that types it in and runs it there.

A Tiny BASIC for the PSI COMP80 that replaces BURP in the ROM, written from
scratch for it. The monitor (0000-03FF) is unchanged; BASIC fills the 2 KB
at 0400-0BFF where BURP was. As with BURP, you enter it with the RS key from
the monitor's READY state.

It is an integer BASIC of the kind the small machines of 1976-79 had:
numbered lines, 26 variables, one array, FOR loops and subroutines, and
graphics on the quarter-block characters.

## Running it

`build.sh` makes `../psicomp80_basic.rom`. Once the MAME driver has it as a
BIOS option (`-bios basic`), press `^` (RS) at READY. The top line changes to
BASIC, `OK` appears and a `_` cursor. Type a line and press Return: with a
number in front it goes into the program, without one it runs straight away.

## Example programs

`examples/` has four programs to type in:

| | |
|---|---|
| `guess.bas` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=basicguess) | Guess the number: RND picks one from 1 to 100 and INPUT takes your guesses, with HIGHER or LOWER until you get it. `RUN` |
| `primes.bas` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=basicprimes) | The 95 primes below 500 by the sieve of Eratosthenes, in the array @(). About 4 s. `RUN` |
| `lines.bas` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=basiclines) | String art: 32 straight lines whose envelopes make two curves, drawn with PLOT by a Bresenham subroutine at 1000. About 30 s; a key stops it. `RUN` |
| `worm.bas` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=basicworm) | A worm 24 points long bouncing round a box, its tail rubbed out with UNPLOT from a ring of positions kept in @(). Runs until a key. `RUN` |

## Keys

| | |
|---|---|
| Return | ends the line |
| RS (`^`) | rubs out the last character; at READY it enters BASIC |
| FS | back to the monitor |
| any key while a program runs | stops it: the machine resets to the monitor; RS comes back to BASIC with the program kept |

Backspace is not a rubout: the keyboard folds it into H.

## The language

Numbers are 16-bit integers, −32768 to 32767; arithmetic wraps round.
Variables are the letters A-Z, all 0 when a program is RUN. Several
statements go on a line, separated by `:`.

| Statement | |
|---|---|
| `PRINT` items | numbers and "strings", separated by `;` (nothing between) or `,` (to the next 16 columns). A `;` or `,` at the end keeps the line. `AT X,Y` among the items moves to column X (0-63) of line Y (1-31). |
| `INPUT` ["prompt";] V, ... | prints `?` and reads a line; the reply can be any expression |
| [`LET`] V `=` expression | `LET` can be left out |
| `IF` condition [`THEN`] statement | or `THEN` line number. When the condition is 0 the rest of the line is skipped. |
| `GOTO` line, `GOSUB` line, `RETURN` | the line can be an expression |
| `FOR` V`=`A `TO` B [`STEP` C] ... `NEXT` V | the loop runs at least once |
| `REM` | the rest of the line is a remark |
| `END` | stops the program |
| `PLOT X,Y`, `UNPLOT X,Y` | set or clear a point: X 0-127, Y 0-61 (0,0 top left), on lines 1-31 of the screen; points off the screen are ignored |
| `CLS` | clears lines 1-31 |
| `RUN`, `LIST` [line], `NEW` | commands, though they work in a program too |

Expressions have `+ - * /` (division rounds towards 0), brackets, unary
minus, and the comparisons `= < > <= >= <>`, which give 1 or 0 and come last.

| Function | |
|---|---|
| `RND(N)` | a random number from 1 to N |
| `ABS(N)` | |
| `POINT(X,Y)` | 1 if that point is set |
| `@(I)` | element I of the array, which uses the free memory after the program: 0 to about 2000 for a short program |

Typing a line number on its own deletes that line; typing a line with the
number of an old one replaces it.

Errors stop the program with a message and the line: `SYNTAX?`, `LINE?`
(no such line, or a negative index), `DIVIDE?` (by 0), `MEMORY?` (program
full, or FOR and GOSUB nested too deep: about 20), `RETURN?` (no GOSUB),
`NEXT?` (no FOR for that variable).

## Memory

| | |
|---|---|
| 0C00-0C03 | 0BA5Ch when the program is valid, and its end (TXTEND) |
| 0C04-1BFF | the program, then the array @() |
| 1C02-1C35 | the variables A-Z |
| 1D00-1D4F | the input line |
| 1DA0-1DA5 | the output position (CURS), the line running, the random number |
| 1E00-1EFF | the stack, with FOR and GOSUB frames |

The program survives a reset (and so a key pressed while it runs); `NEW`
clears it. It does not use the 32 KB expansion.

## Inside

The program is kept as typed, each line its number (2 bytes, low first), its
text without the leading spaces, and 0Dh, in order. Statements run straight
from the text, with DE as the text pointer: the first word is looked up in a
table of statement names (each with 80h on its last letter), most used
first, and anything of the form `V =` goes straight to LET. Expressions are
recursive descent: comparison, then `+ -`, then `* /`, then a factor
(number, variable, `@()`, function or bracket).

GOTO and GOSUB search for the line from the start of the program. FOR and
GOSUB push frames on the Z80 stack, which is otherwise empty between
statements: GOSUB pushes the text pointer, the line and a 0; FOR pushes the
step, the limit, the text pointer, the line and the variable's address. NEXT
drops loops of other variables above its own (left by GOTO), and RETURN
drops any loops inside the subroutine. A FOR of the variable whose loop is
on top replaces it, so a loop can be started again with GOTO.

Keys and the screen work as in COMP80 FORTH: the monitor's NMI handler wakes
the HALT in RAWKEY, and RS at 0800h is a rubout if BASIC was waiting for a
key and a restart if not.

The 2 KB is full to within about 120 bytes. Speed in the emulator at 4 MHz:
about 2700 simple statements a second (`FOR I=1 TO 1000: A=A+I: NEXT I`
takes 1.1 s), and about 380 PLOTs a second.

## Building

    sh basic/build.sh

assembles `basic.asm` with z80asm (stopping on any message, as z80asm still
writes a binary after some errors), checks it is 2 KB, and writes
`../psicomp80_basic.rom` with the monitor in front. If `psicomp80.cpp` has an
entry for the ROM it puts the CRC and SHA1 into it.

## Tests

`tests/` has a session for each example, in the format of
`../forth/tests/`: each line is typed, `\r` is Return, `#ready` waits for
the cursor and `#screen` prints the screen.

- `guess.txt`: `guess.bas` typed in and played to the end by halving
- `primes.txt`: `primes.bas` typed in and run
- `lines.txt`: `lines.bas` typed in and drawn
- `worm.txt`: `worm.bas` typed in and run for 6 s
