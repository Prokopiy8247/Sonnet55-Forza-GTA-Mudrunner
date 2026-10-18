class_name StreetFurniture
extends RefCounted
## Instantiates WorldLayout.furniture: lamps (group street_lamp), traffic signals (state driven by ContentManager through the
## MultiMesh custom data), signs, hydrants, benches, bins, bollards, barriers, cones, bus stops, fences, utility boxes,
## mailboxes, parking meters and billboards. Static props are MultiMesh instances per sector; at most MAX_DYNAMIC cones / bins /
## barriers become sleeping RigidBody3D (ContentProp) for smash physics. Meshes come from Blender props GLBs (props/*) when present,
## else from the code-built ContentProps fallbacks (logged).

const _CP := preload("res://gta/code/world/content_props.gd")
const _PROP := preload("res://gta/code/world/content_prop.gd")

const MAX_DYNAMIC := 150
const DYNAMIC_KINDS := [&"cone", &"bin", &"barrier"]

## kind -> [fallback fn, glb name candidates, lod end, shadow, collider]
## collider: {"shape": "cyl"|"box", "r", "h", "size", "off"} in prop-local space (yaw applied).
static var _defs: Dictionary = {}
static var _glb_names: PackedStringArray = PackedStringArray()
static var stats := {"items": 0, "static": 0, "dynamic": 0, "lamps": 0, "signals": 0, "skipped": 0, "by_kind": {}}
static var hooks: Array = []     # pending signal hooks [{cell, key, index, id, phase}]


static func reset() -> void:
	stats = {"items": 0, "static": 0, "dynamic": 0, "lamps": 0, "signals": 0, "skipped": 0, "by_kind": {}}
	hooks.clear()
	_glb_names = PackedStringArray()


static func _init_defs() -> void:
	if not _defs.is_empty():
		return
	_defs = {
		&"lamp": [_CP.lamp, ["street_lamp", "streetlight", "lamp_post", "lamp"], 230.0, true, {"shape": "cyl", "r": 0.13, "h": 6.5}],
		&"signal": [_CP.signal_pole, ["traffic_light", "traffic_signal", "signal_pole", "signal"], 200.0, true, {"shape": "cyl", "r": 0.12, "h": 3.6}],
		&"sign_stop": [_CP.sign_stop, ["sign_stop", "stop_sign"], 110.0, false, {"shape": "cyl", "r": 0.07, "h": 2.5}],
		&"sign_speed": [_CP.sign_speed, ["sign_speed", "speed_sign", "sign_limit"], 110.0, false, {"shape": "cyl", "r": 0.07, "h": 2.5}],
		&"hydrant": [_CP.hydrant, ["hydrant", "fire_hydrant"], 90.0, false, {"shape": "cyl", "r": 0.2, "h": 0.85}],
		&"bench": [_CP.bench, ["bench"], 110.0, false, {"shape": "box", "size": Vector3(1.8, 0.9, 0.55), "off": Vector3(0, 0.45, 0.12)}],
		&"bin": [_CP.bin, ["trash_bin", "bin", "trashcan", "garbage"], 100.0, false, {"shape": "cyl", "r": 0.3, "h": 0.9}],
		&"bollard": [_CP.bollard, ["bollard"], 90.0, false, {"shape": "cyl", "r": 0.13, "h": 0.95}],
		&"bus_stop": [_CP.bus_stop, ["bus_stop", "bus_shelter"], 170.0, true, {"shape": "box", "size": Vector3(3.4, 2.6, 0.6), "off": Vector3(0, 1.3, 0.75)}],
		&"cone": [_CP.cone, ["road_cone", "traffic_cone", "cone"], 80.0, false, {"shape": "cyl", "r": 0.2, "h": 0.7}],
		&"barrier": [_CP.barrier, ["road_barrier", "barrier", "jersey"], 100.0, false, {"shape": "box", "size": Vector3(1.6, 0.9, 0.5), "off": Vector3(0, 0.45, 0)}],
		&"fence": [_CP.fence, ["fence", "chainlink"], 150.0, false, {"shape": "box", "size": Vector3(3.0, 1.8, 0.12), "off": Vector3(0, 0.9, 0)}],
		&"utility_box": [_CP.utility_box, ["utility_box", "utility", "cabinet"], 100.0, false, {"shape": "box", "size": Vector3(0.85, 1.3, 0.5), "off": Vector3(0, 0.65, 0)}],
		&"mailbox": [_CP.mailbox, ["mailbox", "post_box"], 80.0, false, {"shape": "cyl", "r": 0.22, "h": 1.3}],
		&"parking_meter": [_CP.parking_meter, ["parking_meter", "meter"], 70.0, false, {"shape": "cyl", "r": 0.07, "h": 1.4}],
		&"billboard": [_CP.billboard, ["billboard"], 0.0, true, {"shape": "billboard"}],
	}


