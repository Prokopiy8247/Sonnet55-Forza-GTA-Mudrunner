extends Node
## Renders rig contact sheets into screenshots/rig/*.png through a private SubViewport (own World3D, own light), so the result does
## not depend on the game world. Needs a real renderer:
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\rig\final.png -GameArgs "--exec=res://gta/tests/rig_sheet.gd --delay=2"
## Optional sheet selection (comma list) through the environment variable RIG_SHEETS, default = all:
##   variants, walk, run, aim, stances, actions, ragdoll, sockets

const OUT_DIR := "res://screenshots/rig/"

var _vp: SubViewport = null
var _cam: Camera3D = null
var _root: Node3D = null
var _figs: Array[CharacterRig] = []
var _floor: StaticBody3D = null
var _labels: Array[Label3D] = []


func run(main: Node) -> Variant:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var sel := OS.get_environment("RIG_SHEETS")
	var want: Array = [] if sel == "" else sel.split(",")
	_setup_viewport()
	await get_tree().process_frame
	var sheets: Array[String] = ["variants", "walk", "run", "aim", "stances", "actions", "sockets", "ragdoll", "closeups", "timeline"]
	for s in sheets:
		if want.is_empty() or s in want:
			print("SHEET ", s)
			await call("_sheet_" + s)
	_vp.queue_free()
	return true


# ---------------------------------------------------------------------------------------------------------------------
func _setup_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1920, 1080)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.transparent_bg = false
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.27, 0.33)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.75)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-48, -32, 0)
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.rotation_degrees = Vector3(-20, 150, 0)
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_cam.far = 200.0
	_vp.add_child(_cam)
	_cam.current = true
	_root = Node3D.new()
	_vp.add_child(_root)
	_floor = StaticBody3D.new()
	_floor.collision_layer = GC.L_WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 200)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	_floor.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.5, 0.52)
	mat.roughness = 0.95
	mi.material_override = mat
	_floor.add_child(mi)
	_vp.add_child(_floor)


func _clear() -> void:
	for f in _figs:
		if is_instance_valid(f):
			f.queue_free()
	for l in _labels:
		if is_instance_valid(l):
			l.queue_free()
	_figs.clear()
	_labels.clear()
	for c in _root.get_children():
		c.queue_free()


func _add_fig(variant: Dictionary, pos: Vector3, label: String = "", yaw_deg: float = 0.0) -> CharacterRig:
	var r := CharacterRig.new()
	r.manual_update = true
	_root.add_child(r)
	r.position = pos
	r.rotation_degrees.y = yaw_deg
	r.setup(variant)
	_figs.append(r)
	if label != "":
		var l := Label3D.new()
		l.text = label
		l.font_size = 40
		l.pixel_size = 0.005
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.modulate = Color(1, 1, 1)
		l.outline_size = 8
		l.position = pos + Vector3(0, 2.15, 0)
		_root.add_child(l)
		_labels.append(l)
	return r


func _step(r: CharacterRig, frames: int, dt: float = 1.0 / 60.0, move_speed: float = 0.0) -> void:
	for i in frames:
		if move_speed != 0.0:
			r.position += -r.global_transform.basis.z * move_speed * dt
		r.update_pose(dt)


func _look(from: Vector3, at: Vector3, fov: float = 30.0) -> void:
	_cam.fov = fov
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)


func _save(name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + name + ".png")
	var err := img.save_png(path)
	print("SHOT ", path, " err=", err)


func _weapon_model(id: String) -> Node3D:
	if ModelLib.exists("weapons/" + id):
		return ModelLib.instance("weapons/" + id)
	# stand-in block so the hold direction is visible
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.12, 0.45)
	mi.mesh = bm
	mi.position = Vector3(0, 0.0, -0.18)
	n.add_child(mi)
	print("SHEET weapon model missing: ", id)
	return n


## Camera in front of a row of figures placed at x = -k * spacing (so the order reads left to right) facing the camera (-Z side).
func _figures_front(count: int, spacing: float, y_target: float = 0.9, dist: float = 0.0, fov: float = 30.0, z_target: float = 0.0) -> void:
	var width := spacing * float(count - 1) + 2.4
	var d := dist if dist > 0.0 else width * 1.05 / (2.0 * tan(deg_to_rad(fov * 0.5)) * 1.78)
	var cx := -spacing * float(count - 1) * 0.5
	_look(Vector3(cx, 1.3, -d), Vector3(cx, y_target, z_target), fov)


