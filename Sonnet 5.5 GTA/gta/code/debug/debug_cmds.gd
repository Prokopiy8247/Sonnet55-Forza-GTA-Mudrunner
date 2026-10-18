class_name DebugCmds
extends RefCounted
## Every action of the benchmark menu as a UI-free static function (so the headless test can call them directly).
## All actions return {"ok": bool, "msg": String, ...extras}. They are safe when a target system is missing (ok = false + reason).

static var last_vehicle_id: StringName = &"sedan"
static var debug_gang: Array = []
static var _gang_serial := 0
static var _god_prev: Node = null
static var _boost_prev: Node = null


static func ok(msg: String, extra: Dictionary = {}) -> Dictionary:
	var r := {"ok": true, "msg": msg}
	r.merge(extra, true)
	return r


static func fail(msg: String) -> Dictionary:
	return {"ok": false, "msg": msg}


# ==================================================================================================================
# Helpers
# ==================================================================================================================
static func _player() -> Variant:
	var p = Game.player
	return p if is_instance_valid(p) else null


static func player_vehicle() -> VehicleBase:
	var p = _player()
	if p == null:
		return null
	var v = p.get("current_vehicle")
	if v is VehicleBase and is_instance_valid(v):
		return v
	return null


## The vehicle the player drives, else the nearest one within 12 m.
static func target_vehicle() -> VehicleBase:
	var v := player_vehicle()
	if v != null:
		return v
	var p = _player()
	var vs = Game.sys(&"vehicles")
	if p != null and vs != null and vs.has_method("find_nearest_vehicle"):
		return vs.find_nearest_vehicle(p.global_position, 12.0)
	return null


static func view_dir() -> Vector3:
	var f := Vector3(0, 0, -1)
	var cam: Camera3D = Game.gameplay_camera
	if cam != null and is_instance_valid(cam):
		f = -cam.global_transform.basis.z
	else:
		var p = _player()
		if p != null:
			f = -p.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3(0, 0, -1)


## World point under the crosshair (camera ray), or Vector3.INF.
static func crosshair_point(max_dist: float = 100.0) -> Vector3:
	var cam: Camera3D = Game.gameplay_camera
	if cam == null or not is_instance_valid(cam) or Game.world == null:
		return Vector3.INF
	var from := cam.global_position
	var excl: Array = []
	if _player() != null:
		excl.append(Game.player)
	var pv := player_vehicle()
	if pv != null:
		excl.append(pv)
	var hit := Util.raycast(Game.world, from, from - cam.global_transform.basis.z * max_dist, GC.M_BULLET, excl)
	return hit["position"] if not hit.is_empty() else Vector3.INF


static func spawn_point(at_crosshair: bool, ahead: float = 14.0) -> Vector3:
	if at_crosshair:
		var c := crosshair_point()
		if c != Vector3.INF:
			return c
	var p = _player()
	var base: Vector3 = p.global_position if p != null else Vector3.ZERO
	return base + view_dir() * ahead


static func resolve_ground(pos: Vector3) -> Vector3:
	if Game.world == null or not Game.world.is_inside_tree():
		return pos
	if WorldLayout.is_water(pos.x, pos.z) and pos.y > GC.WATER_LEVEL - 1.0:
		return Vector3(pos.x, GC.WATER_LEVEL + 0.2, pos.z)             # swim at the surface
	var hit := Util.raycast(Game.world, pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 60.0, GC.M_GROUND)
	if hit.is_empty():
		return Vector3(pos.x, maxf(pos.y, WorldLayout.terrain_height(pos.x, pos.z)) + 0.2, pos.z)
	return (hit["position"] as Vector3) + Vector3.UP * 0.1


## True when a standing player capsule fits at `pos` (feet position) without touching world / prop / vehicle colliders.
static func standing_spot_free(pos: Vector3) -> bool:
	if Game.world == null or not Game.world.is_inside_tree():
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pos + Vector3(0, 1.0, 0))
	q.collision_mask = GC.L_WORLD | GC.L_PROP | GC.L_VEHICLE
	return (Game.world as Node3D).get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## resolve_ground() + if the capsule does not fit there, the nearest free spot on rings of 1.5 .. 7.5 m.
static func resolve_standing(pos: Vector3) -> Vector3:
	var g := resolve_ground(pos)
	if standing_spot_free(g + Vector3(0, 0.1, 0)):
		return g
	for r in [1.5, 3.0, 4.5, 6.0, 7.5]:
		for i in 8:
			var a := TAU * float(i) / 8.0
			var cand := resolve_ground(Vector3(pos.x + cos(a) * r, pos.y, pos.z + sin(a) * r))
			if absf(cand.y - g.y) < 2.5 and standing_spot_free(cand + Vector3(0, 0.1, 0)):
				return cand
	return g


static func vehicle_near(pos: Vector3, radius: float) -> bool:
	for v in Game.get_vehicles():
		if is_instance_valid(v) and (v as Node3D).global_position.distance_to(pos) < radius:
			return true
	return false


