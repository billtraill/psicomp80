# COMP80 CALC

[Run CALC in the web emulator](https://billtraill.github.io/psicomp80/emulator.html#rom=sheet). Each example below has a ▶ link that types it in and runs it there.

A spreadsheet for the PSI COMP80, after VisiCalc (1979), that replaces BURP
in the ROM. It was written from scratch for this machine. The monitor
(0000-03FF) is unchanged, and CALC fills the 2 KB at 0400-0BFF where BURP
was. As with BURP, you enter it with the RS key from the monitor's READY
state.

## Running it

`build.sh` makes `../psicomp80_sheet.rom`. Press `^` (RS) at READY. The
screen shows a grid of 6 columns, A-F, each 10 characters wide, and 24 rows.
A `>` marks the current cell. Below the grid, one line shows that cell's
contents, and below that is a `>` prompt where you type.

Each line you type goes into the marked cell, and the marker then moves on to
the next cell down. `/R` makes it move right instead, and `/D` moves it down
again. After every change, every formula is worked out again.

| Typed | What it does |
|---|---|
| `450`  `-33.25`  `3.14159` | a number |
| `+B4*12`  `(A1+A2)/2`  `@SUM(B4...B9)` | a formula: anything that starts with a digit, `.`, `+`, `-`, `(` or `@` |
| `RENT`  `"123`  `"   MONTH` | a label: it starts with a letter, or with `"`, which isn't shown. A long label runs on into empty cells to its right. |
| `>B3` | move the marker to B3 |
| (an empty line) | move on |
| `/B` | blank the marked cell |
| `/C` | clear the whole sheet |
| `/D`, `/R` | after each entry, move down or right |
| `/F0`, `/F1`, `/F2` | show 0, 1 or 2 decimals (the values keep 2) |
| `/U` | copy the cell above into this one, with its references moved down a row |
| `/L` | copy the cell on the left, with its references moved right a column |

`/U` and `/L` make tables quick to fill in. Type a formula once, then press
`/U` for each row below it. A `$` in front of a column letter or a row number
stops that part from moving:
- `+B7*$B$3/100` copied down always uses B3.
- `+$A2*B$1` copied anywhere keeps column A and row 1.

## Numbers and formulas

- **Number format.** Numbers are 32-bit fixed point in hundredths, from
  −21474836.48 to 21474836.47. A number with more than two decimals is cut
  short when typed in.
- **Arithmetic.** `* /` come before `+ -`, and brackets work as usual. `*`
  and `/` go through a 64-bit product and are rounded to the hundredth, so
  `+B6*1.05` and `1/3` come out as you would expect for money.
- **Cell references.** A1 to F24.
- **Sums.** `@SUM(A1...A5)` adds up a range: any rectangle, with its corners
  in either order. The `@` is optional, and `:` can stand in for the dots.
- **Labels and empty cells** count as 0.
- **ERROR.** A formula that can't be worked out shows ERROR, and so does any
  formula that uses it. This covers a mistake in it, dividing by 0, or a
  number too big. A number too wide for its column shows `#########`.
- **Recalculation order.** The sheet is worked out row by row, and again
  while anything changes, up to 8 times, so a formula can use cells further
  down the sheet. A formula that uses its own cell grows a little each time.

The ROM has no MM57109 arithmetic: the chip would be far too slow for a whole
sheet. Integers in hundredths work out a typical sheet in a fraction of a
second.

## Example sheets

`examples/` has four sheets, each a file of lines to type in:

| | |
|---|---|
| `budget.cal` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=sheetbudget) | A household budget: six monthly amounts, each times 12 for the year (one formula and `/U`), the totals by `@SUM`, and the cost a week |
| `interest.cal` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=sheetinterest) | Compound interest on 1000 at 5% for ten years: start, interest and end of each year, all from the rate in B3. Change B3 and the whole table changes |
| `times.cal` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=sheettimes) | A multiplication table from one formula, `+$A2*B$1`, copied across with `/L` and down with `/U` |
| `temp.cal` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=sheettemp) | Celsius to Fahrenheit, −20 to 100 in tens, with `+A2*9/5+32` copied down and one decimal shown |

`tests/` has the same four sheets as sessions for `web/tools/session.js` and
`mame/test_session.lua`. The cursor's address is at 0C02. MAME and the web
emulator give the same screens for all four.

## Keys

| | |
|---|---|
| Return | ends the line |
| RS (`^`) | rubs out the last character; at READY, enters CALC |
| FS | back to the monitor |
| any key while it is working | the machine resets to the monitor; RS comes back with the sheet kept |

## Memory

| | |
|---|---|
| 0C00-0C2C | variables: the cursor (0C02), the marked cell, the arithmetic |
| 0C40 | the line typed (up to 26 characters) |
| 0C80-1E7F | 144 cells of 32 bytes: kind (0 empty, 1 label, 2 value, 3 error), value (4 bytes), text (27 bytes) |
| 1F00 | the stack, going down |

The ROM is full: 2035 of its 2048 bytes are used.
