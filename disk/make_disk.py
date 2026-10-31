"""Build the disc software for this ROM and a disc image with the programs.

fdos_listing.txt is the Dec 1980 listing as printed. It was written for the
Mark III monitor, which has two routines at different addresses from the
original COMP80 ROM used here, so those calls are patched:
    CALL 03C6 (new line, keeps A)        -> CALL 03C4
    CALL 0261 (print inline GS string)   -> CALL 03CE
CALL 03DE (read 4 hex digits) is the same in both.

Writes fdos.bin (1D00-1EFF) and programs.img (IBM 3740: 77 tracks x 26
sectors x 128 bytes, sectors numbered 1-26).
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
TRACKS, SECTORS, SIZE = 77, 26, 128


def load_listing():
    data = bytearray()
    for line in (HERE / "fdos_listing.txt").read_text().splitlines():
        if not line.strip() or line.startswith(";"):
            continue
        addr, *hexes = line.split()
        assert int(addr, 16) == 0x1D00 + len(data) and len(hexes) == 16, line
        data += bytes(int(h, 16) for h in hexes)
    assert len(data) == 512
    return data


def patch(data):
    fixes = {0x03C6: 0x03C4, 0x0261: 0x03CE}
    n = 0
    for i in range(len(data) - 2):
        if data[i] == 0xCD:
            target = data[i + 1] | data[i + 2] << 8
            if target in fixes:
                new = fixes[target]
                data[i + 1], data[i + 2] = new & 0xFF, new >> 8
                n += 1
    assert n == 12, n
    return data


def screen_text(lines):
    """64 x 32 screen of text: ASCII & 3Fh, blanks as spaces."""
    out = bytearray(b"\x20" * 2048)
    for row, text in enumerate(lines):
        for col, ch in enumerate(text[:64]):
            out[row * 64 + col] = ord(ch.upper()) & 0x3F
    return out


# (name, file, track, load address, run command)
PROGRAMS = [
    ("GAME OF LIFE", ROOT / "life/life.bin", 1, 0x1000, "RUN 1000"),
    ("SAILING BOAT", ROOT / "pictures/boat.bin", 2, 0x1000, "RUN 1000"),
    ("SCHMITT TRIGGER", ROOT / "pictures/schmitt.bin", 3, 0x1000, "RUN 1000"),
    ("DISC SOFTWARE", HERE / "fdos.bin", 4, 0x1D00, "RUN 1D00"),
]


def main():
    fdos = patch(load_listing())
    (HERE / "fdos.bin").write_bytes(fdos)

    disk = bytearray(b"\xE5" * (TRACKS * SECTORS * SIZE))

    def put(track, data):
        nsec = (len(data) + SIZE - 1) // SIZE
        assert nsec <= SECTORS
        off = track * SECTORS * SIZE        # sector 1 of the track
        disk[off:off + len(data)] = data
        return nsec

    rows = [
        "",                                 # row 0 is overwritten by READY
        "PSI COMP80 PROGRAM DISC",
        "",
        "LOAD WITH THE DISC SOFTWARE: RUN 1D00, THEN READ",
        "",
        "PROGRAM          DEST  TRACK SECTOR SECTORS  THEN",
        "",
    ]
    table = []
    for name, path, track, addr, run in PROGRAMS:
        nsec = (path.stat().st_size + SIZE - 1) // SIZE
        rows.append(f"{name:<16} {addr:04X}  {track:>5} {1:>6} {nsec:>7}  {run}")
        table.append((name, path, track, addr, nsec, run))
    rows += [
        "",
        "EXAMPLE: READ  DESTINATION: 1000  TRACK: 1  SECTOR: 1",
        "               NUMBER OF SECTORS: 6     THEN RUN 1000",
        "",
        "THIS LIST: READ 8000, TRACK 0, SECTOR 1, 16 SECTORS",
    ]
    put(0, screen_text(rows))
    for name, path, track, addr, nsec, run in table:
        put(track, path.read_bytes())

    (HERE / "programs.img").write_bytes(disk)
    for r in rows:
        print(r)


if __name__ == "__main__":
    main()
