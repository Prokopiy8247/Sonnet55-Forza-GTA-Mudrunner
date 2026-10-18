class_name PoliceRoadblock
extends Node3D
## A police roadblock: parked cruisers angled across the whole road plus concrete / road barriers and cones filling the gaps (a car cannot
## squeeze through: tested), 2-4 officers crouched behind the cars aiming at the oncoming traffic (hold order), optionally a tactical van and a
## spike strip in front (levels 4-5). Cleans itself up when the player is far away, the wanted level dropped, or after a time limit.
##
##   PoliceRoadblock.build(center, travel_dir, level) -> PoliceRoadblock   (PoliceUnits.spawn_roadblock forwards here)

const MAX_AGE := 300.0
const FAR_DISTANCE := 260.0
const BARRIER := "props/concrete_barrier"      # 3.0 x 0.8 x 0.6 (long axis X)
const ROAD_BARRIER := "props/road_barrier"     # 1.6 x 1.0 x 0.84
const CONE := "props/road_cone"

var level := 3
var center := Vector3.ZERO
var travel_dir := Vector3(0, 0, -1)          # direction the oncoming traffic / player moves
var axis := Vector3(1, 0, 0)                 # across the road
var half_width := 7.0
var cars: Array[VehicleBase] = []
var officers: Array[PoliceOfficer] = []
var props: Array[Node3D] = []
var spike: Node3D = null
var age := 0.0
var low_level_t := 0.0
var _check_t := 0.0
var _dismantled := false


static func build(p_center: Vector3, p_dir: Vector3, p_level: int) -> PoliceRoadblock:
	var cont := PoliceUnits.container()
	if cont == null:
		return null
	var rb := PoliceRoadblock.new()
	rb.name = "Roadblock"
	cont.add_child(rb)
	rb._construct(p_center, p_dir, p_level)
	return rb


func _construct(p_center: Vector3, p_dir: Vector3, p_level: int) -> void:
	level = clampi(p_level, 1, 5)
	var d := Vector3(p_dir.x, 0.0, p_dir.z)
	d = d.normalized() if d.length() > 0.01 else Vector3(0, 0, -1)
	# snap to the road underneath: direction and width
	var road := WorldLayout.road_at(p_center.x, p_center.z, 18.0)
	var hw := 7.0
	if not road.is_empty():
		var rd := Vector3(road["dir"].x, 0.0, road["dir"].y)
		if rd.length() > 0.1:
			rd = rd.normalized()
			d = rd if rd.dot(d) >= 0.0 else -rd
		hw = float(road.get("half_width", 7.0))
	half_width = clampf(hw, 3.0, 12.0)
	travel_dir = d
	axis = Vector3(-d.z, 0.0, d.x)
	center = p_center
	global_position = center
	global_rotation = Vector3(0, Util.dir_to_yaw(d), 0)
	_place_vehicles()
	_fill_gaps()
	_place_cones()
	_place_officers()
	if level >= 4:
		_place_spike_strip()


# ---- layout ---------------------------------------------------------------------------------------------------------------
func _at(u: float, along: float = 0.0) -> Vector3:
	return center + axis * u + travel_dir * along


func _ground(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	# first look for the road surface from just above the roadblock centre (a median island / lamp base / bench must not lift a barrier to y = 1),
	# then fall back to a tall ray for slopes
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, center.y + 0.55, p.z), Vector3(p.x, center.y - 4.0, p.z), GC.M_GROUND)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		q = PhysicsRayQueryParameters3D.create(p + Vector3(0, 3.0, 0), p + Vector3(0, -6.0, 0), GC.M_GROUND)
		hit = space.intersect_ray(q)
	if hit.is_empty():
		return p
	return hit["position"]


var _covered: Array[Vector2] = []            # lateral intervals already blocked by vehicles


func _place_vehicles() -> void:
	var n_cars := 2
	if level >= 5:
		n_cars = 3
	var slots: Array[float] = []
	match n_cars:
		2:
			slots = [-half_width * 0.46, half_width * 0.46]
		_:
			slots = [-half_width * 0.62, 0.0, half_width * 0.62]
	var room := PoliceUnits.MAX_CARS - PoliceUnits.count_cars()
	var base_yaw := Util.dir_to_yaw(axis)
	for i in slots.size():
		if room <= 0:
			break
		var u := slots[i]
		var p := _ground(_at(u, 0.0))
		var tilt := 0.32 * (1.0 if u < 0.0 else (-1.0 if u > 0.0 else 0.0))
		var yaw := base_yaw + tilt + (PI if i % 2 == 1 else 0.0)
		var as_van := level >= 4 and i == slots.size() - 1 and room >= 1
		var v := VehicleFactory.spawn(&"police_tactical" if as_van else &"police_cruiser", Transform3D(Basis(Vector3.UP, yaw), p),
			{"faction": GC.F_POLICE, "parked": true, "abandoned": false, "name": "Roadblock Cruiser"})
		if v == null:
			continue
		room -= 1
		v.set_meta(&"roadblock", true)
		v.siren_on = i == 0
		v.headlights_on = true
		cars.append(v)
		var half_len := (5.7 if as_van else 4.75) * 0.5
		var span := maxf(cos(tilt) * half_len, 1.0)
		_covered.append(Vector2(u - span * 0.93, u + span * 0.93))     # barriers tuck 0.15 m under the car ends: no see-through gaps


