extends Node
## Enter / exit / carjack / crimes / death eject / bike crash / run-over / damage zones / pooling / paint / lights / mods.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/vehicle_interact_test.gd -Seconds 120 -GameArgs "--no-vehicles --no-traffic --no-peds"

var T := VehicleTestUtil
var tree: SceneTree
var main_node: Node
var crimes: Array = []


class MockNpc extends CharacterBase:
	var carjacked_by: Node = null

	func on_carjacked(by: Node) -> void:
		carjacked_by = by


func _mk_char(pos: Vector3, player := false, npc := false) -> CharacterBase:
	var c: CharacterBase = MockNpc.new() if not player else CharacterBase.new()
	c.name = "MockPlayer" if player else "MockNpc"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	c.add_child(cs)
	main_node.add_child(c)
	c.global_position = pos
	c.collision_layer = GC.L_PLAYER if player else GC.L_NPC
	c.collision_mask = 0
	if player:
		c.add_to_group(GC.G_PLAYER)
	if npc:
		c.add_to_group(GC.G_NPC)
	return c


func run(main: Node) -> String:
	tree = get_tree()
	main_node = main
	T.make_floor(main)
	Game.wetness = 0.0
	Events.crime_committed.connect(func(crime, pos, perp, info): crimes.append({"crime": crime, "perp": perp, "info": info}))
	await T.frames(tree, 10)
	await _t_enter_exit()
	await _t_carjack()
	await _t_police_theft()
	await _t_passengers()
	await _t_driver_death()
	await _t_bike()
	await _t_runover()
	await _t_damage_zones()
	await _t_visuals()
	await _t_mods()
	await _t_pool()
	print("TEST SUMMARY passed=%d failed=%d" % [T.passed, T.failed])
	return "passed=%d failed=%d" % [T.passed, T.failed]


