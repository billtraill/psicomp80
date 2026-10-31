"""Build the KiCad board for the PSI COMP 80 main board.

Run it with the Python that comes with KiCad (it needs the pcbnew module), e.g. on macOS:

  /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 make_kicad.py

Set KICAD_FOOTPRINTS if the standard footprint libraries are somewhere unusual.
Writes hardware/kicad/psicomp80.kicad_pcb and psicomp80.kicad_pro.

What is in the board: the 16 x 12 in outline; every IC and key at its kit position; the
nets from netlist/psicomp80_netlist.json (transcribed from the Wireless World circuit
diagrams; run merge_netlist.py first); the circuit's discrete parts, at the kit position
when the kit sheet shows the same reference, otherwise in the nearest free spot to the
pins they connect to; the section lines and titles from the layout sheet (User.Drawings);
and the copper traced from the artwork photo, as a guide, on Artwork.Red.Bottom (solder
side) and Artwork.Blue.Top (component side). route_board.py then routes it.
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


# --- nets ------------------------------------------------------------------------------
NETLIST = os.path.join(HERE, "netlist", "psicomp80_netlist.json")
POWER_NETS = ("GND", "+5V", "-5V", "+12V", "-12V", "-4_5V", "VUNREG_*", "PSU_*")


class Nets:
    def __init__(self, board):
        self.board, self.items = board, {}

    def get(self, name):
        if name not in self.items:
            ni = pcbnew.NETINFO_ITEM(self.board, name)
            self.board.Add(ni)
            self.items[name] = ni
        return self.items[name]

    def assign(self, fp, pins, padmap=None):
        """Give each pad the net of its pin; padmap maps pad number -> pin name."""
        for pad in fp.Pads():
            num = pad.GetNumber()
            net = pins.get(padmap.get(num, num) if padmap else num)
            if net and net != "NC":
                pad.SetNet(self.get(net))


def is_power(net):
    return any(re.fullmatch(p.replace("*", ".*").replace("+", r"\+"), net) for p in POWER_NETS)


# --- occupancy, so automatically placed parts do not land on anything ------------------
class Occupancy:
    CELL = 0.5   # mm

    def __init__(self):
        self.w = int(bd.BOARD_W * MM / self.CELL) + 1
        self.h = int(bd.BOARD_H * MM / self.CELL) + 1
        self.grid = bytearray(self.w * self.h)

    def _cells(self, box, margin):
        x0 = int((pcbnew.ToMM(box.GetX()) - ORIGIN[0] - margin) / self.CELL)
        y0 = int((pcbnew.ToMM(box.GetY()) - ORIGIN[1] - margin) / self.CELL)
        x1 = int((pcbnew.ToMM(box.GetRight()) - ORIGIN[0] + margin) / self.CELL)
        y1 = int((pcbnew.ToMM(box.GetBottom()) - ORIGIN[1] + margin) / self.CELL)
        return x0, y0, x1, y1

    def free(self, box, margin=0.4):
        x0, y0, x1, y1 = self._cells(box, margin)
        if x0 < 2 or y0 < 2 or x1 >= self.w - 2 or y1 >= self.h - 2:
            return False
        for y in range(y0, y1 + 1):
            row = self.grid[y * self.w + x0: y * self.w + x1 + 1]
            if any(row):
                return False
        return True

    def mark(self, box):
        x0, y0, x1, y1 = self._cells(box, 0.0)
        for y in range(max(y0, 0), min(y1, self.h - 1) + 1):
            for x in range(max(x0, 0), min(x1, self.w - 1) + 1):
                self.grid[y * self.w + x] = 1


def fp_box(fp):
    cy = fp.GetCourtyard(pcbnew.F_CrtYd)
    if cy.OutlineCount():
        return cy.BBox()
    return fp.GetBoundingBox(False)


# --- footprints for the circuit's parts ---------------------------------------------------
R_FP = ("Resistor_THT", "R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal")
RW_FP = ("Resistor_THT", "R_Axial_DIN0414_L11.9mm_D4.5mm_P15.24mm_Horizontal")
C_FP = ("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm")
CP_FP = ("Capacitor_THT", "CP_Radial_D5.0mm_P2.50mm")
CPL_FP = ("Capacitor_THT", "CP_Radial_D10.0mm_P5.00mm")
D_FP = ("Diode_THT", "D_DO-41_SOD81_P10.16mm_Horizontal")
DP_FP = ("Diode_THT", "D_DO-201AD_P12.70mm_Horizontal")
LED_FP = ("LED_THT", "LED_D5.0mm")
TO92_FP = ("Package_TO_SOT_THT", "TO-92_Inline_Wide")
TO220_FP = ("Package_TO_SOT_THT", "TO-220-3_Vertical")
VR_FP = ("Potentiometer_THT", "Potentiometer_Bourns_3386P_Vertical")
XTAL_FP = ("Crystal", "Crystal_HC49-U_Vertical")
LK2_FP = ("Connector_PinHeader_2.54mm", "PinHeader_1x02_P2.54mm_Vertical")
LK3_FP = ("Connector_PinHeader_2.54mm", "PinHeader_1x03_P2.54mm_Vertical")


def uf(value):
    """Capacitance in microfarads from a value like '4u7', '100n', '22p', '4700u 25V'."""
    m = re.match(r"\s*(\d+)([pnu])(\d*)", value)
    if not m:
        return 0.0
    v = float(m.group(1) + "." + (m.group(3) or "0"))
    return v * {"p": 1e-6, "n": 1e-3, "u": 1.0}[m.group(2)]


def classify(ref, part):
    """(kind, (lib, footprint), padmap pad->pin) for a discrete part of the netlist."""
    v, pins = part["value"], set(part["pins"])
    # R_CPU1 / C_VDU2 style (kind first) or TAPE_R3 / PSU_C1 style (section first)
    bits = ref.split("_")
    base = bits[0] if bits[0] in ("R", "C", "D", "X", "TR", "VR") else bits[-1]
    if pins == {"B", "C", "E"}:
        if re.search(r"TIP|MJE|MM4002", v):
            return "TO220", TO220_FP, {"1": "B", "2": "C", "3": "E"}
        return "TO92", TO92_FP, {"1": "E", "2": "B", "3": "C"}
    if pins == {"IN", "GND", "OUT"}:
        if v.startswith("79"):
            return "TO220", TO220_FP, {"1": "GND", "2": "IN", "3": "OUT"}
        return "TO220", TO220_FP, {"1": "IN", "2": "GND", "3": "OUT"}
    if base.startswith("VR") or ref.startswith("VR"):
        return "VR", VR_FP, {"1": "1", "2": "3", "3": "2"}
    if base.startswith("X"):
        return "XTAL", XTAL_FP, None
    if ref.startswith("LK") or ref.startswith("LINK"):
        if pins == {"A", "B", "COM"}:
            return "LINK", LK3_FP, {"1": "A", "2": "COM", "3": "B"}
        return "LINK", LK2_FP, None
    if base.startswith("D"):
        if "LED" in v:
            return "LED", LED_FP, None
        return ("D", DP_FP, None) if re.search(r"1N54", v) else ("D", D_FP, None)
    if base.startswith("R"):
        return ("RW", RW_FP, None) if re.match(r"0R", v) else ("R", R_FP, None)
    if base.startswith("C"):
        polar = "tantalum" in v or uf(v) >= 1.0
        if not polar:
            return "C", C_FP, None
        return ("CP", CPL_FP, None) if uf(v) >= 100 else ("CP", CP_FP, None)
    sys.exit(f"don't know what footprint {ref} ({v}) needs")


# kit-sheet slot kinds each part kind may use
SLOT_OK = {"R": ("R",), "RW": ("RW", "R"), "C": ("C", "CP"), "CP": ("CP", "C"), "D": ("D",),
           "LED": ("LED",), "TO92": ("TO92",), "TO220": ("TO220",), "VR": ("VR",)}


def kit_slots():
    slots = {}
    for part in bd.TWO_LEAD:
        slots[part[0]] = ("two", part[2], part)
    for part in bd.ONE_POINT:
        if part[2] != "PIN":
            slots[part[0]] = ("one", part[2], part)
    for part in bd.BOXES:
        slots[part[0]] = ("box", "BOX", part)
    return slots


def place_at_slot(board, fp, ref, value, slot):
    how, kind, part = slot
    if how == "two":
        (ax, ay), (bx, by) = g.two_lead_pads(part)
        span = abs(pad_span(fp)) / MM
        mx, my = (ax + bx) / 2, (ay + by) / 2
        ang = math.atan2(by - ay, bx - ax)
        place(board, fp, ref, value, mx - math.cos(ang) * span / 2, my - math.sin(ang) * span / 2, -math.degrees(ang))
    elif how == "one":
        x, y = part[3], part[4]
        rot = bd.SLOT_ROTATION.get(part[0], 0)
        a = math.radians(rot)
        half = pad_span(fp) / 2 / MM
        place(board, fp, ref, value, x - half * math.cos(a), y + half * math.sin(a), rot)
    else:
        x0, y0, x1, y1 = part[2:]
        place(board, fp, ref, value, (x0 + x1) / 2 - pad_span(fp) / 2 / MM, (y0 + y1) / 2)


def pad_span(fp):
    """Distance in mm along x from pad 1 to the furthest pad, footprint unrotated."""
    xs = [pcbnew.ToMM(p.GetFPRelativePosition().x) for p in fp.Pads()]
    return max(xs) - min(xs) if xs else 0.0


def box_footprint(part):
    ref, val, x0, y0, x1, y1 = part
    length, dia = (x1 - x0 - 20) * MM, (y1 - y0) * MM
    names = [os.path.basename(p)[:-10] for p in glob.glob(os.path.join(LIBS, "Capacitor_THT.pretty", "CP_Axial_L*_Horizontal.kicad_mod"))]

    def score(n):
        p = float(re.search(r"_P([\d.]+)mm", n).group(1))
        d = float(re.search(r"_D([\d.]+)mm", n).group(1))
        return abs(p - length) + 0.5 * abs(d - dia)
    return "Capacitor_THT", min(names, key=score)


def pads_footprint(board, name, pads, dia=2.0, drill=1.0):
    """A footprint of plain round pads named after the pins, at frame-px offsets from the first."""
    fp = pcbnew.FOOTPRINT(board)
    fp.SetFPID(pcbnew.LIB_ID("PSI_COMP80", name))
    fp.SetAttributes(pcbnew.FP_THROUGH_HOLE)
    (x0, y0) = pads[0][1]
    for pin, (x, y) in pads:
        pad = pcbnew.PAD(fp)
        pad.SetNumber(pin)
        pad.SetAttribute(pcbnew.PAD_ATTRIB_PTH)
        pad.SetShape(pcbnew.PAD_SHAPE_CIRCLE)
        pad.SetSize(pcbnew.VECTOR2I(pcbnew.FromMM(dia), pcbnew.FromMM(dia)))
        pad.SetDrillSize(pcbnew.VECTOR2I(pcbnew.FromMM(drill), pcbnew.FromMM(drill)))
        pad.SetLayerSet(pad.PTHMask())
        pad.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM((x - x0) * MM), pcbnew.FromMM((y - y0) * MM)))
        fp.Add(pad)
    return fp


# Off-board wiring points, at the pads drawn on the kit sheet (frame px)
CONNECTOR_PADS = {
    "J_TAPE": {"OUT": (1712, 137), "GND": (1714, 167), "IN": (1750, 167)},
    "J_2N3055": {"C": (1658, 812), "B": (1675, 825), "E": (1658, 838)},
    "J_MAINS": {"E": (1930, 1062)},
    "J_VIDEO": {"VIDEO": (1986, 545), "SYNC_N": (1986, 578), "SYNC": (1986, 612), "GND": (1986, 645)},
}
TRANSFORMER_Y = [813, 850, 885, 920, 955, 990, 1025, 1060]   # kit's TP4-TP11 at x = 1958


# Board sections from the layout sheet (frame px): x0, y0, x1, y1
SECTIONS = {"cpu": (0, 0, 430, 948), "kbd": (0, 948, 430, 1075), "mem": (430, 297, 1292, 1075),
            "vdu": (1292, 262, 2000, 785), "tape": (1537, 0, 2000, 262), "psu": (1537, 785, 2000, 1075)}


def section_of(ref, part):
    fig = part["figure"]
    if ref.startswith("TAPE") or ref in ("IC51", "IC52", "IC53", "VR2", "TR8"):
        return SECTIONS["tape"]
    if ref.startswith("PSU") or fig == "net_io.json":
        return SECTIONS["psu"]
    return SECTIONS[{"net_cpu.json": "cpu", "net_mem.json": "mem", "net_vdu.json": "vdu",
                     "net_kbd.json": "kbd", "net_board.json": "vdu"}.get(fig, "mem")]


def expand_bridges(parts):
    """The kit builds the article's two bridge rectifiers from discrete 1N4002s (D4-D11)."""
    out = dict(parts)
    for br, first in (("BR1", 4), ("BR2", 8)):
        if br not in out:
            continue
        p = out.pop(br)["pins"]
        legs = [(p["+"], p["AC1"]), (p["+"], p["AC2"]), (p["AC1"], p["-"]), (p["AC2"], p["-"])]
        for i, (k, a) in enumerate(legs):
            out[f"D{first + i}"] = {"value": "1N4002", "figure": "net_io.json",
                                    "pins": {"1": k, "2": a}, "note": f"leg of {br}"}
    return out


