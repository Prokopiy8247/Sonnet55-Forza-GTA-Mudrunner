class_name ActivityRace
extends ActivityBase
## Street race: 2 laps of the Halcyon Ring (arterial, ~830 m per lap) through race_checkpoint rings (next ring bright, next-next dim),
## 3-2-1 countdown with beeps, finish_line_banner on the start line, lap/checkpoint counters, split popups, medals by time, soft route
## rules (flipped car is put back on its wheels with +5 s, far off the route shows a warning and ends the race after 25 s).
## The route is built from the `Halcyon Ring` road polylines (WorldLayout.roads), so it is lane/road based by construction.

const LAPS := 2
const CP_SPACING := 80.0
const PASS_RADIUS := 11.0
const PASS_DY := 7.0
const RING_SCALE := 1.6
const LOANS := {
	"sports": {"vehicle": &"sports", "name": "Sports car", "desc": "Fast and grippy"},
	"muscle": {"vehicle": &"muscle", "name": "Muscle car", "desc": "Powerful, loose rear"},
	"motorcycle": {"vehicle": &"motorcycle", "name": "Motorcycle", "desc": "Quick, nimble, risky"},
}
const CASH := [100, 200, 350, 500]
## Medal times (seconds) = lap_length * LAPS / average speed + 1 s; tuned against the driving bot of activity_test.gd --part=race (clean 2 laps ~ 77 s at <= 22 m/s)
const GOLD_SPEED := 21.5
const SILVER_SPEED := 17.5
const BRONZE_SPEED := 13.8

var route: Array[Vector3] = []                 # checkpoint centres of ONE lap (index 0 = start/finish line)
var route_dirs: Array[Vector3] = []
var lap_length := 0.0
var start_xf := Transform3D.IDENTITY
var target_i := 0                              # index into the full sequence (0 .. total-1)
var total := 0
var race_time := 0.0
var penalty := 0.0
var vehicle: Node = null
var loaned := false
var times: Array[float] = []
var banner_node: Node3D = null
var rings: Array[Node3D] = []
var _ring_mats: Array[Material] = []
var _off_route_t := 0.0
var _left_vehicle_t := 0.0
var _flip_t := 0.0
var _last_cp_xf := Transform3D.IDENTITY
var _gold := 0.0
var _silver := 0.0
var _bronze := 0.0


func _init() -> void:
	id = &"street_race"
	title = "Ring Street Race"
	kind = Kind.RACE
	accent = GC.COL_ACCENT2
	description = "%d laps of the Halcyon Ring through the checkpoint rings. A car or bike is provided. Hold E to quit." % LAPS
	countdown_seconds = 3
	interact_range = 3.4
	marker_radius = 1.7
	for k in LOANS:
		options.append({"id": k, "name": LOANS[k]["name"], "desc": LOANS[k]["desc"]})


# ---- route ---------------------------------------------------------------------------------------------------------------------
## Closed loop of the Halcyon Ring centre line (Array[Vector3] at 8 m spacing, y = road) chained from the road segments.
static func ring_polyline() -> Array[Vector3]:
	var segs: Array = []
	for r in WorldLayout.roads:
		if str(r["name"]) == "Halcyon Ring":
			segs.append(r["points"])
	var out: Array[Vector3] = []
	if segs.is_empty():
		return out
	var used := {}
	var cur: PackedVector2Array = segs[0]
	used[0] = true
	for p in cur:
		out.append(Vector3(p.x, 0.04, p.y))
	var guard := 0
	while used.size() < segs.size() and guard < 40:
		guard += 1
		var end: Vector2 = Vector2(out[out.size() - 1].x, out[out.size() - 1].z)
		var found := false
		for i in segs.size():
			if used.has(i):
				continue
			var s: PackedVector2Array = segs[i]
			if s.size() < 2:
				used[i] = true
				continue
			if s[0].distance_to(end) < 1.5:
				for k in range(1, s.size()):
					out.append(Vector3(s[k].x, 0.04, s[k].y))
				used[i] = true
				found = true
				break
			elif s[s.size() - 1].distance_to(end) < 1.5:
				for k in range(s.size() - 2, -1, -1):
					out.append(Vector3(s[k].x, 0.04, s[k].y))
				used[i] = true
				found = true
				break
		if not found:
			break
	return out


