"""The files a board house wants for a quote, made from the routed KiCad board
(../kicad/comp80v3.kicad_pcb) into ../fab/:

  comp80v3_gerbers.zip     Gerbers for the six copper layers, mask, silkscreen,
                           paste and outline, and Excellon drill files (plated
                           and not), all from the board's bottom-left corner
  comp80v3_bom_pcbway.csv  the parts list in PCBWay's layout: designators,
                           quantity, maker and part number, the full spec of
                           every passive (so an equivalent can be sourced),
                           package, and SMD or through-hole
  comp80v3_cpl.csv         where each part goes: designator, centre, side, rotation
  comp80v3_assembly.pdf    the assembly drawing: outlines and references

README.md there has the settings for the quote form.

Run it with KiCad's Python (it uses pcbnew and kicad-cli):

  /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3 make_fab.py
"""
import csv, os, shutil, subprocess, zipfile
import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PCB = os.path.join(ROOT, "kicad", "comp80v3.kicad_pcb")
OUT = os.path.join(ROOT, "fab")
CLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
NAME = "comp80v3"

LAYERS = ["F.Cu", "In1.Cu", "In2.Cu", "In3.Cu", "In4.Cu", "B.Cu", "F.Mask", "B.Mask",
          "F.Silkscreen", "B.Silkscreen", "F.Paste", "B.Paste", "Edge.Cuts"]

# The passives and LEDs: the full spec, with a suggested part. Voltage ratings
# are at least twice the rail (5 V parts are 25 V); any part to the same spec will do.
CAPS = {
    ("10u", "C_0805_2012Metric"): ("Murata", "GRM21BR61E106KA73L", "10 uF 25 V X5R 10% 0805"),
    ("22u", "C_0805_2012Metric"): ("Murata", "GRM21BR61A226ME44L", "22 uF 10 V X5R 20% 0805"),
    ("100u", "C_1210_3225Metric"): ("Murata", "GRM32ER60J107ME20L", "100 uF 6.3 V X5R 20% 1210"),
    ("47u", "C_1210_3225Metric"): ("Murata", "GRM32ER61A476ME20L", "47 uF 10 V X5R 20% 1210"),
    ("100n", "C_0603_1608Metric"): ("Murata", "GRM188R71C104KA01D", "100 nF 16 V X7R 10% 0603"),
    ("470n", "C_0402_1005Metric"): ("Murata", "GRM155R61A474KE15D", "470 nF 10 V X5R 10% 0402"),
    ("4.7u", "C_0603_1608Metric"): ("Murata", "GRM188R61A475KE15D", "4.7 uF 10 V X5R 10% 0603"),
    ("100n", "C_0402_1005Metric"): ("Murata", "GRM155R71C104KA88D", "100 nF 16 V X7R 10% 0402"),
    ("1u", "C_0603_1608Metric"): ("Murata", "GRM188R61C105KA93D", "1 uF 16 V X5R 10% 0603"),
}
OTHER = {
    "D1": ("Wurth", "150080RS75000", "Red LED 0805"),
    "D2": ("Wurth", "150080GS75000", "Green LED 0805"),
    "J5": ("", "", "2.54 mm pin header, 1 x 6, straight"),
    "J6": ("", "", "2.54 mm pin header, 1 x 2, straight"),
    "X1": ("ECS", "ECS-2520MV-1000-BN-TR", "100 MHz oscillator, 3.3 V CMOS, 2.5 x 2.0 mm"),
}
# parts used more than once, described as a buyer would rather than by their job
GENERIC = {
    "DFE252012F-2R2M": "2.2 uH power inductor, 1008",
    "TLV62569DBVR": "2 A step-down regulator, SOT-23-5",
    "B3S-1000": "Tactile switch, SMD",
}


def yageo(value):
    """A 1% 0603 resistor, as Yageo's RC0603FR-07 number: 4.7k is 4K7L, 100R is 100RL."""
    v = value.split()[0]
    if v.endswith("R"):
        code = v
    elif "." in v:
        code = v.replace(".", v[-1].upper())[:-1]
    else:
        code = v.upper()
    return "RC0603FR-07" + code + "L"


def run(*args):
    subprocess.run([CLI, *args], check=True, stdout=subprocess.DEVNULL)


def mounting(board):
    """Each footprint's mounting: SMD, THT, or SMD with through-hole pegs or tabs."""
    kind = {}
    for fp in board.GetFootprints():
        attrs = {p.GetAttribute() for p in fp.Pads()}
        smd = pcbnew.PAD_ATTRIB_SMD in attrs
        tht = pcbnew.PAD_ATTRIB_PTH in attrs
        kind[fp.GetReference()] = "SMD + THT tabs" if smd and tht else "THT" if tht else "SMD"
    return kind


