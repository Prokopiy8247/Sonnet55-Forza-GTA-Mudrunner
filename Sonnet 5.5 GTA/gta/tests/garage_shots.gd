extends Node
## Visual QA driver for the garage (needs a real renderer: run with tools\gd.ps1 shot ... -GameArgs "--exec=res://gta/tests/garage_shots.gd --gs-mode=sheet").
##   --gs-mode=sheet   contact sheets (front + rear 3/4 views, 4 option sets) of all 15 ground vehicles   -> screenshots/garage/sheet_*.png
##   --gs-mode=menu    every menu category on a damaged sedan                                              -> screenshots/garage/menu_*.png
##   --gs-mode=one     --gs-veh=<id> --gs-set=<k>  full-res views of one vehicle in the studio            -> screenshots/garage/one_<id>_*.png
##   --gs-mode=phone   phone home + every app page                                                         -> screenshots/garage/phone_*.png
##   --gs-mode=photo   photo mode with each filter                                                         -> screenshots/garage/photo_*.png
##   --gs-mode=bay     the real garage_shop bay from the street (prompt, car in bay)                       -> screenshots/garage/bay_*.png

const GROUND := ["sedan", "compact", "sports", "muscle", "suv", "pickup", "van", "taxi", "police_cruiser", "ambulance", "firetruck", "truck",
	"police_tactical", "motorcycle", "bicycle"]
const OUT := "res://screenshots/garage/"

var gs: GarageSystem = null
var args := {}


func _opt(k: String, d: String) -> String:
	return String(args.get(k, d))


func run(_main: Node) -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			args[s] = "true"
	gs = Game.sys(&"garage")
	if gs == null:
		return "no garage"
	gs.unlock_all = true
	var waited := 0
	while not gs._sites_ready and waited < 400:
		await get_tree().process_frame
		waited += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	match _opt("gs-mode", "sheet"):
		"sheet":
			await _mode_sheet()
		"menu":
			await _mode_menu()
		"one":
			await _mode_one()
		"phone":
			await _mode_phone()
		"photo":
			await _mode_photo()
		"bay":
			await _mode_bay()
		"perf":
			await _mode_perf()
		"dealer":
			await _mode_dealer()
	return "done"


## Walk up to a showroom vehicle: the real interaction prompt ("Buy ...") appears, E buys it (toast) and it lands in the garage.
func _mode_dealer() -> void:
	var vs = Game.sys(&"vehicles")
	await get_tree().create_timer(3.0).timeout
	var target: VehicleBase = null
	for dv in vs.dealer_vehicles:
		if is_instance_valid(dv) and dv.def_id == &"sports":
			target = dv
	if target == null:
		print("GDEALER no sports in dealer lot")
		return
	var p = Game.player
	var side := target.global_transform.basis.x * 3.2
	p.teleport_to(target.global_position + side + Vector3(0, 0.3, 0), NAN)
	Game.cash = 120000
	gs.unlock_all = false
	await get_tree().create_timer(2.5).timeout
	var cam := Camera3D.new()
	_main_add(cam)
	cam.global_position = target.global_position + side * 1.9 + Vector3(0, 1.8, 0) - target.global_transform.basis.z * 3.0
	cam.look_at(target.global_position + Vector3(0, 0.8, 0), Vector3.UP)
	cam.make_current()
	await _frames(20)
	_save(await _grab(), "dealer_prompt")
	var gi = target.get_node_or_null("GarageDealerPoint")
	print("GDEALER point=", gi != null, " interaction=", gi.get_interaction(p) if gi != null else "-")
	var cash0 := Game.cash
	if gi != null:
		gi.interact(p)
	await get_tree().create_timer(0.6).timeout
	print("GDEALER stored=", gs.get_stored_vehicles().size(), " cash ", cash0, " -> ", Game.cash, " price=", target.def.get("price", 0))
	_save(await _grab(), "dealer_bought")


