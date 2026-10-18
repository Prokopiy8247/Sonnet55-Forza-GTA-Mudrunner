"""All preview images of the world build (PNG via our own writer)."""
import os

import numpy as np

import worlddef as W
import roads_def as RD
import profile as PR
import preview as P
from common import HALF, PREVIEW_DIR, log, ss
from pngio import draw_text, text_size, write_png

CLASS_COLORS = {"HIGHWAY": (235, 50, 50), "REGIONAL": (250, 205, 40), "MOUNTAIN": (255, 110, 255), "DIRT": (190, 130, 70),
                "SHORTCUT": (190, 130, 70), "VILLAGE": (250, 250, 250)}


def _draw_roads(img, w2p, roads, nodes=None, width=1.6, mark_flags=True):
    for rd in roads:
        c_, r_ = w2p(rd["xy"][:, 0], rd["xy"][:, 1])
        P.draw_polyline_px(img, c_, r_, CLASS_COLORS[rd["cls"]], width)
        if mark_flags:
            for a, b in PR.runs((rd["flags"] & PR.FLAG_BRIDGE) > 0):
                c_, r_ = w2p(rd["xy"][a:b + 1, 0], rd["xy"][a:b + 1, 1])
                P.draw_polyline_px(img, c_, r_, (70, 170, 255), width + 1.5)
            for a, b in PR.runs((rd["flags"] & PR.FLAG_TUNNEL) > 0):
                c_, r_ = w2p(rd["xy"][a:b + 1, 0], rd["xy"][a:b + 1, 1])
                P.draw_polyline_px(img, c_, r_, (10, 10, 10), width + 1.5)
    if nodes is not None:
        for nm, nd in nodes.items():
            c, r = w2p(nd["xy"][0], nd["xy"][1])
            ci, ri = int(c), int(r)
            if 0 <= ci < img.shape[1] and 0 <= ri < img.shape[0]:
                col = (255, 255, 255) if nd["kind"] != "X" else (255, 60, 60)
                img[max(0, ri - 2):ri + 3, max(0, ci - 2):ci + 3] = col


def _draw_water(img, w2p, M=None):
    import worlddef as W
    r = M["river"] if M is not None else W.make_river()
    c_, r_ = w2p(r['pts'][:, 0], r['pts'][:, 1])
    P.draw_polyline_px(img, c_, r_, (70, 150, 235), 2.0)
    for st in (M["streams"] if M is not None else []):
        c_, r_ = w2p(st['pts'][:, 0], st['pts'][:, 1])
        P.draw_polyline_px(img, c_, r_, (90, 170, 235), 1.0)


def overview(H, M, roads, nodes, sites, path, size_step=4, label=True):
    """hillshade + region colours + roads at 1/4 resolution (1008 px)"""
    Hs = H[::size_step, ::size_step][:1008, :1008]
    reg = None
    if M is not None:
        from terrain import resize_to
        reg_full = M["region"]
        # nearest upsample of the region id map to the preview grid
        step = M["step"]
        idx = (np.arange(Hs.shape[0]) * size_step / step).astype(int)
        idx = np.clip(idx, 0, reg_full.shape[0] - 1)
        reg = reg_full[np.ix_(idx, idx)]
    img = P.render_map(Hs, float(size_step), reg, tint_region=0.3, zex=1.6)
    Hm = P.to_map(Hs)
    img = P.add_contours(img, Hm, float(size_step), interval=50.0, major=250.0, alpha=0.22)
    n = Hs.shape[0]
    x_top = -HALF + (n - 1) * size_step

    def w2p(X, Y):
        return (np.asarray(Y) + HALF) / size_step, (x_top - np.asarray(X)) / size_step
    _draw_water(img, w2p, M)
    _draw_roads(img, w2p, roads, nodes, 1.6)
    if label:
        for nm, kind, X, Y in sites:
            col = {"hub": (255, 70, 70), "village": (255, 255, 120), "hamlet": (200, 235, 255), "harbour": (130, 220, 255),
                   "gas": (255, 160, 60), "lighthouse": (255, 255, 255), "viewpoint": (180, 255, 180)}.get(kind)
            if col is None:
                continue
            c, r = w2p(X, Y)
            img[int(r) - 2:int(r) + 3, int(c) - 2:int(c) + 3] = col
            draw_text(img, int(c) + 5, int(r) - 4, nm[:18], color=col, scale=1, shadow=(0, 0, 0))
    # legend
    y0 = 8
    for nm, col in (("HIGHWAY", CLASS_COLORS["HIGHWAY"]), ("REGIONAL", CLASS_COLORS["REGIONAL"]), ("MOUNTAIN", CLASS_COLORS["MOUNTAIN"]),
                    ("DIRT", CLASS_COLORS["DIRT"]), ("VILLAGE", CLASS_COLORS["VILLAGE"]), ("BRIDGE", (70, 170, 255)), ("TUNNEL", (10, 10, 10))):
        img[y0:y0 + 6, 8:26] = col
        draw_text(img, 30, y0 - 1, nm, color=(255, 255, 255), scale=1, shadow=(0, 0, 0))
        y0 += 11
    P.save(path, img)
    return img