static func nearest_location(ids: Array, pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for id in ids:
		var loc: Dictionary = WorldLayout.get_location(StringName(id))
		if loc.is_empty():
			continue
		var d := Util.dist_xz(loc["pos"], pos)
		if d < best_d:
			best_d = d
			best = loc
	return best


# ==================================================================================================================
# TELEPORT
# ==================================================================================================================
static func teleport_to_position(pos: Vector3, yaw: float = NAN) -> Dictionary:
	var p = _player()
	if p == null:
		return fail("No player")
	var v := player_vehicle()
	var target := resolve_ground(pos) if v != null else resolve_standing(pos)
	if v != null:
		var vyaw := yaw if not is_nan(yaw) else v.global_transform.basis.get_euler().y
		var y := target.y + 0.4
		if v.vclass == GC.VC_BOAT:
			y = GC.WATER_LEVEL + 0.15
		v.place_at(Transform3D(Basis(Vector3.UP, vyaw), Vector3(target.x, y, target.z)))
		var cam = Game.gameplay_camera
		if cam != null and cam.has_method("on_player_teleported"):
			cam.on_player_teleported()
	else:
		p.teleport_to(target + Vector3(0, 0.1, 0), yaw)
		if not is_nan(yaw) and p.get("camera") != null and p.camera.has_method("snap_behind"):
			p.camera.snap_behind(yaw)
	return ok("Teleported to %d, %d" % [int(target.x), int(target.z)], {"pos": target, "close": true})


static func teleport_to_location(id: StringName) -> Dictionary:
	var loc: Dictionary = WorldLayout.get_location(id)
	if loc.is_empty():
		return fail("Unknown location '%s'" % id)
	var r := teleport_to_position(loc["pos"], float(loc.get("yaw", 0.0)))
	if r["ok"]:
		r["msg"] = "Teleported to %s" % String(loc.get("name", id))
	return r


static func teleport_to_waypoint() -> Dictionary:
	var ui = Game.ui
	if ui == null or not bool(ui.get("has_waypoint")):
		return fail("No waypoint set (open the map with M and click)")
	var w: Vector3 = ui.get("waypoint")
	return teleport_to_position(Vector3(w.x, WorldLayout.terrain_height(w.x, w.z) + 40.0, w.z))


# ==================================================================================================================
# VEHICLES
# ==================================================================================================================
static func spawn_vehicle(id: StringName, opts: Dictionary = {}) -> Dictionary:
	if not VehicleDefs.is_implemented(id):
		return fail("%s is not implemented" % id)
	var p = _player()
	if p == null:
		return fail("No player")
	var def: Dictionary = VehicleDefs.get_def(id)
	var cls: StringName = def.get("class", GC.VC_CAR)
	var ppos: Vector3 = p.global_position
	var fo := {"abandoned": true}
	var paint: Color = opts.get("paint", Color(0, 0, 0, 0))
	if paint.a > 0.0:
		fo["paint"] = paint
		fo["finish"] = &"metallic"
	var pos := Vector3.ZERO
	var yaw := 0.0
	var where := ""
	if cls == GC.VC_HELI:
		var pad := nearest_location(["helipad_airport", "helipad_downtown", "helipad_hospital"], ppos)
		if pad.is_empty():
			return fail("No helipad in this world")
		pos = pad["pos"] + Vector3(0, 0.6, 0)
		yaw = float(pad.get("yaw", 0.0))
		var found := false
		for r in [0.0, 12.0, 20.0, 28.0]:
			var n := 1 if r == 0.0 else 8
			for i in n:
				var a := TAU * float(i) / float(n)
				var c: Vector3 = pad["pos"] + Vector3(cos(a) * r, 0, sin(a) * r)
				var spot: Vector3 = AirCommon.find_clear_pad(Game.world, c, 5.5, 3.0)
				if spot != Vector3.INF and not vehicle_near(spot, 9.0):
					pos = spot + Vector3(0, 0.6, 0)
					found = true
					break
			if found:
				break
		where = " at the nearest helipad"
	elif cls == GC.VC_PLANE:
		var rw: Dictionary = WorldLayout.get_location(&"airport_runway_start")
		if rw.is_empty():
			return fail("No runway in this world")
		yaw = float(rw.get("yaw", 0.0))
		var basis := Basis(Vector3.UP, yaw)
		pos = rw["pos"]
		for lat in [-6.0, 6.0, -15.0, 15.0, -24.0, 24.0]:
			var cand: Vector3 = rw["pos"] + basis * Vector3(lat, 0, -2.0)
			pos = cand
			if not vehicle_near(cand, 12.0):
				break
		pos.y += 0.3
		where = " on the runway"
	elif cls == GC.VC_BOAT:
		var w := find_water_spot(ppos)
		if w == Vector3.INF:
			return fail("No open water found")
		pos = w
		yaw = PI
		fo["snap_ground"] = false
		where = " in the nearest water"
	else:
		var length := float(def.get("length", 4.5))
		var fwd := view_dir()
		var dist := 5.0 + length * 0.5
		var pv := player_vehicle()
		if pv != null:
			fwd = -pv.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			dist = 8.0 + length * 0.5 + pv.get_speed()
		var base: Vector3 = ppos
		pos = base + fwd * dist
		var side := fwd.cross(Vector3.UP)
		var placed := false
		for lat in [0.0, 4.5, -4.5, 9.0, -9.0]:
			var cand: Vector3 = base + fwd * dist + side * lat
			if WorldLayout.is_water(cand.x, cand.z):
				continue
			if vehicle_near(cand, length * 0.5 + 2.0):
				continue
			pos = cand
			placed = true
			break
		if not placed and WorldLayout.is_water(pos.x, pos.z):
			return fail("No dry land ahead - walk to the shore first")
		yaw = Util.dir_to_yaw(fwd)
		var lanes: LaneGraph = WorldLayout.lanes
		if lanes != null and lanes.size() > 0:
			var li := lanes.nearest(pos, fwd, 12.0)
			if li >= 0 and lanes.kind[li] == LaneGraph.KIND_STRAIGHT and not vehicle_near(lanes.positions[li], length * 0.5 + 2.0):
				pos = lanes.positions[li]
				yaw = Util.dir_to_yaw(lanes.dirs[li])
				where = " on the road"
		pos.y = ppos.y + 0.5
	var v := VehicleFactory.spawn(id, Transform3D(Basis(Vector3.UP, yaw), pos), fo)
	if v == null:
		return fail("Could not spawn %s (VehicleFactory returned null)" % id)
	last_vehicle_id = id
	if bool(opts.get("siren", false)) and not v.siren_on:
		v.toggle_siren()
	var entered := false
	if bool(opts.get("enter", false)):
		entered = enter_vehicle(v)
	return ok("Spawned %s%s%s" % [String(def.get("name", id)), where, " - you are driving" if entered else ""],
		{"vehicle": v, "entered": entered, "close": bool(opts.get("enter", false))})


static func find_water_spot(near: Vector3) -> Vector3:
	var r := 12.0
	while r <= 330.0:
		for i in 16:
			var a := TAU * float(i) / 16.0
			var x := near.x + cos(a) * r
			var z := near.z + sin(a) * r
			if absf(x) > 290.0 or z > 385.0 or z < -290.0:
				continue
			if WorldLayout.is_water(x, z) and WorldLayout.terrain_height(x, z) < GC.WATER_LEVEL - 1.5:
				var c := Vector3(x, GC.WATER_LEVEL + 0.15, z)
				if not vehicle_near(c, 7.0):
					return c
		r += 10.0
	return WorldLayout.location_pos(&"dock_boat_spawn", Vector3.INF) if WorldLayout.has_location(&"dock_boat_spawn") else Vector3.INF


static func enter_vehicle(v: VehicleBase) -> bool:
	var p = _player()
	if p == null or v == null or not is_instance_valid(v):
		return false
	if player_vehicle() != null and player_vehicle() != v:
		p.exit_vehicle(true)
	return p.enter_vehicle(v, 0)


static func spawn_last_vehicle() -> Dictionary:
	return spawn_vehicle(last_vehicle_id, {"enter": true})


## Removes one vehicle cleanly (traffic book-keeping, police units, pooled recycle).
static func remove_vehicle(v: Variant) -> void:
	if not is_instance_valid(v):
		return
	var peds = Game.sys(&"peds")
	if v is VehicleBase:
		for c in (v as VehicleBase).get_occupants():
			if c == Game.player:
				continue
			if peds != null and peds.has_method("release") and c.is_in_group(GC.G_PED):
				peds.release(c)
			elif not (c is Player):
				c.queue_free()
	var traffic = Game.sys(&"traffic")
	if traffic != null and traffic.has_method("get_driver") and traffic.has_method("recycle_driver"):
		var d = traffic.get_driver(v)
		if d != null:
			traffic.recycle_driver(d)
	if is_instance_valid(v) and v.is_inside_tree():
		if v.is_in_group(GC.G_POLICE) and v.has_meta(&"police_ai"):
			PoliceUnits.despawn(v)
		else:
			VehicleFactory.despawn(v)


static func delete_nearby_vehicles(radius: float = 80.0) -> Dictionary:
	var p = _player()
	if p == null:
		return fail("No player")
	var cur := player_vehicle()
	var n := 0
	for v in Game.get_vehicles().duplicate():
		if v == cur or not is_instance_valid(v) or not (v is VehicleBase):
			continue
		if (v as VehicleBase).is_player_owned:
			continue
		if (v as Node3D).global_position.distance_to(p.global_position) > radius:
			continue
		remove_vehicle(v)
		n += 1
	return ok("Deleted %d vehicle(s) within %d m" % [n, int(radius)], {"count": n})


static func repair_current() -> Dictionary:
	var v := target_vehicle()
	if v == null:
		return fail("No vehicle (sit in one or stand within 12 m)")
	v.repair()
	if v.is_flipped_over():
		v.unflip()
	return ok("Repaired %s" % v.display_name, {"vehicle": v})


static func flip_current() -> Dictionary:
	var v := target_vehicle()
	if v == null:
		return fail("No vehicle (sit in one or stand within 12 m)")
	v.unflip()
	return ok("Flipped %s upright" % v.display_name, {"vehicle": v})


static func set_vehicle_god(on: bool) -> Dictionary:
	Game.cheats["vehicle_god"] = on
	apply_vehicle_god()
	return ok("Vehicle god mode %s" % ("ON" if on else "OFF"))


## Called by the menu tick: keeps the CURRENT vehicle invulnerable while the cheat is on.
static func apply_vehicle_god() -> void:
	var on := bool(Game.cheats.get("vehicle_god", false))
	var v := player_vehicle()
	if _god_prev != null and _god_prev != v and is_instance_valid(_god_prev):
		_god_prev.remove_meta("invulnerable")
	_god_prev = v
	if v == null:
		return
	if on:
		v.set_meta("invulnerable", true)
		if v.get_health_ratio() < 0.98 or v.on_fire:
			v.repair()
	else:
		v.remove_meta("invulnerable")


static func set_speed_boost(f: float) -> Dictionary:
	f = clampf(f, 1.0, 5.0)
	Game.cheats["vehicle_boost"] = f
	apply_speed_boost()
	return ok("Engine boost x%.1f" % f)


static func apply_speed_boost() -> void:
	var f := float(Game.cheats.get("vehicle_boost", 1.0))
	var v := player_vehicle()
	if _boost_prev != null and _boost_prev != v and is_instance_valid(_boost_prev):
		_restore_boost(_boost_prev as VehicleBase)
	_boost_prev = v
	if v == null:
		return
	if f <= 1.001:
		_restore_boost(v)
		return
	if not v.has_meta("dbg_p"):
		v.set_meta("dbg_p", v.mod_power)
		v.set_meta("dbg_t", v.mod_topspeed)
	v.mod_power = float(v.get_meta("dbg_p")) * f
	v.mod_topspeed = float(v.get_meta("dbg_t")) * (1.0 + 0.45 * (pow(f, 1.0 / 3.0) - 1.0))


static func _restore_boost(v: VehicleBase) -> void:
	if v != null and v.has_meta("dbg_p"):
		v.mod_power = float(v.get_meta("dbg_p"))
		v.mod_topspeed = float(v.get_meta("dbg_t"))
		v.remove_meta("dbg_p")
		v.remove_meta("dbg_t")


static func open_customization() -> Dictionary:
	var g = Game.sys(&"garage")
	if g == null:
		return fail("Garage system not booted")
	var v := target_vehicle()
	if v == null:
		return fail("Sit in a car or bike first (or stand next to one)")
	if not g.can_customize(v):
		return fail("%s cannot be customized (cars, bikes and bicycles only)" % v.display_name)
	if g.session != null:
		return fail("A garage session is already running")
	var site: Dictionary = {"id": &"debug", "kind": &"shop", "name": "Customization garage", "bays": []}
	for s in g.sites:
		if s.get("kind", &"") == &"shop":
			site = s
			break
	g.begin_session(v, site, -1)
	return ok("Garage session for %s" % v.display_name, {"vehicle": v, "close": true})


static func set_unlock_all_mods(on: bool) -> Dictionary:
	Game.cheats["unlock_all_mods"] = on
	var g = Game.sys(&"garage")
	if g != null:
		g.unlock_all = on
	return ok("All vehicle mods %s" % ("unlocked (free)" if on else "back to normal prices"))


# ==================================================================================================================
# WEAPONS / PLAYER GEAR
# ==================================================================================================================
static func _wc() -> Variant:
	var p = _player()
	if p == null:
		return null
	var w = p.get("weapons")
	return w if w != null and is_instance_valid(w) else null


static func give_weapon(id: StringName) -> Dictionary:
	var wc = _wc()
	if wc == null:
		return fail("Player has no weapon controller")
	if not WeaponDefs.has(id):
		return fail("Unknown weapon '%s'" % id)
	var total := WeaponDefs.mag_capacity(id, {}) + WeaponDefs.reserve_capacity(id, {})
	wc.give_weapon(id, maxi(total, 1), true)
	wc.refill_all_ammo()
	return ok("Given %s with full ammo" % DebugCatalog.weapon_name(id))


static func give_all_weapons() -> Dictionary:
	var wc = _wc()
	if wc == null:
		return fail("Player has no weapon controller")
	var n := 0
	for id in WeaponDefs.ids():
		if id == &"fists":
			continue
		var total := WeaponDefs.mag_capacity(id, {}) + WeaponDefs.reserve_capacity(id, {})
		wc.give_weapon(id, maxi(total, 1), false)
		n += 1
	wc.refill_all_ammo()
	return ok("Given %d weapons with full ammo" % n, {"count": n})


static func remove_all_weapons() -> Dictionary:
	var wc = _wc()
	if wc == null:
		return fail("Player has no weapon controller")
	for id in wc.get_weapon_ids().duplicate():
		if id != &"fists":
			wc.remove_weapon(id)
	wc.equip(&"fists")
	return ok("All weapons removed")


static func refill_ammo() -> Dictionary:
	var wc = _wc()
	if wc == null:
		return fail("Player has no weapon controller")
	wc.refill_all_ammo()
	return ok("Ammo refilled")


static func set_infinite_ammo(on: bool) -> Dictionary:
	Game.cheats["infinite_ammo"] = on
	return ok("Infinite ammo %s" % ("ON" if on else "OFF"))


## Installs / removes an attachment on the equipped weapon.
static func set_attachment(mod_id: StringName, on: bool) -> Dictionary:
	var wc = _wc()
	if wc == null:
		return fail("Player has no weapon controller")
	var wid: StringName = wc.current_id
	if wid == &"" or not WeaponMods.is_compatible(wid, mod_id):
		return fail("%s does not fit %s" % [mod_id, wid])
	if not wc.set_mod(wid, mod_id, on):
		return fail("Could not change %s" % mod_id)
	return ok("%s %s on %s" % [WeaponMods.get_mod(mod_id).get("name", mod_id), "installed" if on else "removed", DebugCatalog.weapon_name(wid)])


static func give_parachute(on: bool = true) -> Dictionary:
	var p = _player()
	if p == null:
		return fail("No player")
	p.set("has_parachute", on)
	return ok("Parachute %s" % ("given (Space in the air)" if on else "removed"))


static func set_scuba(on: bool) -> Dictionary:
	var p = _player()
	if p == null:
		return fail("No player")
	p.set("has_scuba", on)
	Game.cheats["scuba"] = on
	if on:
		refill_lungs()
	return ok("Scuba gear %s" % ("ON (unlimited air)" if on else "OFF"))


static func refill_lungs() -> Dictionary:
	var p = _player()
	if p == null:
		return fail("No player")
	if p.has_method("lung_capacity"):
		p.set("lungs", float(p.lung_capacity()))
	return ok("Lungs refilled")


static func set_health(v: float) -> Dictionary:
	var p = _player()
	if p == null:
		return fail("No player")
	p.health = clampf(v, 1.0, p.max_health)
	return ok("Health %d" % int(p.health))


static func set_armor(v: float) -> Dictionary:
	var p = _player()
	if p == null:
		return fail("No player")
	p.armor = clampf(v, 0.0, p.max_armor)
	return ok("Armor %d" % int(p.armor))


static func heal_full() -> Dictionary:
	var p = _player()
	if p == null:
		return fail("No player")
	p.health = p.max_health
	p.armor = p.max_armor
	refill_lungs()
	return ok("Health, armor and lungs restored")


# ==================================================================================================================
# PLAYER: money / cheats / wanted / skills / time / weather
# ==================================================================================================================
static func set_money(n: int) -> Dictionary:
	Game.cash = maxi(n, 0)
	return ok("Cash set to %s" % Util.format_money(Game.cash))


static func add_money(n: int) -> Dictionary:
	Game.cash = maxi(Game.cash + n, 0)
	return ok("Cash %s%s (now %s)" % ["+" if n >= 0 else "-", Util.format_money(absi(n)), Util.format_money(Game.cash)])


static func set_invulnerable(on: bool) -> Dictionary:
	Game.cheats["invulnerable"] = on
	return ok("Invulnerability %s" % ("ON" if on else "OFF"))


static func set_never_wanted(on: bool) -> Dictionary:
	Game.cheats["never_wanted"] = on
	if on:
		clear_wanted()
	return ok("Never wanted %s" % ("ON" if on else "OFF"))


static func set_wanted(n: int) -> Dictionary:
	var w = Game.sys(&"wanted")
	if w == null:
		return fail("Wanted system not booted")
	n = clampi(n, 0, 5)
	if n > 0 and bool(Game.cheats.get("never_wanted", false)):
		return fail("Never-wanted is ON - turn it off first")
	w.set_level(n)
	return ok("Wanted level %d" % n if n > 0 else "Wanted level cleared", {"level": n})


static func clear_wanted() -> Dictionary:
	var w = Game.sys(&"wanted")
	if w == null:
		return fail("Wanted system not booted")
	w.clear()
	return ok("Wanted level cleared")


static func skills_max() -> Dictionary:
	var s = Game.sys(&"skills")
	if s == null:
		return fail("Skills system not booted")
	s.max_all()
	return ok("All skills maxed")


static func skills_reset() -> Dictionary:
	var s = Game.sys(&"skills")
	if s == null:
		return fail("Skills system not booted")
	s.reset_all()
	return ok("All skills reset")


static func set_skill(id: StringName, v: float) -> Dictionary:
	var s = Game.sys(&"skills")
	if s == null:
		return fail("Skills system not booted")
	s.set_skill(id, v)
	return ok("%s %d" % [id, int(v)])


static func set_time(hour: float) -> Dictionary:
	var env = Game.sys(&"environment")
	if env != null and env.has_method("set_time"):
		env.set_time(hour)
	else:
		Game.time_of_day = fposmod(hour, 24.0)
	return ok("Time %s" % Util.format_clock(Game.time_of_day))


static func set_time_frozen(on: bool) -> Dictionary:
	Game.time_frozen = on
	return ok("Time %s" % ("frozen" if on else "running"))


static func set_clock_speed(v: float) -> Dictionary:
	Game.time_scale = clampf(v, 0.0, 2000.0)
	return ok("Clock speed x%d (60 = default)" % int(Game.time_scale))


static func set_weather(name: StringName) -> Dictionary:
	var env = Game.sys(&"environment")
	if env == null or not env.has_method("set_weather"):
		return fail("Environment system not booted")
	if not env.set_weather(name):
		return fail("Unknown weather %s" % name)
	return ok("Weather: %s" % name)


# ==================================================================================================================
# WORLD / SPAWN
# ==================================================================================================================
static func spawn_police(kind: StringName, at_crosshair: bool = false) -> Dictionary:
	var p = _player()
	if p == null:
		return fail("No player")
	var pos := spawn_point(at_crosshair, 16.0)
	var ppos: Vector3 = p.global_position
	var to_player := Vector3(ppos.x - pos.x, 0, ppos.z - pos.z)
	var yaw := Util.dir_to_yaw(to_player) if to_player.length() > 1.0 else 0.0
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.3, 0))
	var node: Node = null
	match kind:
		&"car":
			node = PoliceUnits.spawn_patrol_car(xf, 2)
		&"van":
			node = PoliceUnits.spawn_tactical_van(xf)
		&"officer", &"patrol":
			node = PoliceUnits.spawn_officer(&"patrol", xf)
		&"swat":
			node = PoliceUnits.spawn_officer(&"swat", xf)
		&"sniper":
			node = PoliceUnits.spawn_officer(&"sniper", xf)
		&"heli":
			node = PoliceHeliAI.spawn(ppos + Vector3(0, 70, 0) - view_dir() * 40.0)
		&"roadblock":
			node = PoliceUnits.spawn_roadblock(pos, view_dir(), 3)
		_:
			return fail("Unknown police kind '%s'" % kind)
	if node == null:
		return fail("Could not spawn police %s (unit cap reached or no ground)" % kind)
	return ok("Spawned police %s" % kind, {"node": node})


