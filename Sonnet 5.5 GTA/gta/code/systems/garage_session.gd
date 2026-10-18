class_name GarageSession
extends Node
## One visit to the customization garage: locks the player, fades, moves the vehicle into the studio (VehicleBase.place_at), starts the
## orbit camera + studio lights, opens the GarageMenu and – when the menu closes – restores everything and puts the car at the bay exit.
## Holds the committed build (what the car really has) and the pending build (live preview); apply() charges the difference.

const STUDIO_LIFT := 220.0

var system: GarageSystem = null
var vehicle: VehicleBase = null
var site: Dictionary = {}
var bay_index := 0
var committed: GarageBuild = null
var pending: GarageBuild = null
var studio: GarageStudio = null
var cam: GarageCamera = null
var active := false
var studio_origin := Vector3.ZERO
var exit_xf := Transform3D.IDENTITY
var body_min := Vector3(-0.9, 0.2, -2.2)
var body_max := Vector3(0.9, 1.45, 2.2)
var plate_seed := ""

var _orig_xf := Transform3D.IDENTITY
var _prev_cam: Camera3D = null
var _hud_was_hidden := false
var _menu: MenuBase = null
var _ending := false


func begin(sys: GarageSystem, v: VehicleBase, site_: Dictionary, bay: int) -> void:
	system = sys
	vehicle = v
	site = site_
	bay_index = bay
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ui = Game.ui
	var player = Game.player
	if is_instance_valid(player):
		player.input_locked = true
	v.reset_controls()
	# exit placement (just outside the bay, facing out)
	var bays: Array = site.get("bays", [])
	if bay >= 0 and bay < bays.size():
		var e: Vector3 = bays[bay]["entry"]
		var inside: Vector3 = bays[bay]["inside"]
		var dir := Util.flat(inside - e).normalized()
		var p := e - dir * 4.6
		exit_xf = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(-dir)), _ground(p))
		studio_origin = inside + Vector3(0, STUDIO_LIFT, 0)
	else:
		exit_xf = v.global_transform
		studio_origin = v.global_position + Vector3(0, STUDIO_LIFT, 0)
	_orig_xf = v.global_transform
	if ui != null:
		await ui.fade(true, 0.3)
	# ---- build
	committed = GarageBuild.from_vehicle(v)
	if not committed.mods.has("plate_text"):
		committed.mods["plate_text"] = VehicleModsData.random_plate_text(Game.rng)
		v.mods["plate_text"] = committed.mods["plate_text"]
	pending = committed.copy()
	studio = GarageStudio.new()
	studio.name = "GarageStudio"
	add_child(studio)
	studio.global_position = studio_origin
	studio.build(String(site.get("name", VehicleModsData.SHOP_NAME)).to_upper())
	var an := VehicleModsFit.analyze(v.model, v.def_id)
	body_min = an["min"]
	body_max = an["max"]
	cam = GarageCamera.new()
	cam.name = "GarageCamera"
	add_child(cam)
	cam.environment = studio.make_environment()
	cam.global_position = studio_origin + Vector3(0, 2.0, -8.0)
	_prev_cam = get_viewport().get_camera_3d()
	# ---- place the vehicle
	_place_in_studio()
	cam.fov = 46.0
	var ext := maxf(body_max.z - body_min.z, 3.0)
	cam.min_dist = ext * 0.45
	cam.max_dist = ext * 2.9
	focus_default()
	cam.snap_now()
	cam.make_current()
	if ui != null:
		_hud_was_hidden = ui.hud_hidden
		ui.set_hud_visible(false)
	active = true
	# ---- menu
	if ui != null and ui.has_menu(&"garage"):
		_menu = ui.get_menu(&"garage")
		if not _menu.closed.is_connected(_on_menu_closed):
			_menu.closed.connect(_on_menu_closed)
		ui.open_menu(&"garage", {"session": self})
		await ui.fade(false, 0.45)
	else:
		push_error("GarageSession: garage menu not registered")
		await end()


func _ground(p: Vector3) -> Vector3:
	var hit := Util.raycast(vehicle, p + Vector3.UP * 3.0, p + Vector3.DOWN * 8.0, GC.M_GROUND, [vehicle])
	if hit.is_empty():
		return p + Vector3.UP * 0.05
	return (hit["position"] as Vector3) + Vector3.UP * 0.06


func _place_in_studio() -> void:
	var v := vehicle
	for w in v.wheels:
		w.length = w.eq_len
		w.prev_length = w.eq_len
		w.steer_angle = 0.0
		w.slip = 0.0
		w.skid_active = false
	if v.has_method("_update_visuals"):
		v._update_visuals(0.0, 0.0)
	v.place_at(Transform3D(Basis(Vector3.UP, 0.0), studio_origin + Vector3(0, 0.16, 0)))
	if v.has_method("unflip"):
		pass
	v.engine_on = false


# ---- camera presets ---------------------------------------------------------------------------------------------------
func _center() -> Vector3:
	return studio_origin + Vector3(0, (body_max.y + body_min.y) * 0.5 * 0.9 + 0.16, 0)