def add_circuit(board, nets, occ):
    netlist = json.load(open(NETLIST))
    parts = expand_bridges(netlist["parts"])
    kit_ics = {ic["ref"] for ic in bd.ics()}
    pad_xy = {}      # net -> [(x, y)] of pads already placed, frame px

    def remember(fp):
        occ.mark(fp_box(fp))
        for pad in fp.Pads():
            n = pad.GetNetname()
            if n and not is_power(n):
                v = pad.GetPosition()
                pad_xy.setdefault(n, []).append(((pcbnew.ToMM(v.x) - ORIGIN[0]) / MM, (pcbnew.ToMM(v.y) - ORIGIN[1]) / MM))

    # ICs at their kit positions; values and nets from the circuit diagrams
    worst = 0.0
    for ic in bd.ics():
        n, w = ic["pins"], ic["width"]
        name = f"DIP-{n}_W{'15.24' if w > 0.45 else '7.62'}mm"
        pins = g.ic_pins(ic)
        part = parts.get(ic["ref"])
        value = part["value"] if part else ic["value"]
        fp = place(board, load("Package_DIP", name), ic["ref"], value, pins[0][1], pins[0][2], g.ic_placement(ic)[2])
        _, xn, yn = pins[-1]
        px, py = pad_pos(fp, n)
        worst = max(worst, math.hypot(px - xn, py - yn))
        if part:
            nets.assign(fp, part["pins"])
        remember(fp)
    assert worst < 0.5, f"DIP pin placement off by {worst:.2f} px"

    # keep the RAM columns clear for the column bus runs (see preroute_ram_columns)
    cols = {}
    for fp in board.GetFootprints():
        if fp.GetValue() == "21L02":
            cols.setdefault(fp.GetPosition().x, []).extend(p.GetPosition() for p in fp.Pads())
    for pads in cols.values():
        m = pcbnew.FromMM(1.27 + 0.6)
        x0, x1 = min(p.x for p in pads) - m, max(p.x for p in pads) + m
        y0, y1 = min(p.y for p in pads), max(p.y for p in pads)
        occ.mark(pcbnew.BOX2I(pcbnew.VECTOR2I(x0, y0), pcbnew.VECTOR2I(x1 - x0, y1 - y0)))

    # key switches
    for k in bd.keys():
        fp = key_footprint(board, k)
        label = k["legend"] + (" " + k["shifted"] if k["shifted"] else "")
        place(board, fp, k["ref"], label, *k["pad1"])
        if k["ref"] in parts:
            nets.assign(fp, parts[k["ref"]]["pins"])
        fp.Value().SetLayer(pcbnew.F_SilkS)
        size = 2.5 if len(k["legend"]) == 1 else 1.4
        fp.Value().SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(size), pcbnew.FromMM(size)))
        fp.Value().SetTextThickness(pcbnew.FromMM(0.35 if len(k["legend"]) == 1 else 0.2))
        cx, cy = g.key_centre(k)
        fp.Value().SetPosition(pt(cx, cy - 22))
        fp.Reference().SetPosition(pt(cx, cy + 20))
        remember(fp)

    # off-board wiring pads
    for ref, part in parts.items():
        if not ref.startswith("J_"):
            continue
        if ref == "J_TRANSFORMER":
            where = {pin: (1958, y) for pin, y in zip(part["pins"], TRANSFORMER_Y)}
        else:
            where = CONNECTOR_PADS[ref]
        pads = [(pin, where[pin]) for pin in part["pins"]]
        fp = place(board, pads_footprint(board, "Pads_" + ref[2:], pads), ref, part["value"], *pads[0][1])
        nets.assign(fp, part["pins"])
        remember(fp)

    # discrete parts: kit position when the kit sheet has the same reference, else nearby
    slots = kit_slots()
    pending = []
    for ref, part in sorted(parts.items()):
        if ref in kit_ics or ref.startswith("SW") or ref.startswith("J_"):
            continue
        if ref in slots and slots[ref][0] == "box":
            lib, name = box_footprint(slots[ref][2])
            fp = load(lib, name)
            place_at_slot(board, fp, ref, part["value"], slots[ref])
            nets.assign(fp, part["pins"])
            remember(fp)
            continue
        kind, (lib, name), padmap = classify(ref, part)
        if ref in slots and slots[ref][1] in SLOT_OK.get(kind, ()):
            fp = load(lib, name)
            place_at_slot(board, fp, ref, part["value"], slots.pop(ref))
            nets.assign(fp, part["pins"], padmap)
            remember(fp)
        else:
            pending.append((ref, part, kind, lib, name, padmap))
    for ref in [r for r in slots if r in parts]:
        slots.pop(ref)

    while pending:
        def anchors(item):
            pts = [xy for n in item[1]["pins"].values() if n in pad_xy for xy in pad_xy[n]]
            return pts
        pending.sort(key=lambda it: (-len(anchors(it)), it[0]))
        ref, part, kind, lib, name, padmap = pending.pop(0)
        pts = anchors((ref, part))
        x0, y0, x1, y1 = section_of(ref, part)
        tx, ty = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)) if pts else ((x0 + x1) / 2, (y0 + y1) / 2)
        # stay inside the part's own section of the board
        tx, ty = min(max(tx, x0 + 20), x1 - 20), min(max(ty, y0 + 20), y1 - 20)
        fp = load(lib, name)
        nets.assign(fp, part["pins"], padmap)
        placed = False
        for sref, slot in sorted(slots.items(), key=lambda s: dist_to(s[1], tx, ty)):
            if slot[1] not in SLOT_OK.get(kind, ()) or dist_to(slot, tx, ty) > 260:
                continue
            place_at_slot(board, fp, ref, part["value"], slot)
            if occ.free(fp_box(fp), 0.2):
                slots.pop(sref)
                placed = True
                break
            board.Remove(fp)
        if not placed:
            placed = place_free(board, fp, ref, part["value"], tx, ty, occ)
        if not placed:
            sys.exit(f"no room for {ref}")
        remember(fp)


