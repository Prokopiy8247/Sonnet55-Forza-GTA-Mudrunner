class_name AnimalAnim
extends RefCounted
## Procedural limb animation for the skeleton-free Blender animals (rotating the separate part meshes around their pivot origins, see
## docs/api/blender_animals.md). Leg phase speed follows omega = TAU * v / (4 * L * sin(A)) so feet do not slide. Only near animals are posed.

const S_DEAD := 8


static func update(a: Animal, dt: float) -> void:
	a.anim_t += dt
	if a.is_dead:
		_dead(a, dt)
		return
	match a.kind:
		&"land":
			_land(a, dt)
		&"bird":
			_bird(a, dt)
		&"swim":
			_swim(a, dt)


static func _amp_for(d: Dictionary, v: float) -> float:
	var walk := float(d["walk"])
	var trot := float(d["trot"])
	var run := float(d["run"])
	var aw := float(d["amp_walk"])
	var at := float(d["amp_trot"])
	var ar := float(d["amp_run"])
	if v <= walk:
		return lerpf(aw * 0.35, aw, clampf(v / maxf(walk, 0.01), 0.0, 1.0))
	if v <= trot:
		return lerpf(aw, at, (v - walk) / maxf(trot - walk, 0.01))
	return lerpf(at, ar, clampf((v - trot) / maxf(run - trot, 0.01), 0.0, 1.0))


static func _rot_x(n: Node3D, ang: float) -> void:
	if n != null:
		n.rotation = Vector3(ang, 0.0, 0.0)


