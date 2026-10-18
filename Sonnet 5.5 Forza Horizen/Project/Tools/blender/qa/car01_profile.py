"""
car01_profile.py - read-only inspection of the Pulse body curves (side profile + ring cross sections) as PNG plots.
Does not touch the scene.  Run (in Blender):
    QA_OUT = r"<folder for the PNGs>"
    QA_XS = [-1.9, -1.8, ...]          # stations for the cross-section plot (optional)
    exec(compile(open(r"<project>/Tools/blender/qa/car01_profile.py", encoding="utf8").read(), "qa", "exec"), globals())
"""
import os
import bpy

_PROJECT = os.path.dirname(bpy.data.filepath)
CAR01_STAGE = "none"               # load the car script as a module of functions only (builds nothing)
_p = os.path.join(_PROJECT, "Tools", "blender", "cars", "car01_hatch_pulse.py")
exec(compile(open(_p, encoding="utf8").read(), _p, "exec"), globals())
_sp = os.path.join(_PROJECT, "Tools", "blender", "lib", "sectionplot.py")
exec(compile(open(_sp, encoding="utf8").read(), _sp, "exec"), globals())

_out = globals().get("QA_OUT") or os.path.join(_PROJECT, "Saved")
os.makedirs(_out, exist_ok=True)
cvq = {k: as_curve(v) for k, v in body_curves().items()}
xs_all = [-1.975 + 0.025 * i for i in range(int(3.95 / 0.025) + 1)]


def _side():
    lines = []
    cols = dict(zt=(0.1, 0.1, 0.1), ze=(0.5, 0.2, 0.7), zb=(0.9, 0.1, 0.1), zw=(0.1, 0.5, 0.1), zf=(0.4, 0.4, 0.4), zc=(0.9, 0.5, 0.0),
                zs=(0.2, 0.6, 0.8))
    for k, col in cols.items():
        lines.append(([(x, cvq[k](x)) for x in xs_all], col))
    # wheel circles
    for cx in (XF, XR):
        lines.append(([(cx + 0.33 * math.cos(a * 0.1), 0.33 + 0.33 * math.sin(a * 0.1)) for a in range(64)], (0, 0, 0)))
    return plot_lines(lines, (-2.1, 2.1, 0.0, 1.6), size=(1500, 600), out=os.path.join(_out, "car01_side.png"), grid=0.1)


def _plan():
    lines = []
    for k, col in (('hwm', (0.1, 0.1, 0.1)), ('hwb', (0.9, 0.1, 0.1)), ('hwe', (0.1, 0.5, 0.1)), ('hws', (0.2, 0.6, 0.8))):
        lines.append(([(x, cvq[k](x)) for x in xs_all], col))
    return plot_lines(lines, (-2.1, 2.1, 0.0, 1.0), size=(1500, 400), out=os.path.join(_out, "car01_plan.png"), grid=0.1)


def _rings(xs, name):
    lines = []
    pal = [(0.8, 0.1, 0.1), (0.1, 0.5, 0.1), (0.1, 0.1, 0.8), (0.7, 0.4, 0.0), (0.5, 0.1, 0.6), (0.0, 0.6, 0.6), (0.3, 0.3, 0.3),
           (0.9, 0.2, 0.6)]
    for i, x in enumerate(xs):
        ctrl = ring_controls(cvq, x)
        half = catmull_chain([c[1] for c in ctrl], [4] * (len(ctrl) - 1))
        pts = [(-p[0], p[1]) for p in reversed(half)] + [(p[0], p[1]) for p in half]
        lines.append((pts, pal[i % len(pal)]))
    return plot_lines(lines, (-1.0, 1.0, 0.1, 1.5), size=(1000, 800), out=os.path.join(_out, name), grid=0.1)


_side()
_plan()
_rings(globals().get("QA_XS") or [-1.9, -1.8, -1.7, -1.6, -1.5, -1.3], "car01_rings_rear.png")
_rings(globals().get("QA_XF") or [0.3, 0.6, 0.9, 1.2, 1.5, 1.8], "car01_rings_front.png")
print("plots written to", _out)
