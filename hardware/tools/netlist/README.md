# PSI COMP 80 netlist

The electrical connections of the main board, transcribed pin by pin from the circuit
diagrams in the Wireless World articles (J. H. Adams, 1979). `merge_netlist.py` combines
the per-figure files into `psicomp80_netlist.json`, which `make_kicad.py` uses to put a
net on every pad.

| File | Source | Contents |
|---|---|---|
| `net_cpu.json` | Part 1, Fig. 2 (main processing circuit); Part 3, Fig. 18 | Z80, I/O decoders, keyboard input buffer, MM57109 interface, reset and clock |
| `net_mem.json` | Part 2, Fig. 6 (memory) | address buffers, 74LS138 block decoder, four 2708 EPROMs, forty 21L02 RAMs, output buffer, links |
| `net_vdu.json` | Part 2, Fig. 8 (visual display) | 8 MHz oscillator, counter chain, sync, video RAM and multiplexers, 2513 character generator, shift register |
| `net_io.json` | Part 2, Figs. 12, 15, 16 | tape interface, teleprinter interface (not built on this board), power supply |
| `net_kbd.json` | not in the articles | AY-5-2376 keyboard encoder and key matrix, worked out from the GI datasheet |
| `net_board.json` | kit layout sheet | video output pads and spare decoupling capacitors |

Each file lists every pin of every part, and an `uncertain` list says where the figure
had to be interpreted. Read those before trusting a particular pin. The common cases are:

- **Gate and buffer pin numbers.** Several figures draw gates and buffers without pin
  numbers: IC7, IC9–IC14, IC28, IC31–IC33, IC49, IC51–IC53. What each gate does is
  certain, but which gate of a package is used is a choice. Any gate in the same
  package does the same job.
- **Representative blocks.** The figures draw one 21L02 bank and one video RAM pair.
  The netlist expands them to all 40 and 14 chips, using the rules stated in the
  figure text.
- **Power pins** come from the datasheets, because the figures rarely draw them.
- **The keyboard matrix is inferred.** The articles show no keyboard encoder, so each
  key's row and column is the 2376 crossing that produces the key's ASCII code. The
  kit's real wiring may differ.
- **Placeholder references.** Where a figure prints no reference designators, parts
  get placeholder names: `R_CPU3`, `TAPE_R7`, `PSU_C2`, ... Kit references (R40, C14,
  TR9, ...) are used wherever the match is clear.

## Decisions made in the merge

- **Clock names.** Fig. 2's clock input and Fig. 8's "to Z80 clock input" are one net,
  `CLK_2MHZ`. The MM57109 clock is `MM57109_CLK`.
- **−4 V.** Fig. 2's −4 V for the MM57109 is the supply's −4.5 V rail, `-4_5V`.
- **Reset.** The RESET key (SW43) is Fig. 2's reset switch, so it shorts `RESET_N` to 0 V.
- **Teleprinter.** The Fig. 15 interface is left off the board. It needs a second 4013,
  two MJE340s and 2 W resistors, none of which are on the kit.
- **Bridge rectifiers.** The article's two bridges are built from discrete 1N4002s,
  D4–D7 and D8–D11, as on the kit sheet.
- **VR1.** VR1's wiper is tied to one end, so it works as the variable resistor drawn
  in Fig. 8.

## Known differences from the Powertran kit

- The kit's tape interface is a modified version with more parts. The netlist
  follows the article.
- Some values changed on the kit or in the "points arising" sheet, for example
  R41 0R56 → 2R2.
- IC13 and IC27 must be 81LS95 (non-inverting, one shared enable). The kit sheet
  appears to say 81LS98.
- The expansion plug J1 has no published pinout, so the one here is ours (in `net_board.json`):
  the system bus, the 2 MHz clock, the memory enable that the Fig. 7 expansion drives, the
  eleven spare port selects and the supplies. The October 1980 floppy-disc controller needs
  exactly a subset of these. Pins 1 and 3 are left unconnected, as a track passes too close
  to them for a supply pad.

## Signals that genuinely go nowhere

These nets have only one connection, and that is intended:

- the unused 74LS138 port-decoder outputs (`CPU_IC2_Y*`, `CPU_IC3_Y*`)
- the Z80's M1, RFSH and BUSAK
- A13 and A14, which the base board doesn't decode
- the four uncommitted keys
- the 2376 columns X0 and X1, which only produce control codes
