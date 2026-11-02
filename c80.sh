#!/bin/sh
# Start the PSI COMP80 emulator straight into a program.
#   ./c80.sh [32k] life | boat | schmitt | cover | alph | list | disk | forth | forthlife | mandel |
#            forthsier | forthhilbert | forthhanoi | lisp | deriv | hanoi | queens | lispsier |
#            lisphilbert | ready
#            [extra MAME options]
# 32k runs the machine with the 32 KB memory expansion (psicomp80x), which the
# disc FORMAT command needs.
# life/boat/schmitt/cover are copied into memory and run (no tape load needed).
# disk loads the disc software at 1D00 with disk/programs.img in the drive.
# forth boots the FORTH ROM (FORTH in place of BURP) and enters FORTH;
# forthlife, mandel, forthsier, forthhilbert and forthhanoi also type in a FORTH program from forth/examples and
# run it.  lisp boots the LISP ROM and enters LISP; deriv, hanoi, queens,
# lispsier and lisphilbert
# also type in a LISP program from lisp/examples and run it.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
MAME=${MAME_DIR:-$HOME/localdev/mame}
machine=psicomp80
if [ "$1" = 32k ]; then machine=psicomp80x; shift; fi
prog=${1:-ready}; [ $# -gt 0 ] && shift
addr=1000
script=$HERE/start.lua
forth=
lisp=

case "$prog" in
  life)    bin=$HERE/life/life.bin;        typed="RUN 1000" ;;
  boat)    bin=$HERE/pictures/boat.bin;    typed="RUN 1000" ;;
  schmitt) bin=$HERE/pictures/schmitt.bin; typed="RUN 1000" ;;
  cover)   bin=$HERE/pictures/cover.bin;   typed="RUN 1000" ;;
  alph)    bin=;                           typed="ALPH " ;;
  list)    bin=$HERE/life/life.bin;        typed="LIST 1000" ;;
  disk)    bin=$HERE/disk/fdos.bin;        typed="RUN 1D00"; addr=1D00
           set -- -flop "$HERE/disk/programs.img" "$@" ;;
  forth)   bin=;                           typed=
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthlife) bin=; forth=$HERE/forth/examples/life.fs; typed="1000 LIFE"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  mandel)  bin=; forth=$HERE/forth/examples/mandel.fs; typed="MANDEL"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthsier) bin=; forth=$HERE/forth/examples/sier.fs; typed="SIER"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthhilbert) bin=; forth=$HERE/forth/examples/hilbert.fs; typed="HILBERT"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthhanoi) bin=; forth=$HERE/forth/examples/hanoi.fs; typed="6 HANOI"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  lisp)    bin=;                           typed=
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  deriv)   bin=; lisp=$HERE/lisp/examples/deriv.lsp
           typed="(DERIV '(+ (* 3 (EXPT X 2)) (* 2 X)) 'X)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  hanoi)   bin=; lisp=$HERE/lisp/examples/hanoi.lsp; typed="(HANOI 4 'A 'C 'B)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  queens)  bin=; lisp=$HERE/lisp/examples/queens.lsp; typed="(QUEENS 8)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  lispsier) bin=; lisp=$HERE/lisp/examples/sier.lsp; typed="(SIER)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  lisphilbert) bin=; lisp=$HERE/lisp/examples/hilbert.lsp; typed="(HILBERT)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  ready)   bin=;                           typed= ;;
  *) echo "usage: $0 [32k] life|boat|schmitt|cover|alph|list|disk|forth|forthlife|mandel|forthsier|forthhilbert|forthhanoi|lisp|deriv|hanoi|queens|lispsier|lisphilbert|ready [MAME options]" >&2; exit 1 ;;
esac

cd "$MAME"
C80_BIN=$bin C80_TYPE=$typed C80_ADDR=$addr C80_FORTH=$forth C80_LISP=$lisp exec ./mamed $machine -autoboot_script "$script" "$@"
