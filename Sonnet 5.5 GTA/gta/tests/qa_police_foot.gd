extends Node
## QA: 1-star standstill. The player stands still, unarmed, in the open; the real director + real officers must arrive on foot and arrest
## BEFORE the wanted level clears. Logs distance / speed / brain state of every foot officer once per second.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/qa_police_foot.gd -Seconds 240 -GameArgs "--no-hostiles"
## Options: --at=x,z[;x,z...] (default 10,40)  --runs=N (default = number of --at positions)  --level=N (default 1)  --limit=sec (default 120)
const Q := preload("res://gta/tests/qa_util.gd")
var q: Q


func run(_main: Node) -> String:
	q = Q.new(self)
	await get_tree().process_frame
	Game.cheats["invulnerable"] = true
	var ats := q.arg("at", "10,40").split(";")
	var runs := int(q.arg("runs", str(ats.size())))
	var level := int(q.arg("level", "1"))
	var limit := float(q.arg("limit", "120"))
	for r in runs:
		var at := ats[r % ats.size()].split(",")
		await _one(r, Vector3(float(at[0]), 0.3, float(at[1])), level, limit)
	print("TEST SUMMARY ", q.summary())
	return q.summary()


func _one(r: int, pos: Vector3, level: int, limit: float) -> void:
	var w = q.wanted()
	var pl = Game.player
	w.clear()
	if q.police() != null:
		q.police().despawn_all()
	await q.seconds(3.0)
	q.tp_player(pos, 0.0)
	pl.weapons.equip(&"fists")
	await q.seconds(2.0)
	var busted := [false]
	var on_busted := func(): busted[0] = true
	Events.player_busted.connect(on_busted)
	w.set_level(level)
	var t := 0.0
	var cleared_at := -1.0
	var first_foot := -1.0
	var first_foot_dist := -1.0
	var max_speed := 0.0
	var spawn_log := {}
	while t < limit and not busted[0]:
		await q.seconds(1.0)
		t += 1.0
		if Game.wanted_level == 0 and cleared_at < 0.0:
			cleared_at = t
			break
		var line := ""
		for o in q.foot_officers():
			var po := o as PoliceOfficer
			var d := Util.dist_xz(po.global_position, pl.global_position)
			var sp: float = po.mover.speed_xz()
			max_speed = maxf(max_speed, sp)
			if first_foot < 0.0:
				first_foot = t
				first_foot_dist = d
			var id := po.get_instance_id()
			if not spawn_log.has(id):
				spawn_log[id] = d
			line += " [%d d=%.0f v=%.1f %s%s]" % [id % 1000, d, sp, po.brain.get_state_name(), " STUCK" if po.mover.stuck else ""]
		if int(t) % 2 == 0 or line != "":
			print("TEST info r%d t=%3d %s |%s" % [r, int(t), q.police_summary(), line])
	Events.player_busted.disconnect(on_busted)
	q.check("police_foot_busted_r%d" % r, busted[0], "busted=%s after %.0f s (cleared_at=%.0f first_foot=%.0f s at %.0f m, max foot speed %.1f m/s, spawn dists=%s)" % [busted[0], t, cleared_at, first_foot, first_foot_dist, max_speed, str(spawn_log.values())])
	await q.seconds(8.0)
	Game.cheats["invulnerable"] = true
	w.clear()
	await q.seconds(3.0)