static func _list_glbs() -> void:
	if not _glb_names.is_empty():
		return
	var dir := DirAccess.open(ModelLib.ROOT + "props")
	if dir == null:
		_glb_names.append("")
		return
	for f in dir.get_files():
		if f.ends_with(".glb"):
			_glb_names.append(f.get_basename())
	if _glb_names.is_empty():
		_glb_names.append("")


## Finds the props GLB for a kind: exact candidate names first, then any file containing a candidate token.
static func find_glb(kind: StringName) -> String:
	_list_glbs()
	var cands: Array = _defs[kind][1]
	for c in cands:
		if _glb_names.has(String(c)):
			return "props/" + String(c)
	for c in cands:
		for n in _glb_names:
			if n != "" and n.contains(String(c)):
				return "props/" + n
	return ""


static func mesh_key(kind: StringName) -> StringName:
	return StringName("prop_" + String(kind))


## Registers the mesh for a kind (GLB when present, else fallback) and its LOD. Returns false when no mesh exists.
static func _ensure_mesh(batch: ContentBatch, kind: StringName) -> bool:
	var key := mesh_key(kind)
	if ContentLib.has_mesh(key):
		return true
	var def: Array = _defs[kind]
	var rel := find_glb(kind)
	var fb: Callable = def[0]
	if rel != "":
		ContentLib.register_glb_or(key, rel, func(): return fb.call())
	else:
		var cm: ContentMesh = fb.call()
		ContentLib.put(key, cm.to_mesh(ContentLib._default_materials()), "fallback")
		push_warning("StreetFurniture: no props GLB for '%s' - using code-built FALLBACK mesh" % kind)
	var end: float = def[2]
	batch.set_lod(key, 0.0, end, 12.0, def[3])
	return ContentLib.has_mesh(key)


static func _collider(batch: ContentBatch, kind: StringName, xf: Transform3D) -> void:
	var def: Array = _defs[kind]
	var c: Dictionary = def[4]
	match c.get("shape", ""):
		"cyl":
			batch.add_cyl_collider(xf.origin, float(c["r"]), float(c["h"]), &"metal")
		"box":
			var off: Vector3 = c["off"]
			batch.add_box_collider(xf * Transform3D(Basis.IDENTITY, off), c["size"], &"metal")
		"billboard":
			for sx in [-3.2, 3.2]:
				batch.add_cyl_collider((xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0, 0.2))).origin, 0.25, 6.0, &"metal")


