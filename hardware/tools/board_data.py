"""Component placement for the PSI COMP 80 main board.

Everything here was read off the two kit photos (info/pictures/kit-component-layout.webp
and kit-pcb-artwork.webp) after perspective-correcting them onto the same frame.
Coordinates are in "frame pixels": the 16 x 12 inch board (crop mark to crop mark on
the artwork) mapped onto 2000 x 1500, so 125 px = 1 inch, origin top-left, y down.

Positions are good to roughly +/-0.03 in. IC types follow the article's circuit diagrams
where the photo was hard to read; NOTES lists those. Parts whose reference designator could not be read at all use
placeholder references from 101 upwards (R101, C101, ...).
"""

PX_PER_IN = 125.0
BOARD_W, BOARD_H = 2000, 1500   # frame px (16 x 12 in)

# --- Integrated circuits ---------------------------------------------------------
# (ref, value, pins, row spacing in inches, bbox x0, y0, x1, y1, notch side L/R/T/B)
# The notch marks the pin-1 end, as drawn on the component layout sheet.
_ICS = [
    # CPU section
    ("IC14", "74LS04", 14, 0.3, 72, 58, 162, 98, "L"),
    ("IC2", "74LS138", 16, 0.3, 183, 60, 285, 101, "L"),
    ("IC3", "74LS138", 16, 0.3, 306, 63, 410, 107, "L"),
    ("IC1", "Z80", 40, 0.6, 92, 242, 343, 328, "L"),
    ("IC10", "74LS367", 16, 0.3, 93, 387, 192, 435, "R"),
    ("IC9", "74LS367", 16, 0.3, 222, 389, 323, 437, "R"),
    ("IC12", "74LS367", 16, 0.3, 93, 472, 192, 520, "R"),
    ("IC11", "74LS367", 16, 0.3, 223, 473, 325, 522, "L"),
    ("IC6", "MM57109", 28, 0.6, 100, 557, 182, 735, "B"),
    ("IC8", "74LS367", 16, 0.3, 225, 560, 328, 608, "R"),
    ("IC5", "74C173", 16, 0.3, 227, 645, 328, 692, "R"),
    ("IC4", "74C173", 16, 0.3, 228, 730, 330, 775, "R"),
    ("IC7", "4011", 14, 0.3, 242, 813, 330, 858, "R"),
    ("IC55", "74LS00", 14, 0.3, 30, 842, 80, 927, "B"),
    ("IC13", "81LS95", 20, 0.3, 88, 893, 218, 940, "R"),
    # Keyboard encoder section
    ("IC54", "2376", 40, 0.6, 43, 963, 293, 1050, "R"),
    # Memory section
    ("IC15", "74LS367", 16, 0.3, 433, 63, 530, 108, "L"),
    ("IC16", "74LS367", 16, 0.3, 553, 62, 652, 107, "L"),
    ("IC57", "74LS139", 16, 0.3, 676, 62, 776, 107, "L"),
    ("IC17", "74LS138", 16, 0.3, 800, 66, 899, 110, "L"),
    ("IC49", "74LS02", 14, 0.3, 922, 70, 1010, 112, "L"),
    ("IC18", "2708", 24, 0.6, 475, 381, 627, 470, "R"),
    ("IC19", "2708", 24, 0.6, 480, 502, 630, 590, "R"),
    ("IC20", "2708", 24, 0.6, 481, 625, 631, 712, "R"),
    ("IC21", "2708", 24, 0.6, 482, 745, 633, 830, "R"),
    ("IC27", "81LS95", 20, 0.3, 472, 938, 598, 985, "R"),
    # VDU section
    ("IC38", "7493", 14, 0.3, 1803, 302, 1890, 348, "R"),
    ("IC33", "7425", 14, 0.3, 1920, 297, 1965, 385, "T"),
    ("IC42", "74LS157", 16, 0.3, 1317, 395, 1417, 443, "R"),
    ("IC41", "74LS157", 16, 0.3, 1442, 397, 1541, 445, "R"),
    ("IC40", "74LS157", 16, 0.3, 1566, 398, 1665, 448, "R"),
    ("IC35", "7493", 14, 0.3, 1690, 401, 1777, 451, "R"),
    ("IC39", "7493", 14, 0.3, 1800, 403, 1888, 453, "R"),
    ("IC32", "74LS00", 14, 0.3, 1918, 405, 1968, 490, "T"),
    ("IC31", "74LS02", 14, 0.3, 1564, 484, 1652, 532, "R"),
    ("IC48", "7493", 14, 0.3, 1690, 487, 1777, 535, "R"),
    ("IC30", "7493", 14, 0.3, 1800, 490, 1882, 538, "R"),
    ("IC46", "7490", 14, 0.3, 1912, 515, 1960, 600, "T"),
    ("IC45", "74165", 16, 0.3, 1562, 568, 1662, 617, "R"),
    ("IC34", "7490", 14, 0.3, 1686, 570, 1772, 618, "R"),
    ("IC29", "7493", 14, 0.3, 1797, 572, 1882, 620, "R"),
    ("IC47", "2513", 24, 0.6, 1558, 652, 1707, 738, "R"),
    ("IC28", "74LS04", 14, 0.3, 1795, 655, 1878, 703, "R"),
    ("IC36", "74121", 14, 0.3, 1910, 622, 1960, 707, "T"),
    ("IC37", "7492", 14, 0.3, 1790, 740, 1873, 787, "R"),
    # Tape interface section
    ("IC53", "74LS367", 16, 0.3, 1645, 197, 1745, 243, "R"),
    ("IC51", "4013", 14, 0.3, 1768, 203, 1855, 245, "R"),
    ("IC52", "4528", 16, 0.3, 1878, 205, 1975, 252, "R"),
]

