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

class comp80_tape_device : public device_t, public device_image_interface
{
public:
  comp80_tape_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock = 0);

  // tape input bit for IN ($00)
  int input_level();
  // tape output bit for OUT ($20)
  void output_level(int level);

protected:
  // device_t
  virtual void device_start() override;
  virtual void device_reset() override;

  // device_image_interface
  virtual std::pair<std::error_condition, std::string> call_load() override;
  virtual void call_unload() override;
  virtual const char *image_interface() const noexcept override { return "comp80_tape"; }
  virtual const char *file_extensions() const noexcept override { return "c80,bin"; }
  virtual const char *image_type_name() const noexcept override { return "cassette"; }
  virtual const char *image_brief_type_name() const noexcept override { return "tape"; }
  virtual bool is_readable() const noexcept override { return true; }
  virtual bool is_writeable() const noexcept override { return true; }
  virtual bool is_creatable() const noexcept override { return true; }
	// Don't hard-reset the whole machine when the user mounts/unmounts a tape.
	// We want to be able to swap filenames while the monitor is running.
	virtual bool is_reset_on_load() const noexcept override { return false; }

private:
  void reset_input_stream();
  void step_input_until(attotime now);

  // input stream
  std::vector<u8> m_in;
	u32 m_in_byte = 0;
  int m_in_phase = 0;   // 0=leader/idle, 1=start, 2=data, 3=stop
  int m_in_bit = 0;     // data bit index 0..7 (MSB-first)
  int m_in_level = 1;   // current level
  attotime m_next_bit_edge;
  u32 m_leader_bits = 0;

  // output decoder
  enum : u8 { OUT_WAIT_START = 0, OUT_DATA = 1, OUT_WAIT_STOP = 2 };
  u8 m_out_state = OUT_WAIT_START;
  int m_out_bits = 0;
  u8 m_out_accum = 0;
  std::vector<u8> m_out;
  bool m_out_dirty = false;
};

DECLARE_DEVICE_TYPE(COMP80_TAPE, comp80_tape_device)
DEFINE_DEVICE_TYPE(COMP80_TAPE, comp80_tape_device, "comp80_tape", "PSI COMP80 Cassette (digital)")

comp80_tape_device::comp80_tape_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock)
  : device_t(mconfig, COMP80_TAPE, tag, owner, clock)
  , device_image_interface(mconfig, *this)
{
}

void comp80_tape_device::device_start()
{
  save_item(NAME(m_in_byte));
  save_item(NAME(m_in_phase));
  save_item(NAME(m_in_bit));
  save_item(NAME(m_in_level));
  save_item(NAME(m_next_bit_edge));
  save_item(NAME(m_leader_bits));

  save_item(NAME(m_out_state));
  save_item(NAME(m_out_bits));
  save_item(NAME(m_out_accum));
  save_item(NAME(m_out_dirty));

  reset_input_stream();
}

void comp80_tape_device::device_reset()
{
  reset_input_stream();
  m_out_state = OUT_WAIT_START;
  m_out_bits = 0;
  m_out_accum = 0;
  // Do not clear m_out here: user may reset while still wanting captured data.
}

void comp80_tape_device::reset_input_stream()
{
  m_in_byte = 0;
  m_in_phase = 0;
  m_in_bit = 0;
  m_in_level = 1;
  m_next_bit_edge = machine().time();
  // Firmware precedes data with “several seconds” of stop bits (idle=1).
  // Use 2 seconds as a practical default.
  m_leader_bits = 300 * 2;
}

std::pair<std::error_condition, std::string> comp80_tape_device::call_load()
{
  m_in.clear();
  m_out.clear();
  m_out_dirty = false;

  u64 len = length();
  if (len > 0)
  {
    m_in.resize(len);
    fread(m_in.data(), len);
  }

  reset_input_stream();
  // Success: empty error_condition and no message.
  return { std::error_condition(), std::string() };
}

void comp80_tape_device::call_unload()
{
  if (m_out_dirty && !is_readonly())
  {
    fseek(0, SEEK_SET);
    if (!m_out.empty())
      fwrite(m_out.data(), m_out.size());
  }
  m_out_dirty = false;
}

void comp80_tape_device::step_input_until(attotime now)
{
  const attotime bit_time = attotime::from_hz(300);
  const attotime stop_time = bit_time + bit_time / 2; // 1.5 bits

  while (now >= m_next_bit_edge)
  {
    if (!is_loaded() || m_in.empty())
    {
      m_in_level = 1;
      m_next_bit_edge += bit_time;
      continue;
    }

    switch (m_in_phase)
    {
    case 0: // leader/idle (stop bits)
      m_in_level = 1;
      if (m_leader_bits > 0)
        --m_leader_bits;
      else
        m_in_phase = 1;
      m_next_bit_edge += bit_time;
      break;

    case 1: // start bit
      m_in_level = 0;
      m_in_phase = 2;
      m_in_bit = 0;
      m_next_bit_edge += bit_time;
      break;

    case 2: // data bits, MSB-first
      {
        const u8 cur = m_in[m_in_byte];
        const int bit = (cur >> (7 - m_in_bit)) & 1;
        m_in_level = bit;
        m_in_bit++;
        if (m_in_bit >= 8)
          m_in_phase = 3;
        m_next_bit_edge += bit_time;
      }
      break;

    case 3: // stop bits (~1.5 bits)
      m_in_level = 1;
      m_in_phase = 1;
      m_in_bit = 0;
      m_in_byte++;
      if (m_in_byte >= m_in.size())
      {
        m_in_phase = 0;
        m_in_level = 1;
      }
      m_next_bit_edge += stop_time;
      break;
    }
  }
}

int comp80_tape_device::input_level()
{
  step_input_until(machine().time());
  return m_in_level ? 1 : 0;
}

