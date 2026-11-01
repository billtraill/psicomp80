// The National MM57109 calculator chip, as the web emulator (web/src/comp80.js)
// and the MAME driver model it.  Shared by the v2 firmware and the v3 FPGA's
// soft processor; mm57109.h says what the machine around it supplies.
#include "mm57109.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Two one-shot timers, in Z80 cycles: the chip finishing an instruction, and
// the next digit of an OUT.  NEVER when off; mm_due is the sooner.
static uint64_t t_mm = NEVER, t_digit = NEVER;
uint64_t mm_due = NEVER;
static void tick_mm(void);
static void tick_digit(void);
static void set_due(void) { mm_due = t_mm < t_digit ? t_mm : t_digit; }

// MM57109 microcycles (about 10 us on the real chip) to Z80 cycles
static uint64_t micro(uint32_t t) { return (uint64_t)t * mm_clock / 100000; }

// ------------------------------------------------------------------ MM57109
// The National MM57109 calculator chip that BURP does its arithmetic on.
// Port 60 drives its instruction lines (bits 0-5) and HOLD (bit 7); port 03
// reads its RDY (bit 5: 1 while it executes), BR (bit 6: 0 when a test is
// true) and digit outputs (bits 0-3).  Its R/W output, which pulses once for
// each digit of an OUT instruction, is the Z80's INT.  See comp80.js for how
// BURP drives it.

// MM57109 execution times in microcycles (data sheet averages), by opcode.
static const uint32_t MM_TIMES[64] = {
    238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 152, 151, 166, 1312, 284, 134,
    208, 278, 197, 271, 191, 186, 583, 395, 163, 2314, 2314, 812, 839, 1385, 168, 173,
    166, 552, 157, 905, 56200, 56200, 35000, 163, 185, 163, 185, 163, 30700, 30700, 448, 734,
    652, 30800, 27400, 3000, 7000, 24800, 30700, 4500, 55400, 2200, 2200, 3200, 7800, 130, 130, 122,
};

static uint32_t mm_inv_time(int w) {
    switch (w) {
    case 0x24: case 0x25: return 54000;
    case 0x26: return 30200;
    case 0x39: case 0x3a: return 1700;
    case 0x3b: return 2700;
    case 0x3c: return 7300;
    default: return 1700;
    }
}

// What happens when RDY comes back (mm_then), and what a second word does (mm_word2).
enum { THEN_NONE, THEN_BRANCH_TRUE, THEN_BRANCH_FALSE, THEN_WORD2_IGNORE, THEN_WORD2_SMDC, THEN_WORD2_INV };
enum { W2_NONE, W2_IGNORE, W2_SMDC, W2_INV };

static double mmX, mmY, mmZ, mmT, mmM;
static bool mm_sci, mm_error, mm_entry, mm_after_enter, mm_hold, mm_busy, mm_br;
static int mm_mdc, mm_then, mm_word2, mm_code;
static uint8_t mm_digits[16];
static int mm_ndigits, mm_digit_pos;
// number entry
static bool en_exp, en_dp;
static int en_dp_index, en_mant[8], en_nmant, en_exp_digits[2], en_nexp, en_mant_sign, en_exp_sign;

static void entry_reset(void) {
    en_exp = false; en_dp = false; en_dp_index = 0;
    en_nmant = 0; en_nexp = 0; en_mant_sign = 1; en_exp_sign = 1;
}

void mm_reset(void) {
    mmX = mmY = mmZ = mmT = mmM = 0;
    mm_sci = false;
    mm_mdc = 8;
    mm_error = false;
    mm_entry = false;
    mm_after_enter = false;
    mm_hold = true;
    mm_busy = false;
    mm_br = false;
    mm_word2 = W2_NONE;
    mm_then = THEN_NONE;
    mm_ndigits = mm_digit_pos = 0;
    mm_code = 0;
    entry_reset();
    t_mm = NEVER;
    t_digit = NEVER;
    set_due();
}

uint8_t mm_read(void) {
    return (mm_busy ? 0x20 : 0) | (mm_br ? 0 : 0x40) | (mm_code & 0x0f);
}

// RDY comes back after t microcycles; then runs at that point.
static void mm_finish(uint32_t t, int then) { mm_then = then; t_mm = mm_now() + micro(t); set_due(); }

static void tick_mm(void) {
    int f = mm_then;
    mm_then = THEN_NONE;
    switch (f) {
    case THEN_BRANCH_TRUE: mm_br = true; mm_word2 = W2_IGNORE; break;
    case THEN_WORD2_IGNORE: mm_busy = false; mm_word2 = W2_IGNORE; break;
    case THEN_WORD2_SMDC: mm_busy = false; mm_word2 = W2_SMDC; break;
    case THEN_WORD2_INV: mm_busy = false; mm_word2 = W2_INV; break;
    default: mm_busy = false; break;    // THEN_NONE, THEN_BRANCH_FALSE
    }
}

