"""Route the last few connections Freerouting couldn't, by searching a grid.

Run with KiCad's Python after route_board.py:

  KICAD_PY finish_routes.py [--pcb board.kicad_pcb] [NET ...]

For each net still in more than one piece (or the nets named), it searches a
0.2 mm grid on both copper layers (A*, eight directions, vias between layers)
for a path from one piece to the next that keeps the netclass clearance from
everything on other nets, then adds the tracks and vias. The board is saved in
place; check it with KiCad's DRC afterwards.
"""
import heapq, math, os, sys

import numpy as np
import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
PCB = os.path.join(HERE, "..", "kicad", "psicomp80.kicad_pcb")
GRID = float(os.environ.get("GRID", "0.2"))     # mm; GRID=0.1 finds paths through tighter gaps
TRACK = float(os.environ.get("TRACK", "0.2"))   # track width, mm: the board's narrowest, as a new track may start on a necked one
VIA, DRILL = 0.6, 0.3
CLEAR = float(os.environ.get("CLEAR", "0.25"))  # the larger of the board's netclass clearances
EDGE = 1.2                  # keep this far inside the board edge
VIA_COST = 25


def mm(v):
    return pcbnew.ToMM(v)


class Grid:
    def __init__(self, board):
        box = board.GetBoardEdgesBoundingBox()
        self.x0, self.y0 = mm(box.GetLeft()), mm(box.GetTop())
        self.w = int(mm(box.GetWidth()) / GRID) + 1
        self.h = int(mm(box.GetHeight()) / GRID) + 1

    def cell(self, x, y):
        return int(round((x - self.x0) / GRID)), int(round((y - self.y0) / GRID))

    def pos(self, i, j):
        return self.x0 + i * GRID, self.y0 + j * GRID


def mark_segment(arr, g, ax, ay, bx, by, r):
    """Set every cell whose centre lies within r of the segment a-b."""
    i0, j0 = g.cell(min(ax, bx) - r, min(ay, by) - r)
    i1, j1 = g.cell(max(ax, bx) + r, max(ay, by) + r)
    i0, j0, i1, j1 = max(i0, 0), max(j0, 0), min(i1, g.w - 1), min(j1, g.h - 1)
    if i1 < i0 or j1 < j0:
        return
    xs = g.x0 + np.arange(i0, i1 + 1) * GRID
    ys = g.y0 + np.arange(j0, j1 + 1) * GRID
    X, Y = np.meshgrid(xs, ys, indexing="ij")
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = np.clip(((X - ax) * dx + (Y - ay) * dy) / L, 0, 1) if L > 0 else 0
    d2 = (X - (ax + t * dx)) ** 2 + (Y - (ay + t * dy)) ** 2
    arr[i0:i1 + 1, j0:j1 + 1] |= d2 <= r * r


def item_shapes(item):
    """(layers, segments as (ax, ay, bx, by, half-width)) of a copper item."""
    if item.GetClass() == "PCB_VIA":
        p = item.GetPosition()
        r = mm(item.GetWidth(pcbnew.F_Cu)) / 2
        return (pcbnew.F_Cu, pcbnew.B_Cu), [(mm(p.x), mm(p.y), mm(p.x), mm(p.y), r)]
    if item.GetClass() == "PCB_TRACK":
        a, b = item.GetStart(), item.GetEnd()
        return (item.GetLayer(),), [(mm(a.x), mm(a.y), mm(b.x), mm(b.y), mm(item.GetWidth()) / 2)]
    # a pad: a capsule along its longer side (rectangular pads come out slightly rounded)
    layers = [l for l in (pcbnew.F_Cu, pcbnew.B_Cu) if item.IsOnLayer(l)]
    bb = item.GetBoundingBox()
    x0, y0, x1, y1 = mm(bb.GetLeft()), mm(bb.GetTop()), mm(bb.GetRight()), mm(bb.GetBottom())
    w, h = x1 - x0, y1 - y0
    if w >= h:
        r = h / 2
        return layers, [(x0 + r, (y0 + y1) / 2, x1 - r, (y0 + y1) / 2, r)]
    r = w / 2
    return layers, [((x0 + x1) / 2, y0 + r, (x0 + x1) / 2, y1 - r, r)]


