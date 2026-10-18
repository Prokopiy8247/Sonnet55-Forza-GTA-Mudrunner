class_name WeaponModel
extends Node3D
## Visual representation of one held weapon: Blender GLB (weapons/<id>.glb) or a clearly-logged code-built fallback,
## attachments (suppressor / scope / flashlight / grip / extended mag), tint, muzzle flash (mesh + short OmniLight),
## flashlight SpotLight3D and small procedural animations (recoil kick, slide / pump / bolt, reload dip, equip raise).
## Conventions: model origin = grip point, barrel along -Z (Godot forward), Muzzle node at the barrel tip.

static var _warned: Dictionary = {}
static var _fb_mats: Dictionary = {}

var weapon_id: StringName = &""
var def: Dictionary = {}
var is_fallback := false
var mods: Dictionary = {}
var tint: Color = Color(0, 0, 0, 0)

var pose: Node3D = null                # animation offset node (parent of the model root)
var model_root: Node3D = null
var muzzle: Node3D = null
var grip_l: Node3D = null
var eject: Node3D = null
var mounts: Dictionary = {}            # mount name -> Node3D
var parts: Dictionary = {}             # Slide / Magazine / Bolt / Pump / Trigger -> {"node": Node3D, "rest": Vector3}
var muzzle_local := Vector3(0, 0.05, -0.3)
var suppressor_len := 0.0

var _flash_root: Node3D = null
var _flash_light: OmniLight3D = null
var _flash_t := 0.0
var _flash_scale := 1.0
var _spot: SpotLight3D = null
var _spot_glow: MeshInstance3D = null
var _attach_nodes: Array[Node3D] = []
var _kick := 0.0
var _slide_t := 0.0
var _pump_t := 0.0
var _pump_dur := 0.0
var _reload_p := -1.0
var _equip_p := 1.0
var _orig_mats: Dictionary = {}        # MeshInstance3D -> Array of override materials before tinting


# ================================================================================================= creation
static func create(id: StringName, p_mods: Dictionary = {}, p_tint: Color = Color(0, 0, 0, 0)) -> WeaponModel:
	var wm := WeaponModel.new()
	wm.name = "WeaponModel_" + String(id)
	wm.weapon_id = id
	wm.def = WeaponDefs.get_def(id)
	wm._build()
	wm.set_mods(p_mods, false)
	wm.set_tint(p_tint)
	return wm


func _build() -> void:
	pose = Node3D.new()
	pose.name = "Pose"
	add_child(pose)
	var rel: String = def.get("model", "")
	var inst: Node3D = null
	if rel != "" and ModelLib.exists(rel):
		inst = ModelLib.instance(rel)
	if inst == null:
		is_fallback = true
		if rel != "" and not _warned.has(weapon_id):
			_warned[weapon_id] = true
			push_warning("WeaponModel: FALLBACK code-built shape for '%s' (missing %s)" % [weapon_id, ModelLib.path(rel)])
		inst = _build_fallback()
	model_root = inst
	pose.add_child(inst)
	_find_nodes()
	_build_flash()


