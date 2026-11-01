"""Make ../roms.html: the annotated listings of the COMP80 ROMs and their hex dumps.

The text of each line comes from the source, its address from the z80asm
listing that build.sh writes to rom/build/, and its bytes from the ROM image,
so the page always shows what is in the ROMs.

    psicomp80.asm        monitor (0000-03FF) and BURP (0400-0BFF)
    ../forth/forth.asm   FORTH (0400-0BFF)
    ../lisp/lisp.asm     LISP (0400-0BFF)

Run by build.sh. With an argument, the page's links to the other pages are
taken from that file (lines of "page.html URL") and the page goes to
rom/build/roms_artifact.html, for publishing.
"""
import bisect
import hashlib
import html
import re
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
BUILD = HERE / "build"
OUT = REPO / "roms.html"

CODE_END = 0x0C00
FLOW = {"call", "jp", "jr", "djnz", "rst"}
DIRECTIVES = {"db", "dw", "ds", "defb", "defw", "defs", "defm", "equ", "org"}
LABEL = re.compile(r"\s*([A-Za-z_.][\w.]*):")
TOKEN = re.compile(r"""(?P<str>"[^"]*"|'[^']')"""
                   r"|(?P<num>\$[0-9A-Fa-f]+\b|0x[0-9A-Fa-f]+\b|[0-9][0-9A-Fa-f]*[hH]\b|\d+\b)"
                   r"|(?P<id>[A-Za-z_][\w.]*'?)")
# psicomp80.asm repeats the address and bytes at the start of each comment
ADDR_COMMENT = re.compile(r";\s*[0-9A-F]{4}  [0-9A-F]{2}(?: [0-9A-F]{2})*\s*")
ORPHAN = re.compile(r"L[0-9A-F]{4}")


def esc(s):
    return html.escape(s, quote=False)


def number(s):
    s = s.strip()
    if s.startswith("$"):
        return int(s[1:], 16)
    if s.lower().startswith("0x"):
        return int(s[2:], 16)
    if s[-1] in "hH":
        return int(s[:-1], 16)
    return int(s)


def split_comment(line):
    """Code and comment, splitting at the first ';' outside a string."""
    i, quote = 0, False
    while i < len(line):
        ch = line[i]
        if ch == '"':
            quote = not quote
        elif ch == "'" and not quote and i + 2 < len(line) and line[i + 2] == "'":
            i += 3
            continue
        elif ch == ";" and not quote:
            return line[:i], line[i:]
        i += 1
    return line, ""


class Listing:
    """One source file: per line its text, address and the bytes it makes."""

    def __init__(self, src, lst, rom, strip_addr_comments=False):
        text = src.read_text().splitlines()
        lst_lines = lst.read_text().split("\n# End of file")[0].splitlines()[1:]
        assert len(lst_lines) == len(text), (src, len(lst_lines), len(text))
        self.lines = []
        for t, l in zip(text, lst_lines):
            head = l.split("\t", 1)[0]
            addr = int(head[:4], 16)
            code, comment = split_comment(t.rstrip())
            if strip_addr_comments:
                m = ADDR_COMMENT.match(comment)
                if m:
                    comment = comment[m.end():]
                    comment = "; " + comment if comment else ""
            self.lines.append({"addr": addr, "emits": len(head) > 4, "code": code,
                               "comment": comment, "bytes": b""})
        for i, ln in enumerate(self.lines):
            if ln["emits"]:
                end = self.lines[i + 1]["addr"] if i + 1 < len(self.lines) else CODE_END
                ln["bytes"] = rom[ln["addr"]:end]
                # the listing shows the first few bytes ('..' for a string)
                toks = lst_lines[i].split("\t", 1)[0][5:].split()
                for k, tok in enumerate([] if any("." in t for t in toks) else toks):
                    if re.fullmatch(r"[0-9a-f]{2}", tok) and k < len(ln["bytes"]):
                        assert ln["bytes"][k] == int(tok, 16), (src, hex(ln["addr"]))
        # symbols: labels (addresses) and equates (values)
        self.labels, self.equs = {}, {}
        for ln in self.lines:
            m = LABEL.match(ln["code"])
            ln["label"] = None
            if not m:
                continue
            rest = ln["code"][m.end():].split()
            if rest and rest[0].lower() == "equ":
                try:
                    self.equs[m.group(1)] = number(rest[1])
                except (ValueError, IndexError):
                    pass
            else:
                self.labels[m.group(1)] = ln["addr"]
                ln["label"] = m.group(1)