void comp80_tape_device::output_level(int level)
{
  level = level ? 1 : 0;

  switch (m_out_state)
  {
  case OUT_WAIT_START:
    if (level == 0)
    {
      m_out_state = OUT_DATA;
      m_out_bits = 0;
      m_out_accum = 0;
    }
    break;

  case OUT_DATA:
    m_out_accum = (u8)((m_out_accum << 1) | (level & 1));
    m_out_bits++;
    if (m_out_bits >= 8)
      m_out_state = OUT_WAIT_STOP;
    break;

  case OUT_WAIT_STOP:
    if (level == 1)
    {
      m_out.push_back(m_out_accum);
      m_out_dirty = true;
      m_out_state = OUT_WAIT_START;
    }
    else
    {
      m_out_state = OUT_DATA;
      m_out_bits = 0;
      m_out_accum = 0;
    }
    break;
  }
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
#define VERBOSE (LOG_MM57109 | LOG_MM_ACK | LOG_MM_STATUS)

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
        m_tape(*this, "tape") {}

  void psicomp80(machine_config &config);

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
  required_device<comp80_tape_device> m_tape;

  // ROM is mapped read-only (like real hardware)

  // keyboard latch returned by port 01h (ROM does IN then CPL)
  u8 m_key_latch = 0xff;


  u8 m_mm_code = 0x1f;
  bool m_mm_one_shot_clear = false;

  // --- MM57109 port $60 write / port $03 status modelling (BURP relies on
  // this) ---
  u8 m_mm_last_port03 = 0xff; // last value read from port $03 (for change-only logging)
  bool m_mm_RDY = true; // RDY (bit5) for $042E busy/ack loops, RDY=0 means its READY (ie true), RDY=1 means its BUSY (ie false) . BURP waits for RDY=1 after each instruction. Except for BR instuctions which use BR and RDY to indicate branch or not.
  bool m_mm_was_branch_instruction = false; // Used to indicate that the last instruction was a branch instruction
  bool m_mm_instuction_after_branch = false; // Used to indicate that the next instruction is after a branch ... so it should clear ready flag...
  bool m_mm_BR_state = false; // BR (bit6) for $058A; true=branch taken, false=not taken. BR bit = 0 when true, 1 when false (same convention as RDY).
  bool m_mm_HOLD = false; // HOLD (bit 7) Reading a hold bit means the MM57109 is to be put on hold no interrupts, 0 its good to go... 
//   u8 m_mm_latch = 0x00; // phase-1 latched byte (bit7 clear)
//   bool m_mm_expect_latch = true; // handshake phase tracker for $042E (ignore data bit7)
  bool m_mm_inv_pending = false; // last executed opcode was INV (0x20); next selects INV function
  std::vector<u8> m_mm_stream; // committed byte stream (bit7 stripped)
  u64 m_mm_tx_seq = 0;         // transaction counter

  // --- MM57109 register/state model (WIP) ---
  // These fields model the MM57109 internal state at a coarse level so we can
  // progressively implement the instruction set that BURP uses.
  double m_mm_x = 0.0; // X register (top of stack)
  double m_mm_y = 0.0; // Y register
  double m_mm_z = 0.0; // Z register
  double m_mm_t = 0.0; // T register
  double m_mm_m = 0.0; // Memory register M
  bool m_mm_deg_mode =
      false; // angular mode (false=radians, true=degrees) - rough model
  u8 m_mm_mant_digits = 8;       // mantissa digit count (SMDC*)
  bool m_mm_digit_entry = false; // currently collecting digits into X
  std::string m_mm_digit_buf;    // digit-entry buffer (ASCII, e.g. "-12.34E+5")
  // MM57109 number-entry state (digits/DP/EE/CS)
  bool m_mm_entry_exp_mode = false;
  bool m_mm_entry_dp_set = false;
  int m_mm_entry_dp_index = 0; // number of mantissa digits before decimal point
  int m_mm_entry_mant_count = 0; // digits entered into mantissa (0..8)
  int m_mm_entry_exp_count = 0;  // digits entered into exponent (0..2)
  int m_mm_entry_mant_sign = 1;
  int m_mm_entry_exp_sign = 1;
  std::array<u8, 8> m_mm_entry_mant{};
  std::array<u8, 2> m_mm_entry_exp{};
  bool m_mm_two_word_pending = false;
  bool m_mm_irq0_asserted = false;
  u8 m_mm_two_word_op = 0x00;
  bool m_mm_error = false;

  // queue for IM1 nibble delivery (port $03 low nibble + IRQ0 pulses)
  std::vector<u8> m_mm_nibble_q;
  emu_timer *m_mm_nibble_timer = nullptr;
  // Timed RDY/BR modelling: each committed MM57109 byte makes the device "busy"
  // for a programmable number of Z80 clock cycles, then becomes ready and (for
  // branch-type ops) presents the branch result for a short window.
  emu_timer *m_mm_ready_timer = nullptr;
  emu_timer *m_mm_branch_clear_timer = nullptr;
  // Default delays (in Z80 clock cycles). Must be > OUT(11)+IN(10) so $042E
  // loop at 0439 sees RDY=1 (busy) on first poll after OUT $60.
  u32 m_mm_default_exec_cycles = 40;
  u32 m_mm_branch_clear_cycles = 20;
  // When branch result leaves RDY false, delay this many cycles before setting RDY true (for $058A 059E loop).
  u32 m_mm_branch_rdy_delay_cycles = 100;
  // Branch "executing" period: hold m_mm_RDY=0 + m_mm_BR_state=1 (port 0x60) this long so $058A loop at 058E sees it.
  u32 m_mm_branch_exec_cycles = 150;
  // After OUT* last nibble: delay before m_mm_RDY=true so Z80 can finish the
  // last IRQ handler (~65 cy) and run IN at 0439.
  u32 m_mm_out_stream_complete_cycles = 300;
  // Per-opcode execution delay table (index = opcode & 0x3f). Defaults to
  // m_mm_default_exec_cycles; can be tuned per instruction later.
  std::array<u32, 64> m_mm_op_exec_cycles{};

  // State latched at "instruction start" for the ready timer callback.
  bool m_mm_pending_is_branch = false;
  bool m_mm_pending_branch_state = false;
  u8 m_mm_pending_opcode = 0x00;


  // -------- character generator tables --------
  // Each glyph: 8 rows, 5 bits per row (packed in bits 0..4).
  // Table is indexed as ASCII 0x20..0x5F mapped to 0..63.
  static const std::array<std::array<u8, 8>, 64> ascii_font_64x8x5;

  // Placeholder graphics font (fill later)
  static std::array<std::array<u8, 10>, 64> gfx_font_64x10x6;

  // maps
  void mem_map(address_map &map);
  void io_map(address_map &map);

  // I/O handlers
  u8 port00_r();
  u8 port01_r();
  u8 port03_r();
  void port20_w(u8 data);
  void port60_w(u8 data);
  void mm57109_dump_stream(const char *tag, u8 cmd);

  // keyboard -> strobe (NMI) + MM data ready (IRQ0)
  void kbd_put(u8 data);
  // display
  u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap,
                    const rectangle &cliprect);

  // helpers
  static u8 ascii_to_mm_code(u8 data);
  void mm_set_data_ready(u8 code);
  // MM57109 model helpers
  void mm57109_reset();
  void mm57109_execute(u8 op);
  void mm57109_execute_single(u8 op);
  bool mm57109_is_two_word(u8 op) const;
  const char *mm57109_opcode_mn(u8 op) const;
  void mm57109_push(double v);
  double mm57109_pop();
  void mm57109_set_x(double v);
  void mm57109_queue_nibble(u8 nib);
  void mm57109_emit_out_scientific_stream_from_x();
  TIMER_CALLBACK_MEMBER(mm57109_nibble_tick);
  TIMER_CALLBACK_MEMBER(mm57109_ready_tick);
  TIMER_CALLBACK_MEMBER(mm57109_branch_clear_tick);
  void mm57109_begin_processing(u8 opcode, bool is_branch, bool branch_state);

  void mm57109_log_regs(const char *phase, u8 op);

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
	/* 0x00 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x01 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x02 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x03 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x04 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x05 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x06 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x07 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x08 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x09 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x0A */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x0B */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x0C */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x0D */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x0E */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x0F */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x10 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x11 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x12 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x13 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x14 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x15 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x16 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x17 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x18 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x19 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x1A */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x1B */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x1C */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x1D */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x1E */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x1F */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x20 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x21 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x22 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x23 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x24 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x25 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x26 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x27 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x28 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x29 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x2A */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x2B */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x2C */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x2D */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x2E */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x2F */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x30 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x31 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x32 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x33 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x34 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x35 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x36 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x37 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x38 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x39 */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x3A */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x3B */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x3C */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x3D */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x3E */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
	/* 0x3F */ {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
}};
// ------------------ machine lifecycle ------------------

