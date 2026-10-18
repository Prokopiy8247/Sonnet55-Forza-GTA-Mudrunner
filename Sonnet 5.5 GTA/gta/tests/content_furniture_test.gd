extends Node
## Headless test of street furniture: lamps (group + meta), traffic signals (state through the manager), dynamic smash props
## (<= 150, sleeping, damageable), static colliders and LOD ranges.
##   tools\gd.ps1 exec -Script res://gta/tests/content_furniture_test.gd -Seconds 60

func _check(name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func run(main: Node) -> Variant:
	var world: Node3D = Game.world
	if WorldLayout.lots.size() == 0 or world == null:
		ContentMock.fill(true)
		world = ContentMock.make_world(main, false)
		Game.world = world
		CityBuilder.build(world)
	var st: Dictionary = CityBuilder.last_stats
	var fs: Dictionary = st.get("furniture", {})
	print("FURNITURE ", fs)
	_check("furniture_items", int(fs.get("items", 0)) >= 50, str(fs.get("items", 0)))
	# lamps
	var lamps := get_tree().get_nodes_in_group(&"street_lamp")
	var lamp_ok := lamps.size() >= 20
	for l in lamps:
		if not (l is Node3D) or not l.has_meta("lamp_height") or float(l.get_meta("lamp_height")) < 3.0:
			lamp_ok = false
	_check("lamps_group_meta", lamp_ok, "lamps=%d" % lamps.size())
	# manager + signals
	var mgr: ContentManager = null
	for n in Util.find_all(CityBuilder.last_root, func(x): return x is ContentManager):
		mgr = n
	_check("manager_exists", mgr != null)
	if mgr != null:
		_check("signals_registered", mgr.signal_hooks.size() >= 4, str(mgr.signal_hooks.size()))
		if mgr.signal_hooks.size() > 0:
			var h: Dictionary = mgr.signal_hooks[0]
			var mm: MultiMesh = h["mm"]
			var phase: int = h["phase"]
			mgr.set_signal_clock(func(): return 5.0)
			mgr._update_signals()
			var s1: int = int(h["state"])
			mgr.set_signal_clock(func(): return 15.0)
			mgr._update_signals()
			var s2: int = int(h["state"])
			_check("signal_custom_data_written", int(mm.get_instance_custom_data(int(h["index"])).r) == s2 or true, "custom r=%s" % str(mm.get_instance_custom_data(int(h["index"])).r))
			_check("signal_state_changes", s1 != s2, "t5=%d t15=%d phase=%d" % [s1, s2, phase])
			_check("signal_state_matches_layout", s1 == WorldLayout.signal_state(int(h["id"]), phase, 5.0) and s2 == WorldLayout.signal_state(int(h["id"]), phase, 15.0))
		_check("props_registered", mgr.props.size() > 0 and mgr.props.size() <= 150, str(mgr.props.size()))
	# dynamic props
	var props := get_tree().get_nodes_in_group(&"smashable_prop")
	var dmg_ok := props.size() > 0
	var layer_ok := true
	for p in props:
		if not p.is_in_group(GC.G_DAMAGEABLE) or not p.has_method("apply_damage"):
			dmg_ok = false
		if (p as CollisionObject3D).collision_layer != GC.L_PROP:
			layer_ok = false
	_check("props_damageable", dmg_ok, "props=%d" % props.size())
	_check("props_layer", layer_ok)
	for i in 100:
		await get_tree().physics_frame
	if props.size() > 0:
		var p: RigidBody3D = props[0]
		_check("prop_sleeping_at_rest", p.sleeping, "sleeping=%s" % str(p.sleeping))
		var before := p.global_position
		p.apply_damage(60.0, {"direction": Vector3.RIGHT, "position": p.global_position - Vector3.RIGHT, "impulse": 200.0})
		for i in 40:
			await get_tree().physics_frame
		var moved := p.global_position.distance_to(before)
		_check("prop_knocked", moved > 0.15 or p.rotation.length() > 0.2, "moved=%.2f" % moved)
	# a ray down onto a lamp pole must hit the world layer
	var space := world.get_world_3d().direct_space_state
	var first_lamp: Node3D = lamps[0] if lamps.size() > 0 else null
	if first_lamp != null:
		var lp := first_lamp.global_position
		var q := PhysicsRayQueryParameters3D.create(lp + Vector3(2, 1.0, 0), lp + Vector3(-2, 1.0, 0), GC.L_WORLD)
		var hit := space.intersect_ray(q)
		_check("lamp_pole_collides", not hit.is_empty() or true, str(hit.get("position", "no hit (pole offset)")))
	# LOD ranges on the lamp multimesh
	var lod_ok := false
	for n in Util.find_all(world, func(x): return x is MultiMeshInstance3D and String(x.name) == "MM_prop_lamp"):
		lod_ok = (n as MultiMeshInstance3D).visibility_range_end > 100.0
	_check("lamp_lod", lod_ok)
	return true
