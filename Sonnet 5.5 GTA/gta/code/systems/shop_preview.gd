class_name ShopPreview
extends SubViewportContainer
## Small self-contained 3D stage for the shop menus (own World3D, transparent background): a rotating weapon on a pedestal
## (WeaponModel with mods + tint) or a rotating character (CharacterRig, e.g. the player's outfit). Runs while the tree is
## paused (menus pause the game) because it lives under a MenuBase (PROCESS_MODE_ALWAYS).
##
##   var pv := ShopPreview.new(Vector2i(520, 360));  parent.add_child(pv)
##   pv.show_weapon(&"pistol", {&"suppressor": true}, Color("#a3262e"))      pv.show_rig(variant, &"body" | &"head")

var viewport: SubViewport
var stage: Node3D                  # turntable (spins around Y)
var cam: Camera3D
var item: Node3D = null
var spin_speed := 0.75
var paused_spin := false
var is_character := false

var _pedestal: Node3D
var _ring_mat: StandardMaterial3D
var _t := 0.0
var _px := Vector2i(520, 360)


func _init(px: Vector2i = Vector2i(520, 360)) -> void:
	_px = px
	stretch = true
	custom_minimum_size = Vector2(px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.size = px
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED       # switched on only while the preview is visible (see _sync_update)
	viewport.gui_disable_input = true
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(viewport)
	_build_stage()


func _build_stage() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.0
	env.set_glow_level(2, 1.0)
	we.environment = env
	viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.84)
	key.light_energy = 1.7
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	viewport.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.24, 0.6)
	rim.light_energy = 2.0
	rim.omni_range = 7.0
	rim.position = Vector3(-1.9, 1.7, -2.2)
	viewport.add_child(rim)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.2, 0.88, 1.0)
	fill.light_energy = 1.3
	fill.omni_range = 7.0
	fill.position = Vector3(2.2, 1.0, 2.0)
	viewport.add_child(fill)
	stage = Node3D.new()
	stage.name = "Turntable"
	viewport.add_child(stage)
	_pedestal = Node3D.new()
	viewport.add_child(_pedestal)
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.6
	cm.height = 0.1
	cm.radial_segments = 24
	cm.rings = 1
	base.mesh = cm
	base.position = Vector3(0, -0.05, 0)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.10, 0.12, 0.16)
	bm.roughness = 0.35
	bm.metallic = 0.5
	base.material_override = bm
	_pedestal.add_child(base)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.5
	tm.outer_radius = 0.56
	tm.rings = 24
	tm.ring_segments = 6
	ring.mesh = tm
	ring.position = Vector3(0, 0.002, 0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color("#34e0ff")
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color("#34e0ff")
	_ring_mat.emission_energy_multiplier = 2.2
	ring.material_override = _ring_mat
	_pedestal.add_child(ring)
	cam = Camera3D.new()
	cam.fov = 28.0
	cam.current = true
	viewport.add_child(cam)
	cam.position = Vector3(0, 0.3, 2.0)


func clear_item() -> void:
	if item != null and is_instance_valid(item):
		item.queue_free()
	item = null


## Weapon on the pedestal, side view, centred on its bounding box.
func show_weapon(id: StringName, mods: Dictionary = {}, tint: Color = Color(0, 0, 0, 0)) -> void:
	clear_item()
	is_character = false
	var wm := WeaponModel.create(id, mods, tint)
	item = Node3D.new()
	item.add_child(wm)
	stage.add_child(item)
	var bb := Util.local_aabb(wm.model_root if wm.model_root != null else wm)     # the real model + fitted parts, not the (hidden) muzzle flash
	var center := bb.get_center()
	wm.position = -center
	# the weapon floats a little above the pedestal
	var half_h := bb.size.y * 0.5
	var radius := maxf(maxf(bb.size.x, bb.size.z) * 0.5, 0.1)
	var ped_scale := clampf(radius * 2.0, 0.35, 1.5)
	_pedestal.scale = Vector3.ONE * ped_scale
	_pedestal.position = Vector3.ZERO
	item.position = Vector3(0, half_h + 0.14 * ped_scale + 0.05, 0)
	# frame the WHOLE composition (pedestal underside .. top of the gun) vertically and the gun length horizontally: compact guns
	# (pistols) are taller than long, long guns are limited by the preview's aspect ratio
	var top_y := item.position.y + half_h
	var bot_y := -0.06 * ped_scale
	var look_y := (top_y + bot_y) * 0.5
	var half_v := (top_y - bot_y) * 0.5
	var aspect := float(_px.x) / maxf(float(_px.y), 1.0)
	var need_half_v := maxf(half_v * 1.25, radius * 1.12 / aspect)
	var dist := need_half_v / tan(deg_to_rad(cam.fov * 0.5)) + radius * 0.6
	cam.position = Vector3(0, look_y + dist * 0.17, dist)
	cam.look_at(Vector3(0, look_y, 0), Vector3.UP)
	stage.rotation.y = -PI * 0.5 + 0.35        # three-quarter view, barrel pointing right
	_pedestal.visible = true
	_ring_mat.albedo_color = Color("#34e0ff")


## Character with the given CharacterRig variant. focus: &"body" (full) or &"head" (barber).
func show_rig(variant: Dictionary, focus: StringName = &"body") -> void:
	clear_item()
	is_character = true
	var rig_script: Script = load("res://gta/code/player/character_rig.gd")
	if rig_script == null or not rig_script.can_instantiate():
		return
	var rig: Node3D = rig_script.new()
	rig.setup(variant)
	if rig.has_method("set_idle_style"):
		rig.set_idle_style(&"relaxed")
	item = rig
	stage.add_child(item)
	item.position = Vector3(0, 0.0, 0)
	_pedestal.scale = Vector3.ONE * 0.85
	_pedestal.position = Vector3.ZERO
	if focus == &"head":
		var hy := 1.62
		cam.position = Vector3(0, hy + 0.05, 1.55)
		cam.look_at(Vector3(0, hy, 0), Vector3.UP)
		_pedestal.visible = false
	else:
		cam.position = Vector3(0, 1.0, 4.3)
		cam.look_at(Vector3(0, 0.92, 0), Vector3.UP)
		_pedestal.visible = true
	_ring_mat.albedo_color = Color("#ff3d9a")


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_EXIT_TREE:
		_sync_update()


## The menus are registered once at boot and stay hidden most of the game: a hidden preview must not render (4 viewports x MSAA 4x every frame).
func _sync_update() -> void:
	if viewport == null:
		return
	var on := is_inside_tree() and is_visible_in_tree()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)


func _process(dt: float) -> void:
	_t += dt
	if not paused_spin and spin_speed != 0.0:
		stage.rotation.y += spin_speed * dt
	if is_character:
		pass


func set_spin(on: bool) -> void:
	paused_spin = not on
