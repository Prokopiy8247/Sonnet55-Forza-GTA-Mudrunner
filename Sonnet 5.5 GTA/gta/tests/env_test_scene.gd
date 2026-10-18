extends RefCounted
## Self-contained test city for the Environment agent: ground + sea + blocks of window-shaded towers + street lamps
## (group "street_lamp") + cars + palms + distant hills, so sky / lighting / fog / rain / night can be judged
## without the real WorldRoot. Used by env_gallery.gd / env_perf.gd / env_test.gd.
##   var rig := EnvTestScene.build(parent)   # returns {"root": Node3D, "cam": Camera3D, "lamps": int}

const WINDOW_SHADER_CODE := """
shader_type spatial;
global uniform float gta_night;
global uniform float gta_wetness;
uniform vec4 wall_color : source_color = vec4(0.85, 0.8, 0.75, 1.0);
uniform vec4 glass_color : source_color = vec4(0.25, 0.42, 0.55, 1.0);
uniform float seed = 1.0;
varying vec3 wpos;
varying vec3 wnrm;
float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 alb = wall_color.rgb;
	float side = 1.0 - step(0.5, abs(wnrm.y));
	float along = abs(wnrm.x) > 0.5 ? wpos.z : wpos.x;
	vec2 cell = vec2(along / 3.4, wpos.y / 3.6);
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.22, f.y) * step(f.y, 0.78) * side * step(3.0, wpos.y);
	float lit = step(0.5, h21(id + seed * 13.0)) * win;
	vec3 glass = glass_color.rgb;
	vec3 base = mix(alb, glass, win);
	ALBEDO = base;
	ROUGHNESS = mix(0.85, 0.12, win) * mix(1.0, 0.6, gta_wetness);
	METALLIC = win * 0.2;
	vec3 warm = vec3(1.0, 0.78, 0.45);
	vec3 cool = vec3(0.6, 0.85, 1.0);
	EMISSION = mix(warm, cool, step(0.85, h21(id + 7.0))) * lit * gta_night * 1.5;
}
"""

const ASPHALT_SHADER_CODE := """
shader_type spatial;
global uniform float gta_wetness;
uniform vec4 base_color : source_color = vec4(0.23, 0.25, 0.29, 1.0);
void fragment() {
	float wet = clamp(gta_wetness, 0.0, 1.0);
	ALBEDO = base_color.rgb * mix(1.0, 0.55, wet);
	ROUGHNESS = mix(0.92, 0.12, wet);
	METALLIC = 0.0;
	SPECULAR = mix(0.4, 0.8, wet);
}
"""

const PASTELS := ["#f2d6c9", "#cfe6e1", "#f3e4a8", "#bcd2f0", "#e9b5c8", "#d9d3ee", "#f6c7a0", "#b9e2c4"]


static func build(parent: Node) -> Dictionary:
	var root := Node3D.new()
	root.name = "EnvTestScene"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	# ---- ground + sea ----
	var asphalt := ShaderMaterial.new()
	var asphalt_shader := Shader.new()
	asphalt_shader.code = ASPHALT_SHADER_CODE
	asphalt.shader = asphalt_shader
	var land := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 400)
	land.mesh = pm
	land.material_override = asphalt
	land.position = Vector3(0, 0, 0)
	root.add_child(land)
	var body := StaticBody3D.new()
	body.collision_layer = GC.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(900, 1, 400)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	root.add_child(body)

	var sea := MeshInstance3D.new()
	var spm := PlaneMesh.new()
	spm.size = Vector2(4000, 2000)
	sea.mesh = spm
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("#1f8fb5")
	water.metallic = 0.35
	water.roughness = 0.12
	sea.material_override = water
	sea.position = Vector3(0, GC.WATER_LEVEL, 1200)
	root.add_child(sea)
	var seabed := MeshInstance3D.new()
	var bpm := PlaneMesh.new()
	bpm.size = Vector2(4000, 2000)
	seabed.mesh = bpm
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color("#d8c79a")
	sand.roughness = 1.0
	seabed.material_override = sand
	seabed.position = Vector3(0, -28.0, 1200)
	root.add_child(seabed)
	# beach wedge
	var beach := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(900, 0.4, 24)
	beach.mesh = bm
	beach.material_override = sand
	beach.position = Vector3(0, -0.2, 212)
	root.add_child(beach)

	# ---- blocks of towers ----
	var sidewalk := StandardMaterial3D.new()
	sidewalk.albedo_color = Color("#a9adb3")
	sidewalk.roughness = 0.85
	var shader := Shader.new()
	shader.code = WINDOW_SHADER_CODE
	var lamp_count := 0
	for i in range(-6, 7):
		for j in range(-3, 3):
			var cx := i * 60.0
			var cz := j * 60.0
			var slab := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(44, 0.3, 44)
			slab.mesh = sm
			slab.material_override = sidewalk
			slab.position = Vector3(cx, 0.15, cz)
			root.add_child(slab)
			var centre_bias := 1.0 - clampf(Vector2(cx, cz).length() / 380.0, 0.0, 1.0)
			var h := rng.randf_range(10.0, 26.0) + centre_bias * rng.randf_range(10.0, 60.0)
			var w := rng.randf_range(24.0, 34.0)
			var d := rng.randf_range(24.0, 34.0)
			var b := MeshInstance3D.new()
			var bmesh := BoxMesh.new()
			bmesh.size = Vector3(w, h, d)
			b.mesh = bmesh
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("wall_color", Color(PASTELS[rng.randi() % PASTELS.size()]))
			mat.set_shader_parameter("seed", rng.randf() * 10.0)
			b.material_override = mat
			b.position = Vector3(cx, h * 0.5 + 0.3, cz)
			root.add_child(b)
			# lamps on the street corners
			for corner in [Vector2(-24, -24), Vector2(24, 24)]:
				var lamp := _make_lamp(Vector3(cx + corner.x, 0.0, cz + corner.y))
				root.add_child(lamp)
				lamp_count += 1

	# ---- cars ----
	var car_cols := ["#e8334a", "#2fb6e8", "#f2c230", "#f4f4f6", "#2a2f38", "#8f5be0"]
	for k in 10:
		var car := _make_car(Color(car_cols[k % car_cols.size()]))
		car.position = Vector3(-18.0 + k * 4.0 + (k % 2) * 1.5, 0.0, 6.0 + (k % 3) * 3.2)
		car.rotation.y = (PI * 0.5) if k % 2 == 0 else (-PI * 0.5)
		root.add_child(car)

	# ---- palms along the beach ----
	for k in 30:
		var palm := _make_palm()
		palm.position = Vector3(-280.0 + k * 19.0, 0.0, 198.0 + rng.randf_range(-3.0, 4.0))
		root.add_child(palm)

	# ---- distant hills (aerial perspective) ----
	var hill_mat := StandardMaterial3D.new()
	hill_mat.albedo_color = Color("#6f9a78")
	hill_mat.roughness = 1.0
	for k in 22:
		var a := PI + float(k) / 21.0 * PI          # north half-circle (z <= 0) so the south stays open sea
		if k % 5 == 0:
			a = float(k) * 0.37 + 0.2               # a few east / west ones
		var r := rng.randf_range(420.0, 800.0)
		var hill := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = rng.randf_range(90.0, 180.0)
		cm.height = rng.randf_range(50.0, 140.0)
		cm.radial_segments = 6
		hill.mesh = cm
		hill.material_override = hill_mat
		hill.position = Vector3(cos(a) * r, cm.height * 0.5 - 4.0, minf(sin(a) * r, 60.0))
		root.add_child(hill)

	# ---- camera ----
	var cam := Camera3D.new()
	cam.name = "EnvTestCamera"
	cam.fov = 70.0
	cam.far = 2500.0
	root.add_child(cam)
	cam.global_position = Vector3(0, 2.6, 30)
	cam.look_at(Vector3(0, 6, -60), Vector3.UP)
	cam.make_current()
	Game.gameplay_camera = cam
	return {"root": root, "cam": cam, "lamps": lamp_count}


