# PSI COMP 80 main board drawings

Vector versions of the two Powertran kit sheets for the main board, and a KiCad
board built from them. All of it comes from the photos in `info/pictures/`
(`kit-component-layout.webp` and `kit-pcb-artwork.webp`). The Wireless World
articles only print circuit diagrams, not the board.

| File | What it is |
|---|---|
| `psicomp80_component_layout.svg` | The component layout sheet, redrawn: board outline, section boundaries, every IC with its number and type, the discrete parts, and the keyboard legends. |
| `psicomp80_pcb_artwork.svg` | The copper artwork. The red and blue layers are traced from the photo. The pads, drill holes, keyboard legends and crop marks are redrawn on top. Each part is an Inkscape layer, so you can switch layers on and off. |
| `kicad/psicomp80.kicad_pro`, `kicad/psicomp80.kicad_pcb` | A KiCad 10 project. Every part sits on a standard KiCad footprint. The section lines and titles are on User.Drawings. The traced copper is on two user layers, **Artwork.Red** and **Artwork.Blue**, as a routing guide. |
| `kicad/PSI_COMP80.pretty`, `kicad/fp-lib-table` | A project library with the two-pad key switch footprint. |

The board measures 16 in × 12 in between the crop marks on the artwork. The scale
comes from the 0.1 in DIP pad pitch.

## How accurate it is

- **IC positions and numbers** are good. The two photos register onto each other
  to within a few hundredths of an inch, and every IC is snapped to the 0.1 in
  grid. A few labels were hard to read, so check these against the circuit
  diagrams: IC36, IC37, IC38, IC39, IC46, IC48, IC49 and IC50. See `NOTES` in
  `tools/board_data.py`.
- **Discrete parts** (resistors, capacitors, transistors, power-supply parts) are
  placed roughly. The photo is too coarse to read most resistor numbers, so these
  have placeholder references from 101 upwards (R101, C101, ...). KiCad's standard
  lead spacings don't always match the sheet, which is why DRC reports about a
  dozen pad clashes between neighbouring discrete parts.
- **Traced copper** is approximate. The artwork photo only resolves about 65 pixels
  per inch, so a thin track is one or two pixels wide. Where tracks run close
  together, as in the memory address bus, they merge into blobs. The tracing is
  fine as a picture or for following a track by eye. It is **not** good enough to
  make a board from.
- **The KiCad board has no nets or routed copper.** The connections can't be read
  from the photo. To get a working board, enter the schematic from the circuit
  diagrams in Parts 1–6, then route it using the Artwork layers as a guide.

A better source would improve all of this a lot. If you can scan the artwork
sheet flat at 600 dpi (an A3 scanner, or in overlapping pieces), change the
corners in `tools/trace_artwork.py` and re-run it. The traced copper would then
be close to track-accurate.

## Regenerating

The scripts are in `tools/`:

- `board_data.py` holds every placement, read from the photos. Edit this file to
  correct a part.
- `trace_artwork.py` traces the copper layers from the photo into
  `artwork_traced.json`. You only need it if the photo or the corner points
  change. It needs `numpy`, `opencv-python`, `Pillow` and the `potrace` command.
- `make_drawings.py` writes both SVGs. It uses only the standard library.
- `make_kicad.py` writes the KiCad board. It has to run under KiCad's own Python,
  because it needs `pcbnew`.

```bash
cd hardware/tools && python3 make_drawings.py
```

```bash
cd hardware/tools && /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 make_kicad.py
```