def dist_to(slot, x, y):
    how, kind, part = slot
    if how == "two":
        px, py = (part[3] + part[5]) / 2, (part[4] + part[6]) / 2
    elif how == "one":
        px, py = part[3], part[4]
    else:
        px, py = (part[2] + part[4]) / 2, (part[3] + part[5]) / 2
    return math.hypot(px - x, py - y)


def place_free(board, fp, ref, value, tx, ty, occ, limit=700):
    """Spiral out from (tx, ty) on a 0.05 in grid until the footprint fits."""
    step = 0.05 * bd.PX_PER_IN
    for r in range(0, int(limit / step)):
        ring = [(dx, dy) for dx in range(-r, r + 1) for dy in range(-r, r + 1) if max(abs(dx), abs(dy)) == r]
        ring.sort(key=lambda d: d[0] * d[0] + d[1] * d[1])
        for dx, dy in ring:
            x, y = g.snap(tx + dx * step), g.snap(ty + dy * step)
            if y > 1060:       # keep clear of the keyboard
                continue
            for rot in (0, 90):
                place(board, fp, ref, value, x, y, rot)
                if occ.free(fp_box(fp)):
                    return True
                board.Remove(fp)
    return False


def preroute_ram_columns(board, nets):
    """Route the 21L02 arrays by hand, the way the 1979 artwork does it.

    The RAM chips sit in vertical columns (IC22a-h ... IC26a-h, IC43a-g, IC44a-g) and most
    of their pins are common to the whole column. Each such pin is joined to the same pin
    of the chip below, all on the component side, leaving the solder side free for the
    data lines that run across the columns. The runs never cross: a top-row pin runs a
    quarter pitch right of its pad column and drops through the gap to the right of its
    pad in the bottom row; a bottom-row pin runs a quarter pitch left of its column and
    enters the next chip through the gap to the left of its pad in the top row. The runs
    are locked so Freerouting only has to join the columns up.
    """
    q, h = 0.635, 1.27
    cols = {}
    for fp in board.GetFootprints():
        if fp.GetValue() == "21L02":
            cols.setdefault(round(pcbnew.ToMM(fp.GetPosition().x), 1), []).append(fp)
    count = 0
    for chips in cols.values():
        chips.sort(key=lambda f: f.GetPosition().y)
        for a, b in zip(chips, chips[1:]):
            pa = {p.GetNumber(): p for p in a.Pads()}
            pb = {p.GetNumber(): p for p in b.Pads()}
            row_y = lambda pads, top: pcbnew.ToMM(pads["1" if top else "16"].GetPosition().y)
            ta, ba, tb, bb = row_y(pa, True), row_y(pa, False), row_y(pb, True), row_y(pb, False)
            for num in pa:
                net = pa[num].GetNetname()
                if not net or net != pb[num].GetNetname():
                    continue
                x = pcbnew.ToMM(pa[num].GetPosition().x)
                if int(num) <= 8:     # top row
                    path = [(x, ta), (x + q, ta + q), (x + q, ba - h), (x + h, ba - q), (x + h, ba + q),
                            (x + q, ba + h), (x + q, tb - q), (x, tb)]
                else:                 # bottom row
                    # (straight through the top row, jogging well clear of it: pin 1's pad is square)
                    path = [(x, ba), (x - q, ba + q), (x - q, tb - h - q), (x - h, tb - h), (x - h, tb + h),
                            (x - q, tb + h + q), (x - q, bb - q), (x, bb)]
                for (sx, sy), (ex, ey) in zip(path, path[1:]):
                    t = pcbnew.PCB_TRACK(board)
                    t.SetStart(pcbnew.VECTOR2I(pcbnew.FromMM(sx), pcbnew.FromMM(sy)))
                    t.SetEnd(pcbnew.VECTOR2I(pcbnew.FromMM(ex), pcbnew.FromMM(ey)))
                    t.SetWidth(pcbnew.FromMM(0.25))
                    t.SetLayer(pcbnew.F_Cu)
                    t.SetNet(nets.get(net))
                    t.SetLocked(True)
                    board.Add(t)
                count += 1
    return count