func _t_enter_exit() -> void:
	var v := T.spawn(&"sedan", Vector3(0, 0.3, 0), 0.0, {"ai": false, "engine_on": false, "parked": true, "abandoned": false})
	await T.frames(tree, 120)
	T.report("sleeping_parked", v.sleeping, "sleeping=%s" % v.sleeping)
	var c := _mk_char(v.get_entry_position(0) + Vector3(-1.2, 0, 0.5), true)
	var entered := [0]
	Events.vehicle_entered.connect(func(_v, _c, _s): entered[0] += 1)
	crimes.clear()
	var ok := v.request_enter(c)
	T.report("enter_ok", ok and v.driver == c and c.current_vehicle == v and entered[0] == 1, "driver=%s current_vehicle=%s seat=%d" % [v.driver == c, c.current_vehicle == v, c.seat_index])
	T.report("enter_character_reparented", c.get_parent().name.begins_with("SeatAnchor") and c.collision_layer == 0, "parent=%s layer=%d" % [c.get_parent().name, c.collision_layer])
	T.report("enter_theft_crime", crimes.size() == 1 and crimes[0]["crime"] == GC.CRIME_VEHICLE_THEFT and crimes[0]["info"].get("witnessed_by_npc", true) == false, "crimes=%s" % [crimes.map(func(x): return x["crime"])])
	await T.frames(tree, 10)
	T.report("enter_blend_in_progress", c.transform.origin.length() > 0.01, "local offset %.2f (gliding into the seat)" % c.transform.origin.length())
	await T.frames(tree, 60)
	T.report("enter_seated_pose", c.transform.origin.length() < 0.001 and v.engine_on, "local=%s engine_on=%s" % [c.transform.origin, v.engine_on])
	T.report("woke_up_on_entry", not v.sleeping, "sleeping=%s" % v.sleeping)
	# drive a bit with the occupant, check it follows
	for i in 120:
		v.input_throttle = 1.0
		await tree.physics_frame
	T.report("occupant_moves_with_vehicle", c.global_position.distance_to(v.global_position) < 1.5 and v.get_speed() > 5.0, "dist to car %.2f speed %.1f" % [c.global_position.distance_to(v.global_position), v.get_speed()])
	v.reset_controls()
	v.input_brake = 1.0
	await T.frames(tree, 150)
	v.reset_controls()
	var exited := [0]
	Events.vehicle_exited.connect(func(_v, _c): exited[0] += 1)
	v.exit(c)
	await T.frames(tree, 2)
	var d := c.global_position.distance_to(v.global_position)
	var outside := absf((c.global_position - v.global_position).dot(v.global_transform.basis.x)) > 1.0
	T.report("exit_placed_outside", d > 1.2 and outside and c.current_vehicle == null and c.get_parent() == main_node and c.collision_layer == GC.L_PLAYER and exited[0] == 1, "dist=%.2f lateral_ok=%s parent=%s layer=%d" % [d, outside, c.get_parent().name, c.collision_layer])
	await T.frames(tree, 90)
	T.report("engine_off_after_exit", not v.engine_on, "engine_on=%s" % v.engine_on)
	# own vehicle: no second crime
	crimes.clear()
	v.request_enter(c)
	T.report("reenter_stolen_no_new_crime", crimes.is_empty(), "crimes=%d" % crimes.size())
	v.exit(c)
	c.queue_free()
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_carjack() -> void:
	var v := T.spawn(&"sedan", Vector3(0, 0.3, 0), 0.0, {"ai": true, "engine_on": true, "abandoned": false})
	await T.frames(tree, 30)
	var npc := _mk_char(v.global_position, false, true) as MockNpc
	v.enter(npc, 0)
	T.report("npc_driver_seated", v.driver == npc, "driver=%s" % v.driver)
	var player := _mk_char(v.get_entry_position(0) + Vector3(-1.0, 0, 0), true)
	crimes.clear()
	var ok := v.request_enter(player, 0)
	await T.frames(tree, 5)
	T.report("carjack_driver_replaced", ok and v.driver == player and npc.current_vehicle == null, "driver_is_player=%s npc_out=%s" % [v.driver == player, npc.current_vehicle == null])
	T.report("carjack_crime", crimes.size() >= 1 and crimes[0]["crime"] == GC.CRIME_CARJACK and crimes[0]["info"].get("victim") == npc, "crimes=%s" % [crimes.map(func(x): return x["crime"])])
	T.report("carjack_victim_reacts", npc.carjacked_by == player and npc.global_position.distance_to(v.global_position) > 1.0, "on_carjacked called=%s npc dist=%.2f" % [npc.carjacked_by == player, npc.global_position.distance_to(v.global_position)])
	T.report("carjack_ai_flag_cleared", not v.is_ai_controlled and v.is_stolen, "ai=%s stolen=%s" % [v.is_ai_controlled, v.is_stolen])
	v.exit(player)
	player.queue_free()
	npc.queue_free()
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_police_theft() -> void:
	var v := T.spawn(&"police_cruiser", Vector3(0, 0.3, 0), 0.0, {"ai": false, "engine_on": false, "parked": true, "abandoned": false})
	await T.frames(tree, 20)
	T.report("police_faction_group", v.faction == GC.F_POLICE and v.is_in_group(GC.G_POLICE), "faction=%s in_group=%s" % [v.faction, v.is_in_group(GC.G_POLICE)])
	var p := _mk_char(v.get_entry_position(0) + Vector3(-1, 0, 0), true)
	crimes.clear()
	v.request_enter(p)
	T.report("police_vehicle_theft_crime", crimes.size() == 1 and crimes[0]["crime"] == GC.CRIME_POLICE_VEHICLE_THEFT, "crimes=%s" % [crimes.map(func(x): return x["crime"])])
	v.exit(p)
	p.queue_free()
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_passengers() -> void:
	var v := T.spawn(&"sedan", Vector3(0, 0.3, 0), 0.0, {"ai": false, "engine_on": false})
	await T.frames(tree, 20)
	T.report("seat_count", v.seats.size() >= 4, "seats=%d names=%s" % [v.seats.size(), v.seats.map(func(s): return s["name"])])
	var a := _mk_char(T.o(Vector3(-3, 0, 0)), true)
	var b := _mk_char(T.o(Vector3(3, 0, 0)), false, true)
	v.request_enter(a)
	# b approaches from the right side: nearest free seat should be the passenger side
	b.global_position = v.get_entry_position(1) + Vector3(0.8, 0, 0)
	var ok := v.request_enter(b)
	var seat_b := v.get_seat_of(b)
	T.report("passenger_nearest_seat", ok and seat_b == 1, "seat_b=%d" % seat_b)
	T.report("driver_can_shoot", v.can_shoot_from_seat(0) and v.can_shoot_from_seat(1), "can_shoot driver=%s passenger=%s" % [v.can_shoot_from_seat(0), v.can_shoot_from_seat(1)])
	var sock := v.get_weapon_socket(0)
	T.report("weapon_socket_near_window", sock.origin.distance_to(v.global_position) < 2.5, "socket %s" % sock.origin)
	T.report("free_seat_query", v.get_free_seat() >= 2, "free seat=%d" % v.get_free_seat())
	v.exit(a)
	v.exit(b)
	a.queue_free()
	b.queue_free()
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_driver_death() -> void:
	var v := T.spawn(&"compact", Vector3(0, 0.3, 0), 0.0, {"ai": true, "engine_on": true})
	await T.frames(tree, 20)
	var npc := _mk_char(v.global_position, false, true)
	v.enter(npc, 0)
	await T.frames(tree, 10)
	npc.apply_damage(500.0, {"source": null, "type": GC.DMG_BULLET, "zone": GC.ZONE_HEAD})
	await T.frames(tree, 5)
	T.report("dead_driver_ejected", npc.is_dead and v.driver == null and npc.current_vehicle == null, "dead=%s driver=%s" % [npc.is_dead, v.driver])
	npc.queue_free()
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_bike() -> void:
	var wall := T.make_box(main_node, Vector3(0, 1.5, -350.0), Vector3(20.0, 3.0, 1.0), Vector3.ZERO, "BikeWall")
	var b := T.spawn(&"motorcycle", Vector3(0, 0.3, 250.0), 0.0, {"ai": false, "engine_on": false}) as BikeVehicle
	await T.frames(tree, 60)
	var rider := _mk_char(b.get_entry_position(0) + Vector3(-0.8, 0, 0), true)
	b.request_enter(rider)
	await T.frames(tree, 60)
	var min_up := 1.0
	var max_lean := 0.0
	var top := 0.0
	for i in 420:
		b.input_throttle = 1.0
		await tree.physics_frame
		min_up = minf(min_up, b.global_transform.basis.y.y)
		top = maxf(top, b.get_speed_kmh())
	T.report("bike_accelerates_stays_up", top > 105.0 and min_up > 0.8, "top=%.0f km/h min_up=%.2f lean=%.1f deg" % [top, min_up, rad_to_deg(b.lean)])
	# corner at speed: lean into it, stay up
	for i in 120:
		b.input_throttle = 0.5
		b.input_steer = 0.5
		await tree.physics_frame
		max_lean = maxf(max_lean, absf(b.lean))
	T.report("bike_leans_in_corner", max_lean > deg_to_rad(8.0) and not b.fallen, "max lean %.1f deg fallen=%s speed=%.0f" % [rad_to_deg(max_lean), b.fallen, b.get_speed_kmh()])
	# crash into a wall -> rider ejected, bike down (fresh bike + rider, wall 40 m ahead)
	b.exit(rider)
	VehicleFactory.despawn(b)
	await T.frames(tree, 3)
	b = T.spawn(&"motorcycle", Vector3(0, 0.3, -310.0), 0.0, {"ai": false, "engine_on": false}) as BikeVehicle
	await T.frames(tree, 40)
	rider.global_position = b.get_entry_position(0) + Vector3(-0.8, 0, 0)
	b.request_enter(rider)
	await T.frames(tree, 60)
	var crash_wall := T.make_box(main_node, Vector3(0, 1.5, -355.0), Vector3(20.0, 3.0, 1.0), Vector3.ZERO, "BikeWall2")
	var hp0 := rider.health
	b.set_velocity(Vector3(0, 0, -25.0))
	for i in 240:
		b.input_throttle = 1.0
		b.input_steer = 0.0
		await tree.physics_frame
		if b.fallen:
			break
	T.report("bike_crash_ejects_rider", b.fallen and b.driver == null and rider.current_vehicle == null, "fallen=%s driver=%s rider_hp %.0f -> %.0f bike_hp=%.0f" % [b.fallen, b.driver, hp0, rider.health, b.health])
	crash_wall.queue_free()
	# pick up again by entering
	b.place_at(Transform3D(Basis(), T.o(Vector3(0, 0.3, -310.0))))
	await T.frames(tree, 30)
	rider.global_position = b.get_entry_position(0) + Vector3(-0.8, 0, 0)
	b.request_enter(rider)
	await T.frames(tree, 90)
	T.report("bike_pickup_upright", not b.fallen and b.global_transform.basis.y.y > 0.9, "fallen=%s up=%.2f" % [b.fallen, b.global_transform.basis.y.y])
	# bicycle
	b.exit(rider)
	VehicleFactory.despawn(b)
	var cyc := T.spawn(&"bicycle", Vector3(0, 0.3, 0), 0.0, {"ai": false, "engine_on": false}) as BikeVehicle
	await T.frames(tree, 40)
	rider.global_position = cyc.get_entry_position(0) + Vector3(-0.6, 0, 0)
	cyc.request_enter(rider)
	await T.frames(tree, 40)
	var topc := 0.0
	for i in 600:
		cyc.input_throttle = 1.0
		await tree.physics_frame
		topc = maxf(topc, cyc.get_speed_kmh())
	T.report("bicycle_pedal_speed", topc > 20.0 and topc < 40.0 and not cyc.fallen, "top=%.1f km/h" % topc)
	cyc.exit(rider)
	rider.queue_free()
	VehicleFactory.despawn(cyc)
	wall.queue_free()
	await T.frames(tree, 3)


