class_name VehicleFactory
extends RefCounted
## The single entry point for creating vehicles.
##   var v := VehicleFactory.spawn(&"sedan", Transform3D(Basis(), Vector3(0, 1, 0)), {"paint": Color.RED})
## opts keys (all optional): paint: Color, paint2: Color, finish: StringName (gloss|matte|metallic|pearl|chrome),
##   faction: StringName, ai: bool (traffic-driven: is_ai_controlled, engine on), with_driver: bool (asks PedManager for a driver
##   via create_driver(vehicle) when it offers one), mods: Dictionary, health_ratio: float, engine_on: bool,
##   parked: bool (settled on the ground and put to sleep until touched), snap_ground: bool (default true: drop onto the ground
##   below the transform when a collider exists), abandoned: bool (free to take: no theft crime, default true for debug spawns),
##   owned: bool (player-owned), headlights: bool, keep_engine_on: bool, name: String.
## Returns the VehicleBase (already added to the vehicles container) or null.

## ids that had to use the code-built fallback model (the QA report lists them)
static var fallback_used: Dictionary = {}
static var _info_cache: Dictionary = {}
static var _warned: Dictionary = {}

const CAR_WHEELS: Array[String] = ["Wheel_FL", "Wheel_FR", "Wheel_ML", "Wheel_MR", "Wheel_RL", "Wheel_RR"]
const BIKE_WHEELS: Array[String] = ["Wheel_F", "Wheel_R"]


static func spawn(id: StringName, xform: Transform3D, opts: Dictionary = {}) -> VehicleBase:
	if not VehicleDefs.has(id):
		push_warning("VehicleFactory.spawn: unknown vehicle id '%s'" % id)
		return null
	var def: Dictionary = VehicleDefs.get_def(id)
	if not def.get("implemented", false):
		if not _warned.has(id):
			_warned[id] = true
			push_warning("VehicleFactory.spawn: '%s' (%s) is not implemented yet (later wave)" % [id, def.get("class", "")])
		return null
	var sys = Game.sys(&"vehicles")
	var container: Node = null
	if sys != null and sys.has_method("get_container"):
		container = sys.get_container()
	if container == null:
		container = Game.world if Game.world != null else Game.main
	if container == null:
		push_warning("VehicleFactory.spawn: no container node yet")
		return null
	var v: VehicleBase = null
	if sys != null and sys.has_method("take_from_pool"):
		v = sys.take_from_pool(id)
	if v == null:
		v = _build(def)
		if v == null:
			return null
	var xf := xform
	var ground_ok := true
	if opts.get("snap_ground", true) and container.is_inside_tree():
		var snap := _snap_to_ground(container, xform)
		xf = snap["xf"]
		ground_ok = snap["hit"]
	v.transform = xf
	if v.get_parent() == null:
		container.add_child(v)
	_apply_opts(v, def, opts)
	if v.is_inside_tree():
		v.place_at(xf)
	if not ground_ok and opts.get("require_ground", false):
		# the world has no collider here yet: hold the body still until ground appears (VehicleBase._check_ground_ready)
		v.freeze = true
		v._frozen_until_ground = true
	if sys != null and sys.has_method("register_vehicle"):
		sys.register_vehicle(v)
	Events.vehicle_spawned.emit(v)
	return v


static func despawn(vehicle: Node) -> void:
	if not is_instance_valid(vehicle):
		return
	var sys = Game.sys(&"vehicles")
	if sys != null and sys.has_method("release_vehicle"):
		sys.release_vehicle(vehicle)
	else:
		Events.vehicle_removed.emit(vehicle)
		vehicle.queue_free()


# =====================================================================================================
static func _snap_to_ground(container: Node, xf: Transform3D) -> Dictionary:
	var c3 := container as Node3D
	if c3 == null or not c3.is_inside_tree():
		return {"xf": xf, "hit": false}
	var space := c3.get_world_3d().direct_space_state
	var from := xf.origin + Vector3.UP * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, GC.M_GROUND)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {"xf": xf, "hit": false}
	var out := xf
	out.origin.y = hit.position.y + 0.03
	return {"xf": out, "hit": true}


