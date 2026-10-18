"""materials_lib - a tiny node-graph DSL over unreal.MaterialEditingLibrary (used by Tools/ue/materials_*.py).

Design rules
  * Every master material is (re)built by a python function: `new_material()` reuses an existing asset (instances keep their
    parent link and overrides), wipes its expressions and builds the graph again, so the build is idempotent.
  * Graph code reads like maths: `E` handles overload + - * / and `g.lerp`, `g.sat`, ...; heavy shading lives in a few `Custom`
    HLSL nodes (`g.custom`) whose named inputs come from parameter nodes (so everything stays overridable in instances).
  * Textures are sampled with standard TextureSampleParameter2D nodes (correct sampler types / normal unpacking).
Log markers: MAT_*
"""
import os
import sys
import traceback

import unreal

mel = unreal.MaterialEditingLibrary
ea = unreal.EditorAssetLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()
MP = unreal.MaterialProperty

ROOT = unreal.Paths.project_dir().replace("\\", "/")
MAT_ROOT = "/Game/Forza/Materials"
TEX_ROOT = "/Game/Forza/Textures"

_CMOT = {
    "float": unreal.CustomMaterialOutputType.CMOT_FLOAT1,
    "float1": unreal.CustomMaterialOutputType.CMOT_FLOAT1,
    "float2": unreal.CustomMaterialOutputType.CMOT_FLOAT2,
    "float3": unreal.CustomMaterialOutputType.CMOT_FLOAT3,
    "float4": unreal.CustomMaterialOutputType.CMOT_FLOAT4,
}

_SAMPLER = {
    "color": unreal.MaterialSamplerType.SAMPLERTYPE_COLOR,
    "normal": unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL,
    "mask": unreal.MaterialSamplerType.SAMPLERTYPE_MASKS,
    "linear": unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR,
    "alpha": unreal.MaterialSamplerType.SAMPLERTYPE_ALPHA,
}


def log(msg):
    unreal.log("MAT_BUILD " + str(msg))


def warn(msg):
    unreal.log_warning("MAT_BUILD " + str(msg))


def load(path):
    a = ea.load_asset(path)
    if a is None:
        raise RuntimeError("asset not found: " + path)
    return a


def exists(path):
    return ea.does_asset_exist(path)


def ensure_dir(path):
    if not ea.does_directory_exist(path):
        ea.make_directory(path)


def split_path(full):
    d, n = full.rsplit("/", 1)
    return d, n


class E(object):
    """Handle on one output pin of an expression node."""

    __slots__ = ("g", "x", "o")

    def __init__(self, g, x, o=""):
        self.g, self.x, self.o = g, x, o

    def __getitem__(self, out):
        return E(self.g, self.x, out)

    # arithmetic -------------------------------------------------------
    def __add__(self, o):
        return self.g.op("Add", self, o)

    def __radd__(self, o):
        return self.g.op("Add", o, self)

    def __sub__(self, o):
        return self.g.op("Subtract", self, o)

    def __rsub__(self, o):
        return self.g.op("Subtract", o, self)

    def __mul__(self, o):
        return self.g.op("Multiply", self, o)

    def __rmul__(self, o):
        return self.g.op("Multiply", o, self)

    def __truediv__(self, o):
        return self.g.op("Divide", self, o)

    def __rtruediv__(self, o):
        return self.g.op("Divide", o, self)

    def __neg__(self):
        return self.g.op("Multiply", self, -1.0)

    # swizzles ---------------------------------------------------------
    def mask(self, chans):
        return self.g.mask(self, chans)

    @property
    def r(self):
        return self.g.mask(self, "r")

    @property
    def g_(self):
        return self.g.mask(self, "g")

    @property
    def b(self):
        return self.g.mask(self, "b")

    @property
    def a(self):
        return self.g.mask(self, "a")

    @property
    def rgb(self):
        return self.g.mask(self, "rgb")

    @property
    def rg(self):
        return self.g.mask(self, "rg")


