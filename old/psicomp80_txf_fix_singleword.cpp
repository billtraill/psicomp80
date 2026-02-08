// license:BSD-3-Clause
// copyright-holders:ChatGPT
/***************************************************************************

  PSI COMP80 (Wireless World construction project, 1979-1980)
  Work-in-progress driver

  Updates in this build:
    - Display: render a 32-column x 32-row *visible* character screen (192x320)
      using 6x10 character cells (5x8 font + spacer + 2 blank scanlines).
      (Video RAM is still 2 KiB at 8000-87FF mirrored to FFFF; only top 1 KiB
       is displayed for now.)
    - Character generation model: 2513-style 64x8x5 generator + optional graphics
      set selected by VRAM bit 6.
    - Practical code mapping for COMP80 text:
        * Many 2513-based designs store letters as 1..26 (A..Z) in 6-bit RAM,
          keeping bit 6 clear so the ASCII/graphics select line is not tripped.
        * This driver therefore maps:
              code 0x00 -> ' '
              code 0x01..0x1A -> 'A'..'Z'
              code 0x20..0x3F -> treat as ASCII 0x20..0x3F (space/punct/digits)
          Anything else falls back to space.
      This mapping is intended to turn the typical monitor prompt into readable
      text (e.g. "READY>") instead of "@2%!$9&".

    - Placeholder table for 64 graphics characters (to be filled in later)
    - Keyboard strobe generates NMI (wakes DI/HALT loops)
    - MM57109 "data ready" interrupt modelled as IRQ0 latch

***************************************************************************/

#include "emu.h"

#include "cpu/z80/z80.h"
#include "machine/keyboard.h"
#include "screen.h"
#include "emupal.h"

#include <array>
#include <vector>
#include <string>
#include <cmath>
#include <cstdlib>
// ---------------------------------------------------------------------------
// MM57109 tracing
//
// MAME uses logmacro.h. Define VERBOSE before including it to avoid redefinition
// warnings promoted to errors (-Werror,-Wmacro-redefined).
// ---------------------------------------------------------------------------
#define LOG_MM57109   (1U << 0)   // MM57109 byte stream + handshake
#define LOG_MM_STATUS (1U << 1)   // port $03 reads (noisy)
#define LOG_MM_ACK    (1U << 2)   // $3F ACK handling

#define VERBOSE (LOG_MM57109 | LOG_MM_ACK)
// #define VERBOSE (LOG_MM57109 | LOG_MM_ACK | LOG_MM_STATUS)

// ---------------------------------------------------------------------------
// MM57109 opcode → mnemonic helpers (derived from MM57109_cmds_data_with_regs_and_burp.md)
// These are for LOGGING ONLY. They do not change emulation behaviour.
// Note: BURP may use some opcode bytes as interface control/separators.
// ---------------------------------------------------------------------------
static const char *mm57109_opcode_name(u8 op)
{
	switch (op)
	{
		case 0x00: return "0";
		case 0x01: return "1";
		case 0x02: return "2";
		case 0x03: return "3";
		case 0x04: return "4";
		case 0x05: return "5";
		case 0x06: return "6";
		case 0x07: return "7";
		case 0x08: return "8";
		case 0x09: return "9";
		case 0x0A: return "DP";
		case 0x0B: return "EE";
		case 0x0C: return "CS";
		case 0x0D: return "PI";
		case 0x0E: return "AIN";
		case 0x0F: return "HALT";
		case 0x10: return "TJC*";
		case 0x11: return "TX=0*";
		case 0x12: return "TXLTO*";
		case 0x13: return "TXF*";
		case 0x14: return "TERR*";
		case 0x15: return "JMP*";
		case 0x16: return "OUT*";
		case 0x17: return "IN*";
		case 0x18: return "SMDC";
		case 0x19: return "IBNZ*";
		case 0x1A: return "DBNZ*";
		case 0x1B: return "XEM";
		case 0x1C: return "MS";
		case 0x1D: return "MR";
		case 0x1E: return "LSH";
		case 0x1F: return "RSH";
		case 0x20: return "INV*/SPACE?";
		case 0x21: return "EN";
		case 0x22: return "TOGM";
		case 0x23: return "ROLL";
		case 0x24: return "SIN";
		case 0x25: return "COS";
		case 0x26: return "TAN";
		case 0x27: return "SF1";
		case 0x28: return "PF1";
		case 0x29: return "SF2";
		case 0x2A: return "PF2";
		case 0x2B: return "ECLR";
		case 0x2C: return "RTD";
		case 0x2D: return "DTR";
		case 0x2E: return "POP";
		case 0x2F: return "MCLR";
		case 0x30: return "XEY";
		case 0x31: return "EX";
		case 0x32: return "10X";
		case 0x33: return "SQ";
		case 0x34: return "SQRT";
		case 0x35: return "LN";
		case 0x36: return "LOG";
		case 0x37: return "1/X";
		case 0x38: return "YX";
		case 0x39: return "+";
		case 0x3A: return "-";
		case 0x3B: return "x";
		case 0x3C: return "/";
		case 0x3D: return "PRW1";
		case 0x3E: return "PRW2";
		case 0x3F: return "NOP/ACK";
		default: return "UNK";
	}
}

