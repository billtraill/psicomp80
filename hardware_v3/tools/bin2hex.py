"""bin2hex.py in.bin out.hex words: a binary as little-endian 32-bit words, one
per line, padded with zeros to `words` lines, for Verilog's $readmemh."""
import sys

data = open(sys.argv[1], "rb").read()
words = int(sys.argv[3])
data += b"\0" * (-len(data) % 4)
assert len(data) // 4 <= words, f"{len(data)} bytes won't fit in {words * 4}"
lines = [f"{int.from_bytes(data[i:i + 4], 'little'):08x}" for i in range(0, len(data), 4)]
lines += ["00000000"] * (words - len(lines))
open(sys.argv[2], "w").write("\n".join(lines) + "\n")
print(f"{sys.argv[2]}: {len(data)} of {words * 4} bytes")
