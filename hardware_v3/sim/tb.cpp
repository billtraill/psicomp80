// Verilator testbench for comp80_machine.v: runs a COMP80 session on the logic,
// standing in for the soft processor the way soc.v's firmware does (loading
// the ROM through the host port, the MM57109 model from the v2 firmware, the
// keyboard latch), and prints the screens in the same form as
// hardware_v2/firmware/host/session and web/tools/session.js, to compare.
//
//   ./obj/Vcomp80_machine <rom> <steps> [clock=N] [32k]
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "Vcomp80_machine.h"
#include "Vcomp80_machine___024root.h"
#include "verilated.h"

#include "mm57109.h"     // mm57109.c is built as C++ here, alongside this file

static Vcomp80_machine *m;
static uint32_t clock_hz = 4000000;
static const double SYS_HZ = 12e6;      // the simulation's system clock (SYS_HZ in the Makefile)
static bool irq_pulse;

uint32_t mm_clock;
uint64_t mm_now(void) { return m->cycles; }
void mm_irq(void) { irq_pulse = true; }

static uint8_t mem(uint16_t a) { return m->rootp->comp80_machine__DOT__mem[a]; }
static uint8_t screen[2048];

// one system clock, with the soft processor's side of the bridge
static void tick() {
    m->clk = 0; m->eval();
    m->clk = 1; m->eval();
    if (m->scr_we) screen[m->scr_addr] = m->scr_data;
    m->mm_done = 0; m->mm_irq = 0; m->key_strobe = 0; m->h_we = 0;
    if (m->mm_cmd_new) {                         // an OUT 60 is waiting
        mm_write(m->mm_cmd);
        m->mm_status = mm_read();
        m->mm_done = 1;
    }
    if (m->cycles >= mm_due) mm_run(m->cycles);
    m->mm_status = mm_read();
    if (irq_pulse) { m->mm_irq = 1; irq_pulse = false; }
}

static double sec() { return (double)m->cycles / clock_hz; }
static void step(double s) {
    uint64_t end = m->cycles + (uint64_t)(s * clock_hz);
    while (m->cycles < end) tick();
}

static uint64_t key_time;
static bool waiting_for_key() { return m->halted && !m->key_full; }
// comp80.c's comp80_key, against the latch in the logic
static bool key(int c) {
    if (m->key_full && m->cycles - key_time < clock_hz / 20) return false;
    m->key_code = c; m->key_strobe = 1;
    tick();
    key_time = m->cycles;
    return true;
}
static bool rs_rubout;

static void type(const char *text) {
    for (const char *p = text; *p; p++) {
        double t0 = sec();
        while (!waiting_for_key() && sec() - t0 < 0.5) step(0.002);
        int c = (unsigned char)*p;
        if (c == 8 && rs_rubout) c = 0x1e;
        while (!key(c)) { step(0.005); if (sec() - t0 > 600) { fprintf(stderr, "stuck typing\n"); exit(1); } }
        step(0.02);
    }
}

static void print_screen() {
    printf("+%s+\n", std::string(64, '-').c_str());
    for (int r = 0; r < 32; r++) {
        char line[65];
        for (int c = 0; c < 64; c++) {
            uint8_t v = screen[r * 64 + c], ch = v & 0x3f;
            line[c] = v & 0x40 ? '#' : (ch < 0x20 ? ch + 64 : ch);
        }
        line[64] = 0;
        printf("|%s|\n", line);
    }
    printf("+%s+\n", std::string(64, '-').c_str());
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: tb rom steps [clock=N] [32k]\n"); return 2; }
    bool exp = false;
    for (int i = 3; i < argc; i++) {
        if (!strncmp(argv[i], "clock=", 6)) clock_hz = atoi(argv[i] + 6);
        if (!strcmp(argv[i], "32k")) exp = true;
    }
    mm_clock = clock_hz;
    const char *base = strrchr(argv[1], '/') ? strrchr(argv[1], '/') + 1 : argv[1];
    rs_rubout = strstr(base, "forth") || strstr(base, "lisp");
    int curs = strstr(base, "forth") ? 0x1da0 : strstr(base, "lisp") ? 0x0c12 : -1;

    m = new Vcomp80_machine;
    m->rst = 1; m->clk4 = clock_hz == 4000000; m->expansion = exp;
    m->tape_in = 1; m->mm_status = 0x40;
    for (int i = 0; i < 4; i++) tick();
    // power on as comp80_power_on does: memory cleared, the ROM, a blank screen
    uint8_t rom[4096];
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    int n = fread(rom, 1, sizeof rom, f);
    fclose(f);
    for (int a = 0; a < 0x10000; a++) {
        m->h_addr = a; m->h_we = 1;
        m->h_wdata = a < 0x0c00 ? (a < n ? rom[a] : 0xff) : (a >= 0x8000 && a < 0x8800) ? 0x20 : 0;
        m->clk = 0; m->eval(); m->clk = 1; m->eval();
    }
    m->h_we = 0;
    memset(screen, 0x20, sizeof screen);
    mm_reset();
    m->rst = 0;

    auto waiting_line = [&]() {
        return curs >= 0 && mem(mem(curs) | mem(curs + 1) << 8) == 0x1f && waiting_for_key();
    };
    bool nowait = getenv("NOWAIT") != nullptr;
    step(1.5);
    FILE *s = fopen(argv[2], "r");
    if (!s) { perror(argv[2]); return 1; }
    char line[4096];
    while (fgets(line, sizeof line, s)) {
        line[strcspn(line, "\n")] = 0;
        size_t len = strlen(line);
        if (!len) continue;
        if (!strncmp(line, "#wait", 5)) { step(atof(line + 5)); continue; }
        if (!strcmp(line, "#screen")) { print_screen(); continue; }
        if (!strncmp(line, "#snap", 5) || !strncmp(line, "#dump", 5)) continue;
        bool ready = !strcmp(line, "#ready");
        if ((len >= 2 && !strcmp(line + len - 2, "\\r") && !nowait) || ready) {
            double t0 = sec();
            while (!waiting_line()) {
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
    delete m;
    return 0;
}
