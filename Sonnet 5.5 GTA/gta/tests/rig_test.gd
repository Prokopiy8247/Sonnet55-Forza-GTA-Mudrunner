extends Node
## Rig test suite (headless safe). Run with Main:   tools\gd.ps1 exec -Script res://gta/tests/rig_test.gd -Seconds 120
## or standalone (no Main needed):                  tools\gd.ps1 script -Script res://gta/tests/rig_runner.gd -Seconds 120
## Prints "TEST <name> PASS|FAIL <detail>" lines.

var _stage: Node3D = null
var _fails := 0
var _passes := 0


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
	else:
		_fails += 1
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _make_stage(parent: Node) -> void:
	_stage = Node3D.new()
	_stage.name = "RigTestStage"
	parent.add_child(_stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = GC.L_WORLD
	floor_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	floor_body.add_child(cs)
	_stage.add_child(floor_body)


func _rig(variant: Dictionary, pos: Vector3 = Vector3.ZERO) -> CharacterRig:
	var r := CharacterRig.new()
	r.manual_update = true
	_stage.add_child(r)
	r.position = pos
	r.setup(variant)
	return r


func _step(r: CharacterRig, frames: int, dt: float = 1.0 / 60.0) -> void:
	for i in frames:
		r.update_pose(dt)


func _bone_pos(r: CharacterRig, bone: String) -> Vector3:
	var sk := r.get_skeleton()
	var i := sk.find_bone(bone)
	return sk.global_transform * sk.get_bone_global_pose(i).origin


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _skeleton_ok(r: CharacterRig) -> bool:
	var sk := r.get_skeleton()
	for i in sk.get_bone_count():
		var gp := sk.get_bone_global_pose(i)
		if not _finite(gp.origin) or not _finite(gp.basis.x):
			return false
	return true


func run(main: Node) -> Variant:
	_make_stage(main)
	await get_tree().process_frame
	print("TEST info model_exists=%s" % [ModelLib.exists("characters/human")])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	# ---- 1. build all variant kinds -------------------------------------------------------------------------------------
	var kinds: Array[StringName] = [&"player", &"pedestrian", &"police", &"tactical", &"shop", &"gang"]
	var built_ok := true
	var detail := ""
	for k in kinds:
		for n in (1 if k == &"player" else 6):
			var v := CharacterVariants.make(k, rng)
			var r := _rig(v)
			if not r.is_built() or not r.solver.valid:
				built_ok = false
				detail += " %s:unbuilt" % k
			var bodies := 0
			for mi in ModelLib.meshes(r.model):
				if String(mi.name).begins_with("Body_"):
					bodies += 1
			if bodies != 1:
				built_ok = false
				detail += " %s:bodies=%d" % [k, bodies]
			_step(r, 5)
			r.queue_free()
	_check("rig_build_variants", built_ok, "fallback=%s%s" % [CharacterRig.new().using_fallback, detail])

	# ---- 2. variants diversity ----------------------------------------------------------------------------------------------
	var seen := {}
	var bodies_cnt := {&"A": 0, &"B": 0, &"C": 0}
	var scale_ok := true
	for i in 300:
		var v := CharacterVariants.random_pedestrian(rng)
		seen["%s|%s|%s|%s|%s|%s|%s" % [v["body"], v["hair"], v["shirt"], v["pants"], v["hat"], v["jacket"], v["skin"]]] = true
		bodies_cnt[v["body"]] += 1
		var sc: float = v["scale"]
		if sc < 0.92 or sc > 1.08:
			scale_ok = false
	_check("variants_diverse", seen.size() > 250 and bodies_cnt[&"A"] > 60 and bodies_cnt[&"B"] > 60 and bodies_cnt[&"C"] > 20 and scale_ok,
		"unique=%d A/B/C=%s" % [seen.size(), bodies_cnt])
	var nm := CharacterVariants.appearance_name(CharacterVariants.player_default())
	_check("variants_names", nm.length() > 10, nm)
	print("TEST info ", CharacterVariants.appearance_name(CharacterVariants.police_officer(rng)))
	print("TEST info ", CharacterVariants.appearance_name(CharacterVariants.gang_member(rng)))

	# ---- 3. every stance / action produces finite, sane poses ------------------------------------------------------------------
	var stances: Array[StringName] = [&"stand", &"crouch", &"cover_low", &"cover_high", &"swim_surface", &"swim_under", &"sit_car",
		&"sit_bike", &"ladder", &"parachute", &"dead"]
	var r := _rig(CharacterVariants.player_default())
	var sane := true
	var msg := ""
	for st in stances:
		r.set_stance(st)
		r.set_locomotion(1.4 if st != &"sit_car" else 0.0, Vector3(0, 0, -1), false)
		_step(r, 100)
		if not _skeleton_ok(r):
			sane = false
			msg += " %s:nan" % st
		var head := _bone_pos(r, "Head")
		var hips := _bone_pos(r, "Hips")
		if st in [&"stand", &"crouch", &"cover_low", &"cover_high"] and head.y < hips.y + 0.3:
			sane = false
			msg += " %s:head_low(%.2f)" % [st, head.y - hips.y]
		for b in ["Foot_R", "Foot_L"]:
			var fp := _bone_pos(r, b)
			if st in [&"stand", &"crouch", &"cover_low", &"cover_high"] and (fp.y < -0.03 or fp.y > 0.45):
				sane = false
				msg += " %s:%s_y=%.2f" % [st, b, fp.y]
		for b in ["Hand_R", "Hand_L"]:
			var hp := _bone_pos(r, b)
			if hp.distance_to(hips) > 1.1:
				sane = false
				msg += " %s:%s_far(%.2f)" % [st, b, hp.distance_to(hips)]
	r.set_stance(&"stand")
	_step(r, 60)
	_check("rig_stances_sane", sane, msg)

	# ---- 4. actions run without errors and end ---------------------------------------------------------------------------------
	var acts: Array[StringName] = [&"punch", &"kick", &"melee_swing", &"reload", &"hit_react", &"jump", &"land", &"enter_vehicle", &"exit_vehicle", &"throw", &"hands_up"]
	var act_ok := true
	r.set_weapon_pose(&"pistol")
	for a in acts:
		r.play_action(a)
		for i in 90:
			r.update_pose(1.0 / 60.0)
			if i == 20 and not _skeleton_ok(r):
				act_ok = false
				msg += " " + String(a)
		if a == &"jump":
			r.set_grounded(false, 3.0)
	r.set_grounded(true, 0.0)
	r.play_action(&"hands_down")
	_step(r, 120)
	_check("rig_actions", act_ok and not r.is_action_playing(), msg)

	# ---- 5. no foot sliding while walking / running ---------------------------------------------------------------------------------
	for sp in [1.4, 2.4, 4.5, 7.0]:
		var rr := _rig(CharacterVariants.random_pedestrian(rng))
		rr.set_locomotion(sp, Vector3(0, 0, -1), sp > 5.0)
		var dt := 1.0 / 60.0
		_step_move(rr, 90, dt, sp)           # warm up
		var slide_max := 0.0
		var plant_frames := 0
		var prev := [Vector3.ZERO, Vector3.ZERO]
		var have := [false, false]
		var stance_start := [Vector3.ZERO, Vector3.ZERO]
		var in_stance := [false, false]
		for i in 360:
			_step_move(rr, 1, dt, sp)
			var j := 0
			for b in ["Foot_R", "Foot_L"]:
				var fp := _bone_pos(rr, b)
				var planted := fp.y < 0.115
				if planted and not in_stance[j]:
					in_stance[j] = true
					stance_start[j] = fp
				elif planted and in_stance[j]:
					plant_frames += 1
					slide_max = maxf(slide_max, Vector2(fp.x - stance_start[j].x, fp.z - stance_start[j].z).length())
				elif not planted:
					in_stance[j] = false
				j += 1
		# the ankle rolls forward ~0.1 m while the foot is planted; anything beyond ~0.3 m is a visible slide
		_check("rig_no_slide_%.1f" % sp, slide_max < 0.34 and plant_frames > 60, "max_ankle_travel_in_stance=%.3f m planted_frames=%d" % [slide_max, plant_frames])
		rr.queue_free()

	# ---- 6. hand sockets + weapon models -----------------------------------------------------------------------------------------
	r.set_stance(&"stand")
	r.set_weapon_pose(&"pistol")
	r.set_locomotion(0.0)
	r.set_aim(true, 0.0, 0.0)
	_step(r, 60)
	await get_tree().process_frame
	var sock := r.get_hand_socket(true)
	var hand := _bone_pos(r, "Hand_R")
	var fwd := -sock.global_transform.basis.z
	var rig_fwd := -r.global_transform.basis.z
	_check("rig_socket_attached", sock.global_position.distance_to(hand) < 0.14, "dist=%.3f" % sock.global_position.distance_to(hand))
	_check("rig_socket_points_forward", fwd.dot(rig_fwd) > 0.85, "dot=%.3f fwd=%s" % [fwd.dot(rig_fwd), fwd])
	var weapon_ids := ["pistol", "carbine", "smg", "rifle_assault", "shotgun_pump", "sniper", "rocket_launcher", "bat", "knife"]
	var wnode: Node3D = null
	for wid in weapon_ids:
		if ModelLib.exists("weapons/" + wid):
			wnode = ModelLib.instance("weapons/" + wid)
			break
	if wnode != null:
		sock.add_child(wnode)
		r.set_weapon_pose(&"pistol")
		_step(r, 30)
		await get_tree().process_frame
		var muz := wnode.find_child("Muzzle", true, false) as Node3D
		if muz != null:
			var dir: Vector3 = (muz.global_position - sock.global_position).normalized()
			_check("rig_weapon_barrel_forward", dir.dot(rig_fwd) > 0.8, "dot=%.3f" % dir.dot(rig_fwd))
		else:
			print("TEST info weapon has no Muzzle node")
		r.refresh_weapon_grip()
		print("TEST info support_grip=", r.motion.has_support_grip)
		wnode.queue_free()
	else:
		print("TEST info no weapon GLB available for the socket test")
	r.set_aim(false)

	# ---- 6b. behaviours: grip, turn lean, hands up, re-setup, first person, auto landing, ladder ---------------------------------
	if wnode == null:
		wnode = null
	var rg := _rig(CharacterVariants.police_officer())
	rg.set_weapon_pose(&"pistol")
	var pistol := ModelLib.instance("weapons/pistol") if ModelLib.exists("weapons/pistol") else null
	if pistol != null:
		rg.get_hand_socket(true).add_child(pistol)
		rg.set_aim(true, 0.0, 0.0)
		_step(rg, 90)
		await get_tree().process_frame
		var grip := pistol.find_child("Grip_L", true, false) as Node3D
		if grip != null:
			var lh := _bone_pos(rg, "Hand_L")
			var dgrip := lh.distance_to(grip.global_position)
			_check("rig_left_hand_on_grip", dgrip < 0.12, "wrist-to-Grip_L=%.3f m (palm is ~0.05 m beyond the wrist)" % dgrip)
		# re-dress keeps the weapon mounted
		rg.setup(CharacterVariants.gang_member(rng))
		await get_tree().process_frame
		_check("rig_resetup_keeps_weapon", pistol.is_inside_tree() and pistol.get_parent() == rg.get_hand_socket(true), "")
	rg.set_aim(false)
	rg.set_weapon_pose(&"none")
	# turn lean: running while the owner yaws
	var rt := _rig(CharacterVariants.random_pedestrian(rng), Vector3(30, 0, 0))
	rt.set_locomotion(5.0, Vector3(0, 0, -1), false)
	rt.manual_update = true
	for i in 60:
		rt.rotation.y += 0.0
		rt.update_pose(1.0 / 60.0)
	var straight := (_bone_pos(rt, "Head") - _bone_pos(rt, "Hips")).dot(rt.global_transform.basis.x)
	for i in 50:
		rt.rotation.y += 2.4 / 60.0
		rt.update_pose(1.0 / 60.0)
	var turning := (_bone_pos(rt, "Head") - _bone_pos(rt, "Hips")).dot(rt.global_transform.basis.x)
	_check("rig_turn_lean", absf(turning - straight) > 0.012, "straight=%.3f turning=%.3f" % [straight, turning])
	# hands up releases itself
	rt.rotation.y = 0.0
	rt.motion.hands_up_hold = 0.3
	rt.play_action(&"hands_up")
	_step(rt, 10)
	var up_now: bool = rt.motion.hands_up
	_step(rt, 40)
	_check("rig_hands_up_timeout", up_now and not rt.motion.hands_up, "")
	# first person
	rt.set_first_person(true)
	var hidden := true
	for mi in ModelLib.meshes(rt.model):
		var nn := String(mi.name)
		if (nn.begins_with("Hair_") or nn.begins_with("Hat_")) and mi.visible:
			hidden = false
	var head_i := rt.get_skeleton().find_bone("Head")
	var small := rt.get_skeleton().get_bone_pose_scale(head_i).x < 0.05
	rt.set_first_person(false)
	_check("rig_first_person", hidden and small and rt.get_skeleton().get_bone_pose_scale(head_i).x > 0.9, "")
	# a plain jump hop lands by itself
	rt.set_locomotion(0.0)
	rt.play_action(&"jump")
	_step(rt, 120)
	_check("rig_jump_autoland", rt.motion.grounded, "")
	# ladder phase follows the sign of the vertical direction
	rt.set_stance(&"ladder")
	rt.set_locomotion(1.0, Vector3(0, 1, 0))
	_step(rt, 60)
	var ph_up: float = rt.motion._ladder_phase
	rt.set_locomotion(1.0, Vector3(0, -1, 0))
	_step(rt, 60)
	var ph_down: float = rt.motion._ladder_phase
	_check("rig_ladder_direction", ph_up > 0.5 and ph_down < ph_up - 0.5, "up=%.2f down=%.2f" % [ph_up, ph_down])
	rt.queue_free()
	rg.queue_free()

	# ---- 6c. setup() before the rig is in the tree (pooled NPCs), empty variant, API before setup ---------------------------------
	var off := CharacterRig.new()
	off.manual_update = true
	var sock_early_ok := off.get_hand_socket(true) is Node3D          # API before setup builds a default body
	off.setup({})
	_stage.add_child(off)
	off.position = Vector3(40, 0, 0)
	off.set_locomotion(1.4)
	_step(off, 60)
	await get_tree().process_frame
	var hand_off := _bone_pos(off, "Hand_R")
	var sock_now := off.get_hand_socket(true)
	_check("rig_offtree_setup", off.is_built() and sock_now.global_position.distance_to(hand_off) < 0.14 and sock_early_ok,
		"built=%s socket dist=%.3f" % [off.is_built(), sock_now.global_position.distance_to(hand_off)])
	off.queue_free()

	# ---- 6d. transitions are continuous (no pops): max bone travel per frame while switching states -------------------------------------
	var rp := _rig(CharacterVariants.player_default(), Vector3(60, 0, 0))
	var pops := _pop_sequences(rp)
	var worst_name := ""
	var worst := 0.0
	for k in pops:
		if pops[k] > worst:
			worst = pops[k]
			worst_name = k
	_check("rig_no_pops", worst < 0.25, "worst per-frame bone travel %.3f m in '%s' (all: %s)" % [worst, worst_name, _fmt_pops(pops)])
	rp.queue_free()

	# ---- 7. LOD ---------------------------------------------------------------------------------------------------------------------
	var rl := _rig(CharacterVariants.random_pedestrian(rng))
	rl.manual_update = false
	rl.auto_lod = false
	rl.set_locomotion(1.4)
	await get_tree().process_frame
	await get_tree().process_frame
	var p0 := _bone_pos(rl, "Foot_R")
	rl.lod = 2
	for i in 20:
		await get_tree().process_frame
	var p1 := _bone_pos(rl, "Foot_R")
	_check("rig_lod_frozen", p0.distance_to(p1) < 0.001, "moved=%.4f" % p0.distance_to(p1))
	rl.lod = 0
	for i in 20:
		await get_tree().process_frame
	var p2 := _bone_pos(rl, "Foot_R")
	_check("rig_lod_full_animates", p2.distance_to(p1) > 0.01, "moved=%.4f" % p2.distance_to(p1))
	rl.queue_free()

	# ---- 7b. automatic LOD from the camera distance ---------------------------------------------------------------------------------
	var cam := Camera3D.new()
	_stage.add_child(cam)
	cam.global_position = Vector3(0, 1.7, 40)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	var near_rig := _rig(CharacterVariants.random_pedestrian(rng), Vector3(0, 0, 30))
	var mid_rig := _rig(CharacterVariants.random_pedestrian(rng), Vector3(0, 0, -15))
	var far_rig := _rig(CharacterVariants.random_pedestrian(rng), Vector3(0, 0, -60))
	var behind_rig := _rig(CharacterVariants.random_pedestrian(rng), Vector3(0, 0, 80))   # behind the camera
	for q in [near_rig, mid_rig, far_rig, behind_rig]:
		q.manual_update = false
		q.set_locomotion(1.4)
	for i in 60:
		await get_tree().process_frame
	_check("rig_auto_lod", near_rig.lod == 0 and mid_rig.lod == 1 and far_rig.lod == 2 and behind_rig.lod == 2,
		"near=%d (10 m) mid=%d (55 m) far=%d (100 m) behind=%d" % [near_rig.lod, mid_rig.lod, far_rig.lod, behind_rig.lod])
	for q in [near_rig, mid_rig, far_rig, behind_rig]:
		q.queue_free()
	cam.queue_free()

	# ---- 8. performance (60 rigs) -----------------------------------------------------------------------------------------------------
	var crowd: Array[CharacterRig] = []
	for i in 60:
		var cr := _rig(CharacterVariants.random_pedestrian(rng), Vector3(i % 10 * 1.5, 0, i / 10 * 1.5))
		cr.set_locomotion(1.0 + float(i % 5) * 1.2, Vector3(0, 0, -1), false)
		crowd.append(cr)
	_step(crowd[0], 1)
	var t0 := Time.get_ticks_usec()
	for k in 30:
		for cr in crowd:
			cr.update_pose(1.0 / 60.0)
	var per := float(Time.get_ticks_usec() - t0) / (30.0 * crowd.size())
	_check("rig_perf_update", per < 600.0, "%.0f us per rig update (target < 450 on an idle machine, 600 allowed while other agents load the CPU)" % per)
	for cr in crowd:
		cr.queue_free()

	# ---- 9. ragdoll ----------------------------------------------------------------------------------------------------------------------
	await _ragdoll_tests()

	_stage.queue_free()
	print("TEST summary passes=%d fails=%d" % [_passes, _fails])
	return _fails == 0


func _step_move(r: CharacterRig, frames: int, dt: float, speed: float) -> void:
	for i in frames:
		r.position.z -= speed * dt
		r.update_pose(dt)


## Ragdoll tests run 300 m above the world (own floor) so traffic / pedestrians of the booted game can never touch the bodies.
func _ragdoll_tests() -> void:
	var ry := 300.0
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = GC.L_WORLD
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(200, 2, 200)
	fcs.shape = fbox
	fcs.position = Vector3(0, ry - 1.0, 0)
	floor_body.add_child(fcs)
	_stage.add_child(floor_body)
	var rr := _rig(CharacterVariants.police_officer(), Vector3(0, ry + 0.02, 0))
	rr.manual_update = true
	_step(rr, 10)
	var settled := [false]
	rr.ragdoll_settled.connect(func(): settled[0] = true)
	rr.start_ragdoll(Vector3(2, 1, -5), rr.global_position + Vector3(0, 1.3, 0.2))
	_check("rig_ragdoll_started", rr.is_ragdoll(), "")
	var t := 0.0
	var max_stretch := 0.0
	while t < 11.0 and not settled[0]:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if int(t * 60.0) % 30 == 0:
			max_stretch = maxf(max_stretch, _max_bone_stretch(rr))
	var hips := _bone_pos(rr, "Hips") - Vector3(0, ry, 0)
	var head := _bone_pos(rr, "Head") - Vector3(0, ry, 0)
	_check("rig_ragdoll_settles", settled[0] and t < 10.0, "t=%.1f s" % t)
	_check("rig_ragdoll_on_ground", hips.y < 0.45 and hips.y > -0.05 and head.y < 0.75 and _skeleton_ok(rr), "hips_y=%.2f head_y=%.2f" % [hips.y, head.y])
	_check("rig_ragdoll_no_stretch", max_stretch < 0.2, "max_bone_stretch=%.3f m" % max_stretch)
	var travelled := Vector2(hips.x, hips.z).length()
	_check("rig_ragdoll_impulse_moved", travelled > 0.8, "travelled=%.2f m" % travelled)
	rr.stop_ragdoll()
	_step(rr, 40)
	_check("rig_ragdoll_getup", not rr.is_ragdoll() and _skeleton_ok(rr), "")
	rr.queue_free()
	# live cap
	var group: Array[CharacterRig] = []
	for i in 11:
		var g := _rig(CharacterVariants.random_pedestrian(), Vector3(i * 1.2, ry + 0.02, -5))
		g.manual_update = true
		_step(g, 3)
		g.start_ragdoll(Vector3(0, 0, -2), Vector3.ZERO)
		group.append(g)
	for i in 5:
		await get_tree().physics_frame
	_check("rig_ragdoll_cap", RagdollBody.live.size() <= RagdollBody.MAX_LIVE, "live=%d" % RagdollBody.live.size())
	for g in group:
		g.queue_free()
	floor_body.queue_free()


## Largest deviation of a parent->child bone distance from the rest distance (detects exploded / stretched ragdolls).
func _max_bone_stretch(r: CharacterRig) -> float:
	var sk := r.get_skeleton()
	var worst := 0.0
	for i in sk.get_bone_count():
		var par := sk.get_bone_parent(i)
		if par < 0:
			continue
		var d_now := (sk.get_bone_global_pose(i).origin - sk.get_bone_global_pose(par).origin).length()
		var d_rest := (sk.get_bone_global_rest(i).origin - sk.get_bone_global_rest(par).origin).length()
		worst = maxf(worst, absf(d_now - d_rest))
	return worst


func _fmt_pops(d: Dictionary) -> String:
	var parts: Array[String] = []
	for k in d:
		parts.append("%s=%.3f" % [k, d[k]])
	return ", ".join(parts)


## Runs a list of state switches and returns {name: max per-frame travel of any bone (m)}.
func _pop_sequences(r: CharacterRig) -> Dictionary:
	var out := {}
	var sk := r.get_skeleton()
	var n := sk.get_bone_count()
	var prev := PackedVector3Array()
	prev.resize(n)
	var track := func(seq_name: String, frames: int) -> void:
		var worst: float = out.get(seq_name, 0.0)
		var worst_bone := ""
		for f in frames:
			r.update_pose(1.0 / 60.0)
			for i in n:
				var pp := sk.get_bone_global_pose(i).origin
				if f > 0 or out.has(seq_name + "_started"):
					var dd := pp.distance_to(prev[i])
					if dd > worst:
						worst = dd
						worst_bone = sk.get_bone_name(i)
				prev[i] = pp
		out[seq_name] = worst
		if worst > 0.17:
			print("TEST info pop in '%s': %.3f m/frame at bone %s" % [seq_name, worst, worst_bone])
		out[seq_name + "_started"] = true
	r.set_locomotion(0.0)
	track.call("idle", 60)
	out.erase("idle_started")
	# speed ramps
	for sp in [0.5, 1.4, 3.0, 5.0, 7.5, 3.0, 1.4, 0.0]:
		r.set_locomotion(sp, Vector3(0, 0, -1), sp > 6.0)
		track.call("speed", 50)
	# direction changes while walking
	r.set_locomotion(1.4, Vector3(1, 0, 0))
	track.call("strafe", 40)
	r.set_locomotion(1.4, Vector3(0, 0, 1))
	track.call("backwards", 40)
	r.set_locomotion(0.0)
	track.call("stop", 40)
	# crouch / aim / weapon changes
	r.set_stance(&"crouch")
	track.call("crouch", 40)
	r.set_stance(&"stand")
	track.call("uncrouch", 40)
	r.set_weapon_pose(&"rifle")
	track.call("weapon_rifle", 40)
	r.set_aim(true, 0.2, 0.1)
	track.call("aim_on", 40)
	r.set_aim(true, -0.4, -0.2)
	track.call("aim_move", 40)
	r.set_weapon_pose(&"pistol")
	track.call("weapon_pistol", 40)
	r.set_aim(false)
	track.call("aim_off", 40)
	r.set_weapon_pose(&"none")
	track.call("holster", 40)
	# stance switches
	for st in [&"cover_low", &"cover_high", &"stand", &"sit_car", &"stand", &"swim_surface", &"swim_under", &"stand", &"ladder", &"stand", &"parachute", &"stand"]:
		r.set_stance(st)
		track.call("stance_" + String(st), 70)
	# one-shot actions
	for a in [&"punch", &"kick", &"reload", &"throw", &"hit_react", &"jump"]:
		r.play_action(a)
		track.call("action_" + String(a), 60)
	r.set_grounded(true, -4.0)
	track.call("landing", 50)
	r.play_action(&"hands_up")
	track.call("hands_up", 40)
	r.play_action(&"hands_down")
	track.call("hands_down", 40)
	var res := {}
	for k in out:
		if not String(k).ends_with("_started"):
			res[k] = out[k]
	return res