class Page:
    def __init__(self):
        self.anchors = {}       # section prefix -> sorted addresses with an id

    def target(self, prefix, addr):
        """The id of the row for addr in a section (the row it falls in)."""
        a = self.anchors[prefix]
        i = bisect.bisect_right(a, addr) - 1
        return f"{prefix}{a[max(i, 0)]:04x}"

    def section_of(self, own, addr):
        if addr < 0x0400:
            return "m"
        if addr < CODE_END:
            return own
        return None

    def code_html(self, lst, own, code):
        """Highlight a line's code; names and branch addresses become links."""
        out, pos, first = [], 0, True
        m = LABEL.match(code)
        if m:
            out.append(esc(code[:m.start(1)]))
            out.append(f'<span class="lb">{esc(m.group(1))}</span>:')
            pos = m.end()
        mnem = None
        for t in TOKEN.finditer(code, pos):
            out.append(esc(code[pos:t.start()]))
            pos = t.end()
            s = t.group(0)
            if t.group("str"):
                out.append(f'<span class="st">{esc(s)}</span>')
            elif first and t.group("id"):
                mnem = s.lower()
                cls = "dr" if mnem in DIRECTIVES else "mn"
                out.append(f'<span class="{cls}">{esc(s)}</span>')
            elif t.group("num"):
                v = number(s)
                sec = self.section_of(own, v) if mnem in FLOW else None
                if sec:
                    out.append(f'<a class="nu" href="#{self.target(sec, v)}">{esc(s)}</a>')
                else:
                    out.append(f'<span class="nu">{esc(s)}</span>')
            elif s in lst.labels or (s in lst.equs and mnem in FLOW):
                v = lst.labels.get(s, lst.equs.get(s))
                sec = self.section_of(own, v)
                if sec:
                    out.append(f'<a href="#{self.target(sec, v)}">{esc(s)}</a>')
                else:
                    out.append(esc(s))
            else:
                out.append(esc(s))
            first = False
        out.append(esc(code[pos:]))
        return "".join(out)

    def rows(self, lst, lines, prefix):
        """The rows of a listing: address, up to four bytes, source."""
        out, seen = [], set()

        def row(addr, data, src, cls="r", anchor=True):
            ident = ""
            if anchor and addr not in seen:
                seen.add(addr)
                ident = f' id="{prefix}{addr:04x}"'
            a = f"{addr:04X}" if addr is not None else "    "
            out.append(f'<span class="{cls}"{ident}><i>{a}</i>  <u>{data:<11}</u>  {src}</span>')

        for ln in lines:
            code = self.code_html(lst, prefix, ln["code"]) if ln["code"].strip() else esc(ln["code"])
            com = f'<span class="cm">{esc(ln["comment"])}</span>' if ln["comment"] else ""
            src = code + com
            b = ln["bytes"]
            if b:
                if len(b) > 8 and len(set(b)) == 1:
                    row(ln["addr"], f"{b[0]:02X} × {len(b)}", src)
                    continue
                for k in range(0, len(b), 4):
                    chunk = " ".join(f"{x:02X}" for x in b[k:k + 4])
                    row(ln["addr"] + k, chunk, src if k == 0 else "")
            elif ln["label"]:
                row(ln["addr"], "", src)
            elif not ln["code"].strip() and not ln["comment"]:
                out.append('<span class="r"> </span>')
            else:
                bare = not ln["code"].strip()
                row(None, "", src, "r c" if bare else "r", anchor=False)
        return "".join(out)

    def plan_anchors(self, prefix, lines):
        a = set()
        for ln in lines:
            if ln["bytes"]:
                b = ln["bytes"]
                if len(b) > 8 and len(set(b)) == 1:
                    a.add(ln["addr"])
                else:
                    a.update(range(ln["addr"], ln["addr"] + len(b), 4))
            elif ln["label"]:
                a.add(ln["addr"])
        self.anchors[prefix] = sorted(a)


def label_index(lst, lines, prefix, page):
    names = [(ln["label"], ln["addr"]) for ln in lines
             if ln["label"] and not ORPHAN.fullmatch(ln["label"]) and ln["addr"] < CODE_END]
    chips = "".join(f'<a href="#{page.target(prefix, a)}"><b>{a:04X}</b> {esc(n)}</a>' for n, a in names)
    return f'<details class="idx"><summary>Labels <span>{len(names)}</span></summary><div>{chips}</div></details>'


