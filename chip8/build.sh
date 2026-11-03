#!/bin/sh
# Assemble COMP80 CHIP-8 and build the 3 KB ROM: the monitor (0000-03FF, taken
# from psicomp80.rom) followed by the interpreter (0400-0BFF) in place of
# BURP.  Writes chip8/chip8.bin and psicomp80_chip8.rom, and assembles the
# example programs in chip8/examples.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
cd "$HERE"
rm -f chip8.bin
z80asm -o chip8.bin --label=chip8.lbl chip8.asm 2>&1 | tee /dev/stderr | grep -q . && { echo "z80asm reported errors" >&2; exit 1; }
python3 - "$REPO/psicomp80.rom" chip8.bin "$REPO/psicomp80_chip8.rom" "$REPO/psicomp80.cpp" <<'PY'
import re, sys, zlib, hashlib
mon, lang, out, driver = sys.argv[1:]
m = open(mon, "rb").read()[:0x400]
f = open(lang, "rb").read()
assert len(m) == 0x400 and len(f) == 0x800, (len(m), len(f))
rom = m + f
open(out, "wb").write(rom)
sums = f"CRC({zlib.crc32(rom) & 0xffffffff:08x}) SHA1({hashlib.sha1(rom).hexdigest()})"
src = open(driver).read()
new = re.sub(r'("psicomp80_chip8\.rom", 0x0000, 0x0c00,\s*)CRC\(\w+\) SHA1\(\w+\)',
             lambda m: m.group(1) + sums, src)
if new != src:
    open(driver, "w").write(new)
print(f"{out}: {sums}")
PY
for f in examples/*.c8; do
  [ -e "$f" ] && python3 tools/c8asm.py "$f" "${f%.c8}.ch8"
done
exit 0
