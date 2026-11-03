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
            "basic": b64("psicomp80_basic.rom"),
            "logo": b64("psicomp80_logo.rom"),
            "chip8": b64("psicomp80_chip8.rom"),
            "focal": b64("psicomp80_focal.rom"),
            "pilot": b64("psicomp80_pilot.rom"),
            "zasm": b64("psicomp80_zasm.rom"),
            "prolog": b64("psicomp80_prolog.rom"),
            "vtl": b64("psicomp80_vtl.rom"),
            "mouse": b64("psicomp80_mouse.rom"),
            "befunge": b64("psicomp80_befunge.rom"),
            "sheet": b64("psicomp80_sheet.rom"),
            "trac": b64("psicomp80_trac.rom"),
            "pl0": b64("psicomp80_pl0.rom"),
            "bf": b64("psicomp80_bf.rom"),
        },
        "bins": {
            "life": b64("life/life.bin"),
            "plasma": b64("plasma/plasma.bin"),
            "banner": b64("banner/banner.bin"),
            "fire": b64("fire/fire.bin"),
            "dump": b64("dump/dump.bin"),
            "boat": b64("pictures/boat.bin"),
            "schmitt": b64("pictures/schmitt.bin"),
            "cover": b64("pictures/cover.bin"),
            "c8bounce": b64("chip8/examples/bounce.ch8"),
            "c8keys": b64("chip8/examples/keys.ch8"),
            "c8dodge": b64("chip8/examples/dodge.ch8"),
            "c8kaleido": b64("chip8/examples/kaleido.ch8"),
        },
        "sources": {
            "life.asm": (REPO / "life/life.asm").read_text(),
            "plasma.asm": (REPO / "plasma/plasma.asm").read_text(),
            "banner.asm": (REPO / "banner/banner.asm").read_text(),
            "fire.asm": (REPO / "fire/fire.asm").read_text(),
            "dump.asm": (REPO / "dump/dump.asm").read_text(),
            "life.fs": (REPO / "forth/examples/life.fs").read_text(),
            "mandel.fs": (REPO / "forth/examples/mandel.fs").read_text(),
            "sier.fs": (REPO / "forth/examples/sier.fs").read_text(),
            "hilbert.fs": (REPO / "forth/examples/hilbert.fs").read_text(),
            "hanoi.fs": (REPO / "forth/examples/hanoi.fs").read_text(),
            "dragon.fs": (REPO / "forth/examples/dragon.fs").read_text(),
            "koch.fs": (REPO / "forth/examples/koch.fs").read_text(),
            "ant.fs": (REPO / "forth/examples/ant.fs").read_text(),
            "sieve.fs": (REPO / "forth/examples/sieve.fs").read_text(),
            "snake.fs": (REPO / "forth/examples/snake.fs").read_text(),
            "fern.fs": (REPO / "forth/examples/fern.fs").read_text(),
            "sort.fs": (REPO / "forth/examples/sort.fs").read_text(),
            "clock.fs": (REPO / "forth/examples/clock.fs").read_text(),
            "liss.fs": (REPO / "forth/examples/liss.fs").read_text(),
            "rule.fs": (REPO / "forth/examples/rule.fs").read_text(),
            "maze.fs": (REPO / "forth/examples/maze.fs").read_text(),
            "stars.fs": (REPO / "forth/examples/stars.fs").read_text(),
            "balls.fs": (REPO / "forth/examples/balls.fs").read_text(),
            "deriv.lsp": (REPO / "lisp/examples/deriv.lsp").read_text(),
            "hanoi.lsp": (REPO / "lisp/examples/hanoi.lsp").read_text(),
            "queens.lsp": (REPO / "lisp/examples/queens.lsp").read_text(),
            "sier.lsp": (REPO / "lisp/examples/sier.lsp").read_text(),
            "hilbert.lsp": (REPO / "lisp/examples/hilbert.lsp").read_text(),
            "eliza.lsp": (REPO / "lisp/examples/eliza.lsp").read_text(),
            "simp.lsp": (REPO / "lisp/examples/simp.lsp").read_text(),
            "perms.lsp": (REPO / "lisp/examples/perms.lsp").read_text(),
            "fib.lsp": (REPO / "lisp/examples/fib.lsp").read_text(),
            "roman.lsp": (REPO / "lisp/examples/roman.lsp").read_text(),
            "river.lsp": (REPO / "lisp/examples/river.lsp").read_text(),
            "eval.lsp": (REPO / "lisp/examples/eval.lsp").read_text(),
            "unify.lsp": (REPO / "lisp/examples/unify.lsp").read_text(),
            "animal.lsp": (REPO / "lisp/examples/animal.lsp").read_text(),
            "guess.bas": (REPO / "basic/examples/guess.bas").read_text(),
            "primes.bas": (REPO / "basic/examples/primes.bas").read_text(),
            "lines.bas": (REPO / "basic/examples/lines.bas").read_text(),
            "worm.bas": (REPO / "basic/examples/worm.bas").read_text(),
            "flower.logo": (REPO / "logo/examples/flower.logo").read_text(),
            "spiral.logo": (REPO / "logo/examples/spiral.logo").read_text(),
            "tree.logo": (REPO / "logo/examples/tree.logo").read_text(),
            "flake.logo": (REPO / "logo/examples/flake.logo").read_text(),
            "stars.logo": (REPO / "logo/examples/stars.logo").read_text(),
            "bounce.c8": (REPO / "chip8/examples/bounce.c8").read_text(),
            "keys.c8": (REPO / "chip8/examples/keys.c8").read_text(),
            "dodge.c8": (REPO / "chip8/examples/dodge.c8").read_text(),
            "kaleido.c8": (REPO / "chip8/examples/kaleido.c8").read_text(),
            "roots.foc": (REPO / "focal/examples/roots.foc").read_text(),
            "temp.foc": (REPO / "focal/examples/temp.foc").read_text(),
            "interest.foc": (REPO / "focal/examples/interest.foc").read_text(),
            "guess.foc": (REPO / "focal/examples/guess.foc").read_text(),
            "sine.foc": (REPO / "focal/examples/sine.foc").read_text(),
            "greet.pil": (REPO / "pilot/examples/greet.pil").read_text(),
            "quiz.pil": (REPO / "pilot/examples/quiz.pil").read_text(),
            "tables.pil": (REPO / "pilot/examples/tables.pil").read_text(),
            "story.pil": (REPO / "pilot/examples/story.pil").read_text(),
            "draw.pil": (REPO / "pilot/examples/draw.pil").read_text(),
            "nmi.txt": (REPO / "zasm/examples/nmi.txt").read_text(),
            "pattern.txt": (REPO / "zasm/examples/pattern.txt").read_text(),
            "countdown.txt": (REPO / "zasm/examples/countdown.txt").read_text(),
            "life.txt": (REPO / "zasm/examples/life.txt").read_text(),
            "family.pl": (REPO / "prolog/examples/family.pl").read_text(),
            "lists.pl": (REPO / "prolog/examples/lists.pl").read_text(),
            "colour.pl": (REPO / "prolog/examples/colour.pl").read_text(),
            "path.pl": (REPO / "prolog/examples/path.pl").read_text(),
            "primes.vtl": (REPO / "vtl/examples/primes.vtl").read_text(),
            "guess.vtl": (REPO / "vtl/examples/guess.vtl").read_text(),
            "fib.vtl": (REPO / "vtl/examples/fib.vtl").read_text(),
            "circles.vtl": (REPO / "vtl/examples/circles.vtl").read_text(),
            "chaos.vtl": (REPO / "vtl/examples/chaos.vtl").read_text(),
            "fib.mou": (REPO / "mouse/examples/fib.mou").read_text(),
            "fact.mou": (REPO / "mouse/examples/fact.mou").read_text(),
            "sieve.mou": (REPO / "mouse/examples/sieve.mou").read_text(),
            "guess.mou": (REPO / "mouse/examples/guess.mou").read_text(),
            "circles.mou": (REPO / "mouse/examples/circles.mou").read_text(),
            "hello.bef": (REPO / "befunge/examples/hello.bef").read_text(),
            "count.bef": (REPO / "befunge/examples/count.bef").read_text(),
            "fact.bef": (REPO / "befunge/examples/fact.bef").read_text(),
            "stars.bef": (REPO / "befunge/examples/stars.bef").read_text(),
            "budget.cal": (REPO / "sheet/examples/budget.cal").read_text(),
            "interest.cal": (REPO / "sheet/examples/interest.cal").read_text(),
            "times.cal": (REPO / "sheet/examples/times.cal").read_text(),
            "temp.cal": (REPO / "sheet/examples/temp.cal").read_text(),
            "hello.trac": (REPO / "trac/examples/hello.trac").read_text(),
            "fact.trac": (REPO / "trac/examples/fact.trac").read_text(),
            "rev.trac": (REPO / "trac/examples/rev.trac").read_text(),
            "letter.trac": (REPO / "trac/examples/letter.trac").read_text(),
            "squares.pl0": (REPO / "pl0/examples/squares.pl0").read_text(),
            "primes.pl0": (REPO / "pl0/examples/primes.pl0").read_text(),
            "gcd.pl0": (REPO / "pl0/examples/gcd.pl0").read_text(),
            "fact.pl0": (REPO / "pl0/examples/fact.pl0").read_text(),
            "rings.pl0": (REPO / "pl0/examples/rings.pl0").read_text(),
            "hello.bf": (REPO / "bf/examples/hello.bf").read_text(),
            "count.bf": (REPO / "bf/examples/count.bf").read_text(),
            "add.bf": (REPO / "bf/examples/add.bf").read_text(),
            "alpha.bf": (REPO / "bf/examples/alpha.bf").read_text(),
            "reverse.bf": (REPO / "bf/examples/reverse.bf").read_text(),
            "fib.bf": (REPO / "bf/examples/fib.bf").read_text(),
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
