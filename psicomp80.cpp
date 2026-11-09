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
    - Character generation model: 2513-style 64x8x5 generator + optional
graphics set selected by VRAM bit 6.
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
#include "emupal.h"
#include "machine/keyboard.h"
#include "screen.h"
#include "imagedev/cassette.h"
#include "imagedev/floppy.h"
#include "machine/wd_fdc.h"
#include "formats/wd177x_dsk.h"

#include <array>
#include <cmath>
#include <cstdlib>
#include <system_error>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// COMP80 cassette tape image + bitstream bridge
//
// The real COMP80 cassette interface presents the Z80 with a single decoded
// logic bit (FSK demodulated) and accepts a single logic bit to drive the FSK
// modulator. The monitor firmware uses:
//   - IN  ($00) bit 0 : tape input (idle=1, start=0)
//   - OUT ($20) bit 7 : tape output (bit7 first, async serial)
// with 300 baud, 1 start bit (0), 8 data bits MSB-first, and ~1.5 stop bits.
//
// We model a *digital* bitstream (not audio tones). Files are raw byte streams
// in the order the firmware reads/writes them.
//
// Mount/unmount (and therefore change filename at runtime) is handled by MAME's
// File Manager because this is a device_image_interface.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Floppy disc (Wireless World, Oct/Dec 1980): FD1771 controller, 8in drive,
// IBM 3740 format: 77 tracks x 26 sectors (numbered 1-26) x 128 bytes, FM.
// Images are raw sector dumps, track 0 sector 1 first (256,256 bytes).
// ---------------------------------------------------------------------------
class psicomp80_dsk_format : public wd177x_format
{
public:
  psicomp80_dsk_format() : wd177x_format(formats) {}
  virtual const char *name() const noexcept override { return "psicomp80"; }
  virtual const char *description() const noexcept override { return "PSI COMP80 8\" IBM 3740 disc image"; }
  virtual const char *extensions() const noexcept override { return "img"; }

private:
  static const format formats[];
};

const psicomp80_dsk_format::format psicomp80_dsk_format::formats[] = {
  { floppy_image::FF_8, floppy_image::SSSD, floppy_image::FM,
    2000, 26, 77, 1, 128, {}, 1, {}, 26, 11, 27 },
  {}
};

const psicomp80_dsk_format FLOPPY_PSICOMP80_FORMAT;

static void psicomp80_floppies(device_slot_interface &device)
{
  device.option_add("8sssd", FLOPPY_8_SSSD);
}

static void psicomp80_floppy_formats(format_registration &fr)
{
  fr.add(FLOPPY_PSICOMP80_FORMAT);
}

// ---------------------------------------------------------------------------
// MM57109 tracing
//
// MAME uses logmacro.h. Define VERBOSE before including it to avoid
// redefinition warnings promoted to errors (-Werror,-Wmacro-redefined).
// ---------------------------------------------------------------------------
#define LOG_MM57109 (1U << 0)   // MM57109 byte stream + handshake
#define LOG_MM_STATUS (1U << 1) // port $03 reads (noisy)
#define LOG_MM_ACK (1U << 2)    // $3F ACK handling

// #define VERBOSE (LOG_MM57109 | LOG_MM_ACK)
#define VERBOSE 0

// Timestamp for MM57109 logs (seconds since start)
#define MM_TS() (machine().time().as_double())

// ---------------------------------------------------------------------------
// MM57109 opcode → mnemonic helpers (derived from
// MM57109_cmds_data_with_regs_and_burp.md) These are for LOGGING ONLY. They do
// not change emulation behaviour. Note: BURP may use some opcode bytes as
// interface control/separators.
// ---------------------------------------------------------------------------
static const char *mm57109_opcode_name(u8 op) {
  switch (op) {
  case 0x00:
    return "0";
  case 0x01:
    return "1";
  case 0x02:
    return "2";
  case 0x03:
    return "3";
  case 0x04:
    return "4";
  case 0x05:
    return "5";
  case 0x06:
    return "6";
  case 0x07:
    return "7";
  case 0x08:
    return "8";
  case 0x09:
    return "9";
  case 0x0A:
    return "DP";
  case 0x0B:
    return "EE";
  case 0x0C:
    return "CS";
  case 0x0D:
    return "PI";
  case 0x0E:
    return "AIN";
  case 0x0F:
    return "HALT";
  case 0x10:
    return "TJC*";
  case 0x11:
    return "TX=0*";
  case 0x12:
    return "TXLTO*";
  case 0x13:
    return "TXF*";
  case 0x14:
    return "TERR*";
  case 0x15:
    return "JMP*";
  case 0x16:
    return "OUT*";
  case 0x17:
    return "IN*";
  case 0x18:
    return "SMDC";
  case 0x19:
    return "IBNZ*";
  case 0x1A:
    return "DBNZ*";
  case 0x1B:
    return "XEM";
  case 0x1C:
    return "MS";
  case 0x1D:
    return "MR";
  case 0x1E:
    return "LSH";
  case 0x1F:
    return "RSH";
  case 0x20:
    return "INV*/SPACE?";
  case 0x21:
    return "EN";
  case 0x22:
    return "TOGM";
  case 0x23:
    return "ROLL";
  case 0x24:
    return "SIN";
  case 0x25:
    return "COS";
  case 0x26:
    return "TAN";
  case 0x27:
    return "SF1";
  case 0x28:
    return "PF1";
  case 0x29:
    return "SF2";
  case 0x2A:
    return "PF2";
  case 0x2B:
    return "ECLR";
  case 0x2C:
    return "RTD";
  case 0x2D:
    return "DTR";
  case 0x2E:
    return "POP";
  case 0x2F:
    return "MCLR";
  case 0x30:
    return "XEY";
  case 0x31:
    return "EX";
  case 0x32:
    return "10X";
  case 0x33:
    return "SQ";
  case 0x34:
    return "SQRT";
  case 0x35:
    return "LN";
  case 0x36:
    return "LOG";
  case 0x37:
    return "1/X";
  case 0x38:
    return "YX";
  case 0x39:
    return "+";
  case 0x3A:
    return "-";
  case 0x3B:
    return "x";
  case 0x3C:
    return "/";
  case 0x3D:
    return "PRW1";
  case 0x3E:
    return "PRW2";
  case 0x3F:
    return "NOP/ACK";
  default:
    return "UNK";
  }
}

static const char *mm57109_inv_second_name(u8 op) {
  switch (op) {
  case 0x24:
    return "SIN-1*";
  case 0x25:
    return "COS-1*";
  case 0x26:
    return "TAN-1*";
  case 0x39:
    return "M+*";
  case 0x3A:
    return "M-*";
  case 0x3B:
    return "MX*";
  case 0x3C:
    return "M/*";
  default:
    return "UNK";
  }
}


#include "logmacro.h"

namespace {

class psicomp80_state : public driver_device {
public:
  psicomp80_state(const machine_config &mconfig, device_type type,
                  const char *tag)
      : driver_device(mconfig, type, tag), m_cpu(*this, "maincpu"),
        m_vram(*this, "vram"), m_keyboard(*this, "keyboard"),
        m_cassette(*this, "cassette"), m_fdc(*this, "fdc"),
        m_floppy(*this, "fdc:0") {}

  void psicomp80(machine_config &config);
  void psicomp80x(machine_config &config);

private:
  // -------- VDU geometry --------
  static constexpr int kCols = 64;
  static constexpr int kCharW = 6;  // 5 pixels + 1 spacer
  static constexpr int kCharH = 10; // 8 rows from generator + 2 blank

  // Visible text rows: 32 (as per your observation/expectation).
  // VRAM is 2 KiB, so this uses the first 32*32 = 1024 bytes.
  static constexpr int kRowsVisible = 32;

  static constexpr int kWidth = kCols * kCharW;         // 192
  static constexpr int kHeight = kRowsVisible * kCharH; // 320

  // devices/memory
  required_device<z80_device> m_cpu;
  required_shared_ptr<u8> m_vram;
  required_device<generic_keyboard_device> m_keyboard;
  required_device<cassette_image_device> m_cassette;
  required_device<fd1771_device> m_fdc;
  required_device<floppy_connector> m_floppy;

  // Interrupt controller (Oct 1980 Fig. 3): a 74LS147 priority encoder puts a
  // mode 2 vector on the bus. DRQ is input 9 (F3), INTRQ input 8 (F1); the
  // MM57109 is moved to a spare input (we use 1, E3). In IM1 the vector is
  // ignored, so the monitor's MM57109 handling is unchanged.
  bool m_irq_mm_line = false;   // MM57109 R/W: a digit is waiting
  bool m_fdc_intrq = false;
  bool m_fdc_drq = false;
  // The FD1771 does a RESTORE when it is reset, which leaves INTRQ set until
  // its status is read. The monitor and BURP never touch the controller, and
  // BURP's IM 1 handler takes every interrupt for an MM57109 digit, so the
  // controller's interrupts only reach the Z80 once software has used it
  // since the last reset. The disc software reads the status first.
  bool m_fdc_used = false;
  void update_irq();
  IRQ_CALLBACK_MEMBER(irq_ack);

  // ROM is mapped read-only (like real hardware)

  // keyboard latch returned by port 01h (ROM does IN then CPL)
  u8 m_key_latch = 0xff;

  attotime m_key_time;

  // tape input after the Schmitt trigger (idle=1); held between crossings
  u8 m_tape_in = 1;


  // --- MM57109 calculator chip (BURP does its arithmetic on it) ---
  // Port 60 drives its instruction lines (bits 0-5) and HOLD (bit 7); port 03
  // reads RDY (bit 5: 1 while it executes), BR (bit 6: 0 when a test is true)
  // and its digit outputs (bits 0-3). Its R/W output, pulsed once for each
  // digit of an OUT instruction, is the Z80's INT.
  enum : u8 { MM_WORD2_NONE, MM_WORD2_IGNORE, MM_WORD2_SMDC, MM_WORD2_INV };
  enum : u8 { MM_THEN_READY, MM_THEN_WORD2, MM_THEN_BRANCH_TRUE, MM_THEN_BRANCH_FALSE };
  double m_mm_x = 0.0, m_mm_y = 0.0, m_mm_z = 0.0, m_mm_t = 0.0, m_mm_m = 0.0;
  bool m_mm_sci = false;        // TOGM: scientific notation for IN and OUT
  u8 m_mm_mdc = 8;              // mantissa digits for IN and OUT (SMDC)
  bool m_mm_error = false;
  bool m_mm_hold = true;
  bool m_mm_busy = false;       // executing an instruction: RDY low
  bool m_mm_br = false;         // a test was true: BR low
  u8 m_mm_word2 = MM_WORD2_NONE;      // what the next word is for
  u8 m_mm_then = MM_THEN_READY;       // what happens when the instruction ends
  u8 m_mm_then_word2 = MM_WORD2_NONE;
  u8 m_mm_code = 0;             // digit outputs
  u8 m_mm_digits[12];           // OUT: digits still to come
  u8 m_mm_ndigits = 0, m_mm_digit_pos = 0;
  // number entry (digits, DP, EE and CS instructions)
  bool m_mm_entry = false;      // in number entry
  bool m_mm_after_enter = false;// the last instruction was EN
  bool m_mm_en_exp = false, m_mm_en_dp = false;
  u8 m_mm_en_dp_index = 0;
  u8 m_mm_en_mant[8], m_mm_en_nmant = 0;
  u8 m_mm_en_expd[2], m_mm_en_nexp = 0;
  s8 m_mm_en_mant_sign = 1, m_mm_en_exp_sign = 1;
  emu_timer *m_mm_exec_timer = nullptr;
  emu_timer *m_mm_digit_timer = nullptr;

