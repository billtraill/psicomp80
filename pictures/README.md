# Fig. 22 pictures on tape

Recreations of the two pictorial displays in Fig. 22 of the PSI COMP80 articles
(Wireless World, August 1979, p. 81; page 22 of `info/PSI-Comp-80-Wireless-World-1979-80.pdf`):

| Tape | Picture |
|---|---|
| `schmitt.wav` | (a) Schmitt trigger circuit diagram |
| `boat.wav` | (b) sailing boat, "THE HMS SEA HAWK" |
| `cover.wav` | the screen on the cover of the kit leaflet (see below) |

The photos are too blurry to copy exactly, so these were laid out by hand from
measurements of the photos, using the COMP80 graphics character set.
Panel (c) is the monitor's own `ALPH` test pattern. The program listing in (d)
can't be read, so (d) and (e) aren't reproduced.

`cover.wav` is a third picture, not from the articles: the screen on the
cover of the Powertran kit leaflet (`../info/pictures/kit-leaflet.webp`),
where the television shows "ψCOMP 80" in block letters. `cover.py` draws the
letters, measured from the photo, on the quarter-block grid; `cover_screen.png`
is the emulator showing it.

## Loading a picture

One line (loads the tape, checks it, and runs it):

    cd ~/localdev/mame && ./mamed psicomp80 -cass ~/localdev/psicomp80/pictures/boat.wav \
      -autoboot_script ~/localdev/psicomp80/autorun.lua

Use `schmitt.wav` for the circuit, or `cover.wav` for the leaflet's screen. Or by hand:

1. Start MAME, open File Manager → cassette and mount `schmitt.wav` (or
   `boat.wav`), or start with `-cass pictures/schmitt.wav`.
2. Type `READ 1000`, then Tape Control → Play.
3. When the tape has finished (about 40 s), press any key to end READ.
4. Type `RUN 1000`. Press any key to get back to the monitor.

Each tape holds a 16-byte loader at $1000 that copies the 2 KB screen image at
$1010 to video RAM ($8000) and then waits.

## Rebuilding

    python3 make_programs.py        # writes *.bin and *_preview.png (schmitt, boat, cover)

Then record each .bin to tape with MAME (run from the MAME directory):

    C80_BIN=/path/to/schmitt.bin ./mamed psicomp80 -rompath roms \
      -cass /path/to/schmitt.wav -autoboot_script /path/to/record_tape.lua \
      -nothrottle -video none -sound none

The .wav must already exist (an empty 44.1 kHz mono WAV is fine).
`verify_tape.lua` does READ / RUN on a mounted tape and saves a snapshot.
