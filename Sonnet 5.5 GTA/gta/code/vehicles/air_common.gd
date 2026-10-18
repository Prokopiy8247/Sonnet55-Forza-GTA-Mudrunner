class_name AirCommon
extends RefCounted
## Shared helpers of the air / sea vehicles (Air&Sea agent): landing-gear / skid raycast suspension with tyre friction,
## static load distribution, altitude-above-ground queries, surface classification, water level + wave height (matches
## generated/shaders/world_water.gdshader), airspace limits, skills hooks, collision-box info for the factory.
## Everything is static or a tiny data class; the vehicles own the state.

const RHO := 1.225
const AIRSPACE_WARN := 900.0          # m from the map centre: "Leaving airspace" notification
const AIRSPACE_ALERT := 1500.0
const AIRSPACE_KILL := 2500.0         # hard teleport back inside

static var _ray: PhysicsRayQueryParameters3D = null
static var _warn_cd := 0.0


## One landing-gear leg: raycast suspension + wheel (or isotropic skid for helicopters).
class Gear:
	extends RefCounted
	var name: StringName = &""
	var node: Node3D = null              # visual wheel (spins / steers), may be null
	var node_basis := Basis.IDENTITY
	var node_pos := Vector3.ZERO         # wheel centre at rest (vehicle space)
	var top := Vector3.ZERO              # ray origin = strut top, vehicle space
	var radius := 0.0                    # wheel radius (0 = skid / pad)
	var travel := 0.3                    # max length top -> wheel centre
	var rest_len := 0.12                 # length at static equilibrium
	var free_len := 0.2
	var k := 50000.0
	var c := 5000.0
	var steered := false
	var braked := true
	var skid := false                    # isotropic sliding friction (helicopter skid)
	var share := 0.25                    # static load share 0..1
	# dynamic
	var length := 0.3
	var prev_length := 0.3
	var grounded := false
	var fn := 0.0
	var contact := Vector3.ZERO
	var normal := Vector3.UP
	var spin := 0.0
	var w := 0.0
	var steer_angle := 0.0
	var surface: StringName = &"asphalt"
	var surface_mult := 1.0
	var collider_id := 0
	var was_grounded := false
	var slip := 0.0


# =====================================================================================================
# Gear construction
# =====================================================================================================
static func make_gear(gname: StringName, top: Vector3, wheel_radius: float, travel: float, rest_len: float, node: Node3D = null) -> Gear:
	var g := Gear.new()
	g.name = gname
	g.top = top
	g.radius = wheel_radius
	g.travel = travel
	g.rest_len = rest_len
	g.length = rest_len
	g.prev_length = rest_len
	g.node = node
	if node != null:
		g.node_basis = node.transform.basis
		g.node_pos = node.transform.origin
	g.skid = wheel_radius <= 0.001
	return g


## Static load shares (sum 1) from the positions of the contact points and the centre of mass.
## 3 gears: exact solve of force + both moment balances; 4 gears: front / rear pair lever rule, left / right equal.
static func static_shares(gears: Array, com: Vector3) -> void:
	var n := gears.size()
	if n == 0:
		return
	if n == 3:
		var a: Gear = gears[0]
		var b: Gear = gears[1]
		var c: Gear = gears[2]
		var m := Basis(Vector3(1, 1, 1), Vector3(a.top.x, b.top.x, c.top.x), Vector3(a.top.z, b.top.z, c.top.z))
		# Basis columns are the vectors above; we need them as ROWS -> transpose
		var mt := m.transposed()
		if absf(mt.determinant()) > 1e-4:
			var f := mt.inverse() * Vector3(1.0, com.x, com.z)
			a.share = clampf(f.x, 0.05, 0.9)
			b.share = clampf(f.y, 0.05, 0.9)
			c.share = clampf(f.z, 0.05, 0.9)
			var s := a.share + b.share + c.share
			a.share /= s
			b.share /= s
			c.share /= s
			return
	var zmin := INF
	var zmax := -INF
	for g in gears:
		zmin = minf(zmin, (g as Gear).top.z)
		zmax = maxf(zmax, (g as Gear).top.z)
	var zmid := (zmin + zmax) * 0.5
	var n_front := 0
	var n_rear := 0
	for g in gears:
		if (g as Gear).top.z < zmid:
			n_front += 1
		else:
			n_rear += 1
	var span := maxf(zmax - zmin, 0.1)
	var rear_total := clampf((com.z - zmin) / span, 0.1, 0.9)
	for g in gears:
		var gg := g as Gear
		if gg.top.z < zmid:
			gg.share = (1.0 - rear_total) / maxf(float(n_front), 1.0)
		else:
			gg.share = rear_total / maxf(float(n_rear), 1.0)


