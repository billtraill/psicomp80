"""Build the KiCad board for the PSI COMP 80 main board.

Run it with the Python that comes with KiCad (it needs the pcbnew module), e.g. on macOS:

  /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 make_kicad.py

Set KICAD_FOOTPRINTS if the standard footprint libraries are somewhere unusual.
Writes hardware/kicad/psicomp80.kicad_pcb and psicomp80.kicad_pro.

What is in the board: the 16 x 12 in outline, every part placed with a standard KiCad
footprint, the section lines and titles from the layout sheet (User.Drawings), and the
copper traced from the artwork photo as a guide on two user layers (Artwork.Red and
Artwork.Blue). There are no nets and no routed copper: the photo is far too coarse to
read the connections from.
"""
import glob, json, math, os, re, sys

import pcbnew

import board_data as bd
import geometry as g

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "..", "kicad")
MM = 25.4 / bd.PX_PER_IN          # mm per frame px
ORIGIN = (30.0, 30.0)             # where the board's top-left corner sits on the sheet (mm)


def find_libs():
    cands = [os.environ.get("KICAD_FOOTPRINTS", "")]
    for key, val in os.environ.items():
        if re.match(r"KICAD\d*_FOOTPRINT_DIR", key):
            cands.append(val)
    exe = os.path.realpath(sys.executable)
    m = re.search(r"^(.*?/KiCad\.app/Contents)/", exe)
    if m:
        cands.append(os.path.join(m.group(1), "SharedSupport", "footprints"))
    cands += ["/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints",
              "/usr/share/kicad/footprints", "/usr/local/share/kicad/footprints",
              r"C:\Program Files\KiCad\10.0\share\kicad\footprints"]
    for c in cands:
        if c and os.path.isdir(os.path.join(c, "Package_DIP.pretty")):
            return c
    sys.exit("Cannot find the KiCad footprint libraries; set KICAD_FOOTPRINTS")


LIBS = find_libs()


def pt(x, y):
    return pcbnew.VECTOR2I(pcbnew.FromMM(ORIGIN[0] + x * MM), pcbnew.FromMM(ORIGIN[1] + y * MM))


def nearest(lib, pattern, target_mm, key=r"_P([\d.]+)mm"):
    """Footprint in lib matching the glob pattern whose pitch is closest to target_mm."""
    names = [os.path.basename(p)[:-10] for p in glob.glob(os.path.join(LIBS, lib + ".pretty", pattern + ".kicad_mod"))]
    names = [n for n in names if "Vertical" not in n]
    return min(names, key=lambda n: abs(float(re.search(key, n).group(1)) - target_mm))


def load(lib, name):
    fp = pcbnew.FootprintLoad(os.path.join(LIBS, lib + ".pretty"), name)
    if fp is None:
        sys.exit(f"missing footprint {lib}:{name}")
    fp.SetFPID(pcbnew.LIB_ID(lib, name))
    return fp


def place(board, fp, ref, value, x, y, rot=0.0):
    """Put footprint fp with its origin (pad 1) at frame px (x, y), rotated rot degrees CCW."""
    fp.SetReference(ref)
    fp.SetValue(value)
    fp.SetPosition(pt(x, y))
    fp.SetOrientationDegrees(rot)
    board.Add(fp)
    return fp


def pad_pos(fp, num):
    for p in fp.Pads():
        if p.GetNumber() == str(num):
            v = p.GetPosition()
            return (pcbnew.ToMM(v.x) - ORIGIN[0]) / MM, (pcbnew.ToMM(v.y) - ORIGIN[1]) / MM


def add_ics(board):
    worst = 0.0
    for ic in bd.ics():
        n, w = ic["pins"], ic["width"]
        name = f"DIP-{n}_W{'15.24' if w > 0.45 else '7.62'}mm"
        pins = g.ic_pins(ic)
        _, x1, y1 = pins[0]
        fp = place(board, load("Package_DIP", name), ic["ref"], ic["value"], x1, y1, g.ic_placement(ic)[2])
        # the last pin must land where geometry.py says it does
        _, xn, yn = pins[-1]
        px, py = pad_pos(fp, n)
        worst = max(worst, math.hypot(px - xn, py - yn))
    assert worst < 0.5, f"DIP pin placement off by {worst:.2f} px"


def add_two_lead(board):
    for part in bd.TWO_LEAD:
        ref, val, kind, *_ = part
        (ax, ay), (bx, by) = g.two_lead_pads(part)
        dist = math.hypot(bx - ax, by - ay) * MM
        if kind == "R":
            lib, name = "Resistor_THT", nearest("Resistor_THT", "R_Axial_DIN0207_L6.3mm_D2.5mm_P*_Horizontal", dist)
        elif kind == "RW":
            lib, name = "Resistor_THT", nearest("Resistor_THT", "R_Axial_Power_L20.0mm_W6.4mm_P*", dist)
        elif kind == "C":
            lib, name = "Capacitor_THT", nearest("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P*", dist)
        elif val == "1N5402":
            lib, name = "Diode_THT", nearest("Diode_THT", "D_DO-201AD_P*_Horizontal", dist)
        else:
            lib, name = "Diode_THT", nearest("Diode_THT", "D_DO-41_SOD81_P*_Horizontal", dist)
        pitch = float(re.search(r"_P([\d.]+)mm", name).group(1)) / MM
        mx, my = (ax + bx) / 2, (ay + by) / 2
        ang = math.atan2(by - ay, bx - ax)
        place(board, load(lib, name), ref, val,
              mx - math.cos(ang) * pitch / 2, my - math.sin(ang) * pitch / 2, -math.degrees(ang))


