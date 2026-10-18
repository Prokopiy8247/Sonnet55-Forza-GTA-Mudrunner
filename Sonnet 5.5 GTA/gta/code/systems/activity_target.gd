class_name ActivityTarget
extends AnimatableBody3D
## One pop-up range target: the `Plate` mesh of props/range_target(_round).glb hinged on its housing, a trimesh collider on the
## plate, group `damageable` so WeaponController hitscan (Ballistics.shoot -> apply_damage) registers real bullets.
## Scoring comes from the world hit position transformed into plate space (head / body rings, bullseye rings on the round plate).
## Outside a scored round (live == false) a hit just flips the plate down and it pops back up after IDLE_RESET seconds.

signal scored(target: ActivityTarget, info: Dictionary)

const DOWN_ANGLE := PI * 0.5
const RISE_TIME := 0.20
const FALL_TIME := 0.15
const IDLE_RESET := 2.6
const CIV_TINT := {"TargetBlack": Color("#17566e"), "TargetRed": Color("#34e0ff"), "TargetWhite": Color("#f3fbff")}

static var _civ_mats: Dictionary = {}
static var fallback_used := 0

var kind: StringName = &"silhouette"         # or &"round"
var civilian := false
var live := false                           # a scored round is running
var is_up := true
var root: Node3D = null                      # stand + this body
var plate: MeshInstance3D = null
var plate_civ: MeshInstance3D = null
var column := 0
var row_m := 0.0
var slide_amp := 0.0                         # m, lateral sliding (hard round)
var slide_speed := 1.4
var expire_at := -1.0                        # set by the range (activity time)
var wave_id := -1

var _angle := DOWN_ANGLE
var _anim := 1.0                             # 0..1 progress of the current flip
var _from := DOWN_ANGLE
var _to := 0.0
var _pending: Dictionary = {}                # hit scored this frame (shotgun pellets: best one wins)
var _idle_t := -1.0
var _wobble := 0.0
var _slide_t := 0.0
var _home_global := Vector3.ZERO
var _lateral := Vector3.RIGHT


## Builds stand + plate at `xf` (world transform, front = -Z facing the shooters) under `parent`. Returns the hinge body (root is `.root`).
static func create(target_kind: StringName, xf: Transform3D, parent: Node3D) -> ActivityTarget:
	var rel := "props/range_target_round" if target_kind == &"round" else "props/range_target"
	var model: Node3D = ModelLib.instance(rel)
	if model == null:
		push_warning("[Activities] FALLBACK: %s missing - code-built range target stand" % rel)
		fallback_used += 1
		model = _fallback_model(target_kind)
	var holder := Node3D.new()
	holder.name = "RangeTarget_" + String(target_kind)
	parent.add_child(holder)
	holder.global_transform = xf
	holder.add_child(model)
	var hinge := model.find_child("Hinge", true, false) as Node3D
	var plate_node := model.find_child("Plate", true, false) as MeshInstance3D
	var hinge_pos := hinge.position if hinge != null else Vector3(0, 0.3, 0)
	var body := ActivityTarget.new()
	body.kind = target_kind
	body.name = "Plate"
	body.root = holder
	body.sync_to_physics = false
	body.collision_layer = GC.L_PROP
	body.collision_mask = 0
	body.add_to_group(GC.G_DAMAGEABLE)
	body.set_meta(&"surface", &"metal")
	holder.add_child(body)
	body.position = model.position + hinge_pos
	if plate_node != null:
		plate_node.get_parent().remove_child(plate_node)
		body.add_child(plate_node)
		plate_node.transform = Transform3D.IDENTITY
		body.plate = plate_node
		if plate_node.mesh != null:
			var shape := plate_node.mesh.create_trimesh_shape()
			if shape != null:
				shape.backface_collision = true
				var cs := CollisionShape3D.new()
				cs.shape = shape
				body.add_child(cs)
		body.plate_civ = _make_civ_plate(plate_node)
		if body.plate_civ != null:
			body.add_child(body.plate_civ)
			body.plate_civ.visible = false
	body._home_global = holder.global_position
	body._lateral = holder.global_transform.basis.x
	body._angle = 0.0
	body._to = 0.0
	body._from = 0.0
	body._anim = 1.0
	body.rotation.x = 0.0
	body.set_physics_process(false)
	return body


