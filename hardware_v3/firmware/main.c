// COMP80 v3 system controller firmware, for the PicoRV32 in the FPGA.  The
// COMP80 itself is logic (comp80_machine.v); this loads its ROM from the
// microSD card, stands in for the MM57109 and the tape interface, turns USB
// keyboard reports into COMP80 keys, and draws the set-up screen.  The
// MM57109 model, the WAV tapes and the card's files are the v2 firmware's own
// mm57109.c, tape.c and storage.c.
#include <stdio.h>
#include <string.h>
#include <strings.h>

#include "comp80.h"
#include "ff.h"
#include "hw.h"
#include "mm57109.h"
#include "storage.h"
#include "tape.h"
#include "video.h"

const char *const colour_names[COLOUR_COUNT] = {"WHITE", "GREEN", "AMBER"};
static const uint32_t COLOURS[COLOUR_COUNT] = {0xffffff, 0x33ff66, 0xffb000};

comp80_config comp80_cfg = {2000000, false, false};     // tape.c times tapes by this clock
static settings cfg;
static uint32_t ctrl;

// ------------------------------------------------------------ what mm57109.c needs
uint32_t mm_clock = 2000000;
uint64_t mm_now(void) { return z80_cycles(); }
void mm_irq(void) { M_MM_IRQ = 1; }

// ------------------------------------------------------------ newlib's hooks
int _write(int fd, const char *p, int n) {
    (void)fd;
    for (int i = 0; i < n; i++) { while (UART & 1) ; UART = (uint8_t)p[i]; }
    return n;
}
extern char __heap_start;
void *_sbrk(int n) {
    static char *brk = &__heap_start;
    char *p = brk;
    brk += n;
    return p;
}
void _exit(int c) { (void)c; for (;;) ; }
int _close(int f) { (void)f; return -1; }
int _lseek(int f, int o, int w) { (void)f; (void)o; (void)w; return 0; }
int _read(int f, char *p, int n) { (void)f; (void)p; (void)n; return 0; }
int _fstat(int f, void *s) { (void)f; (void)s; return 0; }
int _isatty(int f) { (void)f; return 1; }
int _kill(int p, int s) { (void)p; (void)s; return -1; }
int _getpid(void) { return 1; }

// ------------------------------------------------------------ power on
extern const uint8_t rom_burp[3072];       // data.c from the v2 firmware

static void power_on(void) {
    static uint8_t rom[4096];
    const uint8_t *r = rom_burp;
    int len = sizeof rom_burp;
    bool rs = false;
    if (cfg.rom[0]) {
        char path[80];
        snprintf(path, sizeof path, "/COMP80/ROMS/%s", cfg.rom);
        int n = storage_read(path, rom, sizeof rom);
        if (n > 0) {
            r = rom; len = n;
            for (const char *p = cfg.rom; *p; p++) if (!strncasecmp(p, "FORTH", 5) || !strncasecmp(p, "LISP", 4)) rs = true;
        } else cfg.rom[0] = 0;
    }
    if (tape_state() != TAPE_STOPPED) tape_stop(z80_cycles());
    M_CTRL = ctrl = 0;                         // Z80 held in reset
    for (int a = 0; a < 0x10000; a++)
        Z80_MEM(a) = a < 0x0c00 ? (a < len ? r[a] : 0xff) : (a >= 0x8000 && a < 0x8800) ? 0x20 : 0;
    comp80_cfg = (comp80_config){cfg.clock, cfg.expansion, rs};
    mm_clock = cfg.clock;
    mm_reset();
    M_MM_STATUS = mm_read();
    M_TAPE_IN = 1;
    M_COLOUR = COLOURS[cfg.colour];
    ctrl = CTRL_RUN | (cfg.clock == 4000000 ? CTRL_4MHZ : 0) | (cfg.expansion ? CTRL_EXP : 0);
    M_CTRL = ctrl;
}

// The RESET key: the Z80 restarts, memory stays.
static void reset_key(void) {
    M_CTRL = ctrl & ~CTRL_RUN;
    mm_reset();
    M_MM_STATUS = mm_read();
    M_CTRL = ctrl;
}

