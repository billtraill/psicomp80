"""The COMP80 v2 board: every part, its footprint, where it sits and what its pins join.

  python3 design.py

writes ../netlist.json and ../bom.csv. make_board.py (KiCad's Python) builds the KiCad
board from the same tables, and make_page.py uses them for ../../hardware_v2.html.

One RP2350A runs the unchanged COMP80 ROM images on an emulated Z80, and stands in for
everything else the 1979 board did:
  - HDMI out, from the RP2350's HSTX port (GPIO12-19), 640 x 480 at 60 Hz
  - a USB keyboard on a USB-A socket, through PIO-USB on GPIO20/21
  - ROM images and cassette tapes on a microSD card, in SPI mode on SPI1 (GPIO8-11)
  - power, and the RP2350's own USB for loading firmware, on a USB-C socket

Positions are in mm from the board's top-left corner, with y increasing down the board.
The top edge carries HDMI and USB-A, the left edge USB-C, the right edge the microSD.
"""
import csv, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..")

BOARD_W, BOARD_H = 75.0, 55.0
HOLES = [(3.5, 3.5), (71.5, 3.5), (3.5, 51.5), (71.5, 51.5)]

R = "Resistor_SMD:R_0603_1608Metric"
C = "Capacitor_SMD:C_0603_1608Metric"
C10 = "Capacitor_SMD:C_0805_2012Metric"

# ref: (value, footprint, manufacturer part, description)
PARTS = {
    "U1": ("RP2350A", "Package_DFN_QFN:QFN-60-1EP_7x7mm_P0.4mm_EP3.4x3.4mm", "Raspberry Pi RP2350A",
           "Microcontroller: two Cortex-M33 cores at up to 150 MHz (run here at 240), 520 KB RAM, HSTX, PIO"),
    "U2": ("W25Q32JV", "Package_SO:SOIC-8_5.3x5.3mm_P1.27mm", "Winbond W25Q32JVSSIQ",
           "4 MB QSPI flash: holds the firmware"),
    "U3": ("AP2112K-3.3", "Package_TO_SOT_SMD:SOT-23-5", "Diodes AP2112K-3.3TRG1",
           "3.3 V 600 mA regulator, from the USB-C 5 V"),
    "Y1": ("12MHz", "Crystal:Crystal_SMD_3225-4Pin_3.2x2.5mm", "Abracon ABM8-272-T3",
           "12 MHz crystal for the RP2350's oscillator"),
    "L1": ("3.3uH", "Inductor_SMD:L_0805_2012Metric", "Abracon AOTA-B201610S3R3-101-T",
           "Inductor for the RP2350's on-chip 1.1 V core regulator"),
    "J1": ("USB-C", "Connector_USB:USB_C_Receptacle_GCT_USB4105-xx-A_16P_TopMnt_Horizontal",
           "GCT USB4105-GF-A", "Power in (5 V), and the RP2350's own USB for loading firmware"),
    "J2": ("HDMI", "Connector_Video:HDMI_A_Molex_208658-1001_Horizontal", "Molex 208658-1001",
           "HDMI type A socket: the display"),
    "J3": ("USB-A", "Connector_USB:USB_A_Wuerth_614004134726_Horizontal", "Wurth 614004134726",
           "USB-A socket for the keyboard"),
    "J4": ("microSD", "Connector_Card:microSD_HC_Hirose_DM3AT-SF-PEJM5", "Hirose DM3AT-SF-PEJM5",
           "microSD socket (push-push): ROM images and tapes"),
    "J5": ("DEBUG", "Connector_PinHeader_2.54mm:PinHeader_1x05_P2.54mm_Vertical", "0.1 in header, 5 way",
           "Debug: SWD and the firmware's serial console (not needed to use the computer)"),
    "SW1": ("RESET", "Button_Switch_SMD:SW_SPST_B3S-1000", "Omron B3S-1000",
            "Restarts the RP2350: power-on reset of the COMP80"),
    "SW2": ("BOOTSEL", "Button_Switch_SMD:SW_SPST_B3S-1000", "Omron B3S-1000",
            "Held during reset, the RP2350 appears as a USB drive for new firmware"),
    "D1": ("HALT", "LED_SMD:LED_0805_2012Metric", "red LED, 0805",
           "Lit while the Z80 is halted, as the original's HALT LED"),
    "D2": ("BAT54J", "Diode_SMD:D_SOD-323F", "Nexperia BAT54J",
           "Feeds the HDMI +5 V pin, and stops a display back-powering the board"),
    "F1": ("500mA", "Fuse:Fuse_1206_3216Metric", "Bourns MF-MSMF050-2",
           "Resettable fuse for the keyboard's 5 V"),
    "H1": ("M2.5", "MountingHole:MountingHole_2.7mm_M2.5", "", "Mounting hole"),
    "H2": ("M2.5", "MountingHole:MountingHole_2.7mm_M2.5", "", "Mounting hole"),
    "H3": ("M2.5", "MountingHole:MountingHole_2.7mm_M2.5", "", "Mounting hole"),
    "H4": ("M2.5", "MountingHole:MountingHole_2.7mm_M2.5", "", "Mounting hole"),
}


