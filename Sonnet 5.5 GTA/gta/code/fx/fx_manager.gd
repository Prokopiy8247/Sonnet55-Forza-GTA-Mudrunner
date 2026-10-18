class_name FxManager
extends Node3D
## Pooled cosmetic effects for combat: bullet tracers, ejected shells, surface impacts (dust, chips, sparks, shards,
## splashes, blood puffs), bullet-hole / crack / scorch / blood decals, explosion fireballs, smoke trails, light flashes.
## Everything is created once (pre-warmed) and reused: no node allocation while firing.
## Owned by CombatSystem (Game.sys(&"combat").fx). Safe to use from any module via CombatSystem.get_fx().

const MAX_TRACERS := 40
const MAX_SHELLS := 24
const N_BULLET_DECALS := 40
const N_GLASS_DECALS := 12
const N_BLOOD_DECALS := 12
const N_SCORCH_DECALS := 10

enum Anim { CORE, SHOCK, LIGHT, RING }

## Surface table: fx = particle kinds spawned, decal = decal kind, sfx = sound id, sparks etc.
const SURFACES := {
	&"concrete": {"fx": ["dust_concrete", "chip_concrete"], "decal": "hole", "sfx": &"hit_concrete"},
	&"wood": {"fx": ["dust_wood", "chip_wood"], "decal": "hole", "sfx": &"hit_concrete"},
	&"metal": {"fx": ["spark_metal", "dust_metal"], "decal": "hole_small", "sfx": &"hit_metal"},
	&"glass": {"fx": ["glass_shard"], "decal": "glass", "sfx": &"hit_glass"},
	&"dirt": {"fx": ["dirt_puff", "chip_dirt"], "decal": "", "sfx": &"hit_dirt"},
	&"sand": {"fx": ["sand_puff"], "decal": "", "sfx": &"hit_dirt"},
	&"grass": {"fx": ["grass_puff", "chip_dirt"], "decal": "", "sfx": &"hit_dirt"},
	&"water": {"fx": ["water_splash"], "decal": "", "sfx": &"hit_water"},
	&"flesh": {"fx": ["blood_puff"], "decal": "", "sfx": &"hit_flesh"},
}
const SURFACE_ALIAS := {
	&"asphalt": &"concrete", &"road": &"concrete", &"brick": &"concrete", &"stone": &"concrete", &"plaster": &"concrete",
	&"rock": &"concrete", &"tile": &"concrete", &"sidewalk": &"concrete", &"pavement": &"concrete", &"cement": &"concrete",
	&"steel": &"metal", &"vehicle": &"metal", &"car": &"metal", &"iron": &"metal", &"paint": &"metal",
	&"planks": &"wood", &"plank": &"wood", &"fence": &"wood",
	&"mud": &"dirt", &"soil": &"dirt", &"gravel": &"dirt", &"foliage": &"grass", &"leaves": &"grass", &"bush": &"grass",
	&"skin": &"flesh", &"body": &"flesh", &"character": &"flesh", &"ocean": &"water", &"sea": &"water",
	&"window": &"glass", &"windshield": &"glass",
}

# --------------------------------------------------------------------------------------------- presets
# amount, life, vmin, vmax, spread(deg), gravity(y), smin, smax, mesh(quad|box), mat(smoke|spark|chip|glow), ramp[[t,Color]...], curve
var _presets: Dictionary = {}
var _pools: Dictionary = {}               # kind -> {"nodes": Array, "next": int}

# tracers (parallel arrays, no per-shot allocation)
var _tr_node: Array[MeshInstance3D] = []
var _tr_from: PackedVector3Array = PackedVector3Array()
var _tr_dir: PackedVector3Array = PackedVector3Array()
var _tr_dist: PackedFloat32Array = PackedFloat32Array()
var _tr_prog: PackedFloat32Array = PackedFloat32Array()
var _tr_speed: PackedFloat32Array = PackedFloat32Array()
var _tr_len: PackedFloat32Array = PackedFloat32Array()
var _tr_width: PackedFloat32Array = PackedFloat32Array()
var _tr_on: PackedByteArray = PackedByteArray()
var _tr_next := 0
var _tr_active := 0

# shells
var _sh_node: Array[MeshInstance3D] = []
var _sh_vel: PackedVector3Array = PackedVector3Array()
var _sh_age: PackedFloat32Array = PackedFloat32Array()
var _sh_ground: PackedFloat32Array = PackedFloat32Array()
var _sh_bounces: PackedInt32Array = PackedInt32Array()
var _sh_spin: PackedVector3Array = PackedVector3Array()
var _sh_on: PackedByteArray = PackedByteArray()
var _sh_next := 0
var _sh_active := 0
var _shell_meshes: Dictionary = {}
var _shell_mats: Dictionary = {}

# decals
var _decals: Dictionary = {}              # kind -> {"nodes": Array[Decal], "next": int}

# timed anims (explosion core / shockwave / light / water ring)
class AnimItem:
	extends RefCounted
	var node: Node3D = null
	var kind: int = 0
	var t: float = 0.0
	var dur: float = 1.0
	var r: float = 1.0
	var c0: Color = Color.WHITE
	var c1: Color = Color.WHITE
	var e0: float = 1.0
	var mat: StandardMaterial3D = null
	var light: OmniLight3D = null

