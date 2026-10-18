class_name UnderwaterFish
extends Node3D
## Fish schools: two MultiMeshes (fish_a orange reef fish, fish_b silver) share <= WildlifeDefs.CAP_FISH instances. Each school is a loose
## boid-light group (a moving centre + per-fish offsets with a body wiggle); schools scatter away from a swimming player / fast boats,
## hang around hot spots (pier tips, the wreck, rocks) and are recycled by distance. No node per fish, one transform write per visible fish.

const MM_CAPACITY := 40
const SCHOOL_MIN := 6
const SCHOOL_MAX := 12

var mm_a: MultiMeshInstance3D = null
var mm_b: MultiMeshInstance3D = null
var schools: Array = []
var hotspots: Array[Vector3] = []
var rng := RandomNumberGenerator.new()
var total_fish := 0
var visible_fish := 0
var enabled := true
var _pop_t := 0.0
var _t := 0.0


func setup() -> void:
	name = "FishSchools"
	rng.randomize()
	mm_a = _make_mm("animals/fish_a", "FishA", 1.35)
	mm_b = _make_mm("animals/fish_b", "FishB", 1.2)
	_build_hotspots()


func _make_mm(rel: String, node_name: String, scl: float) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var src := ModelLib.instance(rel)
	var merged: Dictionary = {}
	if src != null:
		merged = AnimalModel.merge_meshes(src)
		src.free()
	var mesh: ArrayMesh = merged.get("mesh", null)
	if mesh == null:
		push_warning("UnderwaterFish: GLB '%s' missing - fish are labelled boxes" % rel)
		AnimalModel.fallbacks[rel] = int(AnimalModel.fallbacks.get(rel, 0)) + 1
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.16, 0.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.0, 1.0)
		bm.material = mat
		mm.mesh = bm
	else:
		mm.mesh = mesh
	mm.instance_count = MM_CAPACITY
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.set_meta(&"scale", scl)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 40.0
	add_child(mmi)
	return mmi


func _build_hotspots() -> void:
	hotspots.clear()
	for p in WorldLayout.piers:
		if bool(p.get("finger", false)):
			continue
		var r: Rect2 = p["rect"]
		hotspots.append(Vector3(r.get_center().x, 0.0, r.end.y + 4.0))
		hotspots.append(Vector3(r.get_center().x + r.size.x * 0.5 + 4.0, 0.0, r.position.y + r.size.y * 0.6))
	var wreck := WorldLayout.get_location(&"diving_wreck")
	if not wreck.is_empty():
		var wp: Vector3 = wreck["pos"]
		for k in 3:
			hotspots.append(Vector3(wp.x + rng.randf_range(-12.0, 12.0), 0.0, wp.z + rng.randf_range(-14.0, 14.0)))
	for k in 6:
		hotspots.append(Vector3(rng.randf_range(-260.0, 260.0), 0.0, rng.randf_range(196.0, 300.0)))


func clear() -> void:
	schools.clear()
	total_fish = 0
	_write(0.0, Vector3.INF, false)


func school_count() -> int:
	return schools.size()


## Adds one school at xz (centre depth from the seabed). Returns false when the water is too shallow or the cap is reached.
func add_school(xz: Vector3, n: int = -1, kind: int = -1) -> bool:
	var floor_y := WorldLayout.terrain_height(xz.x, xz.z)
	if floor_y > GC.WATER_LEVEL - 2.4 or not WorldLayout.is_water(xz.x, xz.z):
		return false
	if n < 0:
		n = rng.randi_range(SCHOOL_MIN, SCHOOL_MAX)
	n = mini(n, MM_CAPACITY - total_fish)
	if n < 3:
		return false
	var s := {
		"c": Vector3(xz.x, clampf(floor_y + rng.randf_range(1.2, 3.5), floor_y + 1.0, GC.WATER_LEVEL - 1.1), xz.z),
		"home": xz, "kind": kind if kind >= 0 else rng.randi() % 2, "n": n, "yaw": rng.randf() * TAU,
		"tgt": Vector3.INF, "spd": rng.randf_range(0.9, 1.7), "scatter": 0.0, "offs": PackedVector3Array(), "ph": PackedFloat32Array(),
		"t": rng.randf() * 10.0, "retarget": 0.0,
	}
	var offs: PackedVector3Array = s["offs"]
	var ph: PackedFloat32Array = s["ph"]
	for i in n:
		offs.append(Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 0.45), rng.randfn(0.0, 1.2)))
		ph.append(rng.randf() * TAU)
	schools.append(s)
	total_fish += n
	return true