## Spring rates from the shares: natural frequency `freq` Hz, damping ratio `zeta`.
static func tune_springs(gears: Array, total_mass: float, gravity: float, freq: float, zeta: float) -> void:
	for g in gears:
		var gg := g as Gear
		var m_w := maxf(total_mass * gg.share, 20.0)
		var omega := TAU * freq
		gg.k = m_w * omega * omega
		gg.c = 2.0 * zeta * sqrt(gg.k * m_w)
		var x0 := m_w * gravity / gg.k
		gg.free_len = gg.rest_len + x0


# =====================================================================================================
# Gear simulation
# =====================================================================================================
## One physics tick of every gear. p keys: mu (tyre friction), roll (rolling resistance coef), brake (0..1), brake_decel (m/s^2),
## steer (rad, + right), hold (stationary hold), lift (0..1: how close to the CoM height the friction acts), dust (bool).
## Returns {"f": Vector3, "t": Vector3, "grounded": int, "max_fn": float, "touchdown": float (sink rate, only on the tick a
## leg touches after being airborne, else 0)}.
static func step_gears(v: VehicleBase, gears: Array, dt: float, q: PhysicsRayQueryParameters3D, p: Dictionary) -> Dictionary:
	var xf := v.global_transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var right := xf.basis.x
	var com_w := xf * v.center_of_mass
	var lv := v.linear_velocity
	var av := v.angular_velocity
	var space := v.get_world_3d().direct_space_state
	var inv_dt := 1.0 / dt
	var m_eff := v.mass / float(maxi(gears.size(), 1))
	var mu_base: float = p.get("mu", 0.8)
	var roll: float = p.get("roll", 0.03)
	var brake: float = p.get("brake", 0.0)
	var brake_decel: float = p.get("brake_decel", 6.0)
	var steer: float = p.get("steer", 0.0)
	var hold: bool = p.get("hold", false)
	var lift: float = p.get("lift", 0.7)
	var tot_f := Vector3.ZERO
	var tot_t := Vector3.ZERO
	var grounded := 0
	var max_fn := 0.0
	var touchdown := 0.0
	for g in gears:
		var gg := g as Gear
		var top_w := xf * gg.top
		q.from = top_w
		q.to = top_w - up * (gg.travel + gg.radius)
		var hit := space.intersect_ray(q)
		gg.was_grounded = gg.grounded
		if hit.is_empty():
			gg.grounded = false
			gg.length = move_toward(gg.length, gg.travel, 1.4 * dt)
			gg.prev_length = gg.length
			gg.fn = 0.0
			gg.slip = 0.0
			continue
		var cpos: Vector3 = hit.position
		var d := top_w.distance_to(cpos)
		var len_ := clampf(d - gg.radius, 0.0, gg.travel)
		var cid: int = hit.collider_id
		if cid != gg.collider_id:
			gg.collider_id = cid
			gg.surface = surface_of(hit.collider)
			gg.surface_mult = float(SURFACE_MU.get(gg.surface, 1.0))
		var comp_speed := 0.0
		if gg.was_grounded:
			comp_speed = clampf((gg.prev_length - len_) * inv_dt, -6.0, 6.0)
		else:
			# first contact: the sink rate decides the landing quality
			touchdown = maxf(touchdown, -lv.dot(up))
		var f_spring := gg.k * maxf(gg.free_len - len_, 0.0)
		if len_ < 0.03:
			f_spring += gg.k * (2.5 * (0.03 - len_) + 5.0 * maxf(0.015 - len_, 0.0))      # bump stop
		var f_damp := gg.c * comp_speed
		gg.fn = maxf(f_spring + f_damp, 0.0)
		gg.length = len_
		gg.prev_length = len_
		gg.contact = cpos
		gg.normal = hit.normal
		gg.grounded = true
		grounded += 1
		max_fn = maxf(max_fn, gg.fn)
		# ---- friction -----------------------------------------------------------------------------------------------
		var n: Vector3 = hit.normal
		var vpt := lv + av.cross(cpos - com_w)
		var mu := mu_base * gg.surface_mult
		var fmax := mu * gg.fn
		var f_trac := Vector3.ZERO
		if gg.skid:
			var vt := vpt - n * vpt.dot(n)
			var sp := vt.length()
			if sp > 1e-4:
				var need := sp * m_eff * inv_dt * 0.55
				f_trac = -vt / sp * minf(need, fmax)
			gg.slip = clampf(sp / 6.0, 0.0, 1.0)
		else:
			var wf_dir := fwd
			if gg.steered:
				wf_dir = fwd * cos(steer) + right * sin(steer)
				gg.steer_angle = steer
			var wf := (wf_dir - n * wf_dir.dot(n)).normalized()
			var wr := wf.cross(n)
			var vf := vpt.dot(wf)
			var vl := vpt.dot(wr)
			var fx := 0.0
			var vstop := absf(vf) * m_eff * inv_dt
			var rr := roll * gg.fn * (1.0 + (1.0 - gg.surface_mult) * 3.0)
			fx -= signf(vf) * minf(rr, vstop)
			if gg.braked and brake > 0.01:
				fx -= signf(vf) * minf(minf(brake * brake_decel * m_eff, fmax * 0.92), vstop)
			if hold and absf(vf) < 1.5:
				fx -= vf * m_eff * inv_dt * 0.5
			fx = clampf(fx, -fmax, fmax)
			var fy_avail := sqrt(maxf(fmax * fmax - fx * fx, 0.0))
			var fy := -clampf(vl * m_eff * inv_dt * 0.75, -fy_avail, fy_avail)
			f_trac = wf * fx + wr * fy
			gg.slip = clampf(absf(vl) / (absf(vf) + 4.0) * 2.0, 0.0, 1.0)
			# wheel spin: follows the ground unless braked hard
			var w_ground := vf / maxf(gg.radius, 0.1)
			if brake > 0.6 and gg.braked:
				gg.w = move_toward(gg.w, 0.0, 60.0 * dt)
			else:
				gg.w = lerpf(gg.w, w_ground, minf(1.0, dt * 20.0))
		var spring_f := up * gg.fn
		var mount := xf * (gg.top - Vector3.UP * gg.length)
		var lift_pt := cpos + up * ((com_w - cpos).dot(up) * lift)
		tot_f += spring_f + f_trac
		tot_t += (mount - com_w).cross(spring_f) + (lift_pt - com_w).cross(f_trac)
	return {"f": tot_f, "t": tot_t, "grounded": grounded, "max_fn": max_fn, "touchdown": touchdown}


