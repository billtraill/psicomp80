// The MM57109 calculator chip on ports 60 (out) and 03 (in).
#ifndef MM57109_H
#define MM57109_H

#include <stdbool.h>
#include <stdint.h>

#define NEVER UINT64_MAX

void mm_reset(void);
void mm_write(uint8_t v);          // OUT 60: instruction lines (bits 0-5) and HOLD (bit 7)
uint8_t mm_read(void);             // IN 03: digit (bits 0-3), RDY (bit 5), BR (bit 6, 0 when true)
void mm_run(uint64_t now);         // run the timers that are due
extern uint64_t mm_due;            // when the next timer is due (Z80 cycles), or NEVER

// Supplied by the machine:
extern uint32_t mm_clock;          // the Z80 clock, Hz
uint64_t mm_now(void);             // Z80 cycles since power on
void mm_irq(void);                 // raise INT (the R/W pulse); the machine clears it when the Z80 takes it

#endif
