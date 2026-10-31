# COMP80 in a web page

`../emulator.html` is the COMP80 as one self-contained web page: a Z80
emulator, the three ROMs (BURP, FORTH and LISP), the example programs and a
help page for each language. Open it in a browser; it needs no server.

- Switch ROM between BURP, FORTH and LISP, and memory between 5 KB and the
  32 KB expansion (both power the machine off and on).
- Run any of the examples: Life, the two Fig. 22 pictures, ALPH and LIST in
  the monitor, BURP's sample program, the FORTH session, Life and Mandelbrot,
  and the LISP session, differentiation, Hanoi and the queens. The page types
  each one in, flat out, then runs it at the real 4 MHz.
- Paste a program to have it typed in a line at a time.
- Keys: Return, `^` (RS), Backspace (rubout in FORTH and LISP), Ctrl+`\` (FS),
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
| `tests/burp.txt` | BURP's sample program: MOV, RS, LIST, RUN |

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
the cursor, hence `NOWAIT=1`). A register trace of BURP from the start of
`RUN 5` matched MAME instruction for instruction until MAME took an
interrupt that the driver means to have cleared.

## What it doesn't do

- No cassette or floppy disc: programs that came on tape are copied into
  memory, as `../c80.sh` does.
- BURP lists and edits programs but can't run them: like the MAME driver,
  it doesn't model the MM57109 calculator chip fully. In MAME `RUN 5`
  floods the screen with B (the key interrupt stays on and BURP's handler
  stores the key code over and over); here it stops in BURP's handshake
  with the chip.
