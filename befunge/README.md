# COMP80 Befunge

Befunge-93 for the PSI COMP80, written for this project, in the 2 KB of ROM
(0400-0BFF) that held BURP. The monitor is unchanged; RS at READY enters it.

Befunge is a two-dimensional language: the program is a grid of characters,
and the instruction pointer moves over it right, left, up or down, turned by
arrows. Here the grid is the screen itself. Lines 1-24 are the 64 × 24
playfield, which wraps round at its edges; the pointer runs over the
characters you can see, and `G` and `P` read and write them, so a program
that changes itself changes on the screen. Line 0 shows BEFUNGE (and, after
STEP, the pointer and the stack); lines 25-31 are for commands and the
program's output, and scroll by themselves.

    sh befunge/build.sh

assembles `befunge.asm` and writes `../psicomp80_befunge.rom` (1695 of the
2048 bytes are used).

## Commands

| Command | |
|---|---|
| `Y X TEXT` | put TEXT on line Y (0-23) of the playfield from column X (0-63): exactly one space after X, then TEXT as it stands, spaces and all |
| `EDIT Y X` | type straight onto the playfield from there, with the cursor on the grid: Return goes to the start column of the next line, RS steps back, and Return on a line where nothing has been typed ends |
| `RUN` | run from the top left corner, going right, with an empty stack |
| `STEP` | do one instruction, then show on line 0 where the pointer is and the top five numbers on the stack, with the next cell as a block; after `@` (END) it starts again |
| `SPEED N` | wait N (0-255, about 0.8 ms each) before each instruction, showing the pointer as a block; 0 runs flat out |
| `CLEAR` | blank the playfield |

Only the first letter counts (`ST` and `SP` for STEP and SPEED). A key while
a program runs stops it, as in the other languages: the COMP80 goes back to
READY, and RS comes back to Befunge with the playfield as it was.

## The instructions

All of Befunge-93:

| | |
|---|---|
| `0`-`9` | push the digit |
| `+ - * / %` | pop a, then b; push b+a, b−a, b×a, b÷a, b mod a (÷ and mod by 0 give 0) |
| `!` | 1 if the top is 0, else 0 |
| `` ` `` (typed and shown `)`) | pop a, b; 1 if b > a |
| `> < ^ v` | go right, left, up, down |
| `?` | go in a random direction |
| `_` | pop; go right if 0, else left |
| `\|` (typed and shown `I`) | pop; go down if 0, else up |
| `"` | string mode: push each character's code until the next `"` |
| `:` | duplicate the top |
| `\` | swap the top two |
| `$` | drop the top |
| `.` | print the top as a number and a space |
| `,` | print the top as a character (10 is a new line) |
| `#` | jump over the next cell |
| `g` (`G`) | pop y, x; push the code of the character at x, y |
| `p` (`P`) | pop y, x, v; put the character with code v at x, y |
| `&` | read a number |
| `~` (typed and shown `(`) | read a key |
| `@` | stop |

The keyboard can't type `^`, `_` or `\` (they are RS, Return and FS), and
the screen has no `|`, `` ` `` or `~`. So, as you type, `'` becomes `^`,
`=` becomes `_` and `;` becomes `\` (in strings too), and `I`, `)` and `(`
stand for `|`, `` ` `` and `~`. A program that writes the real codes with
`p` (124, 96, 126, 103, 112, 118) works as well: both are understood.

Numbers on the stack are 16-bit, and the stack holds 2032 of them (then
STACK FULL). An empty stack gives 0. A cell holds a byte: a character's code
is its ASCII code, so the screen's `@ A-Z [ \ ] ^ _` (codes 00h-1Fh) are
64-95 and `p` with a code outside 32-95 puts a graphics character. Anything
that isn't an instruction does nothing. It runs about 8000 blank cells a
second, fewer instructions.

## Memory

| | |
|---|---|
| 0C00-0C17 | the pointer, its direction, string mode, speed, random seed, and the edit state |
| 0C20-1BFF | the Befunge stack |
| 1D00 | input line |
| 1DA0 | the address of the cursor (shows `_`, 1Fh, while waiting for a line, as in FORTH) |
| 1F00 | the Z80 stack |
| 8040-863F | the playfield |
| 8640-87FF | commands and output |

## Example programs

`examples/` has four, each a list of commands that start with CLEAR and put
the program on the playfield a line at a time; then type RUN.

| | |
|---|---|
| `hello.bef` | `"!DLROW ,OLLEH">:#,_@`: the string is pushed backwards, then printed a character at a time until the 0 under it |
| `count.bef` | counts from 1 to 10: the loop goes right along line 0, and `_` sends it back left along line 1 and up the `^` until the count passes 10 |
| `fact.bef` | the factorial of a number read with `&`: counts down onto the stack, then multiplies them all together (7 gives 5040) |
| `stars.bef` | draws a diagonal of stars with `p`, at x = 3n, y = n + 4, writing onto the screen the program itself is on |

## Tests

`tests/` holds sessions for `../web/tools/session.js` (and
`../mame/test_session.lua` with `SESSION_CURS=1DA0`): one for each example,
`basics.txt` (EDIT, G, signed division, `~`, `&` and `\`, STEP, SPEED, an
unknown command) and `keys.txt` (a key stopping a slow run and RS bringing
the playfield back, then STACK FULL).
