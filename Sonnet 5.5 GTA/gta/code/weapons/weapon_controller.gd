class_name WeaponController
extends Node
## Weapon component of a CharacterBase (player, police, hostile NPCs). Owns the inventory, the held weapon model (attached to
## rig.get_hand_socket(true), or floating at the character when there is no rig), firing, reloading, recoil, accuracy,
## melee, grenades, launchers, mods, the aim ray and the scope/ADS state.
##
## The caller sets the aim ray every frame with set_aim_ray() (camera centre ray for the player, eye -> target for AI);
## shots leave the muzzle and converge on the point the aim ray hits. Everything cosmetic is pooled (FxManager).
## See docs/api/weapons.md for the complete public API.

signal fired(weapon_id: StringName)
signal reloaded(weapon_id: StringName)
signal weapon_changed(weapon_id: StringName)
signal ammo_changed(weapon_id: StringName, in_mag: int, reserve: int)
signal empty_clicked(weapon_id: StringName)
## Extra signals (additive)
signal reload_started(weapon_id: StringName, duration: float)
signal recoil_kick(pitch: float, yaw: float)                 ## radians, per shot (camera already receives it via add_recoil)
signal hit_confirmed(info: Dictionary)                       ## {target, killed, zone, damage, weapon, headshot}
signal melee_hit(info: Dictionary)
signal grenade_thrown(grenade: Node)
signal mods_changed(weapon_id: StringName)

const RECOIL_CAM_SCALE := 1.0          ## degrees of def.recoil -> camera kick multiplier
const AUTO_RELOAD_DELAY := 0.25
const FISTS := &"fists"

var character: CharacterBase = null
var current_id: StringName = &"fists"
## weapon_id -> {"mag": int, "reserve": int, "mods": {mod_id: true}, "tint": Color}
var inventory: Dictionary = {}
var is_aiming := false
var is_reloading := false

# ---- public read-only state (HUD / camera / AI read these) ------------------------------------------------
var kick_pitch := 0.0                   ## current view-kick (rad, + = up) for cameras that want to poll instead of using add_recoil
var kick_yaw := 0.0
var aim_t := 0.0                        ## 0..1 ADS blend
var scope_active := false               ## full-screen scope overlay should be shown (sniper while fully aimed)
var scope_sway := Vector2.ZERO          ## breath sway (yaw, pitch rad) to add to the view while scoped
var current_spread := 1.5               ## current cone half-angle in degrees (crosshair size)
var reload_progress := 0.0              ## 0..1 while is_reloading
var aim_target: Node = null             ## damageable under the crosshair (player only), for the red crosshair
var crouched := false                   ## set by the Player (also auto-read from character.is_crouching / .crouching)
var drive_rig_aim := false              ## true: this controller calls rig.set_aim() (AI); false: the owner does it (player)
var auto_reload := true
var flashlight_on := false              ## manual flashlight state (T); also auto-on when aiming at night
var flashlight_auto := true
var last_target: Node = null            ## last damageable hit by this controller
var ai_target_point := Vector3.ZERO

# ---- internal ---------------------------------------------------------------------------------------------
var _def: Dictionary = {}
var _eff: Dictionary = {}               # effective numbers for the current weapon + mods
var _model: WeaponModel = null
var _free_mode := false
var _free_dir := Vector3(0, 0, -1)
var _now := 0.0
var _dt := 0.016
var _always_tick := false
var _was_dead := false

var _trigger := false
var _next_shot := 0.0
var _equip_end := 0.0
var _burst_left := 0
var _burst_next := 0.0
var _semi_buffer_until := 0.0
var _fire_mode: StringName = &"auto"
var _dry_t := -10.0
var _last_shot_time := -10.0
var _cycle_sfx_at := -1.0
var _cycle_eject := false

var _reload_start := 0.0
var _reload_end := 0.0
var _reload_dur := 1.0
var _reload_style: StringName = &"mag"
var _reload_sfx_done := false
var _shell_next := 0.0
var _auto_reload_at := -1.0
var _reload_queued := false

var _kick_target_pitch := 0.0
var _kick_target_yaw := 0.0
var _recoil_hold := 0.0
var _bloom := 0.0
var _bloom_hold := 0.0

var _aim_origin := Vector3.ZERO
var _aim_dir := Vector3(0, 0, -1)
var _aim_stamp := -10.0
var _aim_goal := 0.0
var _aim_scan := 0.0
var _zoom_level := 0
var _breath_hold := false
var _breath := 1.0
var _exhaust := 0.0
var _fov_overridden := false

var _melee_pending := false
var _melee_hit_time := 0.0
var _melee_busy_until := 0.0
var _melee_heavy := false
var _melee_def: Dictionary = {}
var _melee_weapon: StringName = &"fists"
var _combo := 0
var _last_melee := -10.0
var _melee_buffer := -1
var _cook_t0 := -1.0
var _throw_pending := false
var _throw_at := 0.0
var _throw_cooked := 0.0
var _next_throw := 0.0

var _noise_last := 0.0
var _excl: Array[RID] = []
var _bparams: Dictionary = {}
var _budget: Array = [3]
var _last_in_cat: Dictionary = {}
var _order_dirty := true
var _order: Array = []
var _tracer_col := Color(1.0, 0.88, 0.55)
var _tracer_n := 0
var _pose_sent: StringName = &""


# ================================================================================================= lifecycle
func setup(owner_character: CharacterBase) -> void:
	character = owner_character
	if character != null and character.get("weapons") == null:
		character.weapons = self
	_always_tick = character != null and character.is_player()
	drive_rig_aim = not _always_tick
	_bparams = {
		"shooter": character, "weapon": &"fists", "damage": 10.0, "range": 100.0, "falloff_start": 30.0, "falloff_min": 0.5,
		"penetration": 0, "impulse": 0.0, "exclude": _excl, "mask": GC.M_BULLET, "type": GC.DMG_BULLET, "spawn_fx": true,
		"sfx_budget": _budget,
	}
	if not inventory.has(FISTS):
		inventory[FISTS] = {"mag": 0, "reserve": 0, "mods": {}, "tint": Color(0, 0, 0, 0)}
	_equip_internal(FISTS, true)
	set_physics_process(_always_tick)


func _exit_tree() -> void:
	_release_fov()


func _wake() -> void:
	if not is_physics_processing():
		set_physics_process(true)


# ================================================================================================= inventory
## Adds a weapon. ammo = total rounds you receive (new firearm: fills the magazine first, rest to reserve; owned weapon: adds
## to reserve). Melee weapons ignore ammo. equip_now equips it immediately.
func give_weapon(id: StringName, ammo: int = 0, equip_now: bool = false) -> void:
	if not WeaponDefs.has(id):
		push_warning("WeaponController.give_weapon: unknown weapon '%s'" % id)
		return
	var d := WeaponDefs.get_def(id)
	var is_new := not inventory.has(id)
	var entry: Dictionary = inventory.get(id, {})
	if is_new:
		entry = {"mag": 0, "reserve": 0, "mods": {}, "tint": Color(0, 0, 0, 0)}
		inventory[id] = entry
		_order_dirty = true
	if int(d["mag_size"]) > 0:
		var mods: Dictionary = entry["mods"]
		var mag_cap := WeaponDefs.mag_capacity(id, mods)
		var res_cap := WeaponDefs.reserve_capacity(id, mods)
		if is_new:
			var m := mini(ammo, mag_cap)
			entry["mag"] = m
			entry["reserve"] = clampi(ammo - m, 0, res_cap)
		else:
			entry["reserve"] = mini(int(entry["reserve"]) + ammo, res_cap)
	_emit_ammo(id)
	if equip_now:
		equip(id)
	elif id == current_id:
		_apply_def()