var _anim_free: Dictionary = {}           # kind -> Array[AnimItem]
var _anim_active: Array[AnimItem] = []

var _ready_done := false
var impacts_enabled := true
var _sfx_cool: Dictionary = {}            # sound id -> last time (limits impact sound spam)
var _clock := 0.0


func _ready() -> void:
	name = "Fx"
	set_process(false)
	_build_presets()
	FxRes.warm_up()
	_prewarm()
	_ready_done = true


func _prewarm() -> void:
	for i in MAX_TRACERS:
		var m := MeshInstance3D.new()
		m.mesh = FxRes.box()
		m.material_override = FxRes.tracer_mat()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_tr_node.append(m)
	_tr_from.resize(MAX_TRACERS)
	_tr_dir.resize(MAX_TRACERS)
	_tr_dist.resize(MAX_TRACERS)
	_tr_prog.resize(MAX_TRACERS)
	_tr_speed.resize(MAX_TRACERS)
	_tr_len.resize(MAX_TRACERS)
	_tr_width.resize(MAX_TRACERS)
	_tr_on.resize(MAX_TRACERS)
	_build_shell_assets()
	for i in MAX_SHELLS:
		var m := MeshInstance3D.new()
		m.mesh = _shell_meshes[&"pistol"]
		m.material_override = _shell_mats[&"brass"]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_sh_node.append(m)
	_sh_vel.resize(MAX_SHELLS)
	_sh_age.resize(MAX_SHELLS)
	_sh_ground.resize(MAX_SHELLS)
	_sh_bounces.resize(MAX_SHELLS)
	_sh_spin.resize(MAX_SHELLS)
	_sh_on.resize(MAX_SHELLS)
	for kind in _presets:
		_make_pool(kind, int(_presets[kind].get("pool", 4)))
	_make_decals("hole", N_BULLET_DECALS)
	_make_decals("glass", N_GLASS_DECALS)
	_make_decals("blood", N_BLOOD_DECALS)
	_make_decals("scorch", N_SCORCH_DECALS)
	for k in [Anim.CORE, Anim.SHOCK, Anim.LIGHT, Anim.RING]:
		for i in 3:
			_anim_free_push(_make_anim(k))


