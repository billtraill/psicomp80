# COMP80 PILOT

[Run PILOT in the web emulator](https://billtraill.github.io/psicomp80/emulator.html#rom=pilot). Each example below has a ▶ link that types it in and runs it there.

PILOT, the 1970s teaching language, for the PSI COMP80. It replaces BURP in
the ROM: the monitor (0000-03FF) is unchanged, and PILOT fills the 2 KB at
0400-0BFF where BURP was. As with BURP, you enter it with the RS key from the
monitor's READY state. It is new, written from scratch; the language follows
John Starkweather's PILOT of the 1960s and 70s (Common PILOT's core).

    sh pilot/build.sh

assembles `pilot.asm` with z80asm and writes `pilot.bin` and the ROM,
`../psicomp80_pilot.rom`. PILOT uses about 1750 of its 2048 bytes.

## Using it

Press `^` (RS) at READY. The top line changes to PILOT and a `_` cursor
appears.

- A line starting with a number is stored in the program, in order of
  number; typing the number of a line again replaces it, and the number on
  its own deletes it.
- `LIST` lists the program, `RUN` runs it, `NEW` clears it.
- Any other line runs at once, so `T:HELLO` prints HELLO and `J:*START`
  runs the program from that label.

The program, up to about 3.4 KB, stays in memory if you go back to the
monitor (FS) and come back with RS.

## Statements

A statement is a letter, then optionally Y or N and a condition in
brackets, then a colon and the rest:

    [*LABEL] T[Y|N][(CONDITION)]:TEXT

| | |
|---|---|
| `T:TEXT` | type the text. `$N` and `#N` in it are replaced by the variables' values. |
| `A:` | accept a line from the keyboard as the answer. `A:$N` also keeps it in `$N`; `A:#N` keeps it as a number in `#N`. |
| `M:WORD,WORD` | match: Y if any of the words is in the answer, N if none is. |
| `J:*LABEL` | jump to the line that starts with `*LABEL`. |
| `U:*LABEL` | use the lines from `*LABEL` as a subroutine; `E:` comes back (up to 8 deep). |
| `E:` | end a subroutine, or the program. |
| `C:#N=EXPRESSION` | compute a number. `C:$N=TEXT` sets a string. |
| `G:X,Y` | plot a point on the 128 × 62 quarter-block screen below the title line (X 0-127, Y 0-61). `G:` on its own clears the screen. |
| `R:TEXT` | a remark; it does nothing. |

`TY:` and `TN:` (or any statement with Y or N) only run if the last `M:`
matched, or didn't; `Y:` and `N:` are short for `TY:` and `TN:`. A
condition in brackets runs the statement only if it is true:
`T(#S=4):FULL MARKS!`, `J(#Q<5):*ASK`. It is an expression (true unless 0)
or two compared with `< > = <> <= >=`.

Expressions are 16-bit integers with `+ - * /` and brackets; `#N` (or just
`N`) is a variable and `?N` a random number from 1 to N. There are 26 number
variables `#A`-`#Z` and 26 strings `$A`-`$Z` of up to 31 characters; `RUN`
sets them all to 0 or empty.

A mistake prints `WHAT?`, with `IN` and the line number if a program was
running, and stops it.

## Example programs

`examples/` has five programs to type in:

| | |
|---|---|
| `greet.pil` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=pilotgreet) | asks your name and how you are, and answers using your name. |
| `quiz.pil` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=pilotquiz) | a capitals quiz with a score, marking each answer with a subroutine. |
| `tables.pil` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=pilottables) | a times-table drill: five random questions on the table you choose, with a score. |
| `story.pil` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=pilotstory) | a little adventure with a forest, a dragon and a river, going round until you get home. |
| `draw.pil` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=pilotdraw) | draws a box and its diagonals with `G:`, in under a second. |

## Keys

| Key | What it does |
|---|---|
| Return | enter the line |
| `^` (RS) | rub out the last character. In MAME, Backspace does the same. |
| Ctrl+`\` (FS) | back to the monitor |
| any key while a program runs | stops it: the COMP80 resets to the monitor (READY) |
| `^` at READY | back into PILOT, with the program still there |

The keyboard is upper case only and `_` acts as Return, so `^`, `_` and `\`
can't be typed into a program.

## Tests

`tests/` has a session for each example, in the format of the FORTH and LISP
tests (each line typed, `\r` for Return, `#ready` to wait for the cursor,
`#screen` to print the screen), and `basic.txt`, which tries expressions,
conditions, subroutines, line editing and the error messages.

## Memory

| | |
|---|---|
| 0C00-0C05 | a check word, the end of the program and the random number seed |
| 0C06-197F | the program: for each line its number (2 bytes), the length of the line (1), the text and a 0 |
| 1980-1CBF | `$A`-`$Z` |
| 1CC0-1D0F | the answer |
| 1D10-1D5F | the input line |
| 1D60-1D93 | `#A`-`#Z` |
| 1DA0 | the cursor's place in screen memory |
| 1DA2-1DB9 | the line running, the next line, the match flag, the U: stack |
| up to 1F00 | the machine stack |