## fps / draw calls: city baseline, garage studio with a fully modded car, phone open, photo mode.
func _sample(label: String, seconds: float = 3.0) -> void:
	var t := 0.0
	var n := 0
	var sum := 0.0
	var minf_ := 9999.0
	var calls := 0
	while t < seconds:
		await get_tree().process_frame
		var d := get_process_delta_time()
		t += d
		var fps := Engine.get_frames_per_second()
		if t > 0.5:
			sum += fps
			n += 1
			minf_ = minf(minf_, fps)
			calls = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("GPERF %s avg_fps=%.1f min_fps=%.1f draw_calls=%d" % [label, sum / maxf(float(n), 1.0), minf_, calls])


func _mode_perf() -> void:
	await _sample("city_baseline")
	var v := await _spawn_at_bay("sports")
	v.apply_mods(_set_mods("sports", 0))
	gs.begin_session(v, _shop_site(), 0)
	while gs.session == null or not gs.session.active:
		await get_tree().process_frame
	await get_tree().create_timer(1.0, true, false, true).timeout
	await _sample("garage_session_full_mods")
	var sess: GarageSession = gs.session
	var menu: GarageMenu = sess._menu as GarageMenu
	menu._show_category(menu._cats.find(&"performance"))
	await _sample("garage_menu_performance_page")
	await sess.end()
	await get_tree().create_timer(1.0, true, false, true).timeout
	Game.ui.open_menu(&"phone")
	await get_tree().create_timer(0.6, true, false, true).timeout
	await _sample("phone_open")
	Game.ui.close_menu()
	await get_tree().create_timer(0.5, true, false, true).timeout
	gs.photo.enter()
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _sample("photo_mode_dof")
	gs.photo.dof_amount = 0.7
	gs.photo._apply_dof()
	await _sample("photo_mode_dof_on")
	gs.photo.exit()


# ------------------------------------------------------------------------------------------------------------ helpers
func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _save(img: Image, name_: String) -> void:
	var p := ProjectSettings.globalize_path(OUT + name_ + ".png")
	var err := img.save_png(p)
	print("GSHOT ", p, " err=", err, " size=", img.get_size())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shop_site() -> Dictionary:
	for s in gs.sites:
		if s["kind"] == &"shop":
			return s
	return {}


func _spawn_at_bay(id: String, opts: Dictionary = {}) -> VehicleBase:
	var site := _shop_site()
	var bay: Dictionary = site["bays"][0]
	var e: Vector3 = bay["entry"]
	var inside: Vector3 = bay["inside"]
	var dir := Util.flat(inside - e).normalized()
	var xf := Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), e + Vector3(0, 0.8, 0))
	var v := VehicleFactory.spawn(StringName(id), xf, opts)
	await _frames(10)
	return v


## Deterministic option set k for a vehicle: option idx = 1 + ((k + slot_index) mod n_non_stock)
func _set_mods(id: String, k: int) -> Dictionary:
	var m := {}
	var slots := VehicleModsData.slots_for(StringName(id))
	var si := 0
	for slot in slots:
		var opts := VehicleModsData.slot_options_for(StringName(id), slot)
		var n := opts.size() - 1
		if n >= 1:
			m["p_" + String(slot)] = String(opts[1 + ((k + si) % n)]["id"])
		si += 1
	var kind := String(VehicleModsData.vehicle_cfg(StringName(id)).get("kind", "car"))
	var rims := VehicleModsData.rims_for(kind)
	if rims.size() > 1:
		m["rim_style"] = String(rims[1 + (k % (rims.size() - 1))]["id"])
	var pal_cols := [Color("#ff3d9a"), Color("#34e0ff"), Color("#ffb347"), Color("#6a3cc9")]
	m["rim_color"] = pal_cols[(k + 2) % 4]
	var livs := VehicleModsData.LIVERIES
	m["livery"] = String(livs[1 + (k % (livs.size() - 1))]["id"])
	m["livery_color"] = VehicleModsData.LIVERY_COLORS[(k * 2) % 8]["color"]
	var ug := VehicleModsData.UNDERGLOW
	m["underglow"] = String(ug[1 + (k % (ug.size() - 1))]["id"])
	var pls := VehicleModsData.PLATES
	m["plate"] = String(pls[k % pls.size()]["id"])
	m["plate_text"] = "HB %03d" % (100 + k * 111)
	m["window_tint"] = k % 4
	return m


