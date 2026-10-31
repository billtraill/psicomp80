# MAME-side files

Local changes that live in the MAME checkout (`~/localdev/mame`, a clone of
https://github.com/mamedev/mame), kept here so they're backed up.

| File | Goes to | Purpose |
|---|---|---|
| `mame.lst.patch` | `src/mame/mame.lst` | registers the `psicomp80` system |
| `build.sh` | MAME root | debug build of just this driver |
| `run.sh` | MAME root | run under the debugger |
| `mame.ini` | MAME root | start windowed with MAME's menu keys on |
| `BUILD.md` | — | full build notes (SDL2, regenerating project files) |

`install.sh` copies all of these, plus `../psicomp80.cpp`, `../psicomp80.rom`,
`../psicomp80_forth.rom` and `../psicomp80_lisp.rom`, into the checkout:

    mame/install.sh              # default ~/localdev/mame
    mame/install.sh /path/to/mame

then build with `./build.sh` in the MAME directory.

If the checkout moves, the generated build files still hold the old path: run
the build once with `REGENIE=1`, and fix any old paths left in the `.d`
dependency files under `build/`.
