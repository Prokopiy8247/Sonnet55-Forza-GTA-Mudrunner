class_name UnderwaterWorld
extends Node3D
## The sea floor dressing: shipwreck at `diving_wreck` (tilted onto the slope, trimesh collider so a diver can explore it, treasure cash on
## the hull), coral clusters, kelp forests (MultiMesh + vertex-sway shader), sea rocks, urchins, an anchor and sunken crates, plus a
## pooled diver-bubble emitter that follows the player's head (more bubbles with scuba). Everything is placed deterministically from a seed.
## GLBs used: props/shipwreck coral_a|b|c kelp_a|b sea_rock_a|b sea_urchin anchor sunken_crates (Blender agent 'bl-world-extras').

const SWAY_SHADER := "res://gta/generated/shaders/underwater_sway.gdshader"

var built := false
var wreck: Node3D = null
var wreck_body: StaticBody3D = null
var wreck_pos := Vector3.ZERO
var stats := {"wreck": 0, "coral": 0, "kelp": 0, "rock": 0, "urchin": 0, "extra": 0, "missing": 0, "cash": 0}
var bubbles: CPUParticles3D = null
var _bubble_mat: StandardMaterial3D = null
var _sway: Shader = null
var _scuba_t := 0.0


func build() -> void:
	if built:
		return
	built = true
	name = "UnderwaterWorld"
	_sway = load(SWAY_SHADER) as Shader
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var loc := WorldLayout.get_location(&"diving_wreck")
	var wp: Vector3 = loc["pos"] if not loc.is_empty() else Vector3(-22.0, -13.6, 268.0)
	wreck_pos = wp
	_place_wreck(wp)
	_scatter(rng, wp)
	_make_bubbles()


# ---- wreck -----------------------------------------------------------------------------------------------------------------
func _place_wreck(wp: Vector3) -> void:
	var m := ModelLib.instance("props/shipwreck")
	if m == null:
		stats["missing"] += 1
		push_warning("UnderwaterWorld: props/shipwreck missing - no wreck")
		return
	wreck = Node3D.new()
	wreck.name = "Shipwreck"
	var gh := WorldLayout.terrain_height(wp.x, wp.z)
	var slope := (WorldLayout.terrain_height(wp.x, wp.z + 12.0) - WorldLayout.terrain_height(wp.x, wp.z - 12.0)) / 24.0
	var tilt := atan(-slope) * 0.85                        # +X rotation lifts -Z (the bow) where the sea floor rises to the north
	var roll := 0.1
	wreck.transform = Transform3D(Basis(Vector3.UP, 0.35) * Basis(Vector3.RIGHT, tilt) * Basis(Vector3.BACK, roll), Vector3(wp.x, gh - 0.9, wp.z))
	wreck.add_child(m)
	_parent_for(wp).add_child(wreck)
	for mi in ModelLib.meshes(m):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# collider from the merged mesh
	var merged := AnimalModel.merge_meshes(m)
	var mesh: ArrayMesh = merged.get("mesh", null)
	if mesh != null:
		var shape := mesh.create_trimesh_shape()
		if shape != null:
			wreck_body = StaticBody3D.new()
			wreck_body.name = "WreckCollision"
			wreck_body.collision_layer = GC.L_WORLD
			wreck_body.collision_mask = 0
			wreck_body.set_meta(&"surface", &"metal")
			var cs := CollisionShape3D.new()
			cs.shape = shape
			wreck_body.add_child(cs)
			wreck.add_child(wreck_body)
	stats["wreck"] = 1
	# detail around the hull
	_one("props/anchor", wp + Vector3(7.5, 0.0, -9.0), 0.8, 1.0)
	_one("props/sunken_crates", wp + Vector3(-9.5, 0.0, 6.0), 2.1, 1.0)
	_one("props/sunken_crates", wp + Vector3(10.5, 0.0, 11.0), -0.6, 0.9)


