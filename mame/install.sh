#!/bin/sh
# Copy the psicomp80 driver, ROMs and local config into a MAME checkout.
# Usage: mame/install.sh [path-to-mame]   (default ~/localdev/mame)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
MAME=${1:-$HOME/localdev/mame}

mkdir -p "$MAME/src/mame/drivers" "$MAME/roms/psicomp80"
cp "$REPO/psicomp80.cpp" "$MAME/src/mame/drivers/psicomp80.cpp"
cp "$REPO/psicomp80.rom" "$REPO/psicomp80_forth.rom" "$MAME/roms/psicomp80/"
cp "$HERE/build.sh" "$HERE/run.sh" "$HERE/mame.ini" "$MAME/"

if ! grep -q "@source:drivers/psicomp80.cpp" "$MAME/src/mame/mame.lst"; then
  (cd "$MAME" && git apply "$HERE/mame.lst.patch")
fi
echo "Installed into $MAME; now run ./build.sh there."
