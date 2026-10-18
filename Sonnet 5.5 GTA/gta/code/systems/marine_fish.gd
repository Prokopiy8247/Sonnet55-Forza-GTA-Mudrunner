class_name MarineFish
extends Node3D
## Fish schools as two MultiMeshes (fish_a = orange reef fish, fish_b = silver fish; one draw call per material surface, vertex-shader
## wriggle in marine_fish.gdshader). "Boids-light": every school has a leader on a smooth wandering path around an anchor (pier piles, the
## wreck, rock reefs); each fish chases its own slowly drifting slot around the leader, so the school stays tight without O(n^2) neighbour
## checks. Players / boats / swimmers near a school make it scatter (slots blow outward, the leader bolts away) and regroup afterwards.
## At most CAP fish are alive; schools farther than ACTIVE_DIST from the player are frozen and not drawn.

const CAP := 40
const ACTIVE_DIST := 115.0
const SHADER := "res://gta/generated/shaders/marine_fish.gdshader"

class School:
	var kind := 0                     # 0 fish_a, 1 fish_b
	var anchor := Vector3.ZERO        # centre of interest (world x/z, y = preferred swim depth)
	var radius := 5.0                 # wander radius of the leader
	var count := 8
	var spread := 1.6                 # radius of the fish cloud around the leader
	var active := false
	var slot0 := 0
	var t := 0.0
	var seed := 0.0
	var leader := Vector3.ZERO
	var leader_prev := Vector3.ZERO
	var heading := 0.0
	var shift := Vector3.ZERO         # scatter displacement of the whole school
	var scatter := 0.0                # 0..1 panic
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var off := PackedVector3Array()   # slot offsets in the school frame
	var phase := PackedFloat32Array()
	var size := PackedFloat32Array()
	var floor_y := PackedFloat32Array()
	var name_tag := ""

var schools: Array[School] = []
var active_fish := 0
var stats := {"schools": 0, "active_schools": 0, "fish": 0, "scatters": 0, "us": 0.0}

var _mm: Array[MultiMesh] = [null, null]
var _mmi: Array[MultiMeshInstance3D] = [null, null]
var _frame := 0
var _select_t := 0.0
var _scatter_t := 0.0
var _rng := RandomNumberGenerator.new()
var _loaded := false


func setup(parent: Node) -> void:
	name = "FishSchools"
	parent.add_child(self)
	_rng.seed = 5150
	_loaded = _build_multimeshes()
	if not _loaded:
		push_warning("MarineFish: fish GLBs missing - no fish schools")


func _build_multimeshes() -> bool:
	var ids := ["animals/fish_a", "animals/fish_b"]
	var lens := [0.30, 0.50]
	for k in 2:
		var root := ModelLib.instance(ids[k])
		if root == null:
			return false
		var merged := AnimalModel.merge_meshes(root)
		root.free()
		var mesh: ArrayMesh = merged["mesh"]
		if mesh == null:
			return false
		var sh := load(SHADER) as Shader
		for s in mesh.get_surface_count():
			var src: Material = (merged["materials"] as Array)[s]
			var sm := ShaderMaterial.new()
			sm.shader = sh
			var col := Color(0.8, 0.8, 0.8)
			var rough := 0.55
			if src is StandardMaterial3D:
				col = (src as StandardMaterial3D).albedo_color
				rough = (src as StandardMaterial3D).roughness
			sm.set_shader_parameter("albedo", col)
			sm.set_shader_parameter("body_len", lens[k])
			sm.set_shader_parameter("rough", rough)
			sm.set_shader_parameter("freq", 9.0 if k == 0 else 7.0)
			mesh.surface_set_material(s, sm)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = CAP
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Fish_" + ("A" if k == 0 else "B")
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-400.0, -40.0, 0.0), Vector3(800.0, 60.0, 450.0))
		add_child(mmi)
		_mm[k] = mm
		_mmi[k] = mmi
	return true


