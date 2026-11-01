"""Write ../src/data.c: the COMP80's two character fonts, read from the MAME
driver (../../../psicomp80.cpp) as web/build.py does, and the BURP ROM, built
in for when there's no card.

  python3 make_data.py
"""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]


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


def c_rows(rows):
    return ",\n".join("    {" + ", ".join(f"0x{v:02x}" for v in r) + "}" for r in rows)


def main():
    src = (REPO / "psicomp80.cpp").read_text()
    ascii_ = table(src, "psicomp80_state::ascii_font_64x8x5")
    gfx = table(src, "psicomp80_state::gfx_font_64x10x6")
    assert len(ascii_) == 64 and len(gfx) == 64
    rom = (REPO / "psicomp80.rom").read_bytes()
    assert len(rom) == 3072
    rom_c = ",\n".join("    " + ", ".join(f"0x{b:02x}" for b in rom[i:i + 16]) for i in range(0, len(rom), 16))
    out = f"""// Made by tools/make_data.py from psicomp80.cpp and psicomp80.rom; don't edit.
#include "data.h"

// 5-dot rows of the 64 ASCII characters 20-5F, 8 rows each (rows 8 and 9 are blank)
const uint8_t font_ascii[64][8] = {{
{c_rows(ascii_)}
}};

// 6-dot rows of the 64 graphics characters, 10 rows each
const uint8_t font_gfx[64][10] = {{
{c_rows(gfx)}
}};

// The monitor and BURP ROM, used when the card has no ROM
const uint8_t rom_burp[3072] = {{
{rom_c}
}};
"""
    (HERE.parent / "src" / "data.c").write_text(out)
    print("wrote src/data.c")


if __name__ == "__main__":
    main()
