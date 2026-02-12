# MM57109 command / opcode reference (octal + hex)

This file extends the National Semiconductor MM57109 opcode tables with:

- **2-word format** information for `*` instructions
- A flag for whether the **opcode byte has been observed in BURP/MM57109 traffic** (based on `burp_z80_mm57109.md`)
- Per-instruction **descriptions** and **register effects**

## Notes on the “Observed in BURP” column

- This marks **opcode bytes seen on the Z80’s OUT stream to port `$60`** during BURP execution.
- BURP appears to use some bytes (notably `0x20` and `0x3F`) as **interface control/separators**, which may not correspond 1:1 to the datasheet instruction semantics.

## Instruction tables

### Digit Entry

| Mnemonic | Class | Octal opcode | Hex byte(s) | 2-word format | Observed in BURP | Description | Registers modified |
|---|---|---:|---:|---|---|---|---|
| `0` | digit entry | `00` | `0x00` | — | no | Mantissa/exponent digit entry; first digit initiates number entry (push stack, clear X), then loads digit into X. | stack push; X updated (digit entry) |
| `1` | digit entry | `01` | `0x01` | — | yes | Mantissa/exponent digit entry; first digit initiates number entry (push stack, clear X), then loads digit into X. | stack push; X updated (digit entry) |
| `2` | digit entry | `02` | `0x02` | — | yes | Mantissa/exponent digit entry; first digit initiates number entry (push stack, clear X), then loads digit into X. | stack push; X updated (digit entry) |
| `3` | digit entry | `03` | `0x03` | — | yes | Mantissa/exponent digit entry; first digit initiates number entry (push stack, clear X), then loads digit into X. | stack push; X updated (digit entry) |
| `4` | digit entry | `04` | `0x04` | — | yes | Mantissa/exponent digit entry; first digit initiates number entry (push stack, clear X), then loads digit into X. | stack push; X updated (digit entry) |
| `5` | digit entry | `05` | `0x05` | — | no | Mantissa/exponent digit entry; first digit initiates number entry (push stack, clear X), then loads digit into X. | stack push; X updated (digit entry) |
| `6` | digit entry | `06` | `0x06` | — | yes | Mantissa/exponent digit entry; first digit initiates number entry (push stack, clear X), then loads digit into X. | stack push; X updated (digit entry) |
| `7` | digit entry | `07` | `0x07` | — | no | Mantissa/exponent digit entry; first digit initiates number entry (push stack, clear X), then loads digit into X. | stack push; X updated (digit entry) |
| `8` | digit entry | `10` | `0x08` | — | no | Mantissa/exponent digit entry; first digit initiates number entry (push stack, clear X), then loads digit into X. | stack push; X updated (digit entry) |
| `9` | digit entry | `11` | `0x09` | — | no | Mantissa/exponent digit entry; first digit initiates number entry (push stack, clear X), then loads digit into X. | stack push; X updated (digit entry) |
| `DP` | digit entry | `12` | `0x0A` | — | no | Decimal point: subsequent digits go to mantissa fraction. | X mantissa mode |
| `EE` | digit entry | `13` | `0x0B` | — | no | Enter exponent: subsequent digits go to exponent. | X exponent mode |
| `CS` | digit entry | `14` | `0x0C` | — | no | Change sign of mantissa or exponent depending on exponent-entry state. | X sign (mantissa/exponent) |
| `PI` | digit entry | `15` | `0x0D` | — | no | Load constant π into X (stack not pushed). | X set; stack not pushed |
| `HALT` | digit entry | `17` | `0x0F` | — | no | HALT (external hardware asserts HOLD); behaves like NOP and does not terminate digit entry. | execution waits (HOLD); acts as NOP |
| `EN` | digit entry | `41` | `0x21` | — | no | Enter: terminates digit entry and pushes stack. | stack push (Z→T,Y→Z,X→Y) |
| `NOP` | digit entry | `77` | `0x3F` | — | yes (BURP uses 0x3F as ACK/WRITE) | No operation (terminates digit entry). | — |

