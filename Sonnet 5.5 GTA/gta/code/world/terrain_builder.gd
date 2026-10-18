class_name TerrainBuilder
extends RefCounted
## Builds the terrain mesh + trimesh collider from the baked LayoutTerrain grid (identical triangles for render and physics),
## vertex colours (r = sand, g = rock, b = urban paving, a = noise seed) drive world_terrain.gdshader.

const SHADER := "res://gta/generated/shaders/world_terrain.gdshader"

static var material: ShaderMaterial = null


static func get_material() -> ShaderMaterial:
	if material == null:
		material = ShaderMaterial.new()
		material.resource_name = "WorldTerrain"
		var sh: Shader = load(SHADER)
		if sh == null:
			push_warning("TerrainBuilder: missing shader %s - falling back to a plain material" % SHADER)
		else:
			material.shader = sh
	return material


static func build(parent: Node3D) -> StaticBody3D:
	var NX := LayoutTerrain.NX
	var NZ := LayoutTerrain.NZ
	var CELL := LayoutTerrain.CELL
	var H := LayoutTerrain.heights
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(NX * NZ)
	norms.resize(NX * NZ)
	cols.resize(NX * NZ)
	uvs.resize(NX * NZ)
	for iz in NZ:
		var z := LayoutTerrain.Z0 + iz * CELL
		for ix in NX:
			var x := LayoutTerrain.X0 + ix * CELL
			var i := iz * NX + ix
			var h := H[i]
			var hl := H[iz * NX + maxi(ix - 1, 0)]
			var hr := H[iz * NX + mini(ix + 1, NX - 1)]
			var hd := H[maxi(iz - 1, 0) * NX + ix]
			var hu := H[mini(iz + 1, NZ - 1) * NX + ix]
			var n := Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized()
			verts[i] = Vector3(x, h, z)
			norms[i] = n
			cols[i] = _classify(x, z, h, n)
			uvs[i] = Vector2(x, z)
	var idx := PackedInt32Array()
	idx.resize((NX - 1) * (NZ - 1) * 6)
	var faces_by := {&"grass": PackedVector3Array(), &"sand": PackedVector3Array(), &"rock": PackedVector3Array(), &"concrete": PackedVector3Array()}
	var k := 0
	for iz in NZ - 1:
		for ix in NX - 1:
			var i00 := iz * NX + ix
			var i10 := i00 + 1
			var i01 := i00 + NX
			var i11 := i01 + 1
			idx[k] = i00
			idx[k + 1] = i10
			idx[k + 2] = i01
			idx[k + 3] = i10
			idx[k + 4] = i11
			idx[k + 5] = i01
			k += 6
			# collider surface of this cell from the vertex classification (sand / rock / urban paving / grass)
			var c0 := cols[i00]
			var c1 := cols[i11]
			var sand_w := (c0.r + c1.r + cols[i10].r + cols[i01].r) * 0.25
			var rock_w := (c0.g + c1.g + cols[i10].g + cols[i01].g) * 0.25
			var urb_w := (c0.b + c1.b + cols[i10].b + cols[i01].b) * 0.25
			var surf := &"grass"
			if sand_w > 0.5:
				surf = &"sand"
			elif rock_w > 0.5:
				surf = &"rock"
			elif urb_w > 0.5:
				surf = &"concrete"
			var fa: PackedVector3Array = faces_by[surf]
			fa.append(verts[i00])
			fa.append(verts[i10])
			fa.append(verts[i01])
			fa.append(verts[i10])
			fa.append(verts[i11])
			fa.append(verts[i01])
			faces_by[surf] = fa
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, get_material())
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.extra_cull_margin = 8.0
	parent.add_child(mi)
	var main_body: StaticBody3D = null
	for surf_name in faces_by:
		var fa2: PackedVector3Array = faces_by[surf_name]
		if fa2.is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "Terrain_" + String(surf_name)
		body.collision_layer = GC.L_WORLD
		body.collision_mask = 0
		body.set_meta("surface", surf_name)
		body.add_to_group(&"world_ground")
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(fa2)
		var cs := CollisionShape3D.new()
		cs.name = "TerrainShape"
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)
		if surf_name == &"grass":
			main_body = body
	return main_body


static func _classify(x: float, z: float, h: float, n: Vector3) -> Color:
	var sand := 0.0
	var rock := 0.0
	var urban := 0.0
	# sea bed + beach sand
	if h < -0.9:
		sand = 1.0
	elif z > 120.0:
		var q := LayoutTerrain.wq(x)
		var t := z - LayoutTerrain.shore_edge(x)
		sand = LayoutGeo.smoothstep(-3.0, 2.0, t) * (1.0 - q)
	# steep slopes + altitude -> rock
	var slope := 1.0 - n.y
	rock = LayoutGeo.smoothstep(0.17, 0.42, slope)
	rock = maxf(rock, LayoutGeo.smoothstep(34.0, 52.0, h) * 0.55)
	if z > 185.0 and h < 0.5:
		rock = maxf(rock, LayoutGeo.smoothstep(0.1, 0.3, slope))   # quay wall faces
	# urban paving under blocks / yards
	urban = maxf(urban, _rect_w(x, z, -108.0, -92.0, 108.0, 134.0, 5.0))        # downtown
	urban = maxf(urban, _rect_w(x, z, 108.0, -62.0, 330.0, 86.0, 5.0))          # industrial
	urban = maxf(urban, _rect_w(x, z, 100.0, 86.0, 330.0, 136.0, 5.0))          # airport apron + buildings
	urban = maxf(urban, _rect_w(x, z, -330.0, 90.0, -100.0, 192.0, 5.0))        # waterfront
	urban *= (1.0 - sand)
	urban *= (1.0 - rock)
	# quay faces + the slope behind the quay rim read as concrete
	var q2 := LayoutTerrain.wq(x)
	if q2 > 0.5 and z > 189.0 and z < 199.0:
		urban = 1.0
		sand = 0.0
		rock = 0.0
	return Color(sand, rock, urban, LayoutGeo.vnoise(x * 0.11, z * 0.11, 2))


static func _rect_w(x: float, z: float, x0: float, z0: float, x1: float, z1: float, soft: float) -> float:
	var dx := minf(x - x0, x1 - x)
	var dz := minf(z - z0, z1 - z)
	return clampf(minf(dx, dz) / soft, 0.0, 1.0)