static const char *mm57109_inv_second_name(u8 op)
{
	switch (op)
	{
		case 0x24: return "SIN-1*";
		case 0x25: return "COS-1*";
		case 0x26: return "TAN-1*";
		case 0x39: return "M+*";
		case 0x3A: return "M-*";
		case 0x3B: return "MX*";
		case 0x3C: return "M/*";
		default: return "UNK";
	}
}


#include "logmacro.h"


namespace {

class psicomp80_state : public driver_device
{
public:
	psicomp80_state(const machine_config &mconfig, device_type type, const char *tag)
		: driver_device(mconfig, type, tag)
		, m_cpu(*this, "maincpu")
		, m_vram(*this, "vram")
		, m_keyboard(*this, "keyboard")
	{}

	void psicomp80(machine_config &config);
private:
	// -------- VDU geometry --------
	static constexpr int kCols  = 64;
	static constexpr int kCharW = 6;   // 5 pixels + 1 spacer
	static constexpr int kCharH = 10;  // 8 rows from generator + 2 blank

	// Visible text rows: 32 (as per your observation/expectation).
	// VRAM is 2 KiB, so this uses the first 32*32 = 1024 bytes.
	static constexpr int kRowsVisible = 32;

	static constexpr int kWidth  = kCols * kCharW;           // 192
	static constexpr int kHeight = kRowsVisible * kCharH;    // 320

	// devices/memory
	required_device<z80_device>              m_cpu;
	required_shared_ptr<u8>                  m_vram;
	required_device<generic_keyboard_device> m_keyboard;

	// ROM is mapped read-only (like real hardware)

	// keyboard latch returned by port 01h (ROM does IN then CPL)
	u8 m_key_latch = 0xff;

	// MM57109-ish "data ready" latch for port 03h (and IRQ0 generation)
	bool m_mm_ready = false;
	u8   m_mm_code  = 0x1f;
	bool m_mm_one_shot_clear = false;

	// --- MM57109 port $60 write / port $03 status modelling (BURP relies on this) ---
	bool m_mm_hs_rdy = false;      // handshake RDY (bit5) for $042E busy/ack loops
	bool m_mm_status_rdy = false;  // status RDY (bit5) for $058A wait loop
	bool m_mm_status_b6 = false;   // status bit6 ($40) returned by $058A
	u8   m_mm_latch = 0x00;        // phase-1 latched byte (bit7 clear)
	bool m_mm_expect_latch = true; // handshake phase tracker for $042E (ignore data bit7)
	bool m_mm_inv_pending = false; // last committed opcode was INV (0x20); next selects INV function
	std::vector<u8> m_mm_stream;   // committed byte stream (bit7 stripped)
	u64  m_mm_tx_seq = 0;          // transaction counter

	// --- MM57109 register/state model (WIP) ---
	// These fields model the MM57109 internal state at a coarse level so we can
	// progressively implement the instruction set that BURP uses.
	double m_mm_x = 0.0;  // X register (top of stack)
	double m_mm_y = 0.0;  // Y register
	double m_mm_z = 0.0;  // Z register
	double m_mm_t = 0.0;  // T register
	double m_mm_m = 0.0;  // Memory register M
	bool   m_mm_deg_mode = false; // angular mode (false=radians, true=degrees) - rough model
	u8     m_mm_mant_digits = 8;  // mantissa digit count (SMDC*)
	bool   m_mm_digit_entry = false; // currently collecting digits into X
	std::string m_mm_digit_buf;      // digit-entry buffer (ASCII, e.g. "-12.34E+5")
	bool   m_mm_two_word_pending = false;
	u8     m_mm_two_word_op = 0x00;
	bool   m_mm_error = false;

	// queue for IM1 nibble delivery (port $03 low nibble + IRQ0 pulses)
	std::vector<u8> m_mm_nibble_q;

	// -------- character generator tables --------
	// Each glyph: 8 rows, 5 bits per row (packed in bits 0..4).
	// Table is indexed as ASCII 0x20..0x5F mapped to 0..63.
	static const std::array<std::array<u8, 8>, 64> ascii_font_64x8x5;

	// Placeholder graphics font (fill later)
	static std::array<std::array<u8, 8>, 64> gfx_font_64x8x5;

	// maps
	void mem_map(address_map &map);
	void io_map(address_map &map);

	// I/O handlers
	u8 port01_r();
	u8 port03_r();
	void port60_w(u8 data);
	void mm57109_dump_stream(const char *tag, u8 cmd);

	// keyboard -> strobe (NMI) + MM data ready (IRQ0)
	void kbd_put(u8 data);
	// display
	u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect);

	// helpers
	static u8 ascii_to_mm_code(u8 data);
	void mm_set_data_ready(u8 code);
	// MM57109 model helpers
	void mm57109_reset();
	void mm57109_commit(u8 op);
	void mm57109_execute_single(u8 op);
	bool mm57109_is_two_word(u8 op) const;
	const char *mm57109_opcode_mn(u8 op) const;
	void mm57109_push(double v);
	double mm57109_pop();
	void mm57109_set_x(double v);
	void mm57109_queue_nibble(u8 nib);
	void mm57109_log_state(const char *reason);

