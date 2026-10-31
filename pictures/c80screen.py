"""Build PSI COMP80 screen images (64x32 cells of 6x10 pixels).

Fonts are parsed from ../psicomp80.cpp so previews match the emulator.
Screen bytes: text = ASCII & 0x3F (bit6 clear), graphics = 0x40 | code.
"""
import re
from pathlib import Path
from PIL import Image, ImageDraw

COLS, ROWS, CW, CH = 64, 32, 6, 10
HERE = Path(__file__).resolve().parent


def _parse_fonts():
    src = (HERE.parent / "psicomp80.cpp").read_text()

    def table(name):
        body = src[src.index(name + " = {{"):]
        body = body[: body.index("}};")]
        rows = []
        for line in body.splitlines():
            line = line.split("//")[0]
            if "BLANK" in line:
                rows.append([0] * 8)
                continue
            m = re.search(r"\{([^{}]*)\}", line)
            if m:
                rows.append([int(v, 16) for v in m.group(1).split(",")])
        return rows

    return table("psicomp80_state::ascii_font_64x8x5"), table("psicomp80_state::gfx_font_64x10x6")


ASCII_FONT, GFX_FONT = _parse_fonts()


def glyph(byte):
    """Return the cell as 10 rows of 6-bit masks (bit5 = leftmost)."""
    code = byte & 0x3F
    if byte & 0x40:
        return [r & 0x3F for r in GFX_FONT[code]]
    idx = code ^ 0x20           # 00h-1Fh: @ A-Z [ \ ] ^ _
    return [(r & 0x1F) << 1 for r in ASCII_FONT[idx]] + [0, 0]


def text_byte(ch):
    return ord(ch.upper()) & 0x3F


class Screen:
    def __init__(self):
        self.cells = [[0x20] * COLS for _ in range(ROWS)]

    def text(self, row, col, s):
        for i, ch in enumerate(s):
            if 0 <= col + i < COLS:
                self.cells[row][col + i] = text_byte(ch)

    def gfx(self, row, col, code):
        self.cells[row][col] = 0x40 | code

    def from_bitmap(self, img, keep=None):
        """Pick the best-matching graphics glyph for every cell of a 384x320 1-bit image."""
        px = img.convert("1").load()
        for r in range(ROWS):
            for c in range(COLS):
                if keep and keep(r, c):
                    continue
                target = []
                for y in range(CH):
                    m = 0
                    for x in range(CW):
                        if px[c * CW + x, r * CH + y]:
                            m |= 1 << (5 - x)
                    target.append(m)
                if not any(target):
                    continue
                best, bestd = None, 99
                for code in range(64):
                    if code in (0x1C, 0x1D, 0x1E, 0x1F):  # BURP letters
                        continue
                    g = GFX_FONT[code]
                    d = sum(bin((g[y] & 0x3F) ^ target[y]).count("1") for y in range(CH))
                    if d < bestd:
                        best, bestd = code, d
                n_on = sum(bin(t).count("1") for t in target)
                if bestd < n_on:  # better than leaving it blank
                    self.cells[r][c] = 0x40 | best

    def bytes(self):
        return bytes(b for row in self.cells for b in row)

    def render(self, path, scale=2):
        im = Image.new("L", (COLS * CW, ROWS * CH))
        p = im.load()
        for r in range(ROWS):
            for c in range(COLS):
                for y, bits in enumerate(glyph(self.cells[r][c])):
                    for x in range(CW):
                        if bits & (1 << (5 - x)):
                            p[c * CW + x, r * CH + y] = 255
        # 4:3 display, like the TV in the article photos
        w = COLS * CW * scale
        im.resize((w, w * 3 // 4), Image.NEAREST).save(path)


def canvas():
    im = Image.new("1", (COLS * CW, ROWS * CH))
    return im, ImageDraw.Draw(im)
