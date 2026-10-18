class_name PlayerInteraction
extends Node
## Scans for interactables (group `interactable`) and enterable vehicles near the player, publishes the prompt through
## Events.interaction_prompt and executes the `interact` (E) / `enter_exit` (F) actions.
##
## Interactable contract (docs/ARCHITECTURE.md section 8): get_interaction(player) -> {"text","key","enabled"} and interact(player).
## Optional per-node range override: property/meta `interact_range` (m).

const SCAN_INTERVAL := 0.1

var player: Player = null
var current_interactable: Node = null
var current_info: Dictionary = {}
var nearest_vehicle: Node = null
var prompt_text := ""

var _timer := 0.0
var _last_emitted := "\u0001"
var _aabb_cache: Dictionary = {}     # instance_id -> AABB


func setup(p: Player) -> void:
	player = p


func clear_prompt() -> void:
	current_interactable = null
	nearest_vehicle = null
	current_info = {}
	prompt_text = ""
	_emit_prompt("")


func update(dt: float) -> void:
	if player == null:
		return
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = SCAN_INTERVAL
	if player.is_dead or player.is_busy_for_interaction() or player.input_locked:
		clear_prompt()
		return
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("is_menu_open") and ui.is_menu_open():
		clear_prompt()
		return
	if player.is_in_vehicle():
		current_interactable = null
		nearest_vehicle = null
		prompt_text = ""
		_emit_prompt("")
		return
	_scan_interactables()
	_scan_vehicles()
	var lines: Array[String] = []
	if current_interactable != null:
		var key: String = str(current_info.get("key", "E"))
		lines.append("[%s] %s" % [key, str(current_info.get("text", "Interact"))])
	if nearest_vehicle != null:
		lines.append(_vehicle_prompt(nearest_vehicle))
	if player.takedown_target != null and is_instance_valid(player.takedown_target) and lines.is_empty():
		var kn: bool = player.weapons != null and player.weapons.current_id == &"knife"
		lines.append("[X] Silent kill (hold: knock out)" if kn else "[X] Knock out (hold: kill)")
	prompt_text = "     ".join(lines)          # one line: the HUD shows the first [KEY] as the key cap
	_emit_prompt(prompt_text)


func _emit_prompt(text: String) -> void:
	if text == _last_emitted:
		return
	_last_emitted = text
	Events.interaction_prompt.emit(text)


# ---- Interactables -------------------------------------------------------------------------------------------------
func _scan_interactables() -> void:
	current_interactable = null
	current_info = {}
	var ppos: Vector3 = player.global_position
	var fwd: Vector3 = -player.global_transform.basis.z
	if is_instance_valid(player.camera) and player.aiming:
		fwd = Util.flat(player.camera.get_aim_forward()).normalized()
	var best_score := INF
	for n in get_tree().get_nodes_in_group(GC.G_INTERACT):
		if not (n is Node3D) or not (n as Node3D).is_visible_in_tree():
			continue
		var node := n as Node3D
		var rng := INTERACT_RANGE_DEFAULT
		var r = node.get("interact_range")
		if r == null and node.has_meta(&"interact_range"):
			r = node.get_meta(&"interact_range")
		if r != null:
			rng = float(r)
		var to := node.global_position - ppos
		if absf(to.y) > 2.6:
			continue
		to.y = 0.0
		var d := to.length()
		if d > rng:
			continue
		var dot := 1.0
		if d > 0.9:
			dot = fwd.dot(to / d)
			if dot < -0.25:
				continue
		var score := d - dot * 0.8
		if score < best_score:
			var info := _get_info(node)
			if info.is_empty():
				continue
			best_score = score
			current_interactable = node
			current_info = info


const INTERACT_RANGE_DEFAULT := 2.5


func _get_info(node: Node) -> Dictionary:
	if node.has_method("get_interaction"):
		var d = node.get_interaction(player)
		if d is Dictionary:
			return d
		return {}
	var txt: String = str(node.get_meta(&"interaction_text", node.name))
	return {"text": txt, "key": "E", "enabled": true}


func try_interact() -> bool:
	if player == null or player.is_dead or player.is_in_vehicle():
		return false
	if current_interactable == null or not is_instance_valid(current_interactable):
		return false
	if not bool(current_info.get("enabled", true)):
		Sfx.play_ui(&"ui_error")
		return false
	if current_interactable.has_method("interact"):
		current_interactable.interact(player)
		_timer = 0.0      # refresh the prompt next frame (state may have changed)
		return true
	return false


