# BURP

BURP is the high-level language in the original COMP80 ROM (0400-0BFF), from
the Wireless World articles: a small BASIC-like language whose arithmetic is
done by a National MM57109 scientific calculator chip. `../info/burp.md` has
the articles' description, statements and walkthrough.

It runs in the MAME driver and in `../emulator.html`.

## Running it

    cd ~/localdev/mame && ./mamed psicomp80

At READY, copy the articles' sample program out of ROM and enter BURP:

    MOV 0BB50C000C00
    ^                     (RS: the top line changes to BURP)
    LIST 5                (then a space: BURP commands end with a space)
    RUN 5                 (and a space)

`RUN 5 ` prints the common logarithms of 1 to 25. Then, as in the articles:

    DEL 6
    ADD
    6 LET L=A EX :        (the colon instead of Return leaves ADD)
    RUN 5

which prints e^x for 1 to 25, switching to scientific notation from e^19
(`7.2004899 10` for e^25).

- Commands (`LIST`, `RUN`, `DEL`, `ADD`, `LOAD`) end with a space.
- In `ADD` and `LOAD`, end each line with Return and the last one with a
  colon instead.
- Expressions are in calculator order with a space after every term:
  `LET X=X 1 +`, `LET Y=A SIN SQ`. Trig functions work in radians.
- The MM57109 takes as long as the real chip: about 20 ms for an addition,
  0.3 s for a logarithm and 0.6 s for a sine.
- A key while BURP is busy restarts the monitor (as on the real machine), so
  type each key once BURP is waiting for it. Pasting a line into MAME types
  too fast; `test_burp.lua` types a key at a time.
- Any key stops a running program; RS goes back to BURP.

## Tests

`test_burp.lua` types a session from a file in `tests/`, a key at a time, and
prints the screen:

    cd ~/localdev/mame && BURP_TEST=~/localdev/psicomp80/burp/tests/sample.txt \
      ./mamed psicomp80 -video none -sound none -nothrottle \
      -autoboot_script ~/localdev/psicomp80/burp/test_burp.lua

- `sample.txt`: MOV, RS, LIST 5 and RUN 5 (logarithms)
- `walkthrough.txt`: the articles' walkthrough: square roots, e^x with a
  heading, and the `"THE NATURAL ANTI-LOG OF" A0, " IS" L4` format
- `programs.txt`: new programs with LOAD: IF and a loop, a FOR loop with a
  fractional STEP calling a subroutine with SIN and COS, negative numbers and
  division, and INPUT
- `sierpinski.txt`: Pascal's triangle mod 2 (the Sierpiński triangle), each
  row a number made by multiplying 11, 101 and 10001 for the bits of the row

## What made it work

BURP stopped part way through `RUN` for several reasons, all fixed:

1. **The MM57109 model** in `../psicomp80.cpp` is new. Port 60 drives the
   chip's instruction lines and HOLD (bit 7); port 03 reads RDY (bit 5, 1
   while it executes), BR (bit 6, 0 when a test is true) and the digit
   outputs. With HOLD low the chip fetches an instruction; BURP then raises
   HOLD so it stops when it has finished. Two-word instructions take their
   second word the same way. OUT puts out its twelve digits (exponent, signs,
   decimal point position, eight mantissa digits) during the first word, one
   R/W interrupt each, so they are all in before BURP disables interrupts
   after the second word; the old model sent them after the second word. A
   branch whose test is true pulses BR and waits for a second word (BURP
   sends a NOP); a false one skips it. EN pushes the stack, results are
   rounded to 8 digits, and instructions take the data sheet's times.
2. **The digit interrupt** is now latched until the Z80 takes it. Clearing
   it whenever port 03 was read lost digits, because BURP polls port 03 while
   the digits come in.
3. **The keyboard no longer pulses INT.** On the COMP80 only the MM57109's
   R/W line drives INT (`../info/HardwareDescription.txt`).
4. **The floppy disc controller's interrupts** only reach the Z80 once
   software has used the controller since the last reset. The FD1771 does a
   RESTORE when reset, which leaves INTRQ set; BURP's IM 1 handler took that
   for an MM57109 digit, over and over (the screen filled with B, the last
   key's code). The disc software reads the status before enabling
   interrupts, so it still works.
5. **One ROM byte**, at 06AB, was misread from the listing as 2A; it is 0A
   (`LD L,$0A`, the same test as at 06A0). With 2A, numbers in scientific
   notation were printed without their exponent. `../ROM_listing_fixedup.txt`
   and `../psicomp80.rom` are corrected, and the driver has the new CRC.

The JavaScript copy of the model in `../web/src/comp80.js` is the same.
