extends Node
## Visual QA of the air / sea vehicles in the REAL city (real renderer):  --scen=heli|runway|flight|jet|boat|police|police2|cabin
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\air_last.png -GameArgs "--exec=res://gta/tests/air_shots.gd --scen=heli --no-air --delay=3"
## Each scenario saves screenshots\air_<scen>*.png itself.

var cam: Camera3D
var tree: SceneTree


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path("res://screenshots/" + path))
		print("TEST airshot_%s PASS saved" % path)


func _arg(key: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--" + key + "="):
			return String(a).substr(key.length() + 3)
	return default


func _cam_at(pos: Vector3, look: Vector3, fov: float = 62.0) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func run(main: Node) -> String:
	tree = get_tree()
	cam = Camera3D.new()
	cam.far = 1500.0
	main.add_child(cam)
	cam.make_current()
	Game.time_frozen = true
	Game.wetness = 0.0
	if Game.player != null:
		Game.player.visible = false
	var scen := _arg("scen", "heli")
	var t := float(_arg("hour", ""))
	match scen:
		"heli":
			Game.time_of_day = t if _arg("hour") != "" else 18.4
			await _scen_heli()
		"runway":
			Game.time_of_day = t if _arg("hour") != "" else 16.2
			await _scen_runway()
		"flight":
			Game.time_of_day = t if _arg("hour") != "" else 17.2
			await _scen_flight(&"plane_prop")
		"jet":
			Game.time_of_day = t if _arg("hour") != "" else 11.0
			await _scen_flight(&"plane_jet")
		"boat":
			Game.time_of_day = t if _arg("hour") != "" else 17.0
			await _scen_boat()
		"police":
			Game.time_of_day = t if _arg("hour") != "" else 23.0
			await _scen_police(false)
		"police2":
			Game.time_of_day = t if _arg("hour") != "" else 22.5
			await _scen_police(true)
		"cabin":
			Game.time_of_day = t if _arg("hour") != "" else 15.0
			await _scen_cabin()
		"dust":
			Game.time_of_day = t if _arg("hour") != "" else 15.0
			await _scen_dust()
		"pad":
			Game.time_of_day = t if _arg("hour") != "" else 14.0
			var pid := StringName(_arg("loc", "helipad_hospital"))
			var pp := WorldLayout.location_pos(pid)
			await _frames(60 * 3)
			_cam_at(pp + Vector3(17.0, 9.0, 17.0), pp + Vector3(0, -2.5, 0), 60.0)
			await _frames(3)
			await _save("air_pad_%s.png" % String(pid))
	return "ok"


func _spawn(id: StringName, pos: Vector3, yaw_deg: float, opts: Dictionary = {}) -> VehicleBase:
	var o := {"ai": true, "engine_on": true, "snap_ground": false, "abandoned": true}
	o.merge(opts, true)
	return VehicleFactory.spawn(id, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos), o)


# ---- 1. helicopter hovering over the city at dusk --------------------------------------------------------------------------
func _scen_heli() -> void:
	var h := _spawn(&"heli_civil", Vector3(-35, 78, 30), -35.0, {"paint": Color("#34e0ff"), "finish": &"metallic"}) as HeliVehicle
	h.start_airborne(0.0)
	h.headlights_on = true
	await _frames(60 * 5)
	_cam_at(h.global_position + Vector3(15.0, -1.5, 14.0), h.global_position + Vector3(-1.0, 0.8, 0.0), 58.0)
	await _frames(3)
	await _save("air_heli_hover.png")
	# a second angle: from below and ahead, the rotor disc against the sky
	_cam_at(h.global_position + Vector3(-9.0, -3.0, -17.0), h.global_position + Vector3(0.0, 1.5, 0.0), 54.0)
	await _frames(3)
	await _save("air_heli_hover2.png")
	# forward flight, banked
	h.set_ai_controlled(true)
	for i in 60 * 4:
		h.input_pitch = -0.8
		h.input_roll = 0.4
		await tree.physics_frame
		_cam_at(h.global_position + Vector3(0, 3.0, 0) + h.global_transform.basis * Vector3(10.0, 0.0, 17.0), h.global_position + Vector3(0, 0.5, 0), 62.0)
	await _save("air_heli_flight.png")


