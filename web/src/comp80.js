// The PSI COMP80, following the MAME driver (psicomp80.cpp): 3 KB ROM at
// 0000, RAM 0C00-1FFF, a 2 KB screen at 8000 (mirrored up to FFFF unless the
// 32 KB expansion fills 8800-FFFF), the keyboard as a latched byte on port
// 01 with an NMI per key, and the MM57109 number cruncher on ports 60 and 03
// that BURP uses, interrupting through IM 1.  No tape or floppy disc.
"use strict";

const CLOCK = 4000000;

// MM57109 execution times in microcycles (data sheet averages), by opcode.
const MM_TIMES = [
  238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 152, 151, 166, 1312, 284, 134,   // 0-9 DP EE CS PI AIN HALT
  208, 278, 197, 271, 191, 186, 583, 395, 163, 2314, 2314, 812, 839, 1385, 168, 173,  // TJC .. RSH
  166, 552, 157, 905, 56200, 56200, 35000, 163, 185, 163, 185, 163, 30700, 30700, 448, 734,   // INV EN TOGM ROLL SIN COS TAN flags ECLR RTD DTR POP MCLR
  652, 30800, 27400, 3000, 7000, 24800, 30700, 4500, 55400, 2200, 2200, 3200, 7800, 130, 130, 122,   // XEY EX 10X SQ SQRT LN LOG 1/X YX + - x / PRW1 PRW2 NOP
];
const MM_INV_TIMES = { 0x24: 54000, 0x25: 54000, 0x26: 30200, 0x39: 1700, 0x3a: 1700, 0x3b: 2700, 0x3c: 7300 };

class COMP80 {
  // fonts: { ascii: [64][8] 5-bit rows, gfx: [64][10] 6-bit rows }
  constructor(fonts) {
    this.fonts = fonts;
    this.mem = new Uint8Array(0x10000);
    this.cpu = new Z80(this);
    this.cycles = 0;
    this.timers = {};
    this.rom = null;
    this.romName = "";
    this.expansion = false;
  }

  // ---------------------------------------------------------------- lifecycle

  // Power on with ROM image rom (3072 bytes): RAM cleared, screen blank.
  powerOn(rom, romName, expansion) {
    this.rom = rom;
    this.romName = romName;
    this.expansion = expansion;
    this.mem.fill(0);
    this.mem.set(rom.subarray(0, 0x0c00), 0);
    this.mem.fill(0x20, 0x8000, 0x8800);
    this.reset();
  }

  // The RESET key: the CPU restarts, memory stays.
  reset() {
    this.cpu.reset();
    this.timers = {};
    this.keyLatch = 0xff;
    this.keyTime = -1e9;
    this.irqMmLine = false;
    this.mmReset();
    this.updateIrq();
  }

  // Run for n cycles (or a little over).
  run(n) {
    const end = this.cycles + n;
    const cpu = this.cpu;
    while (this.cycles < end) {
      this.cycles += cpu.step();
      if (this.nextTimer <= this.cycles) this.runTimers();
    }
  }

  // ---------------------------------------------------------------- timers

  setTimer(name, cycles) {
    if (cycles === null) delete this.timers[name];
    else this.timers[name] = this.cycles + cycles;
    this.nextTimer = Infinity;
    for (const k in this.timers) if (this.timers[k] < this.nextTimer) this.nextTimer = this.timers[k];
  }
  timerOn(name) { return name in this.timers; }
  runTimers() {
    for (;;) {
      let name = null, at = Infinity;
      for (const k in this.timers) if (this.timers[k] <= this.cycles && this.timers[k] < at) { at = this.timers[k]; name = k; }
      if (name === null) return;
      this.setTimer(name, null);
      this["tick_" + name]();
    }
  }

  // ---------------------------------------------------------------- bus

