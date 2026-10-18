class_name PoliceOfficer
extends CharacterBase
## Police officer on foot: patrol officer (pistol / SMG / shotgun), SWAT (rifle, vest + helmet, flashbangs-as-grenades, flanking)
## and rooftop sniper. Groups `police` + `npc`, faction GC.F_POLICE.
##
## The Police-A director talks to it only through set_order(order):
##   {"mode": &"patrol"|&"pursue"|&"search"|&"hold"|&"leave", "target": Node, "pos": Vector3, "radius": float, "aggression": 0..1, "lethal": bool}
##   (optional extras: "dir": Vector3 facing for hold, "arrest": bool (false = never call Player.arrest), "stance": &"crouch" for hold)
## Combat itself is the shared CombatBrain (cover, bursts, flanking, grenades ...); this class adds the police-specific behaviour:
## arrest approach + handcuff radius, "Stop!" shouts, sighting reports to WantedSystem, drawn-weapon logic, leaving / entering cars.

signal order_changed(order: Dictionary)
signal arrested(target: Node)

const KINDS := [&"patrol", &"swat", &"sniper"]
const SHOUTS: Array[String] = ["Police! Stop right there!", "Freeze! Hands where I can see them!", "Police! Don't move!", "Get on the ground!"]
const SHOUT_GAP := 6.5
const ARREST_RANGE := 2.5
const ARREST_TIME := 1.1
const STANDOFF_S := 6.0
const THINK_INTERVAL: Array[float] = [0.15, 0.3, 0.6]

static var player_hostile_until := 0.0       # seconds (Time.get_ticks_msec / 1000): the player attacked police recently
static var _last_shout := -100.0
static var _hooked := false
static var arrest_enabled := true            # false: only the director arrests

var kind: StringName = &"patrol"
var ai_accuracy := 0.4
var body_height := 1.8
var is_crouching := false
var order: Dictionary = {}
var mode: StringName = &"patrol"
var home_vehicle: VehicleBase = null
var home_seat := -1
var actor: CombatActor = null
var brain: CombatBrain = null
var mover: CombatMover = null
var arrest_progress := 0.0
var holstered := true
var weapon_drawn := false                 # read by WantedSystem (armed officers count for busting / alarm)
var primary: StringName = &"pistol"
var spawn_time := 0.0

var _order_t := 0.0
var _think_dt := 0.2
var _wander_t := 3.0
var _next_report := 0.0
var _leave_t := 0.0
var _search_next := 0.0
var _clock := 0.0
var _enter_goal_t := 0.0
var _last_idle_style := 0.0
var _stranded_t := 0.0
var _arrest_guard := false