func focus_default() -> void:
	var ext := body_max.z - body_min.z
	cam.focus(_center(), deg_to_rad(36.0), deg_to_rad(13.0), ext * 1.75)


## Points the camera at the area of the car a category / slot is about.
func focus_on(topic: StringName) -> void:
	if cam == null:
		return
	var o := studio_origin + Vector3(0, 0.16, 0)
	var ext := body_max.z - body_min.z
	var wid := body_max.x - body_min.x
	var h := body_max.y
	match topic:
		&"wheels", &"rim_style", &"rim_color":
			var wz := 0.0
			var wx := wid * 0.5
			if not vehicle.wheels.is_empty():
				wz = vehicle.wheels[0].rest.z
				wx = absf(vehicle.wheels[0].rest.x)
			cam.focus(o + Vector3(wx, 0.34, wz), deg_to_rad(82.0), deg_to_rad(8.0), ext * 0.62)
		&"spoiler", &"rear_bumper", &"exhaust", &"plates", &"plate":
			cam.focus(o + Vector3(0, h * 0.5, body_max.z - 0.4), deg_to_rad(158.0), deg_to_rad(15.0), ext * 0.85)
		&"front_bumper", &"grille", &"headlight", &"lights":
			cam.focus(o + Vector3(0, h * 0.42, body_min.z + 0.4), deg_to_rad(-28.0), deg_to_rad(10.0), ext * 0.85)
		&"hood":
			cam.focus(o + Vector3(0, h * 0.7, body_min.z + ext * 0.25), deg_to_rad(-20.0), deg_to_rad(34.0), ext * 1.0)
		&"roof":
			cam.focus(o + Vector3(0, h * 0.95, 0), deg_to_rad(52.0), deg_to_rad(40.0), ext * 1.25)
		&"skirts", &"livery", &"windows":
			cam.focus(o + Vector3(0, h * 0.42, 0), deg_to_rad(90.0), deg_to_rad(10.0), ext * 1.7)
		&"taillight":
			cam.focus(o + Vector3(0, h * 0.45, body_max.z - 0.4), deg_to_rad(150.0), deg_to_rad(10.0), ext * 0.9)
		&"underglow":
			cam.focus(o + Vector3(0, 0.3, 0), deg_to_rad(50.0), deg_to_rad(4.0), ext * 1.35)
		_:
			focus_default()


# ---- build / preview -----------------------------------------------------------------------------------------------
func preview() -> void:
	if vehicle != null and is_instance_valid(vehicle):
		pending.apply_to(vehicle)


func quote() -> Array:
	return system.quote(committed, pending)


func total_cost() -> int:
	return GarageBuild.total_cost(quote())


func has_pending() -> bool:
	return not pending.equals(committed)


## Pays for the pending changes and makes them permanent. Returns false (nothing changed) when the player cannot afford them.
func apply_pending() -> bool:
	var entries := quote()
	if entries.is_empty():
		return true
	if not system.charge(entries):
		Game.notify("Not enough cash: %s needed." % Util.format_money(GarageBuild.total_cost(entries)), &"bad")
		if Sfx != null:
			Sfx.play_ui(&"ui_error")
		return false
	committed = pending.copy()
	Game.notify("Upgrades installed%s." % ("" if GarageBuild.total_cost(entries) <= 0 else " (%s)" % Util.format_money(GarageBuild.total_cost(entries))), &"good")
	return true


func revert_pending() -> void:
	pending = committed.copy()
	preview()


func repair_now() -> bool:
	var ok := system.repair_vehicle(vehicle, true)
	if ok:
		Game.notify("Vehicle repaired.", &"good")
		if Sfx != null:
			Sfx.play_ui(&"ui_confirm")
	return ok


func store_vehicle() -> void:
	# apply nothing pending: discard the preview, then store (the studio car is the one that gets stored)
	committed.apply_to(vehicle)
	var slot := system.store(vehicle)
	if slot >= 0:
		vehicle = null


# ---- ending ----------------------------------------------------------------------------------------------------------------
func _on_menu_closed() -> void:
	if _ending:
		return
	end()


func end() -> void:
	if _ending:
		return
	_ending = true
	var ui = Game.ui
	if ui != null:
		await ui.fade(true, 0.3)
	var v := vehicle
	if v != null and is_instance_valid(v):
		committed.apply_to(v)                        # drop any unconfirmed preview
		v.place_at(exit_xf)
		v.engine_on = true
		var p = Game.player
		if is_instance_valid(p) and p.has_method("_reset_interp"):
			p._reset_interp()
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	elif Game.gameplay_camera != null:
		Game.gameplay_camera.make_current()
	if ui != null:
		ui.set_hud_visible(not _hud_was_hidden)
	active = false
	if studio != null:
		studio.queue_free()
	if cam != null:
		cam.queue_free()
	if is_instance_valid(Game.player):
		Game.player.input_locked = false
	if _menu != null and _menu.closed.is_connected(_on_menu_closed):
		_menu.closed.disconnect(_on_menu_closed)
	system._on_session_finished(v)
	if ui != null:
		await get_tree().create_timer(0.15, true, false, true).timeout
		await ui.fade(false, 0.45)
	queue_free()
