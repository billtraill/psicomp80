# PSI COMP-80 BURP `RUN 5` Failure — Investigation Summary

> **Resolved (October 2026).** BURP runs: see `burp/README.md`. The causes were
> the MM57109 model (OUT\*'s digits came after the second word instead of the
> first, the busy/ready handshake and branches didn't follow the chip, and the
> digit interrupt was cleared by BURP's own status polling), a floppy
> controller interrupt left asserted after reset, and one misread ROM byte at
> 06AB. This note is kept as a record of the investigation.

## Context
- **System:** PSI COMP-80 (Z80-based), emulated in MAME  
- **ROM layout:**
  - `0000–03FF`: Monitor ROM (working, annotated)
  - `0400–0BFF`: BURP language ROM (hand-typed, largely untested)
- **Observed symptom:**
  - `LIST 5` works correctly
  - `RUN 5` parses correctly but returns to the **monitor READY prompt** instead of executing the program

---

## High-level conclusion
The failure is caused by **legal BURP ROM code computing a destination pointer that drifts into the stack area**, eventually overwriting the return address with `0000`, causing execution to restart at the monitor entry point.

This is **not** caused by:
- Keyboard NMI handling
- A CPU reset
- Random emulator memory corruption

It is a deterministic software-side failure, triggered by certain runtime state.

---

## Key observations

### 1. No unexpected reset or interrupt path
- Breakpoints placed on:
  - `RST 38`
  - Monitor reset entry
- Result:
  - No unintended jumps to reset vectors
  - Keyboard NMIs behave consistently
  - Return to monitor happens via **normal control flow**, not via reset or NMI

---

### 2. Root symptom: return address overwritten with `0000`
- Stack watchpoint placed on `SP = 1FDB`
- Observed:
  - Bytes at `1FDB/1FDC` (return address) are overwritten with `00 00`
  - Subsequent `RET` transfers execution to address `0000` (monitor)

---

### 3. Stack overwrite caused by `LDIR` at address `04B6`
Instruction:
```
04B6: ED B0    LDIR
```

This instruction copies:
- Source: `HL`
- Destination: `DE`
- Length: `BC`

If `DE` is sufficiently high (≈ `1FDD`), the copy range overlaps:
- Stack return address at `1FDB/1FDC`

This overwrite is **fully deterministic** once `DE` enters the `1Fxx` range.

---

### 4. Two distinct execution modes observed at `04B6`

#### GOOD case
```
DE = 1E1D
BC = 00FC
HL = 2004
```
- Copy stays below stack
- Execution continues normally

#### BAD case
```
DE = 1F00 (later increments upward on repeated calls)
BC = 0019 (or sometimes 00DC)
HL = 20E7
```
- Copy enters stack page
- Eventually overwrites return address
- Control returns to monitor

---

### 5. Destination pointer already wrong before copy
Breakpoint at `047E` (`EX DE,HL`) shows:

```
PC = 047E
DE = 1FF6
HL = 1FBA
```

After executing `EX DE,HL`:
- `DE` becomes `1FBA`

Therefore:
> The destination pointer is already incorrect **before** the `LDIR` at `04B6`.

---

### 6. Exact mechanism producing `HL = 1FBA`
Relevant code sequence:

```
046F  POP AF
0470  CALL 0714
0473  LD   A,L
0474  AND  $F0
0476  LD   L,A
0477  PUSH HL
0478  ADD  A,$0A
047A  LD   L,A
047B  LD   DE,$1FF6
047E  EX   DE,HL
```

`CALL 0714` enters routine `07AC`, which performs:

```
07AC  AND A
07AD  JR Z,07CD
07AF  INC HL  (4 times)
07B3  LD L,A
07B4  RET
```

If `A = BA`, this forces:
- `HL = 1FBA`

This matches the observed bad state exactly.

---

### 7. Why `A = 0xBA` remains unresolved
Within routine `$0460`:
- `PUSH AF` is executed on entry
- `POP AF` is executed at `046F`

Therefore, `A` should normally be restored to the value supplied by the caller.

In bad runs:
- At `047E`, `AF = BAA8` → `A = BA`

This implies one of two possibilities:
1. `$0460` is being called from an unexpected path with `A = BA`
2. The saved `AF` on the stack is being overwritten before `POP AF`

Which of these is occurring has not yet been determined.

---

## What is known with certainty

- ❌ Not caused by keyboard NMI logic
- ❌ Not caused by missing MM57109 handshake stalling
- ❌ Not random emulator memory corruption
- ✅ Caused by valid Z80 execution paths
- ✅ Caused by destination pointer drifting into stack RAM
- ✅ Drift originates from `A` influencing `HL` via routine `0714`
- ✅ Leads to `LDIR` overwriting return address

---

## What remains unresolved

1. Why `A = BA` is present at `POP AF (046F)`
2. Whether:
   - A BURP ROM transcription error exists
   - BURP expects additional hardware state (e.g. MM57109 behaviour)
   - A legitimate but undocumented BURP execution mode is active

---

## Emulator state
- MM57109 emulation is incomplete but **not proven** to be the cause
- Emulator behaviour matches observed ROM execution
- Failure mechanism is software-driven

---

## Potential future investigation paths (not yet executed)

- Fully document all call sites of `$0460`
- Treat `$0714 / $07AC` as a formatting primitive and reverse-engineer intent
- Verify ROM constants involved in destination pointer calculation
- Temporarily relocate stack to confirm collision hypothesis
- Instrument emulator to log `A` at every entry to `$0460`
- Re-type-check BURP ROM bytes around `$0460–$049A`

---

## Meta
- Investigation is correct but highly stateful
- Pausing here is appropriate
- This document is intended as a handoff / resume point for future analysis
