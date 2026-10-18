class_name LampManager
extends Node3D
## Street-lamp lighting for the whole city with a tiny budget.
##  - World-Content places lamps as Node3D in group `street_lamp` (meta `lamp_height`, optional `lamp_offset`: Vector3,
##    `lamp_color`: Color, `lamp_energy`: float multiplier).
##  - Only the POOL_SIZE nearest lamps get a real SpotLight3D (re-assigned every 0.5 s with hysteresis; lights fade
##    in/out by distance so re-assignment never pops). Lamps fade on across dusk (per-lamp threshold) and rarely flicker.
##  - Up to HALO_MAX lamps within HALO_RADIUS get a cheap additive billboard halo (one MultiMesh draw call).
##  - Everything is asleep (zero per-frame work beyond a bool test) while `on_amount` is ~0 (daytime).
## EnvironmentSystem drives `on_amount` (night, or storm gloom) every frame.

const GROUP := &"street_lamp"
const POOL_SIZE := 28
const HALO_MAX := 200
const LIGHT_RADIUS := 95.0
const HALO_RADIUS := 150.0
const CELL := 40.0
const HALO_SHADER := "res://gta/generated/vfx/lamp_halo.gdshader"
const DEFAULT_HEIGHT := 6.0

var on_amount := 0.0                       # 0..1 (set by EnvironmentSystem)
var enabled := true
var pool_size := POOL_SIZE                 # active lights (quality setting), <= POOL_SIZE
var base_energy := 7.5
var base_color := Color(1.0, 0.77, 0.48)
var flicker_chance := 0.0015               # per light per 0.5 s tick

var _cam_getter: Callable
var _lights: Array[SpotLight3D] = []
var _slot_lamp := PackedInt32Array()        # lamp index, -1 free, -2 releasing
var _slot_energy := PackedFloat32Array()
var _slot_base := PackedFloat32Array()      # distance-faded base energy for this tick
var _slot_thr := PackedFloat32Array()
var _slot_flicker := PackedFloat32Array()
var _lamp_pos := PackedVector3Array()
var _lamp_hash := PackedFloat32Array()
var _lamp_color: Array[Color] = []
var _lamp_mult := PackedFloat32Array()
var _lamp_nodes: Array = []
var _grid: Dictionary = {}
var _group_count := -1
var _dirty := true
var _scan_timer := 0.0
var _assign_timer := 0.0
var _rng := RandomNumberGenerator.new()

var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var _halo_mat: ShaderMaterial
var _halo_count := 0
var _active_lights := 0


func setup(cam_getter: Callable) -> void:
	_cam_getter = cam_getter
	name = "LampManager"
	top_level = true
	_rng.randomize()
	_slot_lamp.resize(POOL_SIZE)
	_slot_energy.resize(POOL_SIZE)
	_slot_base.resize(POOL_SIZE)
	_slot_thr.resize(POOL_SIZE)
	_slot_flicker.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var l := SpotLight3D.new()
		l.name = "LampLight%d" % i
		l.spot_angle = 78.0
		l.spot_angle_attenuation = 1.0
		l.spot_range = 26.0
		l.light_energy = 0.0
		l.light_color = base_color
		l.light_specular = 0.55
		l.shadow_enabled = false
		l.visible = false
		l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		add_child(l)
		_lights.append(l)
		_slot_lamp[i] = -1
	# halos
	var sh := load(HALO_SHADER) as Shader
	if sh != null:
		_halo_mat = ShaderMaterial.new()
		_halo_mat.shader = sh
		_mm = MultiMesh.new()
		_mm.transform_format = MultiMesh.TRANSFORM_3D
		_mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		_mm.mesh = q
		_mm.instance_count = HALO_MAX
		_mm.visible_instance_count = 0
		_mmi = MultiMeshInstance3D.new()
		_mmi.name = "LampHalos"
		_mmi.multimesh = _mm
		_mmi.material_override = _halo_mat
		_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mmi.custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 300, 2000))
		_mmi.top_level = true
		_mmi.visible = false
		add_child(_mmi)
	else:
		push_warning("LampManager: lamp_halo.gdshader missing - lamp halos disabled")
	set_process(true)


