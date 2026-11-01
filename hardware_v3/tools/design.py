"""The COMP80 v3 board: an AMD Artix-7 XC7A100T that is the COMP80 in logic.

  python3 design.py

writes ../netlist.json, ../bom.csv and ../rtl/comp80v3.xdc (the FPGA's pins, so
the board and the logic can't disagree). make_board.py builds the KiCad board
from the same tables, and make_page.py uses them for ../../hardware_v3.html.

The FPGA holds the Z80, the 64 KB of memory, the ports, the display and HDMI
(../rtl). It loads its configuration from the SPI flash U2 at power-on, clocked
by a 100 MHz oscillator. Three buck regulators make 1.0 V (core and block RAM),
1.8 V (auxiliary) and 3.3 V (every I/O bank) from the USB-C 5 V.

Positions are in mm from the board's top-left corner, y down. HDMI and USB-A
are on the top edge, the microSD on the right, USB-C on the left, and the JTAG
and serial headers along the bottom.
"""
import csv, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..")
BALLS = json.load(open(os.path.join(HERE, "fgg484.json")))

BOARD_W, BOARD_H = 100.0, 72.0
HOLES = [(3.5, 3.5), (96.5, 3.5), (3.5, 68.5), (96.5, 68.5)]
FPGA_AT = (50.0, 36.0)

R = "Resistor_SMD:R_0603_1608Metric"
C = "Capacitor_SMD:C_0603_1608Metric"
C04 = "Capacitor_SMD:C_0402_1005Metric"
C08 = "Capacitor_SMD:C_0805_2012Metric"
C12 = "Capacitor_SMD:C_1210_3225Metric"

PARTS = {
    "U1": ("XC7A100T-1FGG484C", "Package_BGA:Xilinx_FGG484", "AMD XC7A100T-1FGG484C",
           "FPGA: 101,440 logic cells, 4,860 Kb of block RAM. The whole COMP80 is in here"),
    "U2": ("IS25LP128F", "Package_SO:SOIC-8_5.3x5.3mm_P1.27mm", "ISSI IS25LP128F-JBLE",
           "16 MB SPI flash: the FPGA's configuration and the soft processor's program"),
    "U3": ("TLV62569DBV", "Package_TO_SOT_SMD:SOT-23-5", "TI TLV62569DBVR", "2 A buck regulator: 1.0 V for the FPGA's core and block RAM"),
    "U4": ("TLV62569DBV", "Package_TO_SOT_SMD:SOT-23-5", "TI TLV62569DBVR", "2 A buck regulator: 1.8 V for the FPGA's auxiliary supply"),
    "U5": ("TLV62569DBV", "Package_TO_SOT_SMD:SOT-23-5", "TI TLV62569DBVR", "2 A buck regulator: 3.3 V for the I/O banks and everything else"),
    "L1": ("2.2uH", "Inductor_SMD:L_1008_2520Metric", "Murata DFE252012F-2R2M", "Inductor for the 1.0 V regulator"),
    "L2": ("2.2uH", "Inductor_SMD:L_1008_2520Metric", "Murata DFE252012F-2R2M", "Inductor for the 1.8 V regulator"),
    "L3": ("2.2uH", "Inductor_SMD:L_1008_2520Metric", "Murata DFE252012F-2R2M", "Inductor for the 3.3 V regulator"),
    "X1": ("100MHz", "Oscillator:Oscillator_SMD_ECS_2520MV-xxx-xx-4Pin_2.5x2.0mm", "ECS-2520MV-1000-BN-TR",
           "100 MHz oscillator: the FPGA's clock"),
    "J1": ("USB-C", "Connector_USB:USB_C_Receptacle_GCT_USB4105-xx-A_16P_TopMnt_Horizontal", "GCT USB4105-GF-A",
           "Power in, 5 V"),
    "J2": ("HDMI", "Connector_Video:HDMI_A_Molex_208658-1001_Horizontal", "Molex 208658-1001", "HDMI type A socket: the display"),
    "J3": ("USB-A", "Connector_USB:USB_A_Wuerth_614004134726_Horizontal", "Wurth 614004134726", "USB-A socket for the keyboard"),
    "J4": ("microSD", "Connector_Card:microSD_HC_Hirose_DM3AT-SF-PEJM5", "Hirose DM3AT-SF-PEJM5", "microSD socket: ROM images and tapes"),
    "J5": ("JTAG", "Connector_PinHeader_2.54mm:PinHeader_1x06_P2.54mm_Vertical", "0.1 in header, 6 way",
           "JTAG for Vivado: VREF, GND, TCK, TDO, TDI, TMS, the order of Digilent's 6-pin cables"),
    "J6": ("SERIAL", "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical", "0.1 in header, 2 way",
           "The soft processor's serial console out (115200 baud) and ground"),
    "SW1": ("RESET", "Button_Switch_SMD:SW_SPST_B3S-1000", "Omron B3S-1000", "Powers the COMP80 on again (the logic, not the FPGA)"),
    "SW2": ("PROG", "Button_Switch_SMD:SW_SPST_B3S-1000", "Omron B3S-1000", "Pulls PROGRAM_B: the FPGA reloads itself from the flash"),
    "D1": ("HALT", "LED_SMD:LED_0805_2012Metric", "red LED, 0805", "Lit while the Z80 is halted, as the original's HALT LED"),
    "D2": ("DONE", "LED_SMD:LED_0805_2012Metric", "green LED, 0805", "Lit once the FPGA has loaded its configuration"),
    "D3": ("BAT54J", "Diode_SMD:D_SOD-323F", "Nexperia BAT54J", "Feeds the HDMI +5 V pin"),
    "F1": ("500mA", "Fuse:Fuse_1206_3216Metric", "Bourns MF-MSMF050-2", "Resettable fuse for the keyboard's 5 V"),
}
for n, (x, y) in enumerate(HOLES):
    PARTS[f"H{n + 1}"] = ("M2.5", "MountingHole:MountingHole_2.7mm_M2.5", "", "Mounting hole")


