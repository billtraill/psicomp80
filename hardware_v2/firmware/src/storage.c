// Files on the microSD card, through FatFs.
#include "storage.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "ff.h"
#include "video.h"

static FATFS fs;
static bool mounted;
static FIL tape_fil;

bool storage_mount(void) {
    mounted = f_mount(&fs, "", 1) == FR_OK;
    if (mounted) {
        f_mkdir("/COMP80");
        f_mkdir("/COMP80/ROMS");
        f_mkdir("/COMP80/TAPES");
    }
    return mounted;
}

bool storage_ready(void) { return mounted; }

static bool ends_with(const char *s, const char *ext) {
    size_t n = strlen(s), e = strlen(ext);
    return n >= e && !strcasecmp(s + n - e, ext);
}

static int by_name(const void *a, const void *b) { return strcasecmp(a, b); }

int storage_list(const char *dir, const char *ext, char names[][NAME_LEN], int max) {
    DIR d;
    FILINFO fi;
    int n = 0;
    if (!mounted || f_opendir(&d, dir) != FR_OK) return 0;
    while (n < max && f_readdir(&d, &fi) == FR_OK && fi.fname[0]) {
        if (fi.fattrib & (AM_DIR | AM_HID | AM_SYS) || fi.fname[0] == '.') continue;
        if (!ends_with(fi.fname, ext) || strlen(fi.fname) >= NAME_LEN) continue;
        strcpy(names[n++], fi.fname);
    }
    f_closedir(&d);
    qsort(names, n, NAME_LEN, by_name);
    return n;
}

int storage_read(const char *path, uint8_t *buf, int max) {
    FIL f;
    UINT got = 0;
    if (!mounted || f_open(&f, path, FA_READ) != FR_OK) return -1;
    FRESULT r = f_read(&f, buf, max, &got);
    f_close(&f);
    return r == FR_OK ? (int)got : -1;
}

void storage_load_settings(settings *s) {
    // defaults: the built-in BURP, 5 KB, the real machine's 2 MHz, white
    memset(s, 0, sizeof *s);
    s->clock = 2000000;
    s->colour = COLOUR_WHITE;
    char text[512];
    int n = storage_read("/COMP80/COMP80.CFG", (uint8_t *)text, sizeof text - 1);
    if (n <= 0) return;
    text[n] = 0;
    for (char *line = strtok(text, "\r\n"); line; line = strtok(NULL, "\r\n")) {
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = 0;
        const char *v = eq + 1;
        if (!strcasecmp(line, "ROM")) snprintf(s->rom, NAME_LEN, "%s", v);
        else if (!strcasecmp(line, "MEMORY")) s->expansion = atoi(v) >= 32;
        else if (!strcasecmp(line, "CLOCK")) s->clock = atoi(v) == 4000000 ? 4000000 : 2000000;
        else if (!strcasecmp(line, "COLOUR"))
            for (int c = 0; c < COLOUR_COUNT; c++) if (!strcasecmp(v, colour_names[c])) s->colour = c;
    }
}

bool storage_save_settings(const settings *s) {
    char text[256];
    int n = snprintf(text, sizeof text, "ROM=%s\nMEMORY=%d\nCLOCK=%lu\nCOLOUR=%s\n", s->rom,
                     s->expansion ? 32 : 5, (unsigned long)s->clock, colour_names[s->colour]);
    FIL f;
    UINT put;
    if (!mounted || f_open(&f, "/COMP80/COMP80.CFG", FA_WRITE | FA_CREATE_ALWAYS) != FR_OK) return false;
    bool ok = f_write(&f, text, n, &put) == FR_OK && put == (UINT)n;
    return f_close(&f) == FR_OK && ok;
}

// ---------------------------------------------------------------- tapes, as tape.c's files

static int t_read(void *buf, int n) { UINT got = 0; f_read(&tape_fil, buf, n, &got); return got; }
static int t_write(const void *buf, int n) { UINT put = 0; f_write(&tape_fil, buf, n, &put); return put; }
static bool t_seek(uint32_t pos) { return f_lseek(&tape_fil, pos) == FR_OK; }
static void t_close(void) { f_close(&tape_fil); }

bool storage_open_tape(const char *name, bool write, tape_file *f) {
    char path[80];
    snprintf(path, sizeof path, "/COMP80/TAPES/%s", name);
    if (!mounted || f_open(&tape_fil, path, write ? FA_WRITE | FA_CREATE_ALWAYS : FA_READ) != FR_OK) return false;
    *f = (tape_file){t_read, t_write, t_seek, t_close};
    return true;
}

void storage_new_tape_name(char out[NAME_LEN]) {
    for (int i = 1; i < 1000; i++) {
        char path[80];
        snprintf(out, NAME_LEN, "TAPE%02d.WAV", i);
        snprintf(path, sizeof path, "/COMP80/TAPES/%s", out);
        if (f_stat(path, NULL) != FR_OK) return;
    }
}
