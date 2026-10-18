class_name InteractionManager
extends Node
## World interactions of Systems-A, hosted by EconomySystem (Game.sys(&"interactions")): roof ladders, the downtown tower elevator, phone
## booths (quick save), benches (sit) and fire hydrants (water jets). One manager, no per-prop scripts: every interactable is a bare
## InteractionPoint that forwards here; baked MultiMesh props (benches, hydrants) are served by a tiny pool that follows the player.
##
## Prompts are the Player's standard `interactable` prompts ("[E] Climb ladder"); the actions are executed in activate().

signal built()
signal ladder_started(ladder_id: String, up: bool)
signal elevator_ridden(to_roof: bool)
signal seat_changed(sitting: bool)
signal booth_used(booth_id: String)

const BENCH_POOL := 3
const BENCH_RANGE := 6.5
const TICK := 0.25
const RIDE_TIME := 1.35

var economy: Node = null
var ladders: Array = []                  # InteractionLadders records (+ "reward")
var elevator: Dictionary = {}            # InteractionElevator.plan() result + built door dictionaries
var booths: Array = []
var is_built := false
var points: Array[InteractionPoint] = []
var sitting := false
var riding := false
var phone_slot := 0                      # save slot used by phone booths (tests switch it)

var _bench_seats: Array = []
var _bench_pool: Array[InteractionPoint] = []
var _hydrants: Array[Vector3] = []
var _jets: InteractionProps.JetPool = null
var _acc := 0.0
var _seat: Dictionary = {}
var _tweens: Dictionary = {}


func setup(eco: Node) -> void:
	economy = eco
	process_mode = Node.PROCESS_MODE_PAUSABLE


func post_setup() -> void:
	Events.projectile_impact.connect(_on_projectile_impact)
	Events.explosion.connect(_on_explosion)
	Events.player_died.connect(func() -> void: _force_stand())
	Events.player_busted.connect(func() -> void: _force_stand())
	Events.player_respawned.connect(func(_p: Vector3) -> void: _force_stand())
	Events.player_hurt.connect(func(_a: float, _i: Dictionary) -> void: _force_stand())


# ======================================================================================================== building
func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91357
	var t0 := Time.get_ticks_msec()
	_build_ladders(rng)
	await get_tree().physics_frame
	_build_elevator()
	_build_booths(rng)
	await get_tree().physics_frame
	_build_benches()
	_build_hydrants()
	is_built = true
	print("[Interactions] ladders=%d elevator=%s phone booths=%d bench seats=%d hydrants=%d (%d ms)" % [
		ladders.size(), str(not elevator.is_empty()), booths.size(), _bench_seats.size(), _hydrants.size(), Time.get_ticks_msec() - t0])
	built.emit()


func get_roof_rewards() -> Array:
	var out: Array = []
	for rec in ladders:
		if rec.has("reward"):
			out.append(rec["reward"])
	return out


func _sector_parent(pos: Vector3) -> Node3D:
	var w = Game.world
	if w != null and is_instance_valid(w):
		if w.has_method("get_sector_parent"):
			var sp = w.get_sector_parent(pos)
			if sp is Node3D:
				return sp
		return w as Node3D
	return null


func _make_point(kind: StringName, pos: Vector3, text: String, rng_m: float, data: Dictionary = {}) -> InteractionPoint:
	var p := InteractionPoint.new()
	p.kind = kind
	p.text = text
	p.interact_range = rng_m
	p.data = data
	p.manager = self
	p.name = "IP_%s_%d" % [String(kind), points.size()]
	add_child(p)
	p.global_position = pos
	points.append(p)
	return p


func _build_ladders(rng: RandomNumberGenerator) -> void:
	ladders = InteractionLadders.plan(rng)
	for i in ladders.size():
		var rec: Dictionary = ladders[i]
		var vis := InteractionLadders.build_visual(rec)
		var parent := _sector_parent(rec["bottom"])
		if parent != null:
			parent.add_child(vis)
		else:
			add_child(vis)
		rec["visual"] = vis
		var n: Vector3 = rec["normal"]
		_make_point(&"ladder_up", (rec["bottom"] as Vector3) + n * 0.95 + Vector3(0, 0.1, 0), "Climb ladder", 1.9, {"ladder": i})
		_make_point(&"ladder_down", (rec["top"] as Vector3) - n * 0.9 + Vector3(0, 0.1, 0), "Climb down the ladder", 1.7, {"ladder": i})
		# roof reward: a cash stash a few metres inland
		var c: Vector3 = (rec["top"] as Vector3) - n * 4.5
		var rp := InteractionUtil.find_walkable(c, {"rng": rng, "max_r": 3.5, "ref_y": float(rec["roof_y"]), "up": 2.5, "down": 1.5, "avoid_road": false, "tries": 30})
		if rp != Vector3.INF:
			rec["reward"] = {"id": "cash_roof_%d" % i, "pos": rp, "amount": int(round(rng.randf_range(300.0, 650.0) / 10.0)) * 10}


