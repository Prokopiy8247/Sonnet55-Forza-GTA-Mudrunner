class_name ActivityStunt
extends ActivityBase
## Stunt jumps at the three StuntBuilder ramps (`stunt_jump_1..3`). Passive: nothing to start - drive (car or bike) up the ramp fast enough and
## fly. Tracks airtime / distance / rotation, checks the landing (upright, not destroyed, inside the landing area) and pays a toast + small cash
## (first time of each jump pays more) + Driving skill. Needs speed >= MIN_SPEED on the ramp and >= MIN_AIR seconds of airtime.

const JUMP_IDS: Array[StringName] = [&"stunt_jump_1", &"stunt_jump_2", &"stunt_jump_3"]
const MIN_SPEED := 8.0
const MIN_AIR := 0.5
const MIN_DIST := 10.0
const RAMP_LEN := 12.0
const LAND_RADIUS := {&"stunt_jump_1": 22.0, &"stunt_jump_2": 22.0, &"stunt_jump_3": 32.0}
const FIRST_CASH := 400
const REPEAT_CASH := 60

enum Stage { NONE, ARMED, AIR }

var jumps: Array = []                          # {id, pos, dir, right, land, radius, index}
var stage: Stage = Stage.NONE
var cur := -1
var _armed_t := 0.0
var _air_t := 0.0
var _ground_t := 0.0
var _launch := Vector3.ZERO
var _launch_speed := 0.0
var _rot := 0.0
var _max_h := 0.0
var _toast_cd := 0.0
var last_result: Dictionary = {}
var test_mode := false                         # tests drive the detector with poll_vehicle()


func _init() -> void:
	id = &"stunt_jumps"
	title = "Stunt Jumps"
	kind = Kind.JUMP
	accent = GC.COL_ACCENT2
	passive = true
	marker_radius = 2.2
	description = "Hit the ramps fast and land safely."


func setup_activity() -> void:
	jumps.clear()
	var n := 0
	for jid in JUMP_IDS:
		var loc: Dictionary = WorldLayout.get_location(jid)
		if loc.is_empty() or not loc.has("land"):
			continue
		n += 1
		var dir := Util.yaw_to_dir(float(loc["yaw"]))
		jumps.append({
			"id": jid, "index": n, "pos": loc["pos"], "dir": dir, "right": Vector3(-dir.z, 0, dir.x),
			"land": loc["land"], "radius": float(LAND_RADIUS.get(jid, 22.0)),
		})


func marker_spots() -> Array:
	var out: Array = []
	for j in jumps:
		var p: Vector3 = j["pos"] - (j["dir"] as Vector3) * 5.0
		out.append(Vector3(p.x, WorldLayout.terrain_height(p.x, p.z) + 0.05, p.z))
	return out


func poll_passive(dt: float) -> bool:
	_toast_cd = maxf(_toast_cd - dt, 0.0)
	var p := player()
	if p == null:
		_reset()
		return false
	var v = p.get("current_vehicle")
	if v == null or not is_instance_valid(v):
		_reset()
		return false
	poll_vehicle(v, dt)
	return false


## Detector step for one vehicle (the player's). Also driven directly by tests.
func poll_vehicle(v: Node, dt: float) -> void:
	var vc = v.get("vclass")
	if vc != GC.VC_CAR and vc != GC.VC_BIKE:
		_reset()
		return
	var pos: Vector3 = (v as Node3D).global_position
	var vel: Vector3 = v.get("linear_velocity") if v.get("linear_velocity") != null else Vector3.ZERO
	var grounded := _is_grounded(v)
	match stage:
		Stage.NONE:
			for j in jumps:
				var local: Vector3 = pos - (j["pos"] as Vector3)
				var along := local.dot(j["dir"])
				var lateral := absf(local.dot(j["right"]))
				var hv := Vector3(vel.x, 0, vel.z)
				if along > -4.0 and along < RAMP_LEN + 2.0 and lateral < 4.5 and hv.length() >= MIN_SPEED \
						and hv.normalized().dot(j["dir"]) > 0.6 and grounded:
					stage = Stage.ARMED
					cur = int(jumps.find(j))
					_armed_t = 0.0
					_launch_speed = hv.length()
					break
		Stage.ARMED:
			_armed_t += dt
			var j: Dictionary = jumps[cur]
			var along2 := (pos - (j["pos"] as Vector3)).dot(j["dir"])
			var hv2 := Vector3(vel.x, 0, vel.z)
			_launch_speed = maxf(_launch_speed * 0.9, hv2.length())
			_air_acc = _air_acc + dt if not grounded else 0.0
			if not grounded and along2 > 5.0 and _air_acc > 0.1:
				stage = Stage.AIR
				_air_t = 0.0
				_ground_t = 0.0
				_rot = 0.0
				_launch = pos
				_max_h = pos.y
			elif _armed_t > 3.5 or along2 > RAMP_LEN + 25.0 or along2 < -8.0 or hv2.length() < 4.0:
				_reset()
		Stage.AIR:
			_air_t += dt
			var angv: Vector3 = v.get("angular_velocity") if v.get("angular_velocity") != null else Vector3.ZERO
			_rot += angv.length() * dt
			_max_h = maxf(_max_h, pos.y)
			var landed: bool = grounded or float(v.get("water_depth") if v.get("water_depth") != null else 0.0) > 0.25 or v.get("is_destroyed") == true
			_ground_t = _ground_t + dt if landed else 0.0
			if _ground_t >= 0.18 or _air_t > 12.0:
				_evaluate(v, pos)