func has_weapon(id: StringName) -> bool:
	return inventory.has(id)


func remove_weapon(id: StringName) -> void:
	if id == FISTS:
		return
	inventory.erase(id)
	_order_dirty = true
	if id == current_id:
		_equip_internal(FISTS, true)


## Adds rounds to a weapon's reserve (capped). Returns the number of rounds actually added.
func add_ammo(id: StringName, amount: int) -> int:
	if not inventory.has(id):
		return 0
	var entry: Dictionary = inventory[id]
	var d := WeaponDefs.get_def(id)
	if int(d.get("mag_size", 0)) <= 0:
		return 0
	var cap := WeaponDefs.reserve_capacity(id, entry["mods"])
	var before: int = int(entry["reserve"])
	entry["reserve"] = mini(before + amount, cap)
	_emit_ammo(id)
	return int(entry["reserve"]) - before


func refill_all_ammo() -> void:
	for id in inventory:
		var d := WeaponDefs.get_def(id)
		if int(d.get("mag_size", 0)) <= 0:
			continue
		var entry: Dictionary = inventory[id]
		entry["mag"] = WeaponDefs.mag_capacity(id, entry["mods"])
		entry["reserve"] = WeaponDefs.reserve_capacity(id, entry["mods"])
		_emit_ammo(id)


func get_weapon_ids() -> Array:
	return inventory.keys()


## Owned weapon ids in wheel order (category order, then price). Fists first.
func get_ordered_ids() -> Array:
	if _order_dirty:
		_order = inventory.keys()
		_order.sort_custom(func(a, b):
			var da := WeaponDefs.get_def(a)
			var db := WeaponDefs.get_def(b)
			var ca := WeaponDefs.CATEGORY_ORDER.find(da.get("category", &""))
			var cb := WeaponDefs.CATEGORY_ORDER.find(db.get("category", &""))
			if ca != cb:
				return ca < cb
			return int(da.get("price", 0)) < int(db.get("price", 0)))
		_order_dirty = false
	return _order


# ================================================================================================= selection
func equip(id: StringName) -> bool:
	if not inventory.has(id):
		return false
	if id == current_id and _model != null or (id == FISTS and current_id == FISTS):
		return true
	_equip_internal(id, false)
	return true


func equip_next() -> void:
	_cycle(1)


func equip_prev() -> void:
	_cycle(-1)


func _cycle(step: int) -> void:
	var ids := get_ordered_ids()
	if ids.size() < 2:
		return
	var i := ids.find(current_id)
	i = (i + step + ids.size()) % ids.size()
	equip(ids[i])


## Slots 1..8 = categories (melee, handgun, smg, shotgun, rifle, sniper, heavy, thrown), 9 = unarmed.
## Pressing the same slot again cycles through the weapons of that category.
func equip_slot(slot: int) -> void:
	if slot == 9 or slot < 1 or slot > WeaponDefs.SLOT_CATEGORIES.size():
		equip(FISTS)
		return
	var cat: StringName = WeaponDefs.SLOT_CATEGORIES[slot - 1]
	var owned: Array = []
	for id in get_ordered_ids():
		if WeaponDefs.get_def(id).get("category", &"") == cat:
			owned.append(id)
	if owned.is_empty():
		return
	if cat == &"melee" and owned.size() > 1 and owned.has(FISTS):
		owned.erase(FISTS)
		owned.append(FISTS)
	var cur_cat: StringName = _def.get("category", &"")
	if cur_cat == cat:
		var i := owned.find(current_id)
		equip(owned[(i + 1) % owned.size()])
	else:
		var last: StringName = _last_in_cat.get(cat, owned[0])
		equip(last if owned.has(last) else owned[0])


func holster() -> void:
	set_trigger(false)
	set_aiming(false)
	equip(FISTS)


func _equip_internal(id: StringName, silent: bool) -> void:
	_cancel_actions()
	var d := WeaponDefs.get_def(id)
	if d.is_empty():
		return
	var changed := id != current_id
	current_id = id
	_def = d
	if id != FISTS:
		_last_in_cat[d["category"]] = id
	_fire_mode = _def["mode"]
	_zoom_level = 0
	_apply_def()
	_free_model()
	if str(d["model"]) != "":
		var entry := _entry()
		_model = WeaponModel.create(id, entry["mods"], entry["tint"])
		_attach_model()
	_equip_end = _now + float(_def["equip_time"])
	if _model != null:
		_model.set_equip_progress(0.0)
	_set_rig_pose()
	if not silent or changed:
		weapon_changed.emit(id)
		Events.weapon_changed.emit(character, id)
		_emit_ammo(id)
		if id != FISTS:
			Sfx.play_3d(&"reload_end", _muzzle_pos(), -9.0, 1.3, 20.0)
	_wake()
	_auto_reload_at = _equip_end + 0.1 if (_uses_mag() and int(_entry()["mag"]) <= 0 and int(_entry()["reserve"]) > 0 and auto_reload) else -1.0


func _apply_def() -> void:
	var entry := _entry()
	_eff = WeaponMods.effective(entry["mods"])
	_eff["damage"] = float(_def["damage"]) * float(_eff["damage_mult"])
	_eff["range"] = float(_def["range"]) * float(_eff["range_mult"])
	_eff["noise"] = float(_def["noise"]) * float(_eff["noise_mult"])
	_eff["zoom"] = float(_def["aim_zoom"]) * float(_eff["zoom_mult"])
	_eff["mag_cap"] = WeaponDefs.mag_capacity(current_id, entry["mods"])
	_eff["sfx"] = &"shot_suppressed" if _eff["suppressed"] else _def["sfx_shot"]
	_tracer_col = FxRes.color_from(_def.get("tracer", "#ffe2a0"), Color(1.0, 0.88, 0.55))
	_noise_last = float(_eff["noise"])


func _cancel_actions() -> void:
	if is_reloading:
		_cancel_reload()
	_burst_left = 0
	_semi_buffer_until = 0.0
	_melee_pending = false
	_cook_t0 = -1.0
	_throw_pending = false
	_cycle_sfx_at = -1.0
	_reload_queued = false
	_auto_reload_at = -1.0


func _entry() -> Dictionary:
	if inventory.has(current_id):
		return inventory[current_id]
	return {"mag": 0, "reserve": 0, "mods": {}, "tint": Color(0, 0, 0, 0)}


func _uses_mag() -> bool:
	return int(_def.get("mag_size", 0)) > 0 and _def.get("category", &"") != &"thrown"


func _is_melee() -> bool:
	return _def.get("category", &"melee") == &"melee"


func _is_thrown() -> bool:
	return _def.get("category", &"") == &"thrown"


func _infinite_ammo() -> bool:
	return character != null and character.is_player() and bool(Game.cheats.get("infinite_ammo", false))


# ================================================================================================= model / rig
func _rig() -> Node:
	if character == null or not is_instance_valid(character):
		return null
	var r = character.get("rig")
	if r != null and is_instance_valid(r):
		return r
	return null


func _hand_socket() -> Node3D:
	var rig := _rig()
	if rig != null and rig.has_method("get_hand_socket"):
		var s = rig.get_hand_socket(true)
		if s != null and is_instance_valid(s) and s != rig and s is Node3D:
			return s
	return null


func _free_model() -> void:
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null


