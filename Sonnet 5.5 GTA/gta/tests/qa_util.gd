extends RefCounted
## Shared helpers of the QA scenario tests (gta/tests/qa_*.gd). Usage:
##   const Q := preload("res://gta/tests/qa_util.gd")
##   var q := Q.new(self)            # self = the test Node (needs to be in the tree)
##   await q.seconds(2.0); q.check("name", ok, "detail"); print(q.summary())
## Nothing here is game code: it only drives / inspects the real systems.

var node: Node
var passed := 0
var failed := 0
var errors_seen: Array[String] = []


func _init(n: Node) -> void:
	node = n


func check(name: String, ok: bool, detail: String = "") -> bool:
	if ok:
		passed += 1
	else:
		failed += 1
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])
	return ok


func info(msg: String) -> void:
	print("TEST info ", msg)


func frames(n: int) -> void:
	for i in n:
		await node.get_tree().physics_frame


func seconds(s: float) -> void:
	await frames(int(s * 60.0))


func summary() -> String:
	return "passed=%d failed=%d" % [passed, failed]


## true when the user arg --only is absent or contains `name`
func only(name: String) -> bool:
	var want := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			want = String(a).substr(7)
	return want == "" or want.split(",").has(name)


func arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + name + "="):
			return s.substr(name.length() + 3)
	return default


# ---- world / player helpers ------------------------------------------------------------------------------------------------
func player() -> Node:
	return Game.player


func wanted() -> Node:
	return Game.sys(&"wanted")


func police() -> Node:
	return Game.sys(&"police")


## Teleport the player to the road surface near `xz` (ground snapped by the player's own guard). Returns the real position.
func tp_player(pos: Vector3, yaw_deg: float = 0.0) -> Vector3:
	var p = Game.player
	if p == null:
		return pos
	if p.is_in_vehicle():
		p.exit_vehicle(true)
	p.teleport_to(pos, deg_to_rad(yaw_deg))
	return pos


func nearest_vehicle(pos: Vector3, max_d: float = 40.0, ids: Array = []) -> VehicleBase:
	var best: VehicleBase = null
	var bd := max_d
	for v in node.get_tree().get_nodes_in_group(GC.G_VEHICLE):
		var vb := v as VehicleBase
		if vb == null or vb.is_destroyed or vb.is_ai_controlled or (vb.driver != null and vb.driver != Game.player):
			continue
		if not ids.is_empty() and not ids.has(vb.def_id):
			continue
		var d := vb.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = vb
	return best


## Spawn a drivable car in front of the player on the nearest lane point (so it stands on a road), return it.
func spawn_car(id: StringName, near: Vector3, opts: Dictionary = {}) -> VehicleBase:
	var li := WorldLayout.lanes.nearest(near, Vector3.ZERO, 60.0)
	var xf := Transform3D(Basis.IDENTITY, near + Vector3(0, 0.6, 0))
	if li >= 0:
		var lp: Vector3 = WorldLayout.lanes.positions[li]
		var d: Vector3 = WorldLayout.lanes.dirs[li]
		xf = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(d)), lp + Vector3(0, 0.6, 0))
	var o := {"abandoned": true}
	o.merge(opts, true)
	return VehicleFactory.spawn(id, xf, o)


func foot_officers() -> Array:
	var out: Array = []
	for o in PoliceUnits.officers():
		var po := o as PoliceOfficer
		if po != null and is_instance_valid(po) and not po.is_in_vehicle() and not po.is_dead:
			out.append(po)
	return out


func police_summary() -> String:
	var foot := 0
	var seated := 0
	var engaged := 0
	for o in PoliceUnits.officers():
		var po := o as PoliceOfficer
		if po.is_in_vehicle():
			seated += 1
		else:
			foot += 1
			if po.brain.is_engaged():
				engaged += 1
	return "L%d/%s cars=%d officers=%d (foot=%d seated=%d engaged=%d)" % [Game.wanted_level, String(Game.wanted_state), PoliceUnits.count_cars(), PoliceUnits.count_officers(), foot, seated, engaged]


## Frame time recorder: call tick(delta) from a loop, then percentiles().
class FrameStats:
	var samples := PackedFloat32Array()

	func tick(delta_ms: float) -> void:
		samples.append(delta_ms)

	func percentiles() -> Dictionary:
		if samples.is_empty():
			return {}
		var s := samples.duplicate()
		s.sort()
		var n := s.size()
		var sum := 0.0
		for x in s:
			sum += x
		return {"n": n, "avg": sum / n, "p50": s[int(n * 0.5)], "p90": s[int(n * 0.9)], "p99": s[mini(int(n * 0.99), n - 1)], "max": s[n - 1]}
