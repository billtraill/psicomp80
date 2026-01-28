# PSI COMP80 Monitor (0x0000–0x03FF) – Notes & Annotations

This note accompanies the annotated disassembly file and calls out the main **keyboard input path** and the visible **command-dispatch structure** in the first 1KB monitor.

## Keyboard input / special keys

The monitor reads a latched keyboard byte from **I/O port $01** and then inverts it (active-low hardware):

- **0x006F**: `IN A,($01)`
- **0x0071**: `CPL`

Normalisation and special-key handling immediately follows:

- **CR handling**: `CP A,$0D` then if equal loads `A,$1F` (0x0072–0x0076). So the monitor treats **0x1F** as its internal “enter/return”.

- **Masking**: if `A >= $40` then `AND $1F` (0x0078–0x007C). This collapses keys into a 5‑bit control-code space.

- **RS (BURP entry)**: `CP A,$1E` then `JP Z,$0800` at **0x0082–0x0084**. That’s the RS key described in the BURP docs.

- **0x1F special**: `CP A,$1F` then a small handler and `RETN` (0x0087–0x008E). This is consistent with the monitor using 0x1F as a “line complete / accept” key.


### Practical breakpoints

- Put a breakpoint at **0x006F** to prove the monitor is consuming a key.
- Put a breakpoint at **0x0084** (or **0x0800**) to prove RS is recognised.


## Command dispatch shape

At **0x0017** the monitor calls a helper (in the 0x03xx area) that returns a key/command code in **A**, then it compares A against a series of constants (examples: **0xFC**, **0x06**, **0x09**, **0xF8**, **0xFD**, etc.).

This looks like the front end is driven by **non-ASCII command keycodes** (likely the COMP80 keypad/function keys), not by parsing printable command words.

A few especially clear cases in the first 1KB:

- **A == 0xFC** at **0x001A** branches to **0x0042**, which calls helpers and then does `JP (HL)` (0x0048). That strongly suggests a **jump table / indirect command vector** mechanism.

- **A == 0x06** at **0x002B** enters a loop writing **0xFF** through memory via HL (`LD (HL),$FF` / `INC L` / loop until L wraps). This looks like a **page clear / buffer initialise** operation.

- **A == 0xFD** at **0x00F3** runs a large nested loop that repeatedly outputs to **port $40** and **port $80** while walking a table at **0x1C00**. This is very likely a **display/CRT controller initialisation** sequence.


## What I haven’t inferred yet

This output is meant to be **accurate for the bytes** in the 0x0000–0x03FF region, but some monitor command meanings (what 0xF8/0xFE/0xF1/0xF2 correspond to on the real keypad, and which exact commands they implement) need correlating with the original COMP80 documentation or the keyboard matrix encoding.

If you paste (or re-upload) the page in the manual that lists the monitor keys/commands, I can update the comments so each `CP A,$xx` case is named explicitly (e.g. “LIST”, “GO”, “EXAMINE”, “DEPOSIT”, etc.).
