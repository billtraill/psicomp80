// The microSD card in SPI mode through soc.v's SPI port, as FatFs's disk I/O
// layer.  The same protocol as the v2 firmware's sdcard.c.
#include <string.h>

#include "ff.h"         // before diskio.h, which uses its types
#include "diskio.h"
#include "hw.h"

static volatile DSTATUS status = STA_NOINIT;
static int block_addressed;     // SDHC/SDXC: sector numbers, not byte addresses

static uint8_t xfer(uint8_t v) {
    SPI_DATA = v;
    while (SPI_BUSY) ;
    return SPI_DATA;
}

static int wait_ready(uint32_t ms) {
    uint32_t t = usec();
    while (xfer(0xff) != 0xff) if (usec() - t > ms * 1000) return 0;
    return 1;
}

static void deselect(void) { SPI_CS = 1; xfer(0xff); }
static int select_card(void) {
    SPI_CS = 0;
    xfer(0xff);
    if (wait_ready(500)) return 1;
    deselect();
    return 0;
}

static uint8_t cmd(uint8_t c, uint32_t arg) {
    if (c & 0x80) {                         // ACMDn = CMD55 then CMDn
        c &= 0x7f;
        uint8_t r = cmd(55, 0);
        if (r > 1) return r;
    }
    if (c != 12) {
        deselect();
        if (!select_card()) return 0xff;
    }
    xfer(0x40 | c);
    xfer(arg >> 24); xfer(arg >> 16); xfer(arg >> 8); xfer(arg);
    xfer(c == 0 ? 0x95 : c == 8 ? 0x87 : 0x01);
    if (c == 12) xfer(0xff);
    uint8_t r;
    int n = 10;
    do r = xfer(0xff); while ((r & 0x80) && --n);
    return r;
}

static int read_block(uint8_t *buf, unsigned n) {
    uint32_t t = usec();
    uint8_t tok;
    do tok = xfer(0xff); while (tok == 0xff && usec() - t < 200000);
    if (tok != 0xfe) return 0;
    for (unsigned i = 0; i < n; i++) buf[i] = xfer(0xff);
    xfer(0xff); xfer(0xff);                 // CRC
    return 1;
}

static int write_block(const uint8_t *buf, uint8_t token) {
    if (!wait_ready(500)) return 0;
    xfer(token);
    if (token == 0xfd) return 1;
    for (int i = 0; i < 512; i++) xfer(buf[i]);
    xfer(0xff); xfer(0xff);
    return (xfer(0xff) & 0x1f) == 0x05;
}

DSTATUS disk_initialize(BYTE drv) {
    if (drv) return STA_NOINIT;
    SPI_DIV = 62;                           // 400 kHz
    SPI_CS = 1;
    for (int i = 0; i < 10; i++) xfer(0xff);
    status = STA_NOINIT;
    block_addressed = 0;
    if (cmd(0, 0) == 1) {
        uint32_t t = usec();
        if (cmd(8, 0x1aa) == 1) {
            uint8_t ocr[4];
            for (int i = 0; i < 4; i++) ocr[i] = xfer(0xff);
            if (ocr[2] == 0x01 && ocr[3] == 0xaa) {
                while (usec() - t < 1000000 && cmd(0x80 | 41, 1u << 30)) ;
                if (usec() - t < 1000000 && cmd(58, 0) == 0) {
                    for (int i = 0; i < 4; i++) ocr[i] = xfer(0xff);
                    block_addressed = ocr[0] & 0x40;
                    status = 0;
                }
            }
        } else {
            while (usec() - t < 1000000 && cmd(0x80 | 41, 0)) ;
            if (usec() - t < 1000000 && cmd(16, 512) == 0) status = 0;
        }
    }
    deselect();
    if (status == 0) SPI_DIV = 1;           // 12.5 MHz
    return status;
}

DSTATUS disk_status(BYTE drv) { return drv ? STA_NOINIT : status; }

DRESULT disk_read(BYTE drv, BYTE *buf, LBA_t sector, UINT count) {
    if (drv || !count) return RES_PARERR;
    if (status & STA_NOINIT) return RES_NOTRDY;
    uint32_t addr = block_addressed ? sector : sector * 512;
    int ok;
    if (count == 1) ok = cmd(17, addr) == 0 && read_block(buf, 512);
    else {
        ok = cmd(18, addr) == 0;
        for (; ok && count; count--, buf += 512) ok = read_block(buf, 512);
        cmd(12, 0);
    }
    deselect();
    return ok ? RES_OK : RES_ERROR;
}

DRESULT disk_write(BYTE drv, const BYTE *buf, LBA_t sector, UINT count) {
    if (drv || !count) return RES_PARERR;
    if (status & STA_NOINIT) return RES_NOTRDY;
    uint32_t addr = block_addressed ? sector : sector * 512;
    int ok;
    if (count == 1) ok = cmd(24, addr) == 0 && write_block(buf, 0xfe);
    else {
        ok = cmd(25, addr) == 0;
        for (; ok && count; count--, buf += 512) ok = write_block(buf, 0xfc);
        if (!write_block(NULL, 0xfd)) ok = 0;
    }
    deselect();
    return ok ? RES_OK : RES_ERROR;
}

DRESULT disk_ioctl(BYTE drv, BYTE c, void *buf) {
    (void)buf;
    if (drv) return RES_PARERR;
    if (status & STA_NOINIT) return RES_NOTRDY;
    if (c == CTRL_SYNC) { int ok = select_card(); deselect(); return ok ? RES_OK : RES_ERROR; }
    return RES_PARERR;
}

DWORD get_fattime(void) { return ((DWORD)(2026 - 1980) << 25) | (1u << 21) | (1u << 16); }