## Camera at +Z for side views of figures placed at x = +k * spacing (they face -X, walking to the left).
func _figures_side(count: int, spacing: float, y_target: float = 0.9, fov: float = 30.0) -> void:
	var width := spacing * float(count - 1) + 2.4
	var d := width * 1.05 / (2.0 * tan(deg_to_rad(fov * 0.5)) * 1.78)
	var cx := spacing * float(count - 1) * 0.5
	_look(Vector3(cx, 1.2, d), Vector3(cx, y_target, 0), fov)


# ---- Sheets ----------------------------------------------------------------------------------------------------------------------
func _sheet_variants() -> void:
	_clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var list: Array[Dictionary] = []
	list.append(CharacterVariants.player_default())
	for i in 3:
		list.append(CharacterVariants.police_officer(rng))
	list.append(CharacterVariants.tactical_officer(rng))
	list.append(CharacterVariants.tactical_officer(rng))
	list.append(CharacterVariants.gang_member(rng))
	list.append(CharacterVariants.gang_member(rng))
	list.append(CharacterVariants.shop_staff(rng))
	for i in 15:
		list.append(CharacterVariants.random_pedestrian(rng))
	for i in list.size():
		var col := i % 8
		var row := i / 8
		var r := _add_fig(list[i], Vector3(-col * 1.25, 0, row * 2.2), "", 12.0)
		r.set_idle_style([&"relaxed", &"relaxed", &"arms_crossed", &"hands_pockets", &"relaxed"][i % 5])
		_step(r, 90)
	_look(Vector3(-4.4, 3.4, -12.5), Vector3(-4.4, 0.75, 2.2), 34.0)
	await _save("variants")


func _sheet_walk() -> void:
	_clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var v := CharacterVariants.player_default()
	for k in 8:
		var r := _add_fig(v, Vector3(k * 1.2, 0, 0), "", 90.0)       # side view: facing +X... (yaw 90 faces -X)
		r.set_locomotion(1.4, Vector3(0, 0, -1), false)
		_step(r, 120)
		_step(r, int(round(float(k) * 7.5)))          # walk cycle = 60 frames at 1.4 m/s
	_figures_side(8, 1.2)
	await _save("walk_cycle")
	_clear()
	# strafe / backwards / crouch walk
	var labels := ["strafe L", "strafe R", "backwards", "crouch idle", "crouch walk", "walk+rifle", "walk+pistol", "walk+aim rifle"]
	var dirs := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0, 0, -1), Vector3(0, 0, -1), Vector3(0, 0, -1), Vector3(0, 0, -1)]
	for k in 8:
		var r := _add_fig(v, Vector3(-k * 1.3, 0, 0), labels[k])
		var spd := 1.3 if k != 3 else 0.0
		r.set_locomotion(spd, dirs[k], false)
		if k >= 3 and k <= 4:
			r.set_stance(&"crouch")
		if k == 5:
			r.set_weapon_pose(&"rifle")
		if k == 6:
			r.set_weapon_pose(&"pistol")
		if k == 7:
			r.set_weapon_pose(&"rifle")
			r.set_aim(true, 0.0, 0.0)
		_step(r, 100)
	_figures_front(8, 1.3)
	await _save("walk_variants")


func _sheet_run() -> void:
	_clear()
	var v := CharacterVariants.player_default()
	for k in 8:
		var r := _add_fig(v, Vector3(k * 1.35, 0, 0), "", 90.0)
		r.set_locomotion(4.5, Vector3(0, 0, -1), false)
		_step(r, 100)
		_step(r, int(round(float(k) * 5.0)))          # run cycle = 40 frames at 4.5 m/s
	_figures_side(8, 1.35)
	await _save("run_cycle")
	_clear()
	for k in 8:
		var r := _add_fig(v, Vector3(k * 1.5, 0, 0), "", 90.0)
		r.set_locomotion(7.0, Vector3(0, 0, -1), true)
		_step(r, 100)
		_step(r, int(round(float(k) * 4.4)))          # sprint cycle = 35 frames at 7 m/s
	_figures_side(8, 1.5)
	await _save("sprint_cycle")


