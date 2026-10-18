class_name ActivitySystem
extends Node
## Optional free-roam activities (NEVER missions): shooting range, stunt jumps, street race. Booted by Main as `activities`.
## Registry + state machine IDLE / COUNTDOWN / RUNNING / FINISHED / ABORTED (one active activity at a time), HUD widget, results card,
## persistent best scores / medals, start points (group `interactable`, prompt "[E] ...") with subtle neon markers shown within 60 m.
## Abort rules: player dead / busted, left the area, wrong vehicle (each activity's check_abort), or hold E for 0.9 s to quit.
## docs/api/activities.md

signal state_changed(new_state: int, activity_id: StringName)
signal activity_finished(activity_id: StringName, result: Dictionary)
signal activity_aborted(activity_id: StringName, reason: String)

enum State { IDLE, COUNTDOWN, RUNNING, FINISHED, ABORTED }

const MEDAL_RANK := {"none": 0, "bronze": 1, "silver": 2, "gold": 3}
const QUIT_HOLD := 0.9
const RESULT_SECONDS := 7.0

var state: State = State.IDLE
var active: ActivityBase = null
var activities: Dictionary = {}                 # StringName -> ActivityBase
var best: Dictionary = {}                       # key -> {value, medal, plays}
var flags: Dictionary = {}                      # misc persisted flags (stunt_1 ...)
var hud: ActivityHud = null
var ready_ok := false
var stats := {"started": 0, "finished": 0, "aborted": 0}

var _layer: CanvasLayer
var _world_root: Node3D
var _points: Dictionary = {}                    # id -> [ActivityPoint]
var _markers: Array = []                        # [{marker, activity}]
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_i := 0
var _timer := 0.0
var _count_n := 0
var _marker_cd := 0.0
var _quit_hold := 0.0
var _e_armed := false
var _cooldown := 0.0
var _busted_flag := false
var _menu: ActivityMenu = null


func setup(_main: Node) -> void:
	add_to_group(GC.G_SYSTEM)
	_layer = CanvasLayer.new()
	_layer.name = "ActivityLayer"
	_layer.layer = 9
	add_child(_layer)
	hud = ActivityHud.new()
	_layer.add_child(hud)
	for i in 4:
		var ap := AudioStreamPlayer.new()
		ap.bus = &"UI" if AudioServer.get_bus_index(&"UI") >= 0 else &"Master"
		ap.volume_db = -6.0
		add_child(ap)
		_sfx_players.append(ap)
	Events.player_busted.connect(func() -> void: _busted_flag = true)
	Events.player_died.connect(func() -> void: _busted_flag = true)
	Events.player_respawned.connect(func(_p: Vector3) -> void: _busted_flag = false)
	Events.load_completed.connect(_on_loaded)


func post_setup() -> void:
	if Game.ui != null and is_instance_valid(Game.ui) and Game.ui.has_method("register_menu"):
		_menu = ActivityMenu.new()
		_menu.system = self
		Game.ui.register_menu(&"activity", _menu)
	_late_init.call_deferred()


## Waits for the built world, then creates the activities (their static content needs the landmark anchors / colliders).
func _late_init() -> void:
	var guard := 0
	while (not WorldLayout.built or Game.world == null or not is_instance_valid(Game.world)) and guard < 600:
		await get_tree().physics_frame
		guard += 1
	for i in 6:
		await get_tree().physics_frame
	_world_root = Node3D.new()
	_world_root.name = "ActivityPoints"
	Game.world.add_child(_world_root)
	for script_path in ["res://gta/code/systems/activity_range.gd", "res://gta/code/systems/activity_stunt.gd", "res://gta/code/systems/activity_race.gd"]:
		var scr = load(script_path)
		if scr == null or not (scr is Script) or not scr.can_instantiate():
			push_error("[Activities] failed to load " + script_path)
			continue
		var act: ActivityBase = scr.new()
		register(act)
	ready_ok = true
	print("[Activities] ready: ", activities.keys())