## Call after lamps were added/removed in bulk (it also auto-detects count changes every 2 s).
func invalidate() -> void:
	_dirty = true
	_scan_timer = 0.0


func get_stats() -> Dictionary:
	return {"lamps": _lamp_pos.size(), "lights_active": _active_lights, "halos": _halo_count, "on_amount": on_amount}


func _process(delta: float) -> void:
	if not enabled:
		_sleep()
		return
	var awake := on_amount > 0.01 or _active_lights > 0
	if not awake:
		if _mmi != null and _mmi.visible:
			_mmi.visible = false
			_halo_count = 0
		return
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 2.0
		_scan()
	_assign_timer -= delta
	if _assign_timer <= 0.0:
		_assign_timer = 0.5
		_assign()
	_update_slots(delta)
	if _halo_mat != null:
		_halo_mat.set_shader_parameter("on_amount", on_amount)


func _sleep() -> void:
	if _active_lights == 0 and (_mmi == null or not _mmi.visible):
		return
	for i in POOL_SIZE:
		_lights[i].visible = false
		_slot_lamp[i] = -1
		_slot_energy[i] = 0.0
	_active_lights = 0
	_halo_count = 0
	if _mmi != null:
		_mmi.visible = false


# ---- Lamp registry ---------------------------------------------------------------------------------------
func _scan() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var nodes := tree.get_nodes_in_group(GROUP)
	if nodes.size() == _group_count and not _dirty:
		return
	_dirty = false
	_group_count = nodes.size()
	# keep slot->lamp links valid: free everything, the next assign tick re-acquires
	for i in POOL_SIZE:
		if _slot_lamp[i] != -1:
			_slot_lamp[i] = -2
	_lamp_pos = PackedVector3Array()
	_lamp_hash = PackedFloat32Array()
	_lamp_mult = PackedFloat32Array()
	_lamp_color.clear()
	_lamp_nodes.clear()
	_grid.clear()
	for n in nodes:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node3d := n as Node3D
		var h: float = float(node3d.get_meta("lamp_height", DEFAULT_HEIGHT))
		var off: Vector3 = node3d.get_meta("lamp_offset", Vector3.ZERO)
		var pos := node3d.global_position + node3d.global_transform.basis * off + Vector3(0.0, h, 0.0)
		var idx := _lamp_pos.size()
		_lamp_pos.append(pos)
		var hs := fposmod(sin(pos.x * 12.9898 + pos.z * 78.233) * 43758.5453, 1.0)
		_lamp_hash.append(hs)
		var lc = node3d.get_meta("lamp_color", base_color)
		_lamp_color.append(lc if lc is Color else base_color)
		_lamp_mult.append(float(node3d.get_meta("lamp_energy", 1.0)))
		_lamp_nodes.append(node3d)
		var key := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		var arr: PackedInt32Array = _grid[key]
		arr.append(idx)
		_grid[key] = arr


