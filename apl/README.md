# COMP80 APL

[Run APL in the web emulator](https://billtraill.github.io/psicomp80/emulator.html#rom=apl). Each example below has a ▶ link that types it in and runs it there.

A small APL for the PSI COMP80. It takes BURP's place in the ROM and was
written from scratch for this machine. The monitor (0000-03FF) is unchanged,
and APL sits in the 2 KB at 0400-0BFF where BURP was. As with BURP, you
enter it with the RS key from the monitor's READY state.

APL is Kenneth Iverson's array language of the 1960s: every value is an
array, functions work on whole arrays at once, and an expression is read
from the right. The COMP80 keyboard has none of APL's special characters,
so the functions are spelt with ASCII signs and words, as the APL systems
on ordinary terminals did. It fills the 2 KB, with 20 bytes to spare.

## Running it

`build.sh` makes `../psicomp80_apl.rom`. Once the MAME driver has it as a
BIOS option (`-bios apl`), press `^` (RS) at READY. The top line changes to
APL and a `_` cursor appears. Type an expression and press Return: its value
is printed on the next line, unless the line is an assignment.

    3 4 RHO IOTA 12
      1  2  3  4
      5  6  7  8
      9 10 11 12

## Example programs

`examples/` has six sessions to type in a line at a time:

| | |
|---|---|
| `basics.apl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=aplbasics) | Adding vectors, right-to-left order (`2 * 3 + 4` is 14), `IOTA`, `+/`, a matrix by `RHO`, and indexing a character vector. |
| `primes.apl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=aplprimes) | The primes below 30. `R .MOD R` is a table of remainders; `0 =` marks the divisors, `+/` counts them in each row, and `2 =` picks out the numbers with exactly two. About 3 s. |
| `table.apl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=apltable) | A multiplication table, `(IOTA 9) .* IOTA 9`, and a table of `>=`. |
| `stats.apl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=aplstats) | The total, average, running totals (`+!`), largest, and the values above the average of a vector. |
| `hist.apl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=aplhist) | A histogram: `" *"[1 + V .>= IOTA MAX/ V]` indexes a two-character string with a 0-1 table, so each value becomes a bar of stars. |
| `pascal.apl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=aplpascal) | Pascal's triangle along its diagonals: each `+!` (running total) of a row of 1s gives the next diagonal. |

## Keys

| | |
|---|---|
| Return | ends the line |
| RS (`^`) | rubs out the last character; at READY it enters APL |
| FS | back to the monitor |
| any key while a line is being worked out | stops it: the machine resets to the monitor; RS comes back to APL with the variables kept |

## The language

| Spelling | APL | |
|---|---|---|
| `+ - * %` | `+ - × ÷` | add, subtract, times, divide (rounding towards 0); monadic `-` negates |
| `= # < > <= >=` | `= ≠ < > ≤ ≥` | comparisons, 1 or 0 |
| `MAX` | `⌈` | the larger |
| `A MOD B` | `B\|A` | the remainder of A divided by B (A if B is 0) |
| `IOTA N` | `⍳N` | 1 to N |
| `RHO B` | `⍴B` | the shape of B |
| `A RHO B` | `A⍴B` | the elements of B, over and over, in the shape A: `N` for a vector, `R C` for a matrix |
| `A / B` | `A/B` | each element of B repeated A times; with 1s and 0s it picks elements out |
| `F/ B` | `F/B` | reduce: F between the elements of each row, from the right |
| `F! B` | `F\B` | scan: the reductions of the first 1, 2, 3 ... elements |
| `A .F B` | `A∘.F B` | outer product: F of each element of A with each of B |
| `V[I]` | `V[I]` | the elements of V (counted from 1) picked by I, in I's shape |
| `X: E` | `X←E` | assignment |
| `"TEXT"` | `'TEXT'` | a character vector |

`F` in a reduction, scan or outer product is any of the scalar functions in
the first four rows.

- **Order.** A function takes everything to its right as its right argument,
  with no precedence: `2 * 3 + 4` is 14, and `-!IOTA 4` is `1 -1 2 -2`.
  Brackets group. The operands are read from the left, so an assignment in
  the middle of a line counts only for what is to its left; give the
  variable its value on a line of its own first.
- **Values** are scalars, vectors and matrices of 16-bit integers (-32768 to
  32767, wrapping round) or characters. A result with one element is always
  a scalar. A scalar, or a shorter argument used over and over, goes with
  every element of the other argument of a scalar function. Negative numbers
  are typed as `0-5` or `-5` (which negates) and print with `-`. `%` and
  `MOD` work on the sizes of negative numbers.
- **Variables** are the single letters A-Z. Each assignment puts a copy of
  the value at the end of the variables' space, so space is not taken back
  when a variable changes: `)` on a line of its own forgets all the
  variables and starts afresh. A line that starts with an assignment does
  not print its value.
- **Printing.** A vector prints on one line, a matrix a row to a line, with
  the numbers right-aligned to the widest and a space before each.
  Characters print as they are.
- **Errors** stop the line: `SYNTAX ERROR`, `VALUE ERROR` (a variable with
  no value), `INDEX ERROR`, `DOMAIN ERROR` (dividing by 0) and `WS FULL
  ERROR` (out of space).

## How it works

- **Parsing.** `expr` reads an expression left to right: a function first
  is monadic and applies to the value of all the rest; otherwise it reads an
  operand, then a dyadic function and all the rest. So the recursion does the
  right-to-left order, and no tokens or precedence are needed. Function names
  are found in one table of signs and words, and a name's number is its place
  in the table.
- **Arrays.** Each value has a 7-byte header (type, rows, columns, number of
  elements) and a word for each element; the type holds the rank, 0 to 2,
  and a bit for characters.
- **Space.** Variables are kept from 0C54h upwards. The values worked out on
  a line are taken from the top, 1CFFh, downwards, and thrown away at the end
  of the line. About 4 KB is free in all.
- **Building results.** Most functions set up the shape of their result and
  call `build`, which calls a routine for each element number: the scalar
  functions take element `I mod N` of each argument (so a scalar or shorter
  argument is used over and over), an outer product takes elements `I / NB`
  and `I mod NB`, a reduction folds row `I`, a scan folds the start of a row,
  indexing looks up element `I` of the index, and so on.
- **Scalar functions** are found by the low byte of their address in a
  12-byte table. They must all be in one page; `build.sh` checks.

## Left out to fit

Catenate and ravel (`,`), `REV`, `TRANS`, `TAKE` and `DROP`, `MIN`, `NOT`,
`IN`, `ABS`, and roll (`?`); user-defined functions; the 32 KB expansion;
reading the right operand of a function first, as APL does; and taking back
the space of a variable when it changes.

## Memory map

| Address | |
|---|---|
| 0C00 | 0A91Ch when the variables are valid |
| 0C02 | the end of the variables' values |
| 0C04 | the variables A-Z, a word each (the value, or 0) |
| 0C38 | the cursor: the screen address it is at |
| 0C3A-0C53 | the line's working space and the function's arguments |
| 0C54-1CFF | variables, upwards, and the line's values, downwards |
| 1D00 | the line typed |
| 1F00 | the stack, downwards |

## Tests

`tests/` has a session for each example, in the format of
`../web/tools/session.js` and `../mame/test_session.lua` (cursor at 0C38),
and `keys.txt`, which stops a long line with a key and comes back with RS to
find the variable still set. The web emulator and MAME give the same screens
for all of them.
