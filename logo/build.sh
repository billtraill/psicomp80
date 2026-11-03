#!/bin/sh
# Assemble COMP80 LOGO and build the 3 KB ROM: the monitor (0000-03FF, taken
# from psicomp80.rom) followed by LOGO (0400-0BFF) in place of BURP.
# Writes logo/logo.bin and psicomp80_logo.rom, and puts the ROM's CRC and
# SHA1 into psicomp80.cpp if it has an entry for it.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
cd "$HERE"
# z80asm still writes a .bin after some errors, so stop on any message
out=$(z80asm -o logo.bin --label=logo.lbl logo.asm 2>&1) || { echo "$out"; exit 1; }
[ -z "$out" ] || { echo "$out"; exit 1; }
python3 - "$REPO/psicomp80.rom" logo.bin "$REPO/psicomp80_logo.rom" "$REPO/psicomp80.cpp" <<'PY'
import re, sys, zlib, hashlib
mon, logo, out, driver = sys.argv[1:]
m = open(mon, "rb").read()[:0x400]
f = open(logo, "rb").read()
assert len(m) == 0x400 and len(f) == 0x800, (len(m), len(f))
rom = m + f
open(out, "wb").write(rom)
sums = f"CRC({zlib.crc32(rom) & 0xffffffff:08x}) SHA1({hashlib.sha1(rom).hexdigest()})"
src = open(driver).read()
new = re.sub(r'("psicomp80_logo\.rom", 0x0000, 0x0c00,\s*)CRC\(\w+\) SHA1\(\w+\)',
             lambda m: m.group(1) + sums, src)
if new != src:
    open(driver, "w").write(new)
print(f"{out}: {sums}")
PY
