class_name InteriorSystem
extends Node
## Enterable interiors (docs/ARCHITECTURE.md s14.5). Small closed rooms (InteriorRoom) are built lazily on first entry at hidden
## far-away locations; entering through a world door = fade -> player.teleport_to -> camera behind the player -> indoor
## environment (own Environment resource, no rain / fog / sun, AudioSystem space &"interior", street ambience ducked) -> fade in.
## The exit door puts the player back at the exact world door and restores everything.
##
## Owned by ShopSystem (Game.sys(&"shops").interiors) and also registered as Game.sys(&"interiors").
##
## Where the rooms live: ROOM_BASE + (index * ROOM_SPACING, 0, 0) = x -1200 .. , y 12, z -1200 - far outside the map (|x|,|z| > 302),
## NOT at y = -400 as the first draft said: the Player respawns anything below y = -120 ("fell out of the world") and AudioSystem
## switches to the underwater mix for any listener below sea level, so rooms sit slightly above the ground plane instead.
##
## API: register_interior(id, builder: Callable(room), meta := {}) - get_room(id) - enter(id, from_pos, from_yaw) - exit() -
##      switch_to(id) - is_inside() - current_interior - is_open(id) - door_for(id) - serialize()/deserialize()
## Signals: entered(id) exited(id)    Flags: Game.get_meta(&"indoors") bool, Game.get_meta(&"interior_id")

signal entered(id: StringName)
signal exited(id: StringName)

const ROOM_BASE := Vector3(-1200.0, 12.0, -1200.0)
const ROOM_SPACING := 120.0
const FADE_OUT := 0.30
const FADE_IN := 0.42
const OPEN_AT := 6.0
const CLOSE_AT := 23.0
const TOAST_ONLY := {
	&"hospital": "Halcyon General: emergency care only. If you collapse nearby the paramedics will bring you in.",
	&"police_station": "Harbor Police HQ. Nothing to see here, citizen - keep moving.",
}

var current_interior: StringName = &""
var transitioning := false
var last_build_ms := 0.0
var build_log: Dictionary = {}               # id -> {ms, tris, surfaces, props, lights}
var enabled := true

var _defs: Dictionary = {}                   # id -> {builder, meta, index}
var _rooms: Dictionary = {}                  # id -> InteriorRoom
var _order: Array[StringName] = []
var _container: Node3D = null
var _door_container: Node3D = null
var _world_doors: Dictionary = {}            # id -> InteriorDoor
var _toast_doors: Array[InteriorDoor] = []
var _return_pos := Vector3.ZERO
var _return_yaw := 0.0
var _env_saved: Environment = null
var _env_swapped: Environment = null
var _pending_state: Dictionary = {}
var _sanity_t := 0.0
var _sign_t := 0.0
var _doors_built := false
var _signs: Dictionary = {}                  # id -> Label3D
var _sign_open: Dictionary = {}              # id -> bool


# ================================================================================================= lifecycle
func setup(_main: Node) -> void:
	_container = Node3D.new()
	_container.name = "Interiors"
	add_child(_container)
	_door_container = Node3D.new()
	_door_container.name = "WorldDoors"
	add_child(_door_container)
	Game.systems[&"interiors"] = self


func post_setup() -> void:
	InteriorDefs.register_all(self)
	# safehouse rooms register themselves from SafehouseSystem.post_setup()
	create_world_doors()
	# a respawn (death / arrest) while inside an interior: reconcile at once instead of waiting for the next periodic check
	Events.player_respawned.connect(func(_p: Vector3) -> void: _sanity_t = 0.0)


func _process(dt: float) -> void:
	if not enabled:
		return
	if is_inside():
		# the weather system re-shows its rain node every frame: keep it hidden while indoors
		var env = Game.sys(&"environment")
		if env != null:
			var wfx = env.get("weather_fx")
			if wfx is Node3D and (wfx as Node3D).visible:
				(wfx as Node3D).visible = false
	_sanity_t -= dt
	if _sanity_t <= 0.0:
		_sanity_t = 0.4
		_sanity_check()
	_sign_t -= dt
	if _sign_t <= 0.0:
		_sign_t = 1.0
		_refresh_signs()


# ================================================================================================= registry
func register_interior(id: StringName, builder: Callable, meta: Dictionary = {}) -> void:
	if not _defs.has(id):
		_order.append(id)
	_defs[id] = {"builder": builder, "meta": meta, "index": _order.find(id)}
	if _doors_built and meta.has("location"):
		_make_world_door(id, meta)


func has_interior(id: StringName) -> bool:
	return _defs.has(id)


