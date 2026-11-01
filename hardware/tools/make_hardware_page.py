"""Make ../../hardware.html: the COMP80 main board, its circuits and its parts.

Reads the KiCad board (../kicad/psicomp80.kicad_pcb) directly, with no KiCad needed,
and draws it as a layered SVG: the component (top) and solder (bottom) copper of the
routed board, the traced 1979 kit artwork for each side, pads and holes, component
outlines and labels. The netlist (netlist/psicomp80_netlist.json) says which article
figure, and so which part of the circuit, each part belongs to.

    python3 make_hardware_page.py            writes ../../hardware.html
    python3 make_hardware_page.py LINKS      writes ../../hardware/build/hardware_artifact.html,
                                             with the links to the other pages taken from
                                             LINKS (lines of "page.html URL"), for publishing
"""
import base64
import html
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
PCB = HERE.parent / "kicad" / "psicomp80.kicad_pcb"
NETLIST = HERE / "netlist" / "psicomp80_netlist.json"
OUT = REPO / "hardware.html"

# board frame: 16 x 12 in from (30, 30) mm; board_data.py's frame pixels are 0.2032 mm
X0, Y0, W, H = 30.0, 30.0, 406.4, 304.8


# ------------------------------------------------------------------ s-expressions

TOKEN = re.compile(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()"]+')


def parse(text):
    stack, cur = [], []
    for t in TOKEN.findall(text):
        if t == "(":
            stack.append(cur)
            cur = []
        elif t == ")":
            done, cur = cur, stack.pop()
            cur.append(done)
        elif t[0] == '"':
            cur.append(t[1:-1].replace('\\"', '"').replace("\\\\", "\\"))
        else:
            cur.append(t)
    return cur[0]


def kids(node, key):
    return [c for c in node if isinstance(c, list) and c and c[0] == key]


def kid(node, key):
    for c in node:
        if isinstance(c, list) and c and c[0] == key:
            return c
    return None


def num(v):
    return float(v)


def f(v):
    """A number for the SVG: two decimals, no trailing zeros."""
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def rot(px, py, deg):
    """KiCad rotation: positive is anticlockwise on screen (y down)."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return px * c + py * s, -px * s + py * c


def arc_path(s, m, e):
    """SVG arc through three points."""
    (x1, y1), (x2, y2), (x3, y3) = s, m, e
    d = 2 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2))
    if abs(d) < 1e-9:
        return f"M{f(x1)} {f(y1)}L{f(x3)} {f(y3)}"
    ux = ((x1 * x1 + y1 * y1) * (y2 - y3) + (x2 * x2 + y2 * y2) * (y3 - y1) + (x3 * x3 + y3 * y3) * (y1 - y2)) / d
    uy = ((x1 * x1 + y1 * y1) * (x3 - x2) + (x2 * x2 + y2 * y2) * (x1 - x3) + (x3 * x3 + y3 * y3) * (x2 - x1)) / d
    r = math.hypot(x1 - ux, y1 - uy)
    cross = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)
    sweep = 1 if cross > 0 else 0
    a1, a2, a3 = (math.atan2(y - uy, x - ux) for x, y in (s, m, e))
    span = (a3 - a1) % (2 * math.pi) if sweep else (a1 - a3) % (2 * math.pi)
    large = 1 if span > math.pi else 0
    return f"M{f(x1)} {f(y1)}A{f(r)} {f(r)} 0 {large} {sweep} {f(x3)} {f(y3)}"


# ------------------------------------------------------------------ what the parts are

TYPES = {
    "Z80": "Z80 microprocessor", "MM57109": "MM57109 scientific calculator chip",
    "AY-5-2376": "AY-5-2376 keyboard encoder", "2708": "2708 EPROM, 1K × 8",
    "21L02": "21L02 static RAM, 1K × 1", "2513": "2513 character generator ROM, 64 characters of 5 × 7 dots",
    "74LS138": "74LS138 3-to-8 line decoder", "74LS139": "74LS139 dual 2-to-4 line decoder",
    "74LS367": "74LS367 hex tri-state buffer", "81LS95": "81LS95 octal tri-state buffer",
    "74C173": "74C173 4-bit latch, tri-state outputs (CMOS)", "4011": "4011 quad 2-input NAND (CMOS)",
    "74LS04": "74LS04 hex inverter", "74LS00": "74LS00 quad 2-input NAND", "74LS02": "74LS02 quad 2-input NOR",
    "7425": "7425 dual 4-input NOR", "74LS157": "74LS157 quad 2-to-1 multiplexer",
    "7493": "7493 4-bit binary counter", "7490": "7490 decade counter", "7492": "7492 divide-by-12 counter",
    "74165": "74165 8-bit shift register, parallel in, serial out", "74121": "74121 monostable",
    "4013": "4013 dual D flip-flop (CMOS)", "4528": "4528 dual monostable (CMOS)",
    "7805": "7805 +5 V regulator", "7812": "7812 +12 V regulator", "7912": "7912 −12 V regulator",
    "7905": "7905 −5 V regulator", "TIP30": "TIP30 PNP power transistor",
    "2N3906": "2N3906 PNP transistor", "2N3904": "2N3904 NPN transistor",
    "1N4001": "1N4001 rectifier diode", "1N4002": "1N4002 rectifier diode", "1N5401": "1N5401 3 A rectifier diode",
}

ROLES = {
    "IC1": "The processor. Everything else hangs off its address, data and control buses.",
    "IC2": "Output port decoder: with IORQ and WR low, address lines A5–A7 pick one of eight output devices.",
    "IC3": "Input port decoder: with IORQ and RD low, A0–A2 pick one of eight input devices.",
    "IC4": "Latch for the MM57109's instruction code (with IC5), loaded by an OUT from the Z80.",
    "IC5": "Latch for the MM57109's instruction code (with IC4).",
    "IC6": "The calculator chip: the floating-point arithmetic for BURP, done one keystroke code at a time.",
    "IC7": "Gates the MM57109's RDY to the Z80, and its HOLD and power-on reset from it, using ISEL.",
    "IC8": "Input port for the MM57109: its digit outputs, gated RDY and branch line onto the data bus.",
    "IC9": "Data bus transceiver, low four bits towards the Z80, and buffers for RD and WR.",
    "IC10": "Data bus transceiver, high four bits towards the Z80, and the MREQ buffer.",
    "IC11": "Data bus transceiver, low four bits from the Z80 when it writes.",
    "IC12": "Data bus transceiver, high four bits from the Z80 when it writes.",
    "IC13": "Keyboard input port: puts the 7-bit key code on the data bus.",
    "IC14": "Inverters: the Z80 clock driver (with TR1's active pull-up) and the keyboard strobe to NMI.",
    "IC15": "Address buffer for A0–A5, which drive dozens of memory chips.",
    "IC16": "Address buffer for A6–A9.",
    "IC17": "Memory decoder: splits the bottom 8K into eight 1K blocks, one chip select each.",
    "IC18": "EPROM 0000–03FF: the monitor.",
    "IC19": "EPROM 0400–07FF: BURP, first half.",
    "IC20": "EPROM 0800–0BFF: BURP, second half.",
    "IC21": "Spare EPROM socket for 0C00–0FFF, used in place of IC22's RAM when link 1 is fitted.",
    "IC27": "Memory output buffer: joins the memory's own data bus to the main one on reads.",
    "IC28": "8 MHz crystal oscillator, video output gate and inverters for the display timing.",
    "IC29": "Halves the 8 MHz dot clock to 4 MHz, and starts the character-row counter with IC35.",
    "IC30": "Divides 4 MHz to the Z80's 2 MHz clock and to 250 kHz for the line timer.",
    "IC31": "Sync and display-reset gating; inverts MREQ for the video RAM.",
    "IC32": "Sync, shift-register load and video RAM multiplexer select gating.",
    "IC33": "Character clock decode and the video gate (blanking between rows and during flyback).",
    "IC34": "Counts the ten scan lines of each character row; lines 9 and 10 are blank.",
    "IC35": "Character-row counter (with IC29): 32 rows.",
    "IC36": "Frame monostable: at the end of the 32nd row it holds the counters for the frame flyback.",
    "IC37": "Divides the 8 MHz dot clock by six: one pulse per character.",
    "IC38": "Character counter, low bits: 64 characters across.",
    "IC39": "Character counter, high bits.",
    "IC40": "Video RAM address multiplexer: Z80 address or display counters.",
    "IC41": "Video RAM address multiplexer.",
    "IC42": "Video RAM address multiplexer.",
    "IC45": "Shift register: loads a row of dots from the character generator and sends them out one at a time.",
    "IC46": "Clock for the MM57109: 400 kHz, or 800 kHz with the link moved.",
    "IC47": "Character generator: screen code and scan line in, five dots out.",
    "IC48": "Line timer: 16 states of 4 µs make each 64 µs line, and state 1 is the line sync.",
    "IC49": "Video RAM write gating.",
    "IC51": "Tape flip-flops: one latches the bit being recorded, the other decides 0 or 1 when reading.",
    "IC52": "Tape monostable: the frequency discriminator that tells 1200 Hz from 2400 Hz.",
    "IC53": "Tape input port: the bit read from tape onto the data bus.",
    "IC54": "Keyboard encoder: scans the key matrix and gives a 7-bit code and a strobe for each key.",
    "IC55": "Inverts the encoder's strobe.",
    "IC56": "+5 V regulator, with TR9 and an off-board 2N3055 carrying most of the current.",
    "IC57": "Optional 2-to-4 decoder for the 32K memory expansion.",
    "TR1": "Active pull-up on the Z80 clock: the Z80 needs a fast rise to 4.4 V.",
    "TR2": "Level shifter for the MM57109's HOLD input.",
    "TR3": "Level shifter for the MM57109's power-on reset.",
    "TR9": "Drives the off-board 2N3055 pass transistor of the 5 V supply.",
    "X_VDU1": "The 8 MHz crystal: every clock in the computer comes from it.",
    "VR1": "Sets the frame monostable's time, and so the frame flyback.",
    "C14": "Reservoir for the 5 V supply.", "C17": "Reservoir for +12 V.", "C18": "Reservoir for −12 V and −5 V.",
    "J1": "Expansion plug: the Z80's buses and control lines, the spare port selects and the supplies (pinout in hardware/README.md).",
    "J_VIDEO": "Video and sync out to the modulator or monitor.",
    "J_TAPE": "To and from the cassette recorder.",
}

for c in "abcdefgh":
    for col, (lo, note) in {"22": (0x0C00, " (with link 2 fitted; link 1 gives this block to IC21 instead)"),
                            "23": (0x1000, ""), "24": (0x1400, " (optional)"), "25": (0x1800, " (optional)"),
                            "26": (0x1C00, "")}.items():
        ROLES[f"IC{col}{c}"] = f"Program RAM {lo:04X}–{lo + 0x3FF:04X}, bit {'abcdefgh'.index(c)}{note}."
for c in "abcdefg":
    for col, lo in (("43", 0x8000), ("44", 0x8400)):
        b = "abcdefg".index(c)
        ROLES[f"IC{col}{c}"] = (f"Video RAM {lo:04X}–{lo + 0x3FF:04X}, "
                                + ("bit 6, for the graphics option (optional)." if b == 6 else f"bit {b} of the screen code."))

KINDS = [("SW", "Key switch"), ("TR", "Transistor"), ("VR", "Preset"), ("LK", "Link"), ("LINK", "Link"),
         ("X", "Crystal"), ("BR", "Bridge rectifier"), ("IC", "Integrated circuit"), ("H", "Mounting hole"),
         ("J", "Connection pads"), ("R", "Resistor"), ("C", "Capacitor"), ("D", "Diode")]

SECTIONS = [
    ("cpu", "CPU"), ("mem", "Memory"), ("vdu", "Display"), ("tape", "Tape interface"),
    ("psu", "Power supply"), ("kbd", "Keyboard"), ("board", "Board"),
]


def kind_of(ref):
    base = re.sub(r"_.*", "", ref)
    for p, k in KINDS:
        if ref.startswith(p) and (len(ref) == len(p) or ref[len(p)].isdigit() or ref[len(p)] == "_"):
            return k
    for p, k in KINDS:
        if base.startswith(p):
            return k
    return "Part"


def describe(ref, value, kind):
    v = value.split(" (")[0]
    if v in TYPES:
        return TYPES[v]
    if kind == "Resistor":
        return f"{value} resistor"
    if kind == "Capacitor":
        return f"{value} capacitor"
    if kind == "Key switch":
        return f"key: {value}"
    return value


def section_by_place(x, y):
    """Which section of the kit sheet a point (mm) is in."""
    px, py = (x - X0) / 0.2032, (y - Y0) / 0.2032
    if py >= 1075:
        return "kbd"
    if px < 430:
        return "cpu" if py < 948 else "kbd"
    if py < 262 and px >= 1537:
        return "tape"
    if px >= 1537 and py >= 785:
        return "psu"
    if px < 918 or (px < 1292 and py >= 297) or (py < 262 and px < 1537):
        return "mem"
    return "vdu"


def section_of(ref, part, x, y):
    if part is None:
        if ref.startswith("D") and ref[1:].isdigit():
            return "psu"        # D4-D11: the bridge rectifiers, built from diodes
        return "mem" if ref in ("IC57", "J1") else section_by_place(x, y)
    fig = part["figure"]
    nets = set(part["pins"].values())
    if fig == "net_cpu.json":
        return "cpu"
    if fig == "net_mem.json":
        return "mem"
    if fig == "net_vdu.json":
        return "vdu"
    if fig == "net_kbd.json":
        return "kbd"
    if fig == "net_io.json":
        if ref.startswith("TAPE") or ref in ("IC51", "IC52", "IC53") or any(n.startswith("TAPE") for n in nets):
            return "tape"
        return "psu"
    return section_by_place(x, y)


# ------------------------------------------------------------------ the board

def build():
    pcb = parse(PCB.read_text())
    netlist = json.loads(NETLIST.read_text())
    parts = {**netlist["parts"]}

    nets, net_id = [], {}

    def nid(name):
        if not name:
            return None
        if name not in net_id:
            net_id[name] = len(nets)
            nets.append(name)
        return net_id[name]

    # tracks by layer, net and width
    tracks = {"F.Cu": defaultdict(list), "B.Cu": defaultdict(list)}
    for s in kids(pcb, "segment"):
        layer = kid(s, "layer")[1]
        if layer not in tracks:
            continue
        a, b = kid(s, "start"), kid(s, "end")
        n = kid(s, "net")
        key = (nid(n[1]) if n else None, num(kid(s, "width")[1]))
        tracks[layer][key].append(f"M{f(num(a[1]))} {f(num(a[2]))}L{f(num(b[1]))} {f(num(b[2]))}")

    vias = []
    for v in kids(pcb, "via"):
        at, n = kid(v, "at"), kid(v, "net")
        vias.append((num(at[1]), num(at[2]), num(kid(v, "size")[1]), num(kid(v, "drill")[1]),
                     nid(n[1]) if n else None))

    # traced kit artwork: User.2 is the blue component side, User.1 the red solder side
    art = {"User.2": [], "User.1": []}
    for p in kids(pcb, "gr_poly"):
        layer = kid(p, "layer")[1]
        if layer not in art:
            continue
        pts = [(num(q[1]), num(q[2])) for q in kid(p, "pts") if isinstance(q, list) and q[0] == "xy"]
        if len(pts) < 3:
            continue
        # relative coordinates at 0.05 mm keep this layer small
        out, lx, ly = [], 0, 0
        for i, (x, y) in enumerate(pts):
            qx, qy = round(x * 20), round(y * 20)
            if i == 0:
                out.append(f"M{f(qx / 20)} {f(qy / 20)}")
            else:
                out.append(f"l{f((qx - lx) / 20)} {f((qy - ly) / 20)}")
            lx, ly = qx, qy
        art[layer].append("".join(out) + "z")

    # section lines and notes drawn on the kit sheet
    sect_lines = []
    for g in kids(pcb, "gr_line"):
        if kid(g, "layer")[1] == "Dwgs.User":
            a, b = kid(g, "start"), kid(g, "end")
            sect_lines.append(f"M{f(num(a[1]))} {f(num(a[2]))}L{f(num(b[1]))} {f(num(b[2]))}")
    sect_text = []
    for t in kids(pcb, "gr_text"):
        if kid(t, "layer")[1] == "Dwgs.User" and not t[1].startswith("PSI COMP 80 main board"):
            at = kid(t, "at")
            size = num(kid(kid(kid(t, "effects"), "font"), "size")[1])
            sect_text.append((t[1], num(at[1]), num(at[2]), size))

    comps = []
    for fp in kids(pcb, "footprint"):
        lib = fp[1]
        at = kid(fp, "at")
        fx, fy = num(at[1]), num(at[2])
        frot = num(at[3]) if len(at) > 3 else 0.0
        props = {p[1]: p for p in kids(fp, "property")}
        ref = props["Reference"][2]
        value = props["Value"][2]

        def to_abs(px, py):
            dx, dy = rot(px, py, frot)
            return fx + dx, fy + dy

        # outline: silkscreen, or the fab layer where there is no silkscreen
        layers = defaultdict(list)
        for g in fp:
            if not (isinstance(g, list) and g and g[0] in ("fp_line", "fp_rect", "fp_arc", "fp_circle", "fp_poly")):
                continue
            layer = kid(g, "layer")[1]
            if g[0] == "fp_line":
                a, b = kid(g, "start"), kid(g, "end")
                d = f"M{f(num(a[1]))} {f(num(a[2]))}L{f(num(b[1]))} {f(num(b[2]))}"
                pts = [(num(a[1]), num(a[2])), (num(b[1]), num(b[2]))]
            elif g[0] == "fp_rect":
                a, b = kid(g, "start"), kid(g, "end")
                x1, y1, x2, y2 = num(a[1]), num(a[2]), num(b[1]), num(b[2])
                d = f"M{f(x1)} {f(y1)}H{f(x2)}V{f(y2)}H{f(x1)}Z"
                pts = [(x1, y1), (x2, y2)]
            elif g[0] == "fp_arc":
                s_, m_, e_ = (kid(g, k) for k in ("start", "mid", "end"))
                p3 = [(num(q[1]), num(q[2])) for q in (s_, m_, e_)]
                d = arc_path(*p3)
                pts = p3
            elif g[0] == "fp_circle":
                c_, e_ = kid(g, "center"), kid(g, "end")
                cx, cy = num(c_[1]), num(c_[2])
                r = math.hypot(num(e_[1]) - cx, num(e_[2]) - cy)
                d = (f"M{f(cx - r)} {f(cy)}a{f(r)} {f(r)} 0 1 0 {f(2 * r)} 0"
                     f"a{f(r)} {f(r)} 0 1 0 {f(-2 * r)} 0")
                pts = [(cx - r, cy - r), (cx + r, cy + r)]
            else:
                pts = [(num(q[1]), num(q[2])) for q in kid(g, "pts") if isinstance(q, list) and q[0] == "xy"]
                d = "M" + "L".join(f"{f(x)} {f(y)}" for x, y in pts) + "Z"
            layers[layer].append((d, pts))
        outline = layers.get("F.SilkS") or layers.get("F.Fab") or []
        body = layers.get("F.Fab") or layers.get("F.CrtYd") or outline

        pads, pts_all = [], []
        for p in kids(fp, "pad"):
            pat = kid(p, "at")
            px, py = num(pat[1]), num(pat[2])
            pa = num(pat[3]) if len(pat) > 3 else 0.0
            size = kid(p, "size")
            sw, sh = num(size[1]), num(size[2])
            drill = kid(p, "drill")
            dr = 0.0
            if drill and len(drill) > 1:
                dr = num(drill[2]) if drill[1] == "oval" else num(drill[1])
            n = kid(p, "net")
            rr = kid(p, "roundrect_rratio")
            pads.append(dict(num=p[1], shape=p[3], x=px, y=py, a=pa - frot, w=sw, h=sh, drill=dr,
                             rr=num(rr[1]) if rr else 0.0, net=nid(n[1]) if n and len(n) > 1 else None))
            pts_all += [(px - sw / 2, py - sh / 2), (px + sw / 2, py + sh / 2)]

        box_pts = [q for _, ps in body for q in ps] or pts_all or [(0, 0)]
        absb = [to_abs(x, y) for x, y in box_pts]
        bx0, by0 = min(x for x, _ in absb), min(y for _, y in absb)
        bx1, by1 = max(x for x, _ in absb), max(y for _, y in absb)
        cx, cy = (bx0 + bx1) / 2, (by0 + by1) / 2
        kind = kind_of(ref)
        part = parts.get(ref)
        comps.append(dict(ref=ref, value=value, lib=lib, kind=kind, x=fx, y=fy, rot=frot,
                          outline=[d for d, _ in outline], pads=pads,
                          box=(bx0, by0, bx1, by1), cx=cx, cy=cy,
                          section=section_of(ref, part, cx, cy),
                          desc=describe(ref, value, kind), role=ROLES.get(ref, ""),
                          figure=part["figure"] if part else ""))

    return dict(tracks=tracks, vias=vias, art=art, sect_lines=sect_lines, sect_text=sect_text,
                comps=comps, nets=nets)


# ------------------------------------------------------------------ SVG

def pad_svg(p, idx):
    n = f' data-n="{p["net"]}"' if p["net"] is not None else ""
    t = f' transform="rotate({f(-p["a"])} {f(p["x"])} {f(p["y"])})"' if p["a"] % 180 else ""
    w, h = p["w"], p["h"]
    if p["shape"] == "circle" or (p["shape"] == "oval" and abs(w - h) < 1e-6):
        el = f'<circle cx="{f(p["x"])}" cy="{f(p["y"])}" r="{f(w / 2)}"{n}/>'
    else:
        if p["shape"] == "oval":
            rx = min(w, h) / 2
        elif p["shape"] == "roundrect":
            rx = min(w, h) * p["rr"]
        else:
            rx = 0
        r = f' rx="{f(rx)}"' if rx else ""
        el = (f'<rect x="{f(p["x"] - w / 2)}" y="{f(p["y"] - h / 2)}" width="{f(w)}" height="{f(h)}"{r}{n}{t}/>')
    return el


def label_svg(c):
    """Reference (and type, for ICs) across the middle of the part, reading left to right or upwards."""
    x0, y0, x1, y1 = c["box"]
    w, h = x1 - x0, y1 - y0
    vertical = h > w * 1.15
    length, depth = (h, w) if vertical else (w, h)
    a = -90 if vertical else 0
    esc = html.escape
    if c["kind"] == "Key switch":
        legend = c["value"] if c["value"] != "uncommitted" else ""
        size = 3.2 if len(legend) <= 3 else 2.2
        return (f'<g class="lb key" transform="translate({f(c["x"] + 4.9)} {f(c["y"] - 3.4)})">'
                f'<text font-size="{size}">{esc(legend)}</text></g>')
    if c["kind"] == "Integrated circuit" and depth > 5:
        big = min(depth * 0.3, 2.6, length / max(len(c["ref"]), 4) * 1.5)
        small = min(big * 0.8, length / max(len(c["value"]), 4) * 1.5)
        return (f'<g class="lb ic" transform="translate({f((x0 + x1) / 2)} {f((y0 + y1) / 2)}) rotate({a})">'
                f'<text font-size="{f(big)}" y="{f(-big * 0.15)}" class="r">{esc(c["ref"])}</text>'
                f'<text font-size="{f(small)}" y="{f(small * 1.05)}">{esc(c["value"])}</text></g>')
    size = max(0.8, min(1.4, length / max(len(c["ref"]), 3) * 1.6))
    if c["kind"] == "Mounting hole":
        return ""
    return (f'<g class="lb sm" transform="translate({f((x0 + x1) / 2)} {f((y0 + y1) / 2)}) rotate({a})">'
            f'<text font-size="{f(size)}" y="{f(size * 0.35)}" class="r">{esc(c["ref"])}</text></g>')


def board_svg(b):
    out = [f'<svg id="board" viewBox="{f(X0 - 4)} {f(Y0 - 4)} {f(W + 8)} {f(H + 8)}" '
           f'xmlns="http://www.w3.org/2000/svg" role="img" aria-label="The COMP80 main board">',
           '<g id="world">',
           f'<rect class="sub" x="{f(X0)}" y="{f(Y0)}" width="{f(W)}" height="{f(H)}" rx="1.5"/>']
    # hit areas sit under everything, so pads and tracks get clicks first
    out.append('<g id="L-hit">')
    for i, c in enumerate(b["comps"]):
        x0, y0, x1, y1 = c["box"]
        out.append(f'<rect x="{f(x0)}" y="{f(y0)}" width="{f(x1 - x0)}" height="{f(y1 - y0)}" data-c="{i}"/>')
    out.append("</g>")
    for gid, layer in (("L-artB", "User.1"), ("L-artT", "User.2")):
        out.append(f'<g id="{gid}" class="art" hidden><path d="{"".join(b["art"][layer])}"/></g>')
    for gid, layer in (("L-bot", "B.Cu"), ("L-top", "F.Cu")):
        out.append(f'<g id="{gid}" class="cu">')
        for (n, w), ds in sorted(b["tracks"][layer].items(), key=lambda kv: (kv[0][0] or -1, kv[0][1])):
            na = f' data-n="{n}"' if n is not None else ""
            out.append(f'<path d="{"".join(ds)}" stroke-width="{f(w)}"{na}/>')
        out.append("</g>")
    out.append('<g id="L-pads">')
    for i, c in enumerate(b["comps"]):
        t = f' transform="translate({f(c["x"])} {f(c["y"])}) rotate({f(-c["rot"])})"'
        out.append(f'<g{t} data-c="{i}">' + "".join(pad_svg(p, i) for p in c["pads"]) + "</g>")
    for x, y, s, d, n in b["vias"]:
        na = f' data-n="{n}"' if n is not None else ""
        out.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(s / 2)}" class="via"{na}/>')
    out.append("</g>")
    out.append('<g id="L-holes">')
    for c in b["comps"]:
        for p in c["pads"]:
            if p["drill"]:
                hx, hy = rot(p["x"], p["y"], c["rot"])
                out.append(f'<circle cx="{f(c["x"] + hx)}" cy="{f(c["y"] + hy)}" r="{f(p["drill"] / 2)}"/>')
    for x, y, s, d, n in b["vias"]:
        out.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(d / 2)}"/>')
    out.append("</g>")
    out.append('<g id="L-silk">')
    for i, c in enumerate(b["comps"]):
        if c["outline"]:
            t = f'translate({f(c["x"])} {f(c["y"])}) rotate({f(-c["rot"])})'
            out.append(f'<path transform="{t}" d="{"".join(c["outline"])}" data-c="{i}"/>')
    out.append("</g>")
    out.append('<g id="L-sect">')
    out.append(f'<path d="{"".join(b["sect_lines"])}"/>')
    for text, x, y, size in b["sect_text"]:
        big = text.endswith("SECTION")
        cls = ' class="big"' if big else ""
        out.append(f'<g class="lb st" transform="translate({f(x)} {f(y)})"><text font-size="{f(3.2 if big else size)}"'
                   f'{cls}>{html.escape(text)}</text></g>')
    out.append("</g>")
    out.append('<g id="L-labels">' + "".join(label_svg(c) for c in b["comps"]) + "</g>")
    out.append('<g id="L-sel"></g>')
    out.append("</g></svg>")
    return "".join(out)


# ------------------------------------------------------------------ parts list

def natural(ref):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", ref)]


def parts_table(b):
    rows = []
    order = {k: i for i, (k, _) in enumerate(SECTIONS)}
    for i, c in sorted(enumerate(b["comps"]), key=lambda ic: (order[ic[1]["section"]], ic[1]["kind"] != "Integrated circuit",
                                                             ic[1]["kind"], natural(ic[1]["ref"]))):
        if c["kind"] == "Mounting hole":
            continue
        sec = dict(SECTIONS)[c["section"]]
        rows.append(f'<tr data-c="{i}" data-s="{c["section"]}"><td><button type="button" class="ref" data-c="{i}">'
                    f'{html.escape(c["ref"])}</button></td><td>{html.escape(c["value"])}</td>'
                    f'<td>{html.escape(c["desc"] if c["desc"] != c["value"] else c["kind"])}'
                    f'{"<span class=sub>" + html.escape(c["role"]) + "</span>" if c["role"] else ""}</td>'
                    f'<td class="sec">{sec}</td></tr>')
    return "".join(rows)


def summary(b):
    """Counts of the main parts by type."""
    count = defaultdict(list)
    for c in b["comps"]:
        if c["kind"] == "Integrated circuit":
            count[c["value"]].append(c["ref"])
    items = sorted(count.items(), key=lambda kv: (-len(kv[1]), kv[0]))
    return "".join(f'<li><b>{len(v)}</b><span>× {html.escape(TYPES.get(k, k))}</span></li>' for k, v in items)


def img(path):
    return "data:image/webp;base64," + base64.b64encode(Path(path).read_bytes()).decode()


def main():
    links = {"screenshots.html": "screenshots.html", "lisp.html": "lisp.html",
             "emulator.html": "emulator.html", "roms.html": "roms.html",
             "hardware_v2.html": "hardware_v2.html", "hardware_v3.html": "hardware_v3.html"}
    out = OUT
    if len(sys.argv) > 1:
        for line in Path(sys.argv[1]).read_text().splitlines():
            if line.strip():
                k, v = line.split()
                links[k] = v
        out = HERE.parent / "build" / "hardware_artifact.html"
        out.parent.mkdir(exist_ok=True)
    b = build()
    data = {
        "nets": b["nets"],
        "comps": [[c["ref"], c["value"], c["kind"], c["section"], [round(v, 2) for v in c["box"]],
                   c["desc"], c["role"], [[p["num"], p["net"]] for p in c["pads"]]] for c in b["comps"]],
        "sections": dict(SECTIONS),
        "board": [X0, Y0, W, H],
    }
    page = (TEMPLATE.replace("{{BOARD}}", board_svg(b))
            .replace("{{DATA}}", json.dumps(data, separators=(",", ":")))
            .replace("{{PARTS}}", parts_table(b))
            .replace("{{SUMMARY}}", summary(b))
            .replace("{{NPARTS}}", str(sum(1 for c in b["comps"] if c["kind"] != "Mounting hole")))
            .replace("{{IMG_LAYOUT}}", img(REPO / "info/pictures/kit-component-layout.webp"))
            .replace("{{IMG_ARTWORK}}", img(REPO / "info/pictures/kit-pcb-artwork.webp")))
    for k, v in links.items():
        page = page.replace(f'href="{k}', f'href="{v}')
    out.write_text(page)
    print(f"{out.name}: {len(page) // 1024} KB, {len(b['comps'])} parts, {len(b['nets'])} nets")


TEMPLATE = (HERE / "hardware_template.html").read_text() if (HERE / "hardware_template.html").exists() else ""

if __name__ == "__main__":
    main()
