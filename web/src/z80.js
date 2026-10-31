// A Z80 CPU for the COMP80 emulator.
//
// new Z80(bus) where bus has read(addr), write(addr, v), input(port16),
// output(port16, v), and optionally irqAck(), called when an interrupt is
// taken.  step() runs one instruction (or one HALT cycle, or
// takes a pending interrupt) and returns the T-states it took.  nmi() and
// irq = true/false raise the interrupt lines.  Documented behaviour and
// flags; the undocumented X/Y flag bits follow the usual rules but nothing
// on the COMP80 depends on them.
"use strict";

const FC = 0x01, FN = 0x02, FP = 0x04, F3 = 0x08, FH = 0x10, F5 = 0x20, FZ = 0x40, FS = 0x80;

const SZ53 = new Uint8Array(256), SZ53P = new Uint8Array(256), PAR = new Uint8Array(256);
for (let i = 0; i < 256; i++) {
  let p = i, par = 1;
  for (let k = 0; k < 8; k++) { par ^= p & 1; p >>= 1; }
  PAR[i] = par ? FP : 0;
  SZ53[i] = (i & (FS | F3 | F5)) | (i === 0 ? FZ : 0);
  SZ53P[i] = SZ53[i] | PAR[i];
}

// T-states for unprefixed opcodes (conditional jumps etc. add the extra
// when taken).
const CYC = [
  4, 10, 7, 6, 4, 4, 7, 4, 4, 11, 7, 6, 4, 4, 7, 4,
  8, 10, 7, 6, 4, 4, 7, 4, 12, 11, 7, 6, 4, 4, 7, 4,
  7, 10, 16, 6, 4, 4, 7, 4, 7, 11, 16, 6, 4, 4, 7, 4,
  7, 10, 13, 6, 11, 11, 10, 4, 7, 11, 13, 6, 4, 4, 7, 4,
  4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
  4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
  4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
  7, 7, 7, 7, 7, 7, 4, 7, 4, 4, 4, 4, 4, 4, 7, 4,
  4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
  4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
  4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
  4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
  5, 10, 10, 10, 10, 11, 7, 11, 5, 10, 10, 0, 10, 17, 7, 11,
  5, 10, 10, 11, 10, 11, 7, 11, 5, 4, 10, 11, 10, 0, 7, 11,
  5, 10, 10, 19, 10, 11, 7, 11, 5, 4, 10, 4, 10, 0, 7, 11,
  5, 10, 10, 4, 10, 11, 7, 11, 5, 6, 10, 4, 10, 0, 7, 11,
];

class Z80 {
  constructor(bus) {
    this.bus = bus;
    this.reset();
  }

  reset() {
    this.a = 0xff; this.f = 0xff; this.b = 0; this.c = 0; this.d = 0; this.e = 0; this.h = 0; this.l = 0;
    this.a_ = 0; this.f_ = 0; this.b_ = 0; this.c_ = 0; this.d_ = 0; this.e_ = 0; this.h_ = 0; this.l_ = 0;
    this.ix = 0xffff; this.iy = 0xffff; this.sp = 0xffff; this.pc = 0;
    this.i = 0; this.r = 0; this.iff1 = 0; this.iff2 = 0; this.im = 0;
    this.halted = false; this.eiDelay = false;
    this.nmiPending = false; this.irq = false;
  }

  nmi() { this.nmiPending = true; }

  // ---------------------------------------------------------------- memory

  rb(a) { return this.bus.read(a & 0xffff); }
  wb(a, v) { this.bus.write(a & 0xffff, v & 0xff); }
  rw(a) { return this.rb(a) | (this.rb(a + 1) << 8); }
  ww(a, v) { this.wb(a, v); this.wb(a + 1, v >> 8); }
  fetch() { const v = this.rb(this.pc); this.pc = (this.pc + 1) & 0xffff; return v; }
  fetchw() { const v = this.rw(this.pc); this.pc = (this.pc + 2) & 0xffff; return v; }
  fetchd() { const v = this.fetch(); return v < 128 ? v : v - 256; }
  push(v) { this.sp = (this.sp - 2) & 0xffff; this.ww(this.sp, v); }
  pop() { const v = this.rw(this.sp); this.sp = (this.sp + 2) & 0xffff; return v; }
  incr() { this.r = (this.r & 0x80) | ((this.r + 1) & 0x7f); }