  // -------- character generator tables --------
  // Each glyph: 8 rows, 5 bits per row (packed in bits 0..4).
  // Table is indexed as ASCII 0x20..0x5F mapped to 0..63.
  static const std::array<std::array<u8, 8>, 64> ascii_font_64x8x5;

  // Placeholder graphics font (fill later)
  static std::array<std::array<u8, 10>, 64> gfx_font_64x10x6;

  // maps
  void mem_map(address_map &map);
  void mem_map_32k(address_map &map);
  void io_map(address_map &map);

  // I/O handlers
  u8 port00_r();
  u8 port01_r();
  u8 port03_r();
  void port20_w(u8 data);
  void port60_w(u8 data);

  // keyboard -> latch and NMI
  void kbd_put(u8 data);
  // display
  u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap,
                    const rectangle &cliprect);

  // MM57109 model
  void mm57109_reset();
  void mm57109_execute(u8 op);
  void mm57109_second_word(u8 kind, u8 op);
  void mm57109_finish(u32 microcycles, u8 then = MM_THEN_READY, u8 word2 = MM_WORD2_NONE);
  double mm57109_round(double v);
  void mm57109_push(double v);
  void mm57109_pop();
  void mm57109_entry_clear();
  double mm57109_entry_value() const;
  void mm57109_out_digits();
  TIMER_CALLBACK_MEMBER(mm57109_exec_done);
  TIMER_CALLBACK_MEMBER(mm57109_digit_tick);

  static u8 glyph_row(u8 vram_byte, int row); // returns 5-bit pattern

protected:
  virtual void machine_start() override;
  virtual void machine_reset() override;
};

// ------------------ Base ASCII font subset (0x20-0x5F) ------------------
static constexpr std::array<u8, 8> BLANK = {0, 0, 0, 0, 0, 0, 0, 0};

const std::array<std::array<u8, 8>, 64> psicomp80_state::ascii_font_64x8x5 = {{
    /* 0x20 ' ' */ BLANK,
    /* 0x21 '!' */ {0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04, 0x00},
    /* 0x22 '"' */ {0x0A, 0x0A, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00},
    /* 0x23 '#' */ {0x0A, 0x0A, 0x1F, 0x0A, 0x1F, 0x0A, 0x0A, 0x00},
    /* 0x24 '$' */ {0x04, 0x0F, 0x14, 0x0E, 0x05, 0x1E, 0x04, 0x00},
    /* 0x25 '%' */ {0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03, 0x00},
    /* 0x26 '&' */ {0x0C, 0x12, 0x14, 0x08, 0x15, 0x12, 0x0D, 0x00},
    /* 0x27 apostrophe */ {0x06, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00},
    /* 0x28 '(' */ {0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02, 0x00},
    /* 0x29 ')' */ {0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08, 0x00},
    /* 0x2A '*' */ {0x00, 0x0A, 0x04, 0x1F, 0x04, 0x0A, 0x00, 0x00},
    /* 0x2B '+' */ {0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00, 0x00},
    /* 0x2C ',' */ {0x00, 0x00, 0x00, 0x00, 0x06, 0x04, 0x08, 0x00},
    /* 0x2D '-' */ {0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00, 0x00},
    /* 0x2E '.' */ {0x00, 0x00, 0x00, 0x00, 0x00, 0x06, 0x06, 0x00},
    /* 0x2F '/' */ {0x01, 0x02, 0x04, 0x08, 0x10, 0x00, 0x00, 0x00},

    /* 0x30 '0' */ {0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E, 0x00},
    /* 0x31 '1' */ {0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E, 0x00},
    /* 0x32 '2' */ {0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F, 0x00},
    /* 0x33 '3' */ {0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E, 0x00},
    /* 0x34 '4' */ {0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02, 0x00},
    /* 0x35 '5' */ {0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E, 0x00},
    /* 0x36 '6' */ {0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E, 0x00},
    /* 0x37 '7' */ {0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08, 0x00},
    /* 0x38 '8' */ {0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E, 0x00},
    /* 0x39 '9' */ {0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C, 0x00},
    /* 0x3A ':' */ {0x00, 0x06, 0x06, 0x00, 0x06, 0x06, 0x00, 0x00},
    /* 0x3B ';' */ {0x00, 0x06, 0x06, 0x00, 0x06, 0x04, 0x08, 0x00},
    /* 0x3C '<' */ {0x02, 0x04, 0x08, 0x10, 0x08, 0x04, 0x02, 0x00},
    /* 0x3D '=' */ {0x00, 0x00, 0x1F, 0x00, 0x1F, 0x00, 0x00, 0x00},
    /* 0x3E '>' */ {0x08, 0x04, 0x02, 0x01, 0x02, 0x04, 0x08, 0x00},
    /* 0x3F '?' */ {0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04, 0x00},

    /* 0x40 '@' */ {0x0E, 0x11, 0x1D, 0x15, 0x1D, 0x10, 0x0E, 0x00},
    /* 0x41 'A' */ {0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11, 0x00},
    /* 0x42 'B' */ {0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E, 0x00},
    /* 0x43 'C' */ {0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E, 0x00},
    /* 0x44 'D' */ {0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C, 0x00},
    /* 0x45 'E' */ {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F, 0x00},
    /* 0x46 'F' */ {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10, 0x00},
    /* 0x47 'G' */ {0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0E, 0x00},
    /* 0x48 'H' */ {0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11, 0x00},
    /* 0x49 'I' */ {0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E, 0x00},
    /* 0x4A 'J' */ {0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C, 0x00},
    /* 0x4B 'K' */ {0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11, 0x00},
    /* 0x4C 'L' */ {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F, 0x00},
    /* 0x4D 'M' */ {0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11, 0x00},
    /* 0x4E 'N' */ {0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11, 0x00},
    /* 0x4F 'O' */ {0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E, 0x00},

    /* 0x50 'P' */ {0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10, 0x00},
    /* 0x51 'Q' */ {0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D, 0x00},
    /* 0x52 'R' */ {0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11, 0x00},
    /* 0x53 'S' */ {0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E, 0x00},
    /* 0x54 'T' */ {0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x00},
    /* 0x55 'U' */ {0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E, 0x00},
    /* 0x56 'V' */ {0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04, 0x00},
    /* 0x57 'W' */ {0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11, 0x00},
    /* 0x58 'X' */ {0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11, 0x00},
    /* 0x59 'Y' */ {0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04, 0x00},
    /* 0x5A 'Z' */ {0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F, 0x00},
    /* 0x5B '[' */ {0x0E, 0x08, 0x08, 0x08, 0x08, 0x08, 0x0E, 0x00},
    /* 0x5C '\' */ {0x10, 0x08, 0x04, 0x02, 0x01, 0x00, 0x00, 0x00},
    /* 0x5D ']' */ {0x0E, 0x02, 0x02, 0x02, 0x02, 0x02, 0x0E, 0x00},
    /* 0x5E '^' */ {0x04, 0x0A, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00},
    /* 0x5F '_' */ {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x00},
}};