def passive(ref, value, fp, desc, part=""):
    PARTS[ref] = (value, fp, part, desc)


passive("R1", "5.1k", R, "USB-C CC1: asks the supply for 5 V")
passive("R2", "5.1k", R, "USB-C CC2: asks the supply for 5 V")
# regulator feedback: Vout = 0.6 V x (1 + Rtop / Rbottom)
for i, (rail, top, bot) in enumerate((("1.0 V", "200k", "301k"), ("1.8 V", "200k", "100k"), ("3.3 V", "453k", "100k"))):
    passive(f"R{3 + 2 * i}", top, R, f"{rail} regulator feedback, top")
    passive(f"R{4 + 2 * i}", bot, R, f"{rail} regulator feedback, bottom")
passive("R9", "4.7k", R, "PROGRAM_B pull-up")
passive("R10", "4.7k", R, "INIT_B pull-up")
passive("R11", "330R", R, "DONE pull-up")
passive("R12", "1k", R, "DONE LED current")
passive("R13", "1k", R, "PUDC_B to 3.3 V: I/O pull-ups off while configuring")
passive("R14", "330R", R, "HALT LED current")
passive("R15", "10k", R, "RESET button pull-up")
for i, sig in enumerate(("DAT0", "DAT3/CS", "CMD", "DAT1", "DAT2")):
    passive(f"R{16 + i}", "10k", R, f"microSD {sig} pull-up")
passive("R21", "15k", R, "Keyboard USB D+ pull-down (host side)")
passive("R22", "15k", R, "Keyboard USB D- pull-down (host side)")
passive("R23", "10k", R, "Flash chip select pull-up")
for i, rail in enumerate(("1.0 V", "1.8 V", "3.3 V")):
    passive(f"C{1 + 2 * i}", "10u", C08, f"{rail} regulator input")
    passive(f"C{2 + 2 * i}", "22u", C08, f"{rail} regulator output")
