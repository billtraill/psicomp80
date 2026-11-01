// The Z80, following web/src/z80.js function for function.
#include "z80.h"

enum { FC = 0x01, FN = 0x02, FP = 0x04, F3 = 0x08, FH = 0x10, F5 = 0x20, FZ = 0x40, FS = 0x80 };

static uint8_t SZ53[256], SZ53P[256];
static bool tables_done;

// T-states for unprefixed opcodes (conditional jumps etc. add the extra when taken)
static const uint8_t CYC[256] = {
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
};

static void make_tables(void) {
    for (int i = 0; i < 256; i++) {
        int p = i, par = 1;
        for (int k = 0; k < 8; k++) { par ^= p & 1; p >>= 1; }
        SZ53[i] = (i & (FS | F3 | F5)) | (i == 0 ? FZ : 0);
        SZ53P[i] = SZ53[i] | (par ? FP : 0);
    }
    tables_done = true;
}

void z80_init(z80 *z, const z80_bus *bus) {
    if (!tables_done) make_tables();
    z->bus = bus;
    z80_reset(z);
}

void z80_reset(z80 *z) {
    z->a = 0xff; z->f = 0xff; z->b = z->c = z->d = z->e = z->h = z->l = 0;
    z->a_ = z->f_ = z->b_ = z->c_ = z->d_ = z->e_ = z->h_ = z->l_ = 0;
    z->ix = 0xffff; z->iy = 0xffff; z->sp = 0xffff; z->pc = 0;
    z->i = 0; z->r = 0; z->iff1 = 0; z->iff2 = 0; z->im = 0;
    z->halted = false; z->ei_delay = false; z->nmi_pending = false; z->irq = false;
}

void z80_nmi(z80 *z) { z->nmi_pending = true; }

// ------------------------------------------------------------------ memory

static inline uint8_t rb(z80 *z, uint16_t a) { return z->bus->read(a); }
static inline void wb(z80 *z, uint16_t a, uint8_t v) { z->bus->write(a, v); }
static inline uint16_t rw(z80 *z, uint16_t a) { return rb(z, a) | (rb(z, (uint16_t)(a + 1)) << 8); }
static inline void ww(z80 *z, uint16_t a, uint16_t v) { wb(z, a, v & 0xff); wb(z, (uint16_t)(a + 1), v >> 8); }
static inline uint8_t fetch(z80 *z) { return rb(z, z->pc++); }
static inline uint16_t fetchw(z80 *z) { uint16_t v = rw(z, z->pc); z->pc += 2; return v; }
static inline int fetchd(z80 *z) { return (int8_t)fetch(z); }
static inline void push(z80 *z, uint16_t v) { z->sp -= 2; ww(z, z->sp, v); }
static inline uint16_t pop(z80 *z) { uint16_t v = rw(z, z->sp); z->sp += 2; return v; }
static inline void incr(z80 *z) { z->r = (z->r & 0x80) | ((z->r + 1) & 0x7f); }

#define BC ((uint16_t)((z->b << 8) | z->c))
#define DE ((uint16_t)((z->d << 8) | z->e))
#define HL ((uint16_t)((z->h << 8) | z->l))
#define AF ((uint16_t)((z->a << 8) | z->f))
static inline void set_bc(z80 *z, unsigned v) { z->b = (v >> 8) & 0xff; z->c = v & 0xff; }
static inline void set_de(z80 *z, unsigned v) { z->d = (v >> 8) & 0xff; z->e = v & 0xff; }
static inline void set_hl(z80 *z, unsigned v) { z->h = (v >> 8) & 0xff; z->l = v & 0xff; }
static inline void set_af(z80 *z, unsigned v) { z->a = (v >> 8) & 0xff; z->f = v & 0xff; }

// ------------------------------------------------------------------ ALU

static void add8(z80 *z, int v, bool carry) {
    int c = carry ? (z->f & FC) : 0, r = z->a + v + c;
    z->f = SZ53[r & 0xff] | ((r >> 8) & FC) | ((z->a ^ v ^ r) & FH) |
           ((((z->a ^ ~v) & (z->a ^ r)) & 0x80) ? FP : 0);
    z->a = r & 0xff;
}

