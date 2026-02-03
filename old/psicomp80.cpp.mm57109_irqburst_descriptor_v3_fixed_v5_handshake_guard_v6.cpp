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

	// MM57109 interface (minimal handshake/status model)
//  - Port 0x60: two-phase write (bit7=0 latch, bit7=1 commit)
//  - Port 0x03:
//      bit5 = handshake-ready (used by ROM routine at $042E)
//      bit6 = data-ready/status (used by ROM routine at $058E)
//      low nibble = DO[3:0] sampled by monitor RST $38 handler (IN $03 / AND $0F)
bool m_mm_hs_rdy = false;      // bit5
bool m_mm_drdy   = false;      // bit6 (asserted after commit, clears on first read)
u8   m_mm_do     = 0x0;        // low nibble presented on port 0x03 when drdy asserted
u8   m_mm_phase1 = 0x00;       // latched data from phase1 (bit7=0)
bool m_mm_expect_phase2 = false;
// Handshake guard: only a matching phase2 (same 7-bit data) may clear hs_rdy.
bool m_mm_handshake_active = false;
u8   m_mm_handshake_data = 0x00;
	bool m_mm_handshake_seen_rdy = false; // set on first port03_r while hs_rdy asserted

// MM57109 "response" helper:
// Some BURP paths enable interrupts and expect a short burst of IRQ0 samples (RST $38 handler stores low nibble of IN($03))
// into a 4-nibble descriptor block at $1FF4..$1FF7. If $1FF7 remains 0, BURP's formatter runs off the top of RAM.
// We model this with a small queued nibble burst delivered via IRQ0 pulses.
emu_timer *m_mm_irq_timer = nullptr;
u8   m_mm_resp_nibbles[4] = { 0x02, 0x00, 0x00, 0x06 }; // default burst ends with 0x06 (matches manual e 1ff7,06 workaround)
u8   m_mm_resp_len = 0;
u8   m_mm_resp_pos = 0;
u8   m_mm_pulses_left = 0;     // how many IM1/IRQ0 samples still to generate for the current burst

// legacy "data ready" helper used by keyboard path (kept for now)
bool m_mm_ready = false;
u8   m_mm_code  = 0x1f;
bool m_mm_one_shot_clear = false;

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
	TIMER_CALLBACK_MEMBER(mm_irq_tick);


	// keyboard -> strobe (NMI) + MM data ready (IRQ0)
	void kbd_put(u8 data);
	// display
	u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect);

	// helpers
	static u8 ascii_to_mm_code(u8 data);
	void mm_set_data_ready(u8 code);

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
	m_mm_irq_timer = timer_alloc(FUNC(psicomp80_state::mm_irq_tick), this);

	save_item(NAME(m_key_latch));

	// legacy
	save_item(NAME(m_mm_ready));
	save_item(NAME(m_mm_code));
	save_item(NAME(m_mm_one_shot_clear));

	// handshake/status
	save_item(NAME(m_mm_hs_rdy));
	save_item(NAME(m_mm_drdy));
	save_item(NAME(m_mm_do));
	save_item(NAME(m_mm_phase1));
	save_item(NAME(m_mm_expect_phase2));
		// handshake guard state
		save_item(NAME(m_mm_handshake_active));
		save_item(NAME(m_mm_handshake_data));
		save_item(NAME(m_mm_handshake_seen_rdy));

	// response burst
	save_item(NAME(m_mm_resp_nibbles));
	save_item(NAME(m_mm_resp_len));
	save_item(NAME(m_mm_resp_pos));
	save_item(NAME(m_mm_pulses_left));
}