static func _fallback_model(target_kind: StringName) -> Node3D:
	var m := Node3D.new()
	var base := MeshInstance3D.new()
	base.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.25, 0.6)
	base.mesh = bm
	base.position = Vector3(0, 0.125, 0)
	m.add_child(base)
	var h := Node3D.new()
	h.name = "Hinge"
	h.position = Vector3(0, 0.3, 0)
	m.add_child(h)
	var pl := MeshInstance3D.new()
	pl.name = "Plate"
	var pm := BoxMesh.new()
	pm.size = Vector3(0.6, 1.55, 0.03) if target_kind != &"round" else Vector3(0.9, 0.9, 0.03)
	pl.mesh = pm
	pl.position = Vector3(0, 0.3, 0)
	m.add_child(pl)
	pm.surface_set_material(0, _civ_mat("TargetBlack"))
	return m


static func _civ_mat(nm: String) -> StandardMaterial3D:
	if _civ_mats.has(nm):
		return _civ_mats[nm]
	var m := StandardMaterial3D.new()
	m.resource_name = nm
	var c: Color = CIV_TINT.get(nm, Color(0.2, 0.2, 0.2))
	m.albedo_color = c
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if nm == "TargetRed":
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.5
	_civ_mats[nm] = m
	return m


## Civilian twin of the plate (cyan palette + a floating ring above the head), swapped in by set_civilian().
static func _make_civ_plate(src: MeshInstance3D) -> MeshInstance3D:
	if src.mesh == null:
		return null
	var cp := MeshInstance3D.new()
	cp.name = "PlateCivilian"
	cp.mesh = src.mesh
	for i in src.mesh.get_surface_count():
		var mat := src.mesh.surface_get_material(i)
		var nm := mat.resource_name if mat != null else ""
		if CIV_TINT.has(nm):
			cp.set_surface_override_material(i, _civ_mat(nm))
	# halo marking a friendly
	var tm := TorusMesh.new()
	tm.inner_radius = 0.17
	tm.outer_radius = 0.21
	tm.rings = 20
	tm.ring_segments = 5
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	halo.mesh = tm
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color("#34e0ff")
	halo.material_override = hm
	halo.position = Vector3(0, 1.75, 0)
	cp.add_child(halo)
	return cp


# ---- state -----------------------------------------------------------------------------------------------------------------
func set_civilian(on: bool) -> void:
	civilian = on
	if plate != null:
		plate.visible = not on
	if plate_civ != null:
		plate_civ.visible = on


func pop_up() -> void:
	if is_up and _anim >= 1.0 and absf(_angle) < 0.01:
		return
	is_up = true
	_pending = {}
	_from = _angle
	_to = 0.0
	_anim = 0.0
	_idle_t = -1.0
	set_physics_process(true)


func pop_down() -> void:
	is_up = false
	collision_layer = 0
	_from = _angle
	_to = DOWN_ANGLE
	_anim = 0.0
	set_physics_process(true)


func is_standing() -> bool:
	return is_up and not is_down_anim()


func is_down_anim() -> bool:
	return _anim < 1.0 and _to > 0.1


func set_sliding(amp: float, speed: float = 1.4) -> void:
	slide_amp = amp
	slide_speed = speed
	_slide_t = randf() * TAU
	set_physics_process(true)


func stop_sliding() -> void:
	slide_amp = 0.0
	if root != null:
		root.global_position = _home_global
	set_physics_process(_anim < 1.0 or not _pending.is_empty() or _idle_t >= 0.0)