  get bc() { return (this.b << 8) | this.c; } set bc(v) { this.b = (v >> 8) & 0xff; this.c = v & 0xff; }
  get de() { return (this.d << 8) | this.e; } set de(v) { this.d = (v >> 8) & 0xff; this.e = v & 0xff; }
  get hl() { return (this.h << 8) | this.l; } set hl(v) { this.h = (v >> 8) & 0xff; this.l = v & 0xff; }
  get af() { return (this.a << 8) | this.f; } set af(v) { this.a = (v >> 8) & 0xff; this.f = v & 0xff; }

  // ---------------------------------------------------------------- ALU

  add8(v, carry) {
    const c = carry ? (this.f & FC) : 0, r = this.a + v + c;
    this.f = SZ53[r & 0xff] | ((r >> 8) & FC) | ((this.a ^ v ^ r) & FH) |
      ((((this.a ^ ~v) & (this.a ^ r)) & 0x80) ? FP : 0);
    this.a = r & 0xff;
  }
  sub8(v, carry, store) {
    const c = carry ? (this.f & FC) : 0, r = this.a - v - c;
    const f = (r & 0x80) | ((r & 0xff) === 0 ? FZ : 0) | ((r >> 8) & FC) | FN |
      ((this.a ^ v ^ r) & FH) | ((((this.a ^ v) & (this.a ^ r)) & 0x80) ? FP : 0);
    if (store) { this.a = r & 0xff; this.f = f | (r & (F3 | F5)); }
    else this.f = f | (v & (F3 | F5));
  }
  and8(v) { this.a &= v; this.f = SZ53P[this.a] | FH; }
  xor8(v) { this.a = (this.a ^ v) & 0xff; this.f = SZ53P[this.a]; }
  or8(v) { this.a = (this.a | v) & 0xff; this.f = SZ53P[this.a]; }
  alu(op, v) {
    switch (op) {
      case 0: this.add8(v, false); break;
      case 1: this.add8(v, true); break;
      case 2: this.sub8(v, false, true); break;
      case 3: this.sub8(v, true, true); break;
      case 4: this.and8(v); break;
      case 5: this.xor8(v); break;
      case 6: this.or8(v); break;
      case 7: this.sub8(v, false, false); break;
    }
  }
  inc8(v) {
    const r = (v + 1) & 0xff;
    this.f = (this.f & FC) | SZ53[r] | (r === 0x80 ? FP : 0) | ((r & 0x0f) === 0 ? FH : 0);
    return r;
  }
  dec8(v) {
    const r = (v - 1) & 0xff;
    this.f = (this.f & FC) | SZ53[r] | FN | (r === 0x7f ? FP : 0) | ((r & 0x0f) === 0x0f ? FH : 0);
    return r;
  }
  add16(x, y) {
    const r = x + y;
    this.f = (this.f & (FS | FZ | FP)) | ((r >> 16) & FC) | (((x ^ y ^ r) >> 8) & FH) | ((r >> 8) & (F3 | F5));
    return r & 0xffff;
  }
  adc16(v) {
    const x = this.hl, r = x + v + (this.f & FC);
    this.f = ((r >> 8) & (FS | F3 | F5)) | ((r & 0xffff) === 0 ? FZ : 0) | ((r >> 16) & FC) |
      (((x ^ v ^ r) >> 8) & FH) | ((((x ^ ~v) & (x ^ r)) & 0x8000) ? FP : 0);
    this.hl = r & 0xffff;
  }
  sbc16(v) {
    const x = this.hl, r = x - v - (this.f & FC);
    this.f = ((r >> 8) & (FS | F3 | F5)) | ((r & 0xffff) === 0 ? FZ : 0) | ((r >> 16) & FC) | FN |
      (((x ^ v ^ r) >> 8) & FH) | ((((x ^ v) & (x ^ r)) & 0x8000) ? FP : 0);
    this.hl = r & 0xffff;
  }
  // CB rotates and shifts: op 0-7 = RLC RRC RL RR SLA SRA SLL SRL
  rot(op, v) {
    let r, c;
    switch (op) {
      case 0: c = v >> 7; r = ((v << 1) | c) & 0xff; break;
      case 1: c = v & 1; r = (v >> 1) | (c << 7); break;
      case 2: c = v >> 7; r = ((v << 1) | (this.f & FC)) & 0xff; break;
      case 3: c = v & 1; r = (v >> 1) | ((this.f & FC) << 7); break;
      case 4: c = v >> 7; r = (v << 1) & 0xff; break;
      case 5: c = v & 1; r = (v >> 1) | (v & 0x80); break;
      case 6: c = v >> 7; r = ((v << 1) | 1) & 0xff; break;
      default: c = v & 1; r = v >> 1; break;
    }
    this.f = SZ53P[r] | c;
    return r;
  }
  daa() {
    let a = this.a, add = 0, c = this.f & FC;
    if ((this.f & FH) || (a & 0x0f) > 9) add = 6;
    if (c || a > 0x99) { add |= 0x60; c = FC; }
    if (this.f & FN) {
      const h = (this.f & FH) && (a & 0x0f) < 6 ? FH : 0;
      a = (a - add) & 0xff;
      this.f = SZ53P[a] | c | FN | h;
    } else {
      const h = (a & 0x0f) > 9 ? FH : 0;
      a = (a + add) & 0xff;
      this.f = SZ53P[a] | c | h;
    }
    this.a = a;
  }

