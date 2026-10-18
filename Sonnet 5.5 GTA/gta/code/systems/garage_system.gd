class_name GarageSystem
extends Node
## Garage / vehicle customization / stored vehicles / phone / photo mode (Garage agent).  Boot key `garage` (Game.sys(&"garage")).
##
## * Customization garage at the `garage_shop` landmark: drive a car or bike into a bay -> "[E] Customize" -> GarageSession
##   (studio + orbit camera + GarageMenu: repair, paint, wheels, body parts, lights, windows, plates, livery, horn, performance).
## * Stored vehicles: 6 slots (store / deliver / remove / serialize), dealer-lot purchase flow, safehouse garage door hook.
## * Phone (P) -> PhoneMenu, Photo mode (F3 / phone camera) -> PhotoMode.
## * Prices are real cash (Game.spend_cash). `unlock_all = true` or Game.cheats["unlock_all_mods"] makes everything free.
## Public API is documented in docs/api/garage_phone.md.

signal stored_changed()
signal session_started(vehicle: VehicleBase)
signal session_ended(vehicle: VehicleBase)
signal vehicle_delivered(slot: int, vehicle: VehicleBase)

const MAX_SLOTS := 6
const BAY_HALF_WIDTH := 3.5
const DELIVERY_INSURANCE := 500

var unlock_all := false
var stored: Array = []                 # MAX_SLOTS entries: Dictionary record or null
var sites: Array = []                  # [{id, kind, name, bays:[{entry, inside}], pos}]
var session: GarageSession = null
var photo: PhotoMode = null
var out_vehicles: Dictionary = {}      # slot -> VehicleBase currently in the world
var pending_delivery: Dictionary = {}  # slot -> true while a delivery countdown runs

var _tick := 0.0
var _prompt_text := ""
var _prompt_refresh := 0.0
var _bay_vehicle: VehicleBase = null
var _bay_site: Dictionary = {}
var _bay_index := 0
var _dealer_scan := 0.0
var _sites_ready := false
var _main: Node = null


# =====================================================================================================
# Lifecycle
# =====================================================================================================
func setup(main: Node) -> void:
	_main = main
	process_mode = Node.PROCESS_MODE_ALWAYS
	stored.resize(MAX_SLOTS)
	for i in MAX_SLOTS:
		stored[i] = null
	VehicleModsVisual.install()


func post_setup() -> void:
	var ui = Game.ui
	if ui != null:
		ui.register_menu(&"garage", GarageMenu.new())
		ui.register_menu(&"garage_stored", GarageStoredMenu.new())
		ui.register_menu(&"phone", PhoneMenu.new())
	photo = PhotoMode.new()
	photo.name = "PhotoMode"
	add_child(photo)
	Events.vehicle_destroyed.connect(_on_vehicle_destroyed)
	_discover_sites_async()


func _discover_sites_async() -> void:
	var waited := 0
	while not WorldLayout.built and waited < 600:
		await get_tree().process_frame
		waited += 1
	for i in 30:
		await get_tree().process_frame
	_discover_sites()


func _discover_sites() -> void:
	sites.clear()
	var anchors: Dictionary = {}                      # landmark -> {anchor name -> pos}
	for n in get_tree().get_nodes_in_group(&"landmark_anchor"):
		if not (n is Node3D):
			continue
		var lm := String(n.get_meta(&"landmark", ""))
		if lm == "":
			continue
		if not anchors.has(lm):
			anchors[lm] = {}
		anchors[lm][String(n.name)] = (n as Node3D).global_position
	# ---- customization garage (two drive-in bays)
	var gs: Dictionary = WorldLayout.get_location(&"garage_shop")
	if not gs.is_empty() or anchors.has("garage_shop"):
		var a: Dictionary = anchors.get("garage_shop", {})
		var base: Vector3 = gs.get("pos", Vector3.ZERO)
		var yaw: float = float(gs.get("yaw", 0.0))
		var rot := Basis(Vector3.UP, yaw)
		var bays: Array = []
		for suffix in ["", "_B"]:
			var e: Variant = a.get("BayEntry" + suffix, null)
			var inside: Variant = a.get("BayInside" + suffix, null)
			if e == null or inside == null:
				var sx := 1.0 if suffix == "_B" else -1.0
				e = base + rot * Vector3(8.0 * sx, 0.0, 6.0)
				inside = base + rot * Vector3(8.0 * sx, 0.0, 14.5)
				push_warning("GarageSystem: garage_shop bay anchors missing - using location offsets")
			bays.append({"entry": e, "inside": inside})
		sites.append({"id": &"garage_shop", "kind": &"shop", "name": String(gs.get("name", VehicleModsData.SHOP_NAME)), "bays": bays})
	# ---- safehouse garage door (store / retrieve)
	var sh: Dictionary = anchors.get("safehouse", {})
	if sh.has("GarageDoor"):
		sites.append({"id": &"safehouse", "kind": &"store", "name": "Safehouse Garage", "pos": sh["GarageDoor"], "bays": []})
	elif WorldLayout.has_location(&"safehouse"):
		sites.append({"id": &"safehouse", "kind": &"store", "name": "Safehouse Garage", "pos": WorldLayout.location_pos(&"safehouse") + Vector3(8.0, 0.0, 6.0), "bays": []})
	_sites_ready = true
	print("[Garage] %d sites discovered (%s)" % [sites.size(), ", ".join(sites.map(func(s): return String(s["id"])))])


