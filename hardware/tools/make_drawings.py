"""Write the vector drawings of the PSI COMP 80 main board.

  python3 make_drawings.py

Produces, in hardware/:
  psicomp80_component_layout.svg   redrawn component layout sheet
  psicomp80_pcb_artwork.svg        the two copper layers traced from the photo, with
                                   the pads and keyboard legends redrawn on top
Uses only the standard library; reads board_data.py and artwork_traced.json.
"""
import json, math, os
from xml.sax.saxutils import escape

import board_data as bd
import geometry as g

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "..")
P = bd.PX_PER_IN
MARGIN = 60
INK = "#1a1a1a"
FONT = "font-family=\"'DejaVu Sans Mono', 'Courier New', monospace\""


def f(v):
    return f"{v:.1f}".rstrip("0").rstrip(".")


def text(x, y, s, size=10, anchor="middle", rot=0, weight="normal", fill=INK, extra=""):
    tr = f' transform="rotate({rot} {f(x)} {f(y)})"' if rot else ""
    return (f'<text x="{f(x)}" y="{f(y)}" font-size="{size}" text-anchor="{anchor}" '
            f'dominant-baseline="central" font-weight="{weight}" fill="{fill}"{tr}{extra}>{escape(s)}</text>')


def svg_open(title, desc, bg):
    w, h = bd.BOARD_W + 2 * MARGIN, bd.BOARD_H + 2 * MARGIN + 40
    return [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" '
        f'width="{w / P:.2f}in" height="{h / P:.2f}in" viewBox="{-MARGIN} {-MARGIN} {w} {h}" {FONT}>',
        f"<title>{escape(title)}</title>",
        f"<desc>{escape(desc)}</desc>",
        f'<rect x="{-MARGIN}" y="{-MARGIN}" width="{w}" height="{h}" fill="{bg}"/>',
    ]


def layer(name, body, extra=""):
    return [f'<g inkscape:groupmode="layer" inkscape:label="{escape(name)}" id="{name.split()[0].lower()}"{extra}>'] + body + ["</g>"]


def caption(lines, s):
    y = bd.BOARD_H + 34
    lines.append(text(0, y, s, 14, "start"))
    lines.append(text(bd.BOARD_W, y, "board 16 in x 12 in (crop marks)  -  1 in = 125 units", 12, "end"))


# --- shapes ---------------------------------------------------------------------------
def ic_outline(ic):
    (x0, y0, x1, y1), (nx, ny) = g.ic_body(ic)
    r = 0.045 * P
    side = ic["notch"]
    # walk the outline clockwise from just past the notch, finish with the notch arc
    if side == "L":
        pts, a, b = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], (x0, ny - r), (x0, ny + r)
    elif side == "R":
        pts, a, b = [(x1, y1), (x0, y1), (x0, y0), (x1, y0)], (x1, ny + r), (x1, ny - r)
    elif side == "T":
        pts, a, b = [(x1, y0), (x1, y1), (x0, y1), (x0, y0)], (nx + r, y0), (nx - r, y0)
    else:
        pts, a, b = [(x0, y1), (x0, y0), (x1, y0), (x1, y1)], (nx - r, y1), (nx + r, y1)
    d = f"M{f(a[0])},{f(a[1])} " + " ".join(f"L{f(x)},{f(y)}" for x, y in pts)
    d += f" L{f(b[0])},{f(b[1])} A{f(r)},{f(r)} 0 0 0 {f(a[0])},{f(a[1])} Z"
    return d


def ic_label(ic):
    (x0, y0, x1, y1), _ = g.ic_body(ic)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    vertical = ic["notch"] in "TB"
    role = bd.ROLE.get(ic["ref"])
    if ic["value"] == "21L02":
        s = ic["ref"] + ("  (OPTIONAL)" if ic["ref"] in ("IC43g", "IC44g") else "")
    else:
        s = f'{ic["ref"]}  {ic["value"]}' + (f"  ({role})" if role and ic["pins"] < 40 else "")
    size = 9 if ic["pins"] <= 16 else 11
    return text(cx, cy, s, size, rot=-90 if vertical else 0)