  // ---------------------------------------------------------------- registers by index

  // r: 0 B 1 C 2 D 3 E 4 H 5 L 7 A (6 is (HL) and handled by the caller).
  // xy: 0 for HL, 1 IX, 2 IY: H and L then mean the index register halves.
  getr(r, xy) {
    switch (r) {
      case 0: return this.b; case 1: return this.c; case 2: return this.d; case 3: return this.e;
      case 4: return xy === 0 ? this.h : (xy === 1 ? this.ix : this.iy) >> 8;
      case 5: return xy === 0 ? this.l : (xy === 1 ? this.ix : this.iy) & 0xff;
      default: return this.a;
    }
  }
  setr(r, v, xy) {
    v &= 0xff;
    switch (r) {
      case 0: this.b = v; break; case 1: this.c = v; break; case 2: this.d = v; break; case 3: this.e = v; break;
      case 4: if (xy === 0) this.h = v; else if (xy === 1) this.ix = (this.ix & 0xff) | (v << 8); else this.iy = (this.iy & 0xff) | (v << 8); break;
      case 5: if (xy === 0) this.l = v; else if (xy === 1) this.ix = (this.ix & 0xff00) | v; else this.iy = (this.iy & 0xff00) | v; break;
      default: this.a = v;
    }
  }
  getxy(xy) { return xy === 0 ? this.hl : xy === 1 ? this.ix : this.iy; }
  setxy(xy, v) { v &= 0xffff; if (xy === 0) this.hl = v; else if (xy === 1) this.ix = v; else this.iy = v; }
  // rp: 0 BC 1 DE 2 HL/IX/IY 3 SP
  getrp(p, xy) { return p === 0 ? this.bc : p === 1 ? this.de : p === 2 ? this.getxy(xy) : this.sp; }
  setrp(p, v, xy) { v &= 0xffff; if (p === 0) this.bc = v; else if (p === 1) this.de = v; else if (p === 2) this.setxy(xy, v); else this.sp = v; }
  // rp2 for PUSH/POP: 3 is AF
  getrp2(p, xy) { return p === 3 ? this.af : this.getrp(p, xy); }
  setrp2(p, v, xy) { if (p === 3) this.af = v; else this.setrp(p, v, xy); }
  cond(cc) {
    switch (cc) {
      case 0: return !(this.f & FZ); case 1: return !!(this.f & FZ);
      case 2: return !(this.f & FC); case 3: return !!(this.f & FC);
      case 4: return !(this.f & FP); case 5: return !!(this.f & FP);
      case 6: return !(this.f & FS); default: return !!(this.f & FS);
    }
  }

  // ---------------------------------------------------------------- step

  step() {
    this.tookInt = false;
    if (this.nmiPending) {
      this.tookInt = true;
      this.nmiPending = false;
      this.halted = false;
      this.iff1 = 0;
      this.incr();
      this.push(this.pc);
      this.pc = 0x66;
      return 11;
    }
    if (this.irq && this.iff1 && !this.eiDelay) {
      this.tookInt = true;
      this.halted = false;
      this.iff1 = this.iff2 = 0;
      this.incr();
      if (this.bus.irqAck) this.bus.irqAck();
      if (this.im === 2) {
        this.push(this.pc);
        this.pc = this.rw((this.i << 8) | 0xff);
        return 19;
      }
      this.push(this.pc);   // IM 0 with RST 38h on the bus, or IM 1
      this.pc = 0x38;
      return 13;
    }
    this.eiDelay = false;
    if (this.halted) { this.incr(); return 4; }
    this.incr();
    return this.exec(this.fetch(), 0);
  }