// Graphics character set: 64 tiles, native 6x10 pixels (no inter-character gap).
// Each entry is 10 rows; each row is 6 bits wide (bit5 = leftmost pixel, bit0 = rightmost).
// Values must be in the range 0x00..0x3f.
std::array<std::array<u8, 10>, 64> psicomp80_state::gfx_font_64x10x6 = {{
	/* 0x00 */ {0x2A,0x15,0x2A,0x15,0x2A,0x15,0x2A,0x15,0x2A,0x15}, // @
	/* 0x01 */ {0x38,0x38,0x38,0x38,0x38,0x00,0x00,0x00,0x00,0x00}, // A
	/* 0x02 */ {0x07,0x07,0x07,0x07,0x07,0x00,0x00,0x00,0x00,0x00}, // B
	/* 0x03 */ {0x3F,0x3F,0x3F,0x3F,0x3F,0x00,0x00,0x00,0x00,0x00}, // C
	/* 0x04 */ {0x00,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x07}, // D
	/* 0x05 */ {0x38,0x38,0x38,0x38,0x38,0x07,0x07,0x07,0x07,0x07}, // E
	/* 0x06 */ {0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07}, // F
	/* 0x07 */ {0x3F,0x3F,0x3F,0x3F,0x3F,0x07,0x07,0x07,0x07,0x07}, // G
	/* 0x08 */ {0x00,0x00,0x00,0x00,0x00,0x38,0x38,0x38,0x38,0x38}, // H
	/* 0x09 */ {0x38,0x38,0x38,0x38,0x38,0x38,0x38,0x38,0x38,0x38}, // I
	/* 0x0A */ {0x07,0x07,0x07,0x07,0x07,0x38,0x38,0x38,0x38,0x38}, // J
	/* 0x0B */ {0x3F,0x3F,0x3F,0x3F,0x3F,0x38,0x38,0x38,0x38,0x38}, // K
	/* 0x0C */ {0x00,0x00,0x00,0x00,0x00,0x3F,0x3F,0x3F,0x3F,0x3F}, // L
	/* 0x0D */ {0x38,0x38,0x38,0x38,0x38,0x3F,0x3F,0x3F,0x3F,0x3F}, // M
	/* 0x0E */ {0x07,0x07,0x07,0x07,0x07,0x3F,0x3F,0x3F,0x3F,0x3F}, // N
	/* 0x0F */ {0x3F,0x3F,0x3F,0x3F,0x3F,0x3F,0x3F,0x3F,0x3F,0x3F}, // O
	/* 0x10 */ {0x00,0x00,0x00,0x00,0x03,0x0C,0x10,0x10,0x20,0x20}, // P
	/* 0x11 */ {0x00,0x00,0x00,0x00,0x30,0x0C,0x02,0x02,0x01,0x01}, // Q
	/* 0x12 */ {0x01,0x01,0x02,0x02,0x0C,0x30,0x00,0x00,0x00,0x00}, // R
	/* 0x13 */ {0x20,0x20,0x10,0x10,0x0C,0x03,0x00,0x00,0x00,0x00}, // S
	/* 0x14 */ {0x00,0x00,0x00,0x00,0x03,0x0F,0x1F,0x1F,0x3F,0x3F}, // T
	/* 0x15 */ {0x00,0x00,0x00,0x00,0x30,0x3C,0x3E,0x3E,0x3F,0x3F}, // U
	/* 0x16 */ {0x3F,0x3F,0x3E,0x3E,0x3C,0x30,0x00,0x00,0x00,0x00}, // V
	/* 0x17 */ {0x3F,0x3F,0x1F,0x1F,0x0F,0x03,0x00,0x00,0x00,0x00}, // W
	/* 0x18 */ {0x01,0x03,0x03,0x07,0x07,0x0F,0x0F,0x1F,0x1F,0x3F}, // X
	/* 0x19 */ {0x20,0x30,0x30,0x38,0x38,0x3C,0x3C,0x3E,0x3E,0x3F}, // Y
	/* 0x1A */ {0x3F,0x3E,0x3E,0x3C,0x3C,0x38,0x38,0x30,0x30,0x20}, // Z
	/* 0x1B */ {0x3F,0x1F,0x1F,0x0F,0x0F,0x07,0x07,0x03,0x03,0x01}, // [
	/* 0x1C */ {0x3E,0x21,0x21,0x21,0x3E,0x21,0x21,0x21,0x21,0x3E}, // B of BURP
	/* 0x1D */ {0x21,0x21,0x21,0x21,0x21,0x21,0x21,0x21,0x21,0x3F}, // U of BURP
	/* 0x1E */ {0x3E,0x21,0x21,0x21,0x3E,0x22,0x21,0x21,0x21,0x21}, // R of BURP
	/* 0x1F */ {0x3E,0x21,0x21,0x21,0x3E,0x20,0x20,0x20,0x20,0x20}, // P of BURP here   
	/* 0x20 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, // Space
	/* 0x21 */ {0x00,0x00,0x00,0x00,0x0E,0x09,0x09,0x0E,0x08,0x08}, // p 
	/* 0x22 */ {0x00,0x00,0x08,0x08,0x09,0x0E,0x0A,0x09,0x00,0x00}, // k
	/* 0x23 */ {0x00,0x00,0x00,0x00,0x1A,0x15,0x15,0x15,0x00,0x00}, // hash key m
	/* 0x24 */ {0x00,0x06,0x09,0x08,0x1C,0x08,0x08,0x17,0x00,0x00}, // £ ($)
	/* 0x25 */ {0x00,0x00,0x00,0x14,0x28,0x28,0x14,0x00,0x00,0x00}, // %
	/* 0x26 */ {0x00,0x00,0x0C,0x12,0x1E,0x11,0x11,0x1E,0x10,0x10}, // &
	/* 0x27 */ {0x00,0x00,0x00,0x09,0x09,0x09,0x0F,0x0E,0x08,0x10}, // mu '
	/* 0x28 */ {0x00,0x00,0x00,0x0E,0x11,0x11,0x0A,0x1B,0x00,0x00}, // ohm {
	/* 0x29 */ {0x00,0x00,0x00,0x10,0x28,0x05,0x02,0x00,0x00,0x00}, // tilde }
	/* 0x2A */ {0x00,0x10,0x28,0x05,0x12,0x28,0x05,0x02,0x00,0x00}, // double tilde +
	/* 0x2B */ {0x2A,0x2A,0x2A,0x2A,0x2A,0x2A,0x2A,0x2A,0x2A,0x2A}, // 3 vertical bars +
	/* 0x2C */ {0x3F,0x00,0x3F,0x00,0x3F,0x00,0x3F,0x00,0x3F,0x00}, // 5 horizontal bars , (comma)
	/* 0x2D */ {0x00,0x00,0x00,0x0B,0x18,0x18,0x0B,0x00,0x00,0x00}, // alpha -
	/* 0x2E */ {0x30,0x30,0x18,0x18,0x0C,0x0C,0x06,0x06,0x03,0x03}, // backslash .   
	/* 0x2F */ {0x03,0x03,0x06,0x06,0x0C,0x0C,0x18,0x18,0x30,0x30}, // slash
	/* 0x30 */ {0x30,0x30,0x30,0x30,0x30,0x30,0x30,0x30,0x30,0x30}, //  Vertical bar left
	/* 0x31 */ {0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C}, //  Vertical bar middle
	/* 0x32 */ {0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03,0x03}, //  Vertical bar right
	/* 0x33 */ {0x3F,0x3F,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, //  Horizontal bar top 3
	/* 0x34 */ {0x00,0x00,0x3F,0x3F,0x00,0x00,0x00,0x00,0x00,0x00}, //  Horizontal bar 4
	/* 0x35 */ {0x00,0x00,0x00,0x00,0x3F,0x3F,0x00,0x00,0x00,0x00}, //  Horizontal bar 5
	/* 0x36 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x3F,0x3F,0x00,0x00}, //  Horizontal bar 6
	/* 0x37 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x3F,0x3F}, //  Horizontal bar 7
	/* 0x38 */ {0x04,0x0E,0x15,0x04,0x04,0x04,0x04,0x04,0x04,0x04}, // up arrow 8
	/* 0x39 */ {0x00,0x00,0x04,0x02,0x3F,0x02,0x04,0x00,0x00,0x00}, // Right arrow 9
	/* 0x3A */ {0x00,0x00,0x80,0x10,0x3F,0x10,0x80,0x00,0x00,0x00}, // Left arrow |
	/* 0x3B */ {0x04,0x04,0x04,0x04,0x04,0x15,0x0E,0x04,0x00,0x00}, // Down arrow ,
	/* 0x3C */ {0x30,0x30,0x30,0x30,0x30,0x0A,0x0E,0x06,0x0F,0x03}, // ?? <
	/* 0x3D */ {0x00,0x20,0x20,0x21,0x03,0x05,0x0F,0x01,0x00,0x00}, // ?? =
	/* 0x3E */ {0x30,0x30,0x30,0x30,0x30,0x04,0x0C,0x0E,0x0A,0x03}, // ?? >
	/* 0x3F */ {0x00,0x00,0x00,0x03,0x07,0x0C,0x30,0x30,0x30,0x30}, // ?? ?	
}};
// ------------------ machine lifecycle ------------------

void psicomp80_state::machine_start() {
  // Power on with a blank screen (the monitor never clears line 0, and code
  // 00h is @, not a space).
  std::fill_n(&m_vram[0], m_vram.bytes(), 0x20);

  m_mm_exec_timer = timer_alloc(FUNC(psicomp80_state::mm57109_exec_done), this);
  m_mm_digit_timer = timer_alloc(FUNC(psicomp80_state::mm57109_digit_tick), this);

  // 8in drives spin all the time; the FD1771 only loads the head.
  m_fdc->set_floppy(m_floppy->get_device());
  if (m_floppy->get_device())
    m_floppy->get_device()->mon_w(0);
  save_item(NAME(m_irq_mm_line));
  save_item(NAME(m_fdc_intrq));
  save_item(NAME(m_fdc_drq));
  save_item(NAME(m_fdc_used));

  save_item(NAME(m_key_latch));
  save_item(NAME(m_tape_in));
  save_item(NAME(m_key_time));

  save_item(NAME(m_mm_x));
  save_item(NAME(m_mm_y));
  save_item(NAME(m_mm_z));
  save_item(NAME(m_mm_t));
  save_item(NAME(m_mm_m));
  save_item(NAME(m_mm_sci));
  save_item(NAME(m_mm_mdc));
  save_item(NAME(m_mm_error));
  save_item(NAME(m_mm_hold));
  save_item(NAME(m_mm_busy));
  save_item(NAME(m_mm_br));
  save_item(NAME(m_mm_word2));
  save_item(NAME(m_mm_then));
  save_item(NAME(m_mm_then_word2));
  save_item(NAME(m_mm_code));
  save_item(NAME(m_mm_digits));
  save_item(NAME(m_mm_ndigits));
  save_item(NAME(m_mm_digit_pos));
  save_item(NAME(m_mm_entry));
  save_item(NAME(m_mm_after_enter));
  save_item(NAME(m_mm_en_exp));
  save_item(NAME(m_mm_en_dp));
  save_item(NAME(m_mm_en_dp_index));
  save_item(NAME(m_mm_en_mant));
  save_item(NAME(m_mm_en_nmant));
  save_item(NAME(m_mm_en_expd));
  save_item(NAME(m_mm_en_nexp));
  save_item(NAME(m_mm_en_mant_sign));
  save_item(NAME(m_mm_en_exp_sign));
}

void psicomp80_state::machine_reset() {
  m_key_latch = 0xff;
  m_fdc_used = false;
  mm57109_reset();
}

// ------------------ memory & I/O ------------------

// With the 32 KB memory expansion (used by the floppy disc FORMAT command,
// which builds a track image at C000). The articles don't give its address
// decoding; here it fills 8000-FFFF behind the screen, so 8800-FFFF is RAM
// and the screen no longer mirrors through the top half of memory.
void psicomp80_state::mem_map_32k(address_map &map) {
  map(0x0000, 0x0bff).rom();
  map(0x0c00, 0x1fff).ram();
  map(0x8000, 0x87ff).ram().share("vram");
  map(0x8800, 0xffff).ram();
}

void psicomp80_state::mem_map(address_map &map) {
  map(0x0000, 0x0bff).rom();
  map(0x0c00, 0x1fff).ram();

  map(0x8000, 0x87ff).mirror(0x7800).ram().share("vram");
}

void psicomp80_state::io_map(address_map &map) {
  map.global_mask(0xff);

  // Tape interface (digital)
  //   IN  ($00) bit0 : tape input level (idle=1)
  //   OUT ($20) bit7 : tape output level (bit7 first)
  map(0x00, 0x00).r(FUNC(psicomp80_state::port00_r));
  map(0x01, 0x01).r(FUNC(psicomp80_state::port01_r));
  map(0x03, 0x03).r(FUNC(psicomp80_state::port03_r));
  map(0x20, 0x20).w(FUNC(psicomp80_state::port20_w));
  map(0x60, 0x60).w(FUNC(psicomp80_state::port60_w));

  // Floppy disc controller (Oct 1980 Table 2): register select is A3/A4.
  //   IN 05/0D/15/1D = status/track/sector/data
  //   OUT A0/A8/B0/B8 = command/track/sector/data
  map(0x05, 0x05).select(0x18).lr8(NAME([this](offs_t o) { if (!machine().side_effects_disabled()) m_fdc_used = true; return m_fdc->read(o >> 3); }));
  map(0xa0, 0xa0).select(0x18).lw8(NAME([this](offs_t o, u8 d) { m_fdc_used = true; m_fdc->write(o >> 3, d); }));
}

void psicomp80_state::update_irq()
{
  const bool irq = m_irq_mm_line || (m_fdc_used && (m_fdc_intrq || m_fdc_drq));
  m_cpu->set_input_line(INPUT_LINE_IRQ0, irq ? ASSERT_LINE : CLEAR_LINE);
}

IRQ_CALLBACK_MEMBER(psicomp80_state::irq_ack)
{
  if (m_fdc_used && m_fdc_drq)
    return 0xf3;
  if (m_fdc_used && m_fdc_intrq)
    return 0xf1;
  // The MM57109's R/W interrupt is latched until the Z80 takes it. (Clearing
  // it when port 03 is read loses digits: BURP polls port 03 while the digits
  // come in, and a digit arriving during one of those INs would be cleared
  // before the Z80 could take it.)
  m_irq_mm_line = false;
  update_irq();
  return 0xe3;
}

u8 psicomp80_state::port00_r()
{
  // Firmware masks bit 0 (AND 1) and treats idle as 1.
  //
  // Use MAME cassette image device so the user can control play/record
  // and swap images at runtime (TAB → File Manager / Tape Control).
  //
  // If not playing, present idle high.
  const int state = m_cassette->get_state();
  if ((state & CASSETTE_MASK_UISTATE) != CASSETTE_PLAY)
  {
    m_tape_in = 1;
    return 0x01;
  }

  // Schmitt trigger: only change level on a clear crossing so silence
  // (blank tape, end of image) holds the last level instead of reading as a
  // stream of start bits.
  const double level = m_cassette->input(); // -1.0 .. +1.0
  if (level > 0.25)
    m_tape_in = 1;
  else if (level < -0.25)
    m_tape_in = 0;
  return m_tape_in;
}


void psicomp80_state::port20_w(u8 data)
{
  // Cassette output is bit 7 of the data bus (D7), bit7-first.
  // Only drive output when recording.
  const int state = m_cassette->get_state();
  if ((state & CASSETTE_MASK_UISTATE) != CASSETTE_RECORD)
    return;

  const double out = (data & 0x80) ? +1.0 : -1.0;
  m_cassette->output(out);
}


u8 psicomp80_state::port01_r() {
  const u8 v = m_key_latch;
  m_key_latch = 0xff;
  return v;
}

u8 psicomp80_state::port03_r() {
  // RDY (bit 5) and BR (bit 6) as the ROM sees them, and the digit outputs.
  return (m_mm_busy ? 0x20 : 0x00) | (m_mm_br ? 0x00 : 0x40) | (m_mm_code & 0x0f);
}

// ---------------------------------------------------------------------------
// MM57109 model
//
// The Z80 sends an instruction by putting it on port 60 with HOLD (bit 7)
// low: the chip fetches it and RDY goes low (port 03 bit 5 reads 1). BURP
// then raises HOLD, so the chip stops when the instruction has finished and
// RDY comes back. Two-word instructions (INV, SMDC, OUT, IN and the
// branches) take their second word the same way. A branch whose test is true
// pulses BR and waits for its second word (BURP sends a NOP); a false one
// skips it. OUT puts out twelve digits, each with a R/W pulse that interrupts
// the Z80 (IM 1, handler at 0038), before it is ready for its second word.
// Execution times are the data sheet's averages; a microcycle is about 10 us.
// Results are rounded to the chip's 8 significant digits.
// ---------------------------------------------------------------------------

// Execution times in microcycles, by opcode.
static const u16 mm57109_exec_time[64] = {
  238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 152, 151, 166, 1312, 284, 134,       // 0-9 DP EE CS PI AIN HALT
  208, 278, 197, 271, 191, 186, 583, 395, 163, 2314, 2314, 812, 839, 1385, 168, 173,     // TJC .. RSH
  166, 552, 157, 905, 56200, 56200, 35000, 163, 185, 163, 185, 163, 30700, 30700, 448, 734,   // INV EN TOGM ROLL SIN COS TAN flags ECLR RTD DTR POP MCLR
  652, 30800, 27400, 3000, 7000, 24800, 30700, 4500, 55400, 2200, 2200, 3200, 7800, 130, 130, 122  // XEY EX 10X SQ SQRT LN LOG 1/X YX + - x / PRW1 PRW2 NOP
};

void psicomp80_state::mm57109_reset() {
  m_mm_x = m_mm_y = m_mm_z = m_mm_t = m_mm_m = 0.0;
  m_mm_sci = false;
  m_mm_mdc = 8;
  m_mm_error = false;
  m_mm_hold = true;
  m_mm_busy = false;
  m_mm_br = false;
  m_mm_word2 = MM_WORD2_NONE;
  m_mm_then = MM_THEN_READY;
  m_mm_then_word2 = MM_WORD2_NONE;
  m_mm_code = 0;
  m_mm_ndigits = m_mm_digit_pos = 0;
  m_mm_entry = false;
  m_mm_after_enter = false;
  mm57109_entry_clear();
  m_irq_mm_line = false;
  if (m_mm_exec_timer)
    m_mm_exec_timer->adjust(attotime::never);
  if (m_mm_digit_timer)
    m_mm_digit_timer->adjust(attotime::never);
  update_irq();
}

void psicomp80_state::mm57109_entry_clear() {
  m_mm_en_exp = m_mm_en_dp = false;
  m_mm_en_dp_index = 0;
  m_mm_en_nmant = m_mm_en_nexp = 0;
  m_mm_en_mant_sign = m_mm_en_exp_sign = 1;
}

double psicomp80_state::mm57109_entry_value() const {
  double mant = 0.0;
  for (int i = 0; i < m_mm_en_nmant; i++)
    mant = mant * 10.0 + m_mm_en_mant[i];
  const int dp = m_mm_en_dp ? m_mm_en_dp_index : m_mm_en_nmant;
  double v = mant * std::pow(10.0, double(dp - m_mm_en_nmant)) * m_mm_en_mant_sign;
  if (m_mm_en_nexp) {
    int e = 0;
    for (int i = 0; i < m_mm_en_nexp; i++)
      e = e * 10 + m_mm_en_expd[i];
    v *= std::pow(10.0, double(e * m_mm_en_exp_sign));
  }
  return v;
}

// Round to 8 significant digits; the exponent must stay within +-99.
double psicomp80_state::mm57109_round(double v) {
  if (!std::isfinite(v)) {
    m_mm_error = true;
    return 0.0;
  }
  if (v == 0.0)
    return 0.0;
  char buf[32];
  snprintf(buf, sizeof(buf), "%.7e", v);
  const double r = strtod(buf, nullptr);
  const int e = int(std::floor(std::log10(std::fabs(r))));
  if (e > 99) {
    m_mm_error = true;
    return r < 0.0 ? -9.9999999e99 : 9.9999999e99;
  }
  if (e < -99)
    return 0.0;
  return r;
}

void psicomp80_state::mm57109_push(double v) {
  m_mm_t = m_mm_z;
  m_mm_z = m_mm_y;
  m_mm_y = m_mm_x;
  m_mm_x = v;
}

// Drop Y (after a two-operand operation has put its result in X).
void psicomp80_state::mm57109_pop() {
  m_mm_y = m_mm_z;
  m_mm_z = m_mm_t;
}

// OUT in scientific notation: exponent tens and units, the signs (8:
// mantissa, 1: exponent), the decimal point position (0Bh: after the first
// digit, which the ROM turns into 1), then the mantissa digits.
void psicomp80_state::mm57109_out_digits() {
  const double x = mm57109_round(m_mm_x);
  int e = 0;
  char mant[9] = "00000000";
  if (x != 0.0) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%.7e", std::fabs(x));  // d.ddddddde+XX
    mant[0] = buf[0];
    memcpy(mant + 1, buf + 2, 7);
    e = atoi(strchr(buf, 'e') + 1);
  }
  const int ae = std::min(std::abs(e), 99);
  u8 n = 0;
  m_mm_digits[n++] = ae / 10;
  m_mm_digits[n++] = ae % 10;
  m_mm_digits[n++] = (x < 0.0 ? 0x08 : 0x00) | (e < 0 ? 0x01 : 0x00);
  m_mm_digits[n++] = 0x0b;
  for (int i = 0; i < m_mm_mdc && i < 8; i++)
    m_mm_digits[n++] = mant[i] - '0';
  m_mm_ndigits = n;
  m_mm_digit_pos = 0;
}