# ---- Vehicles -------------------------------------------------------------------------------------------------------
func _scan_vehicles() -> void:
	nearest_vehicle = null
	if player._vehicle_enter_cd > 0.0 or (player.move_mode != Player.Move.GROUND and player.move_mode != Player.Move.AIR):
		return
	var ppos: Vector3 = player.global_position
	var best := VEHICLE_RANGE
	for v in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if not (v is Node3D):
			continue
		var vn := v as Node3D
		if vn.get("is_destroyed") == true:
			continue
		if vn.global_position.distance_squared_to(ppos) > 400.0:
			continue
		if vn.has_method("can_be_entered_by") and not vn.can_be_entered_by(player):
			continue
		var d := _distance_to_vehicle(vn, ppos)
		if d < best:
			best = d
			nearest_vehicle = vn


const VEHICLE_RANGE := 3.2


## Distance from `pos` to the vehicle's body box (or its entry point, whichever is closer).
func _distance_to_vehicle(v: Node3D, pos: Vector3) -> float:
	var id := v.get_instance_id()
	if not _aabb_cache.has(id):
		var body := v.find_child("Body", true, false)
		var root: Node3D = body if body is Node3D else v
		var bb := AABB()
		if root is MeshInstance3D or not ModelLib.meshes(root).is_empty():
			bb = Util.local_aabb(root)
			if root != v:
				# express in the vehicle's local space
				var xf := v.global_transform.affine_inverse() * root.global_transform if v.is_inside_tree() and root.is_inside_tree() else Transform3D.IDENTITY
				bb = xf * bb
		if bb.size.length_squared() < 0.5:
			bb = AABB(Vector3(-0.9, 0.0, -2.1), Vector3(1.8, 1.5, 4.2))      # fallback car-sized box
		_aabb_cache[id] = bb
	var bb2: AABB = _aabb_cache[id]
	var local := v.to_local(pos)
	var clamped := local.clamp(bb2.position, bb2.end)
	var d := (local - clamped).length()
	if v.has_method("get_entry_position"):
		var ep: Vector3 = v.get_entry_position(0)
		d = minf(d, Util.dist_xz(ep, pos) - 0.4) if ep.distance_squared_to(v.global_position) > 0.01 else d
	return maxf(d, 0.0)


func _vehicle_prompt(v: Node) -> String:
	if v.has_method("get_interaction"):
		var d = v.get_interaction(player)
		if d is Dictionary and str(d.get("text", "")) != "":
			return "[%s] %s" % [str(d.get("key", "F")), str(d["text"])]
	var nm: String = str(v.get("display_name") if v.get("display_name") != null else "Vehicle")
	var vclass = v.get("vclass")
	var drv = v.get("driver")
	if drv != null and is_instance_valid(drv) and drv != player:
		return "[F] Carjack %s" % nm
	if vclass == GC.VC_BIKE or vclass == GC.VC_BICYCLE:
		return "[F] Ride %s" % nm
	if vclass == GC.VC_BOAT:
		return "[F] Board %s" % nm
	if vclass == GC.VC_HELI or vclass == GC.VC_PLANE:
		return "[F] Fly %s" % nm
	return "[F] Enter %s" % nm


## F key: enter the nearest vehicle / leave the current one.
func try_enter_exit() -> bool:
	if player == null or player.is_dead:
		return false
	if player.is_in_vehicle():
		var v = player.current_vehicle
		if v != null and v.has_method("exit"):
			v.exit(player, false)
			return true
		return false
	if player.is_busy_for_interaction():
		return false
	# make sure the candidate is fresh
	_scan_vehicles()
	if nearest_vehicle == null or not is_instance_valid(nearest_vehicle):
		return false
	var veh := nearest_vehicle
	player._vehicle_enter_cd = 0.5
	if player.cover != null:
		player.cover.leave(true)
	if player.is_swimming:
		return false
	var ok: bool = player.enter_vehicle(veh, 0)          # F always means 'take the wheel' (an occupied driver seat = carjack)
	if not ok:
		ok = player.enter_vehicle(veh, -1)
	if ok and player.rig != null and veh.get("driver") == null:
		player.rig.play_action(&"enter_vehicle")
	clear_prompt()
	return ok