func _attach_model() -> void:
	if _model == null or character == null:
		return
	var socket := _hand_socket()
	var parent: Node = socket if socket != null else character
	_free_mode = socket == null
	if _model.get_parent() != parent:
		if _model.get_parent() != null:
			_model.get_parent().remove_child(_model)
		parent.add_child(_model)
	if not _free_mode:
		_model.transform = Transform3D.IDENTITY
		var gp = _def.get("grip_pos")
		var gr = _def.get("grip_rot")
		if gp is Vector3:
			_model.position = gp
		if gr is Vector3:
			_model.rotation_degrees = gr
	else:
		_free_dir = -character.global_transform.basis.z


func _set_rig_pose() -> void:
	var rig := _rig()
	if rig != null and rig.has_method("set_weapon_pose"):
		rig.set_weapon_pose(_def.get("pose", &"none"))


func _muzzle_pos() -> Vector3:
	if _model != null and is_instance_valid(_model) and _model.is_inside_tree():
		return _model.muzzle_world()
	if character != null and is_instance_valid(character):
		return character.global_position + Vector3(0, 1.35, 0) - character.global_transform.basis.z * 0.6
	return Vector3.ZERO


func _update_model(delta: float) -> void:
	if _model == null or not is_instance_valid(_model):
		return
	# re-attach when the rig appears / changes
	if _free_mode and _hand_socket() != null:
		_attach_model()
	var hide := character.is_dead or (character.is_in_vehicle() and not bool(_def.get("vehicle_ok", false)))
	_model.visible = not hide
	if _now < _equip_end:
		_model.set_equip_progress(1.0 - (_equip_end - _now) / maxf(float(_def["equip_time"]), 0.05))
	elif _model._equip_p < 1.0:
		_model.set_equip_progress(1.0)
	if _free_mode:
		var fwd_char := -character.global_transform.basis.z
		var raised := is_aiming or (_now - _last_shot_time < 1.6) or _now < _melee_busy_until
		var aim_dir := _get_aim_dir()
		var want: Vector3 = aim_dir if raised else (fwd_char + Vector3.DOWN * 0.75).normalized()
		_free_dir = _free_dir.slerp(want, 1.0 - exp(-12.0 * delta)).normalized()
		var pos := character.global_position + Vector3(0, 1.25, 0) + character.global_transform.basis.x * 0.22 + _free_dir * 0.35
		var up := Vector3.UP if absf(_free_dir.y) < 0.98 else Vector3.RIGHT
		_model.global_transform = Transform3D(Basis.looking_at(_free_dir, up), pos)
	# keep the owner's rig aware of the aim (AI only; the Player drives its own rig)
	if drive_rig_aim:
		var rig := _rig()
		if rig != null and rig.has_method("set_aim"):
			var d := _get_aim_dir()
			rig.set_aim(is_aiming or _now - _last_shot_time < 1.2, asin(clampf(d.y, -1.0, 1.0)), 0.0)


# ================================================================================================= input API
## Hold/release the trigger (automatic weapons keep firing while held; grenades cook while held and throw on release).
func set_trigger(pressed: bool) -> void:
	if character == null or not is_instance_valid(character):
		return
	var was := _trigger
	_trigger = pressed
	if pressed and not was:
		_wake()
		_on_trigger_pressed()
	elif was and not pressed:
		if _is_thrown() and _cook_t0 >= 0.0:
			release_grenade()
		_semi_buffer_until = 0.0


func _on_trigger_pressed() -> void:
	if _is_melee():
		melee_attack(false)
	elif _is_thrown():
		begin_grenade_cook()
	else:
		_semi_buffer_until = _now + 0.12
		_try_primary()


## Single shot / swing attempt. Returns true if a round was fired or a melee swing started.
func fire_once() -> bool:
	_wake()
	if _is_melee():
		return _start_melee(false)
	if _is_thrown():
		return throw_grenade_now()
	return _try_primary()


func set_aiming(aiming: bool) -> void:
	is_aiming = aiming
	_aim_goal = 1.0 if aiming else 0.0
	_wake()
	if aiming and _uses_mag() and auto_reload:
		pass


func hold_breath(on: bool) -> void:
	_breath_hold = on


## Cycles the scope zoom level (weapons with scope_zoom2, e.g. the sniper).
func cycle_zoom() -> void:
	if float(_def.get("scope_zoom2", 0.0)) > 0.0:
		_zoom_level = 1 - _zoom_level


func toggle_fire_mode() -> void:
	if _def.get("mode", &"") == &"burst":
		_fire_mode = &"auto" if _fire_mode == &"burst" else &"burst"
		_burst_left = 0


func toggle_flashlight() -> void:
	if _model != null and _model.has_flashlight():
		flashlight_on = not flashlight_on
		_wake()


## Aim ray in world space: origin (camera/eye) and unit direction. Call every frame while the weapon is usable.
func set_aim_ray(origin: Vector3, direction: Vector3) -> void:
	_aim_origin = origin
	_aim_dir = direction.normalized()
	_aim_stamp = _now


## Convenience for AI: aim at a world point from the character's eye. accuracy < 0 uses character.ai_accuracy.
func aim_at_point(point: Vector3, accuracy: float = -1.0) -> void:
	if character == null or not is_instance_valid(character):
		return
	var o := character.get_eye_position()
	var d := point - o
	if d.length_squared() < 0.0001:
		d = -character.global_transform.basis.z
	ai_target_point = point
	if accuracy >= 0.0:
		character.set_meta(&"_acc_override", accuracy)
	set_aim_ray(o, d.normalized())
	if not is_aiming:
		is_aiming = true
		_aim_goal = 1.0
	_wake()


func clear_ai_aim() -> void:
	if is_aiming:
		is_aiming = false
		_aim_goal = 0.0


func _get_aim_dir() -> Vector3:
	if _now - _aim_stamp < 0.4 and _aim_dir.length_squared() > 0.5:
		return _aim_dir
	return character.get_aim_direction()


# ================================================================================================= tick
func _physics_process(delta: float) -> void:
	if character == null or not is_instance_valid(character):
		return
	_dt = delta
	_now += delta
	if character.is_dead:
		if not _was_dead:
			_on_owner_died()
		_was_dead = true
		if _model != null:
			_model.visible = false
		return
	elif _was_dead:
		_was_dead = false
		_on_owner_revived()
	_update_aim_blend(delta)
	_update_accuracy(delta)
	_update_recoil(delta)
	_update_reload()
	_update_fire()
	_update_melee()
	_update_throw()
	_update_model(delta)
	_update_scope(delta)
	_update_aim_target(delta)
	_update_flashlight()
	if not _always_tick and not _needs_tick():
		set_physics_process(false)


func _needs_tick() -> bool:
	return (_trigger or _burst_left > 0 or is_reloading or _now < _equip_end or _melee_pending or _now < _melee_busy_until
		or _cook_t0 >= 0.0 or _throw_pending or absf(kick_pitch) > 0.0005 or _kick_target_pitch > 0.0005 or _bloom > 0.01
		or absf(aim_t - _aim_goal) > 0.005 or _now < _next_shot or _auto_reload_at >= 0.0 or _cycle_sfx_at >= 0.0
		or _semi_buffer_until > _now or is_aiming or _now - _last_shot_time < 1.7 or flashlight_on or _fov_overridden)


func _on_owner_died() -> void:
	_trigger = false
	_cancel_actions()
	is_aiming = false
	_aim_goal = 0.0
	aim_t = 0.0
	scope_active = false
	_release_fov()
	if _model != null:
		_model.set_flashlight(false)


