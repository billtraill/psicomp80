"""Decode dp_tb.v's symbols back into the 800 x 600 picture and check it
against what the screen should look like (12 x 18 pixel cells, the font from
../rtl/font.hex, colour 33 FF 66). Writes dp_frame.png.

  python3 dp_decode.py screen.hex
"""
import sys
from PIL import Image

BE, BS, FS, FE = 0x1FB, 0x1BC, 0x1FE, 0x1F7
syms = []
for line in open("dp_symbols.txt"):
    v = int(line, 16)
    syms += [v & 0x1FF, v >> 9]

lines, cur, active, fill = [], None, False, False
for s in syms:
    if s == BE:
        cur, active, fill = [], True, False
    elif s == BS:
        if active and cur is not None:
            lines.append(cur)
        active = False
    elif active:
        if s == FS:
            fill = True
        elif s == FE:
            fill = False
        elif not fill and not s & 0x100:
            cur.append(s)
# the first run of 600 full lines is a frame
full = [len(l) == 2400 for l in lines]
start = next(i for i in range(len(lines) - 599) if all(full[i:i + 600]))
frame = lines[start:start + 600]

font = [int(x, 16) for x in open("../rtl/font.hex")]
screen = [int(x, 16) for x in open(sys.argv[1])]
ROWH = [2, 2, 2, 2, 1, 2, 2, 2, 2, 1]
ROWMAP = [r for r, h in enumerate(ROWH) for _ in range(h)]
img = Image.new("RGB", (800, 600))
bad = 0
for y in range(600):
    for x in range(800):
        r, g, b = frame[y][3 * x:3 * x + 3]
        img.putpixel((x, y), (r, g, b))
        lit = False
        if 16 <= x < 784 and 12 <= y < 588:
            col, row = (x - 16) // 12, (y - 12) // 18
            v = screen[row * 64 + col]
            bits = font[((v >> 6) & 1) << 10 | (v & 0x3F) << 4 | ROWMAP[(y - 12) % 18]]
            lit = bool(bits & (0x20 >> ((x - 16) % 12 // 2)))
        want = (0x33, 0xFF, 0x66) if lit else (0, 0, 0)
        bad += (r, g, b) != want
img.save("dp_frame.png")
print(f"{len(lines)} lines decoded; frame from line {start}; {bad} pixels differ from the expected picture")
