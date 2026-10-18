"""Splat / weight maps (uint8, sum 255) and vegetation density masks."""
import numpy as np

import worlddef as W
from common import N, HALF, ss, log, gauss_blur
from noise import fbm
from terrain import rng_for, resize_to

LAYER_ORDER = W.LAYERS      # Grass, ForestFloor, Farmland, Rock, Sand, RedClay, Snow, RoadVerge
REGIONS = ("Greenvale", "Highcrest", "Plateau", "Coast", "Basin")


def slope_map(H):
    gy, gx = np.gradient(H)
    return np.sqrt(gx * gx + gy * gy).astype(np.float32)          # rise / run


def quantize_weights(ws):
    """list of float32 arrays -> list of uint8 arrays that sum to 255 exactly (largest remainder)."""
    tot = np.zeros(ws[0].shape, dtype=np.float32)
    for w in ws:
        tot += w
    tot = np.maximum(tot, 1e-6)
    fl = []
    rem = []
    s = np.zeros(ws[0].shape, dtype=np.int16)
    for w in ws:
        v = w / tot * 255.0
        f = np.floor(v)
        fl.append(f.astype(np.uint8))
        rem.append((v - f).astype(np.float32))
        s += f.astype(np.int16)
    missing = (255 - s).astype(np.int16)              # 0..len(ws)-1 units to distribute
    out = fl
    # give the missing units to the layers with the largest remainders (iterate rank by rank)
    order_rem = rem
    for _ in range(len(ws)):
        need = missing > 0
        if not need.any():
            break
        k = np.zeros(ws[0].shape, dtype=np.int8)
        best = order_rem[0].copy()
        for li in range(1, len(ws)):
            gt = order_rem[li] > best
            k[gt] = li
            best[gt] = order_rem[li][gt]
        del best
        for li in range(len(ws)):
            m = need & (k == li)
            if m.any():
                out[li][m] += 1
                order_rem[li][m] = -1.0
        missing = missing - need.astype(np.int16)
    return out