func _on_owner_revived() -> void:
	if _model != null:
		_model.visible = true
	_kick_target_pitch = 0.0
	kick_pitch = 0.0


func _update_aim_blend(delta: float) -> void:
	var goal := _aim_goal
	if is_reloading and not _is_shell_reload():
		goal = 0.35 * goal
	var rate := 7.0 if _def.get("scope", false) else 10.0
	aim_t = Util.damp(aim_t, goal, rate, delta)
	if absf(aim_t - goal) < 0.002:
		aim_t = goal


func _update_accuracy(delta: float) -> void:
	_bloom_hold -= delta
	if _bloom_hold <= 0.0:
		_bloom = maxf(_bloom - float(_def.get("bloom_recover", 5.0)) * delta, 0.0)
	current_spread = get_current_spread()


## Cone half-angle (degrees) of the next shot: hip/aim base, movement, bloom, stance, mods, AI skill.
func get_current_spread() -> float:
	if _def.is_empty():
		return 0.0
	var aim_eff := maxf(aim_t, 0.0)
	var is_ai := character != null and not character.is_player()
	if is_ai:
		aim_eff = maxf(aim_eff, 0.7)
	var hip: float = float(_def["spread"]) * float(_eff.get("spread_mult", 1.0))
	var aimed: float = float(_def["aim_spread"]) * float(_eff.get("aim_spread_mult", 1.0)) * float(_eff.get("spread_mult", 1.0))
	var s := lerpf(hip, aimed, aim_eff)
	var speed := character.get_speed_xz() if character != null else 0.0
	s += float(_def["move_spread"]) * clampf(speed / 6.0, 0.0, 1.4) * lerpf(1.0, 0.45, aim_eff)
	s += _bloom
	if crouched or (character != null and (character.get("is_crouching") == true or character.get("crouching") == true)):
		s *= 0.7
	if character != null:
		if not character.is_on_floor() and absf(character.velocity.y) > 1.5 and not character.is_in_vehicle():
			s *= 1.8
		elif character.is_in_vehicle():
			s *= 1.5
	if is_ai:
		var acc = character.get_meta(&"_acc_override") if character.has_meta(&"_acc_override") else character.get("ai_accuracy")
		var a := clampf(float(acc) if acc != null else 0.5, 0.0, 1.0)
		s *= lerpf(3.2, 0.75, a)
	else:
		s *= _player_skill_mod(&"spread")       # Systems-A hook: shooting skill
	return s


func _update_recoil(delta: float) -> void:
	_recoil_hold -= delta
	var rec_rate := deg_to_rad(float(_def.get("recoil_recover", 9.0)))
	if _recoil_hold <= 0.0:
		_kick_target_pitch = move_toward(_kick_target_pitch, 0.0, rec_rate * delta * (1.0 + _kick_target_pitch * 3.0))
		_kick_target_yaw = move_toward(_kick_target_yaw, 0.0, rec_rate * delta * 1.2)
	kick_pitch = Util.damp(kick_pitch, _kick_target_pitch, 30.0, delta)
	kick_yaw = Util.damp(kick_yaw, _kick_target_yaw, 30.0, delta)
	if absf(kick_pitch) < 0.00005 and _kick_target_pitch <= 0.0:
		kick_pitch = 0.0
		kick_yaw = 0.0


func _update_scope(delta: float) -> void:
	var scoped: bool = bool(_def.get("scope", false)) and aim_t > 0.92 and not is_reloading and _now >= _equip_end
	scope_active = scoped
	if scoped:
		# breath sway; holding breath steadies it for ~3.5 s, then you gasp
		if _breath_hold and _breath > 0.0 and _exhaust <= 0.0:
			_breath = maxf(_breath - delta / 3.5, 0.0)
			if _breath <= 0.0:
				_exhaust = 1.6
		else:
			_breath = minf(_breath + delta / 6.0, 1.0)
		_exhaust = maxf(_exhaust - delta, 0.0)
		var steady := 0.12 if (_breath_hold and _exhaust <= 0.0 and _breath > 0.0) else (1.7 if _exhaust > 0.0 else 1.0)
		var moving := 1.0 + character.get_speed_xz() * 0.35
		var amp := 0.0021 * steady * moving
		scope_sway = Vector2(
			(sin(_now * 1.7) * 0.6 + sin(_now * 0.63 + 1.3) * 0.4) * amp,
			(cos(_now * 1.31) * 0.6 + sin(_now * 0.9 + 0.4) * 0.4) * amp)
	else:
		scope_sway = scope_sway.lerp(Vector2.ZERO, 1.0 - exp(-12.0 * delta))
	# zoom -> camera FOV override (player only)
	if character.is_player():
		var zoom := get_zoom_factor()
		if zoom >= 1.55 and aim_t > 0.02 and not character.is_in_vehicle():
			var cam = Game.gameplay_camera
			if cam != null and is_instance_valid(cam) and cam.has_method("set_fov_override"):
				var base := float(Game.settings.get("fov", 75.0)) * 0.8
				var z := lerpf(1.0, zoom, aim_t)
				cam.set_fov_override(rad_to_deg(2.0 * atan(tan(deg_to_rad(base) * 0.5) / z)))
				_fov_overridden = true
		elif _fov_overridden:
			_release_fov()


func _release_fov() -> void:
	if _fov_overridden:
		var cam = Game.gameplay_camera
		if cam != null and is_instance_valid(cam) and cam.has_method("clear_fov_override"):
			cam.clear_fov_override()
		_fov_overridden = false


## Current ADS zoom (1 = none): weapon zoom x scope mod, sniper has two levels.
func get_zoom_factor() -> float:
	if _def.is_empty():
		return 1.0
	if _def.get("scope", false):
		return float(_def["scope_zoom2"]) if _zoom_level == 1 and float(_def["scope_zoom2"]) > 0.0 else float(_def["aim_zoom"])
	return float(_eff.get("zoom", 1.0))


## FOV (degrees) for a camera with base_fov while this weapon is aimed.
func get_aim_fov(base_fov: float) -> float:
	var z := lerpf(1.0, get_zoom_factor(), aim_t)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / z))


func _update_aim_target(delta: float) -> void:
	if not character.is_player() or _def.is_empty():
		return
	_aim_scan -= delta
	if _aim_scan > 0.0:
		return
	_aim_scan = 0.12
	if _is_melee() or _now - _aim_stamp > 0.4:
		aim_target = null
		return
	var space := character.get_world_3d().direct_space_state
	var from := _aim_origin
	var q := PhysicsRayQueryParameters3D.create(from, from + _aim_dir * 90.0, GC.M_BULLET)
	_fill_exclusions()
	q.exclude = _excl
	var hit := space.intersect_ray(q)
	aim_target = Ballistics.resolve_damageable(hit["collider"]) if not hit.is_empty() else null


func _update_flashlight() -> void:
	if _model == null or not _model.has_flashlight():
		return
	var dark := Game.is_night() or Game.daylight() < 0.3
	var on := flashlight_on or (flashlight_auto and dark and aim_t > 0.5)
	_model.set_flashlight(on and not character.is_dead)


# ================================================================================================= firing
func _can_act() -> bool:
	if character == null or character.is_dead:
		return false
	if _now < _equip_end:
		return false
	if _now < _melee_busy_until:
		return false
	if character.is_in_vehicle() and not bool(_def.get("vehicle_ok", false)):
		return false
	return true


func _mag() -> int:
	return int(_entry()["mag"])