const SURFACE_MU := {
	&"road": 1.0, &"asphalt": 1.0, &"concrete": 1.0, &"metal": 0.9, &"wood": 0.9, &"grass": 0.72, &"dirt": 0.8,
	&"gravel": 0.75, &"sand": 0.62, &"mud": 0.55, &"snow": 0.5, &"rock": 0.95,
}


static func surface_of(collider: Object) -> StringName:
	if collider == null:
		return &"asphalt"
	var n: Object = collider
	for i in 3:
		if n is Node and (n as Node).has_meta(&"surface"):
			return StringName(String((n as Node).get_meta(&"surface")))
		if n is Node and (n as Node).get_parent() != null:
			n = (n as Node).get_parent()
		else:
			break
	if collider is Node:
		var nm := String((collider as Node).name).to_lower()
		if nm.contains("sand") or nm.contains("beach"):
			return &"sand"
		if nm.contains("grass") or nm.contains("park") or nm.contains("lawn"):
			return &"grass"
		if nm.contains("dirt") or nm.contains("hill") or nm.contains("terrain"):
			return &"dirt"
	return &"asphalt"


# =====================================================================================================
# Ground / water queries
# =====================================================================================================
static func ray_query() -> PhysicsRayQueryParameters3D:
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collision_mask = GC.M_GROUND
	return _ray