func _find_nodes() -> void:
	muzzle = model_root.find_child("Muzzle", true, false) as Node3D
	grip_l = model_root.find_child("Grip_L", true, false) as Node3D
	eject = model_root.find_child("Eject", true, false) as Node3D
	for mname in ["AttMuzzle", "AttOptic", "AttRail", "AttGrip", "AttMag"]:
		var n := model_root.find_child(mname, true, false) as Node3D
		if n != null:
			mounts[StringName(mname)] = n
	for pname in ["Slide", "Magazine", "Bolt", "Pump", "Trigger"]:
		var n2 := model_root.find_child(pname, true, false) as Node3D
		if n2 != null:
			parts[StringName(pname)] = {"node": n2, "rest": n2.position}
	var length: float = float(def.get("length", 0.3))
	if muzzle != null:
		muzzle_local = _rel_pos(muzzle)
	else:
		muzzle_local = Vector3(0, 0.04, -length * 0.62)
		var mk := Node3D.new()
		mk.name = "Muzzle"
		mk.position = muzzle_local
		model_root.add_child(mk)
		muzzle = mk
	# default mounts for models that do not provide every attachment empty
	var bb_top := 0.075
	if not mounts.has(&"AttMuzzle"):
		mounts[&"AttMuzzle"] = _make_mount("AttMuzzle", muzzle_local)
	if not mounts.has(&"AttOptic"):
		mounts[&"AttOptic"] = _make_mount("AttOptic", Vector3(0, bb_top, muzzle_local.z * 0.25))
	if not mounts.has(&"AttRail"):
		mounts[&"AttRail"] = _make_mount("AttRail", Vector3(0, 0.0, muzzle_local.z * 0.75))
	if not mounts.has(&"AttGrip"):
		mounts[&"AttGrip"] = _make_mount("AttGrip", Vector3(0, -0.02, muzzle_local.z * 0.55))
	if not mounts.has(&"AttMag"):
		mounts[&"AttMag"] = _make_mount("AttMag", Vector3(0, -0.05, -0.05))


func _make_mount(mname: String, p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = mname
	n.position = p
	model_root.add_child(n)
	return n


## Position of a node relative to the Pose node (works before the model is inside the tree).
func _rel_pos(node: Node3D) -> Vector3:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != pose:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf.origin


# ================================================================================================= muzzle flash
func _build_flash() -> void:
	_flash_root = Node3D.new()
	_flash_root.name = "MuzzleFlash"
	_flash_root.position = muzzle_local
	_flash_root.visible = false
	pose.add_child(_flash_root)
	var flen := 0.42
	var wid := 0.2
	var hb := Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0))
	var vb := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	for bs in [hb, vb]:
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(flen, wid)
		m.mesh = q
		m.material_override = FxRes.flash_mat()
		m.transform = Transform3D(bs, Vector3(0, 0, -flen * 0.5))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flash_root.add_child(m)
	var star := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.28, 0.28)
	star.mesh = sq
	star.material_override = FxRes.star_mat()
	star.position = Vector3(0, 0, -0.03)
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_root.add_child(star)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.78, 0.45)
	_flash_light.light_energy = 3.0
	_flash_light.omni_range = 7.5
	_flash_light.shadow_enabled = false
	_flash_light.position = Vector3(0, 0, -0.18)
	_flash_root.add_child(_flash_light)
	set_process(false)


## Short muzzle flash. scale 1.0 = weapon default (def.flash); suppressed weapons pass a small scale.
func flash(power: float = 1.0) -> void:
	var s := power * float(def.get("flash", 1.0))
	if s <= 0.02 or _flash_root == null:
		return
	_flash_scale = s
	_flash_root.position = muzzle_local + Vector3(0, 0, -suppressor_len)
	_flash_root.scale = Vector3.ONE * s * randf_range(0.85, 1.2)
	_flash_root.rotation = Vector3(0, 0, randf() * TAU)
	_flash_light.light_energy = 2.2 + 1.6 * minf(s, 1.6)
	_flash_light.omni_range = 5.5 + 3.0 * minf(s, 1.6)
	_flash_root.visible = true
	_flash_t = 0.05
	set_process(true)


func kick(amount: float = 1.0) -> void:
	_kick = minf(_kick + amount, 1.6)
	_slide_t = 0.09
	set_process(true)


## Pump / bolt cycle animation of duration `dur` seconds.
func cycle_action(dur: float) -> void:
	_pump_t = dur
	_pump_dur = maxf(dur, 0.05)
	set_process(true)


## 0..1 while reloading, -1 when idle.
func set_reload_progress(p: float) -> void:
	_reload_p = p
	set_process(true)
	_apply_pose()


## 0..1 raise progress (1 = ready).
func set_equip_progress(p: float) -> void:
	_equip_p = p
	set_process(true)
	_apply_pose()


