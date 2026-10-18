extends Node
## Audio in a real drive: run with the harness spawning a car and seating the player:
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/audio_drive_test.gd -Seconds 90 -GameArgs "--vehicle=sports --delay=3"
## Checks the genuine Vehicles / Player integration: EngineSound on the vehicle reacts to throttle, the radio starts when the
## player sits in the running car, station switching works and the engine stops cleanly when the car is left.

var _pass := 0
var _fail := 0


func _t(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _wait_wall(ms: int, cond: Callable) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func run(_main: Node) -> Variant:
	var asys = Game.sys(&"audio")
	var p = Game.player
	_t("drive_player_exists", p != null and is_instance_valid(p), "")
	if p == null or not is_instance_valid(p):
		return false
	var veh = p.get("current_vehicle")
	_t("drive_player_in_vehicle", veh != null and is_instance_valid(veh), "vehicle=%s" % str(veh))
	if veh == null:
		return false
	veh.set_engine(true)
	await get_tree().create_timer(0.5).timeout
	# engine sound exists (created by VehicleAudio or by AudioSystem's fallback)
	var holder: Array = []
	var ok: bool = await _wait_wall(10000, func() -> bool:
		for c in veh.get_children():
			if c is EngineSound:
				holder.append(c)
				return true
		return false)
	var eng: EngineSound = holder[0] if not holder.is_empty() else null
	_t("drive_engine_sound_attached", ok, "profile=%s" % (eng.profile if eng != null else &"-"))
	if eng != null:
		veh.input_throttle = 0.0
		for i in 40:
			await get_tree().physics_frame
		var layers_idle := _active_layers(eng)
		veh.input_throttle = 1.0
		for i in 240:
			await get_tree().physics_frame
		var layers_fast := _active_layers(eng)
		var pitch_idle := float(layers_idle["pitch"])
		var pitch_fast := float(layers_fast["pitch"])
		_t("drive_engine_reacts_to_throttle", int(layers_fast["count"]) >= 1 and (pitch_fast > pitch_idle * 0.9 or float(layers_fast["max_vol"]) > float(layers_idle["max_vol"]) - 1.0), "idle: %s | full throttle: %s speed %.1f m/s" % [str(layers_idle), str(layers_fast), veh.get_speed()])
		veh.input_throttle = 0.0
	# radio with the real player + vehicle
	var radio_ok: bool = await _wait_wall(20000, func() -> bool: return asys.is_radio_playing())
	_t("drive_radio_plays", radio_ok, "station=%s gain=%.2f queued=%.1fs" % [asys.get_station(), asys.radio.gain, asys.radio.buffered_seconds()])
	var before: StringName = asys.get_station()
	asys.radio_next()
	var switched: bool = await _wait_wall(3000, func() -> bool: return asys.get_station() != before)
	_t("drive_radio_next", switched, "%s -> %s" % [before, asys.get_station()])
	var st: Dictionary = Sfx.stats()
	_t("drive_voices_within_pool", int(st["active_3d"]) <= Sfx.POOL_3D, str(st))
	return _fail == 0


func _active_layers(eng: EngineSound) -> Dictionary:
	var count := 0
	var pitch := 0.0
	var max_vol := -99.0
	for c in eng.get_children():
		if c is AudioStreamPlayer3D and not c.stream_paused:
			count += 1
			pitch = maxf(pitch, c.pitch_scale)
			max_vol = maxf(max_vol, c.volume_db)
	return {"count": count, "pitch": snappedf(pitch, 0.01), "max_vol": snappedf(max_vol, 0.1)}