func _try_primary() -> bool:
	if _def.is_empty() or _is_melee() or _is_thrown() or not _can_act():
		return false
	if _now < _next_shot:
		return false
	if _mag() <= 0:
		_dry_fire()
		return false
	if is_reloading:
		if _is_shell_reload():
			_cancel_reload()
		else:
			return false
	var mode: StringName = _fire_mode
	_do_shot()
	if mode == &"burst":
		_burst_left = int(_def["burst_count"]) - 1
		_burst_next = _now + 1.0 / float(_def["burst_rate"])
	return true


func _update_fire() -> void:
	if _def.is_empty() or _is_melee() or _is_thrown():
		_auto_reload_check()
		return
	if _trigger and _fire_mode == &"auto" and _can_act():
		var guard := 0
		while _now >= _next_shot and guard < 3:
			guard += 1
			if _mag() <= 0:
				_dry_fire()
				break
			if is_reloading:
				if _is_shell_reload():
					_cancel_reload()
				else:
					break
			_do_shot()
	if _burst_left > 0:
		if not _can_act() or _mag() <= 0:
			_burst_left = 0
		elif _now >= _burst_next:
			_do_shot(true)
			_burst_left -= 1
			_burst_next = _now + 1.0 / float(_def["burst_rate"])
			if _burst_left <= 0:
				_next_shot = maxf(_next_shot, _now + float(_def["burst_pause"]))
	if _semi_buffer_until > _now and _now >= _next_shot and _fire_mode != &"auto":
		_semi_buffer_until = 0.0
		_try_primary()
	if _cycle_sfx_at >= 0.0 and _now >= _cycle_sfx_at:
		_cycle_sfx_at = -1.0
		Sfx.play_3d(&"reload_end", _muzzle_pos(), -4.0, 1.1, 25.0)
		if _cycle_eject:
			_cycle_eject = false
			_eject_shell()
	_auto_reload_check()


func _auto_reload_check() -> void:
	if _auto_reload_at >= 0.0 and _now >= _auto_reload_at:
		_auto_reload_at = -1.0
		if auto_reload and _uses_mag() and _mag() <= 0 and not is_reloading and not _trigger:
			start_reload()


func _dry_fire() -> void:
	if _now - _dry_t > 0.32:
		_dry_t = _now
		Sfx.play_3d(&"dry_fire", _muzzle_pos(), -3.0, 1.0, 25.0)
		empty_clicked.emit(current_id)
		if auto_reload and int(_entry()["reserve"]) > 0 and not is_reloading:
			start_reload()
		elif _infinite_ammo():
			start_reload()


func _fill_exclusions() -> void:
	_excl.clear()
	_excl.append(character.get_rid())
	var v = character.get("current_vehicle")
	if v != null and is_instance_valid(v) and v is CollisionObject3D:
		_excl.append((v as CollisionObject3D).get_rid())


## Fires one round / one volley: ammo, hitscan or projectile, recoil, FX, sound, events.
func _do_shot(in_burst: bool = false) -> void:
	var entry := _entry()
	if not _infinite_ammo():
		entry["mag"] = int(entry["mag"]) - 1
	var interval := 1.0 / maxf(float(_def["fire_rate"]), 0.05)
	if not in_burst:
		var base := _now if (_now - _next_shot) > _dt * 1.5 else _next_shot
		_next_shot = base + interval
	_last_shot_time = _now
	var muzzle := _muzzle_pos()
	var fwd := _shot_direction(muzzle)
	var projectile: StringName = _def.get("projectile", &"")
	if projectile != &"":
		_launch_projectile(projectile, muzzle, fwd)
	else:
		_fire_hitscan(muzzle, fwd)
	# ---- feedback ----------------------------------------------------------------------------
	if _model != null:
		_model.flash(float(_eff["flash_mult"]))
		_model.kick(1.0 if float(_def["recoil"]) < 3.0 else 1.5)
	var mode: StringName = _def["mode"]
	if mode == &"pump" or mode == &"bolt":
		if _model != null:
			_model.cycle_action(interval * 0.7)
		_cycle_sfx_at = _now + interval * 0.38
		_cycle_eject = true
	else:
		_eject_shell()
	var loud := float(_eff["noise"])
	_noise_last = loud
	var pitch := randf_range(0.96, 1.04)
	Sfx.play_3d(_eff["sfx"], muzzle, -5.0 if _eff["suppressed"] else 0.0, pitch, clampf(loud * 2.6, 70.0, 420.0))
	Events.gunshot.emit(muzzle, loud, character)
	Events.weapon_fired.emit(character, current_id)
	fired.emit(current_id)
	_apply_recoil()
	_bloom = minf(_bloom + float(_def["bloom"]), float(_def["bloom_max"]))
	_bloom_hold = 0.12
	_emit_ammo(current_id)
	if int(entry["mag"]) <= 0 and int(entry["reserve"]) > 0 and auto_reload:
		_auto_reload_at = _now + AUTO_RELOAD_DELAY + (0.0 if mode != &"semi" else 0.15)
	_wake()


## Direction from the muzzle converging on the aim-ray target, with wall-clipping protection.
func _shot_direction(muzzle: Vector3) -> Vector3:
	var space := character.get_world_3d().direct_space_state
	var rng_m: float = minf(float(_eff["range"]), 250.0)
	var a_dir := _get_aim_dir()
	var a_org := _aim_origin if _now - _aim_stamp < 0.4 else character.get_eye_position()
	var eye := character.get_eye_position()
	var along := maxf((eye - a_org).dot(a_dir), 0.0)
	var start := a_org + a_dir * along
	_fill_exclusions()
	var q := PhysicsRayQueryParameters3D.create(start, start + a_dir * rng_m, GC.M_BULLET)
	q.exclude = _excl
	var hit := space.intersect_ray(q)
	var target: Vector3 = hit["position"] if not hit.is_empty() else start + a_dir * 90.0
	_aim_hit_target = target
	var d := target - muzzle
	if d.length() < 1.6 or d.normalized().dot(a_dir) < 0.55:
		return a_dir
	return d.normalized()


var _aim_hit_target := Vector3.ZERO