# ====================================================================================================================
# land animals
# ====================================================================================================================
static func _land(a: Animal, dt: float) -> void:
	var d := a.def
	var parts := a.parts
	var scl := a.model_scale
	var big_hop: bool = d.get("hop", false)
	var spd := a.speed
	var moving := spd > 0.1
	var L := maxf(float(d["hip"]) * scl, 0.1)
	var target_amp := _amp_for(d, spd) if moving else 0.0
	a.gait_amp = Util.damp(a.gait_amp, target_amp, 12.0, dt)
	var amp := a.gait_amp
	if moving:
		var s := sin(clampf(maxf(amp, 0.12), 0.12, 1.2))
		var omega := TAU * spd / (4.0 * L * s)
		if big_hop:
			omega = clampf(TAU / 0.34 * clampf(spd / 6.0, 0.6, 1.4), 12.0, 26.0)
		a.gait_phase = fposmod(a.gait_phase + minf(omega, 46.0) * dt, TAU * 8.0)
	var ph := a.gait_phase
	var run_gait := spd > float(d["run"]) * 0.82 and L > 0.4
	var fl := parts.get("Leg_FL") as Node3D
	var fr := parts.get("Leg_FR") as Node3D
	var bl := parts.get("Leg_BL") as Node3D
	var br := parts.get("Leg_BR") as Node3D
	if big_hop:
		var sf := sin(ph) * amp
		var sh := sin(ph + 0.9) * amp
		_rot_x(fl, sf)
		_rot_x(fr, sf)
		_rot_x(bl, sh)
		_rot_x(br, sh)
		a.bob = maxf(sin(ph + 0.45), 0.0) * 0.16 * clampf(spd / 5.0, 0.0, 1.0)
		a.pitch_visual = cos(ph + 0.45) * 0.17 * clampf(spd / 5.0, 0.0, 1.0)
	else:
		var p_fl := ph
		var p_fr := ph + PI
		var p_bl := ph + PI
		var p_br := ph
		if run_gait:
			# bound / gallop: front pair together, hind pair together, offset
			p_fr = ph
			p_bl = ph + PI * 0.75
			p_br = ph + PI * 0.75
		_rot_x(fl, sin(p_fl) * amp)
		_rot_x(fr, sin(p_fr) * amp)
		_rot_x(bl, sin(p_bl) * amp)
		_rot_x(br, sin(p_br) * amp)
		var bob_amp := 0.012 * L * clampf(spd / maxf(float(d["walk"]), 0.1), 0.0, 1.6)
		a.bob = absf(sin(ph)) * bob_amp * (3.0 if run_gait else 1.0)
		a.pitch_visual = (sin(ph * 2.0) * 0.045 * clampf(spd / 6.0, 0.0, 1.0)) if run_gait else 0.0
	# ---- head / neck ----------------------------------------------------------------------------------------------
	var st := a.state
	var neck := parts.get("Neck") as Node3D
	var head := parts.get("Head") as Node3D
	var head_goal := 0.0
	var neck_goal := 0.0
	var yaw_goal := 0.0
	var grazing := st == WildlifeBrain.S_GRAZE or st == WildlifeBrain.S_EAT
	if grazing:
		if neck != null:
			neck_goal = -0.62
			head_goal = -0.22
		else:
			head_goal = -0.62 if L > 0.8 else -0.5
		# nibble
		head_goal += sin(a.anim_t * 5.0 + a.rng_seed) * 0.05
	elif st == WildlifeBrain.S_ALERT:
		neck_goal = 0.12 if neck != null else 0.0
		head_goal = 0.1 if neck != null else 0.28
		if a.threat_pos != Vector3.INF:
			var to := a.threat_pos - a.global_position
			yaw_goal = clampf(Util.angle_diff(a.yaw, Util.dir_to_yaw(to)), -0.9, 0.9)
	elif st == WildlifeBrain.S_FLEE or st == WildlifeBrain.S_CHASE or st == WildlifeBrain.S_FIGHT:
		head_goal = 0.1 if neck != null else -0.05
		if st == WildlifeBrain.S_CHASE or st == WildlifeBrain.S_FIGHT:
			head_goal = -0.25
	elif st == WildlifeBrain.S_IDLE:
		yaw_goal = sin(a.anim_t * 0.45 + a.rng_seed) * 0.6 * (1.0 if sin(a.anim_t * 0.21 + a.rng_seed * 2.0) > 0.0 else 0.0)
		head_goal = 0.04
	a.head_pitch = Util.damp(a.head_pitch, head_goal, 7.0, dt)
	a.neck_pitch = Util.damp(a.neck_pitch, neck_goal, 6.0, dt)
	a.head_yaw = Util.damp(a.head_yaw, yaw_goal, 6.0, dt)
	if neck != null:
		neck.rotation = Vector3(a.neck_pitch, 0.0, 0.0)
	if head != null:
		head.rotation = Vector3(a.head_pitch, a.head_yaw, 0.0)
	# ---- jaw (barking / biting) ----------------------------------------------------------------------------------------
	var jaw := parts.get("Jaw") as Node3D
	if jaw != null:
		a.jaw_open = maxf(a.jaw_open - dt * 3.0, 0.0)
		jaw.rotation = Vector3(-0.38 * clampf(a.jaw_open, 0.0, 1.0) * (0.6 + 0.4 * sin(a.anim_t * 22.0)), 0.0, 0.0)
	# ---- tail ---------------------------------------------------------------------------------------------------------------
	var tail := parts.get("Tail") as Node3D
	if tail != null:
		if bool(d.get("tail_wag", false)) and (st == WildlifeBrain.S_IDLE or st == WildlifeBrain.S_WALK or st == WildlifeBrain.S_ALERT):
			tail.rotation = Vector3(-0.25, sin(a.anim_t * 11.0) * 0.5, 0.0)
		elif (a.sp == &"deer" or a.sp == &"deer_buck") and (st == WildlifeBrain.S_FLEE or st == WildlifeBrain.S_ALERT):
			tail.rotation = Vector3(-0.95, 0.0, 0.0)           # white flag up
		elif a.sp == &"cat":
			tail.rotation = Vector3(-0.35 + sin(a.anim_t * 1.6 + a.rng_seed) * 0.15, sin(a.anim_t * 2.1 + a.rng_seed) * 0.25, 0.0)
		elif a.sp == &"cow" or a.sp == &"horse":
			tail.rotation = Vector3(0.0, sin(a.anim_t * 1.7 + a.rng_seed) * 0.28, 0.0)
		else:
			tail.rotation = Vector3(-0.1 if st != WildlifeBrain.S_FLEE else -0.3, sin(a.anim_t * 2.4 + a.rng_seed) * 0.1, 0.0)
	# ---- ears: occasional flick ---------------------------------------------------------------------------------------------
	var el := parts.get("Ear_L") as Node3D
	var er := parts.get("Ear_R") as Node3D
	if el != null and er != null:
		var fl_t := sin(a.anim_t * 0.9 + a.rng_seed * 3.0)
		var f := maxf(fl_t - 0.93, 0.0) * 8.0
		var ef := f * 0.5 if st != WildlifeBrain.S_ALERT else 0.0
		el.rotation = Vector3(0.0, 0.0, -ef + (0.14 if st == WildlifeBrain.S_ALERT else 0.0))
		er.rotation = Vector3(0.0, 0.0, ef * 0.6 - (0.14 if st == WildlifeBrain.S_ALERT else 0.0))
	# ---- visual root: bob + slope pitch / roll ------------------------------------------------------------------------------------
	a.vroot.position = Vector3(0.0, a.bob, 0.0)
	a.vroot.rotation = Vector3(a.slope_pitch + a.pitch_visual, 0.0, a.slope_roll)


