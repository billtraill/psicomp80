#!/bin/sh
# Assemble COMP80 PL/0 and build the 3 KB ROM: the monitor (0000-03FF, taken
# from psicomp80.rom) followed by PL/0 (0400-0BFF) in place of BURP.
# Writes pl0/pl0.bin and psicomp80_pl0.rom, and puts the ROM's CRC and
# SHA1 into psicomp80.cpp if it has an entry for it.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
cd "$HERE"
# z80asm still writes a binary after some errors, so stop on any message
if z80asm -o pl0.bin --label=pl0.lbl pl0.asm 2>&1 | grep .; then exit 1; fi
python3 - "$REPO/psicomp80.rom" pl0.bin "$REPO/psicomp80_pl0.rom" "$REPO/psicomp80.cpp" <<'PY'
import re, sys, zlib, hashlib
mon, pl0, out, driver = sys.argv[1:]
m = open(mon, "rb").read()[:0x400]
b = open(pl0, "rb").read()
assert len(m) == 0x400 and len(b) == 0x800, (len(m), len(b))
rom = m + b
open(out, "wb").write(rom)
sums = f"CRC({zlib.crc32(rom) & 0xffffffff:08x}) SHA1({hashlib.sha1(rom).hexdigest()})"
src = open(driver).read()
new = re.sub(r'("psicomp80_pl0\.rom", 0x0000, 0x0c00,\s*)CRC\(\w+\) SHA1\(\w+\)',
             lambda m: m.group(1) + sums, src)
if new != src:
    open(driver, "w").write(new)
print(f"{out}: {sums}")
PY