def copper(board):
    items = list(board.Tracks())
    for fp in board.GetFootprints():
        items += list(fp.Pads())
    return items


def pieces(board, net):
    """The net's copper, split into connected pieces (lists of items)."""
    items = [it for it in copper(board) if it.GetNetCode() == net]
    shapes = [item_shapes(it) for it in items]
    parent = list(range(len(items)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def touch(s1, s2):
        (l1, g1), (l2, g2) = s1, s2
        if not set(l1) & set(l2):
            return False
        for ax, ay, bx, by, r in g1:
            for cx, cy, dx, dy, q in g2:
                # endpoints near the other's centre line are enough for tracks meeting pads and vias
                for px, py in ((ax, ay), (bx, by)):
                    if seg_dist(px, py, cx, cy, dx, dy) <= q + r * 0.5 + 0.01:
                        return True
                for px, py in ((cx, cy), (dx, dy)):
                    if seg_dist(px, py, ax, ay, bx, by) <= r + q * 0.5 + 0.01:
                        return True
        return False

    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            if find(i) != find(j) and touch(shapes[i], shapes[j]):
                parent[find(i)] = find(j)
    groups = {}
    for i in range(len(items)):
        groups.setdefault(find(i), []).append(i)
    return [[(items[i], shapes[i]) for i in g] for g in groups.values()]


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = 0 if L == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def route(board, g, net):
    groups = pieces(board, net)
    if len(groups) < 2:
        return 0
    LAYERS = (pcbnew.F_Cu, pcbnew.B_Cu)
    # what the track (and a via) must keep clear of
    block = {l: np.zeros((g.w, g.h), bool) for l in LAYERS}
    vblock = {l: np.zeros((g.w, g.h), bool) for l in LAYERS}
    for it in copper(board):
        if it.GetNetCode() == net:
            continue
        layers, segs = item_shapes(it)
        for l in layers:
            for ax, ay, bx, by, r in segs:
                mark_segment(block[l], g, ax, ay, bx, by, r + CLEAR + TRACK / 2 + GRID * 0.5)
                mark_segment(vblock[l], g, ax, ay, bx, by, r + CLEAR + VIA / 2 + GRID * 0.5)
    margin = int(EDGE / GRID)
    for l in LAYERS:
        for arr in (block[l], vblock[l]):
            arr[:margin, :] = arr[-margin:, :] = True
            arr[:, :margin] = arr[:, -margin:] = True
    # the rule areas along the board edge are kept clear by the margin; the
    # holes of mounting holes are pads, so they're in already

    # join the pieces one by one onto the biggest
    groups.sort(key=len, reverse=True)
    tree = groups[0]
    added = 0
    for other in groups[1:]:
        src = {l: np.zeros((g.w, g.h), bool) for l in LAYERS}
        dst = {l: np.zeros((g.w, g.h), bool) for l in LAYERS}
        for marks, group in ((src, other), (dst, tree)):
            for it, (layers, segs) in group:
                for l in layers:
                    for ax, ay, bx, by, r in segs:
                        mark_segment(marks[l], g, ax, ay, bx, by, max(r - GRID * 0.5, GRID * 0.3))
        path = astar(g, block, vblock, src, dst)
        if path is None:
            print(f"  {board.GetNetInfo().GetNetItem(net).GetNetname()}: no path")
            continue
        added += emit(board, g, net, path)
        tree = tree + other
    return added


def astar(g, block, vblock, src, dst):
    LAYERS = (pcbnew.F_Cu, pcbnew.B_Cu)
    dsts = [np.argwhere(dst[l]) for l in LAYERS]
    if not any(len(d) for d in dsts):
        return None
    tx, ty = np.concatenate([d for d in dsts if len(d)]).mean(axis=0)
    heap, best, came = [], {}, {}
    for li, l in enumerate(LAYERS):
        for i, j in np.argwhere(src[l]):
            k = (int(i), int(j), li)
            best[k] = 0.0
            heapq.heappush(heap, (math.hypot(i - tx, j - ty), 0.0, k))
    moves = [(1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
             (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)]
    seen = 0
    while heap:
        f, c, (i, j, li) = heapq.heappop(heap)
        if c > best.get((i, j, li), 1e18):
            continue
        l = LAYERS[li]
        if dst[l][i, j] and (i, j, li) in came:
            path = [(i, j, li)]
            while path[-1] in came:
                path.append(came[path[-1]])
            return path[::-1]
        seen += 1
        if seen > 20_000_000:
            return None
        for di, dj, w in moves:
            ni, nj = i + di, j + dj
            if not (0 <= ni < g.w and 0 <= nj < g.h):
                continue
            if block[l][ni, nj] and not dst[l][ni, nj] and not src[l][ni, nj]:
                continue
            k = (ni, nj, li)
            nc = c + w
            if nc < best.get(k, 1e18):
                best[k] = nc
                came[k] = (i, j, li)
                heapq.heappush(heap, (nc + math.hypot(ni - tx, nj - ty), nc, k))
        # a via to the other layer
        oi = 1 - li
        if not vblock[LAYERS[0]][i, j] and not vblock[LAYERS[1]][i, j]:
            k = (i, j, oi)
            nc = c + VIA_COST
            if nc < best.get(k, 1e18):
                best[k] = nc
                came[k] = (i, j, li)
                heapq.heappush(heap, (nc + math.hypot(i - tx, j - ty), nc, k))
    return None


def emit(board, g, net, path):
    LAYERS = (pcbnew.F_Cu, pcbnew.B_Cu)
    netinfo = board.GetNetInfo().GetNetItem(net)
    n = 0

    def pt(i, j):
        x, y = g.pos(i, j)
        return pcbnew.VECTOR2I(pcbnew.FromMM(x), pcbnew.FromMM(y))

    # straight runs between bends and layer changes
    start = path[0]
    prev = path[0]
    direction = None
    for k in path[1:] + [None]:
        if k is not None and k[2] == prev[2]:
            d = (k[0] - prev[0], k[1] - prev[1])
            if direction is None or d == direction:
                direction = d
                prev = k
                continue
        if (start[0], start[1]) != (prev[0], prev[1]):
            t = pcbnew.PCB_TRACK(board)
            t.SetStart(pt(start[0], start[1]))
            t.SetEnd(pt(prev[0], prev[1]))
            t.SetWidth(pcbnew.FromMM(TRACK))
            t.SetLayer(LAYERS[prev[2]])
            t.SetNet(netinfo)
            board.Add(t)
            n += 1
        if k is None:
            break
        if k[2] != prev[2]:
            v = pcbnew.PCB_VIA(board)
            v.SetPosition(pt(prev[0], prev[1]))
            v.SetWidth(pcbnew.FromMM(VIA))
            v.SetDrill(pcbnew.FromMM(DRILL))
            v.SetNet(netinfo)
            board.Add(v)
            n += 1
            start = k
            prev = k
            direction = None
        else:
            start = prev
            direction = (k[0] - prev[0], k[1] - prev[1])
            prev = k
    return n


def main():
    global PCB
    args = sys.argv[1:]
    if args[:1] == ["--pcb"]:
        PCB, args = args[1], args[2:]
    board = pcbnew.LoadBoard(PCB)
    g = Grid(board)
    names = args
    nets = [board.FindNet(n).GetNetCode() for n in names] if names else \
        [c for c in range(1, board.GetNetCount())]
    total = 0
    for code in nets:
        name = board.GetNetInfo().GetNetItem(code).GetNetname()
        if not names and name in ("", "GND"):
            continue
        n = route(board, g, code)
        if n:
            print(f"{name}: {n} tracks and vias added")
            total += n
    board.Save(PCB)
    board = pcbnew.LoadBoard(PCB)
    board.BuildConnectivity()
    print(total, "added;", board.GetConnectivity().GetUnconnectedCount(False), "connections still open")


if __name__ == "__main__":
    main()