	static u8 glyph_row(u8 vram_byte, int row); // returns 5-bit pattern

protected:
	virtual void machine_start() override;
	virtual void machine_reset() override;
};

// ------------------ Base ASCII font subset (0x20-0x5F) ------------------
static constexpr std::array<u8, 8> BLANK = {0,0,0,0,0,0,0,0};

const std::array<std::array<u8, 8>, 64> psicomp80_state::ascii_font_64x8x5 = {{
	/* 0x20 ' ' */ BLANK,
	/* 0x21 '!' */ {0x04,0x04,0x04,0x04,0x04,0x00,0x04,0x00},
	/* 0x22 '"' */ {0x0A,0x0A,0x0A,0x00,0x00,0x00,0x00,0x00},
	/* 0x23 '#' */ {0x0A,0x0A,0x1F,0x0A,0x1F,0x0A,0x0A,0x00},
	/* 0x24 '$' */ {0x04,0x0F,0x14,0x0E,0x05,0x1E,0x04,0x00},
	/* 0x25 '%' */ {0x18,0x19,0x02,0x04,0x08,0x13,0x03,0x00},
	/* 0x26 '&' */ {0x0C,0x12,0x14,0x08,0x15,0x12,0x0D,0x00},
	/* 0x27 apostrophe */ {0x06,0x04,0x08,0x00,0x00,0x00,0x00,0x00},
	/* 0x28 '(' */ {0x02,0x04,0x08,0x08,0x08,0x04,0x02,0x00},
	/* 0x29 ')' */ {0x08,0x04,0x02,0x02,0x02,0x04,0x08,0x00},
	/* 0x2A '*' */ {0x00,0x0A,0x04,0x1F,0x04,0x0A,0x00,0x00},
	/* 0x2B '+' */ {0x00,0x04,0x04,0x1F,0x04,0x04,0x00,0x00},
	/* 0x2C ',' */ {0x00,0x00,0x00,0x00,0x06,0x04,0x08,0x00},
	/* 0x2D '-' */ {0x00,0x00,0x00,0x1F,0x00,0x00,0x00,0x00},
	/* 0x2E '.' */ {0x00,0x00,0x00,0x00,0x00,0x06,0x06,0x00},
	/* 0x2F '/' */ {0x01,0x02,0x04,0x08,0x10,0x00,0x00,0x00},

	/* 0x30 '0' */ {0x0E,0x11,0x13,0x15,0x19,0x11,0x0E,0x00},
	/* 0x31 '1' */ {0x04,0x0C,0x04,0x04,0x04,0x04,0x0E,0x00},
	/* 0x32 '2' */ {0x0E,0x11,0x01,0x02,0x04,0x08,0x1F,0x00},
	/* 0x33 '3' */ {0x1F,0x02,0x04,0x02,0x01,0x11,0x0E,0x00},
	/* 0x34 '4' */ {0x02,0x06,0x0A,0x12,0x1F,0x02,0x02,0x00},
	/* 0x35 '5' */ {0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E,0x00},
	/* 0x36 '6' */ {0x06,0x08,0x10,0x1E,0x11,0x11,0x0E,0x00},
	/* 0x37 '7' */ {0x1F,0x01,0x02,0x04,0x08,0x08,0x08,0x00},
	/* 0x38 '8' */ {0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E,0x00},
	/* 0x39 '9' */ {0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C,0x00},
	/* 0x3A ':' */ {0x00,0x06,0x06,0x00,0x06,0x06,0x00,0x00},
	/* 0x3B ';' */ {0x00,0x06,0x06,0x00,0x06,0x04,0x08,0x00},
	/* 0x3C '<' */ {0x02,0x04,0x08,0x10,0x08,0x04,0x02,0x00},
	/* 0x3D '=' */ {0x00,0x00,0x1F,0x00,0x1F,0x00,0x00,0x00},
	/* 0x3E '>' */ {0x08,0x04,0x02,0x01,0x02,0x04,0x08,0x00},
	/* 0x3F '?' */ {0x0E,0x11,0x01,0x02,0x04,0x00,0x04,0x00},

	/* 0x40 '@' */ {0x0E,0x11,0x1D,0x15,0x1D,0x10,0x0E,0x00},
	/* 0x41 'A' */ {0x0E,0x11,0x11,0x1F,0x11,0x11,0x11,0x00},
	/* 0x42 'B' */ {0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E,0x00},
	/* 0x43 'C' */ {0x0E,0x11,0x10,0x10,0x10,0x11,0x0E,0x00},
	/* 0x44 'D' */ {0x1C,0x12,0x11,0x11,0x11,0x12,0x1C,0x00},
	/* 0x45 'E' */ {0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F,0x00},
	/* 0x46 'F' */ {0x1F,0x10,0x10,0x1E,0x10,0x10,0x10,0x00},
	/* 0x47 'G' */ {0x0E,0x11,0x10,0x17,0x11,0x11,0x0E,0x00},
	/* 0x48 'H' */ {0x11,0x11,0x11,0x1F,0x11,0x11,0x11,0x00},
	/* 0x49 'I' */ {0x0E,0x04,0x04,0x04,0x04,0x04,0x0E,0x00},
	/* 0x4A 'J' */ {0x07,0x02,0x02,0x02,0x02,0x12,0x0C,0x00},
	/* 0x4B 'K' */ {0x11,0x12,0x14,0x18,0x14,0x12,0x11,0x00},
	/* 0x4C 'L' */ {0x10,0x10,0x10,0x10,0x10,0x10,0x1F,0x00},
	/* 0x4D 'M' */ {0x11,0x1B,0x15,0x15,0x11,0x11,0x11,0x00},
	/* 0x4E 'N' */ {0x11,0x19,0x15,0x13,0x11,0x11,0x11,0x00},
	/* 0x4F 'O' */ {0x0E,0x11,0x11,0x11,0x11,0x11,0x0E,0x00},

	/* 0x50 'P' */ {0x1E,0x11,0x11,0x1E,0x10,0x10,0x10,0x00},
	/* 0x51 'Q' */ {0x0E,0x11,0x11,0x11,0x15,0x12,0x0D,0x00},
	/* 0x52 'R' */ {0x1E,0x11,0x11,0x1E,0x14,0x12,0x11,0x00},
	/* 0x53 'S' */ {0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E,0x00},
	/* 0x54 'T' */ {0x1F,0x04,0x04,0x04,0x04,0x04,0x04,0x00},
	/* 0x55 'U' */ {0x11,0x11,0x11,0x11,0x11,0x11,0x0E,0x00},
	/* 0x56 'V' */ {0x11,0x11,0x11,0x11,0x11,0x0A,0x04,0x00},
	/* 0x57 'W' */ {0x11,0x11,0x11,0x15,0x15,0x1B,0x11,0x00},
	/* 0x58 'X' */ {0x11,0x11,0x0A,0x04,0x0A,0x11,0x11,0x00},
	/* 0x59 'Y' */ {0x11,0x11,0x0A,0x04,0x04,0x04,0x04,0x00},
	/* 0x5A 'Z' */ {0x1F,0x01,0x02,0x04,0x08,0x10,0x1F,0x00},
	/* 0x5B '[' */ {0x0E,0x08,0x08,0x08,0x08,0x08,0x0E,0x00},
	/* 0x5C '\' */ {0x10,0x08,0x04,0x02,0x01,0x00,0x00,0x00},
	/* 0x5D ']' */ {0x0E,0x02,0x02,0x02,0x02,0x02,0x0E,0x00},
	/* 0x5E '^' */ {0x04,0x0A,0x11,0x00,0x00,0x00,0x00,0x00},
	/* 0x5F '_' */ {0x00,0x00,0x00,0x00,0x00,0x00,0x1F,0x00},
}};