def add_edge_keepout(board, width_mm=1.0):
    """Rule areas along the board edge so the router keeps copper off it."""
    w = width_mm / MM
    for x0, y0, x1, y1 in ((0, 0, bd.BOARD_W, w), (0, bd.BOARD_H - w, bd.BOARD_W, bd.BOARD_H),
                           (0, 0, w, bd.BOARD_H), (bd.BOARD_W - w, 0, bd.BOARD_W, bd.BOARD_H)):
        z = pcbnew.ZONE(board)
        z.SetIsRuleArea(True)
        z.SetDoNotAllowTracks(True)
        z.SetDoNotAllowVias(True)
        z.SetDoNotAllowZoneFills(True)
        z.SetDoNotAllowPads(False)
        z.SetDoNotAllowFootprints(False)
        ls = pcbnew.LSET()
        ls.AddLayer(pcbnew.F_Cu)
        ls.AddLayer(pcbnew.B_Cu)
        z.SetLayerSet(ls)
        ol = z.Outline()
        ol.NewOutline()
        for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
            v = pt(x, y)
            ol.Append(v.x, v.y)
        board.Add(z)


def apply_netclasses(board):
    bds = board.GetDesignSettings()
    bds.m_TrackMinWidth = pcbnew.FromMM(0.12)       # Freerouting necks tracks down between pads
    bds.m_CopperEdgeClearance = pcbnew.FromMM(0.5)
    ns = bds.m_NetSettings
    d = ns.GetDefaultNetclass()
    d.SetTrackWidth(pcbnew.FromMM(0.25))
    d.SetClearance(pcbnew.FromMM(0.2))
    d.SetViaDiameter(pcbnew.FromMM(0.9))
    d.SetViaDrill(pcbnew.FromMM(0.45))
    pw = pcbnew.NETCLASS("Power")
    pw.SetTrackWidth(pcbnew.FromMM(0.6))
    pw.SetClearance(pcbnew.FromMM(0.25))
    pw.SetViaDiameter(pcbnew.FromMM(1.2))
    pw.SetViaDrill(pcbnew.FromMM(0.6))
    ns.SetNetclass("Power", pw)
    for pattern in POWER_NETS:
        ns.SetNetclassPatternAssignment(pattern, "Power")
    ns.RecomputeEffectiveNetclasses()
    board.SynchronizeNetsAndNetClasses(True)

