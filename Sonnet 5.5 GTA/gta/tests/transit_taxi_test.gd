extends Node
## Full taxi trip (headless): call -> approach -> curb stop -> F boards the rear seat (NOT a carjack) -> destination list -> drive -> fare -> F exits -> cab leaves.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/transit_taxi_test.gd -Seconds 420 -GameArgs "--no-traffic --time=12"


func report(test_name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)


func run(_main: Node) -> void:
	var tr = Game.sys(&"transit")
	var tm = Game.sys(&"traffic")
	report("taxi_systems", tr != null and tm != null and tr.taxi != null)
	if tr == null or tm == null:
		return
	var waited := 0
	while int(tm.state) != 1 and waited < 900:
		await get_tree().physics_frame
		waited += 1
	var pl = Game.player
	pl.teleport_to(WorldLayout.location_pos(&"taxi_stand") + Vector3(0, 0.5, 0))
	await _frames(90)
	var ts: TaxiService = tr.taxi
	ts.debug = true
	var cash0: int = Game.cash
	var ok: bool = tr.call_taxi()
	report("taxi_call", ok and ts.state == TaxiService.S.APPROACH, "state=%d" % ts.state)
	if not ok:
		return
	var taxi: VehicleBase = ts.taxi
	var d0: float = Util.dist_xz(taxi.global_position, pl.global_position)
	report("taxi_spawned_far", d0 > 60.0, "spawn distance %.0f m, driver npc=%s" % [d0, str(ts.npc)])
	var f := 0
	while ts.state == TaxiService.S.APPROACH and f < 60 * 140:
		await get_tree().physics_frame
		f += 1
	report("taxi_arrived", ts.state == TaxiService.S.WAITING, "after %.0f s state=%d dist to player %.1f m speed %.1f hazard=%s" % [f / 60.0, ts.state, Util.dist_xz(taxi.global_position, pl.global_position), taxi.get_speed(), str(ts.drv.hazard_on)])
	if ts.state != TaxiService.S.WAITING:
		print("TAXI debug: ", ts.drv.debug_string())
		return
	report("taxi_prompt", String(taxi.get_interaction(pl).get("text", "")).begins_with("Get in"), str(taxi.get_interaction(pl)))
	# put the player next to the cab and press F
	pl.teleport_to(taxi.global_position + taxi.global_transform.basis.x * 2.6 + Vector3(0, 0.3, 0))
	await _frames(5)
	var npc0 = ts.npc
	if not OS.get_cmdline_user_args().has("--noboard"):
		await _press(&"enter_exit")
	await _frames(60)
	report("taxi_boarded", pl.current_vehicle == taxi and pl.seat_index >= 2, "seat=%d" % pl.seat_index)
	report("taxi_not_carjacked", taxi.driver == npc0 and not ts.drv.mode == TrafficDriver.MODE_DEAD and Game.wanted_level == 0, "driver ok=%s wanted=%d" % [str(taxi.driver == npc0), Game.wanted_level])
	await _frames(60)
	report("taxi_menu_open", Game.ui != null and Game.ui.is_menu_open() and ts.state == TaxiService.S.CHOOSE, "state=%d" % ts.state)
	if Game.ui != null and Game.ui.is_menu_open():
		Game.ui.close_menu()
	await _frames(3)
	var dests: Array = ts._build_destinations()
	report("taxi_destinations", dests.size() >= 8, "%d destinations" % dests.size())
	# pick the nearest one that is at least 150 m away
	dests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["len"]) < float(b["len"]))
	var pick: Dictionary = {}
	for dd in dests:
		if float(dd["len"]) > 150.0:
			pick = dd
			break
	report("taxi_pick", not pick.is_empty(), "%s %.0f m fare $%d" % [str(pick.get("name", "")), float(pick.get("len", 0)), int(pick.get("fare", 0))])
	ts.state = TaxiService.S.CHOOSE
	ts._start_trip(pick)
	report("taxi_trip_started", ts.state == TaxiService.S.RIDE)
	f = 0
	var top := 0.0
	while ts.state == TaxiService.S.RIDE and f < 60 * 150:
		await get_tree().physics_frame
		f += 1
		top = maxf(top, taxi.get_speed())
		if f == 20 or f == 40 or f == 90:
			print("RAYDBG early f=%d pos=%s v=%s fwdspd=%.2f gear=%d thr=%.2f brk=%.2f hb=%s reason=%d" % [f, str(taxi.global_position), str(taxi.linear_velocity), taxi.get_forward_speed(), taxi.gear, taxi.input_throttle, taxi.input_brake, str(taxi.input_handbrake), ts.drv.stop_reason])
		if f == 600:
			var xfd := taxi.global_transform
			var fw := -xfd.basis.z
			for off in [0.0, 0.6, -0.6]:
				var o: Vector3 = xfd.origin + Vector3.UP * 0.7 + xfd.basis.x * off
				var hit := Util.raycast(taxi, o, o + fw * 8.0, 0xFFFF, [taxi])
				print("RAYDBG off=%.1f fwd=%s hit=%s" % [off, str(fw), str(hit.get("collider", null)) + " at " + str(hit.get("position", Vector3.ZERO))])
			for vv in get_tree().get_nodes_in_group(GC.G_VEHICLE):
				if vv != taxi and vv.global_position.distance_to(taxi.global_position) < 14.0:
					print("RAYDBG near vehicle ", vv.name, " ", vv.global_position, " ", vv.get("def_id"))
			for cb in taxi.get_colliding_bodies():
				print("RAYDBG colliding ", cb.name, " ", cb.get_class(), " layer=", cb.collision_layer, " pos=", cb.global_position if cb is Node3D else "")
			print("RAYDBG gear=", taxi.gear, " rpm=", taxi.rpm, " fwdspd=", taxi.get_forward_speed(), " health=", taxi.health, "/", taxi.max_health, " pscale=", taxi.power_scale, " thr=", taxi.input_throttle, " brk=", taxi.input_brake, " driver=", taxi.driver)
			print("RAYDBG wheels ", taxi.wheels.size(), " lin_vel=", taxi.linear_velocity, " sleeping=", taxi.sleeping, " freeze=", taxi.freeze, " mass=", taxi.mass)
			print("RAYDBG route p0..3 ", ts.drv.P.slice(0, 4), " dirs ", [RoutePlanner.graph().positions[ts.drv.P[0]], RoutePlanner.graph().positions[ts.drv.P[3]]])
		if OS.get_cmdline_user_args().has("--short") and f > 700:
			return
		if f % 120 == 0 and f <= 1200 or f % 600 == 0:
			print("RIDE t=%d pos=%s spd=%.1f rem=%.1f mode=%d reason=%d seg=%d P=%d arrived=%s idle=%.1f thr=%.2f brk=%.2f hb=%s eng=%s ai=%s" % [f / 60, str(taxi.global_position), taxi.get_speed(), ts.drv.remaining(), ts.drv.mode, ts.drv.stop_reason, ts.drv.seg, ts.drv.P.size(), str(ts.drv.arrived), ts.drv.idle_t, taxi.input_throttle, taxi.input_brake, str(taxi.input_handbrake), str(taxi.engine_on), str(taxi.is_ai_controlled)])
	report("taxi_trip_done", ts.state == TaxiService.S.ARRIVED, "ride %.0f s top speed %.1f m/s" % [f / 60.0, top])
	var end_lane := RoutePlanner.nearest_lane(taxi.global_position, Vector3.ZERO, 12.0)
	var dist_to_dest: float = Util.dist_xz(taxi.global_position, pick["pos"])
	report("taxi_at_destination", dist_to_dest < 60.0, "%.0f m from the named location" % dist_to_dest)
	var spent := cash0 - Game.cash
	report("taxi_fare_charged", spent == int(pick.get("fare", -1)), "cash %d -> %d (fare %d)" % [cash0, Game.cash, int(pick.get("fare", 0))])
	await _frames(30)
	await _press(&"enter_exit")
	await _frames(40)
	report("taxi_player_out", not pl.is_in_vehicle(), "in vehicle=%s" % str(pl.is_in_vehicle()))
	f = 0
	while ts.state != TaxiService.S.IDLE and f < 60 * 125:
		await get_tree().physics_frame
		f += 1
	report("taxi_cleanup", ts.state == TaxiService.S.IDLE, "state=%d after %.0f s" % [ts.state, f / 60.0])
	# refusal with a wanted level
	var w = Game.sys(&"wanted")
	if w != null:
		w.set_level(2)
		var r: bool = tr.call_taxi()
		report("taxi_refused_when_wanted", not r and ts.state == TaxiService.S.IDLE)
		w.clear()
	# skip: call again, board, start, skip
	ok = tr.call_taxi()
	f = 0
	while ts.state == TaxiService.S.APPROACH and f < 60 * 140:
		await get_tree().physics_frame
		f += 1
	if ts.state == TaxiService.S.WAITING:
		pl.teleport_to(ts.taxi.global_position + ts.taxi.global_transform.basis.x * 2.6 + Vector3(0, 0.3, 0))
		await _frames(5)
		await _press(&"enter_exit")
		await _frames(120)
		if Game.ui != null and Game.ui.is_menu_open():
			Game.ui.close_menu()
		var ds: Array = ts._build_destinations()
		ds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["len"]) > float(b["len"]))
		ts.state = TaxiService.S.CHOOSE
		ts._start_trip(ds[0])
		await _frames(120)
		ts._skip()
		f = 0
		while ts.state == TaxiService.S.RIDE and f < 60 * 20:
			await get_tree().physics_frame
			f += 1
		report("taxi_skip", ts.state == TaxiService.S.ARRIVED, "skip arrived after %.1f s, dist to destination %.0f m" % [f / 60.0, Util.dist_xz(ts.taxi.global_position, ds[0]["pos"])])
		ts.reset()
	print("TAXI TEST DONE")
