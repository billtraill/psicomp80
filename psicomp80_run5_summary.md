# PSI COMP‑80 / BURP – RUN 5 investigation summary (as of 2026‑01‑31)

This note captures what we’ve established so far about **why `RUN 5` returns to the Monitor (READY prompt)**, plus the most productive next debugging steps.

## Current state

- **Monitor ROM (0000–03FF)** appears to be working.
- **BURP ROM (0400–0BFF)** loads and accepts commands. Keystrokes and the “HALT-per-keystroke” behaviour in BURP mode are consistent with how the original machine used interrupts to wake from HALT.
- You can load the sample program into RAM (0C00…) and **`LIST 5` works**.
- **`RUN 5` does *not* run the program**; it returns to Monitor/READY.

Sample program (from `burp.md`):

```
005 FORA=1 STEP 1 UNTIL 25
006 LET L=A LOG
007 PRINT A0L8
008 NEXT A
009 END
```

The documentation also states that **`ADD`/`LOAD` are terminated with `C0`** as an end-of-program marker so the interpreter knows where to stop scanning. fileciteturn6file10L14-L22

Your loaded memory block ends with `... 1F C0`, matching that expectation.

## What the RUN 5 trace shows (top‑down)

You provided `RUN5_V6.TRC`, captured starting from the **final space** of `RUN 5 ` (i.e. when the command is enacted).

### 1) The interpreter scans the program block at 0C00

The trace shows the interpreter executing code that:

- sets **HL = 0C00**
- reads bytes until it finds either:
  - `C0` (end-of-program block), or
  - `ED` (start-of-line marker / line header), then compares the next byte to the requested line number `C`

This sequence is clearly visible in the trace:

- `0982: ld hl,$0C00`
- `0985: ld a,(hl)`
- `0986: cp $C0`
- `098A: cp $ED`
- `098F: ld a,(hl)`
- `0990: cp c`
- `0993: call $0794` (helper routine used once line is matched)

This corresponds to the bytes visible in the ROM listing around 0870–0990. fileciteturn6file6L2-L4 fileciteturn6file6L18-L20

**Important:** You previously tried a breakpoint at **0840** and never hit it; that’s consistent with this trace because the RUN path is using the **0982** scan loop rather than the earlier **0840** loop (which exists in ROM but isn’t taken for this command path). fileciteturn6file12L9-L12

➡️ **Practical breakpoint:** put your breakpoint at **0982**, **0985**, or **0993** instead of 0840.

### 2) RUN dispatch does lots of `CP`/`JR` “token tests”

After the scan helper returns, the trace shows many `cp` / `jr nz` checks (e.g. 0996..0AAE). This looks like a classic **token/command dispatch chain**: compare token value, branch to handler.

### 3) RUN eventually calls a “format/IO” routine that talks to the MM57109 interface

From the trace:

- `0AC0: call $0460`
- Later again: `0AC8: call $0460` with `A = 1B`

`0460` does:

- `exx`
- sets `HL = 1FF4`
- `im 1`, `ei`
- calls `0446`, which reads bytes at the return address (inline stream) until `FF`, and for each byte calls `042E`
- `042E` is the routine that performs the **port 03 / port 60 handshake** (RDY/HOLD style loop) used to communicate with the coprocessor interface.

This matches the MM57109 “RDY/HOLD” description in the hardware document (RDY sensed by Z80, HOLD controlled by Z80, plus gating by ISEL). fileciteturn6file9L52-L83

So, **RUN uses the MM57109 interface early**, even before it reaches the user program.

## The core failure mode we’ve repeatedly observed

### Symptom
At some point during the RUN command path, **the Z80 ends up executing from address 0000**, so it looks like it “resets” to Monitor:

- The trace shows execution falling back to:
  - `0000: ld sp,$1FDF` then Monitor starts printing its READY banner via `03CE`.

### What that implies
This is not a breakpoint/interrupt illusion. It means one of:

1) a **`JP 0000` / `CALL 0000`** occurs, or
2) a **`RET`** occurs with the top of stack containing **0000** (i.e. return address got corrupted), or
3) a **reset line / hard reset** (unlikely if MAME doesn’t show an explicit reset cause).

In earlier debugger work you captured a smoking gun consistent with (2):

- a watchpoint on the stack area **1FDB–1FDC** showed it being overwritten to **00 00** while PC was in **04B6**, which is a `LDIR` loop.
- After that overwrite, a later `RET` sends execution to 0000.

So the strongest current hypothesis is:

> **A block copy (`LDIR`) is occasionally writing into the stack/return-address area (1FDB…), corrupting the return address to 0000; a subsequent `RET` jumps to 0000 and the Monitor restarts.**

This explains the “returns to READY” behaviour without needing to assume extra interrupts.

## Why this likely happens *during RUN 5*
The trace indicates that RUN goes through the MM57109/printing/formatting path (0460/042E) and then reaches code that uses `LDIR` (04AA/04B6) as part of some data move. When the destination pointer (DE) or copy length (BC) is wrong, it can spill into 1FDB.