func _sheet_aim() -> void:
	_clear()
	var kinds := [&"pistol", &"smg", &"rifle", &"shotgun", &"sniper", &"heavy", &"melee_knife", &"melee_bat"]
	var ids := ["pistol", "smg", "rifle_assault", "shotgun_pump", "sniper", "rocket_launcher", "knife", "bat"]
	var v := CharacterVariants.police_officer()
	for k in 8:
		var r := _add_fig(v, Vector3(-k * 1.5, 0, 0), String(kinds[k]) + " aim", 35.0)
		r.set_weapon_pose(kinds[k])
		var w := _weapon_model(ids[k])
		r.get_hand_socket(true).add_child(w)
		r.set_aim(true, 0.0, 0.0)
		_step(r, 80)
		r.refresh_weapon_grip()
		_step(r, 40)
	_figures_front(8, 1.5, 1.0, 0.0, 34.0)
	await _save("aim_weapons")
	_clear()
	# carry + pitched aim
	for k in 8:
		var r := _add_fig(v, Vector3(-k * 1.5, 0, 0), String(kinds[k]) + (" carry" if k < 6 else " idle"), 35.0)
		r.set_weapon_pose(kinds[k])
		var w := _weapon_model(ids[k])
		r.get_hand_socket(true).add_child(w)
		_step(r, 80)
		r.refresh_weapon_grip()
		if k % 2 == 1:
			r.set_aim(true, 0.5, 0.0)
		_step(r, 60)
	_figures_front(8, 1.5, 1.0, 0.0, 34.0)
	await _save("carry_weapons")
	_clear()
	# aim from the side, pitch down / level / up with rifle
	var pitches := [-0.7, -0.3, 0.0, 0.4, 0.8]
	for k in 5:
		var r := _add_fig(v, Vector3(k * 1.5, 0, 0), "pitch %.1f" % pitches[k], 90.0)
		r.set_weapon_pose(&"rifle")
		r.get_hand_socket(true).add_child(_weapon_model("rifle_assault"))
		r.set_aim(true, pitches[k], 0.0)
		_step(r, 100)
	_figures_side(5, 1.5, 1.0)
	await _save("aim_pitch_side")


func _sheet_stances() -> void:
	var v := CharacterVariants.player_default()
	var groups := [
		[[&"crouch", "crouch"], [&"cover_low", "cover_low"], [&"cover_high", "cover_high"], [&"swim_surface", "swim_surface"], [&"swim_under", "swim_under"], [&"sit_car", "sit_car"]],
		[[&"sit_bike", "sit_bike"], [&"ladder", "ladder"], [&"parachute", "parachute"], [&"dead", "dead"], [&"stand", "hands_up"], [&"stand", "jump"]],
	]
	for gi in groups.size():
		for side_view in [false, true]:
			_clear()
			var grp: Array = groups[gi]
			for k in grp.size():
				var st: StringName = grp[k][0]
				var nm: String = grp[k][1]
				var pos := Vector3(k * 1.5 if side_view else -k * 1.5, 0, 0)
				var r := _add_fig(v, pos, nm, 90.0 if side_view else 25.0)
				if st == &"swim_surface" or st == &"swim_under":
					r.set_locomotion(1.8)
				if st == &"ladder":
					r.set_locomotion(1.0)
				r.set_stance(st)
				if nm == "hands_up":
					r.play_action(&"hands_up")
				if nm == "jump":
					r.play_action(&"jump")
					r.set_grounded(false, 3.0)
				if st == &"cover_low" or st == &"cover_high":
					r.set_weapon_pose(&"pistol")
					r.get_hand_socket(true).add_child(_weapon_model("pistol"))
				if st == &"sit_car":
					_mock_car(pos, 90.0 if side_view else 25.0)
				if st == &"sit_bike":
					_mock_bike(pos, 90.0 if side_view else 25.0)
				_step(r, 150)
			if side_view:
				_figures_side(grp.size(), 1.5, 0.8, 34.0)
			else:
				_figures_front(grp.size(), 1.5, 0.8, 0.0, 34.0)
			await _save("stances_%d%s" % [gi, "_side" if side_view else ""])


func _mock_car(pos: Vector3, yaw_deg: float) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation_degrees.y = yaw_deg
	_root.add_child(pivot)
	pos = Vector3.ZERO
	# seat cushion + steering wheel at the positions CharacterRig assumes (origin = seat point)
	var seat := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.1, 0.5)
	seat.mesh = bm
	seat.position = pos + Vector3(0, -0.05, 0.05)
	pivot.add_child(seat)
	var back := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.5, 0.6, 0.08)
	back.mesh = bb
	back.position = pos + Vector3(0, 0.3, 0.3)
	pivot.add_child(back)
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.17
	tm.outer_radius = 0.20
	wheel.mesh = tm
	var axis := Vector3(0, 0.38, -0.93).normalized()
	wheel.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), pos + Vector3(0, 0.30, -0.45))
	pivot.add_child(wheel)


