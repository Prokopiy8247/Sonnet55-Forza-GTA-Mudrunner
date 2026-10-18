class_name SafehouseSystem
extends Node
## The player's safehouse (WorldLayout location `safehouse`): an apartment (bed -> sleep / time skip with fade + full heal, wardrobe ->
## free outfit changes, nightstand -> save point, TV, fridge snack, stairs to the garage) and a 3-bay garage (stored vehicles shown in the
## bays, console lists them and brings one out onto the street). Respawn option: after a knock-out the player wakes up at the safehouse
## instead of the hospital (Game.player meta `respawn_at_safehouse`, toggle in the sleep menu).
## Interiors are built lazily by the shared InteriorSystem (Game.sys(&"interiors")).
##
## API: enter_apartment() enter_garage() open_sleep_menu() sleep(kind) save_game() toggle_tv() snack() open_wardrobe() open_garage_menu()
##      bring_out_vehicle(slot) set_respawn_here(bool) serialize()/deserialize()

signal slept(hours: float, wake_hour: float)
signal game_saved()

const SLEEP_OPTIONS := {
	&"night": {"label": "Sleep until morning", "hour": 7.0, "heal": 1.0},
	&"nap": {"label": "Take a nap", "hours": 3.0, "heal": 0.4},
	&"evening": {"label": "Rest until evening", "hour": 18.5, "heal": 0.6},
}
const SNACK_COOLDOWN_S := 60.0
const SNACK_HEAL := 25.0

var owned := true
var respawn_here := true
var tv_on := false
var last_saved_unix := 0.0
var interiors: InteriorSystem = null
var menus: Dictionary = {}
var sleeping := false

var _tv_mat: StandardMaterial3D = null
var _tv_t := 0.0
var _snack_ready_at := 0.0
var _cash_at_death := 0


func setup(_main: Node) -> void:
	pass


func post_setup() -> void:
	var shops = Game.sys(&"shops")
	var it = Game.sys(&"interiors")
	if it is InteriorSystem:
		interiors = it
	elif shops != null:
		interiors = shops.get("interiors")
	if interiors == null:
		push_warning("SafehouseSystem: no InteriorSystem - safehouse disabled")
		return
	interiors.register_interior(&"safehouse", Callable(self, "_build_apartment"),
		{"name": "Safehouse", "location": &"safehouse", "anchor": "Door", "hours": false, "prompt": "Enter Safehouse", "range": 2.8, "sign": false})
	interiors.register_interior(&"safehouse_garage", Callable(self, "_build_garage"),
		{"name": "Safehouse Garage", "location": &"safehouse", "anchor": "GarageDoor", "return_mode": &"anchor", "hours": false,
		"prompt": "Enter Garage", "sign_height": 2.4, "range": 3.2, "sign": false})
	interiors.entered.connect(_on_interior_entered)
	var ui = Game.ui
	if ui != null and ui.has_method("register_menu"):
		menus[&"safehouse_sleep"] = SafehouseSleepMenu.new()
		menus[&"safehouse_garage_menu"] = SafehouseGarageMenu.new()
		for id in menus:
			ui.register_menu(id, menus[id])
	Events.player_died.connect(func() -> void: _cash_at_death = Game.cash)
	Events.player_respawned.connect(_on_player_respawned)
	call_deferred("_sync_flag")


func _sync_flag() -> void:
	var p = Game.player
	if is_instance_valid(p):
		p.set_meta(&"respawn_at_safehouse", owned and respawn_here)
		if "respawn_at_safehouse" in p:
			p.set("respawn_at_safehouse", owned and respawn_here)


func set_respawn_here(on: bool) -> void:
	respawn_here = on
	_sync_flag()
	Game.notify("You will wake up %s after a knock-out." % ("at your safehouse" if on else "at the hospital"), &"info")


func _process(dt: float) -> void:
	if tv_on and _tv_mat != null and interiors != null and interiors.current_interior == &"safehouse":
		_tv_t += dt
		var c := Color.from_hsv(fmod(_tv_t * 0.07 + floorf(_tv_t / 2.2) * 0.23, 1.0), 0.55, 1.0)
		var flick := 0.85 + 0.15 * sin(_tv_t * 17.0) * sin(_tv_t * 5.3)
		_tv_mat.emission = c
		_tv_mat.emission_energy_multiplier = 1.4 * flick
		var room := interiors.get_current_room()
		if room != null and room.info.has("tv_light"):
			var l: OmniLight3D = room.info["tv_light"]
			l.light_color = c
			l.light_energy = 0.9 * flick