// The instruction ends after the given time; then decides what follows.
void psicomp80_state::mm57109_finish(u32 microcycles, u8 then, u8 word2) {
  m_mm_then = then;
  m_mm_then_word2 = word2;
  m_mm_exec_timer->adjust(attotime::from_usec(microcycles * 10));
}

TIMER_CALLBACK_MEMBER(psicomp80_state::mm57109_exec_done) {
  switch (m_mm_then) {
  case MM_THEN_WORD2:         // ready for the second word
    m_mm_busy = false;
    m_mm_word2 = m_mm_then_word2;
    break;
  case MM_THEN_BRANCH_TRUE:   // BR low, and wait for the second word
    m_mm_br = true;
    m_mm_word2 = MM_WORD2_IGNORE;
    break;
  default:                    // done (a false branch skips its second word)
    m_mm_busy = false;
    break;
  }
}

// OUT: one digit per R/W pulse, then ready for the second word.
TIMER_CALLBACK_MEMBER(psicomp80_state::mm57109_digit_tick) {
  if (m_mm_digit_pos < m_mm_ndigits) {
    m_mm_code = m_mm_digits[m_mm_digit_pos++];
    m_irq_mm_line = true;
    update_irq();
    m_mm_digit_timer->adjust(attotime::from_usec(48 * 10));
  } else {
    m_mm_busy = false;
    m_mm_word2 = MM_WORD2_IGNORE;
  }
}

void psicomp80_state::port60_w(u8 data) {
  m_mm_hold = BIT(data, 7);
  if (m_mm_hold)
    return;
  const u8 op = data & 0x3f;
  if (m_mm_word2 != MM_WORD2_NONE) {
    const u8 kind = m_mm_word2;
    m_mm_word2 = MM_WORD2_NONE;
    m_mm_busy = true;
    m_mm_br = false;
    mm57109_second_word(kind, op);
    return;
  }
  if (m_mm_busy)
    return;
  m_mm_busy = true;
  m_mm_br = false;
  mm57109_execute(op);
}

void psicomp80_state::mm57109_second_word(u8 kind, u8 op) {
  const double x = m_mm_x;
  u32 t = 130;
  if (kind == MM_WORD2_SMDC) {
    if (op >= 1 && op <= 8)
      m_mm_mdc = op;
  } else if (kind == MM_WORD2_INV) {
    LOGMASKED(LOG_MM57109, "MM57109: %s X=%g M=%g\n", mm57109_inv_second_name(op), m_mm_x, m_mm_m);
    switch (op) {
    case 0x24: if (x < -1.0 || x > 1.0) m_mm_error = true; else m_mm_x = mm57109_round(std::asin(x)); t = 54000; break;
    case 0x25: if (x < -1.0 || x > 1.0) m_mm_error = true; else m_mm_x = mm57109_round(std::acos(x)); t = 54000; break;
    case 0x26: m_mm_x = mm57109_round(std::atan(x)); t = 30200; break;
    case 0x39: m_mm_m = mm57109_round(m_mm_m + x); t = 1700; break;
    case 0x3a: m_mm_m = mm57109_round(m_mm_m - x); t = 1700; break;
    case 0x3b: m_mm_m = mm57109_round(m_mm_m * x); t = 2700; break;
    case 0x3c: if (x == 0.0) m_mm_error = true; else m_mm_m = mm57109_round(m_mm_m / x); t = 7300; break;
    default: break;
    }
  }
  mm57109_finish(t);
}

