class_name MarineBrain
extends RefCounted
## Shark behaviour: patrol deep water (dorsal fin at the surface), notice a swimmer / boat, circle, then charge and bite swimmers in DEEP
## water only (never the shallows, the beach or near the piers). Deterministic helper statics so tests can query the attack conditions.

const DEEP_Y := -5.0                  # seabed below this = "deep water" (attacks allowed)
const KEEP_Y := -3.6                  # sharks never swim over a seabed shallower than this
const PIER_SAFE := 11.0               # no attacks within this distance of a pier deck
const NOTICE_SWIM := 40.0
const NOTICE_BOAT := 55.0
const BITE_DAMAGE := 22.0
const BITE_RANGE := 2.3


static func near_pier(x: float, z: float, margin: float) -> bool:
	for p in WorldLayout.piers:
		var r: Rect2 = p["rect"]
		if r.grow(margin).has_point(Vector2(x, z)):
			return true
	return false


## True when a swimmer at this position may be attacked: open deep water, away from the beach and the piers.
static func attackable_pos(p: Vector3) -> bool:
	if not WorldLayout.is_water(p.x, p.z):
		return false
	if WorldLayout.terrain_height(p.x, p.z) > DEEP_Y:
		return false
	if p.z < 200.0:
		return false
	return not near_pier(p.x, p.z, PIER_SAFE)


static func deep_enough(x: float, z: float) -> bool:
	return WorldLayout.terrain_height(x, z) < KEEP_Y and absf(x) < 290.0 and z < 385.0


static func move(a: Animal, w: WildlifeWorld, dt: float) -> void:
	if a.is_dead:
		WildlifeBrain.move_dead(a, dt)
		return
	var diff := Util.angle_diff(a.yaw, a.heading)
	var tr := a.turn_rate
	var step := clampf(diff, -tr * dt, tr * dt)
	a.yaw += step
	a.roll_visual = Util.damp(a.roll_visual, clampf(-step / maxf(dt, 0.001) * 0.25, -0.5, 0.5), 4.0, dt)
	a.speed = move_toward(a.speed, a.want_speed, (5.0 if a.state == WildlifeBrain.S_ATTACK else 1.4) * dt)
	var dir := Util.yaw_to_dir(a.yaw)
	var nx := a.pos.x + dir.x * a.speed * dt
	var nz := a.pos.z + dir.z * a.speed * dt
	if deep_enough(nx, nz):
		a.pos.x = nx
		a.pos.z = nz
	else:
		a.heading = Util.dir_to_yaw(Util.flat(a.home - a.pos))
		a.speed *= 0.9
	var floor_y := WorldLayout.terrain_height(a.pos.x, a.pos.z) + 1.2
	var ty := clampf(a.aux, floor_y, GC.WATER_LEVEL - 0.3)
	var vy := clampf((ty - a.pos.y) * 1.2, -1.6, 1.6)
	a.pos.y += vy * dt
	a.pitch_visual = Util.damp(a.pitch_visual, clampf(vy / maxf(a.speed, 1.0), -0.35, 0.35), 4.0, dt)
	a.xf_dirty = true