# Program memory: 21L02 (1K x 1) array, columns IC22..IC26, rows a..h
_MEM_COLS = {"IC22": (666, 766), "IC23": (791, 891), "IC24": (915, 1015),
             "IC25": (1039, 1139), "IC26": (1162, 1262)}
_MEM_ROWS = [(384, 434), (470, 520), (556, 606), (640, 689),
             (725, 773), (808, 856), (893, 941), (977, 1025)]
# Video memory: IC43a-g, IC44a-g
_VID_COLS = {"IC43": (1315, 1414), "IC44": (1439, 1538)}
_VID_ROWS = [(483, 531), (567, 615), (650, 698), (733, 781),
             (817, 865), (900, 948), (983, 1031)]

NOTES = {
    "IC57": "16-pin slot on the kit sheet; probably the optional Fig. 7 74LS139 for 32K expansion (label hard to read)",
    "IC49": "printed IC50 or IC49 on the kit sheet; the article's IC49 is this 74LS02",
    "IC38": "reference hard to read on the kit sheet",
    "IC39": "printed IC38 or IC39 on the kit sheet",
    "IC46": "reference hard to read on the kit sheet",
    "IC48": "reference hard to read on the kit sheet",
    "IC13": "kit sheet reads 81LS98; the article's 81LS95 is what the circuit needs",
    "IC27": "kit sheet reads 81LS98; the article's 81LS95 is what the circuit needs",
}

ROLE = {"IC18": "MONITOR", "IC19": "BURP 1", "IC20": "BURP 2", "IC21": "OPTIONAL",
        "IC54": "KEYBOARD ENCODER", "IC47": "CHARACTER GEN"}

OPTIONAL = {"IC21"} | {f"IC{c}{r}" for c in (24, 25) for r in "abcdefgh"} | {"IC43g", "IC44g"}


def ics():
    out = []
    for ref, val, pins, w, x0, y0, x1, y1, notch in _ICS:
        out.append(dict(ref=ref, value=val, pins=pins, width=w,
                        bbox=(x0, y0, x1, y1), notch=notch))
    for cols, rows, val in ((_MEM_COLS, _MEM_ROWS, "21L02"), (_VID_COLS, _VID_ROWS, "21L02")):
        for col, (x0, x1) in cols.items():
            for i, (y0, y1) in enumerate(rows):
                out.append(dict(ref=f"{col}{'abcdefgh'[i]}", value=val, pins=16, width=0.3,
                                bbox=(x0, y0, x1, y1), notch="R"))
    return out