## Straight-down probe from `from`. Returns {"y": ground height or -INF, "surface": StringName, "normal": Vector3, "water": bool,
## "dist": metres to the hit (INF = nothing)}. Water counts when the point is over the sea and nothing solid is above the surface.
static func probe_down(node: Node3D, from: Vector3, max_dist: float = 400.0, exclude: Array = []) -> Dictionary:
	var out := {"y": -INF, "surface": &"", "normal": Vector3.UP, "water": false, "dist": INF}
	if node == null or not node.is_inside_tree():
		return out
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * max_dist, GC.M_GROUND)
	var rids: Array[RID] = []
	for e in exclude:
		if e is CollisionObject3D:
			rids.append(e.get_rid())
	q.exclude = rids
	var hit := node.get_world_3d().direct_space_state.intersect_ray(q)
	var water_y := GC.WATER_LEVEL
	var over_water := WorldLayout.is_water(from.x, from.z)
	if not hit.is_empty():
		var hp: Vector3 = hit.position
		if over_water and hp.y < water_y and from.y > water_y:
			out["y"] = water_y
			out["surface"] = &"water"
			out["water"] = true
			out["dist"] = from.y - water_y
			return out
		out["y"] = hp.y
		out["surface"] = surface_of(hit.collider)
		out["normal"] = hit.normal
		out["dist"] = from.y - hp.y
		return out
	if over_water and from.y > water_y:
		out["y"] = water_y
		out["surface"] = &"water"
		out["water"] = true
		out["dist"] = from.y - water_y
	return out


## Sea surface height at (x, z): GC.WATER_LEVEL plus the shader's wave displacement. `t` is the clock the visuals use
## (TIME of the water shader ~ seconds since start); the CPU clock is close enough for floating bodies.
static func wave_height(x: float, z: float, t: float, rain: float = 0.0, wave_amp: float = 0.12) -> float:
	var open_sea := lerpf(0.22, 1.0, smoothstep(165.0, 250.0, z))
	if z < 100.0:
		open_sea = 0.15
	var amp := wave_amp * open_sea * (1.0 + rain * 1.4)
	var h := sin((x * 0.92 + z * 0.38) * 0.30 + t * 0.85)
	h += 0.6 * sin((x * -0.42 + z * 0.91) * 0.52 + t * 1.25 + 1.7)
	h += 0.35 * sin((x * 0.71 - z * 0.70) * 1.05 + t * 1.85 + 4.0)
	return h * 0.5 * amp


static func water_surface(x: float, z: float) -> float:
	if not WorldLayout.is_water(x, z):
		return -INF
	return GC.WATER_LEVEL + wave_height(x, z, Time.get_ticks_msec() * 0.001, Game.rain_intensity)


## Altitude above the ground / sea under the vehicle (metres) - cheap enough for 10-20 Hz.
static func agl_of(node: Node3D, exclude: Array = []) -> float:
	var r := probe_down(node, node.global_position + Vector3.UP * 0.5, 800.0, exclude)
	if r["dist"] == INF:
		return 800.0
	return float(r["dist"]) - 0.5


