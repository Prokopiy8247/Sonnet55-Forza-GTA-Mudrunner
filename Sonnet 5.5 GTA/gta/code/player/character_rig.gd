class_name CharacterRig
extends Node3D
## Visual + procedural animation of any humanoid (player, pedestrians, police, shop staff, gang members).
## Built from characters/human.glb (docs/ARCHITECTURE.md sections 7, 8, 12); while the GLB is missing a clearly logged
## procedural fallback skeleton + mannequin (RigFallback) is used instead. Public API documented in docs/api/character_rig.md.
##
## Typical use (owner = CharacterBase):
##   rig = CharacterRig.new(); add_child(rig); rig.setup(CharacterVariants.random_pedestrian(rng))
##   every frame: rig.set_locomotion(speed, local_move_dir, sprinting)   (the rig animates itself in _process)
## All methods are safe to call before / after setup() and on a rig that is not in the tree.

signal ragdoll_settled
signal ragdoll_started

const MODEL_ID := "characters/human"
const BODY_PREFIXES := ["Body_", "Hair_", "Hat_", "Helmet_", "Glasses_", "Vest_", "Jacket_", "Backpack", "Beard_"]
const LOD_NEAR := 38.0
const LOD_MID := 75.0

static var _warned_fallback := false
static var _warned_bodies: Dictionary = {}
static var _mat_cache: Dictionary = {}

## 0 = full rate, 1 = reduced (about 15 Hz), 2 = frozen (no animation). Owners may write it after setting auto_lod = false.
var lod := 0
## When true the rig sets `lod` itself from the camera distance / visibility (cheap check every ~0.4 s).
var auto_lod := true
## Tests drive the animation by calling update_pose(dt) themselves.
var manual_update := false
var variant: Dictionary = {}
var model: Node3D = null
var skeleton: Skeleton3D = null
var using_fallback := false
var solver := RigSolver.new()
var motion := RigMotion.new()

var _built := false
var _sockets: Array[Node3D] = [null, null]
var _attach: Array[BoneAttachment3D] = [null, null]
var _stance: StringName = &"stand"
var _look_point := Vector3.ZERO
var _look_time := -10.0
var _clock := 0.0
var _lod_timer := 0.0
var _lod_accum := 0.0
var _last_yaw := 0.0
var _have_yaw := false
var _last_pos := Vector3.ZERO
var _have_pos := false
var _vel := Vector3.ZERO
var _ragdoll: RagdollBody = null
var _frozen_ragdoll := false
var _first_person := false
var _grip_watch := 0
var _head_bone := -1
var _last_scale := 1.0
var _getup := 0.0


# =====================================================================================================================
# Construction / appearance
# =====================================================================================================================
## variant keys: see CharacterVariants. Safe to call again to re-dress the character (weapons in the sockets survive).
func setup(v: Dictionary = {}) -> void:
	variant = v.duplicate()
	_build_model()
	_apply_variant()
	if _built:
		motion.snap_to_stance()
		_pose_once()


func _ensure_built() -> void:
	if not _built:
		setup(variant)


func _build_model() -> void:
	# keep whatever is mounted in the sockets across a rebuild
	var carried: Array[Array] = [[], []]
	for s in 2:
		if _sockets[s] != null and is_instance_valid(_sockets[s]):
			for ch in _sockets[s].get_children():
				_sockets[s].remove_child(ch)
				carried[s].append(ch)
	if _ragdoll != null:
		_ragdoll.destroy()
		_ragdoll = null
	_frozen_ragdoll = false
	if model != null and is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	model = null
	skeleton = null
	_built = false
	var inst: Node3D = null
	if ModelLib.exists(MODEL_ID):
		inst = ModelLib.instance(MODEL_ID)
	using_fallback = false
	if inst != null:
		skeleton = _find_skeleton(inst)
		if skeleton == null:
			push_error("CharacterRig: %s has no Skeleton3D - using the procedural fallback" % MODEL_ID)
			inst.free()
			inst = null
	if inst == null:
		inst = RigFallback.build()
		skeleton = _find_skeleton(inst)
		using_fallback = true
		if not _warned_fallback:
			_warned_fallback = true
			push_warning("CharacterRig: FALLBACK mannequin in use (%s missing or unusable). Replace with the Blender GLB." % MODEL_ID)
	model = inst
	model.name = "Model"
	add_child(model)
	if not solver.setup(skeleton):
		push_error("CharacterRig: skeleton does not match docs/ARCHITECTURE.md s12 - animation disabled")
	motion.setup(solver)
	_head_bone = skeleton.find_bone("Head")
	_prune_and_show()
	_make_sockets()
	for s in 2:
		for ch in carried[s]:
			_sockets[s].add_child(ch)
	_built = true