def route_zoom(H, roads, nodes, box, path, step=2, rid_filter=None, hairpins=True, upscale=1, label=None):
    """zoomed crop (world box) at `step` m/px using the 1 m heightmap"""
    xmin, xmax, ymin, ymax = box
    Hs = H[::step, ::step]
    img, w2p, px = P.crop_view(Hs, float(step), None, box, upscale=upscale, contour=10.0 if step <= 2 else 25.0, zex=1.2, tint=0.0)
    sel = [r for r in roads if (rid_filter is None or r["id"] in rid_filter)]
    _draw_water(img, w2p)
    _draw_roads(img, w2p, sel, nodes, 1.8)
    if hairpins:
        for rd in sel:
            hp = (rd["flags"] & PR.FLAG_HAIRPIN) > 0
            for a, b in PR.runs(hp):
                m = (a + b) // 2
                c, r = w2p(rd["xy"][m, 0], rd["xy"][m, 1])
                ci, ri = int(c), int(r)
                if 0 <= ci < img.shape[1] and 0 <= ri < img.shape[0]:
                    img[max(0, ri - 2):ri + 3, max(0, ci - 2):ci + 3] = (255, 255, 0)
    if label:
        draw_text(img, 6, 6, label, color=(255, 255, 255), scale=2, shadow=(0, 0, 0))
    P.save(path, img)


def profile_strip(roads_seq, path, title, width=1700, height=420, speed_note=True):
    """elevation profile strip of a chain of roads with bridge / tunnel marks and grade colouring"""
    S = []
    Z = []
    T = []
    FL = []
    G = []
    marks = []
    off = 0.0
    for rd in roads_seq:
        S.append(rd["s"] + off)
        Z.append(rd["z"])
        T.append(rd["terrain"])
        FL.append(rd["flags"])
        G.append(rd["grade"])
        marks.append((off, rd["id"]))
        off += rd["s"][-1]
    S = np.concatenate(S)
    Z = np.concatenate(Z)
    T = np.concatenate(T)
    FL = np.concatenate(FL)
    G = np.concatenate(G)
    L = S[-1]
    zmin = min(Z.min(), T.min()) - 15
    zmax = max(Z.max(), T.max()) + 25
    ml, mr, mt, mb = 56, 14, 34, 40
    img = np.full((height, width, 3), 24, dtype=np.uint8)
    pw = width - ml - mr
    ph = height - mt - mb
    xs = np.arange(pw)
    sq = xs / (pw - 1) * L
    zq = np.interp(sq, S, Z)
    tq = np.interp(sq, S, T)
    gq = np.interp(sq, S, np.abs(G))
    fq = FL[np.clip(np.searchsorted(S, sq), 0, len(S) - 1)]
    def ypix(z):
        return mt + (1.0 - (z - zmin) / (zmax - zmin)) * (ph - 1)
    # grid
    for zz in np.arange(np.ceil(zmin / 100) * 100, zmax, 100):
        y = int(ypix(zz))
        img[y, ml:ml + pw] = (50, 50, 56)
        draw_text(img, 4, y - 3, "%d" % zz, color=(160, 160, 170))
    for ss_ in np.arange(0, L, 2000):
        x = ml + int(ss_ / L * (pw - 1))
        img[mt:mt + ph, x] = (50, 50, 56)
        draw_text(img, x - 6, mt + ph + 6, "%.0fKM" % (ss_ / 1000), color=(160, 160, 170))
    # terrain fill
    for i in range(pw):
        yt = int(ypix(tq[i]))
        img[yt:mt + ph, ml + i] = (78, 72, 62)
        img[yt, ml + i] = (130, 120, 100)
    # road profile coloured by grade
    for i in range(pw):
        y = int(ypix(zq[i]))
        g = gq[i]
        col = (80, 220, 110) if g < 0.05 else (240, 220, 60) if g < 0.09 else (255, 140, 40) if g < 0.115 else (255, 60, 60)
        img[max(0, y - 1):y + 2, ml + i] = col
        if fq[i] & PR.FLAG_BRIDGE:
            img[mt - 12:mt - 4, ml + i] = (70, 170, 255)
        if fq[i] & PR.FLAG_TUNNEL:
            img[mt - 12:mt - 4, ml + i] = (240, 240, 240)
        if fq[i] & PR.FLAG_HAIRPIN:
            img[mt - 22:mt - 16, ml + i] = (255, 255, 0)
    for off_, rid in marks:
        x = ml + int(off_ / L * (pw - 1))
        img[mt:mt + ph, x] = (120, 120, 200)
        draw_text(img, x + 3, mt + ph - 12, rid, color=(190, 190, 255))
    draw_text(img, 8, 8, title, color=(255, 255, 255), scale=1)
    draw_text(img, 8, 20, "BRIDGE=BLUE TUNNEL=WHITE HAIRPIN=YELLOW  GRADE: GREEN<5 YELLOW<9 ORANGE<11.5 RED", color=(170, 170, 180))
    P.save(path, img)


