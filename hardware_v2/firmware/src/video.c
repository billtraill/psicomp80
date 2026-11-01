// HDMI from the RP2350's HSTX port, after the pico-examples dvi_out_hstx_encoder
// example: the HSTX's TMDS encoder takes RGB332 pixels from a 640 x 480
// framebuffer, which two chained DMA channels feed it a line at a time along
// with the sync command lists.  The HSTX clock is 126 MHz from the USB PLL,
// shifting out two bits a cycle: 252 Mb/s, the bit rate of 640 x 480 at 60 Hz.
#include "video.h"

#include <string.h>

#include "board.h"
#include "data.h"
#include "hardware/dma.h"
#include "hardware/gpio.h"
#include "hardware/irq.h"
#include "hardware/structs/bus_ctrl.h"
#include "hardware/structs/hstx_ctrl.h"
#include "hardware/structs/hstx_fifo.h"

// ---------------------------------------------------------------- timing (VESA 640 x 480 @ 60 Hz)

#define TMDS_CTRL_00 0x354u
#define TMDS_CTRL_01 0x0abu
#define TMDS_CTRL_10 0x154u
#define TMDS_CTRL_11 0x2abu

#define SYNC_V0_H0 (TMDS_CTRL_00 | (TMDS_CTRL_00 << 10) | (TMDS_CTRL_00 << 20))
#define SYNC_V0_H1 (TMDS_CTRL_01 | (TMDS_CTRL_00 << 10) | (TMDS_CTRL_00 << 20))
#define SYNC_V1_H0 (TMDS_CTRL_10 | (TMDS_CTRL_00 << 10) | (TMDS_CTRL_00 << 20))
#define SYNC_V1_H1 (TMDS_CTRL_11 | (TMDS_CTRL_00 << 10) | (TMDS_CTRL_00 << 20))

#define H_FRONT_PORCH 16
#define H_SYNC_WIDTH  96
#define H_BACK_PORCH  48
#define H_ACTIVE      640
#define V_FRONT_PORCH 10
#define V_SYNC_WIDTH  2
#define V_BACK_PORCH  33
#define V_ACTIVE      480
#define V_TOTAL       (V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH + V_ACTIVE)

#define HSTX_CMD_RAW_REPEAT  (0x1u << 12)
#define HSTX_CMD_TMDS        (0x2u << 12)
#define HSTX_CMD_NOP         (0xfu << 12)

static uint32_t vblank_line_vsync_off[] = {
    HSTX_CMD_RAW_REPEAT | H_FRONT_PORCH, SYNC_V1_H1,
    HSTX_CMD_RAW_REPEAT | H_SYNC_WIDTH, SYNC_V1_H0,
    HSTX_CMD_RAW_REPEAT | (H_BACK_PORCH + H_ACTIVE), SYNC_V1_H1,
    HSTX_CMD_NOP,
};
static uint32_t vblank_line_vsync_on[] = {
    HSTX_CMD_RAW_REPEAT | H_FRONT_PORCH, SYNC_V0_H1,
    HSTX_CMD_RAW_REPEAT | H_SYNC_WIDTH, SYNC_V0_H0,
    HSTX_CMD_RAW_REPEAT | (H_BACK_PORCH + H_ACTIVE), SYNC_V0_H1,
    HSTX_CMD_NOP,
};
static uint32_t vactive_line[] = {
    HSTX_CMD_RAW_REPEAT | H_FRONT_PORCH, SYNC_V1_H1,
    HSTX_CMD_NOP,
    HSTX_CMD_RAW_REPEAT | H_SYNC_WIDTH, SYNC_V1_H0,
    HSTX_CMD_NOP,
    HSTX_CMD_RAW_REPEAT | H_BACK_PORCH, SYNC_V1_H1,
    HSTX_CMD_TMDS | H_ACTIVE,
};

static uint8_t framebuf[H_ACTIVE * V_ACTIVE] __attribute__((aligned(4)));

// ---------------------------------------------------------------- DMA

#define DMACH_PING 10       // PIO-USB has channel 0
#define DMACH_PONG 11

static bool dma_pong;
static uint v_scanline = 2;
static bool vactive_cmdlist_posted;