func _fire_hitscan(muzzle: Vector3, dir_in: Vector3) -> void:
	var space := character.get_world_3d().direct_space_state
	var fx := CombatSystem.get_fx()
	# the muzzle may be poking through a wall: start from the wall surface instead
	var from := muzzle
	var eye := character.get_eye_position()
	var cq := PhysicsRayQueryParameters3D.create(eye, muzzle, GC.L_WORLD | GC.L_PROP | GC.L_VEHICLE)
	_fill_exclusions()
	cq.exclude = _excl
	var cblock := space.intersect_ray(cq)
	if not cblock.is_empty():
		from = (cblock["position"] as Vector3) + (cblock["normal"] as Vector3) * 0.03
	var spread := current_spread
	var pellets := int(_def["pellets"])
	var pspread := float(_def["pellet_spread"])
	var p := _bparams
	p["shooter"] = character
	p["weapon"] = current_id
	p["range"] = _eff["range"]
	p["falloff_start"] = float(_def["falloff_start"]) * float(_eff["range_mult"])
	p["falloff_min"] = float(_def["falloff_min"])
	p["penetration"] = int(_def["penetration"])
	p["impulse"] = float(_def["impulse"]) / sqrt(float(pellets))
	p["damage"] = _eff["damage"]
	_budget[0] = 3
	var base_dir := _cone(dir_in, spread)
	var any_char_hit := false
	var any_kill := false
	var head_hit := false
	var total_damage := 0.0
	var tr_every := int(_def["tracer_every"])
	_tracer_n += 1
	var vis_from := muzzle
	for i in pellets:
		var pdir := _cone(base_dir, pspread) if pellets > 1 else base_dir
		var res := Ballistics.shoot(space, from, pdir, p)
		var end: Vector3 = res["pos"]
		if fx != null and (tr_every > 0 and (_tracer_n % tr_every == 0) and (i < 3 or pellets == 1)):
			fx.tracer(vis_from, end, _tracer_col, 0.02 if pellets == 1 else 0.012, 420.0, 4.5 if pellets == 1 else 3.0)
		if res["damaged"]:
			last_target = res["target"]
			total_damage += float(res["damage"])
			if res["character"]:
				any_char_hit = true
				if res["zone"] == GC.ZONE_HEAD:
					head_hit = true
			if res["killed"]:
				any_kill = true
			hit_confirmed.emit({"target": res["target"], "killed": res["killed"], "zone": res["zone"], "damage": res["damage"],
				"weapon": current_id, "headshot": res["zone"] == GC.ZONE_HEAD})
	if character.is_player() and total_damage > 0.0:
		Events.hit_marker.emit(any_kill)
		if head_hit:
			Sfx.play_2d(&"hit_headshot", -4.0, 1.0)
		elif any_char_hit:
			Sfx.play_2d(&"hit_flesh", -10.0, 1.0)


func _launch_projectile(kind: StringName, muzzle: Vector3, dir_in: Vector3) -> void:
	var cs := CombatSystem.get_instance()
	if cs == null:
		return
	var dir := _cone(dir_in, current_spread * 0.4)
	var speed := float(_def["proj_speed"])
	var vel := dir * speed
	if kind == &"grenade_launcher":
		vel += Vector3.UP * 1.5
	cs.spawn_projectile(kind, _def, muzzle + dir * 0.3, vel, character)
	if _model != null and kind == &"rocket":
		_model.flash(0.6)


func _eject_shell() -> void:
	var fx := CombatSystem.get_fx()
	var kind: StringName = _def.get("shell", &"")
	if fx == null or kind == &"" or kind == &"revolver" or _model == null or not _model.is_inside_tree():
		return
	if _eff["suppressed"] and false:
		return
	var right := _model.right_world()
	var fwd := _model.forward_world()
	var vel := right * randf_range(1.6, 2.8) + Vector3.UP * randf_range(1.2, 2.2) - fwd * randf_range(0.0, 0.6)
	fx.eject_shell(_model.eject_world(), vel, kind, character.global_position.y)


func _apply_recoil() -> void:
	var rp := deg_to_rad(float(_def["recoil"])) * float(_eff["recoil_mult"]) * randf_range(0.85, 1.15)
	var ry := deg_to_rad(float(_def["recoil_yaw"])) * float(_eff["recoil_mult"]) * randf_range(-1.0, 1.0)
	var skill_recoil := _player_skill_mod(&"recoil")       # Systems-A hook: shooting skill
	rp *= skill_recoil
	ry *= skill_recoil
	if aim_t > 0.5:
		rp *= 0.8
	if crouched:
		rp *= 0.85
	var maxk := deg_to_rad(float(_def["recoil_max"]))
	_kick_target_pitch = minf(_kick_target_pitch + rp, maxk)
	_kick_target_yaw = clampf(_kick_target_yaw + ry, -maxk * 0.5, maxk * 0.5)
	_recoil_hold = 0.07 + 0.03 * float(_def["recoil"]) * 0.2
	recoil_kick.emit(rp, ry)
	if character.is_player():
		var cam = Game.gameplay_camera
		if cam != null and is_instance_valid(cam):
			if cam.has_method("add_recoil"):
				cam.add_recoil(rp * RECOIL_CAM_SCALE, ry * RECOIL_CAM_SCALE)
			if cam.has_method("add_shake"):
				var heavy := float(_def["recoil"])
				if heavy >= 3.0:
					cam.add_shake(clampf(heavy * 0.05, 0.1, 0.4), 0.18)


static func _cone(dir: Vector3, half_angle_deg: float) -> Vector3:
	if half_angle_deg <= 0.001:
		return dir
	var a := deg_to_rad(half_angle_deg) * sqrt(randf())
	var phi := randf() * TAU
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var upv := right.cross(dir)
	return (dir * cos(a) + (right * cos(phi) + upv * sin(phi)) * sin(a)).normalized()


# ================================================================================================= reload
func _is_shell_reload() -> bool:
	return _reload_style == &"shell"


func start_reload() -> void:
	if is_reloading or _def.is_empty() or not _uses_mag() or character == null or character.is_dead:
		return
	var entry := _entry()
	var cap := int(_eff.get("mag_cap", int(_def["mag_size"])))
	var unlimited := _infinite_ammo()
	if int(entry["mag"]) >= cap or (int(entry["reserve"]) <= 0 and not unlimited):
		return
	if _now < _equip_end:
		_reload_queued = true
		return
	if _now < _melee_busy_until:
		return
	is_reloading = true
	_reload_style = _def["reload_style"]
	_reload_start = _now
	_reload_dur = float(_def["reload_time"]) * _player_skill_mod(&"reload_time")       # Systems-A hook: shooting skill
	if _eff.get("mag_cap", 0) != _def["mag_size"]:
		_reload_dur *= 1.08
	_reload_sfx_done = false
	_burst_left = 0
	_auto_reload_at = -1.0
	reload_progress = 0.0
	if _is_shell_reload():
		_shell_next = _now + _reload_dur
		_reload_end = _now + _reload_dur
	else:
		_reload_end = _now + _reload_dur + (0.0 if int(entry["mag"]) > 0 else 0.2)
	var rig := _rig()
	if rig != null and rig.has_method("play_action"):
		rig.play_action(&"reload")
	if _model != null:
		_model.set_reload_progress(0.0)
	Sfx.play_3d(&"reload_start", _muzzle_pos(), -2.0, 1.0, 30.0)
	reload_started.emit(current_id, _reload_end - _now)
	_wake()


func _update_reload() -> void:
	if not is_reloading:
		if _reload_queued and _now >= _equip_end:
			_reload_queued = false
			start_reload()
		return
	var entry := _entry()
	var cap := int(_eff.get("mag_cap", int(_def["mag_size"])))
	if _is_shell_reload():
		if _now >= _shell_next:
			if int(entry["mag"]) < cap and (int(entry["reserve"]) > 0 or _infinite_ammo()):
				entry["mag"] = int(entry["mag"]) + 1
				if not _infinite_ammo():
					entry["reserve"] = int(entry["reserve"]) - 1
				Sfx.play_3d(&"reload_start", _muzzle_pos(), -8.0, 1.5, 20.0)
				_emit_ammo(current_id)
				_shell_next = _now + float(_def["shell_time"])
			else:
				_finish_reload()
				return
		var total := float(cap - int(entry["mag"]))
		reload_progress = 1.0 - clampf(total / maxf(float(cap), 1.0), 0.0, 1.0)
		if _model != null:
			_model.set_reload_progress(0.5)
	else:
		var u := clampf((_now - _reload_start) / maxf(_reload_end - _reload_start, 0.01), 0.0, 1.0)
		reload_progress = u
		if _model != null:
			_model.set_reload_progress(u)
		if u >= 0.78 and not _reload_sfx_done:
			_reload_sfx_done = true
			Sfx.play_3d(&"reload_end", _muzzle_pos(), -2.0, 1.0, 30.0)
		if _now >= _reload_end:
			var need := cap - int(entry["mag"])
			if _infinite_ammo():
				entry["mag"] = cap
			else:
				var take := mini(need, int(entry["reserve"]))
				entry["mag"] = int(entry["mag"]) + take
				entry["reserve"] = int(entry["reserve"]) - take
			_finish_reload()