# ---- 2. propeller plane rolling on the runway ----------------------------------------------------------------------------------
func _scen_runway() -> void:
	var loc: Dictionary = WorldLayout.get_location(&"airport_runway_start")
	var p0: Vector3 = loc["pos"]
	var pl := _spawn(&"plane_prop", Vector3(p0.x + 3.0, 0.1, p0.z - 1.0), -90.0, {"paint": Color("#ffb347"), "finish": &"metallic", "snap_ground": true}) as PlaneVehicle
	await _frames(60)
	for i in 60 * 3:
		pl.input_throttle = 1.0
		await tree.physics_frame
	for i in 3:
		pl.input_throttle = 1.0
		await tree.physics_frame
	var fwd := -pl.global_transform.basis.z
	_cam_at(pl.global_position + Vector3(fwd.x * 9.0 + 6.5, 1.6, fwd.z * 9.0 - 3.0) , pl.global_position + Vector3(0, 1.3, 0), 60.0)
	await _frames(2)
	await _save("air_runway_roll.png")
	_cam_at(pl.global_position + Vector3(-fwd.x * 16.0, 4.0, 11.0), pl.global_position + Vector3(fwd.x * 2.0, 1.4, 0), 58.0)
	await _frames(2)
	await _save("air_runway_roll2.png")


# ---- 3. plane in flight ----------------------------------------------------------------------------------------------------------------
func _scen_flight(id: StringName) -> void:
	var loc: Dictionary = WorldLayout.get_location(&"airport_runway_start")
	var p0: Vector3 = loc["pos"]
	var pl := _spawn(id, Vector3(p0.x + 3.0, 0.1, p0.z - 1.0), -90.0, {"paint": Color("#ffb347") if id == &"plane_prop" else Color("#e8e4da"), "finish": &"metallic", "snap_ground": true}) as PlaneVehicle
	await _frames(60)
	var airborne := false
	for i in 60 * 40:
		pl.input_throttle = 1.0
		await tree.physics_frame
		if pl.grounded_count == 0:
			airborne = true
		if i % 30 == 0:
			print("DBG flight t=%.1f pos=(%.0f,%.1f,%.0f) spd=%.0f pitch=%.1f bank=%.1f gnd=%d hp=%.0f" % [i / 60.0, pl.global_position.x, pl.global_position.y, pl.global_position.z, pl.linear_velocity.length() * 3.6, rad_to_deg(AirCommon.pitch_of(pl.global_transform.basis)), rad_to_deg(AirCommon.bank_of(pl.global_transform.basis)), pl.grounded_count, pl.health])
		if pl.is_destroyed:
			print("DBG flight destroyed at ", pl.global_position)
			break
		if airborne and pl.global_position.y > 70.0:
			break
	# turn left over the sea (south) so the city / coast is in the background
	for i in 60 * 6:
		pl.input_throttle = 0.8
		pl.input_roll = 0.55
		await tree.physics_frame
	var side := pl.global_transform.basis.x
	var f2 := -pl.global_transform.basis.z
	_cam_at(pl.global_position + side * 17.0 + f2 * 10.0 + Vector3(0, 2.5, 0), pl.global_position, 58.0)
	await _frames(1)
	await _save("air_%s_flight.png" % String(id))
	for i in 60 * 3:
		pl.input_throttle = 0.8
		pl.input_roll = 0.0
		await tree.physics_frame
		f2 = -pl.global_transform.basis.z
		_cam_at(pl.global_position - f2 * 22.0 + Vector3(5.0, 5.5, 0), pl.global_position + f2 * 6.0, 62.0)
	await _save("air_%s_chase.png" % String(id))