static void __scratch_x("") dma_irq_handler(void) {
    // the channel that just finished gets the next-but-one transfer; the other
    // is already running
    uint ch_num = dma_pong ? DMACH_PONG : DMACH_PING;
    dma_channel_hw_t *ch = &dma_hw->ch[ch_num];
    dma_hw->intr = 1u << ch_num;
    dma_pong = !dma_pong;

    if (v_scanline >= V_FRONT_PORCH && v_scanline < V_FRONT_PORCH + V_SYNC_WIDTH) {
        ch->read_addr = (uintptr_t)vblank_line_vsync_on;
        ch->transfer_count = count_of(vblank_line_vsync_on);
    } else if (v_scanline < V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH) {
        ch->read_addr = (uintptr_t)vblank_line_vsync_off;
        ch->transfer_count = count_of(vblank_line_vsync_off);
    } else if (!vactive_cmdlist_posted) {
        ch->read_addr = (uintptr_t)vactive_line;
        ch->transfer_count = count_of(vactive_line);
        vactive_cmdlist_posted = true;
    } else {
        ch->read_addr = (uintptr_t)&framebuf[(v_scanline - (V_TOTAL - V_ACTIVE)) * H_ACTIVE];
        ch->transfer_count = H_ACTIVE / sizeof(uint32_t);
        vactive_cmdlist_posted = false;
    }
    if (!vactive_cmdlist_posted) v_scanline = (v_scanline + 1) % V_TOTAL;
}

void video_init(void) {
    // RGB332 pixels, four to a 32-bit word: red is bits 7-5, green 4-2, blue 1-0
    hstx_ctrl_hw->expand_tmds =
        2 << HSTX_CTRL_EXPAND_TMDS_L2_NBITS_LSB | 0 << HSTX_CTRL_EXPAND_TMDS_L2_ROT_LSB |
        2 << HSTX_CTRL_EXPAND_TMDS_L1_NBITS_LSB | 29 << HSTX_CTRL_EXPAND_TMDS_L1_ROT_LSB |
        1 << HSTX_CTRL_EXPAND_TMDS_L0_NBITS_LSB | 26 << HSTX_CTRL_EXPAND_TMDS_L0_ROT_LSB;
    hstx_ctrl_hw->expand_shift =
        4 << HSTX_CTRL_EXPAND_SHIFT_ENC_N_SHIFTS_LSB | 8 << HSTX_CTRL_EXPAND_SHIFT_ENC_SHIFT_LSB |
        1 << HSTX_CTRL_EXPAND_SHIFT_RAW_N_SHIFTS_LSB | 0 << HSTX_CTRL_EXPAND_SHIFT_RAW_SHIFT_LSB;
    // a TMDS clock period of 5 HSTX cycles; the output shifts 2 bits a cycle
    hstx_ctrl_hw->csr = 0;
    hstx_ctrl_hw->csr = HSTX_CTRL_CSR_EXPAND_EN_BITS | 5u << HSTX_CTRL_CSR_CLKDIV_LSB |
                        5u << HSTX_CTRL_CSR_N_SHIFTS_LSB | 2u << HSTX_CTRL_CSR_SHIFT_LSB |
                        HSTX_CTRL_CSR_EN_BITS;

    hstx_ctrl_hw->bit[HSTX_BIT_CK] = HSTX_CTRL_BIT0_CLK_BITS;
    hstx_ctrl_hw->bit[HSTX_BIT_CK + 1] = HSTX_CTRL_BIT0_CLK_BITS | HSTX_CTRL_BIT0_INV_BITS;
    static const int lane_bit[3] = {HSTX_BIT_D0, HSTX_BIT_D1, HSTX_BIT_D2};
    for (uint lane = 0; lane < 3; ++lane) {
        // even bits in the first half of each HSTX cycle, odd bits in the second
        uint32_t sel = (lane * 10) << HSTX_CTRL_BIT0_SEL_P_LSB | (lane * 10 + 1) << HSTX_CTRL_BIT0_SEL_N_LSB;
        hstx_ctrl_hw->bit[lane_bit[lane]] = sel;
        hstx_ctrl_hw->bit[lane_bit[lane] + 1] = sel | HSTX_CTRL_BIT0_INV_BITS;
    }
    for (int i = 12; i <= 19; ++i) gpio_set_function(i, GPIO_FUNC_HSTX);

    dma_channel_claim(DMACH_PING);
    dma_channel_claim(DMACH_PONG);
    dma_channel_config c = dma_channel_get_default_config(DMACH_PING);
    channel_config_set_chain_to(&c, DMACH_PONG);
    channel_config_set_dreq(&c, DREQ_HSTX);
    dma_channel_configure(DMACH_PING, &c, &hstx_fifo_hw->fifo, vblank_line_vsync_off,
                          count_of(vblank_line_vsync_off), false);
    c = dma_channel_get_default_config(DMACH_PONG);
    channel_config_set_chain_to(&c, DMACH_PING);
    channel_config_set_dreq(&c, DREQ_HSTX);
    dma_channel_configure(DMACH_PONG, &c, &hstx_fifo_hw->fifo, vblank_line_vsync_off,
                          count_of(vblank_line_vsync_off), false);

    dma_hw->ints0 = (1u << DMACH_PING) | (1u << DMACH_PONG);
    dma_hw->inte0 = (1u << DMACH_PING) | (1u << DMACH_PONG);
    irq_set_exclusive_handler(DMA_IRQ_0, dma_irq_handler);
    irq_set_priority(DMA_IRQ_0, 0);     // highest: a late line would tear the picture
    irq_set_enabled(DMA_IRQ_0, true);
    bus_ctrl_hw->priority = BUSCTRL_BUS_PRIORITY_DMA_W_BITS | BUSCTRL_BUS_PRIORITY_DMA_R_BITS;
    dma_channel_start(DMACH_PING);
}

