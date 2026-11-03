# COMP80 PL/0

A compiler for PL/0, the little language Niklaus Wirth used to teach
compiler writing in *Algorithms + Data Structures = Programs* (1976). It fits
in the 2 KB of ROM (0400-0BFF) that held BURP, alongside the unchanged monitor.
It compiles the whole program in one pass, straight into Z80 machine code,
and then runs it. That makes it about 16 times as fast as COMP80 BASIC.

    sh pl0/build.sh

`build.sh` assembles `pl0.asm` with z80asm and writes `pl0.bin` and
`../psicomp80_pl0.rom`: the monitor followed by PL/0. It uses 2036 of the
2048 bytes.

## Using it

Press RS at READY. The top line shows PL/0 and an `OK` prompt appears. Type
the program in numbered lines, as in BASIC. A line is kept as typed, with its
indenting, and a number on its own deletes that line.

| Command | What it does |
|---|---|
| `RUN` | compile the program and run it |
| `CODE` | compile it and print how many bytes of machine code it made |
| `LIST` [line] | list the program, or from a line on |
| `NEW` | forget the program |

A compile error stops with `SYNTAX?` or `NAME?` (a name that isn't
declared, or is the wrong kind) and the line it was found in. A program that
is too long gives `FULL`, and dividing by 0 while it runs gives `DIVIDE?`.
Any key while a program runs resets the COMP80 to the monitor. RS comes back
to PL/0 with the program kept.

## The language

    program    = block "." .
    block      = [CONST name = number {, name = number} ;]
                 [VAR name {, name} ;]
                 {PROCEDURE name ; block ;} statement .
    statement  = [ name := expression | CALL name | ? name | ! expression
                 | BEGIN statement {; statement} END
                 | IF condition THEN statement
                 | WHILE condition DO statement
                 | PLOT expression , expression | CLS ] .
    condition  = ODD expression | expression (= # < <= > >=) expression .
    expression = [-] term {(+|-) term} .
    term       = factor {(*|/) factor} .
    factor     = name | number | ( expression ) .

- **Numbers and names.** Numbers are 16-bit integers, from −32768 to 32767,
  and `/` rounds towards 0. Names are a letter and then letters and digits,
  any length. `#` means "not equal".
- **Input and output.** `! E` prints a number on a line of its own. `? V`
  prints `?` and reads a number into V.
- **Graphics.** `PLOT X,Y` sets a point on the 128 × 62 quarter-block
  graphics of lines 1-31, with X from 0 to 127 and Y from 0 to 61. `CLS`
  clears those lines.
- **Scope.** Names belong to the block they are declared in, and procedures
  can be nested.
- **Variables.** Every variable has one place in memory, so a procedure that
  calls itself shares its variables with itself, as in FORTRAN. `fact.pl0`
  shows the usual PL/0 way round that.
- **Left out.** There are no comments and no unary plus.

## How it compiles

The scanner reads the program text a token at a time:

- a name, copied to a buffer and looked up in the table of words;
- a number;
- `:=`, `<=` or `>=`;
- otherwise one sign.

The parser is recursive descent, one routine for each rule above, and each
routine puts out the code for what it has just read:

| PL/0 | Z80 code |
|---|---|
| a number | `LD HL,n` |
| a variable | `LD HL,(v)` |
| a constant | `LD HL,n` |
| `a + b` | code for a, `PUSH HL`, code for b, `POP DE`, `ADD HL,DE` |
| `a - b` | the same, ending `EX DE,HL`, `OR A`, `SBC HL,DE` |
| `*` and `/` | `CALL` to a multiply or divide routine |
| `- a` | code for a, `CALL` to negate |
| `v := e` | code for e, `LD (v),HL` |
| `IF c THEN s` | code for c, `JP Z,end`, code for s |
| `WHILE c DO s` | code for c, `JP Z,end`, code for s, `JP` back to c |
| `CALL p` | `CALL p` |
| a procedure | its block, then `RET` |
| a block | `JP` over its procedures to its statement |

- **One load on the right.** When the right side of an operator is a single
  load, the `PUSH HL` becomes `EX DE,HL` and there is no `POP`.
- **Conditions.** A comparison calls a routine that sets the Z flag when it
  is false. The byte after the `CALL` says which of < = > make it true. `ODD`
  is `BIT 0,L`.
- **Jumps forward.** The address of a jump over code not yet compiled is
  filled in once that code is done.

Names go in a table at 1A00, each one's name, kind and value. A block's
names are dropped when it ends. Variables are given two bytes each from
1C00. The code goes straight after the program text, and RUN calls it. The
examples compile in about 30 ms. `primes.pl0`, for instance, is 295 bytes of
text and makes 139 bytes of code.

**Speed.** A loop of 30000 times round `A := A + I; I := I + 1` takes about
2.1 s, about 14000 times round a second. COMP80 BASIC manages about 900 a
second with `FOR I=1 TO 1000: A=A+I: NEXT I`.

## Memory

| Address | What |
|---|---|
| 0C00-0C03 | marker and the end of the program text |
| 0C04- | program text: each line its number (2 bytes), its text and 0Dh, up to 17FF |
| after the text | the compiled code, up to 19FF |
| 1A00-1BFF | names |
| 1C00-1CFF | variables, 2 bytes each |
| 1D00-1D4F | input line |
| 1D50-1D9F | the last name read |
| 1DA0- | cursor (1DA0), compiler state |
| 1F00 down | stack |

The cursor's address is at 1DA0, as in FORTH and BASIC. The byte there is 1Fh
(`_`) while PL/0 waits for a line.

## Examples

Type them in, with the line numbers, and RUN.

| File | |
|---|---|
| `squares.pl0` | the squares of 1 to 10, with WHILE |
| `primes.pl0` | the primes below 100 by trial division, testing `N / D * D = N` |
| `gcd.pl0` | asks for two numbers with `?` and prints their greatest common divisor by subtraction; 1071 and 462 give 21 |
| `fact.pl0` | factorials 1 to 7 from a procedure that calls itself. With only global variables, FACT takes N down by 1 before calling itself and puts it back afterwards. |
| `rings.pl0` | rings of quarter blocks with PLOT: the points where (DX² + DY²) / 256 is odd, DY scaled by 5/3 for the shape of the points. About 7.5 s for 7936 points; it then waits in a loop until a key is pressed. |

## Tests

`tests/` has a session for each example, in the format of
`../web/tools/session.js`, and `basics.txt`:

- constants, nested procedures and local variables;
- every comparison and `ODD`;
- arithmetic down to −32768;
- `SYNTAX?` and `NAME?` with their line numbers, and `DIVIDE?`;
- `LIST` from a line, `NEW`, and an unknown command.

They give the same screens in the web emulator and in MAME. For MAME, the
`pl0.bin` image is patched over 0400-0BFF of the BURP ROM, as
`../lisp/test_lisp.lua` does, with the cursor address changed to 1DA0.