void psicomp80_state::machine_reset()
{
	m_key_latch = 0xff;

	// legacy
	m_mm_ready = false;
	m_mm_code  = 0x1f;
	m_mm_one_shot_clear = false;

	// handshake/status
	m_mm_hs_rdy = false;
	m_mm_drdy = false;
	m_mm_do = 0x00;
	m_mm_phase1 = 0x00;
	m_mm_expect_phase2 = false;
	m_mm_handshake_active = false;
	m_mm_handshake_data = 0x00;
	m_mm_handshake_seen_rdy = false;

	// response burst
	m_mm_resp_len = 0;
	m_mm_resp_pos = 0;
	m_mm_pulses_left = 0;
	if (m_mm_irq_timer)
		m_mm_irq_timer->adjust(attotime::never);
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

void psicomp80_state::port60_w(u8 data)
{
	// The ROM uses a two-phase write protocol via $042E:
	//   wait hs_rdy==0, OUT $60,<byte>
	//   wait hs_rdy==1, OUT $60,<byte>|$80
	//
	// Separately, BURP polls port 0x03 bits 5/6 at $058E, waiting for *exactly one* of them to be set.
	// We model that by asserting bit6 (data-ready) after a commit, then clearing it on the first port03 read.
	//

	if ((data & 0x80) == 0x00)
	{
		// Phase 1: start a handshake window for this 7-bit value.
		// Real hardware appears to require: wait RDY==0, write value, then wait RDY==1, write SAME value with bit7 set.
		// IMPORTANT: other code (e.g. IM1 handler paths) may also write port $60 while a handshake is in progress.
		// We therefore *only* allow a matching phase2 (same low 7 bits) to close the handshake and drop RDY.
		m_mm_phase1 = data;
		m_mm_expect_phase2 = true;          // still useful for diagnostics
		m_mm_handshake_active = true;
		m_mm_handshake_data = data & 0x7f;
			m_mm_handshake_seen_rdy = false;
		m_mm_hs_rdy = true;                // port03 bit5 -> 1 so ROM can exit the $0439 wait loop
		logerror("MM57109: phase1 latch=%02X\n", data);
		return;
	}

		// Phase 2 (commit): only close the handshake if this is the matching value.
	const u8 low7 = data & 0x7f;
		// IMPORTANT: we must not drop RDY (bit5) before the ROM's wait loop at $0439 has observed it.
		// With IM 1 enabled, the monitor's ISR can run between OUT($60),A and IN($03) and may write
		// unrelated values to $60.  Guard against prematurely clearing RDY by requiring that at least
		// one port03_r has occurred while RDY was asserted for this handshake.
		const bool is_matching_phase2 = (m_mm_handshake_active && (low7 == m_mm_handshake_data) && m_mm_handshake_seen_rdy);

	// If it's a non-matching phase2, treat it as an ordinary output that should NOT interfere
	// with the ROM's $042E handshake state.
	const u8 committed = low7;

	m_mm_expect_phase2 = false; // diagnostic only
		if (is_matching_phase2)
	{
		m_mm_handshake_active = false;
		m_mm_hs_rdy = false;      // port03 bit5 -> 0 so the next $042E can begin
	}

	// Minimal DO behaviour for now: expose low nibble of the committed byte.
	// This is *not* a full MM57109 implementation, but it prevents deadlocks and gives deterministic traces.
	m_mm_do = committed & 0x0f;
	// Only assert DRDY for a proper handshake completion. For non-matching phase2 writes,
	// we leave DRDY alone to avoid confusing BURP's $058E poll.
	if (is_matching_phase2)
		m_mm_drdy = true;

		// The ROM enables IM1+EI (see $0462-$0467) and expects *multiple* IRQ0 samples to be taken
		// by the monitor's IM1 handler at $0038, storing successive low nibbles at $1FF4..$1FF7.
		// On real hardware, the MM57109 (or glue) likely generates several IRQ0 pulses to deliver
		// a small descriptor/status block.
		//
		// In the traces so far, only $1FF4 gets written (nibble=2) and $1FF7 remains 0, which makes
		// the formatter at $04A0 compute an enormous LDIR count and run off the top of RAM.
		// The manual debugger workaround (e 1ff7,06) effectively forces that count to be 6.
		//
			// So, for now, after each commit we emit a 4-nibble IRQ0 burst: [<lo-nibble>,0,0,6].
		// (This is still "minimal" emulation: it is a behavioural shim to unblock BURP while we
		// reverse-engineer the true MM57109 protocol from the ROM.)
				bool burst_started = false;
				if (is_matching_phase2 && m_mm_resp_len == 0 && m_mm_pulses_left == 0)
			{
				// Queue the 4 nibbles; port03_r will advance one nibble per ISR read.
				m_mm_resp_nibbles[0] = u8(m_mm_do & 0x0f);
				m_mm_resp_nibbles[1] = 0x00;
				m_mm_resp_nibbles[2] = 0x00;
				m_mm_resp_nibbles[3] = 0x06;
				m_mm_resp_len = 4;
				m_mm_resp_pos = 0;

				// IMPORTANT: We must not emit these pulses "back-to-back" in the same timeslice.
				// In practice, multiple pulse_input_line() calls can collapse to a single serviced interrupt
				// (especially if the CPU hasn't had a chance to re-enable IFF1 between pulses).
				// Instead, schedule a short burst with small spacing so the Z80 can take 4 distinct IM1 entries.
				m_mm_pulses_left = 4;
				m_mm_irq_timer->adjust(attotime::from_usec(20));
					burst_started = true;
			}

			logerror("MM57109: commit byte=%02X (raw=%02X) -> DO=%X, assert drdy, irq0 burst [%X,0,0,6]%s\n",
				committed, data, m_mm_do, (m_mm_do & 0x0f), burst_started ? "" : " (suppressed: burst already active)");
}


TIMER_CALLBACK_MEMBER(psicomp80_state::mm_irq_tick)
{
	if (!m_mm_pulses_left)
		return;

	// Generate one IRQ0 pulse (IM1 vector at 0x0038 in Z80 IM 1).
	// Width must be non-zero (MAME will reject zero-width pulses).
	m_cpu->pulse_input_line(INPUT_LINE_IRQ0, attotime::from_usec(2));
	--m_mm_pulses_left;

	// Space pulses slightly so the CPU can service each one and return.
	if (m_mm_pulses_left)
		m_mm_irq_timer->adjust(attotime::from_usec(20));
}



u8 psicomp80_state::port03_r()
{
	// Base: legacy 5-bit code (kept for monitor/keyboard experiments)
	u8 v = (m_mm_code & 0x1f);

	// Always present handshake/status bits even during the IRQ0 burst sampling path.
	// The BURP handshake routine at $042E waits on bit5 toggling, and will deadlock
	// if our "burst" return path masks those bits.
	// If we're between phase1 and phase2 (m_mm_expect_phase2), force hs_rdy=1 so the ROM's
	// handshake waiter at $0439 can always make forward progress.
	if (m_mm_hs_rdy || m_mm_expect_phase2)
	{
		v |= 0x20; // bit5
		if (m_mm_handshake_active)
			m_mm_handshake_seen_rdy = true; // something observed RDY-high; allow phase2 to close handshake
	}
	if (m_mm_drdy)
		v |= 0x40; // bit6

	// IRQ0 burst sampling path: on each read, return the next queued nibble.
	if (m_mm_resp_len)
	{
		const u8 nib = (m_mm_resp_pos < m_mm_resp_len) ? (m_mm_resp_nibbles[m_mm_resp_pos] & 0x0f) : 0x0f;
		if (m_mm_resp_pos < m_mm_resp_len)
			m_mm_resp_pos++;
		if (m_mm_resp_pos >= m_mm_resp_len)
		{
			m_mm_resp_len = 0;
			m_mm_resp_pos = 0;
		}
		// Preserve handshake/status bits (already OR'd into v above) while overriding only the low nibble.
		return (v & 0xf0) | nib;
	}

	// Normal (non-burst) data-ready path provides DO nibble as well.
	if (m_mm_drdy)
		v = (v & 0xf0) | (m_mm_do & 0x0f) | 0x40; /// bit6 + DO nibble

	// If data-ready is being used (BURP poll at $058E), clear it after *one* successful read,
	// because the ROM then spins waiting for port 0x03 to become zero (PC $059E).
	if (m_mm_drdy)
	{
		m_mm_drdy = false;
		m_mm_do = 0x00;
	}

	// Preserve legacy one-shot clear for m_mm_ready (bit5) if it is still in use elsewhere.
	// (This is separate from m_mm_hs_rdy/m_mm_drdy.)
	if (m_mm_ready)
	{
		if (m_mm_one_shot_clear)
		{
			m_mm_ready = false;
			m_mm_one_shot_clear = false;
		}
		else
		{
			m_mm_one_shot_clear = true;
		}
		// legacy readiness shows up on bit5 too
		v |= 0x20;
	}

	return v;
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
	// Legacy helper: used by keyboard path to present a 5-bit code on port 0x03.
	m_mm_code = code & 0x1f;
	m_mm_ready = true;
	m_mm_one_shot_clear = false;

	// Also present the low nibble as DO and assert drdy once, so BURP-style polls can see activity.
	m_mm_do = code & 0x0f;
	m_mm_drdy = true;

	// Real hardware likely uses an interrupt for "data ready"; keep IRQ0 for now.
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
