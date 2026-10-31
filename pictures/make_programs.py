"""Write each picture as a COMP80 program image: loader at $1000, screen at $1010."""
import boat
import cover
import schmitt

BASE = 0x1000
LOADER = bytes([
    0x21, 0x10, 0x10,   # LD HL,$1010   screen image
    0x11, 0x00, 0x80,   # LD DE,$8000   video RAM
    0x01, 0x00, 0x08,   # LD BC,$0800   64 x 32 cells
    0xED, 0xB0,         # LDIR
    0x18, 0xFE,         # JR $          wait; any key returns to the monitor
]).ljust(0x10, b"\x00")

for name, mod in (("schmitt", schmitt), ("boat", boat), ("cover", cover)):
    s = mod.build()
    s.render(f"{name}_preview.png")
    data = LOADER + s.bytes()
    open(f"{name}.bin", "wb").write(data)
    print(f"{name}.bin: {len(data)} bytes, TAPE {BASE:04X}{BASE + len(data):04X}")