  // Run one unprefixed (xy = 0) or DD/FD-prefixed (xy = 1/2) opcode.
  exec(op, xy) {
    let t = CYC[op];
    const x = op >> 6, y = (op >> 3) & 7, z = op & 7, p = y >> 1, q = y & 1;
    // address of (HL) or (IX+d), fetched only when the opcode uses it
    const mem = () => xy === 0 ? this.hl : (this.getxy(xy) + this.fetchd()) & 0xffff;

    if (x === 1) {
      if (op === 0x76) { this.halted = true; return 4; }
      if (z === 6) { const a = mem(); this.setr(y, this.rb(a), 0); return t + (xy ? 8 : 0); }
      if (y === 6) { const a = mem(); this.wb(a, this.getr(z, 0)); return t + (xy ? 8 : 0); }
      this.setr(y, this.getr(z, xy), xy);
      return t;
    }
    if (x === 2) {
      if (z === 6) { const a = mem(); this.alu(y, this.rb(a)); return t + (xy ? 8 : 0); }
      this.alu(y, this.getr(z, xy));
      return t;
    }
    if (x === 0) {
      switch (z) {
        case 0:
          switch (y) {
            case 0: return t;
            case 1: { const a = this.a, f = this.f; this.a = this.a_; this.f = this.f_; this.a_ = a; this.f_ = f; return t; }
            case 2: { const d = this.fetchd(); this.b = (this.b - 1) & 0xff; if (this.b) { this.pc = (this.pc + d) & 0xffff; t += 5; } return t; }
            case 3: { const d = this.fetchd(); this.pc = (this.pc + d) & 0xffff; return t; }
            default: { const d = this.fetchd(); if (this.cond(y - 4)) { this.pc = (this.pc + d) & 0xffff; t += 5; } return t; }
          }
        case 1:
          if (q === 0) this.setrp(p, this.fetchw(), xy);
          else this.setxy(xy, this.add16(this.getxy(xy), this.getrp(p, xy)));
          return t;
        case 2:
          switch (y) {
            case 0: this.wb(this.bc, this.a); break;
            case 1: this.a = this.rb(this.bc); break;
            case 2: this.wb(this.de, this.a); break;
            case 3: this.a = this.rb(this.de); break;
            case 4: this.ww(this.fetchw(), this.getxy(xy)); break;
            case 5: this.setxy(xy, this.rw(this.fetchw())); break;
            case 6: this.wb(this.fetchw(), this.a); break;
            default: this.a = this.rb(this.fetchw());
          }
          return t;
        case 3:
          this.setrp(p, this.getrp(p, xy) + (q ? -1 : 1), xy);
          return t;
        case 4: case 5: {
          const f = z === 4 ? (v) => this.inc8(v) : (v) => this.dec8(v);
          if (y === 6) { const a = mem(); this.wb(a, f(this.rb(a))); return t + (xy ? 8 : 0); }
          this.setr(y, f(this.getr(y, xy)), xy);
          return t;
        }
        case 6:
          if (y === 6) { const a = mem(); this.wb(a, this.fetch()); return t + (xy ? 5 : 0); }
          this.setr(y, this.fetch(), xy);
          return t;
        default:
          switch (y) {
            case 0: { const c = this.a >> 7; this.a = ((this.a << 1) | c) & 0xff; this.f = (this.f & (FS | FZ | FP)) | (this.a & (F3 | F5)) | c; break; }
            case 1: { const c = this.a & 1; this.a = (this.a >> 1) | (c << 7); this.f = (this.f & (FS | FZ | FP)) | (this.a & (F3 | F5)) | c; break; }
            case 2: { const c = this.a >> 7; this.a = ((this.a << 1) | (this.f & FC)) & 0xff; this.f = (this.f & (FS | FZ | FP)) | (this.a & (F3 | F5)) | c; break; }
            case 3: { const c = this.a & 1; this.a = (this.a >> 1) | ((this.f & FC) << 7); this.f = (this.f & (FS | FZ | FP)) | (this.a & (F3 | F5)) | c; break; }
            case 4: this.daa(); break;
            case 5: this.a ^= 0xff; this.f = (this.f & (FS | FZ | FP | FC)) | FH | FN | (this.a & (F3 | F5)); break;
            case 6: this.f = (this.f & (FS | FZ | FP)) | FC | (this.a & (F3 | F5)); break;
            default: this.f = (this.f & (FS | FZ | FP)) | ((this.f & FC) ? FH : FC) | (this.a & (F3 | F5)); break;
          }
          return t;
      }
    }
    // x === 3
    switch (z) {
      case 0: if (this.cond(y)) { this.pc = this.pop(); t += 6; } return t;
      case 1:
        if (q === 0) { this.setrp2(p, this.pop(), xy); return t; }
        switch (p) {
          case 0: this.pc = this.pop(); return t;
          case 1: {
            let v;
            v = this.b; this.b = this.b_; this.b_ = v; v = this.c; this.c = this.c_; this.c_ = v;
            v = this.d; this.d = this.d_; this.d_ = v; v = this.e; this.e = this.e_; this.e_ = v;
            v = this.h; this.h = this.h_; this.h_ = v; v = this.l; this.l = this.l_; this.l_ = v;
            return t;
          }
          case 2: this.pc = this.getxy(xy); return t;
          default: this.sp = this.getxy(xy); return t;
        }
      case 2: { const a = this.fetchw(); if (this.cond(y)) this.pc = a; return t; }
      case 3:
        switch (y) {
          case 0: this.pc = this.fetchw(); return t;
          case 1: return this.execCB(xy);
          case 2: this.bus.output((this.a << 8) | this.fetch(), this.a); return t;
          case 3: this.a = this.bus.input((this.a << 8) | this.fetch()) & 0xff; return t;
          case 4: { const v = this.rw(this.sp); this.ww(this.sp, this.getxy(xy)); this.setxy(xy, v); return t; }
          case 5: { const v = this.de; this.de = this.hl; this.hl = v; return t; }
          case 6: this.iff1 = this.iff2 = 0; return t;
          default: this.iff1 = this.iff2 = 1; this.eiDelay = true; return t;
        }
      case 4: { const a = this.fetchw(); if (this.cond(y)) { this.push(this.pc); this.pc = a; t += 7; } return t; }
      case 5:
        if (q === 0) { this.push(this.getrp2(p, xy)); return t; }
        switch (p) {
          case 0: { const a = this.fetchw(); this.push(this.pc); this.pc = a; return t; }
          case 1: this.incr(); return this.exec(this.fetch(), 1) + 4;
          case 2: this.incr(); return this.execED();
          default: this.incr(); return this.exec(this.fetch(), 2) + 4;
        }
      case 6: this.alu(y, this.fetch()); return t;
      default: this.push(this.pc); this.pc = y * 8; return t;
    }
  }