class Graph(object):
    def __init__(self, mat):
        self.m = mat
        self._prio = 0
        self._consts = {}
        self._count = 0
        self._depth = {}
        self._rows = {}
        self.params = {}  # name -> kind

    # ------------------------------------------------------------------ nodes
    def _place(self, depth):
        row = self._rows.get(depth, 0)
        self._rows[depth] = row + 1
        return -2600 + depth * 280, row * 150

    def node(self, cls, props=None, ins=None, depth=None):
        """Create expression `cls` (short name like 'Multiply'), set props, connect inputs (dict name -> E|number)."""
        klass = getattr(unreal, "MaterialExpression" + cls)
        d = 0
        in_nodes = []
        if ins:
            for k, v in ins.items():
                if isinstance(v, E):
                    d = max(d, self._depth.get(id(v.x), 0) + 1)
        if depth is not None:
            d = depth
        x, y = self._place(d)
        e = mel.create_material_expression(self.m, klass, x, y)
        self._depth[id(e)] = d
        self._count += 1
        if props:
            for k, v in props.items():
                e.set_editor_property(k, v)
        if ins:
            for k, v in ins.items():
                v = self._coerce(v)
                pin = "" if k == "Input" else k  # single unnamed input pins are addressed with an empty name
                if not mel.connect_material_expressions(v.x, v.o, e, pin):
                    raise RuntimeError("connect failed %s.%s <- %s[%s]" % (cls, k, type(v.x).__name__, v.o))
        return E(self, e)

    def _coerce(self, v):
        if isinstance(v, E):
            return v
        if isinstance(v, bool):
            v = 1.0 if v else 0.0
        if isinstance(v, (int, float)):
            return self.c(float(v))
        if isinstance(v, (tuple, list)):
            if len(v) == 2:
                return self.c2(*v)
            if len(v) == 3:
                return self.c3(*v)
            if len(v) == 4:
                return self.c4(*v)
        raise TypeError("cannot coerce %r to expression" % (v,))

    def c(self, v):
        key = ("c", float(v))
        if key not in self._consts:
            e = self.node("Constant", {"r": float(v)})
            self._consts[key] = e
        return self._consts[key]

    def c2(self, a, b):
        return self.node("Constant2Vector", {"r": float(a), "g": float(b)})

    def c3(self, r, g, b):
        key = ("c3", float(r), float(g), float(b))
        if key not in self._consts:
            self._consts[key] = self.node("Constant3Vector", {"constant": unreal.LinearColor(r, g, b, 1.0)})
        return self._consts[key]

    def c4(self, r, g, b, a):
        return self.node("Constant4Vector", {"constant": unreal.LinearColor(r, g, b, a)})

    def op(self, name, a, b):
        return self.node(name, None, {"A": self._coerce(a), "B": self._coerce(b)})

    def lerp(self, a, b, t):
        return self.node("LinearInterpolate", None, {"A": a, "B": b, "Alpha": t})

    def sat(self, a):
        return self.node("Saturate", None, {"Input": a})

    def oneminus(self, a):
        return self.node("OneMinus", None, {"Input": a})

    def pow(self, a, b):
        return self.node("Power", None, {"Base": a, "Exp": b})

    def clamp(self, a, lo, hi):
        return self.node("Clamp", None, {"Input": a, "Min": lo, "Max": hi})

    def mn(self, a, b):
        return self.op("Min", a, b)

    def mx(self, a, b):
        return self.op("Max", a, b)

    def abs(self, a):
        return self.node("Abs", None, {"Input": a})

    def frac(self, a):
        return self.node("Frac", None, {"Input": a})

    def append(self, a, b):
        return self.node("AppendVector", None, {"A": a, "B": b})

    def mask(self, e, chans):
        props = {"r": "r" in chans, "g": "g" in chans, "b": "b" in chans, "a": "a" in chans}
        return self.node("ComponentMask", props, {"Input": e})

    # ------------------------------------------------------------- parameters
    def _next_prio(self):
        self._prio += 1
        return self._prio

    def scalar(self, name, default, group="", lo=None, hi=None):
        props = {"parameter_name": name, "default_value": float(default), "group": group, "sort_priority": self._next_prio()}
        if lo is not None:
            props["slider_min"] = float(lo)
        if hi is not None:
            props["slider_max"] = float(hi)
        self.params[name] = "scalar"
        return self.node("ScalarParameter", props)

    def vector(self, name, rgba, group=""):
        if len(rgba) == 3:
            rgba = tuple(rgba) + (1.0,)
        props = {"parameter_name": name, "default_value": unreal.LinearColor(*rgba), "group": group, "sort_priority": self._next_prio()}
        self.params[name] = "vector"
        return self.node("VectorParameter", props)

    def switch(self, name, default, true_in, false_in, group=""):
        props = {"parameter_name": name, "default_value": bool(default), "group": group, "sort_priority": self._next_prio()}
        self.params[name] = "switch"
        return self.node("StaticSwitchParameter", props, {"True": true_in, "False": false_in})

    def texture(self, name, tex_path, kind, uv, group="", mip_bias=None):
        """TextureSampleParameter2D; kind = color|normal|mask|linear|alpha; default texture asset path."""
        tex = load(tex_path)
        props = {
            "parameter_name": name,
            "texture": tex,
            "sampler_type": _SAMPLER[kind],
            "group": group,
            "sort_priority": self._next_prio(),
        }
        self.params[name] = "texture"
        e = self.node("TextureSampleParameter2D", props, {"UVs": uv} if uv is not None else None)
        return e

    def mpc(self, collection, pname):
        e = self.node("CollectionParameter", {"collection": collection, "parameter_name": pname})
        return e

    # ----------------------------------------------------------- engine nodes
    def texcoord(self, index=0):
        return self.node("TextureCoordinate", {"coordinate_index": index})

    def world_pos(self):
        return self.node("WorldPosition")

    def vertex_color(self):
        return self.node("VertexColor")

    def vertex_normal(self):
        return self.node("VertexNormalWS")

    def camera_vector(self):
        return self.node("CameraVectorWS")

    def camera_pos(self):
        return self.node("CameraPositionWS")

    def time(self):
        return self.node("Time")

    def custom(self, code, ins, out="float3", extra=None, desc="Custom"):
        """HLSL node. ins: ordered dict name -> E (HLSL variable names = keys). extra: dict outname -> type for additional outputs.
        Returns E for the main output; `E["Name"]` picks an additional output."""
        names = list(ins.keys())
        depth = 0
        for v in ins.values():
            if isinstance(v, E):
                depth = max(depth, self._depth.get(id(v.x), 0) + 1)
        x, y = self._place(depth)
        e = mel.create_material_expression(self.m, unreal.MaterialExpressionCustom, x, y)
        self._depth[id(e)] = depth
        self._count += 1
        cis = []
        for n in names:
            ci = unreal.CustomInput()
            ci.set_editor_property("input_name", n)
            cis.append(ci)
        e.set_editor_property("inputs", cis)
        e.set_editor_property("code", code)
        e.set_editor_property("output_type", _CMOT[out])
        e.set_editor_property("description", desc)
        if extra:
            outs = []
            for n, t in extra.items():
                co = unreal.CustomOutput()
                co.set_editor_property("output_name", n)
                co.set_editor_property("output_type", _CMOT[t])
                outs.append(co)
            e.set_editor_property("additional_outputs", outs)
        for n in names:
            v = self._coerce(ins[n])
            if not mel.connect_material_expressions(v.x, v.o, e, n):
                raise RuntimeError("custom connect failed %s <- %s[%s]" % (n, type(v.x).__name__, v.o))
        return E(self, e)

    # ----------------------------------------------------------------- output
    def out(self, prop, e):
        e = self._coerce(e)
        if not mel.connect_material_property(e.x, e.o, prop):
            raise RuntimeError("connect_material_property failed %s <- %s[%s]" % (prop, type(e.x).__name__, e.o))

    def done(self):
        errs = mel.recompile_material(self.m)
        return [str(x) for x in errs]