func _ready() -> void:
	match kind:
		&"swat":
			max_health = 135.0
			max_armor = 100.0
			display_name = "SWAT Officer"
		&"sniper":
			max_health = 100.0
			display_name = "Police Sniper"
		_:
			max_health = 100.0
			display_name = "Police Officer"
	super._ready()
	faction = GC.F_POLICE
	add_to_group(GC.G_POLICE)
	add_to_group(GC.G_NPC)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id()) * 7919 + Time.get_ticks_usec()
	var appearance := CharacterVariants.make(&"tactical" if kind == &"swat" else &"police", rng)
	var loadout: Array = []
	var cfg := {"target_groups": [GC.G_HOSTILE] as Array[StringName]}
	match kind:
		&"swat":
			primary = &"rifle_assault" if rng.randf() < 0.65 else (&"carbine" if rng.randf() < 0.6 else &"shotgun_pump")
			loadout = [[primary, 240], [&"pistol", 60], [&"grenade", 2]]
			armor = 55.0
			ai_accuracy = 0.58
			cfg.merge({"accuracy": 0.58, "reaction_time": 0.38, "flank": true, "grenades": true, "cover_bias": 0.7, "use_cover": true,
				"alert_radius": 70.0, "sight_range": 85.0, "aggression": 0.8, "burst_shots": Vector2i(2, 4), "burst_time": Vector2(0.5, 1.1),
				"burst_pause": Vector2(0.45, 1.1)})
		&"sniper":
			primary = &"rifle_marksman" if rng.randf() < 0.5 else &"sniper"
			loadout = [[primary, 60], [&"pistol", 30]]
			ai_accuracy = 0.78
			cfg.merge({"accuracy": 0.78, "reaction_time": 0.9, "flank": false, "use_cover": false, "hold_position": true,
				"sight_range": 140.0, "alert_radius": 50.0, "burst_shots": Vector2i(1, 1), "burst_pause": Vector2(1.6, 3.0), "fov_deg": 90.0})
		_:
			var r := rng.randf()
			primary = &"pistol" if r < 0.62 else (&"smg" if r < 0.86 else &"shotgun_pump")
			loadout = [[primary, 150], [&"pistol", 60]] if primary != &"pistol" else [[&"pistol", 150]]
			ai_accuracy = 0.4
			cfg.merge({"accuracy": 0.4, "reaction_time": 0.55, "cover_bias": 0.5, "alert_radius": 45.0, "sight_range": 70.0,
				"retreat_hp": 0.18, "retreat_chance": 0.2})
	actor = CombatActor.new()
	actor.build(self, appearance, loadout, cfg)
	brain = actor.brain
	mover = actor.mover
	brain.combat_enabled = true               # targets: hostile gangs always, the player only while wanted (CharacterBase.is_hostile_to)
	brain.dodge_vehicles = true
	mover.run_speed = 5.2 if kind != &"swat" else 5.5
	mover.sprint_speed = 6.5 if kind != &"swat" else 6.8
	mover.walk_speed = 1.8
	holstered = true
	actor.weapons.equip(&"fists")
	spawn_time = Time.get_ticks_msec() / 1000.0
	brain.target_sighted.connect(_on_target_sighted)
	if kind == &"sniper":
		brain.hold_position = true
		brain.hold_stance = &"stand"
	_wander_t = randf_range(2.0, 7.0)
	_install_hooks()


static func _install_hooks() -> void:
	if _hooked:
		return
	_hooked = true
	Events.character_damaged.connect(_on_any_damaged)


## Remembers when the player last attacked police (drives the "may we shoot" decision at low wanted levels).
static func _on_any_damaged(character: Node, _amount: float, info: Dictionary) -> void:
	var src = info.get("source", null)
	if src == null or not is_instance_valid(src) or not is_instance_valid(character):
		return
	if src == Game.player and character.get("faction") == GC.F_POLICE:
		player_hostile_until = Time.get_ticks_msec() / 1000.0 + 25.0


func _exit_tree() -> void:
	if actor != null:
		actor.dispose()


# =====================================================================================================================
# Orders
# =====================================================================================================================
func set_order(o: Dictionary) -> void:
	var req_mode: StringName = o.get("mode", &"patrol")
	if has_meta(&"roadblock") and req_mode != &"leave" and req_mode != &"hold":
		return                    # roadblock officers keep their post until the roadblock is dismantled (or they are told to leave)
	order = o.duplicate()
	var new_mode: StringName = order.get("mode", &"patrol")
	var changed := new_mode != mode
	mode = new_mode
	var t = order.get("target", null)
	if t != null and is_instance_valid(t):
		brain.forced_target = t
	elif mode == &"pursue" and Game.player != null and is_instance_valid(Game.player):
		brain.forced_target = Game.player
	elif mode != &"pursue":
		brain.forced_target = null
	var aggr := clampf(float(order.get("aggression", 0.5)), 0.0, 1.0)
	brain.aggression = aggr
	var base_acc := 0.58 if kind == &"swat" else (0.78 if kind == &"sniper" else 0.4)
	brain.accuracy = base_acc * lerpf(0.82, 1.12, aggr)
	ai_accuracy = brain.accuracy
	brain.reaction_time = (0.38 if kind == &"swat" else 0.55) * lerpf(1.3, 0.8, aggr)
	if changed:
		arrest_progress = 0.0
		_leave_t = 0.0
		brain.hold_position = (mode == &"hold") or kind == &"sniper"
		if mode == &"hold":
			brain.hold_stance = order.get("stance", &"stand")
		brain.clear_target_memory_if_idle()
	# an officer driving / riding forwards the order to the car (director may only talk to officers)
	if is_in_vehicle() and current_vehicle != null and current_vehicle.has_meta(&"police_ai"):
		var ai = current_vehicle.get_meta(&"police_ai")
		if is_instance_valid(ai) and ai.has_method("set_order") and seat_index == 0:
			ai.set_order(order)
	_order_t = 0.0
	order_changed.emit(order)


