class_name InteractionProps
extends RefCounted
## Street-prop interactions of Systems-A: phone booths (real props placed here, quick save), benches (the street furniture MultiMesh
## benches get a small pool of follow-the-player seat anchors) and fire hydrants (cosmetic water jets when shot / blown up / rammed).
## Only DYNAMIC state lives in nodes; the baked MultiMesh props stay as they are.

const BOOTH_GLB := "props/phone_booth"
const BENCH_GLB := "props/bench"
const SEAT_LOCAL := Vector3(0.0, 0.5, -0.05)            # bench.glb SeatPoint (bench front = -Z)
const BOOTH_USE_LOCAL := Vector3(0.0, 0.0, -0.8)        # phone_booth.glb UsePoint
const LANE_CLEARANCE := 2.6                              # min distance (m) from a booth centre to any lane centre line (QA: traffic queues)

## [location id, offset from the location, hint] - first free walkable spot near each becomes a phone booth.
const BOOTH_SPOTS := [
	[&"player_spawn", Vector3(-9.0, 0, 3.0)], [&"gas_station", Vector3(15.0, 0, 7.0)], [&"train_station_a", Vector3(15.0, 0, 8.0)],
	[&"beach_spawn", Vector3(16.0, 0, -9.0)], [&"marina_office", Vector3(10.0, 0, 6.0)], [&"airport_terminal", Vector3(-14.0, 0, 6.0)],
	[&"hospital", Vector3(-6.0, 0, 24.0)], [&"park_center", Vector3(7.0, 0, 7.0)], [&"clothing_store", Vector3(-12.0, 0, 6.0)],
]


## [{pos, yaw, use_pos}] valid phone booth placements (sidewalk spots, front along the street).
static func plan_phone_booths(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for spec in BOOTH_SPOTS:
		var id: StringName = spec[0]
		if not WorldLayout.has_location(id):
			continue
		var c: Vector3 = WorldLayout.location_pos(id) + (spec[1] as Vector3)
		for attempt in 3:
			var p := InteractionUtil.find_walkable(c, {"rng": rng, "max_r": 5.0 + attempt * 3.0, "tries": 40, "avoid_road": true, "radius": 0.9})
			if p == Vector3.INF:
				continue
			var yaw := _street_yaw(p)
			if not InteractionUtil.box_free(p + Vector3(0, 1.3, 0), Vector3(1.1, 2.5, 1.1), yaw):
				continue
			if not InteractionUtil.clear_at(p + Basis(Vector3.UP, yaw) * BOOTH_USE_LOCAL, 0.35):
				continue
			if InteractionElevator.furniture_near(p, 1.8):      # baked street furniture (lamps, bins, bus stops) has no collider
				continue
			# QA: a booth within ~2 m of a lane centre line makes traffic dodge, slow down and queue (seen at the junction (105, 85))
			if not InteractionUtil.lane_clear(p, LANE_CLEARANCE):
				continue
			var tooclose := false
			for o in out:
				if Util.dist_xz(o["pos"], p) < 4.0:
					tooclose = true
			if tooclose:
				continue
			out.append({"id": "phone_%d" % out.size(), "pos": p, "yaw": yaw, "use_pos": p + Basis(Vector3.UP, yaw) * BOOTH_USE_LOCAL, "near": id})
			break
	return out


## Direction (yaw) along the nearest road so the booth opening faces the pavement.
static func _street_yaw(p: Vector3) -> float:
	var best := {"dist": INF, "dir": Vector2(0, 1)}
	for e in LayoutRoadNet.edges:
		var r := InteractionUtil.nearest_on_polyline(e["pts"], Vector2(p.x, p.z))
		if float(r["dist"]) < float(best["dist"]):
			best = r
	var d: Vector2 = best["dir"]
	return Util.dir_to_yaw(Vector3(d.x, 0, d.y))


static func build_booth(spec: Dictionary, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "PhoneBooth_" + String(spec["id"])
	parent.add_child(root)
	root.global_transform = Transform3D(Basis(Vector3.UP, float(spec["yaw"])), spec["pos"])
	var model := ModelLib.instance(BOOTH_GLB)
	if model == null:
		push_warning("[InteractionProps] props/phone_booth.glb missing - booth uses a code-built box")
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 2.5, 0.9)
		mi.mesh = bm
		mi.position = Vector3(0, 1.25, 0)
		root.add_child(mi)
		root.set_meta(&"fallback", true)
	else:
		root.add_child(model)
	# solid body so nobody walks through it and bullets stop (the real booth is glass: the box is only the frame footprint)
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.collision_layer = GC.L_WORLD
	body.collision_mask = 0
	body.set_meta(&"surface", &"metal")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.0, 2.6, 1.0)
	cs.shape = sh
	cs.position = Vector3(0, 1.3, 0)
	body.add_child(cs)
	root.add_child(body)
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 160.0
	return root


