class_name VehicleSystem
extends Node
## Vehicle container + bookkeeping (Vehicles agent). Booted by Main: setup(main) once, post_setup() after all systems exist.
## Owns: the "Vehicles" Node3D under Game.world, the shared VehicleFx (skid marks / smoke / fire), the spawn POOL (recycles
## undamaged vehicles by id), the distance LOD pass (visual_lod, real headlight/siren lights only near the camera, engine audio only
## near the camera), the showroom ("dealer_lot": one of every ground vehicle) and two drivable cars near "player_spawn".
## VehicleFactory is the public spawn API; this class is its backend (get_container / take_from_pool / register_vehicle /
## release_vehicle) and offers a few queries for other modules.

static var instance: VehicleSystem = null

const POOL_MAX_PER_ID := 3
const POOL_MAX_TOTAL := 14
const LOD_RADIUS := 120.0
const LIGHT_RADIUS := 65.0
const MAX_DYNAMIC_LIGHT_VEHICLES := 6

var container: Node3D = null
var fx: VehicleFx = null
var dealer_vehicles: Array[VehicleBase] = []
var start_vehicles: Array[VehicleBase] = []
var spawn_world_vehicles := true            # false in tests that build their own scene
var _pool: Dictionary = {}                  # StringName -> Array[VehicleBase]
var _pool_total := 0
var _lod_t := 0.0
var _dyn: Array = []
var _main: Node = null
var stats := {"spawned": 0, "pooled_reuse": 0, "released": 0}


func setup(main: Node) -> void:
	instance = self
	_main = main
	_ensure_container()


func _ensure_container() -> void:
	if is_instance_valid(container):
		return
	container = Node3D.new()
	container.name = "Vehicles"
	var parent: Node = Game.world if Game.world != null else _main
	if parent == null:
		parent = self
	parent.add_child(container)
	fx = VehicleFx.new()
	container.add_child(fx)


func post_setup() -> void:
	_ensure_container()
	if spawn_world_vehicles and not OS.get_cmdline_user_args().has("--no-vehicles"):
		_spawn_world_vehicles()


func get_container() -> Node3D:
	_ensure_container()
	return container


# ---- pool --------------------------------------------------------------------------------------------------------------
func take_from_pool(id: StringName) -> VehicleBase:
	var arr: Array = _pool.get(id, [])
	while not arr.is_empty():
		var v: VehicleBase = arr.pop_back()
		_pool_total -= 1
		if is_instance_valid(v):
			stats["pooled_reuse"] += 1
			return v
	return null


func register_vehicle(v: VehicleBase) -> void:
	stats["spawned"] += 1


## Removes a vehicle from the world: undamaged ones are recycled by VehicleFactory.spawn, wrecks are freed.
func release_vehicle(v: Node) -> void:
	if not is_instance_valid(v):
		return
	Events.vehicle_removed.emit(v)
	stats["released"] += 1
	if v is VehicleBase:
		var vb := v as VehicleBase
		for c in vb.get_occupants():
			vb.exit(c, false)
		_dyn.erase(vb)
		dealer_vehicles.erase(vb)
		start_vehicles.erase(vb)
		var poolable := not vb.is_destroyed and not vb.on_fire and _pool_total < POOL_MAX_TOTAL and vb.health > vb.max_health * 0.25
		var arr: Array = _pool.get(vb.def_id, [])
		if poolable and arr.size() < POOL_MAX_PER_ID and vb.is_inside_tree():
			vb.reset_for_reuse()
			if vb.get_parent() != null:
				vb.get_parent().remove_child(vb)
			arr.append(vb)
			_pool[vb.def_id] = arr
			_pool_total += 1
			return
	v.queue_free()


func clear_pool() -> void:
	for id in _pool:
		for v in _pool[id]:
			if is_instance_valid(v):
				v.queue_free()
	_pool.clear()
	_pool_total = 0


# ---- queries -------------------------------------------------------------------------------------------------------------
func get_vehicles() -> Array[VehicleBase]:
	var out: Array[VehicleBase] = []
	for n in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if n is VehicleBase and n.is_inside_tree():
			out.append(n)
	return out


## Nearest enterable vehicle within max_dist (XZ) of pos, preferring ones whose door is close; null if none.
func find_nearest_vehicle(pos: Vector3, max_dist: float = 4.0, exclude: Node = null) -> VehicleBase:
	var best: VehicleBase = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if n == exclude or not (n is VehicleBase) or not n.is_inside_tree():
			continue
		var vb := n as VehicleBase
		if vb.is_destroyed:
			continue
		# distance to the closest door / entry point (or the body itself)
		var d := Util.dist_xz(vb.global_position, pos) - float(vb.def.get("length", 4.5)) * 0.25
		for i in vb.seats.size():
			d = minf(d, Util.dist_xz(vb.get_entry_position(i), pos))
		if d < best_d:
			best_d = d
			best = vb
	return best