static func spawn_gang(at_crosshair: bool = true) -> Dictionary:
	if _player() == null:
		return fail("No player")
	var hm: Node = PoliceUnits.ensure_hostile_manager()
	debug_gang = debug_gang.filter(func(m): return is_instance_valid(m) and not m.is_dead)
	if debug_gang.size() >= 9:
		return fail("Already 9 debug gang members alive")
	var center := resolve_ground(spawn_point(at_crosshair, 18.0))
	var cont: Node = hm._root() if hm != null and hm.has_method("_root") else Game.world
	if cont == null:
		return fail("No world to spawn into")
	_gang_serial += 1
	var shared: Array = []
	for i in 3:
		var a := TAU * float(i) / 3.0
		var gp := resolve_ground(center + Vector3(cos(a), 0, sin(a)) * 2.4)
		var m := GangNpc.new()
		m.turf = center
		m.turf_radius = 5.0
		m.group_id = 90 + _gang_serial
		m.group_members = shared
		m.name = "DebugGang_%d_%d" % [_gang_serial, i]
		cont.add_child(m)
		m.global_transform = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(center - gp) if center.distance_to(gp) > 0.5 else 0.0), gp)
		m.reset_physics_interpolation()
		shared.append(m)
		debug_gang.append(m)
	return ok("Spawned a gang group (3). They react when you draw a weapon near them.", {"count": 3})


