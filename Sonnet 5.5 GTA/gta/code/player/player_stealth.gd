class_name PlayerStealth
extends Node
## Stealth layer of the Player (spec 10A): noise model, visibility score, silent takedown from behind.
##
## PUBLISHED on the Player every physics tick (read duck-typed by pedestrians, police and gang AI; see docs/api/player_advanced.md):
##   player.noise_radius       metres within which the player can currently be HEARD (feet, swimming, melee, gunshots incl. suppressor, vehicles)
##   player.visibility01       0..1 how conspicuous the player is at close range (light, posture, motion, cover, muzzle flash)
##   player.detection_range    metres at which a viewer WITH line of sight can notice the player (6 .. 75)
##   player.stealth_exposed    visibility01 >= EXPOSED_AT
##   player.get_visibility_from(viewer_pos) -> float   per-viewer score 0..1 (distance falloff, cover between, light, posture)
##   player.takedown_target    the unaware NPC that X would silently take down right now (or null)
##
## Takedown: X (melee) behind an unaware NPC. Knife = silent kill; fists / blunt / firearm = knock-out (hold X to flip lethal <-> knock-out).
## No Events.gunshot is emitted and the player's noise stays below 3 m during it.

const EXPOSED_AT := 0.55
const SIGHT_MIN := 6.0
const SIGHT_MAX := 75.0
const TAKEDOWN_RANGE := 2.6
const TAKEDOWN_COOLDOWN := 0.9
const TD_STRIKE_TIME := 0.38
const TD_DURATION := 1.05
const TD_ABORT_TIME := 1.5
const NOISE_FALL_RATE := 22.0               # m/s: the audible radius collapses quickly once the noise stops
const GUN_HOLD := 0.35
const GUN_DECAY := 1.8
const LAMP_RADIUS := 12.0

var player: Player = null
var noise := 0.0                            # smoothed noise radius
var foot_noise := 0.0
var gun_noise := 0.0
var spike_noise := 0.0
var visibility := 0.5
var light := 1.0
var detection_range := 30.0
var target: Node3D = null                   # takedown candidate (updated ~10 Hz while on foot)
var in_takedown := false

var _gun_t := 99.0
var _gun_peak := 0.0
var _spike_t := 99.0
var _flash_boost := 0.0
var _light_timer := 0.0
var _scan_timer := 0.0
var _lamps_boost := 0.0
var _cooldown := 0.0
var _td_t := 0.0
var _td_victim: Node3D = null
var _td_lethal := false
var _td_struck := false
var _td_weapon: StringName = &"fists"
var _heavy_flag := false


func setup(p: Player) -> void:
	player = p
	Events.gunshot.connect(_on_gunshot)
	if p.weapons != null and p.weapons.has_signal(&"melee_hit"):
		p.weapons.melee_hit.connect(func(_info: Dictionary) -> void: on_melee_hit())


# ==========================================================================================================
# Per-tick update (called by Player._post_tick)
# ==========================================================================================================
func tick(dt: float) -> void:
	if player == null:
		return
	_cooldown = maxf(_cooldown - dt, 0.0)
	_gun_t += dt
	_spike_t += dt
	_flash_boost = maxf(_flash_boost - dt / 1.2, 0.0)
	_light_timer -= dt
	if _light_timer <= 0.0:
		_light_timer = 0.3
		light = _compute_light()
	_update_noise(dt)
	_update_visibility()
	_scan_timer -= dt
	if _scan_timer <= 0.0:
		_scan_timer = 0.1
		target = find_takedown_target() if _can_scan() else null
	player.takedown_target = target


func _update_noise(dt: float) -> void:
	foot_noise = _foot_noise()
	# gunshots: the loudness is held for a moment, then dies away
	if _gun_t < GUN_HOLD:
		gun_noise = _gun_peak
	elif _gun_t < GUN_HOLD + GUN_DECAY:
		gun_noise = _gun_peak * (1.0 - (_gun_t - GUN_HOLD) / GUN_DECAY)
	else:
		gun_noise = 0.0
		_gun_peak = 0.0
	if _spike_t > 0.35:
		spike_noise = maxf(spike_noise - 40.0 * dt, 0.0)
	var target_noise := maxf(foot_noise, maxf(gun_noise, spike_noise))
	if in_takedown:
		target_noise = minf(target_noise, 2.5)
	if target_noise >= noise:
		noise = target_noise
	else:
		noise = maxf(target_noise, noise - maxf(NOISE_FALL_RATE, noise * 1.2) * dt)
	player.noise_radius = noise