# =====================================================================================================
# Frame loop: bay prompt, dealer interactables
# =====================================================================================================
func _process(dt: float) -> void:
	_tick -= dt
	if _tick > 0.0:
		return
	_tick = 0.12
	_dealer_scan -= 0.12
	if _dealer_scan <= 0.0:
		_dealer_scan = 2.5
		_refresh_dealer_points()
	_update_bay_prompt()


func _update_bay_prompt() -> void:
	var want := ""
	_bay_vehicle = null
	if _sites_ready and session == null and is_instance_valid(Game.player) and (photo == null or not photo.active):
		var p = Game.player
		var ui = Game.ui
		var blocked: bool = ui != null and ui.has_method("is_input_blocked") and ui.is_input_blocked()
		if not blocked and p.has_method("is_in_vehicle") and p.is_in_vehicle() and not bool(p.get("is_dead")):
			var v = p.get("current_vehicle")
			if v is VehicleBase and v.driver == p and can_customize(v):
				for s in sites:
					if s["kind"] == &"shop":
						var bi := _bay_index_of(s, v)
						if bi >= 0 and v.get_speed_kmh() < 14.0:
							_bay_vehicle = v
							_bay_site = s
							_bay_index = bi
							want = "[E] Customize %s" % v.display_name
							break
					elif s["kind"] == &"store":
						if Util.dist_xz((s["pos"] as Vector3), v.global_position) < 6.0 and v.get_speed_kmh() < 14.0:
							_bay_vehicle = v
							_bay_site = s
							_bay_index = -1
							want = "[E] Garage - store %s" % v.display_name
							break
	_prompt_refresh -= 0.12
	if want != _prompt_text or (want != "" and _prompt_refresh <= 0.0):
		if want != "" or _prompt_text != "":
			Events.interaction_prompt.emit(want)
		_prompt_text = want
		_prompt_refresh = 0.5


## Index of the bay of `site` that contains the vehicle (driven inside), or -1.
func _bay_index_of(site: Dictionary, v: Node3D) -> int:
	var pos := v.global_position
	var bays: Array = site["bays"]
	for i in bays.size():
		var e: Vector3 = bays[i]["entry"]
		var inside: Vector3 = bays[i]["inside"]
		var dir := Util.flat(inside - e)
		var len_ := dir.length()
		if len_ < 0.5:
			continue
		dir /= len_
		var perp := Vector3(-dir.z, 0.0, dir.x)
		var rel := Util.flat(pos - e)
		var t := rel.dot(dir)
		var lat := absf(rel.dot(perp))
		if t > 0.8 and t < len_ + 4.0 and lat < BAY_HALF_WIDTH and absf(pos.y - e.y) < 3.0:
			return i
	return -1


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventMouseButton) or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"phone"):
		toggle_phone()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact") and _bay_vehicle != null and session == null:
		var v := _bay_vehicle
		var s := _bay_site
		var bi := _bay_index
		get_viewport().set_input_as_handled()
		if s["kind"] == &"shop":
			begin_session(v, s, bi)
		else:
			open_stored_menu(s["id"])


# =====================================================================================================
# Phone / photo mode entry points
# =====================================================================================================
func toggle_phone() -> void:
	var ui = Game.ui
	if ui == null:
		return
	if ui.current_menu_id == &"phone":
		ui.close_menu()
		return
	if not phone_available():
		return
	ui.open_menu(&"phone")