### Move

| Mnemonic | Class | Octal opcode | Hex byte(s) | 2-word format | Observed in BURP | Description | Registers modified |
|---|---|---:|---:|---|---|---|---|
| `XEM` | move | `33` | `0x1B` | — | yes | Exchange X with memory. | X↔memory |
| `MS` | move | `34` | `0x1C` | — | no | Store X to memory. | memory updated from X |
| `MR` | move | `35` | `0x1D` | — | yes | Recall memory into X (push stack). | stack push; X loaded from memory |
| `LSH` | move | `36` | `0x1E` | — | no | Left shift X mantissa. | X mantissa shifted left |
| `RSH` | move | `37` | `0x1F` | — | no | Right shift X mantissa. | X mantissa shifted right |
| `ROLL` | move | `43` | `0x23` | — | no | Roll stack. | stack permuted |
| `POP` | move | `56` | `0x2E` | — | no | Pop stack. | stack pop (Y→X,Z→Y,T→Z) |
| `XEY` | move | `60` | `0x30` | — | yes | Exchange X and Y. | X↔Y |

### Math

| Mnemonic | Class | Octal opcode | Hex byte(s) | 2-word format | Observed in BURP | Description | Registers modified |
|---|---|---:|---:|---|---|---|---|
| `SIN` | math | `44` | `0x24` | — | no | sin(X) → X. | X result only |
| `COS` | math | `45` | `0x25` | — | no | cos(X) → X. | X result only |
| `TAN` | math | `46` | `0x26` | — | no | tan(X) → X. | X result only |
| `RTD` | math | `54` | `0x2C` | — | no | Radians→Degrees conversion (X updated). | X result only |
| `DTR` | math | `55` | `0x2D` | — | no | Degrees→Radians conversion (X updated). | X result only |
| `EX` | math | `61` | `0x31` | — | no | e^X → X. | X result only |
| `10X` | math | `62` | `0x32` | — | no | 10^X → X. | X result only |
| `SQ` | math | `63` | `0x33` | — | no | X^2 → X. | X result only |
| `SQRT` | math | `64` | `0x34` | — | no | sqrt(X) → X. | X result only |
| `LN` | math | `65` | `0x35` | — | no | ln(X) → X. | X result only |
| `LOG` | math | `66` | `0x36` | — | no | log10(X) → X. | X result only |
| `1/X` | math | `67` | `0x37` | — | no | 1/X → X. | X result only |
| `YX` | math | `70` | `0x38` | — | no | Y^X → X. | X result; stack popped |
| `+` | math | `71` | `0x39` | — | yes | X+Y → X (stack popped). | X result; stack popped |
| `-` | math | `72` | `0x3A` | — | yes | Y−X → X (stack popped). | X result; stack popped |
| `x` | math | `73` | `0x3B` | — | yes | Y×X → X (stack popped). | X result; stack popped |
| `/` | math | `74` | `0x3C` | — | yes | Y÷X → X (stack popped). | X result; stack popped |

### Inv (2-Word)

| Mnemonic | Class | Octal opcode | Hex byte(s) | 2-word format | Observed in BURP | Description | Registers modified |
|---|---|---:|---:|---|---|---|---|
| `M+*` | inv (2-word) | `40,71` | `0x20 0x39` | 1st word INV, 2nd word op code | yes (BURP uses 0x20 as SPACE/sep) | Add X to memory: M+X→M (INV +) | M updated; X,Y,Z,T unchanged |
| `M-*` | inv (2-word) | `40,72` | `0x20 0x3A` | 1st word INV, 2nd word op code | yes (BURP uses 0x20 as SPACE/sep) | Subtract X from memory: M−X→M (INV −) | M updated; X,Y,Z,T unchanged |
| `MX*` | inv (2-word) | `40,73` | `0x20 0x3B` | 1st word INV, 2nd word op code | yes (BURP uses 0x20 as SPACE/sep) | Multiply memory by X: M×X→M (INV ×) | M updated; X,Y,Z,T unchanged |
| `M/*` | inv (2-word) | `40,74` | `0x20 0x3C` | 1st word INV, 2nd word op code | yes (BURP uses 0x20 as SPACE/sep) | Divide memory by X: M÷X→M (INV ÷) | M updated; X,Y,Z,T unchanged |
| `SIN-1*` | inv (2-word) | `40,44` | `0x20 0x24` | 1st word INV, 2nd word op code | yes (BURP uses 0x20 as SPACE/sep) | arcsin(X) → X (INV SIN) | X result only |
| `COS-1*` | inv (2-word) | `40,45` | `0x20 0x25` | 1st word INV, 2nd word op code | yes (BURP uses 0x20 as SPACE/sep) | arccos(X) → X (INV COS) | X result only |
| `TAN-1*` | inv (2-word) | `40,46` | `0x20 0x26` | 1st word INV, 2nd word op code | yes (BURP uses 0x20 as SPACE/sep) | arctan(X) → X (INV TAN) | X result only |