static void sub8(z80 *z, int v, bool carry, bool store) {
    int c = carry ? (z->f & FC) : 0, r = z->a - v - c;
    int f = (r & 0x80) | ((r & 0xff) == 0 ? FZ : 0) | ((r >> 8) & FC) | FN |
            ((z->a ^ v ^ r) & FH) | ((((z->a ^ v) & (z->a ^ r)) & 0x80) ? FP : 0);
    if (store) { z->a = r & 0xff; z->f = f | (r & (F3 | F5)); }
    else z->f = f | (v & (F3 | F5));
}

static void alu(z80 *z, int op, int v) {
    switch (op) {
    case 0: add8(z, v, false); break;
    case 1: add8(z, v, true); break;
    case 2: sub8(z, v, false, true); break;
    case 3: sub8(z, v, true, true); break;
    case 4: z->a &= v; z->f = SZ53P[z->a] | FH; break;
    case 5: z->a ^= v; z->f = SZ53P[z->a]; break;
    case 6: z->a |= v; z->f = SZ53P[z->a]; break;
    default: sub8(z, v, false, false); break;
    }
}

static uint8_t inc8(z80 *z, uint8_t v) {
    uint8_t r = v + 1;
    z->f = (z->f & FC) | SZ53[r] | (r == 0x80 ? FP : 0) | ((r & 0x0f) == 0 ? FH : 0);
    return r;
}

static uint8_t dec8(z80 *z, uint8_t v) {
    uint8_t r = v - 1;
    z->f = (z->f & FC) | SZ53[r] | FN | (r == 0x7f ? FP : 0) | ((r & 0x0f) == 0x0f ? FH : 0);
    return r;
}

static uint16_t add16(z80 *z, unsigned x, unsigned y) {
    unsigned r = x + y;
    z->f = (z->f & (FS | FZ | FP)) | ((r >> 16) & FC) | (((x ^ y ^ r) >> 8) & FH) | ((r >> 8) & (F3 | F5));
    return r & 0xffff;
}

static void adc16(z80 *z, int v) {
    int x = HL, r = x + v + (z->f & FC);
    z->f = ((r >> 8) & (FS | F3 | F5)) | ((r & 0xffff) == 0 ? FZ : 0) | ((r >> 16) & FC) |
           (((x ^ v ^ r) >> 8) & FH) | ((((x ^ ~v) & (x ^ r)) & 0x8000) ? FP : 0);
    set_hl(z, r & 0xffff);
}

static void sbc16(z80 *z, int v) {
    int x = HL, r = x - v - (z->f & FC);
    z->f = ((r >> 8) & (FS | F3 | F5)) | ((r & 0xffff) == 0 ? FZ : 0) | ((r >> 16) & FC) | FN |
           (((x ^ v ^ r) >> 8) & FH) | ((((x ^ v) & (x ^ r)) & 0x8000) ? FP : 0);
    set_hl(z, r & 0xffff);
}

// CB rotates and shifts: op 0-7 = RLC RRC RL RR SLA SRA SLL SRL
static uint8_t rot(z80 *z, int op, uint8_t v) {
    int r, c;
    switch (op) {
    case 0: c = v >> 7; r = (v << 1) | c; break;
    case 1: c = v & 1; r = (v >> 1) | (c << 7); break;
    case 2: c = v >> 7; r = (v << 1) | (z->f & FC); break;
    case 3: c = v & 1; r = (v >> 1) | ((z->f & FC) << 7); break;
    case 4: c = v >> 7; r = v << 1; break;
    case 5: c = v & 1; r = (v >> 1) | (v & 0x80); break;
    case 6: c = v >> 7; r = (v << 1) | 1; break;
    default: c = v & 1; r = v >> 1; break;
    }
    r &= 0xff;
    z->f = SZ53P[r] | c;
    return r;
}

static void daa(z80 *z) {
    int a = z->a, add = 0, c = z->f & FC;
    if ((z->f & FH) || (a & 0x0f) > 9) add = 6;
    if (c || a > 0x99) { add |= 0x60; c = FC; }
    if (z->f & FN) {
        int h = (z->f & FH) && (a & 0x0f) < 6 ? FH : 0;
        a = (a - add) & 0xff;
        z->f = SZ53P[a] | c | FN | h;
    } else {
        int h = (a & 0x0f) > 9 ? FH : 0;
        a = (a + add) & 0xff;
        z->f = SZ53P[a] | c | h;
    }
    z->a = a;
}