# ---- 4. speedboat with wake --------------------------------------------------------------------------------------------------------
func _scen_boat() -> void:
	var b := _spawn(&"speedboat", Vector3(-150, -1.2, 262), -60.0, {"paint": Color("#ff3d9a"), "finish": &"gloss"}) as BoatVehicle
	await _frames(90)
	for i in 60 * 8:
		b.input_throttle = 1.0
		b.input_steer = 0.22 if i > 60 * 5 else 0.0
		await tree.physics_frame
		if i > 60 * 5:
			var f := -b.global_transform.basis.z
			_cam_at(b.global_position + Vector3(-f.z * 11.0 + f.x * 3.0, 3.2, f.x * 11.0 + f.z * 3.0), b.global_position + f * 3.0 + Vector3(0, 0.6, 0), 60.0)
		if i == 60 * 7:
			await _save("air_boat_wake.png")
	var f2 := -b.global_transform.basis.z
	_cam_at(b.global_position - f2 * 12.0 + Vector3(0, 3.5, 0), b.global_position + f2 * 4.0 + Vector3(0, 0.5, 0), 62.0)
	await _frames(2)
	await _save("air_boat_rear.png")
	_cam_at(b.global_position + Vector3(0, 30, 0) - f2 * 6.0, b.global_position - f2 * 12.0, 60.0)
	await _frames(2)
	await _save("air_boat_top.png")


# ---- 5. police helicopter with searchlight at night ----------------------------------------------------------------------
func _scen_police(from_ground: bool) -> void:
	var ppos := WorldLayout.location_pos(&"player_spawn")
	if Game.player != null:
		Game.player.teleport_to(ppos)
		Game.player.visible = true
	var v := PoliceHeliAI.spawn(ppos + Vector3(60, 52, 55)) as HeliVehicle
	var ai := PoliceHeliAI.of(v)
	ai.level_override = 4
	ai.set_order({"mode": &"pursue", "target": Game.player, "aggression": 1.0, "lethal": true})
	await _frames(60 * 14)
	if from_ground:
		_cam_at(ppos + Vector3(-6, 1.7, 8), v.global_position + Vector3(0, -8, 0), 66.0)
		await _frames(2)
		await _save("air_police_ground.png")
	else:
		var d := v.global_position - ppos
		var side := d.cross(Vector3.UP).normalized()
		_cam_at(v.global_position + side * 38.0 + Vector3(0, -6, 0) + d.normalized() * 6.0, (v.global_position + ppos) * 0.5 + Vector3(0, 6, 0), 58.0)
		await _frames(2)
		await _save("air_police_beam.png")
		_cam_at(v.global_position + side * 16.0 + Vector3(0, 2, 0), v.global_position + Vector3(0, 0, 0), 50.0)
		await _frames(2)
		await _save("air_police_closeup.png")


# ---- 7. downwash: hovering low over the beach sand and over the sea -----------------------------------------------------------
func _scen_dust() -> void:
	var beach := WorldLayout.location_pos(&"beach_spawn")
	var h := _spawn(&"heli_civil", Vector3(beach.x, 5.5, beach.z - 6.0), 0.0, {"paint": Color("#ff3d9a"), "finish": &"metallic"}) as HeliVehicle
	h.start_airborne(0.0)
	await _frames(60 * 6)
	_cam_at(h.global_position + Vector3(13.0, -1.5, 15.0), h.global_position + Vector3(0, -2.0, 0), 62.0)
	await _frames(2)
	await _save("air_dust_beach.png")
	# over the water: spray
	var w := _spawn(&"heli_civil", Vector3(beach.x + 45.0, 5.0, beach.z + 70.0), 0.0, {"paint": Color("#34e0ff"), "finish": &"metallic"}) as HeliVehicle
	w.start_airborne(0.0)
	await _frames(60 * 6)
	_cam_at(w.global_position + Vector3(14.0, -1.0, 16.0), w.global_position + Vector3(0, -3.0, 0), 62.0)
	await _frames(2)
	await _save("air_dust_sea.png")


# ---- 6. view from the pilot seat (first person) -----------------------------------------------------------------------
func _scen_cabin() -> void:
	var h := _spawn(&"heli_civil", Vector3(-35, 78, 30), -35.0) as HeliVehicle
	h.start_airborne(0.0)
	await _frames(60 * 3)
	var seat: Vector3 = h.seats[0]["pos"]
	cam.global_position = h.to_global(seat + Vector3(0, 0.62, -0.2))
	cam.global_transform = Transform3D(h.global_transform.basis, cam.global_position)
	await _frames(2)
	await _save("air_cabin.png")