### Clear

| Mnemonic | Class | Octal opcode | Hex byte(s) | 2-word format | Observed in BURP | Description | Registers modified |
|---|---|---:|---:|---|---|---|---|
| `ECLR` | clear | `53` | `0x2B` | — | yes | Clear error flag. | error flag cleared |
| `MCLR` | clear | `57` | `0x2F` | — | yes | Master clear: clear internal registers and memory; initialise device. | all regs+memory cleared |

### Branch

| Mnemonic | Class | Octal opcode | Hex byte(s) | 2-word format | Observed in BURP | Description | Registers modified |
|---|---|---:|---:|---|---|---|---|
| `TJC*` | branch | `20` | `0x10` | 2nd word: branch address | no | Branch if JC true (2-word). | see description |
| `TX=0*` | branch | `21` | `0x11` | 2nd word: branch address | no | Branch if X == 0 (2-word). | see description |
| `TXLTO*` | branch | `22` | `0x12` | 2nd word: branch address | no | Branch if |X| < 1 (2-word). | see description |
| `TXF*` | branch | `23` | `0x13` | 2nd word: branch address | no | Branch if X < 0 (2-word). | see description |
| `TERR*` | branch | `24` | `0x14` | 2nd word: branch address | no | Branch if ERROR flag set (2-word). | see description |
| `JMP*` | branch | `25` | `0x15` | 2nd word: branch address | no | Unconditional branch (2-word). | see description |
| `IBNZ*` | branch | `31` | `0x19` | 2nd word: branch address | no | Increment M; if M≠0 branch to 2nd-word address; if M==0 skip 2nd word. | M updated; flow control |
| `DBNZ*` | branch | `32` | `0x1A` | 2nd word: branch address | no | Decrement M; if M≠0 branch to 2nd-word address; if M==0 skip 2nd word. | M updated; flow control |

### I/O

| Mnemonic | Class | Octal opcode | Hex byte(s) | 2-word format | Observed in BURP | Description | Registers modified |
|---|---|---:|---:|---|---|---|---|
| `AIN` | i/o | `16` | `0x0E` | — | no | Asynchronous single-digit input (ISEL=0 selects digit input). | X updated (digit) |
| `OUT*` | i/o | `26` | `0x16` | 2nd word: high-order digit addr | yes | Multi-digit output from X using digit addressing & R/W strobe (2-word). | — (outputs digits from X) |
| `IN*` | i/o | `27` | `0x17` | 2nd word: high-order digit addr | no | Multi-digit input to X using digit addressing & DAS (2-word). | stack push; X loaded |
| `SF1` | i/o | `47` | `0x27` | — | no | Set flag F1 high. | flag updated/pulsed |
| `PF1` | i/o | `50` | `0x28` | — | no | Pulse flag F1 (toggles/pulses). | flag updated/pulsed |
| `SF2` | i/o | `51` | `0x29` | — | no | Set flag F2 high. | flag updated/pulsed |
| `PF2` | i/o | `52` | `0x2A` | — | no | Pulse flag F2 (toggles/pulses). | flag updated/pulsed |
| `PRW1` | i/o | `75` | `0x3D` | — | no | Pulse R/W 1 (external strobe; may clock extra bits). | — (R/W pulse) |
| `PRW2` | i/o | `76` | `0x3E` | — | no | Pulse R/W 2 (as PRW1; different low bits). | — (R/W pulse) |