// ------------------------------------------------------------------ registers by index

// r: 0 B 1 C 2 D 3 E 4 H 5 L 7 A (6 is (HL), handled by the caller).
// xy: 0 for HL, 1 IX, 2 IY: H and L then mean the index register halves.
static uint8_t getr(z80 *z, int r, int xy) {
    switch (r) {
    case 0: return z->b;
    case 1: return z->c;
    case 2: return z->d;
    case 3: return z->e;
    case 4: return xy == 0 ? z->h : (xy == 1 ? z->ix : z->iy) >> 8;
    case 5: return xy == 0 ? z->l : (xy == 1 ? z->ix : z->iy) & 0xff;
    default: return z->a;
    }
}

static void setr(z80 *z, int r, int v, int xy) {
    v &= 0xff;
    switch (r) {
    case 0: z->b = v; break;
    case 1: z->c = v; break;
    case 2: z->d = v; break;
    case 3: z->e = v; break;
    case 4:
        if (xy == 0) z->h = v;
        else if (xy == 1) z->ix = (z->ix & 0xff) | (v << 8);
        else z->iy = (z->iy & 0xff) | (v << 8);
        break;
    case 5:
        if (xy == 0) z->l = v;
        else if (xy == 1) z->ix = (z->ix & 0xff00) | v;
        else z->iy = (z->iy & 0xff00) | v;
        break;
    default: z->a = v;
    }
}

static uint16_t getxy(z80 *z, int xy) { return xy == 0 ? HL : xy == 1 ? z->ix : z->iy; }
static void setxy(z80 *z, int xy, unsigned v) {
    v &= 0xffff;
    if (xy == 0) set_hl(z, v); else if (xy == 1) z->ix = v; else z->iy = v;
}
// rp: 0 BC 1 DE 2 HL/IX/IY 3 SP
static uint16_t getrp(z80 *z, int p, int xy) { return p == 0 ? BC : p == 1 ? DE : p == 2 ? getxy(z, xy) : z->sp; }
static void setrp(z80 *z, int p, unsigned v, int xy) {
    v &= 0xffff;
    if (p == 0) set_bc(z, v); else if (p == 1) set_de(z, v); else if (p == 2) setxy(z, xy, v); else z->sp = v;
}
// rp2 for PUSH/POP: 3 is AF
static uint16_t getrp2(z80 *z, int p, int xy) { return p == 3 ? AF : getrp(z, p, xy); }
static void setrp2(z80 *z, int p, unsigned v, int xy) { if (p == 3) set_af(z, v); else setrp(z, p, v, xy); }

static bool cond(z80 *z, int cc) {
    switch (cc) {
    case 0: return !(z->f & FZ);
    case 1: return z->f & FZ;
    case 2: return !(z->f & FC);
    case 3: return z->f & FC;
    case 4: return !(z->f & FP);
    case 5: return z->f & FP;
    case 6: return !(z->f & FS);
    default: return z->f & FS;
    }
}

// ------------------------------------------------------------------ execution

static int exec_cb(z80 *z, int xy);
static int exec_ed(z80 *z);

// address of (HL) or (IX+d), fetched only when the opcode uses it
static uint16_t mem(z80 *z, int xy) { return xy == 0 ? HL : (uint16_t)(getxy(z, xy) + fetchd(z)); }