## Finds a flat, obstacle-free spot for a helicopter near `center` (rooftop helipads are cluttered by air-conditioners, tanks, stair
## blocks): every sample of the 3 x 5 m skid footprint must hit the same level (+-0.1 m) and 8 horizontal rays at hub height (rotor radius
## `rotor_r`) must be free. Candidates are tried on rings (0, 3, 6 ... `search` m) around the centre. Returns the ground point or Vector3.INF.
static func find_clear_pad(node: Node, center: Vector3, rotor_r: float = 5.5, search: float = 24.0, rise: float = 10.0) -> Vector3:
	if node == null or not node.is_inside_tree():
		return Vector3.INF
	var space := node.get_viewport().world_3d.direct_space_state
	var mask := GC.L_WORLD | GC.L_PROP
	var ring := 0.0
	while ring <= search:
		var n := 1 if ring == 0.0 else int(ceil(TAU * ring / 3.0))
		for i in n:
			var a := TAU * float(i) / float(n)
			var c := Vector3(center.x + cos(a) * ring, center.y, center.z + sin(a) * ring)
			var base := _clear_level(space, c, mask, rise)
			if not is_nan(base):
				# rotor disc clearance: horizontal rays at hub height
				var hub := Vector3(c.x, base + 3.1, c.z)
				var free := true
				for k in 8:
					var d := Vector3(cos(TAU * float(k) / 8.0), 0.0, sin(TAU * float(k) / 8.0))
					var q := PhysicsRayQueryParameters3D.create(hub, hub + d * rotor_r, mask)
					if not space.intersect_ray(q).is_empty():
						free = false
						break
				if free:
					return Vector3(c.x, base, c.z)
		ring += 3.0
	return Vector3.INF


static func _clear_level(space: PhysicsDirectSpaceState3D, c: Vector3, mask: int, rise: float) -> float:
	var level := NAN
	for ix in 3:
		for iz in 5:
			var p := Vector3(c.x + (float(ix) - 1.0) * 1.6, c.y + rise, c.z + (float(iz) - 2.0) * 1.4)
			var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * (rise + 14.0), mask)
			var h := space.intersect_ray(q)
			if h.is_empty():
				return NAN
			var y: float = h.position.y
			if is_nan(level):
				level = y
			elif absf(y - level) > 0.1:
				return NAN
	return level


# =====================================================================================================
# Wind / skills / airspace
# =====================================================================================================
## Wind in m/s (Game.wind is a unit-less vector: x east, z south; storms strengthen it).
static func wind_ms() -> Vector3:
	var w: Vector3 = Game.wind
	var k := 3.0
	if Game.weather == GC.W_STORM:
		k = 7.0
	elif Game.weather == GC.W_RAIN:
		k = 4.5
	return Vector3(w.x, 0.0, w.z) * k


## Handling-penalty multiplier from the flying skill (1.0 = untrained, 0.65 = master).
static func stability_mult() -> float:
	var s = Game.sys(&"skills")
	if s != null and s.has_method("get_modifier"):
		return float(s.get_modifier(&"aircraft_stability"))
	if s != null and s.has_method("get_skill01"):
		return 1.0 - 0.35 * float(s.get_skill01(&"flying"))
	return 1.0


static func record_flying(amount: float) -> void:
	var s = Game.sys(&"skills")
	if s != null and s.has_method("record"):
		s.record(&"flying", amount)


static func notify(text: String, kind: StringName = &"warn") -> void:
	Events.notification.emit(text, kind)


