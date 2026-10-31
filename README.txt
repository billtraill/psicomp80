PSI COMP80 – MAME skeleton driver (WIP)

Files in this folder:
  - psicomp80.cpp      : MAME driver source (drop into src/mame/drivers/psicomp80.cpp or similar)
  - psicomp80.rom      : Raw 3 KiB ROM image

Quick build/run (macOS):

1) Get MAME source (example):
   git clone https://github.com/mamedev/mame.git
   cd mame

2) Copy driver file into tree, e.g.:

   This is assuming you are in the psicomp80 dir and the mame is one up ...

   cp psicomp80.cpp ../mame/src/mame/drivers/psicomp80.cpp
  

3) Build ONLY this driver (fast iteration):
```
make DEBUG=1 SYMBOLS=1 OPTIMIZE=0 \
  SOURCES=src/mame/drivers/psicomp80.cpp \
  OSD=sdl \
  USE_LIBSDL=1 \
  SDL_INSTALL_ROOT=/opt/homebrew \
  -j$(sysctl -n hw.ncpu)
```

4) Put the ROM zip where MAME looks for ROMs:
   mkdir -p roms/psicomp80
   cp psicomp80.rom ../mame/roms/psicomp80/

5) Run with debugger:
   ./psicomp80emu psicomp80 -debug

Useful debugger commands:
   bpset 38           ; break on IM1 interrupt handler entry
   wpset 8000,800,w   ; watch VRAM writes (0x800 bytes at 0x8000)


Make the ROM

```
python convert_to_rom.py
```

Get the checksum for the ROM
```
python calc_rom_crc.py
```

Remember to add the checksum to the psicomp80.cpp file.


Rechecked the 1st page of hex dump, looks OK apart from maybe 1 ambigious byte on the line 03B0 there is a byte that looks like FG that I've interpreted as FC.


Rememeber to copy the ROM to 
```
mame/roms/psicom80/psicomp80.rom
```
and copy the psicomp80.cpp file to 
```
mame/src/mame/drivers/psicomp80.cpp
```

There is a mame/build.sh and mame/run.sh files to run the emulator.

/h2 Tapes

Each tape loads at 1000 and runs with RUN 1000. autorun.lua loads the mounted
tape (fast-forwarded), checks it against the .bin next to the .wav, retries if
the load went wrong, and types RUN 1000. Don't touch the keyboard until the
program starts. Run from anywhere:

Game of Life
```
cd ~/localdev/mame && ./mamed psicomp80 -cass ~/localdev/psicomp80/life/life.wav -autoboot_script ~/localdev/psicomp80/autorun.lua
```
Keys: R = new random board, P = pause / resume (shows PAUSED), S = stop and
go back to the monitor. Other keys are ignored. See life/README.md.

Fig. 22(b) sailing boat
```
cd ~/localdev/mame && ./mamed psicomp80 -cass ~/localdev/psicomp80/pictures/boat.wav -autoboot_script ~/localdev/psicomp80/autorun.lua
```

Fig. 22(a) Schmitt trigger circuit
```
cd ~/localdev/mame && ./mamed psicomp80 -cass ~/localdev/psicomp80/pictures/schmitt.wav -autoboot_script ~/localdev/psicomp80/autorun.lua
```
For the pictures, press any key to go back to the monitor.

To load a tape by hand instead: type READ 1000, then Tab -> Tape Control ->
Play (Tab again to close the menu), wait for the tape to stop, press any key,
then type RUN 1000.

/h2 Things to Try

/h3 Guessing game
At address 01B6 in the ROM is a guessing game. It can be run by
```
RUN 01B6
```

/h3 

/h2 TODO

- Since `RUN 01B6` does something but `LIST 1000` just resets. Debug from where it reads 01B6 to see where it came from, so that I can figure out how the command line is parsed.
- Return key seems a bit funny as it can take several attempts to do `RUN 01B6` which is odd and the program does not seem to work properly.
- Check out the other Monitor commands.
- Add documentation about the monitor commands
- Try and dump. dissasseble the ROM and add comments. Might make debugging easier.
- Add this to a git repository.