// Run one unprefixed (xy = 0) or DD/FD-prefixed (xy = 1/2) opcode.
static int exec(z80 *z, uint8_t op, int xy) {
    int t = CYC[op];
    int x = op >> 6, y = (op >> 3) & 7, zz = op & 7, p = y >> 1, q = y & 1;

    if (x == 1) {
        if (op == 0x76) { z->halted = true; return 4; }
        if (zz == 6) { uint16_t a = mem(z, xy); setr(z, y, rb(z, a), 0); return t + (xy ? 8 : 0); }
        if (y == 6) { uint16_t a = mem(z, xy); wb(z, a, getr(z, zz, 0)); return t + (xy ? 8 : 0); }
        setr(z, y, getr(z, zz, xy), xy);
        return t;
    }
    if (x == 2) {
        if (zz == 6) { uint16_t a = mem(z, xy); alu(z, y, rb(z, a)); return t + (xy ? 8 : 0); }
        alu(z, y, getr(z, zz, xy));
        return t;
    }
    if (x == 0) {
        switch (zz) {
        case 0:
            switch (y) {
            case 0: return t;
            case 1: { uint8_t a = z->a, f = z->f; z->a = z->a_; z->f = z->f_; z->a_ = a; z->f_ = f; return t; }
            case 2: { int d = fetchd(z); z->b--; if (z->b) { z->pc += d; t += 5; } return t; }
            case 3: { int d = fetchd(z); z->pc += d; return t; }
            default: { int d = fetchd(z); if (cond(z, y - 4)) { z->pc += d; t += 5; } return t; }
            }
        case 1:
            if (q == 0) setrp(z, p, fetchw(z), xy);
            else setxy(z, xy, add16(z, getxy(z, xy), getrp(z, p, xy)));
            return t;
        case 2:
            switch (y) {
            case 0: wb(z, BC, z->a); break;
            case 1: z->a = rb(z, BC); break;
            case 2: wb(z, DE, z->a); break;
            case 3: z->a = rb(z, DE); break;
            case 4: ww(z, fetchw(z), getxy(z, xy)); break;
            case 5: setxy(z, xy, rw(z, fetchw(z))); break;
            case 6: wb(z, fetchw(z), z->a); break;
            default: z->a = rb(z, fetchw(z));
            }
            return t;
        case 3:
            setrp(z, p, getrp(z, p, xy) + (q ? -1 : 1), xy);
            return t;
        case 4: case 5:
            if (y == 6) {
                uint16_t a = mem(z, xy);
                uint8_t v = rb(z, a);
                wb(z, a, zz == 4 ? inc8(z, v) : dec8(z, v));
                return t + (xy ? 8 : 0);
            }
            setr(z, y, zz == 4 ? inc8(z, getr(z, y, xy)) : dec8(z, getr(z, y, xy)), xy);
            return t;
        case 6:
            if (y == 6) { uint16_t a = mem(z, xy); wb(z, a, fetch(z)); return t + (xy ? 5 : 0); }
            setr(z, y, fetch(z), xy);
            return t;
        default:
            switch (y) {
            case 0: { int c = z->a >> 7; z->a = (z->a << 1) | c; z->f = (z->f & (FS | FZ | FP)) | (z->a & (F3 | F5)) | c; break; }
            case 1: { int c = z->a & 1; z->a = (z->a >> 1) | (c << 7); z->f = (z->f & (FS | FZ | FP)) | (z->a & (F3 | F5)) | c; break; }
            case 2: { int c = z->a >> 7; z->a = (z->a << 1) | (z->f & FC); z->f = (z->f & (FS | FZ | FP)) | (z->a & (F3 | F5)) | c; break; }
            case 3: { int c = z->a & 1; z->a = (z->a >> 1) | ((z->f & FC) << 7); z->f = (z->f & (FS | FZ | FP)) | (z->a & (F3 | F5)) | c; break; }
            case 4: daa(z); break;
            case 5: z->a ^= 0xff; z->f = (z->f & (FS | FZ | FP | FC)) | FH | FN | (z->a & (F3 | F5)); break;
            case 6: z->f = (z->f & (FS | FZ | FP)) | FC | (z->a & (F3 | F5)); break;
            default: z->f = (z->f & (FS | FZ | FP)) | ((z->f & FC) ? FH : FC) | (z->a & (F3 | F5)); break;
            }
            return t;
        }
    }
    // x == 3
    switch (zz) {
    case 0: if (cond(z, y)) { z->pc = pop(z); t += 6; } return t;
    case 1:
        if (q == 0) { setrp2(z, p, pop(z), xy); return t; }
        switch (p) {
        case 0: z->pc = pop(z); return t;
        case 1: {
            uint8_t v;
            v = z->b; z->b = z->b_; z->b_ = v; v = z->c; z->c = z->c_; z->c_ = v;
            v = z->d; z->d = z->d_; z->d_ = v; v = z->e; z->e = z->e_; z->e_ = v;
            v = z->h; z->h = z->h_; z->h_ = v; v = z->l; z->l = z->l_; z->l_ = v;
            return t;
        }
        case 2: z->pc = getxy(z, xy); return t;
        default: z->sp = getxy(z, xy); return t;
        }
    case 2: { uint16_t a = fetchw(z); if (cond(z, y)) z->pc = a; return t; }
    case 3:
        switch (y) {
        case 0: z->pc = fetchw(z); return t;
        case 1: return exec_cb(z, xy);
        case 2: { uint8_t n = fetch(z); z->bus->output((z->a << 8) | n, z->a); return t; }
        case 3: { uint8_t n = fetch(z); z->a = z->bus->input((z->a << 8) | n); return t; }
        case 4: { uint16_t v = rw(z, z->sp); ww(z, z->sp, getxy(z, xy)); setxy(z, xy, v); return t; }
        case 5: { uint16_t v = DE; set_de(z, HL); set_hl(z, v); return t; }
        case 6: z->iff1 = z->iff2 = 0; return t;
        default: z->iff1 = z->iff2 = 1; z->ei_delay = true; return t;
        }
    case 4: { uint16_t a = fetchw(z); if (cond(z, y)) { push(z, z->pc); z->pc = a; t += 7; } return t; }
    case 5:
        if (q == 0) { push(z, getrp2(z, p, xy)); return t; }
        switch (p) {
        case 0: { uint16_t a = fetchw(z); push(z, z->pc); z->pc = a; return t; }
        case 1: incr(z); return exec(z, fetch(z), 1) + 4;
        case 2: incr(z); return exec_ed(z);
        default: incr(z); return exec(z, fetch(z), 2) + 4;
        }
    case 6: alu(z, y, fetch(z)); return t;
    default: push(z, z->pc); z->pc = y * 8; return t;
    }
}

