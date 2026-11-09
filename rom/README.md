# ROM listings

`psicomp80.asm` is the annotated disassembly of the original ROM,
`../psicomp80.rom`: the monitor (0000-03FF) and BURP (0400-0BFF). It
assembles with z80asm back to the ROM byte for byte. Each line's comment
starts with the address and bytes, as in the magazine's hex listing; branch
targets without a name are labelled `L<address>`. Edit this file to improve
the annotations.

`psicomp80.asm` assembles after one of two one-line files. After
`monitor_original.asm` it gives the original ROM; after `monitor_keysafe.asm`
it gives the key-safe monitor (with BURP), whose keyboard handler at 0066
ignores a key that comes while the CPU is not in a HALT, where the original
restarts the monitor. The handler keeps the program's A and flags with PUSH AF
until it has checked for the HALT, reads and drops the key, and returns with
every register as it was. It needs ten more bytes, so the code at 0095-012F
moves up by ten into the free bytes that were at 0130; the one jump into it
(004B) and BURP's one call (0915) are assembled to match, and nothing a
language uses (03xx) moves. The halted path leaves the stack as the original
does, so programs that keep SP in ROM (Storm, the memory dump) still work.

The FORTH and LISP ROMs share the monitor and have their own sources:
`../forth/forth.asm` and `../lisp/lisp.asm`.

    sh rom/build.sh

checks that each source assembles to its ROM (all three ROMs must also share
the monitor), writes listings to `rom/build/`, assembles the key-safe monitor
and writes `../psicomp80_ks.rom` and `../psicomp80_<lang>_ks.rom` from it and
each language ROM (`tools/keysafe_roms.py`, which also adds and updates their
`<name>ks` BIOS entries in `../psicomp80.cpp`; run `build.sh` again after
rebuilding a language), and runs `make_page.py`, which
makes `../roms.html`: the four listings (monitor, BURP, FORTH, LISP) with every
label and jump target a link, and hex dumps of the three ROMs with their CRC
and SHA1. The page takes each line's text from the source, its address from
the assembler listing and its bytes from the ROM image.

`tools/make_rom_asm.py` made `psicomp80.asm` from the earlier disassemblies,
now in `../old/` (`comp80_monitor_plus_burp_0000_0BFF_annotated.asm`,
`burp_disassembly_0400_0BFF.md` and its path map). It decoded the ROM afresh
and took the names, comments and code/data boundaries from them, fixing places
where they disagreed with the bytes (instructions left as DB, instructions
split across lines, the WRITE/PRINT keyword table at 07A2 decoded as code). It
is kept as a record; it would overwrite the hand edits if run again.