func phone_available() -> bool:
	var ui = Game.ui
	if ui == null or session != null or (photo != null and photo.active):
		return false
	if not is_instance_valid(Game.player) or bool(Game.player.get("is_dead")):
		return false
	if ui.is_input_blocked():
		return false
	if ui.death != null and ui.death.is_active():
		return false
	return true


func start_photo_mode() -> void:
	if photo != null and not photo.active:
		photo.enter()


# =====================================================================================================
# Pricing helpers
# =====================================================================================================
func is_free() -> bool:
	return unlock_all or bool(Game.cheats.get("unlock_all_mods", false))


func can_customize(v: Node) -> bool:
	if not (v is VehicleBase):
		return false
	var vb := v as VehicleBase
	if vb.is_destroyed or vb.is_flipped_over():
		return false
	if vb.vclass != GC.VC_CAR and vb.vclass != GC.VC_BIKE and vb.vclass != GC.VC_BICYCLE:
		return false
	return VehicleDefs.is_implemented(vb.def_id)


## Cost entries of a pending build against the committed one (see GarageBuild.diff_against).
func quote(base: GarageBuild, target: GarageBuild) -> Array:
	return target.diff_against(base, true, VehicleModsData.price_mult(target.def_id), is_free())


## Charges the entries (spend_cash) - returns false and does nothing when the player cannot afford it.
func charge(entries: Array) -> bool:
	var total := GarageBuild.total_cost(entries)
	if total <= 0:
		return true
	if not Game.spend_cash(total):
		return false
	if Sfx != null:
		Sfx.play_ui(&"ui_cash")
	return true


func repair_needed(v: VehicleBase) -> bool:
	if v.get_health_ratio() < 0.995:
		return true
	for w in v.wheels:
		if w.flat:
			return true
	return v.dmg != null and (v.dmg.glass_state > 0 or v.on_fire)


func repair_cost(v: VehicleBase) -> int:
	if not repair_needed(v):
		return 0
	var base := float(v.def.get("price", 0))
	if base <= 0.0:
		base = 12000.0
	var dmg := 1.0 - v.get_health_ratio()
	var cost := dmg * clampf(base * 0.12, 150.0, 5000.0)
	for w in v.wheels:
		if w.flat:
			cost += 60.0
	if v.dmg != null:
		cost += 90.0 * float(v.dmg.glass_state)
	cost = maxf(cost, 25.0)
	return int(round(cost / 5.0)) * 5


## Repairs everything (health, tyres, glass, lights, handling damage) and charges `repair_cost` unless free. Returns success.
func repair_vehicle(v: VehicleBase, charge_money: bool = true) -> bool:
	if v == null or not is_instance_valid(v):
		return false
	var cost := repair_cost(v)
	if charge_money and cost > 0 and not is_free():
		if not Game.spend_cash(cost):
			Game.notify("Not enough cash for the repair (%s)." % Util.format_money(cost), &"bad")
			return false
		if Sfx != null:
			Sfx.play_ui(&"ui_cash")
	v.repair()
	return true


# =====================================================================================================
# Stored vehicles
# =====================================================================================================
func get_stored_vehicles() -> Array:
	var out: Array = []
	for i in MAX_SLOTS:
		if stored[i] != null:
			var r: Dictionary = (stored[i] as Dictionary).duplicate()
			r["slot"] = i
			r["out"] = out_vehicles.has(i) and is_instance_valid(out_vehicles[i]) and not (out_vehicles[i] as VehicleBase).is_destroyed
			out.append(r)
	return out


func get_record(slot: int) -> Dictionary:
	if slot < 0 or slot >= MAX_SLOTS or stored[slot] == null:
		return {}
	return stored[slot]


func free_slot_count() -> int:
	var n := 0
	for i in MAX_SLOTS:
		if stored[i] == null:
			n += 1
	return n


func _free_slot() -> int:
	for i in MAX_SLOTS:
		if stored[i] == null:
			return i
	return -1


func _record_from(v: VehicleBase, slot: int) -> Dictionary:
	var b := GarageBuild.from_vehicle(v)
	if not b.mods.has("plate_text"):
		b.mods["plate_text"] = VehicleModsData.random_plate_text(Game.rng)
	return {"def": String(v.def_id), "name": v.display_name, "build": b.to_dict(), "health": v.get_health_ratio(), "slot": slot,
		"plate": String(b.mods.get("plate_text", ""))}


