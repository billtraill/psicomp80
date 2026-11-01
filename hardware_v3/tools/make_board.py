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
        if ring_out and p.GetNetname() not in PLANE_NETS:
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
    print(v2.fanout(board, PLANE_NETS), "fanout vias")

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

    for text, x, y, size in (("PSI COMP 80 v3", 20.0, 30.0, 1.8), ("ARTIX-7  HDMI  USB  microSD", 20.0, 33.0, 0.9)):
        t = pcbnew.PCB_TEXT(board)
        t.SetText(text)
        t.SetPosition(pt(x, y))
        t.SetLayer(pcbnew.F_SilkS)
        t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
        t.SetTextThickness(mm(size * 0.15))
        board.Add(t)

    board.Save(pcb)
    pro = os.path.join(KICAD, "comp80v3.kicad_pro")
    if not os.path.exists(pro):
        open(pro, "w").write('{"meta": {"filename": "comp80v3.kicad_pro", "version": 3}}\n')
    print(pcb, len(board.GetFootprints()), "footprints")


if __name__ == "__main__":
    main()
