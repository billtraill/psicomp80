#!/bin/sh
# Check the annotated ROM sources against the ROM images and make the web
# page of listings and hex dumps (../roms.html).
#   rom/psicomp80.asm    -> must assemble to ../psicomp80.rom (monitor + BURP)
#   ../forth/forth.asm   -> must give 0400-0BFF of ../psicomp80_forth.rom
#   ../lisp/lisp.asm     -> must give 0400-0BFF of ../psicomp80_lisp.rom
#   ../<lang>/<lang>.asm -> the same for basic, logo, chip8, focal, pilot, zasm,
#                           prolog, vtl, mouse, befunge, sheet, trac, pl0 and bf
# Every language ROM shares the monitor (0000-03FF) with psicomp80.rom.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
OUT=$HERE/build
mkdir -p "$OUT"

(cd "$HERE" && z80asm -o "$OUT/psicomp80.bin" -l"$OUT/psicomp80.lst" -L"$OUT/psicomp80.lbl" psicomp80.asm)
cmp "$OUT/psicomp80.bin" "$REPO/psicomp80.rom"
echo "psicomp80.asm: assembles to psicomp80.rom"

for lang in forth lisp basic logo chip8 focal pilot zasm prolog vtl mouse befunge sheet trac pl0 bf; do
  (cd "$REPO/$lang" && z80asm -o "$OUT/$lang.bin" -l"$OUT/$lang.lst" -L"$OUT/$lang.lbl" "$lang.asm")
  python3 - "$OUT/$lang.bin" "$REPO/psicomp80_$lang.rom" "$REPO/psicomp80.rom" <<'PY'
import sys
lang, rom, mon = (open(p, "rb").read() for p in sys.argv[1:])
assert rom[:0x400] == mon[:0x400], "monitor differs"
assert rom[0x400:] == lang, "language part differs"
PY
  echo "$lang/$lang.asm: assembles to 0400-0BFF of psicomp80_$lang.rom"
done

python3 "$HERE/make_page.py"