## Stores a vehicle in the garage (a free slot, or its own slot when it was delivered from one). Returns the slot or -1.
## The vehicle is removed from the world (the player is moved out first).
func store(v: VehicleBase) -> int:
	if v == null or not is_instance_valid(v) or v.is_destroyed or not can_customize(v):
		return -1
	var slot := int(v.get_meta(&"garage_slot", -1))
	if slot < 0 or slot >= MAX_SLOTS or (stored[slot] != null and out_vehicles.get(slot, null) != v):
		slot = _free_slot()
	if slot < 0:
		Game.notify("Your garage is full (%d/%d). Remove a vehicle from the phone first." % [MAX_SLOTS, MAX_SLOTS], &"warn")
		return -1
	var rec := _record_from(v, slot)
	stored[slot] = rec
	v.is_player_owned = true
	v.set_meta(&"garage_slot", slot)
	for c in v.get_occupants():
		v.exit(c, false)
	out_vehicles.erase(slot)
	pending_delivery.erase(slot)
	VehicleFactory.despawn(v)
	Game.notify("%s stored in garage slot %d." % [rec["name"], slot + 1], &"good")
	stored_changed.emit()
	return slot


## Adds a brand new vehicle (purchase) to a free slot without spawning it. Returns the slot or -1.
func add_record(def_id: StringName, paint1: Color, paint2: Color, finish: StringName = &"gloss", mods: Dictionary = {}) -> int:
	var slot := _free_slot()
	if slot < 0 or not VehicleDefs.has(def_id):
		return -1
	var b := GarageBuild.new()
	b.def_id = def_id
	b.paint1 = paint1
	b.paint2 = paint2
	b.finish = finish
	b.mods = mods.duplicate(true)
	b.mods["plate_text"] = VehicleModsData.random_plate_text(Game.rng)
	stored[slot] = {"def": String(def_id), "name": String(VehicleDefs.get_def(def_id).get("name", def_id)), "build": b.to_dict(), "health": 1.0, "slot": slot,
		"plate": String(b.mods["plate_text"])}
	stored_changed.emit()
	return slot


