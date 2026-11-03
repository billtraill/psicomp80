#!/bin/sh
# Assemble COMP80 BF and build the 3 KB ROM: the monitor (0000-03FF, taken
# from psicomp80.rom) followed by BF (0400-0BFF) in place of BURP.
# Writes bf/bf.bin and psicomp80_bf.rom.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
cd "$HERE"
z80asm -o bf.bin --label=bf.lbl bf.asm 2>&1 | tee asm.err
if [ -s asm.err ]; then rm -f asm.err; echo "z80asm reported errors" >&2; exit 1; fi
rm -f asm.err
python3 - "$REPO/psicomp80.rom" bf.bin "$REPO/psicomp80_bf.rom" "$REPO/psicomp80.cpp" <<'PY'
import re, sys, zlib, hashlib
mon, bf, out, driver = sys.argv[1:]
m = open(mon, "rb").read()[:0x400]
p = open(bf, "rb").read()
assert len(m) == 0x400 and len(p) == 0x800, (len(m), len(p))
rom = m + p
open(out, "wb").write(rom)
sums = f"CRC({zlib.crc32(rom) & 0xffffffff:08x}) SHA1({hashlib.sha1(rom).hexdigest()})"
src = open(driver).read()
new = re.sub(r'("psicomp80_bf\.rom", 0x0000, 0x0c00,\s*)CRC\(\w+\) SHA1\(\w+\)',
             lambda m: m.group(1) + sums, src)
if new != src:
    open(driver, "w").write(new)
print(f"{out}: {sums}")
PY
