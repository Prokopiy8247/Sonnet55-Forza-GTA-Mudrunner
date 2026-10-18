extends Node
## Screenshot scenarios for the UI. Run through the real renderer, e.g.
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\ui_hud.png -Resolution 1920x1080 `
##       -GameArgs "--exec=res://gta/tests/ui_shot.gd --ui-scene=hud --no-intro --delay=2"
## Scenes: hud hud_car hud_heli hud_plane hud_boat lowhp wheel map pause settings controls status showcase death busted widgets chute air stealth
## Optional: --tab=<n> for showcase / pause pages.

var scene := "hud"
var opts: Dictionary = {}


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func run(main: Node) -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--") and s.find("=") > 0:
			opts[s.substr(2, s.find("=") - 2)] = s.substr(s.find("=") + 1)
	scene = String(opts.get("ui-scene", "hud"))
	var ui = Game.ui
	if ui == null:
		print("TEST ui_shot FAIL Game.ui is null")
		return "no ui"
	ui.capture_when_idle = false
	if scene == "live":
		await _scene_live(ui)
		print("TEST ui_shot_live PASS rendered")
		return scene
	UiFakes.fill_world()
	var holder := Node3D.new()
	holder.name = "UiTestHolder"
	main.add_child(holder)
	var pl := UiFakes.make_player(holder, Vector3(10, 0, 30))
	var cam := Camera3D.new()
	cam.name = "UiTestCam"
	holder.add_child(cam)
	cam.global_position = Vector3(10, 3, 40)
	cam.rotation = Vector3(0, deg_to_rad(35.0), 0)
	Game.gameplay_camera = cam
	Game.cash = 48250
	Game.time_of_day = 14.5
	await _wait(0.2)
	match scene:
		"hud": await _scene_hud(ui, pl, holder)
		"hud_car": await _scene_vehicle(ui, pl, holder, GC.VC_CAR)
		"hud_boat": await _scene_vehicle(ui, pl, holder, GC.VC_BOAT)
		"hud_heli": await _scene_vehicle(ui, pl, holder, GC.VC_HELI)
		"hud_plane": await _scene_vehicle(ui, pl, holder, GC.VC_PLANE)
		"lowhp": await _scene_lowhp(ui, pl)
		"wheel": await _scene_wheel(ui, pl)
		"map": await _scene_map(ui, pl, holder)
		"pause": await _scene_menu(ui, &"pause", int(opts.get("tab", 0)))
		"settings": await _scene_menu(ui, &"pause", 2)
		"controls": await _scene_menu(ui, &"pause", 3)
		"status": await _scene_status(ui)
		"showcase": await _scene_menu(ui, &"ui_showcase", int(opts.get("tab", 0)))
		"death": await _scene_death(ui, false)
		"busted": await _scene_death(ui, true)
		"stealth": await _scene_stealth(ui, pl)
		"chute": await _scene_chute(ui, pl)
		"air": await _scene_air(ui, pl)
		"raster": await _scene_raster(ui)
		"widgets": await _scene_widgets(ui, pl)
		_: print("unknown scene ", scene)
	await _wait(0.4)
	print("TEST ui_shot_%s PASS rendered" % scene)
	return scene


func _common_hud(ui, pl) -> void:
	Game.wanted_level = 3
	Game.wanted_state = &"pursuit"
	Events.wanted_changed.emit(3, &"pursuit")
	UiFakes.make_police(pl.get_parent(), pl.global_position, 7)
	Events.notification.emit("Picked up $250.", &"good")
	Events.notification.emit("Police are looking for you!", &"warn")
	Events.notification.emit("Weapon equipped: Pistol", &"info")
	Events.district_changed.emit(GC.D_DOWNTOWN)


func _scene_hud(ui, pl, holder) -> void:
	_common_hud(ui, pl)
	pl.weapons.is_aiming = true
	pl.health = 72.0
	Game.cash += 1500
	Events.interaction_prompt.emit("[E] Buy weapons")
	Events.subtitle.emit("Clerk: Take your time, we are open all night.", 6.0)
	await _wait(0.6)
	Events.hit_marker.emit(false)
	await _wait(0.9)


func _scene_vehicle(ui, pl, holder, vclass: StringName) -> void:
	Game.wanted_level = 2
	Game.wanted_state = &"search"
	Events.wanted_changed.emit(2, &"search")
	Events.wanted_search_progress.emit(0.45)
	var v := UiFakes.FakeVehicle.new()
	v.vclass = vclass
	v.is_player_owned = false
	match vclass:
		GC.VC_HELI:
			v.display_name = "Skyhawk"
			v.kmh = 142.0
			v.linear_velocity = Vector3(0, 2.5, 0)
		GC.VC_PLANE:
			v.display_name = "Albatross"
			v.kmh = 235.0
			v.linear_velocity = Vector3(0, -1.2, 0)
			v.input_throttle = 0.75
		GC.VC_BOAT:
			v.display_name = "Marlin"
			v.kmh = 64.0
	holder.add_child(v)
	v.global_position = Vector3(10, 120 if vclass in [GC.VC_HELI, GC.VC_PLANE] else 0.0, 30)
	if vclass in [GC.VC_HELI, GC.VC_PLANE]:
		v.rotation = Vector3(deg_to_rad(8), deg_to_rad(40), deg_to_rad(-18))
	pl.current_vehicle = v
	Events.notification.emit("Radio: Halcyon FM", &"info")
	await _wait(1.0)


func _scene_lowhp(ui, pl) -> void:
	pl.health = 100.0
	pl.armor = 0.0
	await _wait(0.2)
	pl.health = 14.0
	Game.wanted_level = 1
	Game.wanted_state = &"pursuit"
	Events.player_hurt.emit(30.0, {"source": null, "direction": Vector3(0.6, 0, 0.8)})
	ui.feedback.add_hit_angle(deg_to_rad(95.0), 1.0)
	ui.feedback.add_hit_angle(deg_to_rad(-140.0), 0.8)
	await _wait(0.5)
	Events.player_hurt.emit(20.0, {})
	await _wait(0.2)


func _scene_wheel(ui, pl) -> void:
	pl.weapons.current_id = &"smg"
	ui.wheel.open_with(pl.weapons.get_weapon_ids(), &"smg", {&"pistol": [12, 84], &"smg": [30, 180], &"revolver": [6, 30], &"shotgun_pump": [8, 32], &"rifle_assault": [30, 240],
		&"carbine": [30, 150], &"sniper": [5, 25], &"rocket_launcher": [1, 4], &"grenade": [0, 6]})
	await _wait(0.5)
	ui.wheel._set_selection(3, 0)
	await _wait(0.4)


func _scene_map(ui, pl, holder) -> void:
	UiFakes.make_police(holder, pl.global_position, 5)
	Game.wanted_level = 2
	Game.wanted_state = &"pursuit"
	ui.set_waypoint(Vector3(160, 0, 150))
	ui.open_menu(&"map")
	await _wait(2.5)    # wait for the raster


func _scene_menu(ui, id: StringName, tab: int) -> void:
	ui.open_menu(id, {"tab": tab})
	await _wait(0.5)


func _scene_status(ui) -> void:
	ui.stats["time_played"] = 5025.0
	ui.stats["dist_foot"] = 8450.0
	ui.stats["dist_driven"] = 31200.0
	ui.stats["kills"] = 17
	ui.stats["money_earned"] = 128400
	ui.stats["money_spent"] = 79150
	ui.stats["wanted_peak"] = 4
	ui.stats["deaths"] = 2
	ui.stats["busted"] = 1
	ui.stats["vehicles"] = 23
	for k in [[&"stamina", 0.62], [&"shooting", 0.38], [&"strength", 0.21], [&"stealth", 0.74], [&"driving", 0.9], [&"flying", 0.12], [&"lung", 0.5]]:
		ui.skill_cache[k[0]] = k[1]
	ui.open_menu(&"status")
	await _wait(0.5)


func _scene_death(ui, busted: bool) -> void:
	if busted:
		Events.player_busted.emit()
	else:
		Events.player_died.emit()
	await _wait(1.0)


func _scene_stealth(ui, pl) -> void:
	pl.stance = &"crouch"
	pl.noise_level = 0.35
	await _wait(0.8)


func _scene_chute(ui, pl) -> void:
	pl.is_parachuting = true
	pl.global_position = Vector3(10, 96, 30)
	await _wait(0.8)


func _scene_air(ui, pl) -> void:
	pl.lung = 0.22
	pl.is_underwater = true
	await _wait(0.8)


func _scene_raster(ui) -> void:
	await _wait(3.0)
	var tex: Texture2D = ui.hud.raster.texture
	print("RASTER real=%s size=%s rebuilds=%d" % [ui.hud.raster.is_real, tex.get_size(), ui.hud.raster.rebuild_count])
	var img: Image = tex.get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path("res://screenshots/ui_raster.png"))
		print("RASTER px(10,10)=", img.get_pixel(10, 10), " px(400,300)=", img.get_pixel(400, 300), " px(760,760)=", img.get_pixel(760, 760), " fmt=", img.get_format())
	var layers := ["land", "districts", "nature", "relief", "piers", "airport", "roads", "buildings"]
	for l in layers:
		ui.hud.raster.debug_skip = {l: true}
		await ui.hud.raster.build()
		var im: Image = ui.hud.raster.texture.get_image()
		print("RASTER skip=%s px(10,10)=%s px(400,300)=%s" % [l, im.get_pixel(10, 10), im.get_pixel(400, 300)])
	ui.hud.raster.debug_skip = {}
	print("LAYOUT roads=%d footprints=%d water=%d districts=%d nature=%d locations=%d built=%s" % [WorldLayout.roads.size(), WorldLayout.building_footprints.size(),
		WorldLayout.water_polys.size(), WorldLayout.districts.size(), WorldLayout.nature_zones.size(), WorldLayout.locations.size(), WorldLayout.built])
	if WorldLayout.roads.size() > 0:
		var kinds := {}
		for r in WorldLayout.roads:
			kinds[r.get("kind", &"?")] = kinds.get(r.get("kind", &"?"), 0) + 1
		print("ROAD kinds ", kinds, " sample ", WorldLayout.roads[0])
	if WorldLayout.districts.size() > 0:
		print("DISTRICT sample ", WorldLayout.districts[0])
	if WorldLayout.building_footprints.size() > 0:
		print("FOOTPRINT sample ", WorldLayout.building_footprints[0])


## Real modules only (no fakes): gives the real player weapons and a wanted level, then lets the HUD run.
func _scene_live(ui) -> void:
	var p = Game.player
	if not is_instance_valid(p):
		print("TEST ui_live FAIL no real player")
		return
	if p.get("weapons") != null:
		for w in [&"pistol", &"smg", &"shotgun_pump", &"rifle_assault", &"sniper", &"grenade"]:
			p.weapons.give_weapon(w, 90)
		p.weapons.equip(&"smg")
	var ws = Game.sys(&"wanted")
	if ws != null and ws.has_method("set_level"):
		ws.set_level(2)
	Events.notification.emit("Live HUD test: real player, real world.", &"info")
	Events.interaction_prompt.emit("Press to interact")
	await _wait(2.5)
	if p.get("health") != null:
		p.health = 55.0
	await _wait(1.0)


func _scene_widgets(ui, pl) -> void:
	pl.stance = &"crouch"
	pl.noise_level = 0.45
	pl.lung = 0.22
	pl.is_underwater = true
	pl.is_parachuting = true
	pl.global_position = Vector3(10, 64, 30)
	pl.stamina = 0.35
	Game.cheats["show_fps"] = true
	Game.cheats["show_coords"] = true
	pl.weapons.reload_progress = 0.6
	pl.weapons.is_reloading = true
	await _wait(1.2)