# ================================================================================================= rooms
func _build_apartment(room: InteriorRoom) -> void:
	InteriorSafehouse.build_apartment(room)
	var tv = room.info.get("tv", null)
	if tv != null and is_instance_valid(tv):
		_tv_mat = StandardMaterial3D.new()
		_tv_mat.albedo_color = Color("#080b10")
		_tv_mat.roughness = 0.15
		_tv_mat.metallic = 0.2
		Util.replace_material(tv, "NeonScreen", _tv_mat)
		_apply_tv_state(room)


func _build_garage(room: InteriorRoom) -> void:
	InteriorSafehouse.build_garage(room)


func _on_interior_entered(id: StringName) -> void:
	if id == &"safehouse_garage":
		var room := interiors.get_room(id, false)
		var garage = Game.sys(&"garage")
		var recs: Array = []
		if room != null and garage != null and garage.has_method("get_stored_vehicles"):
			recs = garage.get_stored_vehicles()
			InteriorSafehouse.refresh_garage_display(room, recs)
	elif id == &"safehouse":
		var room2 := interiors.get_room(id, false)
		if room2 != null:
			_apply_tv_state(room2)


func enter_apartment() -> void:
	if interiors != null:
		interiors.switch_to(&"safehouse")


func enter_garage() -> void:
	if interiors != null:
		interiors.switch_to(&"safehouse_garage")


# ================================================================================================= apartment actions
func open_sleep_menu() -> void:
	if Game.ui != null:
		Game.ui.open_menu(&"safehouse_sleep", {})


func open_wardrobe() -> void:
	var shops = Game.sys(&"shops")
	if shops != null:
		shops.open_menu(&"wardrobe", interiors.get_current_room() if interiors != null else null)


func open_garage_menu() -> void:
	if Game.ui != null:
		Game.ui.open_menu(&"safehouse_garage_menu", {})


## kind: &"night" (until 07:00, full heal) / &"nap" (3 h, +40% health) / &"evening" (18:30). Fade, set the clock through
## EnvironmentSystem.set_time, heal. Coroutine: `await safehouse.sleep(&"night")`. Returns the hours that passed.
func sleep(kind: StringName = &"night", instant: bool = false) -> float:
	if sleeping or not SLEEP_OPTIONS.has(kind):
		return 0.0
	sleeping = true
	var opt: Dictionary = SLEEP_OPTIONS[kind]
	var now := Game.time_of_day
	var target: float = float(opt["hour"]) if opt.has("hour") else fposmod(now + float(opt["hours"]), 24.0)
	var passed := fposmod(target - now, 24.0)
	if passed < 0.5 and opt.has("hour"):
		passed += 24.0
	if Game.ui != null and Game.ui.is_menu_open():
		Game.ui.close_menu()
	await get_tree().process_frame
	var ui = Game.ui
	if not instant and ui != null and ui.has_method("fade"):
		await ui.fade(true, 0.9)
	var env = Game.sys(&"environment")
	if env != null and env.has_method("set_time"):
		env.set_time(target)
	else:
		Game.time_of_day = target
		Events.time_changed.emit(target)
	var p = Game.player
	if is_instance_valid(p):
		var mh := float(p.get("max_health"))
		p.heal(mh * float(opt["heal"]))
		if kind != &"nap":
			p.set("stamina", float(p.get("max_stamina")))
	if not instant:
		await get_tree().create_timer(0.9).timeout
		if ui != null and ui.has_method("fade"):
			await ui.fade(false, 1.1)
	sleeping = false
	Game.notify("You slept %d hours. It is %s." % [int(round(passed)), Util.format_clock(target)], &"good")
	slept.emit(passed, target)
	return passed


func save_game(slot: int = 0) -> bool:
	var ok := false
	if SaveSystem != null and SaveSystem.has_method("save_game"):
		ok = bool(SaveSystem.save_game(slot))
	if ok:
		last_saved_unix = Time.get_unix_time_from_system()
		Game.notify("Game saved", &"good")
		Sfx.play_ui(&"ui_confirm")
		game_saved.emit()
	else:
		Game.notify("Saving isn't available right now.", &"warn")
		Sfx.play_ui(&"ui_error")
	return ok


func toggle_tv() -> void:
	tv_on = not tv_on
	var room := interiors.get_room(&"safehouse", false) if interiors != null else null
	if room != null:
		_apply_tv_state(room)
	Sfx.play_ui(&"radio_tune" if tv_on else &"ui_click")
	Game.notify("TV %s" % ("on" if tv_on else "off"), &"info")


