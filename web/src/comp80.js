// The PSI COMP80, following the MAME driver (psicomp80.cpp): 3 KB ROM at
// 0000, RAM 0C00-1FFF, a 2 KB screen at 8000 (mirrored up to FFFF unless the
// 32 KB expansion fills 8800-FFFF), the keyboard as a latched byte on port
// 01 with an NMI per key, and the MM57109 number cruncher on ports 60 and 03
// that BURP uses.  No tape or floppy disc.
"use strict";

const CLOCK = 4000000;

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
    this.irqMmPulse = false;
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

  updateIrq() { this.cpu.irq = this.irqMmLine || this.irqMmPulse; }
  tick_pulse() { this.irqMmPulse = false; this.updateIrq(); }

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
    this.mmSetDataReady(this.asciiToMmCode(c));
    return true;
  }

  asciiToMmCode(c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    if (c === 0x0d || c === 0x0a) return 0x10;
    if (c === 0x1b) return 0x11;
    if (c === 0x20) return 0x12;
    return 0x1f;
  }

  mmSetDataReady(code) {
    this.mmCode = code & 0x0f;
    this.irqMmPulse = true;
    this.updateIrq();
    this.setTimer("pulse", 4);                   // 1 us
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
  // A coarse model of the National MM57109 calculator chip, as in the MAME
  // driver: BURP writes instructions to port 60 (bit 7 set first as HOLD,
  // then the instruction), polls RDY and BR on port 03, and reads results a
  // digit at a time through IM 1 interrupts.

  mmReset() {
    this.mmCode = 0x1f;
    this.mmRDY = true;
    this.mmBR = false;
    this.mmInv = false;
    this.mmIrq0 = false;
    this.mmX = 0; this.mmY = 0; this.mmZ = 0; this.mmT = 0; this.mmM = 0;
    this.mmDeg = false;
    this.mmMantDigits = 8;
    this.mmEntry = false;
    this.mmTwoWord = false;
    this.mmTwoWordOp = 0;
    this.mmError = false;
    this.mmNibbles = [];
    this.mmPendingBranch = false;
    this.mmPendingBranchState = false;
    this.entryReset();
  }

  entryReset() {
    this.enExp = false; this.enDp = false; this.enDpIndex = 0;
    this.enMantCount = 0; this.enExpCount = 0; this.enMantSign = 1; this.enExpSign = 1;
    this.enMant = [0, 0, 0, 0, 0, 0, 0, 0]; this.enExpDigits = [0, 0];
  }

  port03() {
    const v = (this.mmRDY ? 0 : 0x20) | (this.mmBR ? 0 : 0x40) | (this.mmCode & 0x1f);
    if (this.mmIrq0) {
      this.irqMmLine = false;
      this.updateIrq();
      this.mmIrq0 = false;
      if (this.mmNibbles.length) this.setTimer("nibble", 0);
    }
    return v;
  }

  port60(v) {
    if (v & 0x80) return;                        // HOLD
    this.mmIrq0 = false;
    this.mmExecute(v);
  }

  mmPush(v) { this.mmT = this.mmZ; this.mmZ = this.mmY; this.mmY = this.mmX; this.mmX = v; }
  mmPop() { const v = this.mmX; this.mmX = this.mmY; this.mmY = this.mmZ; this.mmZ = this.mmT; return v; }

  mmQueueNibble(n) {
    this.mmNibbles.push(n & 0x0f);
    if (!this.timerOn("nibble")) this.setTimer("nibble", 0);
  }

  tick_nibble() {
    if (!this.mmNibbles.length) return;
    this.mmCode = this.mmNibbles.shift();
    if (!this.mmNibbles.length) this.setTimer("ready", 300);
    else if (!this.timerOn("ready")) this.mmRDY = true;
    if (!this.mmIrq0) { this.irqMmLine = true; this.updateIrq(); this.mmIrq0 = true; }
  }

  tick_ready() {
    if (this.mmPendingBranch) {
      this.mmBR = this.mmPendingBranchState;
      this.mmRDY = !this.mmPendingBranchState;
      this.setTimer("branch", this.mmRDY ? 20 : 100);
    } else {
      this.mmRDY = true;
    }
  }

  tick_branch() { this.mmBR = false; this.mmRDY = true; }

  mmBegin(isBranch, branchState) {
    this.mmRDY = false;
    this.mmBR = false;
    this.mmPendingBranch = isBranch;
    this.mmPendingBranchState = branchState;
    this.setTimer("ready", null);
    this.setTimer("branch", null);
    this.setTimer("ready", isBranch ? 150 : 40);
  }

  // OUT*: X as a digit stream: exponent MSD, LSD, sign bits, decimal point
  // position, then the mantissa digits.
  mmOutX() {
    this.setTimer("ready", null);
    const x = this.mmX, mdc = this.mmMantDigits || 8, dp = 0x0b;
    if (x === 0) {
      [0, 0, 0, dp].forEach((n) => this.mmQueueNibble(n));
      for (let i = 0; i < mdc; i++) this.mmQueueNibble(0);
      return;
    }
    const neg = x < 0, ax = Math.abs(x);
    let e = Math.floor(Math.log10(ax)), norm = ax / Math.pow(10, e);
    if (norm >= 10) { norm /= 10; e++; }
    if (norm < 1) { norm *= 10; e--; }
    const ae = Math.min(Math.abs(e), 99);
    this.mmQueueNibble(Math.floor(ae / 10) % 10);
    this.mmQueueNibble(ae % 10);
    this.mmQueueNibble((neg ? 0x08 : 0) | (e < 0 ? 0x01 : 0));
    this.mmQueueNibble(dp);
    let t = norm;
    for (let i = 0; i < mdc; i++) {
      const d = Math.max(0, Math.min(9, Math.floor(t)));
      this.mmQueueNibble(d);
      t = (t - d) * 10;
    }
  }

  mmEntryValue() {
    let mant = 0;
    for (let i = 0; i < this.enMantCount; i++) mant = mant * 10 + (this.enMant[i] % 10);
    const dpIndex = this.enDp ? this.enDpIndex : this.enMantCount;
    let v = mant;
    if (dpIndex !== this.enMantCount) v *= Math.pow(10, dpIndex - this.enMantCount);
    v *= this.enMantSign;
    if (this.enExpCount > 0) {
      let ev = this.enExpCount === 1 ? this.enExpDigits[0] % 10 : (this.enExpDigits[0] % 10) * 10 + (this.enExpDigits[1] % 10);
      v *= Math.pow(10, ev * this.enExpSign);
    }
    return v;
  }

  mmExecute(op) {
    const opcode = op & 0x3f;
    const isBranch = opcode === 0x13;            // TXF*
    this.mmBegin(isBranch, isBranch ? Math.abs(this.mmX) < 1 : false);
    if (this.mmTwoWord) {
      const two = this.mmTwoWordOp;
      this.mmTwoWord = false;
      this.mmTwoWordOp = 0;
      if (two === 0x16) this.mmOutX();
      return;
    }
    if (!this.mmInv && opcode === 0x20) { this.mmInv = true; return; }
    if ([0x10, 0x11, 0x12, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a].includes(opcode)) {
      this.mmTwoWord = true;
      this.mmTwoWordOp = opcode;
      return;
    }
    this.mmExecuteSingle(opcode);
  }

  mmExecuteSingle(opcode) {
    const DEG = 180 / Math.PI;
    this.mmBR = false;
    const isEntry = opcode <= 0x0f, isEn = opcode === 0x21;
    if (this.mmEntry && !isEntry) {
      this.mmX = this.mmEntryValue();
      this.mmEntry = false;
      this.entryReset();
    }
    if (isEn) return;
    const start = () => {
      if (!this.mmEntry) {
        this.mmT = this.mmZ; this.mmZ = this.mmY; this.mmY = this.mmX; this.mmX = 0;
        this.mmEntry = true;
        this.entryReset();
      }
    };
    if (opcode <= 0x09) {
      start();
      if (!this.enExp) { if (this.enMantCount < 8) this.enMant[this.enMantCount++] = opcode; }
      else if (this.enExpCount < 2) this.enExpDigits[this.enExpCount++] = opcode;
      this.mmX = this.mmEntryValue();
      return;
    }
    switch (opcode) {
      case 0x0a: start(); if (!this.enDp) { this.enDp = true; this.enDpIndex = this.enMantCount; } return;
      case 0x0b: start(); this.enExp = true; return;
      case 0x0c: start(); if (this.enExp) this.enExpSign = -this.enExpSign; else this.enMantSign = -this.enMantSign; return;
      case 0x0d: start(); this.mmX = Math.PI; return;
      case 0x0e: start(); return;
      case 0x0f: return;
    }
    if (this.mmInv) {
      this.mmInv = false;
      const x = this.mmX;
      switch (opcode) {
        case 0x24: if (x < -1 || x > 1) { this.mmError = true; this.mmX = 0; } else this.mmX = Math.asin(x) * (this.mmDeg ? DEG : 1); return;
        case 0x25: if (x < -1 || x > 1) { this.mmError = true; this.mmX = 0; } else this.mmX = Math.acos(x) * (this.mmDeg ? DEG : 1); return;
        case 0x26: this.mmX = Math.atan(x) * (this.mmDeg ? DEG : 1); return;
        case 0x39: this.mmM += x; return;
        case 0x3a: this.mmM -= x; return;
        case 0x3b: this.mmM *= x; return;
        case 0x3c: if (x === 0) this.mmError = true; else this.mmM /= x; return;
      }
    }
    const x = this.mmX, rad = this.mmDeg ? x / DEG : x;
    switch (opcode) {
      case 0x1c: this.mmM = x; return;
      case 0x1d: this.mmPush(this.mmM); return;
      case 0x39: { const a = this.mmPop(), b = this.mmPop(); this.mmPush(b + a); return; }
      case 0x3a: { const a = this.mmPop(), b = this.mmPop(); this.mmPush(b - a); return; }
      case 0x3b: { const a = this.mmPop(), b = this.mmPop(); this.mmPush(b * a); return; }
      case 0x3c: { const a = this.mmPop(), b = this.mmPop(); if (a === 0) { this.mmError = true; this.mmPush(0); } else this.mmPush(b / a); return; }
      case 0x2b: this.mmError = false; return;
      case 0x2f: this.mmM = 0; return;
      case 0x2c: this.mmX = x * DEG; return;
      case 0x2d: this.mmX = x / DEG; return;
      case 0x2e: this.mmPop(); return;
      case 0x30: this.mmX = this.mmY; this.mmY = x; return;
      case 0x31: this.mmX = Math.exp(x); return;
      case 0x32: this.mmX = Math.pow(10, x); return;
      case 0x33: this.mmX = x * x; return;
      case 0x34: if (x < 0) { this.mmError = true; this.mmX = 0; } else this.mmX = Math.sqrt(x); return;
      case 0x35: if (x <= 0) { this.mmError = true; this.mmX = 0; } else this.mmX = Math.log(x); return;
      case 0x36: if (x <= 0) { this.mmError = true; this.mmX = 0; } else this.mmX = Math.log10(x); return;
      case 0x37: if (x === 0) { this.mmError = true; this.mmX = 0; } else this.mmX = 1 / x; return;
      case 0x38: { const a = this.mmPop(), b = this.mmPop(); this.mmPush(Math.pow(b, a)); return; }
      case 0x24: this.mmX = Math.sin(rad); return;
      case 0x25: this.mmX = Math.cos(rad); return;
      case 0x26: this.mmX = Math.tan(rad); return;
      case 0x22: this.mmDeg = !this.mmDeg; return;
    }
  }
}

if (typeof module !== "undefined") module.exports = { COMP80, CLOCK };
