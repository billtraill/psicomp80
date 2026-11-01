// The set-up screen.
#include "menu.h"

#include <stdio.h>
#include <string.h>
#include <strings.h>

#include "comp80.h"
#include "data.h"
#include "keyboard.h"
#include "pico/stdlib.h"
#include "tape.h"
#include "video.h"

settings cfg;

static uint8_t screen[2048];
static char roms[MAX_FILES][NAME_LEN], tapes[MAX_FILES][NAME_LEN];
static int nroms, ntapes;
static uint8_t rom_buf[4096];

// ---------------------------------------------------------------- drawing

static void clear(void) { memset(screen, 0x20, sizeof screen); }

// Text in the COMP80's codes: 20-3F as they are, 40-5F as 00-1F (bit 6 is graphics).
static void put(int row, int col, const char *s) {
    for (; *s && col < 64; s++, col++) {
        int c = *s >= 'a' && *s <= 'z' ? *s - 32 : *s;
        if (c < 0x20 || c > 0x5f) c = '?';
        screen[row * 64 + col] = c & 0x3f;
    }
}

static void rule(int row) {
    for (int col = 0; col < 64; col++) screen[row * 64 + col] = 0x40 | 0x0c;   // a graphics bar
}

void menu_message(const char *line1, const char *line2) {
    clear();
    put(14, 2, line1);
    put(16, 2, line2);
    video_source(screen);
    sleep_ms(2500);
}

// ---------------------------------------------------------------- power on

// FORTH and LISP rub out with RS; the ROM's file name says which it is
static bool is_rs_rom(const char *name) {
    for (const char *p = name; *p; p++)
        if (!strncasecmp(p, "FORTH", 5) || !strncasecmp(p, "LISP", 4)) return true;
    return false;
}

void power_on(void) {
    comp80_config c = {cfg.clock, cfg.expansion, false};
    const uint8_t *rom = rom_burp;
    int len = sizeof rom_burp;
    if (cfg.rom[0]) {
        char path[80];
        snprintf(path, sizeof path, "/COMP80/ROMS/%s", cfg.rom);
        int n = storage_read(path, rom_buf, sizeof rom_buf);
        if (n > 0) {
            rom = rom_buf;
            len = n;
            c.backspace_is_rs = is_rs_rom(cfg.rom);
        } else {
            menu_message("CAN'T READ THAT ROM FROM THE CARD:", cfg.rom);
            cfg.rom[0] = 0;
        }
    }
    if (tape_state() != TAPE_STOPPED) tape_stop(comp80_cycles);
    comp80_power_on(rom, len, &c);
    video_colour(cfg.colour);
    video_source(comp80_mem + COMP80_SCREEN);
}

// ---------------------------------------------------------------- the menu

enum { ITEM_ROM, ITEM_MEMORY, ITEM_CLOCK, ITEM_COLOUR, ITEM_TAPE, ITEM_POWER, ITEM_BACK, ITEMS };

static int rom_index(void) {
    for (int i = 0; i < nroms; i++) if (!strcasecmp(roms[i], cfg.rom)) return i + 1;
    return 0;                   // the built-in one
}

