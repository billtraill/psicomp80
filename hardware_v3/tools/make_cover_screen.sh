#!/bin/sh
# Run the kit leaflet's "PSI COMP 80" picture (pictures/cover.bin) on the v2
# firmware's machine code and keep its screen, for the board's silkscreen
# (make_board.py draws it dot for dot). Writes ../pictures/cover_screen.hex.
set -e
cd "$(dirname "$0")/../.."
make -C hardware_v2/firmware/host session >/dev/null
printf 'RUN 1000\n#wait 3\n' > /tmp/comp80_cover_steps.txt
SCREEN=hardware_v3/pictures/cover_screen.hex LOAD=pictures/cover.bin@1000 NOWAIT=1 \
  hardware_v2/firmware/host/session psicomp80.rom /tmp/comp80_cover_steps.txt clock=4000000 > /dev/null
rm /tmp/comp80_cover_steps.txt
echo wrote hardware_v3/pictures/cover_screen.hex