# ---- scoring -----------------------------------------------------------------------------------------------------------------
## Points for a world-space hit position. Dictionary: points, zone (&"head" &"bull" &"body" &"limb" &"civilian" &"ring"), label, dist, ring.
func score_hit(world_pos: Vector3) -> Dictionary:
	var l := to_local(world_pos)
	var out := {"points": 30, "zone": &"limb", "label": "HIT", "dist": 9.0, "ring": 0, "x": l.x, "y": l.y}
	if civilian:
		out["points"] = -150
		out["zone"] = &"civilian"
		out["label"] = "CIVILIAN"
		return out
	if kind == &"round":
		var d := Vector2(l.x, l.y - 0.45).length()
		out["dist"] = d
		var rings := [[0.045, 100, "BULLSEYE"], [0.10, 90, "INNER"], [0.17, 80, "HIT"], [0.24, 70, "HIT"], [0.32, 60, "OUTER"], [0.40, 50, "OUTER"]]
		out["points"] = 40
		out["zone"] = &"ring"
		out["label"] = "EDGE"
		for i in rings.size():
			if d <= float(rings[i][0]):
				out["points"] = int(rings[i][1])
				out["label"] = String(rings[i][2])
				out["ring"] = 6 - i
				if i == 0:
					out["zone"] = &"bull"
				break
		return out
	var dh := Vector2(l.x, l.y - 1.39).length()
	var db := Vector2(l.x, l.y - 0.88).length()
	if dh <= 0.105:
		out["points"] = 150 if dh <= 0.052 else 120
		out["zone"] = &"head"
		out["label"] = "HEADSHOT"
		out["dist"] = dh
		return out
	out["dist"] = db
	if db <= 0.04:
		out["points"] = 100
		out["zone"] = &"bull"
		out["label"] = "BULLSEYE"
		out["ring"] = 4
	elif db <= 0.105:
		out["points"] = 85
		out["zone"] = &"body"
		out["label"] = "CENTRE"
		out["ring"] = 3
	elif db <= 0.17:
		out["points"] = 70
		out["zone"] = &"body"
		out["label"] = "BODY"
		out["ring"] = 2
	elif db <= 0.235:
		out["points"] = 55
		out["zone"] = &"body"
		out["label"] = "BODY"
		out["ring"] = 1
	elif l.y > 1.05 and absf(l.x) < 0.14:
		out["points"] = 45
		out["zone"] = &"body"
		out["label"] = "NECK"
	return out


## Damage contract: bullets from WeaponController / Ballistics land here.
func apply_damage(amount: float, info: Dictionary = {}) -> void:
	if not is_up or is_down_anim():
		return
	if _anim < 1.0 and _to < 0.1 and _angle > 0.7:
		return                                  # still folded down while rising
	var hp: Vector3 = info.get("position", global_position + Vector3(0, 0.88, 0))
	var sc := score_hit(hp)
	sc["damage"] = amount
	sc["weapon"] = info.get("weapon", &"")
	sc["position"] = hp
	sc["source"] = info.get("source", null)
	if _pending.is_empty():
		_pending = sc
		set_physics_process(true)
	elif int(sc["points"]) > int(_pending["points"]) and not civilian:
		_pending = sc


func _physics_process(dt: float) -> void:
	var busy := false
	if not _pending.is_empty():
		var info := _pending
		_pending = {}
		is_up = false
		collision_layer = 0
		_from = _angle
		_to = DOWN_ANGLE
		_anim = 0.0
		if live:
			scored.emit(self, info)
		else:
			_idle_t = IDLE_RESET
			if Sfx != null:
				Sfx.play_3d(&"hit_metal", global_position + Vector3(0, 0.9, 0), -6.0, 1.4, 60.0)
	if _anim < 1.0:
		var dur := RISE_TIME if _to < 0.1 else FALL_TIME
		_anim = minf(_anim + dt / dur, 1.0)
		var e := smoothstep(0.0, 1.0, _anim)
		_angle = lerpf(_from, _to, e)
		if _anim >= 1.0:
			_angle = _to
			if _to < 0.1:
				collision_layer = GC.L_PROP
				_wobble = 0.34
			busy = true
		else:
			busy = true
		if _to < 0.1 and _anim > 0.55:
			collision_layer = GC.L_PROP
	if _wobble > 0.0:
		_wobble = maxf(_wobble - dt, 0.0)
		rotation.x = _angle + sin(_wobble * 52.0) * 0.07 * (_wobble / 0.34)
		busy = true
	else:
		rotation.x = _angle
	if _idle_t >= 0.0:
		_idle_t -= dt
		busy = true
		if _idle_t < 0.0 and not live:
			pop_up()
	if slide_amp > 0.0 and root != null:
		_slide_t += dt * slide_speed
		root.global_position = _home_global + _lateral * (sin(_slide_t) * slide_amp)
		busy = true
	set_physics_process(busy)