func list_interiors() -> Array[StringName]:
	return _order.duplicate()


func room_origin(id: StringName) -> Vector3:
	var idx := _order.find(id)
	return ROOM_BASE + Vector3(ROOM_SPACING * float(maxi(idx, 0)), 0.0, 0.0)


func get_room(id: StringName, build: bool = true) -> InteriorRoom:
	if _rooms.has(id) and is_instance_valid(_rooms[id]):
		return _rooms[id]
	if not build or not _defs.has(id):
		return null
	return _build_room(id)


func get_current_room() -> InteriorRoom:
	return get_room(current_interior, false) if current_interior != &"" else null


func is_inside() -> bool:
	return current_interior != &""


func _build_room(id: StringName) -> InteriorRoom:
	var t0 := Time.get_ticks_usec()
	var def: Dictionary = _defs[id]
	var room := InteriorRoom.new()
	room.name = "Room_" + String(id)
	room.id = id
	room.display_name = String(def["meta"].get("name", String(id).capitalize()))
	room.position = room_origin(id)
	room.visible = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	_container.add_child(room)
	var builder: Callable = def["builder"]
	if builder.is_valid():
		builder.call(room)
	if room.exit_door != null and not room.exit_door.on_interact.is_valid():
		room.exit_door.on_interact = func(_p: Variant) -> void: exit()
	room.is_built = true
	_rooms[id] = room
	room.build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	last_build_ms = room.build_ms
	var tr := room.tri_report()
	build_log[id] = {"ms": room.build_ms, "tris": int(tr["room"]), "clerk_tris": int(tr["clerk"]), "display_tris": int(tr["display"]), "surfaces": room.count_surfaces(),
		"props": room.props.size(), "lights": room.lights.size()}
	print("[Interiors] built '%s' in %.1f ms (room %d tris, clerk %d, displays %d, %d surfaces, %d lights)" % [id, room.build_ms, tr["room"], tr["clerk"], tr["display"], build_log[id]["surfaces"], room.lights.size()])
	return room


# ================================================================================================= hours
## Closed 23:00 - 06:00 unless the interior's meta says "hours": false (gas station, safehouse). Game.cheats["shops_always_open"] overrides.
func is_open(id: StringName) -> bool:
	var meta: Dictionary = _defs.get(id, {}).get("meta", {})
	if not bool(meta.get("hours", false)):
		return true
	if bool(Game.cheats.get("shops_always_open", false)):
		return true
	var h := Game.time_of_day
	return h >= OPEN_AT and h < CLOSE_AT


func open_text(id: StringName) -> String:
	return "Open" if is_open(id) else "Closed"


# ================================================================================================= world doors
func create_world_doors() -> void:
	if _doors_built:
		return
	_doors_built = true
	for id in _order:
		var meta: Dictionary = _defs[id]["meta"]
		if meta.has("location"):
			_make_world_door(id, meta)
	for loc_id in TOAST_ONLY:
		_make_toast_door(loc_id, String(TOAST_ONLY[loc_id]))


func _find_anchor(landmark: StringName, anchor_name: String) -> Node3D:
	for n in get_tree().get_nodes_in_group(&"landmark_anchor"):
		if n is Node3D and String(n.get_meta(&"landmark", "")) == String(landmark) and String(n.name) == anchor_name:
			return n as Node3D
	return null


## Door position + outward yaw for a location: the GLB `Door` empty when the landmark has one, else the WorldLayout location.
func door_transform(location: StringName, anchor_name: String = "Door", mode: StringName = &"location") -> Dictionary:
	var loc: Dictionary = WorldLayout.get_location(location)
	if loc.is_empty():
		return {}
	var pos: Vector3 = loc["pos"]
	var yaw: float = float(loc.get("yaw", 0.0))
	var out_dir := Util.yaw_to_dir(yaw)
	var anchor := _find_anchor(location, anchor_name)
	var ret := pos
	var door_pos := pos
	if anchor != null:
		if anchor_name != "Door":
			# side doors (GarageDoor ...): the outward direction is where the anchor lies relative to the building origin, snapped to an axis
			var holder := anchor.get_parent() as Node3D
			var rel := anchor.global_position - (holder.global_position if holder != null else pos)
			rel.y = 0.0
			out_dir = Vector3(signf(rel.x), 0.0, 0.0) if absf(rel.x) > absf(rel.z) else Vector3(0.0, 0.0, signf(rel.z))
			yaw = Util.dir_to_yaw(out_dir)
		door_pos = anchor.global_position + out_dir * 0.9
		door_pos.y = pos.y
		if mode == &"anchor":
			ret = anchor.global_position + out_dir * 1.7
			ret.y = pos.y
	return {"door": door_pos, "return": ret, "yaw": yaw, "out": out_dir, "anchor": anchor != null}