# ====================================================================================================================
# birds
# ====================================================================================================================
static func _bird(a: Animal, dt: float) -> void:
	var parts := a.parts
	var st := a.state
	var wr := parts.get("Wing_R") as Node3D
	var wl := parts.get("Wing_L") as Node3D
	var legl := parts.get("Leg_L") as Node3D
	var legr := parts.get("Leg_R") as Node3D
	var head := parts.get("Head") as Node3D
	var tail := parts.get("Tail") as Node3D
	var flying := st == WildlifeBrain.S_FLY or st == WildlifeBrain.S_TAKEOFF or st == WildlifeBrain.S_LAND
	if flying:
		var freq := 5.2 if a.sp == &"crow" else 3.4
		if st == WildlifeBrain.S_TAKEOFF:
			freq *= 1.45
		a.flap_phase = fposmod(a.flap_phase + dt * TAU * freq, TAU * 16.0)
		var sw := sin(a.flap_phase)
		var base := 0.12
		var ang := base + sw * a.flap_amp * (0.55 if sw < 0.0 else 0.85)
		if wr != null:
			wr.rotation = Vector3(0.0, 0.0, ang)
		if wl != null:
			wl.rotation = Vector3(0.0, 0.0, -ang)
		_rot_x(legl, -1.0)
		_rot_x(legr, -1.0)
		if tail != null:
			tail.rotation = Vector3(0.12 + 0.1 * sw * a.flap_amp, 0.0, 0.0)
		if head != null:
			head.rotation = Vector3(0.0, 0.0, 0.0)
		a.vroot.position = Vector3(0.0, sw * 0.03 * a.flap_amp, 0.0)
		a.vroot.rotation = Vector3(a.pitch_visual, 0.0, a.roll_visual)
		return
	# on the ground: tiny fast steps, pecking
	var spd := a.speed
	var moving := spd > 0.08
	var amp := 0.5 if moving else 0.0
	a.gait_amp = Util.damp(a.gait_amp, amp, 14.0, dt)
	if moving:
		a.gait_phase = fposmod(a.gait_phase + dt * (6.0 + spd * 7.0), TAU * 8.0)
	var s := sin(a.gait_phase) * a.gait_amp
	_rot_x(legl, s)
	_rot_x(legr, -s)
	var head_goal := 0.0
	if st == WildlifeBrain.S_PECK:
		var cyc := fposmod(a.anim_t * 1.5 + a.rng_seed, 3.0)
		head_goal = -0.9 if cyc < 0.35 else (-0.9 + 0.9 * clampf((cyc - 0.35) / 0.25, 0.0, 1.0) if cyc < 0.6 else 0.0)
		if moving:
			head_goal = sin(a.gait_phase) * 0.18
	elif st == WildlifeBrain.S_ALERT:
		head_goal = 0.25
	a.head_pitch = Util.damp(a.head_pitch, head_goal, 18.0, dt)
	var yaw_goal := 0.0
	if st == WildlifeBrain.S_PERCH or st == WildlifeBrain.S_PECK:
		yaw_goal = sin(a.anim_t * 0.7 + a.rng_seed) * 0.7 * (1.0 if sin(a.anim_t * 0.31 + a.rng_seed) > 0.2 else 0.0)
	a.head_yaw = Util.damp(a.head_yaw, yaw_goal, 9.0, dt)
	if head != null:
		head.rotation = Vector3(a.head_pitch, a.head_yaw, 0.0)
	a.vroot.position = Vector3(0.0, absf(sin(a.gait_phase)) * 0.01 * clampf(spd, 0.0, 1.0), 0.0)
	a.vroot.rotation = Vector3(a.slope_pitch, 0.0, a.slope_roll)