func _process(delta: float) -> void:
	var busy := false
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash_root.visible = false
		else:
			busy = true
	if _kick > 0.001:
		_kick = maxf(_kick - delta * 9.0, 0.0)
		busy = true
	if _slide_t > 0.0:
		_slide_t -= delta
		busy = true
	if _pump_t > 0.0:
		_pump_t = maxf(_pump_t - delta, 0.0)
		busy = true
	if _reload_p >= 0.0 or _equip_p < 1.0:
		busy = true
	_apply_pose()
	_animate_parts()
	if not busy:
		set_process(false)


func _apply_pose() -> void:
	if pose == null:
		return
	var k := _kick
	var pos := Vector3(0, 0, 0.045 * k)
	var rx := 0.07 * k
	if _equip_p < 1.0:
		var e := 1.0 - pow(1.0 - clampf(_equip_p, 0.0, 1.0), 2.0)
		rx += lerpf(-1.0, 0.0, e)
		pos += Vector3(0, lerpf(-0.12, 0.0, e), 0)
	if _reload_p >= 0.0:
		var s := sin(clampf(_reload_p, 0.0, 1.0) * PI)
		rx += -0.45 * s
		pos += Vector3(0.0, -0.05 * s, 0.03 * s)
	pose.position = pos
	pose.rotation = Vector3(rx, 0, 0)


func _animate_parts() -> void:
	if parts.has(&"Slide"):
		var pr: Dictionary = parts[&"Slide"]
		var off := 0.032 * clampf(_slide_t / 0.09, 0.0, 1.0) if _slide_t > 0.0 else 0.0
		(pr["node"] as Node3D).position = (pr["rest"] as Vector3) + Vector3(0, 0, off)
	for pname in [&"Pump", &"Bolt"]:
		if parts.has(pname):
			var pp: Dictionary = parts[pname]
			var off2 := 0.0
			if _pump_t > 0.0:
				var u := 1.0 - _pump_t / _pump_dur
				off2 = sin(u * PI) * (0.075 if pname == &"Pump" else 0.06)
			(pp["node"] as Node3D).position = (pp["rest"] as Vector3) + Vector3(0, 0, off2)
	if parts.has(&"Magazine"):
		var pm: Dictionary = parts[&"Magazine"]
		var drop := 0.0
		if _reload_p >= 0.0:
			var u2 := clampf(_reload_p, 0.0, 1.0)
			drop = 0.16 * (smoothstep(0.1, 0.3, u2) - smoothstep(0.55, 0.8, u2))
		(pm["node"] as Node3D).position = (pm["rest"] as Vector3) + Vector3(0, -drop, 0)


# ================================================================================================= queries
func muzzle_world() -> Vector3:
	if not is_inside_tree():
		return global_position
	return pose.global_transform * (muzzle_local + Vector3(0, 0, -suppressor_len))


func forward_world() -> Vector3:
	return -pose.global_transform.basis.z.normalized()


func eject_world() -> Vector3:
	if eject != null and eject.is_inside_tree():
		return eject.global_position
	return pose.global_transform * (Vector3(0.02, 0.05, muzzle_local.z * 0.35))


func right_world() -> Vector3:
	return pose.global_transform.basis.x.normalized()


# ================================================================================================= mods / tint / light
func set_mods(p_mods: Dictionary, rebuild_light: bool = true) -> void:
	mods = p_mods.duplicate()
	for n in _attach_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_attach_nodes.clear()
	suppressor_len = 0.0
	if _spot != null:
		_spot.queue_free()
		_spot = null
		_spot_glow = null
	for mod_id in WeaponMods.MOD_ORDER:
		if not mods.get(mod_id, false):
			continue
		var md: Dictionary = WeaponMods.get_mod(mod_id)
		var mount: Node3D = mounts.get(md["mount"], null)
		if mount == null:
			continue
		var att: Node3D = null
		var rel: String = md["model"]
		if ModelLib.exists(rel):
			att = ModelLib.instance(rel)
		if att == null:
			att = _build_att_fallback(mod_id)
			if not _warned.has(StringName("att_" + String(mod_id))):
				_warned[StringName("att_" + String(mod_id))] = true
				push_warning("WeaponModel: FALLBACK attachment shape for '%s' (missing %s)" % [mod_id, ModelLib.path(rel)])
		mount.add_child(att)
		_attach_nodes.append(att)
		if mod_id == &"suppressor":
			suppressor_len = float(md.get("length", 0.17))
		if mod_id == &"flashlight":
			_make_spot(mount)
	set_tint(tint)


