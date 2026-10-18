extends Node
## Real-renderer render cost of every interior (CPU / GPU ms, draw calls, objects, primitives) + the first-entry build time.
##   powershell -NoProfile -File tools\gd.ps1 game -Seconds 60 -Resolution 1920x1080 -GameArgs "--exec=res://gta/tests/shop_perf.gd --no-traffic --no-peds --no-intro --time=14"
## Prints one "PERFSHOP <id> ..." line per room (and one for the street outside the weapon shop door).


func _measure(label: String, build_ms: float) -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 50:
		await get_tree().process_frame
	var cpu := 0.0
	var gpu := 0.0
	var dc := 0.0
	var obj := 0.0
	var prim := 0.0
	var ft := 0.0
	var worst := 0.0
	var n := 120
	for i in n:
		await get_tree().process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var f := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		ft += f
		worst = maxf(worst, f)
	print("PERFSHOP %-16s build_ms=%5.1f cpu_ms=%.2f gpu_ms=%.2f draw_calls=%d objects=%d prims=%d process_ms=%.2f fps=%d" % [
		label, build_ms, cpu / n, gpu / n, int(dc / n), int(obj / n), int(prim / n), ft / n, Engine.get_frames_per_second()])


func run(_main: Node) -> Variant:
	for i in 90:
		await get_tree().process_frame
	var it = Game.sys(&"interiors")
	var p = Game.player
	if it == null or not is_instance_valid(p):
		print("PERFSHOP abort no interiors")
		return null
	var wd = it.door_for(&"weapon_shop")
	p.teleport_to(wd.data["return"] + Vector3(0, 0.3, 0), float(wd.data["yaw"]) + PI)
	await _measure("street(door)", 0.0)
	for id in it.list_interiors():
		var door = it.door_for(id)
		var ret: Vector3 = door.data["return"] if door != null else p.global_position
		var yaw: float = float(door.data["yaw"]) if door != null else 0.0
		var t0 := Time.get_ticks_usec()
		var had_room: bool = it.get_room(id, false) != null
		await it.enter(id, ret, yaw, true)
		var room: InteriorRoom = it.get_current_room()
		var bms: float = room.build_ms if (room != null and not had_room) else 0.0
		await _measure(String(id), bms)
		await it.exit(true)
		await get_tree().process_frame
	return true
