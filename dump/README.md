# Memory dump

A memory viewer for the PSI COMP80, in Z80 assembly. It shows 30 lines of 16
bytes: the address, the bytes in hex in pairs, and the same bytes as
characters, with a dot for anything that isn't a letter, digit or sign.

    DUMP 0000   N B PAGE   D U LINE   G ADDRESS   Q QUIT
    ADDR 0001 0203 0405 0607 0809 0A0B 0C0D 0E0F 0123456789ABCDEF
    0000 31DF 1F11 0080 CDCE 0320 1205 0104 191D 1........ ......
    0010 CDC4 033E 80D3 00CD 5503 FEFC 200D 1822 ...>....U... .."

## Running it

    ./c80.sh dump

or in the monitor: load `dump.bin` at 1000h and type `RUN 1000`.

| Key | |
|---|---|
| N, B | next page, back a page (480 bytes) |
| D, U | down a line, up a line (16 bytes); Return also goes down a line |
| G | then four hex digits: go to that address (a `?` shows while it waits for them) |
| Q | back to the monitor (FS does the same) |

The first address is the word at 1003h, 0000h to start with, and it is kept
when you leave, so `RUN 1000` comes back to the same place. To start
somewhere else, `LOAD 1003 00 1D @` (low byte first) before `RUN 1000`
starts at 1D00h. It works with any of the ROMs.

## Reading keys at any time

A key strobes NMI, and the monitor's NMI handler goes back to READY unless
the interrupted instruction comes after a HALT. Like the Game of Life, the
viewer keeps its stack pointer in ROM, at 0362h. The NMI's push is lost
(ROM ignores writes), and the handler takes the ROM word at 0360h, 101Eh, as
the return address; the program has a HALT byte at 101Dh, so the handler
accepts it and returns to the key handler at 101Eh with the key in A. The
word is in the monitor, so the trick works with every ROM.

Return takes another path: the handler calls 03C4h to pad to the next line,
which returns through the ROM words at 035Eh (03C4h, so it runs once more)
and 0360h, and arrives at the key handler with A = 03h, taken as D. That
needs DE to point at the start of a line (no padding to do), so DE always
points at 1F40h, where the handler also stores each key.

With SP in ROM there can be no CALL, PUSH or POP: the hex printer returns
with `JP (IY)`. A key can come at any moment, even half way through drawing
a page (a page takes about 45 ms); it abandons the page, and the key handler
draws it again from the new address.

## Files

| File | |
|---|---|
| `dump.asm` | source |
| `dump.bin` | assembled program, 1000h-1214h |
| `test_dump.lua` | MAME test: tries every key, checks the address and first line each time (including five N presses in quick succession, which arrive while a page is being drawn), then Q |

## Rebuilding

    z80asm -i dump.asm -o dump.bin

z80asm reports an error but still writes a file, so check what it prints.
Run the test from the MAME directory:

    DUMP_BIN=~/localdev/psicomp80/dump/dump.bin ./mamed psicomp80 -rompath roms \
      -autoboot_script ~/localdev/psicomp80/dump/test_dump.lua \
      -nothrottle -video none -sound none
