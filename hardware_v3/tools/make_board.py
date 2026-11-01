"""Build the COMP80 v3 KiCad board from design.py.

Run with KiCad's Python (it needs pcbnew):

  KICAD_PY make_board.py

Writes ../kicad/comp80v3.kicad_pcb: six layers (signals outside; ground, 3.3 V,
1.0 V and 1.8 V planes inside), every part at its place in design.py with its
nets, and the BGA broken out: each FPGA ball that goes to a plane, or isn't on
the outer two rows, gets a via in the gap beside it. Then
../../hardware/tools/route_board.py routes it. The footprint and fanout helpers
are the v2 board's (../../hardware_v2/tools/make_board.py).
"""
import importlib.util, math, os

import pcbnew

import design as d

HERE = os.path.dirname(os.path.abspath(__file__))
KICAD = os.path.join(HERE, "..", "kicad")
spec = importlib.util.spec_from_file_location("v2board", os.path.join(HERE, "..", "..", "hardware_v2", "tools", "make_board.py"))
v2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)
v2.d = d                       # the v2 helpers read the board's size and edges from here
mm, pt, load, track, via = v2.mm, v2.pt, v2.load, v2.track, v2.via
v2.OVERHANG["J7"] = 0.58                # the video USB-C, like the power one
v2.OVERHANG["J3"] = 4.2                 # the flat USB-A: its shell's front, past the edge mark

PLANE_NETS = tuple(net for _, net in d.PLANES)
LAYER = {"In1.Cu": pcbnew.In1_Cu, "In2.Cu": pcbnew.In2_Cu, "In3.Cu": pcbnew.In3_Cu, "In4.Cu": pcbnew.In4_Cu}


def breakout(board, u1):
    """A dog-bone via half a pitch diagonally from every ball that needs one. All in
    the same direction, so no two vias can meet; the outer two rows' signals leave on
    the top layer instead."""
    c = u1.GetPosition()
    n = 0
    for p in u1.Pads():
        if not p.GetNetCode():
            continue
        a = p.GetPosition()
        ring_out = max(abs(a.x - c.x), abs(a.y - c.y)) >= mm(9.4)
        if ring_out and p.GetNetname() not in PLANE_NETS + tuple(n for _, n, _ in d.ISLANDS):
            continue
        v = pcbnew.VECTOR2I(a.x + mm(0.5), a.y + mm(0.5))
        track(board, p.GetNet(), a, v, 0.15)
        via(board, p.GetNet(), v, 0.45, 0.2)
        n += 1
    return n


def place_decoupling(board):
    """The 0.47 uF capacitors in a ring just outside the FPGA's body, the 4.7 uF ones
    in a row below it. Each joins its plane through the fanout vias."""
    cx, cy = d.FPGA_AT
    small = [c for c in d.DECOUPLE if c[2] == "470n"]
    mid = [c for c in d.DECOUPLE if c[2] != "470n"]
    spots = []
    for k in range(6):
        spots.append((cx - 8.0 + k * 3.2, cy - 13.8, 90))       # above
        spots.append((cx - 8.0 + k * 3.2, cy + 13.8, 90))       # below
    for k in range(5):
        spots.append((cx - 13.8, cy - 7.0 + k * 3.5, 0))        # left
        spots.append((cx + 13.8, cy - 7.0 + k * 3.5, 0))        # right
    out = []
    for (ref, net, value), (x, y, r) in zip(small, spots):
        fp = load(d.PARTS[ref][1])
        fp.SetPosition(pt(x, y))
        fp.SetOrientationDegrees(r)
        out.append((ref, fp))
    for k, (ref, net, value) in enumerate(mid):
        fp = load(d.PARTS[ref][1])
        fp.SetPosition(pt(cx - 12.0 + k * 4.0, cy + 16.4))
        fp.SetOrientationDegrees(90)
        out.append((ref, fp))
    return out


