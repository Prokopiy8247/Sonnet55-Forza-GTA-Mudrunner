class_name VehicleLights
extends RefCounted
## Headlights / tail + brake + reverse lights / police-ambulance-fire siren flashing for one vehicle.
## Emissive lamp materials are SHARED (VehicleMaterials.lamp) and swapped per surface on state change only.
## Real SpotLight3D/OmniLight3D nodes exist only for vehicles near the camera (VehicleSystem enables them via set_dynamic_lights).

var v: VehicleBase = null
var _surfs := {&"head": [], &"tail": [], &"amber": [], &"red": [], &"blue": []}
var _state := {&"head": &"", &"tail": &"", &"amber": &"", &"red": &"", &"blue": &""}
var _head_pos: Array[Vector3] = []
var _tail_pos: Array[Vector3] = []
var _siren_pos := Vector3(0, 1.7, -0.3)
var _has_siren_bar := false
var _spots: Array[SpotLight3D] = []
var _siren_lights: Array[OmniLight3D] = []
var _dynamic := false
var _siren_t := 0.0
var _xenon := false
var _wrecked := false
var _blink_t := 0.0


func setup(vehicle: VehicleBase) -> void:
	v = vehicle
	var model: Node3D = v.model
	if model == null:
		return
	for mi in ModelLib.meshes(model):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null:
				continue
			match m.resource_name:
				"LightHead": _surfs[&"head"].append([mi, i])
				"LightTail": _surfs[&"tail"].append([mi, i])
				"LightAmber": _surfs[&"amber"].append([mi, i])
				"LightRed": _surfs[&"red"].append([mi, i])
				"LightBlue": _surfs[&"blue"].append([mi, i])
	var hl: Variant = _find_pos(model, "HeadlightL")
	var hr: Variant = _find_pos(model, "HeadlightR")
	var hf: Variant = _find_pos(model, "HeadlightF")
	if hl != null and hr != null:
		_head_pos = [hl, hr]
	elif hf != null:
		_head_pos = [hf]
	var tl: Variant = _find_pos(model, "TaillightL")
	var tr_: Variant = _find_pos(model, "TaillightR")
	if tl != null and tr_ != null:
		_tail_pos = [tl, tr_]
	elif tr_ != null:
		_tail_pos = [tr_]
	var bar := model.find_child("SirenBar", true, false) as Node3D
	if bar != null:
		_siren_pos = Util._rel_transform(model, bar).origin
		_has_siren_bar = true
		v.set_meta("has_siren", true)
	if String(v.def.get("siren", "")) != "":
		v.set_meta("has_siren", true)
	if _head_pos.is_empty():
		var half := float(v.def.get("width", 1.8)) * 0.5 - 0.35
		var zf := -float(v.def.get("length", 4.5)) * 0.5 + 0.1
		_head_pos = [Vector3(-half, 0.65, zf), Vector3(half, 0.65, zf)]
	_set_state(&"head", &"off")
	_set_state(&"tail", &"off")
	_set_state(&"amber", &"off")
	_set_state(&"red", &"off")
	_set_state(&"blue", &"off")


static func _find_pos(model: Node3D, node_name: String) -> Variant:
	var n := model.find_child(node_name, true, false) as Node3D
	if n == null:
		return null
	return Util._rel_transform(model, n).origin


## Garage tint of a lamp kind (&"head" / &"tail"): Color with r < 0 restores the stock look.
var tints: Dictionary = {}


func set_tint(kind: StringName, color: Color) -> void:
	if color.r < 0.0:
		if not tints.has(kind):
			return
		tints.erase(kind)
	else:
		tints[kind] = color
	_state[kind] = &""                     # force the material swap on the next update()
	if kind == &"head":
		for s in _spots:
			s.light_color = color if color.r >= 0.0 else Color(1.0, 0.95, 0.82)


func _set_state(kind: StringName, state: StringName) -> void:
	if _state[kind] == state:
		return
	_state[kind] = state
	var mat: Material = VehicleMaterials.lamp(kind, state)
	if tints.has(kind):
		mat = VehicleMaterials.lamp_tinted(kind, state, tints[kind])
	for pair in _surfs[kind]:
		var mi: MeshInstance3D = pair[0]
		if is_instance_valid(mi):
			mi.set_surface_override_material(pair[1], mat)


