"""Draw the routed KiCad board as artwork in the style of the kit's two-colour sheet.

  KICAD_PY export_routed_svg.py

Reads hardware/kicad/psicomp80.kicad_pcb (after route_board.py) and writes
hardware/psicomp80_pcb_routed.svg: component-side copper (F.Cu) in blue, solder-side
copper (B.Cu) in red, seen from the component side, with pads, vias, drill holes and the
keyboard legends on top. Needs KiCad's Python for pcbnew.
"""
import math, os

import pcbnew

import board_data as bd
import geometry as g
import make_drawings as md

HERE = os.path.dirname(os.path.abspath(__file__))
PCB = os.path.join(HERE, "..", "kicad", "psicomp80.kicad_pcb")
OUT = os.path.join(HERE, "..", "psicomp80_pcb_routed.svg")
ORIGIN = (30.0, 30.0)            # must match make_kicad.py
PX = bd.PX_PER_IN / 25.4         # frame px per mm
BLUE, RED, PAD, PAPER = "#4f93d0", "#cf4529", "#7a2414", "#fbf7ef"


def xy(v):
    return (pcbnew.ToMM(v.x) - ORIGIN[0]) * PX, (pcbnew.ToMM(v.y) - ORIGIN[1]) * PX


def f(v):
    return md.f(v)


def pad_shape(pad):
    x, y = xy(pad.GetPosition())
    sx, sy = pcbnew.ToMM(pad.GetSize(pcbnew.F_Cu).x) * PX, pcbnew.ToMM(pad.GetSize(pcbnew.F_Cu).y) * PX
    rot = -pad.GetOrientationDegrees()
    shape = pad.GetShape(pcbnew.F_Cu)
    if shape == pcbnew.PAD_SHAPE_CIRCLE:
        return f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(sx / 2)}"/>'
    rx = min(sx, sy) / 2 if shape == pcbnew.PAD_SHAPE_OVAL else (min(sx, sy) * 0.25 if shape == pcbnew.PAD_SHAPE_ROUNDRECT else 0)
    return (f'<rect x="{f(-sx / 2)}" y="{f(-sy / 2)}" width="{f(sx)}" height="{f(sy)}" rx="{f(rx)}" '
            f'transform="translate({f(x)} {f(y)}) rotate({f(rot)})"/>')


def main():
    board = pcbnew.LoadBoard(PCB)
    tracks = {pcbnew.F_Cu: [], pcbnew.B_Cu: []}
    vias, holes, pads = [], [], []
    for t in board.GetTracks():
        if t.GetClass() == "PCB_VIA":
            x, y = xy(t.GetPosition())
            vias.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(pcbnew.ToMM(t.GetWidth(pcbnew.F_Cu)) * PX / 2)}"/>')
            holes.append((x, y, pcbnew.ToMM(t.GetDrillValue()) * PX / 2))
        elif t.GetLayer() in tracks:
            (x1, y1), (x2, y2) = xy(t.GetStart()), xy(t.GetEnd())
            tracks[t.GetLayer()].append((round(pcbnew.ToMM(t.GetWidth()) * PX, 2), f"M{f(x1)},{f(y1)}L{f(x2)},{f(y2)}"))
    for fp in board.GetFootprints():
        for pad in fp.Pads():
            if not pad.IsOnCopperLayer():
                continue
            pads.append(pad_shape(pad))
            if pad.GetDrillSize().x:
                x, y = xy(pad.GetPosition())
                holes.append((x, y, pcbnew.ToMM(pad.GetDrillSize().x) * PX / 2))

    def track_layer(items, colour):
        by_width = {}
        for w, d in items:
            by_width.setdefault(w, []).append(d)
        return [f'<path d="{"".join(ds)}" fill="none" stroke="{colour}" stroke-width="{w:g}" '
                f'stroke-linecap="round" stroke-linejoin="round"/>' for w, ds in sorted(by_width.items())]

    n_f, n_b = len(tracks[pcbnew.F_Cu]), len(tracks[pcbnew.B_Cu])
    out = md.svg_open("PSI COMP 80 routed PCB",
                      "Main board routed from the netlist transcribed from the Wireless World circuit diagrams. "
                      "Seen from the component side: blue = component-side copper, red = solder-side copper.",
                      PAPER)
    out += md.layer("Blue copper - component side", track_layer(tracks[pcbnew.F_Cu], BLUE), ' opacity="0.9"')
    out += md.layer("Red copper - solder side", track_layer(tracks[pcbnew.B_Cu], RED), ' opacity="0.9"')
    out += md.layer("Pads and vias", [f'<g fill="{PAD}">'] + pads + vias + ["</g>"])
    out += md.layer("Drill holes", [f'<path d="{"".join(f"M{f(x - r)},{f(y)}a{f(r)},{f(r)} 0 1 0 {f(2 * r)},0a{f(r)},{f(r)} 0 1 0 {f(-2 * r)},0" for x, y, r in holes)}" fill="{PAPER}"/>'])

    ov = [f'<rect x="0" y="0" width="{bd.BOARD_W}" height="{bd.BOARD_H}" fill="none" stroke="{md.INK}" stroke-width="2"/>']
    for line in bd.SECTION_LINES:
        ov.append(f'<polyline points="{" ".join(f"{f(x)},{f(y)}" for x, y in line)}" fill="none" stroke="{md.INK}" stroke-width="1" opacity="0.35"/>')
    for s, x, y in bd.SECTION_TEXT:
        ov.append(md.text(x, y, s, 15, fill="#555"))
    for fp in board.GetFootprints():
        ref = fp.GetReference()
        if ref.startswith(("SW", "H", "J_")):
            continue
        x, y = xy(fp.GetBoundingBox(False).GetCenter())
        ov.append(md.text(x, y, ref, 7, fill="#333"))
    for k in bd.keys():
        cx, cy = g.key_centre(k)
        if k["legend"] == "uncommitted":
            continue
        if len(k["legend"]) > 1:
            ov.append(md.text(cx, cy + 2, k["legend"], 10, weight="bold"))
        else:
            if k["shifted"]:
                ov.append(md.text(cx, cy - 22, k["shifted"], 15, weight="bold"))
            ov.append(md.text(cx, cy + 2, k["legend"], 22, weight="bold"))
    out += md.layer("Legends and references", ov)
    md.caption(out, f"PSI COMP 80 main board - routed from the article circuit diagrams ({n_f} component-side and "
                    f"{n_b} solder-side segments, {len(vias)} vias)")
    out.append("</svg>")
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print(OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()
