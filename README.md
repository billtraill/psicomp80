# PSI COMP80

**The web pages: [billtraill.github.io/psicomp80](https://billtraill.github.io/psicomp80/)**: screens, an emulator to run in your browser, annotated ROM listings, a LISP, and the hardware in three versions.

The PSI COMP80 is a Z80 computer designed by J. H. Adams. It was published as a build-it-yourself series, "A scientific computer", in *Wireless World* from April to September 1979, and Powertran sold it as a kit. It has a 64 × 32 character screen, an MM57109 calculator chip for its arithmetic, and BURP, a calculator language, in 3 KB of ROM.

This repository brings it back:
- a MAME driver;
- the ROM, disassembled and annotated;
- twenty more ROMs written for it: FORTH, LISP, Tiny BASIC, Logo, CHIP-8, FOCAL, PILOT, a Z80 assembler and disassembler (ZASM), Prolog, VTL-2, Mouse, Befunge, a spreadsheet (CALC), TRAC, a PL/0 compiler, BF, a line editor (ED), a card-file database (FILE), an adventure engine (QUEST) and APL;
- its programs and the 1980 floppy disc system;
- a web emulator;
- the original board redrawn in KiCad, plus two new versions that run the same ROMs on current parts.

## The web pages

| Page | What it is |
|---|---|
| [PSI COMP80 Screens](https://billtraill.github.io/psicomp80/screenshots.html) | What it looked like: the monitor, BURP, FORTH, LISP, the Game of Life, the articles' pictures |
| [Emulator](https://billtraill.github.io/psicomp80/emulator.html) | The COMP80 in the browser, with all twenty-one ROMs and their example programs |
| [ROM Listings](https://billtraill.github.io/psicomp80/roms.html) | The monitor and the twenty-one languages and programs, annotated, with hex dumps |
| [COMP80 LISP](https://billtraill.github.io/psicomp80/lisp.html) | The LISP that takes BURP's place in the ROM, with examples |
| [Original hardware](https://billtraill.github.io/psicomp80/hardware.html) | The 1979 main board redrawn from the kit: every part and every circuit |
| [v2 hardware](https://billtraill.github.io/psicomp80/hardware_v2.html) | One RP2350 microcontroller, HDMI, a USB keyboard, ROMs and tapes on microSD |
| [v3 hardware](https://billtraill.github.io/psicomp80/hardware_v3.html) | The machine in logic in an Artix-7 FPGA, with HDMI and DisplayPort over USB-C |

Each page is a single self-contained HTML file in this folder, so they also work offline straight from a clone.

## What's in this repository

| Where | What |
|---|---|
| `psicomp80.cpp`, `mame/` | The MAME driver, and the files and script that install it into a MAME checkout; `mame/test_session.lua` types a test session at any of the ROMs |
| `psicomp80.rom`, `psicomp80_*.rom` | The ROM images: the monitor with BURP, or one of the other twenty, in the top 2 KB; each also as `…_ks.rom`, with the key-safe monitor |
| `rom/` | The annotated disassembly (`psicomp80.asm`), which assembles back to the ROM byte for byte, and the listings page |
| `burp/`, `forth/`, `lisp/` | BURP, FORTH and LISP: notes, sources, examples and tests |
| `basic/`, `logo/`, `chip8/`, `focal/`, `pilot/`, `zasm/`, `prolog/` | The other languages, each with its source, `build.sh`, README, examples and tests |
| `vtl/`, `mouse/`, `befunge/`, `sheet/`, `trac/`, `pl0/`, `bf/`, `ed/`, `db/`, `adv/`, `apl/` | The ROMs under Other on the emulator page, laid out the same way |
| `life/`, `pictures/` | The Game of Life and the articles' pictures, as programs and tapes |
| `storm/`, `plasma/`, `dump/`, `fire/`, `banner/` | More machine code: Storm (a shooting game), a plasma, a memory viewer, a fire effect and a scrolling banner |
| `disk/` | The floppy disc extension (October and December 1980): disc image and software |
| `web/` | The web emulator's source and build |
| `hardware/` | The original board in KiCad, and the hardware page |
| `hardware_v2/` | The RP2350 version: board, firmware and tests |
| `hardware_v3/` | The FPGA version: board, Verilog, firmware, simulations, and the Vivado and setup guides |
| `info/` | The *Wireless World* articles and the MM57109 data sheet |
| `c80.sh`, `start.lua`, `autorun.lua` | Start MAME straight into a program, or load a tape |
| `monitor_cmds.md` | The monitor's commands |
| `old/`, `early_versions/` | Earlier disassemblies and driver versions |

## Running it in MAME

1. Get the MAME source next to this folder, at `~/localdev/mame` (or set `MAME_DIR`):

   ```bash
   git clone https://github.com/mamedev/mame.git ~/localdev/mame
   ```

2. Copy the driver, the ROMs and the build scripts into it:

   ```bash
   mame/install.sh
   ```

3. Build just this driver, in the MAME folder:

   ```bash
   cd ~/localdev/mame && ./build.sh
   ```

   `mame/BUILD.md` has the full notes: SDL2 on macOS, and regenerating the project files after the checkout moves.

4. Run it under the debugger with `./run.sh`. Useful debugger commands:

   ```
   bpset 38           ; break on the IM 1 interrupt handler
   wpset 8000,800,w   ; watch writes to the screen (0x800 bytes at 0x8000)
   ```

After changing a ROM, `python3 calc_rom_crc.py` gives the checksum that goes in `psicomp80.cpp`. `convert_to_rom.py` made the first ROM image from the magazine's hex listing.

## Starting a program directly

`c80.sh` starts MAME straight into a program. It copies the program into memory and types the command for you, with no tape to load. Extra MAME options can go after the name.

```bash
./c80.sh life       # Game of Life
./c80.sh boat       # Fig. 22(b) sailing boat
./c80.sh schmitt    # Fig. 22(a) Schmitt trigger circuit
./c80.sh cover      # the screen on the kit leaflet's cover
./c80.sh alph       # the monitor's ALPH character set test
./c80.sh list       # LIST 1000 with Life loaded
./c80.sh disk       # floppy disc software, program disc in the drive
./c80.sh forth      # FORTH ROM (FORTH in place of BURP)
./c80.sh forthlife  # Game of Life typed into FORTH
./c80.sh mandel     # Mandelbrot set typed into FORTH
./c80.sh lisp       # LISP ROM (LISP in place of BURP)
./c80.sh deriv      # symbolic differentiation typed into LISP
./c80.sh hanoi      # Towers of Hanoi typed into LISP
./c80.sh queens     # eight queens typed into LISP
./c80.sh ready      # just the monitor
```

The [screens page](https://billtraill.github.io/psicomp80/screenshots.html) shows what each one looks like.

## BURP

BURP, the original language, runs. At READY type `MOV 0BB50C000C00`, then `^` (RS), then `RUN 5` and a space for the articles' sample program. [`burp/README.md`](burp/README.md) has the walkthrough, the tests, and what was fixed to make it run: the MM57109 model, the interrupts, and one misread ROM byte.

## FORTH and LISP

`psicomp80_forth.rom` and `psicomp80_lisp.rom` replace BURP with a small FORTH or LISP and leave the monitor unchanged. The driver offers them as BIOS options, with BURP as the default:

```bash
cd ~/localdev/mame && ./mamed psicomp80 -bios forth
```

```bash
cd ~/localdev/mame && ./mamed psicomp80 -bios lisp
```

Then press `^` (RS) at READY, as for BURP. See [`forth/README.md`](forth/README.md), [`lisp/README.md`](lisp/README.md) and the [LISP page](https://billtraill.github.io/psicomp80/lisp.html).

## The key-safe monitor

The 1979 monitor takes a key only while the CPU waits for one in a HALT. A key that comes at any other moment restarts the monitor, so a key stops a running program, and a game that reads keys while it runs can be restarted by one. Every ROM also comes with a key-safe monitor, made for this project, which ignores such a key instead and lets the program carry on. The ROM images are `psicomp80_ks.rom` and `psicomp80_<lang>_ks.rom`, and the driver's BIOS names end in `ks`:

```bash
cd ~/localdev/mame && ./mamed psicomp80 -bios pl0ks
```

With it a running program can only be stopped with RESET (F3 in MAME, Esc on the web page), and keys pressed while a program is busy are lost rather than restarting it. The web emulator has the same choice under Monitor. The change is the keyboard handler at 0066, with ten bytes found by moving the code at 0095–012F up into the free bytes at 0130; the entry points the languages use are where they were. See [`rom/README.md`](rom/README.md).

## Tapes

Each tape loads at 1000 and runs with `RUN 1000`. `autorun.lua` loads the mounted tape fast-forwarded, checks it against the `.bin` next to the `.wav`, retries a bad load, and types `RUN 1000`. Don't touch the keyboard until the program starts.

```bash
cd ~/localdev/mame && ./mamed psicomp80 -cass ~/localdev/psicomp80/life/life.wav -autoboot_script ~/localdev/psicomp80/autorun.lua
```

The other tapes are `pictures/boat.wav` (Fig. 22(b)), `pictures/schmitt.wav` (Fig. 22(a)) and `pictures/cover.wav` (the kit leaflet's cover). In Life, R starts a new random board, P pauses and S goes back to the monitor (see [`life/README.md`](life/README.md)). For the pictures, any key goes back to the monitor.

To load a tape by hand: type `READ 1000`, then Tab → Tape Control → Play (Tab again to close the menu). Wait for the tape to stop, press any key, then type `RUN 1000`.

## Floppy disc

The floppy disc extension from the October and December 1980 articles: an FD1771 controller and an 8 inch IBM 3740 drive (77 tracks × 26 sectors × 128 bytes). `disk/programs.img` is a disc with all the programs on it.

```bash
./c80.sh disk
```

Then use `READ` followed by the destination, track, sector and number of sectors, each followed by a space. For example, `READ 1000 1 1 6` then `RUN 1000` runs the Game of Life, and `READ 8000 0 1 16` shows the disc's catalogue. Type `RUN 1D00` before each disc command.

`FORMAT` builds a track image at C000, which needs the 32 KB memory expansion. That machine is `psicomp80x` ("COMP80 with 32K expansion"):

```bash
./c80.sh 32k disk
```

See [`disk/README.md`](disk/README.md).

## In a web browser

[`emulator.html`](https://billtraill.github.io/psicomp80/emulator.html) is the COMP80 as a single web page. It switches between the BURP, FORTH and LISP ROMs, runs all the example programs by typing them in for you, and has a help page for each language. It has no tape or disc. Rebuild it with `python3 web/build.py`; see [`web/README.md`](web/README.md).

## ROM listings

[`rom/psicomp80.asm`](rom/psicomp80.asm) is the annotated disassembly of `psicomp80.rom` (the monitor and BURP), and it assembles back to the ROM byte for byte. The [listings page](https://billtraill.github.io/psicomp80/roms.html) shows it with the FORTH and LISP sources, each name and jump a link, and hex dumps of all three ROMs. `rom/build.sh` checks the sources against the ROMs and rebuilds the page. See [`rom/README.md`](rom/README.md).

## Hardware

- **The original** ([page](https://billtraill.github.io/psicomp80/hardware.html), [`hardware/`](hardware/)): the 1979 main board in KiCad, with copper routed or traced from the kit artwork. The page talks through each circuit and lists every part. Rebuild it with `python3 hardware/tools/make_hardware_page.py`.
- **v2** ([page](https://billtraill.github.io/psicomp80/hardware_v2.html), [`hardware_v2/`](hardware_v2/)): one RP2350 microcontroller emulates the machine. It has HDMI, a USB keyboard, ROMs and tapes on microSD, and USB-C power. Board, firmware and tests.
- **v3** ([page](https://billtraill.github.io/psicomp80/hardware_v3.html), [`hardware_v3/`](hardware_v3/)): the machine in logic in an Artix-7 XC7A100T FPGA. It has HDMI, a USB keyboard, microSD, USB-C power, and DisplayPort over a second USB-C socket. [`VIVADO_TODO.md`](hardware_v3/VIVADO_TODO.md) has the build steps still to do, and [`SETUP.md`](hardware_v3/SETUP.md) covers setting up a board.

## Things to try

- The monitor's commands are in [`monitor_cmds.md`](monitor_cmds.md). `ALPH` shows the character set; `LIST 1000` lists memory; `ALT` changes it.
- `RUN 01B6` was once thought to be a guessing game. It's actually a jump into the middle of the monitor's register display routine (01AA), which is why it behaves oddly.

## To do

- [ ] **v3: make and bring up a board** ([`SETUP.md`](hardware_v3/SETUP.md)). Check the USB-C monitor with the plug both ways up: the lane order and AUX polarity for each orientation were worked out from the specifications, not measured.
- [ ] **v2: make and test a board.** The firmware's machine matches the web emulator in host tests, but it hasn't run on hardware.
- [ ] **v2: fit a flat USB-A socket.** The Würth 614004134726 stands upright; v3 now uses a flat Molex 67643.
- [ ] **v3, optional: power from the video USB-C.** Today only J1 powers the board. Taking power from J7 needs a power mux, overvoltage protection, and firmware that asks the monitor for 5 V and swaps data roles.
- [ ] **Web emulator, optional: tapes and discs.** Programs are copied into memory instead.

Done:
- [x] **v3: build the bitstream.** Vivado 2026.1 builds it and every clock meets timing; [`hardware_v3/VIVADO_TODO.md`](hardware_v3/VIVADO_TODO.md) has the results.

Done from the original list:
- [x] Worked out how the monitor parses commands: `LIST 1000` works, and the reason `RUN 01B6` misbehaves is above.
- [x] Fixed the keyboard: the driver latches each key and pulses NMI, as the 1979 keyboard did.
- [x] Documented the monitor commands ([`monitor_cmds.md`](monitor_cmds.md)).
- [x] Disassembled and annotated the ROM ([`rom/psicomp80.asm`](rom/psicomp80.asm)).
- [x] Put the project in git, on GitHub with web pages.
