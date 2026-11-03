#!/bin/sh
# Assemble COMP80 APL and build the 3 KB ROM: the monitor (0000-03FF, taken
# from psicomp80.rom) followed by APL (0400-0BFF) in place of BURP.
# Writes apl/apl.bin and psicomp80_apl.rom, and puts the ROM's CRC and
# SHA1 into psicomp80.cpp if it has an entry for it.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
cd "$HERE"
# z80asm still writes a binary after some errors, so stop on any message
if z80asm -o apl.bin --label=apl.lbl apl.asm 2>&1 | grep .; then exit 1; fi
python3 - "$REPO/psicomp80.rom" apl.bin "$REPO/psicomp80_apl.rom" "$REPO/psicomp80.cpp" <<'PY'
import re, sys, zlib, hashlib
mon, apl, out, driver = sys.argv[1:]
m = open(mon, "rb").read()[:0x400]
b = open(apl, "rb").read()
assert len(m) == 0x400 and len(b) == 0x800, (len(m), len(b))
rom = m + b
open(out, "wb").write(rom)
sums = f"CRC({zlib.crc32(rom) & 0xffffffff:08x}) SHA1({hashlib.sha1(rom).hexdigest()})"
src = open(driver).read()
new = re.sub(r'("psicomp80_apl\.rom", 0x0000, 0x0c00,\s*)CRC\(\w+\) SHA1\(\w+\)',
             lambda m: m.group(1) + sums, src)
if new != src:
    open(driver, "w").write(new)
print(f"{out}: {sums}")
PY
# CALLF finds the scalar functions by the low byte of their address: they
# must all be in one page, and so must the table.
python3 - apl.lbl <<'PY'
import re, sys
lab = {m[0]: int(m[1], 16) for m in re.findall(r"(\w+):\s+equ \$([0-9a-f]+)", open(sys.argv[1]).read())}
fs = [v for k, v in lab.items() if k.startswith("f_") or k == "fc1"]
assert len({v >> 8 for v in fs}) == 1, "the scalar functions cross a page"
assert lab["ftab"] >> 8 == (lab["ftab"] + 11) >> 8, "the table crosses a page"
PY