void psicomp80_state::machine_start() {
  m_mm_stream.reserve(256);
  m_mm_nibble_timer =
      timer_alloc(FUNC(psicomp80_state::mm57109_nibble_tick), this);
  m_mm_ready_timer =
      timer_alloc(FUNC(psicomp80_state::mm57109_ready_tick), this);
  m_mm_branch_clear_timer =
      timer_alloc(FUNC(psicomp80_state::mm57109_branch_clear_tick), this);

  // Default all opcodes to the same execution time for now; tweak per opcode
  // later as we learn the real MM57109 timing.
  m_mm_op_exec_cycles.fill(m_mm_default_exec_cycles);


  save_item(NAME(m_key_latch));
  save_item(NAME(m_mm_code));
  save_item(NAME(m_mm_one_shot_clear));
  save_item(NAME(m_mm_last_port03));

  save_item(NAME(m_mm_RDY));
  save_item(NAME(m_mm_BR_state));
  save_item(NAME(m_mm_HOLD));
//   save_item(NAME(m_mm_latch));
  save_item(NAME(m_mm_was_branch_instruction));
  save_item(NAME(m_mm_instuction_after_branch));
  //save_item(NAME(m_mm_expect_latch));
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
  save_item(NAME(m_mm_irq0_asserted));
  save_item(NAME(m_mm_two_word_op));
  save_item(NAME(m_mm_error));
}

void psicomp80_state::machine_reset() {
  m_key_latch = 0xff;
  
  mm57109_reset();
}

// ------------------ memory & I/O ------------------

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
}

u8 psicomp80_state::port00_r()
{
  // Firmware masks bit 0 (AND 1) and treats idle as 1.
  const int lvl = m_tape->input_level();
  return (lvl ? 0x01 : 0x00);
}

void psicomp80_state::port20_w(u8 data)
{
  // Cassette output is bit 7 of the data bus (D7).
  const int lvl = (data & 0x80) ? 1 : 0;
  m_tape->output_level(lvl);
}

u8 psicomp80_state::port01_r() {
  const u8 v = m_key_latch;
  m_key_latch = 0xff;
  return v;
}

u8 psicomp80_state::port03_r() {
  // Port $03: combined MM57109 status + 4-bit data.
  //
  // BURP uses bit5 ($20) as the RDY line, it needs to see RDY go high to indicate its busy, the RDY to low 
  // $042E:
  //   - it waits for RDY=0 before (its ready for an instuction), then waits for RDY=1  (its busy executing the instuction) before putting it in HOLD.
  //
  // BURP also uses bit6 ($40) BR (branch). Same convention as RDY: state true -> bit 0, state false -> bit 1.
  //   - bit5 RDY: m_mm_RDY=true -> 0, m_mm_RDY=false -> 1
  //   - bit6 BR:  m_mm_BR_state=true -> 0, m_mm_BR_state=false -> 1
  //
  // Low bits contain the current 4-bit (or 5-bit) code sample; only the low
  // nibble is meaningful for IM1 capture (A & $0F).
  bool RDY = m_mm_RDY;
  bool BR_state = m_mm_BR_state;

  u8 v = (RDY ? 0x00 : 0x20) | (BR_state ? 0x00 : 0x40) | (m_mm_code & 0x1f);

  // Log when value changed, or always when PC=003B (IRQ handler IN) to see every interrupt.
  const bool log_read = (v != m_mm_last_port03) || ((u16)m_cpu->pc() == 0x003B);
  if (log_read) {
    const int rdy_bit = (v >> 5) & 1;
    const int br_bit = (v >> 6) & 1;
    LOGMASKED(LOG_MM_STATUS,
              "[t=%.6f] MM57109 R: IN ($03) @PC=%04X -> %02X (m_mm_RDY=%s m_mm_BR_state=%s RDY bit=%d BR bit=%d code=%02X)\n",
              MM_TS(), (u16)m_cpu->pc(), v,
              RDY ? "true" : "false", BR_state ? "true" : "false", rdy_bit, br_bit, m_mm_code);
    if (v != m_mm_last_port03)
      m_mm_last_port03 = v;
  }

  // If we're currently presenting a queued digit nibble via IRQ0, the ROM IM1
  // handler will read port $03 to sample it. Model this as a handshake: the
  // read acknowledges the current nibble, so we deassert IRQ0 and (if more
  // digits are queued) arm the next.
  if (m_mm_irq0_asserted) {
    m_cpu->set_input_line(INPUT_LINE_IRQ0, CLEAR_LINE);
    m_mm_irq0_asserted = false;
    if (m_mm_nibble_timer && !m_mm_nibble_q.empty())
      m_mm_nibble_timer->adjust(attotime::zero);
  }

  return v;
}

// ---------------------------------------------------------------------------
// MM57109 coarse state model (registers + instruction dispatcher)
// ---------------------------------------------------------------------------

