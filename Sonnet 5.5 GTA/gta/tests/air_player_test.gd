extends Node
## The REAL Player enters / flies / leaves every air and sea vehicle through the real input actions (Input.action_press) and the
## real PlayerInteraction (F / E): showcase spawns, helicopter take-off + landing + exit, plane take-off + bail-out with parachute,
## jet take-off roll, speedboat boarding from the water and driving.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/air_player_test.gd -Seconds 240 -GameArgs "--no-traffic --no-peds"

var T := VehicleTestUtil
var tree: SceneTree
var player: Node


func run(main: Node) -> String:
	tree = get_tree()
	player = Game.player
	T.report("player_exists", player != null, "")
	if player == null:
		return "no player"
	Game.cheats["never_wanted"] = true            # stealing aircraft must not bring a police army into the test
	await _wait_showcase()
	await _t_showcase()
	await _t_heli()
	await _t_police_heli()
	await _t_plane(&"plane_prop")
	await _t_bail()
	await _t_jet()
	await _t_boat()
	_release_all()
	print("TEST SUMMARY passed=%d failed=%d" % [T.passed, T.failed])
	return "passed=%d failed=%d" % [T.passed, T.failed]


func _release_all() -> void:
	for a in [&"air_throttle_up", &"air_throttle_down", &"air_pitch_up", &"air_pitch_down", &"air_roll_left", &"air_roll_right", &"air_yaw_left", &"air_yaw_right", &"enter_exit", &"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(a)


func _wait_showcase() -> void:
	var vs = Game.sys(&"vehicles")
	for i in 60 * 14:
		if vs != null and vs.air_sea_vehicles.size() >= 6:
			break
		await tree.physics_frame
	await T.frames(tree, 120)


func _find(id: StringName, near: Vector3 = Vector3.INF) -> VehicleBase:
	var best: VehicleBase = null
	var bd := INF
	for n in tree.get_nodes_in_group(GC.G_VEHICLE):
		if n is VehicleBase and n.def_id == id:
			var d := 0.0 if near == Vector3.INF else (n as Node3D).global_position.distance_to(near)
			if d < bd:
				bd = d
				best = n
	return best


func _t_showcase() -> void:
	var checks := [
		[&"heli_civil", &"helipad_downtown"], [&"heli_police", &"helipad_hospital"], [&"plane_prop", &"airport_runway_start"],
		[&"plane_jet", &"airport_runway_start"], [&"speedboat", &"dock_boat_spawn"], [&"heli_civil", &"helipad_airport"]]
	for c in checks:
		var loc: Dictionary = WorldLayout.get_location(c[1])
		var v := _find(c[0], loc.get("pos", Vector3.ZERO))
		var ok := v != null and v.global_position.distance_to(loc.get("pos", Vector3.ZERO)) < 22.0 and v.global_position.y > -3.0
		T.report("showcase_%s_at_%s" % [c[0], c[1]], ok, "pos=%s loc=%s" % [v.global_position if v != null else "none", loc.get("pos", Vector3.ZERO)])
	var prop := _find(&"plane_prop")
	if prop != null:
		var yaw_dir := -prop.global_transform.basis.z
		T.report("showcase_plane_faces_down_runway", yaw_dir.x > 0.95, "heading %s" % yaw_dir)
		T.report("showcase_plane_on_gear", prop.grounded_count == 3, "grounded=%d y=%.2f sleeping=%s" % [prop.grounded_count, prop.global_position.y, prop.sleeping])
	var heli := _find(&"heli_civil", WorldLayout.location_pos(&"helipad_downtown"))
	if heli != null:
		T.report("showcase_heli_rests_on_roof", heli.grounded_count >= 3, "grounded=%d y=%.2f (pad y %.2f)" % [heli.grounded_count, heli.global_position.y, WorldLayout.location_pos(&"helipad_downtown").y])


func _enter(v: VehicleBase) -> bool:
	var pos := v.get_entry_position(0) + Vector3(0, 0.3, 0)
	player.teleport_to(pos + (v.global_position - pos).normalized() * -0.8)
	await T.frames(tree, 40)
	player.interaction._scan_vehicles()
	var ok: bool = player.interaction.try_enter_exit()
	await T.frames(tree, 70)
	return ok and player.is_in_vehicle() and v.driver == player


func _t_heli() -> void:
	var v := _find(&"heli_civil", WorldLayout.location_pos(&"helipad_airport")) as HeliVehicle
	if v == null:
		T.report("heli_found", false, "")
		return
	var dmg_log := []
	var dcb := func(veh: Node, amount: float, info: Dictionary) -> void:
		if veh == v:
			dmg_log.append("%.0f %s at y=%.1f" % [amount, info.get("type", "?"), veh.global_position.y])
	Events.vehicle_damaged.connect(dcb)
	var ok := await _enter(v)
	T.report("heli_player_enters", ok, "in_vehicle=%s driver=%s prompt='%s'" % [player.is_in_vehicle(), v.driver == player, v.get_interaction(player).get("text", "")])
	if not ok:
		return
	T.report("heli_camera_mode_aircraft", player.camera.mode == PlayerCamera.Mode.AIRCRAFT, "mode=%d" % player.camera.mode)
	var hints := v.get_camera_hints()
	T.report("heli_camera_hints", float(hints["distance"]) > 12.0 and float(hints["height"]) > 4.0, "dist %.1f height %.1f fov %.0f" % [hints["distance"], hints["height"], hints["fov"]])
	await T.frames(tree, 60 * 4)
	T.report("heli_rotor_running", v.rotor_rpm > 0.95 and v.engine_on, "rpm=%.2f" % v.rotor_rpm)
	Input.action_press(&"air_throttle_up")
	await T.frames(tree, 60 * 5)
	Input.action_release(&"air_throttle_up")
	var y1 := v.global_position.y
	T.report("heli_player_takes_off", v.grounded_count == 0 and y1 > 15.0, "altitude %.1f m, vz %.1f" % [y1, v.linear_velocity.y])
	# exit refused in the air
	player.interaction.try_enter_exit()
	await T.frames(tree, 10)
	T.report("heli_exit_refused_airborne", player.is_in_vehicle() and v.driver == player, "still in vehicle=%s" % player.is_in_vehicle())
	# fly forward
	Input.action_press(&"air_pitch_down")
	await T.frames(tree, 60 * 5)
	Input.action_release(&"air_pitch_down")
	T.report("heli_player_flies_forward", v.get_speed() > 15.0, "speed %.1f m/s" % v.get_speed())
	# yaw and bank keys
	Input.action_press(&"air_yaw_right")
	var yaw0 := v.global_transform.basis.get_euler().y
	await T.frames(tree, 60 * 1)
	Input.action_release(&"air_yaw_right")
	T.report("heli_player_yaw_key", absf(wrapf(v.global_transform.basis.get_euler().y - yaw0, -PI, PI)) > 0.5, "")
	await T.frames(tree, 60 * 6)
	# land
	Input.action_press(&"air_throttle_down")
	for i in 60 * 40:
		await tree.physics_frame
		if v.grounded_count >= 3:
			break
	Input.action_release(&"air_throttle_down")
	await T.frames(tree, 120)
	Events.vehicle_damaged.disconnect(dcb)
	T.report("heli_player_lands", v.grounded_count >= 2 and v.health >= v.max_health * 0.88 and v.last_touchdown_sink < 2.0,   # gang members of the Foundry Yard turf nearby may take a few shots at the pilot
		 "grounded=%d health %.0f/%.0f touchdown sink %.2f pos=%s damage=%s" % [v.grounded_count, v.health, v.max_health, v.last_touchdown_sink, v.global_position, dmg_log])
	player.interaction.try_enter_exit()
	await T.frames(tree, 30)
	T.report("heli_player_exits_on_ground", not player.is_in_vehicle() and v.driver == null and absf(player.global_position.y - v.global_position.y) < 2.5, "player y=%.2f heli y=%.2f" % [player.global_position.y, v.global_position.y])


func _t_police_heli() -> void:
	# stealing the police helicopter: crime, key L = searchlight that follows the camera, the police brain stays out of the way
	var v := _find(&"heli_police", WorldLayout.location_pos(&"helipad_hospital")) as HeliVehicle
	if v == null:
		T.report("police_heli_found", false, "")
		return
	var crimes := []
	var cb := func(crime: StringName, _pos: Vector3, _perp: Node, _info: Dictionary) -> void:
		crimes.append(crime)
	Events.crime_committed.connect(cb)
	var ok := await _enter(v)
	Events.crime_committed.disconnect(cb)
	T.report("police_heli_player_enters", ok, "in_vehicle=%s prompt '%s' can_enter=%s grounded=%d agl=%.1f heli=%s player=%s sleeping=%s" % [player.is_in_vehicle(), v.get_interaction(player).get("text", ""), v.can_be_entered_by(player), v.grounded_count, v.agl, v.global_position, player.global_position, v.sleeping])
	if not ok:
		return
	T.report("police_heli_theft_is_a_crime", crimes.has(GC.CRIME_POLICE_VEHICLE_THEFT) or crimes.has(GC.CRIME_AIRCRAFT_THEFT), "crimes=%s" % [crimes])
	await T.frames(tree, 60 * 4)
	T.report("police_heli_searchlight_exists", v.searchlight != null and not v.searchlight.external_control, "searchlight=%s" % v.searchlight)
	Input.action_press(&"headlights")
	await T.frames(tree, 3)
	Input.action_release(&"headlights")
	await T.frames(tree, 60 * 2)
	var sl := v.searchlight
	T.report("police_heli_L_toggles_searchlight", sl != null and sl.enabled and sl.fade > 0.9 and sl.dir.y < -0.1, "enabled=%s fade=%.2f dir=%s" % [sl.enabled if sl != null else false, sl.fade if sl != null else 0.0, sl.dir if sl != null else Vector3.ZERO])
	T.report("police_heli_beam_reaches_ground", sl != null and sl.hit_dist > 1.0 and sl.hit_dist < sl.range_m + 1.0, "beam ends %.1f m away at %s" % [sl.hit_dist if sl != null else -1.0, sl.hit_pos if sl != null else Vector3.ZERO])
	Input.action_press(&"headlights")
	await T.frames(tree, 3)
	Input.action_release(&"headlights")
	await T.frames(tree, 60 * 2)
	T.report("police_heli_L_again_switches_off", sl != null and not sl.enabled and sl.fade < 0.05, "fade=%.2f" % (sl.fade if sl != null else -1.0))
	T.report("police_heli_no_brain_when_stolen", PoliceHeliAI.of(v) == null, "ai=%s" % PoliceHeliAI.of(v))
	player.interaction.try_enter_exit()
	await T.frames(tree, 40)


func _t_plane(id: StringName) -> void:
	var v := _find(id) as PlaneVehicle
	if v == null:
		T.report("plane_found", false, "")
		return
	var ok := await _enter(v)
	T.report("plane_player_enters", ok, "in_vehicle=%s prompt '%s'" % [player.is_in_vehicle(), v.get_interaction(player).get("text", "")])
	if not ok:
		return
	await T.frames(tree, 30)
	var x0 := v.global_position.x
	Input.action_press(&"air_throttle_up")
	var lifted := false
	var rot_speed: float = v.stall_speed * 1.1
	for i in 60 * 25:
		await tree.physics_frame
		if v.linear_velocity.length() > rot_speed and not lifted:
			Input.action_press(&"air_pitch_up")
		if v.grounded_count == 0 and v.linear_velocity.length() > 15.0:
			lifted = true
			Input.action_release(&"air_pitch_up")
			break
	var dist := v.global_position.x - x0
	T.report("plane_player_takes_off", lifted and dist < 200.0, "airborne after %.0f m at %.0f km/h" % [dist, v.linear_velocity.length() * 3.6])
	await T.frames(tree, 60 * 6)
	T.report("plane_player_climbs", v.global_position.y > 25.0 and v.linear_velocity.length() > v.stall_speed, "alt %.0f m speed %.0f km/h cam mode %d" % [v.global_position.y, v.linear_velocity.length() * 3.6, player.camera.mode])
	# exit refused in flight
	player.interaction.try_enter_exit()
	await T.frames(tree, 5)
	T.report("plane_exit_refused_in_flight", player.is_in_vehicle(), "")


func _t_bail() -> void:
	var v := _find(&"plane_prop") as PlaneVehicle
	if v == null or not player.is_in_vehicle():
		return
	# gain some height first
	Input.action_press(&"air_pitch_up")
	await T.frames(tree, 60 * 2)
	Input.action_release(&"air_pitch_up")
	await T.frames(tree, 60 * 4)
	var agl := v.agl
	player.has_parachute = false
	Input.action_press(&"enter_exit")
	var out := false
	for i in 60 * 3:
		await tree.physics_frame
		if not player.is_in_vehicle():
			out = true
			break
	Input.action_release(&"enter_exit")
	T.report("plane_bail_out_by_holding_F", out and v.driver == null, "released after holding F at %.0f m AGL" % agl)
	await T.frames(tree, 60 * 2)
	var chute := false
	for i in 60 * 6:
		await tree.physics_frame
		if player.move_mode == Player.Move.PARACHUTE:
			chute = true
			break
	T.report("plane_bail_out_parachute", chute, "move_mode=%d has_parachute=%s y=%.0f vy=%.1f" % [player.move_mode, player.has_parachute, player.global_position.y, player.velocity.y])
	# let the pilot land safely
	for i in 60 * 40:
		await tree.physics_frame
		if player.is_on_floor():
			break
	T.report("plane_bail_out_survives", not player.is_dead, "health %.0f" % player.health)
	player.has_parachute = false


func _t_jet() -> void:
	var v := _find(&"plane_jet") as PlaneVehicle
	if v == null:
		T.report("jet_found", false, "")
		return
	player.revive()
	var ok := await _enter(v)
	T.report("jet_player_enters", ok, "in_vehicle=%s" % player.is_in_vehicle())
	if not ok:
		return
	await T.frames(tree, 30)
	var x0 := v.global_position.x
	Input.action_press(&"air_throttle_up")
	var lifted := false
	for i in 60 * 20:
		await tree.physics_frame
		if v.linear_velocity.length() > v.stall_speed * 1.08 and not lifted:
			Input.action_press(&"air_pitch_up")
		if v.grounded_count == 0 and v.linear_velocity.length() > 20.0:
			lifted = true
			Input.action_release(&"air_pitch_up")
			break
	var dist := v.global_position.x - x0
	var runway_end := WorldLayout.location_pos(&"airport_runway_end").x
	T.report("jet_player_takes_off_within_runway", lifted and v.global_position.x < runway_end, "airborne after %.0f m (x=%.0f, runway ends x=%.0f) at %.0f km/h" % [dist, v.global_position.x, runway_end, v.linear_velocity.length() * 3.6])
	Input.action_release(&"air_throttle_up")
	await T.frames(tree, 60 * 5)
	# airspace warning: put the jet 850 m out heading east
	v.place_at(Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(850, 300, 150)))
	v.set_velocity(Vector3(150, 0, 0))
	var warned := [false]
	var cb := func(text: String, _kind: StringName) -> void:
		if text.contains("airspace"):
			warned[0] = true
	Events.notification.connect(cb)
	Input.action_press(&"air_throttle_up")
	for i in 60 * 6:
		await tree.physics_frame
		if warned[0]:
			break
	Input.action_release(&"air_throttle_up")
	Events.notification.disconnect(cb)
	T.report("jet_leaving_airspace_warning", warned[0], "distance from centre %.0f m" % Vector2(v.global_position.x, v.global_position.z).length())
	# hard limit: beyond 2500 m the aircraft is turned around
	v.place_at(Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(2600, 300, 150)))
	v.set_velocity(Vector3(150, 0, 0))
	await T.frames(tree, 20)
	T.report("jet_airspace_hard_limit", Vector2(v.global_position.x, v.global_position.z).length() < 1500.0, "now %.0f m from the centre" % Vector2(v.global_position.x, v.global_position.z).length())
	# bail out and clean up
	player.interaction.try_enter_exit()
	v.bail_out(player)
	await T.frames(tree, 30)
	T.report("jet_bail_releases", not player.is_in_vehicle(), "")
	VehicleFactory.despawn(v)
	player.has_parachute = false
	player.teleport_to(WorldLayout.location_pos(&"player_spawn"))
	await T.frames(tree, 60 * 3)


