"""Build the standalone COMP80 emulator page.

  python3 web/build.py

Reads the fonts from psicomp80.cpp, the three ROMs, the example programs and
the help pages, writes web/build/data.js (used by the Node tests) and puts
everything into one self-contained page, ../emulator.html.  The same page
without the document around it goes to web/build/artifact.html, for
publishing as a claude.ai artifact.
"""
import base64, json, re
from pathlib import Path

WEB = Path(__file__).resolve().parent
REPO = WEB.parent


def fonts():
    src = (REPO / "psicomp80.cpp").read_text()

    def table(name):
        body = src[src.index(name + " = {{"):]
        body = body[: body.index("}};")]
        rows = []
        for line in body.splitlines():
            line = line.split("//")[0]
            if "BLANK" in line:
                rows.append([0] * 8)
                continue
            m = re.search(r"\{([^{}]*)\}", line)
            if m:
                rows.append([int(v, 16) for v in m.group(1).split(",")])
        return rows

    ascii_ = table("psicomp80_state::ascii_font_64x8x5")
    gfx = table("psicomp80_state::gfx_font_64x10x6")
    assert len(ascii_) == 64 and len(gfx) == 64, (len(ascii_), len(gfx))
    return {"ascii": ascii_, "gfx": gfx}


def b64(path):
    return base64.b64encode((REPO / path).read_bytes()).decode()


def data():
    return {
        "fonts": fonts(),
        "roms": {
            "burp": b64("psicomp80.rom"),
            "forth": b64("psicomp80_forth.rom"),
            "lisp": b64("psicomp80_lisp.rom"),
        },
        "bins": {
            "life": b64("life/life.bin"),
            "boat": b64("pictures/boat.bin"),
            "schmitt": b64("pictures/schmitt.bin"),
            "cover": b64("pictures/cover.bin"),
        },
        "sources": {
            "life.fs": (REPO / "forth/examples/life.fs").read_text(),
            "mandel.fs": (REPO / "forth/examples/mandel.fs").read_text(),
            "deriv.lsp": (REPO / "lisp/examples/deriv.lsp").read_text(),
            "hanoi.lsp": (REPO / "lisp/examples/hanoi.lsp").read_text(),
            "queens.lsp": (REPO / "lisp/examples/queens.lsp").read_text(),
        },
    }


def main():
    d = data()
    js = "const C80DATA = " + json.dumps(d, separators=(",", ":")) + ";\n"
    (WEB / "build").mkdir(exist_ok=True)
    (WEB / "build" / "data.js").write_text(js + "if (typeof module !== 'undefined') module.exports = C80DATA;\n")
    if not (WEB / "src" / "page.html").exists():
        return
    page = (WEB / "src" / "page.html").read_text()
    scripts = "\n".join((WEB / "src" / f).read_text() for f in ("z80.js", "comp80.js", "examples.js", "app.js"))
    page = page.replace("<!--DATA-->", "<script>\n" + js + "</script>")
    page = page.replace("<!--SCRIPTS-->", "<script>\n" + scripts + "</script>")
    page = page.replace("<!--HELP-->", (WEB / "src" / "help.html").read_text())
    # The artifact host wraps a fragment in its own document; the standalone
    # page needs the document around it.
    (WEB / "build" / "artifact.html").write_text(page)
    doc = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
           '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
           '<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}'
           'body{margin:0}</style>\n</head>\n<body>\n' + page + '\n</body>\n</html>\n')
    (REPO / "emulator.html").write_text(doc)
    print(f"emulator.html: {len(doc)} bytes")


if __name__ == "__main__":
    main()
