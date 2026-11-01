# Ordering the v3 board

Everything a board house needs to quote and build the COMP80 v3 board. It's laid out for [PCBWay](https://www.pcbway.com/), but any house that makes 6-layer boards and assembles BGAs can use the same files.

| File | What it is | Upload it to |
|---|---|---|
| `comp80v3_gerbers.zip` | Gerbers (six copper layers, solder mask, silkscreen, paste, outline) and Excellon drill files, plated and unplated | PCB quote |
| `comp80v3_bom_pcbway.csv` | The parts list in PCBWay's layout: 43 lines, 128 parts | Assembly quote |
| `comp80v3_cpl.csv` | Pick-and-place: each part's centre and rotation, in mm from the board's bottom-left corner | Assembly quote |
| `comp80v3_assembly.pdf` | Assembly drawing: part outlines and references | Assembly quote, as a reference |

All the files share one origin, the bottom-left corner of the board, so they line up.

## The board: settings for the quote form

| Setting | Value |
|---|---|
| Layers | 6 (signal, ground, 3.3 V, 1.0 V, 1.8 V, signal) |
| Size | 110 × 84 mm, rectangular |
| Thickness | 1.6 mm |
| Minimum track / gap | 0.15 mm / 0.12 mm: choose 4/4 mil |
| Minimum hole | 0.2 mm (vias are 0.45 mm across with 0.2 mm holes, 0.125 mm annular ring) |
| Holes | 485 plated, 8 unplated (four 2.7 mm mounting holes, four USB-C pegs) |
| Surface finish | ENIG: the BGA needs a flat finish |
| Solder mask / silkscreen | Any colour; white silkscreen reads best on green |
| Vias | Tented |
| Copper | 1 oz outer, 0.5 oz inner is fine |

Things to mention in the order notes:

- **Via in pad**: the FUSB302 (U6) has one 0.2 mm via inside its exposed ground pad. Ask for it to be plugged and capped (filled, plated over), or at least tented from the bottom, so solder doesn't wick down it.
- **Impedance control** is optional. The HDMI and DisplayPort pairs are 0.15 mm tracks on the outer layers over the ground plane, but they weren't routed as tightly coupled pairs. If you order impedance control, ask for a stack-up that brings a 0.15 mm outer track close to 50 Ω. Don't expect a strict 100 Ω differential.
- Check the minimum annular ring and hole size against PCBWay's current capabilities for 6-layer boards when you quote. 0.125 mm rings on 0.2 mm holes are near the limit of a standard process.

## Assembly

| | |
|---|---|
| Sides | Top only |
| Unique parts | 43 |
| SMD parts | 125, including 1 BGA (U1) |
| Through-hole | 3 (J3, J5, J6); J1, J2 and J7 are surface mount with through-hole tabs |

- **The FPGA** (U1, XC7A100T-1FGG484C) is a 484-ball BGA at 1.0 mm pitch. Ask for X-ray inspection. It's also by far the dearest part: buy it through an authorised distributor, or send PCBWay one you've bought (consigned parts), to avoid fakes.
- **Passives**: each line gives the full spec (value, size, voltage, dielectric, tolerance) and a suggested Murata or Yageo part. Any part to the same spec or better is fine, and the BOM's notes say so.
- **Rotations** in the pick-and-place file follow KiCad's convention. PCBWay checks them against their own footprint library and asks if anything looks wrong. The assembly drawing shows each part's outline, and pin 1 where the footprint marks it.
- **J5 and J6** (JTAG and serial headers) can be left off and fitted by hand if that's cheaper.
- The board arrives unprogrammed. [`../SETUP.md`](../SETUP.md) covers programming and first power-up.

## Before ordering

The design has been simulated, synthesised and built in Vivado, and the board passes KiCad's design check. No board has been made yet. [`../SETUP.md`](../SETUP.md) and [`../VIVADO_TODO.md`](../VIVADO_TODO.md) list what to check on the first one, notably the USB-C monitor with the plug both ways up.

## Rebuilding these files

After any change to the board:

```bash
cd hardware_v3/tools && /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 make_fab.py
```