ONE_POINT_FP = {
    "CP": ("Capacitor_THT", "CP_Radial_D5.0mm_P2.50mm", 2.5),
    "TO92": ("Package_TO_SOT_THT", "TO-92_Inline", 2.54),
    "LED": ("LED_THT", "LED_D5.0mm", 2.54),
    "VR": ("Potentiometer_THT", "Potentiometer_Bourns_3386P_Vertical", 5.08),
    "TO220": ("Package_TO_SOT_THT", "TO-220-3_Horizontal_TabDown", 5.08),
    "PIN": ("TestPoint", "TestPoint_THTPad_D2.0mm_Drill1.0mm", 0.0),
}


def add_one_point(board):
    for ref, val, kind, x, y in bd.ONE_POINT:
        lib, name, span = ONE_POINT_FP[kind]
        # centre the pad row on the drawn position
        place(board, load(lib, name), ref, val or ref, x - span / 2 / MM, y)


def add_boxes(board):
    for ref, val, x0, y0, x1, y1 in bd.BOXES:
        length, dia = (x1 - x0 - 20) * MM, (y1 - y0) * MM
        names = [os.path.basename(p)[:-10] for p in glob.glob(os.path.join(LIBS, "Capacitor_THT.pretty", "CP_Axial_L*_Horizontal.kicad_mod"))]

        def score(n):
            p = float(re.search(r"_P([\d.]+)mm", n).group(1))
            d = float(re.search(r"_D([\d.]+)mm", n).group(1))
            return abs(p - length) + 0.5 * abs(d - dia)
        name = min(names, key=score)
        pitch = float(re.search(r"_P([\d.]+)mm", name).group(1)) / MM
        place(board, load("Capacitor_THT", name), ref, val, (x0 + x1) / 2 - pitch / 2, (y0 + y1) / 2)


def add_expansion(board):
    e = bd.EXPANSION
    num, x, y = g.expansion_pins()[0]
    name = f"PinHeader_2x{e['pins_per_row']}_P2.54mm_Vertical"
    place(board, load("Connector_PinHeader_2.54mm", name), e["ref"], e["value"], x, y, 90)


def key_footprint(board, k):
    fp = pcbnew.FOOTPRINT(board)
    fp.SetFPID(pcbnew.LIB_ID("PSI_COMP80", "KeySwitch_2pad"))
    fp.SetAttributes(pcbnew.FP_THROUGH_HOLE)
    dx, dy = bd.KEY_DX * MM, bd.KEY_DY * MM
    for i, (px, py) in enumerate(((0.0, 0.0), (dx, dy))):
        pad = pcbnew.PAD(fp)
        pad.SetNumber(str(i + 1))
        pad.SetAttribute(pcbnew.PAD_ATTRIB_PTH)
        pad.SetShape(pcbnew.PAD_SHAPE_CIRCLE)
        pad.SetSize(pcbnew.VECTOR2I(pcbnew.FromMM(3.2), pcbnew.FromMM(3.2)))
        pad.SetDrillSize(pcbnew.VECTOR2I(pcbnew.FromMM(1.3), pcbnew.FromMM(1.3)))
        pad.SetLayerSet(pad.PTHMask())
        pad.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(px), pcbnew.FromMM(py)))
        fp.Add(pad)
    # keycap outline, relative to pad 1
    w, h = g.key_size(k)
    cx, cy = dx / 2, dy / 2
    rect = pcbnew.PCB_SHAPE(fp, pcbnew.SHAPE_T_RECT)
    rect.SetLayer(pcbnew.F_Fab)
    rect.SetStart(pcbnew.VECTOR2I(pcbnew.FromMM(cx - w * MM / 2), pcbnew.FromMM(cy - h * MM / 2)))
    rect.SetEnd(pcbnew.VECTOR2I(pcbnew.FromMM(cx + w * MM / 2), pcbnew.FromMM(cy + h * MM / 2)))
    rect.SetWidth(pcbnew.FromMM(0.15))
    fp.Add(rect)
    return fp


def add_keys(board):
    for k in bd.keys():
        fp = key_footprint(board, k)
        label = k["legend"] + (" " + k["shifted"] if k["shifted"] else "")
        place(board, fp, k["ref"], label, *k["pad1"])
        fp.Value().SetLayer(pcbnew.F_SilkS)
        fp.Value().SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(2.5 if len(k["legend"]) == 1 else 1.4),
                                               pcbnew.FromMM(2.5 if len(k["legend"]) == 1 else 1.4)))
        fp.Value().SetTextThickness(pcbnew.FromMM(0.35 if len(k["legend"]) == 1 else 0.2))
        cx, cy = g.key_centre(k)
        fp.Value().SetPosition(pt(cx, cy - 22))
        fp.Reference().SetPosition(pt(cx, cy + 20))


