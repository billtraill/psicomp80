// license:BSD-3-Clause
// copyright-holders:ChatGPT
/***************************************************************************

  PSI COMP80 (Wireless World construction project, 1979-1980)
  Skeleton driver (work-in-progress)

  Implemented model (bring-up oriented):
    - Video RAM at 8000-87FF, mirrored every 0800 up to FFFF (per hardware notes)
    - Basic raster display that visualises VRAM immediately (debug glyphs)
    - Keyboard strobe generates NMI (wakes DI/HALT loops)
    - MM57109 "data ready" interrupt modelled as IRQ0 (IM 1 -> 0038h) latch

  IMPORTANT:
    - This is NOT a cycle-accurate VDU or a full MM57109 emulation.
    - Character generator bitmaps are not yet known; display uses a debug renderer
      (6 vertical bars based on VRAM byte bits) so you can see activity.

***************************************************************************/

#include "emu.h"

#include "cpu/z80/z80.h"
#include "machine/keyboard.h"
#include "screen.h"
#include "emupal.h"

#include <algorithm>
#include <vector>

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
	// -------- hardware-ish geometry (from notes: 10x6 char format; 32 columns via /32 counter) --------
	static constexpr int kCols  = 32;
	static constexpr int kCharW = 6;
	static constexpr int kCharH = 10;

	// 2 KiB VRAM -> 2048/32 = 64 rows
	static constexpr int kRows  = 64;

	static constexpr int kWidth  = kCols * kCharW; // 192
	static constexpr int kHeight = kRows * kCharH; // 640

	// devices/memory
	required_device<z80_device>              m_cpu;
	required_shared_ptr<u8>                  m_vram;
	required_device<generic_keyboard_device> m_keyboard;

	// ROM shadow (writable) for live patching/bring-up
	std::vector<u8> m_romshadow;

	// keyboard latch returned by port 01h (ROM does IN then CPL)
	u8 m_key_latch = 0xff;

	// MM57109-ish "data ready" latch for port 03h (and IRQ0 generation)
	bool m_mm_ready = false;
	u8   m_mm_code  = 0x1f;  // 5-bit code
	bool m_mm_one_shot_clear = false;

	// ROM shadow handlers
	u8  romshadow_r(offs_t offset);
	void romshadow_w(offs_t offset, u8 data);

	// maps
	void mem_map(address_map &map);
	void io_map(address_map &map);

	// I/O handlers (current bring-up model)
	u8 port01_r();
	u8 port03_r();

	// keyboard -> strobe (NMI) + MM data ready (IRQ0)
	void kbd_put(u8 data);

	// display
	u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect);

	// helpers
	static u8 ascii_to_mm_code(u8 data);
	void mm_set_data_ready(u8 code);

protected:
	virtual void machine_start() override;
	virtual void machine_reset() override;
};