func remove(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS or stored[slot] == null:
		return false
	var name_ := String(stored[slot]["name"])
	stored[slot] = null
	if out_vehicles.has(slot) and is_instance_valid(out_vehicles[slot]):
		(out_vehicles[slot] as VehicleBase).is_player_owned = false
		(out_vehicles[slot] as VehicleBase).remove_meta(&"garage_slot")
	out_vehicles.erase(slot)
	pending_delivery.erase(slot)
	Game.notify("%s removed from your garage." % name_, &"info")
	stored_changed.emit()
	return true


## Spawns the stored vehicle near the player on a drivable road point out of view after `delay` seconds (phone toast on arrival).
## Coroutine: `var v = await garage.deliver(slot)`. Returns the VehicleBase (or null).
func deliver(slot: int, delay: float = 4.0) -> VehicleBase:
	var rec := get_record(slot)
	if rec.is_empty():
		return null
	if out_vehicles.has(slot) and is_instance_valid(out_vehicles[slot]) and not (out_vehicles[slot] as VehicleBase).is_destroyed:
		_announce_existing(slot)
		return out_vehicles[slot]
	if pending_delivery.has(slot):
		Game.notify("%s is already on its way." % rec["name"], &"info")
		return null
	pending_delivery[slot] = true
	Game.notify("Vehicle service: your %s will arrive shortly." % rec["name"], &"info")
	if delay > 0.0:
		await get_tree().create_timer(delay, true, false, true).timeout
	pending_delivery.erase(slot)
	if get_record(slot).is_empty():
		return null
	return deliver_now(slot)


func _announce_existing(slot: int) -> void:
	var v: VehicleBase = out_vehicles[slot]
	Game.notify("Your %s is already out - waypoint set." % v.display_name, &"info")
	if Game.ui != null and Game.ui.has_method("set_waypoint"):
		Game.ui.set_waypoint(v.global_position)


func deliver_now(slot: int, at: Variant = null, silent: bool = false) -> VehicleBase:
	var rec := get_record(slot)
	if rec.is_empty():
		return null
	if out_vehicles.has(slot) and is_instance_valid(out_vehicles[slot]):
		var existing: VehicleBase = out_vehicles[slot]
		if not existing.is_destroyed:
			return existing
		# destroyed: insurance replacement
		if not is_free() and not Game.spend_cash(DELIVERY_INSURANCE):
			Game.notify("Insurance replacement costs %s." % Util.format_money(DELIVERY_INSURANCE), &"bad")
			return null
		if not is_free():
			Game.notify("Insurance replacement: %s" % Util.format_money(DELIVERY_INSURANCE), &"info")
		rec["health"] = 1.0
	var xf: Transform3D = at if at is Transform3D else _pick_delivery_transform()
	var b := GarageBuild.from_dict(rec["build"])
	var v := VehicleFactory.spawn(b.def_id, xf, {"paint": b.paint1, "paint2": b.paint2, "finish": b.finish, "mods": b.mods.duplicate(true),
		"health_ratio": clampf(float(rec.get("health", 1.0)), 0.05, 1.0), "owned": true, "abandoned": true, "engine_on": false})
	if v == null:
		Game.notify("Vehicle service failed - no room to deliver.", &"bad")
		return null
	v.is_player_owned = true
	v.take_for_player(true)
	v.set_meta(&"garage_slot", slot)
	out_vehicles[slot] = v
	if not silent:
		Game.notify("Your %s has been delivered. Waypoint set." % rec["name"], &"good")
		if Game.ui != null and Game.ui.has_method("set_waypoint"):
			Game.ui.set_waypoint(v.global_position)
	vehicle_delivered.emit(slot, v)
	return v


func _pick_delivery_transform() -> Transform3D:
	var ppos := Game.get_player_position()
	var lanes = WorldLayout.lanes
	var cam: Camera3D = Game.gameplay_camera
	if lanes != null and lanes.size() > 0:
		var fallback := -1
		for attempt in 16:
			var idx: int = lanes.random_point_in_ring(ppos, 50.0 + float(attempt) * 3.0, 130.0, Game.rng, 12)
			if idx < 0:
				continue
			var p: Vector3 = lanes.positions[idx]
			if Game.nearest_in_group(GC.G_VEHICLE, p, 7.0) != null:
				continue
			if fallback < 0:
				fallback = idx
			var visible_now := false
			if cam != null and is_instance_valid(cam):
				visible_now = cam.is_position_in_frustum(p + Vector3.UP) and not _blocked_view(cam.global_position, p)
			if not visible_now:
				return Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(lanes.dirs[idx])), p + Vector3.UP * 0.3)
		if fallback >= 0:
			return Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(lanes.dirs[fallback])), (lanes.positions[fallback] as Vector3) + Vector3.UP * 0.3)
	var pl = Game.player
	if pl is Node3D:
		var f: Vector3 = -(pl as Node3D).global_transform.basis.z
		return Transform3D((pl as Node3D).global_transform.basis, ppos + f * 14.0 + Vector3.UP * 0.6)
	return Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))


func _blocked_view(from: Vector3, to: Vector3) -> bool:
	if _main == null or not (_main is Node3D):
		return false
	return not Util.has_line_of_sight(_main as Node3D, from, to + Vector3.UP, GC.M_LOS)


func _on_vehicle_destroyed(v: Node, _killer: Node) -> void:
	if v is VehicleBase and v.has_meta(&"garage_slot"):
		var slot := int(v.get_meta(&"garage_slot"))
		if out_vehicles.get(slot, null) == v:
			Game.notify("Your %s was destroyed. Request it again from the phone (insurance %s)." % [v.display_name, Util.format_money(DELIVERY_INSURANCE)], &"warn")


# =====================================================================================================
# Dealer lot purchases
# =====================================================================================================
func _refresh_dealer_points() -> void:
	var vs = Game.sys(&"vehicles")
	if vs == null:
		return
	for v in vs.dealer_vehicles:
		if not is_instance_valid(v) or not v.is_inside_tree():
			continue
		if v.get_node_or_null("GarageDealerPoint") != null:
			continue
		if int(v.def.get("price", 0)) <= 0:
			continue
		var gi := GarageInteractable.new()
		gi.name = "GarageDealerPoint"
		gi.kind = &"dealer"
		gi.vehicle = v
		gi.interact_range = maxf(3.4, float(v.def.get("length", 4.5)) * 0.5 + 1.2)
		v.add_child(gi)


