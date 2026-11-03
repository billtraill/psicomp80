# COMP80 ED

A line editor for the PSI COMP80 in the style of the Unix `ed` and the
editors of its time, written for this project in the 2 KB of ROM
(0400h–0BFFh) that held BURP. The monitor (0000h–03FFh) is unchanged; RS at
READY enters ED, and the top line shows ED.

    sh ed/build.sh

assembles `ed.asm` with z80asm and writes `ed.bin` and `../psicomp80_ed.rom`.

## Using it

ED keeps a buffer of lines and a current line, dot. At the `*` prompt type a
command: an optional address or range, then a letter. A, I and C then take
lines of text until a line that is just a full stop.

    *A
    DEAR AUNT JEAN,
    THANK YOU FOR THE SOCKS.
    .
    *2S/SOCKS/LOVELY RED SOCKS/
    *,N
    1 DEAR AUNT JEAN,
    2 THANK YOU FOR THE LOVELY RED SOCKS.

### Addresses

| | |
|---|---|
| `n` | line n |
| `.` | the current line |
| `$` | the last line |
| `/TEXT/` | the next line containing TEXT, going round from the end to the start; `//` looks for the same text again |
| `+n`, `-n` | after an address, n lines on or back; alone, from dot (`+` and `-` alone are 1) |
| `a,b` | lines a to b; `a,` is a to the end |
| `,` or `%` | the whole buffer, 1,$ |

### Commands

| | |
|---|---|
| `A` | append lines after the line (default dot); `0A` puts them at the start |
| `I` | insert lines before the line |
| `C` | change: delete the lines and type new ones in their place |
| `D` | delete; dot is then the line after them |
| `P` | print the lines |
| `N` | print them with their numbers |
| `V` | view the 30 lines round dot (or round the address), numbered, with a `>` after the number of the current one |
| `M d` | move the lines to after line d (0 for the start) |
| `T d` | copy them to after line d |
| `J` | join the lines into one (default dot and the line after) |
| `S/OLD/NEW/` | change the first OLD in each line to NEW; `G` after it changes every one. Any character can stand in for `/`; `S//NEW/` uses the last text looked for |
| `G/TEXT/cmd` | do cmd on every line in the range (default all) containing TEXT, with dot at it: `G/X/D` deletes them. With no cmd it prints them |
| `=` | print the line number of the address (default `$`, the number of lines) |
| `E` | empty the buffer |
| `W` | show how to save the buffer on tape |
| `R` | take in a buffer read back from tape |
| `Q` | go back to the monitor (RS comes back with the buffer kept) |
| an address alone | make it dot and print it |
| Return alone | print the next line |

Default ranges are dot for the commands that work on lines (D, P, N, C, M,
T, S). Text is plain: patterns are matched as they stand, with no special
characters. A mistake prints `?` and what was wrong: ADDRESS, COMMAND, NO
MATCH, PATTERN, TOO LONG (a changed line over 127 characters), FULL or NO
TEXT.

### Saving on tape

`W` prints the size of the buffer and the monitor command that records it,
such as `TAPE 0C100D2F`: press FS for the monitor, type that, and RS comes
back to ED. To load it again, FS, `READ 0C10` (or the first address `W`
showed), a key when the tape has been read, then RS and `R`, which finds the
end of the text and says how many bytes it has.

### Keys

The keyboard can't type `^` (it is RS, the rubout), `_` (Return) or `\`
(FS), so they can't be in text or patterns. Any key while ED is busy resets
to the monitor, as on the real machine; RS comes back to ED with the buffer
as it was.

## Memory

| | |
|---|---|
| 0C00–0C09 | header: a magic number, the end of the text, its start and limit, and dot |
| 0C10–1BFF | the text: lines ending in 0Dh, with a 0 after the last (about 4 KB) |
| 8800–FFEF | the text instead, with the 32 KB expansion (about 30 KB) |
| 1C00–1CFF | the line S builds, and S's new text |
| 1D00–1DBF | the input line, the last pattern, the cursor and ED's variables |
| 1E00–1E9F | G's command and pattern |

ED looks for the expansion when it starts with no buffer in memory: without
it, 8800h is the screen again.

## Examples

`examples/` has four sessions, each a file of lines to type (no blank
lines; every line is typed):

| | |
|---|---|
| `letter.ed` | a short letter typed in with A, a word changed with S, a line moved with M and a P.S. inserted before the last line with I |
| `list.ed` | a shopping list: G/ X/D deletes the items marked X, two lines are added and joined, and S changes the join to " AND " |
| `search.ed` | the planets: searches, `//`, `$-2` and a range from dot, then G with S...G to mark every U |
| `view.ed` | lines copied with T, S on a range with G, and V showing the 30 lines round line 8 |

## Tests

`tests/` has a session for each example and `basic.txt`, which covers the
empty buffer, G with D, Return alone, relative addresses, I, C, M, searches,
S with the last pattern, errors, E, T, M, J, W and R. Each runs in
`web/tools/session.js` and in MAME with `mame/test_session.lua`
(`SESSION_CURS=1DA0`), and the two give the same screens.

## How it works

The buffer is one block of text from BEG up to the 0 at ENDP. A line
number is found by counting 0Dh bytes from the start, so every command
works by line number and there is nothing else to keep up to date.
Inserting moves the rest of the text up with LDDR and deleting moves it
down with LDIR. M copies the lines (like T) and then deletes the old ones;
S builds the new line in a buffer and puts it in place of the old one. G
runs its command on each line that matches, adjusting where it is by the
number of lines the command took away or added.

Keys and the screen work as in COMP80 FORTH and VTL-2: the monitor's NMI
handler echoes each key and wakes the HALT in RAWKEY; RS while waiting is a
rubout, and RS at any other time restarts ED, keeping the buffer.

Left out to fit: undo, the H command (the error says why instead),
patterns with special characters, marks, and G inside G.
