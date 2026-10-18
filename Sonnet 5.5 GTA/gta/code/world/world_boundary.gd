class_name WorldBoundary
extends RefCounted
## World edge treatment: invisible walls for ground entities (the east wall is low over the runway extension so aircraft can
## leave), a far ocean around the near sea, and a mountain / hill ring (backdrop) beyond the playable terrain.

const WALL_IN := 302.0           # inner face distance (x/z) of the invisible walls
const WALL_SOUTH := 398.0        # sea limit for boats / swimmers
const BOX_X := 330.0             # terrain mesh half extents
const BOX_Z0 := -330.0
const BOX_Z1 := 420.0
const FAR := 3200.0


static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Boundary"
	parent.add_child(root)
	_walls(root)
	_far_ocean(root)
	_backdrop(root)
	return root


static func _wall(body: StaticBody3D, name_: String, center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = name_
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = center
	body.add_child(cs)


static func _walls(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "BoundaryWalls"
	body.collision_layer = GC.L_WORLD
	body.collision_mask = 0
	body.set_meta("surface", &"concrete")
	body.set_meta("invisible_wall", true)
	root.add_child(body)
	var h := 60.0                     # from y=-30 to y=30
	var cy := 0.0
	var t := 10.0
	_wall(body, "WallN", Vector3(0, cy, -(WALL_IN + t * 0.5)), Vector3(2.0 * (WALL_IN + t), h, t))
	_wall(body, "WallW", Vector3(-(WALL_IN + t * 0.5), cy, 45.0), Vector3(t, h, 2.0 * WALL_IN + 190.0))
	_wall(body, "WallS", Vector3(0, cy, WALL_SOUTH + t * 0.5), Vector3(2.0 * (WALL_IN + t), h, t))
	# east wall: tall in two pieces, low section over the runway extension (aircraft taking off over the edge)
	var ez0 := -(WALL_IN + t)
	var ez1 := 132.0
	var ez2 := 198.0
	var ez3 := WALL_SOUTH + t
	_wall(body, "WallE1", Vector3(WALL_IN + t * 0.5, cy, (ez0 + ez1) * 0.5), Vector3(t, h, ez1 - ez0))
	_wall(body, "WallE3", Vector3(WALL_IN + t * 0.5, cy, (ez2 + ez3) * 0.5), Vector3(t, h, ez3 - ez2))
	_wall(body, "WallE2Low", Vector3(WALL_IN + t * 0.5, -12.0, (ez1 + ez2) * 0.5), Vector3(t, 36.0, ez2 - ez1))


static func _far_ocean(root: Node3D) -> void:
	var mat := WaterBuilder.get_material()
	var strips := [
		[Rect2(330.0, 100.0, FAR - 330.0, FAR - 100.0), Vector2(60, 60)],
		[Rect2(-FAR, 100.0, FAR - 330.0, FAR - 100.0), Vector2(60, 60)],
		[Rect2(-330.0, 430.0, 660.0, FAR - 430.0), Vector2(30, 30)],
	]
	for s in strips:
		var r: Rect2 = s[0]
		var pm := PlaneMesh.new()
		pm.size = r.size
		pm.subdivide_width = clampi(int(r.size.x / 70.0), 4, 64)
		pm.subdivide_depth = clampi(int(r.size.y / 70.0), 4, 64)
		pm.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "FarOcean"
		mi.mesh = pm
		mi.position = Vector3(r.position.x + r.size.x * 0.5, GC.WATER_LEVEL, r.position.y + r.size.y * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 50.0
		mi.add_to_group(&"water_surface")
		root.add_child(mi)


static func backdrop_height(x: float, z: float) -> float:
	var cx := clampf(x, -BOX_X + 1.0, BOX_X - 1.0)
	var cz := clampf(z, BOX_Z0 + 1.0, BOX_Z1 - 1.0)
	var base := LayoutTerrain.height(cx, cz)
	if absf(x) > BOX_X - 1.0 and z > 150.0:
		# beyond the east / west edge the coast is a gentle slope (a radial grid cannot follow the 4 m quay cliff)
		var gentle := -clampf((z - 188.0) * 0.10, 0.0, 3.0) - maxf(z - 230.0, 0.0) * 0.12
		base = lerpf(base, gentle, LayoutGeo.smoothstep(150.0, 186.0, z))
	var dx := maxf(absf(x) - BOX_X, 0.0)
	var dz := maxf(maxf(BOX_Z0 - z, z - BOX_Z1), 0.0)
	var d := maxf(dx, dz)
	# sea stays sea in the south: keep the sea floor, only the flanks (and far corners) rise into hills
	var land := 1.0
	if z > 185.0:
		land = LayoutGeo.smoothstep(1300.0, 2100.0, absf(x))
		base = lerpf(base, -22.0, LayoutGeo.smoothstep(330.0, 700.0, maxf(d, 0.0)))
	var rise := LayoutGeo.smoothstep(30.0, 950.0, d)
	var n1 := LayoutGeo.vnoise(x / 420.0, z / 420.0, 21)
	var n2 := LayoutGeo.vnoise(x / 170.0, z / 170.0, 22)
	var n3 := LayoutGeo.vnoise(x / 70.0, z / 70.0, 23)
	var m := n1 * 0.62 + n2 * 0.28 + n3 * 0.10
	# keep the runway extension corridor (east, z 130..200) low so aircraft can leave
	var corridor := LayoutGeo.smoothstep(34.0, 110.0, absf(z - 165.0)) if x > 0.0 else 1.0
	var h := base + rise * (35.0 + 330.0 * pow(m, 1.7)) * land * corridor
	h -= 0.18 * (1.0 - LayoutGeo.smoothstep(0.0, 14.0, d + 2.0))
	return h


static func _backdrop(root: Node3D) -> void:
	var c := Vector2(0.0, 45.0)
	var hx := BOX_X - 2.0
	var hz := (BOX_Z1 - BOX_Z0) * 0.5 - 2.0
	var nang := 160
	var nring := 28
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for k in nring + 1:
		var f := pow(float(k) / float(nring), 1.9)
		for i in nang:
			var a := TAU * float(i) / float(nang)
			var dir := Vector2(cos(a), sin(a))
			var r0 := minf(hx / maxf(absf(dir.x), 0.0001), hz / maxf(absf(dir.y), 0.0001))
			var r1 := FAR / maxf(maxf(absf(dir.x), absf(dir.y)), 0.0001)
			var r := lerpf(r0, r1, f)
			var p := c + dir * r
			var h := backdrop_height(p.x, p.y)
			verts.append(Vector3(p.x, h, p.y))
			norms.append(Vector3.UP)
			var rock := LayoutGeo.smoothstep(40.0, 140.0, h)
			var seaf := 1.0 if h < -1.0 else 0.0
			cols.append(Color(seaf, rock, 0.0, LayoutGeo.vnoise(p.x * 0.01, p.y * 0.01, 4)))
	var idx := PackedInt32Array()
	for k in nring:
		for i in nang:
			var i2 := (i + 1) % nang
			var a0 := k * nang + i
			var a1 := k * nang + i2
			var b0 := (k + 1) * nang + i
			var b1 := (k + 1) * nang + i2
			# winding so that the top faces up (clockwise seen from above): outward = increasing ring index
			idx.append_array([a0, b0, a1, a1, b0, b1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, TerrainBuilder.get_material())
	var mi := MeshInstance3D.new()
	mi.name = "BackdropRing"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2000.0
	root.add_child(mi)