func register(act: ActivityBase) -> void:
	act.sys = self
	act.name = String(act.id)
	add_child(act)
	activities[act.id] = act
	act.setup_activity()
	if act.passive:
		_add_markers(act)
		return
	if act.point_pos == Vector3.ZERO:
		return
	var pt := ActivityPoint.new()
	pt.name = "Point_" + String(act.id)
	pt.activity = act
	pt.system = self
	pt.interact_range = act.interact_range
	_world_root.add_child(pt)
	pt.global_position = act.point_pos
	_points[act.id] = [pt]
	if act.show_marker:
		_add_markers(act)


func _add_markers(act: ActivityBase) -> void:
	var spots: Array = act.marker_spots()
	for sp in spots:
		var m := ActivityMarker.new()
		m.name = "Marker_" + String(act.id)
		_world_root.add_child(m)
		m.global_position = sp
		m.setup(act.accent, act.marker_radius, 4.5)
		_markers.append({"marker": m, "activity": act})


func get_activity(aid: StringName) -> ActivityBase:
	return activities.get(aid, null)


# ---- interaction -----------------------------------------------------------------------------------------------------------
func describe_point(pt: ActivityPoint, player: Node) -> Dictionary:
	var act := pt.activity
	if act == null:
		return {}
	if state != State.IDLE:
		if active == act and (state == State.RUNNING or state == State.COUNTDOWN):
			return {"text": "Hold E to quit %s" % act.title, "key": "E", "enabled": false}
		return {"text": "%s (another activity is running)" % act.title, "key": "E", "enabled": false}
	if _cooldown > 0.0:
		return {"text": act.prompt_text(player), "key": "E", "enabled": false}
	var reason := act.can_start(player, {})
	return {"text": act.prompt_text(player) if reason == "" else reason, "key": "E", "enabled": reason == ""}


func interact_point(pt: ActivityPoint, player: Node) -> void:
	var act := pt.activity
	if act == null or state != State.IDLE or _cooldown > 0.0:
		return
	var reason := act.can_start(player, {})
	if reason != "":
		Game.notify(reason, &"warn")
		return
	if not act.options.is_empty() and Game.ui != null and is_instance_valid(Game.ui) and Game.ui.has_method("open_menu") and _menu != null:
		Game.ui.open_menu(&"activity", {"id": act.id})
		return
	start(act.id, {})


func start_deferred(aid: StringName, opts: Dictionary) -> void:
	# the menu closes (and unpauses) first; start on the next physics frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	start(aid, opts)


# ---- state machine -------------------------------------------------------------------------------------------------------------
func start(aid: StringName, opts: Dictionary = {}) -> bool:
	var act := get_activity(aid)
	if act == null or state != State.IDLE:
		return false
	var p: Node = Game.player
	if p == null or not is_instance_valid(p):
		return false
	var reason := act.can_start(p, opts)
	if reason != "":
		Game.notify(reason, &"warn")
		return false
	active = act
	_busted_flag = false
	if not act.begin(opts):
		active = null
		return false
	act.running = true
	stats["started"] = int(stats["started"]) + 1
	_quit_hold = 0.0
	_e_armed = false
	Game.set_meta(&"activity_active", String(act.id))
	if act.countdown_seconds > 0:
		_set_state(State.COUNTDOWN)
		_count_n = act.countdown_seconds
		_timer = 0.0
		hud.countdown(str(_count_n))
		play_sfx(&"beep")
	else:
		_set_state(State.RUNNING)
		act.on_go()
	return true


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(int(s), active.id if active != null else &"")