def display_char(v):
    """The character the COMP80 shows for a screen code (graphics as a dot)."""
    if v & 0x40:
        return "·"
    c = v & 0x3F
    return chr(c + 64 if c < 0x20 else c)


def ascii_char(v):
    return chr(v) if 0x20 <= v < 0x7F else "·"


def hex_dump(name, rom, lang, page):
    rows = []
    for a in range(0, len(rom), 16):
        b = rom[a:a + 16]
        cells = " ".join(f"<b>{x:02X}</b>" + (" " if k == 7 else "") for k, x in enumerate(b))
        d = esc("".join(display_char(x) for x in b))
        t = esc("".join(ascii_char(x) for x in b))
        sec = "m" if a < 0x400 else lang
        rows.append(f'<span class="h" data-a="{a:04x}" data-s="{sec}"><a href="#{page.target(sec, a)}">{a:04X}</a>  '
                    f'{cells}  <span class="td">{d}</span><span class="ta">{t}</span></span>')
    return "".join(rows)


SECTIONS = [
    ("monitor", "m", "Monitor", "0000–03FF",
     "<p>The first kilobyte of every COMP80 ROM, the same in all three. Reset clears the screen and prints READY. "
     "Keys arrive as non-maskable interrupts: the handler at 0066 echoes each key on the screen, and a command key "
     "turns into a jump to its command. The commands examine, change, move, fill, find and list memory, read and "
     "write tape, and run code; RS (the ^ key) enters the language at 0800.</p>"
     "<p>An annotated disassembly. The names and comments come from the earlier disassemblies (now in "
     "<code>old/</code>), corrected where the bytes disagreed. Source: <code>rom/psicomp80.asm</code>.</p>"),
    ("burp", "b", "BURP", "0400–0BFF",
     "<p>The language in the original ROM, from the Wireless World articles: a small BASIC-like language whose "
     "arithmetic is done by a National MM57109 calculator chip. The Z80 sends the chip its key codes "
     "(<a href=\"#b042e\">MM_SEND</a>) and reads back the digits of the result (<a href=\"#b0460\">MM_OUT_X</a>). "
     "Entry is <a href=\"#b0800\">BURP_ENTRY</a>; from 0BB5 the ROM holds the articles' sample program.</p>"
     "<p>An annotated disassembly, in the same file as the monitor: <code>rom/psicomp80.asm</code>.</p>"),
    ("forth", "f", "FORTH", "0400–0BFF",
     "<p>A small direct-threaded FORTH written for this project to fit where BURP was. The listing is its own "
     "source, so the names in threaded definitions link to the words they call. Source: "
     "<code>forth/forth.asm</code>.</p>"),
    ("lisp", "l", "LISP", "0400–0BFF",
     "<p>A LISP 1.5 style interpreter written for this project, with garbage collection, LAMBDA and dynamic "
     "scope, in the same 2 KB. Source: <code>lisp/lisp.asm</code>.</p>"),
]

ROMS = [("psicomp80.rom", "BURP", "b"), ("psicomp80_forth.rom", "FORTH", "f"), ("psicomp80_lisp.rom", "LISP", "l")]

LINKS = {"screenshots.html": "screenshots.html", "lisp.html": "lisp.html", "emulator.html": "emulator.html",
         "hardware.html": "hardware.html"}


