// Boot the system controller's firmware with the machine (sim_soc.v): prints
// what it sends on the serial port, then the COMP80's screen.
#include <cstdio>
#include <string>

#include "Vsim_soc.h"
#include "verilated.h"

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const double SYS_HZ = 12e6, BAUD = 115200;
    Vsim_soc *m = new Vsim_soc;
    uint8_t screen[2048];
    for (auto &c : screen) c = 0x20;
    int bit_clocks = (int)(SYS_HZ / BAUD), rx_count = -1, rx_bits = 0, rx_byte = 0;
    std::string serial;
    m->rst = 1;
    uint64_t total = (uint64_t)(SYS_HZ * (argc > 1 ? atof(argv[1]) : 3.0));
    for (uint64_t t = 0; t < total; t++) {
        m->clk = 0; m->eval(); m->clk = 1; m->eval();
        if (t == 20) m->rst = 0;
        if (m->scr_we) screen[m->scr_addr] = m->scr_data;
        // a UART receiver on uart_tx
        if (rx_count < 0) { if (!m->uart_tx) { rx_count = bit_clocks * 3 / 2; rx_bits = 0; rx_byte = 0; } }
        else if (--rx_count == 0) {
            if (rx_bits < 8) { rx_byte |= m->uart_tx << rx_bits; rx_bits++; rx_count = bit_clocks; }
            else { serial += (char)rx_byte; rx_count = -1; }
        }
    }
    printf("serial: %s", serial.c_str());
    printf("+%s+\n", std::string(64, '-').c_str());
    for (int r = 0; r < 32; r++) {
        char line[65];
        for (int c = 0; c < 64; c++) { uint8_t v = screen[r * 64 + c], ch = v & 0x3f; line[c] = v & 0x40 ? '#' : (ch < 0x20 ? ch + 64 : ch); }
        line[64] = 0;
        printf("|%s|\n", line);
    }
    printf("+%s+\nhalted: %d\n", std::string(64, '-').c_str(), m->halted);
    delete m;
    return 0;
}