func _make_world_door(id: StringName, meta: Dictionary) -> void:
	if _world_doors.has(id):
		return
	var loc: StringName = meta.get("location", id)
	var tf := door_transform(loc, String(meta.get("anchor", "Door")), StringName(meta.get("return_mode", &"location")))
	if tf.is_empty():
		push_warning("InteriorSystem: no WorldLayout location '%s' for interior '%s' - no world door" % [loc, id])
		return
	var door := InteriorDoor.new("Enter", Callable())
	door.name = "Door_" + String(id)
	door.tag = id
	door.interact_range = float(meta.get("range", 2.6))
	door.position = tf["door"]
	door.data = {"return": tf["return"], "yaw": tf["yaw"], "interior": id}
	door.text_provider = func(_p: Variant) -> Dictionary:
		return _world_door_info(id)
	door.on_interact = func(_p: Variant) -> void:
		_world_door_use(id, door)
	_door_container.add_child(door)
	_world_doors[id] = door
	# neon OPEN / CLOSED sign above the door (shops only: a home has no sign, meta "sign": false)
	if not bool(meta.get("sign", true)):
		return
	var sign_node := Label3D.new()
	sign_node.name = "Sign"
	sign_node.font_size = 64
	sign_node.pixel_size = 0.0045
	sign_node.outline_size = 12
	sign_node.shaded = false
	sign_node.double_sided = true
	sign_node.no_depth_test = false
	sign_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign_node.position = Vector3(0, float(meta.get("sign_height", 2.75)), 0)
	sign_node.rotation.y = float(tf["yaw"]) + PI
	door.add_child(sign_node)
	_signs[id] = sign_node
	_sign_open[id] = true
	_update_sign(id)


func _make_toast_door(loc_id: StringName, text: String) -> void:
	var tf := door_transform(loc_id)
	if tf.is_empty():
		return
	var loc: Dictionary = WorldLayout.get_location(loc_id)
	var d := InteriorDoor.new("Entrance", Callable())
	d.name = "ToastDoor_" + String(loc_id)
	d.interact_range = 3.0
	d.position = tf["door"]
	var nm := String(loc.get("name", String(loc_id).capitalize()))
	d.text = nm
	d.on_interact = func(_p: Variant) -> void:
		Game.notify(text, &"info")
		Sfx.play_ui(&"ui_notify")
	_door_container.add_child(d)
	_toast_doors.append(d)


func _world_door_info(id: StringName) -> Dictionary:
	var meta: Dictionary = _defs.get(id, {}).get("meta", {})
	var nm := String(meta.get("name", String(id).capitalize()))
	if is_inside() or transitioning:
		return {}
	if not is_open(id):
		return {"text": "%s - Closed (opens %02d:00)" % [nm, int(OPEN_AT)], "key": "E", "enabled": false}
	return {"text": String(meta.get("prompt", "Enter " + nm)), "key": "E", "enabled": true}


func _world_door_use(id: StringName, door: InteriorDoor) -> void:
	if transitioning or is_inside():
		return
	if not is_open(id):
		Sfx.play_ui(&"ui_error")
		return
	if StringName(Game.wanted_state) == &"pursuit" and Game.wanted_level > 0:
		Game.notify("You can't go in there with the police on your tail.", &"warn")
		Sfx.play_ui(&"ui_error")
		return
	enter(id, door.data.get("return", door.global_position), float(door.data.get("yaw", 0.0)))


func door_for(id: StringName) -> InteriorDoor:
	return _world_doors.get(id, null)


func _refresh_signs() -> void:
	for id in _signs:
		_update_sign(id)


func _update_sign(id: StringName) -> void:
	var l: Label3D = _signs.get(id, null)
	if l == null or not is_instance_valid(l):
		return
	var open := is_open(id)
	if _sign_open.get(id, null) == open and l.text != "":
		return
	_sign_open[id] = open
	l.text = "OPEN" if open else "CLOSED"
	var c := Color("#7be495") if open else Color("#ff4d4d")
	l.modulate = Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 1.0)
	l.outline_modulate = Color(c.r * 0.2, c.g * 0.2, c.b * 0.2, 1.0)


# ================================================================================================= transitions
func _fade(to_black: bool, secs: float, instant: bool) -> void:
	if instant:
		return
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("fade"):
		await ui.fade(to_black, secs)
	else:
		await get_tree().create_timer(secs).timeout