# ---------------------------------------------------------------------------- assets
def new_material(path, **props):
    """Create (or reuse + wipe) the Material at `path`; props are Material editor properties."""
    d, n = split_path(path)
    ensure_dir(d)
    if exists(path):
        m = load(path)
        # 5.8.2: delete_all_material_expressions removes only about HALF of the expressions per call (it deletes while iterating; measured 130 -> 64 -> 31 -> ...),
        # so every rebuild used to leave stale orphan nodes (duplicate parameter names!). Repeat until the material is empty.
        left = mel.get_num_material_expressions(m)
        for _ in range(24):
            if left == 0:
                break
            mel.delete_all_material_expressions(m)
            left = mel.get_num_material_expressions(m)
        if left:  # still not empty: rebuild from a fresh asset
            warn("%s: %d expression(s) survived delete_all_material_expressions - recreating the asset" % (path, left))
            ea.delete_asset(path)
            m = at.create_asset(n, d, unreal.Material, unreal.MaterialFactoryNew())
    else:
        m = at.create_asset(n, d, unreal.Material, unreal.MaterialFactoryNew())
    m.set_editor_property("material_domain", unreal.MaterialDomain.MD_SURFACE)
    m.set_editor_property("blend_mode", unreal.BlendMode.BLEND_OPAQUE)
    m.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_DEFAULT_LIT)
    m.set_editor_property("two_sided", False)
    for k, v in props.items():
        m.set_editor_property(k, v)
    return m


