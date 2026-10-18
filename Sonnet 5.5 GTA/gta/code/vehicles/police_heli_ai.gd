class_name PoliceHeliAI
extends Node
## Police helicopter brain (Air&Sea agent, ARCHITECTURE 14.4). The PoliceManager director spawns it with `PoliceHeliAI.spawn(pos)` and steers it
## through `set_mode(&"patrol"|&"pursue"|&"search")`, `set_target(node)` and `set_order(order)` (the unit-order dictionary of 14.2).
##   * patrol  - orbit the city at 80-120 m (searchlight on at night, sweeping the streets ahead);
##   * pursue  - follow the target at 55-60 m altitude, >= 56 m away (overwatch ring, slow orbit when he stands still), smooth lag, nose to the suspect, searchlight locked on him; sighting
##               reports go to WantedSystem.report_sighting while the beam (or plain LOS in daylight) covers the player;
##   * search  - slow circles over the search area, the beam sweeping the ground, locks on when the player is found;
##   * hold / leave - hover on the spot / fly away (self-despawn when far).
## Wanted level >= 4: the door gunner fires short, inaccurate bursts (Ballistics + chunky tracers, Events.gunshot, rate limited).
## The AI is a child Node of the HeliVehicle (`heli.ai`, meta `police_ai`) and pilots it through AirAutopilot.

signal mode_changed(mode: StringName)
signal player_sighted(pos: Vector3)

const MAX_ACTIVE := 2
const MODES: Array[StringName] = [&"patrol", &"pursue", &"search", &"hold", &"leave"]

static var active: Array = []              # live PoliceHeliAI nodes (spawn cap, queries)

var heli: HeliVehicle = null
var autopilot: AirAutopilot = null
var searchlight: AirSearchlight = null
var mode: StringName = &"patrol"
var target: Node3D = null
var search_center := Vector3.ZERO
var search_radius := 80.0
var aggression := 0.8
var lethal := true
var level := 0                              # wanted level snapshot (Game.wanted_level)
var level_override := -1                    # tests / scripted scenes: >= 0 replaces the wanted level
var gunner_enabled := true
var gunner_min_level := 4
var player_lit := false                     # the beam / LOS currently covers the player
var player_seen_t := -99.0
var stats := {"bursts": 0, "rounds": 0, "sightings": 0, "mode_changes": 0}

# tunables
var patrol_center := Vector3(0, 0, 25)
var patrol_radius := 150.0
var patrol_alt := 105.0
var patrol_speed := 24.0
var pursue_alt := 58.0                       # above the target
var pursue_trail := 58.0                     # trails the moving target by this much
var pursue_min_radius := 56.0                # stand-off ring around the target (overwatch orbit): never hovers straight above the camera
var pursue_speed := 42.0
var search_alt := 62.0
var gun_range := 150.0
var gun_damage := 6.0
var gun_inaccuracy_deg := 3.6
var gun_burst_gap := Vector2(2.6, 4.8)

var _applied: StringName = &""
var _applied_target: Node3D = null
var _t := 0.0
var _think_t := 0.0
var _sight_t := 0.0
var _sweep_t := 0.0
var _burst_left := 0
var _burst_t := 0.0
var _gun_cd := 2.5
var _leave_far := Vector3.ZERO
var _los_q: PhysicsRayQueryParameters3D = null
var _gun_snd_t := 0.0