# =========================================================================================== presets
func _grad(stops: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(float(s[0]))
		cols.append(s[1] as Color)
	g.offsets = offs
	g.colors = cols
	return g


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points:
		c.add_point(Vector2(float(p[0]), float(p[1])))
	return c


func _build_presets() -> void:
	var c_grow := _curve([[0.0, 0.35], [0.5, 0.9], [1.0, 1.0]])
	var c_shrink := _curve([[0.0, 1.0], [1.0, 0.0]])
	var c_puff := _curve([[0.0, 0.25], [0.35, 0.85], [1.0, 1.0]])
	_presets = {
		"spark_metal": {"amount": 11, "life": 0.34, "vmin": 4.0, "vmax": 10.0, "spread": 58.0, "g": -14.0, "smin": 0.6, "smax": 1.3,
			"mesh": "streak", "mat": "streak", "pool": 8, "curve": c_shrink, "expl": 1.0,
			"ramp": _grad([[0.0, Color(1.0, 0.97, 0.75, 1.0)], [0.4, Color(1.0, 0.65, 0.2, 0.95)], [1.0, Color(1.0, 0.3, 0.05, 0.0)]])},
		"dust_metal": {"amount": 3, "life": 0.45, "vmin": 0.3, "vmax": 1.0, "spread": 50.0, "g": 0.2, "smin": 0.1, "smax": 0.18,
			"mesh": "quad", "mat": "smoke", "pool": 6, "curve": c_puff, "expl": 1.0,
			"ramp": _grad([[0.0, Color(0.85, 0.85, 0.88, 0.45)], [1.0, Color(0.7, 0.7, 0.72, 0.0)]])},
		"dust_concrete": {"amount": 7, "life": 0.8, "vmin": 0.6, "vmax": 2.0, "spread": 55.0, "g": 0.35, "smin": 0.2, "smax": 0.38,
			"mesh": "quad", "mat": "smoke", "pool": 10, "curve": c_puff, "expl": 0.9,
			"ramp": _grad([[0.0, Color(0.82, 0.78, 0.72, 0.8)], [1.0, Color(0.75, 0.72, 0.68, 0.0)]])},
		"chip_concrete": {"amount": 7, "life": 0.6, "vmin": 2.0, "vmax": 5.5, "spread": 60.0, "g": -11.0, "smin": 0.02, "smax": 0.05,
			"mesh": "box", "mat": "chip", "pool": 8, "curve": null, "expl": 1.0,
			"ramp": _grad([[0.0, Color(0.72, 0.70, 0.66, 1.0)], [0.85, Color(0.6, 0.58, 0.55, 1.0)], [1.0, Color(0.6, 0.58, 0.55, 0.0)]])},
		"dust_wood": {"amount": 4, "life": 0.6, "vmin": 0.4, "vmax": 1.4, "spread": 55.0, "g": 0.3, "smin": 0.09, "smax": 0.16,
			"mesh": "quad", "mat": "smoke", "pool": 4, "curve": c_puff, "expl": 0.9,
			"ramp": _grad([[0.0, Color(0.72, 0.55, 0.36, 0.55)], [1.0, Color(0.65, 0.5, 0.33, 0.0)]])},
		"chip_wood": {"amount": 7, "life": 0.6, "vmin": 1.8, "vmax": 5.0, "spread": 65.0, "g": -10.0, "smin": 0.012, "smax": 0.035,
			"mesh": "box", "mat": "chip", "pool": 4, "curve": null, "expl": 1.0,
			"ramp": _grad([[0.0, Color(0.62, 0.43, 0.25, 1.0)], [0.85, Color(0.5, 0.34, 0.2, 1.0)], [1.0, Color(0.5, 0.34, 0.2, 0.0)]])},
		"glass_shard": {"amount": 14, "life": 0.85, "vmin": 1.5, "vmax": 5.0, "spread": 75.0, "g": -9.8, "smin": 0.012, "smax": 0.035,
			"mesh": "box", "mat": "glow", "pool": 8, "curve": null, "expl": 1.0,
			"ramp": _grad([[0.0, Color(0.85, 0.95, 1.0, 1.0)], [0.7, Color(0.7, 0.88, 0.98, 0.9)], [1.0, Color(0.7, 0.88, 0.98, 0.0)]])},
		"dirt_puff": {"amount": 7, "life": 0.85, "vmin": 0.6, "vmax": 2.0, "spread": 55.0, "g": 0.3, "smin": 0.13, "smax": 0.26,
			"mesh": "quad", "mat": "smoke", "pool": 6, "curve": c_puff, "expl": 0.9,
			"ramp": _grad([[0.0, Color(0.55, 0.42, 0.3, 0.6)], [1.0, Color(0.5, 0.4, 0.3, 0.0)]])},
		"sand_puff": {"amount": 8, "life": 0.9, "vmin": 0.6, "vmax": 2.0, "spread": 55.0, "g": 0.3, "smin": 0.13, "smax": 0.26,
			"mesh": "quad", "mat": "smoke", "pool": 4, "curve": c_puff, "expl": 0.9,
			"ramp": _grad([[0.0, Color(0.93, 0.82, 0.58, 0.6)], [1.0, Color(0.9, 0.8, 0.58, 0.0)]])},
		"grass_puff": {"amount": 6, "life": 0.8, "vmin": 0.6, "vmax": 1.8, "spread": 55.0, "g": 0.3, "smin": 0.12, "smax": 0.22,
			"mesh": "quad", "mat": "smoke", "pool": 4, "curve": c_puff, "expl": 0.9,
			"ramp": _grad([[0.0, Color(0.5, 0.58, 0.3, 0.55)], [1.0, Color(0.45, 0.55, 0.28, 0.0)]])},
		"chip_dirt": {"amount": 6, "life": 0.6, "vmin": 1.5, "vmax": 4.0, "spread": 60.0, "g": -10.0, "smin": 0.015, "smax": 0.035,
			"mesh": "box", "mat": "chip", "pool": 6, "curve": null, "expl": 1.0,
			"ramp": _grad([[0.0, Color(0.42, 0.3, 0.2, 1.0)], [0.85, Color(0.35, 0.26, 0.18, 1.0)], [1.0, Color(0.35, 0.26, 0.18, 0.0)]])},
		"water_splash": {"amount": 16, "life": 0.75, "vmin": 2.0, "vmax": 5.0, "spread": 28.0, "g": -10.0, "smin": 0.05, "smax": 0.1,
			"mesh": "quad", "mat": "smoke", "pool": 6, "curve": c_shrink, "expl": 0.98,
			"ramp": _grad([[0.0, Color(0.92, 0.97, 1.0, 0.95)], [0.7, Color(0.75, 0.9, 1.0, 0.7)], [1.0, Color(0.7, 0.88, 1.0, 0.0)]])},
		"blood_puff": {"amount": 9, "life": 0.5, "vmin": 0.8, "vmax": 2.8, "spread": 62.0, "g": -7.0, "smin": 0.05, "smax": 0.1,
			"mesh": "quad", "mat": "smoke", "pool": 8, "curve": c_shrink, "expl": 1.0,
			"ramp": _grad([[0.0, Color(0.78, 0.06, 0.08, 0.95)], [0.6, Color(0.55, 0.03, 0.05, 0.8)], [1.0, Color(0.4, 0.02, 0.04, 0.0)]])},
		"smoke_puff": {"amount": 4, "life": 1.1, "vmin": 0.1, "vmax": 0.5, "spread": 30.0, "g": 0.4, "smin": 0.06, "smax": 0.12,
			"mesh": "quad", "mat": "smoke", "pool": 8, "curve": c_puff, "expl": 0.8,
			"ramp": _grad([[0.0, Color(0.85, 0.85, 0.85, 0.35)], [1.0, Color(0.7, 0.7, 0.7, 0.0)]])},
		"expl_fire": {"amount": 40, "life": 1.0, "vmin": 2.0, "vmax": 7.5, "spread": 180.0, "g": 1.6, "smin": 1.3, "smax": 2.6,
			"mesh": "quad", "mat": "smoke", "pool": 3, "curve": c_puff, "expl": 0.9, "shape_r": 0.45, "damp": 1.4,
			"ramp": _grad([[0.0, Color(1.0, 0.93, 0.55, 1.0)], [0.2, Color(1.0, 0.58, 0.14, 0.97)], [0.55, Color(0.62, 0.24, 0.09, 0.8)], [1.0, Color(0.18, 0.12, 0.1, 0.0)]])},
		"expl_glow": {"amount": 8, "life": 0.4, "vmin": 0.5, "vmax": 2.5, "spread": 180.0, "g": 0.0, "smin": 3.2, "smax": 4.6,
			"mesh": "quad", "mat": "spark", "pool": 3, "curve": c_shrink, "expl": 1.0, "shape_r": 0.3,
			"ramp": _grad([[0.0, Color(1.0, 0.9, 0.55, 0.75)], [1.0, Color(1.0, 0.5, 0.1, 0.0)]])},
		"expl_smoke": {"amount": 28, "life": 3.6, "vmin": 0.8, "vmax": 3.6, "spread": 90.0, "g": 1.5, "smin": 1.5, "smax": 3.0,
			"mesh": "quad", "mat": "smoke", "pool": 3, "curve": c_puff, "expl": 0.6, "shape_r": 0.4, "damp": 1.2,
			"ramp": _grad([[0.0, Color(0.32, 0.3, 0.28, 0.0)], [0.12, Color(0.28, 0.26, 0.25, 0.8)], [0.6, Color(0.2, 0.19, 0.19, 0.55)], [1.0, Color(0.15, 0.15, 0.16, 0.0)]])},
		"expl_debris": {"amount": 20, "life": 1.5, "vmin": 5.0, "vmax": 15.0, "spread": 75.0, "g": -16.0, "smin": 0.05, "smax": 0.14,
			"mesh": "box", "mat": "chip", "pool": 3, "curve": null, "expl": 1.0, "shape_r": 0.25,
			"ramp": _grad([[0.0, Color(0.16, 0.15, 0.15, 1.0)], [0.5, Color(0.28, 0.25, 0.22, 1.0)], [1.0, Color(0.28, 0.25, 0.22, 0.0)]])},
		"expl_sparks": {"amount": 36, "life": 0.9, "vmin": 6.0, "vmax": 19.0, "spread": 100.0, "g": -12.0, "smin": 1.0, "smax": 2.2,
			"mesh": "streak", "mat": "streak", "pool": 3, "curve": c_shrink, "expl": 1.0, "shape_r": 0.2,
			"ramp": _grad([[0.0, Color(1.0, 0.95, 0.7, 1.0)], [0.4, Color(1.0, 0.55, 0.12, 1.0)], [1.0, Color(1.0, 0.25, 0.05, 0.0)]])},
		"dust_ring": {"amount": 18, "life": 1.3, "vmin": 2.5, "vmax": 6.0, "spread": 12.0, "g": 0.2, "smin": 0.7, "smax": 1.3,
			"mesh": "quad", "mat": "smoke", "pool": 3, "curve": c_puff, "expl": 0.95, "shape_r": 0.6, "damp": 3.0, "flat": true,
			"ramp": _grad([[0.0, Color(0.72, 0.68, 0.62, 0.55)], [1.0, Color(0.7, 0.66, 0.6, 0.0)]])},
		"trail_smoke": {"amount": 48, "life": 1.6, "vmin": 0.05, "vmax": 0.4, "spread": 25.0, "g": 0.25, "smin": 0.5, "smax": 1.0,
			"mesh": "quad", "mat": "smoke", "pool": 4, "curve": c_puff, "expl": 0.0, "continuous": true,
			"ramp": _grad([[0.0, Color(0.95, 0.93, 0.9, 0.85)], [0.35, Color(0.7, 0.68, 0.66, 0.6)], [1.0, Color(0.45, 0.45, 0.45, 0.0)]])},
		"trail_fire": {"amount": 16, "life": 0.22, "vmin": 0.2, "vmax": 1.0, "spread": 12.0, "g": 0.0, "smin": 0.35, "smax": 0.6,
			"mesh": "quad", "mat": "spark", "pool": 4, "curve": c_shrink, "expl": 0.0, "continuous": true,
			"ramp": _grad([[0.0, Color(1.0, 0.95, 0.7, 1.0)], [0.5, Color(1.0, 0.55, 0.12, 0.9)], [1.0, Color(0.8, 0.2, 0.05, 0.0)]])},
		"fire_flame": {"amount": 18, "life": 0.8, "vmin": 0.6, "vmax": 2.0, "spread": 18.0, "g": 2.5, "smin": 0.35, "smax": 0.7,
			"mesh": "quad", "mat": "spark", "pool": 6, "curve": c_shrink, "expl": 0.0, "continuous": true, "shape_r": 0.5,
			"ramp": _grad([[0.0, Color(1.0, 0.9, 0.5, 0.95)], [0.4, Color(1.0, 0.45, 0.1, 0.8)], [1.0, Color(0.5, 0.12, 0.05, 0.0)]])},
		"fire_smoke": {"amount": 12, "life": 2.0, "vmin": 0.8, "vmax": 1.8, "spread": 15.0, "g": 1.2, "smin": 0.4, "smax": 0.9,
			"mesh": "quad", "mat": "smoke", "pool": 6, "curve": c_puff, "expl": 0.0, "continuous": true, "shape_r": 0.4,
			"ramp": _grad([[0.0, Color(0.2, 0.19, 0.18, 0.0)], [0.2, Color(0.2, 0.19, 0.18, 0.55)], [1.0, Color(0.12, 0.12, 0.12, 0.0)]])},
	}


func _make_pool(kind: String, count: int) -> void:
	var nodes: Array = []
	for i in count:
		nodes.append(_make_particles(kind))
	_pools[kind] = {"nodes": nodes, "next": 0}


func _make_particles(kind: String) -> CPUParticles3D:
	var pr: Dictionary = _presets[kind]
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = not bool(pr.get("continuous", false))
	p.amount = int(pr["amount"])
	p.lifetime = float(pr["life"])
	p.explosiveness = float(pr.get("expl", 0.9))
	p.randomness = 1.0
	p.lifetime_randomness = 0.3
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = Vector3.UP
	p.spread = float(pr["spread"])
	p.initial_velocity_min = float(pr["vmin"])
	p.initial_velocity_max = float(pr["vmax"])
	p.gravity = Vector3(0.0, float(pr["g"]), 0.0)
	p.scale_amount_min = float(pr["smin"])
	p.scale_amount_max = float(pr["smax"])
	if pr.get("curve", null) != null:
		p.scale_amount_curve = pr["curve"]
	p.color_ramp = pr["ramp"]
	if pr.has("damp"):
		p.damping_min = float(pr["damp"]) * 0.7
		p.damping_max = float(pr["damp"])
	if pr.has("shape_r"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = float(pr["shape_r"])
	if pr.get("flat", false):
		p.direction = Vector3.UP
	var mesh_kind: String = pr["mesh"]
	if mesh_kind == "quad":
		p.mesh = FxRes.quad()
	elif mesh_kind == "streak":
		p.mesh = FxRes.streak_mesh()
		p.particle_flag_align_y = true
	else:
		p.mesh = FxRes.box()
	match String(pr["mat"]):
		"smoke":
			p.material_override = FxRes.smoke_mat()
		"spark":
			p.material_override = FxRes.spark_mat()
		"glow":
			p.material_override = FxRes.glow_chip_mat()
		"streak":
			p.material_override = FxRes.streak_mat()
		_:
			p.material_override = FxRes.chip_mat()
	if mesh_kind == "box":
		p.angle_min = -180.0
		p.angle_max = 180.0
	elif mesh_kind == "quad":
		p.angle_min = 0.0
		p.angle_max = 360.0
	p.top_level = true
	add_child(p)
	return p


func _make_decals(kind: String, count: int) -> void:
	var nodes: Array = []
	for i in count:
		var d := Decal.new()
		d.visible = false
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.normal_fade = 0.15
		d.distance_fade_enabled = true
		d.distance_fade_begin = 30.0
		d.distance_fade_length = 15.0
		match kind:
			"hole":
				d.texture_albedo = FxRes.hole_tex()
				d.size = Vector3(0.1, 0.12, 0.1)
			"glass":
				d.texture_albedo = FxRes.glass_tex()
				d.size = Vector3(0.45, 0.12, 0.45)
			"blood":
				d.texture_albedo = FxRes.blood_tex()
				d.size = Vector3(0.4, 0.12, 0.4)
			"scorch":
				d.texture_albedo = FxRes.scorch_tex()
				d.size = Vector3(4.0, 0.6, 4.0)
				d.distance_fade_begin = 90.0
				d.distance_fade_length = 40.0
		add_child(d)
		nodes.append(d)
	_decals[kind] = {"nodes": nodes, "next": 0}


# =========================================================================================== particles
func _emit(kind: String, pos: Vector3, dir: Vector3 = Vector3.UP, k: float = 1.0, color_mul: Color = Color.WHITE) -> CPUParticles3D:
	if not _pools.has(kind):
		return null
	var pool: Dictionary = _pools[kind]
	var nodes: Array = pool["nodes"]
	var i: int = pool["next"]
	pool["next"] = (i + 1) % nodes.size()
	var p: CPUParticles3D = nodes[i]
	if not is_instance_valid(p):
		p = _make_particles(kind)
		nodes[i] = p
	var pr: Dictionary = _presets[kind]
	p.global_transform = Transform3D(_basis_from_y(dir), pos)
	if k != 1.0:
		p.initial_velocity_min = float(pr["vmin"]) * k
		p.initial_velocity_max = float(pr["vmax"]) * k
		p.scale_amount_min = float(pr["smin"]) * k
		p.scale_amount_max = float(pr["smax"]) * k
		if pr.has("shape_r"):
			p.emission_sphere_radius = float(pr["shape_r"]) * k
	elif p.initial_velocity_max != float(pr["vmax"]) or p.scale_amount_max != float(pr["smax"]):
		p.initial_velocity_min = float(pr["vmin"])
		p.initial_velocity_max = float(pr["vmax"])
		p.scale_amount_min = float(pr["smin"])
		p.scale_amount_max = float(pr["smax"])
		if pr.has("shape_r"):
			p.emission_sphere_radius = float(pr["shape_r"])
	p.color = color_mul
	p.restart()
	p.emitting = true
	return p


## Continuous emitter (rocket smoke, fire). Caller keeps the node and calls release_emitter() when done.
func acquire_emitter(kind: String) -> CPUParticles3D:
	if not _pools.has(kind):
		return null
	var pool: Dictionary = _pools[kind]
	var nodes: Array = pool["nodes"]
	for i in nodes.size():
		var p: CPUParticles3D = nodes[i]
		if is_instance_valid(p) and not p.emitting and not p.has_meta(&"in_use"):
			p.set_meta(&"in_use", true)
			return p
	var p2 := _make_particles(kind)
	p2.set_meta(&"in_use", true)
	nodes.append(p2)
	return p2


func release_emitter(p: CPUParticles3D) -> void:
	if not is_instance_valid(p):
		return
	p.emitting = false
	p.set_meta(&"in_use", false)
	p.remove_meta(&"in_use")


static func _basis_from_y(y: Vector3) -> Basis:
	var up := y.normalized() if y.length_squared() > 0.0001 else Vector3.UP
	var tmp := Vector3.RIGHT if absf(up.y) > 0.98 else Vector3.UP
	var x := tmp.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)


# =========================================================================================== impacts
func normalize_surface(surface: StringName) -> StringName:
	if SURFACES.has(surface):
		return surface
	if SURFACE_ALIAS.has(surface):
		return SURFACE_ALIAS[surface]
	return &"concrete"


## Surface impact: particles + decal + sound. strength 0.5..2 scales the burst. `static_hit` allows decals.
func impact(pos: Vector3, normal: Vector3, surface: StringName, strength: float = 1.0, static_hit: bool = true, play_sound: bool = true) -> void:
	if not impacts_enabled or not _ready_done:
		return
	var s := normalize_surface(surface)
	var def: Dictionary = SURFACES[s]
	var n := normal if normal.length_squared() > 0.01 else Vector3.UP
	var base := pos + n * 0.02
	for kind in def["fx"]:
		_emit(String(kind), base, n, clampf(strength, 0.5, 2.0))
	if s == &"water":
		ring(pos, 0.9 * strength, Color(0.85, 0.95, 1.0, 0.8), 0.55)
	if static_hit:
		var dk: String = def["decal"]
		if dk == "hole" or dk == "hole_small":
			place_decal("hole", pos, n, 0.075 + 0.04 * randf() if dk == "hole_small" else 0.1 + 0.05 * randf())
		elif dk == "glass":
			place_decal("glass", pos, n, 0.3 + 0.2 * randf())
	if play_sound:
		_play_impact_sound(def["sfx"], pos)


func _play_impact_sound(sound: StringName, pos: Vector3) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var last: float = _sfx_cool.get(sound, -10.0)
	if t - last < 0.045:
		return
	_sfx_cool[sound] = t
	Sfx.play_3d(sound, pos, -4.0, randf_range(0.92, 1.08), 60.0)


func blood(pos: Vector3, dir: Vector3, amount: float = 1.0) -> void:
	_emit("blood_puff", pos, -dir if dir.length_squared() > 0.01 else Vector3.UP, clampf(amount, 0.5, 2.0))


func smoke_puff(pos: Vector3, dir: Vector3 = Vector3.UP, k: float = 1.0) -> void:
	_emit("smoke_puff", pos, dir, k)


func debris_burst(pos: Vector3, normal: Vector3, kind: String = "chip_concrete", k: float = 1.0) -> void:
	_emit(kind, pos, normal, k)


## Flat expanding ring on a surface (water ripples, shockwaves).
func ring(pos: Vector3, radius: float, color: Color, dur: float = 0.5) -> void:
	var a := _anim_acquire(Anim.RING)
	a.t = 0.0
	a.dur = dur
	a.r = radius
	a.c0 = color
	a.node.global_position = pos + Vector3(0, 0.04, 0)
	a.node.scale = Vector3.ONE * 0.1
	a.node.visible = true
	a.mat.albedo_color = color
	_anim_active.append(a)
	set_process(true)


func place_decal(kind: String, pos: Vector3, normal: Vector3, size: float = 0.1) -> Decal:
	if not _decals.has(kind):
		return null
	var pool: Dictionary = _decals[kind]
	var nodes: Array = pool["nodes"]
	var i: int = pool["next"]
	pool["next"] = (i + 1) % nodes.size()
	var d: Decal = nodes[i]
	if not is_instance_valid(d):
		return null
	var b := _basis_from_y(normal).rotated(normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP, randf() * TAU)
	d.global_transform = Transform3D(b, pos)
	var thick := 0.14 if kind != "scorch" else 0.8
	d.size = Vector3(size, thick, size)
	d.visible = true
	return d


## Scorch mark under an explosion; finds the ground within `drop` metres below pos.
func scorch(pos: Vector3, radius: float) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.0, 0), pos + Vector3(0, -4.0, 0), GC.L_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var d := place_decal("scorch", hit["position"], hit["normal"], radius * 1.35)
	if d != null:
		d.modulate = Color(1, 1, 1, 0.85)