func _fill_gaps() -> void:
	# lateral intervals of the road not yet covered by a vehicle, filled with barriers (scaled to fit exactly)
	_covered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var gaps: Array[Vector2] = []
	var cursor := -half_width - 0.4
	for iv in _covered:
		if iv.x > cursor + 0.25:
			gaps.append(Vector2(cursor, iv.x))
		cursor = maxf(cursor, iv.y)
	if cursor < half_width + 0.4 - 0.25:
		gaps.append(Vector2(cursor, half_width + 0.4))
	for g in gaps:
		var width := g.y - g.x
		var n := maxi(int(ceil(width / 3.0)), 1)
		var each := width / float(n)
		for k in n:
			var u := g.x + each * (float(k) + 0.5)
			_add_barrier(u, each, level < 4)


func _add_barrier(u: float, length: float, concrete: bool) -> void:
	var rel := ROAD_BARRIER if not concrete else BARRIER
	var base_len := 1.6 if not concrete else 3.0
	var model: Node3D = null
	if ModelLib.exists(rel):
		model = ModelLib.instance(rel)
	var holder := StaticBody3D.new()
	holder.name = "Barrier"
	holder.collision_layer = GC.L_WORLD
	holder.collision_mask = 0
	holder.set_meta(&"surface", &"concrete")
	var sc := clampf(length / base_len, 0.55, 1.5)
	var h := 0.9 if concrete else 1.02
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length + 0.1, h, 0.62 if concrete else 0.84)
	shape.shape = box
	shape.position = Vector3(0, h * 0.5, 0)
	holder.add_child(shape)
	if model != null:
		model.scale = Vector3(sc, 1.0, 1.0)
		holder.add_child(model)
	else:
		push_warning("PoliceRoadblock: '%s' missing - code-built barrier box" % rel)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		mi.mesh = bm
		mi.position = shape.position
		holder.add_child(mi)
	add_child(holder)
	var p := _ground(_at(u, 0.0))
	holder.global_transform = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(axis) + PI * 0.5), p)
	props.append(holder)


func _place_cones() -> void:
	if not ModelLib.exists(CONE):
		return
	var count := 7 if level >= 4 else 5
	for i in count:
		var u := lerpf(-half_width, half_width, float(i) / float(count - 1))
		var c := ModelLib.instance(CONE)
		add_child(c)
		var p := _ground(_at(u, -7.5 - 1.0 * (i % 2)))
		c.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), p)
		props.append(c)


func _place_officers() -> void:
	var n := 2 if level <= 3 else (3 if level == 4 else 4)
	var room := PoliceUnits.MAX_OFFICERS - PoliceUnits.count_officers()
	n = mini(n, room)
	var lateral: Array[float] = [-half_width * 0.38, half_width * 0.38, -half_width * 0.8, half_width * 0.8]
	for i in n:
		var u := lateral[i]
		var behind := 2.7 + (0.4 if i >= 2 else 0.0)
		var p := _ground(_at(u, behind))
		var kind: StringName = &"swat" if level >= 4 and i % 2 == 1 else &"patrol"
		var o := PoliceUnits.spawn_officer(kind, Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(-travel_dir)), p)) as PoliceOfficer
		if o == null:
			continue
		o.set_order({"mode": &"hold", "pos": p, "dir": -travel_dir, "stance": &"cover_low", "aggression": 0.7, "lethal": true})
		o.set_meta(&"roadblock", true)
		officers.append(o)


func _place_spike_strip() -> void:
	spike = PoliceUnits.spawn_spike_strip(_at(0.0, -16.0), travel_dir, half_width * 2.0)


# =====================================================================================================================
# Lifetime
# =====================================================================================================================
func _physics_process(dt: float) -> void:
	if _dismantled:
		return
	age += dt
	_check_t -= dt
	if _check_t > 0.0:
		return
	_check_t = 1.0
	var pl = Game.player
	if age > MAX_AGE:
		dismantle()
		return
	if Game.wanted_level < 2:
		low_level_t += 1.0
		if low_level_t > 14.0:
			dismantle()
			return
	else:
		low_level_t = 0.0
	if pl != null and is_instance_valid(pl):
		var d: float = (pl as Node3D).global_position.distance_to(center)
		if d > FAR_DISTANCE:
			dismantle()
			return
		# officers all dead: nothing left worth keeping beyond the cars; keep it simple
	# keep only valid refs
	officers = officers.filter(func(o): return is_instance_valid(o))
	cars = cars.filter(func(c): return is_instance_valid(c))


func is_intact() -> bool:
	return not _dismantled


## Removes the cars (back to the vehicle pool), officers, barriers, cones and the spike strip.
func dismantle() -> void:
	if _dismantled:
		return
	_dismantled = true
	for o in officers:
		if is_instance_valid(o):
			o.queue_free()
	for c in cars:
		if is_instance_valid(c):
			PoliceUnits.despawn(c)
	for p in props:
		if is_instance_valid(p):
			p.queue_free()
	if is_instance_valid(spike):
		spike.queue_free()
	officers.clear()
	cars.clear()
	props.clear()
	queue_free()