## Registers a school. `anchor.y` is the preferred swim depth (world y); `radius` the wander radius of its leader.
func add_school(tag: String, kind: int, anchor: Vector3, radius: float, count: int, spread: float = 1.6) -> School:
	var s := School.new()
	s.name_tag = tag
	s.kind = kind
	s.anchor = anchor
	s.radius = radius
	s.count = count
	s.spread = spread
	s.seed = _rng.randf() * 100.0
	s.t = _rng.randf() * 50.0
	s.pos.resize(count)
	s.vel.resize(count)
	s.off.resize(count)
	s.phase.resize(count)
	s.size.resize(count)
	s.floor_y.resize(count)
	for i in count:
		# slots: flattened ellipsoid cloud, longer along the swimming direction (-Z in the school frame)
		var v := Vector3(_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 0.55), _rng.randfn(0.0, 1.4))
		if v.length() > 2.6:
			v = v.normalized() * 2.6
		s.off[i] = v * spread * 0.5
		s.phase[i] = _rng.randf() * TAU
		s.size[i] = _rng.randf_range(0.82, 1.22) * (1.0 if kind == 0 else 0.95)
	_update_leader(s, 0.0)
	_place_school(s)
	schools.append(s)
	stats["schools"] = schools.size()
	return s


func _place_school(s: School) -> void:
	var fwd := Util.yaw_to_dir(s.heading)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	for i in s.count:
		var o: Vector3 = s.off[i]
		var p := s.leader + right * o.x + Vector3.UP * o.y + fwd * -o.z
		s.pos[i] = p
		s.vel[i] = fwd * 0.8
		s.floor_y[i] = WorldLayout.terrain_height(p.x, p.z)


func _update_leader(s: School, dt: float) -> void:
	s.t += dt
	var w1 := 0.17 + 0.02 * sin(s.seed)
	var w2 := 0.23 + 0.03 * cos(s.seed * 1.7)
	var a := s.t
	var base := Vector3(s.anchor.x, s.anchor.y, s.anchor.z)
	var r := s.radius
	var p := base + Vector3(cos(a * w1 + s.seed) * r, sin(a * 0.31 + s.seed * 2.0) * 0.6, sin(a * w2 + s.seed * 0.5) * r * 0.8)
	p += s.shift
	# keep the leader in water that is deep enough
	var fl := WorldLayout.terrain_height(p.x, p.z)
	p.y = clampf(p.y, fl + 0.8, GC.WATER_LEVEL - 0.7)
	s.leader_prev = s.leader
	s.leader = p
	var d := p - s.leader_prev
	if Vector2(d.x, d.z).length() > 0.0005:
		s.heading = lerp_angle(s.heading, Util.dir_to_yaw(Vector3(d.x, 0.0, d.z)), minf(dt * 3.0, 1.0)) if dt > 0.0 else Util.dir_to_yaw(Vector3(d.x, 0.0, d.z))


## Call every physics frame with the shared world knowledge.
func update(dt: float, w: WildlifeWorld) -> void:
	if not _loaded:
		return
	var t0 := Time.get_ticks_usec()
	_frame += 1
	_select_t -= dt
	if _select_t <= 0.0:
		_select_t = 0.5
		_select_active(w)
	_scatter_t -= dt
	var check_scatter := false
	if _scatter_t <= 0.0:
		_scatter_t = 0.12
		check_scatter = true
	var half := _frame & 1
	for s in schools:
		if not s.active:
			continue
		if check_scatter:
			_sense(s, w)
		# smooth the scatter state
		s.scatter = maxf(s.scatter - dt * 0.45, 0.0)
		s.shift = s.shift.lerp(Vector3.ZERO, minf(dt * (0.35 if s.scatter < 0.3 else 0.08), 1.0))
		_update_leader(s, dt)
		_update_fish(s, dt, half)
	stats["us"] = lerpf(float(stats["us"]), float(Time.get_ticks_usec() - t0), 0.05)


func _select_active(w: WildlifeWorld) -> void:
	var cands: Array = []
	var ref := w.player_pos
	for s in schools:
		var d := Util.dist_xz(s.anchor, ref)
		cands.append([d, s])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var budget := CAP
	var changed := false
	var active_count := 0
	var counts := [0, 0]
	for c in cands:
		var s2: School = c[1]
		var want: bool = float(c[0]) < ACTIVE_DIST + s2.radius and budget >= s2.count
		if want:
			budget -= s2.count
			active_count += 1
		if want != s2.active:
			changed = true
			s2.active = want
			if want:
				_place_school(s2)
	if not changed and _mm[0].visible_instance_count + _mm[1].visible_instance_count > 0:
		stats["active_schools"] = active_count
		return
	# reassign slots (contiguous per MultiMesh)
	var cursor := [0, 0]
	active_fish = 0
	for s3 in schools:
		if not s3.active:
			continue
		s3.slot0 = cursor[s3.kind]
		cursor[s3.kind] += s3.count
		counts[s3.kind] += s3.count
		active_fish += s3.count
		var mm := _mm[s3.kind]
		for i in s3.count:
			mm.set_instance_custom_data(s3.slot0 + i, Color(s3.phase[i], clampf(s3.size[i] - 0.8, 0.0, 1.0), 0.0, 0.0))
	_mm[0].visible_instance_count = counts[0]
	_mm[1].visible_instance_count = counts[1]
	stats["active_schools"] = active_count
	stats["fish"] = active_fish