std::array<std::array<u8, 8>, 64> psicomp80_state::gfx_font_64x8x5 = []{
	std::array<std::array<u8, 8>, 64> t{};
	for (auto &g : t) g = BLANK;
	return t;
}();

// ------------------ machine lifecycle ------------------

void psicomp80_state::machine_start()
{
	m_mm_stream.reserve(256);

	save_item(NAME(m_key_latch));
	save_item(NAME(m_mm_ready));
	save_item(NAME(m_mm_code));
	save_item(NAME(m_mm_one_shot_clear));

	save_item(NAME(m_mm_hs_rdy));
	save_item(NAME(m_mm_status_rdy));
	save_item(NAME(m_mm_status_b6));
	save_item(NAME(m_mm_latch));
	save_item(NAME(m_mm_expect_latch));
	save_item(NAME(m_mm_inv_pending));
	save_item(NAME(m_mm_tx_seq));

	save_item(NAME(m_mm_x));
	save_item(NAME(m_mm_y));
	save_item(NAME(m_mm_z));
	save_item(NAME(m_mm_t));
	save_item(NAME(m_mm_m));
	save_item(NAME(m_mm_deg_mode));
	save_item(NAME(m_mm_mant_digits));
	save_item(NAME(m_mm_digit_entry));
	save_item(NAME(m_mm_two_word_pending));
	save_item(NAME(m_mm_two_word_op));
	save_item(NAME(m_mm_error));
}

void psicomp80_state::machine_reset()
{
	m_key_latch = 0xff;
	m_mm_ready = false;
	m_mm_code  = 0x1f;
	m_mm_one_shot_clear = false;
	mm57109_reset();
}

// ------------------ memory & I/O ------------------

void psicomp80_state::mem_map(address_map &map)
{
	map(0x0000, 0x0bff).rom();
	map(0x0c00, 0x1fff).ram();

	map(0x8000, 0x87ff).mirror(0x7800).ram().share("vram");
}