// OUT: one digit per R/W pulse, each an interrupt; then wait for the second word.
static void tick_digit(void) {
    if (mm_digit_pos < mm_ndigits) {
        mm_code = mm_digits[mm_digit_pos++];
        mm_irq();
        t_digit = mm_now() + micro(48);
        set_due();
    } else {
        mm_busy = false;
        mm_word2 = W2_IGNORE;
    }
}

// Round to the chip's 8 significant digits.
static double mm_round(double v) {
    if (!isfinite(v)) { mm_error = true; return 0; }
    if (v == 0) return 0;
    char s[32];
    snprintf(s, sizeof s, "%.7e", v);
    double r = strtod(s, NULL);
    int e = (int)floor(log10(fabs(r)));
    if (e > 99) { mm_error = true; return r < 0 ? -9.9999999e99 : 9.9999999e99; }
    if (e < -99) return 0;
    return r;
}

static void mm_push(double v) { mmT = mmZ; mmZ = mmY; mmY = mmX; mmX = v; }
static void mm_pop(void) { mmY = mmZ; mmZ = mmT; }

static double mm_entry_value(void) {
    double mant = 0;
    for (int i = 0; i < en_nmant; i++) mant = mant * 10 + en_mant[i];
    int dp = en_dp ? en_dp_index : en_nmant;
    double v = mant * pow(10, dp - en_nmant) * en_mant_sign;
    int e = 0;
    for (int i = 0; i < en_nexp; i++) e = e * 10 + en_exp_digits[i];
    if (en_nexp) v *= pow(10, e * en_exp_sign);
    return v;
}

// The digits of an OUT instruction in scientific notation: exponent tens and
// units, the signs (8 mantissa, 1 exponent), the decimal point position (0Bh:
// after the first digit), then the mantissa digits.
static void mm_out_digits(void) {
    double x = mm_round(mmX);
    int e = 0;
    char mant[9] = "00000000";
    if (x != 0) {
        char s[32];
        snprintf(s, sizeof s, "%.7e", fabs(x));     // d.ddddddde+nn
        mant[0] = s[0];
        memcpy(mant + 1, s + 2, 7);
        e = atoi(strchr(s, 'e') + 1);
    }
    int ae = abs(e) > 99 ? 99 : abs(e);
    int n = 0;
    mm_digits[n++] = ae / 10;
    mm_digits[n++] = ae % 10;
    mm_digits[n++] = (x < 0 ? 8 : 0) | (e < 0 ? 1 : 0);
    mm_digits[n++] = 0x0b;
    for (int i = 0; i < mm_mdc; i++) mm_digits[n++] = mant[i] - '0';
    mm_ndigits = n;
    mm_digit_pos = 0;
}

static void start_entry(bool after_enter) {
    if (mm_entry) return;
    if (after_enter) mmX = 0; else mm_push(0);
    mm_entry = true;
    entry_reset();
}

// a one-argument function: an error leaves 0
static void fn(double v, bool bad) {
    if (bad) { mm_error = true; mmX = 0; } else mmX = mm_round(v);
}

// a two-argument function: Y op X, popping the stack
static void two(double v) { v = mm_round(v); mm_pop(); mmX = v; }

// the test result shows when the instruction has executed
static void branch(uint32_t t, bool c) { mm_finish(t, c ? THEN_BRANCH_TRUE : THEN_BRANCH_FALSE); }

// The second word after INV.
static void mm_inverse(int w) {
    double x = mmX;
    switch (w) {
    case 0x24: if (x < -1 || x > 1) mm_error = true; else mmX = mm_round(asin(x)); break;
    case 0x25: if (x < -1 || x > 1) mm_error = true; else mmX = mm_round(acos(x)); break;
    case 0x26: mmX = mm_round(atan(x)); break;
    case 0x39: mmM = mm_round(mmM + x); break;
    case 0x3a: mmM = mm_round(mmM - x); break;
    case 0x3b: mmM = mm_round(mmM * x); break;
    case 0x3c: if (x == 0) mm_error = true; else mmM = mm_round(mmM / x); break;
    }
    mm_finish(mm_inv_time(w), THEN_NONE);
}

