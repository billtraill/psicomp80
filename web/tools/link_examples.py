#!/usr/bin/env python3
"""Link each language's README to the web emulator.

At the top of <lang>/README.md goes a link that powers the emulator on with
that ROM (emulator.html#rom=<lang>), and each row of an examples table whose
first cell is an example's file (`sieve.pl0`) gets a ▶ link that runs it
(emulator.html#example=<id>); the file can have another extension or a
folder (`examples/fib.mou`).  Examples with no such row are listed, with
their links, in a section "In the emulator" before the tests.  The examples
are the ones in web/src/examples.js.  Run it again after adding examples;
rows that already have a link are left alone.
"""
import json
import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BASE = "https://billtraill.github.io/psicomp80/emulator.html"
NAMES = {"burp": "BURP", "forth": "FORTH", "lisp": "LISP", "basic": "BASIC", "logo": "Logo",
         "chip8": "CHIP-8", "focal": "FOCAL", "pilot": "PILOT", "zasm": "ZASM", "prolog": "Prolog",
         "vtl": "VTL-2", "mouse": "Mouse", "befunge": "Befunge", "sheet": "CALC", "trac": "TRAC",
         "pl0": "PL/0", "bf": "BF", "ed": "ED", "db": "FILE", "adv": "QUEST", "apl": "APL"}


SECTION = "## In the emulator"
CELL = re.compile(r"^\| `([^`]+)`")


def examples():
    js = (REPO / "web/src/examples.js").read_text()
    out = subprocess.run(["node", "-e", js.replace("const EXAMPLES", "global.EXAMPLES") +
                          ";console.log(JSON.stringify(EXAMPLES.map(e => [e.id, e.lang, e.file || null, e.title])))"],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def main():
    exs = examples()
    for lang, name in NAMES.items():
        readme = REPO / lang / "README.md"
        text = readme.read_text()
        lines = text.split("\n")
        # the section of examples without a row, made afresh each time
        if SECTION in lines:
            a = lines.index(SECTION)
            b = next((i for i in range(a + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
            del lines[a:b]
        rest = []
        for eid, elang, file, title in exs:
            if elang != lang:
                continue
            hits = []
            for i, ln in enumerate(lines):
                m = CELL.match(ln)
                if file and m and Path(m.group(1)).stem == Path(file).stem:
                    hits.append(i)
                    if not ln[m.end():].startswith(" [▶]("):
                        lines[i] = ln[:m.end(1) + 1] + f" [▶]({BASE}#example={eid})" + ln[m.end(1) + 1:]
            if not hits:
                rest.append(f"- [{title}]({BASE}#example={eid})")
        if rest:
            at = next((i for i, ln in enumerate(lines) if ln.startswith("## Tests")), len(lines))
            lines[at:at] = [SECTION, "", "These examples run in the web emulator from these links:", ""] + rest + [""]
        # the link at the top, after the title
        top = f"[Run {name} in the web emulator]({BASE}#rom={lang}). " + (
            "Each example below has a ▶ link that types it in and runs it there."
            if any(" [▶](" in ln for ln in lines) else
            "The examples are linked under In the emulator, below; each types one in and runs it there.")
        old = next((i for i, ln in enumerate(lines) if ln.startswith(f"[Run {name} in the web emulator]")), None)
        if old is not None:
            lines[old] = top
        else:
            h1 = next(i for i, ln in enumerate(lines) if ln.startswith("# "))
            lines[h1 + 1:h1 + 1] = ["", top]
        new = "\n".join(lines)
        if new != text:
            readme.write_text(new)
        if rest:
            print(f"{lang}: {len(rest)} in the section")


if __name__ == "__main__":
    main()