static func _spawn_dynamic(batch: ContentBatch, mgr: ContentManager, kind: StringName, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var key := mesh_key(kind)
	var mesh := ContentLib.get_mesh(key)
	if mesh == null:
		return
	var id := ContentBatch.cell_id(xf.origin)
	var parent := batch.dynamic_parent(id)
	var body := _PROP.new()
	body.kind = kind
	body.name = "Prop_%s_%d" % [kind, stats["dynamic"]]
	body.collision_layer = GC.L_PROP
	body.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_NPC | GC.L_PLAYER | GC.L_PROP
	body.add_to_group(GC.G_DAMAGEABLE)
	body.add_to_group(&"smashable_prop")
	body.can_sleep = true
	body.linear_damp = 0.25
	body.angular_damp = 0.9
	match kind:
		&"cone":
			body.mass = 2.5
		&"bin":
			body.mass = 9.0
		_:
			body.mass = 18.0
	var cs := CollisionShape3D.new()
	var c: Dictionary = (_defs[kind] as Array)[4]
	if c["shape"] == "cyl":
		var sh := CylinderShape3D.new()
		sh.radius = c["r"]
		sh.height = c["h"]
		cs.shape = sh
		cs.position = Vector3(0, float(c["h"]) * 0.5, 0)
	else:
		var sb := BoxShape3D.new()
		sb.size = c["size"]
		cs.shape = sb
		cs.position = c["off"]
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 120.0
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	body.add_child(mi)
	parent.add_child(body)
	batch.own(body)
	var inv := Transform3D.IDENTITY
	if parent.is_inside_tree():
		inv = parent.global_transform.affine_inverse()
	body.transform = inv * xf
	body.sleeping = true
	mgr.register_prop(body)
	stats["dynamic"] += 1


static func build(batch: ContentBatch, mgr: ContentManager) -> void:
	_init_defs()
	var items: Array = WorldLayout.furniture
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var now := Time.get_ticks_msec() / 1000.0
	for item in items:
		var kind: StringName = item.get("kind", &"")
		if kind == &"palm" or kind == &"tree_street":
			continue   # NatureBuilder
		if not _defs.has(kind):
			stats["skipped"] += 1
			continue
		if not _ensure_mesh(batch, kind):
			stats["skipped"] += 1
			continue
		stats["items"] += 1
		var bk: Dictionary = stats["by_kind"]
		bk[kind] = int(bk.get(kind, 0)) + 1
		var pos: Vector3 = item.get("pos", Vector3.ZERO)
		var yaw := float(item.get("yaw", 0.0))
		var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
		var key := mesh_key(kind)
		var irand := rng.randf()
		var custom := Color(0.0, rng.randf(), rng.randf(), irand)
		if kind in DYNAMIC_KINDS and int(stats["dynamic"]) < MAX_DYNAMIC:
			_spawn_dynamic(batch, mgr, kind, xf, rng)
			continue
		if kind == &"signal":
			var sid := int(item.get("signal_id", -1))
			var f := -xf.basis.z
			var phase := int(item.get("phase", -1))
			if phase < 0:
				phase = 0 if absf(f.z) >= absf(f.x) else 1
			var st := WorldLayout.signal_state(sid, phase, now) if sid >= 0 else 0
			custom = Color(float(st), 0.0, 0.0, irand)
			var idx := batch.add(key, xf, custom)
			hooks.append({"cell": ContentBatch.cell_id(pos), "key": key, "index": idx, "id": sid, "phase": phase, "state": st})
			stats["signals"] += 1
		else:
			batch.add(key, xf, custom)
		stats["static"] += 1
		_collider(batch, kind, xf)
		if kind == &"lamp":
			_make_lamp_node(batch, key, xf)


static func _make_lamp_node(batch: ContentBatch, key: StringName, xf: Transform3D) -> void:
	var id := ContentBatch.cell_id(xf.origin)
	var parent := batch.sector_parent(id)
	var n := Node3D.new()
	n.name = "Lamp_%d" % stats["lamps"]
	n.add_to_group(&"street_lamp")
	var bb: AABB = ContentLib.aabbs.get(key, AABB(Vector3.ZERO, Vector3(1, 6.5, 1)))
	var h := bb.end.y - 0.12
	var off := Vector3.ZERO
	if bb.position.z < -0.7:
		off = Vector3(0, 0, bb.position.z + 0.5)   # arm lamp: the light sits under the head toward the road
	n.set_meta("lamp_height", h)
	n.set_meta("lamp_offset", off)
	parent.add_child(n)
	batch.own(n)
	var inv := Transform3D.IDENTITY
	if parent.is_inside_tree():
		inv = parent.global_transform.affine_inverse()
	n.transform = inv * xf
	stats["lamps"] += 1


## After ContentBatch.flush(): hands the signal MultiMesh instances to the manager.
static func finish(batch: ContentBatch, mgr: ContentManager) -> void:
	for h in hooks:
		var mm := batch.get_multimesh(int(h["cell"]), h["key"])
		if mm != null:
			mgr.register_signal(mm, int(h["index"]), int(h["id"]), int(h["phase"]))
			mgr.signal_hooks[mgr.signal_hooks.size() - 1]["state"] = int(h["state"])
	hooks.clear()
