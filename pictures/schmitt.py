"""Fig. 22(a): Schmitt trigger circuit diagram."""
from c80screen import Screen

VBAR, HMID, HTOP, HBOT, FULL = 0x31, 0x35, 0x33, 0x37, 0x0F


def build():
    s = Screen()

    def vline(c, r0, r1):
        for r in range(r0, r1 + 1):
            s.gfx(r, c, VBAR)

    def hline(r, c0, c1, g=HMID):
        for c in range(c0, c1 + 1):
            s.gfx(r, c, g)

    def resistor_v(c, r0, r1):
        for r in range(r0, r1 + 1):
            s.gfx(r, c, FULL)

    # supply rails
    hline(3, 6, 32, HBOT)
    s.text(3, 34, "+5V SUPPLY")
    hline(21, 6, 32, HTOP)
    s.text(21, 34, "0V")

    # left divider: 47k / 47k, input coupling capacitor
    vline(13, 4, 4); resistor_v(13, 5, 7); vline(13, 8, 14)
    resistor_v(13, 15, 17); vline(13, 18, 20)
    s.text(6, 7, "47K"); s.text(16, 7, "47K")
    hline(11, 6, 8)
    s.gfx(11, 9, VBAR); s.gfx(11, 10, 0x30)   # capacitor plates
    hline(11, 11, 12)
    s.text(12, 8, "1"); s.gfx(12, 9, 0x27)     # 1 uF (mu)

    # centre leg: 100k down to the transistor pair, 2.2k emitter resistor
    vline(18, 4, 4); resistor_v(18, 5, 7); vline(18, 8, 14)
    resistor_v(18, 15, 17); vline(18, 18, 20)
    s.text(6, 20, "100K"); s.text(16, 20, "2.2K")
    hline(11, 14, 17)                          # base feed from the divider

    # 10k feedback resistor between the two stages
    hline(9, 19, 19)
    for c in range(20, 24):
        s.gfx(9, c, FULL)
    hline(9, 24, 26)
    s.text(10, 20, "10K")
    hline(13, 19, 26)                          # common emitter line

    # right leg: 1k collector load, output, 10k to 0V
    vline(27, 4, 4); resistor_v(27, 5, 7); vline(27, 8, 13)
    s.text(6, 29, "1K")
    hline(8, 28, 31)
    s.gfx(8, 32, 0x0F)                         # output terminal
    vline(25, 14, 15); resistor_v(25, 16, 18); vline(25, 19, 20)
    s.text(17, 27, "10K")

    s.text(23, 9, "SCHMITT TRIGGER CIRCUIT")
    hline(24, 9, 31, HTOP)
    return s


if __name__ == "__main__":
    build().render("schmitt_preview.png")