func _foot_noise() -> float:
	var h := Vector2(player.velocity.x, player.velocity.z).length()
	var n := 0.0
	match player.move_mode:
		Player.Move.SWIM:
			if player.head_underwater:
				n = 1.5 if h > 1.0 else 0.0
			else:
				n = 6.0 if h > 1.0 else 1.5
		Player.Move.VEHICLE:
			n = _vehicle_noise()
		Player.Move.COVER:
			n = 2.2 if h > 0.5 else 0.0
		Player.Move.PARACHUTE:
			n = 5.0
		Player.Move.GROUND, Player.Move.AIR:
			if h >= 0.8:
				if player.sprinting:
					n = 13.0
				elif player.crouching:
					n = 2.0 * _stealth_noise_mult()
				elif h > Player.RUN_SPEED * 0.75:
					n = 8.0
				else:
					n = 5.0
				n *= _surface_mult()
			if player.move_mode == Player.Move.AIR and h < 0.8:
				n = 0.0
		Player.Move.LADDER, Player.Move.TRAVERSE:
			n = 3.5
		_:
			n = 0.0
	if Game.rain_intensity > 0.4:
		n *= 0.85                    # rain masks footsteps
	return n


func _vehicle_noise() -> float:
	var v = player.current_vehicle
	if v == null or not is_instance_valid(v):
		return 0.0
	var kmh := 0.0
	if v.has_method("get_speed_kmh"):
		kmh = float(v.get_speed_kmh())
	var engine_on = v.get("engine_on")
	var base := 10.0 if (engine_on == null or engine_on == true) else 2.0
	return base + minf(kmh / 5.0, 26.0)


func _stealth_noise_mult() -> float:
	var s = Game.sys(&"skills")
	if s != null and s.has_method("get_modifier"):
		return clampf(float(s.get_modifier(&"noise")), 0.4, 1.0)
	return 1.0 - 0.45 * player._skill01(&"stealth")


func _surface_mult() -> float:
	match player.surface_type:
		&"grass", &"sand", &"dirt":
			return 0.8
		&"wood", &"metal":
			return 1.2
		&"water":
			return 1.1
	return 1.0


# ---- gunshots / melee ---------------------------------------------------------------------------------------
func _on_gunshot(_pos: Vector3, loudness: float, source: Node) -> void:
	if source != player:
		return
	_gun_peak = maxf(_gun_peak * (1.0 - clampf((_gun_t - GUN_HOLD) / GUN_DECAY, 0.0, 1.0)), loudness)
	gun_noise = _gun_peak
	_gun_t = 0.0
	# the muzzle flash of an unsuppressed gun is visible; a suppressor hides most of it
	var supp := loudness < 22.0
	_flash_boost = maxf(_flash_boost, 0.12 if supp else 0.45)


## Called by Player.melee(): a swing is audible; a connected blow louder (set_melee_hit).
func on_melee_swing() -> void:
	spike_noise = maxf(spike_noise, 7.0)
	_spike_t = 0.0


func on_melee_hit() -> void:
	spike_noise = maxf(spike_noise, 18.0)
	_spike_t = 0.0


func on_landing(drop: float) -> void:
	var n := clampf(drop * 3.0, 0.0, 14.0)
	if n > spike_noise:
		spike_noise = n
		_spike_t = 0.0


# ==========================================================================================================
# Visibility
# ==========================================================================================================
func _compute_light() -> float:
	var gloom := 1.0 - Game.daylight()
	var env = Game.sys(&"environment")
	if env != null and env.has_method("get_gloom"):
		gloom = clampf(float(env.get_gloom()), 0.0, 1.0)
	var l := 1.0 - 0.8 * gloom
	var pp := player.global_position
	if pp.y < -100.0:
		return 0.75              # interiors / underground rooms are lit
	if gloom > 0.25:
		var boost := 0.0
		for lamp in get_tree().get_nodes_in_group(&"street_lamp"):
			var n3 := lamp as Node3D
			if n3 == null:
				continue
			var dx := n3.global_position.x - pp.x
			var dz := n3.global_position.z - pp.z
			var d2 := dx * dx + dz * dz
			if d2 > LAMP_RADIUS * LAMP_RADIUS:
				continue
			var k := 1.0 - sqrt(d2) / LAMP_RADIUS
			boost += k * k * 0.5
		l += minf(boost, 0.55) * gloom
		_lamps_boost = minf(boost, 0.55)
	else:
		_lamps_boost = 0.0
	if player._flash_on or (player.weapons != null and player.weapons.get("flashlight_on") == true):
		l += 0.35 * gloom                  # a torch makes you easy to see
	return clampf(l, 0.1, 1.0)


