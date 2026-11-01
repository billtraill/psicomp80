// The microSD card in SPI mode, as FatFs's disk I/O layer (diskio.h).  SDSC,
// SDHC and SDXC cards; one drive.
#include <string.h>

#include "board.h"
#include "ff.h"         // before diskio.h, which uses its types
#include "diskio.h"
#include "hardware/gpio.h"
#include "hardware/spi.h"
#include "pico/time.h"

static volatile DSTATUS status = STA_NOINIT;
static bool block_addressed;     // SDHC/SDXC: sector numbers, not byte addresses

static void cs(bool on) { gpio_put(PIN_SD_CS, !on); }
static uint8_t xfer(uint8_t v) { uint8_t r; spi_write_read_blocking(SD_SPI, &v, &r, 1); return r; }

static bool wait_ready(uint32_t ms) {
    absolute_time_t end = make_timeout_time_ms(ms);
    while (xfer(0xff) != 0xff) if (time_reached(end)) return false;
    return true;
}

static void deselect(void) { cs(false); xfer(0xff); }
static bool select_card(void) {
    cs(true);
    xfer(0xff);
    if (wait_ready(500)) return true;
    deselect();
    return false;
}

// Send a command; returns the R1 response (bit 7 set if none came).
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
    uint8_t frame[6] = {0x40 | c, arg >> 24, arg >> 16, arg >> 8, arg, 0x01};
    if (c == 0) frame[5] = 0x95;            // the CRCs the card checks before it's in SPI mode
    if (c == 8) frame[5] = 0x87;
    spi_write_blocking(SD_SPI, frame, 6);
    if (c == 12) xfer(0xff);
    uint8_t r;
    int n = 10;
    do r = xfer(0xff); while ((r & 0x80) && --n);
    return r;
}

static bool read_block(uint8_t *buf, unsigned n) {
    absolute_time_t end = make_timeout_time_ms(200);
    uint8_t t;
    do t = xfer(0xff); while (t == 0xff && !time_reached(end));
    if (t != 0xfe) return false;
    memset(buf, 0xff, n);
    spi_write_read_blocking(SD_SPI, buf, buf, n);
    xfer(0xff); xfer(0xff);                 // CRC
    return true;
}

static bool write_block(const uint8_t *buf, uint8_t token) {
    if (!wait_ready(500)) return false;
    xfer(token);
    if (token == 0xfd) return true;         // stop multiple-block write
    spi_write_blocking(SD_SPI, buf, 512);
    xfer(0xff); xfer(0xff);
    return (xfer(0xff) & 0x1f) == 0x05;     // data accepted
}

DSTATUS disk_initialize(BYTE drv) {
    if (drv) return STA_NOINIT;
    spi_init(SD_SPI, 400 * 1000);
    gpio_set_function(PIN_SD_MISO, GPIO_FUNC_SPI);
    gpio_set_function(PIN_SD_SCK, GPIO_FUNC_SPI);
    gpio_set_function(PIN_SD_MOSI, GPIO_FUNC_SPI);
    gpio_init(PIN_SD_CS);
    gpio_set_dir(PIN_SD_CS, GPIO_OUT);
    cs(false);
    for (int i = 0; i < 10; i++) xfer(0xff);    // 80 clocks with CS high

    status = STA_NOINIT;
    block_addressed = false;
    if (cmd(0, 0) == 1) {                       // idle
        absolute_time_t end = make_timeout_time_ms(1000);
        if (cmd(8, 0x1aa) == 1) {               // SD v2
            uint8_t ocr[4];
            for (int i = 0; i < 4; i++) ocr[i] = xfer(0xff);
            if (ocr[2] == 0x01 && ocr[3] == 0xaa) {
                while (!time_reached(end) && cmd(0x80 | 41, 1u << 30)) ;
                if (!time_reached(end) && cmd(58, 0) == 0) {
                    for (int i = 0; i < 4; i++) ocr[i] = xfer(0xff);
                    block_addressed = ocr[0] & 0x40;
                    status = 0;
                }
            }
        } else {                                // SD v1
            while (!time_reached(end) && cmd(0x80 | 41, 0)) ;
            if (!time_reached(end) && cmd(16, 512) == 0) status = 0;
        }
    }
    deselect();
    if (status == 0) spi_set_baudrate(SD_SPI, 12500 * 1000);
    return status;
}

DSTATUS disk_status(BYTE drv) { return drv ? STA_NOINIT : status; }

DRESULT disk_read(BYTE drv, BYTE *buf, LBA_t sector, UINT count) {
    if (drv || !count) return RES_PARERR;
    if (status & STA_NOINIT) return RES_NOTRDY;
    uint32_t addr = block_addressed ? sector : sector * 512;
    bool ok;
    if (count == 1) {
        ok = cmd(17, addr) == 0 && read_block(buf, 512);
    } else {
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
    bool ok;
    if (count == 1) {
        ok = cmd(24, addr) == 0 && write_block(buf, 0xfe);
    } else {
        ok = cmd(25, addr) == 0;
        for (; ok && count; count--, buf += 512) ok = write_block(buf, 0xfc);
        if (!write_block(NULL, 0xfd)) ok = false;
    }
    deselect();
    return ok ? RES_OK : RES_ERROR;
}

DRESULT disk_ioctl(BYTE drv, BYTE c, void *buf) {
    (void)buf;
    if (drv) return RES_PARERR;
    if (status & STA_NOINIT) return RES_NOTRDY;
    if (c == CTRL_SYNC) {
        bool ok = select_card();
        deselect();
        return ok ? RES_OK : RES_ERROR;
    }
    return RES_PARERR;
}

DWORD get_fattime(void) {
    return ((DWORD)(2026 - 1980) << 25) | (1u << 21) | (1u << 16);     // no clock on the board
}