static int exec_cb(z80 *z, int xy) {
    uint16_t a;
    uint8_t op;
    if (xy) { a = getxy(z, xy) + fetchd(z); op = fetch(z); }
    else { incr(z); op = fetch(z); a = HL; }
    int x = op >> 6, y = (op >> 3) & 7, zz = op & 7;
    bool memop = xy != 0 || zz == 6;
    uint8_t v = memop ? rb(z, a) : getr(z, zz, 0), r;
    if (x == 1) {
        int bit = v & (1 << y);
        z->f = (z->f & FC) | FH | (bit ? 0 : FZ | FP) | (bit & FS) | ((memop ? (a >> 8) : v) & (F3 | F5));
        return xy ? 20 : (zz == 6 ? 12 : 8);
    }
    if (x == 0) r = rot(z, y, v);
    else if (x == 2) r = v & ~(1 << y);
    else r = v | (1 << y);
    if (memop) {
        wb(z, a, r);
        if (xy && zz != 6) setr(z, zz, r, 0);   // undocumented copy to a register
        return xy ? 23 : 15;
    }
    setr(z, zz, r, 0);
    return 8;
}

static int exec_ed(z80 *z) {
    uint8_t op = fetch(z);
    int x = op >> 6, y = (op >> 3) & 7, zz = op & 7, p = y >> 1, q = y & 1;
    if (x == 1) {
        switch (zz) {
        case 0: {
            uint8_t v = z->bus->input(BC);
            if (y != 6) setr(z, y, v, 0);
            z->f = (z->f & FC) | SZ53P[v];
            return 12;
        }
        case 1: z->bus->output(BC, y == 6 ? 0 : getr(z, y, 0)); return 12;
        case 2: if (q == 0) sbc16(z, getrp(z, p, 0)); else adc16(z, getrp(z, p, 0)); return 15;
        case 3: {
            uint16_t a = fetchw(z);
            if (q == 0) ww(z, a, getrp(z, p, 0)); else setrp(z, p, rw(z, a), 0);
            return 20;
        }
        case 4: { uint8_t v = z->a; z->a = 0; sub8(z, v, false, true); return 8; }
        case 5: z->pc = pop(z); z->iff1 = z->iff2; return 14;
        case 6: { static const uint8_t IM[8] = {0, 0, 1, 2, 0, 0, 1, 2}; z->im = IM[y]; return 8; }
        default:
            switch (y) {
            case 0: z->i = z->a; return 9;
            case 1: z->r = z->a; return 9;
            case 2: z->a = z->i; z->f = (z->f & FC) | SZ53[z->a] | (z->iff2 ? FP : 0); return 9;
            case 3: z->a = z->r; z->f = (z->f & FC) | SZ53[z->a] | (z->iff2 ? FP : 0); return 9;
            case 4: {   // RRD
                uint8_t m = rb(z, HL);
                wb(z, HL, (z->a << 4) | (m >> 4));
                z->a = (z->a & 0xf0) | (m & 0x0f);
                z->f = (z->f & FC) | SZ53P[z->a];
                return 18;
            }
            case 5: {   // RLD
                uint8_t m = rb(z, HL);
                wb(z, HL, (m << 4) | (z->a & 0x0f));
                z->a = (z->a & 0xf0) | (m >> 4);
                z->f = (z->f & FC) | SZ53P[z->a];
                return 18;
            }
            default: return 8;
            }
        }
    }
    if (x == 2 && zz <= 3 && y >= 4) {
        int inc = (y & 1) ? -1 : 1;
        bool repeat = y >= 6;
        switch (zz) {
        case 0: {   // LDI LDD LDIR LDDR
            uint8_t v = rb(z, HL);
            wb(z, DE, v);
            set_hl(z, (HL + inc) & 0xffff); set_de(z, (DE + inc) & 0xffff); set_bc(z, (BC - 1) & 0xffff);
            int n = v + z->a;
            z->f = (z->f & (FS | FZ | FC)) | (BC ? FP : 0) | (n & F3) | ((n << 4) & F5);
            if (repeat && BC) { z->pc -= 2; return 21; }
            return 16;
        }
        case 1: {   // CPI CPD CPIR CPDR
            uint8_t v = rb(z, HL), r = z->a - v;
            int h = (z->a ^ v ^ r) & FH;
            set_hl(z, (HL + inc) & 0xffff); set_bc(z, (BC - 1) & 0xffff);
            int n = r - (h ? 1 : 0);
            z->f = (z->f & FC) | FN | h | (r & FS) | (r == 0 ? FZ : 0) | (BC ? FP : 0) | (n & F3) | ((n << 4) & F5);
            if (repeat && BC && r != 0) { z->pc -= 2; return 21; }
            return 16;
        }
        case 2: {   // INI IND INIR INDR
            uint8_t v = z->bus->input(BC);
            wb(z, HL, v);
            set_hl(z, (HL + inc) & 0xffff); z->b--;
            z->f = SZ53[z->b] | FN | (z->f & FC);
            if (repeat && z->b) { z->pc -= 2; return 21; }
            return 16;
        }
        default: {  // OUTI OUTD OTIR OTDR
            uint8_t v = rb(z, HL);
            z->b--;
            z->bus->output(BC, v);
            set_hl(z, (HL + inc) & 0xffff);
            z->f = SZ53[z->b] | FN | (z->f & FC);
            if (repeat && z->b) { z->pc -= 2; return 21; }
            return 16;
        }
        }
    }
    return 8;   // other ED codes act as NOPs
}

int z80_step(z80 *z) {
    if (z->nmi_pending) {
        z->nmi_pending = false;
        z->halted = false;
        z->iff1 = 0;
        incr(z);
        push(z, z->pc);
        z->pc = 0x66;
        return 11;
    }
    if (z->irq && z->iff1 && !z->ei_delay) {
        z->halted = false;
        z->iff1 = z->iff2 = 0;
        incr(z);
        if (z->bus->irq_ack) z->bus->irq_ack();
        if (z->im == 2) {
            push(z, z->pc);
            z->pc = rw(z, (z->i << 8) | 0xff);
            return 19;
        }
        push(z, z->pc);   // IM 0 with RST 38h on the bus, or IM 1
        z->pc = 0x38;
        return 13;
    }
    z->ei_delay = false;
    if (z->halted) { incr(z); return 4; }
    incr(z);
    return exec(z, fetch(z), 0);
}
