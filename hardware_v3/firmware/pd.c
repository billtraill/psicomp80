// USB Power Delivery for DisplayPort over USB-C: the board's side of the
// conversation with a USB-C monitor, through the FUSB302B PD PHY (U6) on a
// bit-banged I2C bus.
//
// The board is the source and the host (DFP): it puts Rp on both CC pins,
// finds the monitor's Rd (which also says which way up the plug is), switches
// VBUS on, offers 5 V at 0.5 A, then asks for DisplayPort alternate mode:
// Discover Identity, Discover SVIDs, Discover Modes (SVID FF01), Enter Mode,
// DP Status Update and DP Configure. The monitor's hot-plug state, from its
// Status Update reply and its Attention messages, goes to the DisplayPort
// logic, with the lane map for the plug's orientation. The FUSB302 answers
// and checks GoodCRC itself, and retries.
//
// Register and token values from the FUSB302B data sheet; message formats
// from the USB PD 2.0 specification and VESA's DisplayPort Alt Mode standard.
#include "pd.h"

#include <stdio.h>
#include <string.h>

#include "hw.h"

#define FUSB 0x22               // FUSB302BMPX's I2C address (B01: 0x23, B10: 0x24, B11: 0x25)

enum {
    REG_SWITCHES0 = 0x02, REG_SWITCHES1 = 0x03, REG_MEASURE = 0x04, REG_CONTROL0 = 0x06,
    REG_CONTROL1 = 0x07, REG_CONTROL2 = 0x08, REG_CONTROL3 = 0x09, REG_MASK = 0x0a, REG_POWER = 0x0b,
    REG_RESET = 0x0c, REG_MASKA = 0x0e, REG_MASKB = 0x0f, REG_STATUS0 = 0x40, REG_STATUS1 = 0x41,
    REG_INTERRUPT = 0x42, REG_FIFOS = 0x43, REG_INTERRUPTA = 0x3e, REG_INTERRUPTB = 0x3f,
};
// SWITCHES0
#define PU_EN2 0x80
#define PU_EN1 0x40
#define MEAS_CC2 0x08
#define MEAS_CC1 0x04
// SWITCHES1: source, DFP, PD 2.0, automatic GoodCRC, transmit on CC1/CC2
#define SW1_SRC_DFP (0x80 | 0x10 | 0x20 | 0x04)
// STATUS0 / STATUS1
#define COMP 0x20
#define RX_EMPTY 0x20
// TX FIFO tokens
#define TX_ON 0xa1
#define SOP1 0x12
#define SOP2 0x13
#define PACKSYM 0x80
#define JAM_CRC 0xff
#define EOP 0x14
#define TX_OFF 0xfe

// PD messages
enum { CTRL_GOODCRC = 1, CTRL_ACCEPT = 3, CTRL_REJECT = 4, CTRL_PS_RDY = 6, CTRL_GET_SOURCE_CAP = 7,
       CTRL_SOFT_RESET = 13 };
enum { DATA_SOURCE_CAP = 1, DATA_REQUEST = 2, DATA_VENDOR = 15 };
// structured VDM commands
enum { VDM_DISCOVER_IDENTITY = 1, VDM_DISCOVER_SVIDS = 2, VDM_DISCOVER_MODES = 3, VDM_ENTER_MODE = 4,
       VDM_ATTENTION = 6, VDM_DP_STATUS = 0x10, VDM_DP_CONFIGURE = 0x11 };
#define SVID_PD 0xff00
#define SVID_DP 0xff01

// ------------------------------------------------------------ I2C, bit-banged through PD_IO
#define PD_IO REG(0x2000003c)
static uint32_t pd_out;             // bit 0 SCL low, 1 SDA low, 2 VBUS on

