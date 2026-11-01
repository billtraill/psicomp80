"""Write ../../hardware_v3.html, the web page for the COMP80 v3 board.

  python3 make_page.py [links-file]

It reads the KiCad board (../kicad/comp80v3.kicad_pcb, with its planes filled)
and design.py, draws the board with the same code as the original board's page
(../../hardware/tools/make_hardware_page.py), and fills page_template.html,
whose viewer script is the original page's. With a links file (lines of
"page.html URL"), links to the other pages are replaced and the page goes to
../build/hardware_v3_artifact.html instead.
"""
import html, json, re, sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "hardware" / "tools"))
import make_hardware_page as h     # noqa: E402
import design as d                 # noqa: E402

PCB = HERE.parent / "kicad" / "comp80v3.kicad_pcb"
OUT = REPO / "hardware_v3.html"

SECTIONS = [("fpga", "FPGA"), ("config", "Configuration"), ("power", "Power"), ("video", "HDMI"),
            ("dp", "USB-C video"), ("usb", "Keyboard"), ("sd", "microSD"), ("misc", "Buttons and debug")]
DP_PARTS = {"J7", "U6", "U7", "X2", "C70", "R24", "R25", "R26", "R27", "R28", "R29", "R30",
            *(f"C{n}" for n in range(45, 59))}
DECOUPLE = {c[0] for c in d.DECOUPLE}


def section_of(ref):
    if ref in DP_PARTS:
        return "dp"
    if ref == "U1" or ref in DECOUPLE or ref in ("C7", "C8", "C9", "X1", "C10"):
        return "fpga"
    if ref in ("U2", "C11", "R23", "R9", "R10", "R11", "R12", "R13", "D2", "SW2", "J5"):
        return "config"
    if ref in ("J1", "R1", "R2", "C15") or ref[:1] in "UL" or ref in [f"R{i}" for i in range(3, 9)] + [f"C{i}" for i in range(1, 7)]:
        return "power"
    if ref in ("J2", "D3"):
        return "video"
    if ref in ("J3", "F1", "C14", "R21", "R22"):
        return "usb"
    if ref in ("J4", "C12", "C13") or ref in [f"R{16 + i}" for i in range(5)]:
        return "sd"
    return "misc"


KIND = {"U": "Integrated circuit", "R": "Resistor", "C": "Capacitor", "J": "Connector", "SW": "Push button",
        "D": "Diode", "L": "Inductor", "F": "Fuse", "X": "Oscillator", "H": "Mounting hole"}


def kind_of(ref):
    if ref in ("D1", "D2"):
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
    # the board's own silkscreen: the cover screen drawn as rectangles, and the name
    b["silk_rects"] = []
    for r in h.kids(pcb, "gr_rect"):
        if h.kid(r, "layer")[1] == "F.SilkS":
            a, e = h.kid(r, "start"), h.kid(r, "end")
            x0, y0, x1, y1 = h.num(a[1]), h.num(a[2]), h.num(e[1]), h.num(e[2])
            b["silk_rects"].append(f"M{h.f(min(x0, x1))} {h.f(min(y0, y1))}h{h.f(abs(x1 - x0))}v{h.f(abs(y1 - y0))}h{h.f(-abs(x1 - x0))}z")
    b["silk_text"] = []
    for t in h.kids(pcb, "gr_text"):
        if h.kid(t, "layer")[1] == "F.SilkS":
            at = h.kid(t, "at")
            size = h.num(h.kid(h.kid(h.kid(t, "effects"), "font"), "size")[1])
            b["silk_text"].append((t[1], h.num(at[1]), h.num(at[2]), size))
    return b


