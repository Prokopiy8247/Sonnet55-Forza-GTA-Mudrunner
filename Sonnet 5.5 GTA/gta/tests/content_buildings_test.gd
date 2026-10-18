extends Node
## Headless test of the building pipeline: mock layout -> CityBuilder.build -> checks instances, colliders, timing, LOD ranges.
##   tools\gd.ps1 exec -Script res://gta/tests/content_buildings_test.gd -Seconds 40

func _check(name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func run(main: Node) -> Variant:
	var use_real: bool = WorldLayout.lots.size() > 0 and Game.world != null
	var world: Node3D = Game.world
	if not use_real:
		ContentMock.fill(true)
		world = ContentMock.make_world(main, false)
		Game.world = world
		var t0 := Time.get_ticks_msec()
		CityBuilder.build(world)
		var dt := Time.get_ticks_msec() - t0
		_check("build_time", dt <= 4000, "%d ms" % dt)
	var st: Dictionary = CityBuilder.last_stats
	print("STATS ", st)
	_check("buildings_built", int(st.get("buildings", 0)) >= 20, str(st.get("buildings", 0)))
	_check("kit_modules_used", int(st.get("kit_parts", 0)) >= 30, "kit parts registered=%s" % str(st.get("kit_parts", 0)))
	_check("instances", int(st.get("instances", 0)) > 2000, str(st.get("instances", 0)))
	_check("multimesh_count", int(st.get("multimeshes", 0)) > 5 and int(st.get("multimeshes", 0)) < 900, str(st.get("multimeshes", 0)))
	_check("colliders", int(st.get("colliders", 0)) >= 20, str(st.get("colliders", 0)))
	var root: Node3D = world
	_check("content_root", CityBuilder.last_root != null)
	# every MultiMeshInstance3D must have a mesh with materials on every surface
	var bad := 0
	var mmis := 0
	var far_ok := false
	var near_lod_ok := false
	for n in Util.find_all(world, func(x): return x is MultiMeshInstance3D):
		mmis += 1
		var mmi := n as MultiMeshInstance3D
		var mesh := mmi.multimesh.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			bad += 1
			continue
		for s in mesh.get_surface_count():
			if mesh.surface_get_material(s) == null:
				bad += 1
		if String(mmi.name) == "MM_far_box" and mmi.visibility_range_begin > 100.0:
			far_ok = true
		if String(mmi.name).begins_with("MM_K_Office_Bay_Window") and mmi.visibility_range_end > 100.0:
			near_lod_ok = true
	_check("meshes_have_materials", bad == 0, "bad=%d of %d" % [bad, mmis])
	_check("far_lod_range", far_ok)
	_check("near_lod_range", near_lod_ok)
	# helipad hosted on one tower
	var heli := 0
	for n in Util.find_all(world, func(x): return x is MultiMeshInstance3D and (String(x.name) == "MM_helipad" or String(x.name) == "MM_K_Roof_Helipad_Pad")):
		heli += (n as MultiMeshInstance3D).multimesh.instance_count
	_check("helipad_tower", heli == 1, "helipads=%d" % heli)
	# collision: a ray from above the tallest mock tower must hit the world layer
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(30, 100, 30), Vector3(30, -5, 30), GC.L_WORLD)
	var hit := space.intersect_ray(q)
	_check("collision_ray", not hit.is_empty(), str(hit.get("position", "none")))
	print("FALLBACKS ", ContentLib.fallbacks)
	return true