def build_layers(M, H, roadres, verbose=True):
    """M: macro terrain dict (region weights, step), H: final heights (1 m). roadres: carve result (emin, cls, d0)."""
    step = M["step"]
    H = np.asarray(H, dtype=np.float32)
    sl = slope_map(H)
    sl = gauss_blur(sl, 0.8).astype(np.float32)
    # region weights upsampled to 1 m (float16 to save memory)
    rw = {}
    for k, name in enumerate(REGIONS):
        rw[name] = resize_to(M["wstack"][k], step, 1.0).astype(np.float16)
    rng = rng_for("layers")
    n_patch = fbm((N, N), 260.0, 4, rng_for("l_patch"), step=1.0).astype(np.float32)
    n_forest = fbm((N, N), 180.0, 5, rng_for("l_forest"), step=1.0).astype(np.float32)
    n_field = fbm((N, N), 95.0, 3, rng_for("l_field"), step=1.0).astype(np.float32)
    n_fine = fbm((N, N), 14.0, 3, rng_for("l_fine"), step=1.0).astype(np.float32)
    land = H > 0.3
    z = H
    # base soil weights per layer from region parameters
    base = {}
    for L in LAYER_ORDER:
        acc = np.zeros(H.shape, dtype=np.float32)
        for name in REGIONS:
            v = W.REGION_PARAMS[name]["soil"].get(L, 0.0)
            if v > 0:
                acc += rw[name].astype(np.float32) * np.float32(v)
        base[L] = acc
    forest_dens = np.zeros(H.shape, dtype=np.float32)
    scrub_dens = np.zeros(H.shape, dtype=np.float32)
    crop_dens = np.zeros(H.shape, dtype=np.float32)
    for name in REGIONS:
        p = W.REGION_PARAMS[name]
        w32 = rw[name].astype(np.float32)
        forest_dens += w32 * np.float32(p["forest"])
        scrub_dens += w32 * np.float32(p["scrub"])
        crop_dens += w32 * np.float32(p["crops"])

    flat = 1.0 - ss(sl, 0.06, 0.22)                     # 1 on flat ground
    steep = ss(sl, 0.42, 0.85)                          # 1 on steep ground
    cliffy = ss(sl, 0.8, 1.3)
    # forest patches
    forest_mask = ss(n_forest + 0.35 * n_patch, -0.15, 0.55)
    # --- weights
    w_rock = base["Rock"] * 0.6 + 1.2 * steep + 2.0 * cliffy + 0.5 * ss(z, 380.0, 520.0) * (rw["Highcrest"].astype(np.float32))
    w_snow = ss(z + 28.0 * n_patch + 10.0 * n_fine, 470.0, 545.0) * (1.0 - steep) * (0.25 + rw["Highcrest"].astype(np.float32) * 1.0)
    w_snow = w_snow * 3.0
    coastal = rw["Coast"].astype(np.float32)
    beach = ss(6.5 - z, 0.0, 4.5) * land * (0.4 + 0.8 * coastal)
    w_sand = base["Sand"] * (0.55 + 0.3 * n_patch) + 4.0 * beach + 0.4 * (1.0 - steep) * rw["Plateau"].astype(np.float32) * ss(-n_fine, -0.2, 0.9)
    clay_band = 0.5 + 0.5 * np.sin((z + 6.0 * n_patch) * 0.55)          # banded canyon strata
    w_clay = base["RedClay"] * (0.75 + 0.5 * clay_band) * (1.0 - 0.6 * beach) + 0.9 * steep * rw["Plateau"].astype(np.float32)
    fields = ss(n_field, -0.15, 0.15)
    field_zone = (rw["Greenvale"].astype(np.float32) * 1.0 + rw["Basin"].astype(np.float32) * 0.5) * flat * (1.0 - ss(z, 140.0, 190.0))
    w_farm = base["Farmland"] * 0.4 + 2.6 * field_zone * fields
    w_forest = base["ForestFloor"] * 0.5 + 2.2 * forest_mask * forest_dens * (1.0 - steep) * (1.0 - 0.8 * fields * field_zone)
    w_grass = base["Grass"] * (0.7 + 0.4 * n_patch) * (1.0 - 0.7 * steep) * (1.0 - 0.9 * beach) * (1.0 - ss(z, 420.0, 540.0)) + 0.15
    w_grass = w_grass * (1.0 - 0.8 * w_snow.clip(0, 1))
    # sea floor / water: sand
    sea = ~land
    w_sand = np.where(sea, 3.0, w_sand)
    # road verge from the carve result
    e = roadres["emin"]
    cls = roadres["cls"]
    dirt = (cls == 4) | (cls == 5)
    asph = (cls == 1) | (cls == 2) | (cls == 3) | (cls == 6)
    verge = np.zeros(H.shape, dtype=np.float32)
    verge = np.where(asph, 1.0 - ss(e, 0.2, 3.2), verge)
    verge = np.where(dirt, 1.0 - ss(e, 1.5, 6.5), verge)
    verge = verge * (1.0 - 0.5 * ss(n_fine, 0.2, 1.0) * ss(e, 1.0, 3.0))
    w_verge = verge * 12.0
    ws = {"Grass": w_grass, "ForestFloor": w_forest, "Farmland": w_farm, "Rock": w_rock, "Sand": w_sand,
          "RedClay": w_clay, "Snow": w_snow, "RoadVerge": w_verge}
    del w_grass, w_forest, w_farm, w_rock, w_sand, w_clay, w_snow, w_verge, base, rw, clay_band, beach, coastal, field_zone, fields, verge
    for k in ws:
        ws[k] = np.maximum(ws[k], 0.0).astype(np.float32)
    q = quantize_weights([ws[L] for L in LAYER_ORDER])
    del ws
    layers = {L: q[i] for i, L in enumerate(LAYER_ORDER)}
    # ---------------------------------------------------------------- vegetation density masks
    clear = ss(e, 7.0, 22.0)                                  # no vegetation on / next to roads
    clear = np.where(roadres["touched"], clear, 1.0)
    water_clear = ss(z, 0.8, 3.0)
    slope_ok = 1.0 - ss(sl, 0.55, 0.95)
    forest = forest_dens * forest_mask * (1.0 - ss(z, 450.0, 560.0)) * slope_ok * clear * water_clear
    forest = forest * (1.0 - 0.9 * (layers["Farmland"].astype(np.float32) / 255.0))
    forest = forest * (1.0 - (layers["Sand"].astype(np.float32) / 255.0) * 0.8)
    scrub_noise = ss(n_patch + 0.5 * n_fine, -0.5, 0.6)
    scrub = scrub_dens * (0.35 + 0.65 * scrub_noise) * slope_ok * clear * water_clear
    scrub = scrub * (1.0 - 0.9 * (layers["Snow"].astype(np.float32) / 255.0))
    crops = crop_dens * (layers["Farmland"].astype(np.float32) / 255.0) * clear * flat
    dens = {"forest": np.clip(forest * 255.0 * 1.4, 0, 255).astype(np.uint8),
            "scrub": np.clip(scrub * 255.0 * 1.4, 0, 255).astype(np.uint8),
            "crops": np.clip(crops * 255.0 * 1.4, 0, 255).astype(np.uint8)}
    return layers, dens, sl
