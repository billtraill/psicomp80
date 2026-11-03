"""A small CHIP-8 assembler, for the example programs.

  python3 c8asm.py prog.c8 prog.ch8

Mnemonics as in Cowgod's CHIP-8 reference: CLS, RET, JP addr, JP V0,addr,
CALL addr, SE/SNE Vx,byte|Vy, LD (all its forms: Vx,byte  Vx,Vy  I,addr
Vx,DT  Vx,K  DT,Vx  ST,Vx  F,Vx  B,Vx  [I],Vx  Vx,[I]), ADD Vx,byte|Vy
ADD I,Vx, OR, AND, XOR, SUB, SHR, SUBN, SHL, RND Vx,byte, DRW Vx,Vy,n,
SKP Vx, SKNP Vx.  Also "label:", "name = value", DB and DW with numbers
or labels, and ; comments.  Numbers are decimal, 0x hex or 0b binary
(with . allowed for 0 in binary, so sprites can be drawn: 0b..1111..).
The program starts at 200h.
"""
import re, sys


def num(s, syms):
    s = s.strip()
    if s in syms:
        return syms[s]
    if s.lower().startswith("0b"):
        return int(s[2:].replace(".", "0"), 2)
    if "+" in s:
        a, b = s.rsplit("+", 1)
        return num(a, syms) + num(b, syms)
    return int(s, 0)


def reg(s):
    m = re.fullmatch(r"V([0-9A-F])", s.strip().upper())
    return int(m.group(1), 16) if m else None


def assemble(src):
    lines = []
    for raw in src.splitlines():
        line = raw.split(";")[0].strip()
        if line:
            lines.append(line)
    syms = {}
    for final in (False, True):
        pc, out = 0x200, bytearray()
        for line in lines:
            m = re.match(r"(\w+):\s*(.*)", line)
            if m:
                syms[m.group(1)] = pc
                line = m.group(2)
                if not line:
                    continue
            m = re.fullmatch(r"(\w+)\s*=\s*(.+)", line)
            if m:
                syms[m.group(1)] = num(m.group(2), syms)
                continue
            op, _, rest = line.partition(" ")
            op = op.upper()
            args = [a.strip() for a in rest.split(",")] if rest.strip() else []
            n = (lambda s: num(s, syms)) if final else (lambda s: num(s, syms) if (s in syms or not s[0].isalpha()) else 0)
            if op == "DB":
                bs = [n(a) & 0xFF for a in args]
            elif op == "DW":
                bs = sum([[n(a) >> 8 & 0xFF, n(a) & 0xFF] for a in args], [])
            else:
                w = encode(op, args, n)
                bs = [w >> 8, w & 0xFF]
            out += bytes(bs)
            pc += len(bs)
    return bytes(out)


def encode(op, a, n):
    U = [x.upper() for x in a]
    x = reg(a[0]) if a else None
    y = reg(a[1]) if len(a) > 1 else None
    if op == "CLS": return 0x00E0
    if op == "RET": return 0x00EE
    if op == "JP":
        if len(a) == 2: return 0xB000 | n(a[1]) & 0xFFF
        return 0x1000 | n(a[0]) & 0xFFF
    if op == "CALL": return 0x2000 | n(a[0]) & 0xFFF
    if op in ("SE", "SNE"):
        if y is not None: return (0x5000 if op == "SE" else 0x9000) | x << 8 | y << 4
        return (0x3000 if op == "SE" else 0x4000) | x << 8 | n(a[1]) & 0xFF
    if op == "LD":
        if U[0] == "I": return 0xA000 | n(a[1]) & 0xFFF
        if U[0] == "DT": return 0xF015 | y << 8
        if U[0] == "ST": return 0xF018 | y << 8
        if U[0] == "F": return 0xF029 | y << 8
        if U[0] == "B": return 0xF033 | y << 8
        if U[0] == "[I]": return 0xF055 | y << 8
        if U[1] == "[I]": return 0xF065 | x << 8
        if U[1] == "DT": return 0xF007 | x << 8
        if U[1] == "K": return 0xF00A | x << 8
        if y is not None: return 0x8000 | x << 8 | y << 4
        return 0x6000 | x << 8 | n(a[1]) & 0xFF
    if op == "ADD":
        if U[0] == "I": return 0xF01E | y << 8
        if y is not None: return 0x8004 | x << 8 | y << 4
        return 0x7000 | x << 8 | n(a[1]) & 0xFF
    alu = {"OR": 1, "AND": 2, "XOR": 3, "SUB": 5, "SUBN": 7}
    if op in alu: return 0x8000 | x << 8 | y << 4 | alu[op]
    if op == "SHR": return 0x8006 | x << 8
    if op == "SHL": return 0x800E | x << 8
    if op == "RND": return 0xC000 | x << 8 | n(a[1]) & 0xFF
    if op == "DRW": return 0xD000 | x << 8 | y << 4 | n(a[2]) & 0xF
    if op == "SKP": return 0xE09E | x << 8
    if op == "SKNP": return 0xE0A1 | x << 8
    raise SystemExit(f"unknown instruction: {op} {', '.join(a)}")


if __name__ == "__main__":
    src, dst = sys.argv[1:]
    code = assemble(open(src).read())
    open(dst, "wb").write(code)
    print(f"{dst}: {len(code)} bytes")