You also noted runs where DE started around 1FF6 at 047E, and later you observed DE marching downward through 1Fxx. This fits the idea that the routine is operating in the 1Fxx workspace and can collide with the stack at 1FDB if bounds aren’t enforced.

## Two plausible root causes (still open)

### A) MM57109 emulation/handshake still incomplete
Even after “getting past initialisation”, RUN uses the MM57109 path (0460/042E), and the hardware doc warns RDY pulses can occur during certain operations and must be gated by ISEL. fileciteturn6file9L71-L83

If our emulation returns inconsistent values on port 03 (RDY/ISEL bits), BURP may take a path that assumes data is present, producing bad lengths/pointers before the `LDIR`.

### B) A transcription error in the BURP ROM
Because the Monitor region is solid but BURP is untested/hand-entered, a single wrong byte in a pointer/length computation can put DE into 1FDB or set BC too large.

One big clue from earlier debugging is that you’ve already found at least one genuine ROM transcription error (03B9 FE vs FC), so this remains realistic.

## What to do next (highest value)

These steps are designed to *prove* whether the jump to 0000 is due to a corrupted return address, and to identify which pointer/length becomes wrong.

### 1) Put a write watchpoint on the stack return area
In MAME debugger:

- `wp 1FDB,2,w`

Run `RUN 5` and **stop at the first write to 1FDB/1FDC**.

At that stop, record:
- PC (where the write came from),
- registers (especially **DE, HL, BC, SP**),
- the two bytes being written.

If the first time you see **00 00** written, you’ve confirmed the return address corruption mechanism.

### 2) When it stops in the `LDIR` loop, capture the *initial* registers
`LDIR` loops don’t show you the “setup” unless you break just before them.

So:
- Set a breakpoint at **04B6** (and/or **04AA**).
- When it hits, immediately `r` (register dump) and `u` (disassemble around PC).
- Crucially: note **BC** (copy length), **DE** (dest), **HL** (src), **SP**.

If **DE** is below about **1FDD** and **BC** is non‑trivial, it’s almost guaranteed to clobber 1FDB.

### 3) Backtrack to the *first* place DE/BC become wrong
Once you have the “bad” DE/BC at 04B6:
- Set a **watchpoint on DE** (destination area) earlier, or
- Step back by setting breakpoints at the preceding instructions in the trace:
  - 047B sets `DE = 1FF6` in one common path (from trace snippets you captured earlier).
  - 04A0–04B2 manipulate counts/offsets used for the copy.
- Another good approach: set a conditional breakpoint on 04B6 **only when DE <= 1FDD**.

### 4) Confirm which scan loop is actually used for RUN in your ROM build
Because you tried 0840 and didn’t hit it, and the trace shows 0982, focus on the 0982 loop.

If your current ROM build differs from `ROM_listing_fixedup.txt`, reconcile that first.

### 5) If DE/BC look insane, suspect a 1‑byte ROM error near the arithmetic that computes them
At that point, we can take the suspect routine and:
- compare its bytes against the typed listing,
- sanity check instruction boundaries,
- and look for “impossible” Z80 opcodes or odd control-flow.

## Notes about files
Some earlier generated intermediate files (old driver variants) may expire from the chat storage over time. Keep local copies of any versions you want to preserve.

---
If you want, in the next round we can:
- take your “first bad write to 1FDB” stop (PC+registers) and do a precise reconstruction of the DE/BC/HL provenance, and
- decide whether this is more consistent with a ROM byte error or an MM57109 port-bit behaviour issue.



Looking at 0982:

```
     0C00  ED 05 06 0F 12 20 01 3D 31 20 13 14 05 10 20 31   í.... .=1 .... 1
     0C10  20 15 0E 14 09 0C 20 32 35 20 1F ED 06 0C 05 14    ... . 25 .í....
     0C20  20 0C 3D 01 20 0C 0F 07 20 1F ED 07 10 12 09 0E    .=. ... .í... .
     0C30  14 20 01 30 20 0C 38 20 1F ED 08 0E 05 18 14 20   . .0 .8 .í.....
     0C40  01 20 1F ED 09 05 0E 04 20 1F C0 00 00 00 00 00   . .í ... .À.....
```
The program
```
```
005 FOR A=1 STEP 1 UNTIL 25
006 LET L=A LOG
007 PRINT A0L8
008 NEXT A
009 END
```

So it looks like start of line marker is ED followed by the line number... and the line terminates with 1F.

So RUN 5 will probably look for line 5?
```
     0C00  ED 05 06 0F 12 20 01 3D 31 20 13 14 05 10 20 31 20 15 0E 14 09 0C 20 32 35 20 1F   - FOR A=1 STEP 1 UNTIL 25
     0C1B  ED 06 0C 05 14 20 0C 3D 01 20 0C 0F 07 20 1F                                       - LET L=A LOG
     0C2A  ED 07 10 12 09 0E 14 20 01 30 20 0C 38 20 1F                                       - PRINT A0L8
     0C39  ED 08 0E 05 18 14 20 01 20 1F                                                      - NEXT A
     0C43  ED 09 05 0E 04 20 1F                                                               - END
     0C4A  C0 
```

a = ED 