func _make_spot(mount: Node3D) -> void:
	_spot = SpotLight3D.new()
	_spot.name = "Flashlight"
	_spot.spot_range = 30.0
	_spot.spot_angle = 30.0
	_spot.spot_angle_attenuation = 1.4
	_spot.light_energy = 6.0
	_spot.light_color = Color(1.0, 0.96, 0.85)
	_spot.shadow_enabled = false
	_spot.position = Vector3(0, 0, -0.06)
	_spot.visible = false
	mount.add_child(_spot)
	_attach_nodes.append(_spot)
	_spot_glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	_spot_glow.mesh = q
	_spot_glow.material_override = FxRes.glow_mat(Color(1.0, 0.97, 0.85, 0.9))
	_spot_glow.position = Vector3(0, 0, -0.07)
	_spot_glow.visible = false
	_spot_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mount.add_child(_spot_glow)
	_attach_nodes.append(_spot_glow)


func has_flashlight() -> bool:
	return _spot != null


func set_flashlight(on: bool) -> void:
	if _spot != null:
		_spot.visible = on
		_spot_glow.visible = on


func is_flashlight_on() -> bool:
	return _spot != null and _spot.visible


## Cosmetic finish: replaces the "Gun" body material (and "GunLight") with a tinted copy. Alpha 0 = factory finish.
func set_tint(c: Color) -> void:
	tint = c
	if model_root == null:
		return
	for mi in ModelLib.meshes(model_root):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null:
				continue
			var mname := m.resource_name
			if mname != "Gun" and mname != "GunLight" and mname != "Tint" and mname != "Paint":
				continue
			if c.a <= 0.01:
				if mi.get_surface_override_material(i) != null and mi.has_meta(&"tinted"):
					mi.set_surface_override_material(i, null)
				continue
			var base: Material = mi.mesh.surface_get_material(i)
			var tm: StandardMaterial3D
			if base is StandardMaterial3D:
				tm = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				tm = StandardMaterial3D.new()
				tm.roughness = 0.55
				tm.metallic = 0.35
			var shade := 1.0 if mname != "GunLight" else 1.25
			tm.albedo_color = Color(c.r * shade, c.g * shade, c.b * shade, 1.0)
			tm.resource_name = mname
			mi.set_surface_override_material(i, tm)
			mi.set_meta(&"tinted", true)


# ================================================================================================= fallback shapes
static func _fb_mat(key: String) -> StandardMaterial3D:
	if _fb_mats.has(key):
		return _fb_mats[key]
	var m := StandardMaterial3D.new()
	m.roughness = 0.55
	match key:
		"gun":
			m.albedo_color = Color(0.18, 0.19, 0.22)
			m.metallic = 0.55
			m.roughness = 0.4
			m.resource_name = "Gun"
		"metal":
			m.albedo_color = Color(0.55, 0.58, 0.62)
			m.metallic = 0.8
			m.roughness = 0.3
			m.resource_name = "Metal"
		"dark":
			m.albedo_color = Color(0.07, 0.07, 0.08)
			m.resource_name = "MetalDark"
		"grip":
			m.albedo_color = Color(0.1, 0.1, 0.11)
			m.roughness = 0.9
			m.resource_name = "Grip"
		"wood":
			m.albedo_color = Color(0.5, 0.33, 0.2)
			m.roughness = 0.8
			m.resource_name = "Wood"
		"olive":
			m.albedo_color = Color(0.3, 0.34, 0.2)
			m.resource_name = "Gun"
		"accent":
			m.albedo_color = Color(1.0, 0.24, 0.6)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.24, 0.6)
			m.emission_energy_multiplier = 0.8
			m.resource_name = "Trim"
		"glass":
			m.albedo_color = Color(0.2, 0.9, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.2, 0.9, 1.0)
			m.emission_energy_multiplier = 1.2
			m.resource_name = "LampGlow"
		_:
			m.albedo_color = Color(0.3, 0.3, 0.3)
	_fb_mats[key] = m
	return m


