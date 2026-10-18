class_name ParkedCars
extends RefCounted
## ~56 curb-side parking slots chosen once from the lane graph (right edge of ordinary streets, never near junctions, never on the
## fast arterial): downtown / residential / industrial plus a few at the harbour, airport and beach. Cars are parked parallel to the
## road with two wheels on the curb, random models and colours, ASLEEP (VehicleBase parked flag: no physics until touched), and
## are spawned / despawned by distance (< SPAWN_DIST) so the node count stays low. They are full VehicleBase instances:
## the player can steal them (not abandoned -> normal vehicle-theft crime), traffic squeezes past them with a lateral side-step.

const TARGET_SLOTS := 56
const SPAWN_DIST := 135.0
const DESPAWN_DIST := 170.0
const CURB_OVERLAP := 0.65        # how far the car's outer side overlaps the sidewalk (m)
const QUOTA := {
	&"downtown": 20, &"residential": 16, &"industrial": 9, &"waterfront": 4, &"airport": 3, &"beach": 2, &"park_hills": 2,
}
const MIX := {
	&"downtown": {&"sedan": 2.0, &"compact": 1.8, &"suv": 1.0, &"taxi": 0.6, &"van": 0.6, &"pickup": 0.4, &"muscle": 0.25},
	&"residential": {&"compact": 2.2, &"sedan": 1.8, &"suv": 1.6, &"pickup": 1.0, &"van": 0.5, &"muscle": 0.3},
	&"industrial": {&"pickup": 2.0, &"van": 2.0, &"truck": 1.3, &"sedan": 0.8, &"suv": 0.5},
	&"default": {&"sedan": 1.6, &"compact": 1.3, &"suv": 1.2, &"pickup": 1.0, &"van": 0.6},
}

var slots: Array = []
var rng := RandomNumberGenerator.new()
var spawner: TrafficSpawner = null
var mgr: Node = null
var stats := {"slots": 0, "live": 0, "spawned": 0, "despawned": 0, "displaced": 0, "blocked": 0, "stolen": 0}
var _shape: BoxShape3D = null
var _query: PhysicsShapeQueryParameters3D = null
var _check_t := 0.0


func build(sp: TrafficSpawner, seed_value: int = 7731) -> void:
	spawner = sp
	rng.seed = seed_value
	slots.clear()
	if not TrafficNet.ensure():
		return
	var G: LaneGraph = WorldLayout.lanes
	var by_district: Dictionary = {}
	for i in G.size():
		if G.kind[i] != LaneGraph.KIND_STRAIGHT:
			continue
		if TrafficNet.near_junction[i] != 0:
			continue
		var sp_lim: float = G.speed_limit[i]
		if sp_lim > 14.5 or sp_lim < 8.0:
			continue
		var p: Vector3 = G.positions[i]
		var d: StringName = WorldLayout.district_at(p.x, p.z)
		if d == GC.D_SEA:
			continue
		if not by_district.has(d):
			by_district[d] = []
		(by_district[d] as Array).append(i)
	var chosen: Array[Vector3] = []
	for d in QUOTA:
		var list: Array = by_district.get(d, [])
		_shuffle(list)
		var want: int = QUOTA[d]
		var got := 0
		for i2 in list:
			if got >= want:
				break
			var slot := _make_slot(G, i2, d)
			if slot.is_empty():
				continue
			var sp2: Vector3 = slot["pos"]
			var too_close := false
			for c in chosen:
				if Vector2(c.x - sp2.x, c.z - sp2.z).length() < 9.0:
					too_close = true
					break
			if too_close:
				continue
			chosen.append(sp2)
			slots.append(slot)
			got += 1
	stats["slots"] = slots.size()
	print("[Traffic] parked car slots: %d" % slots.size())


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _make_slot(G: LaneGraph, i: int, d: StringName) -> Dictionary:
	var p: Vector3 = G.positions[i]
	var dir: Vector3 = G.dirs[i]
	var ri := WorldLayout.road_at(p.x, p.z, 9.0)
	if ri.is_empty() or not bool(ri.get("on_road", false)):
		return {}
	var id := _pick_id(d)
	var def := VehicleDefs.get_def(id)
	var half_w := float(def.get("width", 1.8)) * 0.5
	var off := float(ri["half_width"]) - float(ri["dist"]) + CURB_OVERLAP - half_w
	if off < 0.4 or off > 3.4:
		return {}
	var right := Vector3(-dir.z, 0.0, dir.x)
	var pos := p + right * off
	var yaw := Util.dir_to_yaw(dir) + rng.randf_range(-0.035, 0.035)
	pos += dir * rng.randf_range(-1.5, 1.5)
	var opts := spawner.pick_paint(id, rng) if spawner != null else {}
	return {"pos": pos, "yaw": yaw, "id": id, "opts": opts, "veh": null, "state": 0, "cool": 0.0, "bad": false, "district": d, "lane": i}