def board_svg(b):
    s = h.board_svg(b)
    extra = "".join(f'<g id="L-in{k}" class="plane" hidden><path d="{"".join(b["planes"][f"In{k}.Cu"])}"/></g>'
                    for k in (1, 2, 3, 4))
    s = s.replace('<g id="L-artB"', extra + '<g id="L-artB"', 1)
    # KiCad's text size is the capital height: about 0.72 of the font size
    silk = f'<path class="logo" d="{"".join(b["silk_rects"])}"/>' + "".join(
        f'<text class="brd" x="{h.f(x)}" y="{h.f(y)}" font-size="{h.f(size / 0.72)}">{html.escape(text)}</text>'
        for text, x, y, size in b["silk_text"])
    return s.replace('<g id="L-silk">', '<g id="L-silk">' + silk, 1)


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


def io_table():
    rows = []
    for port, (ball, std, use) in d.IO.items():
        bank = d.BALLS[ball].rsplit("_", 1)[1]
        rows.append(f"<tr><td>{ball}</td><td>{html.escape(use)} <span class=sub>bank {bank}, {std}</span></td></tr>")
    return "".join(rows)


def img(path):
    import base64
    return "data:image/png;base64," + base64.b64encode(Path(path).read_bytes()).decode()


def util():
    """The utilisation table's label and rows: Vivado's post-route report if there is
    one (vivado/build.tcl), otherwise the yosys totals (tools/synth.sh)."""
    total = {"LUTs": 63400, "Flip-flops": 126800, "Block RAM (36 Kb)": 135, "DSP slices": 240}
    f = HERE.parent / "vivado" / "out" / "utilisation.txt"
    if f.exists():
        text = f.read_text()
        def used(name):
            return float(re.search(r"^\| " + name + r"\s+\|\s+([\d.]+) \|", text, re.M).group(1))
        got, label = {"LUTs": used("Slice LUTs"), "Flip-flops": used("Slice Registers"),
                      "Block RAM (36 Kb)": used("Block RAM Tile"), "DSP slices": used("DSPs")}, "Vivado, placed and routed"
    else:
        f = HERE.parent / "build" / "synth" / "utilisation.txt"
        if not f.exists():
            return "", ""
        text = f.read_text()
        text = text[text.index("design hierarchy"):]
        count = {}
        for line in text.splitlines():
            m = re.match(r"\s+(\d+)\s+(LUT\d|FD\w+|RAMB\w+|CARRY4|OSERDESE2|MMCME2_BASE|PLLE2_BASE)$", line)
            if m:
                count[m.group(2)] = int(m.group(1))
        got = {"LUTs": sum(v for k, v in count.items() if k.startswith("LUT")),
               "Flip-flops": sum(v for k, v in count.items() if k.startswith("FD")),
               "Block RAM (36 Kb)": count.get("RAMB36E1", 0) + count.get("RAMB18E1", 0) / 2, "DSP slices": 0}
        label = "yosys, the whole design"
    return label, "".join(f"<tr><td>{n}</td><td>{v:,.4g}</td><td>{total[n]:,}</td><td>{v / total[n] * 100:.1f}%</td></tr>"
                          for n, v in got.items())


def template():
    """page_template.html, with the original page's style and viewer script spliced in."""
    v1 = (REPO / "hardware" / "tools" / "hardware_template.html").read_text()
    style = v1[v1.index("<style>"):v1.index("</style>") + len("</style>")]
    script = v1[v1.index("<script>"):v1.index("</script>") + len("</script>")]
    # what differs for this board: its layers, its size, its words
    swaps = [
        ('const layers = { top: true, bot: true, pads: true, silk: true, labels: true, sect: false };',
         'const layers = { top: true, bot: true, in1: false, in2: false, in3: false, in4: false, pads: true, silk: true, labels: true, sect: false };'),
        ('    vis("L-sect", layers.sect);', '    vis("L-sect", layers.sect);\n    for (const k of [1, 2, 3, 4]) vis("L-in" + k, layers["in" + k]);'),
        ('svg.classList.toggle("z1", vb.w < 270);', 'svg.classList.toggle("z1", vb.w < 75);'),
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
    info.innerHTML = `<span class="kicker">The v3 board</span>
      <p>Click a part to see what it is and what each pin connects to, or a track or pad to follow its signal.</p>
      <ul class="legend">
        <li><i style="background:var(--cuT)"></i>Top copper (all the parts are on top)</li>
        <li><i style="background:var(--cuB)"></i>Bottom copper</li>
        <li><i style="background:var(--gnd)"></i>Ground plane, inner layer 1</li>
        <li><i style="background:var(--v33)"></i>3.3 V plane, inner layer 2, with a 2.5 V island</li>
        <li><i style="background:var(--v10)"></i>1.0 V plane, inner layer 3, with the transceivers' 1.0 V island</li>
        <li><i style="background:var(--v18)"></i>1.8 V plane, inner layer 4, with a 1.2 V island</li>
        <li><i style="background:var(--pad)"></i>Pads and vias</li>
        <li><i style="background:var(--hl)"></i>The signal you pick</li>
      </ul>
      <p class="desc">${comps.filter(c => c.kind !== "Mounting hole").length} parts and ${D.nets.length} signals. Try <button class="link" data-find="U1">the FPGA</button>, <button class="link" data-find="TMDS_CKP">the HDMI clock</button> or <button class="link" data-find="FLASH_SCK">the configuration clock</button>.</p>`;
  }