static func _apply_opts(v: VehicleBase, def: Dictionary, opts: Dictionary) -> void:
	v.faction = opts.get("faction", def.get("faction", GC.F_CIVILIAN))
	if v.faction == GC.F_POLICE and not v.is_in_group(GC.G_POLICE):
		v.add_to_group(GC.G_POLICE)
	var paints: Array = def.get("paints", [])
	var c1: Color = opts.get("paint", paints[Game.rng.randi() % paints.size()] if not paints.is_empty() else Color(0.75, 0.15, 0.15))
	var c2: Color = opts.get("paint2", Color(0.1, 0.1, 0.12) if not opts.has("paint") else c1.darkened(0.55))
	var fin: StringName = opts.get("finish", &"gloss")
	v.set_paint(c1, c2, fin)
	v.health = v.max_health * clampf(float(opts.get("health_ratio", 1.0)), 0.01, 1.0)
	v._update_damage_state()
	var default_free: bool = not opts.get("ai", false) and not opts.get("parked", false)
	v.abandoned = bool(opts.get("abandoned", default_free or opts.get("owned", false)))
	v.is_player_owned = bool(opts.get("owned", false))
	v.keep_engine_on = bool(opts.get("keep_engine_on", false))
	if opts.has("mods"):
		v.apply_mods(opts["mods"])
	if opts.get("ai", false):
		v.set_ai_controlled(true)
		v.set_engine(true)
		v.keep_engine_on = true
	if opts.get("engine_on", false):
		v.set_engine(true)
	v.headlights_on = bool(opts.get("headlights", Game.is_night() and opts.get("ai", false)))
	if opts.has("name"):
		v.display_name = String(opts["name"])
	if opts.get("parked", false):
		v.set_meta("parked", true)
		v._pending_sleep = true
	if opts.get("with_driver", false):
		var peds = Game.sys(&"peds")
		if peds != null and peds.has_method("create_driver"):
			var d = peds.create_driver(v)
			if d != null:
				v.enter(d, 0)
		elif not _warned.has(&"driver"):
			_warned[&"driver"] = true
			push_warning("VehicleFactory: with_driver requested but PedManager.create_driver() is not available yet")


# =====================================================================================================
static func _build(def: Dictionary) -> VehicleBase:
	var id: StringName = def["id"]
	var cls: StringName = def["class"]
	var v: VehicleBase
	if cls == GC.VC_BIKE or cls == GC.VC_BICYCLE:
		v = BikeVehicle.new()
	elif cls == GC.VC_HELI:
		v = HeliVehicle.new()
	elif cls == GC.VC_PLANE:
		v = PlaneVehicle.new()
	elif cls == GC.VC_BOAT:
		v = BoatVehicle.new()
	else:
		v = CarVehicle.new()
	v.def_id = id
	v.def = def
	v.vclass = cls
	v.faction = def.get("faction", GC.F_CIVILIAN)
	v.display_name = String(def.get("name", String(id)))
	v.name = "Veh_" + String(id)
	v.max_health = float(def.get("health", 1000.0))
	v.health = v.max_health
	# ---- model (Blender GLB or logged fallback)
	var model: Node3D = null
	if ModelLib.exists(String(def["model"])):
		model = ModelLib.instance(String(def["model"]))
	if model == null:
		model = VehicleFallback.build(def)
		if not fallback_used.has(id):
			push_warning("VehicleFactory: using the CODE-BUILT FALLBACK model for '%s' (vehicles GLB '%s' missing)" % [id, def["model"]])
		fallback_used[id] = true
		ModelLib.missing[String(def["model"])] = int(ModelLib.missing.get(String(def["model"]), 0)) + 1
	else:
		fallback_used.erase(id)
	var is_air_sea: bool = cls == GC.VC_HELI or cls == GC.VC_PLANE or cls == GC.VC_BOAT
	var info := AirCommon.model_info(id, model, def) if is_air_sea else get_model_info(id, model, def)
	# ---- rigid body setup
	v.collision_layer = GC.L_VEHICLE
	v.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP
	v.gravity_scale = float(def.get("gravity_scale", 1.15))
	v.can_sleep = true
	v.continuous_cd = true
	v.contact_monitor = true
	v.max_contacts_reported = 4
	v.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	v.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	v.linear_damp = 0.0
	v.angular_damp = 0.25
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.04
	v.physics_material_override = pm
	v._bind_model(model, info)
	for i in info["boxes"].size():
		var b: Dictionary = info["boxes"][i]
		var cs := CollisionShape3D.new()
		cs.name = "Col%d" % i
		var bs := BoxShape3D.new()
		bs.size = b["size"]
		cs.shape = bs
		cs.position = b["pos"]
		v.add_child(cs)
	if is_air_sea:
		v.call(&"setup_air")              # HeliVehicle / PlaneVehicle / BoatVehicle (Air&Sea agent)
	else:
		(v as CarVehicle).setup_physics()
	if v is BikeVehicle:
		(v as BikeVehicle).setup_bike()
	# ---- components
	v.lights = VehicleLights.new()
	v.lights.setup(v)
	v.audio = VehicleAudio.new()
	v.audio.setup(v)
	v.dmg = VehicleDamage.new()
	v.dmg.setup(v)
	v._stagger = int(v.get_instance_id() % 30)
	return v


