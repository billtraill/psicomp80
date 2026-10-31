"""Fig. 22(b): sailing boat."""
from c80screen import Screen, canvas


def build():
    im, d = canvas()
    # small cloud, top left
    d.rectangle((30, 28, 41, 33), fill=1)
    # sail: triangle split by the mast
    apex, base_y, left, right, mast = (138, 30), 120, 102, 180, 138
    d.polygon((apex, (left, base_y), (mast - 2, base_y)), fill=1)
    d.polygon((apex, (mast + 3, base_y), (right, base_y)), fill=1)
    # mast below the sail
    d.rectangle((mast - 1, base_y, mast, 150), fill=1)
    # hull: raised bow and stern, lower deck between, sloping bow
    d.polygon(((54, 140), (78, 140), (78, 150), (198, 150), (198, 140),
               (228, 140), (228, 170), (66, 170)), fill=1)
    # keel teeth along the bottom of the hull
    for x in range(66, 228, 6):
        d.rectangle((x + 2, 170, x + 3, 175), fill=1)
    s = Screen()
    s.from_bitmap(im)
    # moon: four quarter-circle tiles
    s.gfx(5, 5, 0x14); s.gfx(5, 6, 0x15)
    s.gfx(6, 5, 0x17); s.gfx(6, 6, 0x16)
    # birds: two arcs make a 'v'
    for c in (11, 19):
        s.gfx(4, c, 0x13); s.gfx(4, c + 1, 0x12)
    # dotted water line running off to the right
    for c in range(39, 64, 2):
        s.gfx(17, c, 0x08)
    s.text(19, 13, "* THE HMS SEA HAWK *")
    return s


if __name__ == "__main__":
    build().render("boat_preview.png")