func _t_runover() -> void:
	var v := T.spawn(&"sedan", Vector3(0, 0.3, 14.0), 0.0, {"ai": true, "engine_on": true})
	var ped := _mk_char(T.o(Vector3(0, 0, -20.0)), false, true)
	var hit_events := [0]
	Events.vehicle_collision.connect(func(veh, other, _i): if other == ped: hit_events[0] += 1)
	await T.frames(tree, 30)
	var hp0 := ped.health
	v.set_velocity(Vector3(0, 0, -14.0))
	for i in 120:
		v.input_throttle = 0.6
		await tree.physics_frame
	T.report("runover_damages_pedestrian", ped.health < hp0 and hit_events[0] >= 1, "ped health %.0f -> %.0f events=%d car speed %.1f" % [hp0, ped.health, hit_events[0], v.get_speed()])
	ped.queue_free()
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_damage_zones() -> void:
	var v := T.spawn(&"sedan", Vector3(0, 0.3, 0), 0.0, {"ai": false, "engine_on": true})
	await T.frames(tree, 30)
	# tyre hit
	var wp := v.global_transform * v.wheels[0].rest
	v.apply_damage(20.0, {"type": GC.DMG_BULLET, "zone": GC.ZONE_TIRE, "position": wp})
	T.report("tire_puncture", v.wheels[0].flat, "front-left flat=%s" % v.wheels[0].flat)
	v.input_throttle = 1.0
	v.is_ai_controlled = true
	await T.frames(tree, 120)
	T.report("flat_tire_pulls", v.is_inside_tree() and v.get_speed() > 2.0, "speed with flat tyre %.1f" % v.get_speed())
	v.reset_controls()
	# glass
	v.apply_damage(5.0, {"type": GC.DMG_BULLET, "zone": GC.ZONE_GLASS, "position": v.global_position + Vector3(0, 1.2, 0)})
	T.report("glass_cracks", v.dmg.glass_state == 1, "glass_state=%d" % v.dmg.glass_state)
	v.apply_damage(5.0, {"type": GC.DMG_BULLET, "zone": GC.ZONE_GLASS, "position": v.global_position + Vector3(0, 1.2, 0)})
	T.report("glass_shatters", v.dmg.glass_state == 2, "glass_state=%d" % v.dmg.glass_state)
	# smoke / fire thresholds
	v.apply_damage(v.max_health * 0.70, {"type": GC.DMG_COLLISION})
	T.report("engine_smoke_below_35", v.get_health_ratio() < 0.35 and not v.on_fire and v.power_scale < 1.0, "ratio=%.2f on_fire=%s power=%.2f" % [v.get_health_ratio(), v.on_fire, v.power_scale])
	v.apply_damage(v.max_health * 0.2, {"type": GC.DMG_COLLISION})
	T.report("fire_below_15", v.on_fire and not v.is_destroyed, "ratio=%.2f on_fire=%s" % [v.get_health_ratio(), v.on_fire])
	var destroyed := [false]
	v.destroyed.connect(func(_k): destroyed[0] = true)
	await T.frames(tree, 60 * 9)
	T.report("burning_vehicle_explodes", destroyed[0] and v.is_destroyed, "destroyed=%s after fire drain" % destroyed[0])
	# repair
	v.repair()
	T.report("repair_restores", v.health == v.max_health and not v.is_destroyed and not v.wheels[0].flat and v.dmg.glass_state == 0, "health=%.0f flat=%s glass=%d" % [v.health, v.wheels[0].flat, v.dmg.glass_state])
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _count_override(v: VehicleBase, mat_name: String, color: Color) -> int:
	var n := 0
	for mi in ModelLib.meshes(v.model):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is StandardMaterial3D and m.resource_name == mat_name and (m as StandardMaterial3D).albedo_color.is_equal_approx(color):
				n += 1
	return n