## Enter an interior. `from_pos` / `from_yaw` = the exact world door the player returns to on exit (defaults: where he stands).
## Coroutine: `await interiors.enter(...)` returns true when the player is inside (fade finished). `instant` skips fades / waits.
func enter(id: StringName, from_pos: Vector3 = Vector3.INF, from_yaw: float = NAN, instant: bool = false) -> bool:
	if transitioning or not _defs.has(id):
		return false
	var p = Game.player
	if not is_instance_valid(p) or p.get("is_dead") == true:
		return false
	if p.has_method("is_in_vehicle") and p.is_in_vehicle():
		Game.notify("Get out of your vehicle first.", &"warn")
		return false
	transitioning = true
	Events.interaction_prompt.emit("")
	var lock_prev: bool = bool(p.get("input_locked"))
	p.set("input_locked", true)
	await _fade(true, FADE_OUT, instant)
	var room := get_room(id)
	if room == null:
		await _fade(false, FADE_IN, instant)
		p.set("input_locked", lock_prev)
		transitioning = false
		return false
	var was_inside := is_inside()
	if not was_inside:
		_return_pos = from_pos if from_pos != Vector3.INF else p.global_position
		_return_yaw = from_yaw if not is_nan(from_yaw) else float(p.rotation.y)
	else:
		_hide_room(current_interior)
	_show_room(room)
	current_interior = id
	_apply_indoor(true, room)
	await get_tree().physics_frame
	room.refresh_daylight(Game.daylight())
	var clerk = room.clerk
	if clerk != null and is_instance_valid(clerk) and clerk.has_method("can_respawn") and clerk.can_respawn():
		clerk.respawn()
	_place_player(room.to_global(room.spawn_pos), room.spawn_yaw)
	if not instant:
		await get_tree().create_timer(0.12).timeout
	await _fade(false, FADE_IN, instant)
	p.set("input_locked", lock_prev)
	transitioning = false
	entered.emit(id)
	return true


## Leave the current interior and return to the exact world door.
func exit(instant: bool = false) -> bool:
	if transitioning or not is_inside():
		return false
	var p = Game.player
	if not is_instance_valid(p):
		return false
	transitioning = true
	Events.interaction_prompt.emit("")
	var id := current_interior
	var lock_prev: bool = bool(p.get("input_locked"))
	p.set("input_locked", true)
	await _fade(true, FADE_OUT, instant)
	var ret_pos := _return_pos
	var ret_yaw := _return_yaw
	var from_room := get_room(id, false)
	if from_room != null and from_room.info.has("exit_door_id"):
		var dd := door_for(StringName(from_room.info["exit_door_id"]))
		if dd != null:
			ret_pos = dd.data.get("return", ret_pos)
			ret_yaw = float(dd.data.get("yaw", ret_yaw))
	_hide_room(id)
	current_interior = &""
	_apply_indoor(false, null)
	_place_player(ret_pos, ret_yaw)
	if not instant:
		# the world sectors around the door re-appear within a quarter of a second
		await get_tree().create_timer(0.45).timeout
	await _fade(false, FADE_IN, instant)
	p.set("input_locked", lock_prev)
	transitioning = false
	exited.emit(id)
	return true


## Interior -> interior without going outside (apartment <-> garage). The world return door stays the original one.
func switch_to(id: StringName, instant: bool = false) -> bool:
	if not is_inside():
		return false
	return await enter(id, Vector3.INF, NAN, instant)


func _place_player(pos: Vector3, yaw: float) -> void:
	var p = Game.player
	if not is_instance_valid(p):
		return
	p.teleport_to(pos, yaw)
	var cam = p.get("camera")
	if cam != null and is_instance_valid(cam) and cam.has_method("snap_behind"):
		cam.snap_behind(yaw)
	# the HUD polls the district under the player and would flash "Greenhill Park" on every visit: tell it nothing changed
	var hud = Game.ui.get("hud") if Game.ui != null else null
	if hud != null and "_last_district" in hud:
		hud.set("_last_district", WorldLayout.district_at(pos.x, pos.z))
		hud.set("_district_poll", -0.6)


func _show_room(room: InteriorRoom) -> void:
	room.visible = true
	room.process_mode = Node.PROCESS_MODE_INHERIT


func _hide_room(id: StringName) -> void:
	var room := get_room(id, false)
	if room != null:
		room.visible = false
		room.process_mode = Node.PROCESS_MODE_DISABLED


