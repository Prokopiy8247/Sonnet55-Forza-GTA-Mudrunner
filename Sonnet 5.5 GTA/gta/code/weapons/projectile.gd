class_name Projectile
extends Node3D
## Rockets, launcher grenades and thrown grenades. Swept ray movement (no tunnelling), grenade bounce, fuse timers,
## smoke trails (pooled emitters) and detonation through CombatSystem.explode().
##   kind: &"rocket" (straight, accelerating, explodes on impact), &"grenade_launcher" (lobbed, explodes on a direct hit on a
##   character / vehicle, bounces off the world, fuse), &"grenade" (thrown, bounces, fuse; can be cooked).

const MASK := GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP | GC.L_NPC | GC.L_PLAYER | GC.L_ANIMAL | GC.L_RAGDOLL

static var _query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
static var _bounce_cool := 0.0
static var _no_excl: Array[RID] = []

var kind: StringName = &"grenade"
var velocity := Vector3.ZERO
var source: Node = null
var weapon_id: StringName = &"grenade"
var blast_radius := 7.0
var blast_damage := 200.0
var blast_force := 14.0
var speed_target := 60.0
var fuse := 3.0
var age := 0.0
var gravity := 9.8
var restitution := 0.42
var friction := 0.72
var exploded := false

var _resting := false
var _smoke: CPUParticles3D = null
var _fire: CPUParticles3D = null
var _light: OmniLight3D = null
var _spin := Vector3.ZERO
var _excl: Array[RID] = []
var _visual: Node3D = null
var _blink := 0.0
var _blink_mat: StandardMaterial3D = null


## Builds a projectile (not yet in the tree). def is the WeaponDefs entry of the firing weapon.
static func create(p_kind: StringName, def: Dictionary, origin: Vector3, vel: Vector3, p_source: Node, opts: Dictionary = {}) -> Projectile:
	var p := Projectile.new()
	p.name = "Projectile_" + String(p_kind)
	p.kind = p_kind
	p.weapon_id = def.get("id", &"grenade")
	p.blast_radius = float(def.get("blast_radius", 7.0))
	p.blast_damage = float(def.get("blast_damage", 200.0))
	p.blast_force = float(def.get("blast_force", 14.0))
	p.speed_target = float(def.get("proj_speed", 40.0))
	p.fuse = float(opts.get("fuse", def.get("fuse", 3.0)))
	p.velocity = vel
	p.source = p_source
	p.position = origin
	if p_kind == &"rocket":
		p.gravity = 0.4
	elif p_kind == &"grenade_launcher":
		p.restitution = 0.3
		p.friction = 0.6
	if p_source is CollisionObject3D:
		p._excl.append((p_source as CollisionObject3D).get_rid())
	var sv = p_source.get("current_vehicle") if p_source != null else null
	if sv is CollisionObject3D:
		p._excl.append((sv as CollisionObject3D).get_rid())
	return p


## Velocity of a 35 deg lob that lands on `target` (clamped to vmax). Used for grenade throws and the preview arc.
static func lob_velocity(origin: Vector3, target: Vector3, theta_deg: float = 35.0, vmax: float = 24.0, g: float = 9.8) -> Vector3:
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var d := flat.length()
	if d < 0.5:
		return Vector3.UP * 4.0
	var th := deg_to_rad(theta_deg)
	var h := target.y - origin.y
	# v^2 = g d^2 / (2 cos^2(th) (d tan(th) - h))
	var denom := 2.0 * cos(th) * cos(th) * (d * tan(th) - h)
	var v := vmax
	if denom > 0.01:
		v = minf(sqrt(g * d * d / denom), vmax)
	v = maxf(v, 4.0)
	var dir := flat / d
	return (dir * cos(th) + Vector3.UP * sin(th)) * v


## Samples the arc of a thrown grenade (for aim previews). Returns world points; stops at the first collision.
static func trace_arc(world: World3D, origin: Vector3, vel: Vector3, steps: int = 36, dt: float = 0.06, g: float = 9.8) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var space := world.direct_space_state
	var p := origin
	var v := vel
	pts.append(p)
	for i in steps:
		v.y -= g * dt
		var np := p + v * dt
		_query.from = p
		_query.to = np
		_query.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP
		_query.exclude = _no_excl
		var hit := space.intersect_ray(_query)
		if not hit.is_empty():
			pts.append(hit["position"])
			break
		pts.append(np)
		p = np
	return pts


