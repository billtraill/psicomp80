"""Build the COMP80 v2 KiCad board from design.py.

Run with KiCad's Python (it needs pcbnew):

  KICAD_PY make_board.py

Writes ../kicad/comp80v2.kicad_pcb: four layers (signals on the outside, a ground plane
on In1.Cu and 3.3 V on In2.Cu), every part on its footprint at its place in design.py,
with its nets, and the board outline. route.py then routes it.
"""
import math, os

import pcbnew

import design as d

HERE = os.path.dirname(os.path.abspath(__file__))
KICAD = os.path.join(HERE, "..", "kicad")
FPLIB = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
ORIGIN = (100.0, 100.0)          # board's top-left corner on the KiCad sheet, mm


def mm(v):
    return pcbnew.FromMM(v)


def pt(x, y):
    return pcbnew.VECTOR2I(mm(ORIGIN[0] + x), mm(ORIGIN[1] + y))


def load(fpid):
    lib, name = fpid.split(":")
    fp = pcbnew.FootprintLoad(os.path.join(FPLIB, lib + ".pretty"), name)
    assert fp, fpid
    fp.SetFPID(pcbnew.LIB_ID(lib, name))
    return fp


def courtyard(fp):
    """Bounding box of the footprint's front courtyard (falls back to its whole box)."""
    box = None
    for item in fp.GraphicalItems():
        if item.GetLayer() == pcbnew.F_CrtYd:
            b = item.GetBoundingBox()
            if box is None:
                box = b
            else:
                box.Merge(b)
    return box or fp.GetBoundingBox(False)


def mouth(fp):
    """Unit vector from the signal pads towards the far side of the body: the way a
    connector faces."""
    pads = [p.GetPosition() for p in fp.Pads() if p.GetNumber() not in ("", "SH")]
    px = sum(p.x for p in pads) / len(pads)
    py = sum(p.y for p in pads) / len(pads)
    c = courtyard(fp).GetCenter()
    dx, dy = c.x - px, c.y - py
    return (1 if dx > 0 else -1, 0) if abs(dx) > abs(dy) else (0, 1 if dy > 0 else -1)


EDGE_DIR = {"left": (-1, 0), "right": (1, 0), "top": (0, -1), "bottom": (0, 1)}
OVERHANG = {"J1": 0.8, "J2": 1.0, "J3": 2.0, "J4": 0.0}   # how far each connector's front passes the edge


def place_edge(fp, ref, x, y):
    """Turn an edge connector to face out of its edge and push it up to the edge."""
    edge = d.EDGE[ref]
    want = EDGE_DIR[edge]
    fp.SetPosition(pt(x, y))
    for rot in (0, 90, 180, 270):
        fp.SetOrientationDegrees(rot)
        if mouth(fp) == want:
            break
    else:
        raise SystemExit(f"{ref}: can't face {edge}")
    b = courtyard(fp)
    o = mm(OVERHANG[ref])
    p = fp.GetPosition()
    if edge == "top":
        p.y += pt(0, 0).y - o - b.GetTop()
    elif edge == "bottom":
        p.y += pt(0, d.BOARD_H).y + o - b.GetBottom()
    elif edge == "left":
        p.x += pt(0, 0).x - o - b.GetLeft()
    else:
        p.x += pt(d.BOARD_W, 0).x + o - b.GetRight()
    fp.SetPosition(p)


def pad_of(fp, num):
    for p in fp.Pads():
        if p.GetNumber() == str(num):
            return p
    raise KeyError(num)


def place_decoupling(board, u1, caps):
    """Put each capacitor beside the U1 pin it serves, pointing away from the chip with
    pad 1 (the supply) towards the pin. Caps on neighbouring pins are spread along the
    side so they don't overlap."""
    c = u1.GetPosition()
    sides = {}
    for ref, pin in caps.items():
        pad = pad_of(u1, pin).GetPosition()
        dx, dy = pad.x - c.x, pad.y - c.y
        if abs(dx) > abs(dy):
            u = ((1 if dx > 0 else -1), 0)
            along = pad.y
        else:
            u = (0, (1 if dy > 0 else -1))
            along = pad.x
        sides.setdefault(u, []).append([along, ref, pad])
    out = []
    gap = mm(1.9)
    for u, caps_ in sides.items():
        caps_.sort()
        for _ in range(20):                      # push apart until no two are closer than gap
            moved = False
            for a, b in zip(caps_, caps_[1:]):
                if b[0] - a[0] < gap:
                    push = (gap - (b[0] - a[0])) // 2 + 1
                    a[0] -= push
                    b[0] += push
                    moved = True
            if not moved:
                break
        for along, ref, pad in caps_:
            dist = mm(2.6)
            fp = load(d.PARTS[ref][1])
            if u[0]:
                fp.SetPosition(pcbnew.VECTOR2I(pad.x + u[0] * dist, along))
            else:
                fp.SetPosition(pcbnew.VECTOR2I(along, pad.y + u[1] * dist))
            # pads lie along x at rotation 0, pad 1 on the left
            fp.SetOrientationDegrees({(1, 0): 0, (-1, 0): 180, (0, 1): 270, (0, -1): 90}[u])
            out.append((ref, fp))
    return out