func _apply_tv_state(room: InteriorRoom) -> void:
	if _tv_mat != null:
		_tv_mat.emission_enabled = tv_on
		if not tv_on:
			_tv_mat.albedo_color = Color("#080b10")
		else:
			_tv_mat.albedo_color = Color("#101820")
	if room.info.has("tv_light"):
		var l: OmniLight3D = room.info["tv_light"]
		l.light_energy = 0.9 if tv_on else 0.0


func snack() -> void:
	var now := Time.get_ticks_msec() * 0.001
	var p = Game.player
	if not is_instance_valid(p):
		return
	if now < _snack_ready_at:
		Game.notify("The fridge is empty for now - give it a minute.", &"warn")
		Sfx.play_ui(&"ui_error")
		return
	if float(p.get("health")) >= float(p.get("max_health")) - 0.5:
		Game.notify("You're not hungry.", &"info")
		return
	_snack_ready_at = now + SNACK_COOLDOWN_S
	p.heal(SNACK_HEAL)
	Game.notify("You grab a bite from the fridge (+%d HP)" % int(SNACK_HEAL), &"good")
	Sfx.play_ui(&"pickup")


# ================================================================================================= garage actions
func get_stored_records() -> Array:
	var garage = Game.sys(&"garage")
	if garage != null and garage.has_method("get_stored_vehicles"):
		return garage.get_stored_vehicles()
	return []


## Leaves the garage through the roller door and drops the stored vehicle in front of it. Coroutine.
func bring_out_vehicle(slot: int) -> bool:
	var garage = Game.sys(&"garage")
	if garage == null or not garage.has_method("deliver_now") or interiors == null:
		Game.notify("Vehicle storage isn't available.", &"warn")
		return false
	if Game.ui != null and Game.ui.is_menu_open():
		Game.ui.close_menu()
	await get_tree().process_frame
	var door := interiors.door_for(&"safehouse_garage")
	if interiors.is_inside():
		await interiors.exit()
	var xf := Transform3D.IDENTITY
	var ok_xf := false
	if door != null:
		var yaw: float = float(door.data.get("yaw", 0.0))
		var ret: Vector3 = door.data.get("return", door.global_position)
		var pos: Vector3 = ret + Util.yaw_to_dir(yaw) * 3.4 + Vector3(0, 0.7, 0)
		xf = Transform3D(Basis(Vector3.UP, yaw), pos)
		ok_xf = true
	var v = garage.deliver_now(slot, xf if ok_xf else null, true)
	if v == null:
		Game.notify("Couldn't bring the vehicle out.", &"warn")
		return false
	Game.notify("%s is waiting outside the garage." % str(v.display_name), &"good")
	return true


# ================================================================================================= respawn
func _on_player_respawned(pos: Vector3) -> void:
	_sync_flag()
	if not owned or not respawn_here or interiors == null:
		return
	var hosp: Dictionary = WorldLayout.get_location(&"hospital")
	if hosp.is_empty() or Util.dist_xz(pos, hosp["pos"]) > 40.0:
		return          # only a hospital respawn (knock-out) is redirected; arrest respawns stay at the police station
	var tf := interiors.door_transform(&"safehouse", "Door")
	if tf.is_empty():
		return
	var p = Game.player
	if not is_instance_valid(p):
		return
	var ret_pos: Vector3 = tf["return"]
	p.teleport_to(ret_pos + Vector3(0, 0.15, 0), float(tf["yaw"]))
	var cam = p.get("camera")
	if cam != null and is_instance_valid(cam) and cam.has_method("snap_behind"):
		cam.snap_behind(float(tf["yaw"]))
	# the hospital bill was charged by the Player; home care is cheaper (20% of it, at least $50)
	var paid := _cash_at_death - Game.cash
	if paid > 0:
		var keep := maxi(int(round(float(paid) * 0.2)), 50)
		Game.cash += maxi(paid - keep, 0)
	Game.notify("You came to in your own bed... a neighbour dragged you home.", &"info")


# ================================================================================================= save
func serialize() -> Dictionary:
	return {"owned": owned, "respawn_here": respawn_here, "tv_on": tv_on, "last_saved": last_saved_unix}


func deserialize(data: Dictionary) -> void:
	owned = bool(data.get("owned", true))
	respawn_here = bool(data.get("respawn_here", true))
	tv_on = bool(data.get("tv_on", false))
	last_saved_unix = float(data.get("last_saved", 0.0))
	_sync_flag()