def passive(ref, value, fp, desc, part=""):
    PARTS[ref] = (value, fp, part, desc)


for ref, desc in (("R1", "USB-C CC1: asks the supply for 5 V"), ("R2", "USB-C CC2: asks the supply for 5 V")):
    passive(ref, "5.1k", R, desc)
passive("R3", "27R", R, "USB D+ series resistor")
passive("R4", "27R", R, "USB D- series resistor")
passive("R5", "33R", R, "Filters the core regulator's analogue supply")
passive("R6", "1k", R, "Crystal drive limit")
passive("R7", "10k", R, "RUN pull-up")
passive("R8", "1k", R, "BOOTSEL: pulls the flash chip select low")
for i, (ref, sig) in enumerate((("R9", "DAT0/MISO"), ("R10", "DAT3/CS"), ("R11", "CMD/MOSI"),
                                ("R12", "DAT1"), ("R13", "DAT2"))):
    passive(ref, "10k", R, f"microSD {sig} pull-up")
for i, sig in enumerate(("D2+", "D2-", "D1+", "D1-", "D0+", "D0-", "CLK+", "CLK-")):
    passive(f"R{14 + i}", "270R", R, f"HDMI TMDS {sig} series resistor")
passive("R22", "27R", R, "Keyboard USB D+ series resistor")
passive("R23", "27R", R, "Keyboard USB D- series resistor")
passive("R24", "15k", R, "Keyboard USB D+ pull-down (host side)")
passive("R25", "15k", R, "Keyboard USB D- pull-down (host side)")
passive("R26", "330R", R, "HALT LED current")

passive("C1", "10u", C10, "Regulator input")
passive("C2", "10u", C10, "Regulator output, 3.3 V")
C04 = "Capacitor_SMD:C_0402_1005Metric"     # the caps right beside U1's 0.4 mm pitch pins
for i in range(6):
    passive(f"C{3 + i}", "100n", C04, "RP2350 IOVDD decoupling")
passive("C9", "100n", C04, "RP2350 QSPI_IOVDD and USB_OTP_VDD decoupling")
passive("C10", "100n", C, "RP2350 3.3 V decoupling, on the plane")
passive("C11", "100n", C04, "RP2350 ADC_AVDD decoupling")
passive("C12", "4.7u", C, "Core regulator input")
passive("C13", "4.7u", C, "Core regulator analogue supply")
passive("C14", "4.7u", C, "Core regulator output, 1.1 V")
for i in range(3):
    passive(f"C{15 + i}", "100n", C04, "RP2350 DVDD decoupling")
passive("C18", "15p", C, "Crystal load")
passive("C19", "15p", C, "Crystal load")
passive("C20", "100n", C, "Flash decoupling")
passive("C21", "10u", C10, "microSD supply")
passive("C22", "100n", C, "microSD decoupling")
passive("C23", "10u", C10, "Keyboard 5 V")


# RP2350A pins (QFN-60), from KiCad's MCU_RaspberryPi symbol
RP2350A = {
    "IOVDD": [1, 11, 20, 30, 38, 45], "DVDD": [6, 23, 39],
    "GPIO0": 2, "GPIO1": 3, "GPIO2": 4, "GPIO3": 5, "GPIO4": 7, "GPIO5": 8, "GPIO6": 9, "GPIO7": 10,
    "GPIO8": 12, "GPIO9": 13, "GPIO10": 14, "GPIO11": 15, "GPIO12": 16, "GPIO13": 17, "GPIO14": 18,
    "GPIO15": 19, "XIN": 21, "XOUT": 22, "SWCLK": 24, "SWDIO": 25, "RUN": 26, "GPIO16": 27,
    "GPIO17": 28, "GPIO18": 29, "GPIO19": 31, "GPIO20": 32, "GPIO21": 33, "GPIO22": 34, "GPIO23": 35,
    "GPIO24": 36, "GPIO25": 37, "GPIO26": 40, "GPIO27": 41, "GPIO28": 42, "GPIO29": 43,
    "ADC_AVDD": 44, "VREG_AVDD": 46, "VREG_PGND": 47, "VREG_LX": 48, "VREG_VIN": 49, "VREG_FB": 50,
    "USB_DM": 51, "USB_DP": 52, "USB_OTP_VDD": 53, "QSPI_IOVDD": 54, "QSPI_SD3": 55, "QSPI_SCLK": 56,
    "QSPI_SD0": 57, "QSPI_SD2": 58, "QSPI_SD1": 59, "QSPI_SS": 60, "GND": 61,
}