func _pick_id(d: StringName) -> StringName:
	var table: Dictionary = MIX.get(d, MIX[&"default"])
	var total := 0.0
	for id in table:
		if VehicleDefs.is_implemented(id):
			total += float(table[id])
	var r := rng.randf() * total
	for id in table:
		if not VehicleDefs.is_implemented(id):
			continue
		r -= float(table[id])
		if r <= 0.0:
			return id
	return &"sedan"


# ---- runtime ------------------------------------------------------------------------------------------------------------------
## Spawns every slot within range at once (game start / teleport); `visible_check` false = ignore the camera.
func populate_all(centre: Vector3, now: float, max_spawns: int = 99) -> int:
	return update(centre, now, max_spawns, false)


## Periodic pass (~4 Hz): despawn far cars, free displaced / stolen ones, spawn at most `budget` new ones.
func update(centre: Vector3, now: float, budget: int, check_visible: bool = true) -> int:
	var spawned := 0
	var live := 0
	for s in slots:
		var sp: Vector3 = s["pos"]
		var dx := sp.x - centre.x
		var dz := sp.z - centre.z
		var d2 := dx * dx + dz * dz
		var veh = s["veh"]
		if veh != null:
			if not is_instance_valid(veh) or not veh.is_inside_tree():
				s["veh"] = null
				s["state"] = 0
				continue
			live += 1
			if _is_taken(veh, s):
				s["veh"] = null
				s["state"] = 2
				s["cool"] = now + 420.0
				stats["stolen" if veh.driver != null else "displaced"] += 1
				if mgr != null:
					mgr.add_orphan(veh)
				continue
			if d2 > DESPAWN_DIST * DESPAWN_DIST:
				if not (check_visible and mgr != null and d2 < 200.0 * 200.0 and mgr.is_seen(veh.global_position)):
					VehicleFactory.despawn(veh)
					s["veh"] = null
					s["state"] = 0
					stats["despawned"] += 1
			continue
		if s["bad"] or (int(s["state"]) == 2 and now < float(s["cool"])):
			continue
		if d2 > SPAWN_DIST * SPAWN_DIST or spawned >= budget:
			continue
		if check_visible and d2 > 25.0 * 25.0 and d2 < 95.0 * 95.0 and mgr != null and mgr.is_seen(sp):
			continue
		if d2 < 9.0 * 9.0:
			continue
		var r := _spawn_slot(s)
		if r:
			spawned += 1
			live += 1
	stats["live"] = live
	return spawned


func _is_taken(veh, s: Dictionary) -> bool:
	if veh.driver != null or veh.is_ai_controlled or veh.is_destroyed:
		return true
	var sp: Vector3 = s["pos"]
	if Vector2(veh.global_position.x - sp.x, veh.global_position.z - sp.z).length() > 2.2:
		return true
	return false


func _spawn_slot(s: Dictionary) -> bool:
	var pos: Vector3 = s["pos"]
	var id: StringName = s["id"]
	var def := VehicleDefs.get_def(id)
	if Game.world == null:
		return false
	var space: PhysicsDirectSpaceState3D = Game.world.get_world_3d().direct_space_state
	if _shape == null:
		_shape = BoxShape3D.new()
		_query = PhysicsShapeQueryParameters3D.new()
		_query.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP
	var y := WorldLayout.terrain_height(pos.x, pos.z)
	_shape.size = Vector3(float(def.get("width", 1.8)) - 0.1, 0.5, float(def.get("length", 4.5)) - 0.2)
	_query.shape = _shape
	_query.transform = Transform3D(Basis(Vector3.UP, float(s["yaw"])), Vector3(pos.x, y + 0.75, pos.z))
	var hits := space.intersect_shape(_query, 3)
	for h in hits:
		var col = h.get("collider", null)
		if col is VehicleBase:
			return false                         # try again later (someone is parked / driving there)
		if col != null:
			# the query box floats 0.5 m above the road / curb, so any other hit is a pole, hydrant, tree, bench or wall: slot unusable
			s["bad"] = true
			stats["blocked"] += 1
			return false
	var opts: Dictionary = (s["opts"] as Dictionary).duplicate()
	opts["parked"] = true
	opts["require_ground"] = true
	var xf := Transform3D(Basis(Vector3.UP, float(s["yaw"])), Vector3(pos.x, y + 0.2, pos.z))
	var v := VehicleFactory.spawn(id, xf, opts)
	if v == null:
		s["bad"] = true
		return false
	v.set_meta("traffic_parked", true)
	s["veh"] = v
	s["state"] = 1
	stats["spawned"] += 1
	return true


func clear_all() -> void:
	for s in slots:
		var veh = s["veh"]
		if veh != null and is_instance_valid(veh) and veh.driver == null:
			VehicleFactory.despawn(veh)
		s["veh"] = null
		s["state"] = 0


func live_vehicles() -> Array[VehicleBase]:
	var out: Array[VehicleBase] = []
	for s in slots:
		var veh = s["veh"]
		if veh != null and is_instance_valid(veh):
			out.append(veh)
	return out
