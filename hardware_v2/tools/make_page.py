"""Write ../../hardware_v2.html, the web page for the COMP80 v2 board.

  python3 make_page.py [links-file]

It reads the KiCad board (../kicad/comp80v2.kicad_pcb, with its planes filled)
and design.py, draws the board with the same code as the original board's page
(../../hardware/tools/make_hardware_page.py), and fills page_template.html,
whose viewer script is the original page's. With a links file (lines of
"page.html URL"), links to the other pages are replaced and the page goes to
../build/hardware_v2_artifact.html instead.
"""
import html, json, re, sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "hardware" / "tools"))
import make_hardware_page as h     # noqa: E402
import design as d                 # noqa: E402

PCB = HERE.parent / "kicad" / "comp80v2.kicad_pcb"
OUT = REPO / "hardware_v2.html"

SECTIONS = [("mcu", "RP2350"), ("power", "Power"), ("video", "HDMI"), ("usb", "Keyboard"),
            ("sd", "microSD"), ("misc", "Buttons and debug")]


def section_of(ref):
    if ref in ("U1", "U2", "Y1", "L1", "R5", "R6") or ref in d.DECOUPLE or ref in ("C12", "C13", "C14", "C10", "C18", "C19", "C20"):
        return "mcu"
    if ref in ("J1", "U3", "C1", "C2", "R1", "R2", "R3", "R4"):
        return "power"
    if ref in ("J2", "D2") or ref in [f"R{14 + i}" for i in range(8)]:
        return "video"
    if ref in ("J3", "F1", "C23", "R22", "R23", "R24", "R25"):
        return "usb"
    if ref in ("J4", "C21", "C22", "R9", "R10", "R11", "R12", "R13"):
        return "sd"
    return "misc"


KIND = {"U": "Integrated circuit", "R": "Resistor", "C": "Capacitor", "J": "Connector", "SW": "Push button",
        "D": "Diode", "L": "Inductor", "F": "Fuse", "Y": "Crystal", "H": "Mounting hole"}


def kind_of(ref):
    if ref == "D1":
        return "LED"
    p = ref.rstrip("0123456789")
    return KIND.get(p, "Part")


def build():
    """The original page's build(), pointed at this board, plus the two planes."""
    netlist = json.loads((HERE.parent / "netlist.json").read_text())
    for p in netlist["parts"].values():
        p.setdefault("figure", "")
    tmp = HERE.parent / "build" / "netlist_for_page.json"
    tmp.parent.mkdir(exist_ok=True)
    tmp.write_text(json.dumps(netlist))
    h.PCB, h.NETLIST = PCB, tmp
    h.section_of = lambda ref, part, x, y: section_of(ref)
    h.kind_of = kind_of
    h.describe = lambda ref, value, kind: d.PARTS[ref][3] if ref in d.PARTS else value
    h.ROLES = {ref: (f"Made by: {p[2]}" if p[2] else "") for ref, p in d.PARTS.items()}
    b = h.build()
    # the filled planes on the inner layers
    pcb = h.parse(PCB.read_text())
    planes = defaultdict(list)
    for z in h.kids(pcb, "zone"):
        for fp in h.kids(z, "filled_polygon"):
            layer = h.kid(fp, "layer")[1]
            pts = [(h.num(q[1]), h.num(q[2])) for q in h.kid(fp, "pts") if isinstance(q, list) and q[0] == "xy"]
            planes[layer].append("M" + "L".join(f"{h.f(x)} {h.f(y)}" for x, y in pts) + "Z")
    b["planes"] = planes
    return b


def board_svg(b):
    s = h.board_svg(b)
    extra = (f'<g id="L-in1" class="plane" hidden><path d="{"".join(b["planes"]["In1.Cu"])}"/></g>'
             f'<g id="L-in2" class="plane" hidden><path d="{"".join(b["planes"]["In2.Cu"])}"/></g>')
    return s.replace('<g id="L-artB"', extra + '<g id="L-artB"', 1)


