// The machine, following web/src/comp80.js.  The MM57109 is in mm57109.c.
#include "comp80.h"
#include "mm57109.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

uint8_t comp80_mem[0x10000];
z80 comp80_cpu;
uint64_t comp80_cycles;
comp80_config comp80_cfg = {2000000, false, false};

static uint8_t key_latch = 0xff;
static uint64_t key_time;
static bool irq_mm_line;

// what the MM57109 model needs from the machine
uint32_t mm_clock = 2000000;
uint64_t mm_now(void) { return comp80_cycles; }
static void update_irq(void) { comp80_cpu.irq = irq_mm_line; }
void mm_irq(void) { irq_mm_line = true; update_irq(); }
// The R/W interrupt is latched until the Z80 takes it.
static void irq_ack(void) { irq_mm_line = false; update_irq(); }

// ------------------------------------------------------------------ bus

static uint8_t bus_read(uint16_t a) {
    if (a >= 0x8000 && !comp80_cfg.expansion) return comp80_mem[0x8000 | (a & 0x7ff)];
    if (a >= 0x2000 && a < 0x8000) return 0;
    return comp80_mem[a];
}

static void bus_write(uint16_t a, uint8_t v) {
    if (a < 0x0c00) return;                              // ROM
    if (a >= 0x8000) { comp80_mem[comp80_cfg.expansion ? a : (0x8000 | (a & 0x7ff))] = v; return; }
    if (a >= 0x2000) return;                             // nothing there
    comp80_mem[a] = v;
}

static uint8_t bus_input(uint16_t port) {
    switch (port & 0xff) {
    case 0x00: return tape_in(comp80_cycles) ? 0x01 : 0x00;
    case 0x01: { uint8_t v = key_latch; key_latch = 0xff; return v; }
    case 0x03: return mm_read();
    default: return 0xff;
    }
}

static void bus_output(uint16_t port, uint8_t v) {
    switch (port & 0xff) {
    case 0x20: tape_out(comp80_cycles, v >> 7); break;
    case 0x60: mm_write(v); break;
    }
}

static const z80_bus BUS = {bus_read, bus_write, bus_input, bus_output, irq_ack};

// ------------------------------------------------------------------ lifecycle

void comp80_power_on(const uint8_t *rom, int len, const comp80_config *cfg) {
    comp80_cfg = *cfg;
    mm_clock = cfg->clock;
    memset(comp80_mem, 0, sizeof comp80_mem);
    memset(comp80_mem, 0xff, COMP80_ROM_SIZE);
    memcpy(comp80_mem, rom, len < COMP80_ROM_SIZE ? len : COMP80_ROM_SIZE);
    memset(comp80_mem + COMP80_SCREEN, 0x20, 0x800);
    z80_init(&comp80_cpu, &BUS);
    comp80_reset();
}

void comp80_reset(void) {
    z80_reset(&comp80_cpu);
    key_latch = 0xff;
    key_time = 0;
    irq_mm_line = false;
    mm_reset();
    update_irq();
}

void comp80_run(uint32_t n) {
    uint64_t end = comp80_cycles + n;
    while (comp80_cycles < end) {
        comp80_cycles += z80_step(&comp80_cpu);
        if (comp80_cycles >= mm_due) mm_run(comp80_cycles);
    }
}

// ------------------------------------------------------------------ keyboard

bool comp80_waiting_for_key(void) { return comp80_cpu.halted && key_latch == 0xff; }

bool comp80_key(int c) {
    if (c == 0x1b) { comp80_reset(); return true; }
    if (c == 0x08 && comp80_cfg.backspace_is_rs) c = 0x1e;
    if (c == 0) return false;
    if (key_latch != 0xff && comp80_cycles - key_time < comp80_cfg.clock / 20) return false;
    key_latch = ~c & 0xff;
    key_time = comp80_cycles;
    z80_nmi(&comp80_cpu);
    return true;
}

// ------------------------------------------------------------------ screen

void comp80_screen_line(int row, char out[65]) {
    for (int col = 0; col < 64; col++) {
        uint8_t v = comp80_mem[COMP80_SCREEN + row * 64 + col], c = v & 0x3f;
        out[col] = v & 0x40 ? '#' : (c < 0x20 ? c + 64 : c);
    }
    out[64] = 0;
}
