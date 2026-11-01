// A Z80 for the COMP80, ported from the web emulator's z80.js, which is
// checked against MAME.  z80_step() runs one instruction (or one HALT cycle,
// or takes a pending interrupt) and returns the T-states it took.  The bus is
// four functions the machine supplies; irq_ack is called when an interrupt is
// taken.  Documented behaviour and flags; nothing on the COMP80 depends on the
// undocumented ones.
#ifndef Z80_H
#define Z80_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint8_t (*read)(uint16_t a);
    void (*write)(uint16_t a, uint8_t v);
    uint8_t (*input)(uint16_t port);
    void (*output)(uint16_t port, uint8_t v);
    void (*irq_ack)(void);
} z80_bus;

typedef struct {
    uint8_t a, f, b, c, d, e, h, l;
    uint8_t a_, f_, b_, c_, d_, e_, h_, l_;
    uint16_t ix, iy, sp, pc;
    uint8_t i, r, iff1, iff2, im;
    bool halted, ei_delay, nmi_pending, irq;
    const z80_bus *bus;
} z80;

void z80_init(z80 *z, const z80_bus *bus);
void z80_reset(z80 *z);
void z80_nmi(z80 *z);
int z80_step(z80 *z);

#endif
