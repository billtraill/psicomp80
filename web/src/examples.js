// The example programs.  Each one powers the machine on with its ROM and
// runs its steps:
//   { fs: true }               FS, which puts the monitor back to READY
//   { keys: "text" }           type text a key at a time
//   { bin: name, at: addr }    copy a program into memory
//   { source: file }           type a FORTH or LISP file a line at a time,
//                              leaving out blank lines and LISP comments
//   { line: "text" }           type a line once FORTH or LISP is waiting
//   { fast: true | false }     run flat out, or at the real speed
//   { ready: true }            wait until the computer is waiting for a key
// "file" is the source shown with the example: the file typed in, or for a
// machine-code program the assembly it was made from.
// "rom": null means any ROM: the monitor is the same in all three.  With
// BURP every key waits until BURP is ready for it: BURP is often busy with
// its calculator chip, and a key then would reset the machine.
"use strict";

const EXAMPLES = [
  {
    id: "life", lang: "monitor", rom: null, title: "Game of Life",
    text: "Conway’s Game of Life in Z80 machine code, 128 × 64 cells, each character showing a 2 × 2 block of cells. It loads at 1000 and runs with RUN 1000, as it would from tape.",
    keys: "R new random board · P pause and resume · S stop", file: "life.asm",
    steps: [{ fs: true }, { bin: "life", at: 0x1000 }, { keys: "RUN 1000" }],
  },
  {
    id: "boat", lang: "monitor", rom: null, title: "Sailing boat (Fig. 22b)",
    text: "The articles’ picture of HMS Sea Hawk, redrawn with the COMP80’s graphics characters. A short loader copies the picture to the screen and waits.",
    keys: "any key: back to the monitor",
    steps: [{ fs: true }, { bin: "boat", at: 0x1000 }, { keys: "RUN 1000" }],
  },
  {
    id: "schmitt", lang: "monitor", rom: null, title: "Schmitt trigger (Fig. 22a)",
    text: "The circuit diagram from the same figure, drawn the same way.",
    keys: "any key: back to the monitor",
    steps: [{ fs: true }, { bin: "schmitt", at: 0x1000 }, { keys: "RUN 1000" }],
  },
  {
    id: "cover", lang: "monitor", rom: null, title: "The kit leaflet’s screen",
    text: "The cover of the Powertran kit leaflet shows a COMP80 with its television displaying “ψCOMP 80” in block letters. This redraws it from the photo, with the quarter-block graphics characters, and shows it the same way as the Fig. 22 pictures.",
    keys: "any key: back to the monitor",
    steps: [{ fs: true }, { bin: "cover", at: 0x1000 }, { keys: "RUN 1000" }],
  },
  {
    id: "alph", lang: "monitor", rom: null, title: "ALPH test pattern",
    text: "The monitor’s own character test: every letter, digit and sign, and all 64 graphics characters.",
    steps: [{ fs: true }, { keys: "ALPH " }],
  },
  {
    id: "list", lang: "monitor", rom: null, title: "LIST a program",
    text: "Life’s machine code in memory, shown with the monitor’s LIST command: an address, then the bytes in hex.",
    steps: [{ fs: true }, { bin: "life", at: 0x1000 }, { keys: "LIST 1000" }],
  },
  {
    id: "burp", lang: "burp", rom: "burp", title: "BURP sample program",
    text: "The sample program from the articles, kept in the BURP ROM at 0BB5: MOV copies it to 0C00, RS enters BURP, LIST shows it and RUN prints the common logarithms of 1 to 25, worked out by the MM57109 chip in about 10 s.",
    steps: [{ fs: true }, { keys: "MOV 0BB50C000C00" }, { keys: "^" }, { keys: "LIST 5 " }, { ready: true }, { keys: "RUN 5 " }],
  },
  {
    id: "burpexp", lang: "burp", rom: "burp", title: "e to the x, in scientific notation",
    text: "The articles’ next step: line 6 becomes LET L=A EX and a heading is added. From e¹⁹ the results no longer fit in 8 digits and BURP switches to scientific notation, with the exponent at the end.",
    steps: [{ fs: true }, { keys: "MOV 0BB50C000C00" }, { keys: "^" },
      { keys: "DEL 6 " }, { ready: true }, { keys: "ADD " }, { keys: "6 LET L=A EX :" }, { ready: true },
      { keys: "ADD " }, { keys: '4 PRINT " X           EXP X" :' }, { ready: true }, { keys: "RUN 4 " }],
  },
  {
    id: "burptrig", lang: "burp", rom: "burp", title: "Sines and cosines",
    text: "A FOR loop with a fractional STEP calling a subroutine, then a negative number and a division. The chip works in radians; each sine takes it about half a second.",
    steps: [{ fs: true }, { keys: "^" }, { keys: "LOAD " },
      { keys: "10 FOR A=0 STEP 0.5 UNTIL 2 \r" }, { keys: "20 GOSUB 100 \r" }, { keys: "30 NEXT A \r" },
      { keys: "40 LET N=0 3 - \r" }, { keys: "50 LET Q=N 4 / \r" }, { keys: '60 PRINT "N=" N2, " N/4=" Q4 \r' },
      { keys: "70 END \r" }, { keys: "100 LET S=A SIN \r" }, { keys: "110 LET C=A COS \r" },
      { keys: "120 PRINT A2 S6 C6 \r" }, { keys: "130 RETURN :" }, { ready: true }, { keys: "RUN 10 " }],
  },
  {
    id: "burpsier", lang: "burp", rom: "burp", title: "Sierpiński triangle",
    text: "Pascal’s triangle with each number taken mod 2 is the Sierpiński triangle. BURP has no way to print part of a line, so each row is a number whose digits are the cells: row r is the product of 11, 101 and 10001 for the bits set in r, as (1 + x)ʳ mod 2 is the product of 1 + x^(2ᵇ). The bottom half prints in two numbers, as the chip holds 8 digits. About 20 s.",
    steps: [{ fs: true }, { keys: "^" }, { keys: "LOAD " },
      { keys: '10 PRINT "SIERPINSKI TRIANGLE" \r' }, { keys: "20 FOR R=0 STEP 1 UNTIL 7 \r" }, { keys: "30 GOSUB 100 \r" },
      { keys: "40 PRINT P0, \r" }, { keys: "50 NEXT R \r" }, { keys: "60 LET T=10000000 \r" },
      { keys: "70 FOR R=0 STEP 1 UNTIL 7 \r" }, { keys: "80 GOSUB 100 \r" }, { keys: "90 LET H=P T * \r" },
      { keys: "92 PRINT H0, P0, \r" }, { keys: "94 LET T=T 10 / \r" }, { keys: "96 NEXT R \r" }, { keys: "98 END \r" },
      { keys: "100 LET P=1 \r" }, { keys: "110 LET B=R \r" }, { keys: "120 IF B<4 THEN 150 \r" },
      { keys: "130 LET P=P 10001 * \r" }, { keys: "140 LET B=B 4 - \r" }, { keys: "150 IF B<2 THEN 180 \r" },
      { keys: "160 LET P=P 101 * \r" }, { keys: "170 LET B=B 2 - \r" }, { keys: "180 IF B<1 THEN 200 \r" },
      { keys: "190 LET P=P 11 * \r" }, { keys: "200 RETURN :" }, { ready: true }, { keys: "RUN 10 " }],
  },
  {
    id: "forth", lang: "forth", rom: "forth", title: "A FORTH session",
    text: "Squares, a factorial that calls itself, hex numbers, bars of graphics blocks, and the stack shown with .S.",
    steps: [{ keys: "^" }, { fast: true },
      { line: ": SQUARES 11 1 DO I DUP * . LOOP ;" }, { line: "SQUARES" },
      { line: ": FACT DUP 1 > IF DUP 1- FACT * ELSE DROP 1 THEN ;" }, { line: "7 FACT ." },
      { line: "VARIABLE N  10 N !  N @ 3 * ." }, { line: "HEX FF . 1000 DECIMAL . " },
      { line: ": BOX 0 DO 143 EMIT LOOP ;" }, { line: ": BAR 5 0 DO CR I 4 * 1+ BOX LOOP ;" },
      { line: "BAR" }, { fast: false }, { line: "1 2 3 .S" }],
  },
  {
    id: "forthlife", lang: "forth", rom: "forth", title: "Game of Life in FORTH",
    text: "64 × 31 cells, one per character, read straight from screen memory. About 3 s a generation.",
    file: "life.fs",
    steps: [{ keys: "^" }, { fast: true }, { source: "life.fs" }, { fast: false }, { line: "1000 LIFE" }],
  },
  {
    id: "mandel", lang: "forth", rom: "forth", title: "Mandelbrot set in FORTH",
    text: "One point per character, shaded by escape time, in 16-bit fixed point with 90 as 1.0. About 95 s to draw.",
    file: "mandel.fs",
    steps: [{ keys: "^" }, { fast: true }, { source: "mandel.fs" }, { fast: false }, { line: "MANDEL" }],
  },
  {
    id: "forthsier", lang: "forth", rom: "forth", title: "Sierpiński triangle in FORTH",
    text: "Pascal’s triangle mod 2 over the whole screen: 64 rows, four cells to a character, written straight to screen memory. Entry x of row y is odd when x AND y = x. About 10 s to draw.",
    keys: "any key: back to FORTH",
    file: "sier.fs",
    steps: [{ keys: "^" }, { fast: true }, { source: "sier.fs" }, { fast: false }, { line: "SIER" }],
  },
  {
    id: "forthhilbert", lang: "forth", rom: "forth", title: "Hilbert curve in FORTH",
    text: "A turtle draws a level-5 Hilbert curve over the whole screen, 32 × 32 points joined by one line that never crosses itself. Each level is four copies of the one below, turned and joined by three steps: HIL calls itself four times. About 10 s.",
    keys: "any key: back to FORTH",
    file: "hilbert.fs",
    steps: [{ keys: "^" }, { fast: true }, { source: "hilbert.fs" }, { fast: false }, { line: "HILBERT" }],
  },
  {
    id: "forthhanoi", lang: "forth", rom: "forth", title: "Towers of Hanoi in FORTH, animated",
    text: "Six discs move from the left peg to the right one, one at a time and never a bigger one on a smaller one. Each disc lifts off its peg, slides across and drops onto the next. 63 moves in about 75 s.",
    keys: "any key stops it (RS to get back into FORTH)",
    file: "hanoi.fs",
    steps: [{ keys: "^" }, { fast: true }, { source: "hanoi.fs" }, { fast: false }, { line: "6 HANOI" }],
  },
  {
    id: "lisp", lang: "lisp", rom: "lisp", title: "A LISP session",
    text: "DEFUN, a factorial that calls itself, APPEND and REVERSE built from CONS, and MAPCAR given a function as its argument.",
    steps: [{ keys: "^" }, { fast: true },
      { line: "(CONS 'A '(B C))" }, { line: "(DEFUN SQ (X) (* X X))" }, { line: "(SQ 12)" },
      { line: "(DEFUN FACT (N)" }, { line: "  (COND ((EQ N 0) 1) (T (* N (FACT (- N 1))))))" }, { line: "(FACT 7)" },
      { line: "(DEFUN APP (A B)" }, { line: "  (COND ((NULL A) B) (T (CONS (CAR A) (APP (CDR A) B)))))" },
      { line: "(DEFUN REV (L)" }, { line: "  (COND (L (APP (REV (CDR L)) (LIST (CAR L))))))" },
      { line: "(REV '(A B C D E))" },
      { line: "(DEFUN MAPCAR (F L)" }, { line: "  (COND (L (CONS (F (CAR L)) (MAPCAR F (CDR L))))))" },
      { line: "(MAPCAR SQ '(1 2 3 4 5))" }, { line: "(MAPCAR '(LAMBDA (X) (CONS X X)) '(A B))" },
      { fast: false }, { line: "(GC)" }],
  },
  {
    id: "deriv", lang: "lisp", rom: "lisp", title: "Symbolic differentiation",
    text: "DERIV applies the sum, product and power rules to an expression and tidies the answer as it goes. The last example differentiates twice.",
    file: "deriv.lsp",
    steps: [{ keys: "^" }, { fast: true }, { source: "deriv.lsp" }, { fast: false },
      { line: "(DERIV '(+ (* 3 (EXPT X 2)) (* 2 X)) 'X)" },
      { line: "(DERIV '(EXPT (+ (* 2 X) 1) 3) 'X)" },
      { line: "(DERIV (DERIV '(EXPT X 4) 'X) 'X)" }],
  },
  {
    id: "hanoi", lang: "lisp", rom: "lisp", title: "Towers of Hanoi",
    text: "Moves four discs from peg A to peg C, one at a time, never a bigger one on a smaller one: 15 moves.",
    file: "hanoi.lsp",
    steps: [{ keys: "^" }, { fast: true }, { source: "hanoi.lsp" }, { fast: false }, { line: "(HANOI 4 'A 'C 'B)" }],
  },
  {
    id: "queens", lang: "lisp", rom: "lisp", title: "Eight queens",
    text: "A backtracking search for eight queens that don’t attack each other. The first solution takes about 26 s.",
    file: "queens.lsp",
    steps: [{ keys: "^" }, { fast: true }, { source: "queens.lsp" }, { fast: false }, { line: "(QUEENS 8)" }],
  },
  {
    id: "lispsier", lang: "lisp", rom: "lisp", title: "Sierpiński triangle in LISP",
    text: "Pascal’s triangle mod 2, 16 rows printed a character at a time with TYO. ODD tests an entry a bit at a time with REM and /, and FROM is a loop that halves its range, so the recursion stays shallow. About 6 s.",
    file: "sier.lsp",
    steps: [{ keys: "^" }, { fast: true }, { source: "sier.lsp" }, { fast: false }, { line: "(SIER)" }],
  },
  {
    id: "lisphilbert", lang: "lisp", rom: "lisp", title: "Hilbert curve in LISP",
    text: "A Hilbert curve of 16 × 16 points, printed a line at a time. D works out how far along the curve each point is, a quarter at a time, and two neighbours are joined when their distances differ by 1. About 30 s.",
    file: "hilbert.lsp",
    steps: [{ keys: "^" }, { fast: true }, { source: "hilbert.lsp" }, { fast: false }, { line: "(HILBERT)" }],
  },
];
