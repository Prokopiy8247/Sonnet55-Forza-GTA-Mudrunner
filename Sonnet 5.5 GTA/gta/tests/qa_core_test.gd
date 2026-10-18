extends Node
## QA wave-3 regression test: phone-booth lane clearance, police helicopter stand-off ring, 1-star standstill arrest by real foot officers,
## and an error-free run (the harness log is grepped for SCRIPT ERROR afterwards).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/qa_core_test.gd -Seconds 120 -GameArgs "--no-traffic --no-peds --no-hostiles"
## Optional: --only=booths,heli,arrest

var _busted := false
var _busted_t := -1.0
var _t0 := 0.0


func _report(name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _wants(tag: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			return String(a).substr(7).split(",").has(tag)
	return true


func run(main: Node) -> String:
	var tree := get_tree()
	for i in 20:
		await tree.physics_frame
	Events.player_busted.connect(func() -> void:
		_busted = true
		_busted_t = Time.get_ticks_msec() / 1000.0 - _t0)
	if _wants("booths"):
		_t_booths()
	if _wants("heli"):
		await _t_heli(tree)
	if _wants("arrest"):
		await _t_arrest(tree)
	return "done"


func _t_booths() -> void:
	var im = Game.sys(&"interactions")
	if im == null:
		var eco = Game.sys(&"economy")
		if eco != null:
			im = eco.get("interactions")
	if im == null:
		_report("booths_lane_clear", false, "no interaction manager")
		return
	var worst := INF
	var n := 0
	for b in im.booths:
		var d := InteractionUtil.lane_distance(b["pos"])
		worst = minf(worst, d)
		n += 1
	_report("booths_lane_clear", n > 0 and worst >= 2.0, "%d booths, nearest lane centre line %.2f m (limit 2.0)" % [n, worst])
	var d0 := InteractionUtil.lane_distance(Vector3(98.6, 0, 86.2))
	_report("lane_distance_detects_old_booth_spot", d0 < 2.0, "(98.6, 86.2) is %.2f m from a lane centre" % d0)


func _t_heli(tree: SceneTree) -> void:
	var p = Game.player
	if p == null:
		_report("heli_standoff_ring", false, "no player")
		return
	Game.cheats["never_wanted"] = true
	p.teleport_to(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 1.0, 0))
	for i in 30:
		await tree.physics_frame
	var pp: Vector3 = (p as Node3D).global_position
	var heli := PoliceHeliAI.spawn(pp + Vector3(0, 70, 0), {"mode": &"pursue", "target": p, "force": true})
	if heli == null:
		_report("heli_standoff_ring", false, "PoliceHeliAI.spawn returned null")
		return
	var ai := PoliceHeliAI.of(heli)
	ai.level_override = 3
	var min_d := INF
	for i in 60 * 24:
		await tree.physics_frame
		if i > 60 * 12:
			min_d = minf(min_d, Util.dist_xz((heli as Node3D).global_position, (p as Node3D).global_position))
		if i % 240 == 0:
			var hp3: Vector3 = (heli as Node3D).global_position
			print("QA heli t=%d pos=(%.0f, %.0f, %.0f) d_h=%.1f mode=%s destroyed=%s ap_mode=%s minr=%.0f" % [i / 60, hp3.x, hp3.y, hp3.z, Util.dist_xz(hp3, pp), str(ai.mode), str(heli.is_destroyed), str(ai.autopilot.mode), ai.autopilot.follow_min_radius])
	var dh := Util.dist_xz((heli as Node3D).global_position, (p as Node3D).global_position)
	_report("heli_standoff_ring", min_d >= 45.0, "closest horizontal distance after 12 s settle: %.1f m (now %.1f m)" % [min_d, dh])
	PoliceHeliAI.of(heli).despawn()
	Game.cheats["never_wanted"] = false
	for i in 30:
		await tree.physics_frame


func _t_arrest(tree: SceneTree) -> void:
	var p = Game.player
	var w = Game.sys(&"wanted")
	var pol = Game.sys(&"police")
	if p == null or w == null or pol == null:
		_report("one_star_standstill_arrest", false, "missing player/wanted/police")
		return
	_busted = false
	p.teleport_to(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 1.0, 0))
	for i in 60:
		await tree.physics_frame
	_t0 = Time.get_ticks_msec() / 1000.0
	var cleared_at := -1.0
	w.set_level(1)
	var spawn_d := -1.0
	for i in 60 * 85:
		await tree.physics_frame
		if spawn_d < 0.0 and PoliceUnits.count_officers() > 0:
			var off: Node3D = PoliceUnits.officers()[0]
			spawn_d = Util.dist_xz(off.global_position, (p as Node3D).global_position)
		if _busted:
			break
		if Game.wanted_level == 0 and cleared_at < 0.0:
			cleared_at = Time.get_ticks_msec() / 1000.0 - _t0
			break
	_report("one_star_standstill_arrest", _busted, "busted=%s after %.1f s, cleared_without_arrest_at=%.1f, first officer spawned %.0f m away, officers=%d" % [str(_busted), _busted_t, cleared_at, spawn_d, PoliceUnits.count_officers()])
	for i in 200:
		await tree.physics_frame