// ------------------------------------------------------------ the machine's side jobs
static int last_tape_out = 1;

static void service(void) {
    uint32_t st = M_STATUS;
    if (st & ST_MM_CMD) {                      // an OUT 60: the Z80 waits for this
        mm_write(M_MM_CMD);
        M_MM_STATUS = mm_read();
        M_MM_DONE = 1;
    }
    uint64_t now = z80_cycles();
    if (now >= mm_due) { mm_run(now); M_MM_STATUS = mm_read(); }
    switch (tape_state()) {
    case TAPE_PLAYING: M_TAPE_IN = tape_in(now); break;
    case TAPE_RECORDING: {
        int lv = (st & ST_TAPE_OUT) ? 1 : 0;
        if (lv != last_tape_out) { tape_out(now, lv); last_tape_out = lv; }
        tape_poll(now);
        break;
    }
    }
}

// ------------------------------------------------------------ the keyboard
// USB HID usages to COMP80 codes, as the v2 firmware's keyboard.c (and so the
// web emulator) map them; 0x101.. are F1.., 0x120.. the arrows.
enum { KEY_F1 = 0x101, KEY_F2, KEY_F12 = 0x10c, KEY_UP = 0x120, KEY_DOWN, KEY_LEFT, KEY_RIGHT };
static const char PLAIN[] = "1234567890\r\x1b\b\t -=[]\\#;'`,./";
static const char SHIFTED[] = "!@#$%^&*()\r\x1b\b\t _+{}|~:\"~<>?";

static int code_for(uint8_t u, uint8_t mod) {
    if (mod & 0xcc) return 0;                  // Alt or GUI
    if (u >= 0x3a && u <= 0x45) return KEY_F1 + (u - 0x3a);
    switch (u) {
    case 0x28: return 0x0d;
    case 0x2a: return 0x08;
    case 0x29: return 0x1b;
    case 0x4f: return KEY_RIGHT;
    case 0x50: return KEY_LEFT;
    case 0x51: return KEY_DOWN;
    case 0x52: return KEY_UP;
    }
    if (mod & 0x11) return u == 0x31 ? 0x1c : 0;      // Ctrl+\ is FS
    int c = 0;
    if (u >= 0x04 && u <= 0x1d) c = 'A' + u - 0x04;
    else if (u >= 0x1e && u <= 0x38) c = ((mod & 0x22) ? SHIFTED : PLAIN)[u - 0x1e];
    return c >= 0x20 && c <= 0x5f ? c : 0;
}

static int queue[16], qhead, qtail;
static void push(int k) { int n = (qtail + 1) % 16; if (n != qhead) { queue[qtail] = k; qtail = n; } }
static bool pop(int *k) { if (qhead == qtail) return false; *k = queue[qhead]; qhead = (qhead + 1) % 16; return true; }

static uint32_t last_tog = 0xffffffff, held_since, repeat_at;
static uint8_t last[4], held, held_mod;

static void keyboard_poll(void) {
    uint32_t s = M_USB_STATE;
    uint32_t tog = s >> 10 & 1;
    if (tog != last_tog && (s >> 8 & 3) == 1) {
        last_tog = tog;
        uint32_t k = M_USB_KEYS;
        uint8_t now[4] = {k, k >> 8, k >> 16, k >> 24}, mod = s & 0xff, newest = 0;
        for (int i = 0; i < 4; i++) {
            if (now[i] < 4) continue;
            bool was = false;
            for (int j = 0; j < 4; j++) was |= last[j] == now[i];
            if (!was) { int c = code_for(now[i], mod); if (c) push(c); newest = now[i]; }
        }
        if (newest) { held = newest; held_since = usec(); repeat_at = 500000; }
        else { bool still = false; for (int i = 0; i < 4; i++) still |= now[i] == held; if (!still) held = 0; }
        held_mod = mod;
        memcpy(last, now, 4);
    }
    if (held && usec() - held_since > repeat_at) {    // auto-repeat
        int c = code_for(held, held_mod);
        if (c && c < 0x100) push(c);
        repeat_at += 80000;
    }
}

