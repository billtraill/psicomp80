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

	// MM57109-ish "data ready" latch for port 03h (and IRQ0 generation)
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

	save_item(NAME(m_key_latch));
	save_item(NAME(m_mm_ready));
	save_item(NAME(m_mm_code));
	save_item(NAME(m_mm_one_shot_clear));
}

void psicomp80_state::machine_reset()
{
	m_key_latch = 0xff;
	m_mm_ready = false;
	m_mm_code  = 0x1f;
	m_mm_one_shot_clear = false;
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
}

u8 psicomp80_state::port01_r()
{
	const u8 v = m_key_latch;
	m_key_latch = 0xff;
	return v;
}

u8 psicomp80_state::port03_r()
{
	u8 v = (m_mm_ready ? 0x20 : 0x00) | (m_mm_code & 0x1f);

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
        ROM_LOAD("psicomp80.rom", 0x0000, 0x0c00, CRC(97854074) SHA1(e55177c02771ae7a41fea6a783d2b792713af25e))
ROM_END

COMP(1979, psicomp80, 0, 0, psicomp80, psicomp80, psicomp80_state, empty_init,
     "PSI/Powertran", "COMP80", MACHINE_NOT_WORKING | MACHINE_NO_SOUND)
