"""lane4_hair.py - Hair_1..6, Beard_1..2 (material Hair, rigid to Head). Set C4_ONLY=['Hair_1',...] to build a subset."""
_S = math.sin
_C = math.cos
_fy = lambda x, z: c4_front_y(C4_HEAD_REF, x, z)


def c4_h1():   # short crop
    b = c4_new("h1")
    c4_hshell(b, lambda a: 1.652 + 0.074 * _S(a), [(0, .010), (.3, .016), (.62, .019), (.85, .015), (1, .008)], zt=1.81)
    return c4_finish(b, "Hair_1", rigid="Head")


def c4_h2():   # side part with swept fringe
    b = c4_new("h2")
    c4_hshell(b, lambda a: 1.652 + 0.07 * _S(a), [(0, .010), (.3, .017), (.62, .024), (.85, .020), (1, .012)], zt=1.815, shift=(-.010, .004))
    # swept fringe over the left brow
    ys = _fy(-.04, 1.735)
    b.block((-.045, ys + .004), 1.700, 1.752, (.105, .036), (.09, .026), "Hair", top_shift=(.01, .008))
    b.block((.045, ys + .002), 1.722, 1.752, (.07, .03), (.06, .02), "Hair")
    return c4_finish(b, "Hair_2", rigid="Head")


def c4_h3():   # long straight
    b = c4_new("h3")
    zb = lambda a: 1.72 - 0.32 * (((1 - _S(a)) / 2) ** 0.8)
    c4_hshell(b, zb, [(0, .016), (.22, .024), (.5, .025), (.8, .019), (1, .008)], zt=1.812, n=12)
    return c4_finish(b, "Hair_3", rigid="Head")


def c4_h4():   # ponytail
    b = c4_new("h4")
    c4_hshell(b, lambda a: 1.655 + 0.06 * _S(a) - (0.03 if _S(a) < 0 else 0), [(0, .010), (.3, .016), (.62, .019), (.85, .015), (1, .008)], zt=1.81)
    c4_tube(b, [(0, -.105, 1.722), (0, -.158, 1.70), (0, -.195, 1.625), (0, -.205, 1.53), (0, -.19, 1.44)], [.032, .042, .040, .032, .014], 6, "Hair")
    c4_tube(b, [(0, -.128, 1.712), (0, -.152, 1.703)], [.046, .046], 6, "Accent")
    return c4_finish(b, "Hair_4", rigid="Head")


def c4_h5():   # curly afro
    b = c4_new("h5")
    zb = lambda a: 1.60 + (0.12 if _S(a) > 0 else 0.06) * _S(a)
    c4_hshell(b, zb, [(0, .030), (.25, .060), (.55, .082), (.8, .066), (1, .030)], zt=1.845, n=12, jit=.014)
    return c4_finish(b, "Hair_5", rigid="Head")


def c4_h6():   # mohawk on a buzzed scalp
    b = c4_new("h6")
    c4_hshell(b, lambda a: 1.665 + 0.065 * _S(a), [(0, .006), (.4, .009), (.8, .008), (1, .004)], zt=1.806)
    prof = [(-.115, 1.70), (-.06, 1.775), (0, 1.803), (.06, 1.79), (.085, 1.762), (.092, 1.80), (.075, 1.842), (.05, 1.885), (.025, 1.845), (0, 1.905),
            (-.03, 1.85), (-.055, 1.9), (-.085, 1.83), (-.118, 1.775)]
    b.profile_extrude(prof, .016, "Hair")
    return c4_finish(b, "Hair_6", rigid="Head")


def c4_b1():   # full beard + moustache
    b = c4_new("b1")
    zb = lambda a: 1.525 + 0.062 * _C(a) ** 2
    c4_hshell(b, zb, [(0, .010), (.35, .015), (.7, .013), (1, .008)], zt=1.628, n=9, arc=(math.radians(-12), math.radians(192)))
    b.box((0, _fy(0, 1.603) + .004, 1.603), (.07, .024, .014), "Hair")
    return c4_finish(b, "Beard_1", rigid="Head")


def c4_b2():   # goatee + moustache
    b = c4_new("b2")
    c4_hshell(b, lambda a: 1.522, [(0, .010), (.4, .017), (.8, .013), (1, .008)], zt=1.598, n=5, arc=(math.radians(52), math.radians(128)))
    b.box((0, _fy(0, 1.603) + .004, 1.606), (.075, .022, .012), "Hair")
    return c4_finish(b, "Beard_2", rigid="Head")


_all = dict(Hair_1=c4_h1, Hair_2=c4_h2, Hair_3=c4_h3, Hair_4=c4_h4, Hair_5=c4_h5, Hair_6=c4_h6, Beard_1=c4_b1, Beard_2=c4_b2)
for _n in globals().get("C4_ONLY", list(_all.keys())):
    _o = _all[_n]()
    print(_n, "tris", c4_tris(_o), "inv", sum(1 for (_f, _v, _e) in c4_islands(_o) if _v < 0), "open_e", sum(_e for (_f, _v, _e) in c4_islands(_o)))