// comp80.c's comp80_key against the latch in the logic: false if the last key
// hasn't been read yet (for up to 1/20 s), so offer it again later
static uint64_t key_time;
static bool key(int c) {
    if (c == 0x1b) { reset_key(); return true; }
    if (c == 0x08 && comp80_cfg.backspace_is_rs) c = 0x1e;
    uint64_t now = z80_cycles();
    if ((M_STATUS & ST_KEY_FULL) && now - key_time < comp80_cfg.clock / 20) return false;
    M_KEY = c;
    key_time = now;
    return true;
}

// ------------------------------------------------------------ the set-up screen
static char roms[MAX_FILES][NAME_LEN], tapes[MAX_FILES][NAME_LEN];

static void put(int row, int col, const char *s) {
    for (; *s && col < 64; s++, col++) {
        int c = *s >= 'a' && *s <= 'z' ? *s - 32 : *s;
        if (c < 0x20 || c > 0x5f) c = '?';
        MENU_SCR(row * 64 + col) = c & 0x3f;
    }
}
static void clear(void) { for (int i = 0; i < 2048; i++) MENU_SCR(i) = 0x20; }

enum { ITEM_ROM, ITEM_MEMORY, ITEM_CLOCK, ITEM_COLOUR, ITEM_TAPE, ITEM_POWER, ITEM_BACK, ITEMS };

static void draw(int sel, bool tape_list, int tsel, int ntapes) {
    char s[80];
    clear();
    put(1, 2, "PSI COMP 80 V3");
    put(1, 40, storage_ready() ? "MICROSD CARD READY" : "NO MICROSD CARD");
    for (int c = 0; c < 64; c++) { MENU_SCR(2 * 64 + c) = 0x4c; MENU_SCR(26 * 64 + c) = 0x4c; }
    if (!tape_list) {
        static const char *const LABEL[ITEMS] = {"ROM", "MEMORY", "Z80 CLOCK", "COLOUR", "TAPE",
                                                 "POWER ON WITH THESE SETTINGS", "BACK TO THE COMP80"};
        for (int i = 0; i < ITEMS; i++) {
            int row = 4 + i * 2;
            if (i == sel) put(row, 2, ">");
            put(row, 4, LABEL[i]);
            if (i == ITEM_ROM) put(row, 16, cfg.rom[0] ? cfg.rom : "BURP (BUILT IN)");
            if (i == ITEM_MEMORY) put(row, 16, cfg.expansion ? "32K (WITH THE EXPANSION)" : "5K");
            if (i == ITEM_CLOCK) put(row, 16, cfg.clock == 4000000 ? "4 MHZ (AS MAME AND THE WEB EMULATOR)" : "2 MHZ (AS THE REAL MACHINE)");
            if (i == ITEM_COLOUR) put(row, 16, colour_names[cfg.colour]);
            if (i == ITEM_TAPE) {
                uint64_t now = z80_cycles();
                if (tape_state() == TAPE_PLAYING) snprintf(s, sizeof s, "PLAYING, %lu S", (unsigned long)tape_seconds(now));
                else if (tape_state() == TAPE_RECORDING) snprintf(s, sizeof s, "RECORDING, %lu S", (unsigned long)tape_seconds(now));
                else snprintf(s, sizeof s, "STOPPED");
                put(row, 16, s);
            }
        }
        put(20, 2, "LEFT/RIGHT CHANGES; ROM, MEMORY AND CLOCK TAKE EFFECT");
        put(21, 2, "AT POWER ON.");
    } else {
        put(4, 4, "TAPES IN /COMP80/TAPES ON THE CARD");
        int top = tsel > 12 ? tsel - 12 : 0;
        for (int i = top; i < ntapes + 2 && i < top + 15; i++) {
            int row = 6 + (i - top);
            if (i == tsel) put(row, 2, ">");
            if (i == 0) put(row, 4, "STOP THE TAPE");
            else if (i == 1) put(row, 4, "RECORD A NEW TAPE");
            else { snprintf(s, sizeof s, "PLAY %s", tapes[i - 2]); put(row, 4, s); }
        }
        put(22, 2, "START THE TAPE, THEN READ OR TAPE ON THE COMP80.");
    }
    put(27, 2, "UP/DOWN CHOOSE   RETURN SELECT   F1 BACK TO THE COMP80");
    put(29, 2, "ON THE COMP80:  F1 SET-UP   F2 TAPES   F12 POWER ON");
    put(30, 2, "                ESC RESET   BACKSPACE RUB OUT   CTRL+\\ FS");
}