# What each RP2350 GPIO does (the firmware's pin map, firmware/board.h, must agree)
GPIO_USE = {
    0: ("UART_TX", "Serial console out (debug header)"),
    1: ("UART_RX", "Serial console in (debug header)"),
    8: ("SD_MISO", "microSD DAT0, SPI1 RX"),
    9: ("SD_CS", "microSD DAT3, SPI1 chip select"),
    10: ("SD_SCK", "microSD CLK, SPI1 SCK"),
    11: ("SD_MOSI", "microSD CMD, SPI1 TX"),
    12: ("HDMI_D2P", "HSTX bit 0: TMDS data 2+ (red)"),
    13: ("HDMI_D2N", "HSTX bit 1: TMDS data 2-"),
    14: ("HDMI_D1P", "HSTX bit 2: TMDS data 1+ (green)"),
    15: ("HDMI_D1N", "HSTX bit 3: TMDS data 1-"),
    16: ("HDMI_D0P", "HSTX bit 4: TMDS data 0+ (blue, and the sync)"),
    17: ("HDMI_D0N", "HSTX bit 5: TMDS data 0-"),
    18: ("HDMI_CKP", "HSTX bit 6: TMDS clock+"),
    19: ("HDMI_CKN", "HSTX bit 7: TMDS clock-"),
    20: ("USBH_DP", "Keyboard USB D+ (PIO-USB)"),
    21: ("USBH_DM", "Keyboard USB D- (PIO-USB; must be D+ plus one)"),
    25: ("HALT_LED", "HALT LED"),
}

# Connections: net -> list of (ref, pad). Power and ground first.
NETS = {}


def join(net, *pins):
    NETS.setdefault(net, []).extend(pins)


def u1(name):
    p = RP2350A[name]
    return [("U1", str(n)) for n in p] if isinstance(p, list) else [("U1", str(p))]


# USB-C: 5 V in, and the RP2350's USB
join("+5V", ("J1", "A4"), ("J1", "B4"), ("J1", "A9"), ("J1", "B9"), ("U3", "1"), ("U3", "3"),
     ("C1", "1"), ("F1", "1"), ("D2", "2"))
join("GND", ("J1", "A1"), ("J1", "B1"), ("J1", "A12"), ("J1", "B12"), ("J1", "SH"), ("R1", "2"), ("R2", "2"),
     ("U3", "2"), ("C1", "2"), ("C2", "2"))
join("USBC_CC1", ("J1", "A5"), ("R1", "1"))
join("USBC_CC2", ("J1", "B5"), ("R2", "1"))
join("USBC_DP", ("J1", "A6"), ("J1", "B6"), ("R3", "1"))
join("USBC_DM", ("J1", "A7"), ("J1", "B7"), ("R4", "1"))
join("USB_DP", ("R3", "2"), *u1("USB_DP"))
join("USB_DM", ("R4", "2"), *u1("USB_DM"))

# 3.3 V and the RP2350's supplies
join("+3V3", ("U3", "5"), ("C2", "1"), *u1("IOVDD"), *u1("QSPI_IOVDD"), *u1("USB_OTP_VDD"), *u1("ADC_AVDD"),
     *u1("VREG_VIN"), ("R5", "1"), ("R7", "1"), ("U2", "8"), ("C20", "1"),
     ("R9", "1"), ("R10", "1"), ("R11", "1"), ("R12", "1"), ("R13", "1"), ("J4", "4"), ("C21", "1"), ("C22", "1"))
for i in range(6):
    join("+3V3", (f"C{3 + i}", "1"))
    join("GND", (f"C{3 + i}", "2"))
for c in ("C9", "C10", "C11", "C12"):
    join("+3V3", (c, "1"))
    join("GND", (c, "2"))
join("VREG_AVDD", ("R5", "2"), ("C13", "1"), *u1("VREG_AVDD"))
join("VREG_LX", *u1("VREG_LX"), ("L1", "1"))
join("+1V1", ("L1", "2"), *u1("VREG_FB"), *u1("DVDD"), ("C14", "1"), ("C15", "1"), ("C16", "1"), ("C17", "1"))
join("GND", *u1("GND"), *u1("VREG_PGND"), ("C13", "2"), ("C14", "2"), ("C15", "2"), ("C16", "2"), ("C17", "2"),
     ("C20", "2"), ("C21", "2"), ("C22", "2"))