## "[E] Buy" on a showroom vehicle: pays VehicleDefs price and stores a copy in the garage. Returns the slot or -1.
func buy_dealer_vehicle(v: VehicleBase) -> int:
	if v == null or not is_instance_valid(v):
		return -1
	var price := int(v.def.get("price", 0))
	if price <= 0:
		Game.notify("%s is not for sale." % v.display_name, &"warn")
		return -1
	return buy_vehicle(v.def_id, v.paint_primary, v.paint_secondary, v.paint_finish)


func buy_vehicle(def_id: StringName, paint1: Color, paint2: Color, finish: StringName = &"gloss") -> int:
	var def := VehicleDefs.get_def(def_id)
	if def.is_empty() or not VehicleDefs.is_implemented(def_id):
		return -1
	if free_slot_count() <= 0:
		Game.notify("Your garage is full (%d/%d). Remove a vehicle from the phone first." % [MAX_SLOTS, MAX_SLOTS], &"warn")
		return -1
	var price := int(def.get("price", 0))
	if not is_free() and not Game.spend_cash(price):
		Game.notify("Not enough cash: %s costs %s." % [def["name"], Util.format_money(price)], &"bad")
		if Sfx != null:
			Sfx.play_ui(&"ui_error")
		return -1
	if not is_free() and Sfx != null:
		Sfx.play_ui(&"ui_cash")
	var slot := add_record(def_id, paint1, paint2, finish)
	if slot < 0:
		return -1
	Game.notify("Purchased %s - stored in garage slot %d. Call vehicle service on your phone (P)." % [def["name"], slot + 1], &"good")
	return slot


# =====================================================================================================
# Garage session (studio)
# =====================================================================================================
func begin_session(v: VehicleBase, site: Dictionary, bay: int = 0) -> void:
	if session != null or v == null or not can_customize(v):
		return
	var s := GarageSession.new()
	session = s
	s.name = "GarageSession"
	_main.add_child(s)
	_bay_vehicle = null
	if _prompt_text != "":
		Events.interaction_prompt.emit("")
		_prompt_text = ""
	session_started.emit(v)
	await s.begin(self, v, site, bay)


func _on_session_finished(v: VehicleBase) -> void:
	session = null
	session_ended.emit(v)


func open_stored_menu(site_id: StringName = &"") -> void:
	if Game.ui != null and session == null:
		Game.ui.open_menu(&"garage_stored", {"site": site_id})


# =====================================================================================================
# Persistence (SaveSystem collects serialize() / deserialize())
# =====================================================================================================
func serialize() -> Dictionary:
	var recs: Array = []
	for i in MAX_SLOTS:
		var r = stored[i]
		if r == null:
			recs.append(null)
			continue
		var rec: Dictionary = (r as Dictionary).duplicate(true)
		var ov = out_vehicles.get(i, null)
		if ov is VehicleBase and is_instance_valid(ov) and not (ov as VehicleBase).is_destroyed:
			var live := _record_from(ov, i)
			rec["build"] = live["build"]
			rec["health"] = live["health"]
			var p := (ov as VehicleBase).global_position
			rec["out"] = {"pos": [p.x, p.y, p.z], "yaw": (ov as VehicleBase).global_rotation.y}
		else:
			rec.erase("out")
		recs.append(rec)
	return {"version": 1, "slots": recs}


func deserialize(data: Dictionary) -> void:
	for i in MAX_SLOTS:
		var ov = out_vehicles.get(i, null)
		if ov is VehicleBase and is_instance_valid(ov):
			VehicleFactory.despawn(ov)
		stored[i] = null
	out_vehicles.clear()
	pending_delivery.clear()
	var slots = data.get("slots", [])
	if slots is Array:
		for i in mini(slots.size(), MAX_SLOTS):
			if slots[i] is Dictionary and (slots[i] as Dictionary).has("build"):
				stored[i] = slots[i]
	stored_changed.emit()
	_respawn_out_vehicles()


func _respawn_out_vehicles() -> void:
	for i in MAX_SLOTS:
		var rec = stored[i]
		if rec == null or not (rec as Dictionary).has("out"):
			continue
		var o: Dictionary = rec["out"]
		var pa: Array = o.get("pos", [0, 1, 0])
		var xf := Transform3D(Basis(Vector3.UP, float(o.get("yaw", 0.0))), Vector3(float(pa[0]), float(pa[1]) + 0.2, float(pa[2])))
		deliver_now(i, xf, true)