static func _part(parent: Node3D, shape: String, size: Vector3, pos: Vector3, mat: String, rot_deg: Vector3 = Vector3.ZERO, pname: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if shape == "cyl":
		var c := CylinderMesh.new()
		c.top_radius = size.x
		c.bottom_radius = size.z if size.z > 0.0 else size.x
		c.height = size.y
		c.radial_segments = 8
		c.rings = 1
		mi.mesh = c
	elif shape == "cone":
		var c2 := CylinderMesh.new()
		c2.top_radius = 0.001
		c2.bottom_radius = size.x
		c2.height = size.y
		c2.radial_segments = 8
		c2.rings = 1
		mi.mesh = c2
	elif shape == "sphere":
		var s := SphereMesh.new()
		s.radius = size.x
		s.height = size.x * 2.0
		s.radial_segments = 10
		s.rings = 5
		mi.mesh = s
	else:
		var b := BoxMesh.new()
		b.size = size
		mi.mesh = b
	mi.material_override = _fb_mat(mat)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if pname != "":
		mi.name = pname
	parent.add_child(mi)
	return mi


## Barrel-like cylinder lying along -Z (rotated 90 deg about X). size = (radius, length, radius_end_or_0).
static func _tube(parent: Node3D, radius: float, length: float, pos: Vector3, mat: String, radius_end: float = 0.0, pname: String = "") -> MeshInstance3D:
	return _part(parent, "cyl", Vector3(radius, length, radius_end), pos, mat, Vector3(90, 0, 0), pname)


func _build_fallback() -> Node3D:
	var r := Node3D.new()
	r.name = "FallbackModel"
	r.set_meta(&"fallback", true)
	var id := weapon_id
	match id:
		&"pistol":
			_part(r, "box", Vector3(0.03, 0.034, 0.17), Vector3(0, 0.05, -0.05), "gun", Vector3.ZERO, "Slide")
			_part(r, "box", Vector3(0.028, 0.024, 0.13), Vector3(0, 0.022, -0.04), "dark")
			_part(r, "box", Vector3(0.028, 0.09, 0.045), Vector3(0, -0.035, 0.015), "grip", Vector3(-12, 0, 0))
			_part(r, "box", Vector3(0.012, 0.03, 0.012), Vector3(0, 0.005, -0.02), "dark")
			_part(r, "box", Vector3(0.026, 0.07, 0.035), Vector3(0, -0.06, 0.01), "dark", Vector3(-12, 0, 0), "Magazine")
		&"revolver":
			_part(r, "box", Vector3(0.034, 0.05, 0.12), Vector3(0, 0.035, -0.035), "gun")
			_tube(r, 0.012, 0.17, Vector3(0, 0.056, -0.175), "metal")
			_tube(r, 0.027, 0.06, Vector3(0, 0.045, -0.06), "metal", 0.0)
			_part(r, "box", Vector3(0.03, 0.095, 0.05), Vector3(0, -0.035, 0.02), "wood", Vector3(-14, 0, 0))
		&"smg":
			_part(r, "box", Vector3(0.046, 0.07, 0.28), Vector3(0, 0.04, -0.1), "gun")
			_part(r, "box", Vector3(0.026, 0.14, 0.036), Vector3(0, -0.08, -0.09), "dark", Vector3.ZERO, "Magazine")
			_part(r, "box", Vector3(0.03, 0.09, 0.042), Vector3(0, -0.04, 0.02), "grip", Vector3(-10, 0, 0))
			_tube(r, 0.016, 0.14, Vector3(0, 0.052, -0.29), "metal")
			_part(r, "box", Vector3(0.012, 0.012, 0.18), Vector3(0, 0.045, 0.23), "dark")
			_part(r, "box", Vector3(0.016, 0.02, 0.03), Vector3(0, 0.083, -0.05), "metal")
		&"shotgun_pump":
			_tube(r, 0.014, 0.62, Vector3(0, 0.055, -0.4), "metal")
			_tube(r, 0.012, 0.46, Vector3(0, 0.025, -0.33), "gun")
			_part(r, "box", Vector3(0.042, 0.065, 0.22), Vector3(0, 0.04, -0.02), "gun")
			_part(r, "box", Vector3(0.046, 0.042, 0.15), Vector3(0, 0.012, -0.3), "wood", Vector3.ZERO, "Pump")
			_part(r, "box", Vector3(0.042, 0.1, 0.3), Vector3(0, -0.005, 0.24), "wood", Vector3(-8, 0, 0))
		&"shotgun_auto":
			_tube(r, 0.016, 0.52, Vector3(0, 0.055, -0.36), "metal")
			_part(r, "box", Vector3(0.05, 0.075, 0.3), Vector3(0, 0.04, -0.04), "gun")
			_tube(r, 0.05, 0.07, Vector3(0, -0.05, -0.1), "dark", 0.0, "Magazine")
			_part(r, "box", Vector3(0.04, 0.045, 0.18), Vector3(0, 0.02, -0.28), "grip")
			_part(r, "box", Vector3(0.04, 0.09, 0.28), Vector3(0, 0.0, 0.25), "grip", Vector3(-8, 0, 0))
		&"rifle_assault":
			_part(r, "box", Vector3(0.046, 0.072, 0.34), Vector3(0, 0.04, -0.06), "gun")
			_tube(r, 0.011, 0.36, Vector3(0, 0.056, -0.52), "metal")
			_part(r, "box", Vector3(0.042, 0.05, 0.3), Vector3(0, 0.045, -0.33), "dark")
			_part(r, "box", Vector3(0.03, 0.14, 0.05), Vector3(0, -0.08, -0.08), "dark", Vector3(8, 0, 0), "Magazine")
			_part(r, "box", Vector3(0.03, 0.09, 0.04), Vector3(0, -0.04, 0.04), "grip", Vector3(-12, 0, 0))
			_part(r, "box", Vector3(0.04, 0.085, 0.27), Vector3(0, 0.02, 0.27), "grip")
			_part(r, "box", Vector3(0.012, 0.03, 0.03), Vector3(0, 0.092, -0.05), "metal")
		&"carbine":
			_part(r, "box", Vector3(0.044, 0.07, 0.3), Vector3(0, 0.04, -0.05), "gun")
			_tube(r, 0.011, 0.26, Vector3(0, 0.056, -0.43), "metal")
			_part(r, "box", Vector3(0.04, 0.048, 0.22), Vector3(0, 0.045, -0.28), "dark")
			_part(r, "box", Vector3(0.03, 0.13, 0.045), Vector3(0, -0.075, -0.06), "dark", Vector3(8, 0, 0), "Magazine")
			_part(r, "box", Vector3(0.03, 0.09, 0.04), Vector3(0, -0.04, 0.04), "grip", Vector3(-12, 0, 0))
			_part(r, "box", Vector3(0.012, 0.012, 0.22), Vector3(0, 0.03, 0.2), "dark")
		&"rifle_marksman":
			_part(r, "box", Vector3(0.046, 0.075, 0.4), Vector3(0, 0.04, -0.06), "gun")
			_tube(r, 0.012, 0.5, Vector3(0, 0.058, -0.62), "metal")
			_part(r, "box", Vector3(0.044, 0.052, 0.34), Vector3(0, 0.045, -0.4), "dark")
			_tube(r, 0.022, 0.2, Vector3(0, 0.1, -0.1), "dark")
			_part(r, "box", Vector3(0.03, 0.1, 0.05), Vector3(0, -0.07, -0.05), "dark", Vector3.ZERO, "Magazine")
			_part(r, "box", Vector3(0.03, 0.09, 0.04), Vector3(0, -0.04, 0.05), "grip", Vector3(-12, 0, 0))
			_part(r, "box", Vector3(0.042, 0.1, 0.3), Vector3(0, 0.015, 0.3), "grip")
		&"sniper":
			_part(r, "box", Vector3(0.044, 0.075, 0.42), Vector3(0, 0.04, -0.05), "gun")
			_tube(r, 0.014, 0.75, Vector3(0, 0.058, -0.77), "metal")
			_tube(r, 0.028, 0.34, Vector3(0, 0.115, -0.1), "dark")
			_tube(r, 0.036, 0.04, Vector3(0, 0.115, -0.26), "dark", 0.028)
			_part(r, "box", Vector3(0.012, 0.014, 0.05), Vector3(0.036, 0.062, 0.02), "metal", Vector3.ZERO, "Bolt")
			_part(r, "box", Vector3(0.045, 0.11, 0.38), Vector3(0, 0.0, 0.33), "wood", Vector3(-6, 0, 0))
			_part(r, "box", Vector3(0.03, 0.04, 0.06), Vector3(0, -0.05, -0.1), "dark", Vector3.ZERO, "Magazine")
		&"rocket_launcher":
			_tube(r, 0.058, 1.0, Vector3(0, 0.1, -0.15), "olive")
			_tube(r, 0.075, 0.1, Vector3(0, 0.1, -0.7), "dark", 0.058)
			_tube(r, 0.07, 0.12, Vector3(0, 0.1, 0.38), "dark", 0.095)
			_part(r, "box", Vector3(0.032, 0.11, 0.05), Vector3(0, 0.0, 0.0), "grip", Vector3(-8, 0, 0))
			_part(r, "box", Vector3(0.03, 0.09, 0.04), Vector3(0, 0.0, -0.3), "grip")
			_part(r, "box", Vector3(0.03, 0.05, 0.08), Vector3(0.05, 0.18, -0.1), "metal")
		&"grenade_launcher":
			_part(r, "box", Vector3(0.06, 0.08, 0.3), Vector3(0, 0.04, -0.05), "gun")
			_tube(r, 0.03, 0.34, Vector3(0, 0.06, -0.35), "metal")
			_tube(r, 0.058, 0.1, Vector3(0, 0.05, -0.08), "dark", 0.0, "Magazine")
			_part(r, "box", Vector3(0.03, 0.09, 0.04), Vector3(0, -0.04, 0.03), "grip", Vector3(-12, 0, 0))
			_part(r, "box", Vector3(0.04, 0.09, 0.22), Vector3(0, 0.0, 0.24), "grip")
		&"grenade":
			_part(r, "sphere", Vector3(0.036, 0, 0), Vector3(0, 0.0, 0), "olive")
			_part(r, "box", Vector3(0.012, 0.014, 0.05), Vector3(0, 0.04, 0.008), "metal")
			_part(r, "box", Vector3(0.02, 0.01, 0.02), Vector3(0, 0.036, 0.0), "metal")
		&"knife":
			_part(r, "box", Vector3(0.007, 0.03, 0.17), Vector3(0, 0.0, -0.13), "metal")
			_part(r, "box", Vector3(0.022, 0.034, 0.012), Vector3(0, 0.0, -0.04), "dark")
			_part(r, "box", Vector3(0.022, 0.03, 0.11), Vector3(0, 0.0, 0.02), "grip")
		&"bat":
			_part(r, "cyl", Vector3(0.036, 0.9, 0.016), Vector3(0, 0.0, -0.4), "wood", Vector3(-90, 0, 0))
			_part(r, "cyl", Vector3(0.018, 0.1, 0.018), Vector3(0, 0.0, 0.1), "grip", Vector3(-90, 0, 0))
		&"crowbar":
			_part(r, "cyl", Vector3(0.012, 0.66, 0.012), Vector3(0, 0.0, -0.28), "metal", Vector3(-90, 0, 0))
			_part(r, "box", Vector3(0.016, 0.016, 0.1), Vector3(0, -0.04, -0.62), "metal", Vector3(35, 0, 0))
			_part(r, "box", Vector3(0.02, 0.018, 0.05), Vector3(0, 0.0, 0.08), "metal")
		_:
			_part(r, "box", Vector3(0.04, 0.06, 0.3), Vector3(0, 0.03, -0.1), "gun")
	# anchors the code expects
	var length: float = float(def.get("length", 0.3))
	var m_z := -length * 0.62
	match id:
		&"pistol": m_z = -0.14
		&"revolver": m_z = -0.265
		&"smg": m_z = -0.37
		&"shotgun_pump": m_z = -0.72
		&"shotgun_auto": m_z = -0.63
		&"rifle_assault": m_z = -0.7
		&"carbine": m_z = -0.56
		&"rifle_marksman": m_z = -0.87
		&"sniper": m_z = -1.15
		&"rocket_launcher": m_z = -0.66
		&"grenade_launcher": m_z = -0.52
		&"grenade": m_z = -0.04
	var mk := Node3D.new()
	mk.name = "Muzzle"
	var my := 0.056
	if id == &"pistol":
		my = 0.05
	elif id == &"rocket_launcher":
		my = 0.1
	elif id == &"grenade":
		my = 0.0
	mk.position = Vector3(0, my, m_z)
	r.add_child(mk)
	var gl := Node3D.new()
	gl.name = "Grip_L"
	gl.position = Vector3(0, 0.0, m_z * 0.5)
	r.add_child(gl)
	var ej := Node3D.new()
	ej.name = "Eject"
	ej.position = Vector3(0.025, 0.06, m_z * 0.18)
	r.add_child(ej)
	return r


func _build_att_fallback(mod_id: StringName) -> Node3D:
	var n := Node3D.new()
	n.name = "FallbackAtt_" + String(mod_id)
	n.set_meta(&"fallback", true)
	match mod_id:
		&"suppressor":
			_tube(n, 0.021, 0.17, Vector3(0, 0, -0.085), "dark")
			_tube(n, 0.023, 0.012, Vector3(0, 0, -0.17), "metal")
		&"scope":
			_tube(n, 0.02, 0.17, Vector3(0, 0.03, 0), "dark")
			_tube(n, 0.026, 0.03, Vector3(0, 0.03, -0.09), "dark", 0.02)
			_tube(n, 0.026, 0.03, Vector3(0, 0.03, 0.09), "dark", 0.02)
			_part(n, "box", Vector3(0.014, 0.03, 0.04), Vector3(0, 0.008, 0.0), "metal")
			_part(n, "box", Vector3(0.012, 0.012, 0.004), Vector3(0, 0.03, -0.108), "glass")
		&"flashlight":
			_tube(n, 0.016, 0.07, Vector3(0, -0.012, -0.03), "dark")
			_tube(n, 0.019, 0.012, Vector3(0, -0.012, -0.07), "metal")
			_part(n, "box", Vector3(0.026, 0.01, 0.01), Vector3(0, -0.012, -0.073), "glass")
		&"grip":
			_part(n, "box", Vector3(0.026, 0.085, 0.032), Vector3(0, -0.055, 0), "grip", Vector3(10, 0, 0))
		&"magazine_ext":
			_part(n, "box", Vector3(0.028, 0.09, 0.038), Vector3(0, -0.045, 0), "dark")
	return n