# =====================================================================================================
# Factory
# =====================================================================================================
## Spawns a police helicopter in flight at `pos` (y = altitude; clamped to >= 60 m above the ground). Returns the VehicleBase or null
## (cap reached / helicopter not available). The returned vehicle carries the AI: `PoliceHeliAI.of(vehicle)`.
static func spawn(pos: Vector3, opts: Dictionary = {}) -> VehicleBase:
	_prune()
	if active.size() >= MAX_ACTIVE and not opts.get("force", false):
		return null
	if not VehicleDefs.is_implemented(&"heli_police"):
		return null
	var ground := WorldLayout.terrain_height(pos.x, pos.z) if WorldLayout.built else 0.0
	var p := Vector3(pos.x, maxf(pos.y, ground + 60.0), pos.z)
	var look := Vector3(0, p.y, 0) - p
	if look.length() < 5.0:
		look = Vector3(0, 0, -1)
	var yaw := Util.dir_to_yaw(Vector3(look.x, 0.0, look.z))
	var v := VehicleFactory.spawn(&"heli_police", Transform3D(Basis(Vector3.UP, yaw), p), {
		"faction": GC.F_POLICE, "ai": true, "keep_engine_on": true, "abandoned": false, "snap_ground": false,
		"engine_on": true, "name": "Police Helicopter", "headlights": true})
	if v == null or not (v is HeliVehicle):
		return v
	var h := v as HeliVehicle
	var ai := PoliceHeliAI.new()
	ai.name = "PoliceHeliAI"
	ai.heli = h
	h.add_child(ai)
	h.ai = ai
	h.set_meta(&"police_ai", ai)
	h.set_meta(&"has_siren", true)
	if not h.is_in_group(GC.G_POLICE):
		h.add_to_group(GC.G_POLICE)
	h.siren_on = true
	h.headlights_on = true
	h.start_airborne(float(opts.get("speed", 16.0)))
	ai.setup()
	var m: StringName = opts.get("mode", &"patrol")
	ai.set_mode(m)
	var tgt = opts.get("target", null)
	if tgt is Node3D:
		ai.set_target(tgt)
	return h


static func of(v: Node) -> PoliceHeliAI:
	if v == null or not is_instance_valid(v):
		return null
	if v.has_meta(&"police_ai"):
		var a = v.get_meta(&"police_ai")
		if a is PoliceHeliAI and is_instance_valid(a):
			return a
	return v.get_node_or_null("PoliceHeliAI") as PoliceHeliAI


static func _prune() -> void:
	for i in range(active.size() - 1, -1, -1):
		if not is_instance_valid(active[i]):
			active.remove_at(i)


static func active_count() -> int:
	_prune()
	return active.size()


# =====================================================================================================
# Lifecycle
# =====================================================================================================
func setup() -> void:
	if heli == null:
		heli = get_parent() as HeliVehicle
	if heli == null:
		return
	autopilot = AirAutopilot.attach(heli)
	autopilot.min_agl = 28.0
	autopilot.follow_lag = 1.1
	searchlight = heli.searchlight
	if searchlight != null:
		searchlight.external_control = true
		searchlight.shadows = true
		searchlight.energy = 18.0
		searchlight.slew_deg = 52.0
	_los_q = PhysicsRayQueryParameters3D.new()
	_los_q.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP
	_los_q.exclude = [heli.get_rid()]
	var idx := active.size()
	patrol_radius = 150.0 + 25.0 * float(idx % 2)
	patrol_alt = 105.0 - 12.0 * float(idx % 2)
	if not active.has(self):
		active.append(self)
	process_priority = -6


func _ready() -> void:
	if heli == null:
		setup()
	set_physics_process(true)


func _exit_tree() -> void:
	active.erase(self)
	if searchlight != null and is_instance_valid(searchlight):
		searchlight.set_enabled(false)
		searchlight.external_control = false
	if autopilot != null and is_instance_valid(autopilot):
		autopilot.queue_free()
	if heli != null and is_instance_valid(heli):
		if heli.has_meta(&"police_ai") and heli.get_meta(&"police_ai") == self:
			heli.remove_meta(&"police_ai")
		if heli.ai == self:
			heli.ai = null


# =====================================================================================================
# Orders (PoliceManager / WantedSystem side)
# =====================================================================================================
func set_mode(m: StringName) -> void:
	if not MODES.has(m):
		m = &"patrol"
	if m == mode and _applied == m:
		return
	mode = m
	_applied = &""                      # re-apply at the next think
	_think_t = 0.0
	stats["mode_changes"] = int(stats["mode_changes"]) + 1
	mode_changed.emit(m)


func set_target(n: Node) -> void:
	var t := n as Node3D
	if t == target:
		return
	target = t
	_applied = &""


func get_target() -> Node3D:
	if target != null and is_instance_valid(target):
		return target
	var p = Game.player
	return p as Node3D if (p != null and is_instance_valid(p)) else null


