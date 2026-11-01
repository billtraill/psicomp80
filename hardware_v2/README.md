# COMP80 v2: the COMP80 on an RP2350

The same computer as the 1979 board, built from current parts: one Raspberry Pi
RP2350A runs the unchanged COMP80 ROM images on an emulated Z80. It shows the
screen over HDMI, takes a USB keyboard, loads ROMs and tapes from a microSD card,
and runs from a USB-C supply. The web page, `../hardware_v2.html`, walks through
it with a zoomable board.

| File | What it is |
|---|---|
| `tools/design.py` | The design: every part, footprint, connection and position. Writes `netlist.json` and `bom.csv` |
| `tools/make_board.py` | Builds `kicad/comp80v2.kicad_pcb` from the design (KiCad's Python): four layers, the parts, the RP2350's supply pins tracked by hand, a via beside every plane pad |
| `kicad/` | The KiCad 10 board, routed and filled. KiCad's DRC: no errors |
| `netlist.json`, `bom.csv` | The connections, and the parts list grouped for ordering |
| `firmware/` | The RP2350 firmware (C, Pico SDK); see its README. `comp80v2.uf2` is a build |
| `tools/make_page.py`, `tools/page_template.html` | Make `../hardware_v2.html` |

## The board

75 × 55 mm, four layers: signals on the outside, ground on In1.Cu, 3.3 V on In2.Cu.

- **U1 RP2350A** at 240 MHz (1.2 V core), with 4 MB of QSPI flash (U2) and a 12 MHz
  crystal. Its on-chip regulator makes the 1.1 V core supply through L1.
- **HDMI** (J2) from the HSTX port, GPIO12–19, through 270 Ω resistors.
- **USB keyboard** (J3) through PIO-USB on GPIO20/21.
- **microSD** (J4) in SPI mode on SPI1, GPIO8–11.
- **USB-C** (J1) for 5 V and for loading firmware; an AP2112K makes 3.3 V.
- RESET and BOOTSEL buttons, a HALT LED, and a debug header with SWD and the serial
  console.

## Regenerating

```bash
cd hardware_v2/tools && python3 design.py
```

```bash
cd hardware_v2/tools && /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 make_board.py
```

```bash
cd hardware/tools && /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 route_board.py --pcb ../../hardware_v2/kicad/comp80v2.kicad_pcb --freerouting freerouting-2.5.0.jar --java /opt/homebrew/opt/openjdk/bin/java --passes 80
```

```bash
cd hardware_v2/tools && python3 make_page.py
```

Routing takes about two minutes and is deterministic.

## Not built yet

The board passes KiCad's DRC, and the firmware compiles and passes its tests on a
Mac, but neither has been on real hardware. The RP2350 is a 0.4 mm QFN with 0402
capacitors beside it, so it wants a stencil and reflow or an assembly service.
