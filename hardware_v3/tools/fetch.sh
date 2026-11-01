#!/bin/sh
# Fetch the outside HDL into ../build: the TV80 Z80 (MIT), PicoRV32 (ISC) and
# usb_hid_host (Apache-2.0), DisplayPort_Verilog (MIT), and FatFs for the
# firmware, at the commits the design was made with.
set -e
cd "$(dirname "$0")/../build"
get() {   # dir url commit
  [ -d "$1" ] || git clone -q "$2" "$1"
  git -C "$1" checkout -q "$3"
}
get tv80 https://github.com/hutch31/tv80.git 66a131c38d05ef58b3d8c4f1507a72e6e4aa5d65
get picorv32 https://github.com/YosysHQ/picorv32.git ef203c2b0a3fb793280f5114941416c425c5b461
get usb_hid_host https://github.com/nand2mario/usb_hid_host.git 678b0137bd32d1ca99fb2d48865f4eb1df712c4e
get fatfs https://github.com/abbrev/fatfs.git ab992fcf2926b8a1ee3f0a8f9cefb6584174100d
get DisplayPort_Verilog https://github.com/hamsternz/DisplayPort_Verilog.git 3d509d41c07a151704f3e7135a032d16d9b6a0b1
echo fetched
