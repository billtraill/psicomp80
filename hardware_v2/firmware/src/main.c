// COMP80 v2 firmware: the PSI COMP80 on one RP2350, running its unchanged ROM
// images.  Core 0 runs the Z80 at its real speed and feeds the HDMI output's
// DMA; core 1 runs the USB keyboard and draws the screen.
#include <stdio.h>

#include "board.h"
#include "comp80.h"
#include "hardware/clocks.h"
#include "hardware/gpio.h"
#include "hardware/pll.h"
#include "hardware/vreg.h"
#include "keyboard.h"
#include "menu.h"
#include "pico/multicore.h"
#include "pico/stdlib.h"
#include "storage.h"
#include "tape.h"
#include "video.h"

// Clocks: the system at 240 MHz (PIO-USB wants a multiple of 48 MHz), the USB
// PLL moved to 126 MHz for the HSTX (252 Mb/s for 640 x 480), and the USB,
// ADC and peripheral clocks taken from the system PLL instead.
static void clocks_setup(void) {
    vreg_set_voltage(VREG_VOLTAGE_1_20);
    sleep_ms(10);
    set_sys_clock_khz(240000, true);
    clock_configure(clk_peri, 0, CLOCKS_CLK_PERI_CTRL_AUXSRC_VALUE_CLKSRC_PLL_SYS, 240 * MHZ, 120 * MHZ);
    clock_configure(clk_usb, 0, CLOCKS_CLK_USB_CTRL_AUXSRC_VALUE_CLKSRC_PLL_SYS, 240 * MHZ, 48 * MHZ);
    clock_configure(clk_adc, 0, CLOCKS_CLK_ADC_CTRL_AUXSRC_VALUE_CLKSRC_PLL_SYS, 240 * MHZ, 48 * MHZ);
    pll_init(pll_usb, 1, 1512 * MHZ, 6, 2);
    clock_configure(clk_hstx, 0, CLOCKS_CLK_HSTX_CTRL_AUXSRC_VALUE_CLKSRC_PLL_USB, 126 * MHZ, 126 * MHZ);
}

static void core1_main(void) {
    keyboard_init();
    for (;;) {
        keyboard_task();
        video_update();
    }
}

int main(void) {
    clocks_setup();
    stdio_init_all();
    gpio_init(PIN_HALT_LED);
    gpio_set_dir(PIN_HALT_LED, GPIO_OUT);
    printf("COMP80 v2\n");

    video_init();
    multicore_launch_core1(core1_main);

    if (!storage_mount()) menu_message("NO MICROSD CARD: STARTING THE BUILT-IN BURP ROM.",
                                       "PUT ROMS IN /COMP80/ROMS AND TAPES IN /COMP80/TAPES.");
    storage_load_settings(&cfg);
    power_on();

    // Run the Z80 a millisecond at a time against the system timer, so it keeps
    // its real speed however long the keyboard or the card takes.
    absolute_time_t next = get_absolute_time();
    uint64_t behind_limit = 50000;           // after 50 ms behind (a menu, a card), don't race to catch up
    for (;;) {
        int k;
        while (keyboard_get(&k)) {
            if (k == KEY_F1 || k == KEY_F2) {
                menu_run(k == KEY_F2);
                next = get_absolute_time();
            } else if (k == KEY_F12) {
                power_on();
            } else if (k < 0x100) {
                while (!comp80_key(k)) comp80_run(comp80_cfg.clock / 1000);   // the last key not taken yet
            }
        }
        comp80_run(comp80_cfg.clock / 1000);
        tape_poll(comp80_cycles);
        gpio_put(PIN_HALT_LED, comp80_cpu.halted);
        next = delayed_by_us(next, 1000);
        if (absolute_time_diff_us(next, get_absolute_time()) > (int64_t)behind_limit) next = get_absolute_time();
        sleep_until(next);
    }
}
