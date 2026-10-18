extends Node
## Debug probe (Police-A): do the cars reach an on-foot player?
func run(_main: Node) -> Variant:
	for i in 10:
		await get_tree().physics_frame
	var pm := Game.sys(&"police") as PoliceManager
	var wanted := Game.sys(&"wanted") as WantedSystem
	var player = Game.player
	player.invulnerable = true
	player.use_real_input = false
	wanted.bust_quiet_time = 1e9
	PoliceCarAI.debug_names = true
	player.teleport_to(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	for i in 40:
		await get_tree().physics_frame
	print("DBG player at ", player.global_position)
	wanted.set_level(3)
	var t := 0.0
	var tick := 0
	while t < 40.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		tick += 1
		if tick % 120 == 0:
			for id in pm.units:
				var rec: Dictionary = pm.units[id]
				var n: Node3D = rec["node"]
				if is_instance_valid(n) and rec["kind"] in [&"foot", &"swat"]:
					var o := n as PoliceOfficer
					print("DBG t=%.0f OFFICER %s d=%.0f mode=%s brain=%s goal=%s arrived=%s vel=%.1f in_veh=%s pos=%s" % [t, rec["kind"], Util.dist_xz(n.global_position, player.global_position), o.mode, str(o.brain.state) if o.brain else "-", str(o.mover.has_goal) if o.mover else "-", str(o.mover.arrived) if o.mover else "-", o.velocity.length(), str(o.is_in_vehicle()), str(n.global_position)])
					continue
				if not is_instance_valid(n) or rec["kind"] != &"car":
					continue
				var ai = n.get_meta(&"police_ai") if n.has_meta(&"police_ai") else null
				var spd := 0.0
				if n.has_method("get_speed"):
					spd = n.get_speed()
				print("DBG t=%.0f car role=%s d=%.0f spd=%.1f mode=%s ai_mode=%s stuck=%s ahead=%s(%s) dest=%s" % [t, rec["role"], Util.dist_xz(n.global_position, player.global_position), spd, rec["mode"],
					str(ai.mode) if ai else "-", str(ai._stuck_count) if ai else "-", str(snappedf(ai._ahead, 0.1)) if ai else "-", str(ai.ahead_name) if ai else "-", str(ai._dest) if ai else "-"])
	return true