static func activate_gang_turfs() -> Dictionary:
	var hm: Node = PoliceUnits.ensure_hostile_manager()
	if hm == null or not hm.has_method("force_spawn_all"):
		return fail("HostileManager not available")
	hm.force_spawn_all()
	return ok("All gang turfs populated (%d alive)" % int(hm.alive_count()))


static func spawn_pedestrians(n: int = 10) -> Dictionary:
	var peds = Game.sys(&"peds")
	var p = _player()
	if peds == null or p == null:
		return fail("Pedestrian system not booted")
	var arr: Array = peds.spawn_crowd(p.global_position, 28.0, n)
	return ok("Spawned %d pedestrians" % arr.size(), {"count": arr.size()})


static func call_taxi() -> Dictionary:
	var t = Game.sys(&"transit")
	if t == null or not t.has_method("call_taxi"):
		return fail("Taxi service not available (TransitSystem.call_taxi missing)")
	t.call_taxi()
	return ok("Taxi called")


static func taxi_available() -> bool:
	var t = Game.sys(&"transit")
	return t != null and t.has_method("call_taxi")


static func spawn_service(id: StringName) -> Dictionary:
	return spawn_vehicle(id, {"enter": false, "siren": true})


static func explode_at_crosshair() -> Dictionary:
	var c = Game.sys(&"combat")
	if c == null:
		return fail("Combat system not booted")
	var pos := crosshair_point(120.0)
	if pos == Vector3.INF:
		pos = spawn_point(false, 14.0)
	c.explode(pos, 9.0, 260.0, null, {"big": true, "weapon": &"debug"})
	return ok("Boom at %d, %d" % [int(pos.x), int(pos.z)], {"pos": pos})