  read(a) {
    if (a >= 0x8000 && !this.expansion) return this.mem[0x8000 | (a & 0x7ff)];
    if (a >= 0x2000 && a < 0x8000) return 0;
    return this.mem[a];
  }
  write(a, v) {
    if (a < 0x0c00) return;                      // ROM
    if (a >= 0x8000) { this.mem[this.expansion ? a : 0x8000 | (a & 0x7ff)] = v; return; }
    if (a >= 0x2000) return;                     // nothing there
    this.mem[a] = v;
  }
  input(port) {
    switch (port & 0xff) {
      case 0x00: return 0x01;                    // tape: idle
      case 0x01: { const v = this.keyLatch; this.keyLatch = 0xff; return v; }
      case 0x03: return this.port03();
      default: return 0xff;
    }
  }
  output(port, v) {
    if ((port & 0xff) === 0x60) this.port60(v);
  }

  updateIrq() { this.cpu.irq = this.irqMmLine; }

  // ---------------------------------------------------------------- keyboard

  // True when a key now would be read rather than reset the machine: the CPU
  // is waiting in a HALT and the last key has been taken.
  waitingForKey() { return this.cpu.halted && this.keyLatch === 0xff; }

  // A key with ASCII code c (the host keyboard's view).  ESC is RESET.
  // Backspace becomes RS under FORTH and LISP, which use RS as rubout.
  key(c) {
    if (c === 0x1b) { this.reset(); return true; }
    if (c === 0x08 && this.romName !== "burp") c = 0x1e;
    if (c === 0) return false;
    if (this.keyLatch !== 0xff && this.cycles - this.keyTime < CLOCK / 20) return false;
    this.keyLatch = ~c & 0xff;
    this.keyTime = this.cycles;
    this.cpu.nmi();
    return true;
  }

  // ---------------------------------------------------------------- screen

  // Draw the screen into a 384 x 320 RGBA buffer (Uint8ClampedArray).
  render(px, fg = [255, 255, 255], bg = [0, 0, 0]) {
    const A = this.fonts.ascii, G = this.fonts.gfx, m = this.mem;
    for (let row = 0; row < 32; row++) {
      for (let col = 0; col < 64; col++) {
        const v = m[0x8000 + row * 64 + col], gfx = v & 0x40, code = v & 0x3f;
        for (let y = 0; y < 10; y++) {
          let bits;
          if (gfx) bits = G[code][y] & 0x3f;
          else bits = y < 8 ? (A[code ^ 0x20][y] & 0x1f) << 1 : 0;
          let o = ((row * 10 + y) * 384 + col * 6) * 4;
          for (let x = 0; x < 6; x++, o += 4) {
            const c = bits & (0x20 >> x) ? fg : bg;
            px[o] = c[0]; px[o + 1] = c[1]; px[o + 2] = c[2]; px[o + 3] = 255;
          }
        }
      }
    }
  }

  // The screen as text, one string per line (graphics as #).
  screenText() {
    const lines = [];
    for (let row = 0; row < 32; row++) {
      let s = "";
      for (let col = 0; col < 64; col++) {
        const v = this.mem[0x8000 + row * 64 + col], c = v & 0x3f;
        s += v & 0x40 ? "#" : String.fromCharCode(c < 0x20 ? c + 64 : c);
      }
      lines.push(s);
    }
    return lines;
  }

  // ---------------------------------------------------------------- MM57109
  // The National MM57109 calculator chip that BURP does its arithmetic on.
  // Port 60 drives its instruction lines (bits 0-5) and HOLD (bit 7); port
  // 03 reads its RDY (bit 5: 1 while it executes), BR (bit 6: 0 when a test
  // is true) and digit outputs (bits 0-3).  Its R/W output, which pulses
  // once for each digit of an OUT instruction, is the Z80's INT.
  //
  // With HOLD low the chip fetches the instruction on its lines and RDY
  // goes low; BURP then raises HOLD so the chip stops when it has finished.
  // Two-word instructions (INV, SMDC, OUT, IN and the branches) take their
  // second word the same way.  A branch whose test is true pulses BR and
  // waits for its second word (BURP sends a NOP); a false one skips it.
  // Execution times are the data sheet's averages, a microcycle being about
  // 10 us.

