class_name HostileManager
extends Node
## Spawns and tends the gang / hostile NPC groups (2-3 groups of 3-4 members in the industrial yards and a back alley). Members idle on
## their turf until the player provokes them (see GangNpc). At most MAX_ACTIVE gang members are alive at the same time, groups are only
## instantiated while the player is within STREAM_IN metres (and not in view when they appear), they are removed again beyond STREAM_OUT,
## and a wiped-out group comes back after RESPAWN_DELAY seconds once the player is away from its turf.
##
## Created lazily: PoliceUnits.ensure_hostile_manager() (called by the first PoliceUnits function and by a deferred hook once the game booted).
## Public API: groups, alive_count(), force_spawn_all(), clear_all(), turfs

const MAX_ACTIVE := 12
const GROUP_COUNT := 3
const STREAM_IN := 260.0
const STREAM_OUT := 330.0
const MIN_SPAWN_DISTANCE := 85.0
const RESPAWN_DELAY := 300.0
const TICK := 1.0

var groups: Array = []                # [{turf: Dictionary, members: Array, spawned: bool, respawn_at: float, wiped: bool, index: int}]
var turfs: Array = []
var enabled := true
var stats := {"spawned": 0, "groups_wiped": 0, "respawns": 0}

var _t := 0.5
var _clock := 0.0
var _inited := false
var _container: Node3D = null


func _ready() -> void:
	set_physics_process(true)


func _init_turfs() -> void:
	if _inited:
		return
	if not WorldLayout.built:
		return
	_inited = true
	turfs = find_turfs()
	for i in turfs.size():
		groups.append({"turf": turfs[i], "members": [], "spawned": false, "respawn_at": 0.0, "wiped": false, "index": i})
	print("[HostileManager] %d gang turfs: %s" % [turfs.size(), ", ".join(turfs.map(func(t): return "%s@(%.0f,%.0f)" % [t["name"], t["center"].x, t["center"].z]))])


## Chooses up to GROUP_COUNT turfs: industrial yards first, then a back alley far from the player spawn.
static func find_turfs() -> Array:
	var out: Array = []
	var yards: Array = []
	for l in WorldLayout.lots:
		if l.get("district", &"") == GC.D_INDUSTRIAL and String(l.get("ground", "")) == "yard":
			var r: Rect2 = l["rect"]
			yards.append({"center": r.get_center(), "area": r.get_area(), "rect": r})
	yards.sort_custom(func(a, b): return float(a["area"]) > float(b["area"]))
	var spawn := WorldLayout.location_pos(&"player_spawn")
	var idx := 0
	for y in yards:
		if out.size() >= 2:
			break
		var c2: Vector2 = y["center"]
		var rect: Rect2 = y["rect"]
		var c := Vector3(c2.x, 0.0, c2.y)
		if Util.dist_xz(c, spawn) < MIN_SPAWN_DISTANCE:
			continue
		out.append({"name": "Foundry Yard %d" % (idx + 1), "center": c, "radius": clampf(minf(rect.size.x, rect.size.y) * 0.3, 4.0, 9.0), "kind": &"yard"})
		idx += 1
	# a back alley: the alley road farthest from the spawn (stand on its sidewalk side)
	var best: Dictionary = {}
	var best_d := 0.0
	for r in WorldLayout.roads:
		if r.get("kind", &"") != &"alley":
			continue
		var pts: PackedVector2Array = r["points"]
		if pts.size() < 2:
			continue
		var mid := pts[pts.size() / 2]
		var d := Util.dist_xz(Vector3(mid.x, 0, mid.y), spawn)
		if d > best_d and d > MIN_SPAWN_DISTANCE:
			best_d = d
			var a := pts[maxi(pts.size() / 2 - 1, 0)]
			var b := pts[mini(pts.size() / 2 + 1, pts.size() - 1)]
			var dir := (b - a).normalized()
			var side := Vector2(-dir.y, dir.x)
			var hw := float(r.get("width", 6.0)) * 0.5 + 2.2
			best = {"name": String(r["name"]), "center": Vector3(mid.x + side.x * hw, 0.0, mid.y + side.y * hw), "radius": 4.5, "kind": &"alley"}
	if not best.is_empty():
		out.append(best)
	# fallback: around the industrial district centre
	if out.is_empty():
		var c := WorldLayout.location_pos(&"district_center_industrial", Vector3(190, 0, -20))
		out.append({"name": "Foundry Yard", "center": c, "radius": 6.0, "kind": &"yard"})
	return out


func alive_count() -> int:
	var n := 0
	for g in groups:
		for m in g["members"]:
			if is_instance_valid(m) and not (m as GangNpc).is_dead:
				n += 1
	return n


func _physics_process(dt: float) -> void:
	if not enabled:
		return
	_clock += dt
	_t -= dt
	if _t > 0.0:
		return
	_t = TICK
	if not _inited:
		_init_turfs()
		if not _inited:
			return
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		return
	var ppos: Vector3 = (pl as Node3D).global_position
	for g in groups:
		_tend_group(g, ppos)