# --- Discrete parts --------------------------------------------------------------
# Two-lead parts: (ref, value, kind, x1, y1, x2, y2)  -- ends of the drawn body
#   kind: R (axial resistor), C (small capacitor), D (diode), RW (wirewound resistor)
# One-point parts: (ref, value, kind, x, y)
#   kind: CP (radial electrolytic / tantalum), TO92, LED, VR (preset), TO220, PIN (wire pad)
TWO_LEAD = [
    # CPU
    ("R101", "4k7", "R", 35, 105, 95, 105),
    ("C1", "100n", "C", 35, 118, 58, 118),
    ("R4", "4k7", "R", 45, 175, 45, 235),
    ("R3", "1k", "R", 45, 247, 45, 308),
    ("R6", "47k", "R", 250, 222, 313, 222),
    ("R5", "47k", "R", 326, 222, 386, 222),
    ("R102", "10k", "R", 28, 544, 88, 544),
    ("R103", "10k", "R", 28, 576, 88, 576),
    ("R104", "10k", "R", 28, 596, 88, 596),
    ("R105", "10k", "R", 28, 614, 88, 614),
    ("R106", "10k", "R", 28, 632, 88, 632),
    ("R107", "10k", "R", 28, 650, 88, 650),
    ("R108", "47k", "R", 28, 671, 88, 671),
    ("R109", "47k", "R", 28, 695, 88, 695),
    ("R110", "2k7", "R", 98, 782, 158, 782),
    ("R111", "4k7", "R", 98, 836, 158, 836),
    ("R112", "?", "R", 185, 752, 185, 812),
    ("R113", "?", "R", 215, 752, 215, 812),
    ("R114", "?", "R", 16, 742, 16, 805),
    ("R115", "330R", "R", 93, 862, 153, 862),
    ("R116", "?", "R", 25, 938, 75, 938),
    ("C13", "22n", "C", 45, 952, 68, 952),
    ("R117", "?", "R", 307, 975, 307, 1048),
    ("C11", "56p", "C", 292, 1062, 315, 1062),
    # VDU
    ("R118", "10k", "R", 1810, 627, 1868, 627),
    ("R119", "1k8", "R", 1740, 668, 1740, 728),
    ("R120", "?", "R", 1899, 630, 1899, 675),
    ("R14", "470R", "R", 1762, 717, 1820, 717),
    ("R15", "470R", "R", 1835, 717, 1893, 717),
    ("C2", "27p", "C", 1792, 727, 1792, 750),
    ("C5", "270n", "C", 1885, 771, 1950, 771),
    ("R10", "2k2", "R", 1716, 770, 1778, 770),
    ("C7", "220n", "C", 1808, 283, 1868, 283),
    # Tape interface
    ("R121", "?", "R", 1555, 95, 1555, 140),
    ("R122", "?", "R", 1575, 108, 1625, 108),
    ("R123", "?", "R", 1575, 123, 1625, 123),
    ("R124", "?", "R", 1630, 98, 1630, 145),
    ("R125", "?", "R", 1645, 98, 1645, 145),
    ("R126", "?", "R", 1608, 160, 1608, 212),
    ("R127", "?", "R", 1625, 160, 1625, 212),
    ("R128", "?", "R", 1758, 100, 1758, 150),
    ("R129", "?", "R", 1785, 130, 1785, 178),
    ("R130", "?", "R", 1797, 100, 1797, 150),
    ("R131", "?", "R", 1810, 108, 1860, 108),
    ("R132", "?", "R", 1810, 127, 1860, 127),
    ("R133", "?", "R", 1870, 100, 1870, 155),
    ("R134", "?", "R", 1893, 110, 1893, 160),
    ("R135", "?", "R", 1833, 177, 1890, 177),
    ("R136", "?", "R", 1917, 135, 1917, 185),
    ("R137", "?", "R", 1938, 145, 1938, 195),
    ("R138", "?", "R", 1958, 155, 1958, 200),
    ("R139", "?", "R", 1852, 66, 1910, 66),
    # Power supply
    ("R40", "0R27", "RW", 1570, 801, 1640, 801),
    ("R41", "0R56", "RW", 1570, 830, 1640, 830),
    ("R44", "1k", "R", 1548, 955, 1607, 955),
    ("R42", "1k", "R", 1627, 960, 1680, 960),
    ("R43", "1k", "R", 1580, 975, 1630, 975),
    ("R45", "1k", "R", 1665, 980, 1722, 980),
    ("R46", "1k", "R", 1567, 995, 1625, 995),
    ("D1", "1N5402", "D", 1845, 812, 1905, 812),
    ("D2", "1N5402", "D", 1845, 893, 1905, 893),
    ("D8", "1N4002", "D", 1780, 918, 1810, 918),
    ("D9", "1N4002", "D", 1850, 918, 1880, 918),
    ("D10", "1N4002", "D", 1780, 992, 1810, 992),
    ("D11", "1N4002", "D", 1850, 992, 1880, 992),
    ("D4", "1N4002", "D", 1780, 1008, 1810, 1008),
    ("D5", "1N4002", "D", 1850, 1008, 1880, 1008),
    ("D6", "1N4002", "D", 1780, 1068, 1810, 1068),
    ("D7", "1N4002", "D", 1850, 1068, 1880, 1068),
]