def parts_table(b):
    rows = []
    order = {k: i for i, (k, _) in enumerate(SECTIONS)}
    for i, c in sorted(enumerate(b["comps"]), key=lambda ic: (order[ic[1]["section"]], ic[1]["kind"] != "Integrated circuit",
                                                             ic[1]["kind"], h.natural(ic[1]["ref"]))):
        if c["kind"] == "Mounting hole":
            continue
        mpn = d.PARTS[c["ref"]][2]
        rows.append(f'<tr data-c="{i}" data-s="{c["section"]}"><td><button type="button" class="ref" data-c="{i}">'
                    f'{html.escape(c["ref"])}</button></td><td>{html.escape(c["value"])}</td>'
                    f'<td>{html.escape(c["desc"])}'
                    f'{"<span class=sub>" + html.escape(mpn) + "</span>" if mpn else ""}</td>'
                    f'<td class="sec">{dict(SECTIONS)[c["section"]]}</td></tr>')
    return "".join(rows)


def gpio_table():
    rows = []
    for g, (net, use) in sorted(d.GPIO_USE.items()):
        rows.append(f"<tr><td>GPIO{g}</td><td>{html.escape(use)}</td></tr>")
    return "".join(rows)


def template():
    """page_template.html, with the original page's style and viewer script spliced in."""
    v1 = (REPO / "hardware" / "tools" / "hardware_template.html").read_text()
    style = v1[v1.index("<style>"):v1.index("</style>") + len("</style>")]
    script = v1[v1.index("<script>"):v1.index("</script>") + len("</script>")]
    # what differs for this board: its layers, its size, its words
    swaps = [
        ('const layers = { top: true, bot: true, pads: true, silk: true, labels: true, sect: false };',
         'const layers = { top: true, bot: true, in1: false, in2: false, pads: true, silk: true, labels: true, sect: false };'),
        ('    vis("L-sect", layers.sect);', '    vis("L-sect", layers.sect);\n    vis("L-in1", layers.in1); vis("L-in2", layers.in2);'),
        ('svg.classList.toggle("z1", vb.w < 270);', 'svg.classList.toggle("z1", vb.w < 60);'),
        ('svg.classList.toggle("z2", vb.w < 120);', 'svg.classList.toggle("z2", vb.w < 34);'),
        ('function clampW(w) { return Math.min(Math.max(w, 6), (BW + 8) * 1.8); }',
         'function clampW(w) { return Math.min(Math.max(w, 2.5), (BW + 8) * 1.8); }'),
        ("`${(px / vb.w * 25.4 / 96 * 100).toFixed(0)}% · ${(vb.w / 25.4).toFixed(1)} in across`",
         "`${(px / vb.w * 25.4 / 96 * 100).toFixed(0)}% · ${vb.w.toFixed(1)} mm across`"),
        ('selectList(list, pl.dataset.title || "The calculator chip", pl.dataset.title ? "On the board:" : "The MM57109 and the parts that talk to it:");',
         'selectList(list, pl.dataset.title || "Parts", "On the board:");'),
        ('const [near, far, nearA, farA] = on ? ["L-bot", "L-top", "L-artB", "L-artT"] : ["L-top", "L-bot", "L-artT", "L-artB"];',
         'const [near, far, nearA, farA] = on ? ["L-bot", "L-top", "L-in2", "L-in1"] : ["L-top", "L-bot", "L-in1", "L-in2"];'),
    ]
    for a, b in swaps:
        assert a in script, a
        script = script.replace(a, b)
    empty_start = script.index("  function showEmpty() {")
    empty_end = script.index("  function showComp(c) {")
    script = script[:empty_start] + '''  function showEmpty() {
    status.textContent = statusText;
    info.innerHTML = `<span class="kicker">The v2 board</span>
      <p>Click a part to see what it is and what each pin connects to, or a track or pad to follow its signal.</p>
      <ul class="legend">
        <li><i style="background:var(--cuT)"></i>Top copper (all the parts are on top)</li>
        <li><i style="background:var(--cuB)"></i>Bottom copper</li>
        <li><i style="background:var(--gnd)"></i>Ground plane, inner layer 1</li>
        <li><i style="background:var(--v33)"></i>3.3 V plane, inner layer 2</li>
        <li><i style="background:var(--pad)"></i>Pads and vias</li>
        <li><i style="background:var(--hl)"></i>The signal you pick</li>
      </ul>
      <p class="desc">${comps.filter(c => c.kind !== "Mounting hole").length} parts and ${D.nets.length} signals. Try <button class="link" data-find="U1">the RP2350</button>, <button class="link" data-find="TMDS_CKP">the HDMI clock</button> or <button class="link" data-find="SD_SCK">the microSD clock</button>.</p>`;
  }
''' + script[empty_end:]
    style = style.replace("--silk: #20252b;", "--silk: #20252b; --gnd: rgba(70, 90, 110, .22); --v33: rgba(190, 120, 30, .22);")
    style = style.replace("--silk: #dfe5ea;", "--silk: #dfe5ea; --gnd: rgba(140, 170, 200, .2); --v33: rgba(255, 180, 80, .18);")
    style = style.replace("</style>", """#L-in1 path { fill: var(--gnd); pointer-events: none; }
#L-in2 path { fill: var(--v33); pointer-events: none; }
.chip.g i { color: #6d8296; } .chip.v i { color: #c8862a; }
.dg rect.mcu { fill: color-mix(in srgb, var(--accent) 16%, var(--paper)); }
.table2 { border-collapse: collapse; width: 100%; font-size: .9375rem; }
.table2 th { text-align: left; font: 600 .6875rem/1 var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--muted);
  padding: 0 1rem .5rem 0; border-bottom: 1px solid var(--rule); }
.table2 td { padding: .5rem 1rem .5rem 0; border-bottom: 1px solid var(--rule); vertical-align: top; }
.table2 td:first-child { font-family: var(--mono); font-size: .875rem; min-width: 6.5rem; }
.tree { font: 400 .875rem/1.6 var(--mono); background: var(--panel); border: 1px solid var(--rule); border-radius: 10px;
  padding: .9rem 1rem; margin: 0; overflow-x: auto; }
.keys { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: .35rem 1rem; margin: 0; font-size: .9375rem; }
.keys dt { font: 600 .8125rem/1.5 var(--mono); }
.keys dd { margin: 0; }
kbd { font: 600 .8125rem var(--mono); border: 1px solid var(--rule); border-bottom-width: 2px; border-radius: 4px; padding: 0 .3rem; background: var(--panel); }
</style>""")
    page = (HERE / "page_template.html").read_text()
    return page.replace("{{STYLE}}", style).replace("{{SCRIPT}}", script)


