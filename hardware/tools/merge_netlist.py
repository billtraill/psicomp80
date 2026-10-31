"""Merge the per-figure netlists into one board netlist and check it.

  python3 merge_netlist.py

Reads netlist/net_*.json (one per article figure, transcribed from the circuit diagrams;
see netlist/README.md), applies the cross-figure net aliases below, and writes
netlist/psicomp80_netlist.json:

  {"parts": {ref: {"value": ..., "figure": ..., "pins": {pin: net}}},
   "nets": {net: [[ref, pin], ...]}}

Prints a report of anything that needs a human: nets with a single connection, parts
that appear in more than one figure, and parts on the kit layout that no figure covers.
"""
import glob, json, os, sys
from collections import defaultdict

import board_data as bd

HERE = os.path.dirname(os.path.abspath(__file__))
NETDIR = os.path.join(HERE, "netlist")

# Same signal, different names in different figures: alias -> canonical name.
ALIASES = {
    "Z80_CLOCK_INPUT": "CLK_2MHZ",      # Fig. 2 "clock in" = Fig. 8 "to Z80 clock input"
    "MM57109_CLOCK": "MM57109_CLK",     # Fig. 2 IC6 pin 7 = Fig. 8 "to IC6 pin 7 clock"
    "-4V": "-4_5V",                     # MM57109 VDD: Fig. 2 says -4V, Fig. 16 makes about -4.4V
    "KBD_RESET_KEY": "RESET_N",         # the keyboard's RESET key is Fig. 2's reset switch
}

# Drawn in a figure but not built on this board:
#  J_KBD    - Fig. 18's keyboard plug; the kit has the encoder on the board itself
#  J_RESET  - Fig. 2's reset switch; on the kit it is the RESET key (SW43)
#  TTY_*    - Fig. 15 teleprinter interface; needs a second 4013 and parts the kit lacks
OFF_BOARD = {"J_KBD", "J_RESET", "J_TTY", "TTY_IC1", "TTY_R1", "TTY_R2", "TTY_R3", "TTY_R4",
             "TTY_TR1", "TTY_TR2"}


def load():
    parts, sources = {}, defaultdict(list)
    for path in sorted(glob.glob(os.path.join(NETDIR, "net_*.json"))):
        fig = json.load(open(path))
        name = os.path.basename(path)
        for p in fig["parts"]:
            ref = p["ref"]
            sources[ref].append(name)
            pins = {str(k): ALIASES.get(v, v) for k, v in p["pins"].items()}
            if ref in parts:
                # a part split across figures (e.g. gates of one IC): merge, report clashes
                for k, v in pins.items():
                    old = parts[ref]["pins"].get(k)
                    if old not in (None, "NC") and v != "NC" and old != v:
                        print(f"CLASH {ref} pin {k}: {old} ({parts[ref]['figure']}) vs {v} ({name})")
                    if old in (None, "NC"):
                        parts[ref]["pins"][k] = v
            else:
                parts[ref] = {"value": p.get("value", ""), "figure": name, "pins": pins}
    return parts, sources


def main():
    parts, sources = load()
    nets = defaultdict(list)
    for ref, p in parts.items():
        if ref in OFF_BOARD:
            continue
        for pin, net in p["pins"].items():
            if net and net != "NC":
                nets[net].append([ref, pin])
    out = {"parts": {r: p for r, p in parts.items() if r not in OFF_BOARD},
           "off_board": {r: p for r, p in parts.items() if r in OFF_BOARD},
           "nets": dict(sorted(nets.items()))}
    json.dump(out, open(os.path.join(NETDIR, "psicomp80_netlist.json"), "w"), indent=1)

    single = sorted(n for n, c in nets.items() if len(c) == 1)
    multi = {r: s for r, s in sources.items() if len(s) > 1}
    kit = {ic["ref"] for ic in bd.ics()}
    missing = sorted(kit - set(parts))
    print(f"{len(parts)} parts, {len(nets)} nets, {sum(len(c) for c in nets.values())} connections")
    print(f"single-connection nets ({len(single)}):", " ".join(single))
    print("parts in several figures:", multi)
    print("kit ICs not in any figure:", " ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