void psicomp80_state::mm57109_execute(u8 op) {
  const u32 t = mm57109_exec_time[op & 0x3f];
  LOGMASKED(LOG_MM57109, "MM57109: %02X %-6s X=%g Y=%g M=%g\n", op, mm57109_opcode_name(op), m_mm_x, m_mm_y, m_mm_m);

  // Any instruction but the number entry ones (00-0F) ends number entry.
  if (m_mm_entry && op > 0x0f) {
    m_mm_x = mm57109_round(mm57109_entry_value());
    m_mm_entry = false;
  }
  const bool after_enter = m_mm_after_enter;
  m_mm_after_enter = false;
  // Starting number entry pushes the stack (unless the last instruction was
  // EN) and clears X.
  auto start_entry = [&]() {
    if (m_mm_entry)
      return;
    if (after_enter)
      m_mm_x = 0.0;
    else
      mm57109_push(0.0);
    m_mm_entry = true;
    mm57109_entry_clear();
  };
  const double x = m_mm_x, y = m_mm_y;
  auto fn = [&](double v, bool bad = false) {
    if (bad) {
      m_mm_error = true;
      m_mm_x = 0.0;
    } else
      m_mm_x = mm57109_round(v);
  };
  auto two = [&](double v) {
    const double r = mm57109_round(v);
    mm57109_pop();
    m_mm_x = r;
  };
  auto branch = [&](bool cond) {
    mm57109_finish(t, cond ? MM_THEN_BRANCH_TRUE : MM_THEN_BRANCH_FALSE);
  };

  switch (op) {
  case 0x0a: // DP
    start_entry();
    if (!m_mm_en_dp) {
      m_mm_en_dp = true;
      m_mm_en_dp_index = m_mm_en_nmant;
    }
    break;
  case 0x0b: // EE
    start_entry();
    m_mm_en_exp = true;
    break;
  case 0x0c: // CS
    if (!m_mm_entry) {
      m_mm_x = -m_mm_x;
      break;
    }
    if (m_mm_en_exp)
      m_mm_en_exp_sign = -m_mm_en_exp_sign;
    else
      m_mm_en_mant_sign = -m_mm_en_mant_sign;
    m_mm_x = mm57109_entry_value();
    break;
  case 0x0d: { // PI
    start_entry();
    static const u8 pi[8] = { 3, 1, 4, 1, 5, 9, 2, 7 };
    memcpy(m_mm_en_mant, pi, 8);
    m_mm_en_nmant = 8;
    m_mm_en_dp = true;
    m_mm_en_dp_index = 1;
    m_mm_x = M_PI;
    break;
  }
  case 0x0e: start_entry(); break;                     // AIN: no digit input lines here
  case 0x0f: break;                                    // HALT: a NOP that doesn't end number entry
  case 0x10: branch(false); return;                    // TJC: the JC input isn't connected
  case 0x11: branch(x == 0.0); return;                 // TX=0
  case 0x12: branch(x < 0.0); return;                  // TXLT0
  case 0x13: branch(std::fabs(x) < 1.0); return;       // TXF
  case 0x14: branch(m_mm_error); return;               // TERR
  case 0x15: branch(true); return;                     // JMP
  case 0x16:                                           // OUT
    mm57109_out_digits();
    m_mm_digit_timer->adjust(attotime::from_usec(40 * 10));
    return;
  case 0x17: mm57109_finish(t, MM_THEN_WORD2, MM_WORD2_IGNORE); return;   // IN: no digit input
  case 0x18: mm57109_finish(t, MM_THEN_WORD2, MM_WORD2_SMDC); return;     // SMDC
  case 0x19: m_mm_m = mm57109_round(m_mm_m + 1.0); branch(m_mm_m != 0.0); return;  // IBNZ
  case 0x1a: m_mm_m = mm57109_round(m_mm_m - 1.0); branch(m_mm_m != 0.0); return;  // DBNZ
  case 0x1b: m_mm_x = m_mm_m; m_mm_m = x; break;       // XEM
  case 0x1c: m_mm_m = x; break;                        // MS
  case 0x1d: mm57109_push(m_mm_m); break;              // MR
  case 0x1e: fn(x * 10.0); break;                      // LSH
  case 0x1f: fn(x / 10.0); break;                      // RSH
  case 0x20: mm57109_finish(t, MM_THEN_WORD2, MM_WORD2_INV); return;      // INV
  case 0x21: mm57109_push(x); m_mm_after_enter = true; break;              // EN
  case 0x22: m_mm_sci = !m_mm_sci; break;              // TOGM
  case 0x23: {                                         // ROLL
    const double old_x = m_mm_x;
    m_mm_x = m_mm_y;
    m_mm_y = m_mm_z;
    m_mm_z = m_mm_t;
    m_mm_t = old_x;
    break;
  }
  case 0x24: fn(std::sin(x)); break;
  case 0x25: fn(std::cos(x)); break;
  case 0x26: fn(std::tan(x)); break;
  case 0x2b: m_mm_error = false; break;                // ECLR
  case 0x2c: fn(x * 180.0 / M_PI); break;              // RTD
  case 0x2d: fn(x * M_PI / 180.0); break;              // DTR
  case 0x2e: m_mm_x = y; mm57109_pop(); break;         // POP
  case 0x2f:                                           // MCLR
    m_mm_x = m_mm_y = m_mm_z = m_mm_t = m_mm_m = 0.0;
    m_mm_error = false;
    break;
  case 0x30: m_mm_x = y; m_mm_y = x; break;            // XEY
  case 0x31: fn(std::exp(x)); break;
  case 0x32: fn(std::pow(10.0, x)); break;
  case 0x33: fn(x * x); break;
  case 0x34: fn(std::sqrt(std::fabs(x)), x < 0.0); break;
  case 0x35: fn(x > 0.0 ? std::log(x) : 0.0, x <= 0.0); break;
  case 0x36: fn(x > 0.0 ? std::log10(x) : 0.0, x <= 0.0); break;
  case 0x37: fn(x != 0.0 ? 1.0 / x : 0.0, x == 0.0); break;
  case 0x38:                                           // YX
    if (y < 0.0 && x != std::floor(x)) {
      m_mm_error = true;
      two(0.0);
    } else
      two(std::pow(y, x));
    break;
  case 0x39: two(y + x); break;
  case 0x3a: two(y - x); break;
  case 0x3b: two(y * x); break;
  case 0x3c:
    if (x == 0.0) {
      m_mm_error = true;
      two(0.0);
    } else
      two(y / x);
    break;
  default:
    if (op <= 0x09) {                                  // digits
      start_entry();
      if (!m_mm_en_exp) {
        if (m_mm_en_nmant < 8)
          m_mm_en_mant[m_mm_en_nmant++] = op;
      } else if (m_mm_en_nexp < 2)
        m_mm_en_expd[m_mm_en_nexp++] = op;
      m_mm_x = mm57109_entry_value();
    }
    // NOP, the flag and R/W pulse instructions change nothing here
    break;
  }
  mm57109_finish(t);
}

// ---------------------------------------------------------------------------
// ------------------ keyboard / interrupts ------------------

void psicomp80_state::kbd_put(u8 data) {
  // The real COMP80 has a dedicated RESET key. For convenience in the
  // emulation, bind that to the host ESC key.
  //
  // generic_keyboard_device delivers character codes; ESC arrives as 0x1B.
  if (data == 0x1b) {
    machine().schedule_soft_reset();
    return;
  }

  // With the FORTH and LISP ROMs, RS (^) is rubout, but the monitor's NMI
  // handler folds Backspace (08h) into the same code as H.  Let the host
  // Backspace key send RS instead.
  if (data == 0x08 && system_bios() >= 2)
    data = 0x1e;

  // The COMP80 keyboard interface is a latched ASCII byte with a single strobe
  // to NMI. The monitor's NMI routine will reset if NMI arrives while the CPU
  // is not in HALT, so we must avoid generating extra strobes (e.g. key-up
  // events / auto-repeat bursts). Treat 0x00 as "no character" and ignore it.
  if (data == 0x00)
    return;

  // Debounce / one-shot strobe: ignore further key events until the monitor
  // reads port 0x01 (port01_r clears m_key_latch back to 0xFF). Let it lapse
  // after a short time: a key that interrupts a running program (e.g. to end
  // READ) makes the NMI handler jump to 0000 without reading port 0x01, which
  // would otherwise leave the keyboard dead.
  if (m_key_latch != 0xff && machine().time() - m_key_time < attotime::from_msec(50))
    return;

  m_key_latch = ~data;
  m_key_time = machine().time();

  m_cpu->pulse_input_line(INPUT_LINE_NMI, attotime::zero);
}

// ------------------ character mapping / display ------------------

static inline u8 map_code6_to_ascii_index(u8 code6) {
  // Returns index into ascii_font_64x8x5 (0..63 corresponding to ASCII
  // 0x20..0x5F): codes 00h-1Fh are @, A-Z, [ \ ] ^ _ and 20h-3Fh are as ASCII.
  return code6 ^ 0x20;
}

u8 psicomp80_state::glyph_row(u8 vram_byte, int row) {
  const bool gfx = BIT(vram_byte, 6);
  const u8 code6 = vram_byte & 0x3f;

  if (gfx) {
    // Graphics tiles are native 6x10 (no external padding). Each row uses 6 bits
    // (bit5 = leftmost pixel).
    if (row < 0 || row >= 10)
      return 0x00;
    return gfx_font_64x10x6[code6][row] & 0x3f;
  }

  // ASCII characters come from a 2513-style 5x8 dot matrix (bit4 = leftmost pixel).
  // The display cell is 6x10, so the renderer adds the spacer column and extra scanlines.
  const u8 idx = map_code6_to_ascii_index(code6);
  if (row < 0 || row >= 8)
    return 0x00;
  return ascii_font_64x8x5[idx][row] & 0x1f;
}

u32 psicomp80_state::screen_update(screen_device &screen, bitmap_rgb32 &bitmap,
                                   const rectangle &cliprect) {
  const u32 bg = rgb_t::black();
  const u32 fg = rgb_t::white();

  bitmap.fill(bg, cliprect);

  for (int row = 0; row < kRowsVisible; row++) {
    for (int col = 0; col < kCols; col++) {
      const int index = row * kCols + col;
      const u8 vram = m_vram[index];
      const bool gfx = BIT(vram, 6);

      const int x0 = col * kCharW; // kCharW is the *cell* width (6)
      const int y0 = row * kCharH; // kCharH is the *cell* height (10)

      for (int y = 0; y < kCharH; y++) {
        const int py = y0 + y;
        if (py < cliprect.top() || py > cliprect.bottom())
          continue;

        const u8 bits = glyph_row(vram, y);

        for (int x = 0; x < kCharW; x++) {
          const int px = x0 + x;
          if (px < cliprect.left() || px > cliprect.right())
            continue;

          bool on = false;
          if (gfx) {
            // 6x10 graphics tile: bit5 leftmost, no implicit spacer.
            on = BIT(bits, 5 - x);
          } else {
            // 5x8 ASCII glyph: bit4 leftmost, with implicit spacer at x==5 and blank rows 8-9.
            if (x < 5)
              on = BIT(bits, 4 - x);
          }

          bitmap.pix(py, px) = on ? fg : bg;
        }
      }
    }
  }

  return 0;
}

// ------------------ machine config ------------------

static INPUT_PORTS_START(psicomp80) INPUT_PORTS_END

    void psicomp80_state::psicomp80(machine_config &config) {
  Z80(config, m_cpu, 4'000'000);
  m_cpu->set_addrmap(AS_PROGRAM, &psicomp80_state::mem_map);
  m_cpu->set_addrmap(AS_IO, &psicomp80_state::io_map);

  // Cassette: use the built-in cassette image device so the macOS UI shows
// "Tape Control" and "File Manager" entries.
CASSETTE(config, m_cassette);
m_cassette->set_formats(cassette_default_formats);
// No motor-control relay on the COMP80: the tape runs whenever play/record
// is selected. With the motor disabled MAME never advances the tape.
m_cassette->set_default_state(CASSETTE_STOPPED | CASSETTE_MOTOR_ENABLED);

  GENERIC_KEYBOARD(config, m_keyboard, 0);
  m_keyboard->set_keyboard_callback(FUNC(psicomp80_state::kbd_put));

  m_cpu->set_irq_acknowledge_callback(FUNC(psicomp80_state::irq_ack));

  // Floppy disc: FD1771 clocked at 2 MHz for an 8in drive
  FD1771(config, m_fdc, 2'000'000);
  m_fdc->intrq_wr_callback().set([this](int state) { m_fdc_intrq = state; update_irq(); });
  m_fdc->drq_wr_callback().set([this](int state) { m_fdc_drq = state; update_irq(); });
  m_fdc->set_force_ready(true);
  FLOPPY_CONNECTOR(config, m_floppy, psicomp80_floppies, "8sssd", psicomp80_floppy_formats);

  screen_device &screen(SCREEN(config, "screen", SCREEN_TYPE_RASTER));
  screen.set_refresh_hz(50);
  screen.set_vblank_time(ATTOSECONDS_IN_USEC(2500));
  screen.set_size(kWidth, kHeight);
  screen.set_visarea(0, kWidth - 1, 0, kHeight - 1);
  screen.set_screen_update(FUNC(psicomp80_state::screen_update));

  PALETTE(config, "palette", palette_device::MONOCHROME);
}

