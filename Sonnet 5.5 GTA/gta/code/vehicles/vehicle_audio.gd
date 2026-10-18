class_name VehicleAudio
extends RefCounted
## Engine / skid / siren / horn / impact audio hooks for one vehicle. Engine loops only exist while the engine runs and
## the vehicle is near the camera (VehicleSystem sets visual_lod = 1 for far vehicles, which stops the update).
## Everything is null-safe: a missing sound id or a stub EngineSound is silently skipped.

var v: VehicleBase = null
var engine: Node = null
var skid: AudioStreamPlayer3D = null
var siren: AudioStreamPlayer3D = null
var _profile: StringName = &""
var _skid_vol := -40.0
var _t := 0.0


func setup(vehicle: VehicleBase) -> void:
	v = vehicle
	_profile = StringName(v.def.get("engine", &""))


func update(dt: float) -> void:
	if v == null or not v.is_inside_tree():
		return
	_t += dt
	# ---- engine -----------------------------------------------------------------------------------------------------
	if v.engine_on and _profile != &"" and not v.is_destroyed:
		if engine == null:
			engine = EngineSound.create(_profile)
			if engine != null:
				engine.name = "EngineSound"
				v.add_child(engine)
				if engine.has_method("start"):
					engine.start()
		if engine != null and engine.has_method("update"):
			var eng_load := clampf(v.input_throttle if v.get_forward_speed() > -1.0 or v.gear < 0 else 0.4, 0.0, 1.0)
			if v.has_method("get_engine_load"):
				eng_load = v.get_engine_load()          # aircraft / boats report their own load (collective, throttle)
			engine.update(v.get_rpm01(), eng_load)
	elif engine != null:
		_drop_engine()
	# ---- skid -----------------------------------------------------------------------------------------------------------
	var sk: float = v.skid_level if v.get("skid_level") != null else 0.0
	if sk > 0.2 and v.get_speed() > 3.0:
		if skid == null:
			skid = _make_loop(&"skid")
		if skid != null:
			skid.volume_db = lerpf(-22.0, 0.0, clampf((sk - 0.2) * 1.4, 0.0, 1.0))
			skid.pitch_scale = lerpf(0.85, 1.25, clampf(v.get_speed() / 35.0, 0.0, 1.0))
			if not skid.playing:
				skid.play()
	elif skid != null and skid.playing:
		skid.stop()
	# ---- siren ------------------------------------------------------------------------------------------------------------
	if v.siren_on and not v.is_destroyed:
		if siren == null:
			var kind := String(v.def.get("siren", "police"))
			siren = _make_loop(StringName("siren_" + (kind if kind != "" else "police")))
		if siren != null and not siren.playing:
			siren.play()
	elif siren != null and siren.playing:
		siren.stop()


func _make_loop(sound_id: StringName) -> AudioStreamPlayer3D:
	if not Sfx.has_sound(sound_id):
		return null
	if Sfx.has_method("create_player_3d"):
		var sp: AudioStreamPlayer3D = Sfx.create_player_3d(sound_id, v, 0.0, 90.0, false)
		if sp != null:
			sp.finished.connect(func() -> void:
				if is_instance_valid(sp) and ((sp == skid and v.skid_level > 0.2) or (sp == siren and v.siren_on)):
					sp.play())
			return sp
	var s: AudioStream = Sfx.get_stream(sound_id)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.max_distance = 90.0
	p.unit_size = 8.0
	p.bus = &"Master"
	v.add_child(p)
	p.finished.connect(func() -> void:
		if is_instance_valid(p) and ((p == skid and v.skid_level > 0.2) or (p == siren and v.siren_on)):
			p.play())
	return p


func _drop_engine() -> void:
	if engine != null:
		if engine.has_method("stop"):
			engine.stop()
		engine.queue_free()
		engine = null
	if skid != null and skid.playing:
		skid.stop()


## Far vehicles / pooled vehicles: release every audio node.
func release() -> void:
	_drop_engine()
	if skid != null:
		skid.queue_free()
		skid = null
	if siren != null:
		siren.queue_free()
		siren = null


func _snd(id: StringName, db: float = 0.0, pitch: float = 1.0, dist: float = 70.0) -> void:
	if v != null and v.is_inside_tree() and Sfx.has_sound(id):
		Sfx.play_3d(id, v.global_position, db, pitch, dist, v)


func play_ignition() -> void:
	_snd(&"ignition", -2.0)


func play_engine_off() -> void:
	_snd(&"engine_off", -4.0)


func play_horn() -> void:
	var id: StringName = StringName(v.def.get("horn", &"horn_car"))
	var pitch := 1.0
	if v.has_meta(&"horn_sound"):       # garage horn style (VehicleModsVisual sets the meta from mods["horn"])
		id = StringName(v.get_meta(&"horn_sound"))
		pitch = float(v.get_meta(&"horn_pitch", 1.0))
	elif v.mods.has("horn"):
		pitch = 1.0 + float(v.mods.get("horn", 0)) * 0.08
	_snd(id, 0.0, pitch, 120.0)


func play_door(open: bool) -> void:
	_snd(&"door_vehicle_open" if open else &"door_vehicle_close", -4.0, 1.0, 30.0)


func play_impact(impact: float) -> void:
	if impact > 10.0:
		_snd(&"crash_heavy", minf(impact * 0.2 - 2.0, 4.0), randf_range(0.9, 1.05), 110.0)
	else:
		_snd(&"crash_light", minf(impact * 0.4 - 4.0, 2.0), randf_range(0.9, 1.1), 80.0)


func play_thud() -> void:
	_snd(&"hit_metal", -4.0, randf_range(0.7, 0.9), 40.0)


func play_burst() -> void:
	_snd(&"hit_metal", -2.0, 1.4, 40.0)


func play_splash(big: bool) -> void:
	_snd(&"splash_big" if big else &"splash", 0.0, 1.0, 80.0)


func on_destroyed() -> void:
	release()
	_snd(&"explosion_big", 2.0, randf_range(0.95, 1.05), 220.0)
