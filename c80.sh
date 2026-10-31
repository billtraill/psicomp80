#!/bin/sh
# Start the PSI COMP80 emulator straight into a program.
#   ./c80.sh life | boat | schmitt | alph | list | disk | ready   [extra MAME options]
# life/boat/schmitt are copied into memory and run (no tape load needed).
# disk loads the disc software at 1D00 with disk/programs.img in the drive.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
MAME=${MAME_DIR:-$HOME/localdev/mame}
prog=${1:-ready}; [ $# -gt 0 ] && shift
addr=1000

case "$prog" in
  life)    bin=$HERE/life/life.bin;        typed="RUN 1000" ;;
  boat)    bin=$HERE/pictures/boat.bin;    typed="RUN 1000" ;;
  schmitt) bin=$HERE/pictures/schmitt.bin; typed="RUN 1000" ;;
  alph)    bin=;                           typed="ALPH " ;;
  list)    bin=$HERE/life/life.bin;        typed="LIST 1000" ;;
  disk)    bin=$HERE/disk/fdos.bin;        typed="RUN 1D00"; addr=1D00
           set -- -flop "$HERE/disk/programs.img" "$@" ;;
  ready)   bin=;                           typed= ;;
  *) echo "usage: $0 life|boat|schmitt|alph|list|disk|ready [MAME options]" >&2; exit 1 ;;
esac

cd "$MAME"
C80_BIN=$bin C80_TYPE=$typed C80_ADDR=$addr exec ./mamed psicomp80 -autoboot_script "$HERE/start.lua" "$@"