## Airspace limits for a player-flown aircraft: warning toasts beyond AIRSPACE_WARN, hard return beyond AIRSPACE_KILL.
## Returns the distance from the map centre. `acc` is the caller's per-vehicle cooldown (seconds), returned updated via dict.
static func airspace_tick(v: VehicleBase, dt: float, st: Dictionary) -> float:
	var p := v.global_position
	var d := Vector2(p.x, p.z).length()
	st["cd"] = float(st.get("cd", 0.0)) - dt
	var pilot = v.driver
	var is_player: bool = pilot != null and is_instance_valid(pilot) and pilot.has_method("is_player") and pilot.is_player()
	if not is_player:
		return d
	if d > AIRSPACE_KILL:
		var dir_in := Vector3(-p.x, 0.0, -p.z).normalized()
		var newp := Vector3(dir_in.x * -700.0, maxf(p.y, 160.0), dir_in.z * -700.0)
		# land back inside the island facing the centre
		var xf := Transform3D(Basis.looking_at(dir_in, Vector3.UP), newp)
		var speed := maxf(v.linear_velocity.length(), 25.0)
		v.global_transform = xf
		v.linear_velocity = dir_in * speed
		v.angular_velocity = Vector3.ZERO
		v._skip_dv = 3
		notify("Airspace limit reached - you were turned around", &"bad")
		st["cd"] = 8.0
	elif d > AIRSPACE_WARN and float(st["cd"]) <= 0.0:
		if d > AIRSPACE_ALERT:
			notify("Leaving airspace - turn back NOW", &"bad")
			st["cd"] = 3.5
		else:
			notify("Leaving airspace", &"warn")
			st["cd"] = 6.0
	return d


# =====================================================================================================
# Bail-out
# =====================================================================================================
## Pilot jumps out of a flying aircraft: placed at the door, keeps the aircraft's momentum (no vehicle fall damage), gets an
## emergency parachute and the Player's canopy logic (PlayerTraversal.try_parachute) is attempted for the next 4 s.
static func bail_out_character(v: VehicleBase, c: Node) -> void:
	if c == null or not is_instance_valid(c) or not (c is Node3D):
		return
	var idx := v.get_seat_of(c)
	if idx < 0:
		return
	var side_sign: float = float(v.seats[idx].get("side", -1.0))
	var side_dir := v.global_transform.basis.x * (1.0 if side_sign >= 0.0 else -1.0)
	var saved := v.linear_velocity
	v.linear_velocity = Vector3.ZERO           # VehicleBase.exit() hurts by vehicle speed; the chute pilot is spared
	v.exit(c, true)
	v.linear_velocity = saved
	if c.get("velocity") != null:
		c.velocity = saved * 0.7 + side_dir * 3.5 + Vector3.UP * 2.0
	if c.get("has_parachute") != null:
		c.has_parachute = true
	notify("Bailed out - the parachute opens when you fall fast enough (hold SPACE to cut away)", &"info")
	_try_chute(v.get_tree(), c, 24)


static func _try_chute(tree: SceneTree, c: Node, tries: int) -> void:
	for i in tries:
		await tree.create_timer(0.2).timeout
		if not is_instance_valid(c):
			return
		var tr = c.get("traversal")
		if tr != null and tr.has_method("try_parachute") and tr.try_parachute():
			return


# =====================================================================================================
# Factory info (collision boxes from the def)
# =====================================================================================================
## Model info for the factory (air / sea): collision boxes come from def["col_boxes"] = [[center, size], ...] (vehicle space).
static func model_info(_id: StringName, _model: Node3D, def: Dictionary) -> Dictionary:
	var boxes: Array = []
	for b in def.get("col_boxes", []):
		boxes.append({"pos": b[0], "size": b[1]})
	if boxes.is_empty():
		var l: float = def.get("length", 6.0)
		var w: float = def.get("width", 2.0)
		var h: float = def.get("height", 2.0)
		boxes.append({"pos": Vector3(0, h * 0.5, 0), "size": Vector3(w * 0.5, h * 0.6, l * 0.8)})
	return {"wheels": [], "boxes": boxes, "vert_count": 0}


## Rotation helper: pitch angle (nose above horizon, rad) and bank angle (right side down positive) of a basis.
static func pitch_of(b: Basis) -> float:
	return asin(clampf(-b.z.y, -1.0, 1.0))


static func bank_of(b: Basis) -> float:
	return -asin(clampf(b.x.y, -1.0, 1.0))