func get_order() -> Dictionary:
	return order


func _lethal() -> bool:
	if order.has("lethal"):
		return bool(order["lethal"])
	return Game.wanted_level >= 2


func _shooting_authorised() -> bool:
	return _lethal() or Time.get_ticks_msec() / 1000.0 < player_hostile_until


# =====================================================================================================================
# Tick
# =====================================================================================================================
func _physics_process(dt: float) -> void:
	_clock += dt
	if is_dead:
		actor.physics(dt)
		return
	if actor.down:
		actor.physics(dt)
		return
	if is_in_vehicle():
		_tick_seated(dt)
		actor.physics(dt)
		return
	_order_t -= dt
	if _order_t <= 0.0:
		_think_dt = THINK_INTERVAL[clampi(actor.lod, 0, 2)]
		_order_t = _think_dt
		_think()
	actor.physics(dt)


func _tick_seated(_dt: float) -> void:
	# seated officers shoot from the window when the order allows it (passengers only)
	brain.shoot_allowed = _shooting_authorised() and Game.wanted_level >= 2
	brain.seated_fire = seat_index > 0
	brain.combat_enabled = mode == &"pursue" or mode == &"hold"
	if brain.combat_enabled and brain.forced_target == null and Game.player != null:
		brain.forced_target = Game.player


func _think() -> void:
	var wl := Game.wanted_level
	var pl = Game.player
	if mode != &"leave":
		var t_is_player: bool = pl != null and brain.has_target() and brain.target == pl
		var authorised := _shooting_authorised()
		_set_arrest_mode(t_is_player and not authorised)
		brain.shoot_allowed = (not t_is_player) or authorised
		if t_is_player and is_instance_valid(pl):
			var t_in_vehicle: bool = pl.get("current_vehicle") != null and is_instance_valid(pl.current_vehicle)
			var dist := Util.dist_xz((pl as Node3D).global_position, global_position)
			_arrest_logic(pl, dist, t_in_vehicle, _target_speed(pl))
			if not authorised and brain.target_visible and dist < 40.0:
				_shout()
	match mode:
		&"pursue":
			_think_pursue(pl, wl)
		&"search":
			_think_search(pl)
		&"hold":
			_think_hold(pl)
		&"leave":
			_think_leave()
		_:
			_think_patrol()
	_update_weapon_state()


func _update_weapon_state() -> void:
	var want_drawn := brain.in_combat or brain.is_engaged() or mode == &"pursue" or mode == &"hold" or (mode == &"search" and Game.wanted_level > 0)
	if mode == &"patrol" and not brain.in_combat:
		want_drawn = false
	if mode == &"leave":
		want_drawn = false
	if want_drawn and holstered:
		holstered = false
		actor.weapons.equip(primary)
	elif not want_drawn and not holstered and not brain.in_combat:
		holstered = true
		actor.weapons.equip(&"fists")
	weapon_drawn = not holstered


# ---- patrol (idle at the station / stroll) -----------------------------------------------------------------------------
func _think_patrol() -> void:
	brain.combat_enabled = true
	brain.forced_target = null
	if brain.is_engaged():
		return
	_wander_t -= _think_dt
	if mover.has_goal and not mover.arrived:
		return
	if _wander_t <= 0.0:
		_wander_t = randf_range(7.0, 14.0)
		var base: Vector3 = order.get("pos", global_position)
		var g := WorldLayout.ped_graph
		var idx := g.nearest(base + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12)), 20.0) if g.size() > 0 else -1
		if idx >= 0 and randf() < 0.55:
			mover.set_goal(g.positions[idx], mover.walk_speed, 1.2)
		else:
			mover.stop()
			var styles := [&"relaxed", &"arms_crossed", &"hands_pockets"]
			actor.rig.set_idle_style(styles[randi() % styles.size()])
			mover.face_direction(randf() * TAU)


