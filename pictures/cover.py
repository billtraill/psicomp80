"""The screen on the cover of the Powertran kit leaflet: a big "psi COMP 80".

The leaflet (info/pictures/kit-leaflet.webp) shows a COMP80 with its
television displaying the name in block letters made of graphics characters.
The letters here are measured from that photo. They are drawn on the
quarter-block grid (half a character wide, half a line tall: 128 x 64 on the
screen), so each cell comes out as one of the quarter-block graphics
characters; strokes are a whole character wide and a whole line deep.
Every letter starts on a character boundary, so the cut-off corners of the
C, O, P, 8 and 0 can be the diagonal half-block characters 18h-1Bh, as on
the cover.
"""
from c80screen import Screen, canvas

TOP = 20        # quarter-block row of the top of the letters (line 10)
HEIGHT = 12     # letter height in quarter-blocks (6 lines; psi's stem adds 3)

# diagonal half-block characters that cut off a corner (24-27 decimal)
ROUND_TL, ROUND_TR, ROUND_BR, ROUND_BL = 0x18, 0x19, 0x1A, 0x1B


def build():
    im, d = canvas()
    corners = []    # (line, column, character) put in after the bitmap

    def block(x, y, w=1, h=1):
        """Fill w x h quarter-blocks from (x, y) (screen quarter-block grid)."""
        d.rectangle((x * 3, (TOP + y) * 5, (x + w) * 3 - 1, (TOP + y + h) * 5 - 1), fill=1)

    def corner(x, y, code):
        """A rounded corner in the character cell at quarter-block (x, y)."""
        corners.append(((TOP + y) // 2, x // 2, code))

    def box(x, w, rounded=False):
        """Top and bottom bars and both sides."""
        block(x, 0, w, 2)
        block(x, HEIGHT - 2, w, 2)
        block(x, 0, 2, HEIGHT)
        block(x + w - 2, 0, 2, HEIGHT)
        if rounded:
            corner(x, 0, ROUND_TL)
            corner(x + w - 2, 0, ROUND_TR)
            corner(x, HEIGHT - 2, ROUND_BL)
            corner(x + w - 2, HEIGHT - 2, ROUND_BR)

    def psi(x):
        # two matching arms that lean right, stepping half a character each
        # line all the way down to a bar along the bottom, and a stem that
        # leans the same way: from a line above the bar, through its middle,
        # to three lines below it
        for arm in (x, x + 14):
            for y in range(HEIGHT):
                block(arm + (HEIGHT - 1 - y) // 2, y, 2, 1)
        block(x, HEIGHT - 2, 16, 2)
        for y in range(HEIGHT - 4, HEIGHT + 6):
            block(x + 7 + (HEIGHT - 1 - y) // 2, y, 2, 1)
        return 22

    def c(x):
        block(x, 0, 10, 2)
        block(x, HEIGHT - 2, 10, 2)
        block(x, 0, 2, HEIGHT)
        corner(x, 0, ROUND_TL)
        corner(x, HEIGHT - 2, ROUND_BL)
        return 10

    def o(x):
        box(x, 10, rounded=True)
        return 10

    def m(x):
        block(x, 0, 2, HEIGHT)
        block(x + 10, 0, 2, HEIGHT)
        # the V: each side steps half a block across for every half block
        # down, starting half a block inside the leg, so the top of each side
        # is three half-blocks wide, and meeting at a point two lines down
        for y in range(4):
            block(x + 1 + y, y, 2, 1)
            block(x + 9 - y, y, 2, 1)
        block(x + 5, 4, 2, 1)
        return 12

    def p(x):
        # the bowl is the top three lines
        block(x, 0, 10, 2)
        block(x, 0, 2, HEIGHT)
        block(x + 8, 0, 2, 6)
        block(x, 4, 10, 2)
        corner(x + 8, 0, ROUND_TR)
        corner(x + 8, 4, ROUND_BR)
        return 10

    def eight(x):
        # two equal holes, so the middle bar straddles two lines
        box(x, 10, rounded=True)
        block(x, 5, 10, 2)
        return 10

    def zero(x):
        box(x, 10, rounded=True)
        # the slash runs from the inside corner at the bottom left to the one
        # at the top right, a character further over on each line; a stroke
        # wide, it meets the sides with half its width showing at each end
        for line in range(1, HEIGHT // 2 - 1):
            block(x + 1 + 2 * (HEIGHT // 2 - 2 - line), 2 * line, 2, 2)
        return 10

    # psi C O M P, a word space, 8 0: 112 quarter-blocks of 128, centred
    x = 8
    for draw, gap in ((psi, 4), (c, 4), (o, 4), (m, 4), (p, 8), (eight, 4), (zero, 0)):
        x += draw(x) + gap

    s = Screen()
    s.from_bitmap(im, codes=range(16))      # quarter blocks only
    for line, col, code in corners:
        s.gfx(line, col, code)
    return s


if __name__ == "__main__":
    build().render("cover_preview.png")