## PoliceDirector order dictionary: {"mode": patrol|pursue|search|hold|leave, "target": Node, "pos": Vector3, "radius": float,
## "aggression": 0..1, "lethal": bool}
func set_order(order: Dictionary) -> void:
	var m: StringName = order.get("mode", mode)
	aggression = clampf(float(order.get("aggression", aggression)), 0.0, 1.0)
	lethal = bool(order.get("lethal", lethal))
	var tgt = order.get("target", null)
	if tgt is Node3D:
		set_target(tgt)
	var pos = order.get("pos", null)
	if pos is Vector3 and (pos as Vector3) != Vector3.ZERO:
		var np := pos as Vector3
		if np.distance_to(search_center) > 12.0:
			search_center = np
			if mode == &"search":
				_applied = &""
	var rad := float(order.get("radius", 0.0))
	if rad > 1.0 and m == &"search":
		search_radius = rad
	set_mode(m)


func despawn() -> void:
	if heli != null and is_instance_valid(heli):
		VehicleFactory.despawn(heli)


# =====================================================================================================
# Per-frame
# =====================================================================================================
func _physics_process(dt: float) -> void:
	if heli == null or not is_instance_valid(heli):
		queue_free()
		return
	_t += dt
	if heli.is_destroyed:
		if searchlight != null:
			searchlight.set_enabled(false)
		if autopilot != null:
			autopilot.mode = AirAutopilot.Mode.OFF
		return
	# a human pilot took over (the player stole the helicopter): the brain retires for good, the helicopter becomes an ordinary stolen aircraft
	var drv = heli.driver
	if drv != null and is_instance_valid(drv) and drv.has_method("is_player") and drv.is_player():
		heli.keep_engine_on = false
		heli.set_ai_controlled(false)
		if autopilot != null and is_instance_valid(autopilot):
			autopilot.mode = AirAutopilot.Mode.OFF
		queue_free()
		return
	if autopilot != null:
		autopilot.enabled = not heli.engine_failed
	if searchlight != null:
		searchlight.external_control = true
	level = level_override if level_override >= 0 else Game.wanted_level
	_think_t -= dt
	if _think_t <= 0.0:
		_think_t = 0.125
		_think()
	_light(dt)
	_sight(dt)
	_gunner(dt)


func _think() -> void:
	if autopilot == null:
		return
	var tgt := get_target()
	var changed := _applied != mode or _applied_target != tgt
	match mode:
		&"patrol":
			if changed:
				autopilot.look_at_point = Vector3.INF
				autopilot.heading_target = NAN
				autopilot.orbit(patrol_center, patrol_radius, patrol_alt, patrol_speed, active.find(self) % 2 == 0)
		&"pursue":
			if tgt == null:
				if changed:
					autopilot.hover()
			else:
				if changed:
					autopilot.heading_target = NAN
					autopilot.follow(tgt, Vector3(0, pursue_alt, 0), pursue_trail, pursue_speed)
					autopilot.follow_lag = 1.1
					autopilot.follow_min_radius = pursue_min_radius
					autopilot.orbit_cw = active.find(self) % 2 == 0
				autopilot.look_at_point = tgt.global_position
		&"search":
			if changed:
				var c := search_center
				if c == Vector3.ZERO:
					var w = Game.sys(&"wanted")
					if w != null and w.has_method("get_last_known_position"):
						c = w.get_last_known_position()
					elif tgt != null:
						c = tgt.global_position
				search_center = c
				var wr = Game.sys(&"wanted")
				if search_radius <= 1.0 and wr != null and wr.has_method("get_search_radius"):
					search_radius = float(wr.get_search_radius())
				var r := clampf(search_radius * 0.5, pursue_min_radius, 110.0)
				autopilot.look_at_point = Vector3.INF
				autopilot.orbit(Vector3(c.x, 0.0, c.z), r, WorldLayout.terrain_height(c.x, c.z) + search_alt, 13.0, active.find(self) % 2 == 1)
		&"hold":
			if changed:
				autopilot.hover()
		&"leave":
			if changed:
				var away := (heli.global_position - Vector3(0, heli.global_position.y, 0))
				away.y = 0.0
				away = away.normalized() if away.length() > 1.0 else Vector3(1, 0, 0)
				_leave_far = Vector3(away.x * 900.0, 130.0, away.z * 900.0)
				autopilot.look_at_point = Vector3.INF
				autopilot.goto(_leave_far, 40.0, 130.0)
			var dd := Vector2(heli.global_position.x, heli.global_position.z).length()
			var p = Game.player
			var dp := 0.0
			if p != null and is_instance_valid(p):
				dp = heli.global_position.distance_to((p as Node3D).global_position)
			if dd > 520.0 or dp > 500.0:
				despawn()
				return
	_applied = mode
	_applied_target = tgt


