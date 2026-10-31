#!/bin/sh
# Start the PSI COMP80 emulator straight into a program.
#   ./c80.sh life | boat | schmitt | alph | list | ready   [extra MAME options]
# life/boat/schmitt are copied into memory and run (no tape load needed).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
MAME=${MAME_DIR:-$HOME/localdev/mame}
prog=${1:-ready}; [ $# -gt 0 ] && shift

case "$prog" in
  life)    bin=$HERE/life/life.bin;        typed="RUN 1000" ;;
  boat)    bin=$HERE/pictures/boat.bin;    typed="RUN 1000" ;;
  schmitt) bin=$HERE/pictures/schmitt.bin; typed="RUN 1000" ;;
  alph)    bin=;                           typed="ALPH " ;;
  list)    bin=$HERE/life/life.bin;        typed="LIST 1000" ;;
  ready)   bin=;                           typed= ;;
  *) echo "usage: $0 life|boat|schmitt|alph|list|ready [MAME options]" >&2; exit 1 ;;
esac

cd "$MAME"
C80_BIN=$bin C80_TYPE=$typed exec ./mamed psicomp80 -autoboot_script "$HERE/start.lua" "$@"
