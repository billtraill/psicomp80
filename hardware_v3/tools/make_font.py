"""Write ../rtl/font.hex for video.v: the COMP80's character sets from the MAME
driver's tables (../../psicomp80.cpp), read as web/build.py reads them.

  python3 make_font.py

2048 lines, one per {graphics bit, 6-bit code, row 0-15}: the row's six dots,
bit 5 leftmost.  ASCII characters use rows 0-7 (their 5 dots in bits 4-0 of
the table, moved one left so the gap is on the right); graphics use rows 0-9.
"""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]


def table(src, name):
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


def main():
    src = (REPO / "psicomp80.cpp").read_text()
    ascii_ = table(src, "psicomp80_state::ascii_font_64x8x5")
    gfx = table(src, "psicomp80_state::gfx_font_64x10x6")
    out = []
    for g in (0, 1):
        for code in range(64):
            for row in range(16):
                if g:
                    v = gfx[code][row] & 0x3f if row < 10 else 0
                else:
                    v = (ascii_[code ^ 0x20][row] & 0x1f) << 1 if row < 8 else 0
                out.append(f"{v:02x}")
    (HERE.parent / "rtl" / "font.hex").write_text("\n".join(out) + "\n")
    print("wrote rtl/font.hex")


if __name__ == "__main__":
    main()