  mmReset() {
    this.mmX = 0; this.mmY = 0; this.mmZ = 0; this.mmT = 0; this.mmM = 0;
    this.mmSci = false;           // TOGM: scientific notation for IN and OUT
    this.mmMDC = 8;               // mantissa digits for IN and OUT (SMDC)
    this.mmError = false;
    this.mmEntry = false;         // in number entry
    this.mmAfterEnter = false;    // the last instruction was EN
    this.mmHold = true;
    this.mmBusy = false;
    this.mmBR = false;
    this.mmWord2 = null;          // what to do with a second word
    this.mmDigits = [];
    this.mmCode = 0;
    this.entryReset();
    this.setTimer("mm", null);
    this.setTimer("mmdigit", null);
  }

  entryReset() {
    this.enExp = false; this.enDp = false; this.enDpIndex = 0;
    this.enMant = []; this.enExpDigits = []; this.enMantSign = 1; this.enExpSign = 1;
  }

  port03() {
    return (this.mmBusy ? 0x20 : 0) | (this.mmBR ? 0 : 0x40) | (this.mmCode & 0x0f);
  }

  // The R/W interrupt is latched until the Z80 takes it.
  irqAck() { this.irqMmLine = false; this.updateIrq(); }

  port60(v) {
    this.mmHold = (v & 0x80) !== 0;
    if (this.mmHold) return;
    const op = v & 0x3f;
    if (this.mmWord2) {
      const f = this.mmWord2;
      this.mmWord2 = null;
      this.mmBusy = true;
      this.mmBR = false;
      f(op);
      if (!this.timerOn("mm")) this.mmFinish(130);
      return;
    }
    if (this.mmBusy) return;
    this.mmBusy = true;
    this.mmBR = false;
    this.mmExecute(op);
  }

  // RDY comes back after t microcycles; then() runs at that point.
  mmFinish(t, then) { this.mmThen = then || null; this.setTimer("mm", t * 40); }
  tick_mm() {
    const f = this.mmThen;
    this.mmThen = null;
    if (f) f(); else this.mmBusy = false;
  }

  // OUT: one digit per R/W pulse, each an interrupt; then wait for the
  // second word.
  tick_mmdigit() {
    if (this.mmDigits.length) {
      this.mmCode = this.mmDigits.shift();
      this.irqMmLine = true;
      this.updateIrq();
      this.setTimer("mmdigit", 48 * 40);
    } else {
      this.mmBusy = false;
      this.mmWord2 = () => {};
    }
  }

  // Round to the chip's 8 significant digits.
  mmRound(v) {
    if (!isFinite(v)) { this.mmError = true; return 0; }
    if (v === 0) return 0;
    const r = Number(v.toPrecision(8));
    const e = Math.floor(Math.log10(Math.abs(r)));
    if (e > 99) { this.mmError = true; return Math.sign(r) * 9.9999999e99; }
    if (e < -99) return 0;
    return r;
  }

  mmPush(v) { this.mmT = this.mmZ; this.mmZ = this.mmY; this.mmY = this.mmX; this.mmX = v; }
  mmPop() { this.mmY = this.mmZ; this.mmZ = this.mmT; }

  mmEntryValue() {
    let mant = 0;
    for (const d of this.enMant) mant = mant * 10 + d;
    const dp = this.enDp ? this.enDpIndex : this.enMant.length;
    let v = mant * Math.pow(10, dp - this.enMant.length) * this.enMantSign;
    let e = 0;
    for (const d of this.enExpDigits) e = e * 10 + d;
    if (this.enExpDigits.length) v *= Math.pow(10, e * this.enExpSign);
    return v;
  }