# ======================================================================================================== benches / hydrants data
## Bench seats from the street furniture list: [{pos (seat point, world), yaw}]. yaw = facing of the sitter (Util convention).
static func bench_seats() -> Array:
	var out: Array = []
	for f in WorldLayout.furniture:
		if f["kind"] != &"bench":
			continue
		var yaw: float = float(f["yaw"])
		var seat: Vector3 = (f["pos"] as Vector3) + Basis(Vector3.UP, yaw) * SEAT_LOCAL
		out.append({"pos": seat, "yaw": yaw, "base": f["pos"]})
	return out


static func hydrant_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for f in WorldLayout.furniture:
		if f["kind"] == &"hydrant":
			out.append(f["pos"])
	return out


# ======================================================================================================== water jet
## Pool of cosmetic hydrant jets (CPUParticles3D). start(pos) plays one for `seconds`.
class JetPool extends Node3D:
	const POOL := 4
	var _jets: Array[CPUParticles3D] = []
	var _splash: Array[CPUParticles3D] = []
	var _until: Array[float] = []
	var _clock := 0.0

	static var _drop_tex: GradientTexture2D = null

	## Soft round droplet sprite (shared by every jet).
	static func _droplet() -> GradientTexture2D:
		if _drop_tex == null:
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
			_drop_tex = GradientTexture2D.new()
			_drop_tex.gradient = g
			_drop_tex.fill = GradientTexture2D.FILL_RADIAL
			_drop_tex.fill_from = Vector2(0.5, 0.5)
			_drop_tex.fill_to = Vector2(1.0, 0.5)
			_drop_tex.width = 32
			_drop_tex.height = 32
		return _drop_tex

	static func _water_mesh(size: float, alpha: float) -> QuadMesh:
		var qm := QuadMesh.new()
		qm.size = Vector2(size, size)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _droplet()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color(0.86, 0.95, 1.0, alpha)
		mat.disable_receive_shadows = true
		qm.material = mat
		return qm

	func _ready() -> void:
		name = "HydrantJets"
		for i in POOL:
			# the fountain: a fat column that arcs over at the top and rains down
			var p := CPUParticles3D.new()
			p.emitting = false
			p.amount = 220
			p.lifetime = 1.35
			p.local_coords = false
			p.direction = Vector3.UP
			p.spread = 7.0
			p.initial_velocity_min = 8.0
			p.initial_velocity_max = 10.5
			p.gravity = Vector3(0, -11.5, 0)
			p.scale_amount_min = 0.9
			p.scale_amount_max = 1.7
			p.mesh = _water_mesh(0.3, 0.9)
			var grad := Gradient.new()
			grad.set_color(0, Color(1, 1, 1, 0.95))
			grad.set_color(1, Color(0.62, 0.84, 1.0, 0.0))
			p.color_ramp = grad
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(p)
			_jets.append(p)
			# spray / mist at the cap of the hydrant
			var s := CPUParticles3D.new()
			s.emitting = false
			s.amount = 60
			s.lifetime = 0.6
			s.local_coords = false
			s.direction = Vector3.UP
			s.spread = 80.0
			s.initial_velocity_min = 1.6
			s.initial_velocity_max = 3.6
			s.gravity = Vector3(0, -8.0, 0)
			s.scale_amount_min = 0.8
			s.scale_amount_max = 1.5
			s.mesh = _water_mesh(0.2, 0.75)
			var sg := Gradient.new()
			sg.set_color(0, Color(1, 1, 1, 0.8))
			sg.set_color(1, Color(0.75, 0.9, 1.0, 0.0))
			s.color_ramp = sg
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(s)
			_splash.append(s)
			_until.append(0.0)

	func start(pos: Vector3, seconds: float = 7.0) -> void:
		var idx := -1
		for i in POOL:                                          # same hydrant again -> extend
			if _jets[i].emitting and _jets[i].global_position.distance_to(pos + Vector3(0, 0.75, 0)) < 0.6:
				_until[i] = _clock + seconds
				return
		for i in POOL:
			if not _jets[i].emitting:
				idx = i
				break
		if idx < 0:
			idx = 0
		var j := _jets[idx]
		j.global_position = pos + Vector3(0, 0.75, 0)
		j.restart()
		j.emitting = true
		var s := _splash[idx]
		s.global_position = pos + Vector3(0, 0.08, 0)
		s.restart()
		s.emitting = true
		_until[idx] = _clock + seconds
		Sfx.play_3d(&"splash_big", pos, -6.0, 1.15, 40.0)

	func active_count() -> int:
		var n := 0
		for j in _jets:
			if j.emitting:
				n += 1
		return n

	func _process(delta: float) -> void:
		_clock += delta
		for i in POOL:
			if _jets[i].emitting and _clock >= _until[i]:
				_jets[i].emitting = false
				_splash[i].emitting = false