# ====================================================================================================================
# swimmers
# ====================================================================================================================
static func _swim(a: Animal, dt: float) -> void:
	var parts := a.parts
	var spd := a.speed
	match a.sp:
		&"shark":
			a.swim_phase = fposmod(a.swim_phase + dt * TAU * (0.55 + spd * 0.22), TAU * 16.0)
			var sw := sin(a.swim_phase)
			var tailp := parts.get("Fin_Tail") as Node3D
			if tailp != null:
				tailp.rotation = Vector3(0.0, sw * (0.2 + 0.05 * spd), 0.0)
			var jaw := parts.get("Jaw") as Node3D
			if jaw != null:
				a.jaw_open = maxf(a.jaw_open - dt * 2.2, 0.0)
				jaw.rotation = Vector3(0.12 - 0.42 * clampf(a.jaw_open, 0.0, 1.0), 0.0, 0.0)     # rest is already ~13 deg open
			for fn in ["Fin_L", "Fin_R"]:
				var f := parts.get(fn) as Node3D
				if f != null:
					f.rotation = Vector3(0.0, 0.0, (0.08 if fn == "Fin_R" else -0.08) * (1.0 + 0.5 * sin(a.swim_phase * 0.5)))
			a.vroot.rotation = Vector3(a.pitch_visual, sin(a.swim_phase - 0.7) * 0.05, a.roll_visual)
			a.vroot.position = Vector3.ZERO
		&"dolphin":
			a.swim_phase = fposmod(a.swim_phase + dt * TAU * (1.1 + spd * 0.28), TAU * 16.0)
			var sw2 := sin(a.swim_phase)
			var tail2 := parts.get("Fin_Tail") as Node3D
			if tail2 != null:
				tail2.rotation = Vector3(sw2 * 0.3, 0.0, 0.0)          # horizontal flukes beat up / down
			a.vroot.rotation = Vector3(a.pitch_visual + sw2 * 0.03, 0.0, a.roll_visual)
			a.vroot.position = Vector3.ZERO
		&"sea_turtle":
			a.swim_phase = fposmod(a.swim_phase + dt * TAU * (0.35 + spd * 0.5), TAU * 16.0)
			var sw3 := sin(a.swim_phase)
			var ff_r := parts.get("Flipper_FR") as Node3D
			var ff_l := parts.get("Flipper_FL") as Node3D
			var fb_r := parts.get("Flipper_BR") as Node3D
			var fb_l := parts.get("Flipper_BL") as Node3D
			var rowing := 0.2 + clampf(spd, 0.0, 1.2) * 0.4
			if ff_r != null:
				ff_r.rotation = Vector3(0.0, 0.0, sw3 * rowing)
			if ff_l != null:
				ff_l.rotation = Vector3(0.0, 0.0, -sw3 * rowing)
			if fb_r != null:
				fb_r.rotation = Vector3(0.0, 0.0, sw3 * rowing * 0.5)
			if fb_l != null:
				fb_l.rotation = Vector3(0.0, 0.0, -sw3 * rowing * 0.5)
			var th := parts.get("Head") as Node3D
			if th != null:
				th.rotation = Vector3(sin(a.anim_t * 0.8) * 0.1, 0.0, 0.0)
			a.vroot.rotation = Vector3(a.pitch_visual, 0.0, a.roll_visual + sw3 * 0.05)
			a.vroot.position = Vector3.ZERO


# ====================================================================================================================
# death: ragdoll-lite
# ====================================================================================================================
static func _dead(a: Animal, dt: float) -> void:
	var parts := a.parts
	var sign_side := 1.0 if int(a.rng_seed * 10.0) % 2 == 0 else -1.0
	if a.kind == &"swim":
		a.roll_visual = lerpf(a.roll_visual, PI * sign_side, 1.0 - exp(-3.0 * dt))
		a.vroot.rotation = Vector3(a.pitch_visual, 0.0, a.roll_visual)
		a.vroot.position = Vector3.ZERO
		return
	if not a.dead_pose_done:
		# stiff splayed limbs
		var rng := RandomNumberGenerator.new()
		rng.seed = int(a.rng_seed * 1000.0)
		for pn in ["Leg_FL", "Leg_FR", "Leg_BL", "Leg_BR", "Leg_L", "Leg_R"]:
			var n := parts.get(pn) as Node3D
			if n != null:
				n.rotation = Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.25, 0.25))
		var head := parts.get("Head") as Node3D
		if head != null:
			head.rotation = Vector3(rng.randf_range(-0.3, 0.2), rng.randf_range(-0.5, 0.5), 0.0)
		var neck := parts.get("Neck") as Node3D
		if neck != null:
			neck.rotation = Vector3(-0.2, 0.0, 0.0)
		for wn in ["Wing_L", "Wing_R"]:
			var w := parts.get(wn) as Node3D
			if w != null:
				w.rotation = Vector3(0.0, 0.0, (0.4 if wn == "Wing_R" else -0.4))
		a.dead_pose_done = true
	var c := maxf(float(a.def.get("hip", 0.3)) * a.model_scale * 0.9, 0.08)
	var hw := maxf(float(a.def.get("shape", [0.2])[0]) * a.model_scale * 0.7, 0.04)
	if a.airborne:
		a.roll_visual += dt * 7.0 * sign_side              # tumble while flung
	else:
		var target := (PI * 0.5 - 0.08) * sign_side
		a.roll_visual = lerpf(a.roll_visual, target, 1.0 - exp(-9.0 * dt))
	var th := a.roll_visual
	var k := clampf(absf(sin(th)), 0.0, 1.0)
	a.vroot.rotation = Vector3(a.slope_pitch * 0.5, 0.0, th)
	if a.airborne:
		a.vroot.position = Vector3.ZERO
	else:
		a.vroot.position = Vector3(c * sin(th), lerpf(c, hw, k) - c * cos(th), 0.0)