static void io(int scl_low, int sda_low) {
    pd_out = (pd_out & 4) | (sda_low ? 2 : 0) | (scl_low ? 1 : 0);
    PD_IO = pd_out;
    for (volatile int i = 0; i < 60; i++) ;      // ~5 us at 50 MHz: about 100 kHz
}
static int sda_in(void) { return PD_IO >> 1 & 1; }
static void start(void) { io(0, 0); io(0, 1); io(1, 1); }
static void stop(void) { io(1, 1); io(0, 1); io(0, 0); }
static int put8(uint8_t v) {
    for (int i = 7; i >= 0; i--) { int b = v >> i & 1; io(1, !b); io(0, !b); io(1, !b); }
    io(1, 0); io(0, 0);
    int nak = sda_in();
    io(1, 0);
    return !nak;
}
static uint8_t get8(int ack) {
    uint8_t v = 0;
    for (int i = 0; i < 8; i++) { io(1, 0); io(0, 0); v = v << 1 | sda_in(); io(1, 0); }
    io(1, ack); io(0, ack); io(1, ack);
    return v;
}
static int wr(uint8_t reg, const uint8_t *d, int n) {
    start();
    int ok = put8(FUSB << 1) && put8(reg);
    for (int i = 0; ok && i < n; i++) ok = put8(d[i]);
    stop();
    return ok;
}
static int rd(uint8_t reg, uint8_t *d, int n) {
    start();
    int ok = put8(FUSB << 1) && put8(reg);
    start();
    ok = ok && put8(FUSB << 1 | 1);
    for (int i = 0; ok && i < n; i++) d[i] = get8(i < n - 1);
    stop();
    return ok;
}
static void set(uint8_t reg, uint8_t v) { wr(reg, &v, 1); }
static uint8_t get(uint8_t reg) { uint8_t v = 0; rd(reg, &v, 1); return v; }

// ------------------------------------------------------------ DisplayPort settings
#define DP_CTRL REG(0x20000038)     // bit 0 hot-plug, bit 1 AUX swapped, bits 15-8 lane map
// Which DisplayPort lane each of J7's pairs carries (2 bits per pair: TX1, RX1,
// TX2, RX2), for pin assignments C and E. VESA's DFP_D table: plug one way up,
// ML0 on RX2, ML1 on TX2, ML2 on TX1, ML3 on RX1; the other way up, RX1 and
// TX1 take ML0 and ML1. Check this against the standard at bring-up; the logic
// takes any map.
#define LANES_CC1 (0 << 6 | 1 << 4 | 3 << 2 | 2)
#define LANES_CC2 (3 << 6 | 2 << 4 | 0 << 2 | 1)

// ------------------------------------------------------------ the state machine
static int state = PD_DETACHED, cc, msg_id, hpd, pin_assign;
static uint32_t timer, last_poll;
static const char *const NAMES[] = {"detached", "powering", "contract", "identity", "svids", "modes",
                                    "entering", "status", "configuring", "dp"};

const char *pd_state_name(void) { return NAMES[state]; }
int pd_hpd(void) { return hpd; }

static void dp_update(void) {
    DP_CTRL = (cc == 2 ? LANES_CC2 : LANES_CC1) << 8 | (cc == 2 ? 2 : 0) | (hpd ? 1 : 0);
}

static void goto_state(int s) { state = s; timer = usec(); }

// Send a message: header and data objects, little-endian, between SOP and EOP.
static void send(int type, int ndo, const uint32_t *obj) {
    uint16_t h = type | (ndo << 12) | (msg_id << 9) | 0x0100 /* source */ | 0x0020 /* DFP */ | 0x0040 /* PD 2.0 */;
    msg_id = (msg_id + 1) & 7;
    uint8_t b[40];
    int n = 0;
    b[n++] = SOP1; b[n++] = SOP1; b[n++] = SOP1; b[n++] = SOP2;
    b[n++] = PACKSYM | (2 + 4 * ndo);
    b[n++] = h; b[n++] = h >> 8;
    for (int i = 0; i < ndo; i++) { b[n++] = obj[i]; b[n++] = obj[i] >> 8; b[n++] = obj[i] >> 16; b[n++] = obj[i] >> 24; }
    b[n++] = JAM_CRC; b[n++] = EOP; b[n++] = TX_OFF; b[n++] = TX_ON;
    set(REG_CONTROL0, 0x44);         // flush the TX FIFO
    wr(REG_FIFOS, b, n);
}

static void vdm(int cmd, uint16_t svid, int pos, int ndo, const uint32_t *extra) {
    uint32_t o[3];
    o[0] = (uint32_t)svid << 16 | 0x8000 /* structured */ | (pos << 8) | cmd;
    for (int i = 0; i < ndo; i++) o[1 + i] = extra[i];
    send(DATA_VENDOR, 1 + ndo, o);
}