def two_lead_shape(part):
    ref, val, kind, x1, y1, x2, y2 = part
    ang = math.degrees(math.atan2(y2 - y1, x2 - x1))
    L = math.hypot(x2 - x1, y2 - y1)
    cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
    h = {"R": 11, "RW": 20, "C": 9, "D": 10}[kind]
    out = [f'<g transform="translate({f(cx)} {f(cy)}) rotate({f(ang)})">',
           f'<rect x="{f(-L / 2)}" y="{f(-h / 2)}" width="{f(L)}" height="{h}" fill="none" stroke="{INK}" stroke-width="1.6"/>']
    if kind == "D":
        out.append(f'<rect x="{f(L / 2 - 6)}" y="{f(-h / 2)}" width="5" height="{h}" fill="{INK}"/>')
    label = (ref if ref[1:].isdigit() and int(ref[1:]) < 101 else "") + ("  " + val if val != "?" else "")
    if label.strip():
        flip = 180 if 90 < ang % 360 <= 270 else 0
        out.append(text(0, 0, label.strip(), 6.5, rot=flip))
    out.append("</g>")
    return out


def one_point_shape(part):
    ref, val, kind, x, y = part
    named = not (ref[-3:].isdigit() and int("".join(c for c in ref if c.isdigit())) >= 101)
    o = []
    if kind == "CP":
        o.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="10" fill="none" stroke="{INK}" stroke-width="1.6"/>')
        o.append(f'<path d="M{f(x - 7)},{f(y + 7)} L{f(x + 7)},{f(y - 7)}" stroke="{INK}" stroke-width="1.2"/>')
        o.append(text(x + 15, y, "+", 9))
        if named:
            o.append(text(x, y + 18, f"{ref} {val}", 7))
    elif kind == "TO92":
        o.append(f'<path d="M{f(x - 12)},{f(y + 6)} A13,13 0 1 1 {f(x + 12)},{f(y + 6)} Z" fill="none" stroke="{INK}" stroke-width="1.6"/>')
        for dx in (-7, 0, 7):
            o.append(f'<circle cx="{f(x + dx)}" cy="{f(y)}" r="1.6" fill="{INK}"/>')
        o.append(text(x + 18, y - 8, ref, 7.5, "start"))
        o.append(text(x + 18, y + 2, val, 7.5, "start"))
    elif kind == "LED":
        o.append(f'<path d="M{f(x - 7)},{f(y - 6)} L{f(x + 7)},{f(y - 6)} L{f(x)},{f(y + 6)} Z" fill="{INK}"/>')
        o.append(f'<path d="M{f(x - 8)},{f(y + 7)} L{f(x + 8)},{f(y + 7)}" stroke="{INK}" stroke-width="1.6"/>')
        o.append(f'<path d="M{f(x + 10)},{f(y - 2)} l8,-6 M{f(x + 12)},{f(y + 4)} l8,-6" stroke="{INK}" stroke-width="1.2"/>')
        o.append(text(x - 12, y, f"{ref} {val}", 7, "end"))
    elif kind == "VR":
        o.append(f'<path d="M{f(x - 26)},{f(y + 10)} L{f(x - 26)},{f(y - 10)} L{f(x + 12)},{f(y - 10)} A14,10 0 0 1 {f(x + 12)},{f(y + 10)} Z" fill="none" stroke="{INK}" stroke-width="1.6"/>')
        o.append(text(x - 4, y, f"{ref} {val}", 7.5))
    elif kind == "TO220":
        o.append(f'<rect x="{f(x - 24)}" y="{f(y - 10)}" width="48" height="20" fill="none" stroke="{INK}" stroke-width="1.6"/>')
        o.append(f'<rect x="{f(x - 24)}" y="{f(y - 10)}" width="48" height="5" fill="{INK}"/>')
        o.append(text(x, y + 3, f"{ref} {val}" if val != "?" else ref, 6.5))
    elif kind == "PIN":
        o.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="3.5" fill="{INK}"/>')
        if val:
            o.append(text(x + 7, y, val, 7, "start"))
    return o


def keycap(k, legend_size=26):
    cx, cy = g.key_centre(k)
    w, h = g.key_size(k)
    o = [f'<rect x="{f(cx - w / 2)}" y="{f(cy - h / 2)}" width="{f(w)}" height="{f(h)}" fill="none" stroke="{INK}" stroke-width="1.6"/>']
    L = k["legend"]
    if L == "uncommitted":
        for i, s in enumerate(("UNCOMMITTED SWITCH", "(FOR FUTURE", "EXPANSION)")):
            o.append(text(cx - w / 2 + 4, cy - 12 + i * 11, s, 6.5, "start"))
    elif len(L) > 1:
        o.append(text(cx, cy, L, 12, weight="bold"))
    elif k["shifted"]:
        o.append(text(cx, cy - 15, k["shifted"], 18, weight="bold"))
        o.append(text(cx, cy + 12, L, legend_size, weight="bold"))
    else:
        o.append(text(cx, cy, L, legend_size, weight="bold"))
    return o