  execCB(xy) {
    let a, op;
    if (xy) { a = (this.getxy(xy) + this.fetchd()) & 0xffff; op = this.fetch(); }
    else { this.incr(); op = this.fetch(); a = this.hl; }
    const x = op >> 6, y = (op >> 3) & 7, z = op & 7;
    const memop = xy !== 0 || z === 6;
    const v = memop ? this.rb(a) : this.getr(z, 0);
    let r;
    if (x === 1) {
      const bit = v & (1 << y);
      this.f = (this.f & FC) | FH | (bit ? 0 : FZ | FP) | (bit & FS) | ((memop ? (a >> 8) : v) & (F3 | F5));
      return xy ? 20 : (z === 6 ? 12 : 8);
    }
    if (x === 0) r = this.rot(y, v);
    else if (x === 2) r = v & ~(1 << y);
    else r = v | (1 << y);
    if (memop) {
      this.wb(a, r);
      if (xy && z !== 6) this.setr(z, r, 0);   // undocumented copy to a register
      return xy ? 23 : 15;
    }
    this.setr(z, r, 0);
    return 8;
  }

  execED() {
    const op = this.fetch();
    const x = op >> 6, y = (op >> 3) & 7, z = op & 7, p = y >> 1, q = y & 1;
    if (x === 1) {
      switch (z) {
        case 0: {
          const v = this.bus.input(this.bc) & 0xff;
          if (y !== 6) this.setr(y, v, 0);
          this.f = (this.f & FC) | SZ53P[v];
          return 12;
        }
        case 1: this.bus.output(this.bc, y === 6 ? 0 : this.getr(y, 0)); return 12;
        case 2: if (q === 0) this.sbc16(this.getrp(p, 0)); else this.adc16(this.getrp(p, 0)); return 15;
        case 3: {
          const a = this.fetchw();
          if (q === 0) this.ww(a, this.getrp(p, 0)); else this.setrp(p, this.rw(a), 0);
          return 20;
        }
        case 4: { const v = this.a; this.a = 0; this.sub8(v, false, true); return 8; }
        case 5: this.pc = this.pop(); this.iff1 = this.iff2; return 14;
        case 6: this.im = [0, 0, 1, 2, 0, 0, 1, 2][y]; return 8;
        default:
          switch (y) {
            case 0: this.i = this.a; return 9;
            case 1: this.r = this.a; return 9;
            case 2: this.a = this.i; this.f = (this.f & FC) | SZ53[this.a] | (this.iff2 ? FP : 0); return 9;
            case 3: this.a = this.r; this.f = (this.f & FC) | SZ53[this.a] | (this.iff2 ? FP : 0); return 9;
            case 4: { // RRD
              const m = this.rb(this.hl);
              this.wb(this.hl, ((this.a << 4) | (m >> 4)) & 0xff);
              this.a = (this.a & 0xf0) | (m & 0x0f);
              this.f = (this.f & FC) | SZ53P[this.a];
              return 18;
            }
            case 5: { // RLD
              const m = this.rb(this.hl);
              this.wb(this.hl, ((m << 4) | (this.a & 0x0f)) & 0xff);
              this.a = (this.a & 0xf0) | (m >> 4);
              this.f = (this.f & FC) | SZ53P[this.a];
              return 18;
            }
            default: return 8;
          }
      }
    }
    if (x === 2 && z <= 3 && y >= 4) {
      const inc = (y & 1) ? -1 : 1, repeat = y >= 6;
      switch (z) {
        case 0: { // LDI LDD LDIR LDDR
          const v = this.rb(this.hl);
          this.wb(this.de, v);
          this.hl = (this.hl + inc) & 0xffff; this.de = (this.de + inc) & 0xffff; this.bc = (this.bc - 1) & 0xffff;
          const n = v + this.a;
          this.f = (this.f & (FS | FZ | FC)) | (this.bc ? FP : 0) | (n & F3) | ((n << 4) & F5);
          if (repeat && this.bc) { this.pc = (this.pc - 2) & 0xffff; return 21; }
          return 16;
        }
        case 1: { // CPI CPD CPIR CPDR
          const v = this.rb(this.hl), r = (this.a - v) & 0xff;
          const h = (this.a ^ v ^ r) & FH;
          this.hl = (this.hl + inc) & 0xffff; this.bc = (this.bc - 1) & 0xffff;
          const n = r - (h ? 1 : 0);
          this.f = (this.f & FC) | FN | h | (r & FS) | (r === 0 ? FZ : 0) | (this.bc ? FP : 0) | (n & F3) | ((n << 4) & F5);
          if (repeat && this.bc && r !== 0) { this.pc = (this.pc - 2) & 0xffff; return 21; }
          return 16;
        }
        case 2: { // INI IND INIR INDR
          const v = this.bus.input(this.bc) & 0xff;
          this.wb(this.hl, v);
          this.hl = (this.hl + inc) & 0xffff; this.b = (this.b - 1) & 0xff;
          this.f = SZ53[this.b] | FN | (this.f & FC);
          if (repeat && this.b) { this.pc = (this.pc - 2) & 0xffff; return 21; }
          return 16;
        }
        default: { // OUTI OUTD OTIR OTDR
          const v = this.rb(this.hl);
          this.b = (this.b - 1) & 0xff;
          this.bus.output(this.bc, v);
          this.hl = (this.hl + inc) & 0xffff;
          this.f = SZ53[this.b] | FN | (this.f & FC);
          if (repeat && this.b) { this.pc = (this.pc - 2) & 0xffff; return 21; }
          return 16;
        }
      }
    }
    return 8;   // other ED codes act as NOPs
  }
}

if (typeof module !== "undefined") module.exports = { Z80 };