// A received message, if there is one. Returns its type (data messages + 0x10), or 0.
static uint32_t rx_obj[7];
static int rx_ndo;
static int receive(void) {
    if (get(REG_STATUS1) & RX_EMPTY) return 0;
    uint8_t t, h[2];
    rd(REG_FIFOS, &t, 1);
    rd(REG_FIFOS, h, 2);
    uint16_t hdr = h[0] | h[1] << 8;
    rx_ndo = hdr >> 12 & 7;
    for (int i = 0; i < rx_ndo; i++) {
        uint8_t o[4];
        rd(REG_FIFOS, o, 4);
        rx_obj[i] = o[0] | o[1] << 8 | o[2] << 16 | (uint32_t)o[3] << 24;
    }
    uint8_t crc[4];
    rd(REG_FIFOS, crc, 4);
    if ((t & 0xe0) != 0xe0) return 0;    // only SOP messages (not SOP' or SOP'')
    int type = hdr & 0x1f;
    return rx_ndo ? 0x10 | type : type;
}

static void detach(void) {
    pd_out &= ~4;                       // VBUS off
    PD_IO = pd_out;
    hpd = 0; cc = 0; msg_id = 0;
    dp_update();
    set(REG_SWITCHES1, 0x20);
    set(REG_SWITCHES0, PU_EN1 | PU_EN2);
    goto_state(PD_DETACHED);
}

void pd_init(void) {
    PD_IO = pd_out = 0;
    set(REG_RESET, 0x01);               // reset the chip
    set(REG_POWER, 0x0f);               // everything on
    set(REG_CONTROL0, 0x04);            // Rp at default USB current; interrupts unmasked
    set(REG_CONTROL3, 0x07);            // retry 3 times
    set(REG_MASK, 0x00);
    set(REG_MASKA, 0x00);
    set(REG_MASKB, 0x00);
    detach();
    printf("USB-PD: FUSB302 id %02x\n", get(0x01));
}

// Is the monitor's Rd on this CC pin? (Rd pulls Rp's voltage between 0.2 and 1.6 V.)
static int rd_on(int pin) {
    set(REG_SWITCHES0, PU_EN1 | PU_EN2 | (pin == 1 ? MEAS_CC1 : MEAS_CC2));
    set(REG_MEASURE, 0x26);             // 1.6 V
    delay_ms(1);
    int below_open = !(get(REG_STATUS0) & COMP);
    set(REG_MEASURE, 0x05);             // 0.2 V
    delay_ms(1);
    int above_ra = get(REG_STATUS0) & COMP;
    return below_open && above_ra;
}