static func _make_lamp(pos: Vector3) -> Node3D:
	var lamp := Node3D.new()
	lamp.name = "TestLamp"
	lamp.position = pos
	lamp.add_to_group("street_lamp")
	lamp.set_meta("lamp_height", 6.2)
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.1
	cm.height = 6.2
	cm.radial_segments = 6
	pole.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#3d4450")
	pm.roughness = 0.6
	pole.material_override = pm
	pole.position = Vector3(0, 3.1, 0)
	lamp.add_child(pole)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.9, 0.18, 0.4)
	head.mesh = hm
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("#fff0c8")
	glow.emission_enabled = true
	glow.emission = Color("#ffcf80")
	glow.emission_energy_multiplier = 1.5
	head.material_override = glow
	head.position = Vector3(0, 6.25, 0)
	lamp.add_child(head)
	return lamp


static func _make_car(col: Color) -> Node3D:
	var car := Node3D.new()
	car.name = "TestCar"
	var paint := StandardMaterial3D.new()
	paint.albedo_color = col
	paint.metallic = 0.7
	paint.roughness = 0.25
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("#1a2330")
	glass.metallic = 0.5
	glass.roughness = 0.08
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.7, 4.2)
	body.mesh = bm
	body.material_override = paint
	body.position = Vector3(0, 0.65, 0)
	car.add_child(body)
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.6, 0.6, 2.2)
	cabin.mesh = cm
	cabin.material_override = glass
	cabin.position = Vector3(0, 1.25, -0.1)
	car.add_child(cabin)
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color("#15171a")
	for sx in [-0.95, 0.95]:
		for sz in [-1.4, 1.4]:
			var w := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.34
			wm.bottom_radius = 0.34
			wm.height = 0.25
			wm.radial_segments = 10
			w.mesh = wm
			w.material_override = wheel_mat
			w.rotation.z = PI * 0.5
			w.position = Vector3(sx, 0.34, sz)
			car.add_child(w)
	return car


static func _make_palm() -> Node3D:
	var palm := Node3D.new()
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color("#9a7a52")
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color("#3fa862")
	leaf_mat.roughness = 0.8
	var t := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18
	tm.bottom_radius = 0.28
	tm.height = 7.0
	tm.radial_segments = 6
	t.mesh = tm
	t.material_override = trunk_mat
	t.position = Vector3(0, 3.5, 0)
	palm.add_child(t)
	for k in 6:
		var leaf := MeshInstance3D.new()
		var lm := PrismMesh.new()
		lm.size = Vector3(0.8, 3.4, 0.12)
		leaf.mesh = lm
		leaf.material_override = leaf_mat
		leaf.position = Vector3(0, 7.0, 0)
		leaf.rotation = Vector3(deg_to_rad(-70.0), float(k) / 6.0 * TAU, 0.0)
		leaf.translate_object_local(Vector3(0, 1.4, 0))
		palm.add_child(leaf)
	return palm