func set_xenon(on: bool) -> void:
	_xenon = on
	_state[&"head"] = &""


func set_wrecked() -> void:
	_wrecked = true
	for k in [&"head", &"tail", &"amber", &"red", &"blue"]:
		_set_state(k, &"off")
	_apply_dynamic(false)


func repair() -> void:
	_wrecked = false


## Called every physics tick of the vehicle (cheap: compares small state ids).
func update(dt: float) -> void:
	if v == null or _wrecked or v.is_destroyed:
		return
	var head_on := v.headlights_on and (v.engine_on or v.driver != null or v.is_ai_controlled)
	_set_state(&"head", (&"xenon" if _xenon else &"on") if head_on else &"off")
	# tail lights
	var tail := &"off"
	if v.get("braking") == true:
		tail = &"brake"
	elif v.gear < 0 and v.engine_on:
		tail = &"reverse"
	elif head_on:
		tail = &"low"
	_set_state(&"tail", tail)
	# siren
	if v.siren_on:
		_siren_t += dt
		var ph := fposmod(_siren_t, 0.64)
		var red_on := (ph < 0.08) or (ph > 0.16 and ph < 0.24) or (ph > 0.32 and ph < 0.4)
		var blue_on := (ph > 0.4 and ph < 0.48) or (ph > 0.5 and ph < 0.58)
		var fire := String(v.def.get("siren", "")) == "fire"
		if fire:
			red_on = ph < 0.32
			blue_on = false
			_set_state(&"amber", &"on" if ph >= 0.32 else &"off")
		else:
			_set_state(&"amber", &"off")
		_set_state(&"red", &"on" if red_on else &"off")
		_set_state(&"blue", &"on" if blue_on else &"off")
		if _dynamic:
			_ensure_siren_lights()
			if _siren_lights.size() == 2:
				_siren_lights[0].visible = red_on
				_siren_lights[1].visible = blue_on or (fire and ph >= 0.32)
	elif _state[&"red"] != &"off" or _state[&"blue"] != &"off":
		_set_state(&"red", &"off")
		_set_state(&"blue", &"off")
		_set_state(&"amber", &"off")
		for l in _siren_lights:
			l.visible = false
	# head spotlights follow the state
	if _dynamic:
		var want := head_on
		if _spots.is_empty() and want:
			_create_spots()
		for s in _spots:
			s.visible = want


## Enables real light nodes (headlight spots, siren omni lights); VehicleSystem calls this for vehicles near the camera.
func set_dynamic_lights(enabled: bool) -> void:
	if _dynamic == enabled:
		return
	_dynamic = enabled
	_apply_dynamic(enabled)


func _apply_dynamic(enabled: bool) -> void:
	if not enabled:
		for s in _spots:
			s.visible = false
		for l in _siren_lights:
			l.visible = false


func _create_spots() -> void:
	if v == null or not is_instance_valid(v):
		return
	for p in _head_pos:
		var s := SpotLight3D.new()
		s.name = "HeadSpot"
		s.position = p + Vector3(0, 0.02, -0.15)
		s.rotation_degrees = Vector3(-4.0, 0, 0)
		s.spot_range = 42.0
		s.spot_angle = 30.0
		s.spot_angle_attenuation = 1.3
		s.light_energy = 3.2
		s.light_color = tints.get(&"head", Color(1.0, 0.95, 0.82))
		s.light_specular = 0.6
		s.shadow_enabled = false
		s.light_cull_mask = 0xFFFFF
		v.add_child(s)
		_spots.append(s)


func _ensure_siren_lights() -> void:
	if not _siren_lights.is_empty() or v == null:
		return
	var cols := [Color(1, 0.1, 0.08), Color(0.15, 0.35, 1.0)]
	var fire := String(v.def.get("siren", "")) == "fire"
	for i in 2:
		var o := OmniLight3D.new()
		o.name = "SirenLight%d" % i
		o.position = _siren_pos + Vector3((-0.35 if i == 0 else 0.35), 0.2, 0)
		o.omni_range = 13.0
		o.light_energy = 4.0
		o.light_color = (Color(1, 0.55, 0.1) if fire and i == 1 else cols[i])
		o.shadow_enabled = false
		o.visible = false
		v.add_child(o)
		_siren_lights.append(o)