def add_expansion(board):
    e = bd.EXPANSION
    num, x, y = g.expansion_pins()[0]
    name = f"PinHeader_2x{e['pins_per_row']}_P2.54mm_Vertical"
    return [place(board, load("Connector_PinHeader_2.54mm", name), e["ref"], e["value"], x, y, 90)]


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


def add_holes(board):
    return [place(board, load("MountingHole", "MountingHole_3.2mm_M3"), f"H{i + 1}", "MountingHole", x, y)
            for i, (x, y) in enumerate(bd.HOLES)]


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
             "Artwork.Blue.Top (component side) / Artwork.Red.Bottom (solder side) are copper traced from a photo (approximate)", 1000, 1530, 2.5)


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
    board.SetLayerName(pcbnew.User_1, "Artwork.Red.Bottom")
    board.SetLayerName(pcbnew.User_2, "Artwork.Blue.Top")
    tb = board.GetTitleBlock()
    tb.SetTitle("PSI COMP 80 main board")
    tb.SetCompany("Wireless World 1979 / Powertran kit - reconstruction")
    tb.SetComment(0, "Placement from photos of the kit sheets; nets from the Wireless World circuit diagrams")

    add_artwork(board)
    add_furniture(board)
    occ = Occupancy()
    for fp in add_expansion(board) + add_holes(board):
        occ.mark(fp_box(fp))
    nets = Nets(board)
    add_circuit(board, nets, occ)
    add_edge_keepout(board)
    apply_netclasses(board)
    print(preroute_ram_columns(board, nets), "RAM column links pre-routed")

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

    write_project(os.path.join(OUTDIR, "psicomp80.kicad_pro"))
    print(pcb, len(board.GetFootprints()), "footprints,", len(nets.items), "nets")