func _t_visuals() -> void:
	var v := T.spawn(&"police_cruiser", Vector3(0, 0.3, 0), 0.0, {"ai": true, "engine_on": true})
	await T.frames(tree, 20)
	v.set_paint(Color("#ff3d9a"), Color("#222222"), &"metallic")
	T.report("paint_applied", _count_override(v, "Paint", Color("#ff3d9a")) >= 1, "paint surfaces=%d" % _count_override(v, "Paint", Color("#ff3d9a")))
	v.headlights_on = true
	await T.frames(tree, 5)
	var head_on := false
	for pair in v.lights._surfs[&"head"]:
		var m := (pair[0] as MeshInstance3D).get_active_material(pair[1])
		head_on = head_on or (m is StandardMaterial3D and m.emission_enabled)
	T.report("headlights_emissive", head_on or v.lights._surfs[&"head"].is_empty(), "head surfaces=%d on=%s" % [v.lights._surfs[&"head"].size(), head_on])
	v.input_brake = 1.0
	v.set_velocity(-v.global_transform.basis.z * 8.0)
	await T.frames(tree, 5)
	T.report("brake_lights_state", v.lights._state[&"tail"] == &"brake" or v.lights._surfs[&"tail"].is_empty(), "tail state=%s surfaces=%d" % [v.lights._state[&"tail"], v.lights._surfs[&"tail"].size()])
	v.reset_controls()
	v.siren_on = true
	var seen := {}
	for i in 60:
		await tree.physics_frame
		seen[str(v.lights._state[&"red"]) + str(v.lights._state[&"blue"])] = true
	T.report("siren_flashes", seen.size() >= 3 or v.lights._surfs[&"red"].is_empty(), "distinct red/blue states=%d red surfaces=%d blue=%d" % [seen.size(), v.lights._surfs[&"red"].size(), v.lights._surfs[&"blue"].size()])
	T.report("camera_hints", v.get_camera_hints().has("distance") and v.get_camera_hints()["fov"] > 60.0, "hints=%s" % [v.get_camera_hints()])
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_mods() -> void:
	var v := T.spawn(&"sedan", Vector3(0, 0.3, 0), 0.0)
	await T.frames(tree, 20)
	var base_top_t := 0.0
	v.apply_mods({"engine": 4, "turbo": 1, "brakes": 3, "armor": 5, "tires": 3, "window_tint": 3, "weight": 2})
	# The table of truth is res://gta/resources/data/vehicle_mods.gd (merged over VehicleDefs.MOD_EFFECTS by VehicleBase.apply_mods):
	# engine 4 = x1.35 power, turbo = up to +24 % boost (mod_turbo_boost, NOT folded into mod_power), brakes 3 = x1.40, armour 5 = x0.5 damage,
	# tyres 3 = bullet-proof, weight 2 = lighter (sedan 1450 kg -> ~1276 kg). Combined peak power = 1.35 x 1.24 = x1.67.
	var peak_power: float = v.mod_power * (1.0 + v.mod_turbo_boost)
	T.report("mods_effects", v.mod_power > 1.3 and v.mod_turbo_boost > 0.2 and peak_power > 1.6 and v.mod_brake > 1.3 and v.damage_taken_mult <= 0.51 and v.bulletproof_tires and v.mass < float(v.def["mass"]) * 0.95, "power x%.2f turbo +%.2f (peak x%.2f) brake x%.2f dmg x%.2f bulletproof=%s mass=%.0f" % [v.mod_power, v.mod_turbo_boost, peak_power, v.mod_brake, v.damage_taken_mult, v.bulletproof_tires, v.mass])
	var h0 := v.health
	v.apply_damage(100.0, {"type": GC.DMG_EXPLOSION})
	T.report("armor_reduces_damage", h0 - v.health < 70.0, "took %.1f of 100" % (h0 - v.health))
	var wp := v.global_transform * v.wheels[0].rest
	v.apply_damage(10.0, {"type": GC.DMG_BULLET, "zone": GC.ZONE_TIRE, "position": wp})
	T.report("bulletproof_tires_hold", not v.wheels[0].flat, "flat=%s" % v.wheels[0].flat)
	v.apply_mods({})
	T.report("mods_reset", is_equal_approx(v.mod_power, 1.0) and not v.bulletproof_tires, "power x%.2f" % v.mod_power)
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_pool() -> void:
	var sys = Game.sys(&"vehicles")
	var v := T.spawn(&"taxi", Vector3(5, 0.3, 5), 0.0, {"ai": true, "engine_on": true})
	await T.frames(tree, 20)
	v.apply_damage(100.0, {"type": GC.DMG_COLLISION})
	v.headlights_on = true
	var id := v.get_instance_id()
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)
	var v2 := T.spawn(&"taxi", Vector3(-5, 0.3, 5), 90.0, {"ai": false, "engine_on": false, "paint": Color.GREEN})
	await T.frames(tree, 60)
	var reused: bool = v2.get_instance_id() == id
	T.report("pool_reuse_clean_state", reused and v2.health == v2.max_health and not v2.engine_on and not v2.headlights_on and not v2.is_ai_controlled and v2.get_speed() < 0.5, "reused=%s health=%.0f engine=%s lights=%s ai=%s stats=%s" % [reused, v2.health, v2.engine_on, v2.headlights_on, v2.is_ai_controlled, sys.stats])
	T.report("pool_position_reset", absf(v2.global_position.x - T.o(Vector3(-5.0, 0, 5.0)).x) < 0.5 and absf(v2.global_position.y) < 0.3, "pos=%s" % v2.global_position)
	VehicleFactory.despawn(v2)
	await T.frames(tree, 3)