# =====================================================================================================
# Searchlight
# =====================================================================================================
func _light(dt: float) -> void:
	if searchlight == null:
		return
	var night := Game.is_night() or Game.daylight() < 0.35
	var tgt := get_target()
	var on := false
	match mode:
		&"pursue":
			on = true
			if tgt != null:
				var tp := tgt.global_position + Vector3(0, 0.9, 0)
				var tv = tgt.get("linear_velocity")
				if tv == null:
					tv = tgt.get("velocity")
				if tv is Vector3:
					tp += (tv as Vector3) * 0.35
				searchlight.aim_at(tp)
		&"search":
			on = true
			_sweep_t += dt
			var c := search_center
			var r := maxf(search_radius * 0.8, 24.0)
			var tgt_pos := tgt.global_position if tgt != null else Vector3.INF
			if tgt != null and player_lit and heli.global_position.distance_to(tgt_pos) < 160.0:
				searchlight.aim_at(tgt_pos + Vector3(0, 0.9, 0))        # found him: stay on him
			else:
				var a := _sweep_t * 0.42
				var sp := c + Vector3(cos(a) * r, 0.0, sin(a * 1.3) * r)
				sp.y = WorldLayout.terrain_height(sp.x, sp.z)
				searchlight.aim_at(sp)
		&"patrol":
			on = night
			if on:
				_sweep_t += dt
				var fwd := -heli.global_transform.basis.z
				var side := heli.global_transform.basis.x
				var gp := heli.global_position + fwd * 60.0 + side * sin(_sweep_t * 0.6) * 45.0
				gp.y = maxf(WorldLayout.terrain_height(gp.x, gp.z), 0.0)
				searchlight.aim_at(gp)
		_:
			on = false
	searchlight.set_enabled(on)
	searchlight.update(dt)


# =====================================================================================================
# Sightings (beam / LOS -> WantedSystem)
# =====================================================================================================
func _sight(dt: float) -> void:
	_sight_t -= dt
	if _sight_t > 0.0:
		return
	_sight_t = 0.4
	var p = Game.player
	if p == null or not is_instance_valid(p) or not (p is Node3D):
		player_lit = false
		return
	var pp := (p as Node3D).global_position + Vector3(0, 1.0, 0)
	var covered := false
	if searchlight != null and searchlight.enabled and searchlight.covers(pp, 2.0):
		covered = true
	elif Game.daylight() > 0.45 and mode != &"patrol":
		# daylight: plain line of sight within 140 m counts (the beam is not needed to see)
		covered = heli.global_position.distance_to(pp) < 140.0
	elif mode == &"pursue" and heli.global_position.distance_to(pp) < 60.0:
		covered = true
	if covered and not _blocked(pp):
		player_lit = true
		player_seen_t = _t
		stats["sightings"] = int(stats["sightings"]) + 1
		var w = Game.sys(&"wanted")
		if w != null and w.has_method("report_sighting"):
			w.report_sighting((p as Node3D).global_position, heli)
		player_sighted.emit((p as Node3D).global_position)
	else:
		if _t - player_seen_t > 1.2:
			player_lit = false


func _blocked(point: Vector3) -> bool:
	if _los_q == null or heli == null:
		return false
	var from := heli.global_position + Vector3(0, -0.4, 0)
	_los_q.from = from
	_los_q.to = point
	_los_q.exclude = [heli.get_rid()]
	var p = Game.player
	if p is CollisionObject3D:
		_los_q.exclude = [heli.get_rid(), (p as CollisionObject3D).get_rid()]
	var hit := heli.get_world_3d().direct_space_state.intersect_ray(_los_q)
	if hit.is_empty():
		return false
	var col: Object = hit.collider
	# the player's own vehicle does not block the view of the player
	if p != null and is_instance_valid(p):
		var pv = p.get("current_vehicle")
		if pv != null and col == pv:
			return false
	return true


