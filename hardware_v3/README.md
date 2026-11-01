# COMP80 v3: the COMP80 in an Artix-7 FPGA

The COMP80 built again in logic, in an AMD Artix-7 XC7A100T. A Verilog Z80 and its
64 KB of memory, the I/O ports, the keyboard latch and NMI, and the display are all
logic. A PicoRV32 RISC-V soft processor in the same FPGA reads the microSD card,
models the MM57109 and the cassette, and turns USB keyboard reports into key codes.
The outside is the same as v2: HDMI, USB keyboard, microSD and USB-C power. The web
page is `../hardware_v3.html`.

**Vivado hasn't been run yet**: see `VIVADO_TODO.md` for picking it up on another
machine.

| Folder | What's in it |
|---|---|
| `rtl/` | The logic: `top.v`, `comp80_machine.v` (the COMP80), `tv80c.v` (TV80 with a clock enable), `video.v`, `hdmi_out.v`, `soc.v` (PicoRV32 and its registers), `spi_master.v`, `font.hex`, and `comp80v3.xdc` (pins, made by `tools/design.py`) |
| `firmware/` | The soft processor's firmware: `main.c`, `sd_spi.c`, `hw.h`, plus v2's `mm57109.c`, `tape.c` and `storage.c`. `firmware.hex` is the built RAM image |
| `sim/` | Verilator and Icarus Verilog testbenches |
| `vivado/build.tcl` | The Vivado build: bitstream and flash image |
| `tools/` | `design.py` (the board), `make_board.py` (KiCad), `fetch.sh` (outside HDL), `synth.sh` (yosys), `make_font.py`, `make_page.py` |
| `kicad/` | The KiCad 10 board: six layers, routed and filled. KiCad's DRC: no errors |
| `netlist.json`, `bom.csv` | The connections and the parts list |

Outside HDL, fetched into `build/` by `tools/fetch.sh` at fixed commits: TV80 (MIT),
PicoRV32 (ISC), usb_hid_host (Apache-2.0), and FatFs for the firmware.

## Tests

```bash
cd hardware_v3/sim && make test
```

This runs LISP, FORTH and BURP sessions on the logic and on v2's C core and compares
the screens: they match. It takes about a minute each.

```bash
cd hardware_v3/sim && make boot
```

This boots the soft processor's firmware with the machine. It prints `COMP80 v3`,
loads the built-in ROM and reaches READY.

```bash
cd hardware_v3/sim && iverilog -g2012 -DSIM -o video_tb video_tb.v ../rtl/video.v ../rtl/hdmi_out.v && vvp video_tb +screen=screen.hex
```

This draws one HDMI frame from a 2 KB screen dump (v2's `host/session` writes one
with `SCREEN=file`) and checks every TMDS symbol.

```bash
sh hardware_v3/tools/synth.sh
```

This runs yosys for the XC7A100T. The design comes to about 4,100 LUTs, 2,240
flip-flops and 49 block RAMs.

## The board

100 × 72 mm, six layers: signals outside, then ground, 3.3 V, 1.0 V and 1.8 V planes.
The XC7A100T in FGG484, a 16 MB SPI flash for its configuration, a 100 MHz
oscillator, and three TLV62569 bucks (1.0, 1.8, 3.3 V) from USB-C. It has HDMI
straight from TMDS_33 outputs, a USB-A socket for the keyboard, microSD, a 6-pin
JTAG header, a serial header, RESET and PROG buttons, and HALT and DONE LEDs.

```bash
cd hardware_v3/tools && python3 design.py
```

```bash
cd hardware_v3/tools && /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 make_board.py
```

```bash
cd hardware/tools && /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 route_board.py --pcb ../../hardware_v3/kicad/comp80v3.kicad_pcb --freerouting freerouting-2.5.0.jar --java /opt/homebrew/opt/openjdk/bin/java --passes 60
```

Freerouting leaves one HDMI line. Finish it with the grid router at v3's clearances:

```bash
cd hardware/tools && GRID=0.05 CLEAR=0.15 TRACK=0.15 /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 finish_routes.py --pcb ../../hardware_v3/kicad/comp80v3.kicad_pcb TMDS_D2N
```

## Firmware

```bash
cd hardware_v3/firmware && make
```

This needs a RISC-V GCC (xPack `riscv-none-elf-gcc` 15) and `build/fatfs`. It writes
`firmware.hex`, which goes into the bitstream as the soft processor's RAM contents.