func _build_elevator() -> void:
	elevator = InteractionElevator.plan()
	if elevator.is_empty():
		return
	var g: Dictionary = elevator["ground"]
	var r: Dictionary = elevator["roof"]
	var gparent := _sector_parent(g["pos"])
	var rparent := _sector_parent(r["pos"])
	if gparent == null:
		gparent = rparent
	var gx := Transform3D(Basis(Vector3.UP, float(g["yaw"])), (g["pos"] as Vector3) + (g["normal"] as Vector3) * 0.03)
	g["door"] = InteractionElevator.build_door(InteractionElevator.DOOR_GLB, gx, gparent)
	var rx := Transform3D(Basis(Vector3.UP, float(r["yaw"])), r["pos"])
	r["door"] = InteractionElevator.build_door(InteractionElevator.ROOF_GLB, rx, rparent, Vector3(3.8, 3.2, 3.2))
	_make_point(&"elevator_up", (g["pos"] as Vector3) + (g["normal"] as Vector3) * 1.25 + Vector3(0, 0.1, 0), "Take the elevator to the rooftop helipad", 2.4, {})
	_make_point(&"elevator_down", (r["pos"] as Vector3) + (r["normal"] as Vector3) * 2.9 + Vector3(0, 0.1, 0), "Take the elevator down", 2.4, {})


func _build_booths(rng: RandomNumberGenerator) -> void:
	booths = InteractionProps.plan_phone_booths(rng)
	for b in booths:
		var parent := _sector_parent(b["pos"])
		if parent != null:
			b["node"] = InteractionProps.build_booth(b, parent)
		_make_point(&"phone", b["use_pos"], "Use the phone (save game)", 1.9, {"booth": b["id"]})


func _build_benches() -> void:
	_bench_seats = InteractionProps.bench_seats()
	for i in BENCH_POOL:
		var p := _make_point(&"bench", Vector3(0, -500, 0), "Sit down", 2.0, {"seat": -1})
		p.visible = false
		_bench_pool.append(p)


func _build_hydrants() -> void:
	_hydrants = InteractionProps.hydrant_positions()
	_jets = InteractionProps.JetPool.new()
	add_child(_jets)


# ======================================================================================================== prompts / actions
func describe(point: InteractionPoint, player: Node) -> Dictionary:
	var ok := player != null and player.get("move_mode") != null
	match point.kind:
		&"ladder_up", &"ladder_down":
			return {"text": point.text, "key": "E", "enabled": ok and not sitting and not riding}
		&"elevator_up", &"elevator_down":
			return {"text": point.text, "key": "E", "enabled": ok and not riding}
		&"phone":
			return {"text": point.text, "key": "E", "enabled": ok}
		&"bench":
			return {"text": "Sit down" if not sitting else "Stand up", "key": "E", "enabled": ok}
	return {"text": point.text, "key": point.key, "enabled": point.enabled}


func activate(point: InteractionPoint, player: Node) -> void:
	match point.kind:
		&"ladder_up", &"ladder_down":
			_use_ladder(point, player)
		&"elevator_up":
			ride(player, true)
		&"elevator_down":
			ride(player, false)
		&"phone":
			_use_phone(point, player)
		&"bench":
			if sitting:
				_stand(player)
			else:
				_sit(player, int(point.data.get("seat", -1)))


# ---- ladders ---------------------------------------------------------------------------------------------------------
func _use_ladder(point: InteractionPoint, player: Node) -> bool:
	var rec: Dictionary = ladders[int(point.data["ladder"])]
	var tr = player.get("traversal")
	if tr == null:
		return false
	var up := point.kind == &"ladder_up"
	var n: Vector3 = rec["normal"]
	var ok: bool = tr.start_ladder(rec["bottom"], rec["top"], -n, 0.0 if up else 1.0)
	if ok:
		ladder_started.emit(String(rec["id"]), up)
		Sfx.play_3d(&"door_vehicle_close", rec["bottom"], -8.0, 1.6, 20.0)
	return ok


# ---- phone ---------------------------------------------------------------------------------------------------------------
func _use_phone(point: InteractionPoint, player: Node) -> void:
	var ok: bool = SaveSystem != null and SaveSystem.save_game(phone_slot)
	if ok:
		Game.notify("Game saved (phone booth).", &"good")
		Sfx.play_ui(&"ui_confirm")
		booth_used.emit(String(point.data.get("booth", "")))
	else:
		Game.notify("The line is dead - could not save.", &"bad")
		Sfx.play_ui(&"ui_error")