void psicomp80_state::psicomp80x(machine_config &config) {
  psicomp80(config);
  m_cpu->set_addrmap(AS_PROGRAM, &psicomp80_state::mem_map_32k);
}

} // anonymous namespace

ROM_START(psicomp80)
ROM_REGION(0x10000, "maincpu", 0)
ROM_DEFAULT_BIOS("burp")
ROM_SYSTEM_BIOS(0, "burp", "Monitor + BURP")
ROMX_LOAD("psicomp80.rom", 0x0000, 0x0c00,
         CRC(58d2ab1c) SHA1(1488f7c27d8142e5bbe6a45e2ae3e3dfd0c46562), ROM_BIOS(0))
// Monitor + COMP80 FORTH in place of BURP (forth/, built by forth/build.sh)
ROM_SYSTEM_BIOS(1, "forth", "Monitor + FORTH")
ROMX_LOAD("psicomp80_forth.rom", 0x0000, 0x0c00,
         CRC(a6681425) SHA1(0f0804fd4a9f0048feffe6b47b18bf8fdd91f232), ROM_BIOS(1))
// Monitor + COMP80 LISP in place of BURP (lisp/, built by lisp/build.sh)
ROM_SYSTEM_BIOS(2, "lisp", "Monitor + LISP")
ROMX_LOAD("psicomp80_lisp.rom", 0x0000, 0x0c00,
         CRC(dacda6b0) SHA1(bb6dd54ec8e27fb2456cb89c2891a533a8870753), ROM_BIOS(2))
// Monitor + COMP80 Tiny BASIC in place of BURP (basic/, built by basic/build.sh)
ROM_SYSTEM_BIOS(3, "basic", "Monitor + BASIC")
ROMX_LOAD("psicomp80_basic.rom", 0x0000, 0x0c00,
         CRC(ed276001) SHA1(efd6fa022f60c20f314d64c63e4239b4a3a75109), ROM_BIOS(3))
// Monitor + COMP80 Logo in place of BURP (logo/, built by logo/build.sh)
ROM_SYSTEM_BIOS(4, "logo", "Monitor + LOGO")
ROMX_LOAD("psicomp80_logo.rom", 0x0000, 0x0c00,
         CRC(5cd69a7d) SHA1(8391e3056e4a58de3e79951ee1cd96f90bf76e8a), ROM_BIOS(4))
// Monitor + COMP80 CHIP-8 interpreter in place of BURP (chip8/, built by chip8/build.sh)
ROM_SYSTEM_BIOS(5, "chip8", "Monitor + CHIP-8")
ROMX_LOAD("psicomp80_chip8.rom", 0x0000, 0x0c00,
         CRC(19ccb0e6) SHA1(26284b4662bdf78fec999ce281a22e6a4b9e213a), ROM_BIOS(5))
// Monitor + COMP80 FOCAL in place of BURP (focal/, built by focal/build.sh)
ROM_SYSTEM_BIOS(6, "focal", "Monitor + FOCAL")
ROMX_LOAD("psicomp80_focal.rom", 0x0000, 0x0c00,
         CRC(c17bb84d) SHA1(71c17ab2a9884f49d02d8be721986a806cf3806c), ROM_BIOS(6))
// Monitor + COMP80 PILOT in place of BURP (pilot/, built by pilot/build.sh)
ROM_SYSTEM_BIOS(7, "pilot", "Monitor + PILOT")
ROMX_LOAD("psicomp80_pilot.rom", 0x0000, 0x0c00,
         CRC(3579c8b1) SHA1(13d0a6d6cd08ca05bc785d8a5a09249138875e29), ROM_BIOS(7))
// Monitor + COMP80 ZASM assembler and disassembler in place of BURP (zasm/, built by zasm/build.sh)
ROM_SYSTEM_BIOS(8, "zasm", "Monitor + ZASM assembler")
ROMX_LOAD("psicomp80_zasm.rom", 0x0000, 0x0c00,
         CRC(6a2531bf) SHA1(1bd8816616b566f244543ee38e209bd4a809a747), ROM_BIOS(8))
// Monitor + COMP80 Prolog in place of BURP (prolog/, built by prolog/build.sh)
ROM_SYSTEM_BIOS(9, "prolog", "Monitor + Prolog")
ROMX_LOAD("psicomp80_prolog.rom", 0x0000, 0x0c00,
         CRC(7c6db089) SHA1(dc6c27554340767799120dab7a8d22374aa4eb69), ROM_BIOS(9))
// Monitor + COMP80 VTL-2 in place of BURP (vtl/, built by vtl/build.sh)
ROM_SYSTEM_BIOS(10, "vtl", "Monitor + VTL-2")
ROMX_LOAD("psicomp80_vtl.rom", 0x0000, 0x0c00,
         CRC(9545892e) SHA1(fe9740c7102add496cdd200fdd0b1b5e28984891), ROM_BIOS(10))
// Monitor + COMP80 Mouse in place of BURP (mouse/, built by mouse/build.sh)
ROM_SYSTEM_BIOS(11, "mouse", "Monitor + MOUSE")
ROMX_LOAD("psicomp80_mouse.rom", 0x0000, 0x0c00,
         CRC(5d4aafb8) SHA1(c1e9498791acc28a9f776c395546798965a7d4b5), ROM_BIOS(11))
// Monitor + COMP80 Befunge in place of BURP (befunge/, built by befunge/build.sh)
ROM_SYSTEM_BIOS(12, "befunge", "Monitor + Befunge")
ROMX_LOAD("psicomp80_befunge.rom", 0x0000, 0x0c00,
         CRC(8f0e8bda) SHA1(f6d027c58b29deda8241f9ba9ed9a656d5cac8b2), ROM_BIOS(12))
// Monitor + COMP80 CALC spreadsheet in place of BURP (sheet/, built by sheet/build.sh)
ROM_SYSTEM_BIOS(13, "sheet", "Monitor + CALC spreadsheet")
ROMX_LOAD("psicomp80_sheet.rom", 0x0000, 0x0c00,
         CRC(a99d0be4) SHA1(5bd4ee07749f1d39a05fca5517fe9cda6f3b8fc3), ROM_BIOS(13))
// Monitor + COMP80 TRAC in place of BURP (trac/, built by trac/build.sh)
ROM_SYSTEM_BIOS(14, "trac", "Monitor + TRAC")
ROMX_LOAD("psicomp80_trac.rom", 0x0000, 0x0c00,
         CRC(477a1b44) SHA1(de0e30d805310488501898d1efd83c3b0306c7dd), ROM_BIOS(14))
// Monitor + COMP80 PL/0 compiler in place of BURP (pl0/, built by pl0/build.sh)
ROM_SYSTEM_BIOS(15, "pl0", "Monitor + PL/0")
ROMX_LOAD("psicomp80_pl0.rom", 0x0000, 0x0c00,
         CRC(6125162f) SHA1(8a3c71199e07692cdcf8e53d11b04f6528c813a4), ROM_BIOS(15))
// Monitor + COMP80 BF (Brainf***) interpreter in place of BURP (bf/, built by bf/build.sh)
ROM_SYSTEM_BIOS(16, "bf", "Monitor + BF")
ROMX_LOAD("psicomp80_bf.rom", 0x0000, 0x0c00,
         CRC(6d2e5156) SHA1(ff83b2441e06071c98f4848dfdd577dffd153600), ROM_BIOS(16))
// Monitor + COMP80 ED line editor in place of BURP (ed/, built by ed/build.sh)
ROM_SYSTEM_BIOS(17, "ed", "Monitor + ED editor")
ROMX_LOAD("psicomp80_ed.rom", 0x0000, 0x0c00,
         CRC(8804e08f) SHA1(65e3aed4f79009d87ac67ad48e398a92294e49ed), ROM_BIOS(17))
// Monitor + COMP80 FILE card index in place of BURP (db/, built by db/build.sh)
ROM_SYSTEM_BIOS(18, "db", "Monitor + FILE card index")
ROMX_LOAD("psicomp80_db.rom", 0x0000, 0x0c00,
         CRC(f90bbfb1) SHA1(a0b9810b13f24e6329fc440802edf1325aa0861f), ROM_BIOS(18))
// Monitor + COMP80 QUEST adventure engine in place of BURP (adv/, built by adv/build.sh)
ROM_SYSTEM_BIOS(19, "adv", "Monitor + QUEST adventure")
ROMX_LOAD("psicomp80_adv.rom", 0x0000, 0x0c00,
         CRC(b8afac62) SHA1(5d6b8feebbcaf44c8df2b42872b4913aca7462ec), ROM_BIOS(19))
// Monitor + COMP80 APL subset in place of BURP (apl/, built by apl/build.sh)
ROM_SYSTEM_BIOS(20, "apl", "Monitor + APL")
ROMX_LOAD("psicomp80_apl.rom", 0x0000, 0x0c00,
         CRC(858d8054) SHA1(5be94670c7e0ec401df9ff57fd660848250b35e4), ROM_BIOS(20))
// Key-safe monitor (rom/monitor_keysafe.asm) + BURP: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(21, "burpks", "Key-safe monitor + BURP")
ROMX_LOAD("psicomp80_ks.rom", 0x0000, 0x0c00,
         CRC(da99550a) SHA1(2c139dc3fee1d02980f5398334916a7cccaa79bd), ROM_BIOS(21))
// Key-safe monitor (rom/monitor_keysafe.asm) + FORTH: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(22, "forthks", "Key-safe monitor + FORTH")
ROMX_LOAD("psicomp80_forth_ks.rom", 0x0000, 0x0c00,
         CRC(24163421) SHA1(4bc756f880755d0b0fbf4cebed9cbb9165cb9d7c), ROM_BIOS(22))
// Key-safe monitor (rom/monitor_keysafe.asm) + LISP: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(23, "lispks", "Key-safe monitor + LISP")
ROMX_LOAD("psicomp80_lisp_ks.rom", 0x0000, 0x0c00,
         CRC(58b386b4) SHA1(645d6f2acc815dd175c9708661dfb53f9e253bf7), ROM_BIOS(23))
// Key-safe monitor (rom/monitor_keysafe.asm) + BASIC: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(24, "basicks", "Key-safe monitor + BASIC")
ROMX_LOAD("psicomp80_basic_ks.rom", 0x0000, 0x0c00,
         CRC(6f594005) SHA1(c34add4812dfa7871b668de49d3f80fbf2572fd4), ROM_BIOS(24))
// Key-safe monitor (rom/monitor_keysafe.asm) + LOGO: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(25, "logoks", "Key-safe monitor + LOGO")
ROMX_LOAD("psicomp80_logo_ks.rom", 0x0000, 0x0c00,
         CRC(dea8ba79) SHA1(73f74a6ee27338702b6462a66205d917f6b9e79e), ROM_BIOS(25))
// Key-safe monitor (rom/monitor_keysafe.asm) + CHIP-8: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(26, "chip8ks", "Key-safe monitor + CHIP-8")
ROMX_LOAD("psicomp80_chip8_ks.rom", 0x0000, 0x0c00,
         CRC(9bb290e2) SHA1(7e3d836ea2d5943ec546620cbf79dd9358e346b5), ROM_BIOS(26))