static func set_traffic(on: bool) -> Dictionary:
	Game.cheats["traffic"] = on
	var t = Game.sys(&"traffic")
	if not on and t != null and t.has_method("clear_traffic"):
		t.clear_traffic()
	return ok("Traffic %s" % ("ON" if on else "OFF"))


static func set_pedestrians(on: bool) -> Dictionary:
	Game.cheats["pedestrians"] = on
	var p = Game.sys(&"peds")
	if not on and p != null and p.has_method("clear_all"):
		p.clear_all(false)
	return ok("Pedestrians %s" % ("ON" if on else "OFF"))


static func set_wildlife(on: bool) -> Dictionary:
	Game.cheats["wildlife"] = on
	var w = Game.sys(&"wildlife")
	if w != null:
		if w.has_method("set_enabled"):
			w.set_enabled(on)
		elif "enabled" in w:
			w.set("enabled", on)
	return ok("Wildlife %s%s" % [("ON" if on else "OFF"), "" if w != null and (w.has_method("set_enabled") or "enabled" in w) else " (cheat flag only - wildlife system has no hook yet)"])


static func set_density(kind: String, v: float) -> Dictionary:
	Game.settings[kind] = clampf(v, 0.0, 2.0)
	Events.settings_changed.emit()
	return ok("%s density x%.1f" % [kind.replace("_density", ""), v])