void psicomp80_state::machine_start()
{
	// Create a writable shadow of the ROM so we can patch bytes during bring-up.
	const u8 *rom = memregion("maincpu")->base();
	m_romshadow.resize(0x0c00);
	std::copy(rom, rom + 0x0c00, m_romshadow.begin());

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

u8 psicomp80_state::romshadow_r(offs_t offset)
{
	return (offset < m_romshadow.size()) ? m_romshadow[offset] : 0xff;
}

void psicomp80_state::romshadow_w(offs_t offset, u8 data)
{
	if (offset < m_romshadow.size())
		m_romshadow[offset] = data;
}

void psicomp80_state::mem_map(address_map &map)
{
	map(0x0000, 0x0bff).rw(FUNC(psicomp80_state::romshadow_r), FUNC(psicomp80_state::romshadow_w));
	map(0x0c00, 0x1fff).ram();

	// Video RAM (2 KiB) mirrored every 0x0800 up to 0xFFFF per hardware description.
	map(0x8000, 0x87ff).mirror(0x7800).ram().share("vram");
}

void psicomp80_state::io_map(address_map &map)
{
	map.global_mask(0xff);

	// Keyboard latch (active-low; ROM does CPL after read)
	map(0x01, 0x01).r(FUNC(psicomp80_state::port01_r));

	// MM57109-ish status/data (bit5 "ready", bits0..4 code)
	map(0x03, 0x03).r(FUNC(psicomp80_state::port03_r));

	// Other ports currently unknown/unimplemented.
}

u8 psicomp80_state::port01_r()
{
	// ROM does IN (01h) then CPL.
	// Real keyboard latch likely clears after a read; do one-shot clear to prevent repeats.
	const u8 v = m_key_latch;
	m_key_latch = 0xff;
	return v;
}

u8 psicomp80_state::port03_r()
{
	// bit 5: data ready
	// bits 0..4: 5-bit code
	u8 v = (m_mm_ready ? 0x20 : 0x00) | (m_mm_code & 0x1f);

	// One-shot clear behaviour: drop ready after it has been observed.
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

u8 psicomp80_state::ascii_to_mm_code(u8 data)
{
	// Minimal mapping to let ROM make progress:
	//  - '0'..'9' -> 0..9
	//  - 'A'..'F'/'a'..'f' -> 10..15
	//  - Enter -> 0x10
	//  - Esc   -> 0x11
	//  - Space -> 0x12
	//  - Everything else -> 0x1f
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

	// Assert IRQ0 for IM 1 (vector 0038h). HOLD_LINE is the safe "pulse".
	m_cpu->set_input_line(INPUT_LINE_IRQ0, HOLD_LINE);
}

void psicomp80_state::kbd_put(u8 data)
{
	// Port 01h latch is active-low because ROM does IN then CPL.
	m_key_latch = ~data;

	// Keyboard strobe -> NMI (wakes DI/HALT paths). Only on actual keypress.
	m_cpu->pulse_input_line(INPUT_LINE_NMI, attotime::zero);

	// Also feed the MM57109-style "data ready" path so IM1 ISR can run when enabled.
	mm_set_data_ready(ascii_to_mm_code(data));
}

u32 psicomp80_state::screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	const u32 bg = rgb_t::black();
	const u32 fg = rgb_t::white();

	bitmap.fill(bg, cliprect);

	// Debug renderer: each VRAM byte becomes a 6x10 cell.
	// The first 8 scanlines are "active"; last 2 blank (per hardware notes).
	// Within each active scanline, we draw 6 vertical bars representing bits 5..0 of the VRAM byte.
	for (int row = 0; row < kRows; row++)
	{
		for (int col = 0; col < kCols; col++)
		{
			const int index = row * kCols + col;
			const u8 code = m_vram[index];

			const int x0 = col * kCharW;
			const int y0 = row * kCharH;

			for (int y = 0; y < 8; y++)
			{
				const int py = y0 + y;
				if (py < cliprect.top() || py > cliprect.bottom())
					continue;

				u32 *dst = &bitmap.pix(py, x0);
				for (int x = 0; x < kCharW; x++)
				{
					const int bit = (kCharW - 1) - x; // show bits 5..0 left->right
					const int px = x0 + x;
					if (px < cliprect.left() || px > cliprect.right())
						continue;

					dst[x] = BIT(code, bit) ? fg : bg;
				}
			}
		}
	}

	return 0;
}

static INPUT_PORTS_START(psicomp80)
INPUT_PORTS_END

void psicomp80_state::psicomp80(machine_config &config)
{
	// CPU clock unknown; refine later.
	Z80(config, m_cpu, 4'000'000);
	m_cpu->set_addrmap(AS_PROGRAM, &psicomp80_state::mem_map);
	m_cpu->set_addrmap(AS_IO, &psicomp80_state::io_map);

	// Generic keyboard -> ASCII bytes
	GENERIC_KEYBOARD(config, m_keyboard, 0);
	m_keyboard->set_keyboard_callback(FUNC(psicomp80_state::kbd_put));

	// Simple raster screen for VRAM visualisation
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
	ROM_LOAD("psicomp80.rom", 0x0000, 0x0c00, CRC(1e12191d) SHA1(ba8ff61e42e7a1b8a07088e9a9c9e20a6596a847))
ROM_END

//   YEAR  NAME       PARENT  COMPAT  MACHINE    INPUT     CLASS            INIT        COMPANY          FULLNAME  FLAGS
COMP(1979, psicomp80, 0,      0,      psicomp80, psicomp80, psicomp80_state, empty_init, "PSI/Powertran", "COMP80", MACHINE_NOT_WORKING | MACHINE_NO_SOUND)
