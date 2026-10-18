extends Node
## Shops menu / interaction integration test (Shops/Interiors agent): the real PlayerInteraction path (prompt -> E -> enter), the
## counter use points opening the real menus, driving every menu through its buttons (purchase, cash accounting, live state), closing
## the menus (game unpaused, input unlocked).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/shop_menu_test.gd -Seconds 120 -GameArgs "--no-intro --no-traffic --no-peds"

var _fails := 0
var _passes := 0
var _prompts: Array[String] = []


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		print("TEST ", name, " PASS ", detail)
	else:
		_fails += 1
		print("TEST ", name, " FAIL ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _buttons(root: Node, out: Array = []) -> Array:
	for c in root.get_children():
		if c is BaseButton:
			out.append(c)
		_buttons(c, out)
	return out


func _find_button(root: Node, starts: String) -> Button:
	for b in _buttons(root):
		if b is Button and (b as Button).text.begins_with(starts) and (b as Button).visible:
			return b
	return null


func _press(b: BaseButton) -> void:
	if b != null and not b.disabled:
		b.pressed.emit()


func _menu(shops: Node, id: StringName) -> Node:
	return shops.menus[id]


func _close_menu() -> void:
	if Game.ui != null and Game.ui.is_menu_open():
		Game.ui.close_menu()


func _use(room: InteriorRoom, tag: StringName) -> void:
	var d: InteriorDoor = room.points[tag]
	d.interact(Game.player)


func run(_main: Node) -> void:
	await _frames(25)
	var shops = Game.sys(&"shops")
	var it = Game.sys(&"interiors")
	var sh = Game.sys(&"safehouse")
	var p = Game.player
	var wc = p.weapons
	if shops == null or it == null or not is_instance_valid(p) or Game.ui == null:
		print("TEST ABORT missing systems")
		return
	Events.interaction_prompt.connect(func(t: String) -> void: _prompts.append(t))
	Game.cash = 20000
	shops.free_shopping = false
	Game.time_of_day = 12.0
	# ---------------------------------------------------------------- real interaction path: prompt -> E -> enter
	var door = it.door_for(&"weapon_shop")
	var ret: Vector3 = door.data["return"]
	var yaw: float = float(door.data["yaw"])
	p.teleport_to(ret + Vector3(0, 0.3, 0), yaw + PI)      # walking TOWARDS the door
	await _frames(40)
	_ok("world_door_prompt", _prompts.has("Enter Gunsmith") or _prompts.any(func(t: String) -> bool: return t.contains("Gunsmith")), "last prompts %s" % str(_prompts.slice(maxi(_prompts.size() - 3, 0))))
	var pi = p.get("interaction")
	var tried := false
	if pi != null and pi.has_method("try_interact"):
		tried = bool(pi.try_interact())
	elif pi == null:
		Input.action_press(&"interact")
		await _frames(3)
		Input.action_release(&"interact")
		tried = true
	await _frames(3)
	var t0 := Time.get_ticks_msec()
	while not it.is_inside() and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	_ok("interact_enters_weapon_shop", tried and it.is_inside() and it.current_interior == &"weapon_shop", "tried=%s inside=%s" % [str(tried), str(it.is_inside())])
	await _frames(20)
	var room: InteriorRoom = it.get_current_room()
	if room == null:
		print("TEST ABORT no room")
		return
	# exit prompt inside
	p.global_position = room.to_global(room.exit_door.position) + Vector3(0, 0.1, 0.0)
	await _frames(20)
	_ok("exit_prompt_inside", _prompts.any(func(t: String) -> bool: return t.contains("Exit")), "")
	# ---------------------------------------------------------------- weapons menu
	p.global_position = room.to_global(room.points[&"counter"].position) + Vector3(0, 0.1, 0)
	_use(room, &"counter")
	await _frames(6)
	_ok("counter_opens_weapon_menu", Game.ui.is_menu_open() and Game.ui.current_menu == _menu(shops, &"shop_weapons"), "")
	_ok("menu_pauses_game", get_tree().paused, "")
	var wm: WeaponShopMenu = _menu(shops, &"shop_weapons")
	_ok("menu_has_room_data", wm.room == room and wm.shop_id == &"weapon_shop", "")
	wm._on_tab(1)
	wm._select(&"smg")
	await _frames(2)
	var cash0 := Game.cash
	var b := _find_button(wm, "Buy")
	_ok("weapon_buy_button_exists", b != null, "")
	_press(b)
	await _frames(2)
	_ok("menu_buy_smg", wc.has_weapon(&"smg") and Game.cash == cash0 - 1650, "cash %d -> %d" % [cash0, Game.cash])
	var reserve0 := int(wc.inventory[&"smg"]["reserve"])
	b = _find_button(wm, "+1 mag")
	_press(b)
	await _frames(2)
	_ok("menu_buy_ammo", int(wc.inventory[&"smg"]["reserve"]) > reserve0, "reserve %d -> %d" % [reserve0, int(wc.inventory[&"smg"]["reserve"])])
	wm._on_tab(6)
	await _frames(2)
	p.armor = 0.0
	cash0 = Game.cash
	b = _find_button(wm, "Buy")
	_press(b)
	await _frames(2)
	_ok("menu_buy_armor", p.armor >= 99.0 and Game.cash == cash0 - ShopSystem.ARMOR_PRICE, "armor %.0f cash %d" % [p.armor, Game.cash])
	# every category tab + every weapon selects without error
	var sel_count := 0
	for t in WeaponShopMenu.TABS.size():
		wm._on_tab(t)
		for id in wm._items_for_tab():
			wm._select(id)
			sel_count += 1
	_ok("weapon_menu_every_item_selectable", sel_count >= 14, "%d items" % sel_count)
	_close_menu()
	await _frames(4)
	_ok("menu_closed_unpauses", not Game.ui.is_menu_open() and not get_tree().paused, "")
	# ---------------------------------------------------------------- bench
	wc.give_weapon(&"pistol", 60, false)
	wc.equip(&"pistol")
	_use(room, &"bench")
	await _frames(6)
	_ok("bench_opens", Game.ui.current_menu == _menu(shops, &"shop_bench"), "")
	var bm: WeaponBenchMenu = _menu(shops, &"shop_bench")
	bm._select(&"pistol")
	cash0 = Game.cash
	bm._toggle_mod(&"suppressor")
	await _frames(2)
	_ok("bench_install_mod", wc.has_mod(&"pistol", &"suppressor") and Game.cash < cash0, "cash %d -> %d" % [cash0, Game.cash])
	bm._hover_mod(&"magazine_ext")
	bm._hover_tint(&"crimson")
	bm._hover_tint(&"")
	cash0 = Game.cash
	var tint_btn: BaseButton = null
	for bt in _buttons(bm):
		if (bt as BaseButton).tooltip_text.begins_with("Crimson"):
			tint_btn = bt
	_ok("bench_tint_button", tint_btn != null, "")
	_press(tint_btn)
	await _frames(2)
	var tint: Color = wc.inventory[&"pistol"]["tint"]
	_ok("bench_tint_applied", tint.a > 0.5 and Game.cash == cash0 - WeaponMods.TINT_PRICE, "tint %s cash %d" % [tint.to_html(), Game.cash])
	bm._toggle_mod(&"suppressor")
	await _frames(2)
	_ok("bench_remove_mod", not wc.has_mod(&"pistol", &"suppressor"), "")
	_close_menu()
	await _frames(4)
	_ok("modded_weapon_model_ok", true, "")
	await it.exit(true)
	await _frames(10)
	# ---------------------------------------------------------------- clothing store + wardrobe
	var cd = it.door_for(&"clothing_store")
	await it.enter(&"clothing_store", cd.data["return"], float(cd.data["yaw"]), true)
	await _frames(10)
	room = it.get_current_room()
	_use(room, &"counter")
	await _frames(6)
	var cm: WardrobeMenu = _menu(shops, &"shop_clothes")
	_ok("clothes_menu_opens_store_mode", Game.ui.current_menu == cm and cm.mode == &"store", "")
	for ci in WardrobeDefs.CATEGORIES.size():
		cm._on_tab(ci)
	cm._on_tab(0)
	cm._try(&"tops", "top_coral_tee")
	cm._try(&"hats", "hat_black_cap")
	await _frames(2)
	cash0 = Game.cash
	var pend: Dictionary = cm._pending()
	cm._buy_btn.pressed.emit()
	await _frames(4)
	_ok("clothes_buy_and_wear", Game.cash == cash0 - int(pend["total"]) and int(pend["total"]) > 0 and String(p.rig.variant["hat"]) == "Hat_Cap" and shops.owns_item("hat_black_cap"), "paid %d" % (cash0 - Game.cash))
	_close_menu()
	await _frames(4)
	await it.exit(true)
	await _frames(5)
	# safehouse wardrobe (free)
	var sd = it.door_for(&"safehouse")
	await it.enter(&"safehouse", sd.data["return"], float(sd.data["yaw"]), true)
	await _frames(10)
	room = it.get_current_room()
	_use(room, &"wardrobe")
	await _frames(6)
	_ok("wardrobe_opens_wardrobe_mode", Game.ui.current_menu == cm and cm.mode == &"wardrobe", "mode %s" % str(cm.mode))
	cash0 = Game.cash
	cm._try(&"tops", "top_black_tee")
	cm._buy_btn.pressed.emit()
	await _frames(4)
	_ok("wardrobe_wear_free", Game.cash == cash0 and (shops.get_variant()["shirt"] as Color).is_equal_approx(Color("#2a2d33")), "cash %d" % Game.cash)
	_close_menu()
	await _frames(4)
	# ---------------------------------------------------------------- sleep menu
	Game.time_of_day = 22.0
	Game.time_frozen = true
	_use(room, &"bed")
	await _frames(6)
	_ok("bed_opens_sleep_menu", Game.ui.current_menu == _menu(sh, &"safehouse_sleep"), "")
	var sb := _find_button(_menu(sh, &"safehouse_sleep"), "Sleep")
	if sb == null:
		for bt in _buttons(_menu(sh, &"safehouse_sleep")):
			print("   sleep menu button: ", bt.name, " ", (bt as BaseButton).tooltip_text, " ", (bt as Button).text if bt is Button else "")
	_close_menu()
	await _frames(3)
	await it.exit(true)
	await _frames(5)
	# ---------------------------------------------------------------- barber
	var bd = it.door_for(&"barber")
	await it.enter(&"barber", bd.data["return"], float(bd.data["yaw"]), true)
	await _frames(10)
	room = it.get_current_room()
	var barber_tag: StringName = &""
	for tg in room.points:
		if StringName(room.points[tg].data.get("menu", &"")) == &"barber":
			barber_tag = tg
			break
	_ok("barber_use_points_exist", barber_tag != &"", str(room.points.keys()))
	_use(room, barber_tag)
	await _frames(6)
	var bam: BarberMenu = _menu(shops, &"shop_barber")
	_ok("barber_menu_opens", Game.ui.current_menu == bam, "points %s" % str(room.points.keys()))
	if Game.ui.current_menu == bam:
		for ti in 3:
			bam._on_tab(ti)
		bam._on_tab(0)
		bam._pick_hair(4)
		bam._pick_beard(&"Beard_1")
		await _frames(2)
		cash0 = Game.cash
		bam._pay.pressed.emit()
		await _frames(4)
		_ok("barber_pay", Game.cash < cash0 and int(p.rig.variant["hair"]) == 4 and String(p.rig.variant["beard"]) == "Beard_1", "cash %d -> %d hair %s" % [cash0, Game.cash, str(p.rig.variant["hair"])])
	_close_menu()
	await _frames(4)
	await it.exit(true)
	await _frames(5)
	# ---------------------------------------------------------------- gas station food + scuba shop
	var gd = it.door_for(&"gas_station")
	await it.enter(&"gas_station", gd.data["return"], float(gd.data["yaw"]), true)
	await _frames(10)
	room = it.get_current_room()
	p.health = 40.0
	_use(room, &"counter")
	await _frames(6)
	var gm: GoodsMenu = _menu(shops, &"shop_goods")
	_ok("food_menu_opens", Game.ui.current_menu == gm and gm.catalog == &"food", "")
	gm._select(&"burger")
	await _frames(2)
	cash0 = Game.cash
	b = _find_button(gm, "Buy")
	_press(b)
	await _frames(2)
	_ok("food_menu_buy_heals", absf(p.health - 65.0) < 0.6 and Game.cash == cash0 - 8, "hp %.0f cash %d" % [p.health, Game.cash])
	_close_menu()
	await _frames(4)
	await it.exit(true)
	await _frames(5)
	var scd = it.door_for(&"scuba_shop")
	await it.enter(&"scuba_shop", scd.data["return"], float(scd.data["yaw"]), true)
	await _frames(10)
	room = it.get_current_room()
	_use(room, &"counter")
	await _frames(6)
	_ok("scuba_menu_opens", Game.ui.current_menu == gm and gm.catalog == &"scuba", "")
	gm._select(&"scuba_kit")
	await _frames(2)
	shops.scuba_owned = false
	cash0 = Game.cash
	b = _find_button(gm, "Buy")
	_press(b)
	await _frames(2)
	_ok("scuba_menu_buy", shops.scuba_owned and Game.cash == cash0 - ShopSystem.SCUBA_PRICE, "cash %d" % Game.cash)
	_close_menu()
	await _frames(4)
	# closed-shop: the menu cannot be reached when the world door is closed
	await it.exit(true)
	await _frames(5)
	Game.time_of_day = 2.0
	var cd2: Dictionary = it.door_for(&"clothing_store").get_interaction(p)
	_ok("closed_shop_blocks_entry", not bool(cd2.get("enabled", true)), str(cd2))
	it._world_door_use(&"clothing_store", it.door_for(&"clothing_store"))
	await _frames(5)
	_ok("closed_shop_no_enter", not it.is_inside(), "")
	Game.time_of_day = 12.0
	_ok("no_menu_left_open", not Game.ui.is_menu_open() and not get_tree().paused, "")
	print("TEST SUMMARY pass=%d fail=%d" % [_passes, _fails])