static func think(a: Animal, w: WildlifeWorld, dt: float) -> void:
	if a.is_dead:
		return
	a.state_t += dt
	a.bite_cd -= dt
	var d := a.def
	var swim_speed := float(d["walk"])
	var pl := w.player
	var pd := 1e9
	var swimmer_ok := false
	var boat_target := false
	if pl != null:
		pd = a.pos.distance_to(w.player_pos)
		swimmer_ok = w.player_swimming and attackable_pos(w.player_pos)
		boat_target = w.player_in_vehicle and w.player_vehicle != null and bool(w.player_vehicle.get("vclass") == GC.VC_BOAT) and WorldLayout.is_water(w.player_pos.x, w.player_pos.z)
	var cheat_off: bool = not Game.cheats.get("sharks", true)
	match a.state:
		WildlifeBrain.S_SWIM, WildlifeBrain.S_IDLE:
			a.turn_rate = 1.2
			a.want_speed = swim_speed
			if a.aux2 > 0.0:
				a.aux2 -= dt
			if (a.state_t > a.dur) or Util.dist_xz(a.pos, a.goal) < 5.0 or a.goal == Vector3.INF:
				a.goal = _patrol_goal(a, w)
				a.dur = w.rng.randf_range(10.0, 25.0)
				a.state_t = 0.0
				a.aux = GC.WATER_LEVEL - (0.4 if w.rng.randf() < 0.6 else w.rng.randf_range(1.5, 4.0))
			a.heading = Util.dir_to_yaw(Util.flat(a.goal - a.pos))
			if not cheat_off and a.aux2 <= 0.0 and ((swimmer_ok and pd < NOTICE_SWIM) or (boat_target and pd < NOTICE_BOAT)):
				WildlifeBrain.set_state(a, WildlifeBrain.S_STALK, w.rng.randf_range(5.0, 9.0))
				a.target = pl
				a.circle_dir = 1.0 if w.rng.randf() < 0.5 else -1.0
				a.circle_r = 15.0
				a.bites_left = 3
				a.aux2 = 0.0
				if swimmer_ok:
					Events.notification.emit("Shark!", &"bad")
					w.voice(a, &"splash", -6.0)
		WildlifeBrain.S_STALK:
			a.turn_rate = 2.0
			a.want_speed = float(d["trot"])
			if pl == null or cheat_off or not (swimmer_ok or boat_target) or pd > NOTICE_BOAT + 12.0:
				a.target = null
				WildlifeBrain.set_state(a, WildlifeBrain.S_SWIM, 12.0)
				a.aux2 = 6.0
				return
			a.circle_r = maxf(a.circle_r - dt * 0.9, 6.0)
			var radial := Util.flat(a.pos - w.player_pos)
			var rd := maxf(radial.length(), 0.1)
			var tang := Vector3(-radial.z, 0.0, radial.x).normalized() * a.circle_dir
			var want := tang + radial.normalized() * clampf((a.circle_r - rd) * 0.08, -0.9, 0.9)
			a.heading = Util.dir_to_yaw(want)
			a.aux = clampf(w.player_pos.y - 0.6, WorldLayout.terrain_height(a.pos.x, a.pos.z) + 1.3, GC.WATER_LEVEL - 0.35)
			if a.state_t > a.dur and swimmer_ok:
				WildlifeBrain.set_state(a, WildlifeBrain.S_ATTACK, 7.0)
			elif a.state_t > a.dur + 6.0:
				a.target = null
				WildlifeBrain.set_state(a, WildlifeBrain.S_SWIM, 12.0)
				a.aux2 = 15.0
		WildlifeBrain.S_ATTACK:
			a.turn_rate = 3.6
			a.want_speed = float(d["run"])
			if pl == null or not swimmer_ok:
				WildlifeBrain.set_state(a, WildlifeBrain.S_RETREAT, 4.0)
				return
			var to := w.player_pos + Vector3(0.0, 0.3, 0.0) - a.pos
			a.heading = Util.dir_to_yaw(Util.flat(to))
			a.aux = clampf(w.player_pos.y, WorldLayout.terrain_height(a.pos.x, a.pos.z) + 1.2, GC.WATER_LEVEL - 0.3)
			if to.length() < BITE_RANGE and a.bite_cd <= 0.0:
				a.bite_cd = 2.2
				a.jaw_open = 1.0
				a.bites_left -= 1
				var info := {"source": a, "type": GC.DMG_ANIMAL, "zone": GC.ZONE_TORSO, "position": w.player_pos + Vector3.UP * 0.8,
					"direction": Util.flat(to).normalized(), "weapon": &"shark_bite", "impulse": 3.0}
				if pl.has_method("apply_damage"):
					pl.apply_damage(w.rng.randf_range(BITE_DAMAGE * 0.8, BITE_DAMAGE * 1.25), info)
				if Game.gameplay_camera != null and Game.gameplay_camera.has_method("add_shake"):
					Game.gameplay_camera.add_shake(0.5, 0.45)
				w.voice(a, &"splash_big", 0.0)
				Events.notification.emit("The shark bit you!", &"bad")
				WildlifeBrain.set_state(a, WildlifeBrain.S_RETREAT, 3.5)
		WildlifeBrain.S_RETREAT:
			a.turn_rate = 2.4
			a.want_speed = float(d["trot"]) * 1.2
			if a.threat_pos != Vector3.INF:
				a.heading = Util.dir_to_yaw(Util.flat(a.pos - a.threat_pos))
			elif pl != null:
				a.heading = Util.dir_to_yaw(Util.flat(a.pos - w.player_pos))
			if a.state_t > a.dur:
				if a.bites_left <= 0:
					WildlifeBrain.set_state(a, WildlifeBrain.S_SWIM, 14.0)
					a.aux2 = 25.0
					a.target = null
				else:
					WildlifeBrain.set_state(a, WildlifeBrain.S_STALK, w.rng.randf_range(2.0, 4.0))
					a.circle_r = 11.0
	if a.state != WildlifeBrain.S_STALK and a.state != WildlifeBrain.S_ATTACK and not deep_enough(a.pos.x + sin(-a.yaw) * 8.0, a.pos.z - cos(a.yaw) * 8.0):
		a.heading = Util.dir_to_yaw(Util.flat(a.home - a.pos))


static func _patrol_goal(a: Animal, w: WildlifeWorld) -> Vector3:
	for i in 10:
		var ang := w.rng.randf() * TAU
		var dd := w.rng.randf_range(25.0, 60.0)
		var g := a.home + Vector3(cos(ang) * dd, 0.0, sin(ang) * dd)
		if deep_enough(g.x, g.z) and g.z > 215.0:
			return g
	return a.home


## Finds a deep-water spawn point 55..130 m from `around` (null when none).
static func pick_spawn(around: Vector3, rng: RandomNumberGenerator, rmin: float, rmax: float) -> Vector3:
	for i in 24:
		var ang := rng.randf() * TAU
		var dd := rng.randf_range(rmin, rmax)
		var x := around.x + cos(ang) * dd
		var z := around.z + sin(ang) * dd
		if z > 225.0 and deep_enough(x, z) and WorldLayout.terrain_height(x, z) < -8.0:
			return Vector3(x, GC.WATER_LEVEL - 0.4, z)
	return Vector3.INF
