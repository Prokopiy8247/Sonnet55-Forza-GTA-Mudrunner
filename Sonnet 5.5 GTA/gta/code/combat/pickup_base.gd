class_name PickupBase
extends Area3D
## Walk-over pickup (group "pickup"): floating, spinning, bobbing model + ground ring. The player collects it by touching
## the trigger. Subclasses (WeaponPickup, AmmoPickup, HealthPickup, ArmorPickup, CashPickup) implement apply().
## CombatSystem animates all pickups near the player from one loop (no per-pickup _process).

signal collected(by: Node)

const PICKUP_RADIUS := 1.35

var kind: StringName = &"generic"
var amount: int = 0
var respawn_time := 0.0              # > 0: world pickup that comes back after N seconds; 0: removed when collected
var lifetime := 0.0                  # > 0: dropped pickup that vanishes after N seconds
var bob_height := 0.72
var spin_speed := 1.7
var glow_color := Color(1.0, 0.85, 0.4)
var visual: Node3D = null
var active := true
var born_msec := 0

var _ring: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null
var _t_off := 0.0
var _respawn_at := 0
var _overlap_poll := 0.0
var _fallback := false


func _init() -> void:
	add_to_group(GC.G_PICKUP)
	collision_layer = GC.L_TRIGGER
	collision_mask = GC.L_PLAYER
	monitoring = true
	monitorable = false


func _ready() -> void:
	born_msec = Time.get_ticks_msec()
	_t_off = randf() * 10.0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = PICKUP_RADIUS
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	visual = Node3D.new()
	visual.name = "Visual"
	visual.position = Vector3(0, bob_height, 0)
	add_child(visual)
	var model := _make_model()
	if model != null:
		visual.add_child(model)
	_ring = MeshInstance3D.new()
	_ring.mesh = FxRes.ground_quad()
	_ring_mat = FxRes.ring_mat()
	_ring_mat.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.55)
	_ring.material_override = _ring_mat
	_ring.position = Vector3(0, 0.06, 0)
	_ring.scale = Vector3(1.5, 1.0, 1.5)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	body_entered.connect(_on_body_entered)


# ---- overridables -----------------------------------------------------------------------------
## Model for the floating visual. Default: props/pickup_<kind>.glb else a code-built fallback.
func _make_model() -> Node3D:
	var rel := "props/pickup_" + String(kind)
	if ModelLib.exists(rel):
		var m := ModelLib.instance(rel)
		if m != null:
			return m
	_fallback = true
	return _fallback_model()


func _fallback_model() -> Node3D:
	var r := Node3D.new()
	r.name = "FallbackPickup"
	r.set_meta(&"fallback", true)
	WeaponModel._part(r, "box", Vector3(0.3, 0.2, 0.2), Vector3.ZERO, "accent")
	return r


## Apply the pickup to the character. Return false when it cannot be used now (stay in the world).
func apply(_character: Node) -> bool:
	return true


func get_label() -> String:
	return String(kind).capitalize()


# ---- collection ---------------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	try_collect(body)


func try_collect(body: Node) -> bool:
	if not active or body == null or not body.is_in_group(GC.G_PLAYER):
		return false
	if not apply(body):
		return false
	_collected(body)
	return true


func _collected(by: Node) -> void:
	Events.pickup_collected.emit(kind, amount)
	var label := get_label()
	if label != "":
		Events.notification.emit(label, &"good")
	if kind == &"cash":
		Sfx.play_ui(&"ui_cash")
	else:
		Sfx.play_3d(&"pickup", global_position, 0.0, 1.0, 30.0)
	var fx := CombatSystem.get_fx()
	if fx != null:
		fx.ring(global_position, 1.0, Color(glow_color.r, glow_color.g, glow_color.b, 0.9), 0.4)
	collected.emit(by)
	if respawn_time > 0.0:
		set_active(false)
		_respawn_at = Time.get_ticks_msec() + int(respawn_time * 1000.0)
	else:
		queue_free()


func set_active(on: bool) -> void:
	active = on
	visible = on
	set_deferred("monitoring", on)


## Called by CombatSystem for pickups near the player.
func animate(t: float, delta: float) -> void:
	if not active:
		if _respawn_at > 0 and Time.get_ticks_msec() >= _respawn_at:
			_respawn_at = 0
			set_active(true)
		return
	if visual != null:
		visual.rotation.y += spin_speed * delta
		visual.position.y = bob_height + sin((t + _t_off) * 2.3) * 0.09
	if _ring_mat != null:
		var pulse := 0.5 + 0.5 * sin((t + _t_off) * 2.0)
		_ring.scale = Vector3(1.35 + pulse * 0.25, 1.0, 1.35 + pulse * 0.25)
		_ring_mat.albedo_color.a = 0.35 + 0.3 * pulse
	_overlap_poll -= delta
	if _overlap_poll <= 0.0:
		_overlap_poll = 0.45
		for b in get_overlapping_bodies():
			if try_collect(b):
				return
	if lifetime > 0.0:
		var left := lifetime - float(Time.get_ticks_msec() - born_msec) * 0.001
		if left < 8.0 and visual != null:
			visual.visible = int(left * 5.0) % 2 == 0
		if left <= 0.0:
			queue_free()


## Cheap age test used by the CombatSystem sweep for pickups far from the player.
func is_expired() -> bool:
	return lifetime > 0.0 and float(Time.get_ticks_msec() - born_msec) * 0.001 >= lifetime