func _posture_factor() -> float:
	if player.is_swimming:
		return 0.3 if player.head_underwater else 0.85
	match player.move_mode:
		Player.Move.COVER:
			var c = player.cover
			var peeking: bool = c != null and absf(float(c.peek)) > 0.5
			return (0.6 if peeking else 0.45) if (c != null and not c.low) else (0.62 if peeking else 0.55)
		Player.Move.VEHICLE:
			return 0.9
		Player.Move.PARACHUTE:
			return 1.1
	var f := 1.0
	if player.crouching:
		f = 0.62
	elif player.sprinting:
		f = 1.2
	if player.aiming:
		f *= 1.1
	return f


func _update_visibility() -> void:
	var h := Vector2(player.velocity.x, player.velocity.z).length()
	var motion := lerpf(0.8, 1.0, clampf(h / 4.0, 0.0, 1.0))
	var v := light * _posture_factor() * motion + _flash_boost
	visibility = clampf(v, 0.04, 1.0)
	var wx := 1.0 - 0.35 * clampf(Game.fog_amount, 0.0, 1.0) - 0.15 * clampf(Game.rain_intensity, 0.0, 1.0)
	detection_range = lerpf(SIGHT_MIN, SIGHT_MAX, pow(visibility, 0.8)) * wx
	player.visibility01 = visibility
	player.detection_range = detection_range
	player.stealth_exposed = visibility >= EXPOSED_AT


## Per-viewer score: 0 beyond the detection range, falls off with distance, and is reduced when the viewer is on the wall side of cover.
func get_visibility_from(viewer_pos: Vector3) -> float:
	if player == null:
		return 1.0
	var d := Util.dist_xz(viewer_pos, player.global_position)
	if d >= detection_range:
		return 0.0
	var v := visibility * (1.0 - smoothstep(detection_range * 0.35, detection_range, d))
	var c = player.cover
	if player.move_mode == Player.Move.COVER and c != null and c.active:
		var to_viewer := Util.flat(viewer_pos - player.global_position).normalized()
		var open_side: float = to_viewer.dot(c.normal)
		if open_side < -0.1:
			v *= 0.2
		elif open_side < 0.35 and not c.low:
			v *= 0.6
	return clampf(v, 0.0, 1.0)


# ==========================================================================================================
# Takedown from behind
# ==========================================================================================================
func _can_scan() -> bool:
	if player.is_dead or in_takedown or player.input_locked:
		return false
	if player.move_mode != Player.Move.GROUND:
		return false
	if player.sprinting or player.is_swimming:
		return false
	if player.has_method("is_in_vehicle") and player.is_in_vehicle():
		return false
	return true


