# COMP80 TRAC

[Run TRAC in the web emulator](https://billtraill.github.io/psicomp80/emulator.html#rom=trac). Each example below has a ▶ link that types it in and runs it there.

TRAC, Calvin Mooers' Text Reckoning And Compiling language of 1964, for the
PSI COMP80, in the style of TRAC T-64. It replaces BURP in the ROM: the
monitor (0000-03FF) is unchanged, and TRAC fills the 2 KB at 0400-0BFF where
BURP was. As with BURP, you enter it with the RS key from the monitor's
READY state. It is new, written from scratch.

    sh trac/build.sh

assembles `trac.asm` with z80asm and writes `trac.bin` and the ROM,
`../psicomp80_trac.rom`. TRAC uses about 1880 of its 2048 bytes.

## Using it

Press `^` (RS) at READY. The top line changes to TRAC and a `_` cursor
appears. TRAC is reading what you type, up to the meta character, `'`:

    #(PS,HELLO)'

prints HELLO. Return starts a new line without ending the input, so a
definition can run over several lines; nothing happens until the `'`.

TRAC works on strings. Everything typed is scanned a character at a time:

- `#(` starts an active function: when its `)` is reached it is evaluated,
  and its value goes back in front of what is still to be scanned, so it is
  scanned again.
- `##(` starts a neutral function: its value is kept as it is, not scanned
  again.
- `(` protects: everything up to the matching `)` is kept as it is, without
  the outer parentheses.
- `,` separates arguments. Return is dropped, unless it is protected.

When everything has been scanned, TRAC starts again with its idling
procedure, `#(PS,#(RS))`: read a string, scan it, print the result.

Because an active function's value is scanned again, commas in it separate
arguments: use `##(` for a value that should stay as it is, such as a form
with commas in it.

The forms stay in memory if you go back to the monitor (FS) and come back
with RS. Any key while TRAC is busy goes back to the monitor, as on the real
machine.

## Primitives

Names are in capitals; a missing argument is the null string, and an unknown
function has the null value.

| Function | Value |
|---|---|
| `PS,X` | prints X |
| `RS` | what is typed, up to the meta character |
| `RC` | the next key typed |
| `CM,X` | makes the first character of X the meta character |
| `DS,N,X` | defines form N as X |
| `SS,N,X1,X2…` | marks each X1 in N as segment gap 1, each X2 as gap 2, … |
| `CL,N,A1,A2…` | form N with gap 1 filled by A1, gap 2 by A2, … |
| `CS,N,Z` | the next segment of N, up to a gap, or Z if there's none left |
| `CC,N,Z` | the next character of N, or Z |
| `IN,N,X,Z` | N from its form pointer up to the next X, the pointer moving past X; or Z if there is no X |
| `CR,N` | puts the form pointer back to the start |
| `DD,N1,N2…` | deletes the forms; `DA` deletes them all |
| `AD,A,B,Z` `SU` `ML` `DV` | A + B, A − B, A × B, A / B: the numbers at the ends of A and B, with A's prefix in front (`#(SU,X5,9)` is X-4). `DV` by 0 gives Z |
| `EQ,A,B,T,F` | T if A and B are the same string, otherwise F |
| `GR,A,B,T,F` | T if A's number is greater than B's, otherwise F |
| `LN,S` | the names of the forms, each after S |
| `PF,N` | prints form N with its gaps as `<1>`, `<2>`, … |

Numbers are 16-bit integers, from −32768 to 32767; they wrap round rather
than giving Z.

## Left out

CN (call n characters), the boolean functions, the block storage functions
(SB, FB, EB), the trace (TN, TF), and overflow detection for AD, SU and ML.
The keyboard has no lower case, so names are in capitals.

## Example programs

`examples/` has four, to type in a line at a time:

| | |
|---|---|
| `hello.trac` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=trachello) | PS, DS and CL, and the difference protection makes |
| `fact.trac` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=tracfact) | The classic factorial, a form that calls itself through EQ, ML and SU: `#(CL,FACT,7)` gives 5040. Then Fibonacci with GR and AD: `#(CL,FIB,10)` gives 55 in about 2.5 s |
| `rev.trac` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=tracrev) | A string reversed: R takes a character from the form S with CC, calls itself for the rest, then puts the character after it |
| `letter.trac` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=tracletter) | A form letter over several lines, with gaps for the name, the present and the sender, filled in twice |

## Tests

`tests/` has a session for each example, and `basic.txt`, which tries every
primitive, rubout, RC, changing the meta character, running out of room
(FULL), an unknown function and a lone `)`. They are in the format of
`../web/tools/session.js`; a line is typed once TRAC is waiting (`#ready`),
and a line ending with the meta character is typed without a Return.

## How it works

The neutral string grows up from 1400h and the active string down from
1C00h, so a function's value is put back in front of the rest of the active
string by moving the start back. `#(`, `##(` and `,` leave marker bytes in
the neutral string; at `)` the last marker is found, the arguments between
it are split, the primitive is looked up by its two letters, and its value
replaces the function. Forms are kept from 0C40h to 13FFh as records: length,
form pointer, name, body, with a segment gap stored as one byte 80h + its
number.

| Address | What |
|---|---|
| 0C00-0C3F | variables: CURS (the screen cursor) at 0C06h, the meta character at 0C04h |
| 0C40-13FF | forms |
| 1400-1BFF | neutral string (up) and active string (down) |
| 1C00-1DEF | what RS reads |