# =========================================================================================== tracers
func tracer(from: Vector3, to: Vector3, color: Color = Color(1.0, 0.85, 0.5, 1.0), width: float = 0.022, speed: float = 380.0, length: float = 4.5) -> void:
	if not _ready_done:
		return
	var dist := from.distance_to(to)
	if dist < 2.5:
		return
	var i := _tr_next
	_tr_next = (_tr_next + 1) % MAX_TRACERS
	if _tr_on[i] == 0:
		_tr_active += 1
	_tr_on[i] = 1
	_tr_from[i] = from
	_tr_dir[i] = (to - from) / dist
	_tr_dist[i] = dist
	_tr_prog[i] = 0.0
	_tr_speed[i] = speed
	_tr_len[i] = minf(length, dist)
	_tr_width[i] = width
	var m := _tr_node[i]
	m.set_instance_shader_parameter("col", color)
	m.visible = true
	set_process(true)


# =========================================================================================== shells
func _build_shell_assets() -> void:
	var small := BoxMesh.new()
	small.size = Vector3(0.011, 0.011, 0.03)
	var rifle := BoxMesh.new()
	rifle.size = Vector3(0.013, 0.013, 0.05)
	var shot := CylinderMesh.new()
	shot.top_radius = 0.01
	shot.bottom_radius = 0.01
	shot.height = 0.045
	shot.radial_segments = 6
	shot.rings = 1
	_shell_meshes = {&"pistol": small, &"revolver": small, &"rifle": rifle, &"sniper": rifle, &"shotgun": shot}
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.66, 0.26)
	brass.metallic = 0.7
	brass.roughness = 0.35
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.78, 0.15, 0.12)
	red.roughness = 0.6
	_shell_mats = {&"brass": brass, &"red": red}