def main():
    links = {"hardware.html": "hardware.html", "hardware_v3.html": "hardware_v3.html", "emulator.html": "emulator.html",
             "roms.html": "roms.html", "screenshots.html": "screenshots.html"}
    out = OUT
    if len(sys.argv) > 1:
        for line in Path(sys.argv[1]).read_text().splitlines():
            if line.strip():
                k, v = line.split()
                links[k] = v
        out = HERE.parent / "build" / "hardware_v2_artifact.html"
    b = build()
    h.X0, h.Y0, h.W, h.H = 100.0, 100.0, d.BOARD_W, d.BOARD_H
    data = {
        "nets": b["nets"],
        "comps": [[c["ref"], c["value"], c["kind"], c["section"], [round(v, 3) for v in c["box"]],
                   c["desc"], c["role"], [[p["num"], p["net"]] for p in c["pads"] if p["num"]]] for c in b["comps"]],   # not paste-only pads
        "sections": dict(SECTIONS),
        "board": [h.X0, h.Y0, h.W, h.H],
    }
    ntracks = sum(len(v) for layer in b["tracks"].values() for v in layer.values())
    page = (template().replace("{{BOARD}}", board_svg(b).replace("The COMP80 main board", "The COMP80 v2 board"))
            .replace("{{DATA}}", json.dumps(data, separators=(",", ":")))
            .replace("{{PARTS}}", parts_table(b))
            .replace("{{GPIO}}", gpio_table())
            .replace("{{NPARTS}}", str(sum(1 for c in b["comps"] if c["kind"] != "Mounting hole")))
            .replace("{{NVIAS}}", str(len(b["vias"])))
            .replace("{{NTRACKS}}", str(ntracks)))
    for k, v in links.items():
        page = page.replace(f'href="{k}', f'href="{v}')
    assert "{{" not in page, re.findall(r"\{\{\w+\}\}", page)
    out.write_text(page)
    print(f"{out.name}: {len(page) // 1024} KB, {len(b['comps'])} parts, {len(b['nets'])} nets")


if __name__ == "__main__":
    main()