def add_holes(board):
    for i, (x, y) in enumerate(bd.HOLES):
        place(board, load("MountingHole", "MountingHole_3.2mm_M3"), f"H{i + 1}", "MountingHole", x, y)


def add_line(board, layer, a, b, width=0.25):
    s = pcbnew.PCB_SHAPE(board, pcbnew.SHAPE_T_SEGMENT)
    s.SetLayer(layer)
    s.SetStart(pt(*a))
    s.SetEnd(pt(*b))
    s.SetWidth(pcbnew.FromMM(width))
    board.Add(s)


def add_text(board, layer, s, x, y, size=2.5):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(s)
    t.SetLayer(layer)
    t.SetPosition(pt(x, y))
    t.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(size), pcbnew.FromMM(size)))
    t.SetTextThickness(pcbnew.FromMM(size * 0.12))
    board.Add(t)


def add_furniture(board):
    corners = [(0, 0), (bd.BOARD_W, 0), (bd.BOARD_W, bd.BOARD_H), (0, bd.BOARD_H)]
    for a, b in zip(corners, corners[1:] + corners[:1]):
        add_line(board, pcbnew.Edge_Cuts, a, b, 0.1)
    for line in bd.SECTION_LINES:
        for a, b in zip(line, line[1:]):
            add_line(board, pcbnew.Dwgs_User, a, b, 0.4)
    for s, x, y in bd.SECTION_TEXT:
        add_text(board, pcbnew.Dwgs_User, s, x, y, 3.0)
    for s, x, y in bd.SMALL_TEXT:
        add_text(board, pcbnew.Dwgs_User, s, x, y, 1.2)
    add_text(board, pcbnew.Dwgs_User, "PSI COMP 80 main board - placement redrawn from the Powertran kit sheets; "
             "Artwork.Red / Artwork.Blue layers are copper traced from a photo (approximate)", 1000, 1530, 2.5)


def add_artwork(board):
    traced = json.load(open(os.path.join(HERE, "artwork_traced.json")))
    for name, layer in (("red", pcbnew.User_1), ("blue", pcbnew.User_2)):
        for rings in traced[name]:
            poly = pcbnew.SHAPE_POLY_SET()
            outline = poly.NewOutline()
            for x, y in rings[0]:
                poly.Append(pt(x, y).x, pt(x, y).y, outline)
            for ring in rings[1:]:
                hole = poly.NewHole(outline)
                for x, y in ring:
                    poly.Append(pt(x, y).x, pt(x, y).y, outline, hole)
            s = pcbnew.PCB_SHAPE(board, pcbnew.SHAPE_T_POLY)
            s.SetLayer(layer)
            s.SetPolyShape(poly)
            s.SetFilled(True)
            s.SetWidth(0)
            board.Add(s)


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    board = pcbnew.BOARD()
    layers = board.GetEnabledLayers()
    layers.AddLayer(pcbnew.User_1)
    layers.AddLayer(pcbnew.User_2)
    board.SetEnabledLayers(layers)
    board.SetLayerName(pcbnew.User_1, "Artwork.Red")
    board.SetLayerName(pcbnew.User_2, "Artwork.Blue")
    tb = board.GetTitleBlock()
    tb.SetTitle("PSI COMP 80 main board")
    tb.SetCompany("Wireless World 1979 / Powertran kit - reconstruction")
    tb.SetComment(0, "Placement and traced artwork from photos of the kit sheets; no nets")

    add_artwork(board)
    add_furniture(board)
    add_ics(board)
    add_two_lead(board)
    add_one_point(board)
    add_boxes(board)
    add_expansion(board)
    add_keys(board)
    add_holes(board)

    pcb = os.path.join(OUTDIR, "psicomp80.kicad_pcb")
    board.Save(pcb)
    # project-local library holding the key switch footprint
    lib = os.path.join(OUTDIR, "PSI_COMP80.pretty")
    os.makedirs(lib, exist_ok=True)
    key = key_footprint(board, bd.keys()[1])
    key.SetReference("SW**")
    key.SetValue("KeySwitch_2pad")
    pcbnew.PCB_IO_KICAD_SEXPR().FootprintSave(lib, key)
    with open(os.path.join(OUTDIR, "fp-lib-table"), "w") as fh:
        fh.write('(fp_lib_table\n  (version 7)\n  (lib (name "PSI_COMP80")(type "KiCad")'
                 '(uri "${KIPRJMOD}/PSI_COMP80.pretty")(options "")(descr "PSI COMP 80 key switch"))\n)\n')

    pro = os.path.join(OUTDIR, "psicomp80.kicad_pro")
    if not os.path.exists(pro):
        json.dump({"meta": {"filename": "psicomp80.kicad_pro", "version": 1}}, open(pro, "w"), indent=2)
    print(pcb, len(board.GetFootprints()), "footprints")


if __name__ == "__main__":
    main()