// Key-safe monitor (rom/monitor_keysafe.asm) + FOCAL: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(27, "focalks", "Key-safe monitor + FOCAL")
ROMX_LOAD("psicomp80_focal_ks.rom", 0x0000, 0x0c00,
         CRC(43059849) SHA1(4d655b2eda1e352b07153838cd81a4bdbaaac06f), ROM_BIOS(27))
// Key-safe monitor (rom/monitor_keysafe.asm) + PILOT: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(28, "pilotks", "Key-safe monitor + PILOT")
ROMX_LOAD("psicomp80_pilot_ks.rom", 0x0000, 0x0c00,
         CRC(b707e8b5) SHA1(89960113443d6e5baf22d01aee61de49e3aa6bfe), ROM_BIOS(28))
// Key-safe monitor (rom/monitor_keysafe.asm) + ZASM assembler: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(29, "zasmks", "Key-safe monitor + ZASM assembler")
ROMX_LOAD("psicomp80_zasm_ks.rom", 0x0000, 0x0c00,
         CRC(e85b11bb) SHA1(02a7caf17091170311f8c6ec4ec73d6d1f213b24), ROM_BIOS(29))
// Key-safe monitor (rom/monitor_keysafe.asm) + Prolog: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(30, "prologks", "Key-safe monitor + Prolog")
ROMX_LOAD("psicomp80_prolog_ks.rom", 0x0000, 0x0c00,
         CRC(fe13908d) SHA1(4ff93ea8341afa0beafbc83f45416aa0d4ef4eeb), ROM_BIOS(30))
// Key-safe monitor (rom/monitor_keysafe.asm) + VTL-2: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(31, "vtlks", "Key-safe monitor + VTL-2")
ROMX_LOAD("psicomp80_vtl_ks.rom", 0x0000, 0x0c00,
         CRC(173ba92a) SHA1(bb3a499fe243b53ee47ac6a00d0a2d2e15cb436d), ROM_BIOS(31))
// Key-safe monitor (rom/monitor_keysafe.asm) + MOUSE: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(32, "mouseks", "Key-safe monitor + MOUSE")
ROMX_LOAD("psicomp80_mouse_ks.rom", 0x0000, 0x0c00,
         CRC(df348fbc) SHA1(29c32996f706d45387ec1f9cc67b12a6fa6d2206), ROM_BIOS(32))
// Key-safe monitor (rom/monitor_keysafe.asm) + Befunge: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(33, "befungeks", "Key-safe monitor + Befunge")
ROMX_LOAD("psicomp80_befunge_ks.rom", 0x0000, 0x0c00,
         CRC(0d70abde) SHA1(31250108e2739fca44bb4d7b417f9e09dfa6624a), ROM_BIOS(33))
// Key-safe monitor (rom/monitor_keysafe.asm) + CALC spreadsheet: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(34, "sheetks", "Key-safe monitor + CALC spreadsheet")
ROMX_LOAD("psicomp80_sheet_ks.rom", 0x0000, 0x0c00,
         CRC(2be32be0) SHA1(b2a8b8cf8918f99371ce48119fc4508ca270a9b6), ROM_BIOS(34))
// Key-safe monitor (rom/monitor_keysafe.asm) + TRAC: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(35, "tracks", "Key-safe monitor + TRAC")
ROMX_LOAD("psicomp80_trac_ks.rom", 0x0000, 0x0c00,
         CRC(c5043b40) SHA1(8b30aa3ff72dfb9282e2a13189b48cc9061ba13d), ROM_BIOS(35))
// Key-safe monitor (rom/monitor_keysafe.asm) + PL/0: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(36, "pl0ks", "Key-safe monitor + PL/0")
ROMX_LOAD("psicomp80_pl0_ks.rom", 0x0000, 0x0c00,
         CRC(e35b362b) SHA1(a117f0cee18e4acf4703bcfb830ebbd973c4ec38), ROM_BIOS(36))
// Key-safe monitor (rom/monitor_keysafe.asm) + BF: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(37, "bfks", "Key-safe monitor + BF")
ROMX_LOAD("psicomp80_bf_ks.rom", 0x0000, 0x0c00,
         CRC(ef507152) SHA1(d2087e44850464b8450d4df2ad02e937684d63c2), ROM_BIOS(37))
// Key-safe monitor (rom/monitor_keysafe.asm) + ED editor: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(38, "edks", "Key-safe monitor + ED editor")
ROMX_LOAD("psicomp80_ed_ks.rom", 0x0000, 0x0c00,
         CRC(0a7ac08b) SHA1(8cfe0d247fed411e3cb76769761722f132b6d220), ROM_BIOS(38))
// Key-safe monitor (rom/monitor_keysafe.asm) + FILE card index: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(39, "dbks", "Key-safe monitor + FILE card index")
ROMX_LOAD("psicomp80_db_ks.rom", 0x0000, 0x0c00,
         CRC(7b759fb5) SHA1(c6a4b428d0c4ea7436ffe35750d20984ce2ee24d), ROM_BIOS(39))
// Key-safe monitor (rom/monitor_keysafe.asm) + QUEST adventure: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(40, "advks", "Key-safe monitor + QUEST adventure")
ROMX_LOAD("psicomp80_adv_ks.rom", 0x0000, 0x0c00,
         CRC(3ad18c66) SHA1(70a562205bde94ffd3fd72b2d37263a40847827b), ROM_BIOS(40))
// Key-safe monitor (rom/monitor_keysafe.asm) + APL: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(41, "aplks", "Key-safe monitor + APL")
ROMX_LOAD("psicomp80_apl_ks.rom", 0x0000, 0x0c00,
         CRC(07f3a050) SHA1(0eff164228832b2d74d185ca505ee1a845ace426), ROM_BIOS(41))
ROM_END

COMP(1979, psicomp80, 0, 0, psicomp80, psicomp80, psicomp80_state, empty_init,
     "PSI/Powertran", "COMP80", MACHINE_NOT_WORKING | MACHINE_NO_SOUND)

ROM_START(psicomp80x)
ROM_REGION(0x10000, "maincpu", 0)
ROM_DEFAULT_BIOS("burp")
ROM_SYSTEM_BIOS(0, "burp", "Monitor + BURP")
ROMX_LOAD("psicomp80.rom", 0x0000, 0x0c00,
         CRC(58d2ab1c) SHA1(1488f7c27d8142e5bbe6a45e2ae3e3dfd0c46562), ROM_BIOS(0))
// Monitor + COMP80 FORTH in place of BURP (forth/, built by forth/build.sh)
ROM_SYSTEM_BIOS(1, "forth", "Monitor + FORTH")
ROMX_LOAD("psicomp80_forth.rom", 0x0000, 0x0c00,
         CRC(a6681425) SHA1(0f0804fd4a9f0048feffe6b47b18bf8fdd91f232), ROM_BIOS(1))
// Monitor + COMP80 LISP in place of BURP (lisp/, built by lisp/build.sh)
ROM_SYSTEM_BIOS(2, "lisp", "Monitor + LISP")
ROMX_LOAD("psicomp80_lisp.rom", 0x0000, 0x0c00,
         CRC(dacda6b0) SHA1(bb6dd54ec8e27fb2456cb89c2891a533a8870753), ROM_BIOS(2))
// Monitor + COMP80 Tiny BASIC in place of BURP (basic/, built by basic/build.sh)
ROM_SYSTEM_BIOS(3, "basic", "Monitor + BASIC")
ROMX_LOAD("psicomp80_basic.rom", 0x0000, 0x0c00,
         CRC(ed276001) SHA1(efd6fa022f60c20f314d64c63e4239b4a3a75109), ROM_BIOS(3))
// Monitor + COMP80 Logo in place of BURP (logo/, built by logo/build.sh)
ROM_SYSTEM_BIOS(4, "logo", "Monitor + LOGO")
ROMX_LOAD("psicomp80_logo.rom", 0x0000, 0x0c00,
         CRC(5cd69a7d) SHA1(8391e3056e4a58de3e79951ee1cd96f90bf76e8a), ROM_BIOS(4))
// Monitor + COMP80 CHIP-8 interpreter in place of BURP (chip8/, built by chip8/build.sh)
ROM_SYSTEM_BIOS(5, "chip8", "Monitor + CHIP-8")
ROMX_LOAD("psicomp80_chip8.rom", 0x0000, 0x0c00,
         CRC(19ccb0e6) SHA1(26284b4662bdf78fec999ce281a22e6a4b9e213a), ROM_BIOS(5))
// Monitor + COMP80 FOCAL in place of BURP (focal/, built by focal/build.sh)
ROM_SYSTEM_BIOS(6, "focal", "Monitor + FOCAL")
ROMX_LOAD("psicomp80_focal.rom", 0x0000, 0x0c00,
         CRC(c17bb84d) SHA1(71c17ab2a9884f49d02d8be721986a806cf3806c), ROM_BIOS(6))
// Monitor + COMP80 PILOT in place of BURP (pilot/, built by pilot/build.sh)
ROM_SYSTEM_BIOS(7, "pilot", "Monitor + PILOT")
ROMX_LOAD("psicomp80_pilot.rom", 0x0000, 0x0c00,
         CRC(3579c8b1) SHA1(13d0a6d6cd08ca05bc785d8a5a09249138875e29), ROM_BIOS(7))
// Monitor + COMP80 ZASM assembler and disassembler in place of BURP (zasm/, built by zasm/build.sh)
ROM_SYSTEM_BIOS(8, "zasm", "Monitor + ZASM assembler")
ROMX_LOAD("psicomp80_zasm.rom", 0x0000, 0x0c00,
         CRC(6a2531bf) SHA1(1bd8816616b566f244543ee38e209bd4a809a747), ROM_BIOS(8))
// Monitor + COMP80 Prolog in place of BURP (prolog/, built by prolog/build.sh)
ROM_SYSTEM_BIOS(9, "prolog", "Monitor + Prolog")
ROMX_LOAD("psicomp80_prolog.rom", 0x0000, 0x0c00,
         CRC(7c6db089) SHA1(dc6c27554340767799120dab7a8d22374aa4eb69), ROM_BIOS(9))
// Monitor + COMP80 VTL-2 in place of BURP (vtl/, built by vtl/build.sh)
ROM_SYSTEM_BIOS(10, "vtl", "Monitor + VTL-2")
ROMX_LOAD("psicomp80_vtl.rom", 0x0000, 0x0c00,
         CRC(9545892e) SHA1(fe9740c7102add496cdd200fdd0b1b5e28984891), ROM_BIOS(10))
// Monitor + COMP80 Mouse in place of BURP (mouse/, built by mouse/build.sh)
ROM_SYSTEM_BIOS(11, "mouse", "Monitor + MOUSE")
ROMX_LOAD("psicomp80_mouse.rom", 0x0000, 0x0c00,
         CRC(5d4aafb8) SHA1(c1e9498791acc28a9f776c395546798965a7d4b5), ROM_BIOS(11))
// Monitor + COMP80 Befunge in place of BURP (befunge/, built by befunge/build.sh)
ROM_SYSTEM_BIOS(12, "befunge", "Monitor + Befunge")
ROMX_LOAD("psicomp80_befunge.rom", 0x0000, 0x0c00,
         CRC(8f0e8bda) SHA1(f6d027c58b29deda8241f9ba9ed9a656d5cac8b2), ROM_BIOS(12))
