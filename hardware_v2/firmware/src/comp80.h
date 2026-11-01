// The PSI COMP80, as the web emulator (web/src/comp80.js) and the MAME driver
// (psicomp80.cpp) have it: a 3 KB ROM at 0000, RAM 0C00-1FFF, a 2 KB screen at
// 8000 (mirrored up to FFFF unless the 32 KB expansion fills 8800-FFFF), the
// keyboard as a latched byte on port 01 with an NMI per key, the MM57109 number
// cruncher on ports 60 and 03, interrupting through IM 1, and the cassette
// interface as a bitstream on ports 00 (in, bit 0) and 20 (out, bit 7).
#ifndef COMP80_H
#define COMP80_H

#include <stdbool.h>
#include <stdint.h>

#include "z80.h"

#define COMP80_ROM_SIZE 0x0c00
#define COMP80_SCREEN   0x8000

typedef struct {
    uint32_t clock;          // Z80 clock, Hz: 2 MHz on the real machine (Wireless World, Fig. 8)
    bool expansion;          // the 32 KB memory expansion at 8800-FFFF
    bool backspace_is_rs;    // FORTH and LISP rub out with RS (1E), BURP with BS
} comp80_config;

extern uint8_t comp80_mem[0x10000];
extern z80 comp80_cpu;
extern uint64_t comp80_cycles;
extern comp80_config comp80_cfg;

// Power on with a ROM image (3072 bytes; a shorter one is padded with FF):
// RAM cleared, screen blank.
void comp80_power_on(const uint8_t *rom, int len, const comp80_config *cfg);
// The RESET key: the CPU restarts, memory stays.
void comp80_reset(void);
// Run for n cycles (or a little over).
void comp80_run(uint32_t n);
// A key with ASCII code c.  ESC is RESET.  Returns false if the last key
// hasn't been taken yet, so the caller should offer it again later.
bool comp80_key(int c);
// True when a key now would be read rather than reset the machine.
bool comp80_waiting_for_key(void);
// The screen as text, one line of 64 characters (graphics as #) per call.
void comp80_screen_line(int row, char out[65]);

// The cassette, supplied by tape.c: the level on IN 00 bit 0 (idle 1) and
// what OUT 20 bit 7 writes, each at a time in Z80 cycles.
int tape_in(uint64_t cycles);
void tape_out(uint64_t cycles, int level);

#endif