static func kill_nearby_npcs(radius: float = 40.0) -> Dictionary:
	var p = _player()
	if p == null:
		return fail("No player")
	var n := 0
	for c in Game.get_tree().get_nodes_in_group(GC.G_NPC):
		if c == p or not is_instance_valid(c) or not (c is Node3D) or not c.has_method("apply_damage"):
			continue
		if bool(c.get("is_dead")):
			continue
		if (c as Node3D).global_position.distance_to(p.global_position) > radius:
			continue
		c.apply_damage(9999.0, {"source": null, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "position": (c as Node3D).global_position, "weapon": &"debug"})
		n += 1
	return ok("%d NPC(s) knocked out" % n, {"count": n})


static func set_slowmo(on: bool) -> Dictionary:
	Game.cheats["slowmo"] = on
	Engine.time_scale = 0.25 if on else 1.0
	return ok("Slow motion %s" % ("ON" if on else "OFF"))


# ==================================================================================================================
# OVERLAYS
# ==================================================================================================================
static func set_cheat(key: String, on: bool) -> Dictionary:
	Game.cheats[key] = on
	return ok("%s %s" % [key.replace("_", " "), "ON" if on else "OFF"])


static func set_hud_visible(on: bool) -> Dictionary:
	if Game.ui == null:
		return fail("UI not booted")
	Game.ui.set_hud_visible(on)
	return ok("HUD %s" % ("shown" if on else "hidden"))


static func set_render_mode(index: int) -> Dictionary:
	index = clampi(index, 0, DebugCatalog.RENDER_MODES.size() - 1)
	var vp := Game.get_tree().root
	vp.debug_draw = DebugCatalog.RENDER_MODES[index][1]
	return ok("Render mode: %s" % DebugCatalog.RENDER_MODES[index][0])