## Ejects a casing. `vel` is the world-space initial velocity; ground_y the floor height to bounce on.
func eject_shell(pos: Vector3, vel: Vector3, kind: StringName, ground_y: float) -> void:
	if not _ready_done or not _shell_meshes.has(kind):
		return
	var i := _sh_next
	_sh_next = (_sh_next + 1) % MAX_SHELLS
	if _sh_on[i] == 0:
		_sh_active += 1
	_sh_on[i] = 1
	_sh_vel[i] = vel
	_sh_age[i] = 0.0
	_sh_ground[i] = ground_y + 0.015
	_sh_bounces[i] = 0
	_sh_spin[i] = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
	var m := _sh_node[i]
	m.mesh = _shell_meshes[kind]
	m.material_override = _shell_mats[&"red"] if kind == &"shotgun" else _shell_mats[&"brass"]
	m.global_position = pos
	m.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	m.visible = true
	set_process(true)


# =========================================================================================== explosions
func _make_anim(kind: int) -> AnimItem:
	var a := AnimItem.new()
	a.kind = kind
	match kind:
		Anim.CORE, Anim.SHOCK:
			var m := MeshInstance3D.new()
			m.mesh = FxRes.facet_sphere()
			a.mat = FxRes.fire_core_mat() if kind == Anim.CORE else FxRes.fire_shell_mat()
			m.material_override = a.mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.visible = false
			m.top_level = true
			add_child(m)
			a.node = m
		Anim.RING:
			var m2 := MeshInstance3D.new()
			m2.mesh = FxRes.ground_quad()
			a.mat = FxRes.ring_mat()
			m2.material_override = a.mat
			m2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m2.visible = false
			m2.top_level = true
			add_child(m2)
			a.node = m2
		Anim.LIGHT:
			var l := OmniLight3D.new()
			l.shadow_enabled = false
			l.visible = false
			l.top_level = true
			l.light_color = Color(1.0, 0.7, 0.35)
			add_child(l)
			a.node = l
			a.light = l
	return a