func _t_boat() -> void:
	var v := _find(&"speedboat") as BoatVehicle
	if v == null:
		T.report("boat_found", false, "")
		return
	player.revive()
	var vp := v.global_position
	# swim to the boat, board with E
	player.teleport_to(Vector3(vp.x + 3.2, GC.WATER_LEVEL + 0.5, vp.z + 1.0))
	await T.frames(tree, 120)
	T.report("boat_player_swims", player.is_swimming, "swimming=%s y=%.2f" % [player.is_swimming, player.global_position.y])
	await T.frames(tree, 20)
	player.interaction._scan_interactables()
	var prompt: String = str(player.interaction.current_info.get("text", ""))
	T.report("boat_swimmer_prompt", prompt.begins_with("Board"), "prompt='%s'" % prompt)
	var ok: bool = player.interaction.try_interact()
	await T.frames(tree, 90)
	T.report("boat_board_from_water", ok and player.is_in_vehicle() and v.driver == player, "in_vehicle=%s" % player.is_in_vehicle())
	if not player.is_in_vehicle():
		return
	await T.frames(tree, 60)
	var p0 := v.global_position
	Input.action_press(&"move_forward")
	await T.frames(tree, 60 * 6)
	T.report("boat_player_drives", v.get_speed() > 12.0, "speed %.1f m/s (%.0f km/h) after 6 s" % [v.get_speed(), v.get_speed_kmh()])
	Input.action_press(&"move_right")
	var h0 := Util.dir_to_yaw(Util.flat(-v.global_transform.basis.z).normalized())
	await T.frames(tree, 60 * 2)
	Input.action_release(&"move_right")
	var h1 := Util.dir_to_yaw(Util.flat(-v.global_transform.basis.z).normalized())
	T.report("boat_player_steers", absf(rad_to_deg(wrapf(h1 - h0, -PI, PI))) > 25.0, "heading change %.0f deg" % rad_to_deg(wrapf(h1 - h0, -PI, PI)))
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")
	await T.frames(tree, 60 * 6)
	Input.action_release(&"move_back")
	await T.frames(tree, 60 * 3)
	T.report("boat_stops", v.get_speed() < 3.0, "speed %.1f" % v.get_speed())
	player.interaction.try_enter_exit()
	await T.frames(tree, 30)
	T.report("boat_player_exits", not player.is_in_vehicle() and v.driver == null, "player at %s" % player.global_position)