## Called every physics tick by WildlifeSystem.
func update(dt: float, w: WildlifeWorld) -> void:
	if not enabled:
		return
	_t += dt
	_pop_t -= dt
	var ppos := w.player_pos
	var swimmer_pos := ppos
	var swim_scare := w.player_swimming or w.player_underwater
	var mm_i_a := 0
	var mm_i_b := 0
	var ma := mm_a.multimesh
	var mb := mm_b.multimesh
	var sca := float(mm_a.get_meta(&"scale"))
	var scb := float(mm_b.get_meta(&"scale"))
	visible_fish = 0
	var i_school := schools.size() - 1
	while i_school >= 0:
		var s: Dictionary = schools[i_school]
		i_school -= 1
		var c: Vector3 = s["c"]
		var dxz := Util.dist_xz(c, ppos)
		if dxz > 135.0:
			# too far: drop (population tick refills near the player)
			total_fish -= int(s["n"])
			schools.remove_at(i_school + 1)
			continue
		s["t"] = float(s["t"]) + dt
		# retarget around the home spot
		s["retarget"] = float(s["retarget"]) - dt
		if float(s["retarget"]) <= 0.0 or s["tgt"] == Vector3.INF:
			s["retarget"] = rng.randf_range(3.0, 7.0)
			var home: Vector3 = s["home"]
			var tx := home.x + rng.randf_range(-11.0, 11.0)
			var tz := home.z + rng.randf_range(-11.0, 11.0)
			var fl := WorldLayout.terrain_height(tx, tz)
			if fl < GC.WATER_LEVEL - 2.2 and WorldLayout.is_water(tx, tz):
				s["tgt"] = Vector3(tx, clampf(fl + rng.randf_range(1.0, 4.0), fl + 0.9, GC.WATER_LEVEL - 1.0), tz)
			else:
				s["tgt"] = c
		# scatter: swimmer / diver / fast boat close by
		var scare := 0.0
		if swim_scare and dxz < 9.0 and absf(swimmer_pos.y - c.y) < 7.0:
			scare = clampf(1.0 - dxz / 9.0, 0.0, 1.0)
		for v in w.vehicles:
			if bool(v["boat"]) and Util.dist_xz(c, v["pos"]) < 12.0:
				scare = maxf(scare, 0.8)
		var sc: float = s["scatter"]
		sc = Util.damp(sc, 1.0 if scare > 0.0 else 0.0, 7.0 if scare > 0.0 else 0.7, dt)
		s["scatter"] = sc
		var tgt: Vector3 = s["tgt"]
		var spd: float = s["spd"]
		var move_dir := tgt - c
		if scare > 0.0:
			var away := c - swimmer_pos
			away.y *= 0.3
			move_dir = away.normalized() * 8.0
			spd = 5.5
		var ml := move_dir.length()
		if ml > 0.4:
			var step := move_dir / ml * spd * dt
			var nc := c + step
			var fl2 := WorldLayout.terrain_height(nc.x, nc.z)
			if fl2 < GC.WATER_LEVEL - 1.8 and WorldLayout.is_water(nc.x, nc.z):
				nc.y = clampf(nc.y, fl2 + 0.8, GC.WATER_LEVEL - 0.9)
				c = nc
				s["c"] = c
			else:
				s["tgt"] = s["home"]
			var want_yaw := Util.dir_to_yaw(Vector3(move_dir.x, 0.0, move_dir.z))
			s["yaw"] = float(s["yaw"]) + clampf(Util.angle_diff(float(s["yaw"]), want_yaw), -3.0 * dt, 3.0 * dt)
		if dxz > 100.0:
			continue
		# write the fish
		var yaw: float = s["yaw"]
		var b := Basis(Vector3.UP, yaw)
		var offs: PackedVector3Array = s["offs"]
		var ph: PackedFloat32Array = s["ph"]
		var t: float = s["t"]
		var spread := 1.0 + sc * 1.5
		var n: int = s["n"]
		var is_a: bool = int(s["kind"]) == 0
		for i in n:
			var o := offs[i]
			var p := c + b * Vector3(o.x * spread, o.y * spread, o.z * (1.0 + sc * 0.6)) + Vector3(sin(t * 0.8 + ph[i]) * 0.25, sin(t * 0.6 + ph[i] * 1.7) * 0.12, cos(t * 0.7 + ph[i]) * 0.25)
			var wig := sin(t * (6.0 + spd * 2.0) + ph[i]) * (0.16 + sc * 0.2)
			var fb := Basis(Vector3.UP, yaw + wig + sin(ph[i] * 3.0) * 0.2 * sc)
			var scl := sca if is_a else scb
			fb = fb.scaled(Vector3.ONE * scl)
			if is_a:
				if mm_i_a < MM_CAPACITY:
					ma.set_instance_transform(mm_i_a, Transform3D(fb, p))
					mm_i_a += 1
			else:
				if mm_i_b < MM_CAPACITY:
					mb.set_instance_transform(mm_i_b, Transform3D(fb, p))
					mm_i_b += 1
	ma.visible_instance_count = mm_i_a
	mb.visible_instance_count = mm_i_b
	visible_fish = mm_i_a + mm_i_b


func _write(_dt: float, _p: Vector3, _x: bool) -> void:
	mm_a.multimesh.visible_instance_count = 0
	mm_b.multimesh.visible_instance_count = 0
	visible_fish = 0


## Keeps the population topped up: schools at hot spots / over deep-enough water 25..110 m from the player.
func populate(w: WildlifeWorld, instant: bool) -> void:
	if not enabled or total_fish >= MM_CAPACITY - 5 or w.player == null:
		return
	var ppos := w.player_pos
	# only worth having fish when the sea is anywhere near
	if ppos.z < 100.0:
		return
	var tries := 10
	while tries > 0 and total_fish < MM_CAPACITY - 5:
		tries -= 1
		var spot := Vector3.INF
		if rng.randf() < 0.65 and not hotspots.is_empty():
			var h: Vector3 = hotspots[rng.randi() % hotspots.size()]
			spot = Vector3(h.x + rng.randf_range(-3.0, 3.0), 0.0, h.z + rng.randf_range(-3.0, 3.0))
		else:
			var ang := rng.randf() * TAU
			var dd := rng.randf_range(20.0, 95.0)
			spot = Vector3(ppos.x + cos(ang) * dd, 0.0, ppos.z + sin(ang) * dd)
		var d := Util.dist_xz(spot, ppos)
		if d < (8.0 if instant else 28.0) or d > 105.0:
			continue
		var too_close := false
		for s in schools:
			if Util.dist_xz(s["c"], spot) < 14.0:
				too_close = true
				break
		if too_close:
			continue
		if add_school(spot):
			return