# ---- elevator ------------------------------------------------------------------------------------------------------------
## Doors open -> fade -> short ride -> teleport -> doors open at the other end. Awaitable (tests).
func ride(player: Node, to_roof: bool) -> void:
	if riding or elevator.is_empty() or player == null or not is_instance_valid(player):
		return
	riding = true
	var from_d: Dictionary = (elevator["ground"] if to_roof else elevator["roof"])["door"]
	var dest: Dictionary = (elevator["roof"] if to_roof else elevator["ground"])
	var to_d: Dictionary = dest["door"]
	if player.get("interaction") != null:
		player.interaction.clear_prompt()
	player.set("input_locked", true)
	if player.has_method("release_input"):
		player.release_input()
	Sfx.play_ui(&"ui_confirm")
	_set_door(from_d, true, 0.5)
	await get_tree().create_timer(0.55).timeout
	Events.subtitle.emit("Going up..." if to_roof else "Going down...", RIDE_TIME + 0.4)
	await InteractionUtil.fade_out(0.4)
	_set_door(from_d, false, 0.3)
	if is_instance_valid(Game.gameplay_camera) and Game.gameplay_camera.has_method("add_shake"):
		Game.gameplay_camera.add_shake(0.06, RIDE_TIME)
	await get_tree().create_timer(RIDE_TIME).timeout
	player.teleport_to(dest["stand"], float(dest["yaw"]))
	if is_instance_valid(Game.gameplay_camera) and Game.gameplay_camera.has_method("snap_behind"):
		Game.gameplay_camera.snap_behind(float(dest["yaw"]))
	_set_door(to_d, true, 0.4)
	Sfx.play_ui(&"ui_notify")
	await InteractionUtil.fade_in(0.45)
	player.set("input_locked", false)
	await get_tree().create_timer(1.1).timeout
	_set_door(to_d, false, 0.5)
	riding = false
	elevator_ridden.emit(to_roof)


func _set_door(d: Dictionary, open: bool, seconds: float) -> void:
	var l: Node3D = d.get("left")
	var r: Node3D = d.get("right")
	if l == null and r == null:
		return
	var key: int = (d["root"] as Node).get_instance_id()
	if _tweens.has(key) and _tweens[key] is Tween and (_tweens[key] as Tween).is_valid():
		(_tweens[key] as Tween).kill()
	var tw := create_tween()
	tw.set_parallel(true)
	_tweens[key] = tw
	var s := InteractionElevator.DOOR_SLIDE if open else 0.0
	if l != null:
		tw.tween_property(l, "position", (d["left_rest"] as Vector3) + Vector3(-s, 0, 0), seconds).set_trans(Tween.TRANS_SINE)
	if r != null:
		tw.tween_property(r, "position", (d["right_rest"] as Vector3) + Vector3(s, 0, 0), seconds).set_trans(Tween.TRANS_SINE)
	d["open"] = 1.0 if open else 0.0


# ---- benches ---------------------------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not is_built:
		return
	_acc += delta
	if _acc < TICK:
		return
	_acc = 0.0
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	_update_bench_pool(p)
	_check_vehicle_hydrants()


func _update_bench_pool(p: Node) -> void:
	if sitting:
		for bp in _bench_pool:
			bp.visible = false
		return
	var pp: Vector3 = p.global_position
	var near: Array = []                  # [dist, idx]
	var r2 := BENCH_RANGE * BENCH_RANGE
	for i in _bench_seats.size():
		var s: Vector3 = _bench_seats[i]["pos"]
		var dx := s.x - pp.x
		var dz := s.z - pp.z
		var d2 := dx * dx + dz * dz
		if d2 < r2 and absf(s.y - pp.y) < 2.0:
			near.append([d2, i])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for k in BENCH_POOL:
		var bp := _bench_pool[k]
		if k < near.size():
			var idx: int = near[k][1]
			var seat: Dictionary = _bench_seats[idx]
			# the prompt anchor sits in front of the bench, one step away from the seat
			bp.global_position = (seat["pos"] as Vector3) + Util.yaw_to_dir(float(seat["yaw"])) * 0.7 - Vector3(0, 0.45, 0)
			bp.data["seat"] = idx
			bp.visible = true
		else:
			bp.visible = false