static void mm_execute(int op) {
    uint32_t T = MM_TIMES[op];
    bool entry_op = op <= 0x0f;
    // Any instruction but these ends number entry.
    if (mm_entry && !entry_op) {
        mmX = mm_round(mm_entry_value());
        mm_entry = false;
    }
    bool after_enter = mm_after_enter;
    mm_after_enter = false;
    double x = mmX, y = mmY;
    switch (op) {
    case 0x0a: start_entry(after_enter); if (!en_dp) { en_dp = true; en_dp_index = en_nmant; } break;
    case 0x0b: start_entry(after_enter); en_exp = true; break;
    case 0x0c:
        if (!mm_entry) { mmX = -mmX; break; }
        if (en_exp) en_exp_sign = -en_exp_sign; else en_mant_sign = -en_mant_sign;
        mmX = mm_entry_value();
        break;
    case 0x0d: {
        static const int PI8[8] = {3, 1, 4, 1, 5, 9, 2, 7};
        start_entry(after_enter);
        mmX = M_PI;
        memcpy(en_mant, PI8, sizeof PI8);
        en_nmant = 8; en_dp = true; en_dp_index = 1;
        break;
    }
    case 0x0e: start_entry(after_enter); break;          // AIN: no digit input here
    case 0x0f: break;                                    // HALT: a NOP that keeps number entry going
    case 0x10: branch(T, false); return;                 // TJC: the JC input isn't connected
    case 0x11: branch(T, x == 0); return;                // TX=0
    case 0x12: branch(T, x < 0); return;                 // TXLT0
    case 0x13: branch(T, fabs(x) < 1); return;           // TXF
    case 0x14: branch(T, mm_error); return;              // TERR
    case 0x15: branch(T, true); return;                  // JMP
    case 0x16:                                           // OUT
        mm_out_digits();
        t_digit = mm_now() + micro(40);
        set_due();
        return;
    case 0x17: mm_finish(T, THEN_WORD2_IGNORE); return;  // IN
    case 0x18: mm_finish(T, THEN_WORD2_SMDC); return;    // SMDC
    case 0x19: mmM = mm_round(mmM + 1); branch(T, mmM != 0); return;   // IBNZ
    case 0x1a: mmM = mm_round(mmM - 1); branch(T, mmM != 0); return;   // DBNZ
    case 0x1b: mmX = mmM; mmM = x; break;                // XEM
    case 0x1c: mmM = x; break;                           // MS
    case 0x1d: mm_push(mmM); break;                      // MR
    case 0x1e: mmX = mm_round(x * 10); break;            // LSH
    case 0x1f: mmX = mm_round(x / 10); break;            // RSH
    case 0x20: mm_finish(T, THEN_WORD2_INV); return;     // INV
    case 0x21: mm_push(x); mm_after_enter = true; break; // EN
    case 0x22: mm_sci = !mm_sci; break;                  // TOGM
    case 0x23: { double t = mmX; mmX = mmY; mmY = mmZ; mmZ = mmT; mmT = t; break; }   // ROLL
    case 0x24: fn(sin(x), false); break;
    case 0x25: fn(cos(x), false); break;
    case 0x26: fn(tan(x), false); break;
    case 0x2b: mm_error = false; break;                  // ECLR
    case 0x2c: fn(x * 180 / M_PI, false); break;         // RTD
    case 0x2d: fn(x * M_PI / 180, false); break;         // DTR
    case 0x2e: mmX = y; mm_pop(); break;                 // POP
    case 0x2f:                                           // MCLR
        mmX = mmY = mmZ = mmT = mmM = 0;
        mm_error = false;
        break;
    case 0x30: mmX = y; mmY = x; break;                  // XEY
    case 0x31: fn(exp(x), false); break;
    case 0x32: fn(pow(10, x), false); break;
    case 0x33: fn(x * x, false); break;
    case 0x34: fn(x < 0 ? 0 : sqrt(x), x < 0); break;
    case 0x35: fn(x <= 0 ? 0 : log(x), x <= 0); break;
    case 0x36: fn(x <= 0 ? 0 : log10(x), x <= 0); break;
    case 0x37: fn(x == 0 ? 0 : 1 / x, x == 0); break;
    case 0x38:
        if (y < 0 && x != round(x)) { mm_error = true; two(0); }
        else two(pow(y, x));
        break;
    case 0x39: two(y + x); break;
    case 0x3a: two(y - x); break;
    case 0x3b: two(y * x); break;
    case 0x3c: if (x == 0) { mm_error = true; two(0); } else two(y / x); break;
    default:
        if (op <= 0x09) {                                // digits
            start_entry(after_enter);
            if (!en_exp) { if (en_nmant < 8) en_mant[en_nmant++] = op; }
            else if (en_nexp < 2) en_exp_digits[en_nexp++] = op;
            mmX = mm_entry_value();
        }
        // NOP, flags and R/W pulses do nothing here
    }
    mm_finish(T, THEN_NONE);
}

void mm_write(uint8_t v) {
    mm_hold = (v & 0x80) != 0;
    if (mm_hold) return;
    int op = v & 0x3f;
    if (mm_word2 != W2_NONE) {
        int f = mm_word2;
        mm_word2 = W2_NONE;
        mm_busy = true;
        mm_br = false;
        if (f == W2_SMDC) { if (op >= 1 && op <= 8) mm_mdc = op; }
        else if (f == W2_INV) mm_inverse(op);
        if (t_mm == NEVER) mm_finish(130, THEN_NONE);
        return;
    }
    if (mm_busy) return;
    mm_busy = true;
    mm_br = false;
    mm_execute(op);
}

void mm_run(uint64_t now) {
    if (now >= t_mm) { t_mm = NEVER; set_due(); tick_mm(); }
    if (now >= t_digit) { t_digit = NEVER; set_due(); tick_digit(); }
}
