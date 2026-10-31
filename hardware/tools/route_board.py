"""Autoroute the KiCad board with Freerouting.

Run with KiCad's Python (needs pcbnew) once make_kicad.py has written a board with nets:

  KICAD_PY route_board.py --freerouting /path/to/freerouting.jar [--java java] [--passes 40]

Exports hardware/kicad/psicomp80.kicad_pcb to Specctra DSN, routes it with Freerouting
on two layers (F.Cu = component side, B.Cu = solder side), imports the session back and
saves the board in place. The DSN and SES files are kept next to the board.
"""
import argparse, os, subprocess, sys, time

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
KICAD = os.path.join(HERE, "..", "kicad")
PCB = os.path.join(KICAD, "psicomp80.kicad_pcb")


def remove_dangling(board):
    """Delete track stubs left with a loose end by the router (repeat until none are left)."""
    removed = 0
    while True:
        board.BuildConnectivity()
        conn = board.GetConnectivity()
        stubs = [t for t in board.GetTracks() if t.GetClass() == "PCB_TRACK" and conn.TestTrackEndpointDangling(t, False)]
        if not stubs:
            return removed
        for t in stubs:
            board.Remove(t)
        removed += len(stubs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--freerouting", required=True)
    ap.add_argument("--java", default="java")
    ap.add_argument("--passes", type=int, default=40)
    ap.add_argument("--pcb", default=PCB)
    a = ap.parse_args()

    dsn = os.path.splitext(a.pcb)[0] + ".dsn"
    ses = os.path.splitext(a.pcb)[0] + ".ses"
    board = pcbnew.LoadBoard(a.pcb)
    if not pcbnew.ExportSpecctraDSN(board, dsn):
        sys.exit("DSN export failed")
    if os.path.exists(ses):
        os.remove(ses)
    t = time.time()
    subprocess.run([a.java, "-jar", a.freerouting, "-de", dsn, "-do", ses, "-mp", str(a.passes),
                    "--gui.enabled=false"], check=True)
    if not os.path.exists(ses):
        sys.exit("Freerouting wrote no session file")
    print(f"routed in {time.time() - t:.0f} s")
    board = pcbnew.LoadBoard(a.pcb)
    if not pcbnew.ImportSpecctraSES(board, ses):
        sys.exit("SES import failed")
    print(remove_dangling(board), "dangling track stubs removed")
    board.Save(a.pcb)
    tracks = [t for t in board.GetTracks() if t.GetClass() == "PCB_TRACK"]
    vias = [t for t in board.GetTracks() if t.GetClass() == "PCB_VIA"]
    print(a.pcb, len(tracks), "track segments", len(vias), "vias")


if __name__ == "__main__":
    main()
