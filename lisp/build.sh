#!/bin/sh
# Assemble COMP80 LISP and build the 3 KB ROM: the monitor (0000-03FF, taken
# from psicomp80.rom) followed by LISP (0400-0BFF) in place of BURP.
# Writes lisp/lisp.bin and psicomp80_lisp.rom, and puts the ROM's CRC and
# SHA1 into psicomp80.cpp.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
cd "$HERE"
z80asm -o lisp.bin --label=lisp.lbl lisp.asm
python3 - "$REPO/psicomp80.rom" lisp.bin "$REPO/psicomp80_lisp.rom" "$REPO/psicomp80.cpp" <<'PY'
import re, sys, zlib, hashlib
mon, lisp, out, driver = sys.argv[1:]
m = open(mon, "rb").read()[:0x400]
f = open(lisp, "rb").read()
assert len(m) == 0x400 and len(f) == 0x800, (len(m), len(f))
rom = m + f
open(out, "wb").write(rom)
sums = f"CRC({zlib.crc32(rom) & 0xffffffff:08x}) SHA1({hashlib.sha1(rom).hexdigest()})"
src = open(driver).read()
src = re.sub(r'("psicomp80_lisp\.rom", 0x0000, 0x0c00,\s*)CRC\(\w+\) SHA1\(\w+\)',
             lambda m: m.group(1) + sums, src)
open(driver, "w").write(src)
print(f"{out}: {sums}")
PY
