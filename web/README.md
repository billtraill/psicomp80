# COMP80 in a web page

`../emulator.html` is the COMP80 as one self-contained web page: a Z80
emulator, the twenty-one ROMs (BURP, FORTH, LISP, BASIC, Logo, CHIP-8, FOCAL,
PILOT, ZASM and Prolog, and under Other VTL-2, Mouse, Befunge, CALC, TRAC,
PL/0, BF, ED, FILE, QUEST and APL), the example programs and a help page for
each.
Open it in a browser; it needs no server.

- Switch ROM between the ten on buttons and the eleven in the Other menu, and
  memory between 5 KB and the 32 KB expansion (both power the machine off and on).
- Run any of the 140 examples: machine code (Storm, a shooting game; Life, a
  plasma, fire, a scrolling banner, a memory viewer, the Fig. 22 pictures);
  BURP's sample program and number programs from Collatz to Zeller's
  congruence; FORTH graphics, animations and games (Mandelbrot, fractals,
  Langton's ant, a maze, sorting, bouncing balls, snake, a clock); LISP's
  symbolic programs (differentiation, Eliza, the animal game, unification,
  LISP in LISP); and a few for each of the other languages, the Other ones in one group. The page types
  each one in, flat out, then runs it at the real 4 MHz.
- Paste a program to have it typed in a line at a time.
- Keys: Return, `^` (RS), Backspace (rubout in the languages that read a line), Ctrl+`\` (FS),
  Esc (RESET). A key while a program runs resets to the monitor, as on the
  real machine.

## How it is built

| File | |
|---|---|
| `src/z80.js` | the Z80 |
| `src/comp80.js` | the machine, following `../psicomp80.cpp`: memory map, keyboard latch and NMI, screen, and the driver's MM57109 model |
| `src/examples.js` | the examples and the steps that type them in |
| `src/app.js` | the page: main loop, keys, controls, typing |
| `src/page.html`, `src/help.html` | the page and the help pages |
| `build.py` | puts it all together, with the fonts read from the driver |
| `tools/session.js` | runs a session from a test file in Node and prints the screen |

    python3 web/build.py

writes `../emulator.html`, `build/artifact.html` (the same page without the
`<html>` around it, for publishing as an artifact) and `build/data.js` (the
ROMs, fonts and programs, for the Node tools).

## Checking it against MAME

`tools/session.js` takes the same test files as `../lisp/test_lisp.lua`:

    node web/tools/session.js lisp lisp/tests/basic.txt
    NOWAIT=1 node web/tools/session.js forth forth/tests/break.txt

The screens it prints match MAME's, line for line, for all the LISP tests
and the FORTH tests (FORTH's are written for a harness that doesn't wait for
the cursor, hence `NOWAIT=1`). BURP's MM57109 model is the same as the
driver's (see `../burp/README.md`), and the BURP examples print what the
driver does.

## What it doesn't do

- No cassette or floppy disc: programs that came on tape are copied into
  memory, as `../c80.sh` does.