var _air_acc := 0.0


func _is_grounded(v: Node) -> bool:
	var gc = v.get("grounded_count")
	if gc != null:
		return int(gc) >= (1 if v.get("vclass") == GC.VC_BIKE else 2)
	var node := v as Node3D
	return Util.raycast(node, node.global_position + Vector3.UP * 0.2, node.global_position + Vector3.DOWN * 1.2, GC.M_GROUND, [v]).size() > 0


func _reset() -> void:
	stage = Stage.NONE
	cur = -1
	_armed_t = 0.0
	_air_t = 0.0
	_ground_t = 0.0
	_air_acc = 0.0


func _evaluate(v: Node, pos: Vector3) -> void:
	var j: Dictionary = jumps[cur]
	var dist := Util.dist_xz(pos, _launch)
	var air := _air_t
	var up_y: float = (v as Node3D).global_transform.basis.y.y
	var destroyed: bool = v.get("is_destroyed") == true
	var in_zone := Util.dist_xz(pos, j["land"]) <= float(j["radius"])
	var upright := up_y > 0.45
	var jid: StringName = j["id"]
	var res := {"id": jid, "dist": dist, "air": air, "rot": _rot, "upright": upright, "in_zone": in_zone, "destroyed": destroyed, "ok": false}
	if air >= MIN_AIR and dist >= MIN_DIST:
		if in_zone and upright and not destroyed:
			res["ok"] = true
			_reward(j, res, v)
		elif _toast_cd <= 0.0:
			_toast_cd = 4.0
			var msg := "Stunt jump failed: land upright inside the landing area." if not destroyed else "Stunt jump failed: vehicle destroyed."
			Events.notification.emit(msg, &"warn")
			say(msg, 2.5)
	last_result = res
	_reset()


func _reward(j: Dictionary, res: Dictionary, v: Node) -> void:
	var flag := "stunt_first_%d" % int(j["index"])
	var first := not bool(sys.flags.get(flag, false))
	sys.flags[flag] = true
	var rot_turns := float(res["rot"]) / TAU
	var score := int(round(float(res["dist"]) * 10.0 + float(res["air"]) * 100.0 + minf(rot_turns, 3.0) * 80.0 + float((v as Node3D).global_transform.basis.y.y) * 40.0))
	var cash := FIRST_CASH if first else REPEAT_CASH
	res["score"] = score
	res["first"] = first
	res["cash"] = cash
	var key := "stunt:%d" % int(j["index"])
	var prev: Dictionary = sys.best.get(key, {})
	var is_best := prev.is_empty() or float(score) > float(prev["value"])
	sys.complete_passive(self, {"key": key, "value": float(score), "medal": "none", "cash": cash, "skill": {"driving": 14.0 if first else 6.0}})
	var msg := "Stunt jump! %d m, %.1f s airtime, %d pts%s" % [int(round(float(res["dist"]))), float(res["air"]), score, "  (+$%d first time!)" % cash if first else "  (+$%d)" % cash]
	Events.notification.emit(msg, &"good")
	if sys.hud != null:
		sys.hud.banner("STUNT JUMP!  %d m" % int(round(float(res["dist"]))), 2.8, ActivityHud.COL_GOLD)
		sys.hud.popup("+%d" % score, ActivityHud.COL_GOLD, Vector2(-1, -1), 44)
		if is_best and not prev.is_empty():
			sys.hud.popup("NEW BEST", GC.COL_ACCENT2, Vector2(960, 420), 30)