static func _find_skeleton(root: Node) -> Skeleton3D:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			return n as Skeleton3D
		for c in n.get_children():
			stack.append(c)
	return null


func _is_variant_part(n: String) -> bool:
	for p in BODY_PREFIXES:
		if n.begins_with(p):
			return true
	return false


## The mesh node name that the variant asks for in a category, or "" when none.
func _wanted_names() -> Dictionary:
	var want := {}
	var body := String(variant.get("body", "A")).to_upper()
	if body.begins_with("BODY_"):
		body = body.substr(5)
	if not (body in ["A", "B", "C"]):
		body = "A"
	if model.find_child("Body_" + body, true, false) == null:
		if not _warned_bodies.has(body):
			_warned_bodies[body] = true
			push_warning("CharacterRig: %s has no Body_%s mesh yet - using Body_A instead (asset still in progress)" % [MODEL_ID, body])
		body = "A"
	want["Body_" + body] = "body"
	var hv: Variant = variant.get("hair", 1)
	var style := 1
	if hv is int or hv is float:
		style = int(hv)
	elif variant.has("hair_style"):
		style = int(variant["hair_style"])
	if style > 0:
		want["Hair_%d" % clampi(style, 1, 6)] = "hair"
	for cat in ["hat", "glasses", "jacket", "vest", "backpack", "beard"]:
		var val := String(variant.get(cat, ""))
		if val == "" or val == "false" or val == "none":
			continue
		var cands: Array[String] = []
		cands.append(val)
		match cat:
			"hat":
				cands.append_array(["Hat_" + val, "Helmet_" + val])
			"glasses":
				cands.append("Glasses_" + val)
			"jacket":
				cands.append("Jacket_" + val)
			"vest":
				cands.append("Vest_" + val)
			"backpack":
				cands.append_array(["Backpack", "Backpack_" + val])
			"beard":
				cands.append("Beard_" + val)
		for cnd in cands:
			if model.find_child(cnd, true, false) != null:
				want[cnd] = cat
				break
	return want


func _prune_and_show() -> void:
	var want := _wanted_names()
	var to_free: Array[Node] = []
	for mi in ModelLib.meshes(model):
		var n := String(mi.name)
		if _is_variant_part(n):
			if want.has(n):
				mi.visible = true
			else:
				to_free.append(mi)
	for n in to_free:
		n.get_parent().remove_child(n)
		n.free()


func _apply_variant() -> void:
	if model == null:
		return
	var sc := clampf(float(variant.get("scale", 1.0)), 0.5, 1.6)
	_last_scale = sc
	scale = Vector3.ONE * sc
	for s in 2:
		if _sockets[s] != null:
			_sockets[s].scale = Vector3.ONE / sc
	# colours
	var skin: Color = _col("skin", Color("#d9a77c"))
	var hair_c: Color = _col("hair_color", Color("#4a3022"))
	var hv: Variant = variant.get("hair", null)
	if hv is Color:
		hair_c = hv
	var shirt: Color = _col("shirt", Color("#5b7fa6"))
	var pants: Color = _col("pants", Color("#25324d"))
	var shoes: Color = _col("shoes", Color("#15171a"))
	var accent: Color = _col("accent", Color("#ff3d9a"))
	var cmap := {"Skin": skin, "Shirt": shirt, "Pants": pants, "Shoes": shoes, "Accent": accent, "Hair": hair_c}
	var jacket_c: Color = _col("jacket_color", shirt.darkened(0.25))
	var vest_c: Color = _col("vest_color", Color("#2b2e33"))
	var hat_c: Color = _col("hat_color", accent)
	var pack_c: Color = _col("pack_color", accent)
	for mi in ModelLib.meshes(model):
		if mi.mesh == null:
			continue
		var n := String(mi.name)
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			var mname := ""
			if src != null:
				mname = src.resource_name.get_slice(".", 0)
			var c: Variant = _color_for_part(n, mname, cmap, jacket_c, vest_c, hat_c, pack_c, hair_c)
			if c is Color:
				mi.set_surface_override_material(i, _flat_mat(c, mname))
			elif src is StandardMaterial3D:
				mi.set_surface_override_material(i, _tune_original(src as StandardMaterial3D))


