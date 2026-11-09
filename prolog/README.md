# COMP80 PROLOG

[Run Prolog in the web emulator](https://billtraill.github.io/psicomp80/emulator.html#rom=prolog). Each example below has a ▶ link that types it in and runs it there.

A small Prolog for the PSI COMP80 that replaces BURP in the ROM, in the same
way as [COMP80 LISP](../lisp/README.md). The monitor (0000-03FF) is
unchanged; Prolog fills the 2 KB at 0400-0BFF where BURP was. As with BURP,
you enter it with the RS key from the monitor's READY state.

    sh prolog/build.sh

assembles `prolog.asm` with z80asm and writes `../psicomp80_prolog.rom`: the
monitor from `../psicomp80.rom` followed by Prolog.

## Using it

Press `^` (RS) at READY. The top line changes to PROLOG and a `_` cursor
appears. Type a clause and it is added to the program; type a query, starting
`?-`, and Prolog answers it. Both end with a full stop, and can run over
several lines.

    PARENT(CAL,BEN).
    PARENT(BEN,EVE).
    GRAND(X,Z) :- PARENT(X,Y), PARENT(Y,Z).
    ?- GRAND(CAL,Q).
    Q = EVE?

For each answer Prolog shows the variables of the query, or YES if it has
none. If there may be other answers it waits with a `?`: press `;` for the
next one, or any other key to stop. NO means there are no (more) answers.

The COMP80 has no lower case, and `_` and `|` can't be typed, so:

| | |
|---|---|
| `X`, `Y`, `L1` | a variable is a single letter, or a letter followed by digits |
| `TOM`, `RED`, `FOO2` | any other name is an atom (so are `[]` and `!`) |
| `?` | an anonymous variable: each `?` is a new one |
| `F(A,B)` | not allowed, as F is a variable: use `FOO(A,B)` |
| `[1,2,3]`, `[H:T]` | lists; `:` takes the place of `|` |
| `-12` | numbers are integers, −16384 to 16383 |
| `% ...` | a comment, to the end of the line |

Memory: clauses and the terms Prolog makes while it works share the heap,
3 KB on the 8 KB machine (1000-1BFF) and 30 KB with the 32 KB expansion
(8800-FFEF). There is no garbage collector: the heap is given back when
Prolog backtracks and when a query is over. A step of a program typically
takes 50-80 bytes, so a query that runs straight through without
backtracking can make about 40 steps on the 8 KB machine, and about 400 with
the expansion; after that it stops with NO MEM. TOO DEEP means too many
choice points (about 100 on the 8 KB machine, 600 with the expansion).

## Built-in predicates

There are no operators: arithmetic is done with relations, as in
micro-PROLOG.

| | |
|---|---|
| `EQ(X,Y)` | X and Y unify |
| `SUM(X,Y,Z)` | X + Y = Z. Any two of them must be numbers, and the third is worked out: `SUM(X,1,N)` gives N − 1. |
| `TIMES(X,Y,Z)` | X × Y = Z, where X and Y must be numbers |
| `LESS(X,Y)` | X < Y, for numbers |
| `WRITE(X)` | print X |
| `NL` | start a new line |
| `FAIL` | fail |
| `!` | cut: commit to this clause and to the choices made in it so far |

There is no `NOT`, but cut and fail make one, as in `examples/path.pl`:

    NOTIN(X,L) :- MEMBER(X,L), !, FAIL.
    NOTIN(?,?).

Messages: SYNTAX (the rest of the line is skipped), NO MEM, TOO DEEP. A key
while a query runs resets to the monitor; RS then comes back to Prolog with
the program kept.

## How it works

The header of `prolog.asm` has the details. Terms are 16-bit words: odd
numbers are integers, atoms are addresses in the symbol table, and compound
terms and lists are made of 4-byte cells. A variable is the address of a
cell plus 2. A clause is stored as a term with its variables numbered; to use
it, Prolog copies it into the heap with new variables, with the goals still
to be done joined onto the end of its body and each cut replaced by the depth
of the choice point stack to go back to. So the goals still to prove are just
a list. Choice points (the goals, the next clause, the heap top) are on the
Z80 stack, and the bindings made are kept on a trail in the heap, so
backtracking can undo them. A clause is tried only if its head has the
goal's name, and a choice point is made only if another clause with that
name follows, so a predicate whose last clause matches leaves none.

## Example programs

`examples/` has four programs to type in:

| | |
|---|---|
| `family.pl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=prologfamily) | A family tree: `FATHER`, `GRAND` and the recursive `ANCESTOR`. `?- ANCESTOR(X,GUS).` gives FAY, ADA, CAL and BEN. |
| `lists.pl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=prologlists) | `APPEND`, `MEMBER`, `REVERSE` (with an accumulator) and `LENGTH`. `?- APPEND(X,Y,[1,2,3]).` gives the four ways to split the list. |
| `colour.pl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=prologcolour) | Colouring a map of five countries with three colours so that no neighbours match: `?- MAP(A,B,C,D,E).` |
| `path.pl` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=prologpath) | Finding a way between two towns without going through one twice, using the cut-and-fail `NOTIN`. `?- WAY(ARK,FORD,P).` gives `P = [ARK,BAY,DALE,ELM,FORD]` and two more. |

Each first answer takes under half a second.

## Tests

`tests/` has a session for each example (typed in, then its queries with `;`
at each prompt) and `basics.txt` (arithmetic, cut, printing, a syntax error,
NO MEM and TOO DEEP), in the format of `../lisp/tests`.

## Keys

| Key | What it does |
|---|---|
| Return | end the line |
| `^` (RS) | rub out the last character |
| `;` | at a `?` prompt: the next answer |
| Ctrl+`\` (FS) | back to the monitor |
| any key while a query runs | stops it: the COMP80 resets to the monitor (READY) |