void psicomp80_state::io_map(address_map &map)
{
	map.global_mask(0xff);

	map(0x01, 0x01).r(FUNC(psicomp80_state::port01_r));
	map(0x03, 0x03).r(FUNC(psicomp80_state::port03_r));
	map(0x60, 0x60).w(FUNC(psicomp80_state::port60_w));
}

u8 psicomp80_state::port01_r()
{
	const u8 v = m_key_latch;
	m_key_latch = 0xff;
	return v;
}

u8 psicomp80_state::port03_r()
{
	// Port $03: combined MM57109 status + 4-bit data.
	//
	// BURP uses bit5 ($20) as the READY line for the two-phase handshake in $042E:
	//   - it waits for READY=0 before phase1 OUT, then waits for READY=1 before phase2 OUT.
	//
	// BURP also uses bit6 ($40) as a secondary "result/status" indicator via $058A (mask $60).
	// To avoid deadlocking $042E, we model:
	//   - bit5 as the *handshake* READY only (m_mm_hs_rdy)
	//   - bit6 as the *status/result* READY (m_mm_status_rdy)
	//
	// Low bits contain the current 4-bit (or 5-bit) code sample; only the low nibble is
	// meaningful for IM1 capture (A & $0F).
	const bool hs_rdy = m_mm_hs_rdy;
	const bool st_rdy = m_mm_status_rdy;
	const bool br_b6  = m_mm_status_b6;

	u8 v = ((hs_rdy || st_rdy) ? 0x20 : 0x00) | (br_b6 ? 0x40 : 0x00) | (m_mm_code & 0x1f);

	LOGMASKED(LOG_MM_STATUS,
		"MM57109 R: IN ($03) @PC=%04X -> %02X(%03o) (hs_rdy=%d st_rdy=%d code=%02X(%03o))\n",
		(u16)m_cpu->pc(), v, unsigned(v), hs_rdy, st_rdy, m_mm_code, unsigned(m_mm_code));

	return v;
}





// ---------------------------------------------------------------------------
// MM57109 coarse state model (registers + instruction dispatcher)
// ---------------------------------------------------------------------------

void psicomp80_state::mm57109_reset()
{
	m_mm_hs_rdy = false;
	m_mm_status_rdy = false;
	m_mm_status_b6 = false;
	m_mm_latch = 0x00;
	m_mm_expect_latch = true;
	m_mm_inv_pending = false;
	m_mm_stream.clear();
	m_mm_tx_seq = 0;

	m_mm_x = m_mm_y = m_mm_z = m_mm_t = 0.0;
	m_mm_m = 0.0;
	m_mm_deg_mode = false;
	m_mm_mant_digits = 8;
	m_mm_digit_entry = false;
	m_mm_digit_buf.clear();
	m_mm_two_word_pending = false;
	m_mm_two_word_op = 0x00;
	m_mm_error = false;
	m_mm_nibble_q.clear();
}

bool psicomp80_state::mm57109_is_two_word(u8 op) const
{
	// Per MM57109 datasheet: several instructions are 2-word (opcode + parameter/addr).
	// We don't implement their behaviour yet, but we track the second word so we can
	// correlate BURP byte streams with required functionality.
	switch (op & 0x3f)
	{
	case 0x10: // TJC*
	case 0x11: // TX=0*
	case 0x12: // TX<0*
	case 0x15: // JMP*
	case 0x17: // IN*
	case 0x18: // SMDC*
	case 0x19: // IBNZ*
	case 0x1a: // DBNZ*
	case 0x16: // OUT* (note: also appears as 0x16)
		return true;
	default:
		return false;
	}
}

const char *psicomp80_state::mm57109_opcode_mn(u8 op) const
{
	// Prefer the existing mnemonic mapping (already used for logging).
	return mm57109_opcode_name(op & 0x3f);
}

void psicomp80_state::mm57109_push(double v)
{
	m_mm_t = m_mm_z;
	m_mm_z = m_mm_y;
	m_mm_y = m_mm_x;
	m_mm_x = v;
}

double psicomp80_state::mm57109_pop()
{
	double v = m_mm_x;
	m_mm_x = m_mm_y;
	m_mm_y = m_mm_z;
	m_mm_z = m_mm_t;
	// m_mm_t holds last T; keep as-is
	return v;
}

void psicomp80_state::mm57109_set_x(double v)
{
	m_mm_x = v;
}

void psicomp80_state::mm57109_queue_nibble(u8 nib)
{
	m_mm_nibble_q.push_back(nib & 0x0f);

	// Present the nibble on the low bits of port $03 and raise IRQ0 so BURP IM1 handler
	// ($0038) captures it into RAM.
	mm_set_data_ready(nib & 0x0f);
}

void psicomp80_state::mm57109_log_state(const char *reason)
{
	LOGMASKED(LOG_MM57109, "MM57109: state(%s) X=%g Y=%g Z=%g T=%g M=%g deg=%d mant=%u err=%d digit='%s' inv=%d\n",
		reason, m_mm_x, m_mm_y, m_mm_z, m_mm_t, m_mm_m,
		m_mm_deg_mode ? 1 : 0, unsigned(m_mm_mant_digits), m_mm_error ? 1 : 0,
		m_mm_digit_buf.c_str(), m_mm_inv_pending ? 1 : 0);
}