ONE_POINT = [
    # CPU
    ("TR1", "2N3906", "TO92", 40, 155),
    ("C101", "1u", "CP", 226, 222),
    ("C102", "1u", "CP", 354, 286),
    ("TR3", "BC212L", "TO92", 70, 773),
    ("TR2", "BC212L", "TO92", 65, 822),
    ("C12", "2u2", "CP", 180, 862),
    # Memory: decoupling capacitors ("all unmarked capacitors are 1u for decoupling")
    ("C103", "1u", "CP", 467, 355), ("C104", "1u", "CP", 490, 355), ("C105", "1u", "CP", 518, 370),
    # (kit sheet has these at the left end of each RAM column, between rows d and e; moved
    # into the gaps between the columns so the column bus runs can pass)
    ("C106", "1u", "CP", 647, 707), ("C107", "1u", "CP", 781, 707), ("C108", "1u", "CP", 906, 707),
    ("C109", "1u", "CP", 1031, 707), ("C110", "1u", "CP", 1150, 707),
    ("C111", "1u", "CP", 680, 1057), ("C112", "1u", "CP", 803, 1057), ("C113", "1u", "CP", 925, 1057),
    ("C114", "1u", "CP", 1050, 1057), ("C115", "1u", "CP", 1172, 1057),
    ("C116", "1u", "CP", 600, 1000), ("C117", "1u", "CP", 598, 1020), ("C118", "1u", "CP", 607, 1038),
    ("C119", "1u", "CP", 1325, 1060), ("C120", "1u", "CP", 1445, 1060),
    # VDU
    ("C121", "1u", "CP", 1682, 436), ("C122", "1u", "CP", 1945, 393),
    ("VR1", "20k", "VR", 1930, 736),
    # Tape interface
    ("TR5", "BC107L", "TO92", 1585, 145), ("TR4", "BC182L", "TO92", 1675, 145),
    ("TR6", "BC182L", "TO92", 1823, 148), ("TR7", "BC182L", "TO92", 1858, 150),
    ("TR8", "BC212L", "TO92", 1930, 112),
    ("VR2", "4k7", "VR", 1690, 105),
    ("D3", "LED", "LED", 1815, 72),
    ("C8", "10u", "CP", 1745, 115), ("C9", "10u", "CP", 1768, 165),
    ("C123", "1u", "CP", 1540, 125), ("C124", "1u", "CP", 1868, 225),
    ("TP1", "TAPE OUT", "PIN", 1712, 137), ("TP2", "0V", "PIN", 1714, 167),
    ("TP3", "TAPE IN", "PIN", 1750, 167),
    # Power supply
    ("C3", "10u", "CP", 1575, 857),
    ("TR9", "TIP30A", "TO220", 1610, 860),
    ("IC56", "78M05", "TO220", 1660, 878),
    ("REG1", "?", "TO220", 1588, 936), ("REG2", "?", "TO220", 1650, 936), ("REG3", "?", "TO220", 1715, 936),
    ("C125", "1u", "CP", 1600, 965), ("C126", "1u", "CP", 1647, 992), ("C127", "1u", "CP", 1690, 990),
    ("TP4", "", "PIN", 1958, 813), ("TP5", "", "PIN", 1958, 850), ("TP6", "", "PIN", 1958, 885),
    ("TP7", "", "PIN", 1958, 920), ("TP8", "", "PIN", 1958, 955), ("TP9", "", "PIN", 1958, 990),
    ("TP10", "", "PIN", 1958, 1025), ("TP11", "", "PIN", 1958, 1060),
    # Keyboard LED
    ("D12", "LED", "LED", 117, 1472),
]

# Parts that stand rotated (degrees anticlockwise) at their slot
SLOT_ROTATION = {"C106": 90, "C107": 90, "C108": 90, "C109": 90, "C110": 90}

# Large boxed parts: (ref, value, x0, y0, x1, y1) -- reservoir capacitors drawn as boxes
BOXES = [
    ("C14", "4700u 25V", 1685, 793, 1938, 908),
    ("C19", "220u 63V", 1752, 915, 1908, 997),
    ("C18", "1000u 25V", 1755, 1002, 1908, 1072),
    ("C17", "1000u 25V", 1570, 1002, 1730, 1072),
]

# Expansion plug: 2 x 32 at 0.1 in, centred on (x, y)
EXPANSION = dict(ref="J1", value="EXPANSION PLUG", pins_per_row=32, x=1293.5, y=111)


