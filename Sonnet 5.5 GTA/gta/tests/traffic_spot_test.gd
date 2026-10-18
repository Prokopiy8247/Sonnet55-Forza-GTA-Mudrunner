extends Node
## Debug scenario: spawn ONE traffic car on a given lane point and print its state every N frames.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/traffic_spot_test.gd -Seconds 60 -GameArgs "--no-peds --time=9.5 --lane=1768 --secs=10 --every=10 --model=sedan"
## Options: --lane=N (lane point) --secs=S --every=F (frames between prints) --model=id --follow (keep the player next to the car)

var tm = null


func _arg(name: String, default_value: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + name + "="):
			return s.substr(name.length() + 3)
		if s == "--" + name:
			return "true"
	return default_value


func run(_main: Node) -> void:
	tm = Game.sys(&"traffic")
	var waited := 0
	while tm.state != 1 and waited < 600:
		await get_tree().physics_frame
		waited += 1
	tm.spawn_enabled = false
	tm.clear_traffic()
	var lane := int(_arg("lane", "0"))
	var secs := float(_arg("secs", "10"))
	var every := int(_arg("every", "10"))
	var models: PackedStringArray = _arg("model", "sedan").split(",")
	for m in models:
		await _one(lane, secs, every, StringName(m))
	print("SPOT DONE")


func _one(lane: int, secs: float, every: int, model: StringName) -> void:
	var G: LaneGraph = WorldLayout.lanes
	var pos: Vector3 = G.positions[lane]
	var dir: Vector3 = G.dirs[lane]
	Game.player.teleport_to(pos - dir * 18.0 + Vector3(-dir.z, 0.0, dir.x) * 3.4 + Vector3(0, 0.6, 0), NAN)
	for i in 20:
		await get_tree().physics_frame
	var v: VehicleBase = null
	for k in 60:
		v = tm.spawn_at_lane(lane, model)
		if v != null:
			break
		await get_tree().physics_frame
	if v == null:
		print("SPOT spawn failed")
		return
	var d: TrafficDriver = tm.get_driver(v)
	print("SPOT lane %d at %s dir %s limit %.1f, path: %s" % [lane, str(pos.snapped(Vector3(0.1, 0.1, 0.1))), str(dir.snapped(Vector3(0.01, 0.01, 0.01))), G.speed_limit[lane], str(d.P.slice(0, 14))])
	for f in int(secs * 60.0):
		await get_tree().physics_frame
		if not is_instance_valid(v) or d.mode == TrafficDriver.MODE_DEAD:
			print("SPOT car gone: reason=%s" % d.released_reason)
			break
		if f % every == 0:
			print("  [%d] %s" % [f, d.debug_string()])
	tm.recycle_driver(d, "recycle")
	await get_tree().physics_frame