  // The digits of an OUT instruction in scientific notation: exponent
  // tens and units, the signs (8 mantissa, 1 exponent), the decimal point
  // position (0Bh: after the first digit), then the mantissa digits.
  mmOutDigits() {
    const x = this.mmRound(this.mmX), digits = [];
    let e = 0, mant = "0".repeat(8);
    if (x !== 0) {
      const s = Math.abs(x).toExponential(7);       // d.ddddddde±n
      mant = s[0] + s.slice(2, 9);
      e = parseInt(s.slice(s.indexOf("e") + 1), 10);
    }
    const ae = Math.min(Math.abs(e), 99);
    digits.push(Math.floor(ae / 10), ae % 10, (x < 0 ? 8 : 0) | (e < 0 ? 1 : 0), 0x0b);
    for (let i = 0; i < this.mmMDC; i++) digits.push(+mant[i]);
    return digits;
  }

  mmExecute(op) {
    const T = MM_TIMES[op] || 200;
    const entryOp = op <= 0x0f;
    // Any instruction but these ends number entry.
    if (this.mmEntry && !entryOp) {
      this.mmX = this.mmRound(this.mmEntryValue());
      this.mmEntry = false;
    }
    const afterEnter = this.mmAfterEnter;
    this.mmAfterEnter = false;
    const startEntry = () => {
      if (this.mmEntry) return;
      if (afterEnter) this.mmX = 0; else this.mmPush(0);
      this.mmEntry = true;
      this.entryReset();
    };
    const x = this.mmX, y = this.mmY, R = (v) => this.mmRound(v);
    const fn = (f, bad) => { if (bad) { this.mmError = true; this.mmX = 0; } else this.mmX = R(f()); };
    const two = (f) => { const v = R(f()); this.mmPop(); this.mmX = v; };
    const branch = (cond) => {
      // the test result shows when the instruction has executed
      this.mmFinish(T, () => {
        if (cond) { this.mmBR = true; this.mmWord2 = () => {}; }
        else this.mmBusy = false;
      });
    };
    switch (op) {
      case 0x0a: startEntry(); if (!this.enDp) { this.enDp = true; this.enDpIndex = this.enMant.length; } break;
      case 0x0b: startEntry(); this.enExp = true; break;
      case 0x0c:
        if (!this.mmEntry) { this.mmX = -this.mmX; break; }
        if (this.enExp) this.enExpSign = -this.enExpSign; else this.enMantSign = -this.enMantSign;
        this.mmX = this.mmEntryValue();
        break;
      case 0x0d: startEntry(); this.mmX = Math.PI; this.enMant = [3, 1, 4, 1, 5, 9, 2, 7]; this.enDp = true; this.enDpIndex = 1; break;
      case 0x0e: startEntry(); break;                  // AIN: no digit input here
      case 0x0f: break;                                // HALT: a NOP that keeps number entry going
      case 0x10: branch(false); return;                // TJC: the JC input isn't connected
      case 0x11: branch(x === 0); return;              // TX=0
      case 0x12: branch(x < 0); return;                // TXLT0
      case 0x13: branch(Math.abs(x) < 1); return;      // TXF
      case 0x14: branch(this.mmError); return;         // TERR
      case 0x15: branch(true); return;                 // JMP
      case 0x16:                                       // OUT
        this.mmDigits = this.mmOutDigits();
        this.setTimer("mmdigit", 40 * 40);
        return;
      case 0x17: this.mmFinish(T, () => { this.mmBusy = false; this.mmWord2 = () => {}; }); return;   // IN
      case 0x18: this.mmFinish(T, () => { this.mmBusy = false; this.mmWord2 = (w) => { if (w >= 1 && w <= 8) this.mmMDC = w; }; }); return;
      case 0x19: this.mmM = R(this.mmM + 1); branch(this.mmM !== 0); return;   // IBNZ
      case 0x1a: this.mmM = R(this.mmM - 1); branch(this.mmM !== 0); return;   // DBNZ
      case 0x1b: this.mmX = this.mmM; this.mmM = x; break;                     // XEM
      case 0x1c: this.mmM = x; break;                                          // MS
      case 0x1d: this.mmPush(this.mmM); break;                                 // MR
      case 0x1e: this.mmX = R(x * 10); break;                                  // LSH
      case 0x1f: this.mmX = R(x / 10); break;                                  // RSH
      case 0x20:                                                               // INV
        this.mmFinish(T, () => { this.mmBusy = false; this.mmWord2 = (w) => this.mmInverse(w); });
        return;
      case 0x21: this.mmPush(x); this.mmAfterEnter = true; break;              // EN
      case 0x22: this.mmSci = !this.mmSci; break;                              // TOGM
      case 0x23: { const t = this.mmX; this.mmX = this.mmY; this.mmY = this.mmZ; this.mmZ = this.mmT; this.mmT = t; break; }   // ROLL
      case 0x24: fn(() => Math.sin(x)); break;
      case 0x25: fn(() => Math.cos(x)); break;
      case 0x26: fn(() => Math.tan(x)); break;
      case 0x2b: this.mmError = false; break;                                  // ECLR
      case 0x2c: fn(() => x * 180 / Math.PI); break;                           // RTD
      case 0x2d: fn(() => x * Math.PI / 180); break;                           // DTR
      case 0x2e: this.mmX = y; this.mmPop(); break;                            // POP
      case 0x2f:                                                               // MCLR
        this.mmX = this.mmY = this.mmZ = this.mmT = this.mmM = 0;
        this.mmError = false;
        break;
      case 0x30: this.mmX = y; this.mmY = x; break;                            // XEY
      case 0x31: fn(() => Math.exp(x)); break;
      case 0x32: fn(() => Math.pow(10, x)); break;
      case 0x33: fn(() => x * x); break;
      case 0x34: fn(() => Math.sqrt(x), x < 0); break;
      case 0x35: fn(() => Math.log(x), x <= 0); break;
      case 0x36: fn(() => Math.log10(x), x <= 0); break;
      case 0x37: fn(() => 1 / x, x === 0); break;
      case 0x38: if (y < 0 && x !== Math.round(x)) { this.mmError = true; two(() => 0); } else two(() => Math.pow(y, x)); break;
      case 0x39: two(() => y + x); break;
      case 0x3a: two(() => y - x); break;
      case 0x3b: two(() => y * x); break;
      case 0x3c: if (x === 0) { this.mmError = true; two(() => 0); } else two(() => y / x); break;
      default:
        if (op <= 0x09) {                                                      // digits
          startEntry();
          if (!this.enExp) { if (this.enMant.length < 8) this.enMant.push(op); }
          else if (this.enExpDigits.length < 2) this.enExpDigits.push(op);
          this.mmX = this.mmEntryValue();
        }
        // NOP, flags and R/W pulses do nothing here
    }
    this.mmFinish(T);
  }

  // The second word after INV.
  mmInverse(w) {
    const x = this.mmX, R = (v) => this.mmRound(v);
    switch (w) {
      case 0x24: if (x < -1 || x > 1) this.mmError = true; else this.mmX = R(Math.asin(x)); break;
      case 0x25: if (x < -1 || x > 1) this.mmError = true; else this.mmX = R(Math.acos(x)); break;
      case 0x26: this.mmX = R(Math.atan(x)); break;
      case 0x39: this.mmM = R(this.mmM + x); break;
      case 0x3a: this.mmM = R(this.mmM - x); break;
      case 0x3b: this.mmM = R(this.mmM * x); break;
      case 0x3c: if (x === 0) this.mmError = true; else this.mmM = R(this.mmM / x); break;
    }
    this.mmFinish(MM_INV_TIMES[w] || 1700);
  }
}

if (typeof module !== "undefined") module.exports = { COMP80, CLOCK };