func _anim_free_push(a: AnimItem) -> void:
	if not _anim_free.has(a.kind):
		_anim_free[a.kind] = []
	(_anim_free[a.kind] as Array).append(a)


func _anim_acquire(kind: int) -> AnimItem:
	var arr: Array = _anim_free.get(kind, [])
	if arr.is_empty():
		# recycle the oldest active one of this kind
		for a in _anim_active:
			if a.kind == kind:
				_anim_active.erase(a)
				return a
		return _make_anim(kind)
	return arr.pop_back()


func _anim_release(a: AnimItem) -> void:
	a.node.visible = false
	if a.kind == Anim.LIGHT and a.light != null:
		a.light.light_energy = 0.0
	_anim_free_push(a)


## Full explosion visuals (no damage). `radius` is the blast radius in metres.
func explosion(pos: Vector3, radius: float, opts: Dictionary = {}) -> void:
	if not _ready_done:
		return
	var k := clampf(radius / 7.0, 0.3, 1.9)
	var big := radius >= 5.5
	var up := Vector3.UP
	_emit("expl_fire", pos + Vector3(0, radius * 0.1, 0), up, k)
	_emit("expl_glow", pos + Vector3(0, radius * 0.12, 0), up, k)
	_emit("expl_smoke", pos + Vector3(0, radius * 0.12, 0), up, k)
	_emit("expl_debris", pos + Vector3(0, 0.25, 0), up, k)
	_emit("expl_sparks", pos + Vector3(0, 0.3, 0), up, k)
	_emit("dust_ring", pos + Vector3(0, 0.25, 0), Vector3(0, 1, 0), k)
	# faceted white-hot core
	var core := _anim_acquire(Anim.CORE)
	core.t = 0.0
	core.dur = 0.26 + 0.1 * k
	core.r = radius * 0.5
	core.c0 = Color(1.0, 0.92, 0.65, 1.0)
	core.c1 = Color(1.0, 0.5, 0.12, 0.0)
	core.node.global_position = pos + Vector3(0, radius * 0.1, 0)
	core.node.scale = Vector3.ONE * 0.3
	core.node.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	core.node.visible = true
	_anim_active.append(core)
	# slower orange fireball shell
	var sh := _anim_acquire(Anim.SHOCK)
	sh.t = 0.0
	sh.dur = 0.5 + 0.15 * k
	sh.r = radius * 0.58
	sh.c0 = Color(1.0, 0.64, 0.16, 0.82)
	sh.c1 = Color(0.85, 0.32, 0.07, 0.0)
	sh.node.global_position = pos + Vector3(0, radius * 0.18, 0)
	sh.node.scale = Vector3.ONE * 0.2
	sh.node.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	sh.node.visible = true
	_anim_active.append(sh)
	# shockwave ring on the ground
	ring(pos, radius * 1.7, Color(1.0, 0.85, 0.6, 0.65), 0.42 + 0.1 * k)
	# flash light
	var li := _anim_acquire(Anim.LIGHT)
	li.t = 0.0
	li.dur = 0.55 + 0.2 * k
	li.e0 = 10.0 + 12.0 * k
	li.light.omni_range = radius * (3.2 if big else 4.0)
	li.light.light_energy = li.e0
	li.light.light_color = Color(1.0, 0.68, 0.34)
	li.node.global_position = pos + Vector3(0, 1.0, 0)
	li.node.visible = true
	_anim_active.append(li)
	if opts.get("scorch", true):
		scorch(pos, radius)
	set_process(true)