# ---- per-frame bookkeeping -------------------------------------------------------------------------------------------------
func _process(dt: float) -> void:
	_lod_t -= dt
	if _lod_t <= 0.0:
		_lod_t = 0.3
		_lod_pass()


func _camera_pos() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null and is_instance_valid(Game.gameplay_camera):
		cam = Game.gameplay_camera
	if cam != null:
		return cam.global_position
	if is_instance_valid(Game.player):
		return Game.player.global_position
	return Vector3.ZERO


func _lod_pass() -> void:
	var cp := _camera_pos()
	var lit: Array = []
	for n in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if not (n is VehicleBase) or not n.is_inside_tree():
			continue
		var v := n as VehicleBase
		if v.global_position.y < -45.0:
			VehicleFactory.despawn.call_deferred(v)
			continue
		var d := v.global_position.distance_to(cp)
		var lod := 0 if d < LOD_RADIUS * float(v.def.get("lod_mult", 1.0)) else 1       # aircraft / boats stay 'near' (audio, rotors, wake) much farther out
		if lod != v.visual_lod:
			v.visual_lod = lod
			if lod == 1:
				if v.audio != null:
					v.audio.release()
				if v.lights != null:
					v.lights.set_dynamic_lights(false)
		if lod == 0 and d < LIGHT_RADIUS and (v.headlights_on or v.siren_on):
			lit.append([d, v])
	lit.sort_custom(func(a, b): return a[0] < b[0])
	var now: Array = []
	for i in mini(lit.size(), MAX_DYNAMIC_LIGHT_VEHICLES):
		var v2: VehicleBase = lit[i][1]
		now.append(v2)
		if v2.lights != null:
			v2.lights.set_dynamic_lights(true)
	for old in _dyn:
		if is_instance_valid(old) and not now.has(old) and old.lights != null:
			old.lights.set_dynamic_lights(false)
	_dyn = now


# =====================================================================================================
# World vehicles: showroom + two cars near the player spawn
# =====================================================================================================
## One display row along the lot's X axis (the forecourt strip is 12 m deep: even the 8.6 m fire engine fits when parked facing the street).
const SHOWROOM_ORDER: Array = [&"firetruck", &"truck", &"police_tactical", &"ambulance", &"van", &"pickup", &"suv", &"sedan", &"sports",
	&"muscle", &"compact", &"taxi", &"police_cruiser", &"motorcycle", &"bicycle"]
const SHOWROOM_PAINTS: Array[Color] = [Color("#ff3d9a"), Color("#34e0ff"), Color("#ffb347"), Color("#e8e4da"), Color("#c43a3a"), Color("#4b8a5f"), Color("#2f6fb5")]


func _spawn_world_vehicles() -> void:
	# let the world build its colliders first (Jolt needs a physics step to register them)
	var waited := 0
	while not WorldLayout.built and waited < 180:
		await get_tree().physics_frame
		waited += 1
	for i in 8:
		await get_tree().physics_frame
	spawn_showroom()
	spawn_start_cars()
	spawn_air_sea()


func _lot_width(origin: Vector3) -> float:
	for lot in WorldLayout.lots:
		var r: Rect2 = lot.get("rect", Rect2())
		if lot.get("kind", &"") == &"empty" and r.has_point(Vector2(origin.x, origin.z)):
			return r.size.x - 4.0
	return 56.0


func spawn_showroom() -> void:
	var loc: Dictionary = WorldLayout.get_location(&"dealer_lot")
	var origin: Vector3 = loc.get("pos", Vector3(20, 1, 20))
	var yaw: float = float(loc.get("yaw", 0.0))
	if loc.is_empty():
		push_warning("VehicleSystem: location 'dealer_lot' missing - showroom placed near (20,1,20)")
	var b := Basis(Vector3.UP, yaw)
	var right := b * Vector3.RIGHT
	var ids: Array = SHOWROOM_ORDER.filter(func(i): return VehicleDefs.is_implemented(i))
	var sum_w := 0.0
	var widths: Array[float] = []
	for id in ids:
		var w := float(VehicleDefs.get_def(id).get("width", 1.8))
		widths.append(w)
		sum_w += w
	var gap := clampf((_lot_width(origin) - sum_w) / maxf(float(ids.size() - 1), 1.0), 0.45, 1.4)
	var x := -(sum_w + gap * float(ids.size() - 1)) * 0.5
	var paint_i := 0
	for i in ids.size():
		var id: StringName = ids[i]
		var px := x + widths[i] * 0.5
		x += widths[i] + gap
		var xf := Transform3D(b, origin + right * px)
		var opts := {"parked": true, "require_ground": true, "paint": SHOWROOM_PAINTS[paint_i % SHOWROOM_PAINTS.size()], "finish": &"metallic" if paint_i % 3 == 0 else &"gloss"}
		if VehicleDefs.get_def(id).get("paints", []).size() == 1:
			opts.erase("paint")
		paint_i += 1
		var v := VehicleFactory.spawn(id, xf, opts)
		if v != null:
			v.set_meta("dealer", true)
			dealer_vehicles.append(v)
		else:
			push_warning("VehicleSystem: showroom spawn of '%s' failed" % id)
	print("[Vehicles] showroom: %d/%d vehicles at %s (gap %.2f m)" % [dealer_vehicles.size(), ids.size(), origin, gap])