func _one(rel: String, p: Vector3, yaw: float, scl: float) -> void:
	var m := ModelLib.instance(rel)
	if m == null:
		stats["missing"] += 1
		return
	var gh := WorldLayout.terrain_height(p.x, p.z)
	m.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl), Vector3(p.x, gh - 0.05, p.z))
	_parent_for(p).add_child(m)
	stats["extra"] += 1


## Spawns cash on the hull (rays down from above the wreck onto the collider). Called by the system once physics has the collider.
func place_treasure() -> int:
	if wreck == null or wreck_body == null or not is_inside_tree():
		return 0
	var combat = Game.sys(&"combat")
	if combat == null or not combat.has_method("spawn_pickup"):
		return 0
	var space := get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var n := 0
	var tries := 0
	while n < 3 and tries < 60:
		tries += 1
		var from := wreck_pos + Vector3(rng.randf_range(-6.0, 6.0), 14.0, rng.randf_range(-12.0, 12.0))
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -24.0, 0.0), GC.L_WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit["collider"] != wreck_body:
			continue
		var hp: Vector3 = hit["position"]
		if hp.y < wreck_pos.y + 1.5:
			continue
		combat.spawn_pickup(&"cash", hp + Vector3(0.0, 0.35, 0.0), 600 + 150 * n, {"respawn": 900.0, "snap": false})
		n += 1
	stats["cash"] = n
	return n


# ---- scatter ----------------------------------------------------------------------------------------------------------------
func _scatter(rng: RandomNumberGenerator, wp: Vector3) -> void:
	var spots: Dictionary = {"coral": [], "kelp": [], "rock": [], "urchin": []}
	# candidate points: the whole near-shore shelf (x -285..285, z 178..300) + a denser ring around the wreck
	var n_try := 0
	while n_try < 2600 and (spots["coral"].size() < 70 or spots["kelp"].size() < 90):
		n_try += 1
		var x := rng.randf_range(-285.0, 285.0)
		var z := rng.randf_range(176.0, 300.0)
		if rng.randf() < 0.3:
			x = wp.x + rng.randf_range(-28.0, 28.0)
			z = wp.z + rng.randf_range(-30.0, 30.0)
		var h := WorldLayout.terrain_height(x, z)
		var depth := GC.WATER_LEVEL - h
		if depth < 1.8 or not WorldLayout.is_water(x, z):
			continue
		if MarineBrain.near_pier(x, z, 2.5):
			continue
		if Vector2(x - wp.x, z - wp.z).length() < 12.0:
			continue                                           # keep the hull footprint clear
		var slope := LayoutTerrain.normal_at(x, z).y
		if slope < 0.9:
			continue
		var cluster := rng.randf()
		var p := Vector3(x, h, z)
		if depth < 9.0 and cluster < 0.42 and spots["coral"].size() < 70:
			for k in rng.randi_range(2, 4):
				var q := p + Vector3(rng.randf_range(-2.2, 2.2), 0.0, rng.randf_range(-2.2, 2.2))
				spots["coral"].append(q)
		elif depth > 3.0 and cluster < 0.82 and spots["kelp"].size() < 90:
			for k in rng.randi_range(3, 6):
				var q2 := p + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0))
				spots["kelp"].append(q2)
		elif spots["rock"].size() < 36:
			spots["rock"].append(p)
			if rng.randf() < 0.5:
				spots["urchin"].append(p + Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5)))
	_multimesh_group("coral", ["props/coral_a", "props/coral_b", "props/coral_c"], spots["coral"], rng, 0.8, 1.7, false)
	_multimesh_group("kelp", ["props/kelp_a", "props/kelp_b"], spots["kelp"], rng, 0.9, 1.9, true)
	_multimesh_group("rock", ["props/sea_rock_a", "props/sea_rock_b"], spots["rock"], rng, 1.0, 2.6, false)
	_multimesh_group("urchin", ["props/sea_urchin"], spots["urchin"], rng, 1.0, 1.6, false)


