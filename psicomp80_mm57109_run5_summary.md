# PSI COMP80 – BURP RUN 5 / MM57109 Investigation Summary

## Context

This work concerns emulation of the **PSI / Powertran COMP80** in **MAME 0.284**, specifically:
- The **BURP language interpreter** (ROM $0400–$0BFF)
- Interaction with the **MM57109 math coprocessor**
- A failure when executing `RUN 5` on a simple BURP program

The ROM contents were **hand-transcribed**, so both emulation defects *and* ROM transcription errors are possible.

---

## Test Program

```
005 FOR A=1 STEP 1 UNTIL 25
006 LET L=A LOG
007 PRINT A0L8
008 NEXT A
009 END
```

Loaded at `$0C00` with:
- `ED` = start-of-line marker
- Line ends at `1F`
- Program terminator `C0`

---

## Known-Good Baseline Behaviour

A **previous version of `psicomp80.cpp`** exhibited the following:

- Monitor works correctly
- BURP prompt works
- `LIST 5` works
- `RUN 5`:
  - Executes PRINT once (values incorrect: often zero)
  - Advances into the FOR/NEXT logic
  - Then **returns to READY / monitor** prematurely

**Important:**  
In this version, BURP *did not*:
- Hang in the MM57109 handshake loop at `$0439`
- Immediately reset to READY on any keypress

---

## Key Symptom

When executing `RUN 5`, BURP eventually:

- Writes a bad value to `$1FF7`
- This value is later used as a **count / control nibble**
- Result:
  - Reads from `$2000+` (invalid RAM – real HW RAM is `$0C00–$1FFF`)
  - Execution runs away
  - Control returns to monitor (READY)

No invalid *writes* above `$1FFF` are observed, only reads.

---

## Critical Observation (Manual Hack)

Using the MAME debugger:

1. Break at `$04A0` (just before the block copy / formatting loop)
2. Manually force:

```
e 1ff7,06
```

(or another small nonzero nibble, e.g. `0C`)

### Result

- BURP **no longer returns to READY**
- Execution continues correctly into later program lines
- FOR/NEXT logic proceeds further

This strongly indicates:

> The reset-to-READY is caused by an **incorrect value written to `$1FF7`**, not by a general MM57109 handshake failure.

---

## IM1 / $1FF4–$1FF7 Descriptor

- `$1FF4–$1FF7` are written by the **IM1 interrupt handler at `$003D`**
- These bytes appear to form a **4-nibble descriptor** used by BURP
- Expected behaviour:
  - All four bytes written
  - `$1FF7` must end with a *small, sane* value (≤6 observed safe)

Observed failures:
- Only 2–3 bytes written
- `$1FF7` often ends up `00`
- Leads to runaway copy / formatting logic

---

## MM57109 Emulation Attempts

Multiple iterations attempted to emulate:

- `$60` data port (two-phase handshake)
- `$03` status port (bit5 = handshake ready, bit6 = data ready)
- IRQ0 “burst” behaviour (4 IM1 pulses)

Problems encountered during these attempts:
- `$0439` infinite loop waiting for bit5
- Handshake-ready asserted/cleared at wrong time
- `$3F` wrongly treated as special ACK
- Keystrokes in BURP causing immediate soft reset
- Regressions vs earlier working driver
- Increasing behavioural instability

**Conclusion:**  
MM57109 emulation is incomplete, but **not the root cause** of the original RUN 5 failure.

---

## Current Best Hypothesis

1. BURP expects a **specific 4-nibble result** from MM57109 / IM1 processing
2. The final nibble (`$1FF7`) is wrong
3. BURP uses this nibble as a length / control value
4. Bad value causes reads beyond `$1FFF`
5. Interpreter detects failure and returns to READY

The wrong `$1FF7` value may be caused by:
- Incomplete IM1 burst delivery
- Incorrect MM57109 data semantics
- OR a **single incorrect ROM byte** in the BURP formatter / descriptor consumer

---

## Recommended Restart Plan

For a clean restart in a new chat:

1. Revert to the **last known-good `psicomp80.cpp`**
   - BURP accepts keystrokes
   - No `$0439` hang
2. Add **logging only**, no logic changes
3. Ensure:
   - `$1FF4–$1FF7` are always written
   - `$1FF7` is logged whenever modified
4. Optionally apply a **temporary clamp**:
   - If `$1FF7 == 0`, force to `06`
5. Once RUN 5 executes fully:
   - Incrementally implement real MM57109 semantics

---

## Files to Re-Upload in New Chat

Some earlier uploads may have expired. Please re-upload:

- Last known-good `psicomp80.cpp`
- `ROM_listing_fixedup.txt`
- `comp80_monitor_plus_burp_0000_0BFF_annotated_v12.asm`
- One representative trace (e.g. `run5_v7.trc`)
- One MAME log (`error.log`)

---

_End of summary_
