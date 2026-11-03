# COMP80 FOCAL

FOCAL, DEC's 1968 interactive language, for the PSI COMP80. It replaces
BURP in the ROM: the monitor (0000-03FF) is unchanged, and FOCAL fills the
2 KB at 0400-0BFF where BURP was. As with BURP, you enter it with the RS key
from the monitor's READY state.

Like BURP, it does its arithmetic on the MM57109 calculator chip, so numbers
are floating point with 8 digits, and the functions are the chip's own
sines, logs and square roots. It is written from scratch, after the FOCAL-8
manual, cut down to fit.

## Running it

The ROM is `psicomp80_focal.rom`, built by `build.sh`. Press `^` (RS) at
READY. The top line changes to FOCAL and a `*` prompt appears. A line typed
without a number runs straight away; a line with a number goes into the
program.

    *TYPE FSQT(2),!
     1.4142136
    *1.1 FOR I=1,5; TYPE I," ",I**2,!
    *GO

## Example programs

`examples/` has five programs to type in:

| | |
|---|---|
| `roots.foc` | Square roots and cube roots of 1 to 12, using FSQT and `**`. About 10 s. |
| `temp.foc` | Celsius to Fahrenheit from -20 to 100 in 10s: a FOR with a step on one line. About 4 s. |
| `interest.foc` | Compound interest: ASK for an amount, a rate and a number of years, then a line a year, rounded to the penny with FITR. |
| `guess.foc` | Guess the number: FRAN picks one from 1 to 100 and IF says too big, too small or right, counting the guesses. |
| `sine.foc` | A sine wave down the screen: for each line FITR(14+13*FSIN(X/3)) spaces, then a star. About 45 s. |

## Keys

| Key | What it does |
|---|---|
| Return | run or store the line |
| `^` (RS) | rub out the last character |
| Ctrl+`\` (FS) | back to the monitor |
| any key while a program runs | stops it: the COMP80 resets to the monitor (READY) |
| `^` at READY | back into FOCAL, with the program and variables still there |

`^` is the RS key, so FOCAL's `^` for powers can't be typed: use `**`
instead, as in FORTRAN.

## The language

Line numbers are group.step, from 1.01 to 99.99, with 1.1 the same as 1.10.
A line can hold several commands, separated by `;`. Commands are known by
their first letter, so `T` is TYPE and `GO` is GOTO:

| Command | |
|---|---|
| `TYPE "TEXT", !, E, ...` | prints text, a new line (`!`) and numbers |
| `ASK "TEXT", V, ...` | prints the text, then a `:` for each variable and waits for a number (it can be any expression) |
| `SET V=E` | |
| `IF (E) L1,L2,L3` | goes to L1 if E is negative, L2 if it is 0, L3 if it is positive; if that line number is left out, it goes on with the line |
| `GOTO L` | `GO` alone runs the program from the start |
| `DO L` | runs line L, or the whole group with `DO 2`, then comes back |
| `RETURN` | ends a DO early |
| `FOR V=A,B,C; ...` | runs the rest of the line with V = A, A+B, ... up to C; `FOR V=A,C` counts in 1s. The rest of the line always runs at least once. |
| `COMMENT` | the rest of the line is ignored |
| `QUIT` | stops the program |
| `WRITE` | lists the program |
| `ERASE` | clears the variables; `ERASE ALL` clears the program too |

A line number typed on its own deletes that line. As in FOCAL, a program
runs on from one group to the next, so it usually ends with a QUIT.

Expressions have `+ - * /`, `**` for powers, brackets and these functions:
`FSQT FABS FSIN FCOS FEXP FLOG FITR FRAN`. FLOG is the natural log, FITR the
integer part, and `FRAN()` a random number from 0 to 1. Angles are in
radians. Variables are a letter and an optional second letter or digit
(`X`, `AB`, `X1`); they start at 0. Names beginning with F are functions.

Numbers print with a space in front (or `-`): `12`, `0.5`, `3.1415927`,
`1.5E-7`. Commas between items don't add any spaces: put them in as text.

Errors print `?` and, in a program, the line: `?01.20`.

## Limits

- The chip's stack holds four numbers, so an expression can have at most
  four values waiting at once: `A+B*(C-D/E)` works, deeper nesting doesn't.
- Numbers you type have at most 8 digits, and there is no `E` notation.
- A line holds up to 60 characters.
- It is slow, as BURP is: each operation takes the chip 2 to 50 ms, and a
  variable is keyed back into it a digit at a time. A FOR loop goes round
  about seven times a second.
- No arrays, `%` formats, `MODIFY` or `$`.

## Memory

| | |
|---|---|
| 0C00-0C17 | FOCAL's variables (the end of the program, the lowest variable, the cursor, the FOR running) |
| 0C18- | the program: each line its number (step, group), its text and a 0 |
| -1BFF | the variables, 14 bytes each, going down from 1C00 |
| 1C00-1CBF | the command line, 12 digits from the chip, ASK's line |
| -1EFF | the Z80 stack |

## Inside

An expression is worked out as it is parsed, by recursive descent: each
number or variable is keyed into the chip, which pushes its stack, and each
operator is sent after its right-hand side. A variable keeps the 12 digits
the chip's OUT instruction gives (exponent, signs, mantissa); keying it back
in leaves out the zeros at the end. FITR keys a number back with only the
digits before the point. FRAN keys in a point and 8 digits from a
xorshift, whose seed is stirred by the time between key presses.

FOR keeps its variable and the text of its step, its end and the rest of the
line in four words, saving an outer FOR's on the stack; the step and end are
worked out again each time round. It goes on while (V − C) × B is not above
0, which covers counting up and down.

## Building

    sh focal/build.sh

assembles `focal.asm` with z80asm and writes `focal.bin` and
`../psicomp80_focal.rom` (the monitor from `psicomp80.rom` followed by
FOCAL). FOCAL uses all 2 KB but for 4 bytes.

## Tests

`tests/` has a session for each example, in the format of
`../forth/tests`: each line is typed, `\r` is Return and lines ending in it
wait for FOCAL's cursor first.

- `roots.txt`, `temp.txt`, `sine.txt`: typed in and run to the end
- `interest.txt`: run with 1000 at 5% for 8 years
- `guess.txt`: run with the guesses 50, 75 and 90 (FRAN depends on the
  timing of the key presses, so the answers can differ)
