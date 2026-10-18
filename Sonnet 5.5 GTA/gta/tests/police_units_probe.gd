extends Node
## Scratch probe (Police-B): 1-star standstill with the real director, prints the foot officers' state every 2 s.
func run(main: Node) -> String:
	await get_tree().process_frame
	Game.cheats["invulnerable"] = true
	var w = Game.sys(&"wanted")
	var pl = Game.player
	pl.teleport_to(Vector3(10.0, 0.3, 40.0), 0.0)
	pl.weapons.equip(&"fists")
	await get_tree().create_timer(1.5).timeout
	PoliceCarAI.debug_names = true
	w.set_level(1)
	for s in 25:
		await get_tree().create_timer(2.0).timeout
		var line := "TEST probe t=%d lvl=%d state=%s seen=%s heat=%.1f lk=%s |" % [s * 2, w.level, w.state, w.is_player_seen(), w.heat, str(w.get_last_known_position())]
		for o in PoliceUnits.officers():
			var po := o as PoliceOfficer
			if po.is_in_vehicle():
				continue
			var wp: Vector3 = po.mover.path[po.mover.path_i] if po.mover.path_i < po.mover.path.size() else po.mover.goal
			if po.mover.stuck_time > 0.3:
				var dirw := (wp - po.global_position)
				dirw.y = 0.0
				dirw = dirw.normalized()
				var sp := po.get_world_3d().direct_space_state
				var rq := PhysicsRayQueryParameters3D.create(po.global_position + Vector3(0, 0.5, 0), po.global_position + Vector3(0, 0.5, 0) + dirw * 3.0, GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP)
				var rh := sp.intersect_ray(rq)
				if not rh.is_empty():
					var cc: Node = rh["collider"]
					line += " <BLOCK %s/%s d=%.1f>" % [cc.get_parent().name if cc.get_parent() else "", cc.name, po.global_position.distance_to(rh["position"])]
			line += " [%s %s/%s d=%.0f pos=(%.0f,%.1f,%.0f) wp=(%.0f,%.0f,%.0f) i=%d/%d stuck=%s st=%.1f v=%.1f real=%.1f lod=%d]" % [po.kind, po.mode, po.brain.get_state_name(), Util.dist_xz(po.global_position, pl.global_position),
				po.global_position.x, po.global_position.y, po.global_position.z, wp.x, wp.y, wp.z, po.mover.path_i, po.mover.path.size(), po.mover.stuck, po.mover.stuck_time, po.mover.speed_xz(), Vector2(po.velocity.x, po.velocity.z).length(), po.actor.lod]
		for c in PoliceUnits.police_cars():
			var ai := (c as VehicleBase).get_meta(&"police_ai") as PoliceCarAI
			line += " {car %s v=%.1f d=%.0f pos=(%.0f,%.0f) r=%.0f resp=%s ahead=%.1f %s stuck=%d rev=%s lane=%d thr=%.2f brk=%.2f hb=%s}" % [ai.mode, (c as VehicleBase).get_speed(), Util.dist_xz((c as Node3D).global_position, pl.global_position),
				(c as Node3D).global_position.x, (c as Node3D).global_position.z, ai.search_radius, ai._responding, ai._ahead, ai.ahead_name if ai._ahead < 8.0 else "", ai._stuck_count, ai._now < ai._reverse_until, ai._lane_i,
				(c as VehicleBase).input_throttle, (c as VehicleBase).input_brake, (c as VehicleBase).input_handbrake]
		print(line)
	return "done"
