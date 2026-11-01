// USB keyboard: TinyUSB host, boot-protocol keyboard reports.
#include "keyboard.h"

#include "board.h"
#include "pico/time.h"
#include "pico/util/queue.h"
#include "pio_usb.h"
#include "tusb.h"

static queue_t keys;
static volatile bool connected;

// HID usages 1E-38 (digits and punctuation, US layout), plain and shifted
static const char PLAIN[] = "1234567890\r\x1b\b\t -=[]\\#;'`,./";
static const char SHIFTED[] = "!@#$%^&*()\r\x1b\b\t _+{}|~:\"~<>?";

// The COMP80 code for a key, as web/src/app.js's hostKey gives it, or 0.
static int code_for(uint8_t usage, uint8_t mod) {
    bool shift = mod & (KEYBOARD_MODIFIER_LEFTSHIFT | KEYBOARD_MODIFIER_RIGHTSHIFT);
    bool ctrl = mod & (KEYBOARD_MODIFIER_LEFTCTRL | KEYBOARD_MODIFIER_RIGHTCTRL);
    if (mod & (KEYBOARD_MODIFIER_LEFTALT | KEYBOARD_MODIFIER_RIGHTALT | KEYBOARD_MODIFIER_LEFTGUI |
               KEYBOARD_MODIFIER_RIGHTGUI)) return 0;
    if (usage >= 0x3a && usage <= 0x45) return KEY_F1 + (usage - 0x3a);
    switch (usage) {
    case 0x28: return 0x0d;     // Return
    case 0x2a: return 0x08;     // Backspace
    case 0x29: return 0x1b;     // Esc: the RESET key
    case 0x4f: return KEY_RIGHT;
    case 0x50: return KEY_LEFT;
    case 0x51: return KEY_DOWN;
    case 0x52: return KEY_UP;
    }
    if (ctrl) return usage == 0x31 ? 0x1c : 0;     // Ctrl+\ is FS
    int c = 0;
    if (usage >= 0x04 && usage <= 0x1d) c = 'A' + usage - 0x04;
    else if (usage >= 0x1e && usage <= 0x38) c = (shift ? SHIFTED : PLAIN)[usage - 0x1e];
    return c >= 0x20 && c <= 0x5f ? c : 0;     // the COMP80 has codes 20-5F only
}

// auto-repeat, as the host keyboard would in the web emulator
static uint8_t held, held_mod;
static absolute_time_t next_repeat;

static void push(int k) { uint16_t v = k; queue_try_add(&keys, &v); }

void keyboard_init(void) {
    queue_init(&keys, sizeof(uint16_t), 32);
    pio_usb_configuration_t cfg = PIO_USB_DEFAULT_CONFIG;
    cfg.pin_dp = PIN_USBH_DP;
    tuh_configure(1, TUH_CFGID_RPI_PIO_USB_CONFIGURATION, &cfg);
    tuh_init(1);
}

void keyboard_task(void) {
    tuh_task();
    if (held && time_reached(next_repeat)) {
        int k = code_for(held, held_mod);
        if (k && k < 0x100) push(k);
        next_repeat = make_timeout_time_ms(80);
    }
}

bool keyboard_get(int *key) {
    uint16_t v;
    if (!queue_try_remove(&keys, &v)) return false;
    *key = v;
    return true;
}

bool keyboard_connected(void) { return connected; }

// ---------------------------------------------------------------- TinyUSB callbacks

void tuh_hid_mount_cb(uint8_t dev, uint8_t idx, uint8_t const *desc, uint16_t len) {
    (void)desc; (void)len;
    if (tuh_hid_interface_protocol(dev, idx) == HID_ITF_PROTOCOL_KEYBOARD) {
        connected = true;
        tuh_hid_receive_report(dev, idx);
    }
}

void tuh_hid_umount_cb(uint8_t dev, uint8_t idx) {
    (void)dev; (void)idx;
    connected = false;
    held = 0;
}

void tuh_hid_report_received_cb(uint8_t dev, uint8_t idx, uint8_t const *report, uint16_t len) {
    static uint8_t last[6];
    if (tuh_hid_interface_protocol(dev, idx) == HID_ITF_PROTOCOL_KEYBOARD && len >= 8) {
        const hid_keyboard_report_t *r = (const hid_keyboard_report_t *)report;
        uint8_t newest = 0;
        for (int i = 0; i < 6; i++) {
            uint8_t u = r->keycode[i];
            if (u < 4) continue;
            bool was = false;
            for (int j = 0; j < 6; j++) was |= last[j] == u;
            if (!was) {
                int k = code_for(u, r->modifier);
                if (k) push(k);
                newest = u;
            }
        }
        if (newest) {
            held = newest;
            next_repeat = make_timeout_time_ms(500);
        } else {
            bool still = false;
            for (int i = 0; i < 6; i++) still |= r->keycode[i] == held;
            if (!still) held = 0;
        }
        held_mod = r->modifier;
        for (int i = 0; i < 6; i++) last[i] = r->keycode[i];
    }
    tuh_hid_receive_report(dev, idx);
}