static func build_route(poly: Array[Vector3], start_near: Vector3) -> Dictionary:
	# rotate so that index 0 is the polyline point nearest to start_near
	var best_i := 0
	var best_d := INF
	for i in poly.size():
		var d := Util.dist_xz(poly[i], start_near)
		if d < best_d:
			best_d = d
			best_i = i
	var pts: Array[Vector3] = []
	for k in poly.size():
		pts.append(poly[(best_i + k) % poly.size()])
	# arc length, then a checkpoint every CP_SPACING
	var cps: Array[Vector3] = [pts[0]]
	var acc := 0.0
	var total_len := 0.0
	var next_at := CP_SPACING
	for k in range(1, pts.size() + 1):
		var a: Vector3 = pts[k - 1]
		var b: Vector3 = pts[k % pts.size()]
		var seg := Util.dist_xz(a, b)
		total_len += seg
		acc += seg
		if acc >= next_at and k < pts.size():
			cps.append(b)
			next_at += CP_SPACING
	# do not keep a last checkpoint closer than 40 m to the start
	while cps.size() > 2 and Util.dist_xz(cps[cps.size() - 1], cps[0]) < 40.0:
		cps.pop_back()
	var dirs: Array[Vector3] = []
	for i in cps.size():
		var d := cps[(i + 1) % cps.size()] - cps[i]
		dirs.append(Vector3(d.x, 0, d.z).normalized())
	return {"cps": cps, "dirs": dirs, "length": total_len}


func setup_activity() -> void:
	var poly := ring_polyline()
	if poly.size() < 20:
		push_warning("ActivityRace: Halcyon Ring polyline missing - race disabled")
		return
	var info := build_route(poly, Vector3(105.0, 0.0, -45.0))
	route = info["cps"]
	route_dirs = info["dirs"]
	lap_length = float(info["length"])
	total = route.size() * LAPS
	_gold = lap_length * LAPS / GOLD_SPEED + 1.0
	_silver = lap_length * LAPS / SILVER_SPEED + 1.0
	_bronze = lap_length * LAPS / BRONZE_SPEED + 1.0
	# start point on the sidewalk, 9.5 m towards the inside of the ring from the start line
	var inward := (Vector3(0.0, 0.0, 15.0) - route[0])
	inward = Vector3(inward.x, 0, inward.z).normalized()
	point_pos = route[0] + inward * 9.6
	point_pos.y = WorldLayout.terrain_height(point_pos.x, point_pos.z) + 0.15
	# start grid: on the lane graph (right-hand lane in route direction), 9 m behind the line
	var back := route[0] - route_dirs[0] * 9.0
	var li := WorldLayout.lanes.nearest(back, route_dirs[0], 12.0) if WorldLayout.lanes != null else -1
	var gp := back
	var gdir := route_dirs[0]
	if li >= 0:
		gp = WorldLayout.lanes.positions[li]
		gdir = WorldLayout.lanes.dirs[li]
		gdir = Vector3(gdir.x, 0, gdir.z).normalized()
	start_xf = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(gdir)), Vector3(gp.x, 0.2, gp.z))
	# register the map blip (WorldLayout.locations -> UIIcons.LOC `race_start`)
	WorldLayout.locations[&"race_start"] = {"pos": point_pos, "yaw": Util.dir_to_yaw(-inward), "radius": 4.0, "kind": &"activity", "name": "Ring Street Race"}
	var mk: Array[Material] = []
	for a in [0.55, 0.16]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(0.2, 0.9, 1.0, a) if a > 0.3 else Color(1.0, 0.24, 0.6, a)
		mk.append(m)
	_ring_mats = mk


func can_start(p: Node, _opts: Dictionary) -> String:
	if route.is_empty():
		return "The race is not available."
	if p == null or p.get("is_dead") == true:
		return "Not now."
	if p.has_method("is_in_vehicle") and p.is_in_vehicle():
		return "Park and step out to enter the race."
	if Game.wanted_level > 0:
		return "Lose the police first."
	return ""


func prompt_text(_p: Node) -> String:
	return "Ring Street Race"


func marker_spots() -> Array:
	return [point_pos]