static void menu(bool tapes_only) {
    if (!storage_ready()) storage_mount();
    int nroms = storage_list("/COMP80/ROMS", ".ROM", roms, MAX_FILES);
    int ntapes = storage_list("/COMP80/TAPES", ".WAV", tapes, MAX_FILES);
    int sel = 0, tsel = 0;
    bool tape_list = tapes_only;
    M_CTRL = ctrl | CTRL_MENU;
    uint32_t redraw = usec() - 1000000;
    for (;;) {
        service();
        keyboard_poll();
        if (usec() - redraw > 250000) { draw(sel, tape_list, tsel, ntapes); redraw = usec(); }
        int k;
        if (!pop(&k)) continue;
        redraw = usec() - 1000000;
        if (k == KEY_F1 || k == 0x1b) {
            if (tape_list && !tapes_only) { tape_list = false; continue; }
            break;
        }
        if (tape_list) {
            if (k == KEY_UP && tsel > 0) tsel--;
            else if (k == KEY_DOWN && tsel < ntapes + 1) tsel++;
            else if (k == 0x0d) {
                tape_file f;
                char name[NAME_LEN];
                if (tsel == 0) tape_stop(z80_cycles());
                else if (tsel == 1) {
                    storage_new_tape_name(name);
                    if (storage_open_tape(name, true, &f)) { tape_record(&f, z80_cycles()); last_tape_out = 1; }
                } else if (storage_open_tape(tapes[tsel - 2], false, &f)) tape_play(&f, z80_cycles());
                break;
            }
            continue;
        }
        if (k == KEY_UP && sel > 0) sel--;
        else if (k == KEY_DOWN && sel < ITEMS - 1) sel++;
        else if (k == KEY_LEFT || k == KEY_RIGHT || (k == 0x0d && sel <= ITEM_COLOUR)) {
            int d = k == KEY_LEFT ? -1 : 1;
            if (sel == ITEM_ROM) {
                int i = 0;
                for (int j = 0; j < nroms; j++) if (!strcasecmp(roms[j], cfg.rom)) i = j + 1;
                i = (i + d + nroms + 1) % (nroms + 1);
                if (i == 0) cfg.rom[0] = 0; else strcpy(cfg.rom, roms[i - 1]);
            }
            if (sel == ITEM_MEMORY) cfg.expansion = !cfg.expansion;
            if (sel == ITEM_CLOCK) cfg.clock = cfg.clock == 2000000 ? 4000000 : 2000000;
            if (sel == ITEM_COLOUR) { cfg.colour = (cfg.colour + d + COLOUR_COUNT) % COLOUR_COUNT; M_COLOUR = COLOURS[cfg.colour]; }
        } else if (k == 0x0d && sel == ITEM_TAPE) tape_list = true;
        else if (k == 0x0d && sel == ITEM_POWER) { storage_save_settings(&cfg); power_on(); return; }
        else if (k == 0x0d && sel == ITEM_BACK) break;
    }
    storage_save_settings(&cfg);
    M_CTRL = ctrl;
}

// ------------------------------------------------------------ main
int main(void) {
    printf("COMP80 v3\n");
    if (!storage_mount()) printf("no microSD card: the built-in BURP ROM\n");
    storage_load_settings(&cfg);
    power_on();
    for (;;) {
        service();
        keyboard_poll();
        int k;
        if (pop(&k)) {
            if (k == KEY_F1 || k == KEY_F2) menu(k == KEY_F2);
            else if (k == KEY_F12) power_on();
            else if (k < 0x100) {
                while (!key(k)) service();
            }
        }
    }
}