def main():
    if len(sys.argv) > 1:
        for line in Path(sys.argv[1]).read_text().splitlines():
            if line.strip():
                k, v = line.split()
                LINKS[k] = v
    roms = {n: (REPO / n).read_bytes() for n, _, _ in ROMS}
    main_lst = Listing(HERE / "psicomp80.asm", BUILD / "psicomp80.lst", roms["psicomp80.rom"], True)
    forth = Listing(REPO / "forth/forth.asm", BUILD / "forth.lst", roms["psicomp80_forth.rom"])
    lisp = Listing(REPO / "lisp/lisp.asm", BUILD / "lisp.lst", roms["psicomp80_lisp.rom"])
    split = next(i for i, ln in enumerate(main_lst.lines) if "BURP ROM 0400-0BFF" in ln["comment"]) - 1
    parts = {"m": (main_lst, main_lst.lines[:split]), "b": (main_lst, main_lst.lines[split:]),
             "f": (forth, forth.lines), "l": (lisp, lisp.lines)}
    # the BURP section shares psicomp80.asm's labels; FORTH and LISP only add their own
    page = Page()
    for p, (lst, lines) in parts.items():
        page.plan_anchors(p, lines)

    body = []
    for view, p, title, rng, intro in SECTIONS:
        lst, lines = parts[p]
        code_bytes = sum(len(ln["bytes"]) for ln in lines)
        body.append(f'<section class="view" id="{view}" data-view="{view}" data-p="{p}">'
                    f'<div class="shead"><span class="kicker">{rng}</span><h2>{title}</h2>{intro}</div>'
                    f'{label_index(lst, lines, p, page)}'
                    f'<div class="lstwrap"><pre class="lst">{page.rows(lst, lines, p)}</pre></div></section>')

    dumps = []
    for name, lang, p in ROMS:
        rom = roms[name]
        crc = f"{zlib.crc32(rom) & 0xffffffff:08x}"
        sha = hashlib.sha1(rom).hexdigest()
        dumps.append(f'<div class="dump"><h3>{name} <span>monitor + {lang} · {len(rom)} bytes</span></h3>'
                     f'<p class="sums"><span>CRC <b>{crc}</b></span><span>SHA1 <b>{sha}</b></span></p>'
                     f'<div class="lstwrap"><pre class="hex" data-p="{p}">{hex_dump(name, rom, p, page)}</pre></div></div>')
    body.append('<section class="view" id="hex" data-view="hex" data-p="hex">'
                '<div class="shead"><span class="kicker">0000–0BFF · three ROMs</span><h2>Hex dumps</h2>'
                '<p>The three 3 KB ROM images, sixteen bytes to a line as in the magazine\'s listing. '
                'The first 400h bytes, the monitor, are the same in all three. Click an address or a byte to see '
                'it in the listing. The checksums are the ones the MAME driver expects.</p>'
                '<div class="tsel" role="group" aria-label="Text column"><span class="lbl">Text column</span>'
                '<button type="button" data-t="d" aria-pressed="true">Screen codes</button>'
                '<button type="button" data-t="a" aria-pressed="false">ASCII</button></div></div>'
                + "".join(dumps) + '</section>')

    html_out = TEMPLATE.replace("{{BODY}}", "".join(body))
    for k, v in LINKS.items():
        html_out = html_out.replace(f'href="{k}"', f'href="{v}"')
    out = BUILD / "roms_artifact.html" if len(sys.argv) > 1 else OUT
    out.write_text(html_out)
    print(f"{out.name}: {len(html_out) // 1024} KB")