''' + script[empty_end:]
    style = style.replace("--silk: #20252b;", "--silk: #20252b; --gnd: rgba(70, 90, 110, .22); --v33: rgba(190, 120, 30, .22); --v10: rgba(150, 60, 160, .2); --v18: rgba(40, 140, 90, .22);")
    style = style.replace("--silk: #dfe5ea;", "--silk: #dfe5ea; --gnd: rgba(140, 170, 200, .2); --v33: rgba(255, 180, 80, .18); --v10: rgba(220, 140, 230, .18); --v18: rgba(110, 220, 160, .18);")
    style = style.replace("</style>", """#L-in1 path { fill: var(--gnd); pointer-events: none; }
#L-in2 path { fill: var(--v33); pointer-events: none; }
#L-in3 path { fill: var(--v10); pointer-events: none; }
#L-in4 path { fill: var(--v18); pointer-events: none; }
#L-silk path.logo { fill: var(--silk); stroke: none; opacity: .85; }
#L-silk text.brd { fill: var(--silk); font-family: "Helvetica Neue", Arial, sans-serif; font-weight: 600; dominant-baseline: central; white-space: pre; opacity: .85; pointer-events: none; }
.chip.g i { color: #6d8296; } .chip.v i { color: #c8862a; } .chip.v1 i { color: #a45bb0; } .chip.v8 i { color: #2f9e6a; }
.frames { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 18rem), 1fr)); gap: 1rem; }
.frames img { display: block; width: 100%; height: auto; border-radius: 6px; image-rendering: pixelated; }
.frames figure { margin: 0; display: grid; gap: .4rem; }
.frames figcaption { font-size: .875rem; color: var(--muted); }
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
    links = {"hardware.html": "hardware.html", "hardware_v2.html": "hardware_v2.html", "emulator.html": "emulator.html",
             "roms.html": "roms.html", "screenshots.html": "screenshots.html"}
    out = OUT
    if len(sys.argv) > 1:
        for line in Path(sys.argv[1]).read_text().splitlines():
            if line.strip():
                k, v = line.split()
                links[k] = v
        out = HERE.parent / "build" / "hardware_v3_artifact.html"
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
    page = (template().replace("{{BOARD}}", board_svg(b).replace("The COMP80 main board", "The COMP80 v3 board"))
            .replace("{{DATA}}", json.dumps(data, separators=(",", ":")))
            .replace("{{PARTS}}", parts_table(b))
            .replace("{{IO}}", io_table())
            .replace("{{FRAME_BURP}}", img(HERE.parent / "pictures" / "frame_burp.png"))
            .replace("{{FRAME_LIFE}}", img(HERE.parent / "pictures" / "frame_life.png"))
            .replace("{{FRAME_DP}}", img(HERE.parent / "pictures" / "frame_dp.png"))
            .replace("{{UTIL}}", util()[1])
            .replace("{{UTIL_SRC}}", util()[0])
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
