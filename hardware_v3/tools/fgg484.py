"""Write fgg484.json: the XC7A100T-FGG484's balls and their names, from KiCad's
FPGA_Xilinx_Artix7 symbol library, for design.py.

  python3 fgg484.py
"""
import json, re
from pathlib import Path

LIB = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/FPGA_Xilinx_Artix7.kicad_sym"
s = Path(LIB).read_text()
i = s.index('\t(symbol "XC7A100T-FGG484"')
j = s.index('\n\t(symbol "', i + 10)
pins = re.findall(r'\(pin \w+ \w+\s*\(at[^)]*\)\s*\(length[^)]*\)\s*\(name "([^"]*)".*?\(number "([^"]*)"', s[i:j], re.S)
balls = {num: name for name, num in pins}
assert len(balls) == 484
Path(__file__).with_name("fgg484.json").write_text(json.dumps(balls, indent=0, sort_keys=True))
print(len(balls), "balls")