# ---- Per-tick assignment ----------------------------------------------------------------------------------
func _assign() -> void:
	var cam = _cam_getter.call() if _cam_getter.is_valid() else null
	if cam == null or _lamp_pos.is_empty():
		return
	var cp: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_transform.basis.z
	var held := {}
	for s in POOL_SIZE:
		if _slot_lamp[s] >= 0:
			held[_slot_lamp[s]] = s
	var cands: Array = []
	var r := HALO_RADIUS
	var cx0 := floori((cp.x - r) / CELL)
	var cx1 := floori((cp.x + r) / CELL)
	var cz0 := floori((cp.z - r) / CELL)
	var cz1 := floori((cp.z + r) / CELL)
	var r2 := r * r
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var key := Vector2i(cx, cz)
			if not _grid.has(key):
				continue
			for idx in (_grid[key] as PackedInt32Array):
				var p := _lamp_pos[idx]
				var dv := p - cp
				var d2 := dv.x * dv.x + dv.z * dv.z + dv.y * dv.y * 0.25
				if d2 > r2:
					continue
				var d := sqrt(d2)
				var score := d
				if d > 22.0 and dv.dot(fwd) < -0.3 * d:
					score = d * 1.5
				if held.has(idx):
					score *= 0.8
				cands.append(Vector3(score, float(idx), d))
	cands.sort()

	# lights: nearest pool_size lamps within LIGHT_RADIUS that are visible in the tree
	var want := {}
	var want_dist := {}
	var count := 0
	for c in cands:
		if count >= mini(pool_size, POOL_SIZE):
			break
		var idx := int(c.y)
		if c.z > LIGHT_RADIUS:
			continue
		var node = _lamp_nodes[idx]
		if not is_instance_valid(node) or not (node as Node3D).is_visible_in_tree():
			continue
		want[idx] = true
		want_dist[idx] = c.z
		count += 1
	# release slots whose lamp is no longer wanted
	for s in POOL_SIZE:
		var li := _slot_lamp[s]
		if li >= 0 and not want.has(li):
			_slot_lamp[s] = -2
	# distance-fade bookkeeping for the ones we keep
	for s in POOL_SIZE:
		var li := _slot_lamp[s]
		if li >= 0:
			_slot_base[s] = _fade_energy(li, float(want_dist.get(li, LIGHT_RADIUS)))
			if _rng.randf() < flicker_chance + (0.02 if _lamp_hash[li] > 0.97 else 0.0) and _slot_flicker[s] <= 0.0:
				_slot_flicker[s] = _rng.randf_range(0.3, 1.1)
			held.erase(li)
			want.erase(li)
	# assign free slots to new lamps
	var free_slot := 0
	for li in want:
		while free_slot < POOL_SIZE and _slot_lamp[free_slot] != -1:
			free_slot += 1
		if free_slot >= POOL_SIZE:
			break
		var l := _lights[free_slot]
		l.global_position = _lamp_pos[li]
		l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		l.light_color = _lamp_color[li]
		_slot_lamp[free_slot] = li
		_slot_energy[free_slot] = 0.0
		_slot_thr[free_slot] = 0.10 + _lamp_hash[li] * 0.45
		_slot_base[free_slot] = _fade_energy(li, float(want_dist.get(li, LIGHT_RADIUS)))
		_slot_flicker[free_slot] = 0.0
		free_slot += 1

	# halos
	if _mm != null:
		var n := 0
		for c in cands:
			if n >= HALO_MAX:
				break
			var idx2 := int(c.y)
			var node2 = _lamp_nodes[idx2]
			if not is_instance_valid(node2) or not (node2 as Node3D).is_visible_in_tree():
				continue
			var sz := 2.1 + _lamp_hash[idx2] * 0.4
			_mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3(sz, sz, sz)), _lamp_pos[idx2]))
			_mm.set_instance_custom_data(n, Color(0.05 + _lamp_hash[idx2] * 0.50, 0.0, 0.0, 0.0))
			n += 1
		_mm.visible_instance_count = n
		_halo_count = n
		_mmi.visible = n > 0


func _fade_energy(lamp: int, dist: float) -> float:
	return base_energy * _lamp_mult[lamp] * (1.0 - smoothstep(LIGHT_RADIUS * 0.62, LIGHT_RADIUS, dist))


func _update_slots(delta: float) -> void:
	var k := 1.0 - exp(-6.0 * delta)
	var active := 0
	var t := Time.get_ticks_msec() * 0.001
	for s in POOL_SIZE:
		var li := _slot_lamp[s]
		var target := 0.0
		if li >= 0:
			target = _slot_base[s] * smoothstep(_slot_thr[s], _slot_thr[s] + 0.25, on_amount)
			if _slot_flicker[s] > 0.0:
				_slot_flicker[s] -= delta
				var ph := int(t * 31.0 + float(s) * 7.0)
				target *= 0.12 if (ph % 3 == 0 or ph % 7 == 0) else 0.85
		var e := _slot_energy[s]
		e += (target - e) * k
		if li == -2 and e < 0.02:
			_slot_lamp[s] = -1
			e = 0.0
		_slot_energy[s] = e
		var light := _lights[s]
		if e > 0.01:
			light.light_energy = e
			light.visible = true
			active += 1
		elif light.visible:
			light.visible = false
	_active_lights = active