# ---- pursuit ---------------------------------------------------------------------------------------------------------------
func _think_pursue(pl, wl: int) -> void:
	var tgt: Node = order.get("target", null)
	if tgt == null or not is_instance_valid(tgt):
		tgt = pl
	if tgt == null or not is_instance_valid(tgt):
		return
	brain.combat_enabled = true
	brain.forced_target = tgt
	# nobody in sight: run to the last known position the director gave us (and look around when we get there)
	if not brain.has_target() and order.has("pos") and brain.state == CombatBrain.State.IDLE:
		var op: Vector3 = order["pos"]
		if Util.dist_xz(op, global_position) > 4.0:
			brain.investigate(op, 10.0)
	var t_in_vehicle: bool = tgt.get("current_vehicle") != null and is_instance_valid(tgt.current_vehicle)
	var tpos: Vector3 = (tgt as Node3D).global_position
	var dist := Util.dist_xz(tpos, global_position)
	var tspeed := _target_speed(tgt)
	_closein_watchdog(tgt, tpos, dist, t_in_vehicle)
	# fast target in a vehicle: get back into our own car when it is close, otherwise keep engaging from where we are
	if t_in_vehicle and tspeed > 7.0 and dist > 14.0 and _try_enter_home():
		return
	# commandeer a civilian car when stranded at high levels (stretch)
	if t_in_vehicle and tspeed > 8.0 and dist > 30.0 and wl >= 4 and home_vehicle == null:
		_stranded_t += _think_dt
		if _stranded_t > 2.5 and _try_commandeer():
			return
	else:
		_stranded_t = 0.0


var _arrest_mode := false
var _standoff_best := INF
var _standoff_t := 0.0
var _closein_until := 0.0
var _closein_active := false
var standoff_breaks := 0              # how often the watchdog had to push this officer (stats / tests)


