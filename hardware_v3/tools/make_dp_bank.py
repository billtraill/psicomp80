"""Write ../rtl/dp_transceivers.v: hamsternz's two-channel GTP bank
(DisplayPort_Verilog's src/artix7/transceiver_bank.v, MIT) widened to all four
GTP channels of the XC7A100T's quad, so any DisplayPort lane can go out on any
of the USB-C socket's four high-speed pairs.

  python3 make_dp_bank.py      (after tools/fetch.sh)

Channel 0 stays the master: its PLL controls and its output clock drive the
quad, as in the original, so it is powered whenever any channel is.
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE.parent / "build" / "DisplayPort_Verilog" / "src" / "artix7" / "transceiver_bank.v"
OUT = HERE.parent / "rtl" / "dp_transceivers.v"


def main():
    s = SRC.read_text()
    s = s.replace("./src/artix7/transceiver_bank.v : ",
                  "dp_transceivers.v : four GTP channels for DisplayPort over USB-C\n"
                  "//\n// Made by hardware_v3/tools/make_dp_bank.py from Mike Field's transceiver_bank.v\n"
                  "// (commit 3d509d4): the same quad set-up, with all four channels")
    s = s.replace("module transceiver_bank(", "module dp_transceivers(")
    for a, b in (("input   [1:0] powerup_channel,", "input   [3:0] powerup_channel,"),
                 ("output  [1:0] tx_running,", "output  [3:0] tx_running,"),
                 ("output  [1:0] gtptx_p,", "output  [3:0] gtptx_p,"),
                 ("output  [1:0] gtptx_n", "output  [3:0] gtptx_n"),
                 ("wire [1:0] txusrclk;", "wire [3:0] txusrclk;"),
                 ("wire [1:0] txusrclk2;", "wire [3:0] txusrclk2;"),
                 ("wire [1:0] tx_out_clk;", "wire [3:0] tx_out_clk;"),
                 ("wire [1:0] pll_pd;", "wire [3:0] pll_pd;"),
                 ("wire [1:0] pll_reset;", "wire [3:0] pll_reset;"),
                 ("wire [1:0] pll_locken;", "wire [3:0] pll_locken;")):
        assert a in s, a
        s = s.replace(a, b)
    # two more channels, copies of tx1
    i = s.index("transceiver tx1(")
    j = s.index("endmodule")
    tx1 = s[i:j]
    extra = ""
    for k in (2, 3):
        t = tx1.replace("transceiver tx1(", f"transceiver tx{k}(")
        t = t.replace("[1]", f"[{k}]").replace("tx_symbols[39:20]", f"tx_symbols[{20 * k + 19}:{20 * k}]")
        extra += t
    s = s[:j] + extra + s[j:]
    OUT.write_text(s)
    print("wrote", OUT.relative_to(HERE.parent))


if __name__ == "__main__":
    main()