func _tend_group(g: Dictionary, ppos: Vector3) -> void:
	var turf: Dictionary = g["turf"]
	var center: Vector3 = turf["center"]
	var d := Util.dist_xz(center, ppos)
	var members: Array = g["members"]
	# drop dead / freed references
	var live: Array = []
	var any_alive := false
	for m in members:
		if is_instance_valid(m):
			live.append(m)
			if not (m as GangNpc).is_dead:
				any_alive = true
	members.clear()
	members.append_array(live)
	if g["spawned"]:
		if not any_alive and not g["wiped"]:
			g["wiped"] = true
			g["respawn_at"] = _clock + RESPAWN_DELAY
			stats["groups_wiped"] += 1
		if g["wiped"]:
			# corpses are cleaned up by the actors; the group slot stays "spawned" until it comes back
			if _clock >= float(g["respawn_at"]) and d > MIN_SPAWN_DISTANCE and d < STREAM_IN and not _in_view(center):
				_remove_members(g)
				g["spawned"] = false
				g["wiped"] = false
				stats["respawns"] += 1
			return
		# stream out (members still alive, nobody fighting)
		if d > STREAM_OUT and not _fighting(g):
			_remove_members(g)
			g["spawned"] = false
		return
	# not spawned: stream in
	if d < STREAM_IN and d > MIN_SPAWN_DISTANCE and not _in_view(center) and alive_count() + 4 <= MAX_ACTIVE:
		_spawn_group(g)


func _fighting(g: Dictionary) -> bool:
	for m in g["members"]:
		if is_instance_valid(m) and (m as GangNpc).provoked:
			return true
	return false


func _in_view(p: Vector3) -> bool:
	var cam: Camera3D = Game.gameplay_camera
	if cam == null or not is_instance_valid(cam):
		return false
	return cam.is_position_in_frustum(p + Vector3(0, 1.0, 0)) and cam.global_position.distance_to(p) < 160.0


func _remove_members(g: Dictionary) -> void:
	for m in g["members"]:
		if is_instance_valid(m):
			m.queue_free()
	g["members"].clear()


func _root() -> Node3D:
	if _container != null and is_instance_valid(_container):
		return _container
	_container = Node3D.new()
	_container.name = "GangNpcs"
	if Game.world != null:
		Game.world.add_child(_container)
	else:
		add_child(_container)
	return _container


func _spawn_group(g: Dictionary) -> void:
	var turf: Dictionary = g["turf"]
	var center: Vector3 = turf["center"]
	var radius: float = float(turf["radius"])
	var n := 4 if (int(g["index"]) % 2 == 0) else 3
	n = mini(n, MAX_ACTIVE - alive_count())
	var shared: Array = g["members"]
	var used: Array[Vector3] = []
	var tries := 0
	while used.size() < n and tries < 40:
		tries += 1
		var a := randf() * TAU
		var p := center + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.8, radius)
		var ground := _ground(p)
		if ground == Vector3.INF or not _spot_clear(ground):
			continue
		var close := false
		for u in used:
			if Util.dist_xz(u, ground) < 1.4:
				close = true
		if close:
			continue
		used.append(ground)
	for i in used.size():
		var m := GangNpc.new()
		m.turf = center
		m.turf_radius = radius
		m.group_id = int(g["index"])
		m.group_members = shared
		m.name = "Gang_%d_%d" % [int(g["index"]), i]
		_root().add_child(m)
		# face the middle of the group (a loose huddle)
		var to := center - used[i]
		var yaw := Util.dir_to_yaw(to) if Util.flat(to).length() > 0.5 else randf() * TAU
		m.global_transform = Transform3D(Basis(Vector3.UP, yaw), used[i])
		m.reset_physics_interpolation()
		shared.append(m)
		stats["spawned"] += 1
	g["spawned"] = true
	g["wiped"] = false


## A capsule the size of a gang member must fit at the spot (not inside a bin / pole / fence): bodies spawned overlapping static
## geometry get pushed through the floor by the depenetration.
func _spot_clear(p: Vector3) -> bool:
	if Game.world == null:
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), p + Vector3(0, 1.05, 0))
	q.collision_mask = GC.L_WORLD | GC.L_PROP | GC.L_VEHICLE
	return (Game.world as Node3D).get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _ground(p: Vector3) -> Vector3:
	if Game.world == null:
		return Vector3.INF
	var space := (Game.world as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 6.0, 0), p + Vector3(0, -8.0, 0), GC.L_WORLD | GC.L_PROP)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	var hp: Vector3 = hit["position"]
	if absf(hit["normal"].y) < 0.8 or hp.y < -0.5 or hp.y > 3.0:
		return Vector3.INF               # roof / wall / water edge / slope
	# nothing solid right above the spot (under a canopy / inside a building)
	var q2 := PhysicsRayQueryParameters3D.create(hp + Vector3(0, 0.2, 0), hp + Vector3(0, 2.2, 0), GC.L_WORLD | GC.L_PROP)
	if not space.intersect_ray(q2).is_empty():
		return Vector3.INF
	return hp + Vector3(0, 0.05, 0)


## Debug / test helper: instantiate every group right now (ignores the stream-in distance).
func force_spawn_all() -> void:
	_init_turfs()
	for g in groups:
		if not g["spawned"]:
			_spawn_group(g)


func clear_all() -> void:
	for g in groups:
		_remove_members(g)
		g["spawned"] = false
		g["wiped"] = false
