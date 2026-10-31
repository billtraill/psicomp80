"""Make rom/psicomp80.asm, an annotated source for the monitor + BURP ROM.

  python3 rom/tools/make_rom_asm.py

A one-off conversion, kept as a record of where psicomp80.asm came from.
The instructions are disassembled afresh from ../psicomp80.rom; the
comments, labels and section notes come from the earlier annotated
disassemblies (now in ../old/): the instruction and data boundaries are
taken from the listing in comp80_monitor_plus_burp_0000_0BFF_annotated.asm,
and comments from the two BURP markdown disassemblies fill in where it has
none. The result is ordinary z80asm source; rom/build.sh assembles it and
checks that it gives the ROM byte for byte.
"""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
OLD = REPO / "old"
ROM = (REPO / "psicomp80.rom").read_bytes()

# ---------------------------------------------------------------- disassembler

R = ["B", "C", "D", "E", "H", "L", "(HL)", "A"]
RP = ["BC", "DE", "HL", "SP"]
RP2 = ["BC", "DE", "HL", "AF"]
CC = ["NZ", "Z", "NC", "C", "PO", "PE", "P", "M"]
ALU = ["ADD A,", "ADC A,", "SUB ", "SBC A,", "AND ", "XOR ", "OR ", "CP "]
ROT = ["RLC", "RRC", "RL", "RR", "SLA", "SRA", None, "SRL"]
H2 = lambda v: f"${v:02X}"
H4 = lambda v: f"${v:04X}"


def decode(mem, pc):
    """Decode the instruction at pc: (text, length, target, kind) with
    {T} in text standing for a branch target, or None if not a documented
    instruction."""
    b = lambda i: mem[(pc + i) & 0xFFFF]
    w = lambda i: b(i) | (b(i + 1) << 8)
    op = b(0)
    x, y, z = op >> 6, (op >> 3) & 7, op & 7; p, q = y >> 1, y & 1

    if op in (0xDD, 0xFD):
        return decode_index(mem, pc, "IX" if op == 0xDD else "IY")
    if op == 0xCB:
        o = b(1)
        cx, cy, cz = o >> 6, (o >> 3) & 7, o & 7
        if cx == 0:
            return (None if ROT[cy] is None else f"{ROT[cy]} {R[cz]}", 2, None, None)
        return (f"{['', 'BIT', 'RES', 'SET'][cx]} {cy},{R[cz]}", 2, None, None)
    if op == 0xED:
        return decode_ed(mem, pc)
    if x == 1:
        return ("HALT" if op == 0x76 else f"LD {R[y]},{R[z]}", 1, None, None)
    if x == 2:
        return (f"{ALU[y]}{R[z]}", 1, None, None)
    if x == 0:
        if z == 0:
            if y == 0: return ("NOP", 1, None, None)
            if y == 1: return ("EX AF,AF'", 1, None, None)
            d = b(1) - 256 if b(1) > 127 else b(1)
            t = (pc + 2 + d) & 0xFFFF
            if y == 2: return ("DJNZ {T}", 2, t, "jr")
            if y == 3: return ("JR {T}", 2, t, "jr")
            return (f"JR {CC[y - 4]},{{T}}", 2, t, "jr")
        if z == 1:
            return ((f"LD {RP[p]},{H4(w(1))}", 3, None, None) if q == 0 else (f"ADD HL,{RP[p]}", 1, None, None))
        if z == 2:
            return [("LD (BC),A", 1, None, None), ("LD A,(BC)", 1, None, None),
                    ("LD (DE),A", 1, None, None), ("LD A,(DE)", 1, None, None),
                    (f"LD ({H4(w(1))}),HL", 3, None, None), (f"LD HL,({H4(w(1))})", 3, None, None),
                    (f"LD ({H4(w(1))}),A", 3, None, None), (f"LD A,({H4(w(1))})", 3, None, None)][y]
        if z == 3: return (f"{'INC' if q == 0 else 'DEC'} {RP[p]}", 1, None, None)
        if z == 4: return (f"INC {R[y]}", 1, None, None)
        if z == 5: return (f"DEC {R[y]}", 1, None, None)
        if z == 6: return (f"LD {R[y]},{H2(b(1))}", 2, None, None)
        return (["RLCA", "RRCA", "RLA", "RRA", "DAA", "CPL", "SCF", "CCF"][y], 1, None, None)
    # x == 3
    if z == 0: return (f"RET {CC[y]}", 1, None, None)
    if z == 1:
        if q == 0: return (f"POP {RP2[p]}", 1, None, None)
        return (["RET", "EXX", "JP (HL)", "LD SP,HL"][p], 1, None, None)
    if z == 2: return (f"JP {CC[y]},{{T}}", 3, w(1), "jp")
    if z == 3:
        if y == 0: return ("JP {T}", 3, w(1), "jp")
        if y == 2: return (f"OUT ({H2(b(1))}),A", 2, None, None)
        if y == 3: return (f"IN A,({H2(b(1))})", 2, None, None)
        return ([None, None, None, None, "EX (SP),HL", "EX DE,HL", "DI", "EI"][y], 1, None, None)
    if z == 4: return (f"CALL {CC[y]},{{T}}", 3, w(1), "call")
    if z == 5:
        if q == 0: return (f"PUSH {RP2[p]}", 1, None, None)
        if p == 0: return ("CALL {T}", 3, w(1), "call")
        return (None, 1, None, None)
    if z == 6: return (f"{ALU[y]}{H2(b(1))}", 2, None, None)
    return (f"RST {H2(y * 8)}", 1, None, None)