# =========================================================================================== update
func _process(delta: float) -> void:
	_clock += delta
	var any := false
	# tracers
	if _tr_active > 0:
		for i in MAX_TRACERS:
			if _tr_on[i] == 0:
				continue
			var prog := _tr_prog[i] + _tr_speed[i] * delta
			_tr_prog[i] = prog
			var head := minf(prog, _tr_dist[i])
			var tail := maxf(prog - _tr_len[i], 0.0)
			if tail >= _tr_dist[i]:
				_tr_on[i] = 0
				_tr_active -= 1
				_tr_node[i].visible = false
				continue
			var seg := head - tail
			var d := _tr_dir[i]
			var center := _tr_from[i] + d * (tail + seg * 0.5)
			var bs := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT)
			bs = bs * Basis.from_scale(Vector3(_tr_width[i], _tr_width[i], maxf(seg, 0.05)))
			_tr_node[i].global_transform = Transform3D(bs, center)
		any = any or _tr_active > 0
	# shells
	if _sh_active > 0:
		for i in MAX_SHELLS:
			if _sh_on[i] == 0:
				continue
			var age := _sh_age[i] + delta
			_sh_age[i] = age
			var m := _sh_node[i]
			if age > 2.4:
				_sh_on[i] = 0
				_sh_active -= 1
				m.visible = false
				continue
			var v := _sh_vel[i]
			if v.length_squared() > 0.0004:
				v.y -= 9.8 * delta
				var p := m.global_position + v * delta
				if p.y <= _sh_ground[i]:
					p.y = _sh_ground[i]
					if _sh_bounces[i] < 2 and absf(v.y) > 0.8:
						v.y = -v.y * 0.35
						v.x *= 0.55
						v.z *= 0.55
						_sh_bounces[i] += 1
					else:
						v = Vector3.ZERO
				_sh_vel[i] = v
				m.global_position = p
				m.rotate_x(_sh_spin[i].x * delta)
				m.rotate_y(_sh_spin[i].y * delta)
		any = any or _sh_active > 0
	# timed anims
	var n := _anim_active.size()
	for idx in range(n - 1, -1, -1):
		var a: AnimItem = _anim_active[idx]
		a.t += delta
		var u := clampf(a.t / a.dur, 0.0, 1.0)
		if u >= 1.0:
			_anim_active.remove_at(idx)
			_anim_release(a)
			continue
		match a.kind:
			Anim.CORE, Anim.SHOCK:
				var e := 1.0 - pow(1.0 - u, 3.0)
				a.node.scale = Vector3.ONE * lerpf(a.r * 0.3, a.r, e)
				a.mat.albedo_color = a.c0.lerp(a.c1, u * u if a.kind == Anim.CORE else u)
			Anim.RING:
				var e2 := 1.0 - pow(1.0 - u, 2.5)
				var s := lerpf(0.2, a.r * 2.0, e2)
				a.node.scale = Vector3(s, 1.0, s)
				var c := a.c0
				c.a = a.c0.a * (1.0 - u)
				a.mat.albedo_color = c
			Anim.LIGHT:
				a.light.light_energy = a.e0 * pow(1.0 - u, 2.0)
	any = any or not _anim_active.is_empty()
	if not any:
		set_process(false)
