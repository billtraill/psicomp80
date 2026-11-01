#!/bin/sh
# Synthesise the design with yosys for the XC7A100T, to check it builds and
# fits (Vivado does the real build: see ../VIVADO_TODO.md). Writes
# ../build/synth/utilisation.txt.
set -e
cd "$(dirname "$0")/.."
sh tools/fetch.sh >/dev/null
mkdir -p build/synth && cd build/synth
ln -sf ../../rtl/font.hex font.hex
ln -sf ../../firmware/firmware.hex firmware.hex
cp ../usb_hid_host/src/usb_hid_host_rom.hex .
yosys -q -l synth.log ../../tools/synth.ys
grep -A60 "design hierarchy" utilisation.txt | grep -E "LUT|FD|RAMB|CARRY|OSERDES|MMCM|PLLE"