# crystal
join("XIN", *u1("XIN"), ("Y1", "1"), ("C18", "1"))
join("XOUT", *u1("XOUT"), ("R6", "1"))
join("XTAL", ("R6", "2"), ("Y1", "3"), ("C19", "1"))
join("GND", ("Y1", "2"), ("Y1", "4"), ("C18", "2"), ("C19", "2"))

# reset, BOOTSEL, debug
join("RUN", *u1("RUN"), ("R7", "2"), ("SW1", "1"))
join("GND", ("SW1", "2"), ("SW2", "2"), ("J5", "1"))
join("SWCLK", *u1("SWCLK"), ("J5", "2"))
join("SWDIO", *u1("SWDIO"), ("J5", "3"))
join("UART_TX", *u1("GPIO0"), ("J5", "4"))
join("UART_RX", *u1("GPIO1"), ("J5", "5"))

# flash
join("QSPI_SS", *u1("QSPI_SS"), ("U2", "1"), ("R8", "1"))
join("BOOTSEL", ("R8", "2"), ("SW2", "1"))
join("QSPI_SD0", *u1("QSPI_SD0"), ("U2", "5"))
join("QSPI_SD1", *u1("QSPI_SD1"), ("U2", "2"))
join("QSPI_SD2", *u1("QSPI_SD2"), ("U2", "3"))
join("QSPI_SD3", *u1("QSPI_SD3"), ("U2", "7"))
join("QSPI_SCLK", *u1("QSPI_SCLK"), ("U2", "6"))
join("GND", ("U2", "4"))

# microSD, SPI mode
join("SD_MISO", *u1("GPIO8"), ("J4", "7"), ("R9", "2"))
join("SD_CS", *u1("GPIO9"), ("J4", "2"), ("R10", "2"))
join("SD_SCK", *u1("GPIO10"), ("J4", "5"))
join("SD_MOSI", *u1("GPIO11"), ("J4", "3"), ("R11", "2"))
join("SD_DAT1", ("J4", "8"), ("R12", "2"))
join("SD_DAT2", ("J4", "1"), ("R13", "2"))
join("GND", ("J4", "6"), ("J4", "SH"))

# HDMI: GPIO12-19 through 270R to the TMDS pairs
for i, (net, pin) in enumerate((("D2P", 1), ("D2N", 3), ("D1P", 4), ("D1N", 6), ("D0P", 7), ("D0N", 9),
                                ("CKP", 10), ("CKN", 12))):
    join(f"HDMI_{net}_IO", *u1(f"GPIO{12 + i}"), (f"R{14 + i}", "1"))
    join(f"TMDS_{net}", (f"R{14 + i}", "2"), ("J2", str(pin)))
join("GND", ("J2", "2"), ("J2", "5"), ("J2", "8"), ("J2", "11"), ("J2", "17"), ("J2", "SH"))
join("HDMI_5V", ("D2", "1"), ("J2", "18"))

# keyboard USB host
join("USBH_DP_IO", *u1("GPIO20"), ("R22", "1"))
join("USBH_DM_IO", *u1("GPIO21"), ("R23", "1"))
join("USBH_DP", ("R22", "2"), ("R24", "1"), ("J3", "3"))
join("USBH_DM", ("R23", "2"), ("R25", "1"), ("J3", "2"))
join("USBH_VBUS", ("F1", "2"), ("C23", "1"), ("J3", "1"))
join("GND", ("R24", "2"), ("R25", "2"), ("C23", "2"), ("J3", "4"), ("J3", "SH"))

# HALT LED
join("HALT_LED", *u1("GPIO25"), ("R26", "1"))
join("HALT_LED_A", ("R26", "2"), ("D1", "2"))     # LED pad 2 is the anode
join("GND", ("D1", "1"))