# ------------------------------------------------------------------------------------------------------------ sheet
func _mode_sheet() -> void:
	var sets := int(_opt("gs-sets", "2"))
	var ids: Array = GROUND
	if args.has("gs-veh"):
		ids = String(args["gs-veh"]).split(",")
	var tiles: Dictionary = {}                         # "front_k" -> Array of [id, Image]
	var paints := [Color("#e0322b"), Color("#1f4fb8"), Color("#eceff1"), Color("#14161b")]
	for id in ids:
		var v := await _spawn_at_bay(id)
		if v == null:
			continue
		var site := _shop_site()
		gs.begin_session(v, site, 0)
		var waited := 0
		while gs.session == null or not gs.session.active:
			await get_tree().process_frame
			waited += 1
			if waited > 600:
				break
		var sess: GarageSession = gs.session
		await get_tree().create_timer(0.8, true, false, true).timeout
		if sess._menu != null:
			sess._menu.visible = false
		sess.cam.auto_rotate = false
		sess.cam.keys_enabled = false
		for k in range(int(_opt("gs-k0", "0")), int(_opt("gs-k0", "0")) + sets):
			var pend := sess.pending
			pend.mods = _set_mods(id, k)
			pend.paint1 = paints[k % 4]
			pend.paint2 = paints[(k + 1) % 4]
			pend.finish = [&"gloss", &"metallic", &"pearl", &"matte"][k % 4]
			sess.preview()
			await _frames(6)
			var ext := (sess.body_max.z - sess.body_min.z) * float(_opt("gs-dist", "1.45"))
			sess.cam.screen_shift = 0.0
			for view in ["front", "rear", "side", "top"]:
				if view == "top" or view == "side":
					if not args.has("gs-all-views"):
						continue
				match view:
					"front":
						sess.cam.focus(sess._center(), deg_to_rad(36.0), deg_to_rad(14.0), ext, false)
					"rear":
						sess.cam.focus(sess._center(), deg_to_rad(148.0), deg_to_rad(14.0), ext, false)
					"side":
						sess.cam.focus(sess._center(), deg_to_rad(90.0), deg_to_rad(6.0), ext, false)
					"top":
						sess.cam.focus(sess._center(), deg_to_rad(90.0), deg_to_rad(58.0), ext * 0.95, false)
				sess.cam.snap_now()
				await _frames(5)
				var img := await _grab()
				if args.has("gs-debug"):
					print("GSDBG %s %s dist=%.2f yaw=%.1f pitch=%.1f g_dist=%.2f cam=%s tgt=%s" % [id, view, sess.cam.dist, rad_to_deg(sess.cam.yaw), rad_to_deg(sess.cam.pitch),
						sess.cam._g_dist, sess.cam.global_position, sess.cam.target])
				var key := "%s_%d" % [view, k]
				if not tiles.has(key):
					tiles[key] = []
				tiles[key].append([id, img])
				if args.has("gs-full"):
					_save(img, "full_%s_%s_%d" % [id, view, k])
		await sess.end()
		await _frames(5)
		while gs.session != null:
			await get_tree().process_frame
		await get_tree().create_timer(0.8, true, false, true).timeout
		VehicleFactory.despawn(v)
		await _frames(3)
	# ---- compose contact sheets
	var cols := int(_opt("gs-cols", "3"))
	var tw := 640 if cols >= 3 else 960
	var th := 360 if cols >= 3 else 540
	var rows_per_page := 3 if cols >= 3 else 2
	for key in tiles:
		var arr: Array = tiles[key]
		var per_page := cols * rows_per_page
		var pages := int(ceil(float(arr.size()) / float(per_page)))
		for pg in pages:
			var rows := int(ceil(float(mini(per_page, arr.size() - pg * per_page)) / float(cols)))
			var sheet := Image.create(cols * tw, rows * th, false, Image.FORMAT_RGBA8)
			for i in mini(per_page, arr.size() - pg * per_page):
				var item: Array = arr[pg * per_page + i]
				var im: Image = (item[1] as Image).duplicate()
				im.convert(Image.FORMAT_RGBA8)
				# crop the middle (menu hidden: car is centred) then resize
				var w := im.get_width()
				var h := im.get_height()
				var crop := Rect2i(int(w * 0.1), int(h * 0.1), int(w * 0.8), int(h * 0.8))
				var c := im.get_region(crop)
				c.resize(tw, th, Image.INTERPOLATE_LANCZOS)
				sheet.blit_rect(c, Rect2i(0, 0, tw, th), Vector2i((i % cols) * tw, (i / cols) * th))
			_save(sheet, "sheet_%s_p%d" % [key, pg])
			var names := ""
			for i in mini(per_page, arr.size() - pg * per_page):
				names += "%s " % (arr[pg * per_page + i] as Array)[0]
			print("GSHEET sheet_%s_p%d: %s" % [key, pg, names])