// Monitor + COMP80 CALC spreadsheet in place of BURP (sheet/, built by sheet/build.sh)
ROM_SYSTEM_BIOS(13, "sheet", "Monitor + CALC spreadsheet")
ROMX_LOAD("psicomp80_sheet.rom", 0x0000, 0x0c00,
         CRC(a99d0be4) SHA1(5bd4ee07749f1d39a05fca5517fe9cda6f3b8fc3), ROM_BIOS(13))
// Monitor + COMP80 TRAC in place of BURP (trac/, built by trac/build.sh)
ROM_SYSTEM_BIOS(14, "trac", "Monitor + TRAC")
ROMX_LOAD("psicomp80_trac.rom", 0x0000, 0x0c00,
         CRC(477a1b44) SHA1(de0e30d805310488501898d1efd83c3b0306c7dd), ROM_BIOS(14))
// Monitor + COMP80 PL/0 compiler in place of BURP (pl0/, built by pl0/build.sh)
ROM_SYSTEM_BIOS(15, "pl0", "Monitor + PL/0")
ROMX_LOAD("psicomp80_pl0.rom", 0x0000, 0x0c00,
         CRC(6125162f) SHA1(8a3c71199e07692cdcf8e53d11b04f6528c813a4), ROM_BIOS(15))
// Monitor + COMP80 BF (Brainf***) interpreter in place of BURP (bf/, built by bf/build.sh)
ROM_SYSTEM_BIOS(16, "bf", "Monitor + BF")
ROMX_LOAD("psicomp80_bf.rom", 0x0000, 0x0c00,
         CRC(6d2e5156) SHA1(ff83b2441e06071c98f4848dfdd577dffd153600), ROM_BIOS(16))
// Monitor + COMP80 ED line editor in place of BURP (ed/, built by ed/build.sh)
ROM_SYSTEM_BIOS(17, "ed", "Monitor + ED editor")
ROMX_LOAD("psicomp80_ed.rom", 0x0000, 0x0c00,
         CRC(8804e08f) SHA1(65e3aed4f79009d87ac67ad48e398a92294e49ed), ROM_BIOS(17))
// Monitor + COMP80 FILE card index in place of BURP (db/, built by db/build.sh)
ROM_SYSTEM_BIOS(18, "db", "Monitor + FILE card index")
ROMX_LOAD("psicomp80_db.rom", 0x0000, 0x0c00,
         CRC(f90bbfb1) SHA1(a0b9810b13f24e6329fc440802edf1325aa0861f), ROM_BIOS(18))
// Monitor + COMP80 QUEST adventure engine in place of BURP (adv/, built by adv/build.sh)
ROM_SYSTEM_BIOS(19, "adv", "Monitor + QUEST adventure")
ROMX_LOAD("psicomp80_adv.rom", 0x0000, 0x0c00,
         CRC(b8afac62) SHA1(5d6b8feebbcaf44c8df2b42872b4913aca7462ec), ROM_BIOS(19))
// Monitor + COMP80 APL subset in place of BURP (apl/, built by apl/build.sh)
ROM_SYSTEM_BIOS(20, "apl", "Monitor + APL")
ROMX_LOAD("psicomp80_apl.rom", 0x0000, 0x0c00,
         CRC(858d8054) SHA1(5be94670c7e0ec401df9ff57fd660848250b35e4), ROM_BIOS(20))
// Key-safe monitor (rom/monitor_keysafe.asm) + BURP: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(21, "burpks", "Key-safe monitor + BURP")
ROMX_LOAD("psicomp80_ks.rom", 0x0000, 0x0c00,
         CRC(da99550a) SHA1(2c139dc3fee1d02980f5398334916a7cccaa79bd), ROM_BIOS(21))
// Key-safe monitor (rom/monitor_keysafe.asm) + FORTH: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(22, "forthks", "Key-safe monitor + FORTH")
ROMX_LOAD("psicomp80_forth_ks.rom", 0x0000, 0x0c00,
         CRC(24163421) SHA1(4bc756f880755d0b0fbf4cebed9cbb9165cb9d7c), ROM_BIOS(22))
// Key-safe monitor (rom/monitor_keysafe.asm) + LISP: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(23, "lispks", "Key-safe monitor + LISP")
ROMX_LOAD("psicomp80_lisp_ks.rom", 0x0000, 0x0c00,
         CRC(58b386b4) SHA1(645d6f2acc815dd175c9708661dfb53f9e253bf7), ROM_BIOS(23))
// Key-safe monitor (rom/monitor_keysafe.asm) + BASIC: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(24, "basicks", "Key-safe monitor + BASIC")
ROMX_LOAD("psicomp80_basic_ks.rom", 0x0000, 0x0c00,
         CRC(6f594005) SHA1(c34add4812dfa7871b668de49d3f80fbf2572fd4), ROM_BIOS(24))
// Key-safe monitor (rom/monitor_keysafe.asm) + LOGO: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(25, "logoks", "Key-safe monitor + LOGO")
ROMX_LOAD("psicomp80_logo_ks.rom", 0x0000, 0x0c00,
         CRC(dea8ba79) SHA1(73f74a6ee27338702b6462a66205d917f6b9e79e), ROM_BIOS(25))
// Key-safe monitor (rom/monitor_keysafe.asm) + CHIP-8: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(26, "chip8ks", "Key-safe monitor + CHIP-8")
ROMX_LOAD("psicomp80_chip8_ks.rom", 0x0000, 0x0c00,
         CRC(9bb290e2) SHA1(7e3d836ea2d5943ec546620cbf79dd9358e346b5), ROM_BIOS(26))
// Key-safe monitor (rom/monitor_keysafe.asm) + FOCAL: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(27, "focalks", "Key-safe monitor + FOCAL")
ROMX_LOAD("psicomp80_focal_ks.rom", 0x0000, 0x0c00,
         CRC(43059849) SHA1(4d655b2eda1e352b07153838cd81a4bdbaaac06f), ROM_BIOS(27))
// Key-safe monitor (rom/monitor_keysafe.asm) + PILOT: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(28, "pilotks", "Key-safe monitor + PILOT")
ROMX_LOAD("psicomp80_pilot_ks.rom", 0x0000, 0x0c00,
         CRC(b707e8b5) SHA1(89960113443d6e5baf22d01aee61de49e3aa6bfe), ROM_BIOS(28))
// Key-safe monitor (rom/monitor_keysafe.asm) + ZASM assembler: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(29, "zasmks", "Key-safe monitor + ZASM assembler")
ROMX_LOAD("psicomp80_zasm_ks.rom", 0x0000, 0x0c00,
         CRC(e85b11bb) SHA1(02a7caf17091170311f8c6ec4ec73d6d1f213b24), ROM_BIOS(29))
// Key-safe monitor (rom/monitor_keysafe.asm) + Prolog: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(30, "prologks", "Key-safe monitor + Prolog")
ROMX_LOAD("psicomp80_prolog_ks.rom", 0x0000, 0x0c00,
         CRC(fe13908d) SHA1(4ff93ea8341afa0beafbc83f45416aa0d4ef4eeb), ROM_BIOS(30))
// Key-safe monitor (rom/monitor_keysafe.asm) + VTL-2: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(31, "vtlks", "Key-safe monitor + VTL-2")
ROMX_LOAD("psicomp80_vtl_ks.rom", 0x0000, 0x0c00,
         CRC(173ba92a) SHA1(bb3a499fe243b53ee47ac6a00d0a2d2e15cb436d), ROM_BIOS(31))
// Key-safe monitor (rom/monitor_keysafe.asm) + MOUSE: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(32, "mouseks", "Key-safe monitor + MOUSE")
ROMX_LOAD("psicomp80_mouse_ks.rom", 0x0000, 0x0c00,
         CRC(df348fbc) SHA1(29c32996f706d45387ec1f9cc67b12a6fa6d2206), ROM_BIOS(32))
// Key-safe monitor (rom/monitor_keysafe.asm) + Befunge: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(33, "befungeks", "Key-safe monitor + Befunge")
ROMX_LOAD("psicomp80_befunge_ks.rom", 0x0000, 0x0c00,
         CRC(0d70abde) SHA1(31250108e2739fca44bb4d7b417f9e09dfa6624a), ROM_BIOS(33))
// Key-safe monitor (rom/monitor_keysafe.asm) + CALC spreadsheet: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(34, "sheetks", "Key-safe monitor + CALC spreadsheet")
ROMX_LOAD("psicomp80_sheet_ks.rom", 0x0000, 0x0c00,
         CRC(2be32be0) SHA1(b2a8b8cf8918f99371ce48119fc4508ca270a9b6), ROM_BIOS(34))
// Key-safe monitor (rom/monitor_keysafe.asm) + TRAC: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(35, "tracks", "Key-safe monitor + TRAC")
ROMX_LOAD("psicomp80_trac_ks.rom", 0x0000, 0x0c00,
         CRC(c5043b40) SHA1(8b30aa3ff72dfb9282e2a13189b48cc9061ba13d), ROM_BIOS(35))
// Key-safe monitor (rom/monitor_keysafe.asm) + PL/0: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(36, "pl0ks", "Key-safe monitor + PL/0")
ROMX_LOAD("psicomp80_pl0_ks.rom", 0x0000, 0x0c00,
         CRC(e35b362b) SHA1(a117f0cee18e4acf4703bcfb830ebbd973c4ec38), ROM_BIOS(36))
// Key-safe monitor (rom/monitor_keysafe.asm) + BF: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(37, "bfks", "Key-safe monitor + BF")
ROMX_LOAD("psicomp80_bf_ks.rom", 0x0000, 0x0c00,
         CRC(ef507152) SHA1(d2087e44850464b8450d4df2ad02e937684d63c2), ROM_BIOS(37))
// Key-safe monitor (rom/monitor_keysafe.asm) + ED editor: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(38, "edks", "Key-safe monitor + ED editor")
ROMX_LOAD("psicomp80_ed_ks.rom", 0x0000, 0x0c00,
         CRC(0a7ac08b) SHA1(8cfe0d247fed411e3cb76769761722f132b6d220), ROM_BIOS(38))
// Key-safe monitor (rom/monitor_keysafe.asm) + FILE card index: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(39, "dbks", "Key-safe monitor + FILE card index")
ROMX_LOAD("psicomp80_db_ks.rom", 0x0000, 0x0c00,
         CRC(7b759fb5) SHA1(c6a4b428d0c4ea7436ffe35750d20984ce2ee24d), ROM_BIOS(39))
// Key-safe monitor (rom/monitor_keysafe.asm) + QUEST adventure: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(40, "advks", "Key-safe monitor + QUEST adventure")
ROMX_LOAD("psicomp80_adv_ks.rom", 0x0000, 0x0c00,
         CRC(3ad18c66) SHA1(70a562205bde94ffd3fd72b2d37263a40847827b), ROM_BIOS(40))
// Key-safe monitor (rom/monitor_keysafe.asm) + APL: a key that comes
// while a program runs is ignored instead of restarting the monitor
ROM_SYSTEM_BIOS(41, "aplks", "Key-safe monitor + APL")
ROMX_LOAD("psicomp80_apl_ks.rom", 0x0000, 0x0c00,
         CRC(07f3a050) SHA1(0eff164228832b2d74d185ca505ee1a845ace426), ROM_BIOS(41))
ROM_END

COMP(1980, psicomp80x, psicomp80, 0, psicomp80x, psicomp80, psicomp80_state, empty_init,
     "PSI/Powertran", "COMP80 with 32K expansion", MACHINE_NOT_WORKING | MACHINE_NO_SOUND)
