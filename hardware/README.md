# PSI COMP 80 main board drawings

Vector drawings of the Powertran kit's main board, and a routed KiCad board. The board
gets its parts and positions from the photos of the kit sheets in `info/pictures/`
(`kit-component-layout.webp` and `kit-pcb-artwork.webp`). It gets its electrical
connections from the circuit diagrams in the Wireless World articles.

| File | What it is |
|---|---|
| `psicomp80_pcb_routed.svg` | **The electrically accurate artwork.** The board routed from the netlist transcribed from the article circuit diagrams, drawn like the kit sheet and seen from the component side: blue is the component (top) side, red the solder (bottom) side. |
| `psicomp80_component_layout.svg` | The component layout sheet, redrawn: board outline, section boundaries, every IC with its number and type, the discrete parts as drawn on the kit sheet, and the keyboard legends. |
| `psicomp80_pcb_artwork.svg` | The kit's original copper artwork, traced from the photo (approximate), with the pads and legends redrawn on top. |
| `kicad/psicomp80.kicad_pro`, `kicad/psicomp80.kicad_pcb` | A KiCad 10 project. Every part sits on a standard footprint with its nets, and the board is routed on two layers. The traced original copper stays on two user layers, **Artwork.Blue.Top** and **Artwork.Red.Bottom**, for comparison. |
| `kicad/PSI_COMP80.pretty`, `kicad/fp-lib-table` | The project library: the two-pad key switch footprint and the wiring-pad footprints. |
| `tools/netlist/` | The netlist, one file per article figure, plus the merged `psicomp80_netlist.json`. Its README covers sources, conventions and the points where a figure had to be interpreted. |
| `../hardware.html` | A web page of the board: zoom and pan, each side's copper on and off (routed or traced kit artwork), click a part or track for its pins and signal, the circuits talked through, and the parts list. `tools/make_hardware_page.py` makes it from the KiCad board and the netlist, with `tools/hardware_template.html`; it needs only Python 3. |

The board is 16 in × 12 in between the crop marks on the artwork. The scale comes from
the 0.1 in DIP pad pitch. The board is double-sided. On the kit's artwork the "1" mark
and the "COMPONENT SIDE" legend are printed in blue, and the "2" mark is red and reads
mirrored. So blue is the component side and red the solder side.

## How accurate it is

- **Connections** follow the article circuit diagrams pin by pin. Some figures don't
  print every pin number, and the keyboard encoder isn't drawn at all; the netlist
  README lists each case.
- **The routed tracks are not the original tracks.** Electrically they match the
  article, but the track paths don't follow the 1979 artwork. The 21L02 RAM columns are
  the exception: `make_kicad.py` pre-routes their buses itself on the component side,
  the way the original artwork does, and Freerouting routes everything else.
- **Design checks.** KiCad's DRC on the routed board finds 0 unconnected pads, and no
  clearance violations or shorts. Tracks are 0.25 mm with 0.2 mm clearance; power nets
  are 0.6 mm. Freerouting necks a few tracks down to 0.125–0.19 mm between pads. The
  remaining DRC messages are cosmetic: silkscreen overlaps, and courtyard overlaps
  where the kit sheet packs parts tightly. The "library not included" warnings go away
  once KiCad's default footprint libraries are set up.
- **IC positions** match the kit sheet. The two photos register onto each other to
  within a few hundredths of an inch, and every IC is snapped to the 0.1 in grid. IC
  types follow the article where the photo was hard to read; see `NOTES` in
  `tools/board_data.py`.
- **Discrete parts** sit at their kit-sheet position when the kit sheet shows the same
  reference, such as R40, C14, TR9 or VR1. Otherwise they go in the nearest free spot,
  in their own section of the board, to the pins they connect to.
- **The traced original copper** is approximate. The artwork photo only resolves about
  65 pixels per inch, so where tracks run close together they merge. A flat 600 dpi
  scan of the artwork sheet would make it close to track-accurate: change the corners
  in `tools/trace_artwork.py` and re-run it.

## Regenerating

The scripts are in `tools/`:

| Step | Script | Runs under |
|---|---|---|
| 1 | `merge_netlist.py`: merges `netlist/net_*.json` and reports dangling nets | any Python 3 |
| 2 | `make_kicad.py`: builds the board, placing parts and putting nets on pads | KiCad's Python |
| 3 | `route_board.py`: routes the board with Freerouting (needs Java) | KiCad's Python |
| 4 | `export_routed_svg.py`: writes `psicomp80_pcb_routed.svg` | KiCad's Python |
| – | `make_drawings.py`: writes the component layout and traced artwork SVGs | any Python 3 |
| – | `trace_artwork.py`: traces the copper out of the photo (only if the photo changes) | numpy, OpenCV, Pillow, potrace |

`board_data.py` holds every placement read from the photos. Edit it to move a part.

```bash
cd hardware/tools && python3 merge_netlist.py
```

```bash
cd hardware/tools && /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 make_kicad.py
```

```bash
cd hardware/tools && /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 route_board.py --freerouting freerouting-2.5.0.jar --java /opt/homebrew/opt/openjdk/bin/java
```

```bash
cd hardware/tools && /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 export_routed_svg.py
```

Freerouting comes from https://github.com/freerouting/freerouting/releases, and Java
from `brew install openjdk`.