func _color_for_part(part: String, mname: String, cmap: Dictionary, jacket_c: Color, vest_c: Color, hat_c: Color, pack_c: Color, hair_c: Color) -> Variant:
	if part.begins_with("Body_"):
		return cmap.get(mname, null)
	if part.begins_with("Hair_") or part.begins_with("Beard_"):
		return hair_c if mname in ["Hair", ""] else cmap.get(mname, null)        # Accent = hair tie / band
	if part.begins_with("Hat_") or part.begins_with("Helmet_"):
		if mname in ["Accent", "Hat", "Shirt", "Hair", "Gun"]:
			return hat_c
		return null
	if part.begins_with("Jacket_"):
		if mname in ["Shirt", "Jacket"]:
			return jacket_c
		if mname == "Accent":
			return jacket_c.lightened(0.18) if jacket_c.get_luminance() < 0.45 else jacket_c.darkened(0.25)   # collar / cuffs / zip trim
		return cmap.get(mname, null) if mname in ["Skin", "Pants", "Shoes"] else null
	if part.begins_with("Vest_"):
		if mname in ["Accent", "Shirt", "Vest"]:
			return vest_c
		return null
	if part.begins_with("Backpack"):
		if mname in ["Accent", "Shirt", "Pack"]:
			return pack_c
		return null
	if part.begins_with("Glasses_"):
		return null
	return cmap.get(mname, null)


func _col(key: String, default_c: Color) -> Color:
	var v: Variant = variant.get(key, default_c)
	if v is Color:
		return v
	if v is String or v is StringName:
		return Color(String(v))
	return default_c