def decode_index(mem, pc, ix):
    b = lambda i: mem[(pc + i) & 0xFFFF]
    w = lambda i: b(i) | (b(i + 1) << 8)
    op = b(1)
    dsp = lambda i: (lambda d: f"({ix}{'+' if d >= 0 else '-'}{H2(abs(d))})")(b(i) - 256 if b(i) > 127 else b(i))
    x, y, z = op >> 6, (op >> 3) & 7, op & 7; p, q = y >> 1, y & 1
    if op == 0xCB:
        o = b(3)
        cx, cy, cz = o >> 6, (o >> 3) & 7, o & 7
        if cz != 6: return (None, 4, None, None)
        if cx == 0: return (None if ROT[cy] is None else f"{ROT[cy]} {dsp(2)}", 4, None, None)
        return (f"{['', 'BIT', 'RES', 'SET'][cx]} {cy},{dsp(2)}", 4, None, None)
    table = {
        0x21: (f"LD {ix},{H4(w(2))}", 4), 0x22: (f"LD ({H4(w(2))}),{ix}", 4), 0x2A: (f"LD {ix},({H4(w(2))})", 4),
        0x23: (f"INC {ix}", 2), 0x2B: (f"DEC {ix}", 2), 0x09: (f"ADD {ix},BC", 2), 0x19: (f"ADD {ix},DE", 2),
        0x29: (f"ADD {ix},{ix}", 2), 0x39: (f"ADD {ix},SP", 2), 0x34: (f"INC {dsp(2)}", 3), 0x35: (f"DEC {dsp(2)}", 3),
        0x36: (f"LD {dsp(2)},{H2(b(3))}", 4), 0xE1: (f"POP {ix}", 2), 0xE5: (f"PUSH {ix}", 2),
        0xE3: (f"EX (SP),{ix}", 2), 0xE9: (f"JP ({ix})", 2), 0xF9: (f"LD SP,{ix}", 2),
    }
    if op in table:
        t, n = table[op]
        return (t, n, None, None)
    if x == 1 and op != 0x76 and (y == 6) != (z == 6):
        return ((f"LD {dsp(2)},{R[z]}", 3, None, None) if y == 6 else (f"LD {R[y]},{dsp(2)}", 3, None, None))
    if x == 2 and z == 6:
        return (f"{ALU[y]}{dsp(2)}", 3, None, None)
    return (None, 2, None, None)