def track(board, net, a, b, width=0.25, layer=pcbnew.F_Cu):
    t = pcbnew.PCB_TRACK(board)
    t.SetStart(a)
    t.SetEnd(b)
    t.SetWidth(mm(width))
    t.SetLayer(layer)
    t.SetNet(net)
    t.SetLocked(True)
    board.Add(t)


def via(board, net, at, size=0.45, drill=0.2):
    v = pcbnew.PCB_VIA(board)
    v.SetPosition(at)
    v.SetWidth(mm(size))
    v.SetDrill(mm(drill))
    v.SetNet(net)
    v.SetLocked(True)
    board.Add(v)


def preroute_decoupling(board, u1, nets):
    """Short tracks from each U1 supply pin to its capacitor, a ground via beyond each
    capacitor, and a grid of ground vias in U1's exposed pad: the parts of the routing
    that are too tight to leave to the autorouter."""
    c = u1.GetPosition()
    done = set()
    for ref, pin in d.DECOUPLE.items():
        pad = pad_of(u1, pin)
        cap = board.FindFootprintByReference(ref)
        p1, p2 = pad_of(cap, 1), pad_of(cap, 2)
        a, b = pad.GetPosition(), p1.GetPosition()
        # leave the pin straight outward, then go to the capacitor
        out = pcbnew.VECTOR2I(a.x + (b.x - a.x if abs(a.x - c.x) > abs(a.y - c.y) else 0) // 2,
                              a.y + (b.y - a.y if abs(a.y - c.y) > abs(a.x - c.x) else 0) // 2)
        track(board, pad.GetNet(), a, out, 0.2)
        track(board, pad.GetNet(), out, b, 0.25)
        g = p2.GetPosition()
        dx, dy = g.x - b.x, g.y - b.y
        n = math.hypot(dx, dy)
        v = pcbnew.VECTOR2I(int(g.x + dx / n * mm(0.9)), int(g.y + dy / n * mm(0.9)))
        track(board, nets["GND"], g, v, 0.3)
        via(board, nets["GND"], v)
        done.add((ref, "2"))
    for i in (-1, 0, 1):
        for j in (-1, 0, 1):
            via(board, nets["GND"], pcbnew.VECTOR2I(c.x + i * mm(1.1), c.y + j * mm(1.1)), 0.5, 0.25)
    # U1's other ground pin (VREG_PGND) goes straight in past the pin row, then to the
    # exposed pad
    pad = pad_of(u1, d.RP2350A["VREG_PGND"])
    a = pad.GetPosition()
    if abs(a.x - c.x) > abs(a.y - c.y):
        inward = pcbnew.VECTOR2I(a.x - (1 if a.x > c.x else -1) * mm(1.2), a.y)
    else:
        inward = pcbnew.VECTOR2I(a.x, a.y - (1 if a.y > c.y else -1) * mm(1.2))
    tip = pcbnew.VECTOR2I(c.x + (1 if a.x > c.x else -1) * mm(1.3), c.y + (1 if a.y > c.y else -1) * mm(1.3))
    track(board, nets["GND"], a, inward, 0.2)
    track(board, nets["GND"], inward, tip, 0.25)
    # VREG_VIN joins the two 3.3 V pins along the same side (USB_OTP_VDD, QSPI_IOVDD)
    # inside the pin ring, so it needs no capacitor or via of its own at the pin
    pins = [pad_of(u1, d.RP2350A[n]) for n in ("VREG_VIN", "USB_OTP_VDD", "QSPI_IOVDD")]
    pts = []
    for p in pins:
        a = p.GetPosition()
        if abs(a.x - c.x) > abs(a.y - c.y):
            pts.append(pcbnew.VECTOR2I(a.x - (1 if a.x > c.x else -1) * mm(1.0), a.y))
        else:
            pts.append(pcbnew.VECTOR2I(a.x, a.y - (1 if a.y > c.y else -1) * mm(1.0)))
        track(board, nets["+3V3"], a, pts[-1], 0.2)
    for a, b in zip(pts, pts[1:]):
        track(board, nets["+3V3"], a, b, 0.2)
    # VREG_LX and VREG_FB straight out to the inductor
    l1 = board.FindFootprintByReference("L1")
    for name, lpad in (("VREG_LX", 1), ("VREG_FB", 2)):
        p = pad_of(u1, d.RP2350A[name])
        a, b = p.GetPosition(), pad_of(l1, lpad).GetPosition()
        bend = pcbnew.VECTOR2I(a.x, b.y - mm(1.0)) if abs(a.y - c.y) > abs(a.x - c.x) else pcbnew.VECTOR2I(b.x - mm(1.0), a.y)
        track(board, p.GetNet(), a, bend, 0.2)
        track(board, p.GetNet(), bend, b, 0.25)
    return done


def fanout(board, names, done=(), skip=("U1",), peg_clear=0):
    """A via beside every surface-mount pad on the plane nets, joined by a short track,
    placed clear of everything on other nets. The autorouter won't drop to the planes
    by itself."""
    clear = mm(0.2)
    vr = mm(0.225)
    edge = pcbnew.BOX2I(pt(0.6, 0.6), pcbnew.VECTOR2I(mm(d.BOARD_W - 1.2), mm(d.BOARD_H - 1.2)))
    obstacles = []                    # (box, net code)
    for fp in board.GetFootprints():
        for p in fp.Pads():
            box = p.GetBoundingBox()
            if peg_clear and p.GetAttribute() == pcbnew.PAD_ATTRIB_NPTH:
                box.Inflate(mm(peg_clear))    # kept clear by a rule area
            obstacles.append((box, p.GetNetCode()))
    for t in board.GetTracks():
        obstacles.append((t.GetBoundingBox(), t.GetNetCode()))

    def free(box, net):
        for b, n in obstacles:
            if n == net:
                continue
            bb = pcbnew.BOX2I(b.GetPosition(), b.GetSize())
            bb.Inflate(clear)
            if bb.Intersects(box):
                return False
        return edge.Contains(box)

    added = 0
    seen = set()
    for fp in board.GetFootprints():
        if fp.GetReference() in skip:
            continue
        centre = fp.GetPosition()
        for p in fp.Pads():
            name = p.GetNetname()
            if name not in names or p.GetAttribute() != pcbnew.PAD_ATTRIB_SMD:
                continue
            a = p.GetPosition()
            if (fp.GetReference(), p.GetNumber()) in done:
                continue                          # already taken to a via by preroute_decoupling
            key = (a.x, a.y, p.GetNetCode())
            if key in seen:
                continue                          # the USB-C footprint stacks A1 on B12, A12 on B1
            seen.add(key)
            size = p.GetBoundingBox().GetSize()
            reach = max(size.x, size.y) // 2 + mm(0.45)
            away = math.atan2(a.y - centre.y, a.x - centre.x) if a != centre else 0.0
            for k in range(16):
                ang = away + (k + 1) // 2 * (1 if k % 2 else -1) * math.pi / 8
                for extra in (0, mm(0.3), mm(0.6)):
                    v = pcbnew.VECTOR2I(int(a.x + math.cos(ang) * (reach + extra)), int(a.y + math.sin(ang) * (reach + extra)))
                    vbox = pcbnew.BOX2I(pcbnew.VECTOR2I(v.x - vr, v.y - vr), pcbnew.VECTOR2I(2 * vr, 2 * vr))
                    tw = mm(0.15)
                    path = []
                    for f in (0.35, 0.55, 0.75):       # the track, beyond the pad itself
                        m = pcbnew.VECTOR2I(int(a.x + (v.x - a.x) * f), int(a.y + (v.y - a.y) * f))
                        path.append(pcbnew.BOX2I(pcbnew.VECTOR2I(m.x - tw, m.y - tw), pcbnew.VECTOR2I(2 * tw, 2 * tw)))
                    if free(vbox, p.GetNetCode()) and all(free(b, p.GetNetCode()) for b in path):
                        break
                else:
                    continue
                break
            else:
                print("no room for a via beside", fp.GetReference(), p.GetNumber(), name)
                continue
            track(board, p.GetNet(), a, v, 0.3)
            via(board, p.GetNet(), v)
            obstacles.append((vbox, p.GetNetCode()))
            added += 1
    return added


def main():
    pcbnew.SETTINGS_MANAGER()     # loads KiCad's settings so footprints and rules behave
    os.makedirs(KICAD, exist_ok=True)
    board = pcbnew.NewBoard(os.path.join(KICAD, "comp80v2.kicad_pcb"))
    board.SetCopperLayerCount(4)
    board.SetLayerName(pcbnew.In1_Cu, "In1.Cu")
    board.SetLayerName(pcbnew.In2_Cu, "In2.Cu")
    for layer in (pcbnew.In1_Cu, pcbnew.In2_Cu):
        board.SetLayerType(layer, pcbnew.LT_POWER)     # planes only: the router keeps signals off them
    tb = board.GetTitleBlock()
    tb.SetTitle("PSI COMP 80 v2")
    tb.SetCompany("A current-parts COMP80: RP2350, HDMI, USB keyboard, microSD, USB-C power")
    tb.SetRevision("1")

    ds = board.GetDesignSettings()
    ds.m_TrackMinWidth = mm(0.09)
    ds.m_MinClearance = mm(0.12)
    ds.m_ViasMinSize = mm(0.45)
    ds.m_MinThroughDrill = mm(0.2)
    ds.m_CopperEdgeClearance = mm(0.3)
    ds.m_HoleClearance = mm(0.18)       # the USB-C footprint's own pegs sit 0.19 mm from its pads
    ns = ds.m_NetSettings
    dflt = ns.GetDefaultNetclass()
    dflt.SetTrackWidth(mm(0.15))
    dflt.SetClearance(mm(0.12))
    dflt.SetViaDiameter(mm(0.6))
    dflt.SetViaDrill(mm(0.3))
    power = pcbnew.NETCLASS("Power")
    power.SetTrackWidth(mm(0.3))
    power.SetClearance(mm(0.12))
    power.SetViaDiameter(mm(0.8))
    power.SetViaDrill(mm(0.4))
    ns.SetNetclass("Power", power)
    for n in d.POWER_NETS:
        ns.SetNetclassPatternAssignment(n, "Power")
    core = pcbnew.NETCLASS("Core")
    core.SetTrackWidth(mm(0.2))
    core.SetClearance(mm(0.12))
    core.SetViaDiameter(mm(0.6))
    core.SetViaDrill(mm(0.3))
    ns.SetNetclass("Core", core)
    for n in d.CORE_NETS:
        ns.SetNetclassPatternAssignment(n, "Core")

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

    u1 = None
    for ref, (value, fpid, mpn, desc) in d.PARTS.items():
        if ref in d.DECOUPLE:
            continue
        fp = load(fpid)
        x, y, rot = d.PLACE[ref]
        if ref in d.EDGE:
            place_edge(fp, ref, x, y)
        else:
            fp.SetPosition(pt(x, y))
            fp.SetOrientationDegrees(rot)
        add(fp, ref)
        if ref == "U1":
            u1 = fp
    for ref, fp in place_decoupling(board, u1, d.DECOUPLE):
        add(fp, ref)
    done = preroute_decoupling(board, u1, nets)
    print(fanout(board, ("GND", "+3V3"), done), "fanout vias")

    # small references, on the silkscreen beside each part
    for fp in board.GetFootprints():
        for t in (fp.Reference(), fp.Value()):
            t.SetTextSize(pcbnew.VECTOR2I(mm(0.8), mm(0.8)))
            t.SetTextThickness(mm(0.12))
        fp.Value().SetLayer(pcbnew.F_Fab)

    # outline, with 2 mm corner radii
    W, H, r = d.BOARD_W, d.BOARD_H, 2.0
    segs = [((r, 0), (W - r, 0)), ((W, r), (W, H - r)), ((W - r, H), (r, H)), ((0, H - r), (0, r))]
    for a, b in segs:
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

    # planes: ground on In1.Cu, 3.3 V on In2.Cu
    for layer, net in ((pcbnew.In1_Cu, "GND"), (pcbnew.In2_Cu, "+3V3")):
        z = pcbnew.ZONE(board)
        z.SetLayer(layer)
        z.SetNet(nets[net])
        z.SetLocalClearance(mm(0.15))
        z.SetMinThickness(mm(0.2))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
        ol = z.Outline()
        ol.NewOutline()
        for x, y in ((0.5, 0.5), (W - 0.5, 0.5), (W - 0.5, H - 0.5), (0.5, H - 0.5)):
            ol.Append(pt(x, y))
        board.Add(z)

    # a title on the silkscreen
    for text, x, y, size in (("PSI COMP 80 v2", 57.0, 45.5, 1.6), ("RP2350  HDMI  USB  microSD", 57.0, 48.0, 0.9)):
        t = pcbnew.PCB_TEXT(board)
        t.SetText(text)
        t.SetPosition(pt(x, y))
        t.SetLayer(pcbnew.F_SilkS)
        t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
        t.SetTextThickness(mm(size * 0.15))
        board.Add(t)

    pcb = os.path.join(KICAD, "comp80v2.kicad_pcb")
    board.Save(pcb)
    pro = os.path.join(KICAD, "comp80v2.kicad_pro")
    if not os.path.exists(pro):
        open(pro, "w").write('{"meta": {"filename": "comp80v2.kicad_pro", "version": 3}}\n')
    print(pcb, len(board.GetFootprints()), "footprints")


if __name__ == "__main__":
    main()
