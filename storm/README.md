# COMP80 STORM

A shooting game for the PSI COMP80 in Z80 machine code, of our own design.
Chains of segments weave down the screen; the cannon at the bottom moves left
and right and fires up. A hit breaks a segment out of its chain, and the
segments behind it go off as a chain of their own, the first of them its new
head. Grey segments follow, solid ones are heads, and starred ones drop bombs.
A chain that reaches the bottom creeps along it towards the cannon. Each shot
costs a quarter of the energy bar, which fills again over time. Clear the
screen and the next wave comes, with more segments, more chains and a faster
step. Three cannons; a hit starts the wave again.

    LOAD the bin at 1000, then RUN 1000      (c80.sh storm does it for you)

| Key | |
|---|---|
| Z or , | left |
| X or . | right |
| space or Return | fire |
| Q | back to the monitor |

On the title and game-over screens any key starts a game. It works with any
of the ROMs, as it uses only the monitor.

## Files

| | |
|---|---|
| `storm.asm` | the source; `z80asm -o storm.bin storm.asm` |
| `storm.bin` | 2171 bytes, loading at 1000h |
| `test_storm.lua` | the MAME test: loads the bin, runs it, plays with keys pressed at any moment, and prints the title, a frame of play and the game-over screen |

    cd ~/localdev/mame
    STORM_BIN=~/localdev/psicomp80/storm/storm.bin ./mamed psicomp80 -rompath roms \
        -video none -sound none -nothrottle -autoboot_script ~/localdev/psicomp80/storm/test_storm.lua

## How it works

**The screen.** Lines 0 and 1 are the score, wave, lives and energy bar.
Lines 2-31, the playfield, are drawn in a buffer at 1880h-1FFFh and copied to
the screen a frame at a time, clearing the buffer as they go, so nothing
flickers. A segment is a character (solid 4Fh, grey 40h or `*`); bullets and
bombs are single quarter blocks, on the left and the right of a character, and
move half a line at a time.

**The chains.** There are 32 segments of 6 bytes: column, line, flags (alive,
head, bomber), step and run. Every few frames each follower takes the place of
the segment in front of it, from the back of the table forwards, and then each
head moves: along its line for a random run of 2-9 steps, then down a line,
sometimes turning round; at a side it turns and drops. On the bottom line it
creeps towards the cannon, every other step. When a segment is hit its flags
are cleared, and the one behind becomes a head with a random direction and a
run of 1, so it drops away at once.

**Keys at any moment.** A key is a non-maskable interrupt, and the monitor's
handler goes back to READY unless the byte before its return address is a HALT.
As in the memory dump and Life, the stack pointer is kept in ROM, at 0364h, so
the NMI's push is lost and the handler takes its return address from the ROM:
0362h holds 1278h, and 1277h is the HALT of the frame's wait, so it returns to
the key handler with the key in A. Return goes through the monitor's
PAD_TO_NEXT_LINE, whose stack walk ends at 101Eh with A = 03h; 101Dh is a
HALT and 101Eh jumps to the key handler. That is also where a key ends up if it
comes while a digit interrupt is being taken (SP 0362h): 0360h holds 101Eh.
With SP in ROM there is no CALL, PUSH or POP, subroutines return through
`JP (IY)`, and DE always points at SCRATCH (0C00h), where the handler writes
the key; Return pads the line at DE, which only works at the start of a line,
so nothing uses LDIR.

**Frames that a key can't break.** A key abandons whatever was going on, so a
frame has phases (PHASE at 0C40h) and the key handler carries on from the
start of the one it interrupted: 0, copy the game S (0F10h) to W (0D00h) and
work out the next frame in W; 3, copy W back to S, which is safe to repeat as
W is complete; 1, draw W into the buffer; 4, copy the buffer to the screen,
carrying on from the line it got to; 2, wait. The keys themselves only set
MOVEDIR and MOVETL (move for 6 frames, as the keyboard says only when a key
goes down) and count FIREQ and ANYKEY.

**Waiting in HALTs.** There is no timer, so the wait asks the MM57109 to put
out a number: each of its 12 digits is an interrupt, about 0.5 ms apart (IM 2,
with the vector at 0EE3h for MAME's E3h and 0EFFh for an FFh bus). A frame is
the work plus the byte at 1003h of digit times (22 to start with), about 21
frames a second while playing. The computer is in a HALT most of the wait, so
a key is taken at once, and the web page, which hands a key over when the
computer is halted, doesn't keep it waiting.

## Memory

| | |
|---|---|
| 0C00h-0C3Fh | SCRATCH: the key handler writes here |
| 0C40h-0C63h | phase, keys, digit counts, scratch words, frame count |
| 0D00h-0DEFh | W, the frame being worked out |
| 0EE3h, 0EFFh | IM 2 vectors |
| 0F10h-0FFFh | S, the game between frames |
| 1000h-187Ah | the program |
| 1880h-1FFFh | the buffer for lines 2-31 |