def slope_preview(H, sl, path):
    s = sl[::4, ::4][:1008, :1008]
    deg = np.degrees(np.arctan(s))
    Hm = P.to_map(deg)
    t = np.clip(Hm / 60.0, 0, 1)
    img = np.empty(Hm.shape + (3,), dtype=np.uint8)
    img[..., 0] = (255 * np.clip(t * 2.0, 0, 1)).astype(np.uint8)
    img[..., 1] = (255 * np.clip(2.0 - t * 2.0, 0, 1) * 0.9).astype(np.uint8)
    img[..., 2] = (40 * (1 - t)).astype(np.uint8)
    sea = P.to_map(H[::4, ::4][:1008, :1008]) <= 0.0
    img[sea] = (20, 60, 120)
    P.save(path, img)


def grade_histogram(roads, path):
    width, height = 900, 380
    img = np.full((height, width, 3), 24, dtype=np.uint8)
    classes = ["HIGHWAY", "REGIONAL", "MOUNTAIN", "DIRT", "VILLAGE"]
    bins = np.arange(0, 0.165, 0.01)
    ml, mt, mb = 60, 30, 40
    ph = height - mt - mb
    pw = width - ml - 20
    allc = {}
    for c in classes:
        gs = []
        for rd in roads:
            if rd["cls"] == c or (c == "DIRT" and rd["cls"] == "SHORTCUT"):
                ok = (rd["flags"] & (PR.FLAG_BRIDGE | PR.FLAG_TUNNEL)) == 0
                gs.append(np.abs(rd["grade"])[ok])
        allc[c] = np.concatenate(gs) if gs else np.zeros(1)
    # grouped log-ish bars (length in km per bin)
    hist = {c: np.histogram(allc[c], bins=bins)[0] * 2.0 / 1000.0 for c in classes}
    ymax = max(h.max() for h in hist.values()) * 1.1 + 1e-6
    nb = len(bins) - 1
    bw = pw / nb
    for bi in range(nb):
        for ci, c in enumerate(classes):
            h = hist[c][bi]
            x0 = int(ml + bi * bw + ci * (bw / (len(classes) + 1)))
            x1 = int(x0 + bw / (len(classes) + 1)) - 1
            y1 = mt + ph
            y0 = int(y1 - h / ymax * ph)
            col = CLASS_COLORS[c]
            img[y0:y1, x0:max(x0 + 1, x1)] = col
        draw_text(img, int(ml + bi * bw), mt + ph + 6, "%d" % (bins[bi] * 100), color=(160, 160, 170))
    draw_text(img, 8, 8, "ROAD GRADE HISTOGRAM (PERCENT, KM PER 1 PERCENT BIN)", color=(255, 255, 255))
    for ci, c in enumerate(classes):
        img[mt + 4 + ci * 11: mt + 10 + ci * 11, width - 130:width - 112] = CLASS_COLORS[c]
        draw_text(img, width - 108, mt + 3 + ci * 11, c, color=(220, 220, 230))
        lim = RD.CLASSES[c]["g_max"]
        x = int(ml + lim / 0.16 * pw)
        img[mt:mt + ph, x] = CLASS_COLORS[c]
    P.save(path, img)


def layers_preview(layers, dens, H, path):
    s = 4
    L = {k: v[::s, ::s][:1008, :1008].astype(np.float32) / 255.0 for k, v in layers.items()}
    cols = {"Grass": (96, 160, 64), "ForestFloor": (40, 90, 48), "Farmland": (200, 180, 90), "Rock": (120, 118, 118),
            "Sand": (230, 210, 150), "RedClay": (190, 90, 50), "Snow": (245, 248, 255), "RoadVerge": (140, 120, 100)}
    img = np.zeros(L["Grass"].shape + (3,), dtype=np.float32)
    for k, c in cols.items():
        img += L[k][..., None] * np.array(c, dtype=np.float32)
    img = P.to_map(np.clip(img, 0, 255).astype(np.uint8))
    sea = P.to_map(H[::s, ::s][:1008, :1008]) <= 0.0
    img[sea] = (30, 80, 140)
    P.save(path, img)
    d = np.zeros(L["Grass"].shape + (3,), dtype=np.float32)
    d[..., 1] = dens["forest"][::s, ::s][:1008, :1008]
    d[..., 0] = dens["scrub"][::s, ::s][:1008, :1008]
    d[..., 2] = dens["crops"][::s, ::s][:1008, :1008]
    d = P.to_map(d.astype(np.uint8))
    d[sea] = (10, 20, 40)
    P.save(path.replace("layers", "density"), d)