### Mode Control

| Mnemonic | Class | Octal opcode | Hex byte(s) | 2-word format | Observed in BURP | Description | Registers modified |
|---|---|---:|---:|---|---|---|---|
| `SMDC` | mode control | `30` | `0x18` | 2nd word: mantissa digits (1-8) | no | Set mantissa digit count from 2nd word (1–8). | mantissa digit count set |
| `INV*` | mode control | `40` | `0x20` | 2nd word: selects op (trig/mem) | yes (BURP uses 0x20 as SPACE/sep) | Inverse prefix: affects next trig/memory function only (2-word form). | inverse-mode latch set |
| `TOGM` | mode control | `42` | `0x22` | — | no | Toggle mode: floating-point ↔ scientific notation (affects IN/OUT only). | mode toggled |


## INPUTTING DATA
As shown in Figure 1, the MM57109 has an internal
register file. Each of the 5 registers (X, Y, Z, T and M)
has 8 mantissa digits, 2 exponent digits, a decimal point
position indicator, and mantissa and exponent sign bits.
Instructions operate on these registers. The instructions
IN and OUT input and 'output numbers to and from the
X register. There are two possible modes of operation for
IN and OUT instructions. Floating point mode transfers
mantissa digits, a mantissa sign digit, and a decimal point
position digit. Scientific notation mode transfers mantissa digits, 2 exponent digits, a digit containing mantissa
and exponent sign bits, and a decimal point position
indicator. Initially the MM57109 is in the floating point
mode. The TOGM instruction toggles to the opposite
mode. The number of mantissa digits input or output
by an IN or OUT instruction is'equal to the mantissa
digit count (MDC). The MDC is initially 8 and can be set
to any value from 1 to 8 using the SMDC instruction.
When an IN or OUT instruction is executed, the four
DA outputs will sequence through values indicating
which digit is to be input or output. The section of this
manual entitled DATA FORMATS gives the values of the
DA lines for each of the digits input or output by an IN
or OUT instruction. During an OUT instruction, the four
DO outputs provide the digit 'outputs, coded in BCD.
The R/W output is pulsed active low once for each digit.
This R/W pulse can be used to write the data into a
RAM or clock it into a latch; During an IN instruction"
the four I lines (14-11), are data, input lines for the
digits to be input (and so are also named D4-Dl). The
same data format is used for I N as is used for OUT. The
DAS output is pulsed active low prior to reading each
digit. This DAS pulse can be used as a data request signal
or to clock data into a latch.