def decode_ed(mem, pc):
    b = lambda i: mem[(pc + i) & 0xFFFF]
    w = lambda i: b(i) | (b(i + 1) << 8)
    op = b(1)
    x, y, z = op >> 6, (op >> 3) & 7, op & 7; p, q = y >> 1, y & 1
    if x == 1:
        if z == 0: return ((f"IN {R[y]},(C)" if y != 6 else None), 2, None, None)
        if z == 1: return ((f"OUT (C),{R[y]}" if y != 6 else None), 2, None, None)
        if z == 2: return (f"{'SBC' if q == 0 else 'ADC'} HL,{RP[p]}", 2, None, None)
        if z == 3: return ((f"LD ({H4(w(2))}),{RP[p]}" if q == 0 else f"LD {RP[p]},({H4(w(2))})"), 4, None, None)
        if op == 0x44: return ("NEG", 2, None, None)
        if op == 0x45: return ("RETN", 2, None, None)
        if op == 0x4D: return ("RETI", 2, None, None)
        if op in (0x46, 0x56, 0x5E): return (f"IM {[0, 1, 2][[0x46, 0x56, 0x5E].index(op)]}", 2, None, None)
        named = {0x47: "LD I,A", 0x4F: "LD R,A", 0x57: "LD A,I", 0x5F: "LD A,R", 0x67: "RRD", 0x6F: "RLD"}
        return (named.get(op), 2, None, None)
    block = {0xA0: "LDI", 0xA8: "LDD", 0xB0: "LDIR", 0xB8: "LDDR", 0xA1: "CPI", 0xA9: "CPD", 0xB1: "CPIR", 0xB9: "CPDR",
             0xA2: "INI", 0xAA: "IND", 0xB2: "INIR", 0xBA: "INDR", 0xA3: "OUTI", 0xAB: "OUTD", 0xB3: "OTIR", 0xBB: "OTDR"}
    return (block.get(op), 2, None, None)


# ---------------------------------------------------------------- old annotations

CITE = re.compile(r"\s*\(?\s*file\S*?turn\S*?L\d+(?:-L\d+)?\)?")


def clean(s):
    s = CITE.sub("", s)
    s = s.replace("**", "").replace(" ", " ")
    return s.rstrip()


def parse_old_asm():
    """Instruction starts, data blocks, labels, comments from the old listing."""
    lines = (OLD / "comp80_monitor_plus_burp_0000_0BFF_annotated.asm").read_text().splitlines()
    items = {}          # addr -> {"data": [bytes] or None, "comment": str}
    labels = {}         # addr -> [names]
    before = {}         # addr -> [comment lines]
    equates = []
    header = []
    pending_c, pending_l = [], []
    seen_code = False
    for raw in lines:
        line = raw.rstrip()
        m = re.match(r"^([0-9A-F]{4}):\s*(.*)$", line)
        if m:
            addr = int(m.group(1), 16)
            rest = m.group(2)
            comment = ""
            if ";" in rest:
                rest, comment = rest.split(";", 1)
            dm = re.search(r"\bDB\s+(\$[0-9A-Fa-f]{2}(?:\s*,\s*\$[0-9A-Fa-f]{2})*)", rest)
            data = [int(v.strip()[1:], 16) for v in dm.group(1).split(",")] if dm and "$" in rest.split("DB", 1)[1][:4] else None
            # an instruction line whose own text carries a second comment, e.g. "CALL $03E7 — MON: ..."
            if data is None and "—" in rest:
                extra = rest.split("—", 1)[1].strip()
                comment = (extra + "; " + comment) if comment.strip() else extra
            items[addr] = {"data": data, "comment": clean(comment.strip())}
            if pending_c:
                before.setdefault(addr, []).extend(pending_c)
            if pending_l:
                labels.setdefault(addr, []).extend(pending_l)
            pending_c, pending_l = [], []
            seen_code = True
            continue
        em = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*):?\s+EQU\s+(.*)$", line, re.I)
        if em:
            equates.append(f"{em.group(1) + ':':<16}EQU {clean(em.group(2))}")
            continue
        lm = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(;.*)?$", line)
        if lm:
            pending_l.append(lm.group(1))
            if lm.group(2):
                pending_c.append(clean(lm.group(2)))
            continue
        if line.strip().startswith(";"):
            (pending_c if seen_code else header).append(clean(line.strip()))
            continue
        if not line.strip():
            if pending_c and pending_c[-1] != "":
                pending_c.append("")
            elif not seen_code and header and header[-1] != "":
                header.append("")
    return items, labels, before, equates, header


def parse_old_md():
    """Section names and per-instruction comments from the BURP markdown."""
    names, comments = {}, {}
    for f in ("burp_disassembly_0400_0BFF.md", "burp_disassembly_0400_0BFF_pathmap.md"):
        for line in (OLD / f).read_text().splitlines():
            h = re.match(r"^##+\s+(.+?)\s*\(\$([0-9A-F]{4})\)\s*$", line)
            if h:
                names.setdefault(int(h.group(2), 16), h.group(1).strip())
                continue
            m = re.match(r"^- `([0-9A-F]{4})`: `[^`]*`\s+\*\*[^*]*\*\*\s*(?:—|-)\s*(.+)$", line)
            if m:
                comments.setdefault(int(m.group(1), 16), clean(m.group(2)))
    return names, comments


