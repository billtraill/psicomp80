#!/bin/sh
# Assemble COMP80 ZASM and build the 3 KB ROM: the monitor (0000-03FF, taken
# from psicomp80.rom) followed by ZASM (0400-0BFF) in place of BURP.
# Writes zasm/zasm.bin and psicomp80_zasm.rom.  z80asm writes a .bin even
# when there are errors, so any error stops the build here.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
cd "$HERE"
if z80asm -o zasm.bin --label=zasm.lbl zasm.asm 2>&1 | grep .; then
  echo "zasm.asm did not assemble" >&2; exit 1
fi
python3 - "$REPO/psicomp80.rom" zasm.bin "$REPO/psicomp80_zasm.rom" "$REPO/psicomp80.cpp" <<'PY'
import re, sys, zlib, hashlib
mon, lang, out, driver = sys.argv[1:]
m = open(mon, "rb").read()[:0x400]
f = open(lang, "rb").read()
assert len(m) == 0x400 and len(f) == 0x800, (len(m), len(f))
rom = m + f
open(out, "wb").write(rom)
sums = f"CRC({zlib.crc32(rom) & 0xffffffff:08x}) SHA1({hashlib.sha1(rom).hexdigest()})"
src = open(driver).read()
new = re.sub(r'("psicomp80_zasm\.rom", 0x0000, 0x0c00,\s*)CRC\(\w+\) SHA1\(\w+\)',
             lambda m: m.group(1) + sums, src)
if new != src:
    open(driver, "w").write(new)
print(f"{out}: {sums}")
PY
