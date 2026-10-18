class_name WaterBuilder
extends RefCounted
## Sea surface (stylised shader), park pond, swim/boat volumes (Area3D on GC.L_WATER with meta water_level / is_sea).

const SHADER := "res://gta/generated/shaders/world_water.gdshader"

static var material: ShaderMaterial = null


static func get_material() -> ShaderMaterial:
	if material == null:
		material = ShaderMaterial.new()
		material.resource_name = "WorldWater"
		var sh: Shader = load(SHADER)
		if sh == null:
			push_warning("WaterBuilder: missing shader %s" % SHADER)
		else:
			material.shader = sh
		material.render_priority = -1
	return material


static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Water"
	parent.add_child(root)
	var mat := get_material()
	# sea surface: x -330..330, z 100..430, 4 m cells
	var sea := PlaneMesh.new()
	sea.size = Vector2(660.0, 330.0)
	sea.subdivide_width = 164
	sea.subdivide_depth = 81
	sea.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "SeaSurface"
	mi.mesh = sea
	mi.position = Vector3(0.0, GC.WATER_LEVEL, 265.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	mi.add_to_group(&"water_surface")
	root.add_child(mi)
	# park pond
	var pond := PlaneMesh.new()
	pond.size = Vector2(64.0, 64.0)
	pond.subdivide_width = 16
	pond.subdivide_depth = 16
	pond.material = mat
	var pi := MeshInstance3D.new()
	pi.name = "PondSurface"
	pi.mesh = pond
	pi.position = Vector3(LayoutTerrain.POND_C.x, GC.WATER_LEVEL, LayoutTerrain.POND_C.y)
	pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pi.add_to_group(&"water_surface")
	root.add_child(pi)
	# swim / boat volumes
	for v in WorldLayout.water_volumes:
		var r: Rect2 = v["rect"]
		var a := Area3D.new()
		a.name = "WaterVolume_" + String(v["id"])
		a.collision_layer = GC.L_WATER
		a.collision_mask = GC.L_PLAYER | GC.L_NPC | GC.L_VEHICLE | GC.L_PROP | GC.L_ANIMAL
		a.monitoring = true
		a.monitorable = true
		a.set_meta("water_level", GC.WATER_LEVEL)
		a.set_meta("surface_y", GC.WATER_LEVEL)
		a.set_meta("is_sea", v["kind"] == &"sea")
		a.set_meta("kind", v["kind"])
		a.add_to_group(&"water_volume")
		var depth := 70.0 if v["kind"] == &"sea" else 6.0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, depth, r.size.y)
		cs.shape = box
		a.add_child(cs)
		a.position = Vector3(r.position.x + r.size.x * 0.5, GC.WATER_LEVEL - depth * 0.5, r.position.y + r.size.y * 0.5)
		root.add_child(a)
	return root