func _sense(s: School, w: WildlifeWorld) -> void:
	var threat := Vector3.INF
	var c := s.leader
	var reach := s.spread * 1.3 + 4.5
	if w.player != null:
		var pp := w.player_pos
		var in_water := w.player_swimming or pp.y < GC.WATER_LEVEL + 0.6
		var dd := Vector2(pp.x - c.x, pp.z - c.z).length()
		if in_water and dd < reach + 2.0 and absf(pp.y - c.y) < 7.0:
			threat = pp
		elif not in_water and dd < reach - 1.0 and pp.y > c.y + 1.0 and pp.y < GC.WATER_LEVEL + 3.5:
			# standing on a pier right above the school
			threat = pp
	for v in w.vehicles:
		if bool(v.get("boat", false)) and float(v["speed"]) > 2.5:
			var vp: Vector3 = v["pos"]
			if Vector2(vp.x - c.x, vp.z - c.z).length() < reach + 4.0:
				threat = vp
	if threat != Vector3.INF and s.scatter < 0.6:
		s.scatter = 1.0
		var away := Vector3(c.x - threat.x, 0.0, c.z - threat.z)
		if away.length() < 0.1:
			away = Vector3(1, 0, 0)
		s.shift += away.normalized() * (7.0 + s.spread * 2.0)
		s.shift.y = -1.0
		stats["scatters"] = int(stats["scatters"]) + 1


func _update_fish(s: School, dt: float, half: int) -> void:
	var fwd := Util.yaw_to_dir(s.heading)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var mm := _mm[s.kind]
	var spread_k := 1.0 + s.scatter * 1.7
	var max_sp := 1.9 + s.scatter * 3.4
	var step_dt := dt * 2.0                  # every fish is updated every second frame
	var gain := 3.2 + s.scatter * 2.0
	var tt := s.t
	for i in range(half, s.count, 2):
		var o: Vector3 = s.off[i]
		# slot drifts slowly so the cloud breathes
		var ph: float = s.phase[i]
		var drift := Vector3(sin(tt * 0.7 + ph), sin(tt * 0.9 + ph * 2.0) * 0.4, cos(tt * 0.6 + ph * 1.3)) * 0.35
		var target := s.leader + right * (o.x * spread_k + drift.x) + Vector3.UP * (o.y * spread_k + drift.y) + fwd * (-o.z * spread_k + drift.z)
		var p: Vector3 = s.pos[i]
		var desired := (target - p) * gain
		var vcur: Vector3 = s.vel[i]
		var sp := desired.length()
		if sp > max_sp:
			desired = desired / sp * max_sp
		vcur = vcur.lerp(desired, minf(step_dt * 3.0, 1.0))
		p += vcur * step_dt
		# stay above the sea floor and below the surface
		if (i + _frame) % 6 < 2:
			s.floor_y[i] = WorldLayout.terrain_height(p.x, p.z)
		p.y = clampf(p.y, s.floor_y[i] + 0.35, GC.WATER_LEVEL - 0.5)
		s.pos[i] = p
		s.vel[i] = vcur
		var vl := vcur.length()
		var yaw := Util.dir_to_yaw(Vector3(vcur.x, 0.0, vcur.z)) if (absf(vcur.x) + absf(vcur.z)) > 0.05 else s.heading
		var pitch := asin(clampf(vcur.y / maxf(vl, 0.01), -0.7, 0.7)) if vl > 0.05 else 0.0
		var b := Basis.from_euler(Vector3(pitch, yaw, 0.0)).scaled(Vector3.ONE * s.size[i])
		mm.set_instance_transform(s.slot0 + i, Transform3D(b, p))


func clear_all() -> void:
	for s in schools:
		s.active = false
	for k in 2:
		if _mm[k] != null:
			_mm[k].visible_instance_count = 0
	active_fish = 0


func get_active_fish() -> int:
	return active_fish


## Number of fish whose distance from the school's leader exceeds `r` (test helper for scatter checks).
func spread_of(s: School) -> float:
	var m := 0.0
	for i in s.count:
		m = maxf(m, s.pos[i].distance_to(s.leader))
	return m