# ---------------------------------------------------------------- build

def main():
    items, labels, before, equates, header = parse_old_asm()
    md_names, md_comments = parse_old_md()

    # instruction and data boundaries, 0000-0BFF
    # The old listing has a few code bytes as DB with no comment (where its
    # disassembler gave up) and one instruction split in two (02A3: SUB $39).
    # Decode those as code when the instruction ends on an item boundary,
    # unless they are inline data after a call that takes some.
    INLINE_CALLS = (0x03CE, 0x0336, 0x0446)
    # Data the old listing decoded as code.
    DATA = {0x07A2: (10, 'keywords "WRITE" and "PRINT" in the 5-bit letter codes (W=17h R=12h I=09h T=14h E=05h P=10h N=0Eh)')}
    for a, (n, c) in DATA.items():
        for b in [b for b in items if a <= b < a + n]:
            del items[b]
        items[a] = {"data": list(ROM[a:a + n]), "comment": c}
    starts = sorted(a for a in items if a < 0x0C00)
    targets = set()
    for a in starts:
        if items[a]["data"] is None:
            t, n, target, kind = decode(ROM, a)
            if target is not None:
                targets.add(target)
    changed = True
    while changed:
        changed = False
        for i, a in enumerate(starts):
            it = items.get(a)
            if not it or it["data"] is None or it["comment"]:
                continue
            prev = [b for b in starts[:i] if b in items]
            if prev and items[prev[-1]]["data"] is None:
                pt, pn, ptarget, pkind = decode(ROM, prev[-1])
                if pkind == "call" and ptarget in INLINE_CALLS:
                    continue
            text, n, target, kind = decode(ROM, a)
            end = a + n
            later = [b for b in starts if a < b < end and b in items]
            if text and (end in items or end == 0x0C00) and all(not items[b]["comment"] and b not in targets for b in later):
                items[a] = {"data": None, "comment": ""}
                for b in later:
                    del items[b]
                changed = True
        starts = sorted(a for a in items if a < 0x0C00)
    # short gaps the old listing skipped over, before the sample program at 0BB5
    for i, a in enumerate(starts[:-1]):
        it = items[a]
        end = a + (len(it["data"]) if it["data"] is not None else decode(ROM, a)[1])
        gap = starts[i + 1] - end
        if 0 < gap <= 3 and end < 0x0BB5:
            text, n, target, kind = decode(ROM, end)
            if text and n == gap:
                items[end] = {"data": None, "comment": ""}
    starts = sorted(a for a in items if a < 0x0C00)
    entries = []        # (addr, length, kind, text, target, comment)
    problems = []
    pos = 0
    for i, a in enumerate(starts):
        if a < pos:
            problems.append(f"{a:04X}: overlaps the previous item")
            continue
        if a > pos:
            entries.append((pos, a - pos, "data", None, None, ""))
        it = items[a]
        nxt = starts[i + 1] if i + 1 < len(starts) else 0x0C00
        if it["data"] is not None:
            n = len(it["data"])
            if bytes(it["data"]) != ROM[a:a + n]:
                problems.append(f"{a:04X}: data differs from the ROM; using the ROM")
            entries.append((a, n, "data", None, None, it["comment"]))
            pos = a + n
            continue
        text, n, target, kind = decode(ROM, a)
        if text is None or a + n > nxt:
            entries.append((a, nxt - a, "data", None, None, it["comment"] or "not a documented instruction"))
            problems.append(f"{a:04X}: kept as data")
            pos = nxt
            continue
        entries.append((a, n, "code", text, target, it["comment"] or md_comments.get(a, "")))
        pos = a + n
    if pos < 0x0C00:
        entries.append((pos, 0x0C00 - pos, "data", None, None, ""))

    # labels: names from the old files, otherwise L<addr> for every branch target
    # Routines the old files describe but don't label, and a few clearer names.
    NAMES = {
        0x0254: "TAPE_LEADER", 0x027F: "TTY_NEWLINE_HL", 0x028E: "TTY_HEX_BYTE", 0x02EC: "TTY_SPACE",
        0x02F0: "TTY_NEWLINE", 0x0301: "TTY_PUTC", 0x0317: "CMD_LIST", 0x034E: "DE_TO_NEXT_8",
        0x0355: "GET_KEY_SELECTOR", 0x0393: "CLEAR_SCREEN", 0x03A9: "PRINT_HEX_BYTE_HL", 0x03AA: "PRINT_HEX_BYTE",
        0x03C4: "PAD_TO_NEXT_LINE", 0x03CE: "PRINT_INLINE", 0x03DE: "READ_HEX_WORD", 0x03E7: "READ_HEX_BYTE",
        0x03F6: "READ_HEX_DIGIT", 0x042E: "MM_SEND", 0x0446: "MM_SEND_INLINE", 0x0452: "SKIP_WORD",
        0x0460: "MM_OUT_X", 0x04E6: "BURP_EXPR_TERM", 0x057B: "BURP_EMIT_BLOCK", 0x058A: "MM_SEND_TEST",
        0x0714: "BURP_CLEAR_BLOCK", 0x0729: "BURP_READ_COMMAND", 0x0736: "BURP_READ_NUMBER",
        0x0794: "BURP_LINE_TOKEN", 0x07AC: "BURP_BLOCK_ADDR", 0x0800: "BURP_ENTRY",
    }
    COMMENTS = {
        0x0823: "delay count for INLINE_DELAY_1B (the CALL above)",
        0x082D: "delay count for INLINE_DELAY_1B (the CALL above)",
        0x08F2: "unused: the JR above never falls through, and the code below is reached by the jump to 08F3",
    }
    name_at = dict(NAMES)
    for a, ns in labels.items():
        if a not in NAMES:
            name_at[a] = ns[0]
    for a, n in md_names.items():
        if a not in name_at:
            name_at[a] = re.sub(r"[^A-Za-z0-9_]", "_", n).upper().strip("_")
    starts_set = {e[0] for e in entries}
    used = set()
    for e in entries:
        if e[4] is not None:
            used.add(e[4])
    label_at = {}
    for a in sorted(used | set(name_at)):
        if a in starts_set:
            label_at[a] = name_at.get(a, f"L{a:04X}")
    # names must be unique
    seen = {}
    for a in sorted(label_at):
        nm = label_at[a]
        if nm in seen:
            label_at[a] = f"{nm}_{a:04X}"
        seen[label_at[a]] = a

    out = []
    out.append("; PSI COMP80 ROM: monitor (0000-03FF) and BURP (0400-0BFF)")
    out.append(";")
    out.append("; Annotated disassembly. It assembles with z80asm to psicomp80.rom byte for")
    out.append("; byte (rom/build.sh checks). Each line's comment starts with the address and")
    out.append("; the bytes, as in the magazine's hex listing. Branch targets without a")
    out.append("; name are labelled L<address>.")
    out.append(";")
    out.append("; Made from the earlier annotated disassemblies (old/) by")
    out.append("; rom/tools/make_rom_asm.py; edit this file from now on.")
    out.append("")
    for h in header:
        out.append(h)
    out.append("")
    for e in equates:
        out.append(e)
    out.append("")
    out.append("        ORG     $0000")
    out.append("")
    for (a, n, kind, text, target, comment) in entries:
        comment = COMMENTS.get(a, comment)
        for c in before.get(a, []):
            out.append(c)
        if a in label_at:
            out.append(f"{label_at[a]}:")
        bs = ROM[a:a + n]
        if kind == "code":
            t = text.replace("{T}", label_at.get(target, H4(target)) if target is not None else "")
            hexb = " ".join(f"{v:02X}" for v in bs)
            out.append(f"        {t:<22}; {a:04X}  {hexb:<11}  {comment}".rstrip())
        else:
            for k in range(0, n, 8):
                chunk = bs[k:k + 8]
                hexb = " ".join(f"{v:02X}" for v in chunk)
                db = ",".join(f"${v:02X}" for v in chunk)
                c = comment if k == 0 else ""
                line = f"        DB {db:<30}; {a + k:04X}  {hexb}"
                out.append((line + ("  " + c if c else "")).rstrip())
    (REPO / "rom" / "psicomp80.asm").write_text("\n".join(out) + "\n")
    print(f"{len(entries)} items, {len(label_at)} labels, {len(problems)} notes")
    for p in problems:
        print("  ", p)


if __name__ == "__main__":
    main()