# --- component layout ------------------------------------------------------------------
def component_layout():
    out = svg_open("PSI COMP 80 component layout",
                   "Main board component layout, redrawn as vectors from a photo of the Powertran kit sheet.",
                   "#ffffff")
    body = [f'<rect x="0" y="0" width="{bd.BOARD_W}" height="{bd.BOARD_H}" fill="none" stroke="{INK}" stroke-width="3"/>']
    for line in bd.SECTION_LINES:
        body.append(f'<polyline points="{" ".join(f"{f(x)},{f(y)}" for x, y in line)}" fill="none" stroke="{INK}" stroke-width="3"/>')
    for s, x, y in bd.SECTION_TEXT:
        if s == "KEYBOARD ENCODER SECTION":
            for i, w in enumerate(("KEYBOARD", "ENCODER", "SECTION")):
                body.append(text(x, y - 22 + i * 22, w, 19, "middle"))
        elif s == "POWER SUPPLY SECTION":
            for i, w in enumerate(("POWER", "SUPPLY", "SECTION")):
                body.append(text(x - 30, y - 22 + i * 22, w, 17, "start"))
        else:
            body.append(text(x, y, s, 20))
    for s, x, y in bd.SMALL_TEXT:
        body.append(text(x, y, s, 8))
    out += layer("Outline and sections", body)

    body = []
    for ic in bd.ics():
        body.append(f'<path d="{ic_outline(ic)}" fill="none" stroke="{INK}" stroke-width="1.8"/>')
        body.append(ic_label(ic))
    e = bd.EXPANSION
    half = (e["pins_per_row"] / 2 + 0.5) * g.PITCH
    body.append(f'<rect x="{f(e["x"] - half)}" y="{f(e["y"] - 18)}" width="{f(2 * half)}" height="36" fill="none" stroke="{INK}" stroke-width="1.8"/>')
    body.append(text(e["x"], e["y"], "OPTIONAL EXPANSION PLUG", 9))
    out += layer("Integrated circuits", body)

    body = []
    for part in bd.TWO_LEAD:
        body += two_lead_shape(part)
    for part in bd.ONE_POINT:
        body += one_point_shape(part)
    for ref, val, x0, y0, x1, y1 in bd.BOXES:
        body.append(f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" fill="none" stroke="{INK}" stroke-width="1.8"/>')
        body.append(text((x0 + x1) / 2, (y0 + y1) / 2 + 10, f"{ref}   {val}", 10))
        body.append(text(x0 + 8, (y0 + y1) / 2 + 10, "+", 10))
    for x, y in bd.HOLES:
        body.append(f'<circle cx="{x}" cy="{y}" r="6" fill="none" stroke="{INK}" stroke-width="1.4"/>')
    out += layer("Discrete parts", body)

    body = []
    for k in bd.keys():
        body += keycap(k)
    out += layer("Keyboard", body)

    caption(out, "PSI COMP 80 (Wireless World 1979) - main board component layout, redrawn from the Powertran kit sheet")
    out.append("</svg>")
    return out


# --- PCB artwork ---------------------------------------------------------------------------
def poly_path(polys):
    parts = []
    for rings in polys:
        for ring in rings:
            parts.append("M" + " ".join(f"{x:g},{y:g}" for x, y in ring) + "Z")
    return "".join(parts)


def pcb_artwork():
    traced = json.load(open(os.path.join(HERE, "artwork_traced.json")))
    out = svg_open("PSI COMP 80 PCB artwork",
                   "Main board copper artwork. The red and blue layers are traced from a photo of the kit's "
                   "artwork sheet (approximate); pads, key legends and outline are redrawn from the placement data.",
                   "#fbf7ef")
    out += layer("Blue copper (traced)", [f'<path d="{poly_path(traced["blue"])}" fill="#5b9fd6" fill-rule="evenodd"/>'],
                 ' opacity="0.85"')
    out += layer("Red copper (traced)", [f'<path d="{poly_path(traced["red"])}" fill="#d1492c" fill-rule="evenodd"/>'],
                 ' opacity="0.9"')

    pads = []
    PAD = "#7a2414"
    for ic in bd.ics():
        horiz = ic["notch"] in "LR"
        for num, x, y in g.ic_pins(ic):
            w, h = (8, 13) if horiz else (13, 8)
            shape = "rect" if num == 1 else "ellipse"
            if shape == "rect":
                pads.append(f'<rect x="{f(x - w / 2)}" y="{f(y - h / 2)}" width="{w}" height="{h}" fill="{PAD}"/>')
            else:
                pads.append(f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{w / 2}" ry="{h / 2}" fill="{PAD}"/>')
    for num, x, y in g.expansion_pins():
        pads.append(f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="4" ry="6" fill="{PAD}"/>')
    for part in bd.TWO_LEAD:
        for x, y in g.two_lead_pads(part):
            pads.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="5.5" fill="{PAD}"/>')
    for ref, val, kind, x, y in bd.ONE_POINT:
        if kind == "TO92":
            pts = [(x - 7, y), (x, y), (x + 7, y)]
        elif kind == "TO220":
            pts = [(x - 12, y), (x, y), (x + 12, y)]
        elif kind in ("CP", "LED"):
            pts = [(x - 5, y), (x + 5, y)]
        elif kind == "VR":
            pts = [(x - 12, y + 6), (x, y - 8), (x + 12, y + 6)]
        else:
            pts = [(x, y)]
        for px, py in pts:
            pads.append(f'<circle cx="{f(px)}" cy="{f(py)}" r="5" fill="{PAD}"/>')
    for ref, val, x0, y0, x1, y1 in bd.BOXES:
        for px in (x0 + 10, x1 - 10):
            pads.append(f'<circle cx="{f(px)}" cy="{f((y0 + y1) / 2)}" r="8" fill="{PAD}"/>')
    for k in bd.keys():
        for x, y in (k["pad1"], k["pad2"]):
            pads.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="12.5" fill="{PAD}"/>')
    for x, y in bd.HOLES:
        pads.append(f'<circle cx="{x}" cy="{y}" r="7" fill="{PAD}"/>')
    out += layer("Pads (redrawn)", pads)

    # drill holes: one white dot per pad centre
    holes = []
    for ic in bd.ics():
        for _, x, y in g.ic_pins(ic):
            holes.append(f"M{f(x - 1.6)},{f(y)}a1.6,1.6 0 1 0 3.2,0a1.6,1.6 0 1 0 -3.2,0")
    for k in bd.keys():
        for x, y in (k["pad1"], k["pad2"]):
            holes.append(f"M{f(x - 2.5)},{f(y)}a2.5,2.5 0 1 0 5,0a2.5,2.5 0 1 0 -5,0")
    out += layer("Drill holes", [f'<path d="{"".join(holes)}" fill="#fbf7ef"/>'])

    ov = []
    for (x, y), (dx, dy) in (((0, 0), (1, 1)), ((2000, 0), (-1, 1)), ((2000, 1500), (-1, -1)), ((0, 1500), (1, -1))):
        ov.append(f'<path d="M{x + 30 * dx},{y} L{x},{y} L{x},{y + 30 * dy}" fill="none" stroke="{INK}" stroke-width="5"/>')
    for line in bd.SECTION_LINES:
        ov.append(f'<polyline points="{" ".join(f"{f(x)},{f(y)}" for x, y in line)}" fill="none" stroke="{INK}" stroke-width="1.2" opacity="0.6"/>')
    for s, x, y in bd.SECTION_TEXT:
        ov.append(text(x, y, s, 15, fill="#444"))
    for k in bd.keys():
        cx, cy = g.key_centre(k)
        L = k["legend"]
        if L == "uncommitted":
            continue
        if len(L) > 1:
            ov.append(text(cx, cy + 2, L, 10, weight="bold"))
        else:
            if k["shifted"]:
                ov.append(text(cx, cy - 22, k["shifted"], 15, weight="bold"))
            ov.append(text(cx, cy + 2, L, 22, weight="bold"))
    ov.append(text(1525, 1325, "COMPONENT SIDE", 9, fill="#444"))
    out += layer("Legends and crop marks", ov)

    caption(out, "PSI COMP 80 (Wireless World 1979) - main board artwork; copper traced from a photo, approximate")
    out.append("</svg>")
    return out


if __name__ == "__main__":
    for name, fn in (("psicomp80_component_layout.svg", component_layout), ("psicomp80_pcb_artwork.svg", pcb_artwork)):
        path = os.path.join(OUTDIR, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(fn()) + "\n")
        print(path, os.path.getsize(path), "bytes")