def new_instance(path, parent, scalars=None, vectors=None, textures=None, switches=None, base_overrides=None):
    """Create/refresh a MaterialInstanceConstant and set parameter overrides (everything not listed is reset)."""
    d, n = split_path(path)
    ensure_dir(d)
    if exists(path):
        mi = load(path)
    else:
        mi = at.create_asset(n, d, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    mel.set_material_instance_parent(mi, parent)
    mi.set_editor_property("scalar_parameter_values", [])
    mi.set_editor_property("vector_parameter_values", [])
    mi.set_editor_property("texture_parameter_values", [])
    # NOTE: MaterialEditingLibrary.set_material_instance_*_parameter_value always RETURNS False in 5.8.2 although the value is applied
    # (found by the cars agent, engine source MaterialEditingLibrary.cpp): verify by reading the value back instead.
    for k, v in (scalars or {}).items():
        mel.set_material_instance_scalar_parameter_value(mi, k, float(v))
        got = mel.get_material_instance_scalar_parameter_value(mi, k)
        if abs(got - float(v)) > 1e-4:
            warn("%s: scalar param '%s' not applied (read back %s, wanted %s) - missing in parent?" % (n, k, got, v))
    for k, v in (vectors or {}).items():
        if len(v) == 3:
            v = tuple(v) + (1.0,)
        mel.set_material_instance_vector_parameter_value(mi, k, unreal.LinearColor(*v))
        got = mel.get_material_instance_vector_parameter_value(mi, k)
        if abs(got.r - v[0]) > 1e-3 or abs(got.g - v[1]) > 1e-3 or abs(got.b - v[2]) > 1e-3:
            warn("%s: vector param '%s' not applied (read back %s, wanted %s)" % (n, k, got, v))
    for k, v in (textures or {}).items():
        t = v if not isinstance(v, str) else load(v)
        mel.set_material_instance_texture_parameter_value(mi, k, t)
        got = mel.get_material_instance_texture_parameter_value(mi, k)
        if got is None or got.get_path_name() != t.get_path_name():
            warn("%s: texture param '%s' not applied (read back %s)" % (n, k, got))
    for k, v in (switches or {}).items():
        mel.set_material_instance_static_switch_parameter_value(mi, k, bool(v))
        got = mel.get_material_instance_static_switch_parameter_value(mi, k)
        if bool(got) != bool(v):
            warn("%s: switch param '%s' not applied" % (n, k))
    if base_overrides:
        bpo = mi.get_editor_property("base_property_overrides")
        for k, v in base_overrides.items():
            bpo.set_editor_property(k, v)
        mi.set_editor_property("base_property_overrides", bpo)
    mel.update_material_instance(mi)
    return mi


def save(asset):
    ea.save_loaded_asset(asset)


def sub_vec(c):
    return unreal.LinearColor(*c)
