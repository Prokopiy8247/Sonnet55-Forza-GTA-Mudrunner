"""
trees.py - idempotent TREE KIT builder (Blender 5.2, run in the shared MCP Blender on :9889).

Usage inside Blender (explicit namespace dict so helper functions see each other):
    NS = {'TREE_IDS': ['tree_pine_a']}            # which assets to (re)build (nothing if omitted)
    P = r"<project>/Tools/blender/nature/trees.py"
    exec(compile(open(P, encoding='utf8').read(), P, 'exec'), NS)
Options (set in NS before exec): TREE_AO=True, TREE_FAR=True, TREE_EXPORT=False

Assets: tree_{pine,oak,birch,palm,dead,poplar,olive}_{a,b,c}  (+ <id>_Far crossed-card meshes, UCX_<id>_NN trunk hulls)
Files:  treelib.py (geometry core) | tree_fams.py (family builders) | trees.py (asset table, harness, export, validation)
"""
import os, io, contextlib
_DIR = os.path.join(r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza", "Tools", "blender", "nature")
for _f in ('treelib.py', 'tree_fams.py'):
    _p = os.path.join(_DIR, _f)
    exec(compile(open(_p, encoding='utf8').read(), _p, 'exec'), globals())

FAMILIES = ['pine', 'oak', 'birch', 'palm', 'dead', 'poplar', 'olive']
VARS = ['a', 'b', 'c']
ASSETS = {}

def stage_xy(aid):
    fam, var = aid.split('_')[1], aid.split('_')[2]
    idx = FAMILIES.index(fam) * 3 + VARS.index(var)
    return STAGE_X0 + idx * STAGE_DX, STAGE_Y

# --------------------------------------------------------------------------------------------- asset table
# ---- PINE / SPRUCE ---------------------------------------------------------------------------
# needle sprays: short dense 2-tri needle strips on needle-sleeved twigs (no bare brown rachis)
PINE_NEEDLE = dict(tprof=((0.5, 1.0),), sleeve=0.22, sleeve_r=1.1)
ASSETS['tree_pine_a'] = dict(fn=build_pine, seed=101, name='Spruce - dense conical', biome=['forest', 'alpine'], scale=(0.8, 1.3), family='conifer',
    P=dict(PINE_NEEDLE, H=18.0, r0=0.42, taper=0.88, z0=2.6, spacing=0.52, nb0=8, nb1=4, Lmax=4.3, lp=0.9, el_bot=-8, el_top=38, droop=0.65, uptip=0.75,
           sway=0.5, flare=0.5, seed=11, tstep=0.085, tlen=0.46, tw=0.075, hang=0.30, tdroop=0.30, topchance=0.6, tdroop_var=0.45, skirt_rough=0.6))
ASSETS['tree_pine_b'] = dict(fn=build_pine, seed=102, name='Subalpine fir - tall whorled spire', biome=['forest', 'alpine'], scale=(0.8, 1.2), family='conifer',
    P=dict(PINE_NEEDLE, H=21.5, r0=0.36, taper=0.95, z0=3.6, spacing=0.84, nb0=8, nb1=5, Lmax=3.0, lp=0.7, el_bot=2, el_top=26, droop=0.35, uptip=0.95, skip=0.08, short=0.1,
           sway=0.4, lean=(0.55, 0.25), flare=0.4, seed=12, tstep=0.095, tlen=0.44, tw=0.105, hang=0.22, tdroop=0.2, tdroop_var=0.5, topchance=0.6,
           # round 3: ragged small skirt, side twigs on every branch, short branchlets between the whorls, irregular whorl spacing / radius
           skirt_frac=0.34, skirt_drop=0.42, skirt_rough=0.8, spacing_jit=0.3, whorl_jit=0.16, subs=2, sub_len=0.38, inter=2, inter_len=0.5))
ASSETS['tree_pine_c'] = dict(fn=build_scots, seed=103, name='Scots pine - layered plates, wind swept', biome=['alpine', 'highland', 'forest'], scale=(0.8, 1.3), family='conifer',
    P=dict(H=14.5, r0=0.42, taper=0.9, flare=0.55, lobes=5, sway=0.65, lean=(0.9, 0.3), seed=13, stubs=8, lee=2.2, lee_amt=0.55,
           nlimbs=9, limb_z=(4.4, 11.8), L_lo=3.6, L_hi=1.5, el_lo=-10, el_hi=22, limb_r=0.15, padR=0.95, plate_pads=5, core_pads=6,
           droop_limbs=[(3.5, 205, 3.0, -30), (4.1, 80, 2.5, -26), (3.0, 320, 2.2, -32)], side_pads=5, top_pads=4,
           leaf_size=(0.38, 0.07), leaf_shape=((0.5, 1.0),), cover=0.58, core=0.55, pad_flat=0.45, fold=0.2, curl=-0.1, ldroop=0.25, outward=1.4, cull_in=0.5, up_bias_leaf=0.45))

# ---- OAK ------------------------------------------------------------------------------------
OAK_BASE = dict(wood='M_Tree_Bark', leaf='M_Tree_Leaf', trunk_amp=0.2, trunk_kf=4.4, trunk_kz=0.8, ridge_w=0.2, bark_cell=0.09, trunk_ring=0.10, lump=0.07, roots=(7, 1.5), limb_stagger=1.2,
                ridged=True, nlimbs=5, seglen=[0.8, 0.6, 0.4], collar=0.6, collar2=0.25,
                sides=[12, 8, 5], bark_amp=[0.12, 0.08, 0.0], r_end=[0.45, 0.4, 0.5], tpow=0.9, flex_gain=[0.5, 0.45, 0.4],
                nsub=[4, 3], s0=[0.30, 0.35], s1=[0.95, 0.95], ang=[(35, 65), (30, 60)], len_ratio=[0.55, 0.55], r_ratio=[0.55, 0.5],
                min_z=2.2, wig=0.2, limb_r=0.72, limb_out=1.0, fill=26, fill_r=1.6, leaf_shape=((0.34, 0.95), (0.7, 0.72)))
ASSETS['tree_oak_a'] = dict(fn=crown_tree, seed=201, name='Oak - wide spreading', biome=['temperate', 'farmland', 'park'], scale=(0.75, 1.25), family='broadleaf',
    P=dict(OAK_BASE, H=14.0, trunk_h=3.0, r0=0.66, r_fork=0.60, cen=(0, 0, 8.6), rad=(7.2, 7.2, 5.0), bot=0.62, clumpR=1.5, leaf_size=(0.5, 0.34),
           limb_phi=(30, 80), limb_q=(0.75, 0.92), flare=0.7, sway=0.25, lobes=6, squash=(1.0, 1.0, 0.78), cover=0.8, mid_clump_len=3.6))
ASSETS['tree_oak_b'] = dict(fn=crown_tree, seed=202, name='Oak - tall oval', biome=['temperate', 'forest'], scale=(0.75, 1.2), family='broadleaf',
    P=dict(OAK_BASE, H=16.0, trunk_h=3.8, r0=0.56, r_fork=0.55, cen=(0, 0, 9.5), rad=(5.2, 5.2, 5.4), bot=0.7, clumpR=1.35, leaf_size=(0.48, 0.32),
           nlimbs=6, leader=True, limb_phi=(12, 55), limb_q=(0.75, 0.92), flare=0.5, sway=0.3, lobes=5, squash=(1.0, 1.0, 0.85), cover=0.7, fill=18, min_z=3.0,
           limb_stagger=1.6, limb_out=0.85, nsub=[3, 3], ang=[(25, 55), (30, 60)], limb_r_list=[1.3, 0.75, 1.0, 0.62, 1.15, 0.8]))
ASSETS['tree_oak_c'] = dict(fn=crown_tree, seed=203, name='Oak - old gnarled low', biome=['temperate', 'farmland', 'meadow'], scale=(0.8, 1.2), family='broadleaf',
    P=dict(OAK_BASE, H=10.5, trunk_h=1.9, r0=0.85, r_fork=0.66, cen=(0.8, 0, 6.8), rad=(7.4, 7.0, 3.6), bot=0.55, clumpR=1.55, leaf_size=(0.5, 0.34),
           nlimbs=4, limb_phi=(55, 95), limb_out=1.3, limb_q=(0.8, 0.95), flare=0.9, sway=0.5, lean=(0.5, 0.2), lobes=7, squash=(1.0, 1.0, 0.7), cover=0.8, fill=22,
           min_z=1.8, trunk_pow=0.6, mid_clump_len=3.0, root_fat=0.8, roots=(7, 1.4), trunk_amp=0.24, peel=0.06,
           extra_clumps=[(0.8, 0.0, 7.2, 1.15), (1.4, 0.9, 6.8, 1.0), (0.2, -1.0, 6.7, 1.0), (2.4, -0.4, 6.5, 0.95), (-0.8, 0.6, 6.6, 0.95),
                         (0.9, 0.1, 8.3, 1.05), (-0.9, 1.7, 7.4, 1.0), (2.6, 1.7, 7.0, 0.95), (1.6, -2.0, 7.3, 1.0), (-2.2, -0.8, 7.2, 0.95), (3.4, 0.4, 6.7, 0.9)]))

# ---- BIRCH ----------------------------------------------------------------------------------
def birch_matfn(mb, pts):
    """white paper bark; the trunk foot (below ~0.4 m) is black fissured bark; taller dark tongues are real geometry (bark_tongues)"""
    dark = mb.mi('M_Tree_Bark_Dark'); light = mb.mi('M_Tree_Bark_Birch')
    npt = len(pts)
    def fn(i, j):
        z = 0.5 * (pts[min(i, npt - 1)].z + pts[min(i + 1, npt - 1)].z)
        return dark if z < 0.30 + 0.16 * hrand(j, 4.1, 2.2) else light
    return fn

def birch_ampfn(z):
    """deep fissures on the black foot (z < ~0.9 m) fading into smooth paper bark"""
    if z < 1.2:
        return (0.05 + 0.20 * (1.0 - smoothstep(0.6, 1.2, z)), z < 1.0)
    return (0.035, False)

BIRCH_MARKS = dict(dens=38.0, w=(0.09, 0.42), h=(0.013, 0.030), z_lo=0.7, K=5)
BIRCH_TONGUES = dict(per_ring=10, h=(0.2, 0.85), w=(0.07, 0.16), z0=0.22)
BIRCH_LIMB_MARKS = dict(dens=30.0, w=(0.05, 0.15), h=(0.009, 0.018), z_lo=0.0, K=5, rmin=0.03)
BIRCH_BASE = dict(wood='M_Tree_Bark_Birch', leaf='M_Tree_LeafLight', wood_lv=['M_Tree_Bark_Birch', 'M_Tree_Bark', 'M_Tree_Bark'], trunk_matfn=birch_matfn, trunk_ampfn=birch_ampfn,
                  trunk_dz=(0.045, 0.30, 1.6, 4.0), trunk_kf=4.6, trunk_kz=1.4, ridge_w=0.20, marks=BIRCH_MARKS, tongues=BIRCH_TONGUES, marks_limb=BIRCH_LIMB_MARKS, bark_cell=0.06,
                  trunk_amp=0.05, flare=0.28, lobes=4, flare_h=0.7, seglen=[0.7, 0.5, 0.35], sides=[10, 7, 5], bark_amp=[0.03, 0.0, 0.0],
                  r_end=[0.5, 0.45, 0.5], tpow=0.9, flex_gain=[0.5, 0.45, 0.4], nsub=[3, 3], s0=[0.28, 0.3], s1=[0.95, 0.95], ang=[(25, 55), (30, 60)],
                  len_ratio=[0.5, 0.5], r_ratio=[0.55, 0.55], up_bias=0.15, wig=0.1, core=0.6, cover=0.75, ldroop=0.55, outward=0.5, leaf_shape=((0.32, 0.95), (0.66, 0.6)),
                  collar=0.7, roots=None, fill_r=0.6, fill_out=0.3, fill_min_z=5.0)
ASSETS['tree_birch_a'] = dict(fn=crown_tree, seed=301, name='Birch - classic airy', biome=['temperate', 'boreal', 'forest'], scale=(0.8, 1.25), family='broadleaf',
    P=dict(BIRCH_BASE, H=12.5, trunk_h=4.0, r0=0.17, r_fork=0.62, cen=(0, 0, 8.3), rad=(3.3, 3.3, 4.4), bot=0.6, clumpR=0.85, leaf_size=(0.3, 0.2),
           nlimbs=3, leader=True, limb_phi=(10, 48), limb_q=(0.7, 0.9), sway=0.25, squash=(1, 1, 0.9), fill=14, min_z=3.4, hull_z=[-0.1, 0.6, 1.8, 3.2]))
ASSETS['tree_birch_b'] = dict(fn=crown_tree, seed=302, name='Birch - multi-stem clump', biome=['temperate', 'boreal', 'meadow'], scale=(0.8, 1.3), family='broadleaf',
    P=dict(BIRCH_BASE, H=10.0, cen=(0, 0, 6.5), rad=(3.8, 3.8, 3.3), bot=0.6, clumpR=0.8, leaf_size=(0.28, 0.19), nlimbs=2, leader=True, limb_phi=(15, 55), limb_q=(0.7, 0.9),
           sway=0.3, squash=(1, 1, 0.9), fill=7, min_z=2.8, trunk_seg=26, fill_min_z=4.0, cover=0.62, hull_z=[-0.1, 0.5, 1.4, 2.4],
           trunk_dz=(0.05, 0.35, 1.4, 3.5), marks=dict(BIRCH_MARKS, dens=30.0), marks_limb=dict(BIRCH_LIMB_MARKS, dens=22.0),
           stems=[dict(base=(-0.45, 0.15), lean=(-1.5, 0.3), h=6.0, r0=0.13, rf=0.6), dict(base=(0.5, 0.0), lean=(1.2, -0.5), h=5.6, r0=0.14, rf=0.6),
                  dict(base=(0.0, -0.5), lean=(0.2, 1.4), h=6.4, r0=0.15, rf=0.6)]))
ASSETS['tree_birch_c'] = dict(fn=crown_tree, seed=303, name='Birch - leaning weeping', biome=['temperate', 'boreal', 'riverside'], scale=(0.8, 1.2), family='broadleaf',
    P=dict(BIRCH_BASE, H=13.0, trunk_h=3.4, r0=0.21, r_fork=0.72, lean=(1.9, 0.7), cen=(1.0, 0.2, 8.0), rad=(3.6, 3.4, 4.9), bot=0.85, clumpR=0.7, leaf_size=(0.3, 0.16), nlimbs=5, leader=False,
           limb_phi=(24, 66), limb_q=(0.72, 0.95), limb_out=1.4, limb_stagger=0.9, sway=0.55, trunk_pow=0.7, squash=(0.62, 0.62, 1.9), ldroop=1.1, curl=-0.35, fill=16, min_z=3.0,
           seglen=[0.6, 0.45, 0.3], end_up=-0.15, hull_z=[-0.1, 0.6, 1.8, 3.0]))

# ---- PALM -----------------------------------------------------------------------------------
ASSETS['tree_palm_a'] = dict(fn=build_palm, seed=401, name='Coconut palm - curved', biome=['coast', 'tropical'], scale=(0.8, 1.2), family='palm',
    P=dict(H=8.8, lean=(2.4, 0.8), r0=0.24, r1=0.16, bulb=0.60, bulb_h=0.7, pitch=0.20, scar=0.11, ring=0.044, sides=16, fiber=0.012, seed=3, bark='M_Tree_Bark',
           nf=19, Lf=4.3, droop=1.7, e_top=50, e_bot=-12, rach_r=0.05, lf_step=0.09, lf_len=1.3, lf_w=0.06, lf_hang=58, lf_fwd=0.5, lf_droop=0.3,
           boots=8, boot_span=1.4, nuts=9, bend=0.3, roots=13, lf_var=(0.7, 1.15), droop_var=(0.65, 1.35)))
ASSETS['tree_palm_b'] = dict(fn=build_palm, seed=402, name='Fan palm - straight tall', biome=['coast', 'desert', 'urban'], scale=(0.8, 1.2), family='palm',
    P=dict(H=10.0, lean=(0.45, 0.2), r0=0.30, r1=0.20, bulb=0.45, bulb_h=0.8, pitch=0.28, scar=0.10, ring=0.05, sides=18, fiber=0.018, diamond=0.025, seed=5, bark='M_Tree_Bark',
           nf=24, Lf=2.4, droop=0.75, e_top=78, e_bot=8, rach_r=0.03, fan=True, fan_n=26, fan_spread=75, fan_len=1.55, fan_w=0.21, fan_hang=0.4, fan_split=0.45,
           skirt=15, skirt_len=1.5, dry_skirt=True, boots=34, boot_span=2.6, bend=0.3, roots=15, amp=0.07))
ASSETS['tree_palm_c'] = dict(fn=build_palm, seed=403, name='Canary date palm - stout', biome=['coast', 'mediterranean', 'urban'], scale=(0.8, 1.25), family='palm',
    P=dict(H=5.6, lean=(0.5, 0.1), r0=0.44, r1=0.38, bulb=0.42, bulb_h=0.7, pitch=0.2, scar=0.12, ring=0.044, sides=20, fiber=0.01, diamond=0.015, seed=7, bark='M_Tree_Bark',
           nf=34, Lf=3.3, droop=1.0, e_top=78, e_bot=20, rach_r=0.05, lf_step=0.1, lf_len=0.9, lf_w=0.055, lf_hang=50, lf_fwd=0.4, lf_droop=0.26,
           boots=30, boot_span=1.7, bend=0.3, amp=0.07, roots=16, upright=(9, 80, 0.55)))

# ---- DEAD / SCRUB ---------------------------------------------------------------------------
DEAD_BASE = dict(wood='M_Tree_Dead', leaf=None, trunk_amp=0.22, trunk_kf=3.6, trunk_kz=1.2, ridge_w=0.22, bark_cell=0.06, trunk_ring=0.07, lump=0.12, roots=None, ridged=True, nlimbs=4,
                 seglen=[0.5, 0.4, 0.3, 0.25],
                 sides=[8, 6, 5, 4], bark_amp=[0.14, 0.1, 0.05, 0.0], r_end=[0.4, 0.4, 0.45, 0.5], tpow=0.9, flex_gain=[0.5, 0.45, 0.4, 0.4],
                 nsub=[3, 3, 2], s0=[0.3, 0.3, 0.3], s1=[0.95, 0.95, 0.95], ang=[(30, 70), (30, 70), (30, 70)], len_ratio=[0.6, 0.6, 0.6], r_ratio=[0.55, 0.55, 0.5],
                 min_z=1.2, wig=0.3, limb_r=0.7, broken=True, sway=0.45, stubs=2, collar=0.55, peel=0.12)
ASSETS['tree_dead_a'] = dict(fn=crown_tree, seed=501, name='Dead tree - bleached split snag', biome=['desert', 'badlands'], scale=(0.8, 1.3), family='dead',
    P=dict(DEAD_BASE, nsub=[4, 4, 3], len_ratio=[0.62, 0.6, 0.55], trunk_amp=0.30, lump=0.18, H=4.6, trunk_h=2.3, r0=0.30, r_fork=0.72, cen=(0, 0, 3.3), rad=(2.0, 2.0, 1.5), bot=0.8, nlimbs=3, limb_r=0.8, limb_stagger=0.9, collar=0.15,
           limb_phi=(20, 60), limb_q=(0.75, 0.95), flare=0.65, lobes=5, sway=0.7, lean=(0.35, 0.1), trunk_pow=0.55, twist=0.5, peel=0.22, bark_cell=0.05, trunk_ring=0.05,
           clefts=[(0.9, 0.14, 0.45, 1.9, 0.55), (4.1, 0.11, 0.9, 1.7, 0.45), (2.6, 0.09, 0.3, 1.2, 0.4)], splinters=(4, 0.18, 0.42), min_z=2.0, stubs=2,
           hull_z=[-0.1, 0.5, 1.2, 1.9]))
ASSETS['tree_dead_b'] = dict(fn=crown_tree, seed=502, name='Scrub tree - flat acacia', biome=['desert', 'savanna'], scale=(0.8, 1.3), family='dead',
    P=dict(DEAD_BASE, leaf='M_Tree_LeafDry', H=4.5, trunk_h=2.4, r0=0.22, r_fork=0.6, cen=(0, 0, 3.6), rad=(3.6, 3.6, 0.8), bot=0.5, lean=(0.5, 0.2), nlimbs=4,
           limb_phi=(62, 85), limb_q=(0.7, 0.95), nsub=[3, 2], clumpR=0.85, leaf_size=(0.24, 0.08), leaf_shape=((0.5, 1.0),), cover=0.55, core=0.55, squash=(1, 1, 0.35),
           fill=10, fill_r=1.2, min_z=2.8, flare=0.4, hull_z=[-0.1, 0.5, 1.3, 2.3], cull_in=0.2, stubs=0, trunk_amp=0.24, peel=0.14, twist=0.4,
           extra_clumps=[(0.3, 0.1, 3.75, 1.15), (0.9, 0.4, 3.6, 0.9), (-0.7, -0.4, 3.6, 0.9), (0.3, -0.9, 3.5, 0.8), (-0.4, 0.9, 3.5, 0.8)]))
ASSETS['tree_dead_c'] = dict(fn=crown_tree, seed=503, name='Dry scrub tree - wind bent juniper', biome=['desert', 'steppe', 'coast'], scale=(0.8, 1.3), family='dead',
    P=dict(DEAD_BASE, leaf='M_Tree_LeafDry', H=3.4, trunk_h=1.5, r0=0.20, r_fork=0.5, cen=(1.0, 0.3, 2.4), rad=(2.1, 1.7, 1.1), bot=0.7, lean=(1.3, 0.4), sway=0.5,
           nlimbs=5, limb_phi=(40, 85), limb_q=(0.75, 0.95), nsub=[3, 2], clumpR=0.5, leaf_size=(0.2, 0.07), leaf_shape=((0.5, 1.0),), cover=0.55, core=0.4, squash=(1, 1, 0.7),
           fill=3, fill_r=0.8, min_z=1.2, flare=0.5, hull_z=[-0.1, 0.4, 1.0, 1.6], bare=0.5, spiral=(0.2, 1.1), lump=0.2, trunk_amp=0.26, peel=0.15, stubs=1,
           seglen=[0.4, 0.35, 0.3, 0.25]))

# ---- POPLAR / CYPRESS -----------------------------------------------------------------------
POP_BASE = dict(wood='M_Tree_Bark', leaf='M_Tree_Leaf', trunk_amp=0.16, trunk_kf=3.6, trunk_kz=0.7, bark_cell=0.08, trunk_ring=0.35, lump=0.05, roots=(4, 0.8), ridged=True, nlimbs=0, seglen=[0.7, 0.45], sides=[7, 5],
                bark_amp=[0.05, 0.0], r_end=[0.5, 0.5], tpow=0.9, flex_gain=[0.55, 0.45], nsub=[2], s0=[0.35], s1=[0.95], ang=[(20, 50)], len_ratio=[0.5], r_ratio=[0.55],
                up_bias=0.5, wig=0.08, leader=True, leader_q=0.96, min_z=2.2, flare=0.5, lobes=6, core=0.62, cover=0.8)
ASSETS['tree_poplar_a'] = dict(fn=crown_tree, seed=601, name='Lombardy poplar - columnar flame', biome=['farmland', 'riverside', 'temperate'], scale=(0.8, 1.2), family='broadleaf',
    P=dict(POP_BASE, H=22.5, trunk_h=21.0, r0=0.40, r_fork=0.2, cen=(0.55, 0.2, 12.6), rad=(2.4, 2.4, 10.2), bot=1.0, clumpR=0.8, leaf_size=(0.3, 0.2), cover=0.68, lean=(1.1, 0.4), sway=0.35,
           side=[(4.6, 20.5, 46, (14, 36), 0.5, lambda z: 0.7 + 1.9 * math.sin(math.pi * clamp((z - 3.0) / 18.5)) ** 0.85 * (1.0 + 0.22 * math.sin(z * 1.9)))], squash=(0.85, 0.85, 1.0), hull_z=[-0.1, 0.6, 2.0, 4.0],
           axis_fill=dict(z0=5.0, z1=20.6, step=0.95, prof=lambda z: 0.3 + 1.2 * math.sin(math.pi * clamp((z - 3.5) / 17.5)) ** 0.9 * (1.0 + 0.2 * math.sin(z * 1.9 + 1.0))), leader_q=0.97))
ASSETS['tree_poplar_b'] = dict(fn=crown_tree, seed=602, name='Italian cypress - flame', biome=['mediterranean', 'farmland', 'cemetery'], scale=(0.8, 1.2), family='conifer',
    P=dict(POP_BASE, leaf='M_Tree_Needle', H=17.0, trunk_h=16.0, r0=0.30, r_fork=0.2, cen=(0.35, 0.15, 9.4), rad=(1.9, 1.9, 7.9), bot=1.0, clumpR=0.62, leaf_size=(0.34, 0.1), lean=(0.7, 0.3), sway=0.3,
           leaf_shape=((0.5, 1.0),), side=[(1.2, 15.2, 38, (10, 26), 0.5, lambda z: 0.5 + 1.2 * math.sin(math.pi * clamp((z - 0.5) / 16.0) ** 0.72) ** 1.1)],
           squash=(0.75, 0.75, 1.5), up_bias_leaf=0.7, ldroop=-0.1, cover=0.75, hull_z=[-0.1, 0.6, 2.0, 3.6], leader_q=0.92,
           axis_fill=dict(z0=2.0, z1=16.4, step=1.0, jit=0.5, prof=lambda z: 0.3 + 1.0 * math.sin(math.pi * clamp((z - 1.0) / 15.5) ** 0.72) ** 1.05)))
ASSETS['tree_poplar_c'] = dict(fn=crown_tree, seed=603, name='Black poplar - narrow oval', biome=['farmland', 'riverside', 'temperate'], scale=(0.8, 1.2), family='broadleaf',
    P=dict(POP_BASE, leaf='M_Tree_LeafLight', H=20.0, trunk_h=18.0, r0=0.38, r_fork=0.25, cen=(0, 0, 12.2), rad=(2.5, 2.5, 8.0), bot=0.9, clumpR=0.9, leaf_size=(0.34, 0.22),
           side=[(4.2, 17.5, 30, (28, 52), 0.45, lambda z: 0.9 + 1.4 * math.sin(math.pi * clamp((z - 3.0) / 16.0)) ** 0.8)], nsub=[3], len_ratio=[0.5], ang=[(25, 55)],
           seglen=[0.8, 0.5], sides=[8, 5], bark_amp=[0.06, 0], fill=8, fill_r=1.0, min_z=3.5, squash=(1, 1, 0.9), hull_z=[-0.1, 0.6, 2.0, 4.0],
           axis_fill=dict(z0=4.6, z1=19.4, step=0.95, jit=0.9, prof=lambda z: 0.5 + 1.0 * math.sin(math.pi * clamp((z - 3.5) / 16.0)) ** 0.8), leader_q=0.88))

# ---- OLIVE / FRUIT --------------------------------------------------------------------------
OLV_BASE = dict(wood='M_Tree_Bark', leaf='M_Tree_LeafDry', trunk_amp=0.22, trunk_kf=3.6, trunk_kz=1.0, ridge_w=0.2, bark_cell=0.07, trunk_ring=0.08, lump=0.14, roots=(4, 0.7), ridged=True, nlimbs=5, seglen=[0.6, 0.45, 0.3],
                sides=[8, 6, 5], bark_amp=[0.12, 0.07, 0.0], r_end=[0.45, 0.45, 0.5], tpow=0.9, flex_gain=[0.5, 0.45, 0.4], nsub=[3, 3], s0=[0.3, 0.3], s1=[0.95, 0.95],
                ang=[(35, 65), (35, 65)], len_ratio=[0.55, 0.55], r_ratio=[0.55, 0.5], wig=0.14, limb_r=0.7, core=0.6, cover=0.9, min_z=1.4, collar=0.55)
ASSETS['tree_olive_a'] = dict(fn=crown_tree, seed=701, name='Olive tree - twisted', biome=['mediterranean', 'farmland'], scale=(0.8, 1.3), family='broadleaf',
    P=dict(OLV_BASE, H=5.0, trunk_h=1.3, r0=0.30, r_fork=0.6, cen=(0, 0, 3.3), rad=(2.6, 2.6, 1.7), bot=0.7, clumpR=0.6, leaf_size=(0.32, 0.1), leaf_shape=((0.5, 1.0),),
           limb_phi=(45, 80), limb_q=(0.75, 0.95), sway=0.45, flare=0.6, lobes=5, fill=12, fill_r=0.9, ldroop=0.3, hull_z=[-0.1, 0.4, 0.9, 1.3],
           twist=1.7, spiral=(0.2, 1.2), trunk_amp=0.28, lump=0.24, clefts=[(2.2, 0.3, 0.25, 0.95, 0.38), (5.0, 0.2, 0.5, 1.1, 0.3)],
           extra_clumps=[(0.0, 0.0, 3.5, 1.0)]))
ASSETS['tree_olive_b'] = dict(fn=crown_tree, seed=702, name='Young orchard tree - round crown', biome=['farmland', 'orchard'], scale=(0.8, 1.2), family='broadleaf',
    P=dict(OLV_BASE, leaf='M_Tree_LeafDry', H=4.1, trunk_h=1.15, r0=0.14, r_fork=0.72, cen=(0, 0, 2.7), rad=(1.8, 1.8, 1.4), bot=0.75, clumpR=0.5, leaf_size=(0.3, 0.1),
           leaf_shape=((0.5, 1.0),), nlimbs=5, limb_phi=(35, 75), limb_q=(0.75, 0.95), sway=0.06, trunk_amp=0.1, flare=0.3, lobes=4, fill=8, fill_r=0.8, min_z=1.2,
           trunk_sides=12, hull_z=[-0.1, 0.4, 0.8, 1.1], roots=(3, 0.4), lump=0.04, twist=0.0,
           extra_clumps=[(0.0, 0.0, 2.85, 0.95)]))
ASSETS['tree_olive_c'] = dict(fn=crown_tree, seed=703, max_h=5.92, name='Olive tree - old split trunk', biome=['mediterranean', 'farmland'], scale=(0.8, 1.2), family='broadleaf',
    P=dict(OLV_BASE, H=5.8, cen=(0, 0, 3.7), rad=(3.0, 2.8, 2.0), bot=0.65, clumpR=0.62, leaf_size=(0.34, 0.1), leaf_shape=((0.5, 1.0),), nlimbs=3, limb_phi=(40, 80),
           limb_q=(0.75, 0.95), sway=0.35, flare=0.7, lobes=4, fill=14, fill_r=1.0, ldroop=0.3, hull_z=[-0.1, 0.4, 0.9, 1.5], twist=1.2, trunk_amp=0.26,
           extra_clumps=[(0.0, 0.0, 4.0, 1.05), (0.2, 0.3, 3.55, 0.9), (-0.3, -0.3, 3.5, 0.9)],
           stems=[dict(base=(-0.28, 0.0), lean=(-0.7, 0.0), h=1.9, r0=0.28, rf=0.7), dict(base=(0.3, 0.1), lean=(0.8, 0.2), h=1.7, r0=0.26, rf=0.7)]))

# --------------------------------------------------------------------------------------------- validation / export
_FBX_LIB = os.path.join(r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza", "Tools", "blender", "lib", "fbx_export.py")
TRI_BUDGET = (200, 60000)

def island_check(obj):
    """connected pieces: closed pieces must have positive signed volume (outward normals); open pieces = single-sided leaf cards"""
    bm = bmesh.new(); bm.from_mesh(obj.data); bm.faces.ensure_lookup_table()
    seen = set(); closed = inverted = opened = 0
    for f in bm.faces:
        if f.index in seen: continue
        stack = [f]; seen.add(f.index); faces = []; boundary = False
        while stack:
            cur = stack.pop(); faces.append(cur)
            for e in cur.edges:
                lf = e.link_faces
                if len(lf) == 1: boundary = True
                for g in lf:
                    if g.index not in seen:
                        seen.add(g.index); stack.append(g)
        if boundary:
            opened += 1; continue
        closed += 1
        vol = 0.0
        for fc in faces:
            vs = [v.co for v in fc.verts]
            for k in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[k].cross(vs[k + 1])) / 6.0
        if vol < 0: inverted += 1
    bm.free()
    return dict(closed_pieces=closed, open_pieces=opened, inverted_closed_pieces=inverted)

def ucx_cover(obj, ucx_names, z0=0.35, z1=1.0, pad=0.12):
    """% of the bark vertices (z0..z1 above ground, i.e. the trunk(s), not foliage) that lie inside the XY box of some UCX hull (+pad)"""
    me = obj.data
    co = np.empty(len(me.vertices) * 3, dtype=np.float32); me.vertices.foreach_get('co', co); co = co.reshape(-1, 3)
    mi = np.empty(len(me.polygons), dtype=np.int32); me.polygons.foreach_get('material_index', mi)
    lp = np.empty(len(me.loops), dtype=np.int32); me.loops.foreach_get('vertex_index', lp)
    ls = np.empty(len(me.polygons), dtype=np.int32); me.polygons.foreach_get('loop_start', ls)
    lt = np.empty(len(me.polygons), dtype=np.int32); me.polygons.foreach_get('loop_total', lt)
    vm = np.zeros(len(me.vertices), bool)
    for pi in range(len(me.polygons)):
        nm = me.materials[mi[pi]].name
        if not any(k in nm for k in ('Leaf', 'Needle', 'Palm')):
            vm[lp[ls[pi]:ls[pi] + lt[pi]]] = True
    pts = co[vm & (co[:, 2] > z0) & (co[:, 2] < z1)][:, :2]
    if len(pts) == 0:
        return 100.0
    ins = np.zeros(len(pts), bool)
    for n in ucx_names:
        h = np.array([(v.co.x, v.co.y) for v in bpy.data.objects[n].data.vertices])
        lo = h.min(0) - pad; hi = h.max(0) + pad
        ins |= ((pts >= lo) & (pts <= hi)).all(axis=1)
    return round(float(100.0 * ins.mean()), 1)

def validate(aid, obj, ucx_names, far_obj=None):
    s = mesh_stats(obj)
    rep = dict(id=aid, **s)
    rep['scale_ok'] = tuple(round(x, 4) for x in obj.scale) == (1.0, 1.0, 1.0) and all(abs(a) < 1e-6 for a in obj.rotation_euler)
    rep['ground_ok'] = (s['bbox_min'][2] <= 0.0 and s['bbox_min'][2] > -0.6)
    rep['uv'] = [u.name for u in obj.data.uv_layers]
    co = np.empty(len(obj.data.uv_layers[0].data) * 2, dtype=np.float32); obj.data.uv_layers[0].data.foreach_get('uv', co)
    rep['uv_finite'] = bool(np.isfinite(co).all())
    cols = np.empty(len(obj.data.color_attributes['Col'].data) * 4, dtype=np.float32); obj.data.color_attributes['Col'].data.foreach_get('color', cols)
    cols = cols.reshape(-1, 4)
    rep['col_range'] = [[round(float(cols[:, k].min()), 2), round(float(cols[:, k].max()), 2)] for k in range(3)]
    rep['materials'] = [m.name for m in obj.data.materials]
    rep['ucx'] = {}
    for n in ucx_names:
        uo = bpy.data.objects[n]
        bm = bmesh.new(); bm.from_mesh(uo.data)
        convex = all(e.calc_face_angle_signed(0.0) >= -1e-4 for e in bm.edges if len(e.link_faces) == 2)
        rep['ucx'][n] = dict(verts=len(uo.data.vertices), convex=convex, manifold=all(len(e.link_faces) == 2 for e in bm.edges))
        bm.free()
    rep['ucx_cover_pct'] = ucx_cover(obj, ucx_names)
    rep['tri_ok'] = TRI_BUDGET[0] <= s['tris'] <= TRI_BUDGET[1]
    rep['name_ok'] = (obj.name == aid and all(n.startswith('UCX_' + aid + '_') for n in ucx_names))
    rep.update(island_check(obj))
    if far_obj is not None:
        fs = mesh_stats(far_obj)
        rep['far'] = dict(name=far_obj.name, tris=fs['tris'], bbox=[fs['bbox_min'], fs['bbox_max']], materials=[m.name for m in far_obj.data.materials])
    return rep

_FBXLOADED = [False]
def _fbx():
    if not _FBXLOADED[0]:
        exec(compile(open(_FBX_LIB, encoding='utf8').read(), _FBX_LIB, 'exec'), globals())
        _FBXLOADED[0] = True

def _png_size(path):
    try:
        with open(path, 'rb') as f:
            d = f.read(32)
        return list(struct.unpack('>II', d[16:24]))
    except Exception:
        return [0, 0]

def export_asset(aid, rep):
    _fbx()
    bpy.context.view_layer.update()   # matrix_world must be current (objects were just created)
    spec = ASSETS[aid]
    ucx = sorted(n for n in rep['ucx'])
    kw = dict(colors_type='LINEAR')
    path = os.path.join(EXPORT_DIR, aid + '.fbx')
    far_name = aid + '_Far'
    p2 = None
    with contextlib.redirect_stdout(io.StringIO()):
        p1 = export_fbx([aid] + ucx, path, center_on='self', extra_kwargs=kw)
        if far_name in bpy.data.objects:
            p2 = export_fbx([far_name], os.path.join(EXPORT_DIR, far_name + '.fbx'), center_on='self', extra_kwargs=kw)
    size = [round(rep['bbox_max'][k] - rep['bbox_min'][k], 3) for k in range(3)]
    far = rep.get('far')
    js = dict(
        id=aid, display_name=spec['name'], kit='trees', family=spec['family'], units='m',
        origin='base centre of trunk on the ground (z=0); trunk/roots buried up to ~0.5 m; +Z up',
        dimensions=dict(x=size[0], y=size[1], z=size[2], height=round(rep['bbox_max'][2], 3)),
        bounds=dict(min=rep['bbox_min'], max=rep['bbox_max']),
        tri_counts=dict(mesh=rep['tris'], far=(far['tris'] if far else 0), ucx=[len(bpy.data.objects[n].data.polygons) for n in ucx]),
        material_slots=rep['materials'],
        collision=dict(type='convex', ucx_hulls=ucx, trunk_only=True, hulls_per_stem=len(ucx) if len(ucx) > 1 and spec['P'].get('stems') else 1,
                       notes='UCX_* trunk capsule-like convex hulls (<=32 verts); one hull per stem on multi-stem trees (birch_b, olive_c), two stacked hulls on curved palm trunks; canopy/foliage has NO collision. UE: Collision Complexity = Use Simple As Complex'),
        far_card=dict(mesh=far_name, fbx=far_name + '.fbx', texture='Textures/T_%s_Far.png' % aid, texture_px=_png_size(os.path.join(EXPORT_DIR, 'Textures', 'T_%s_Far.png' % aid)), texture_pot=True,
                      width_m=(far['bbox'][1][0] - far['bbox'][0][0]) if far else 0, height_m=size[2], tris=(far['tris'] if far else 0),
                      material=(far['materials'][0] if far else None),
                      use='swap in beyond ~120-200 m (or as impostor); alpha-masked (clip ~0.33), two-sided, 2 crossed quads; power-of-two texture atlas = [view along Y | view along X], each half maps to one quad (non-uniform texel aspect, UVs fill 0-1)'),
        biome_tags=spec['biome'], scale_range=list(spec['scale']),
        wind=dict(vertex_color='Col', export_colors='LINEAR (raw 0-1 masks, no sRGB conversion)',
                  R='branch flex 0 (trunk base) -> 1 (twig/leaf tips)', G='leaf flutter 0 (wood) -> 1 (free leaf tips)',
                  B='baked ambient occlusion (ray cast, 1 = open sky)',
                  hint='WPO: sway = R^2 * low-freq wind; flutter = G * high-freq noise; multiply base colour by lerp(0.35,1,B)'),
        lod=dict(nanite='recommended (all opaque geometry, no alpha cards inside the mesh)', far_billboard=far_name,
                 notes='LOD0 = Nanite mesh; <id>_Far = distance impostor / HLOD card'),
        nanite_ok=True,
        uv='UVMap: trunk/branch U wraps once per ring, V = 0.25-0.5 per metre of length (tiling bark); leaf cards map 0-1 per card (planar)',
        quality=dict(closed_pieces=rep['closed_pieces'], open_pieces=rep['open_pieces'], inverted_closed_pieces=rep['inverted_closed_pieces'],
                     nonmanifold_edges=rep['nonmanifold_edges'], boundary_edges_note='open edges belong to single-sided leaf/needle cards by design'),
        files=dict(fbx='Exports/Nature/Trees/%s.fbx' % aid, far_fbx='Exports/Nature/Trees/%s.fbx' % far_name),
        generator='Tools/blender/nature/trees.py (seed %d)' % spec['seed'],
    )
    with open(os.path.join(EXPORT_DIR, aid + '.json'), 'w', encoding='utf8') as f:
        json.dump(js, f, indent=2)
    return p1, p2

# --------------------------------------------------------------------------------------------- harness
def build(aid, ao=True, far=True, export=False, verbose=True):
    t0 = time.time()
    spec = ASSETS[aid]
    remove_asset(aid)
    mats = ensure_tree_materials()
    mb = MB()
    rng = random.Random(spec['seed'])
    info = spec['fn'](mb, rng, spec['P'])
    mh = spec.get('max_h')
    if mh:       # uniform fit to the brief's height range (applied to verts + collision hulls before AO / far card)
        zmax = max(v[2] for v in mb.V)
        if zmax > mh:
            k = mh / zmax
            mb.V = [(x * k, y * k, z * k) for (x, y, z) in mb.V]
            info['hulls'] = [[(Vector(c) * k, r * k) for (c, r) in ring] for ring in info['hulls']]
    t1 = time.time()
    ao_t = bake_ao(mb, **dict(spec.get('ao', {}), tag_mul=spec.get('tag_mul', {'core': 0.55}))) if ao else 0.0
    me = mb_to_mesh(mb, aid, mats)
    col = get_trees_collection()
    x, y = stage_xy(aid)
    obj = make_object(aid, me, col, x, y)
    ucx = make_ucx(aid, obj, info['hulls'], col)
    st = mesh_stats(obj)
    height = st['bbox_max'][2]
    width = max(st['bbox_max'][0] - st['bbox_min'][0], st['bbox_max'][1] - st['bbox_min'][1])
    far_obj = None
    if far:
        half = max(abs(st['bbox_max'][0]), abs(st['bbox_min'][0]), abs(st['bbox_max'][1]), abs(st['bbox_min'][1]))
        far_obj, texpath, fsz = make_far(aid, mb, MAT_DEFS, col, x, FAR_Y, half * 2, height)
    rep = validate(aid, obj, ucx, far_obj)
    rep['seconds'] = round(time.time() - t0, 1); rep['build_s'] = round(t1 - t0, 1); rep['ao_s'] = round(ao_t, 1)
    rep['size'] = (round(width, 2), round(height, 2))
    if 'clumps' in info: rep['clumps'] = info['clumps']
    if export:
        p1, p2 = export_asset(aid, rep)
        rep['exported'] = [p1, p2]
    # aggregated machine-readable validation report (merged per asset)
    try:
        rp = os.path.join(EXPORT_DIR, 'validation_report.json')
        allr = json.load(open(rp, encoding='utf8')) if os.path.exists(rp) else {}
        allr[aid] = rep
        with open(rp, 'w', encoding='utf8') as f:
            json.dump(allr, f, indent=1)
    except Exception as e:
        print('report write failed', e)
    if verbose:
        bad = [k for k in ('scale_ok', 'ground_ok', 'uv_finite', 'tri_ok', 'name_ok') if not rep.get(k)]
        bad += ['inverted_pieces'] if rep['inverted_closed_pieces'] else []
        bad += ['nonmanifold'] if rep['nonmanifold_edges'] else []
        hulls = ' '.join('%d%s' % (v['verts'], '' if v['convex'] else '!') for v in rep['ucx'].values())
        print('%-14s tris %6d  size %5.1f x %5.1f  ucx[%s]  mats %s  %s  %.1fs%s' % (aid, rep['tris'], rep['size'][0], rep['size'][1], hulls,
              len(rep['materials']), ('FAIL ' + ','.join(bad)) if bad else 'ok', rep['seconds'], '  exported' if export else ''))
    return obj, rep

if 'TREE_IDS' in globals():
    for _aid in TREE_IDS:
        build(_aid, ao=globals().get('TREE_AO', True), far=globals().get('TREE_FAR', True), export=globals().get('TREE_EXPORT', False))