func _mock_bike(pos: Vector3, yaw_deg: float) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation_degrees.y = yaw_deg
	_root.add_child(pivot)
	pos = Vector3.ZERO
	var seat := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.12, 0.6)
	seat.mesh = bm
	seat.position = pos + Vector3(0, -0.06, 0.1)
	pivot.add_child(seat)
	var bar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.02
	cm.height = 0.7
	bar.mesh = cm
	bar.transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90)), pos + Vector3(0, 0.45, -0.55))
	pivot.add_child(bar)


func _sheet_actions() -> void:
	_clear()
	var v := CharacterVariants.player_default()
	var acts := [&"punch", &"punch", &"kick", &"melee_swing", &"melee_swing", &"reload", &"reload", &"throw", &"hit_react", &"jump", &"land", &"enter_vehicle"]
	var weapons := [&"none", &"none", &"none", &"melee_bat", &"melee_knife", &"pistol", &"rifle", &"thrown", &"none", &"none", &"none", &"none"]
	var fracs := [0.33, 0.62, 0.45, 0.42, 0.40, 0.45, 0.45, 0.5, 0.15, 0.4, 0.3, 0.45]
	for k in acts.size():
		var r := _add_fig(v, Vector3(-(k % 6) * 2.0, 0.0, (k / 6) * 2.6), "%s %s" % [acts[k], weapons[k]], 30.0)
		r.set_weapon_pose(weapons[k])
		if weapons[k] == &"pistol":
			r.get_hand_socket(true).add_child(_weapon_model("pistol"))
		elif weapons[k] == &"rifle":
			r.get_hand_socket(true).add_child(_weapon_model("rifle_assault"))
		elif weapons[k] == &"melee_bat":
			r.get_hand_socket(true).add_child(_weapon_model("bat"))
		elif weapons[k] == &"melee_knife":
			r.get_hand_socket(true).add_child(_weapon_model("knife"))
		_step(r, 60)
		if k > 0 and acts[k] == acts[k - 1] and k == 1:
			r.play_action(acts[k])
		r.play_action(acts[k])
		if acts[k] == &"hit_react":
			r.hit_react(Vector3(0, 0, 1), 1.0)
		if acts[k] == &"jump":
			r.set_grounded(false, 3.0)
		if acts[k] == &"land":
			r.set_grounded(false, -5.0)
			_step(r, 20)
			r.set_grounded(true, -5.0)
		var dur := 0.55
		match acts[k]:
			&"reload":
				dur = 1.7
			&"punch":
				dur = 0.42
			&"kick":
				dur = 0.62
			&"melee_swing":
				dur = 0.62 if weapons[k] == &"melee_bat" else 0.48
			&"throw":
				dur = 0.75
			&"hit_react":
				dur = 0.4
			&"jump":
				dur = 0.5
			&"land":
				dur = 0.5
		_step(r, int(round(dur * fracs[k] * 60.0)))
	_look(Vector3(-5.0, 3.0, -11.5), Vector3(-5.0, 0.9, 1.2), 36.0)
	await _save("actions")


func _sheet_sockets() -> void:
	_clear()
	var v := CharacterVariants.police_officer()
	# close-up of the right hand holding a pistol, from several angles
	var r := _add_fig(v, Vector3.ZERO, "", 0.0)
	r.set_weapon_pose(&"pistol")
	r.get_hand_socket(true).add_child(_weapon_model("pistol"))
	r.set_aim(true, 0.0, 0.0)
	_step(r, 100)
	r.refresh_weapon_grip()
	_step(r, 30)
	_look(Vector3(0.9, 1.5, -2.2), Vector3(0.0, 1.35, -0.5), 30.0)
	await _save("pistol_closeup_front")
	_look(Vector3(2.0, 1.5, -0.8), Vector3(0.1, 1.35, -0.5), 28.0)
	await _save("pistol_closeup_side")
	_look(Vector3(-0.6, 1.6, 2.0), Vector3(0.0, 1.4, -0.3), 30.0)
	await _save("pistol_closeup_back")