TEMPLATE = r"""<title>COMP80 ROM Listings</title>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@62..125,500..800&amp;family=Source+Sans+3:ital,wght@0,400;0,600;1,400&amp;family=JetBrains+Mono:wght@400;600&amp;display=swap">
<style>
/* Layout: an assembler listing. Address, bytes and source in fixed columns, one view per ROM part. */
:root {
  --paper: #eceff2; --ink: #14181d; --muted: #59626c; --rule: #ccd2d9; --sheet: #f6f8f9;
  --accent: #1c6a86; --mn: #7a3e9d; --nu: #8a5a00; --st: #2d7a3a; --cm: #66707a; --lb: #b23a48;
  --hit: rgba(28, 106, 134, .22);
  --display: "Archivo", "Arial Narrow", system-ui, sans-serif;
  --body: "Source Sans 3", system-ui, -apple-system, "Segoe UI", sans-serif;
  --mono: "JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --paper: #0e1114; --ink: #e5e9ed; --muted: #97a0aa; --rule: #252b32; --sheet: #13171b;
  --accent: #6bb4cd; --mn: #c79be0; --nu: #e0b25c; --st: #8fcf8f; --cm: #8a949e; --lb: #f08a96;
  --hit: rgba(107, 180, 205, .25); color-scheme: dark; } }
:root[data-theme="dark"] {
  --paper: #0e1114; --ink: #e5e9ed; --muted: #97a0aa; --rule: #252b32; --sheet: #13171b;
  --accent: #6bb4cd; --mn: #c79be0; --nu: #e0b25c; --st: #8fcf8f; --cm: #8a949e; --lb: #f08a96;
  --hit: rgba(107, 180, 205, .25); color-scheme: dark; }
body { background: var(--paper); color: var(--ink); font: 400 1.0625rem/1.55 var(--body); }
body::before { content: ""; position: fixed; inset: 0 0 auto; height: env(safe-area-inset-top, 0px); z-index: 10; background: var(--paper); }
.wrap { max-width: 76rem; margin: 0 auto;
  padding-left: max(16px, env(safe-area-inset-left, 0px));
  padding-right: max(16px, env(safe-area-inset-right, 0px));
  padding-block: 2.5rem 4rem; display: grid; gap: 2rem; }
header { display: grid; gap: 1rem; max-width: 46rem; }
.kicker { font: 600 .75rem/1 var(--mono); letter-spacing: .12em; text-transform: uppercase; color: var(--accent); }
h1 { font: 800 clamp(2.4rem, 6vw, 4rem)/.95 var(--display); font-stretch: 70%; letter-spacing: -.01em; margin: 0; text-wrap: balance; }
header p { margin: 0; max-width: 62ch; }
a { color: var(--accent); }
header a, .shead a, footer a { font-weight: 600; text-decoration-thickness: 1px; text-underline-offset: 2px; }
code { font-family: var(--mono); font-size: .9em; }
.map { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 10rem), 1fr)); gap: 1px;
  background: var(--rule); border: 1px solid var(--rule); border-radius: 6px; overflow: hidden; max-width: 46rem; }
.map div { background: var(--paper); padding: .6rem .75rem; display: grid; gap: .15rem; }
.map b { font: 600 .8125rem/1.2 var(--mono); }
.map span { font-size: .875rem; color: var(--muted); }
nav { position: sticky; top: env(safe-area-inset-top, 0px); z-index: 5; background: var(--paper);
  display: flex; flex-wrap: wrap; align-items: center; gap: .5rem 1rem; padding-block: .6rem; border-bottom: 1px solid var(--rule); }
.tabs { display: flex; flex-wrap: wrap; gap: .25rem; }
.tabs a { font: 600 .875rem/1 var(--body); padding: .5rem .75rem; border-radius: 5px; text-decoration: none; color: var(--ink); }
.tabs a:hover { background: color-mix(in srgb, var(--accent) 10%, transparent); }
.tabs a[aria-current="true"] { background: var(--accent); color: var(--paper); }
form.go { display: flex; align-items: center; gap: .4rem; margin-left: auto; }
form.go label { font: 600 .6875rem/1 var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--muted); }
form.go input { font: 600 .875rem/1 var(--mono); width: 4.5rem; padding: .4rem .5rem; border: 1px solid var(--rule);
  border-radius: 5px; background: var(--sheet); color: var(--ink); text-transform: uppercase; }
form.go button, .tsel button { font: 600 .8125rem/1 var(--body); padding: .45rem .7rem; border: 1px solid var(--rule);
  border-radius: 5px; background: var(--sheet); color: var(--ink); cursor: pointer; }
[hidden] { display: none !important; }
.view { display: grid; gap: 1.25rem; scroll-margin-top: 4.5rem; }
.shead { display: grid; gap: .6rem; max-width: 46rem; }
h2 { font: 700 1.75rem/1.1 var(--display); font-stretch: 85%; margin: 0; }
.shead p { margin: 0; color: var(--muted); max-width: 62ch; }
.idx { max-width: 76rem; }
.idx summary { cursor: pointer; font-weight: 600; }
.idx summary span { font: 400 .8125rem/1 var(--mono); color: var(--muted); margin-left: .25rem; }
.idx div { display: flex; flex-wrap: wrap; gap: .3rem .9rem; padding-top: .75rem; font: 400 .8125rem/1.5 var(--mono); }
.idx a { text-decoration: none; color: var(--ink); white-space: nowrap; }
.idx a b { font-weight: 400; color: var(--muted); }
.idx a:hover { color: var(--accent); }
.lstwrap { overflow-x: auto; border: 1px solid var(--rule); border-radius: 6px; background: var(--sheet); min-width: 0; }
pre { margin: 0; padding: .6rem 0; font: 400 .78rem/1.5 var(--mono); tab-size: 8; }
pre > span { display: block; padding: 0 .9rem; white-space: pre; scroll-margin-top: 30vh; }
pre i { font-style: normal; color: var(--muted); }
pre u { text-decoration: none; color: var(--muted); }
pre a { text-decoration: none; }
pre a:hover { text-decoration: underline; }
.lb { color: var(--lb); font-weight: 600; }
.mn { color: var(--mn); }
.dr { color: var(--mn); font-style: italic; }
.nu { color: var(--nu); }
.st { color: var(--st); }
.cm { color: var(--cm); }
.r.c .cm { color: var(--cm); }
.hit { background: var(--hit); transition: background 2s ease-out; }
.dump { display: grid; gap: .5rem; }
h3 { font: 700 1.125rem/1.2 var(--display); font-stretch: 85%; margin: 0; display: flex; flex-wrap: wrap; gap: .25rem .75rem; align-items: baseline; }
h3 span { font: 400 .8125rem/1 var(--mono); color: var(--muted); }
.sums { margin: 0; display: flex; flex-wrap: wrap; gap: .25rem 1.25rem; font: 400 .75rem/1.4 var(--mono); color: var(--muted); min-width: 0; }
.sums span { overflow-wrap: anywhere; }
.sums b { font-weight: 600; color: var(--ink); }
.hex b { font-weight: 400; cursor: pointer; border-radius: 2px; }
.hex b:hover { background: var(--hit); }
.hex .ta { display: none; }
.ascii .hex .ta { display: inline; }
.ascii .hex .td { display: none; }
.td, .ta { color: var(--st); }
.tsel { display: flex; flex-wrap: wrap; align-items: center; gap: .4rem; }
.lbl { font: 600 .6875rem/1 var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--muted); margin-right: .25rem; }
.tsel button[aria-pressed="true"] { background: var(--accent); color: var(--paper); border-color: var(--accent); }
#back { position: fixed; z-index: 6; right: max(16px, calc(16px + env(safe-area-inset-right, 0px)));
  bottom: calc(16px + env(safe-area-inset-bottom, 0px)); font: 600 .875rem/1 var(--body); padding: .7rem 1rem;
  border-radius: 999px; border: 0; background: var(--accent); color: var(--paper); cursor: pointer;
  box-shadow: 0 4px 14px rgba(0, 0, 0, .25); }
#back b { font: 600 .8125rem/1 var(--mono); }
footer { border-top: 1px solid var(--rule); padding-top: 1rem; color: var(--muted); font-size: .875rem; max-width: 62ch; }
@media (max-width: 40rem) { form.go { margin-left: 0; } pre { font-size: .72rem; } }
</style>

<div class="wrap">
<header>
  <span class="kicker">PSI COMP80 · the 3 KB ROM · 0000–0BFF</span>
  <h1>COMP80 ROM Listings</h1>
  <p>Annotated listings of the PSI COMP80's ROMs: the monitor that every ROM starts with, and the three languages that can sit above it in the remaining 2 KB. BURP is the original, from the Wireless World articles; FORTH and LISP were written for this project. Every line shows its address and the bytes it assembles to, read from the ROM images, and every name or branch address is a link to the line it means.</p>
  <p>See also the <a href="screenshots.html">screenshots</a>, the <a href="lisp.html">LISP page</a>, the <a href="hardware.html">hardware</a> and the <a href="emulator.html">emulator</a>, which runs all three ROMs.</p>
  <div class="map" aria-label="Memory map">
    <div><b>0000–03FF</b><span>Monitor ROM, 1 KB</span></div>
    <div><b>0400–0BFF</b><span>BURP, FORTH or LISP, 2 KB</span></div>
    <div><b>0C00–1FFF</b><span>RAM, 5 KB</span></div>
    <div><b>8000–87FF</b><span>Screen, 64 × 32</span></div>
  </div>
</header>
<nav>
  <div class="tabs">
    <a href="#monitor">Monitor</a><a href="#burp">BURP</a><a href="#forth">FORTH</a><a href="#lisp">LISP</a><a href="#hex">Hex dumps</a>
  </div>
  <form class="go"><label for="goaddr">Address</label><input id="goaddr" maxlength="4" autocomplete="off" spellcheck="false" placeholder="0800"><button type="submit">Go</button></form>
</nav>
{{BODY}}
<footer>Generated by <code>rom/make_page.py</code> from the sources and the ROM images; <code>rom/build.sh</code> first checks that each source assembles to its ROM byte for byte.</footer>
</div>
<button id="back" type="button" hidden>← Back to <b></b></button>

<script>
(() => {
  const views = [...document.querySelectorAll(".view")];
  const names = views.map(v => v.id);
  const tabs = [...document.querySelectorAll(".tabs a")];
  const back = document.getElementById("back");
  const trail = [];
  let current = null;

  function show(name) {
    current = name;
    for (const v of views) v.hidden = v.id !== name;
    for (const t of tabs) t.setAttribute("aria-current", t.getAttribute("href") === "#" + name);
  }
  function remember(id) {
    try { history.replaceState(null, "", "#" + id); } catch (e) {}
  }
  function flash(el) {
    el.classList.remove("hit"); void el.offsetWidth; el.classList.add("hit");
    setTimeout(() => el.classList.remove("hit"), 2500);
  }
  // the row for an address in a section: the nearest one at or below it
  function row(p, addr) {
    for (let a = addr; a >= 0 && a > addr - 64; a--) {
      const el = document.getElementById(p + a.toString(16).padStart(4, "0"));
      if (el) return el;
    }
    return null;
  }
  function here() {
    // the address of the first row on screen, for the back button
    const v = document.getElementById(current);
    for (const el of v.querySelectorAll("pre > span[id], pre > span[data-a]")) {
      if (el.getBoundingClientRect().bottom > window.innerHeight * 0.3)
        return (el.dataset.a || el.id.slice(1)).toUpperCase();
    }
    return current;
  }
  function go(el, push) {
    if (!el) return;
    if (push) {
      trail.push({ view: current, y: window.scrollY, label: here() });
      back.hidden = false;
      back.querySelector("b").textContent = trail[trail.length - 1].label;
    }
    show(el.closest(".view").id);
    el.scrollIntoView({ block: "center" });
    flash(el);
    remember(el.id || current);
  }
  function openView(name) {
    show(name);
    remember(name);
    const h = document.querySelector("header"); if (window.scrollY > h.offsetTop + h.offsetHeight) document.getElementById(name).scrollIntoView({ block: "start" });
  }

  document.addEventListener("click", e => {
    const b = e.target.closest(".hex b");
    if (b) {
      const line = b.parentElement, cells = [...line.querySelectorAll("b")];
      const addr = parseInt(line.dataset.a, 16) + cells.indexOf(b);
      go(row(addr < 0x400 ? "m" : line.dataset.s, addr), true);
      return;
    }
    const a = e.target.closest('a[href^="#"]');
    if (!a) return;
    const id = a.getAttribute("href").slice(1);
    e.preventDefault();
    if (names.includes(id)) openView(id);
    else go(document.getElementById(id), true);
  });
  back.addEventListener("click", () => {
    const t = trail.pop();
    show(t.view);
    window.scrollTo(0, t.y);
    back.hidden = trail.length === 0;
    if (trail.length) back.querySelector("b").textContent = trail[trail.length - 1].label;
  });
  document.querySelector("form.go").addEventListener("submit", e => {
    e.preventDefault();
    const input = document.getElementById("goaddr");
    const addr = parseInt(input.value, 16);
    if (isNaN(addr) || addr < 0 || addr > 0xbff) { input.select(); return; }
    let el;
    if (current === "hex") {
      el = document.querySelector(`.hex .h[data-a="${(addr & ~15).toString(16).padStart(4, "0")}"]`);
    } else {
      const p = document.getElementById(current).dataset.p;
      el = row(addr < 0x400 ? "m" : (p === "m" ? "b" : p), addr);
    }
    go(el, true);
  });
  for (const btn of document.querySelectorAll(".tsel button")) {
    btn.addEventListener("click", () => {
      document.getElementById("hex").classList.toggle("ascii", btn.dataset.t === "a");
      for (const o of document.querySelectorAll(".tsel button")) o.setAttribute("aria-pressed", o === btn);
      try { localStorage.setItem("c80-text", btn.dataset.t); } catch (e) {}
    });
  }
  try { if (localStorage.getItem("c80-text") === "a") document.querySelector('.tsel [data-t="a"]').click(); } catch (e) {}

  const start = location.hash.slice(1);
  if (names.includes(start)) show(start);
  else if (start && document.getElementById(start)) go(document.getElementById(start), false);
  else show("monitor");
})();
</script>
"""

if __name__ == "__main__":
    main()