void psicomp80_state::mm57109_reset() {

  m_mm_was_branch_instruction = false;
  m_mm_instuction_after_branch = false;
  m_mm_code = 0x1f;
  m_mm_one_shot_clear = false;
  m_mm_last_port03 = 0xff;

  m_mm_HOLD = false;
  m_mm_RDY = true;
  m_mm_BR_state = false;
//   m_mm_latch = 0x00;
  // m_mm_expect_latch = true;
  m_mm_inv_pending = false;
  m_mm_irq0_asserted = false;
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

bool psicomp80_state::mm57109_is_two_word(u8 op) const {
  // Per MM57109 datasheet: several instructions are 2-word (opcode +
  // parameter/addr). We don't implement their behaviour yet, but we track the
  // second word so we can correlate BURP byte streams with required
  // functionality.
  switch (op & 0x3f) {
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

const char *psicomp80_state::mm57109_opcode_mn(u8 op) const {
  // Prefer the existing mnemonic mapping (already used for logging).
  return mm57109_opcode_name(op & 0x3f);
}

void psicomp80_state::mm57109_push(double v) {
  m_mm_t = m_mm_z;
  m_mm_z = m_mm_y;
  m_mm_y = m_mm_x;
  m_mm_x = v;
}

double psicomp80_state::mm57109_pop() {
  double v = m_mm_x;
  m_mm_x = m_mm_y;
  m_mm_y = m_mm_z;
  m_mm_z = m_mm_t;
  // m_mm_t holds last T; keep as-is
  return v;
}

void psicomp80_state::mm57109_set_x(double v) { m_mm_x = v; }

void psicomp80_state::mm57109_queue_nibble(u8 nib) {
  m_mm_nibble_q.push_back(nib & 0x0f);

  // Start (or restart) the paced nibble delivery timer. Delivering multiple
  // IRQ0 pulses in a single timeslice can collapse into a single interrupt
  // edge; BURP expects a distinct interrupt per digit.
  if (m_mm_nibble_timer && !m_mm_nibble_timer->enabled())
    m_mm_nibble_timer->adjust(attotime::zero);
}

TIMER_CALLBACK_MEMBER(psicomp80_state::mm57109_nibble_tick) {
  if (m_mm_nibble_q.empty())
    return;

  const u8 nib = m_mm_nibble_q.front();
  m_mm_nibble_q.erase(m_mm_nibble_q.begin());

  // Present nibble on port $03 and pulse IRQ0 so the ROM IM 1 handler at $0038
  // stores it.
  m_mm_code = nib & 0x0f;
  // OUT*: when last nibble delivered, start 40-cycle timer then go ready so the
  // Z80 (which may still be in/returning from IRQ storm) sees RDY=1 (busy) at 0439.
  // Other nibble sources: only set RDY when not in instruction busy window.
  if (m_mm_nibble_q.empty()) {
    if (m_mm_ready_timer) {
      const u32 cycles = m_mm_out_stream_complete_cycles;
      m_mm_ready_timer->adjust(attotime::from_ticks(cycles, m_cpu->clock()));
      LOGMASKED(LOG_MM57109,
                "[t=%.6f] MM57109: [OUT*] interrupts complete, m_mm_RDY=%s -> true, timer set for %u cycles\n",
                MM_TS(), m_mm_RDY ? "true" : "false", cycles);
    } else {
      LOGMASKED(LOG_MM57109,
                "[t=%.6f] MM57109: [OUT*] interrupts complete, m_mm_RDY=%s -> true (no timer)\n",
                MM_TS(), m_mm_RDY ? "true" : "false");
      m_mm_RDY = true;
    }
  } else if (!m_mm_ready_timer || !m_mm_ready_timer->enabled()) {
    m_mm_RDY = true;
  }
  m_mm_one_shot_clear = false;
  if (!m_mm_irq0_asserted) {
    m_cpu->set_input_line(INPUT_LINE_IRQ0, ASSERT_LINE);
    m_mm_irq0_asserted = true;
  }
}


TIMER_CALLBACK_MEMBER(psicomp80_state::mm57109_ready_tick)
{
  // End of "busy" window for the last committed byte.
  if (m_mm_pending_is_branch) {
    // Present branch result (ROM samples it via bits 5/6 on the next status read).
    m_mm_was_branch_instruction = true;
    m_mm_BR_state = m_mm_pending_branch_state;
    m_mm_RDY = !m_mm_pending_branch_state;

    // Clear BR and set RDY true after a window. If result left RDY false, use longer delay so $058A completes.
    if (m_mm_branch_clear_timer) {
      const u32 cy = m_mm_RDY ? m_mm_branch_clear_cycles : m_mm_branch_rdy_delay_cycles;
      m_mm_branch_clear_timer->adjust(attotime::from_ticks(cy, m_cpu->clock()));
    }
	LOGMASKED(LOG_MM57109, "[t=%.6f] MM57109: [timer] finished (branch), m_mm_RDY=%s m_mm_BR_state=%s\n", MM_TS(), m_mm_RDY ? "true" : "false", m_mm_BR_state ? "true" : "false");
  } else {
	LOGMASKED(LOG_MM57109, "[t=%.6f] MM57109: [timer] finished, m_mm_RDY=true\n", MM_TS());
    m_mm_RDY = true;
  }
}

TIMER_CALLBACK_MEMBER(psicomp80_state::mm57109_branch_clear_tick)
{
  // After the branch-result window, drop BR and leave the device ready.
  m_mm_BR_state = false;
  m_mm_RDY = true;
  LOGMASKED(LOG_MM57109, "[t=%.6f] MM57109: [timer] branch_clear finished, m_mm_RDY=true\n", MM_TS());
}

void psicomp80_state::mm57109_begin_processing(u8 opcode, bool is_branch, bool branch_state)
{
  // "Start of execution": not ready. Both port bits 1 during execution => m_mm_RDY=false, m_mm_BR_state=false.
  m_mm_RDY = false;
  m_mm_BR_state = false;

  m_mm_pending_opcode = opcode & 0x3f;
  m_mm_pending_is_branch = is_branch;
  m_mm_pending_branch_state = branch_state;

  if (m_mm_ready_timer)
    m_mm_ready_timer->adjust(attotime::never);

  if (m_mm_branch_clear_timer)
    m_mm_branch_clear_timer->adjust(attotime::never);

  const u32 cycles = is_branch ? m_mm_branch_exec_cycles
                               : (m_mm_op_exec_cycles[m_mm_pending_opcode] ? m_mm_op_exec_cycles[m_mm_pending_opcode] : m_mm_default_exec_cycles);
  const attotime dt = attotime::from_ticks(cycles, m_cpu->clock());
  if (m_mm_ready_timer)
    m_mm_ready_timer->adjust(dt);
  LOGMASKED(LOG_MM57109,
            "[t=%.6f] MM57109: [executing] m_mm_RDY=%s m_mm_BR_state=%s (RDY bit=%d BR bit=%d port 0x%02X), timer %u cycles (op %02X)\n",
            MM_TS(), m_mm_RDY ? "true" : "false", m_mm_BR_state ? "true" : "false",
            m_mm_RDY ? 0 : 1, m_mm_BR_state ? 0 : 1,
            (m_mm_RDY ? 0x00 : 0x20) | (m_mm_BR_state ? 0x00 : 0x40), cycles, m_mm_pending_opcode);
  if (is_branch)
    LOGMASKED(LOG_MM57109,
              "[t=%.6f] MM57109: [timer] branch started: m_mm_RDY=%s m_mm_BR_state=%s, timer %u cycles, then m_mm_RDY=%s m_mm_BR_state=%s\n",
              MM_TS(), m_mm_RDY ? "true" : "false", m_mm_BR_state ? "true" : "false", cycles,
              (!branch_state) ? "true" : "false", branch_state ? "true" : "false");
}

void psicomp80_state::mm57109_emit_out_scientific_stream_from_x() {
  // OUT*: keep RDY=1 (busy) until all nibbles are delivered (nibble_tick sets
  // RDY when queue becomes empty). Cancel the per-instruction timer so we don't
  // go ready early.
  LOGMASKED(LOG_MM57109,
            "[t=%.6f] MM57109: [OUT*] stream start, m_mm_RDY=false (RDY bit=1), timer cancelled, queueing nibbles\n",
            MM_TS());
  if (m_mm_ready_timer)
    m_mm_ready_timer->adjust(attotime::never);

  double x = m_mm_x;

  // MDC=8 is the default on COMP80 (SMDC*). BURP/ROM assumes 8-digit mantissa
  // formatting.
  const int mdc = int(m_mm_mant_digits ? m_mm_mant_digits : 8);

  // Scientific OUT format digit order (DA0..DA(MDC+3)):
  //  DA0 exponent MSD, DA1 exponent LSD, DA2 signbits (Sm bit3, Se bit0),
  //  DA3 decimal-point position indicator, DA4..DA(MDC+3) mantissa digits.
  //
  // First attempt at DA3: choose 0x0B so ROM routine at $0460 computes n=1
  // (decimal after 1 digit):
  //   n = ((~DA3)&0x0F) - 3  => n=1 when (~DA3)&0x0F == 4  => DA3 == 0x0B.
  const u8 dp_pos = 0x0B;

  if (x == 0.0) {
    mm57109_queue_nibble(0);      // exp MSD
    mm57109_queue_nibble(0);      // exp LSD
    mm57109_queue_nibble(0);      // signbits
    mm57109_queue_nibble(dp_pos); // dp position
    for (int i = 0; i < mdc; i++)
      mm57109_queue_nibble(0);
    return;
  }

  const bool mant_neg = (x < 0.0);
  double ax = std::fabs(x);

  int exp10 = int(std::floor(std::log10(ax)));
  double norm = ax / std::pow(10.0, exp10); // 1..10

  // Clamp against rounding drift
  if (norm >= 10.0) {
    norm /= 10.0;
    exp10++;
  }
  if (norm < 1.0) {
    norm *= 10.0;
    exp10--;
  }

  const bool exp_neg = (exp10 < 0);
  int aexp = std::abs(exp10);
  if (aexp > 99)
    aexp = 99;

  const int exp_msd = (aexp / 10) % 10;
  const int exp_lsd = (aexp / 1) % 10;

  u8 signbits = 0;
  if (mant_neg)
    signbits |= 0x08; // Sm
  if (exp_neg)
    signbits |= 0x01; // Se

  mm57109_queue_nibble(u8(exp_msd));
  mm57109_queue_nibble(u8(exp_lsd));
  mm57109_queue_nibble(signbits);
  mm57109_queue_nibble(dp_pos);

  double t = norm;
  for (int i = 0; i < mdc; i++) {
    int d = int(std::floor(t));
    if (d < 0)
      d = 0;
    if (d > 9)
      d = 9;
    mm57109_queue_nibble(u8(d));
    t = (t - double(d)) * 10.0;
  }
}

void psicomp80_state::mm57109_log_regs(const char *phase, u8 op) {
  const u8 opcode = op & 0x3f;
  LOGMASKED(LOG_MM57109,
            "MM57109: regs(%s) op=%02X(%03o) %-10s X=%g Y=%g Z=%g T=%g M=%g "
            "deg=%d mant=%u err=%d\n",
            phase, opcode, unsigned(opcode), mm57109_opcode_mn(opcode), m_mm_x,
            m_mm_y, m_mm_z, m_mm_t, m_mm_m, m_mm_deg_mode ? 1 : 0,
            unsigned(m_mm_mant_digits), m_mm_error ? 1 : 0);
}

void psicomp80_state::mm57109_execute_single(u8 op) {
  m_mm_BR_state = false; 
 
  const u8 opcode = op & 0x3f;

  // Digit-entry class per MM57109 docs: 0-9, DP, EE, CS, PI, AIN, HALT
  const bool is_digit = (opcode <= 0x09);
  const bool is_dp = (opcode == 0x0a);
  const bool is_ee = (opcode == 0x0b);
  const bool is_cs = (opcode == 0x0c);
  const bool is_pi = (opcode == 0x0d);
  const bool is_ain = (opcode == 0x0e);
  const bool is_halt = (opcode == 0x0f);
  const bool is_en = (opcode == 0x21);

  const bool is_entry_class =
      is_digit || is_dp || is_ee || is_cs || is_pi || is_ain || is_halt;

  auto update_x_from_entry = [&]() {
    long long mant_int = 0;
    for (int i = 0; i < m_mm_entry_mant_count; i++)
      mant_int = mant_int * 10 + (m_mm_entry_mant[i] % 10);

    const int dp_index =
        m_mm_entry_dp_set ? m_mm_entry_dp_index : m_mm_entry_mant_count;
    const int frac_pow = dp_index - m_mm_entry_mant_count;

    double v = double(mant_int);
    if (frac_pow != 0)
      v *= std::pow(10.0, double(frac_pow));
    v *= double(m_mm_entry_mant_sign);

    if (m_mm_entry_exp_count > 0) {
      int expv = 0;
      if (m_mm_entry_exp_count == 1)
        expv = (m_mm_entry_exp[0] % 10);
      else
        expv = (m_mm_entry_exp[0] % 10) * 10 + (m_mm_entry_exp[1] % 10);

      expv *= m_mm_entry_exp_sign;
      v *= std::pow(10.0, double(expv));
    }

    mm57109_set_x(v);
  };
  // If we're in number-entry and a non-entry instruction arrives, terminate
  // number-entry now.
  // (HALT is explicitly "does not terminate number entry".)
  if (m_mm_digit_entry && !is_entry_class && !is_en) {
    // Build X from entered digits.
    // Mantissa integer from entered digits
    long long mant_int = 0;
    for (int i = 0; i < m_mm_entry_mant_count; i++)
      mant_int = mant_int * 10 + (m_mm_entry_mant[i] % 10);

    const int dp_index =
        m_mm_entry_dp_set ? m_mm_entry_dp_index : m_mm_entry_mant_count;
    const int frac_pow =
        dp_index -
        m_mm_entry_mant_count; // negative if there are fraction digits

    double v = double(mant_int);
    if (frac_pow != 0)
      v *= std::pow(10.0, double(frac_pow));
    v *= double(m_mm_entry_mant_sign);

    // Apply exponent if any digits were entered after EE
    if (m_mm_entry_exp_count > 0) {
      int expv = 0;
      if (m_mm_entry_exp_count == 1)
        expv = (m_mm_entry_exp[0] % 10);
      else
        expv = (m_mm_entry_exp[0] % 10) * 10 + (m_mm_entry_exp[1] % 10);

      expv *= m_mm_entry_exp_sign;
      v *= std::pow(10.0, double(expv));
    }

    mm57109_set_x(v);

    // Reset entry state
    m_mm_digit_entry = false;
    m_mm_digit_buf.clear();
    m_mm_entry_exp_mode = false;
    m_mm_entry_dp_set = false;
    m_mm_entry_dp_index = 0;
    m_mm_entry_mant_count = 0;
    m_mm_entry_exp_count = 0;
    m_mm_entry_mant_sign = 1;
    m_mm_entry_exp_sign = 1;
    m_mm_entry_mant.fill(0);
    m_mm_entry_exp.fill(0);
  }

  // Handle EN (ENTER). If number-entry active, finalize as above (by falling
  // through the termination path). EN itself typically ends number entry; treat
  // it as "finalize if needed" without extra stack motion here.
  if (is_en) {
    if (m_mm_digit_entry) {
      // Force termination by re-invoking this function's termination logic
      // using a fake non-entry op: easiest is to reuse the code above by
      // temporarily clearing the entry-class condition. We'll just finalize
      // inline (duplicate small block).
      long long mant_int = 0;
      for (int i = 0; i < m_mm_entry_mant_count; i++)
        mant_int = mant_int * 10 + (m_mm_entry_mant[i] % 10);

      const int dp_index =
          m_mm_entry_dp_set ? m_mm_entry_dp_index : m_mm_entry_mant_count;
      const int frac_pow = dp_index - m_mm_entry_mant_count;

      double v = double(mant_int);
      if (frac_pow != 0)
        v *= std::pow(10.0, double(frac_pow));
      v *= double(m_mm_entry_mant_sign);

      if (m_mm_entry_exp_count > 0) {
        int expv = 0;
        if (m_mm_entry_exp_count == 1)
          expv = (m_mm_entry_exp[0] % 10);
        else
          expv = (m_mm_entry_exp[0] % 10) * 10 + (m_mm_entry_exp[1] % 10);

        expv *= m_mm_entry_exp_sign;
        v *= std::pow(10.0, double(expv));
      }

      mm57109_set_x(v);

      m_mm_digit_entry = false;
      m_mm_digit_buf.clear();
      m_mm_entry_exp_mode = false;
      m_mm_entry_dp_set = false;
      m_mm_entry_dp_index = 0;
      m_mm_entry_mant_count = 0;
      m_mm_entry_exp_count = 0;
      m_mm_entry_mant_sign = 1;
      m_mm_entry_exp_sign = 1;
      m_mm_entry_mant.fill(0);
      m_mm_entry_exp.fill(0);
    }
    return;
  }

  // Helper: start number-entry if needed (push stack, clear X, reset state)
  auto start_entry_if_needed = [&]() {
    if (!m_mm_digit_entry) {
      // Initiate number entry: Z->T, Y->Z, X->Y, 0->X
      m_mm_t = m_mm_z;
      m_mm_z = m_mm_y;
      m_mm_y = m_mm_x;
      mm57109_set_x(0.0);

      m_mm_digit_entry = true;
      m_mm_digit_buf.clear();

      m_mm_entry_exp_mode = false;
      m_mm_entry_dp_set = false;
      m_mm_entry_dp_index = 0;
      m_mm_entry_mant_count = 0;
      m_mm_entry_exp_count = 0;
      m_mm_entry_mant_sign = 1;
      m_mm_entry_exp_sign = 1;
      m_mm_entry_mant.fill(0);
      m_mm_entry_exp.fill(0);
    }
  };

  // Number-entry opcodes
  if (is_digit) {
    start_entry_if_needed();

    const int d = int(opcode);
    if (!m_mm_entry_exp_mode) {
      // Mantissa digit
      if (m_mm_entry_mant_count < int(m_mm_entry_mant.size())) {
        m_mm_entry_mant[m_mm_entry_mant_count++] = u8(d);
        m_mm_digit_buf.push_back(char('0' + d));
      }
    } else {
      // Exponent digit (2 digits max)
      if (m_mm_entry_exp_count < int(m_mm_entry_exp.size())) {
        m_mm_entry_exp[m_mm_entry_exp_count++] = u8(d);
        m_mm_digit_buf.push_back(char('0' + d));
      }
    }
    update_x_from_entry();
    return;
  }

  if (is_dp) {
    start_entry_if_needed();
    if (!m_mm_entry_dp_set) {
      m_mm_entry_dp_set = true;
      m_mm_entry_dp_index = m_mm_entry_mant_count;
      if (m_mm_digit_buf.find('.') == std::string::npos)
        m_mm_digit_buf.push_back('.');
    }
    return;
  }

  if (is_ee) {
    start_entry_if_needed();
    m_mm_entry_exp_mode = true;
    if (m_mm_digit_buf.find('E') == std::string::npos)
      m_mm_digit_buf.push_back('E');
    return;
  }

  if (is_cs) {
    start_entry_if_needed();
    if (m_mm_entry_exp_mode)
      m_mm_entry_exp_sign = -m_mm_entry_exp_sign;
    else
      m_mm_entry_mant_sign = -m_mm_entry_mant_sign;

    // Keep digit_buf vaguely readable for debugging
    if (!m_mm_digit_buf.empty() && m_mm_digit_buf[0] == '-')
      m_mm_digit_buf.erase(0, 1);
    else
      m_mm_digit_buf.insert(0, 1, '-');
    return;
  }

  if (is_pi) {
    // PI is in the entry-class set, but behaves like "push stack then load pi"
    start_entry_if_needed();
    mm57109_set_x(3.14159265358979323846);
    return;
  }

  if (is_ain) {
    // Not used for COMP-80 monitor yet; treat as no-op placeholder.
    start_entry_if_needed();
    return;
  }

  if (is_halt) {
    // HALT behaves like NOP and does not terminate number entry.
    // Leave entry_active unchanged.
    return;
  }

  // If INV prefix was seen, interpret the next opcode as an inverse/memory
  // variant. This is required for BURP/monitor math functions.
  if (m_mm_inv_pending) {

    LOGMASKED(LOG_MM57109,
              "MM57109: m_mm_inv_pending is true, opcode is %02X(%03o)\n", opcode, unsigned(opcode));
    m_mm_inv_pending = false;
    switch (opcode) {
    case 0x24: // INV SIN  -> ASIN
    {
      double v = m_mm_x;
      if (v < -1.0 || v > 1.0) {
        m_mm_error = true;
        mm57109_set_x(0.0);
      } else {
        double r = std::asin(v);
        if (m_mm_deg_mode)
          r = r * 180.0 / 3.14159265358979323846;
        mm57109_set_x(r);
      }
      return;
    }
    case 0x25: // INV COS  -> ACOS
    {
      double v = m_mm_x;
      if (v < -1.0 || v > 1.0) {
        m_mm_error = true;
        mm57109_set_x(0.0);
      } else {
        double r = std::acos(v);
        if (m_mm_deg_mode)
          r = r * 180.0 / 3.14159265358979323846;
        mm57109_set_x(r);
      }
      return;
    }
    case 0x26: // INV TAN  -> ATAN
    {
      double r = std::atan(m_mm_x);
      if (m_mm_deg_mode)
        r = r * 180.0 / 3.14159265358979323846;
      mm57109_set_x(r);
      return;
    }
    case 0x39: // INV + -> M+
      m_mm_m += m_mm_x;
      return;
    case 0x3a: // INV - -> M-
      LOGMASKED(LOG_MM57109, "MM57109: INV - -> M- (m_mm_x=%f)\n", m_mm_x);
      m_mm_m -= m_mm_x;
      return;
    case 0x3b: // INV * -> MX
      m_mm_m *= m_mm_x;
      return;
    case 0x3c: // INV / -> M/
      if (m_mm_x == 0.0) {
        m_mm_error = true;
      } else
        m_mm_m /= m_mm_x;
      return;
    default:
      break;
    }
    // If we get here, the INV variant isn't implemented yet; fall through to
    // normal decode.
  }

  // Non-entry operations
  switch (opcode) {
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
    if (x == 0.0) {
      m_mm_error = true;
      mm57109_push(0.0);
    } else {
      mm57109_push(y / x);
    }
    return;
  }

  case 0x2b: // ECLR
    m_mm_error = false;
    return;

  case 0x2f: // MCLR
    m_mm_m = 0.0;
    return;

  case 0x2c: // RTD (radians to degrees)
    mm57109_set_x(m_mm_x * 180.0 / 3.14159265358979323846);
    return;

  case 0x2d: // DTR (degrees to radians)
    mm57109_set_x(m_mm_x * 3.14159265358979323846 / 180.0);
    return;

  case 0x2e: // POP (drop X)
    mm57109_pop();
    return;

  case 0x30: // XEY (swap X and Y)
  {
    double t = m_mm_x;
    m_mm_x = m_mm_y;
    m_mm_y = t;
    return;
  }

  case 0x31: // EX (e^x)
    mm57109_set_x(std::exp(m_mm_x));
    return;

  case 0x32: // 10X
    mm57109_set_x(std::pow(10.0, m_mm_x));
    return;

  case 0x33: // SQ
    mm57109_set_x(m_mm_x * m_mm_x);
    return;

  case 0x34: // SQRT
    if (m_mm_x < 0.0) {
      m_mm_error = true;
      mm57109_set_x(0.0);
    } else
      mm57109_set_x(std::sqrt(m_mm_x));
    return;

  case 0x35: // LN (natural log)
    if (m_mm_x <= 0.0) {
      m_mm_error = true;
      mm57109_set_x(0.0);
    } else
      mm57109_set_x(std::log(m_mm_x));
    return;

  case 0x36: // LOG (common log, base 10)
    if (m_mm_x <= 0.0) {
      m_mm_error = true;
      mm57109_set_x(0.0);
    } else
      mm57109_set_x(std::log10(m_mm_x));
    return;

  case 0x37: // 1/X
    if (m_mm_x == 0.0) {
      m_mm_error = true;
      mm57109_set_x(0.0);
    } else
      mm57109_set_x(1.0 / m_mm_x);
    return;

  case 0x38: // YX (Y^X)
  {
    double x = mm57109_pop();
    double y = mm57109_pop();
    mm57109_push(std::pow(y, x));
    return;
  }

  case 0x24: // SIN
  {
    double a = m_mm_x;
    if (m_mm_deg_mode)
      a = a * 3.14159265358979323846 / 180.0;
    mm57109_set_x(std::sin(a));
    return;
  }
  case 0x25: // COS
  {
    double a = m_mm_x;
    if (m_mm_deg_mode)
      a = a * 3.14159265358979323846 / 180.0;
    mm57109_set_x(std::cos(a));
    return;
  }
  case 0x26: // TAN
  {
    double a = m_mm_x;
    if (m_mm_deg_mode)
      a = a * 3.14159265358979323846 / 180.0;
    mm57109_set_x(std::tan(a));
    return;
  }

  case 0x13: // TXF*  (test |X| < 1 -> expose BR/RDY for BURP $058A)
  {
    const bool abs_x_lt_1 = (std::fabs(m_mm_x) < 1.0);
    // m_mm_RDY = !abs_x_lt_1; // don't interfere with $042E handshake READY
    // m_mm_BR_state = abs_x_lt_1;  // RDY bit for $058A (bit5)
    LOGMASKED(LOG_MM57109, "MM57109: TXF* (|X|<1=%d) m_mm_x=%f @PC=%04X\n", abs_x_lt_1,
              m_mm_x, (u16)m_cpu->pc());
    return;
  }

  case 0x22: // TOGM
    m_mm_deg_mode = !m_mm_deg_mode;
    return;

  case 0x3f: // NOP
    return;

  default:
    break;
  }

  LOGMASKED(
      LOG_MM57109,
      "MM57109: UNIMPLEMENTED op=%02X(%03o) %-10s @PC=%04X (inv_pending=%d)\n",
      opcode, unsigned(opcode), mm57109_opcode_mn(opcode), (u16)m_cpu->pc(),
      m_mm_inv_pending ? 1 : 0);
}

void psicomp80_state::mm57109_execute(u8 op) {

  const u8 opcode = op & 0x3f;
  const bool is_branch = (opcode == 0x13); // TXF*
  const bool branch_state = is_branch ? (std::fabs(m_mm_x) < 1.0) : false;
  mm57109_begin_processing(opcode, is_branch, branch_state);


  LOGMASKED(LOG_MM57109,
	"MM57109: execute regs op=%02X(%03o) %-10s X=%g Y=%g Z=%g T=%g M=%g "
	"deg=%d mant=%u err=%d m_mm_RDY=%s m_mm_BR_state=%s\n",
    op, unsigned(op), mm57109_opcode_mn(op), m_mm_x,
	m_mm_y, m_mm_z, m_mm_t, m_mm_m, m_mm_deg_mode ? 1 : 0,
	unsigned(m_mm_mant_digits), m_mm_error ? 1 : 0,
	m_mm_RDY ? "true" : "false", m_mm_BR_state ? "true" : "false");


  

  // Handle pending 2nd word for prior 2-word op
  if (m_mm_two_word_pending) {
    const u8 twoop = m_mm_two_word_op;
    LOGMASKED(LOG_MM57109,
              "MM57109: 2ndword for %02X(%03o) %-10s = %02X(%03o) @PC=%04X\n",
              twoop, unsigned(twoop), mm57109_opcode_mn(twoop), opcode,
              unsigned(opcode), (u16)m_cpu->pc());

    m_mm_two_word_pending = false;
    m_mm_two_word_op = 0x00;

    // OUT* (0x16) is used by BURP to read X in scientific notation. Treat the
    // param word as the completion trigger and emit the digit stream via paced
    // IM 1 interrupts.
    if (twoop == 0x16) {
      mm57109_emit_out_scientific_stream_from_x();
      mm57109_log_regs("after OUT*", twoop);
     
      return;
    }

    return;
  }

  // INV prefix affects interpretation of the next opcode; keep tracking for
  // logging.
  if (!m_mm_inv_pending && opcode == 0x20) {
    m_mm_inv_pending = true;
    LOGMASKED(LOG_MM57109, "MM57109: INV prefix armed\n");
    return;
  }

  if (mm57109_is_two_word(opcode)) {
    m_mm_two_word_pending = true;
    m_mm_two_word_op = opcode;
    LOGMASKED(LOG_MM57109,
              "MM57109: 2-word op %02X(%03o) %-10s awaiting param\n", opcode,
              unsigned(opcode), mm57109_opcode_mn(opcode));
    return;
  }

  mm57109_execute_single(opcode);
  mm57109_log_regs("after", opcode);

}

void psicomp80_state::mm57109_dump_stream(const char *tag, u8 cmd) {
  LOGMASKED(LOG_MM57109,
            "MM57109[%s] #%llu cmd=%02X(%03o) %-10s stream_len=%zu: ", tag,
            (unsigned long long)m_mm_tx_seq, cmd, unsigned(cmd),
            mm57109_opcode_name(cmd), m_mm_stream.size());
  for (u8 b : m_mm_stream)
    LOGMASKED(LOG_MM57109, "%02X(%03o) ", b, unsigned(b));
  LOGMASKED(LOG_MM57109, "\n");

  m_mm_stream.clear();
  ++m_mm_tx_seq;
}

void psicomp80_state::port60_w(u8 data) {
  // const u8 op = data & 0x7f;

  // const char *opname = mm57109_opcode_name(op);
  // LOGMASKED(LOG_MM57109, "MM57109 W: OUT ($60),%02X(%03o) %-10s @PC=%04X
  // (bit7=%d)\n", 	data, unsigned(data), opname, (u16)m_cpu->pc(), (data >> 7) &
  // 1);

  // Two-phase HOLD/RDY handshake as used by BURP routine $042E.
  //
  // NOTE: The byte passed into $042E can legitimately have bit7 set (it is BURP
  // "bytecode"), and $042E itself generates the phase2 write by OR'ing bit7.
  // Real hardware uses the handshake semantics rather than treating bit7 as
  // part of the payload, so model this as a simple two-step state machine:
  //   1) first OUT -> latch payload (data&0x7f), assert RDY (bit5) so $0439
  //   loop can exit 2) second OUT -> commit latched payload, drop RDY so $0430
  //   loop can exit next time
  //
  // This prevents hangs at $0439 if the *first* write happens to have bit7=1.
//   if (m_mm_expect_latch) {
//     m_mm_latch = data & 0x7f;
//     // LOGMASKED(LOG_MM57109, "MM57109: phase1 latch=%02X(%03o) %-10s
//     // (raw=%02X(%03o))\n", 	m_mm_latch, unsigned(m_mm_latch),
//     // mm57109_opcode_name(m_mm_latch), data, unsigned(data));

//     m_mm_RDY = true;
//     m_mm_expect_latch = false;
//     return;
//   }

if (BIT(data, 7)) {
  m_mm_HOLD = true;
  return;
} else {
	m_mm_HOLD = false;
}

  // Execute phase
  //const u8 committed = m_mm_latch;
  const char *mn = m_mm_inv_pending ? mm57109_inv_second_name(data)
                                    : mm57109_opcode_name(data);
  LOGMASKED(LOG_MM57109,
            "[t=%.6f] MM57109: [OUT] instruction executed byte=%02X %-10s @PC=%04X\n",
            MM_TS(), data & 0x7f, mn, (u16)m_cpu->pc());
  m_mm_irq0_asserted = false;
  m_mm_stream.push_back(data);
  mm57109_execute(data);

//   m_mm_RDY = false;
//   m_mm_expect_latch = true;

  // Status bits are handled by mm57109_execute() for now.
}

// ------------------ keyboard / interrupts ------------------

u8 psicomp80_state::ascii_to_mm_code(u8 data) {
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

void psicomp80_state::mm_set_data_ready(u8 code) {
  m_mm_code = code & 0x0f;
  m_mm_one_shot_clear = false;

  // Pulse IRQ0 so each delivered nibble becomes a distinct IM 1 interrupt.
  m_cpu->pulse_input_line(INPUT_LINE_IRQ0, attotime::from_usec(1));
}

void psicomp80_state::kbd_put(u8 data) {
  // The real COMP80 has a dedicated RESET key. For convenience in the
  // emulation, bind that to the host ESC key.
  //
  // generic_keyboard_device delivers character codes; ESC arrives as 0x1B.
  if (data == 0x1b) {
    machine().schedule_soft_reset();
    return;
  }

  // The COMP80 keyboard interface is a latched ASCII byte with a single strobe
  // to NMI. The monitor's NMI routine will reset if NMI arrives while the CPU
  // is not in HALT, so we must avoid generating extra strobes (e.g. key-up
  // events / auto-repeat bursts). Treat 0x00 as "no character" and ignore it.
  if (data == 0x00)
    return;

  // Debounce / one-shot strobe: ignore further key events until the monitor
  // reads port 0x01 (port01_r clears m_key_latch back to 0xFF).
  if (m_key_latch != 0xff)
    return;

  m_key_latch = ~data;

  m_cpu->pulse_input_line(INPUT_LINE_NMI, attotime::zero);

  mm_set_data_ready(ascii_to_mm_code(data));
}

// ------------------ character mapping / display ------------------

static inline u8 map_code6_to_ascii_index(u8 code6) {
  // Returns index into ascii_font_64x8x5 (0..63 corresponding to ASCII
  // 0x20..0x5F), or 0 for space if unknown.
  if (code6 == 0x00)
    return 0; // space

  if (code6 >= 0x01 && code6 <= 0x1A) {
    // 'A' is ASCII 0x41, so (0x41 - 0x20) = 0x21 is the index for 'A'.
    return u8(0x21 + (code6 - 1));
  }

  if (code6 >= 0x20 && code6 <= 0x3F)
    return u8(code6 - 0x20);

  return 0;
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

  // Cassette (digital bitstream)
  COMP80_TAPE(config, m_tape, 0);

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
ROM_LOAD("psicomp80.rom", 0x0000, 0x0c00,
         CRC(b4641327) SHA1(ce29367b7379c8a37eebb73e457052e8a6f7b6df))
ROM_END

COMP(1979, psicomp80, 0, 0, psicomp80, psicomp80, psicomp80_state, empty_init,
     "PSI/Powertran", "COMP80", MACHINE_NOT_WORKING | MACHINE_NO_SOUND)