# --- Keyboard ------------------------------------------------------------------------
# Each key switch has two large pads: the left one at (x, y), the right one 0.38 in to
# the right and slightly lower. Keycap legends as printed on the board.
KEY_DX, KEY_DY = 48, 8
_KEY_ROWS = [
    (1125, [(175, "1", "!"), (270, "2", '"'), (363, "3", "#"), (457, "4", "$"),
            (553, "5", "%"), (645, "6", "&"), (738, "7", "'"), (829, "8", "("),
            (921, "9", ")"), (1011, "Ø", ""), (1103, ":", "*"), (1195, "-", "="),
            (1287, "↑", ""), (1378, "*", "")]),
    (1212, [(122, "*", ""), (217, "Q", ""), (310, "W", ""), (405, "E", ""), (500, "R", ""),
            (593, "T", ""), (687, "Y", ""), (780, "U", ""), (873, "I", ""), (965, "O", ""),
            (1057, "P", ""), (1150, "@", ""), (1240, "↓", ""), (1330, "RETURN", "")]),
    (1300, [(143, "*", ""), (238, "A", ""), (333, "S", ""), (430, "D", ""), (522, "F", ""),
            (620, "G", ""), (712, "H", ""), (805, "J", ""), (899, "K", ""), (987, "L", ""),
            (1080, ";", "+"), (1172, "[", ""), (1263, "]", ""), (1355, "*", "")]),
    (1388, [(98, "RESET", ""), (170, "SHIFT", ""), (288, "Z", ""), (383, "X", ""), (480, "C", ""),
            (572, "V", ""), (667, "B", ""), (760, "N", ""), (851, "M", ""), (945, ",", "<"),
            (1037, ".", ">"), (1128, "/", "?"), (1218, "SHIFT", "")]),
    (1475, [(712, "SPACE", "")]),
    # Hex keypad
    (1128, [(1641, "7", ""), (1730, "8", ""), (1820, "9", ""), (1915, "F", "")]),
    (1216, [(1641, "4", ""), (1730, "5", ""), (1820, "6", ""), (1915, "E", "")]),
    (1303, [(1641, "1", ""), (1730, "2", ""), (1820, "3", ""), (1915, "D", "")]),
    (1391, [(1641, "A", ""), (1730, "Ø", ""), (1820, "B", ""), (1915, "C", "")]),
]
# "*" = uncommitted switch for future expansion


def keys():
    out = []
    n = 1
    for y, row in _KEY_ROWS:
        for x, legend, shifted in row:
            name = "uncommitted" if legend == "*" else legend
            out.append(dict(ref=f"SW{n}", legend=name, shifted=shifted,
                            pad1=(x, y), pad2=(x + KEY_DX, y + KEY_DY),
                            hex=x > 1600))
            n += 1
    return out


# --- Drawing furniture -----------------------------------------------------------
# Section boundary lines from the component layout sheet (polylines, frame px)
SECTION_LINES = [
    [(430, 0), (430, 1075)],                       # CPU | memory
    [(0, 948), (430, 948)],                        # CPU / keyboard encoder
    [(0, 840), (222, 840), (222, 948)],            # box round IC55 / IC13
    [(918, 0), (918, 297), (1292, 297), (1292, 1075)],   # memory | VDU
    [(1023, 0), (1023, 262), (2000, 262)],         # expansion plug / tape box
    [(1537, 0), (1537, 262)],                      # expansion plug | tape interface
    [(1537, 1075), (1537, 785), (2000, 785)],      # VDU / power supply
    [(0, 1075), (2000, 1075)],                     # main board / keyboard
]

SECTION_TEXT = [
    ("CPU SECTION", 305, 158), ("MEMORY SECTION", 643, 237), ("VDU SECTION", 1415, 318),
    ("TAPE INTERFACE SECTION", 1395, 172), ("KEYBOARD ENCODER SECTION", 372, 1000),
    ("POWER SUPPLY SECTION", 1548, 1150),
]

SMALL_TEXT = [
    ("IC22a-h, IC23a-h, IC26a-h all 21L02-4K   IC24a-h, IC25a-h all 21L02-4 (OPTIONAL)", 962, 372),
    ("IC43a-g, IC44a-g all 21L02-4", 1425, 467),
    ("ALL UNMARKED CAPACITORS ARE 1u 10V FOR DECOUPLING POWER LINES", 930, 1045),
    ("PRINTING ON KEYBOARDS MAY DIFFER SLIGHTLY FROM THAT SHOWN ABOVE", 1530, 1478),
    ("Fit link 1 or 2 but not both", 655, 345),
]

# Mounting holes / odd pads seen on the artwork
HOLES = [(28, 28), (1972, 28), (28, 1472), (1972, 1472), (1042, 92), (1077, 92), (1508, 95)]