func _multimesh_group(key: String, ids: Array, pts: Array, rng: RandomNumberGenerator, smin: float, smax: float, swaying: bool) -> void:
	if pts.is_empty():
		return
	var meshes: Array = []
	for rel in ids:
		var m := ModelLib.instance(String(rel))
		if m == null:
			stats["missing"] += 1
			continue
		var merged := AnimalModel.merge_meshes(m)
		m.free()
		var mesh: ArrayMesh = merged.get("mesh", null)
		if mesh == null:
			continue
		if swaying and _sway != null:
			for s in mesh.get_surface_count():
				var src := mesh.surface_get_material(s)
				var sm := ShaderMaterial.new()
				sm.shader = _sway
				var col := Color(0.2, 0.55, 0.3)
				if src is BaseMaterial3D:
					col = (src as BaseMaterial3D).albedo_color
				sm.set_shader_parameter("albedo", col)
				mesh.surface_set_material(s, sm)
		meshes.append(mesh)
	if meshes.is_empty():
		return
	var by_mesh: Array = []
	for i in meshes.size():
		by_mesh.append([])
	for p in pts:
		(by_mesh[rng.randi() % meshes.size()] as Array).append(p)
	for i in meshes.size():
		var arr: Array = by_mesh[i]
		if arr.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[i]
		mm.instance_count = arr.size()
		var centre := Vector3.ZERO
		for p in arr:
			centre += p
		centre /= float(arr.size())
		for k in arr.size():
			var p2: Vector3 = arr[k]
			var sc := rng.randf_range(smin, smax)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.25), sc))
			mm.set_instance_transform(k, Transform3D(basis, Vector3(p2.x, p2.y - 0.04, p2.z)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_%s_%d" % [key, i]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 150.0
		mmi.visibility_range_end_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		add_child(mmi)
		stats[key] += arr.size()


func _parent_for(p: Vector3) -> Node:
	var w = Game.world
	if w != null and w.has_method("get_sector_parent"):
		var sp = w.get_sector_parent(p)
		if sp != null:
			return sp
	return self


# ---- bubbles ---------------------------------------------------------------------------------------------------------------
func _make_bubbles() -> void:
	bubbles = CPUParticles3D.new()
	bubbles.name = "DiverBubbles"
	bubbles.amount = 36
	bubbles.lifetime = 2.4
	bubbles.one_shot = false
	bubbles.emitting = false
	bubbles.local_coords = false
	bubbles.direction = Vector3.UP
	bubbles.spread = 25.0
	bubbles.initial_velocity_min = 0.7
	bubbles.initial_velocity_max = 1.6
	bubbles.gravity = Vector3(0.0, 0.5, 0.0)
	bubbles.scale_amount_min = 0.5
	bubbles.scale_amount_max = 1.3
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bubbles.emission_sphere_radius = 0.12
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	_bubble_mat = StandardMaterial3D.new()
	_bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bubble_mat.albedo_color = Color(0.85, 0.97, 1.0, 0.55)
	sm.material = _bubble_mat
	bubbles.mesh = sm
	bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bubbles)


## Follows the player's head: exhale bubbles every few seconds, a steady stream with scuba.
func update_bubbles(dt: float, w: WildlifeWorld) -> void:
	if bubbles == null:
		return
	if w.player == null or not w.player_underwater and not (w.player.get("head_underwater") == true):
		bubbles.emitting = false
		return
	var head_pos := w.player_pos + Vector3(0.0, 0.55, 0.0)
	bubbles.global_position = head_pos
	_scuba_t += dt
	var steady := w.player_has_scuba or bool(Game.cheats.get("scuba", false))
	if steady:
		bubbles.amount = 36
		bubbles.emitting = fposmod(_scuba_t, 4.0) < 2.6                 # exhale pulses
	else:
		bubbles.amount = 18
		bubbles.emitting = fposmod(_scuba_t, 7.0) < 1.2