def logo(board):
    """The kit leaflet's "PSI COMP 80" screen on the silkscreen, dot for dot: each
    character cell's 6 x 10 dots from the COMP80's own font (../rtl/font.hex),
    every run of lit dots along a row one filled rectangle."""
    screen = [int(v, 16) for v in open(os.path.join(HERE, "..", "pictures", "cover_screen.hex"))]
    font = [int(v, 16) for v in open(os.path.join(HERE, "..", "rtl", "font.hex"))]
    used = [i for i, v in enumerate(screen) if v not in (0x20, 0x40)]
    r0, r1 = min(i // 64 for i in used), max(i // 64 for i in used)
    c0, c1 = min(i % 64 for i in used), max(i % 64 for i in used)
    x0, y0 = d.LOGO_AT
    dot = d.LOGO_DOT
    n = 0
    for row in range(r0, r1 + 1):
        for line in range(10):
            bits = []
            for col in range(c0, c1 + 1):
                v = screen[row * 64 + col]
                f = font[((v >> 6) & 1) << 10 | (v & 0x3f) << 4 | line]
                bits += [bool(f & (0x20 >> k)) for k in range(6)]
            y = y0 + ((row - r0) * 10 + line) * dot
            k = 0
            while k < len(bits):
                if not bits[k]:
                    k += 1
                    continue
                e = k
                while e < len(bits) and bits[e]:
                    e += 1
                r = pcbnew.PCB_SHAPE(board)
                r.SetShape(pcbnew.SHAPE_T_RECT)
                r.SetStart(pt(x0 + k * dot, y))
                r.SetEnd(pt(x0 + e * dot, y + dot))
                r.SetFilled(True)
                r.SetWidth(0)
                r.SetLayer(pcbnew.F_SilkS)
                board.Add(r)
                n += 1
                k = e
    print(n, "silkscreen rectangles in the logo")


def main():
    pcbnew.SETTINGS_MANAGER()
    os.makedirs(KICAD, exist_ok=True)
    pcb = os.path.join(KICAD, "comp80v3.kicad_pcb")
    board = pcbnew.NewBoard(pcb)
    board.SetCopperLayerCount(6)
    for name, layer in LAYER.items():
        board.SetLayerName(layer, name)
        board.SetLayerType(layer, pcbnew.LT_POWER)
    tb = board.GetTitleBlock()
    tb.SetTitle("PSI COMP 80 v3")
    tb.SetCompany("The COMP80 in an Artix-7 XC7A100T: HDMI, USB keyboard, microSD, USB-C power")
    tb.SetRevision("1")

    ds = board.GetDesignSettings()
    ds.SetAuxOrigin(pt(0, d.BOARD_H))   # the fab files' origin: the bottom-left corner
    ds.m_TrackMinWidth = mm(0.09)
    ds.m_MinClearance = mm(0.12)
    ds.m_ViasMinSize = mm(0.45)
    ds.m_MinThroughDrill = mm(0.2)
    ds.m_CopperEdgeClearance = mm(0.3)
    ds.m_HoleClearance = mm(0.18)
    ns = ds.m_NetSettings
    dflt = ns.GetDefaultNetclass()
    dflt.SetTrackWidth(mm(0.15))
    dflt.SetClearance(mm(0.12))
    dflt.SetViaDiameter(mm(0.6))
    dflt.SetViaDrill(mm(0.3))
    power = pcbnew.NETCLASS("Power")
    power.SetTrackWidth(mm(0.4))
    power.SetClearance(mm(0.15))
    power.SetViaDiameter(mm(0.8))
    power.SetViaDrill(mm(0.4))
    ns.SetNetclass("Power", power)
    for n in d.POWER_NETS:
        ns.SetNetclassPatternAssignment(n, "Power")
    small = pcbnew.NETCLASS("SmallPower")
    small.SetTrackWidth(mm(0.25))
    small.SetClearance(mm(0.12))
    small.SetViaDiameter(mm(0.6))
    small.SetViaDrill(mm(0.3))
    ns.SetNetclass("SmallPower", small)
    for n in d.SMALL_POWER_NETS:
        ns.SetNetclassPatternAssignment(n, "SmallPower")
    hdmi = pcbnew.NETCLASS("HDMI")
    hdmi.SetTrackWidth(mm(0.2))
    hdmi.SetClearance(mm(0.15))
    hdmi.SetViaDiameter(mm(0.6))
    hdmi.SetViaDrill(mm(0.3))
    ns.SetNetclass("HDMI", hdmi)
    ns.SetNetclassPatternAssignment("TMDS_*", "HDMI")

    nets = {}
    for name in d.NETS:
        ni = pcbnew.NETINFO_ITEM(board, name)
        board.Add(ni)
        nets[name] = ni
    pins = d.pins_of()

    def add(fp, ref):
        value, fpid, mpn, desc = d.PARTS[ref]
        fp.SetReference(ref)
        fp.SetValue(value)
        board.Add(fp)
        for pad in fp.Pads():
            n = pins.get(ref, {}).get(pad.GetNumber())
            if n:
                pad.SetNet(nets[n])
        return fp

    decouple = {c[0] for c in d.DECOUPLE}
    u1 = None
    for ref, (value, fpid, mpn, desc) in d.PARTS.items():
        if ref in decouple:
            continue
        fp = load(fpid)
        x, y, rot = d.PLACE[ref]
        if ref in d.EDGE:
            v2.place_edge(fp, ref, x, y)
        else:
            fp.SetPosition(pt(x, y))
            fp.SetOrientationDegrees(rot)
        add(fp, ref)
        if ref == "U1":
            u1 = fp
    for ref, fp in place_decoupling(board):
        add(fp, ref)
    print(breakout(board, u1), "FPGA breakout vias")
    done = set()
    # the ferrite bead straddles the 1.0 V island's edge: a via on each side
    fb = board.FindFootprintByReference("FB1")
    for num in ("1", "2"):
        p = v2.pad_of(fb, num)
        a = p.GetPosition()
        v = pcbnew.VECTOR2I(a.x, a.y + (mm(1.1) if a.y > fb.GetPosition().y else -mm(1.1)))
        track(board, p.GetNet(), a, v, 0.3)
        via(board, p.GetNet(), v)
        done.add(("FB1", num))
    # the video USB-C's four VBUS pads, joined across its two rows
    j7 = board.FindFootprintByReference("J7")
    for a, b in (("A4", "B9"), ("A9", "B4")):
        pa, pb = v2.pad_of(j7, a), v2.pad_of(j7, b)
        track(board, pa.GetNet(), pa.GetPosition(), pb.GetPosition(), 0.25)
    # The B row, nearer the edge, is boxed in by the A row: its signals drop to
    # vias on the edge side, staggered at 0.5 mm pitch. SBU1 and CC1, in the
    # middle of the A row, drop to vias below it so the pairs beside them can
    # run straight down to their capacitors.
    for num, dy in (("B2", -1.1), ("B3", -1.9), ("B5", -1.1), ("B8", -1.1), ("B10", -1.1), ("B11", -1.9),
                    ("A8", 1.1), ("A5", 1.1)):
        p = v2.pad_of(j7, num)
        a = p.GetPosition()
        v = pcbnew.VECTOR2I(a.x, a.y + mm(dy))
        track(board, p.GetNet(), a, v, 0.15)
        via(board, p.GetNet(), v)
    # HDMI's ground pins sit between the TMDS pairs at 0.5 mm pitch, with no room
    # for vias. A comb on the edge side joins them to each other, to the shell and
    # through vias to the ground plane, so the pairs have the inner side to themselves.
    j2 = board.FindFootprintByReference("J2")
    gnd = [p for p in j2.Pads() if p.GetNetname() == "GND" and p.GetAttribute() == pcbnew.PAD_ATTRIB_SMD]
    shell = sorted((p for p in j2.Pads() if p.GetNumber() == "SH"), key=lambda p: p.GetPosition().y)[2:]
    bar_y = gnd[0].GetBoundingBox().GetTop() - mm(0.65)
    x0, x1 = min(p.GetPosition().x for p in shell), max(p.GetPosition().x for p in shell)
    net = gnd[0].GetNet()
    track(board, net, pcbnew.VECTOR2I(x0, bar_y), pcbnew.VECTOR2I(x1, bar_y), 0.3)
    for p in shell:
        track(board, net, pcbnew.VECTOR2I(p.GetPosition().x, bar_y), p.GetPosition(), 0.3)
    for p in gnd:
        a = p.GetPosition()
        top = pcbnew.VECTOR2I(a.x, bar_y)
        track(board, net, a, top, 0.2)
        via(board, net, top)
        done.add(("J2", p.GetNumber()))
    # and each TMDS pin drops to a via just below the row, staggered so that the
    # two pins between each pair of ground pins both get out
    for num, dy in (("1", 0.6), ("3", 0.6), ("4", 1.4), ("6", 0.6), ("7", 1.4), ("9", 0.6), ("10", 1.4), ("12", 0.6)):
        p = v2.pad_of(j2, num)
        a = p.GetPosition()
        v = pcbnew.VECTOR2I(a.x, p.GetBoundingBox().GetBottom() + mm(dy))
        track(board, p.GetNet(), a, v, 0.15)
        via(board, p.GetNet(), v)
    # Two signal balls in the second ring are walled in by their neighbours: HDMI's
    # D2+ (B15, behind D1+) and the FUSB302's SCL (C2, beside the 2.5 V via on C1).
    # Each gets a dog-bone via of its own.
    for ball in ("B15", "C2"):
        p = v2.pad_of(u1, ball)
        a = p.GetPosition()
        v = pcbnew.VECTOR2I(a.x + mm(0.5), a.y + mm(0.5))
        track(board, p.GetNet(), a, v, 0.15)
        via(board, p.GetNet(), v, 0.45, 0.2)
    # the FUSB302 senses VBUS on pin 2, between CC2 and its supply: a via just
    # outside it, before the I2C lines to the pull-ups close it in
    p = v2.pad_of(board.FindFootprintByReference("U6"), 2)
    a = p.GetPosition()
    v = pcbnew.VECTOR2I(a.x - mm(0.9), a.y)
    track(board, p.GetNet(), a, v, 0.15)
    via(board, p.GetNet(), v)
    # the FUSB302's exposed pad gets its ground via in the pad: there's no room beside it
    ep = v2.pad_of(board.FindFootprintByReference("U6"), 15)
    via(board, ep.GetNet(), ep.GetPosition(), 0.45, 0.2)
    # keep tracks and vias away from the connectors' plastic pegs, which the router can't see
    for fp in board.GetFootprints():
        for p in fp.Pads():
            if p.GetAttribute() == pcbnew.PAD_ATTRIB_NPTH:
                z = pcbnew.ZONE(board)
                z.SetIsRuleArea(True)
                z.SetDoNotAllowTracks(True)
                z.SetDoNotAllowVias(True)
                z.SetDoNotAllowPads(False)
                z.SetDoNotAllowFootprints(False)
                z.SetDoNotAllowZoneFills(False)
                z.SetLayerSet(pcbnew.LSET.AllCuMask())
                c, r = p.GetPosition(), max(p.GetDrillSize().x, p.GetDrillSize().y) // 2 + mm(0.3)
                ol = z.Outline()
                ol.NewOutline()
                for k in range(16):
                    a = 2 * math.pi * k / 16
                    ol.Append(pcbnew.VECTOR2I(int(c.x + r * math.cos(a)), int(c.y + r * math.sin(a))))
                board.Add(z)
    # an island only helps the pads above it: the rest of its net's pads are routed
    def inside(x, y, poly):
        n = False
        for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
            if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                n = not n
        return n
    for fp in board.GetFootprints():
        for p in fp.Pads():
            for _, net, poly in d.ISLANDS:
                a = p.GetPosition()
                if p.GetNetname() == net and not inside(a.x / 1e6 - v2.ORIGIN[0], a.y / 1e6 - v2.ORIGIN[1], list(poly)):
                    done.add((fp.GetReference(), p.GetNumber()))
    print(v2.fanout(board, PLANE_NETS + tuple(n for _, n, _ in d.ISLANDS), done, peg_clear=0.35), "fanout vias")

    for fp in board.GetFootprints():
        for t in (fp.Reference(), fp.Value()):
            t.SetTextSize(pcbnew.VECTOR2I(mm(0.8), mm(0.8)))
            t.SetTextThickness(mm(0.12))
        fp.Value().SetLayer(pcbnew.F_Fab)

    W, H, r = d.BOARD_W, d.BOARD_H, 2.0
    for a, b in (((r, 0), (W - r, 0)), ((W, r), (W, H - r)), ((W - r, H), (r, H)), ((0, H - r), (0, r))):
        s = pcbnew.PCB_SHAPE(board)
        s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(pt(*a))
        s.SetEnd(pt(*b))
        s.SetLayer(pcbnew.Edge_Cuts)
        s.SetWidth(mm(0.1))
        board.Add(s)
    for cx, cy, a0 in ((r, r, 180), (W - r, r, 270), (W - r, H - r, 0), (r, H - r, 90)):
        s = pcbnew.PCB_SHAPE(board)
        s.SetShape(pcbnew.SHAPE_T_ARC)
        s.SetCenter(pt(cx, cy))
        s.SetStart(pt(cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0))))
        s.SetArcAngleAndEnd(pcbnew.EDA_ANGLE(90, pcbnew.DEGREES_T))
        s.SetLayer(pcbnew.Edge_Cuts)
        s.SetWidth(mm(0.1))
        board.Add(s)

    for layer, net, poly in d.ISLANDS:
        z = pcbnew.ZONE(board)
        z.SetLayer(LAYER[layer])
        z.SetNet(nets[net])
        z.SetAssignedPriority(1)        # over the plane it sits in
        z.SetLocalClearance(mm(0.15))
        z.SetMinThickness(mm(0.15))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
        ol = z.Outline()
        ol.NewOutline()
        for x, y in poly:
            ol.Append(pt(x, y))
        board.Add(z)
    for layer, net in d.PLANES:
        z = pcbnew.ZONE(board)
        z.SetLayer(LAYER[layer])
        z.SetNet(nets[net])
        z.SetLocalClearance(mm(0.15))
        z.SetMinThickness(mm(0.15))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
        ol = z.Outline()
        ol.NewOutline()
        for x, y in ((0.5, 0.5), (W - 0.5, 0.5), (W - 0.5, H - 0.5), (0.5, H - 0.5)):
            ol.Append(pt(x, y))
        board.Add(z)

    logo(board)
    x, y = d.TITLE_AT
    for text, size in d.TITLE:
        t = pcbnew.PCB_TEXT(board)
        t.SetText(text)
        t.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_LEFT)
        t.SetPosition(pt(x, y + size / 2))
        t.SetLayer(pcbnew.F_SilkS)
        t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
        t.SetTextThickness(mm(max(0.15, size * 0.15)))
        board.Add(t)
        y += size * 1.7

    board.Save(pcb)
    pro = os.path.join(KICAD, "comp80v3.kicad_pro")
    if not os.path.exists(pro):
        open(pro, "w").write('{"meta": {"filename": "comp80v3.kicad_pro", "version": 3}}\n')
    # The USB-C socket's own shell pads sit 0.298 mm from its pegs' holes,
    # just inside the board-wide 0.3 mm; that's the maker's land pattern.
    open(os.path.join(KICAD, "comp80v3.kicad_dru"), "w").write(
        '(version 1)\n'
        '(rule "USB-C shell pads by the pegs"\n'
        '  (constraint edge_clearance (min 0.25mm))\n'
        '  (condition "A.memberOfFootprint(\'J7\')"))\n')
    print(pcb, len(board.GetFootprints()), "footprints")


if __name__ == "__main__":
    main()