The IN and OUT instructions have been designed to allow
easy expansion of the internal register file. A 256 x 4
RAM will add an additional 16 registers for data storage.
The DA lines are used to provide part of the RAM
address. The rest of the address, which would specify
one of the 16 registers, comes from the external instruc·
tion storage (ROM, microprocessor, etc). The DO lines
are the input to the RAM, while the RAM outputs are
multiplexed to the I !lines, using ISEl to select between
instructions or data. The processor R/W line is the RAM
R/W signal.
There are three ways to input data to the MM57109.
The first is the IN instruction which has already been
described. Second is the AIN instruction, which inputs
a single digit into the X register. Multiple AIN instruc·
tions will input more than one digit to the X register,
since the AIN instruction does not cause termination of
the number entry mode (number entry mode will be
fully described later in this manual!. The DA lines pro·
vide a digit address from 0 to 7 for multiple AIN instruc·
tions. The ADR input (shared with 16) is a data hold
signal for AIN.lf ADR is high during an AIN instruction,
the processor will wait till it goes low, and then read the
digit on D4-Dl. Finally, the F2 output of the MM57109
will be pulsed active low as a read acknowledge signal.
Note that only mantissa digits, not exponents or signs,
can be entered with AIN.
For systems using a microcomputer with ,the MM57109
as a peripheral, it is likely that neither the IN nor the
AIN instruction would be used. Instead, the third method
of inputting data to the processor would be used. This
method involves entering numbers as instructions. Using
the instructions "0", "1", "2", ... "9", the decimal
point instruction, etc., a number can be entered directly
into the processor in the same manner as one presses
keys to enter numbers into a calculator. The decimal
point is to the right of the last digit entered unless it
was fixed by a DP instruction, The EE instruction
causes the next digits to be entered into the exponent.
The CS instruction changes the sign of the mantissa (or
exponent, if EE instruction was entered).

## 2·WORD INSTRUCTIONS
Several instructions are 2·word instructions, of which
there are 4 types. Each type,generates two RDY pulses,
one for each word. The first type are the inverse instruc·
tions (inverse SIN, COS, TAN and inverse +, -, ,x, / for
memory operations). These instructions require that the
I NV instruction first be executed, followed by the
desired instruction (SIN, COS, etc.). The second type
is the SMDC instruction. The second word of this in·
struction i,s the mantissa digit count, a BCD number
from 1 to 8. The third type is the I N and OUT instruc·
tions. The second word of these instructions is a high
order address for a RAM or a device select code. It is not
necessary to use the second word of I N or OUT instruc·
tions because the MM57109 ignores it, providing only a
RDY pulse that mayor may not be used by external
hardware. The final type of 2·word instructions are the
branch instructions. The second word of these i nstruc·
tions is intended to be a branch address to be loaded
into an external program counter in stand·alone systems.
For a m'icroprocessor system, the second RDY pulse can
be used to clock the BR output into a latch. The latch
can then, be ,tested to discover if the branch condition
was true (BR = 0) or false (BR = 1). Many microcom·
puter applications will not use the branch instructions,
since testing and branching is often more easily done
within the external microprocessor itself.

## MM57109 INSTRUCTION SET

The MM57109 has 70 instructions avaHable to the user.
The 70 instructions are classed into digit entry, move;
math, dear, branch, input/output, and mode control
instructions. Table III contains a detaHed description of
these instructiohs. Figure 9 shows the instruction format.
Table IV contains a summary of·the instructions. Note
that all arithmetic instructions operate on 8·digit man·
tissal2-digit exponent numbers, regardless of mantissa
digit count or notation mode. Accuracy of all instruc-
tions is 7 digits. Computations are performed internally
with 9 digits, then rounded to 8: The eighth digit is
accurate to ±5.

## NUMBER ENTRY
When a digit, decimal point, or 11 is entered with an
AIN, 0-9, DP, or PI instruction, the stack is first pushed
and the X register cleared: Z .... T, Y .... Z, X .... Y, 0 .... X.
This process is referred to as "initiation of number entry."
Following this, the entered digit and future digits are
loaded into the X mantissa. Subsequent entryof digits
or DP, EE, or CS instructions do not cause initiation of
number entry. Digits following the eighth mantissa digit
are ignored. (CAUTION: An internal error will occur
if more than 8 digits are entered with AI N instruction,
or if a non-BCD digit is entered. Note that the ERROR
flag with not be set if this tiappens. A POR sequence
will be' necessary 'to restart the processor.) This number
entry mode is terminated by any instruction except
0-9, DP, EE, CS, PI, AIN or HALT. Termination of
number entry means two things. First, the number is
normalized by adjusting the exponent and decimal
point position so that the decimal point is to the right of
the first mantissa digit. Second, the next digit, decimal
point, or 11 entered will again cause initiation of number
entry, as already described: There' is one exception to
this number entry initiation rule: the' stack 'is not pushed
if the instruction prtor to the entered digit was an
ENTER. However, the X register is still cleared and the
entered digit put in X.
The I N instruction enters all digits of a number. There-
fore, IN does riot cause initiation,of number entry.
However, it does terminate number entry mode if the
processor is in this mode before the IN instruction is
executed. This means the user can mix 0-9, AI Nand
IN instructions without performing an ENTER before
an IN.
The IN instruction 'will always push the stack prior to
inputting digits unless the previous instruction was
ENTER. This allows multiple IN instructions to be
executed without performing an ENTER between them.
INSTRUCTION TIMING
Table V shows execution times of each instruction.
These times are shown in microi:Ycies, '1 microcycle
being equal to 1 S'VNC period '(approximately 10I1s).
Figure 10 shows timing diagrams illustrating the dynamic
characteristics of execution' of each type of instruction,
assuming HOLD = O.

## DATA FORMATS
### IN/OUT Instructions
Mantissa digit count and notation mode determine data
format. Table V II shows the contents of the D, DO and
DA lines for an IN or OUT instruction. Anywhere from
4 to 11 digits will be input or output by a single instruc-
tion.

### AIN Instruction
One digit is input per AI N instruction. A maximum of 8
digits may be entered into the X mantissa by using
consecutive AI N instructions. Digit entry is terminated
by EN or any function instruction, (see NUMBER
ENTRY). Table VII shows the DA lines for consecutive
AIN instructions.

### ERROR CONTROL
The error flag, which can drive an LED indicator, is set
high upon detection of an arithmetic or output error.
(See Table VI).


The error flag can be tested by the TE R R instruction
(which branches if ERROR = 1) or it can be used to
clear the external program counter, resulting in a hard-
ware jump to location 0, the error recovery location.
In either case, an ECLR instruction must be executed to
clear the error fl ago
The occurrence of an error does not affect the operation
of the processor in any way. The OUT instruction will
not output digits if error condition 8 is true, but other-
wise will output digits, even if the error flag is set.

For automatic error recovery, ERROR is wired to the
asynchronous clear input of the external program counter
(PC). The instruction at location 0 is an ECLR to clear
ERROR so that the next RDY pulse will advance the
PC to location 1. A JMP instruction at location 1 with
the branch address at location 2 of an error routine is
then executed, which results in a transfer of program
control to the error routine. These first 3 error recovery
locations are skipped over upon reset (POR) as can be
seen in the initialization and instruction fetch flowcharts.
The program shown in Table VIII shows typical error
recovery coding.


/h2 Instuction Times

Times are in microcycle. A microcyle is 12.5 microseconds.


| Mnemonic | Class | Octal opcode | Hex byte(s) | 2-word format | Observed in BURP | Description | Registers modified |
|---|---|---:|---:|---|---|---|---|
| INSTRUCTION MNEMONIC | EXECUTION TIME (MICROCYCLES) (AVERAGE) | EXECUTION TIME (MICROCYCLES) (WORST·CASE VALUES) |
|---|---|---|
|0-9 | | 238 |
|OP | | 152 |
EE 151 
CS 166 
PI 1312 
HALT 134 
AIN 284 
TJC 208 
TX=O 278 
TXLTO 197 
, TXF 271 
TERR 191 
JMP 186 
IBNZ 2314 
OBNZ 2314 
SMOC 163 
XEM 812 
MS 839 
MR 1385 
LSH 168 
RSH 173 
INV ' . 166 x' 3200 22700
EN 552 
TOGM 157 
ROLL 905 
ECLR 163 
POP 448 
MCLR 734 
XEY 652 
NOP 122 





OUT 583
IN 395
SFI 163
PFI 185
SF2 163
PF2 185
PRWI 130
PRW2 130
SIN 56200 95900
COS 56200 95900
TAN 35000 97600
INVSIN 54000 93900
INV COS 54000 93900
INVTAN 30200 92900
LN 24800 92000
LOG 30700 ,92600
EX 30800 93900
lOX 27400 96500
+.- 2200 6600
INV+.INV- 1700 5000
(M+.M-)
 x' 3200 22700
INVx (MX) 2700 21400
I 7800 22300
INV I (M/) 7300 21100
l/X 4500 22800
YX 55400 95500
SQRT ·7000 30200
 SQ 3000. 21900
OTR.RTO 9600 41700