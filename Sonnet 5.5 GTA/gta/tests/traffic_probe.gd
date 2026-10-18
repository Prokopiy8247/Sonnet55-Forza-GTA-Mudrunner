extends Node
## Debug probe: lists furniture / colliders near a point. powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/traffic_probe.gd -Seconds 20 -GameArgs "--no-peds --at=-2,-55 --r=6"


func _arg(name: String, default_value: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + name + "="):
			return s.substr(name.length() + 3)
	return default_value


func run(_main: Node) -> void:
	for i in 10:
		await get_tree().physics_frame
	var at := _arg("at", "0,0").split(",")
	var c := Vector3(float(at[0]), 0.0, float(at[1]))
	var r := float(_arg("r", "6"))
	print("PROBE at ", c, " r=", r)
	for f in WorldLayout.furniture:
		var p: Vector3 = f["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() < r:
			print("PROBE furniture ", f["kind"], " ", p)
	var space := (Game.world as Node3D).get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, c + Vector3(0, 0.9, 0))
	q.collision_mask = GC.L_WORLD | GC.L_PROP
	var hits := space.intersect_shape(q, 32)
	for h in hits:
		var col = h["collider"]
		var pos = col.global_position if col is Node3D else Vector3.ZERO
		print("PROBE collider ", col, " name=", (col as Node).name, " pos=", pos, " layer=", (col as CollisionObject3D).collision_layer, " meta_surface=", (col as Node).get_meta("surface", ""))
		if not String((col as Node).name).begins_with("Terrain") and not String((col as Node).name).begins_with("Col_"):
			for ch in (col as Node).get_children():
				if ch is CollisionShape3D and (ch as CollisionShape3D).shape != null:
					var sh: Shape3D = (ch as CollisionShape3D).shape
					var info := ""
					if sh is BoxShape3D:
						info = "box " + str((sh as BoxShape3D).size)
					elif sh is CylinderShape3D:
						info = "cyl r=%.2f h=%.2f" % [(sh as CylinderShape3D).radius, (sh as CylinderShape3D).height]
					elif sh is SphereShape3D:
						info = "sphere r=%.2f" % (sh as SphereShape3D).radius
					else:
						info = sh.get_class()
					print("PROBE   shape ", info, " at ", (ch as Node3D).global_position, " parent=", (col as Node).get_parent().name)
	# lane points near
	var G: LaneGraph = WorldLayout.lanes
	for i in G.points_in_radius(c, r + 8.0):
		print("PROBE lane ", i, " pos=", G.positions[i], " dir=", G.dirs[i], " kind=", G.kind[i], " lim=", G.speed_limit[i])
	print("PROBE done")