static func stats_text(ft_max_ms: float = 0.0) -> String:
	var fps := Engine.get_frames_per_second()
	var out: Array[String] = []
	out.append("FPS %d   frame %.1f ms%s" % [fps, 1000.0 / maxf(float(fps), 1.0), ("  (max %.1f)" % ft_max_ms) if ft_max_ms > 0.0 else ""])
	out.append("Draw calls %d   objects %d   tris %dk" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])
	out.append("Nodes %d   physics bodies %d   mem %.0f MB" % [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	var p = _player()
	if p != null:
		var pos: Vector3 = p.global_position
		var v := player_vehicle()
		var spd: float = v.get_speed_kmh() if v != null else float(p.get_speed_xz()) * 3.6
		out.append("XYZ %.1f  %.1f  %.1f   sector S(%d,%d)   %s" % [pos.x, pos.y, pos.z, floori(pos.x / 100.0), floori(pos.z / 100.0), String(WorldLayout.district_at(pos.x, pos.z))])
		out.append("Heading %d deg   speed %d km/h   %s" % [heading_deg(), int(spd), (v.display_name if v != null else "on foot")])
	out.append("Wanted %d (%s)   traffic %d   peds %d   police %d" % [Game.wanted_level, String(Game.wanted_state), _count_traffic(), _count_peds(), Game.get_tree().get_nodes_in_group(GC.G_POLICE).size()])
	return "\n".join(out)


static func heading_deg() -> int:
	var f := view_dir()
	return int(fposmod(-rad_to_deg(Util.dir_to_yaw(f)), 360.0))


static func _count_traffic() -> int:
	var t = Game.sys(&"traffic")
	return int(t.get_active_count()) if t != null and t.has_method("get_active_count") else 0


static func _count_peds() -> int:
	var t = Game.sys(&"peds")
	return int(t.active_count()) if t != null and t.has_method("active_count") else 0


# ==================================================================================================================
# SYSTEM
# ==================================================================================================================
static func save_slot(slot: int) -> Dictionary:
	if SaveSystem == null or not SaveSystem.has_method("save_game"):
		return fail("SaveSystem not available")
	var good: bool = SaveSystem.save_game(slot)
	return ok("Saved to slot %d" % slot) if good else fail("Saving slot %d failed" % slot)


static func load_slot(slot: int) -> Dictionary:
	if SaveSystem == null or not SaveSystem.has_method("load_game"):
		return fail("SaveSystem not available")
	if not SaveSystem.has_save(slot):
		return fail("Slot %d is empty" % slot)
	var good: bool = SaveSystem.load_game(slot)
	return ok("Loading slot %d ..." % slot, {"close": true}) if good else fail("Loading slot %d failed" % slot)


static func open_photo_mode() -> Dictionary:
	var g = Game.sys(&"garage")
	if g == null or not g.has_method("start_photo_mode"):
		return fail("Photo mode not available")
	return ok("Photo mode", {"close": true, "defer": "photo"})


static func reset_to_spawn() -> Dictionary:
	var p = _player()
	if p == null or not p.has_method("respawn_at"):
		return fail("No player")
	p.respawn_at(&"player_spawn", {"penalty": 0, "silent": true, "keep_health": true})
	return ok("Back at the spawn plaza", {"close": true})


static func respawn_hospital() -> Dictionary:
	var p = _player()
	if p == null or not p.has_method("respawn_at"):
		return fail("No player")
	p.respawn_at(&"hospital", {"penalty": 0, "reason": &"debug"})
	return ok("Respawned at the hospital", {"close": true})


static func regenerate_traffic() -> Dictionary:
	var t = Game.sys(&"traffic")
	if t == null or not t.has_method("clear_traffic"):
		return fail("Traffic system not booted")
	t.clear_traffic()
	return ok("Traffic cleared - it refills around you in a few seconds" if bool(Game.cheats.get("traffic", true)) else "Traffic cleared (traffic is OFF)")


static func clear_all_dynamic() -> Dictionary:
	var parts: Array[String] = []
	var t = Game.sys(&"traffic")
	if t != null and t.has_method("clear_traffic"):
		t.clear_traffic()
		parts.append("traffic")
	var pd = Game.sys(&"peds")
	if pd != null and pd.has_method("clear_all"):
		pd.clear_all(false)
		parts.append("peds")
	var po = Game.sys(&"police")
	if po != null and po.has_method("despawn_all"):
		po.despawn_all()
		parts.append("police")
	var hm: Node = Game.world.get_node_or_null("HostileManager") if Game.world != null else null
	if hm != null and hm.has_method("clear_all"):
		hm.clear_all()
		parts.append("gangs")
	for m in debug_gang:
		if is_instance_valid(m):
			m.queue_free()
	debug_gang.clear()
	var cur := player_vehicle()
	var vcount := 0
	for v in Game.get_vehicles().duplicate():
		if v == cur or not (v is VehicleBase) or (v as VehicleBase).is_player_owned or (v as VehicleBase).is_in_group(GC.G_POLICE):
			continue
		if (v as VehicleBase).get_meta("air_sea_showcase", false) or (v as VehicleBase).abandoned == false:
			continue
		remove_vehicle(v)
		vcount += 1
	parts.append("%d free vehicles" % vcount)
	return ok("Cleared: " + ", ".join(parts))


static func state_dump() -> String:
	var lines: Array[String] = ["==== STATE DUMP ===="]
	lines.append(stats_text())
	lines.append("cash %s  health %s  armor %s  time %s  weather %s  frozen %s  time_scale %.0f  engine_scale %.2f" % [Util.format_money(Game.cash),
		str(Game.player.health) if _player() != null else "-", str(Game.player.armor) if _player() != null else "-", Util.format_clock(Game.time_of_day),
		String(Game.weather), str(Game.time_frozen), Game.time_scale, Engine.time_scale])
	lines.append("systems: " + ", ".join(Game.systems.keys().map(func(k): return String(k))))
	lines.append("cheats: " + str(Game.cheats))
	var wc = _wc()
	if wc != null:
		lines.append("weapons: " + ", ".join(wc.get_weapon_ids().map(func(k): return String(k))) + "  current " + String(wc.current_id))
	var veh := player_vehicle()
	lines.append("vehicle: " + (("%s hp %d/%d" % [veh.def_id, int(veh.health), int(veh.max_health)]) if veh != null else "none") + "   total vehicles " + str(Game.get_vehicles().size()))
	lines.append("debug gang alive: %d" % debug_gang.size())
	var text := "\n".join(lines)
	print(text)
	return text


## Fast sanity suite -> [[name, ok, detail]]
static func run_self_checks() -> Array:
	var out: Array = []
	var p = _player()
	out.append(["World built (lanes + ped graph)", WorldLayout.built and WorldLayout.lanes.size() > 0 and WorldLayout.ped_graph.size() > 0,
		"%d lane pts, %d ped pts" % [WorldLayout.lanes.size(), WorldLayout.ped_graph.size()]])
	var need_locs := ["player_spawn", "safehouse", "hospital", "police_station", "weapon_shop", "garage_shop", "clothing_store", "gas_station", "dealer_lot",
		"airport_runway_start", "airport_runway_end", "airport_hangar", "helipad_airport", "helipad_downtown", "helipad_hospital", "dock_boat_spawn", "marina_pier",
		"beach_spawn", "viewpoint", "parachute_peak", "shooting_range", "stunt_jump_1", "stunt_jump_2", "stunt_jump_3", "taxi_stand", "train_station_a",
		"train_station_b", "park_center", "barber", "diving_wreck", "scuba_shop"]
	var miss_l: Array = need_locs.filter(func(i): return not WorldLayout.has_location(StringName(i)))
	out.append(["Required locations", miss_l.is_empty(), "missing: " + str(miss_l) if not miss_l.is_empty() else "%d present" % need_locs.size()])
	var miss_s: Array = []
	for k in [&"world", &"environment", &"audio", &"vehicles", &"combat", &"player", &"wanted", &"police", &"traffic", &"peds", &"economy", &"shops", &"garage",
			&"safehouse", &"skills", &"wildlife", &"activities", &"transit", &"emergency", &"ui", &"debug"]:
		if Game.sys(k) == null:
			miss_s.append(String(k))
	out.append(["Systems booted", miss_s.is_empty(), "missing: " + str(miss_s) if not miss_s.is_empty() else "%d systems" % Game.systems.size()])
	out.append(["Player + camera", p != null and Game.gameplay_camera != null and is_instance_valid(Game.gameplay_camera), ""])
	var miss_v: Array = []
	for id in VehicleDefs.implemented_ids():
		if not ModelLib.exists(String(VehicleDefs.get_def(id).get("model", ""))):
			miss_v.append(String(id))
	out.append(["Vehicle models (%d implemented)" % VehicleDefs.implemented_ids().size(), miss_v.is_empty(), "no GLB: " + str(miss_v) if not miss_v.is_empty() else "all GLB"])
	out.append(["Weapon table (16)", WeaponDefs.ids().size() == 16, "%d weapons" % WeaponDefs.ids().size()])
	if p != null and Game.world != null:
		var hit := Util.raycast(Game.world, p.global_position + Vector3.UP, p.global_position + Vector3.DOWN * 20.0, GC.M_GROUND)
		out.append(["Ground under player", not hit.is_empty() or WorldLayout.is_water(p.global_position.x, p.global_position.z), "y %.2f" % p.global_position.y])
	var env = Game.sys(&"environment")
	out.append(["Environment (time/weather API)", env != null and env.has_method("set_time") and env.has_method("set_weather"), "time %s weather %s" % [Util.format_clock(Game.time_of_day), String(Game.weather)]])
	out.append(["UI menu host + debug menu", Game.ui != null and Game.ui.has_menu(&"debug"), ""])
	out.append(["SaveSystem", SaveSystem != null and SaveSystem.has_method("save_game"), ""])
	out.append(["Fallback vehicle models used", VehicleFactory.fallback_used.is_empty(), str(VehicleFactory.fallback_used.keys())])
	if DisplayServer.get_name() != "headless":
		out.append(["Frame rate >= 30", Engine.get_frames_per_second() >= 30, "%d fps" % Engine.get_frames_per_second()])
	return out


static func version_info() -> Array:
	var vi := Engine.get_version_info()
	return [
		["Game", "%s (benchmark build)" % GC.GAME_NAME],
		["Godot", "%s %s" % [String(vi.get("string", "?")), String(vi.get("status", ""))]],
		["Renderer", "%s / %s" % [RenderingServer.get_video_adapter_name(), String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))]],
		["OS", "%s  %s" % [OS.get_name(), DisplayServer.get_name()]],
		["Window", str(DisplayServer.window_get_size())],
		["Systems booted", str(Game.systems.size())],
		["Vehicles / weapons", "%d / %d" % [VehicleDefs.implemented_ids().size(), WeaponDefs.ids().size()]],
	]