## True when `n` has not noticed the player (duck typed over pedestrians, police officers and gang members).
static func is_unaware(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n.get("is_dead") == true:
		return false
	if n.has_method("is_knocked_down") and n.is_knocked_down():
		return false
	if n.has_method("is_panicked") and n.is_panicked():
		return false
	if n.has_method("is_fleeing") and n.is_fleeing():
		return false
	var pn = n.get("panic")
	if pn != null and float(pn) > 0.25:
		return false
	var br = n.get("brain")
	if br != null and br is Object:
		if br.get("target_visible") == true:
			return false
		var st = br.get("state")
		if st != null:
			# CombatBrain.State: 0 IDLE, 1 SEARCH, 10 HOLD are calm enough; everything else is an active fight
			var si := int(st)
			if si != 0 and si != 1 and si != 10:
				return false
	if n.get("provoked") == true:
		return false
	return true


func _is_candidate(n: Node) -> bool:
	if not (n is CharacterBody3D) or n == player:
		return false
	var b := n as CharacterBody3D
	if not b.is_inside_tree() or not b.is_visible_in_tree():
		return false
	if b.has_method("is_active") and not b.is_active():
		return false
	if b.get("current_vehicle") != null:
		return false
	return is_unaware(b)


## Best unaware NPC that is close, in front of us and facing away.
func find_takedown_target() -> Node3D:
	var pp := player.global_position
	var fwd := -player.global_transform.basis.z
	var best: Node3D = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group(GC.G_NPC):
		if not _is_candidate(n):
			continue
		var b := n as Node3D
		var to := b.global_position - pp
		if absf(to.y) > 1.3:
			continue
		to.y = 0.0
		var d := to.length()
		if d > TAKEDOWN_RANGE or d < 0.05:
			continue
		var dir := to / d
		if fwd.dot(dir) < 0.3 and d > 1.0:
			continue
		# the victim must face away from us (we are behind its back)
		var vf := Util.flat(-b.global_transform.basis.z).normalized()
		if vf.dot(dir) < 0.12:
			continue
		if not Util.has_line_of_sight(player, pp + Vector3.UP * 1.0, b.global_position + Vector3.UP * 1.0, GC.M_LOS):
			continue
		var score := d - fwd.dot(dir) * 0.6
		if score < best_score:
			best_score = score
			best = b
	return best


## Starts the takedown on the current candidate. `heavy` (X held) flips the default (knife: kill / otherwise knock-out).
func try_takedown(heavy: bool = false) -> bool:
	if _cooldown > 0.0 or in_takedown or not _can_scan_basic():
		return false
	var t := target
	if t == null or not is_instance_valid(t):
		t = find_takedown_target()
	if t == null:
		return false
	_td_victim = t
	_td_weapon = player.weapons.current_id if player.weapons != null else &"fists"
	_td_lethal = (_td_weapon == &"knife")
	if heavy:
		_td_lethal = not _td_lethal
	_td_t = 0.0
	_td_struck = false
	in_takedown = true
	player.begin_takedown_motion()
	if player.weapons != null:
		player.weapons.set_trigger(false)
		player.weapons.set_aiming(false)
	var rig = player.rig
	if rig != null:
		rig.play_action(&"melee_swing" if _td_weapon in [&"knife", &"bat", &"crowbar"] else &"punch")
	return true


func _can_scan_basic() -> bool:
	return not player.is_dead and player.move_mode == Player.Move.GROUND and not player.is_swimming and not player.input_locked


func tick_takedown(dt: float) -> void:
	_td_t += dt
	var v := _td_victim
	if v == null or not is_instance_valid(v) or v.get("is_dead") == true:
		_end_takedown()
		return
	var vpos := v.global_position
	var vf := Util.flat(-v.global_transform.basis.z).normalized()
	var goal := vpos - vf * 0.85
	var to := goal - player.global_position
	to.y = 0.0
	var h := Vector3.ZERO
	if to.length() > 0.04:
		h = to.normalized() * minf(to.length() / maxf(dt, 0.001), 5.5)
	player.velocity.x = h.x
	player.velocity.z = h.z
	player.velocity.y = maxf(player.velocity.y - Player.GRAVITY * dt, -20.0)
	player.rotation.y = lerp_angle(player.rotation.y, Util.dir_to_yaw(vf), 1.0 - exp(-18.0 * dt))
	player.move_and_slide()
	player._fall_peak_y = player.global_position.y
	if not _td_struck and _td_t >= TD_STRIKE_TIME:
		if Util.dist_xz(player.global_position, vpos) < 1.5:
			_strike(v)
		elif _td_t > TD_ABORT_TIME:
			_end_takedown()
			return
	if _td_t >= TD_DURATION:
		_end_takedown()


func _strike(v: Node3D) -> void:
	_td_struck = true
	var vf := Util.flat(-v.global_transform.basis.z).normalized()
	var head := v.global_position + Vector3.UP * 1.6
	var info := {"source": player, "type": GC.DMG_MELEE, "zone": GC.ZONE_HEAD, "position": head, "direction": vf,
		"weapon": &"takedown", "impulse": 2.0, "silent": true, "stealth": true, "hit_side": &"back", "normal": -vf}
	Sfx.play_3d(&"hit_flesh", v.global_position + Vector3.UP, -12.0, randf_range(0.9, 1.0), 7.0)     # quiet: nothing like a swing/impact
	if _td_lethal:
		v.apply_damage(1000.0, info)
	else:
		info["knockout"] = true
		if v.has_method("apply_damage"):
			v.apply_damage(1.0, info)
		if v.get("is_dead") != true:
			if v.has_method("knock_down"):
				v.knock_down(vf * 2.0, 9.0)
			else:
				var vr = v.get("rig")
				if vr != null and vr.has_method("start_ragdoll"):
					vr.start_ragdoll(vf * 2.0, head)
	v.set_meta(&"takedown_by_player", true)
	player._skill_use(&"stealth", 2.0)
	player._skill_use(&"strength", 0.3)


func _end_takedown() -> void:
	in_takedown = false
	_td_victim = null
	_cooldown = TAKEDOWN_COOLDOWN
	target = null
	player.end_takedown_motion()
