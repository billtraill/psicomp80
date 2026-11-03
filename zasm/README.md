# COMP80 ZASM

A Z80 assembler and disassembler for the PSI COMP80 that replaces BURP in
the ROM. The monitor (0000-03FF) is unchanged; ZASM fills the 2 KB at
0400-0BFF where BURP was. As with BURP, you enter it with the RS key from the
monitor's READY state.

    sh zasm/build.sh

assembles `zasm.asm` and writes `psicomp80_zasm.rom` (monitor + ZASM) at the
top of the repository.

## Using it

Press `^` (RS) at READY. The top line changes to ZASM and a `>` prompt
appears. Numbers are in hex, as in the monitor, and only the first letter of
a command counts (`D 1000` is `DIS 1000`).

| Command | What it does |
|---|---|
| `DIS addr` | disassembles 24 instructions from addr: address, bytes, then the instruction |
| `DIS` | carries on from where the last DIS stopped (or from where the last ASM started) |
| `ASM addr` | assembles a line at a time from addr. Each line starts with its address; type an instruction and Return, and the line is shown again as DIS would show it. A line that isn't an instruction gets a `?` and is asked for again. A blank line ends. |
| `ASM` | carries on where the last ASM stopped |
| `GO addr` | calls addr; a `RET` comes back to ZASM |

The keys are FORTH's: `^` (RS) rubs out, Ctrl+`\` (FS) goes back to the
monitor, any key while a program runs (other than one waiting in `HALT`)
resets to the monitor, and `^` at READY comes back to ZASM.

### What you type in ASM

Instructions are written the way DIS shows them:

- Numbers are hex and must start with a digit: `LD A,0FF`, not `LD A,FF`, so
  that A, B, C, D, E and the rest are always registers. DIS prints numbers the
  same way.
- Relative jumps (`JR`, `DJNZ`) take the address jumped to: `DJNZ 1007`. One
  that is too far gets a `?`.
- Index registers: `(IX+5)`, `(IY-2)`, `(IX)`.
- `EX AF,AF'`, `IN A,(C)`, `OUT (0FE),A`, `RST 38`, `IM 2`.
- A space is needed after the mnemonic; spaces after a comma or bracket don't
  matter (`LD A, (HL)`), but not before one (`LD A ,B` gets a `?`).

## What it covers

Every documented Z80 instruction, both ways: all the unprefixed opcodes, CB
(rotates, shifts and BIT/RES/SET, with SLL), ED, and DD/FD for IX and IY,
including DD CB d op. DIS was checked against z80dasm on all 650 documented
instructions (it calls SLL what z80dasm calls SLI), and every disassembly of
every opcode was assembled back to its bytes.

Left out to fit in 2 KB:

- The undocumented IXH, IXL, IYH and IYL: `DD 44` shows as `LD B,H`, as the
  prefix is taken to change nothing.
- `ED 70` and `ED 71` show as `IN (HL),(C)` and `OUT (C),(HL)`; DD CB d op
  with a register (the undocumented copies) shows as the plain CB form.
- Unused ED opcodes show as `?`; the ED copies of NEG, RETN, IM and the rest
  show as the instruction, and assemble to the usual opcode.
- Labels, `DB`, `ORG` and expressions. Use the monitor's `LOAD` for data.

## How it works

DIS decodes an opcode by its fields: x = bits 7-6, y = bits 5-3, z = bits
2-0, and y = 2p + q. For x = 0 and x = 3, and ED with x = 1, a table indexed
by z gives a list of format strings and which field picks one. A format
string is text with control codes for the operands (r[y], rp[p], cc[y], a
byte, a word, a relative target, (IX+d) and so on); its last byte has bit 7
set.

ASM is the disassembler run backwards. It tries every opcode in turn, plain,
then CB, ED, DD, FD, DD CB and FD CB, in a 4-byte buffer, with the
disassembler in template mode: each character it would print is compared
with the line typed instead, and the first mismatch gives up that opcode.
Where a number would be printed it reads the typed number and puts it into
the buffer at the place the disassembler read it from. The first opcode
whose text matches the whole line is the instruction, and the buffer is
copied to memory. The worst case, `SET 7,(IY+7F)`, takes 0.65 s.

## Examples

`examples/` has four sessions to type in; `tests/` has each as a session
file in the format of `../forth/tests` (`#bin` loads a file into memory
first):

| | |
|---|---|
| `nmi.txt` | `DIS 0066`: the monitor's keyboard NMI handler, which checks it interrupted a HALT, reads the key from port 01 and turns Return into 1F and RS into a jump to 0800. |
| `pattern.txt` | assembles a program at 1000 that fills the screen with diagonal lines of quarter blocks and waits for a key in a HALT, lists it, and runs it with `G 1000`. |
| `countdown.txt` | assembles a loop at 1100 that counts 9 down to 0 in the top line, about half a second a digit, and runs it. |
| `life.txt` | `DIS 1000` with `../life/life.bin` loaded at 1000: the start of the machine-code Game of Life. |