func _ready() -> void:
	set_physics_process(true)
	_build_visual()
	var fx := CombatSystem.get_fx()
	if kind == &"rocket":
		if fx != null:
			_smoke = fx.acquire_emitter("trail_smoke")
			_fire = fx.acquire_emitter("trail_fire")
			for e in [_smoke, _fire]:
				if e != null:
					e.global_position = global_position
					e.emitting = true
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.65, 0.3)
		_light.light_energy = 2.2
		_light.omni_range = 8.0
		_light.shadow_enabled = false
		add_child(_light)
	_spin = Vector3(randf_range(-9, 9), randf_range(-4, 4), randf_range(-9, 9)) if kind != &"rocket" else Vector3.ZERO
	if velocity.length_squared() > 0.01 and kind == &"rocket":
		look_at(global_position + velocity, Vector3.UP)


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var rel := "weapons/rocket" if kind == &"rocket" else "weapons/grenade"
	if ModelLib.exists(rel):
		var m := ModelLib.instance(rel)
		if m != null:
			if kind == &"grenade_launcher":
				m.scale = Vector3.ONE * 0.75
			_visual.add_child(m)
			return
	if not WeaponModel._warned.has(StringName("proj_" + String(kind))):
		WeaponModel._warned[StringName("proj_" + String(kind))] = true
		push_warning("Projectile: FALLBACK code-built shape for '%s' (missing %s)" % [kind, ModelLib.path(rel)])
	if kind == &"rocket":
		WeaponModel._tube(_visual, 0.05, 0.55, Vector3(0, 0, 0), "olive")
		WeaponModel._part(_visual, "cone", Vector3(0.05, 0.14, 0.0), Vector3(0, 0, -0.34), "accent", Vector3(-90, 0, 0))
		for i in 4:
			var a := TAU * float(i) / 4.0
			WeaponModel._part(_visual, "box", Vector3(0.012, 0.09, 0.1), Vector3(cos(a) * 0.055, sin(a) * 0.055, 0.22), "dark", Vector3(0, 0, rad_to_deg(a) + 90.0))
	else:
		var s := 0.034 if kind == &"grenade" else 0.026
		WeaponModel._part(_visual, "sphere", Vector3(s, 0, 0), Vector3.ZERO, "olive")
		WeaponModel._part(_visual, "box", Vector3(s * 0.4, s * 0.5, s * 1.4), Vector3(0, s * 1.05, 0), "metal")
		var blink := WeaponModel._part(_visual, "sphere", Vector3(0.007, 0, 0), Vector3(0, s * 1.15, -s * 0.4), "accent")
		_blink_mat = blink.material_override as StandardMaterial3D


func _physics_process(delta: float) -> void:
	if exploded:
		return
	age += delta
	if age >= fuse:
		_detonate(global_position, Vector3.UP)
		return
	if _blink_mat != null:
		_blink += delta * (3.0 + age * 4.0)
		_blink_mat.emission_energy_multiplier = 0.2 + 2.0 * maxf(sin(_blink * 6.0), 0.0)
	if _resting:
		return
	var prev := global_position
	if kind == &"rocket":
		var spd := velocity.length()
		if spd < speed_target:
			velocity = velocity.normalized() * minf(speed_target, spd + 150.0 * delta)
		velocity.y -= gravity * delta
	else:
		velocity.y -= gravity * delta
	var nxt := prev + velocity * delta
	_query.from = prev
	_query.to = nxt
	_query.collision_mask = MASK
	_query.exclude = _excl if (age < 0.35 or kind == &"rocket") else _no_excl
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		global_position = nxt
	else:
		var hp: Vector3 = hit["position"]
		var hn: Vector3 = hit["normal"]
		if kind == &"rocket":
			_detonate(hp + hn * 0.15, hn)
			return
		var dmgb := Ballistics.resolve_damageable(hit["collider"])
		if kind == &"grenade_launcher" and dmgb != null:
			_detonate(hp + hn * 0.1, hn)
			return
		_bounce(hp, hn, delta)
	_orient(delta)
	if _smoke != null:
		var back := -velocity.normalized() * 0.45
		_smoke.global_position = global_position + back
		_fire.global_position = global_position + back * 0.8


func _bounce(hp: Vector3, hn: Vector3, delta: float) -> void:
	var vn := velocity.dot(hn)
	var impact_speed := absf(vn)
	var tangential := velocity - hn * vn
	velocity = tangential * friction + hn * (-vn * restitution)
	global_position = hp + hn * 0.05
	if impact_speed > 2.5:
		var t := Time.get_ticks_msec() * 0.001
		if t - _bounce_cool > 0.08:
			_bounce_cool = t
			Sfx.play_3d(&"grenade_bounce", hp, -3.0, randf_range(0.9, 1.1), 40.0)
		_spin = Vector3(randf_range(-8, 8), randf_range(-3, 3), randf_range(-8, 8))
	if velocity.length() < 1.3 and hn.y > 0.55:
		velocity = Vector3.ZERO
		_resting = true
		_spin = Vector3.ZERO


func _orient(delta: float) -> void:
	if kind == &"rocket":
		if velocity.length_squared() > 1.0:
			var d := velocity.normalized()
			var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT
			global_transform = Transform3D(Basis.looking_at(d, up), global_position)
	else:
		rotate_x(_spin.x * delta)
		rotate_y(_spin.y * delta)
		rotate_z(_spin.z * delta)


func _detonate(pos: Vector3, _normal: Vector3) -> void:
	if exploded:
		return
	exploded = true
	var fx := CombatSystem.get_fx()
	if fx != null:
		fx.release_emitter(_smoke)
		fx.release_emitter(_fire)
	var src: Node = source if is_instance_valid(source) else null
	var cs := CombatSystem.get_instance()
	if cs != null:
		cs.explode(pos, blast_radius, blast_damage, src, {"weapon": weapon_id, "force": blast_force})
	else:
		Explosion.detonate(self, pos, blast_radius, blast_damage, src, {"weapon": weapon_id, "force": blast_force})
	queue_free()


## Detonates right now (e.g. cooked grenade in the hand).
func detonate_now() -> void:
	_detonate(global_position, Vector3.UP)
