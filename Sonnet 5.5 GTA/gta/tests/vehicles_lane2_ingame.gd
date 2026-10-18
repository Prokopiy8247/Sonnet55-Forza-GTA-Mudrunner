extends Node
## Spawns lane-2 vehicles through VehicleFactory (runtime paint overrides apply) in front of the player and looks at them with a free camera.
##   $env:VEH_SHOW="ambulance,truck"; tools\gd.ps1 shot -Out screenshots\l2.png -GameArgs "--exec=res://gta/tests/vehicles_lane2_ingame.gd --delay=4 --time=12"
## Env: VEH_SHOW ids, VEH_GAP spacing (m), VEH_YAW extra yaw (deg, default 215 = front three-quarter), VEH_DIST camera distance.


func run(main: Node) -> Variant:
	var ids: PackedStringArray = ["ambulance", "truck"]
	if OS.get_environment("VEH_SHOW") != "":
		ids = OS.get_environment("VEH_SHOW").split(",")
	var gap := 9.0 if OS.get_environment("VEH_GAP") == "" else float(OS.get_environment("VEH_GAP"))
	var yaw := 215.0 if OS.get_environment("VEH_YAW") == "" else float(OS.get_environment("VEH_YAW"))
	var dist := 16.0 if OS.get_environment("VEH_DIST") == "" else float(OS.get_environment("VEH_DIST"))
	var p: Node3D = Game.player
	var pb: Basis = p.global_transform.basis
	var fwd: Vector3 = -pb.z
	var right: Vector3 = pb.x
	var center: Vector3 = p.global_position + fwd * (dist * 0.8)
	var n := ids.size()
	for i in n:
		var off: Vector3 = right * (float(i) - float(n - 1) * 0.5) * gap
		var b: Basis = pb.rotated(Vector3.UP, deg_to_rad(yaw))
		var xf := Transform3D(b, center + off + Vector3(0, 1.0, 0))
		var v = VehicleFactory.spawn(StringName(ids[i]), xf, {"parked": true})
		if v == null:
			push_warning("ingame: spawn failed for " + ids[i])
		elif i == 0 and OS.get_environment("VEH_ENTER") != "":
			await get_tree().create_timer(0.4).timeout
			p.enter_vehicle(v)
			var side := 1.0 if OS.get_environment("VEH_SIDE") == "" else float(OS.get_environment("VEH_SIDE"))
			var cam2 := Camera3D.new()
			cam2.fov = 50.0
			main.add_child(cam2)
			var vp: Vector3 = v.global_position
			var vr: Vector3 = v.global_transform.basis.x
			var vf: Vector3 = -v.global_transform.basis.z
			cam2.global_position = vp + vr * side * dist * 0.5 + vf * 3.0 + Vector3(0, 2.2, 0)
			cam2.look_at(vp + vf * 1.0 + Vector3(0, 1.4, 0), Vector3.UP)
			cam2.make_current()
			for k in 90:
				await get_tree().process_frame
			return true
	var cam := Camera3D.new()
	cam.fov = 55.0
	main.add_child(cam)
	cam.global_position = p.global_position + Vector3(0, 3.2, 0) - fwd * 1.0
	cam.look_at(center + Vector3(0, 1.4, 0), Vector3.UP)
	cam.make_current()
	for i in 90:
		await get_tree().process_frame
	return true