void psicomp80_state::mm57109_execute_single(u8 op)
{
	const u8 opcode = op & 0x3f;

	// Digit-entry class (0..9, DP, EE, CS, PI, EN)
	if (opcode <= 0x09)
	{
		m_mm_digit_entry = true;
		m_mm_digit_buf.push_back(char('0' + opcode));
		return;
	}
	switch (opcode)
	{
	case 0x0a: // DP
		m_mm_digit_entry = true;
		if (m_mm_digit_buf.find('.') == std::string::npos)
			m_mm_digit_buf.push_back('.');
		return;

	case 0x0b: // EE
		m_mm_digit_entry = true;
		if (m_mm_digit_buf.find('E') == std::string::npos)
			m_mm_digit_buf.push_back('E');
		return;

	case 0x0c: // CS (change sign)
		m_mm_digit_entry = true;
		if (!m_mm_digit_buf.empty() && m_mm_digit_buf[0] == '-')
			m_mm_digit_buf.erase(0, 1);
		else
			m_mm_digit_buf.insert(0, 1, '-');
		return;

	case 0x0d: // PI
		m_mm_digit_entry = false;
		m_mm_digit_buf.clear();
		mm57109_set_x(3.14159265358979323846);
		return;

	case 0x21: // EN (end digit entry / push)
		if (m_mm_digit_entry)
		{
			// Very rough parse; this is just to have a meaningful register model.
			char *endp = nullptr;
			double v = std::strtod(m_mm_digit_buf.c_str(), &endp);
			if (endp && endp != m_mm_digit_buf.c_str())
				mm57109_set_x(v);
			m_mm_digit_entry = false;
			m_mm_digit_buf.clear();
		}
		// EN pushes stack (X becomes new entry)
		mm57109_push(m_mm_x);
		return;

	case 0x1c: // MS
		m_mm_m = m_mm_x;
		return;

	case 0x1d: // MR
		mm57109_push(m_mm_m);
		return;

	case 0x39: // +
	{
		double x = mm57109_pop();
		double y = mm57109_pop();
		mm57109_push(y + x);
		return;
	}
	case 0x3a: // -
	{
		double x = mm57109_pop();
		double y = mm57109_pop();
		mm57109_push(y - x);
		return;
	}
	case 0x3b: // *
	{
		double x = mm57109_pop();
		double y = mm57109_pop();
		mm57109_push(y * x);
		return;
	}
	case 0x3c: // /
	{
		double x = mm57109_pop();
		double y = mm57109_pop();
		if (x == 0.0)
		{
			m_mm_error = true;
			mm57109_push(0.0);
		}
		else
		{
			mm57109_push(y / x);
		}
		return;
	}

	case 0x22: // TOGM
		m_mm_deg_mode = !m_mm_deg_mode;
		return;
	case 0x3F: // NOP 
	    // No operation, do nothing
	    return;

	default:
		break;
	}

	LOGMASKED(LOG_MM57109, "MM57109: UNIMPLEMENTED op=%02X(%03o) %-10s @PC=%04X (inv_pending=%d)\n",
		opcode, unsigned(opcode), mm57109_opcode_mn(opcode), (u16)m_cpu->pc(), m_mm_inv_pending ? 1 : 0);
}

void psicomp80_state::mm57109_commit(u8 op)
{
	const u8 opcode = op & 0x3f;

	// Handle pending 2nd word for prior 2-word op
	if (m_mm_two_word_pending)
	{
		LOGMASKED(LOG_MM57109, "MM57109: 2ndword for %02X(%03o) %-10s = %02X(%03o) @PC=%04X (NOT IMPLEMENTED)\n",
			m_mm_two_word_op, unsigned(m_mm_two_word_op), mm57109_opcode_mn(m_mm_two_word_op),
			opcode, unsigned(opcode), (u16)m_cpu->pc());
		m_mm_two_word_pending = false;
		m_mm_two_word_op = 0x00;
		// status: treat as complete
		m_mm_status_b6 = false;
		m_mm_status_rdy = true;
		return;
	}

	// INV prefix affects interpretation of the next opcode; keep tracking for logging.
	if (!m_mm_inv_pending && opcode == 0x20)
	{
		m_mm_inv_pending = true;
		LOGMASKED(LOG_MM57109, "MM57109: INV prefix armed\n");
		m_mm_status_b6 = false;
		m_mm_status_rdy = true;
		return;
	}

	if (m_mm_inv_pending)
	{
		// INV consumed by this opcode
		m_mm_inv_pending = false;
	}

	if (mm57109_is_two_word(opcode))
	{
		m_mm_two_word_pending = true;
		m_mm_two_word_op = opcode;
		LOGMASKED(LOG_MM57109, "MM57109: 2-word op %02X(%03o) %-10s awaiting param\n",
			opcode, unsigned(opcode), mm57109_opcode_mn(opcode));
		m_mm_status_b6 = false;
		m_mm_status_rdy = true;
		return;
	}

	mm57109_execute_single(opcode);

	// For now, assert "RDY wins" status after each committed opcode so ROM wait loops
	// can proceed. We will refine this once instruction behaviour is implemented.
	m_mm_status_b6 = m_mm_error ? true : false;
	m_mm_status_rdy = true;
}


