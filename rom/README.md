# ROM listings

`psicomp80.asm` is the annotated disassembly of the original ROM,
`../psicomp80.rom`: the monitor (0000-03FF) and BURP (0400-0BFF). It
assembles with z80asm back to the ROM byte for byte. Each line's comment
starts with the address and bytes, as in the magazine's hex listing; branch
targets without a name are labelled `L<address>`. Edit this file to improve
the annotations.

The FORTH and LISP ROMs share the monitor and have their own sources:
`../forth/forth.asm` and `../lisp/lisp.asm`.

    sh rom/build.sh

checks that each source assembles to its ROM (all three ROMs must also share
the monitor), writes listings to `rom/build/`, and runs `make_page.py`, which
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
