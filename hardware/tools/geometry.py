"""Pin and pad positions derived from board_data (shared by the SVG and KiCad generators).

All coordinates are frame px (125 px = 1 in, origin top-left, y down).
Kept to Python 3.9 so KiCad's bundled interpreter can import it.
"""
import math
import board_data as bd

P = bd.PX_PER_IN
PITCH = 0.1 * P
GRID = 0.05 * P


def snap(v, g=GRID):
    return round(v / g) * g


def ic_placement(ic):
    """Snapped centre, pin-row length and KiCad rotation (degrees, CCW) for an IC."""
    x0, y0, x1, y1 = ic["bbox"]
    n = ic["pins"]
    # put every pin on the 0.1 in grid: the centre sits half a pitch off the grid along
    # a row with an even number of pins, and across a 0.3 in wide package
    along = PITCH / 2 if (n // 2) % 2 == 0 else 0.0
    across = PITCH / 2 if round(ic["width"] * 10) % 2 else 0.0
    ox, oy = (along, across) if ic["notch"] in "LR" else (across, along)
    cx = snap((x0 + x1) / 2 - ox, PITCH) + ox
    cy = snap((y0 + y1) / 2 - oy, PITCH) + oy
    rot = {"T": 0, "L": 90, "B": 180, "R": 270}[ic["notch"]]
    return cx, cy, rot


def ic_pins(ic):
    """[(pin number, x, y)] with pin 1 next to the notch, numbered anticlockwise from above."""
    n, w = ic["pins"], ic["width"] * P
    cx, cy, rot = ic_placement(ic)
    half = n // 2
    L = (half - 1) * PITCH
    pins = []
    for k in range(half):
        # notch at top: pin 1 top-left, down the left side, back up the right side
        pins.append((k + 1, -w / 2, -L / 2 + k * PITCH))
        pins.append((half + k + 1, w / 2, L / 2 - k * PITCH))
    out = []
    a = math.radians(rot)
    for num, u, v in sorted(pins):
        # KiCad rotation is anticlockwise on screen with y pointing down
        x = u * math.cos(a) + v * math.sin(a)
        y = -u * math.sin(a) + v * math.cos(a)
        out.append((num, cx + x, cy + y))
    return out


def ic_body(ic):
    """Body rectangle (x0, y0, x1, y1) and the notch centre point."""
    n, w = ic["pins"], ic["width"] * P
    cx, cy, rot = ic_placement(ic)
    length = (n // 2) * PITCH
    width = w + 0.08 * P
    if ic["notch"] in "LR":
        x0, x1, y0, y1 = cx - length / 2, cx + length / 2, cy - width / 2, cy + width / 2
        notch = (x0, cy) if ic["notch"] == "L" else (x1, cy)
    else:
        x0, x1, y0, y1 = cx - width / 2, cx + width / 2, cy - length / 2, cy + length / 2
        notch = (cx, y0) if ic["notch"] == "T" else (cx, y1)
    return (x0, y0, x1, y1), notch


def two_lead_pads(part):
    """Pad positions for a two-lead part: at the ends of the drawn body (beyond them for
    the big wirewound resistors)."""
    ref, val, kind, x1, y1, x2, y2 = part
    dx, dy = x2 - x1, y2 - y1
    d = math.hypot(dx, dy) or 1
    ext = 0.06 * P if kind == "RW" else 0.0
    ux, uy = dx / d, dy / d
    return (x1 - ux * ext, y1 - uy * ext), (x2 + ux * ext, y2 + uy * ext)


def expansion_pins():
    e = bd.EXPANSION
    n = e["pins_per_row"]
    x0 = e["x"] - (n - 1) * PITCH / 2
    out = []
    for k in range(n):
        out.append((2 * k + 1, x0 + k * PITCH, e["y"] + PITCH / 2))
        out.append((2 * k + 2, x0 + k * PITCH, e["y"] - PITCH / 2))
    return out


def key_centre(k):
    (x1, y1), (x2, y2) = k["pad1"], k["pad2"]
    return (x1 + x2) / 2, (y1 + y2) / 2


def key_size(k):
    """Keycap outline size (w, h) in frame px."""
    if k["legend"] == "SPACE":
        return 4.6 * 0.72 * P, 0.34 * P
    if k["pad1"][0] < 200 and k["legend"] in ("RESET", "SHIFT"):   # squeezed pair, bottom left
        return 0.55 * P, 0.67 * P
    return 0.72 * P, 0.67 * P
