// Run a COMP80 session on the host with the firmware's own machine code, for
// testing it against the web emulator (web/tools/session.js) and MAME.
//
//   ./session <rom file> <steps file> [32k] [clock=N] [tape=file.wav] [record=file.wav]
//
// The steps file is the format of lisp/tests/*.txt: each line is typed
// (\r = Return, \b = Backspace), "#wait <s>" waits, "#screen" prints
// the screen, "#ready" waits for the cursor.  NOWAIT=1 types without waiting
// for FORTH's or LISP's cursor, as session.js does.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../src/comp80.h"
#include "../src/tape.h"

static FILE *tf;
static int t_read(void *b, int n) { return (int)fread(b, 1, n, tf); }
static int t_write(const void *b, int n) { return (int)fwrite(b, 1, n, tf); }
static bool t_seek(uint32_t p) { return fseek(tf, p, SEEK_SET) == 0; }
static void t_close(void) { fclose(tf); tf = NULL; }
static const tape_file TF = {t_read, t_write, t_seek, t_close};

static double sec(void) { return (double)comp80_cycles / comp80_cfg.clock; }
static void step(double s) { comp80_run((uint32_t)(s * comp80_cfg.clock)); tape_poll(comp80_cycles); }

static void screen(void) {
    char line[65];
    printf("+%s+\n", "----------------------------------------------------------------");
    for (int r = 0; r < 32; r++) { comp80_screen_line(r, line); printf("|%s|\n", line); }
    printf("+%s+\n", "----------------------------------------------------------------");
}

// FORTH or LISP waiting for a line: its cursor (1F) is showing and the CPU is
// waiting for a key
static bool waiting_line(int curs) {
    return curs >= 0 && comp80_mem[comp80_mem[curs] | comp80_mem[curs + 1] << 8] == 0x1f && comp80_waiting_for_key();
}

static void type(const char *text) {
    for (const char *p = text; *p; p++) {
        double t0 = sec();
        while (!comp80_waiting_for_key() && sec() - t0 < 0.5) step(0.002);
        while (!comp80_key((unsigned char)*p)) {
            step(0.005);
            if (sec() - t0 > 600) { fprintf(stderr, "stuck typing %s\n", text); exit(1); }
        }
        step(0.02);
    }
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: session rom steps [32k] [clock=N] [tape=f] [record=f]\n"); return 2; }
    comp80_config cfg = {4000000, false, false};      // the web emulator's and MAME's clock, to compare
    const char *tape = NULL, *record = NULL;
    for (int i = 3; i < argc; i++) {
        if (!strcmp(argv[i], "32k")) cfg.expansion = true;
        else if (!strncmp(argv[i], "clock=", 6)) cfg.clock = atoi(argv[i] + 6);
        else if (!strncmp(argv[i], "tape=", 5)) tape = argv[i] + 5;
        else if (!strncmp(argv[i], "record=", 7)) record = argv[i] + 7;
    }
    const char *base = strrchr(argv[1], '/') ? strrchr(argv[1], '/') + 1 : argv[1];
    cfg.backspace_is_rs = strstr(base, "forth") || strstr(base, "lisp");
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    uint8_t rom[4096];
    int n = (int)fread(rom, 1, sizeof rom, f);
    fclose(f);
    comp80_power_on(rom, n, &cfg);
    // LOAD=file@addr: put a file into memory first, as c80.sh does
    const char *load = getenv("LOAD");
    if (load) {
        char name[512];
        unsigned addr = 0;
        const char *at = strchr(load, '@');
        snprintf(name, sizeof name, "%.*s", (int)(at - load), load);
        sscanf(at + 1, "%x", &addr);
        FILE *c = fopen(name, "rb");
        if (c) { fread(comp80_mem + addr, 1, 0x8000 - addr, c); fclose(c); }
    }
    if (tape) {
        tf = fopen(tape, "rb");
        if (!tf || !tape_play(&TF, comp80_cycles)) { fprintf(stderr, "can't play %s\n", tape); return 1; }
    }
    if (record) {
        tf = fopen(record, "wb+");
        tape_record(&TF, comp80_cycles);
    }
    bool nowait = getenv("NOWAIT") != NULL;
    // FORTH and LISP keep the cursor's address here; the cursor is 1F
    int curs = strstr(base, "forth") ? 0x1da0 : strstr(base, "lisp") ? 0x0c12 : -1;

    step(1.5);
    FILE *s = fopen(argv[2], "r");
    if (!s) { perror(argv[2]); return 1; }
    char line[4096];
    while (fgets(line, sizeof line, s)) {
        line[strcspn(line, "\n")] = 0;
        size_t len = strlen(line);
        if (!len) continue;
        if (!strncmp(line, "#wait", 5)) { step(atof(line + 5)); continue; }
        if (!strcmp(line, "#screen")) { screen(); continue; }
        if (!strncmp(line, "#snap", 5) || !strncmp(line, "#dump", 5)) continue;
        bool ready = !strcmp(line, "#ready");
        if ((len >= 2 && !strcmp(line + len - 2, "\\r") && !nowait) || ready) {
            double t0 = sec();
            while (!waiting_line(curs)) {
                step(0.01);
                if (sec() - t0 > 900) { fprintf(stderr, "never ready for %s\n", line); return 1; }
            }
            if (sec() - t0 > 1) printf("--- busy %.1fs\n", sec() - t0);
            step(0.2);
        }
        if (ready) continue;
        char text[4096];
        int k = 0;
        for (char *p = line; *p; p++) {
            if (p[0] == '\\' && p[1] == 'r') { text[k++] = '\r'; p++; }
            else if (p[0] == '\\' && p[1] == 'b') { text[k++] = 8; p++; }
            else text[k++] = *p;
        }
        text[k] = 0;
        type(text);
        step(0.3);
    }
    if (tape_state() != TAPE_STOPPED) tape_stop(comp80_cycles);
    // SCREEN=file: the 2 KB of screen memory, for hardware_v3/sim/video_tb.v
    const char *dump = getenv("SCREEN");
    if (dump) {
        FILE *o = fopen(dump, "w");
        for (int i = 0; i < 2048; i++) fprintf(o, "%02x\n", comp80_mem[COMP80_SCREEN + i]);
        fclose(o);
    }
    // CHECK=file@addr: compare memory from addr with a file (did a tape load?)
    const char *check = getenv("CHECK");
    if (check) {
        char name[512];
        unsigned addr = 0;
        const char *at = strchr(check, '@');
        snprintf(name, sizeof name, "%.*s", (int)(at - check), check);
        sscanf(at + 1, "%x", &addr);
        FILE *c = fopen(name, "rb");
        uint8_t want[0x8000];
        int n = c ? (int)fread(want, 1, sizeof want, c) : 0, bad = 0;
        if (c) fclose(c);
        for (int i = 0; i < n; i++) bad += comp80_mem[addr + i] != want[i];
        printf("CHECK %s: %d bytes, %d differ\n", name, n, bad);
    }
    return 0;
}