func spawn_start_cars() -> void:
	var loc: Dictionary = WorldLayout.get_location(&"player_spawn")
	var origin: Vector3 = loc.get("pos", Vector3(0, 1, 0))
	var yaw: float = float(loc.get("yaw", 0.0))
	var b := Basis(Vector3.UP, yaw)
	var right := b * Vector3.RIGHT
	var fwd := b * Vector3.FORWARD
	var specs := [[&"sports", Color("#34e0ff"), right * 6.5 + fwd * 3.0], [&"sedan", Color("#ff3d9a"), -right * 6.5 + fwd * 5.0]]
	for s in specs:
		var pos: Vector3 = origin + s[2]
		var v := VehicleFactory.spawn(s[0], Transform3D(b, pos), {"paint": s[1], "finish": &"metallic", "require_ground": true})
		if v != null:
			start_vehicles.append(v)


# =====================================================================================================
# Air & sea showcase vehicles (Air&Sea agent): a helicopter on each helipad, the planes on the runway, a speedboat in the harbour
# =====================================================================================================
var air_sea_vehicles: Array[VehicleBase] = []


func spawn_air_sea() -> void:
	if OS.get_cmdline_user_args().has("--no-air"):
		return
	# [vehicle id, location id, offset (lateral right, forward) in metres in the location's frame, yaw offset deg, opts]
	var specs: Array = [
		[&"heli_civil", &"helipad_downtown", Vector2.ZERO, 0.0, {"paint": Color("#34e0ff"), "finish": &"metallic"}],
		[&"heli_police", &"helipad_hospital", Vector2.ZERO, 0.0, {"abandoned": false}],
		[&"heli_civil", &"helipad_airport", Vector2.ZERO, 0.0, {"paint": Color("#ff3d9a"), "finish": &"metallic"}],
		[&"plane_prop", &"airport_runway_start", Vector2(-6.0, 1.5), 0.0, {"paint": Color("#ffb347"), "finish": &"metallic"}],
		[&"plane_jet", &"airport_runway_start", Vector2(6.0, 2.0), 0.0, {"paint": Color("#e8e4da"), "finish": &"metallic"}],
		[&"speedboat", &"dock_boat_spawn", Vector2.ZERO, 0.0, {"paint": Color("#ff3d9a"), "finish": &"gloss"}],
	]
	for sp in specs:
		var id: StringName = sp[0]
		if not VehicleDefs.is_implemented(id):
			continue
		var loc: Dictionary = WorldLayout.get_location(sp[1])
		if loc.is_empty():
			push_warning("VehicleSystem: location '%s' missing - %s not spawned" % [sp[1], id])
			continue
		var pos: Vector3 = loc["pos"]
		var yaw: float = float(loc.get("yaw", 0.0))
		var b := Basis(Vector3.UP, yaw + deg_to_rad(float(sp[3])))
		pos += Basis(Vector3.UP, yaw) * Vector3(float(sp[2].x), 0.0, -float(sp[2].y))
		var opts := {"parked": true, "abandoned": true, "require_ground": true}
		opts.merge(sp[4], true)
		if id == &"speedboat":
			opts["snap_ground"] = false
			opts["require_ground"] = false
			opts["parked"] = false
			pos.y = GC.WATER_LEVEL + 0.15
		elif loc.get("kind", &"") == &"helipad":
			# rooftop pads are cluttered by roof props: look for a flat, rotor-free spot near the pad centre, else start a hand above it
			var spot := AirCommon.find_clear_pad(self, pos, 5.5 if id != &"heli_police" else 4.6)
			if spot != Vector3.INF:
				pos = spot
			pos.y += 0.6
		var v := VehicleFactory.spawn(id, Transform3D(b, pos), opts)
		if v != null:
			v.set_meta("air_sea_showcase", true)
			air_sea_vehicles.append(v)
		else:
			push_warning("VehicleSystem: air/sea spawn of '%s' failed" % id)
	print("[Vehicles] air/sea: %d/%d spawned" % [air_sea_vehicles.size(), specs.size()])
