extends Node
## Developer scratch probe for the air vehicles (prints telemetry). Not part of the regression set.
##   exec -Script res://gta/tests/air_dbg.gd -GameArgs "--scen=runway --id=plane_prop"
var T := VehicleTestUtil


func run(main: Node) -> String:
	var tree := get_tree()
	var args := OS.get_cmdline_user_args()
	var scen := "pitch"
	var id := &"plane_prop"
	for a in args:
		if String(a).begins_with("--scen="):
			scen = String(a).substr(7)
		if String(a).begins_with("--id="):
			id = StringName(String(a).substr(5))
	if scen == "showcase":
		var vs2 = Game.sys(&"vehicles")
		for i in 60 * 14:
			if vs2 != null and vs2.air_sea_vehicles.size() >= 6:
				break
			await tree.physics_frame
		for k in 8:
			await T.frames(tree, 60)
			for n in tree.get_nodes_in_group(GC.G_VEHICLE):
				if n is HeliVehicle:
					var hv := n as HeliVehicle
					print("DBG show t=%d %s pos=(%.1f,%.2f,%.1f) gnd=%d agl=%.2f frozen=%s freeze=%s sleep=%s vy=%.2f rpm=%.2f" % [k, hv.def_id, hv.global_position.x, hv.global_position.y, hv.global_position.z, hv.grounded_count, hv.agl, hv._frozen_until_ground, hv.freeze, hv.sleeping, hv.linear_velocity.y, hv.rotor_rpm])
		var loc2: Dictionary = WorldLayout.get_location(&"helipad_hospital")
		var space2 := get_viewport().world_3d.direct_space_state
		var excl: Array[RID] = []
		for k in 6:
			var q := PhysicsRayQueryParameters3D.create(loc2["pos"] + Vector3(3.5, 10, 1.0), loc2["pos"] + Vector3(3.5, -25, 1.0), 0xFFFFF)
			q.exclude = excl
			var hit := space2.intersect_ray(q)
			if hit.is_empty():
				break
			var col: Object = hit.collider
			print("DBG show ray hit %d: y=%.2f layer=%d class=%s name=%s parent=%s shape=%d" % [k, hit.position.y, (col as CollisionObject3D).collision_layer, col.get_class(), (col as Node).name, (col as Node).get_parent().name, hit.shape])
			excl.append((col as CollisionObject3D).get_rid())
		return "done"
	if scen == "topspeed":
		T.make_floor(main, 40000.0)
		await T.frames(tree, 10)
		var jv := T.spawn(id, Vector3(0, 300, 0), -90.0, {"ai": true, "engine_on": true, "abandoned": true, "snap_ground": false}) as PlaneVehicle
		jv.set_velocity(Vector3(200, 0, 0))
		await T.frames(tree, 30)
		var y_start := jv.global_position.y
		for i in 60 * 30:
			_in(jv, 1.0, 0.0)
			var dy := y_start - jv.global_position.y
			jv.input_pitch = clampf(dy * 0.04 - jv.linear_velocity.y * 0.08, -0.3, 0.3)
			await tree.physics_frame
		for i in 60 * 8:
			_in(jv, 0.7)
			await tree.physics_frame
			if i % 30 == 0:
				var b2 := jv.global_transform.basis
				var vel2 := jv.linear_velocity
				print("DBG top t=%.1f y=%.0f spd=%.0f gamma=%.1f pitch=%.1f aoa=%.1f g=%.2f thr=%.2f flap=%.2f" % [i / 60.0, jv.global_position.y, vel2.length(), rad_to_deg(atan2(vel2.y, Vector2(vel2.x, vel2.z).length())), rad_to_deg(AirCommon.pitch_of(b2)), rad_to_deg(jv.aoa), jv.g_load, jv.throttle_state, jv.flap])
		T.remove_all(tree)
		return "done"
	if scen == "turn":
		T.make_floor(main, 40000.0)
		await T.frames(tree, 10)
		var v := T.spawn(id, Vector3(0, 300, 0), -90.0, {"ai": true, "engine_on": true, "abandoned": true, "snap_ground": false}) as PlaneVehicle
		var sp0 := 70.0 if id == &"plane_prop" else 200.0
		for a in args:
			if String(a).begins_with("--speed="):
				sp0 = float(String(a).substr(8))
		v.set_velocity(Vector3(sp0, 0, 0))
		await T.frames(tree, 30)
		for i in 60 * 4:
			_in(v, 0.8, 0.0)
			await tree.physics_frame
		var rl := 0.7
		for a in args:
			if String(a).begins_with("--roll="):
				rl = float(String(a).substr(7))
		for i in 60 * 10:
			_in(v, 0.8, 0.0, rl)
			await tree.physics_frame
			if i % 30 == 0:
				var b := v.global_transform.basis
				var vel := v.linear_velocity
				var gamma := atan2(vel.y, Vector2(vel.x, vel.z).length())
				print("DBG turn t=%.1f y=%.0f spd=%.0f gamma=%.1f pitch=%.1f bank=%.1f aoa=%.1f stalled=%.2f g=%.2f thr=%.2f" % [i / 60.0, v.global_position.y, vel.length(), rad_to_deg(gamma), rad_to_deg(AirCommon.pitch_of(b)), rad_to_deg(AirCommon.bank_of(b)), rad_to_deg(v.aoa), v.stalled, v.g_load, v.throttle_state])
		T.remove_all(tree)
		return "done"
	if scen == "runway":
		# the showcase plane on the real runway (real world colliders), AI throttle + rotation like the player test
		var vs = Game.sys(&"vehicles")
		for i in 60 * 14:
			if vs != null and vs.air_sea_vehicles.size() >= 6:
				break
			await tree.physics_frame
		await T.frames(tree, 120)
		var pl: PlaneVehicle = null
		for n in tree.get_nodes_in_group(GC.G_VEHICLE):
			if n is PlaneVehicle and n.def_id == id:
				pl = n
		if pl == null:
			return "no plane"
		pl.set_ai_controlled(true)
		pl.set_engine(true)
		var rot := pl.stall_speed * 1.1
		var rotated := false
		var manual := OS.get_cmdline_user_args().has("--manual")
		var lift_x := -1.0
		var y302 := -1.0
		var hp0 := pl.health
		var x_start := pl.global_position.x
		for i in 60 * 14:
			pl.input_throttle = 1.0
			var spd := pl.linear_velocity.length()
			if spd > rot and not rotated and pl.grounded_count > 0:
				rotated = true
			pl.input_pitch = 1.0 if (manual and rotated and pl.grounded_count > 0) else 0.0
			await tree.physics_frame
			if lift_x < 0.0 and pl.grounded_count == 0 and i > 30:
				lift_x = pl.global_position.x
			if y302 < 0.0 and pl.global_position.x >= 301.0:
				y302 = pl.global_position.y
			if i % 60 == 0 and i < 60 * 9 and OS.get_cmdline_user_args().has("--verbose"):
				print("DBG rw t=%.0f x=%.0f y=%.1f spd=%.0f pitch=%.1f gnd=%d" % [i / 60.0, pl.global_position.x, pl.global_position.y, spd * 3.6, rad_to_deg(AirCommon.pitch_of(pl.global_transform.basis)), pl.grounded_count])
			if pl.is_destroyed:
				break
		print("DBG SUM %s lift_x=%.0f (run %.0f m) y@x301=%.1f m damage=%.0f destroyed=%s" % [id, lift_x, lift_x - x_start, y302, hp0 - pl.health, pl.is_destroyed])
		return "done"
	T.make_floor(main)
	await T.frames(tree, 10)
	var v := T.spawn(id, Vector3(0, 300, 0), -90.0, {"ai": true, "engine_on": true, "abandoned": true, "snap_ground": false}) as PlaneVehicle
	v.set_velocity(Vector3(70, 0, 0))
	await T.frames(tree, 30)
	if scen == "pitch":
		for i in 60 * 3:
			_in(v, 0.8, 0.0)
			await tree.physics_frame
		print("DBG start pitch=%.1f speed=%.1f" % [rad_to_deg(AirCommon.pitch_of(v.global_transform.basis)), v.linear_velocity.length()])
		for i in 60 * 3:
			_in(v, 1.0, 1.0)
			await tree.physics_frame
			if i % 15 == 0:
				var lav := v.global_transform.basis.inverse() * v.angular_velocity
				print("DBG t=%.2f pitch=%.1f aoa=%.1f speed=%.1f stalled=%.2f lav=%s bank=%.1f y=%.0f" % [i / 60.0, rad_to_deg(AirCommon.pitch_of(v.global_transform.basis)), rad_to_deg(v.aoa), v.linear_velocity.length(), v.stalled, str(lav), rad_to_deg(AirCommon.bank_of(v.global_transform.basis)), v.global_position.y])
	T.remove_all(tree)
	return "done"


func _in(v: VehicleBase, thr: float, pitch := 0.0, roll := 0.0, yaw := 0.0, brake := 0.0) -> void:
	v.input_throttle = thr
	v.input_pitch = pitch
	v.input_roll = roll
	v.input_yaw = yaw
	v.input_steer = yaw
	v.input_brake = brake