void pd_poll(int busy) {
    uint32_t now = usec();
    if (state == PD_DETACHED) {
        if (busy || now - last_poll < 300000) return;     // look for a monitor three times a second
        last_poll = now;
        cc = rd_on(1) ? 1 : rd_on(2) ? 2 : 0;
        if (!cc) return;
        printf("USB-PD: monitor on CC%d\n", cc);
        pd_out |= 4;                    // VBUS on
        PD_IO = pd_out;
        set(REG_SWITCHES0, PU_EN1 | PU_EN2 | (cc == 1 ? MEAS_CC1 : MEAS_CC2));
        set(REG_SWITCHES1, SW1_SRC_DFP | (cc == 1 ? 0x01 : 0x02));
        set(REG_CONTROL1, 0x04);        // flush the RX FIFO
        goto_state(PD_POWERING);
        return;
    }
    // still there? (the monitor's Rd gone means it was unplugged)
    if (now - last_poll > 500000 && !busy) {
        last_poll = now;
        if (!rd_on(cc)) { printf("USB-PD: monitor gone\n"); detach(); return; }
        set(REG_SWITCHES0, PU_EN1 | PU_EN2 | (cc == 1 ? MEAS_CC1 : MEAS_CC2));
    }
    // messages come in when the FUSB302 says so: INT_N low until its
    // interrupt registers are read; then empty the RX FIFO
    static int pending;
    if (!(PD_IO & 4)) {
        get(REG_INTERRUPT); get(REG_INTERRUPTA); get(REG_INTERRUPTB);
        pending = 1;
    }
    int msg = 0;
    if (pending) {
        msg = receive();
        if (!msg && (get(REG_STATUS1) & RX_EMPTY)) pending = 0;
    }
    uint32_t pdo = 100u << 10 | 50;     // fixed supply: 5 V (100 x 50 mV), 0.5 A (50 x 10 mA)
    switch (state) {
    case PD_POWERING:                   // VBUS has settled: offer it, every 150 ms until asked
        if (msg == (0x10 | DATA_REQUEST)) {
            send(CTRL_ACCEPT, 0, NULL);
            delay_ms(1);
            send(CTRL_PS_RDY, 0, NULL);
            goto_state(PD_CONTRACT);
        } else if (now - timer > 150000) {
            send(DATA_SOURCE_CAP, 1, &pdo);
            timer = now;
        }
        break;
    case PD_CONTRACT:
        if (now - timer > 50000) { vdm(VDM_DISCOVER_IDENTITY, SVID_PD, 0, 0, NULL); goto_state(PD_IDENTITY); }
        break;
    case PD_IDENTITY:
        if (msg == (0x10 | DATA_VENDOR) && (rx_obj[0] & 0x1f) == VDM_DISCOVER_IDENTITY) {
            vdm(VDM_DISCOVER_SVIDS, SVID_PD, 0, 0, NULL);
            goto_state(PD_SVIDS);
        }
        break;
    case PD_SVIDS:
        if (msg == (0x10 | DATA_VENDOR) && (rx_obj[0] & 0x1f) == VDM_DISCOVER_SVIDS) {
            int dp = 0;
            for (int i = 1; i < rx_ndo; i++)
                dp |= (rx_obj[i] >> 16) == SVID_DP || (rx_obj[i] & 0xffff) == SVID_DP;
            if (!dp) { printf("USB-PD: no DisplayPort mode\n"); hpd = 0; goto_state(PD_DP); break; }
            vdm(VDM_DISCOVER_MODES, SVID_DP, 0, 0, NULL);
            goto_state(PD_MODES);
        }
        break;
    case PD_MODES:
        if (msg == (0x10 | DATA_VENDOR) && (rx_obj[0] & 0x1f) == VDM_DISCOVER_MODES && rx_ndo > 1) {
            // the monitor's DisplayPort capabilities: its UFP_D pin assignments
            // (bits 23-16 for a receptacle, 15-8 for a captive cable's plug)
            uint32_t caps = rx_obj[1];
            int pins = (caps & 0x40) ? (caps >> 8 & 0xff) : (caps >> 16 & 0xff);
            if (!pins) pins = caps >> 8 & 0xff;
            pin_assign = (pins & 0x04) ? 0x04 : (pins & 0x10) ? 0x10 : (pins & 0x08) ? 0x08 : 0x04;   // C, E, D
            vdm(VDM_ENTER_MODE, SVID_DP, 1, 0, NULL);
            goto_state(PD_ENTERING);
        }
        break;
    case PD_ENTERING:
        if (msg == (0x10 | DATA_VENDOR) && (rx_obj[0] & 0x1f) == VDM_ENTER_MODE) {
            uint32_t status = 0x1;      // DFP_D connected
            vdm(VDM_DP_STATUS, SVID_DP, 1, 1, &status);
            goto_state(PD_STATUS);
        }
        break;
    case PD_STATUS:
        if (msg == (0x10 | DATA_VENDOR) && (rx_obj[0] & 0x1f) == VDM_DP_STATUS) {
            hpd = rx_ndo > 1 && (rx_obj[1] >> 7 & 1);
            // configure the monitor as UFP_D, DisplayPort signalling, the pin assignment chosen
            uint32_t config = 0x2 | 0x1 << 2 | (uint32_t)pin_assign << 8;
            vdm(VDM_DP_CONFIGURE, SVID_DP, 1, 1, &config);
            goto_state(PD_CONFIGURING);
        }
        break;
    case PD_CONFIGURING:
        if (msg == (0x10 | DATA_VENDOR) && (rx_obj[0] & 0x1f) == VDM_DP_CONFIGURE) {
            dp_update();
            printf("USB-PD: DisplayPort mode, pin assignment %c, hot-plug %d\n",
                   pin_assign == 0x04 ? 'C' : pin_assign == 0x08 ? 'D' : 'E', hpd);
            goto_state(PD_DP);
        }
        break;
    case PD_DP:
        if (msg == (0x10 | DATA_VENDOR) && (rx_obj[0] & 0x1f) == VDM_ATTENTION && rx_ndo > 1) {
            hpd = rx_obj[1] >> 7 & 1;
            dp_update();
        }
        break;
    }
    if (msg == CTRL_SOFT_RESET) { msg_id = 0; send(CTRL_ACCEPT, 0, NULL); goto_state(PD_POWERING); }
    if (msg == CTRL_GET_SOURCE_CAP) send(DATA_SOURCE_CAP, 1, &pdo);
    // no answer in a second: start again
    if (state > PD_CONTRACT && state < PD_DP && now - timer > 1000000) { printf("USB-PD: no answer\n"); detach(); }
}