# =====================================================================================================
# Door gunner
# =====================================================================================================
func _gunner(dt: float) -> void:
	if not gunner_enabled or mode != &"pursue" or level < gunner_min_level or not lethal:
		_burst_left = 0
		return
	var p = Game.player
	if p == null or not is_instance_valid(p) or not (p is Node3D):
		return
	if p.get("is_dead") == true:
		return
	var muzzle := heli.to_global(Vector3(1.15, 0.6, -0.3))
	var aim := (p as Node3D).global_position + Vector3(0, 1.0, 0)
	var dist := muzzle.distance_to(aim)
	if dist > gun_range or dist < 10.0:
		_burst_left = 0
		return
	if _burst_left > 0:
		_burst_t -= dt
		if _burst_t <= 0.0:
			_burst_t = 0.1
			_burst_left -= 1
			_fire_round(muzzle, aim, p as Node3D)
		return
	_gun_cd -= dt
	if _gun_cd > 0.0 or not player_lit or _t - player_seen_t > 1.0:
		return
	# short burst; the gap shrinks with the wanted level and the aggression of the order
	_burst_left = randi_range(3, 5)
	_burst_t = 0.0
	stats["bursts"] = int(stats["bursts"]) + 1
	var gap := randf_range(gun_burst_gap.x, gun_burst_gap.y) * lerpf(1.25, 0.8, aggression)
	if level >= 5:
		gap *= 0.7
	_gun_cd = gap


func _fire_round(muzzle: Vector3, aim_point: Vector3, who: Node3D) -> void:
	var vel := Vector3.ZERO
	var lv = who.get("linear_velocity")
	if lv == null:
		lv = who.get("velocity")
	if lv is Vector3:
		vel = lv
	# deliberately poor aim: lead by only half the flight time, then a wide random cone (worse the faster the target moves)
	var flight := muzzle.distance_to(aim_point) / 420.0
	var aim := aim_point + vel * flight * 0.5
	var d := (aim - muzzle).normalized()
	var spread := deg_to_rad(gun_inaccuracy_deg + clampf(vel.length() * 0.18, 0.0, 3.5))
	var ang := randf() * TAU
	var tilt := spread * sqrt(randf())
	var perp1 := d.cross(Vector3.UP)
	if perp1.length_squared() < 0.01:
		perp1 = Vector3.RIGHT
	perp1 = perp1.normalized()
	var perp2 := d.cross(perp1).normalized()
	d = (d + (perp1 * cos(ang) + perp2 * sin(ang)) * tan(tilt)).normalized()
	var space := heli.get_world_3d().direct_space_state
	var res := Ballistics.shoot(space, muzzle, d, {
		"shooter": heli, "weapon": &"heli_gun", "damage": gun_damage, "range": gun_range + 30.0, "exclude": [heli.get_rid()],
		"impulse": 1.2, "type": GC.DMG_BULLET, "falloff_start": 70.0, "falloff_min": 0.55})
	stats["rounds"] = int(stats["rounds"]) + 1
	var end: Vector3 = res.get("pos", muzzle + d * gun_range)
	var fx = CombatSystem.get_fx()
	if fx != null and fx.has_method("tracer"):
		fx.tracer(muzzle, end, Color(1.0, 0.72, 0.28, 1.0), 0.075, 240.0, 7.5)
	Events.gunshot.emit(muzzle, 140.0, heli)
	_gun_snd_t -= 0.1
	if _gun_snd_t <= 0.0:
		_gun_snd_t = 0.18
		if Sfx.has_sound(&"shot_smg"):
			Sfx.play_3d(&"shot_smg", muzzle, 2.0, 0.78, 230.0)


# =====================================================================================================
# Debug / tests
# =====================================================================================================
func get_status() -> Dictionary:
	return {
		"mode": mode, "level": level, "lit": player_lit, "light_on": searchlight != null and searchlight.enabled,
		"target": get_target(), "stats": stats.duplicate(),
		"altitude": heli.global_position.y if heli != null else 0.0,
		"speed": heli.get_speed() if heli != null else 0.0,
	}
