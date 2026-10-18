extends Node
## Interiors test (Shops/Interiors agent): world doors, enter / exit transitions for every interior, position restore, indoor flags,
## camera sanity, lazy build time, triangle budgets, leak check over 10 enter / exit cycles, opening hours, wanted block.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/shop_interior_test.gd -Seconds 120 -GameArgs "--no-intro --no-traffic --no-peds"

var _fails := 0
var _passes := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		print("TEST ", name, " PASS ", detail)
	else:
		_fails += 1
		print("TEST ", name, " FAIL ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func run(main: Node) -> void:
	await _frames(20)
	var shops = Game.sys(&"shops")
	var it = Game.sys(&"interiors")
	var sh = Game.sys(&"safehouse")
	var p = Game.player
	_ok("boot_systems", shops != null and it != null and sh != null and is_instance_valid(p), "shops=%s interiors=%s safehouse=%s" % [shops != null, it != null, sh != null])
	if it == null or not is_instance_valid(p):
		print("TEST ABORT no interiors / player")
		return
	var ids: Array = it.list_interiors()
	_ok("registered", ids.size() >= 7, str(ids))
	# ---- world doors
	for id in [&"weapon_shop", &"clothing_store", &"barber", &"gas_station", &"scuba_shop", &"safehouse", &"safehouse_garage"]:
		var d = it.door_for(id)
		var loc_id: StringName = &"safehouse" if id == &"safehouse_garage" else id
		var loc: Dictionary = WorldLayout.get_location(loc_id)
		var dist: float = d.global_position.distance_to(loc["pos"]) if d != null and not loc.is_empty() else 999.0
		_ok("door_" + String(id), d != null and dist < 14.0, "dist to location %.1f m" % dist)
	# ---- prompts / hours
	Game.time_of_day = 12.0
	var wd = it.door_for(&"weapon_shop")
	var info: Dictionary = wd.get_interaction(p)
	_ok("prompt_open", bool(info.get("enabled", false)) and String(info.get("text", "")).begins_with("Enter"), str(info))
	Game.time_of_day = 2.0
	info = wd.get_interaction(p)
	_ok("prompt_closed_night", not bool(info.get("enabled", true)) and String(info.get("text", "")).contains("Closed"), str(info))
	var gd = it.door_for(&"gas_station")
	_ok("gas_station_24h", bool(gd.get_interaction(p).get("enabled", false)), str(gd.get_interaction(p)))
	Game.time_of_day = 12.0
	# ---- enter / exit every interior
	var start_pos: Vector3 = WorldLayout.get_location(&"weapon_shop")["pos"]
	p.teleport_to(start_pos + Vector3(0, 0.3, 0), 0.0)
	await _frames(30)
	for id in [&"weapon_shop", &"clothing_store", &"barber", &"gas_station", &"scuba_shop", &"safehouse", &"safehouse_garage"]:
		var door = it.door_for(id)
		var ret: Vector3 = door.data["return"]
		p.teleport_to(ret + Vector3(0, 0.3, 0), float(door.data["yaw"]))
		await _frames(20)
		var t0 := Time.get_ticks_msec()
		var entered: bool = await it.enter(id, ret, float(door.data["yaw"]), true)
		var room: InteriorRoom = it.get_room(id, false)
		_ok("enter_" + String(id), entered and it.is_inside() and it.current_interior == id and room != null, "build %.1f ms" % (room.build_ms if room != null else -1.0))
		if room == null:
			continue
		await _frames(10)
		var inside_ok: bool = p.global_position.distance_to(room.to_global(room.spawn_pos)) < 3.0 and absf(p.global_position.y - room.global_position.y) < 1.0
		_ok("inside_position_" + String(id), inside_ok, "player %s spawn %s" % [str(p.global_position.snappedf(0.1)), str(room.to_global(room.spawn_pos).snappedf(0.1))])
		_ok("indoor_flag_" + String(id), bool(Game.get_meta(&"indoors", false)) and Game.get_meta(&"interior_id", &"") == id)
		var on_floor: bool = p.is_on_floor()
		_ok("on_floor_" + String(id), on_floor, "floor=%s" % on_floor)
		var cam: Camera3D = Game.gameplay_camera
		_ok("camera_inside_" + String(id), is_instance_valid(cam) and cam.global_position.y > room.global_position.y and cam.global_position.y < room.global_position.y + room.size.y + 0.5
			and absf(cam.global_position.x - room.global_position.x) < room.size.x * 0.5 + 0.5, "cam %s" % str(cam.global_position.snappedf(0.1)))
		var bl: Dictionary = it.build_log.get(id, {})
		_ok("tris_" + String(id), int(bl.get("tris", 99999)) < (4600 if id == &"safehouse" else 2600), "tris=%d surfaces=%d lights=%d build=%.1f ms" % [int(bl.get("tris", -1)), int(bl.get("surfaces", -1)), int(bl.get("lights", -1)), float(bl.get("ms", -1.0))])
		_ok("build_time_" + String(id), float(bl.get("ms", 999.0)) < 150.0, "%.1f ms" % float(bl.get("ms", -1.0)))
		_ok("exit_door_" + String(id), room.exit_door != null and room.exit_door.is_inside_tree(), "")
		var exited: bool = await it.exit(true)
		await _frames(10)
		var back: float = p.global_position.distance_to(ret)
		_ok("exit_" + String(id), exited and not it.is_inside() and back < 0.6, "distance to door %.2f m" % back)
		_ok("outdoor_flag_" + String(id), not bool(Game.get_meta(&"indoors", false)))
	# ---- leak check: nodes under the InteriorSystem + orphans + the whole tree must not grow over 10 enter / exit cycles
	await _frames(10)
	var door2 = it.door_for(&"weapon_shop")
	var ret2: Vector3 = door2.data["return"]
	await it.enter(&"weapon_shop", ret2, float(door2.data["yaw"]), true)       # first entry builds the room (not a leak)
	await _frames(3)
	await it.exit(true)
	await _frames(10)
	var sys_before := _count(it)
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var ui_before := _count(Game.ui)
	for i in 10:
		await it.enter(&"weapon_shop", ret2, float(door2.data["yaw"]), true)
		await _frames(2)
		await it.exit(true)
		await _frames(2)
	await _frames(10)
	var sys_after := _count(it)
	var orphans_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var ui_after := _count(Game.ui)
	_ok("no_leak_10_cycles", sys_after == sys_before and orphans_after <= orphans_before + 60 and ui_after == ui_before, "interior nodes %d -> %d, orphans %d -> %d, ui nodes %d -> %d" % [sys_before, sys_after, orphans_before, orphans_after, ui_before, ui_after])
	_ok("position_restored_after_cycles", p.global_position.distance_to(ret2) < 0.6, str(p.global_position.distance_to(ret2)))
	# ---- vehicle / wanted blocks
	Game.wanted_level = 2
	Game.wanted_state = &"pursuit"
	it._world_door_use(&"weapon_shop", door2)
	await _frames(5)
	_ok("blocked_when_wanted", not it.is_inside() and not it.transitioning)
	Game.wanted_level = 0
	Game.wanted_state = &"clear"
	# ---- full (non instant) transition with fades
	var t1 := Time.get_ticks_msec()
	var full: bool = await it.enter(&"gas_station", ret2, 0.0, false)
	var enter_ms := Time.get_ticks_msec() - t1
	_ok("enter_with_fade", full and it.is_inside(), "%d ms" % enter_ms)
	var ex: bool = await it.exit(false)
	_ok("exit_with_fade", ex and not it.is_inside(), "")
	# ---- hospital / police station: toast-only doors
	var toasts: Array[String] = []
	Events.notification.connect(func(t: String, _k: StringName) -> void: toasts.append(t))
	var toast_doors: Array = it._toast_doors
	_ok("toast_doors_exist", toast_doors.size() >= 2, "%d doors" % toast_doors.size())
	for td in toast_doors:
		td.interact(p)
	_ok("toast_doors_notify", toasts.size() >= 2 and not it.is_inside(), str(toasts.size()))
	# ---- double enter is ignored, exit door interactable leaves with the real fade
	var gd2 = it.door_for(&"barber")
	var ret3: Vector3 = gd2.data["return"]
	var res := [false]
	var runner := func() -> void:
		res[0] = await it.enter(&"barber", ret3, float(gd2.data["yaw"]), true)
	runner.call()
	var second: bool = await it.enter(&"gas_station", ret3, float(gd2.data["yaw"]), true)
	var tw := Time.get_ticks_msec()
	while (it.transitioning or not it.is_inside()) and Time.get_ticks_msec() - tw < 4000:
		await get_tree().process_frame
	_ok("double_enter_ignored", bool(res[0]) and not second and it.current_interior == &"barber", "first=%s second=%s id=%s" % [str(res[0]), str(second), str(it.current_interior)])
	await _frames(10)
	var broom: InteriorRoom = it.get_current_room()
	broom.exit_door.interact(p)
	var tt := Time.get_ticks_msec()
	while it.is_inside() and Time.get_ticks_msec() - tt < 4000:
		await get_tree().process_frame
	await _frames(5)
	_ok("exit_door_interact_leaves", not it.is_inside() and p.global_position.distance_to(ret3) < 0.8 and not bool(Game.get_meta(&"indoors", false)), "dist %.2f" % p.global_position.distance_to(ret3))
	var tl := Time.get_ticks_msec()
	while it.transitioning and Time.get_ticks_msec() - tl < 4000:
		await get_tree().process_frame
	_ok("input_unlocked_after_exit", not bool(p.input_locked), "")
	# ---- the player is teleported out by something else (death respawn) while inside: indoor state is dropped by itself
	await it.enter(&"gas_station", ret3, float(gd2.data["yaw"]), true)
	await _frames(5)
	var sh2 = Game.sys(&"safehouse")
	sh2.respawn_here = false
	p.respawn_at(&"hospital", {"silent": true, "reason": &"death"})
	await _frames(40)
	_ok("external_teleport_drops_indoor_state", not it.is_inside() and not bool(Game.get_meta(&"indoors", false)) and not it.transitioning, "inside=%s meta=%s transitioning=%s" % [str(it.is_inside()), str(Game.get_meta(&"indoors", false)), str(it.transitioning)])
	var env = Game.sys(&"environment")
	if env != null and env.get("world_environment") is WorldEnvironment:
		_ok("outdoor_environment_restored", (env.get("world_environment") as WorldEnvironment).environment != null and it._env_swapped == null, "")
	sh2.respawn_here = true
	print("TEST SUMMARY pass=%d fail=%d" % [_passes, _fails])
	print("TEST interiors stats ", it.get_stats())