## QA: officers sometimes held ~37 m away without ever closing in (cover cycle, lost route, no line of sight). When a foot suspect is more
## than 6 m away and the distance has not shrunk by 3 m for STANDOFF_S seconds, the officer is told where the suspect is (radio) and
## runs straight at him for a few seconds: no cover seeking, the brain's APPROACH state, refreshed every think.
func _closein_watchdog(tgt: Node, tpos: Vector3, dist: float, t_in_vehicle: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if t_in_vehicle or dist < 6.0 or tgt != Game.player:
		_standoff_best = INF
		_standoff_t = 0.0
	elif dist < _standoff_best - 3.0:
		_standoff_best = dist
		_standoff_t = 0.0
	else:
		_standoff_t += _think_dt
		if _standoff_t >= STANDOFF_S and now >= _closein_until:
			_closein_until = now + 8.0
			_standoff_best = dist
			_standoff_t = 0.0
			standoff_breaks += 1
	if now < _closein_until and not t_in_vehicle and dist >= 3.0:
		_closein_active = true
		brain.use_cover = false
		brain.last_seen_pos = tpos
		brain.last_seen_t = brain._now
		brain._alert_until = maxf(brain._alert_until, brain._now + 4.0)
		if brain.state != CombatBrain.State.APPROACH and brain.state != CombatBrain.State.MELEE:
			brain._leave_cover()
			brain.in_combat = true
			brain._set_state(CombatBrain.State.APPROACH)
		mover.sprinting = dist > 14.0
	elif _closein_active:
		_closein_active = false
		brain.use_cover = (not _arrest_mode) and kind != &"sniper"


func _set_arrest_mode(on: bool) -> void:
	if on == _arrest_mode:
		return
	_arrest_mode = on
	brain.aim_without_fire = on
	if on:
		brain.pref_min = 1.2
		brain.pref_max = 2.4
		brain.use_cover = false
		brain.can_melee = false
		brain.shoot_allowed = false
	else:
		actor.auto_range(1.35 if kind == &"swat" else 1.0)
		brain.use_cover = kind != &"sniper"
		brain.can_melee = true


func _arrest_logic(pl, dist: float, t_in_vehicle: bool, tspeed: float) -> void:
	if not arrest_enabled or order.get("arrest", true) == false or pl.get("is_dead") == true:
		return
	var close := dist < ARREST_RANGE and absf(pl.global_position.y - global_position.y) < 2.2
	var still := tspeed < 2.4
	var resisting := false
	if pl.weapons != null:
		resisting = pl.weapons.get("is_aiming") == true or (Time.get_ticks_msec() / 1000.0 < player_hostile_until and tspeed > 3.0)
	if close and still and not resisting and (not t_in_vehicle or tspeed < 1.0):
		arrest_progress += _think_dt
		if arrest_progress >= ARREST_TIME and not _arrest_guard:
			_arrest_guard = true
			if pl.has_method("arrest"):
				pl.arrest(self)
			arrested.emit(pl)
			_arrest_guard = false
			arrest_progress = 0.0
	else:
		arrest_progress = maxf(arrest_progress - _think_dt * 1.5, 0.0)


func _shout() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_shout < SHOUT_GAP:
		return
	_last_shout = now
	Events.subtitle.emit(SHOUTS[randi() % SHOUTS.size()], 2.2)
	Sfx.play_3d(&"gasp", global_position + Vector3(0, 1.6, 0), -12.0, 0.8, 20.0)


func _target_speed(tgt: Node) -> float:
	var v = tgt.get("current_vehicle")
	if v != null and is_instance_valid(v) and v.get("linear_velocity") != null:
		return (v.linear_velocity as Vector3).length()
	var vel = tgt.get("velocity")
	if vel is Vector3:
		return Vector2(vel.x, vel.z).length()
	return 0.0


# ---- cars ------------------------------------------------------------------------------------------------------------------
func _try_enter_home() -> bool:
	if home_vehicle == null or not is_instance_valid(home_vehicle) or home_vehicle.is_destroyed:
		return false
	var v := home_vehicle
	var seat := home_seat if home_seat >= 0 else 0
	if v.seats.size() <= seat or (v.seats[seat]["character"] != null and v.seats[seat]["character"] != self):
		seat = v.get_free_seat()
		if seat < 0:
			return false
	var ep := v.get_entry_position(seat)
	var d := Util.dist_xz(ep, global_position)
	if d > 45.0:
		return false
	if d < 2.4:
		if v.request_enter(self, seat):
			brain.stance_want = &"stand"
			mover.stop()
			return true
		return false
	brain.combat_enabled = false
	brain.clear_target_memory_if_idle()
	mover.sprinting = d > 12.0
	mover.set_goal(ep, mover.sprint_speed if d > 12.0 else mover.run_speed, 1.6)
	return true


func _try_commandeer() -> bool:
	# stretch: take a nearby civilian car (carjack) and drive after the target
	var best: VehicleBase = null
	var best_d := 28.0
	for v in get_tree().get_nodes_in_group(GC.G_TRAFFIC):
		var vb := v as VehicleBase
		if vb == null or vb.is_destroyed or vb.faction == GC.F_POLICE or vb.vclass != GC.VC_CAR:
			continue
		var d := vb.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = vb
	if best == null:
		return false
	var ep := best.get_entry_position(0)
	brain.combat_enabled = false
	mover.sprinting = true
	mover.set_goal(ep, mover.sprint_speed, 1.6)
	if Util.dist_xz(ep, global_position) < 2.4:
		if best.request_enter(self, 0):
			home_vehicle = best
			home_seat = 0
			best.faction = GC.F_POLICE
			best.add_to_group(GC.G_POLICE)
			best.siren_on = true
			PoliceCarAI.attach(best)
			return true
	return true


# ---- search / hold / leave ------------------------------------------------------------------------------------------------
func _think_search(pl) -> void:
	brain.combat_enabled = true
	if pl != null and is_instance_valid(pl) and brain.forced_target == null:
		brain.forced_target = pl
	if brain.is_engaged() and brain.state != CombatBrain.State.SEARCH:
		return
	var center: Vector3 = order.get("pos", global_position)
	var radius := float(order.get("radius", 40.0))
	_search_next -= _think_dt
	if brain.state == CombatBrain.State.SEARCH:
		return
	# not in the search area yet: hurry there at a run / sprint (along the sidewalk graph) instead of strolling around where we stand
	var d_center := Util.dist_xz(center, global_position)
	if d_center > radius * 1.1 + 10.0:
		if not mover.has_goal or mover.arrived or mover.goal.distance_to(center) > 12.0:
			mover.sprinting = d_center > 45.0
			mover.set_goal(center, mover.sprint_speed if d_center > 45.0 else mover.run_speed, 4.0)
		_search_next = 3.0
		return
	if _search_next <= 0.0 or (mover.arrived and not mover.has_goal) or mover.arrived:
		_search_next = randf_range(5.0, 9.0)
		var p := Util.rand_in_ring(center, 0.0, radius)
		var g := WorldLayout.ped_graph
		var idx := g.nearest(p, 25.0) if g.size() > 0 else -1
		var dest := g.positions[idx] if idx >= 0 else p
		mover.sprinting = false
		mover.set_goal(dest, mover.run_speed * 0.7, 2.0)
	# scanning: sweep the head while walking
	if actor.rig != null and mover.has_goal:
		var yaw := rotation.y + sin(_clock * 0.9 + float(get_instance_id() % 7)) * 1.0
		actor.rig.look_at_point(global_position + Util.yaw_to_dir(yaw) * 12.0 + Vector3(0, 1.5, 0))


func _think_hold(pl) -> void:
	brain.combat_enabled = true
	brain.hold_position = true
	if pl != null and is_instance_valid(pl):
		brain.forced_target = order.get("target", pl)
	if not brain.is_engaged():
		var hp: Vector3 = order.get("pos", global_position)
		if Util.dist_xz(hp, global_position) > 1.2 and not mover.stuck:
			mover.set_goal(hp, mover.run_speed, 0.6)
		else:
			mover.stop()
			var dir: Vector3 = order.get("dir", Vector3.ZERO)
			if dir != Vector3.ZERO:
				mover.face_direction(Util.dir_to_yaw(dir))
		brain.stance_want = order.get("stance", &"stand")


func _think_leave() -> void:
	brain.combat_enabled = false
	brain.forced_target = null
	_set_arrest_mode(false)
	brain.shoot_allowed = true
	_leave_t += _think_dt
	if home_vehicle != null and is_instance_valid(home_vehicle) and not home_vehicle.is_destroyed:
		if _try_enter_home():
			return
	# no car: walk away and disappear when nobody looks
	if not mover.has_goal or mover.arrived:
		var away := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var pl = Game.player
		if pl != null and is_instance_valid(pl):
			away = (global_position - pl.global_position)
			away.y = 0.0
			away = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
		mover.set_goal(global_position + away * 40.0, mover.walk_speed * 1.4, 2.0)
	if _leave_t > 14.0 and _unseen_and_far():
		PoliceUnits.despawn(self)


func _unseen_and_far() -> bool:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		return true
	var d: float = (pl as Node3D).global_position.distance_to(global_position)
	if d > 140.0:
		return true
	if d < 35.0:
		return false
	var cam: Camera3D = Game.gameplay_camera
	if cam != null and is_instance_valid(cam):
		return not cam.is_position_in_frustum(global_position + Vector3(0, 1, 0))
	return true


# ---- events ------------------------------------------------------------------------------------------------------------------
func _on_target_sighted(t: Node, pos: Vector3, _first: bool) -> void:
	if t != Game.player:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_report:
		return
	_next_report = now + 0.7
	var w = Game.sys(&"wanted")
	if w != null and w.has_method("report_sighting"):
		w.report_sighting((t as Node3D).global_position, self)


func _on_damaged(amount: float, info: Dictionary) -> void:
	actor.on_damaged(amount, info)
	# being shot at by the player always allows return fire
	if info.get("source", null) == Game.player:
		player_hostile_until = Time.get_ticks_msec() / 1000.0 + 25.0
		if not brain.combat_enabled and Game.wanted_level > 0:
			brain.combat_enabled = true


func _on_death(info: Dictionary) -> void:
	actor.on_death(info)


func _on_revive() -> void:
	actor.on_revive()


func knock_down(impulse: Vector3, duration: float) -> void:
	actor.knock_down(impulse, duration)


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, 1.45 if actor != null and actor.crouched else 1.6, 0.0)