func _finish_reload() -> void:
	is_reloading = false
	reload_progress = 0.0
	if _model != null:
		_model.set_reload_progress(-1.0)
		if _is_shell_reload():
			_model.cycle_action(0.3)
			Sfx.play_3d(&"reload_end", _muzzle_pos(), -3.0, 1.1, 25.0)
	_emit_ammo(current_id)
	reloaded.emit(current_id)


func _cancel_reload() -> void:
	is_reloading = false
	reload_progress = 0.0
	if _model != null:
		_model.set_reload_progress(-1.0)


# ================================================================================================= melee
## Light or heavy melee attack with the equipped melee weapon (guns and thrown items fall back to fists / pistol-whip).
func melee_attack(heavy: bool = false) -> void:
	_start_melee(heavy)


func _start_melee(heavy: bool) -> bool:
	if character == null or character.is_dead or character.is_in_vehicle():
		return false
	if _now < _melee_busy_until:
		# small input buffer so rapid presses chain
		if _melee_busy_until - _now < 0.18:
			_melee_buffer = 1 if heavy else 0
		return false
	var d: Dictionary = _def if _is_melee() else WeaponDefs.get_def(FISTS)
	_melee_def = d
	_melee_weapon = current_id if _is_melee() else FISTS
	if is_reloading:
		_cancel_reload()
	_burst_left = 0
	_melee_heavy = heavy
	if _now - _last_melee < 0.95 and not heavy and bool(d.get("combo", false)):
		_combo += 1
		if _combo > 3:
			_combo = 1
	else:
		_combo = 1
	_last_melee = _now
	var rate := float(d["fire_rate"])
	var dur := 1.0 / maxf(rate, 0.1)
	if heavy:
		dur *= 1.65
	_melee_busy_until = _now + dur
	_melee_pending = true
	_melee_hit_time = _now + float(d["hit_delay"]) * (1.7 if heavy else 1.0)
	var anim: StringName = &"melee_swing"
	if _melee_weapon == FISTS:
		anim = &"kick" if (_combo == 3 or heavy) else &"punch"
	var rig := _rig()
	if rig != null and rig.has_method("play_action"):
		rig.play_action(anim)
	Sfx.play_3d(&"melee_swing", character.global_position + Vector3(0, 1.2, 0), -3.0, randf_range(0.9, 1.15) * (0.85 if heavy else 1.0), 30.0)
	_wake()
	return true


func _update_melee() -> void:
	if _melee_pending and _now >= _melee_hit_time:
		_melee_pending = false
		_resolve_melee()
	if _melee_buffer >= 0 and _now >= _melee_busy_until:
		var h := _melee_buffer == 1
		_melee_buffer = -1
		_start_melee(h)


func _resolve_melee() -> void:
	var fwd := _get_aim_dir()
	fwd = Vector3(fwd.x, 0.0, fwd.z)
	if fwd.length_squared() < 0.01:
		fwd = -character.global_transform.basis.z
	var knockdown := _melee_weapon == FISTS and (_combo == 3 or _melee_heavy)
	var res := MeleeResolver.strike(character, _melee_def, {
		"heavy": _melee_heavy, "combo": _combo, "weapon": _melee_weapon, "forward": fwd,
		"max_targets": 2 if (_melee_heavy and _melee_weapon != FISTS) else 1,
		"damage_mult": (1.0 if _melee_weapon != FISTS or _combo != 3 else 1.5) * _player_skill_mod(&"melee_damage"),       # Systems-A hook: strength skill
		"knockdown": knockdown,
	})
	if res["any"]:
		var snd: StringName = &"punch" if _melee_weapon == FISTS else &"melee_hit"
		Sfx.play_3d(snd, character.global_position + fwd * 1.2 + Vector3(0, 1.2, 0), 0.0, randf_range(0.92, 1.08), 40.0)
		if character.is_player():
			Events.hit_marker.emit(res["killed"])
			CombatUtil.shake_camera(0.08 if not _melee_heavy else 0.16, 0.12)
		for h in res["hits"]:
			last_target = h["target"]
			melee_hit.emit(h)
		_noise_last = 25.0
	else:
		_noise_last = 8.0


# ================================================================================================= grenades
## Quick throw of a grenade (G). Works with any weapon equipped as long as you own grenades.
func throw_grenade() -> void:
	throw_grenade_now()


func throw_grenade_now() -> bool:
	if begin_grenade_cook():
		release_grenade()
		return true
	return false


func _grenade_count() -> int:
	if not inventory.has(&"grenade"):
		return 0
	var e: Dictionary = inventory[&"grenade"]
	return int(e["mag"]) + int(e["reserve"])


func begin_grenade_cook() -> bool:
	if character == null or character.is_dead or character.is_in_vehicle():
		return false
	if _cook_t0 >= 0.0 or _throw_pending or _now < _next_throw or _now < _melee_busy_until:
		return false
	if _grenade_count() <= 0 and not _infinite_ammo():
		return false
	if is_reloading:
		_cancel_reload()
	_cook_t0 = _now
	_wake()
	return true


## Releases a cooking grenade (throws it after the short wind-up).
func release_grenade() -> void:
	if _cook_t0 < 0.0:
		return
	_throw_cooked = _now - _cook_t0
	_cook_t0 = -1.0
	_throw_pending = true
	_throw_at = _now + 0.22
	var rig := _rig()
	if rig != null and rig.has_method("play_action"):
		rig.play_action(&"throw")
	Sfx.play_3d(&"melee_swing", character.global_position + Vector3(0, 1.3, 0), -2.0, 1.2, 25.0)
	_wake()


func _update_throw() -> void:
	if _cook_t0 >= 0.0:
		# overcooked in the hand
		var gdef := WeaponDefs.get_def(&"grenade")
		if _now - _cook_t0 >= float(gdef["fuse"]) - 0.05:
			_cook_t0 = _now - float(gdef["fuse"]) + 0.05
			release_grenade()
	if _throw_pending and _now >= _throw_at:
		_throw_pending = false
		_do_throw()


func _hand_pos() -> Vector3:
	var s := _hand_socket()
	if s != null:
		return s.global_position
	return character.global_position + Vector3(0, 1.4, 0) - character.global_transform.basis.z * 0.45 + character.global_transform.basis.x * 0.2


