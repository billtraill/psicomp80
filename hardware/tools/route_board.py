"""Autoroute the KiCad board with Freerouting.

Run with KiCad's Python (needs pcbnew) once make_kicad.py has written a board with nets:

  KICAD_PY route_board.py --freerouting /path/to/freerouting.jar [--java java] [--passes 40] [--keep]

Exports hardware/kicad/psicomp80.kicad_pcb to Specctra DSN, routes it with Freerouting
on two layers (F.Cu = component side, B.Cu = solder side), imports the session back and
saves the board in place. The DSN and SES files are kept next to the board.
"""
import argparse, os, subprocess, sys, time

import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
KICAD = os.path.join(HERE, "..", "kicad")
PCB = os.path.join(KICAD, "psicomp80.kicad_pcb")


def remove_dangling(path):
    """Delete track stubs left with a loose end by the router (repeat until none are
    left). KiCad's Python loses the board's track list once tracks are removed, so
    each round reloads the board from the file."""
    removed = 0
    while True:
        board = pcbnew.LoadBoard(path)
        board.BuildConnectivity()
        conn = board.GetConnectivity()
        stubs = [t for t in board.Tracks() if t.GetClass() == "PCB_TRACK" and conn.TestTrackEndpointDangling(t, False)]
        if not stubs:
            return removed, board
        for t in stubs:
            board.Delete(t)
        removed += len(stubs)
        board.Save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--freerouting", default="")
    ap.add_argument("--java", default="java")
    ap.add_argument("--passes", type=int, default=40)
    ap.add_argument("--pcb", default=PCB)
    ap.add_argument("--import-only", action="store_true",
                    help="skip routing: import the session file already next to the board")
    ap.add_argument("--keep", action="store_true",
                    help="lock the tracks already on the board so only new connections are routed")
    a = ap.parse_args()

    dsn = os.path.splitext(a.pcb)[0] + ".dsn"
    ses = os.path.splitext(a.pcb)[0] + ".ses"
    board = pcbnew.LoadBoard(a.pcb)
    kept = [t for t in board.GetTracks() if not t.IsLocked()] if a.keep else []
    unlock = {t.m_Uuid.AsString() for t in kept}
    for t in kept:
        t.SetLocked(True)      # exported as fixed wires, which Freerouting leaves alone
    if not pcbnew.ExportSpecctraDSN(board, dsn):
        sys.exit("DSN export failed")
    if not a.import_only:
        if os.path.exists(ses):
            os.remove(ses)
        t = time.time()
        subprocess.run([a.java, "-jar", a.freerouting, "-de", dsn, "-do", ses, "-mp", str(a.passes),
                        "--gui.enabled=false"], check=True)
        if not os.path.exists(ses):
            sys.exit("Freerouting wrote no session file")
        print(f"routed in {time.time() - t:.0f} s")
    board = pcbnew.LoadBoard(a.pcb)
    for t in board.Tracks():
        if t.m_Uuid.AsString() in unlock:
            t.SetLocked(True)  # the session holds only new wires; the import deletes unlocked tracks
    if not pcbnew.ImportSpecctraSES(board, ses):
        sys.exit("SES import failed")
    for t in board.Tracks():
        if t.m_Uuid.AsString() in unlock:
            t.SetLocked(False)
    # KiCad's Python loses track of the board's track list after a big import, so
    # save and reload before tidying
    board.Save(a.pcb)
    removed, board = remove_dangling(a.pcb)
    print(removed, "dangling track stubs removed")
    items = list(board.Tracks())
    tracks = [t for t in items if t.GetClass() == "PCB_TRACK"]
    vias = [t for t in items if t.GetClass() == "PCB_VIA"]
    print(a.pcb, len(tracks), "track segments", len(vias), "vias")


if __name__ == "__main__":
    main()