# ------------------------------------------------------------------------------------------------------------ one vehicle
func _mode_one() -> void:
	var id := _opt("gs-veh", "sedan")
	var k := int(_opt("gs-set", "0"))
	var v := await _spawn_at_bay(id)
	gs.begin_session(v, _shop_site(), 0)
	while gs.session == null or not gs.session.active:
		await get_tree().process_frame
	var sess: GarageSession = gs.session
	await get_tree().create_timer(0.8, true, false, true).timeout
	if args.has("gs-menu") == false and sess._menu != null:
		sess._menu.visible = false
	sess.cam.auto_rotate = false
	sess.cam.keys_enabled = false
	sess.pending.mods = _set_mods(id, k)
	if args.has("gs-stock"):
		sess.pending.mods = {}
	sess.pending.paint1 = Color("#e0322b")
	sess.pending.paint2 = Color("#14161b")
	sess.preview()
	await _frames(8)
	var ext := sess.body_max.z - sess.body_min.z
	var views := {"f34": [36.0, 14.0, 1.7], "r34": [148.0, 14.0, 1.7], "side": [90.0, 5.0, 1.7], "top": [90.0, 60.0, 1.6], "front": [0.0, 8.0, 1.5], "rear": [180.0, 8.0, 1.5],
		"wheel": [82.0, 8.0, 0.62], "hood": [-20.0, 34.0, 1.0]}
	for vn in String(_opt("gs-views", "f34,r34,side")).split(","):
		var cfg: Array = views[vn]
		sess.cam.focus(sess._center(), deg_to_rad(cfg[0]), deg_to_rad(cfg[1]), ext * float(cfg[2]), false)
		sess.cam.snap_now()
		await _frames(5)
		print("GONE view=%s dist=%.2f yaw=%.1f pitch=%.1f campos=%s target=%s car=%s ext=%.2f" % [vn, sess.cam.dist, rad_to_deg(sess.cam.yaw), rad_to_deg(sess.cam.pitch),
			sess.cam.global_position, sess.cam.target, sess.vehicle.global_position, ext])
		_save(await _grab(), "one_%s_%d_%s" % [id, k, vn])
	await sess.end()