# Placement: ref -> (x, y, rotation in degrees, anticlockwise as KiCad)
PLACE = {
    "U1": (36.0, 28.0, 180),
    "U2": (37.5, 45.0, 270),     # pins 1-3 on top, in U1's QSPI pin order
    "U3": (12.0, 43.0, 90),
    "Y1": (44.5, 20.0, 0),
    "L1": (34.0, 38.0, 0),        # under VREG_LX and VREG_FB; make_board.py tracks them straight down
    "J1": (0.0, 30.0, 270),      # edge connectors: x or y is the board edge; make_board.py aligns them
    "J2": (21.0, 0.0, 90),
    "J3": (52.0, 0.0, 180),
    "J4": (75.0, 30.0, 90),
    "J5": (52.0, 51.5, 90),
    "SW1": (12.0, 51.0, 0),
    "SW2": (26.5, 51.0, 0),
    "D1": (42.0, 51.5, 180),
    "D2": (34.0, 14.5, 0),
    "F1": (40.5, 10.0, 90),
    "C1": (8.0, 43.0, 90), "C2": (16.0, 43.0, 90),
    "R1": (7.0, 22.0, 90), "R2": (7.0, 38.0, 90),
    "R3": (14.0, 28.0, 0), "R4": (14.0, 31.0, 0),
    "R5": (27.0, 38.5, 0), "C13": (27.0, 40.5, 0),
    "R6": (43.0, 24.5, 0), "C18": (41.0, 21.0, 90), "C19": (48.0, 21.0, 90),
    "R7": (19.2, 50.0, 90), "R8": (26.5, 45.8, 0),
    "C14": (37.6, 37.6, 90), "C12": (30.5, 35.0, 90), "C10": (40.5, 36.0, 90),
    "C20": (42.5, 47.5, 0),
    "R9": (51.0, 23.5, 0), "R10": (51.0, 25.5, 0), "R11": (51.0, 27.5, 0), "R12": (51.0, 29.5, 0),
    "R13": (51.0, 31.5, 0), "C21": (58.0, 40.0, 90), "C22": (60.5, 40.0, 90),
    "R22": (59.0, 17.0, 0), "R23": (59.0, 19.0, 0), "R24": (63.0, 17.0, 0), "R25": (63.0, 19.0, 0),
    "C23": (40.5, 15.0, 90),
    "R26": (46.0, 51.5, 0),
}
for i in range(8):
    PLACE[f"R{14 + i}"] = (13.5 + i * 2.2, 15.5, 90)
for (ref, (x, y)) in zip(("H1", "H2", "H3", "H4"), HOLES):
    PLACE[ref] = (x, y, 0)
# decoupling capacitors go beside the U1 pin they serve; make_board.py works out where
DECOUPLE = {"C3": 1, "C4": 11, "C5": 20, "C6": 30, "C7": 38, "C8": 45, "C9": 54, "C11": 44,
            "C15": 6, "C16": 23, "C17": 39}

# which edge each edge connector's mouth faces
EDGE = {"J1": "left", "J2": "top", "J3": "top", "J4": "right"}

POWER_NETS = ("+5V", "+3V3", "GND", "USBH_VBUS", "HDMI_5V")
CORE_NETS = ("+1V1", "VREG_LX")       # the RP2350's core supply: narrower, to reach its pins


def pins_of():
    out = {}
    for net, pins in NETS.items():
        for ref, pad in pins:
            out.setdefault(ref, {}).setdefault(pad, net)
    return out


def check():
    pins = pins_of()
    missing = [r for r in PARTS if r not in PLACE and r not in DECOUPLE]
    assert not missing, f"no position for {missing}"
    for net, ps in NETS.items():
        refs = [r for r, _ in ps]
        assert all(r in PARTS for r in refs), (net, refs)
    clash = {}
    for net, ps in NETS.items():
        for p in ps:
            if p in clash and clash[p] != net:
                raise SystemExit(f"{p} on {clash[p]} and {net}")
            clash[p] = net
    single = [n for n, ps in NETS.items() if len(set(ps)) < 2]
    assert not single, single
    return pins


def main():
    pins = check()
    parts = {ref: {"value": v, "footprint": fp, "part": mpn, "description": d, "pins": pins.get(ref, {})}
             for ref, (v, fp, mpn, d) in PARTS.items()}
    gpio = {str(k): {"net": n, "use": u} for k, (n, u) in GPIO_USE.items()}
    json.dump({"board": {"width": BOARD_W, "height": BOARD_H, "layers": 4},
               "parts": parts, "nets": {n: [list(p) for p in sorted(set(ps))] for n, ps in NETS.items()},
               "gpio": gpio}, open(os.path.join(OUT, "netlist.json"), "w"), indent=1)
    # parts list, identical parts on one line
    groups = {}
    for ref, (v, fp, mpn, d) in PARTS.items():
        if ref.startswith("H"):
            continue
        key = (v, fp.split(":")[1], mpn, d if not ref[0] in "RC" else "")
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
    print(f"{len(PARTS)} parts, {len(NETS)} nets, {sum(len(set(p)) for p in NETS.values())} connections")


if __name__ == "__main__":
    main()