void psicomp80_state::mm57109_dump_stream(const char *tag, u8 cmd)
{
	LOGMASKED(LOG_MM57109, "MM57109[%s] #%llu cmd=%02X(%03o) %-10s stream_len=%zu: ",
		tag, (unsigned long long)m_mm_tx_seq, cmd, unsigned(cmd), mm57109_opcode_name(cmd), m_mm_stream.size());
	for (u8 b : m_mm_stream)
		LOGMASKED(LOG_MM57109, "%02X(%03o) ", b, unsigned(b));
	LOGMASKED(LOG_MM57109, "\n");

	m_mm_stream.clear();
	++m_mm_tx_seq;
}

void psicomp80_state::port60_w(u8 data)
{
	// BURP routine $058A uses OUT ($60),$3F as an ACK to clear the MM57109 status RDY.
	// Only treat this as an ACK when status RDY is currently asserted; otherwise $3F is
	// ordinary bytecode and should go through the normal two-phase handshake below.
	if (((data & 0x80) == 0) && ((data & 0x7f) == 0x3f) && m_mm_status_rdy)
	{
		m_mm_status_rdy = false;
		return;
	}


	const u8 op = data & 0x7f;
	const char *opname = mm57109_opcode_name(op);
	LOGMASKED(LOG_MM57109, "MM57109 W: OUT ($60),%02X(%03o) %-10s @PC=%04X (bit7=%d)\n",
		data, unsigned(data), opname, (u16)m_cpu->pc(), (data >> 7) & 1);

	// // Special-case: $058A uses OUT ($60),$3F as an ACK/continue strobe when RDY($20) wins.
	// // Treat this as "clear status-ready" and do not fold it into the normal two-phase send.
	// if (((data & 0x80) == 0) && data == 0x3f && m_mm_status_rdy)
	// {
	// 	LOGMASKED(LOG_MM_ACK, "MM57109 W: OUT ($60),3F @PC=%04X ACK received (status_rdy=1) -> clear status_rdy\n", (u16)m_cpu->pc());
	// 	m_mm_status_rdy = false;
	// 	m_mm_hs_rdy = false;
		
	// 	return;
	// }


// Two-phase HOLD/RDY handshake as used by BURP routine $042E.
//
// NOTE: The byte passed into $042E can legitimately have bit7 set (it is BURP "bytecode"),
// and $042E itself generates the phase2 write by OR'ing bit7. Real hardware uses the
// handshake semantics rather than treating bit7 as part of the payload, so model this as
// a simple two-step state machine:
//   1) first OUT -> latch payload (data&0x7f), assert RDY (bit5) so $0439 loop can exit
//   2) second OUT -> commit latched payload, drop RDY so $0430 loop can exit next time
//
// This prevents hangs at $0439 if the *first* write happens to have bit7=1.
if (m_mm_expect_latch)
{
	m_mm_latch = data & 0x7f;
	LOGMASKED(LOG_MM57109, "MM57109: phase1 latch=%02X(%03o) %-10s (raw=%02X(%03o))\n",
		m_mm_latch, unsigned(m_mm_latch), mm57109_opcode_name(m_mm_latch), data, unsigned(data));

	m_mm_hs_rdy = true;
	m_mm_expect_latch = false;
	return;
}

// Commit phase
const u8 committed = m_mm_latch;
const char *mn = m_mm_inv_pending ? mm57109_inv_second_name(committed) : mm57109_opcode_name(committed);
	LOGMASKED(LOG_MM57109, "MM57109: commit byte=%02X(%03o) %-10s (raw=%02X(%03o))\n",
		committed, unsigned(committed), mn, data, unsigned(data));
	// Track INV prefix (0x20) as a one-instruction mode affecting the following committed opcode.
	if (!m_mm_inv_pending && committed == 0x20)
		m_mm_inv_pending = true;
	else if (m_mm_inv_pending)
		m_mm_inv_pending = false;
m_mm_stream.push_back(committed);
	mm57109_commit(committed);

m_mm_hs_rdy = false;
m_mm_expect_latch = true;

	// Status bits are handled by mm57109_commit() for now.
}



// ------------------ keyboard / interrupts ------------------

u8 psicomp80_state::ascii_to_mm_code(u8 data)
{
	if (data >= '0' && data <= '9')
		return u8(data - '0');

	if (data >= 'a' && data <= 'f')
		return u8(10 + (data - 'a'));

	if (data >= 'A' && data <= 'F')
		return u8(10 + (data - 'A'));

	if (data == 0x0d || data == 0x0a)
		return 0x10;

	if (data == 0x1b)
		return 0x11;

	if (data == ' ')
		return 0x12;

	return 0x1f;
}