# ------------------------------------------------------------------------------------------------------------ menu pages
func _mode_menu() -> void:
	var v := await _spawn_at_bay(_opt("gs-veh", "sedan"))
	v.health = v.max_health * 0.55
	if v.wheels.size() > 0:
		v.wheels[1].flat = true
	if v.dmg != null:
		v.dmg.glass_state = 1
	gs.unlock_all = false
	Game.cash = 25000
	gs.begin_session(v, _shop_site(), 0)
	while gs.session == null or not gs.session.active:
		await get_tree().process_frame
	var sess: GarageSession = gs.session
	await get_tree().create_timer(1.0, true, false, true).timeout
	var menu: GarageMenu = sess._menu as GarageMenu
	sess.cam.auto_rotate = false
	var cats: Array = menu._cats
	var pend := sess.pending
	# pending selections so the right panel has content
	var shots_for := String(_opt("gs-cats", ",".join(cats.map(func(c): return String(c))))).split(",")
	for cname in shots_for:
		var idx := cats.find(StringName(cname))
		if idx < 0:
			continue
		match cname:
			"paint":
				pend.paint1 = Color("#ff3d9a")
				pend.finish = &"pearl"
			"wheels":
				pend.set_id("rim_style", &"split_six")
				pend.mods["rim_color"] = Color(0.85, 0.62, 0.16)
			"body":
				pend.set_part(&"spoiler", &"gt_wing")
				pend.set_part(&"front_bumper", &"splitter")
				pend.set_part(&"hood", &"scoop")
			"lights":
				pend.set_id("underglow", &"cyan", "off")
				pend.set_id("headlight", &"xenon")
			"windows":
				pend.set_level("window_tint", 2)
			"plates":
				pend.mods["plate"] = "neon"
			"livery":
				pend.mods["livery"] = "racing_twin"
				pend.mods["livery_color"] = Color(1, 1, 1)
			"horn":
				pend.mods["horn"] = 2
			"performance":
				pend.set_level("engine", 3)
				pend.set_level("brakes", 2)
				pend.set_level("turbo", 1)
				pend.set_level("armor", 2)
		sess.preview()
		menu._show_category(idx)
		await get_tree().create_timer(0.9, true, false, true).timeout
		_save(await _grab(), "menu_%s" % cname)
	await sess.end()


# ------------------------------------------------------------------------------------------------------------ bay (world)
func _mode_bay() -> void:
	var site := _shop_site()
	var bay: Dictionary = site["bays"][0]
	var e: Vector3 = bay["entry"]
	var inside: Vector3 = bay["inside"]
	var dir := Util.flat(inside - e).normalized()
	var v := VehicleFactory.spawn(&"sports", Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), e + dir * 2.5 + Vector3(0, 0.8, 0)), {})
	await _frames(40)
	Game.player.enter_vehicle(v)
	await _frames(30)
	var cam := Camera3D.new()
	_main_add(cam)
	cam.global_position = e - dir * 9.0 + Vector3(3.0, 3.2, 0)
	cam.look_at(e + dir * 2.0 + Vector3(0, 1.0, 0), Vector3.UP)
	cam.make_current()
	await _frames(20)
	_save(await _grab(), "bay_street")
	print("GBAY prompt=", gs._prompt_text)


func _main_add(n: Node) -> void:
	get_tree().root.get_node("Main").add_child(n)


# ------------------------------------------------------------------------------------------------------------ phone
func _mode_phone() -> void:
	Game.cash = 12345
	var ui = Game.ui
	ui.open_menu(&"phone")
	await get_tree().create_timer(0.9, true, false, true).timeout
	_save(await _grab(), "phone_home")
	var ph: PhoneMenu = ui.get_menu(&"phone") as PhoneMenu
	for app in ["services", "vehicles", "radio", "settings", "stats"]:
		if app == "vehicles":
			gs.add_record(&"sports", Color("#ff3d9a"), Color("#101010"), &"pearl", {"engine": 2})
			gs.add_record(&"muscle", Color("#34e0ff"), Color("#101010"))
		ph._open_app(StringName(app))
		await get_tree().create_timer(0.5, true, false, true).timeout
		_save(await _grab(), "phone_%s" % app)
	ui.close_menu()


# ------------------------------------------------------------------------------------------------------------ photo mode
func _mode_photo() -> void:
	var ph := gs.photo
	ph.enter()
	await get_tree().create_timer(0.8, true, false, true).timeout
	_save(await _grab(), "photo_neutral_ui")
	for f in ["vivid", "noir", "sunset"]:
		ph.filter = StringName(f)
		ph._apply_filter()
		await get_tree().create_timer(0.4, true, false, true).timeout
		_save(await _grab(), "photo_%s" % f)
	ph.dof_amount = 0.7
	ph._apply_dof()
	await get_tree().create_timer(0.4, true, false, true).timeout
	_save(await _grab(), "photo_dof")
	var path: String = await ph.take_photo()
	print("GPHOTO path=", path, " exists=", FileAccess.file_exists(path))
	await get_tree().create_timer(0.6, true, false, true).timeout
	_save(await _grab(), "photo_taken")
	ph.exit()
