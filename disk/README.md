# Floppy disc

The floppy disc extension from Wireless World, *Floppy disc system for the
scientific computer* by J. H. Adams (parts 1 and 2, October and December 1980;
scans in `info/FD_Part_1_Oct_80.pdf` and `info/FD_Part_2_Dec_80.pdf`).

## Hardware (in the driver)

- **FD1771** controller, clocked at 2 MHz for an 8in drive. Its data bus is
  inverted, which is why the software CPLs every byte.
- **8in single-sided drive**, IBM 3740 format: 77 tracks of 26 sectors of 128
  bytes, about 250 KB. Sectors are numbered **1 to 26**.
- **Ports** (Oct 1980 Table 2):

  | Register | Read | Write |
  |---|---|---|
  | Status / Command | `IN 05` | `OUT A0` |
  | Track | `IN 0D` | `OUT A8` |
  | Sector | `IN 15` | `OUT B0` |
  | Data | `IN 1D` | `OUT B8` |

- **Interrupt controller**: a 74LS147 priority encoder gives Z80 mode 2
  vectors. DRQ gives `F3`, INTRQ gives `F1`. The software sets I = 1D, so the
  vectors are read from 1DF3 and 1DF1.

Disc images are raw sector dumps (`.img`, 256,256 bytes, track 0 sector 1
first). Mount one with `-flop file.img`, or through MAME's File Manager, which
can also create a blank formatted disc.

## The disc software

`fdos_listing.txt` is Table 4 of the December article (1D00–1EFF) as printed.
It was written for the author's Mark III monitor, which has two routines at
other addresses, so `make_disk.py` patches those calls for the original
COMP80 ROM and writes `fdos.bin`:

| In the listing | Routine | Patched to |
|---|---|---|
| `CALL 03C6` (5 places) | new line, keeps A | `CALL 03C4` |
| `CALL 0261` (7 places) | print inline text | `CALL 03CE` |

`CALL 03DE` (read 4 hex digits) is the same in both ROMs.

### Starting it

```bash
~/localdev/psicomp80/c80.sh disk
```

This loads the disc software at 1D00, puts `programs.img` in the drive and
types `RUN 1D00`. The head steps to track 0. Or load it from tape:

```bash
cd ~/localdev/mame && C80_ADDR=1D00 ./mamed psicomp80 -cass ~/localdev/psicomp80/disk/fdos.wav -flop ~/localdev/psicomp80/disk/programs.img -autoboot_script ~/localdev/psicomp80/autorun.lua
```

### Commands

Type `RUN 1D00` before each command; when a command finishes the computer
goes back to READY.

| Type | Prompts |
|---|---|
| `READ ` | DESTINATION (4 hex digits, no space), TRACK, SECTOR, NUMBER OF SECTORS |
| `WRITE ` | SOURCE (4 hex digits), TRACK, SECTOR, NUMBER OF SECTORS |
| `FORMAT ` | track number (see below) |

Track, sector and count are decimal, each followed by a space. A transfer
carries on into the next track after sector 26. Each sector is retried up to
20 times; WRITE reads every sector back to check it. If a sector still fails,
`ERROR AT TRACK nnn SECTOR nnn` appears.

For example, to load the Game of Life: `RUN 1D00`, then `READ 1000`, `1 `, `1 `,
`6 `, then `RUN 1000`.

## The program disc

`programs.img` holds:

| Program | Load at | Track | Sector | Sectors | Then |
|---|---|---|---|---|---|
| Catalogue screen | 8000 | 0 | 1 | 16 | (it appears on the screen) |
| Game of Life | 1000 | 1 | 1 | 6 | `RUN 1000` |
| Sailing boat | 1000 | 2 | 1 | 17 | `RUN 1000` |
| Schmitt trigger circuit | 1000 | 3 | 1 | 17 | `RUN 1000` |
| Disc software | 1D00 | 4 | 1 | 4 | `RUN 1D00` |

Reading track 0 to 8000 shows the catalogue. The Game of Life uses RAM up to
1FFF, so it overwrites the disc software; load the software again afterwards.

`c80.sh disk` uses `programs.img` itself, so WRITE changes it. Run
`python3 make_disk.py` to rebuild the original.

## Limits

- **FORMAT** builds a whole track image at C000, which needs the 32 KB memory
  expansion. This emulation only has the 5 KB of RAM at 0C00 (C000 is a mirror
  of the screen), so FORMAT doesn't work. Discs created in MAME's File Manager
  come ready formatted.
- **Track 77**: the article suggests reading track 77 to see the error
  message. With this listing the seek can never be verified, so it retries the
  seek forever instead. Press Esc to reset.
- The disc software leaves the Z80 in interrupt mode 2. That doesn't affect
  the monitor or these programs; reset with Esc before using BURP.

## Files

| File | |
|---|---|
| `fdos_listing.txt` | the listing as printed |
| `make_disk.py` | patches it and builds the disc image |
| `fdos.bin` | disc software for this ROM, 1D00–1EFF |
| `fdos.wav` | disc software on tape (`TAPE 1D001F00`) |
| `programs.img` | the program disc |