passive("C7", "100u", C12, "FPGA core supply (VCCINT, VCCBRAM) bulk")
passive("C8", "47u", C12, "FPGA auxiliary supply (VCCAUX) bulk")
passive("C9", "47u", C12, "I/O supply (VCCO) bulk")
passive("C10", "100n", C, "Oscillator decoupling")
passive("C11", "100n", C, "Flash decoupling")
passive("C12", "10u", C08, "microSD supply")
passive("C13", "100n", C, "microSD decoupling")
passive("C14", "10u", C08, "Keyboard 5 V")
passive("C15", "10u", C08, "USB-C 5 V in")

# The FPGA's decoupling, as the 7 series PCB guide (UG483) asks, rounded:
# 0.47 uF beside the supply balls, 4.7 uF a little further out.
DECOUPLE = []          # (ref, net, value)
n = 16
for net, small, mid in (("+1V0", 8, 3), ("+1V8", 4, 2), ("+3V3", 10, 2)):
    for k in range(small):
        DECOUPLE.append((f"C{n}", net, "470n")); n += 1
    for k in range(mid):
        DECOUPLE.append((f"C{n}", net, "4.7u")); n += 1
for ref, net, value in DECOUPLE:
    rail = {"+1V0": "core (VCCINT, VCCBRAM)", "+1V8": "auxiliary (VCCAUX)", "+3V3": "I/O (VCCO)"}[net]
    passive(ref, value, C04 if value == "470n" else C, f"FPGA {rail} decoupling")

# ------------------------------------------------------------------ the FPGA's pins
# The design's ports (../rtl/top.v) and the balls they use. Bank 16 (top edge)
# has the clock and HDMI, bank 15 (right) the microSD, bank 13 (bottom) the rest.
# Every bank's VCCO is 3.3 V, so all of these are LVCMOS33 but HDMI's TMDS_33.
IO = {
    "clk100": ("B17", "LVCMOS33", "100 MHz oscillator (bank 16 SRCC)"),
    "tmds_p[0]": ("A13", "TMDS_33", "HDMI data 0+ (blue)"), "tmds_n[0]": ("A14", "TMDS_33", "HDMI data 0-"),
    "tmds_p[1]": ("A15", "TMDS_33", "HDMI data 1+ (green)"), "tmds_n[1]": ("A16", "TMDS_33", "HDMI data 1-"),
    "tmds_p[2]": ("B15", "TMDS_33", "HDMI data 2+ (red)"), "tmds_n[2]": ("B16", "TMDS_33", "HDMI data 2-"),
    "tmds_p[3]": ("A18", "TMDS_33", "HDMI clock+"), "tmds_n[3]": ("A19", "TMDS_33", "HDMI clock-"),
    "usb_dp": ("B20", "LVCMOS33", "Keyboard USB D+"),
    "usb_dm": ("A20", "LVCMOS33", "Keyboard USB D-"),
    "sd_sck": ("J22", "LVCMOS33", "microSD CLK"),
    "sd_mosi": ("H22", "LVCMOS33", "microSD CMD"),
    "sd_miso": ("K22", "LVCMOS33", "microSD DAT0"),
    "sd_cs_n": ("M22", "LVCMOS33", "microSD DAT3/CS"),
    "uart_tx": ("AB10", "LVCMOS33", "Serial console out"),
    "led_halt": ("AB11", "LVCMOS33", "HALT LED"),
    "btn_reset_n": ("AB12", "LVCMOS33", "RESET button (low when pressed)"),
}
IO_NET = {"clk100": "CLK100", "usb_dp": "USBH_DP", "usb_dm": "USBH_DM", "sd_sck": "SD_SCK", "sd_mosi": "SD_MOSI",
          "sd_miso": "SD_MISO", "sd_cs_n": "SD_CS", "uart_tx": "UART_TX", "led_halt": "HALT_LED",
          "btn_reset_n": "RESET_N",
          "tmds_p[0]": "TMDS_D0P", "tmds_n[0]": "TMDS_D0N", "tmds_p[1]": "TMDS_D1P", "tmds_n[1]": "TMDS_D1N",
          "tmds_p[2]": "TMDS_D2P", "tmds_n[2]": "TMDS_D2N", "tmds_p[3]": "TMDS_CKP", "tmds_n[3]": "TMDS_CKN"}