func _do_throw() -> void:
	var cs := CombatSystem.get_instance()
	if cs == null:
		return
	var gdef := WeaponDefs.get_def(&"grenade")
	var origin := _hand_pos()
	var space := character.get_world_3d().direct_space_state
	var a_dir := _get_aim_dir()
	var a_org := _aim_origin if _now - _aim_stamp < 0.4 else character.get_eye_position()
	_fill_exclusions()
	var q := PhysicsRayQueryParameters3D.create(a_org, a_org + a_dir * 40.0, GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP | GC.L_NPC)
	q.exclude = _excl
	var hit := space.intersect_ray(q)
	var target: Vector3 = hit["position"] if not hit.is_empty() else a_org + a_dir * 14.0
	if Vector3(target.x - origin.x, 0.0, target.z - origin.z).length() < 3.0:
		target = origin + Vector3(a_dir.x, 0.0, a_dir.z).normalized() * 3.0
	var vel := Projectile.lob_velocity(origin, target, 38.0, float(gdef["proj_speed"]) + 8.0)
	var fuse := maxf(float(gdef["fuse"]) - _throw_cooked, 0.0)
	var g := cs.spawn_projectile(&"grenade", gdef, origin, vel, character, {"fuse": fuse})
	grenade_thrown.emit(g)
	_next_throw = _now + 1.0 / float(gdef["fire_rate"])
	if not _infinite_ammo() and inventory.has(&"grenade"):
		var e: Dictionary = inventory[&"grenade"]
		var total := int(e["mag"]) + int(e["reserve"]) - 1
		e["mag"] = mini(total, 1)
		e["reserve"] = maxi(total - int(e["mag"]), 0)
		_emit_ammo(&"grenade")
		if total <= 0 and current_id == &"grenade":
			remove_weapon(&"grenade")
	Events.weapon_fired.emit(character, &"grenade")
	_last_shot_time = _now
	_noise_last = 40.0


## Preview points of the grenade arc toward the current aim target (for aim UIs).
func get_throw_preview() -> PackedVector3Array:
	if character == null:
		return PackedVector3Array()
	var gdef := WeaponDefs.get_def(&"grenade")
	var origin := _hand_pos()
	var a_dir := _get_aim_dir()
	var a_org := _aim_origin if _now - _aim_stamp < 0.4 else character.get_eye_position()
	var space := character.get_world_3d().direct_space_state
	_fill_exclusions()
	var q := PhysicsRayQueryParameters3D.create(a_org, a_org + a_dir * 40.0, GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP | GC.L_NPC)
	q.exclude = _excl
	var hit := space.intersect_ray(q)
	var target: Vector3 = hit["position"] if not hit.is_empty() else a_org + a_dir * 14.0
	var vel := Projectile.lob_velocity(origin, target, 38.0, float(gdef["proj_speed"]) + 8.0)
	return Projectile.trace_arc(character.get_world_3d(), origin, vel)


# ================================================================================================= queries
func get_current_def() -> Dictionary:
	return _def


func get_ammo_in_mag() -> int:
	return int(_entry()["mag"])


func get_ammo_reserve() -> int:
	return int(_entry()["reserve"])


## Magazine capacity of the equipped weapon including mods.
func get_mag_capacity() -> int:
	return int(_eff.get("mag_cap", int(_def.get("mag_size", 0))))


## True when the equipped weapon is usable from a vehicle seat (pistol, SMG, one-handed...).
func can_fire_from_vehicle() -> bool:
	return bool(_def.get("vehicle_ok", false))


## Loudness (audible radius, m) of the last shot (or of the equipped weapon's next shot); suppressors reduce it.
func get_noise_radius() -> float:
	return _noise_last


func is_armed() -> bool:
	return current_id != FISTS


func is_firearm_equipped() -> bool:
	return not _is_melee() and not _is_thrown()


func get_model() -> WeaponModel:
	return _model


## Support-hand target (Grip_L marker of the weapon model) for rigs that do two-handed IK, or null.
func get_support_grip() -> Node3D:
	return _model.grip_l if _model != null else null


func get_muzzle_position() -> Vector3:
	return _muzzle_pos()


## Effective numbers for the equipped weapon after mods (damage, range, noise, zoom, mag_cap, suppressed ...).
func get_effective() -> Dictionary:
	return _eff


# ================================================================================================= mods / tint
func has_mod(weapon_id: StringName, mod_id: StringName) -> bool:
	return inventory.has(weapon_id) and bool((inventory[weapon_id]["mods"] as Dictionary).get(mod_id, false))


## Installs / removes a mod (no payment: the shop charges WeaponMods.price()). Returns false if incompatible / not owned.
func set_mod(weapon_id: StringName, mod_id: StringName, installed: bool = true) -> bool:
	if not inventory.has(weapon_id) or not WeaponMods.is_compatible(weapon_id, mod_id):
		return false
	var entry: Dictionary = inventory[weapon_id]
	var mods: Dictionary = entry["mods"]
	if installed:
		mods[mod_id] = true
	else:
		mods.erase(mod_id)
	# magazine capacity changed: clamp the loaded rounds / reserve to the new caps
	var d := WeaponDefs.get_def(weapon_id)
	if int(d["mag_size"]) > 0:
		entry["mag"] = mini(int(entry["mag"]), WeaponDefs.mag_capacity(weapon_id, mods))
		entry["reserve"] = mini(int(entry["reserve"]), WeaponDefs.reserve_capacity(weapon_id, mods))
	if weapon_id == current_id:
		_apply_def()
		if _model != null:
			_model.set_mods(mods)
	mods_changed.emit(weapon_id)
	_emit_ammo(weapon_id)
	return true


func set_tint(weapon_id: StringName, color: Color) -> void:
	if not inventory.has(weapon_id):
		return
	inventory[weapon_id]["tint"] = color
	if weapon_id == current_id and _model != null:
		_model.set_tint(color)
	mods_changed.emit(weapon_id)


# ================================================================================================= events / save
func _emit_ammo(id: StringName) -> void:
	var e: Dictionary = inventory.get(id, {})
	var mag := int(e.get("mag", 0))
	var res := int(e.get("reserve", 0))
	ammo_changed.emit(id, mag, res)
	if character != null and character.is_player():
		Events.ammo_changed.emit(character, id, mag, res)


func serialize() -> Dictionary:
	var inv := {}
	for id in inventory:
		var e: Dictionary = inventory[id]
		var mods := {}
		for m in (e["mods"] as Dictionary):
			mods[String(m)] = bool(e["mods"][m])
		var t: Color = e.get("tint", Color(0, 0, 0, 0))
		inv[String(id)] = {"mag": int(e["mag"]), "reserve": int(e["reserve"]), "mods": mods, "tint": t.to_html(true)}
	return {"current": String(current_id), "inventory": inv}


func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		return
	var inv: Dictionary = data.get("inventory", {})
	inventory.clear()
	inventory[FISTS] = {"mag": 0, "reserve": 0, "mods": {}, "tint": Color(0, 0, 0, 0)}
	for k in inv:
		var id := StringName(String(k))
		if not WeaponDefs.has(id):
			continue
		var e: Dictionary = inv[k]
		var mods := {}
		var src: Dictionary = e.get("mods", {})
		for m in src:
			if bool(src[m]):
				mods[StringName(String(m))] = true
		var tint_v = e.get("tint", "")
		var tint := Color(0, 0, 0, 0)
		if tint_v is Color:
			tint = tint_v
		elif tint_v is String and String(tint_v) != "":
			tint = Color(String(tint_v))
		inventory[id] = {"mag": int(e.get("mag", 0)), "reserve": int(e.get("reserve", 0)), "mods": mods, "tint": tint}
	_order_dirty = true
	var cur := StringName(String(data.get("current", "fists")))
	if not inventory.has(cur):
		cur = FISTS
	_equip_internal(cur, false)
	for id in inventory:
		_emit_ammo(id)


## Systems-A hook: SkillsSystem multiplier for the PLAYER only (shooting -> recoil / spread / reload_time, strength -> melee_damage); 1.0 for NPCs or without skills.
func _player_skill_mod(modifier: StringName) -> float:
	if character == null or not character.is_player():
		return 1.0
	var sk = Game.sys(&"skills")
	if sk != null and sk.has_method("get_modifier"):
		return float(sk.get_modifier(modifier))
	return 1.0