func _sheet_ragdoll() -> void:
	_clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var shots := [0.3, 0.7, 1.4, 4.0]
	var impulses := [Vector3(0, 1, -6), Vector3(5, 2, -2), Vector3(-3, 0, 5), Vector3(0, 6, 0), Vector3(1, 0.5, -9)]
	var rigs: Array[CharacterRig] = []
	for k in 5:
		var r := _add_fig(CharacterVariants.random_pedestrian(rng), Vector3(k * 2.4, 0.02, 0), "", 0.0)
		r.set_locomotion(0.0)
		_step(r, 30)
		rigs.append(r)
	for k in 5:
		rigs[k].start_ragdoll(impulses[k], rigs[k].global_position + Vector3(0, 1.3, 0.2))
	var t := 0.0
	for s in shots:
		while t < s:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		_look(Vector3(4.8, 3.4, 8.0), Vector3(4.8, 0.2, -2.0), 40.0)
		await _save("ragdoll_%.1f" % s)
	for r in rigs:
		print("RAGDOLL frozen=", r.is_ragdoll_frozen(), " pos=", r.get_ragdoll_position())


## Larger views of the seated / climbing / swimming poses (3 figures per image, front-3/4 and side).
func _sheet_closeups() -> void:
	var v := CharacterVariants.player_default()
	var groups := [
		["sit_car", "sit_bike", "ladder"],
		["cover_low", "cover_high", "hands_up"],
		["swim_surface", "swim_under", "parachute"],
		["dead_up", "dead_down", "crouch"],
	]
	var gi := 0
	for grp in groups:
		for side_view in [false, true]:
			_clear()
			for k in grp.size():
				var nm: String = grp[k]
				var pos := Vector3(k * 1.9 if side_view else -k * 1.9, 0, 0)
				var yaw := 90.0 if side_view else 30.0
				var r := _add_fig(v, pos, nm, yaw)
				match nm:
					"sit_car":
						r.set_stance(&"sit_car")
						_mock_car(pos, yaw)
					"sit_bike":
						r.set_stance(&"sit_bike")
						_mock_bike(pos, yaw)
					"ladder":
						r.set_locomotion(1.0, Vector3(0, 1, 0))
						r.set_stance(&"ladder")
					"cover_low", "cover_high":
						r.set_weapon_pose(&"rifle")
						r.get_hand_socket(true).add_child(_weapon_model("rifle_assault"))
						r.set_stance(StringName(nm))
					"hands_up":
						r.play_action(&"hands_up")
					"swim_surface", "swim_under":
						r.set_locomotion(1.8)
						r.set_stance(StringName(nm))
					"parachute":
						r.set_stance(&"parachute")
					"dead_up", "dead_down":
						r.motion.dead_face_down = (nm == "dead_down")
						r.set_stance(&"dead")
						r.motion.dead_face_down = (nm == "dead_down")
					"crouch":
						r.set_stance(&"crouch")
						r.set_weapon_pose(&"pistol")
						r.get_hand_socket(true).add_child(_weapon_model("pistol"))
						r.set_aim(true)
				_step(r, 160)
			if side_view:
				_figures_side(grp.size(), 1.9, 0.8, 30.0)
			else:
				_figures_front(grp.size(), 1.9, 0.8, 0.0, 30.0)
			await _save("closeup_%d%s" % [gi, "_side" if side_view else ""])
		gi += 1


## Frame-by-frame strips of the timed actions (7 frames each) to judge the motion arcs.
func _sheet_timeline() -> void:
	var v := CharacterVariants.police_officer()
	var sets := [
		[["punch", &"punch", &"none", ""], ["bat swing", &"melee_swing", &"melee_bat", "bat"], ["knife", &"melee_swing", &"melee_knife", "knife"]],
		[["throw", &"throw", &"thrown", "grenade"], ["reload pistol", &"reload", &"pistol", "pistol"], ["kick", &"kick", &"none", ""]],
	]
	var si := 0
	for set_ in sets:
		_clear()
		var row := 0
		for e in set_:
			var dur := 0.45
			match e[1]:
				&"reload":
					dur = 1.7
				&"kick":
					dur = 0.62
				&"throw":
					dur = 0.75
				&"melee_swing":
					dur = 0.62 if e[2] == &"melee_bat" else 0.48
			for k in 7:
				var r := _add_fig(v, Vector3(-k * 1.45, 0, row * 3.3), "" if k > 0 else String(e[0]), 35.0)
				r.set_weapon_pose(e[2])
				if String(e[3]) != "":
					r.get_hand_socket(true).add_child(_weapon_model(String(e[3])))
				_step(r, 60)
				r.play_action(e[1])
				var frac := 0.08 + float(k) * 0.14
				_step(r, int(round(dur * frac * 60.0)))
			row += 1
		_look(Vector3(-4.35, 5.2, -11.0), Vector3(-4.35, 0.4, 3.0), 40.0)
		await _save("timeline_%d" % si)
		si += 1