func begin(opts: Dictionary) -> bool:
	var p := player()
	var oid := String(opts.get("option", "sports"))
	if not LOANS.has(oid):
		oid = "sports"
	last_option = oid
	var xf := start_xf
	vehicle = VehicleFactory.spawn(LOANS[oid]["vehicle"], xf, {"abandoned": true, "snap_ground": true, "engine_on": true})
	if vehicle == null:
		toast("Could not prepare a race vehicle.", &"warn")
		return false
	loaned = true
	p.teleport_to(xf.origin + Vector3(0, 1.0, 0), Util.dir_to_yaw(-xf.basis.z))
	await_enter.call_deferred()
	times.clear()
	target_i = 1 % maxi(route.size(), 1)
	race_time = 0.0
	penalty = 0.0
	_off_route_t = 0.0
	_left_vehicle_t = 0.0
	_flip_t = 0.0
	_last_cp_xf = xf
	_build_visuals()
	_place_rings()
	hud().begin(title, "%d laps - hold E to quit" % LAPS, accent)
	hud().set_cells([
		{"label": "Time", "value": "0:00.0", "color": GC.COL_TEXT},
		{"label": "Lap", "value": "1/%d" % LAPS, "color": GC.COL_ACCENT2},
		{"label": "Checkpoint", "value": "0/%d" % total, "color": GC.COL_TEXT},
		{"label": "Next", "value": "--", "color": GC.COL_ACCENT},
	])
	var p2 := player()
	p2.input_locked = true
	return true


func await_enter() -> void:
	var p := player()
	if p != null and vehicle != null and is_instance_valid(vehicle):
		p.enter_vehicle(vehicle, 0)


func on_go() -> void:
	var p := player()
	if p != null:
		p.input_locked = false
	race_time = 0.0
	say("GO! Follow the rings.", 2.0)


func _build_visuals() -> void:
	_free_visuals()
	banner_node = ModelLib.instance("props/finish_line_banner")
	if banner_node != null:
		Game.world.add_child(banner_node)
		banner_node.global_transform = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(route_dirs[0])), route[0])
		banner_node.scale = Vector3(1.1, 1.0, 1.0)
	else:
		push_warning("ActivityRace: props/finish_line_banner missing - no banner (logged)")
	for i in 3:
		var r := ModelLib.instance("props/race_checkpoint")
		if r == null:
			push_warning("ActivityRace: props/race_checkpoint missing - no rings (logged)")
			break
		Game.world.add_child(r)
		rings.append(r)


func _free_visuals() -> void:
	for r in rings:
		if is_instance_valid(r):
			r.queue_free()
	rings.clear()
	if banner_node != null and is_instance_valid(banner_node):
		banner_node.queue_free()
	banner_node = null


func _cp_of(seq: int) -> int:
	return seq % route.size()


func _place_rings() -> void:
	for k in rings.size():
		var seq := target_i + k
		var r := rings[k]
		if seq >= total:
			r.visible = false
			continue
		r.visible = true
		var ci := _cp_of(seq)
		var s := RING_SCALE * (1.0 if k == 0 else 0.8)
		r.global_transform = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(route_dirs[ci])) * Basis.from_scale(Vector3(s, s, 1.0)), route[ci])
		Util.replace_material(r, "RingGlow", _ring_mats[0] if k == 0 else _ring_mats[1])