# configuration and JTAG balls
CONFIG = {"L12": "FLASH_SCK", "P22": "FLASH_IO0", "R22": "FLASH_IO1", "P21": "FLASH_IO2", "R21": "FLASH_IO3",
          "T19": "FLASH_CS", "N12": "PROGRAM_B", "U12": "INIT_B", "G11": "DONE", "U13": "TDO", "R13": "TDI",
          "T13": "TMS", "V12": "TCK", "U22": "PUDC_B",
          "U11": "+3V3",     # M0 = 1, M1 = M2 = 0: Master SPI
          "U10": "GND", "U9": "GND",
          "U8": "+3V3"}      # CFGBVS: bank 0 at 3.3 V


def ball_net(ball, name):
    """The net of an FPGA ball that isn't one of the design's I/O."""
    if ball in CONFIG:
        return CONFIG[ball]
    base = name.rsplit("_", 1)[0] if name[-1].isdigit() and "_" in name else name
    if name.startswith(("VCCINT", "VCCBRAM")):
        return "+1V0"
    if name.startswith(("VCCAUX", "VCCADC")):
        return "+1V8"
    if name.startswith("VCCO"):
        return "+3V3"
    if name.startswith(("GND", "VREFP", "VREFN", "VP_", "VN_", "VCCBATT")):
        return "GND"
    # transceivers unused: supplies and receivers grounded, the rest open
    if name.startswith(("MGTAVCC", "MGTAVTT", "MGTPRX")):
        return "GND"
    return None        # unused I/O, transmitters, reference clocks, DXP/DXN, MGTRREF


NETS = {}


def join(net, *pins):
    NETS.setdefault(net, []).extend(pins)


io_balls = {ball: IO_NET[port] for port, (ball, _, _) in IO.items()}
for ball, name in BALLS.items():
    net = io_balls.get(ball) or ball_net(ball, name)
    if net:
        join(net, ("U1", ball))

# power in
join("+5V", ("J1", "A4"), ("J1", "B4"), ("J1", "A9"), ("J1", "B9"), ("C15", "1"), ("F1", "1"), ("D3", "2"))
join("GND", ("J1", "A1"), ("J1", "B1"), ("J1", "A12"), ("J1", "B12"), ("J1", "SH"), ("R1", "2"), ("R2", "2"), ("C15", "2"))
join("USBC_CC1", ("J1", "A5"), ("R1", "1"))
join("USBC_CC2", ("J1", "B5"), ("R2", "1"))

# the regulators: pin 1 EN, 2 GND, 3 SW, 4 VIN, 5 FB
for i, (u, l, rail) in enumerate((("U3", "L1", "+1V0"), ("U4", "L2", "+1V8"), ("U5", "L3", "+3V3"))):
    cin, cout, rt, rb = f"C{1 + 2 * i}", f"C{2 + 2 * i}", f"R{3 + 2 * i}", f"R{4 + 2 * i}"
    join("+5V", (u, "1"), (u, "4"), (cin, "1"))
    join("GND", (u, "2"), (cin, "2"), (cout, "2"), (rb, "2"))
    join(f"SW_{rail[1:]}", (u, "3"), (l, "1"))
    join(rail, (l, "2"), (cout, "1"), (rt, "1"))
    join(f"FB_{rail[1:]}", (u, "5"), (rt, "2"), (rb, "1"))
