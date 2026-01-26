import re, sys, pathlib

infile = "ROM_listing_fixedup.txt"
outfile = "psicomp80.rom"

text = pathlib.Path(infile).read_text(errors="ignore")

# Remove address prefixes at start of lines like "0000 " or "03A0 "
text = re.sub(r'(?m)^\s*[0-9A-Fa-f]{4}\s+', '', text)

# Extract all 2-hex-digit tokens
tokens = re.findall(r'\b[0-9A-Fa-f]{2}\b', text)
data = bytes(int(t, 16) for t in tokens)

pathlib.Path(outfile).write_bytes(data)
print(f"Wrote {len(data)} bytes to {outfile}")