func tick(dt: float, sys_state: int) -> void:
	if sys_state != ActivitySystem.State.RUNNING:
		return
	race_time += dt
	var p := player()
	var v = p.get("current_vehicle") if p != null else null
	if v == null or not is_instance_valid(v) or v != vehicle:
		_left_vehicle_t += dt
		return
	_left_vehicle_t = 0.0
	var vp: Vector3 = (v as Node3D).global_position
	var ci := _cp_of(target_i)
	var cpos := route[ci]
	if Util.dist_xz(vp, cpos) <= PASS_RADIUS and absf(vp.y - cpos.y) <= PASS_DY:
		_pass_checkpoint(ci)
	# soft route rules
	var dnext := Util.dist_xz(vp, route[_cp_of(target_i)])
	if dnext > 190.0:
		_off_route_t += dt
		if _off_route_t > 3.0 and fmod(_off_route_t, 6.0) < dt:
			hud().banner("RETURN TO THE ROUTE", 2.0, GC.COL_WARN)
	else:
		_off_route_t = 0.0
	if v.has_method("is_flipped_over") and v.is_flipped_over():
		_flip_t += dt
		if _flip_t > 2.5:
			_flip_t = 0.0
			penalty += 5.0
			if v.has_method("place_at"):
				v.place_at(Transform3D(_last_cp_xf.basis, _last_cp_xf.origin + Vector3(0, 0.6, 0)))
				v.set_velocity(Vector3.ZERO)
			hud().banner("Reset at the last checkpoint  +5 s", 2.0, GC.COL_WARN)
	else:
		_flip_t = 0.0
	# HUD
	var shown := race_time + penalty
	var h := hud()
	h.set_cell(0, "Time", ActivityHud.format_time(shown), GC.COL_TEXT)
	h.set_cell(1, "Lap", "%d/%d" % [mini(target_i / route.size() + 1, LAPS), LAPS], GC.COL_ACCENT2)
	h.set_cell(2, "Checkpoint", "%d/%d" % [target_i, total], GC.COL_TEXT)
	h.set_cell(3, "Next", "%d m" % int(dnext), GC.COL_ACCENT)
	h.set_progress(float(target_i) / float(total), accent)


func _pass_checkpoint(ci: int) -> void:
	_last_cp_xf = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(route_dirs[ci])), route[ci])
	target_i += 1
	times.append(race_time + penalty)
	play_sfx(&"chime")
	if target_i >= total:
		_finish()
		return
	if ci == 0:
		hud().banner("LAP %d/%d  %s" % [target_i / route.size() + 1, LAPS, ActivityHud.format_time(race_time + penalty)], 2.4, GC.COL_OK)
	else:
		hud().popup(ActivityHud.format_time(race_time + penalty), GC.COL_ACCENT, Vector2(-1, -1), 30)
	_place_rings()


func check_abort() -> String:
	var p := player()
	if p == null:
		return "Player lost"
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.get("is_destroyed") == true:
		return "Your vehicle was destroyed"
	if _left_vehicle_t > 4.0 and running:
		return "You left your vehicle"
	if _off_route_t > 25.0:
		return "You abandoned the route"
	return ""


func on_abort(_reason: String) -> void:
	pass


func _finish() -> void:
	var t := race_time + penalty
	var medal := medal_for(t, _gold, _silver, _bronze, false)
	var splits := ""
	for lap in LAPS:
		var idx := (lap + 1) * route.size() - 1
		if idx < times.size():
			var lt := times[idx] - (times[idx - route.size()] if lap > 0 else 0.0)
			splits += ("Lap %d %s   " % [lap + 1, ActivityHud.format_time(lt)])
	var rows: Array = [
		["Time", ActivityHud.format_time(race_time)],
		["Penalties", "+%.0f s" % penalty, GC.COL_WARN if penalty > 0.0 else GC.COL_OK],
		["Medal times", "%s / %s / %s" % [ActivityHud.format_time(_gold, false), ActivityHud.format_time(_silver, false), ActivityHud.format_time(_bronze, false)]],
		["Laps", splits.strip_edges()],
	]
	finish_activity({
		"key": "race:ring:" + last_option, "value": t, "higher_better": false, "medal": medal,
		"cash": cash_for(medal, CASH), "skill": {"driving": minf(t / 3.0, 40.0)},
		"title": title, "subtitle": "%s - %d laps" % [LOANS[last_option]["name"], LAPS],
		"main": ActivityHud.format_time(t), "rows": rows, "hint": "Press E to continue",
	})


func cleanup() -> void:
	_free_visuals()
	var p := player()
	if p != null:
		p.input_locked = false
		if p.has_method("is_in_vehicle") and p.is_in_vehicle():
			p.exit_vehicle(true)
	if vehicle != null and is_instance_valid(vehicle) and loaned:
		VehicleFactory.despawn(vehicle)
	vehicle = null
	if p != null and point_pos != Vector3.ZERO:
		p.teleport_to(point_pos + Vector3(0, 0.3, 0))


## Test hooks.
func medal_times() -> Array:
	return [_gold, _silver, _bronze]