join("+1V0", ("C7", "1"))
join("+1V8", ("C8", "1"))
join("+3V3", ("C9", "1"))
join("GND", ("C7", "2"), ("C8", "2"), ("C9", "2"))
for ref, net, value in DECOUPLE:
    join(net, (ref, "1"))
    join("GND", (ref, "2"))

# clock: oscillator pin 1 OE, 2 GND, 3 OUT, 4 VDD
join("+3V3", ("X1", "1"), ("X1", "4"), ("C10", "1"))
join("GND", ("X1", "2"), ("C10", "2"))
join("CLK100", ("X1", "3"))

# configuration flash: 1 CS, 2 IO1, 3 IO2, 4 GND, 5 IO0, 6 SCK, 7 IO3, 8 VCC
join("FLASH_CS", ("U2", "1"), ("R23", "1"))
join("FLASH_IO1", ("U2", "2"))
join("FLASH_IO2", ("U2", "3"))
join("FLASH_IO0", ("U2", "5"))
join("FLASH_SCK", ("U2", "6"))
join("FLASH_IO3", ("U2", "7"))
join("+3V3", ("U2", "8"), ("C11", "1"), ("R23", "2"))
join("GND", ("U2", "4"), ("C11", "2"))

# configuration pins
join("PROGRAM_B", ("R9", "1"), ("SW2", "1"))
join("INIT_B", ("R10", "1"))
join("DONE", ("R11", "1"), ("R12", "1"))
join("DONE_LED", ("R12", "2"), ("D2", "2"))
join("PUDC_B", ("R13", "1"))
join("+3V3", ("R9", "2"), ("R10", "2"), ("R11", "2"), ("R13", "2"), ("R15", "2"))
join("GND", ("SW2", "2"), ("D2", "1"), ("D1", "1"), ("SW1", "2"))

# JTAG: VREF, GND, TCK, TDO, TDI, TMS
join("+3V3", ("J5", "1"))
join("GND", ("J5", "2"))
join("TCK", ("J5", "3"))
join("TDO", ("J5", "4"))
join("TDI", ("J5", "5"))
join("TMS", ("J5", "6"))

# serial, HALT LED, RESET
join("UART_TX", ("J6", "1"))
join("GND", ("J6", "2"))
join("HALT_LED", ("R14", "1"))
join("HALT_LED_A", ("R14", "2"), ("D1", "2"))
join("RESET_N", ("R15", "1"), ("SW1", "1"))

# HDMI straight from the TMDS_33 outputs
for net, pin in (("TMDS_D2P", 1), ("TMDS_D2N", 3), ("TMDS_D1P", 4), ("TMDS_D1N", 6), ("TMDS_D0P", 7),
                 ("TMDS_D0N", 9), ("TMDS_CKP", 10), ("TMDS_CKN", 12)):
    join(net, ("J2", str(pin)))
join("GND", ("J2", "2"), ("J2", "5"), ("J2", "8"), ("J2", "11"), ("J2", "17"), ("J2", "SH"))
join("HDMI_5V", ("D3", "1"), ("J2", "18"))

# keyboard
join("USBH_DP", ("R21", "1"), ("J3", "3"))
join("USBH_DM", ("R22", "1"), ("J3", "2"))
join("USBH_VBUS", ("F1", "2"), ("C14", "1"), ("J3", "1"))
join("GND", ("R21", "2"), ("R22", "2"), ("C14", "2"), ("J3", "4"), ("J3", "SH"))