func _physics_process(dt: float) -> void:
	if not ready_ok or Game.paused:
		return
	_cooldown = maxf(_cooldown - dt, 0.0)
	match state:
		State.IDLE:
			_marker_cd -= dt
			if _marker_cd <= 0.0:
				_marker_cd = 0.125
				_update_markers()
			for a in activities.values():
				var act: ActivityBase = a
				if act.passive:
					act.poll_passive(dt)
		State.COUNTDOWN:
			_timer += dt
			_check_active(dt)
			if state != State.COUNTDOWN:
				return
			active.tick(dt, int(state))
			if _timer >= 1.0:
				_timer -= 1.0
				_count_n -= 1
				if _count_n <= 0:
					hud.countdown("GO!")
					play_sfx(&"go")
					_set_state(State.RUNNING)
					active.on_go()
				else:
					hud.countdown(str(_count_n))
					play_sfx(&"beep")
		State.RUNNING:
			_check_active(dt)
			if state == State.RUNNING and active != null:
				active.tick(dt, int(state))
		State.FINISHED:
			_timer += dt
			var quit_early := Input.is_action_just_pressed(&"interact") and _timer > 1.2
			if _timer >= RESULT_SECONDS or quit_early:
				hud.hide_results()
				_end_to_idle()
		State.ABORTED:
			_timer += dt
			if _timer >= 1.2:
				_end_to_idle()


func _check_active(dt: float) -> void:
	var p: Node = Game.player
	if p == null or not is_instance_valid(p):
		abort("Player lost")
		return
	if _busted_flag or p.get("is_dead") == true:
		abort("You were taken out")
		return
	# hold E to quit (must be released once after starting)
	if Input.is_action_pressed(&"interact"):
		if _e_armed:
			_quit_hold += dt
			if _quit_hold >= QUIT_HOLD:
				abort("Quit")
				return
	else:
		_e_armed = true
		_quit_hold = 0.0
	var reason := active.check_abort()
	if reason != "":
		abort(reason)


func abort(reason: String, act: ActivityBase = null) -> void:
	if state != State.COUNTDOWN and state != State.RUNNING:
		return
	if act != null and act != active:
		return
	var a := active
	a.running = false
	a.on_abort(reason)
	a.cleanup()
	hud.finish_activity()
	stats["aborted"] = int(stats["aborted"]) + 1
	Game.notify("%s ended: %s" % [a.title, reason], &"warn" if reason != "Quit" else &"info")
	play_sfx(&"warn")
	activity_aborted.emit(a.id, reason)
	_timer = 0.0
	_set_state(State.ABORTED)


func complete(act: ActivityBase, result: Dictionary) -> void:
	if act != active or (state != State.RUNNING and state != State.COUNTDOWN):
		return
	act.running = false
	var key := String(result.get("key", act.id))
	var value := float(result.get("value", 0.0))
	var higher := bool(result.get("higher_better", true))
	var medal := String(result.get("medal", "none"))
	var prev: Dictionary = best.get(key, {})
	var new_best := prev.is_empty() or (value > float(prev["value"]) if higher else value < float(prev["value"]))
	var better_medal := int(MEDAL_RANK.get(medal, 0)) > int(MEDAL_RANK.get(String(prev.get("medal", "none")), 0))
	var cash := int(result.get("cash", 0))
	if not prev.is_empty() and not better_medal:
		cash = int(cash * 0.5)
	var old_medal := String(prev.get("medal", "none"))
	var top_medal := medal if better_medal else old_medal
	if new_best:
		best[key] = {"value": value, "medal": top_medal, "plays": int(prev.get("plays", 0)) + 1}
	else:
		prev["plays"] = int(prev.get("plays", 0)) + 1
		prev["medal"] = top_medal
		best[key] = prev
	if cash > 0:
		Game.add_cash(cash)
	var skill_sys = Game.sys(&"skills")
	var sk: Dictionary = result.get("skill", {})
	var skill_txt := ""
	if skill_sys != null and skill_sys.has_method("record"):
		for sid in sk:
			skill_sys.record(StringName(sid), float(sk[sid]))
			skill_txt = "%s skill up" % String(sid).capitalize()
	var card := result.duplicate()
	card["cash"] = cash
	card["skill"] = skill_txt
	card["new_best"] = new_best and not prev.is_empty()
	card["medal"] = medal
	act.cleanup()
	hud.finish_activity()
	hud.show_results(card)
	if cash > 0:
		Sfx.play_ui(&"ui_cash")
	play_sfx(&"finish")
	stats["finished"] = int(stats["finished"]) + 1
	activity_finished.emit(act.id, card)
	_timer = 0.0
	_set_state(State.FINISHED)