// ---------------------------------------------------------------- the character screen

const char *const colour_names[COLOUR_COUNT] = {"WHITE", "GREEN", "AMBER"};
static const uint8_t COLOURS[COLOUR_COUNT] = {0xff, 0x1c, 0xf4};    // RGB332

static const uint8_t *volatile source;
static volatile uint8_t colour = 0xff;
static volatile bool all_dirty = true;
static uint8_t shown[2048];
static uint8_t shown_colour;

// A 6 x 10 cell drawn 10 x 15: the dot columns are 1,2,2,1,2,2 pixels wide
// (so the 5-dot letters, in columns 1-5, come out 2,2,1,2,2: symmetrical) and
// the rows alternate 2 and 1 pixels high.  The original's dots weren't square
// either: 64 x 32 characters filled a 4:3 television, as they fill 640 x 480.
static const uint8_t COL_W[6] = {1, 2, 2, 1, 2, 2};
static const uint8_t ROW_H[10] = {2, 1, 2, 1, 2, 1, 2, 1, 2, 1};

static void draw_cell(int i, uint8_t v, uint8_t fg) {
    int row = i / 64, col = i % 64;
    uint8_t *line = framebuf + row * 15 * H_ACTIVE + col * 10;
    bool gfx = v & 0x40;
    int code = v & 0x3f;
    for (int y = 0; y < 10; y++) {
        int bits = gfx ? font_gfx[code][y] & 0x3f : (y < 8 ? (font_ascii[code ^ 0x20][y] & 0x1f) << 1 : 0);
        uint8_t px[10];
        int k = 0;
        for (int x = 0; x < 6; x++) {
            uint8_t c = bits & (0x20 >> x) ? fg : 0;
            for (int w = 0; w < COL_W[x]; w++) px[k++] = c;
        }
        for (int h = 0; h < ROW_H[y]; h++) {
            memcpy(line, px, 10);
            line += H_ACTIVE;
        }
    }
}

void video_source(const uint8_t *screen) { source = screen; all_dirty = true; }
void video_colour(int c) { colour = COLOURS[c % COLOUR_COUNT]; }

void video_update(void) {
    const uint8_t *s = source;
    if (!s) return;
    uint8_t fg = colour;
    bool all = all_dirty || fg != shown_colour;
    all_dirty = false;
    shown_colour = fg;
    for (int i = 0; i < 2048; i++) {
        uint8_t v = s[i];
        if (all || v != shown[i]) {
            shown[i] = v;
            draw_cell(i, v, fg);
        }
    }
}