## Wheel positions / radii, collision boxes and body extents, derived once per vehicle id from the first built model.
static func get_model_info(id: StringName, model: Node3D, def: Dictionary) -> Dictionary:
	if _info_cache.has(id):
		return _info_cache[id]
	var is_bike: bool = def["class"] == GC.VC_BIKE or def["class"] == GC.VC_BICYCLE
	var wheel_nodes: Array[Node3D] = []
	var wheel_infos: Array = []
	for wn in (BIKE_WHEELS if is_bike else CAR_WHEELS):
		var node := model.find_child(wn, true, false) as Node3D
		if node == null:
			continue
		wheel_nodes.append(node)
		var xf := Util._rel_transform(model, node)
		var bb := _subtree_aabb(model, node)
		var radius := maxf(bb.size.y, bb.size.z) * 0.5 if bb.size.x > 0.0 else float(def.get("wheel_radius", 0.33))
		if radius < 0.1 or radius > 1.2:
			radius = float(def.get("wheel_radius", 0.33))
		wheel_infos.append({"name": StringName(wn), "pos": xf.origin, "basis": xf.basis, "radius": radius, "width": maxf(bb.size.x, 0.05)})
	if wheel_infos.size() < 2:
		push_warning("VehicleFactory: model '%s' has no Wheel_* nodes - synthesising wheel positions from the def" % id)
		var wb: float = def["wheelbase"]
		var xs: float = float(def["track"]) * 0.5
		var r: float = def["wheel_radius"]
		wheel_infos.clear()
		if is_bike:
			wheel_infos = [
				{"name": &"Wheel_F", "pos": Vector3(0, r, -wb * 0.5), "basis": Basis.IDENTITY, "radius": r, "width": 0.16},
				{"name": &"Wheel_R", "pos": Vector3(0, r, wb * 0.5), "basis": Basis.IDENTITY, "radius": r, "width": 0.16}]
		else:
			wheel_infos = [
				{"name": &"Wheel_FL", "pos": Vector3(-xs, r, -wb * 0.5), "basis": Basis.IDENTITY, "radius": r, "width": 0.22},
				{"name": &"Wheel_FR", "pos": Vector3(xs, r, -wb * 0.5), "basis": Basis.IDENTITY, "radius": r, "width": 0.22},
				{"name": &"Wheel_RL", "pos": Vector3(-xs, r, wb * 0.5), "basis": Basis.IDENTITY, "radius": r, "width": 0.22},
				{"name": &"Wheel_RR", "pos": Vector3(xs, r, wb * 0.5), "basis": Basis.IDENTITY, "radius": r, "width": 0.22}]
	# vertices of everything that is not a wheel -> body extents + collision boxes
	var verts := PackedVector3Array()
	for mi in ModelLib.meshes(model):
		var skip := false
		for wn2 in wheel_nodes:
			if wn2 == mi or wn2.is_ancestor_of(mi):
				skip = true
				break
		if skip or mi.mesh == null:
			continue
		var mxf := Util._rel_transform(model, mi)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vv = arr[Mesh.ARRAY_VERTEX]
			if vv == null:
				continue
			for p in (vv as PackedVector3Array):
				verts.append(mxf * p)
	var info := {"wheels": wheel_infos, "boxes": _make_boxes(verts, def, is_bike), "vert_count": verts.size()}
	_info_cache[id] = info
	return info