## Passive activities (stunt jumps) pay without taking over the state machine.
func complete_passive(act: ActivityBase, result: Dictionary) -> void:
	var key := String(result.get("key", act.id))
	var value := float(result.get("value", 0.0))
	var prev: Dictionary = best.get(key, {})
	var new_best := prev.is_empty() or value > float(prev["value"])
	var plays := int(prev.get("plays", 0)) + 1
	if new_best:
		best[key] = {"value": value, "medal": String(result.get("medal", "none")), "plays": plays}
	else:
		prev["plays"] = plays
		best[key] = prev
	var cash := int(result.get("cash", 0))
	if cash > 0:
		Game.add_cash(cash)
		Sfx.play_ui(&"ui_cash")
	var skill_sys = Game.sys(&"skills")
	var sk: Dictionary = result.get("skill", {})
	if skill_sys != null and skill_sys.has_method("record"):
		for sid in sk:
			skill_sys.record(StringName(sid), float(sk[sid]))
	play_sfx(&"finish")
	activity_finished.emit(act.id, result)


func _end_to_idle() -> void:
	if Game.has_meta(&"activity_active"):
		Game.remove_meta(&"activity_active")
	hud.hide_results()
	hud.finish_activity()
	active = null
	_cooldown = 0.8
	_set_state(State.IDLE)


# ---- helpers ------------------------------------------------------------------------------------------------------------------
func is_active() -> bool:
	return state == State.COUNTDOWN or state == State.RUNNING


func play_sfx(sound_id: StringName) -> void:
	var st := ActivitySfx.get_stream(sound_id)
	if st == null or _sfx_players.is_empty():
		return
	var ap := _sfx_players[_sfx_i % _sfx_players.size()]
	_sfx_i += 1
	ap.stream = st
	ap.play()


func best_text(key: String, short: bool = false) -> String:
	if not best.has(key):
		return "" if short else "No record yet"
	var b: Dictionary = best[key]
	var medal := String(b.get("medal", "none"))
	var v := float(b["value"])
	var is_time := key.begins_with("race:")
	var vs := ActivityHud.format_time(v) if is_time else "%d pts" % int(v)
	var tail := "" if medal == "none" else (" - " + medal if short else " (%s)" % medal)
	return (vs if short else "Best " + vs) + tail


func _update_markers() -> void:
	var p: Node = Game.player
	if p == null or not is_instance_valid(p):
		return
	var pp: Vector3 = p.global_position
	for e in _markers:
		var m: ActivityMarker = e["marker"]
		if is_instance_valid(m):
			m.update_distance(Util.dist_xz(m.global_position, pp))


func _on_loaded() -> void:
	for a in activities.values():
		(a as ActivityBase).on_loaded()


# ---- persistence ------------------------------------------------------------------------------------------------------------------
func serialize() -> Dictionary:
	var b := {}
	for k in best:
		var e: Dictionary = best[k]
		b[String(k)] = {"value": float(e["value"]), "medal": String(e.get("medal", "none")), "plays": int(e.get("plays", 0))}
	return {"best": b, "flags": flags.duplicate()}


func deserialize(data: Dictionary) -> void:
	best = {}
	var b = data.get("best", {})
	if b is Dictionary:
		for k in b:
			var e = b[k]
			if e is Dictionary and e.has("value"):
				best[String(k)] = {"value": float(e["value"]), "medal": String(e.get("medal", "none")), "plays": int(e.get("plays", 0))}
	var f = data.get("flags", {})
	flags = (f as Dictionary).duplicate() if f is Dictionary else {}
