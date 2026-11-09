# COMP80 VTL-2

[Run VTL-2 in the web emulator](https://billtraill.github.io/psicomp80/emulator.html#rom=vtl). Each example below has a ▶ link that types it in and runs it there.

VTL-2, the Very Tiny Language, for the PSI COMP80. It takes BURP's place in
the ROM and was written from scratch for this machine. The monitor
(0000-03FF) is unchanged, and VTL-2 sits in the 2 KB at 0400-0BFF where BURP
was. As with BURP, you enter it with the RS key from the monitor's READY
state.

The original VTL was written by Gary Shannon and Frank McCoy for the Altair
680 in 1976-77, in under 1 KB of ROM. Everything in it is an assignment.
`#=100` is GOTO 100, `?="HI"` prints, and `A=?` reads a number, and the
expressions are worked out strictly from left to right. This version follows
VTL-2's rules, and adds `@` for quarter-block graphics. It uses about 1250
of the 2048 bytes.

## Running it

`build.sh` makes `../psicomp80_vtl.rom`. Once the MAME driver has it as a
BIOS option (`-bios vtl`), press `^` (RS) at READY. The top line changes to
VTL-2, and `OK` and a `_` cursor appear.

Type a line and press Return:
- With a number in front, it goes into the program; a number on its own
  deletes that line.
- Without a number, it runs straight away.
- `0` lists the program, and `#=1` runs it.

## Example programs

`examples/` has five programs to type in, each run with `#=1`:

| | |
|---|---|
| `primes.vtl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=vtlprimes) | The 62 primes below 300 by trial division. It uses `%`, the remainder of the last division, to test for a factor. About 6 s. |
| `guess.vtl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=vtlguess) | Guess the number. `'/100` leaves a random 0-99 in `%`. As `?` takes an expression, typing `N` wins straight away. |
| `fib.vtl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=vtlfib) | Fibonacci numbers until they pass 65535, printed by a subroutine that returns with `#=!`. |
| `circles.vtl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=vtlcircles) | Five circles by the midpoint rule, using only adding, plotted with `@`. About 2 s; then it waits for a key. |
| `chaos.vtl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=vtlchaos) | A Sierpiński triangle by the chaos game: 2500 points, each half way to a random corner. About 27 s; then it waits for a key. |

## Keys

| | |
|---|---|
| Return | ends the line |
| RS (`^`) | rubs out the last character; at READY it enters VTL-2 |
| FS | back to the monitor |
| any key while a program runs | stops it: the machine resets to the monitor; RS comes back to VTL-2 with the program kept |

## The language

A statement is `V=E`, one to a line.

- **Spaces:** a space ends the statement, so anything after one is a comment,
  and a line starting `)` is all comment. So `A = 5` is wrong: it must be
  `A=5`.
- **Numbers** are 16-bit unsigned, 0-65535, and wrap round: `2-3` is 65535.
- **Expressions** are worked out from left to right with no precedence, so
  `3+4*2` is 14. Brackets group.

| Operator | |
|---|---|
| `+ - * /` | `/` keeps the remainder in `%` |
| `=` `<` `>` | give 1 or 0; `>` is greater than or equal, as in VTL-2 |

Every printable character is a variable. These are special:

| | Assigning | Reading |
|---|---|---|
| `#` | `#=E` goes to line E, or to the first line after it if there is no line E, and sets `!` to this line + 1. Going to 0 does nothing, so `#=(A<5)*100` is IF A<5 GOTO 100. | the line running (0 for a line typed in) |
| `!` | | the line after the last `#=`, so `#=!` returns from a subroutine |
| `?` | `?="TEXT"` prints and starts a new line, unless a `;` follows the quote; `?=E` prints a number; `?=""` starts a new line | reads a line typed in and works it out as an expression |
| `$` | `$=E` prints the character with code E; 13 starts a new line | waits for a key and gives its code (13 for Return) |
| `&` | `&=0` clears the program | the end of the program, where `:` starts |
| `*` | | the top of memory, 7168 (1C00) |
| `'` | `'=E` sets the seed | a random number, 0-65535 |
| `%` | | the remainder of the last division |
| `:E)` | `:E)=V` sets element E | element E of the array after the program |
| `@` | `@=Y*128+X` plots a point: X 0-127, Y 0-61 (0,0 top left) on lines 1-31. Adding 8192 clears it instead. | |

A program ends when it runs off its last line or goes to a line past it
(`#=999`). Errors are few:
- `WHAT?` is a statement that isn't `V=E`.
- `FULL` means the program has no room left.
- Dividing by 0 gives 65535.

## Memory

| | |
|---|---|
| 0C00-0C03 | a marker that the program is valid, and `&` |
| 0C04-1BFF | the program, each line its number, its text and 0Dh, then the `:)` array |
| 1C00-1C7F | the variables, a word for each character from 20h to 5Fh |
| 1D00, 1E00 | the input line, and the line typed for `?` |
| 1DA0 | the cursor's address (the screen shows `_`, 1Fh, there while it waits for a line) |

## Tests

`tests/` has a session file for each example, in the format of
`../web/tools/session.js`. Each types the program in and runs it with
` #=1`. The run line starts with a space because `../mame/test_session.lua`
takes any line starting `#` as one of its own commands.