static func _subtree_aabb(model: Node3D, node: Node3D) -> AABB:
	var have := false
	var out := AABB()
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var xf := Util._rel_transform(model, n as Node3D)
			var bb := xf * (n as MeshInstance3D).get_aabb()
			out = bb if not have else out.merge(bb)
			have = true
		for c in n.get_children():
			stack.append(c)
	return out


static func _make_boxes(verts: PackedVector3Array, def: Dictionary, is_bike: bool) -> Array:
	var l: float = def["length"]
	var w: float = def["width"]
	var h: float = def["height"]
	var boxes: Array = []
	if verts.size() < 8:
		boxes.append({"pos": Vector3(0, 0.3 + (h - 0.3) * 0.25, 0), "size": Vector3(w, (h - 0.3) * 0.5, l)})
		boxes.append({"pos": Vector3(0, 0.3 + (h - 0.3) * 0.75, l * 0.05), "size": Vector3(w * 0.88, (h - 0.3) * 0.5, l * 0.5)})
		return boxes
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for p in verts:
		mn = mn.min(p)
		mx = mx.max(p)
	if is_bike:
		var bottom := maxf(mn.y, 0.25)
		var top := minf(mx.y, bottom + 0.95)
		var bw := 0.42 if def["class"] == GC.VC_BIKE else 0.22
		boxes.append({"pos": Vector3(0, (bottom + top) * 0.5, (mn.z + mx.z) * 0.5), "size": Vector3(bw, top - bottom, (mx.z - mn.z) * 0.78)})
		return boxes
	var bottom_y := maxf(mn.y, 0.26)
	var split := bottom_y + (mx.y - bottom_y) * 0.54
	var lo_mn := Vector3(INF, INF, INF)
	var lo_mx := Vector3(-INF, -INF, -INF)
	var up_mn := Vector3(INF, INF, INF)
	var up_mx := Vector3(-INF, -INF, -INF)
	var up_n := 0
	for p in verts:
		if p.y < split:
			lo_mn = lo_mn.min(p)
			lo_mx = lo_mx.max(p)
		else:
			up_mn = up_mn.min(p)
			up_mx = up_mx.max(p)
			up_n += 1
	var lo_w := minf(lo_mx.x - lo_mn.x, w + 0.1) - 0.06
	var lo_len := (lo_mx.z - lo_mn.z) - 0.08
	boxes.append({"pos": Vector3((lo_mx.x + lo_mn.x) * 0.5, (bottom_y + split) * 0.5, (lo_mx.z + lo_mn.z) * 0.5), "size": Vector3(maxf(lo_w, 0.5), maxf(split - bottom_y, 0.2), maxf(lo_len, 1.0))})
	if up_n > 12:
		var up_w := (up_mx.x - up_mn.x) * 0.9
		var up_len := (up_mx.z - up_mn.z) * 0.96
		boxes.append({"pos": Vector3((up_mx.x + up_mn.x) * 0.5, (split + up_mx.y) * 0.5, (up_mx.z + up_mn.z) * 0.5), "size": Vector3(maxf(up_w, 0.4), maxf(up_mx.y - split, 0.15), maxf(up_len, 0.5))})
	return boxes