def bom(board):
    kind = mounting(board)
    groups = {}
    for row in csv.DictReader(open(os.path.join(ROOT, "bom.csv"))):
        refs = row["References"].split()
        value, fp, part = row["Value"], row["Footprint"], row["Part"]
        if refs[0] in OTHER:
            maker, mpn, desc = OTHER[refs[0]]
        elif refs[0].startswith("C"):
            maker, mpn, desc = CAPS[(value, fp)]
        elif refs[0].startswith("R"):
            maker, mpn = "Yageo", yageo(value)
            desc = f"{value.split()[0].replace('R', '')} ohm 1% 0.1 W 0603".replace("k ohm", " kohm")
        else:
            maker, mpn = part.split(" ", 1) if " " in part else ("", part)
            desc = GENERIC.get(mpn, row["Description"])
        key = (maker, mpn, fp) if mpn else (maker, desc, fp)
        groups.setdefault(key, [desc, []])[1].extend(refs)
    rows = []
    for (maker, mpn, fp), (desc, refs) in groups.items():
        mpn = mpn if mpn != desc else ""
        refs.sort(key=lambda r: (r.rstrip("0123456789"), int(r[len(r.rstrip("0123456789")):] or 0)))
        rows.append((refs, maker, mpn, desc, fp, kind[refs[0]]))
    rows.sort(key=lambda r: (r[0][0].rstrip("0123456789"), int(r[0][0][len(r[0][0].rstrip("0123456789")):])))
    path = os.path.join(OUT, f"{NAME}_bom_pcbway.csv")
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Item #", "Designator", "Qty", "Manufacturer", "Mfg Part #", "Description / Value",
                    "Package/Footprint", "Type", "Your Instructions / Notes"])
        for i, (refs, maker, mpn, desc, fp, mount) in enumerate(rows, 1):
            note = "Equivalent to this spec accepted" if refs[0][0] in "CR" or refs[0][0] in "DJ" and refs[0] in OTHER else ""
            if refs[0] == "U1":
                note = "BGA, 1.0 mm pitch: X-ray inspection please"
            w.writerow([i, " ".join(refs), len(refs), maker, mpn, desc, fp, mount, note])
    return len(rows), sum(len(r[0]) for r in rows)


def cpl():
    raw = os.path.join(OUT, "pos_raw.csv")
    run("pcb", "export", "pos", PCB, "--side", "front", "--format", "csv", "--units", "mm",
        "--use-drill-file-origin", "-o", raw)
    n = 0
    with open(os.path.join(OUT, f"{NAME}_cpl.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
        for row in csv.DictReader(open(raw)):
            if row["Ref"].startswith("H"):          # mounting holes aren't parts
                continue
            w.writerow([row["Ref"], f'{float(row["PosX"]):.3f}', f'{float(row["PosY"]):.3f}',
                        "Top", f'{float(row["Rot"]):.1f}'])
            n += 1
    os.remove(raw)
    return n


def main():
    os.makedirs(OUT, exist_ok=True)
    for name in os.listdir(OUT):                # this script's own files; README.md stays
        if name.startswith(NAME + "_"):
            os.remove(os.path.join(OUT, name))
    gerbers = os.path.join(OUT, "gerbers")
    shutil.rmtree(gerbers, ignore_errors=True)
    os.makedirs(gerbers)
    run("pcb", "export", "gerbers", PCB, "-l", ",".join(LAYERS), "--use-drill-file-origin",
        "--check-zones", "-o", gerbers + os.sep)
    run("pcb", "export", "drill", PCB, "--format", "excellon", "--drill-origin", "plot",
        "--excellon-separate-th", "-u", "mm", "--generate-map", "--map-format", "gerberx2",
        "-o", gerbers + os.sep)
    with zipfile.ZipFile(os.path.join(OUT, f"{NAME}_gerbers.zip"), "w", zipfile.ZIP_DEFLATED) as z:
        for name in sorted(os.listdir(gerbers)):
            z.write(os.path.join(gerbers, name), name)
    files = sorted(os.listdir(gerbers))
    shutil.rmtree(gerbers)
    run("pcb", "export", "pdf", PCB, "-l", "F.Fab,Edge.Cuts", "--mode-single", "--black-and-white", "--scale", "0",
        "-o", os.path.join(OUT, f"{NAME}_assembly.pdf"))
    board = pcbnew.LoadBoard(PCB)
    lines, parts = bom(board)
    placed = cpl()
    print(f"{len(files)} Gerber and drill files zipped; BOM {lines} lines, {parts} parts; {placed} placements")
    for name in files:
        print("  ", name)


if __name__ == "__main__":
    main()