def write_project(path):
    """Project file carrying the net classes, so KiCad and route_board.py use the same rules."""
    def cls(name, track, clearance, via, drill):
        return {"name": name, "track_width": track, "clearance": clearance, "via_diameter": via,
                "via_drill": drill, "microvia_diameter": 0.3, "microvia_drill": 0.1,
                "diff_pair_width": 0.2, "diff_pair_gap": 0.25, "diff_pair_via_gap": 0.25,
                "wire_width": 6, "bus_width": 12, "line_style": 0, "pcb_color": "rgba(0, 0, 0, 0.000)",
                "schematic_color": "rgba(0, 0, 0, 0.000)", "priority": 2147483647 if name == "Default" else 0}
    pro = {"meta": {"filename": os.path.basename(path), "version": 3},
           "board": {"design_settings": {"rules": {"min_track_width": 0.12, "min_copper_edge_clearance": 0.5}}},
           "net_settings": {"meta": {"version": 4},
                            "classes": [cls("Default", 0.25, 0.2, 0.9, 0.45), cls("Power", 0.6, 0.25, 1.2, 0.6)],
                            "netclass_patterns": [{"netclass": "Power", "pattern": p} for p in POWER_NETS]}}
    json.dump(pro, open(path, "w"), indent=2)


if __name__ == "__main__":
    main()