# microSD: 1 DAT2, 2 DAT3/CS, 3 CMD, 4 VDD, 5 CLK, 6 VSS, 7 DAT0, 8 DAT1
join("SD_MISO", ("J4", "7"), ("R16", "2"))
join("SD_CS", ("J4", "2"), ("R17", "2"))
join("SD_MOSI", ("J4", "3"), ("R18", "2"))
join("SD_SCK", ("J4", "5"))
join("SD_DAT1", ("J4", "8"), ("R19", "2"))
join("SD_DAT2", ("J4", "1"), ("R20", "2"))
join("+3V3", ("J4", "4"), ("C12", "1"), ("C13", "1"), *[(f"R{16 + i}", "1") for i in range(5)])
join("GND", ("J4", "6"), ("J4", "SH"), ("C12", "2"), ("C13", "2"))

# ------------------------------------------------------------------ placement
PLACE = {
    "U1": (FPGA_AT[0], FPGA_AT[1], 0),
    "X1": (47.0, 19.0, 0), "C10": (43.5, 19.0, 90),
    "J1": (0.0, 54.0, 270),
    "J2": (57.0, 0.0, 90),
    "J3": (84.0, 0.0, 180),
    "J4": (100.0, 34.0, 90),
    "U2": (78.0, 52.0, 0), "C11": (83.5, 52.0, 90), "R23": (72.0, 47.5, 90),
    "J5": (40.0, 68.0, 90),
    "J6": (58.0, 68.0, 90),
    "SW1": (73.0, 65.5, 0), "SW2": (86.0, 65.5, 0),
    "D1": (66.0, 61.5, 0), "R14": (66.0, 64.0, 0),
    "D2": (35.0, 62.0, 0), "R12": (35.0, 64.5, 0),
    "R9": (82.0, 59.5, 0), "R15": (73.0, 59.5, 0), "R10": (64.5, 52.0, 90), "R11": (35.0, 52.0, 90),
    "R13": (66.5, 46.0, 90),
    "D3": (66.0, 15.5, 0),
    "F1": (75.0, 13.0, 90), "C14": (75.0, 18.0, 90),
    "R21": (92.0, 18.0, 0), "R22": (92.0, 20.0, 0),
    "R1": (7.0, 46.0, 90), "R2": (7.0, 62.0, 90), "C15": (10.5, 60.0, 90),
    "C12": (86.0, 46.0, 90), "C13": (88.5, 46.0, 90),
    "C7": (31.5, 30.0, 90), "C8": (31.5, 40.0, 90), "C9": (68.5, 30.0, 90),
}
for i in range(5):
    PLACE[f"R{16 + i}"] = (76.0, 25.0 + i * 2.0, 0)
# the three regulators, side by side along the bottom left
for i, x in enumerate((14.0, 21.0, 28.0)):
    u, l, cin, cout, rt, rb = f"U{3 + i}", f"L{1 + i}", f"C{1 + 2 * i}", f"C{2 + 2 * i}", f"R{3 + 2 * i}", f"R{4 + 2 * i}"
    PLACE[u] = (x, 52.0, 0)
    PLACE[l] = (x, 56.5, 90)
    PLACE[cin] = (x - 2.5, 48.5, 0)
    PLACE[cout] = (x, 60.5, 0)
    PLACE[rt] = (x + 2.0, 48.5, 90)
    PLACE[rb] = (x + 3.5, 52.0, 90)
for (ref, (x, y)) in zip(("H1", "H2", "H3", "H4"), HOLES):
    PLACE[ref] = (x, y, 0)

# decoupling capacitors in rings round the FPGA: 0.47 uF just outside the ball
# grid, 4.7 uF a row further out (make_board.py sets each one's exact place)
EDGE = {"J1": "left", "J2": "top", "J3": "top", "J4": "right"}
POWER_NETS = ("+5V", "GND", "+3V3", "+1V0", "+1V8", "USBH_VBUS", "HDMI_5V", "SW_1V0", "SW_1V8", "SW_3V3")
PLANES = (("In1.Cu", "GND"), ("In2.Cu", "+3V3"), ("In3.Cu", "+1V0"), ("In4.Cu", "+1V8"))


