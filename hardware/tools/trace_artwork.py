"""Trace the two copper layers out of the PCB artwork photo.

  python3 trace_artwork.py            (needs numpy, opencv-python, Pillow and the potrace CLI)

Steps: perspective-correct info/pictures/kit-pcb-artwork.webp onto the 16 x 12 in board
frame, flatten the uneven lighting, split the red and blue ink by colour, then run
potrace on each mask. Writes artwork_traced.json (polygons in frame px, 125 px = 1 in),
which make_drawings.py and make_kicad.py read. The photo is only about 65 px per inch,
so the traced tracks are approximate: fine as a picture or a routing guide, not for
making a board.
"""
import json, os, subprocess, tempfile
import numpy as np, cv2
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PHOTO = os.path.join(HERE, "..", "..", "info", "pictures", "kit-pcb-artwork.webp")
OUT = os.path.join(HERE, "artwork_traced.json")

# Board crop-mark corners in the photo (TL, TR, BR, BL)
CORNERS = [[57, 107], [1025, 80], [1077, 837], [40, 870]]
SCALE = 2            # trace at 4000 x 3000 for smoother outlines
W, H = 2000 * SCALE, 1500 * SCALE


def rectify():
    im = cv2.cvtColor(np.array(Image.open(PHOTO).convert("RGB")), cv2.COLOR_RGB2BGR)
    M = cv2.getPerspectiveTransform(np.float32(CORNERS), np.float32([[0, 0], [W, 0], [W, H], [0, H]]))
    return cv2.warpPerspective(im, M, (W, H), flags=cv2.INTER_CUBIC)


def flatten(im):
    im = im.astype(np.float32)
    bg = np.stack([cv2.GaussianBlur(cv2.dilate(im[:, :, c], np.ones((61, 61))), (0, 0), 40)
                   for c in range(3)], 2)
    return np.clip(im / np.maximum(bg, 1) * 255, 0, 255).astype(np.uint8)


def masks(flat):
    f = cv2.bilateralFilter(flat, 9, 30, 5).astype(np.int16)
    B, G, R = f[:, :, 0], f[:, :, 1], f[:, :, 2]
    redness, blueness, light = R - (G + B) // 2, B - R, (R + G + B) // 3
    ink = light < 212
    black = (light < 95) & (redness < 35)
    red = ink & ~black & (redness > 28)
    blue = ink & ~black & ~red & (blueness > -14) & (redness < 14)

    def clean(m):
        m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        n, lab, st, _ = cv2.connectedComponentsWithStats(m, 8)
        keep = np.zeros(n, bool)
        keep[1:] = st[1:, cv2.CC_STAT_AREA] > 40
        return keep[lab]
    return {"red": clean(red), "blue": clean(blue)}


def trace(mask):
    with tempfile.TemporaryDirectory() as d:
        pbm, js = os.path.join(d, "m.pbm"), os.path.join(d, "m.json")
        Image.fromarray(~mask).convert("1").save(pbm)
        subprocess.run(["potrace", "-b", "geojson", "-t", "8", "-a", "1.0", "-O", "0.6", pbm, "-o", js], check=True)
        gj = json.load(open(js))
    polys = []
    for feat in gj["features"]:
        rings = []
        for ring in feat["geometry"]["coordinates"]:
            # potrace's origin is bottom-left; flip to top-left and scale to frame px
            pts = np.float32([[x / SCALE, (H - y) / SCALE] for x, y in ring])
            pts = cv2.approxPolyDP(pts.reshape(-1, 1, 2), 0.35, True).reshape(-1, 2)
            if len(pts) >= 3:
                rings.append([[round(float(x), 1), round(float(y), 1)] for x, y in pts])
        if not rings:
            continue
        polys.append(rings)
    return polys


if __name__ == "__main__":
    flat = flatten(rectify())
    out = {name: trace(m) for name, m in masks(flat).items()}
    json.dump(out, open(OUT, "w"), separators=(",", ":"))
    print(OUT, {k: len(v) for k, v in out.items()}, os.path.getsize(OUT), "bytes")