func _sit(player: Node, seat_idx: int) -> bool:
	if seat_idx < 0 or seat_idx >= _bench_seats.size() or sitting:
		return false
	var tr = player.get("traversal")
	if tr == null or player.get("rig") == null:
		return false
	if player.move_mode != Player.Move.GROUND:
		return false
	var seat: Dictionary = _bench_seats[seat_idx]
	var pos: Vector3 = (seat["pos"] as Vector3) - Vector3(0, 0.085, 0)       # Seat points are pelvis points (CharacterRig sit contract)
	var yaw: float = seat["yaw"]
	# hold the player on the seat with the traversal 'scripted motion' (collisions off, body pinned, camera free)
	tr._pts.clear()
	tr._pts.append(pos)
	tr._pts.append(pos)
	tr._dur = 100000.0
	tr._t = 0.0
	tr._end_vel = Vector3.ZERO
	tr._face_yaw = yaw
	tr.kind = &"sit"
	player.crouching = false
	player.sprinting = false
	player.move_mode = Player.Move.TRAVERSE
	player.begin_scripted_motion(&"sit")
	player.stow_weapon()
	player.use_real_input = false
	player.release_input()
	player.global_position = pos
	player.rotation.y = yaw
	player._reset_interp()
	var rig = player.rig
	rig.set_stance(&"sit_car")
	if rig.has_method("set_seat"):
		rig.set_seat(&"passenger")
	player.set("_last_stance", &"stand")             # keeps PlayerRig from overriding the sit pose
	if player.interaction != null:
		player.interaction.clear_prompt()
	sitting = true
	_seat = {"idx": seat_idx, "player": player, "yaw": yaw, "pos": pos}
	seat_changed.emit(true)
	return true


func _stand(player: Node) -> void:
	if not sitting:
		return
	sitting = false
	var yaw: float = _seat.get("yaw", 0.0)
	var pos: Vector3 = _seat.get("pos", player.global_position)
	var out := pos + Util.yaw_to_dir(yaw) * 0.75
	var g := InteractionUtil.ground_at(out.x, out.z, 1.5, 3.0)
	if not g.is_empty():
		out = g["position"]
	else:
		out.y = pos.y - 0.4
	var tr = player.get("traversal")
	if tr != null:
		tr.cancel()
	player.global_position = out + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player._reset_interp()
	if player.rig != null:
		player.rig.set_stance(&"stand")
		if player.rig.has_method("set_seat"):
			player.rig.set_seat(&"driver")
	player.set("_last_stance", &"stand")
	player.use_real_input = true
	player.release_input()
	player.unstow_weapon()
	_seat = {}
	seat_changed.emit(false)


func _force_stand() -> void:
	if sitting and _seat.has("player") and is_instance_valid(_seat["player"]):
		_stand(_seat["player"])
	elif sitting:
		sitting = false
		_seat = {}


func _input(event: InputEvent) -> void:
	if not sitting or not _seat.has("player") or not is_instance_valid(_seat["player"]):
		return
	if event is InputEventMouseMotion or event.is_echo() or not event.is_pressed():
		return
	for a in [&"interact", &"jump", &"move_forward", &"move_left", &"move_right", &"move_back", &"crouch"]:
		if event.is_action_pressed(a):
			_stand(_seat["player"])
			get_viewport().set_input_as_handled()
			return


# ---- hydrants -----------------------------------------------------------------------------------------------------------
func _hydrant_near(pos: Vector3, max_xz: float, max_dy: float = 1.6) -> int:
	var best := -1
	var best_d := max_xz * max_xz
	for i in _hydrants.size():
		var h := _hydrants[i]
		if absf(h.y - pos.y) > max_dy + 0.9:
			continue
		var d := (h.x - pos.x) * (h.x - pos.x) + (h.z - pos.z) * (h.z - pos.z)
		if d < best_d:
			best_d = d
			best = i
	return best


func _on_projectile_impact(position: Vector3, _normal: Vector3, _surface: StringName, _source: Node) -> void:
	if _jets == null or _hydrants.is_empty():
		return
	var i := _hydrant_near(position, 0.75)
	if i >= 0:
		_jets.start(_hydrants[i])


func _on_explosion(position: Vector3, radius: float, _source: Node) -> void:
	if _jets == null:
		return
	for h in _hydrants:
		if h.distance_to(position) < radius * 0.8:
			_jets.start(h)


func _check_vehicle_hydrants() -> void:
	if _jets == null or _hydrants.is_empty():
		return
	for v in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if not (v is RigidBody3D):
			continue
		var rb := v as RigidBody3D
		if rb.linear_velocity.length_squared() < 25.0:           # > 5 m/s
			continue
		var i := _hydrant_near(rb.global_position + rb.linear_velocity.normalized() * 1.0, 2.3)
		if i >= 0:
			_jets.start(_hydrants[i], 9.0)


## Test helper: starts a jet at hydrant `i` (returns its position or Vector3.INF).
func spray_hydrant(i: int) -> Vector3:
	if _jets == null or i < 0 or i >= _hydrants.size():
		return Vector3.INF
	_jets.start(_hydrants[i])
	return _hydrants[i]


func get_hydrants() -> Array[Vector3]:
	return _hydrants


func get_jets() -> InteractionProps.JetPool:
	return _jets


func get_bench_seats() -> Array:
	return _bench_seats
