// The registers soc.v gives the firmware.
#ifndef HW_H
#define HW_H

#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))

#define UART          REG(0x10000000)          // write: send a byte; read bit 0: busy

#define M_CTRL        REG(0x20000000)          // bit 0 run the Z80, 1 4 MHz, 2 32K expansion, 3 show the menu
#define M_COLOUR      REG(0x20000004)          // RGB of the dots
#define M_KEY         REG(0x20000008)          // write: latch a key for IN 01 and pull NMI
#define M_STATUS      REG(0x2000000c)          // bit 0 halted, 1 key not read yet, 2 OUT 60 waiting, 3 tape out
#define M_MM_CMD      REG(0x20000010)          // the waiting OUT 60
#define M_MM_STATUS   REG(0x20000014)          // what IN 03 reads
#define M_MM_DONE     REG(0x20000018)          // write: the OUT 60 is dealt with, let the Z80 go on
#define M_MM_IRQ      REG(0x2000001c)          // write: raise INT
#define M_TAPE_IN     REG(0x20000020)          // the level IN 00 reads
#define M_CYCLES_LO   REG(0x20000024)          // Z80 T-states since reset (read low first)
#define M_CYCLES_HI   REG(0x20000028)
#define M_USB_KEYS    REG(0x2000002c)          // {key4, key3, key2, key1}, HID usages
#define M_USB_STATE   REG(0x20000030)          // bit 10 toggles per report, 9-8 device type (1 keyboard), 7-0 modifiers
#define M_USEC        REG(0x20000034)          // microseconds

#define CTRL_RUN 1
#define CTRL_4MHZ 2
#define CTRL_EXP 4
#define CTRL_MENU 8

#define ST_HALTED 1
#define ST_KEY_FULL 2
#define ST_MM_CMD 4
#define ST_TAPE_OUT 8

#define Z80_MEM(a)    REG(0x30000000 + ((a) << 2))
#define MENU_SCR(i)   REG(0x40000000 + ((i) << 2))

#define SPI_DATA      REG(0x50000000)
#define SPI_BUSY      REG(0x50000004)
#define SPI_CS        REG(0x50000008)          // 1 = card not selected
#define SPI_DIV       REG(0x5000000c)          // SCK = 50 MHz / (2 (div + 1))

static inline uint64_t z80_cycles(void) {
    uint32_t lo = M_CYCLES_LO;
    return (uint64_t)M_CYCLES_HI << 32 | lo;
}
static inline uint32_t usec(void) { return M_USEC; }
static inline void delay_ms(uint32_t ms) { uint32_t t = usec(); while (usec() - t < ms * 1000) ; }

#endif