# ================================================================================================= indoor state
func _make_interior_env(room: InteriorRoom, base: Environment) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = room.theme.get("ambient", Color(0.62, 0.56, 0.5))
	e.ambient_light_energy = float(room.theme.get("ambient_energy", 0.55))
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 2.0
	e.ssao_power = 1.5
	e.ssao_light_affect = 0.2
	e.glow_enabled = true
	e.glow_normalized = false
	e.glow_intensity = 0.55
	e.glow_strength = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.glow_hdr_threshold = 1.0
	e.glow_hdr_scale = 1.6
	for i in 7:
		e.set_glow_level(i, 0.0)
	e.set_glow_level(1, 0.7)
	e.set_glow_level(2, 1.0)
	e.set_glow_level(3, 0.5)
	e.set_glow_level(4, 0.35)
	e.fog_enabled = false
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.12
	if base != null:
		e.tonemap_mode = base.tonemap_mode
		e.tonemap_white = base.tonemap_white
	return e


func _apply_indoor(on: bool, room: InteriorRoom) -> void:
	Game.set_meta(&"indoors", on)
	Game.set_meta(&"interior_id", current_interior if on else &"")
	Game.set_meta(&"npc_interactions_paused", on)
	var env = Game.sys(&"environment")
	if env != null:
		if env.has_method("set_indoors"):
			env.set_indoors(on)
		var we = env.get("world_environment")
		if we is WorldEnvironment:
			var wenv := we as WorldEnvironment
			if on:
				if wenv.environment != _env_swapped:
					_env_saved = wenv.environment          # remember the outdoor environment once (interior -> interior keeps it)
				if room != null:
					_env_swapped = _make_interior_env(room, _env_saved)
					wenv.environment = _env_swapped
			else:
				if _env_swapped != null and wenv.environment == _env_swapped and _env_saved != null:
					wenv.environment = _env_saved
				_env_swapped = null
		var wfx = env.get("weather_fx")
		if wfx is Node3D and not on:
			(wfx as Node3D).visible = true
	var audio = Game.sys(&"audio")
	if audio != null:
		if audio.has_method("set_space"):
			audio.set_space(&"interior" if on else &"auto")
		if audio.has_method("set_duck"):
			audio.set_duck(&"interior", 0.5 if on else 0.0)


# ================================================================================================= self healing
func player_in_interior_space() -> bool:
	var p = Game.player
	if not is_instance_valid(p):
		return false
	var pos: Vector3 = p.global_position
	var max_x := ROOM_BASE.x + ROOM_SPACING * float(maxi(_order.size(), 1)) + 80.0
	return pos.x > ROOM_BASE.x - 80.0 and pos.x < max_x and absf(pos.z - ROOM_BASE.z) < 120.0 and absf(pos.y - ROOM_BASE.y) < 60.0


func _sanity_check() -> void:
	if transitioning:
		return
	var in_space := player_in_interior_space()
	if is_inside() and not in_space:
		# teleported out by something else (death respawn, debug teleport, load): drop the indoor state silently
		var id := current_interior
		_hide_room(id)
		current_interior = &""
		_apply_indoor(false, null)
		exited.emit(id)
	elif not is_inside() and in_space and not _order.is_empty():
		# loaded a save made inside an interior (or teleported in): rebuild the room under the player and adopt it
		var p = Game.player
		var idx := clampi(int(round((p.global_position.x - ROOM_BASE.x) / ROOM_SPACING)), 0, _order.size() - 1)
		var id2: StringName = _order[idx]
		if _pending_state.has("return"):
			var r: Array = _pending_state["return"]
			if r.size() == 3:
				_return_pos = Vector3(r[0], r[1], r[2])
				_return_yaw = float(_pending_state.get("yaw", 0.0))
		else:
			var d := door_for(id2)
			if d != null:
				_return_pos = d.data.get("return", d.global_position)
				_return_yaw = float(d.data.get("yaw", 0.0))
			else:
				_return_pos = WorldLayout.location_pos(&"player_spawn") if WorldLayout.has_location(&"player_spawn") else Vector3(14, 0.3, 38)
		var room := get_room(id2)
		if room != null:
			_show_room(room)
			current_interior = id2
			_apply_indoor(true, room)
			room.refresh_daylight(Game.daylight())
			print("[Interiors] adopted '%s' after load / teleport" % id2)


# ================================================================================================= save
func serialize() -> Dictionary:
	if not is_inside():
		return {}
	return {"inside": String(current_interior), "return": [_return_pos.x, _return_pos.y, _return_pos.z], "yaw": _return_yaw}


func deserialize(data: Dictionary) -> void:
	_pending_state = data.duplicate()


func get_stats() -> Dictionary:
	return {"registered": _order.size(), "built": _rooms.size(), "inside": String(current_interior), "build_log": build_log}