void psicomp80_state::mm_set_data_ready(u8 code)
{
	m_mm_code = code & 0x1f;
	m_mm_ready = true;
	m_mm_one_shot_clear = false;

	m_cpu->set_input_line(INPUT_LINE_IRQ0, HOLD_LINE);
}

void psicomp80_state::kbd_put(u8 data)
{
	// The real COMP80 has a dedicated RESET key. For convenience in the emulation,
	// bind that to the host ESC key.
	//
	// generic_keyboard_device delivers character codes; ESC arrives as 0x1B.
	if (data == 0x1b)
	{
		machine().schedule_soft_reset();
		return;
	}

	// The COMP80 keyboard interface is a latched ASCII byte with a single strobe to NMI.
	// The monitor's NMI routine will reset if NMI arrives while the CPU is not in HALT,
	// so we must avoid generating extra strobes (e.g. key-up events / auto-repeat bursts).
	// Treat 0x00 as "no character" and ignore it.
	if (data == 0x00)
		return;

	// Debounce / one-shot strobe: ignore further key events until the monitor reads port 0x01
	// (port01_r clears m_key_latch back to 0xFF).
	if (m_key_latch != 0xff)
		return;

	m_key_latch = ~data;

	m_cpu->pulse_input_line(INPUT_LINE_NMI, attotime::zero);

	mm_set_data_ready(ascii_to_mm_code(data));
}

// ------------------ character mapping / display ------------------

static inline u8 map_code6_to_ascii_index(u8 code6)
{
	// Returns index into ascii_font_64x8x5 (0..63 corresponding to ASCII 0x20..0x5F),
	// or 0 for space if unknown.
	if (code6 == 0x00)
		return 0; // space

	if (code6 >= 0x01 && code6 <= 0x1A)
	{
		// 'A' is ASCII 0x41, so (0x41 - 0x20) = 0x21 is the index for 'A'.
		return u8(0x21 + (code6 - 1));
	}

	if (code6 >= 0x20 && code6 <= 0x3F)
		return u8(code6 - 0x20);

	return 0;
}

u8 psicomp80_state::glyph_row(u8 vram_byte, int row)
{
	const bool gfx = BIT(vram_byte, 6);
	const u8 code6 = vram_byte & 0x3f;

	if (gfx)
		return gfx_font_64x8x5[code6][row & 7] & 0x1f;

	const u8 idx = map_code6_to_ascii_index(code6);
	return ascii_font_64x8x5[idx][row & 7] & 0x1f;
}

u32 psicomp80_state::screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	const u32 bg = rgb_t::black();
	const u32 fg = rgb_t::white();

	bitmap.fill(bg, cliprect);

	for (int row = 0; row < kRowsVisible; row++)
	{
		for (int col = 0; col < kCols; col++)
		{
			const int index = row * kCols + col;
			const u8 vram = m_vram[index];

			const int x0 = col * kCharW;
			const int y0 = row * kCharH;

			for (int y = 0; y < 8; y++)
			{
				const int py = y0 + y;
				if (py < cliprect.top() || py > cliprect.bottom())
					continue;

				const u8 bits5 = glyph_row(vram, y);

				for (int x = 0; x < 5; x++)
				{
					const int px = x0 + x;
					if (px < cliprect.left() || px > cliprect.right())
						continue;

					const int bit = 4 - x; // bit4 leftmost
					bitmap.pix(py, px) = BIT(bits5, bit) ? fg : bg;
				}
			}
		}
	}

	return 0;
}

// ------------------ machine config ------------------

static INPUT_PORTS_START(psicomp80)
INPUT_PORTS_END

void psicomp80_state::psicomp80(machine_config &config)
{
	Z80(config, m_cpu, 4'000'000);
	m_cpu->set_addrmap(AS_PROGRAM, &psicomp80_state::mem_map);
	m_cpu->set_addrmap(AS_IO, &psicomp80_state::io_map);

	GENERIC_KEYBOARD(config, m_keyboard, 0);
	m_keyboard->set_keyboard_callback(FUNC(psicomp80_state::kbd_put));

	screen_device &screen(SCREEN(config, "screen", SCREEN_TYPE_RASTER));
	screen.set_refresh_hz(50);
	screen.set_vblank_time(ATTOSECONDS_IN_USEC(2500));
	screen.set_size(kWidth, kHeight);
	screen.set_visarea(0, kWidth - 1, 0, kHeight - 1);
	screen.set_screen_update(FUNC(psicomp80_state::screen_update));

	PALETTE(config, "palette", palette_device::MONOCHROME);
}

} // anonymous namespace

ROM_START(psicomp80)
	ROM_REGION(0x10000, "maincpu", 0)
        ROM_LOAD("psicomp80.rom", 0x0000, 0x0c00, CRC(0f771e8e) SHA1(c4521d3234124a73f5e49d17ebe7bfa198a41e2c))
ROM_END

COMP(1979, psicomp80, 0, 0, psicomp80, psicomp80, psicomp80_state, empty_init,
     "PSI/Powertran", "COMP80", MACHINE_NOT_WORKING | MACHINE_NO_SOUND)