def pins_of():
    out = {}
    for net, pins in NETS.items():
        for ref, pad in pins:
            out.setdefault(ref, {}).setdefault(pad, net)
    return out


def check():
    pins = pins_of()
    for net, ps in NETS.items():
        assert all(r in PARTS for r, _ in ps), net
    seen = {}
    for net, ps in NETS.items():
        for p in ps:
            if p in seen and seen[p] != net:
                raise SystemExit(f"{p} on {seen[p]} and {net}")
            seen[p] = net
    single = [n for n, ps in NETS.items() if len(set(ps)) < 2]
    assert not single, single
    missing = [r for r in PARTS if r not in PLACE and r not in {d[0] for d in DECOUPLE}]
    assert not missing, missing
    return pins


def xdc():
    lines = ["# COMP80 v3 pins: made by tools/design.py from the board's tables; don't edit.",
             "# Every bank's VCCO is 3.3 V. HDMI uses TMDS_33, which drives the display's",
             "# 50 ohm terminations directly.", "",
             "set_property CFGBVS VCCO [current_design]",
             "set_property CONFIG_VOLTAGE 3.3 [current_design]",
             "set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]",
             "set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]",
             "set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]", ""]
    for port, (ball, std, what) in IO.items():
        lines.append(f"set_property -dict {{PACKAGE_PIN {ball} IOSTANDARD {std}}} [get_ports {{{port}}}]   ;# {what}")
    lines += ["", "create_clock -period 10.000 -name clk100 [get_ports clk100]",
              "# the USB core, the system clock and the pixel clock only meet through synchronisers",
              "set_clock_groups -asynchronous -group [get_clocks -of_objects [get_pins pll/CLKOUT0]] \\",
              "    -group [get_clocks -of_objects [get_pins pll/CLKOUT1]] \\",
              "    -group [get_clocks -of_objects [get_pins mmcm/CLKOUT0]]",
              "set_property PULLDOWN true [get_ports {usb_dp usb_dm}]",
              "set_property PULLUP true [get_ports btn_reset_n]", ""]
    open(os.path.join(OUT, "rtl", "comp80v3.xdc"), "w").write("\n".join(lines))


def main():
    pins = check()
    parts = {ref: {"value": v, "footprint": fp, "part": mpn, "description": d, "pins": pins.get(ref, {})}
             for ref, (v, fp, mpn, d) in PARTS.items()}
    io = {port: {"ball": b, "standard": s, "use": u, "bank": BALLS[b].rsplit("_", 1)[1]} for port, (b, s, u) in IO.items()}
    json.dump({"board": {"width": BOARD_W, "height": BOARD_H, "layers": 6},
               "parts": parts, "nets": {n: [list(p) for p in sorted(set(ps))] for n, ps in NETS.items()},
               "io": io}, open(os.path.join(OUT, "netlist.json"), "w"), indent=1)
    groups = {}
    for ref, (v, fp, mpn, d) in PARTS.items():
        if ref.startswith("H"):
            continue
        key = (v, fp.split(":")[1], mpn, d if ref[0] not in "RC" else "")
        groups.setdefault(key, []).append(ref)
    order = lambda r: (r.rstrip("0123456789"), int(r[len(r.rstrip("0123456789")):]))
    with open(os.path.join(OUT, "bom.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Qty", "References", "Value", "Footprint", "Part", "Description"])
        for (v, fp, mpn, d), refs in sorted(groups.items(), key=lambda kv: order(sorted(kv[1], key=order)[0])):
            refs.sort(key=order)
            if not d:
                d = "; ".join(sorted({PARTS[r][3] for r in refs}))
            w.writerow([len(refs), " ".join(refs), v, fp, mpn, d])
    xdc()
    used = sum(1 for b in BALLS if ("U1", b) in {p for ps in NETS.values() for p in ps})
    print(f"{len(PARTS)} parts, {len(NETS)} nets; {used} of 484 FPGA balls connected")


if __name__ == "__main__":
    main()