static void draw(int sel, bool tape_list, int tsel) {
    char s[80];
    clear();
    put(1, 2, "PSI COMP 80 V2");
    put(1, 40, storage_ready() ? "MICROSD CARD READY" : "NO MICROSD CARD");
    rule(2);
    if (!tape_list) {
        static const char *const LABEL[ITEMS] = {"ROM", "MEMORY", "Z80 CLOCK", "COLOUR", "TAPE",
                                                 "POWER ON WITH THESE SETTINGS", "BACK TO THE COMP80"};
        for (int i = 0; i < ITEMS; i++) {
            int row = 4 + i * 2;
            if (i == sel) put(row, 2, ">");
            put(row, 4, LABEL[i]);
            switch (i) {
            case ITEM_ROM: put(row, 16, cfg.rom[0] ? cfg.rom : "BURP (BUILT IN)"); break;
            case ITEM_MEMORY: put(row, 16, cfg.expansion ? "32K (WITH THE EXPANSION)" : "5K"); break;
            case ITEM_CLOCK: put(row, 16, cfg.clock == 4000000 ? "4 MHZ (AS MAME AND THE WEB EMULATOR)" : "2 MHZ (AS THE REAL MACHINE)"); break;
            case ITEM_COLOUR: put(row, 16, colour_names[cfg.colour]); break;
            case ITEM_TAPE:
                if (tape_state() == TAPE_PLAYING) snprintf(s, sizeof s, "PLAYING, %lu S", (unsigned long)tape_seconds(comp80_cycles));
                else if (tape_state() == TAPE_RECORDING) snprintf(s, sizeof s, "RECORDING, %lu S", (unsigned long)tape_seconds(comp80_cycles));
                else snprintf(s, sizeof s, "STOPPED");
                put(row, 16, s);
                break;
            }
        }
        put(20, 2, "LEFT/RIGHT CHANGES; ROM, MEMORY AND CLOCK TAKE EFFECT");
        put(21, 2, "AT POWER ON.");
    } else {
        put(4, 4, "TAPES IN /COMP80/TAPES ON THE CARD");
        const int top = tsel > 12 ? tsel - 12 : 0;
        for (int i = top; i < ntapes + 2 && i < top + 15; i++) {
            int row = 6 + (i - top);
            if (i == tsel) put(row, 2, ">");
            if (i == 0) put(row, 4, "STOP THE TAPE");
            else if (i == 1) put(row, 4, "RECORD A NEW TAPE");
            else { snprintf(s, sizeof s, "PLAY %s", tapes[i - 2]); put(row, 4, s); }
        }
        put(22, 2, "START THE TAPE, THEN READ OR TAPE ON THE COMP80.");
    }
    rule(26);
    put(27, 2, "UP/DOWN CHOOSE   RETURN SELECT   F1 BACK TO THE COMP80");
    put(29, 2, "ON THE COMP80:  F1 SET-UP   F2 TAPES   F12 POWER ON");
    put(30, 2, "                ESC RESET   BACKSPACE RUB OUT   CTRL+\\ FS");
    put(31, 2, keyboard_connected() ? "" : "NO USB KEYBOARD FOUND");
}

void menu_run(bool tapes_only) {
    if (!storage_ready()) storage_mount();
    nroms = storage_list("/COMP80/ROMS", ".ROM", roms, MAX_FILES);
    ntapes = storage_list("/COMP80/TAPES", ".WAV", tapes, MAX_FILES);
    int sel = 0, tsel = 0;
    bool tape_list = tapes_only;
    video_source(screen);
    absolute_time_t redraw = get_absolute_time();
    for (;;) {
        if (time_reached(redraw)) {
            draw(sel, tape_list, tsel);
            redraw = make_timeout_time_ms(250);
        }
        tape_poll(comp80_cycles);
        int k;
        if (!keyboard_get(&k)) { sleep_ms(5); continue; }
        redraw = get_absolute_time();
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
                if (tsel == 0) tape_stop(comp80_cycles);
                else if (tsel == 1) {
                    storage_new_tape_name(name);
                    if (storage_open_tape(name, true, &f)) tape_record(&f, comp80_cycles);
                    else menu_message("CAN'T WRITE A TAPE ON THE CARD", "");
                } else if (!storage_open_tape(tapes[tsel - 2], false, &f) || !tape_play(&f, comp80_cycles)) {
                    menu_message("CAN'T PLAY THAT TAPE (PCM WAV FILES ONLY):", tapes[tsel - 2]);
                    continue;
                }
                break;
            }
            continue;
        }
        if (k == KEY_UP && sel > 0) sel--;
        else if (k == KEY_DOWN && sel < ITEMS - 1) sel++;
        else if (k == KEY_LEFT || k == KEY_RIGHT || (k == 0x0d && sel <= ITEM_COLOUR)) {
            int d = k == KEY_LEFT ? -1 : 1;
            switch (sel) {
            case ITEM_ROM: {
                int i = (rom_index() + d + nroms + 1) % (nroms + 1);
                if (i == 0) cfg.rom[0] = 0; else strcpy(cfg.rom, roms[i - 1]);
                break;
            }
            case ITEM_MEMORY: cfg.expansion = !cfg.expansion; break;
            case ITEM_CLOCK: cfg.clock = cfg.clock == 2000000 ? 4000000 : 2000000; break;
            case ITEM_COLOUR: cfg.colour = (cfg.colour + d + COLOUR_COUNT) % COLOUR_COUNT; video_colour(cfg.colour); break;
            }
        } else if (k == 0x0d && sel == ITEM_TAPE) {
            tape_list = true;
        } else if (k == 0x0d && sel == ITEM_POWER) {
            storage_save_settings(&cfg);
            power_on();
            return;
        } else if (k == 0x0d && sel == ITEM_BACK) {
            break;
        }
    }
    storage_save_settings(&cfg);
    video_source(comp80_mem + COMP80_SCREEN);
}