## Flat colour, roughness ~0.85. Shared by colour so 60 pedestrians do not create hundreds of materials.
func _flat_mat(c: Color, slot: String) -> StandardMaterial3D:
	c = Color(roundf(c.r * 31.0) / 31.0, roundf(c.g * 31.0) / 31.0, roundf(c.b * 31.0) / 31.0, 1.0)   # 32 levels per channel: bounded cache
	var key := "%s_%d" % [slot, c.to_rgba32()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = slot
	m.albedo_color = c
	m.roughness = 0.85
	m.metallic = 0.0
	m.metallic_specular = 0.3
	_mat_cache[key] = m
	return m


func _tune_original(m: StandardMaterial3D) -> Material:
	return m


# ---- sockets ---------------------------------------------------------------------------------------------------------------
func _make_sockets() -> void:
	for s in 2:
		var right := s == 0
		var bone_name := "Hand_R" if right else "Hand_L"
		var ba := BoneAttachment3D.new()
		ba.name = "Attach" + bone_name
		skeleton.add_child(ba)
		ba.bone_name = bone_name
		var sock := Node3D.new()
		sock.name = "HandSocket_R" if right else "HandSocket_L"
		ba.add_child(sock)
		_attach[s] = ba
		_sockets[s] = sock
		if solver.valid:
			var hd: int = RigSolver.HAND_R + s * 4
			var fd: Vector3 = solver.hand_dir_rest[s]
			var frame: Basis = solver.hand_rest_frame[s]
			var bone_rest: Basis = solver.rest_basis[hd]
			var thumb: Vector3 = frame.y
			# grip centre: along the fingers from the wrist, slightly towards the thumb side
			var off_model: Vector3 = fd * 0.052 + thumb * 0.022
			sock.transform = Transform3D(bone_rest.transposed() * frame, bone_rest.transposed() * off_model)
		sock.scale = Vector3.ONE / maxf(_last_scale, 0.01)


# =====================================================================================================================
# Public API: control
# =====================================================================================================================
func set_locomotion(speed: float, move_dir_local: Vector3 = Vector3(0, 0, -1), sprinting: bool = false) -> void:
	motion.speed = maxf(speed, 0.0)
	if Vector2(move_dir_local.x, move_dir_local.z).length() > 0.05 or absf(move_dir_local.y) > 0.05:
		motion.move_dir = move_dir_local.normalized()
	motion.sprinting = sprinting


## stance: stand crouch cover_low cover_high swim_surface swim_under sit_car sit_bike ladder parachute ragdoll dead
func set_stance(stance: StringName) -> void:
	if stance == _stance:
		return
	var prev := _stance
	_stance = stance
	if motion.hands_up and stance != &"stand" and stance != &"crouch":
		motion.hands_up = false
	if stance == &"ragdoll":
		start_ragdoll()
		return
	if _ragdoll != null and prev == &"ragdoll":
		stop_ragdoll()
	if stance == &"dead":
		# deterministic but varied: face-down or face-up
		motion.dead_face_down = (int(get_instance_id()) + int(Time.get_ticks_msec() / 50)) % 3 == 0
	motion.stance = stance
	if (stance == &"stand" or stance == &"crouch") and prev == &"dead":
		motion.snap_to_stance()


func get_stance() -> StringName:
	return _stance


## active: raise the weapon / guard; pitch (rad, + = up) and yaw_offset (rad, + = left) are relative to the body facing.
func set_aim(active: bool, pitch: float = 0.0, yaw_offset: float = 0.0) -> void:
	motion.aim_on = active
	motion.aim_pitch = pitch
	motion.aim_yaw = yaw_offset


## kind: none pistol smg rifle shotgun sniper heavy melee_knife melee_bat thrown
func set_weapon_pose(kind: StringName) -> void:
	if not RigMotion.HOLD.has(kind):
		if kind != &"" and kind != &"fists":
			push_warning("CharacterRig: unknown weapon pose '%s' - using none" % kind)
		kind = &"none"
	motion.weapon = kind
	_grip_watch = 6      # re-scan the weapon for Grip_L in a few frames (the weapon node may be attached just after)


## action: punch kick melee_swing reload hit_react jump land enter_vehicle exit_vehicle throw hands_up (+ hands_down, stop).
## `duration` overrides the default length of timed actions (reload time of the weapon, melee swing time ...).
func play_action(action: StringName, duration: float = -1.0) -> void:
	_ensure_built()
	motion.play(action, duration)


func stop_action() -> void:
	motion.play(&"stop")


func is_action_playing(action: StringName = &"") -> bool:
	var a := motion.current_action()
	return a != &"" if action == &"" else a == action


## 0..1 progress of the current timed action (1 when idle).
func action_progress() -> float:
	return motion.action_progress()


## Hit reaction with an explicit world-space travel direction of the hit (the body is pushed along it).
func hit_react(world_direction: Vector3, strength: float = 1.0) -> void:
	var local := global_transform.basis.inverse() * world_direction
	motion.flinch(local, strength)


func set_grounded(grounded: bool, vertical_velocity: float = 0.0) -> void:
	if grounded and not motion.grounded:
		motion.air_vy = vertical_velocity
		motion.play(&"land")
	motion.grounded = grounded
	motion.air_vy = vertical_velocity
	if not grounded:
		motion.report_airborne()


## Vehicle seats / parachute: steering -1..1 (turns the wheel / handlebars / pulls a line).
func set_steering(value: float) -> void:
	motion.steering = value


## Bike body roll (radians, + = lean left).
func set_lean(roll: float) -> void:
	motion.lean_roll = roll


## Cover peek: -1 left .. +1 right (0 = pressed to the wall).
func set_cover_peek(value: float) -> void:
	motion.cover_peek = value


## role: &"driver" (hands on the wheel) or &"passenger"; offset moves the seated body (m, rig space). In sit_* stances the rig
## origin must be the seat point (the vehicle's SeatDriver empty): the pelvis rests ~0.08 m above it.
func set_seat(role: StringName = &"driver", offset: Vector3 = Vector3.ZERO) -> void:
	motion.seat_role = role
	motion.seat_offset = offset


## &"motorcycle" or &"bicycle" (pedalling feet driven by locomotion speed) for the sit_bike stance.
func set_ride_style(style: StringName) -> void:
	motion.ride_style = style


## &"relaxed" &"arms_crossed" &"hands_pockets" &"phone": idle variety for pedestrians (only visible when standing still).
func set_idle_style(style: StringName) -> void:
	motion.idle_style = style


func set_first_person(enabled: bool) -> void:
	_first_person = enabled
	if skeleton != null and _head_bone >= 0:
		skeleton.set_bone_pose_scale(_head_bone, Vector3.ONE * (0.001 if enabled else 1.0))
	if model != null:
		for mi in ModelLib.meshes(model):
			var n := String(mi.name)
			if n.begins_with("Hair_") or n.begins_with("Hat_") or n.begins_with("Helmet_") or n.begins_with("Glasses_") or n.begins_with("Beard_"):
				mi.visible = not enabled


## The head follows a world point for ~0.7 s after the last call (call every frame to keep tracking).
func look_at_point(point: Vector3) -> void:
	_look_point = point
	_look_time = _clock


func clear_look() -> void:
	_look_time = -10.0


# =====================================================================================================================
# Public API: queries
# =====================================================================================================================
func get_hand_socket(right: bool = true) -> Node3D:
	_ensure_built()
	var s: Node3D = _sockets[0 if right else 1]
	return s if s != null else self


func get_skeleton() -> Skeleton3D:
	_ensure_built()
	return skeleton


func get_head_position() -> Vector3:
	if not _built or skeleton == null:
		return global_position + Vector3(0, 1.7, 0) * _last_scale
	if _ragdoll != null and _ragdoll.active:
		return _ragdoll.part_position(RigSolver.HEAD) + Vector3(0, 0.0, 0)
	if _frozen_ragdoll:
		var bi := _head_bone if _head_bone >= 0 else 0
		var gp := skeleton.get_bone_global_pose(bi)
		return skeleton.global_transform * (gp.origin + gp.basis.y.normalized() * 0.14)
	return skeleton.global_transform * solver.head_center()


func get_eye_position() -> Vector3:
	if not _built or skeleton == null or not solver.valid or _ragdoll != null:
		return get_head_position()
	return skeleton.global_transform * solver.eye_position()


## World position of the body while ragdolling (hips); use it to place the owner / camera. Equals global_position otherwise.
func get_ragdoll_position() -> Vector3:
	if _ragdoll != null and (_ragdoll.active or _frozen_ragdoll):
		return _ragdoll.get_center()
	if _frozen_ragdoll and skeleton != null:
		return skeleton.global_transform * skeleton.get_bone_global_pose(0).origin
	return global_position


func is_ragdoll() -> bool:
	return _ragdoll != null and _ragdoll.active


func is_ragdoll_frozen() -> bool:
	return _frozen_ragdoll


func is_built() -> bool:
	return _built


# =====================================================================================================================
# Ragdoll
# =====================================================================================================================
## impulse: velocity change in m/s applied to the whole body (about 3-10 for a strong hit, clamped to 25); hit_position: world
## point of the hit (the nearest bone receives most of it). The current movement of the rig is inherited automatically.
func start_ragdoll(impulse: Vector3 = Vector3.ZERO, hit_position: Vector3 = Vector3.ZERO) -> void:
	_ensure_built()
	if _ragdoll != null and _ragdoll.active:
		_ragdoll.kick(impulse, hit_position)
		return
	if skeleton == null or not solver.valid:
		return
	_stance = &"ragdoll"
	motion.stance = &"ragdoll"
	_frozen_ragdoll = false
	if _ragdoll != null:
		_ragdoll.destroy()
	_ragdoll = RagdollBody.new()
	var ok := _ragdoll.start(self, skeleton, solver, impulse, hit_position, _vel)
	if not ok:
		_ragdoll = null
		return
	_ragdoll.settled.connect(_on_ragdoll_settled)
	_ragdoll.culled.connect(_on_ragdoll_culled)
	ragdoll_started.emit()


func stop_ragdoll() -> void:
	if _ragdoll == null:
		return
	var snap := _ragdoll.capture_pose()
	_ragdoll.destroy()
	_ragdoll = null
	_frozen_ragdoll = false
	if _stance == &"ragdoll":
		_stance = &"stand"
		motion.stance = &"stand"
	if solver.valid and not snap.is_empty():
		solver.begin_blend_from(snap)
		_getup = 0.5
	motion.snap_to_stance()
	_pose_once()


func _on_ragdoll_settled() -> void:
	_frozen_ragdoll = true
	ragdoll_settled.emit()


func _on_ragdoll_culled() -> void:
	# the oldest ragdoll was frozen early because too many bodies are alive
	_frozen_ragdoll = true
	ragdoll_settled.emit()


# =====================================================================================================================
# Per-frame update
# =====================================================================================================================
func _process(delta: float) -> void:
	if manual_update or not _built:
		return
	_tick(delta)


## Advance the animation by `dt` seconds immediately (tests / cutscenes with manual_update = true).
func update_pose(dt: float) -> void:
	_ensure_built()
	_clock += dt
	_motion_step(dt)


func _pose_once() -> void:
	if _built and solver.valid:
		motion.update(1.0 / 60.0)


func _tick(delta: float) -> void:
	_clock += delta
	# velocity estimate (inherited by ragdolls)
	if is_inside_tree():
		var gp := global_position
		if _have_pos and delta > 0.0:
			_vel = _vel.lerp((gp - _last_pos) / delta, 0.4)
		_last_pos = gp
		_have_pos = true
	if _frozen_ragdoll or (_ragdoll != null and _ragdoll.active):
		return
	if auto_lod:
		_lod_timer -= delta
		if _lod_timer <= 0.0:
			_lod_timer = 0.3 + 0.2 * float(get_instance_id() % 7) / 7.0
			_refresh_lod()
	if lod >= 2:
		return
	if lod == 1 or motion.is_calm():
		# reduced rate: ~15 Hz for far characters, 30 Hz for idle ones (breathing / weight shift only)
		_lod_accum += delta
		if _lod_accum < (0.066 if lod == 1 else 0.032):
			return
		delta = _lod_accum
		_lod_accum = 0.0
	_motion_step(delta)


func _motion_step(dt: float) -> void:
	if not solver.valid:
		return
	# turn rate of the owner for body lean
	if is_inside_tree():
		var f := -global_transform.basis.z
		var yaw := atan2(-f.x, -f.z)
		if _have_yaw and dt > 0.0:
			motion.yaw_rate = lerpf(motion.yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / dt, 0.35)
		_last_yaw = yaw
		_have_yaw = true
	# look-at
	if _clock - _look_time < 0.7 and is_inside_tree():
		var head := skeleton.global_transform * solver.head_center()
		var d := global_transform.basis.inverse() * (_look_point - head)
		if d.length() > 0.2:
			motion.look_dir_local = d.normalized()
			motion.look_weight = 1.0
		else:
			motion.look_weight = 0.0
	else:
		motion.look_weight = 0.0
	if _grip_watch > 0:
		_grip_watch -= 1
		if _grip_watch == 0:
			refresh_weapon_grip()
	motion.update(dt)
	if _getup > 0.0:
		_getup = maxf(_getup - dt, 0.0)


## Re-scans the weapon mounted in the right-hand socket for its Grip_L empty (two-handed weapons grip it exactly).
func refresh_weapon_grip() -> void:
	motion.has_support_grip = false
	solver.support_active = false
	var sock := _sockets[0]
	if sock == null or not solver.valid:
		return
	for ch in sock.get_children():
		if not (ch is Node3D):
			continue
		var grip := (ch as Node3D).find_child("Grip_L", true, false) as Node3D
		if grip == null:
			continue
		# Grip_L relative to the right wrist when the hand is in its rest orientation (model axes)
		var hd := RigSolver.HAND_R
		var local := _rel_xform(grip, sock)
		var p_bone: Vector3 = sock.transform * local.origin
		var p_rest: Vector3 = solver.rest_basis[hd] * p_bone
		solver.support_offset = p_rest
		solver.support_active = true
		motion.has_support_grip = true
		return


func _rel_xform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _refresh_lod() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam == null:
		lod = 0
		return
	var d := cam.global_position.distance_to(global_position)
	if d < 7.0:
		lod = 0
		return
	var visible_now := cam.is_position_in_frustum(global_position + Vector3(0, 0.9, 0))
	if not visible_now:
		lod = 2
	elif d < LOD_NEAR:
		lod = 0
	elif d < LOD_MID:
		lod = 1
	else:
		lod = 2


func _exit_tree() -> void:
	# freed / queued for deletion: release the physics bodies now (a plain reparent keeps the ragdoll running)
	if _ragdoll != null and is_queued_for_deletion():
		_ragdoll.destroy()
		_ragdoll = null
