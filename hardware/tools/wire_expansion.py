"""Put the expansion plug's nets on the routed board, without rebuilding it.

Run with KiCad's Python after merge_netlist.py, then route_board.py to route the new
connections (Freerouting keeps the tracks that are already there):

  KICAD_PY wire_expansion.py

make_kicad.py gives J1 the same nets when it builds a board from scratch; this script
is for adding them to the board that is already routed.
"""
import json, os

import pcbnew

import board_data as bd

HERE = os.path.dirname(os.path.abspath(__file__))
PCB = os.path.join(HERE, "..", "kicad", "psicomp80.kicad_pcb")
NETLIST = os.path.join(HERE, "netlist", "psicomp80_netlist.json")


def main():
    board = pcbnew.LoadBoard(PCB)
    ref = bd.EXPANSION["ref"]
    pins = json.load(open(NETLIST))["parts"][ref]["pins"]
    fp = board.FindFootprintByReference(ref)
    nets = board.GetNetsByName()
    new = 0
    for pad in fp.Pads():
        name = pins.get(pad.GetNumber())
        if not name or name == "NC":
            continue
        net = nets[name] if nets.has_key(name) else None
        if net is None:
            net = pcbnew.NETINFO_ITEM(board, name)
            board.Add(net)
            nets = board.GetNetsByName()
        if pad.GetNetname() != name:
            pad.SetNet(net)
            new += 1
    board.BuildConnectivity()
    print(f"{new} pads of {ref} given nets;",
          board.GetConnectivity().GetUnconnectedCount(False), "connections to route")
    board.Save(PCB)


if __name__ == "__main__":
    main()
