# COMP80 MOUSE

Mouse, Peter Grogono's little stack language (BYTE, July 1979), for the PSI
COMP80. It replaces BURP in the ROM: the monitor (0000-03FF) is unchanged,
and Mouse fills the 2 KB at 0400-0BFF where BURP was. As with BURP, you
enter it with the RS key from the monitor's READY state. It is new, written
from scratch; the language follows Grogono's Mouse, with the changes the
COMP80's keyboard needs.

    sh mouse/build.sh

assembles `mouse.asm` with z80asm and writes `mouse.bin` and the ROM,
`../psicomp80_mouse.rom`. Mouse uses all but 24 of its 2048 bytes.

## Using it

Press `^` (RS) at READY. The top line changes to MOUSE and a `_` cursor
appears.

- A line starting with a digit is a program line, kept in order of its
  number; typing the number again replaces it, and the number on its own
  deletes it.
- `LIST` lists the program, `RUN` runs it, `NEW` clears it.
- Any other line runs at once: ` 3 4 + !` prints 7. As Mouse lines often
  start with a number, start such a line with a space to run it straight
  away.

The program's lines run as one stream of text, the line numbers left out.
The main program ends at `$` or `$$`; macro definitions `$A … @` follow it.
`RUN` clears memory first. The program, up to 2 KB, stays in memory if you
go back to the monitor (FS) and come back with RS.

## The language

Everything works on a stack of 16-bit integers.

| | |
|---|---|
| `123` | push a number |
| `A`-`Z` | push a variable's address |
| `:` | store: `value address :`, so `5 X:` sets X |
| `.` | fetch: `address .`, so `X.` is X's value |
| `+ - * /` | arithmetic; `/` rounds towards 0 |
| `%` | remainder (Mouse's `\`), when not followed by a digit |
| `< = >` | compare, giving 1 or 0 |
| `!` | print a number |
| `!'` | print the character whose code is on the stack |
| `!.` | plot point `x y` on the 128 × 62 quarter-block screen below the title line; an x below 0 clears the screen |
| `?` | read a number from the keyboard |
| `?'` | read a character, pushing its code |
| `?.` | a random number from 1 to the number on the stack |
| `"TEXT"` | print TEXT; a `!` in it starts a new line |
| `'C` | push the code of the character C |
| `[ … ]` | pop a number; do what is inside only if it is above 0 |
| `( … )` | loop for ever |
| `&` | pop a number; leave the loop if it is 0 or less (Mouse's `^`) |
| `#A,P1,P2;` | call macro A with parameters P1 and P2 |
| `$A … @` | define macro A; `@` returns from it |
| `%1`-`%9` | a macro's parameters |
| `$` or `$$` | the end of the program |

A macro call gets its own 26 variables: a letter's address is 0-25 plus
26 for each call deep it is. `%1` runs the text of the first parameter in
the caller's variables, at the point it is used, so a parameter can be a
value (`#F,N.;`) or an address (`#S,X;`). Memory is 768 words; the calls
use the bottom of it, so addresses from about 300 up make arrays (the sieve
uses 400-699).

`^` is the RS key and `\` and `_` can't be typed on the COMP80, so the loop's
`^` is `&` and remainder is `%`. `~` can't be typed either, so there are no
comments.

Mistakes stop the program with a message and the line it was in: `STACK?`
(nothing to pop, or more than 64), `ADDRESS?` (outside the 768 words),
`DIVIDE?`, `MACRO?` (not defined), `NESTED?` (calls and loops more than 80
deep), `MISSING?` (no `]`, `)`, `;` or `"` to end a block, or no such
parameter), `FULL` (no room for the line) and `WHAT?`.

## Memory

| | |
|---|---|
| 0C00-0C05 | marker, end of program, random seed |
| 0C06-13FF | program lines: number (2 bytes), length (1), text, 0 |
| 1400-19FF | memory, 768 words |
| 1A00-1A7F | data stack, 64 words |
| 1A80-1CFF | control stack: loops, macro calls and parameters, 8 bytes each |
| 1D10-1D7F | input lines |
| 1DA0-1DE3 | cursor, position, variable offset, macro table |

## Examples

| | |
|---|---|
| `examples/fib.mou` | Fibonacci numbers until they pass 32767, eight to a line. About half a second. |
| `examples/fact.mou` | Factorials 1 to 7 from a macro that calls itself: `$F %1 2 < [ 1 @ ] %1 #F,%1 1 -; * @`. |
| `examples/sieve.mou` | The sieve of Eratosthenes on an array at addresses 400-699: the 62 primes below 300, in about 6 s. |
| `examples/guess.mou` | Guess a number from 1 to 100, with `?.` and `?`. |
| `examples/circles.mou` | Five circles drawn with `!.` by the midpoint algorithm, with a macro plotting four points at a time, in about 3 s. |

## Tests

`tests/` has a session for each example and `basic.txt`, which tries the
operators, conditions, loops, nested macros and parameters, editing and
every error. Run one with

    node web/tools/session.js mouse mouse/tests/basic.txt

once the ROM is in the web page's data, or in MAME with
`mame/test_session.lua` (`SESSION_CURS=1DA0`, `-bios mouse`). The JS
emulator and MAME give the same screens.
