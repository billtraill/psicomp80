#!/usr/bin/env python3
"""Write the key-safe ROMs and give MAME a BIOS for each.

rom/build.sh assembles rom/monitor_keysafe.asm + rom/psicomp80.asm to
rom/build/psicomp80_ks.bin: the key-safe monitor with BURP.  From it this
writes

  psicomp80_ks.rom          key-safe monitor + BURP, as assembled (BURP calls
                            a monitor routine that the key-safe monitor moves)
  psicomp80_<lang>_ks.rom   key-safe monitor + the language part of
                            psicomp80_<lang>.rom, for every language ROM

and, in psicomp80.cpp, adds after each original BIOS a "<name>ks" BIOS for
the key-safe ROM (once) and keeps all of their CRCs and SHA1s up to date.
"""
import hashlib
import re
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BUILD = REPO / "rom" / "build"


def sums(rom):
    return f"CRC({zlib.crc32(rom) & 0xffffffff:08x}) SHA1({hashlib.sha1(rom).hexdigest()})"


def main():
    ks = (BUILD / "psicomp80_ks.bin").read_bytes()
    orig = (REPO / "psicomp80.rom").read_bytes()
    assert len(ks) == 0xC00
    # the key-safe monitor only changes 0066-0139, and the JR at 004B into the code it moves
    changed = [a for a in range(0x400) if ks[a] != orig[a]]
    assert all(a == 0x4C or 0x66 <= a < 0x13A for a in changed), "key-safe monitor changes too much"

    driver = REPO / "psicomp80.cpp"
    src = driver.read_text()
    # each original BIOS: ROM_SYSTEM_BIOS(n, "name", "Monitor + X") / ROMX_LOAD("file", ...)
    entry = re.compile(r'ROM_SYSTEM_BIOS\((\d+), "(\w+)", "Monitor \+ ([^"]*)"\)\n'
                       r'ROMX_LOAD\("(psicomp80(?:_(\w+))?)\.rom", 0x0000, 0x0c00,\n'
                       r'\s*CRC\(\w+\) SHA1\(\w+\), ROM_BIOS\(\d+\)\)\n')
    roms = {}
    for m in entry.finditer(src):
        stem = m.group(4)
        roms[stem] = (m.group(2), m.group(3))
    assert len(roms) == 21, len(roms)
    for stem in roms:
        rom = ks if stem == "psicomp80" else ks[:0x400] + (REPO / f"{stem}.rom").read_bytes()[0x400:]
        (REPO / f"{stem}_ks.rom").write_bytes(rom)
        roms[stem] += (sums(rom),)

    # add the key-safe BIOSes to each ROM set that lacks them, after its originals
    def add_ks(m):
        block = m.group(0)
        if '_ks.rom"' in block:
            return block
        n = len(entry.findall(block))
        lines = []
        for i, (stem, (name, title, s)) in enumerate(roms.items()):
            lines.append(f'// Key-safe monitor (rom/monitor_keysafe.asm) + {title}: a key that comes\n'
                         f'// while a program runs is ignored instead of restarting the monitor\n'
                         f'ROM_SYSTEM_BIOS({n + i}, "{name}ks", "Key-safe monitor + {title}")\n'
                         f'ROMX_LOAD("{stem}_ks.rom", 0x0000, 0x0c00,\n'
                         f'         {s}, ROM_BIOS({n + i}))\n')
        return block.replace("ROM_END", "".join(lines) + "ROM_END")
    new = re.sub(r"ROM_START\(\w+\).*?ROM_END", add_ks, src, flags=re.S)
    # and keep their checksums current
    for stem, (name, title, s) in roms.items():
        new = re.sub(rf'("{stem}_ks\.rom", 0x0000, 0x0c00,\s*)CRC\(\w+\) SHA1\(\w+\)',
                     lambda m: m.group(1) + s, new)
    if new != src:
        driver.write_text(new)
    print(f"wrote {len(roms)} key-safe ROMs; monitor {sums(ks[:0x400])}")


if __name__ == "__main__":
    sys.exit(main())
