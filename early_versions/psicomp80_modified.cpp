// license:BSD-3-Clause
// copyright-holders:ChatGPT
/***************************************************************************

  PSI COMP80 (Wireless World construction project, 1979-1980)

  Bring-up driver focused on the interrupt wiring described in the
  HardwareDescription.txt scan:

    - Keyboard strobe generates a Z80 NMI (non-maskable interrupt).
    - MM57109 R/W ("data bytes waiting") drives the Z80 INT input
      (maskable interrupt).

  The ROM you provided uses HALT as a wait primitive and expects an interrupt
  to wake it (see the HALT at 0x0356 in your trace).

  What this driver implements:
    - A keyboard byte latch on port 0x01 (active-low, because ROM does IN then CPL).
      Any keypress pulses NMI.
    - A very small MM57109-ish stub:
        * Reading port 0x03 returns bit 5 = data-ready, and bits 0..4 = a code.
        * Writing port 0x60 is treated as "MM57109 produced/queued a byte" for
          bring-up: it asserts INT (IRQ0) and makes port 0x03 show READY.
      (This is not a real 57109 emulation; it’s just enough to exercise the ROM’s
       interrupt path so you can iterate.)

***************************************************************************/

#include "emu.h"
#include "cpu/z80/z80.h"
#include "machine/keyboard.h"

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
	// devices/memory
	required_device<z80_device>              m_cpu;
	required_shared_ptr<u8>                  m_vram;
	required_device<generic_keyboard_device> m_keyboard;

	// latched keyboard byte returned by port 0x01 (active-low)
	u8 m_key_latch = 0xff;

	// MM57109-ish "data waiting" latch shown on port 0x03
	bool m_mm_ready = false;
	u8   m_mm_code  = 0x1f;   // 5-bit code exposed in bits 0..4

	// maps
	void mem_map(address_map &map);
	void io_map(address_map &map);

	// I/O
	u8  port01_r();
	u8  port03_r();
	void port60_w(u8 data);

	// keyboard callback
	void kbd_put(u8 data);

	// helper
	void mm_set_ready(u8 code);

	// driver_device
	virtual void machine_start() override;
	virtual void machine_reset() override;
};

void psicomp80_state::machine_start()
{
	save_item(NAME(m_key_latch));
	save_item(NAME(m_mm_ready));
	save_item(NAME(m_mm_code));
}

void psicomp80_state::machine_reset()
{
	m_key_latch = 0xff;
	m_mm_ready = false;
	m_mm_code  = 0x1f;

	// make sure interrupt line is clear after reset
	m_cpu->set_input_line(INPUT_LINE_IRQ0, CLEAR_LINE);
}

void psicomp80_state::mem_map(address_map &map)
{
	// ROM is 0x0000-0x0bff (3 kB) in your dump; leave address space open beyond.
	map(0x0000, 0x0bff).rom().region("maincpu", 0);
	map(0x0c00, 0x1fff).ram();

	// video character RAM
	map(0x8000, 0x87ff).ram().share("vram");
}

void psicomp80_state::io_map(address_map &map)
{
	map.global_mask(0xff);

	// reads
	map(0x01, 0x01).r(FUNC(psicomp80_state::port01_r));
	map(0x03, 0x03).r(FUNC(psicomp80_state::port03_r));

	// writes (most ports still stubbed)
	map(0x60, 0x60).w(FUNC(psicomp80_state::port60_w));
}

u8 psicomp80_state::port01_r()
{
	// ROM does IN (01h) then CPL, so present the raw byte inverted (active-low).
	return m_key_latch;
}

u8 psicomp80_state::port03_r()
{
	// bit 5 = data ready; bits 0..4 = 5-bit code
	u8 v = (m_mm_ready ? 0x20 : 0x00) | (m_mm_code & 0x1f);

	// Typical behavior for an "INT means data waiting" line:
	// once the CPU has read the status/data byte, drop READY and deassert INT.
	if (m_mm_ready)
	{
		m_mm_ready = false;
		m_cpu->set_input_line(INPUT_LINE_IRQ0, CLEAR_LINE);
	}

	return v;
}

void psicomp80_state::mm_set_ready(u8 code)
{
	m_mm_code  = code & 0x1f;
	m_mm_ready = true;

	// assert maskable interrupt (Z80 INT) on IRQ0
	m_cpu->set_input_line(INPUT_LINE_IRQ0, ASSERT_LINE);
}

void psicomp80_state::port60_w(u8 data)
{
	// In the hardware description, the MM57109 indicates "bytes waiting" via
	// its R/W output which is wired to Z80 INT. For bring-up, treat writes to
	// port 0x60 as the event that causes a data-ready/INT.
	//
	// This matches your ROM trace using IN 03 / test bit 5 / OUT 60 patterns.
	mm_set_ready(data);
}

void psicomp80_state::kbd_put(u8 data)
{
	// Latch the keycode for the ROM to read at IN 01.
	// generic_keyboard_device gives ASCII; invert to match active-low read.
	m_key_latch = ~data;

	// Keyboard strobe -> NMI pulse (edge-triggered)
	m_cpu->pulse_input_line(INPUT_LINE_NMI, attotime::zero);
}

void psicomp80_state::psicomp80(machine_config &config)
{
	Z80(config, m_cpu, 4'000'000); // clock unknown; refine later
	m_cpu->set_addrmap(AS_PROGRAM, &psicomp80_state::mem_map);
	m_cpu->set_addrmap(AS_IO, &psicomp80_state::io_map);

	GENERIC_KEYBOARD(config, m_keyboard, 0);
	m_keyboard->set_keyboard_callback(FUNC(psicomp80_state::kbd_put));
}

} // anonymous namespace

ROM_START(psicomp80)
	ROM_REGION(0x10000, "maincpu", 0)
	ROM_LOAD("psicomp80.rom", 0x0000, 0x0c00, CRC(1e12191d) SHA1(ba8ff61e42e7a1b8a07088e9a9c9e20a6596a847))
ROM_END

//   YEAR  NAME      PARENT  COMPAT  MACHINE    INPUT     CLASS            INIT        COMPANY          FULLNAME  FLAGS
COMP(1979, psicomp80, 0,      0,      psicomp80, 0,        psicomp80_state, empty_init, "PSI/Powertran", "COMP80", MACHINE_NOT_WORKING | MACHINE_NO_SOUND)
