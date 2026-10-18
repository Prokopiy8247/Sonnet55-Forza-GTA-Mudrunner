class_name InteriorRoom
extends Node3D
## One enterable interior (a small closed room, built lazily on first entry by InteriorSystem). Local space: origin = floor centre,
## +Y up, the entrance door is in the SOUTH wall (z = +depth/2) and the player walks in facing north (-Z).
## Provides the shell (floor / walls / ceiling / trim / lights / door) and prop helpers (Blender `interiors/*.glb`, colliders
## from AABBs, wall-aligned placement, use points, signs, windows). Layouts live in InteriorDefs / InteriorSafehouse.
##
## Props from `interiors/*.glb` face -Z with their BACK at +Z (UsePoint empties are 0.9 m in front, at -Z).

const WALL_T := 0.6
const PROP_DIR := "interiors/"

## distance from the model origin to its back plane (local +Z) for wall-mounted / wall-backed props
const BACK := {
	"weapon_rack_wall": 0.05, "shelf_wall": 0.21, "mirror_wall": 0.05, "wardrobe": 0.33, "kitchen_unit": 0.34,
	"tv_stand_tv": 0.24, "sofa": 0.44, "nightstand": 0.23, "bed_double": 1.17, "gun_bench": 0.42, "shop_counter": 0.38,
	"scuba_rack": 0.23, "tool_chest": 0.27, "clothing_rack": 0.3, "barber_chair": 0.63, "table_round": 0.56, "chair": 0.22,
	"mannequin": 0.22, "repair_lift": 2.2, "neon_sign_blank": 0.12,
}

static var _mats: Dictionary = {}

var id: StringName = &""
var display_name := ""
var size := Vector3(8.0, 3.2, 8.0)          # clear inside size: x width, y height, z depth
var theme: Dictionary = {}
var spawn_pos := Vector3.ZERO                # local, just inside the door
var spawn_yaw := 0.0
var exit_door: InteriorDoor = null
var exit_x := 0.0
var clerk = null                             # ShopClerk (duck typed)
var points: Dictionary = {}                  # tag -> InteriorDoor
var props: Array[Node3D] = []
var lights: Array[Light3D] = []
var windows: Array[MeshInstance3D] = []
var signs: Array[Label3D] = []
var fallback_models: Array[String] = []
var info: Dictionary = {}                    # free scratch for the layout / owner system
var build_ms := 0.0
var is_built := false

var _body: StaticBody3D = null


# ================================================================================================= materials
static func mat(c: Color, rough: float = 0.85, metal: float = 0.0, emit: float = 0.0, alpha: float = 1.0, vcol: bool = false) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f|%.2f|%d" % [c.to_html(true), rough, metal, emit, alpha, 1 if vcol else 0]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = emit
	if alpha < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if vcol:
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


# ================================================================================================= shell
## theme keys: floor_a floor_b floor_pattern(&"checker"|&"planks"|&"tiles") tile wall wainscot wainscot_h trim ceiling accent accent2
## light light_energy ambient surface(footstep surface meta)
func build_shell(w: float, d: float, h: float, th: Dictionary) -> void:
	size = Vector3(w, h, d)
	theme = th
	_body = StaticBody3D.new()
	_body.name = "Shell"
	_body.collision_layer = GC.L_WORLD
	_body.collision_mask = 0
	_body.set_meta(&"surface", StringName(th.get("surface", &"concrete")))
	add_child(_body)
	var t := WALL_T
	# collision: floor, ceiling, four walls
	_collider(Vector3(0, -0.5, 0), Vector3(w + 2.0 * t, 1.0, d + 2.0 * t))
	_collider(Vector3(0, h + t * 0.5, 0), Vector3(w + 2.0 * t, t, d + 2.0 * t))
	_collider(Vector3(0, h * 0.5, -d * 0.5 - t * 0.5), Vector3(w + 2.0 * t, h, t))
	_collider(Vector3(0, h * 0.5, d * 0.5 + t * 0.5), Vector3(w + 2.0 * t, h, t))
	_collider(Vector3(-w * 0.5 - t * 0.5, h * 0.5, 0), Vector3(t, h, d))
	_collider(Vector3(w * 0.5 + t * 0.5, h * 0.5, 0), Vector3(t, h, d))
	# visuals
	_build_floor()
	var wall_c: Color = th.get("wall", Color("#d8d2c6"))
	var wain_c: Color = th.get("wainscot", Color("#3c4452"))
	var trim_c: Color = th.get("trim", Color("#222831"))
	var ceil_c: Color = th.get("ceiling", Color("#bdb8ad"))
	var wh: float = float(th.get("wainscot_h", 1.05))
	add_box(Vector3(0, h * 0.5, -d * 0.5 - t * 0.5), Vector3(w + 2.0 * t, h, t), wall_c, 0.9)
	add_box(Vector3(0, h * 0.5, d * 0.5 + t * 0.5), Vector3(w + 2.0 * t, h, t), wall_c, 0.9)
	add_box(Vector3(-w * 0.5 - t * 0.5, h * 0.5, 0), Vector3(t, h, d), wall_c, 0.9)
	add_box(Vector3(w * 0.5 + t * 0.5, h * 0.5, 0), Vector3(t, h, d), wall_c, 0.9)
	add_box(Vector3(0, h + t * 0.5, 0), Vector3(w + 2.0 * t, t, d + 2.0 * t), ceil_c, 0.95)
	if wh > 0.01:
		# wainscot band + chair rail on all four walls
		var rail_c: Color = th.get("accent", Color("#ffb347"))
		for wall in [&"n", &"s", &"w", &"e"]:
			var len := w if (wall == &"n" or wall == &"s") else d
			var p := wall_point(wall, 0.0, wh * 0.5, 0.02)
			var sz := Vector3(len, wh, 0.04) if (wall == &"n" or wall == &"s") else Vector3(0.04, wh, len)
			add_box(p, sz, wain_c, 0.8)
			var pr := wall_point(wall, 0.0, wh + 0.03, 0.035)
			var szr := Vector3(len, 0.05, 0.06) if (wall == &"n" or wall == &"s") else Vector3(0.06, 0.05, len)
			add_box(pr, szr, rail_c, 0.5, 0.0, 0.0)
	# skirting + cornice
	for wall in [&"n", &"s", &"w", &"e"]:
		var len2 := w if (wall == &"n" or wall == &"s") else d
		var ps := wall_point(wall, 0.0, 0.07, 0.04)
		var szs := Vector3(len2, 0.14, 0.08) if (wall == &"n" or wall == &"s") else Vector3(0.08, 0.14, len2)
		add_box(ps, szs, trim_c, 0.7)
		var pc := wall_point(wall, 0.0, h - 0.06, 0.05)
		var szc := Vector3(len2, 0.12, 0.1) if (wall == &"n" or wall == &"s") else Vector3(0.1, 0.12, len2)
		add_box(pc, szc, trim_c, 0.7)
	# neon cove around the ceiling edge
	var neon: Color = th.get("neon", th.get("accent2", Color("#34e0ff")))
	for wall in [&"n", &"s", &"w", &"e"]:
		var len3 := w if (wall == &"n" or wall == &"s") else d
		var pn := wall_point(wall, 0.0, h - 0.17, 0.045)
		var szn := Vector3(len3 - 0.2, 0.035, 0.03) if (wall == &"n" or wall == &"s") else Vector3(0.03, 0.035, len3 - 0.2)
		add_box(pn, szn, neon, 0.4, 0.0, 1.35)
	# ceiling light panels (emissive) + the real lights
	var lc: Color = th.get("light", Color("#ffd9a8"))
	var le: float = float(th.get("light_energy", 1.4))
	var nx := 2 if w > 6.5 else 1
	var nz := 2 if d > 6.5 else 1
	for ix in nx:
		for iz in nz:
			var px := (float(ix) + 0.5) / float(nx) * w - w * 0.5
			var pz := (float(iz) + 0.5) / float(nz) * d - d * 0.5
			add_box(Vector3(px, h - 0.02, pz), Vector3(1.5, 0.04, 0.5), lc.lerp(Color.WHITE, 0.35), 0.5, 0.0, 1.5)
			add_light(Vector3(px, h - 0.45, pz), lc, le, maxf(w, d) * 0.62)
	# sealing slab: block sun / moon from leaking around the shell
	add_box(Vector3(0, h + t + 0.25, 0), Vector3(w + 8.0, 0.5, d + 8.0), Color("#15171a"), 1.0)


func _collider(pos: Vector3, sz: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	cs.position = pos
	_body.add_child(cs)


func _build_floor() -> void:
	var w := size.x
	var d := size.z
	var pattern: StringName = theme.get("floor_pattern", &"checker")
	var tile: float = float(theme.get("tile", 1.0))
	var ca: Color = theme.get("floor_a", Color("#3a3f47"))
	var cb: Color = theme.get("floor_b", Color("#2d3138"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(id) + "floor")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int(ceil(w / tile))
	var nz := int(ceil(d / tile))
	for ix in nx:
		for iz in nz:
			var x0 := -w * 0.5 + float(ix) * tile
			var x1 := minf(x0 + tile, w * 0.5)
			var z0 := -d * 0.5 + float(iz) * tile
			var z1 := minf(z0 + tile, d * 0.5)
			var c: Color
			match pattern:
				&"planks":
					c = ca.lerp(cb, rng.randf()) if iz % 2 == 0 else ca.lerp(cb, rng.randf() * 0.7 + 0.15)
					c = c.darkened(0.03) if (ix % 3 == 0) else c
				&"tiles":
					c = ca if (ix + iz) % 3 != 0 else cb
				_:
					c = ca if (ix + iz) % 2 == 0 else cb
			var j := rng.randf_range(-0.025, 0.025)
			c = Color(clampf(c.r + j, 0.0, 1.0), clampf(c.g + j, 0.0, 1.0), clampf(c.b + j, 0.0, 1.0))
			# thin dark gap on two sides of every tile reads as grout / plank seams
			var g := 0.007
			var a := Vector3(x0 + g, 0.0, z0 + g)
			var b := Vector3(x1 - g, 0.0, z0 + g)
			var cc := Vector3(x1 - g, 0.0, z1 - g)
			var dd := Vector3(x0 + g, 0.0, z1 - g)
			for v in [a, b, cc, a, cc, dd]:
				st.set_normal(Vector3.UP)
				st.set_color(c)
				st.add_vertex(v)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	mi.mesh = mesh
	mi.material_override = mat(Color.WHITE, float(theme.get("floor_rough", 0.55)), float(theme.get("floor_metal", 0.0)), 0.0, 1.0, true)
	# grout colour underneath
	var under := add_box(Vector3(0, -0.06, 0), Vector3(size.x + 0.2, 0.08, size.z + 0.2), Color(theme.get("grout", Color("#15171a"))), 1.0)
	under.name = "FloorBase"
	add_child(mi)


# ================================================================================================= primitives
func add_box(pos: Vector3, sz: Vector3, color: Color, rough: float = 0.85, metal: float = 0.0, emit: float = 0.0, alpha: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat(color, rough, metal, emit, alpha)
	if emit > 0.0 or alpha < 0.99:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## A collidable box (counter, crate...) drawn with a flat colour.
func add_solid(pos: Vector3, sz: Vector3, color: Color, rough: float = 0.8, metal: float = 0.0, emit: float = 0.0) -> MeshInstance3D:
	var mi := add_box(pos, sz, color, rough, metal, emit)
	_collider(pos, sz)
	return mi


func add_cyl(pos: Vector3, radius: float, height: float, color: Color, rough: float = 0.7, metal: float = 0.0, emit: float = 0.0, sides: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat(color, rough, metal, emit)
	add_child(mi)
	return mi


func add_light(pos: Vector3, color: Color, energy: float, range_m: float, shadow: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.15
	l.light_specular = 0.35
	l.shadow_enabled = shadow
	add_child(l)
	lights.append(l)
	return l


## Position on a wall plane. wall: &"n" &"s" &"w" &"e"; `along` = coordinate along the wall (x for n/s, z for w/e); `inset` = distance into the room.
func wall_point(wall: StringName, along: float, y: float, inset: float = 0.0) -> Vector3:
	match wall:
		&"n":
			return Vector3(along, y, -size.z * 0.5 + inset)
		&"s":
			return Vector3(along, y, size.z * 0.5 - inset)
		&"w":
			return Vector3(-size.x * 0.5 + inset, y, along)
		_:
			return Vector3(size.x * 0.5 - inset, y, along)


## Yaw that makes a PROP (front = -Z) face into the room from the given wall.
static func wall_prop_yaw(wall: StringName) -> float:
	match wall:
		&"n":
			return PI
		&"s":
			return 0.0
		&"w":
			return -PI * 0.5
		_:
			return PI * 0.5


## Yaw for a Label3D / sprite (front = +Z) that faces into the room from the given wall.
static func wall_label_yaw(wall: StringName) -> float:
	match wall:
		&"n":
			return 0.0
		&"s":
			return PI
		&"w":
			return PI * 0.5
		_:
			return -PI * 0.5


func add_sign(text: String, pos: Vector3, yaw: float, color: Color, font_size: int = 96, pixel: float = 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel
	l.outline_size = 14
	l.outline_modulate = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 1.0)
	l.modulate = Color(color.r * 1.25, color.g * 1.25, color.b * 1.25, 1.0)
	l.shaded = false
	l.double_sided = false
	l.position = pos
	l.rotation.y = yaw
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	signs.append(l)
	return l


## Window on a wall: dark frame + emissive pane (colour follows the time of day, see refresh_daylight).
func add_window(wall: StringName, along: float, w: float, h: float, sill: float = 0.95) -> MeshInstance3D:
	var yaw_is_x := wall == &"n" or wall == &"s"
	var pane_pos := wall_point(wall, along, sill + h * 0.5, 0.045)
	var pane_sz := Vector3(w, h, 0.03) if yaw_is_x else Vector3(0.03, h, w)
	var pane := add_box(pane_pos, pane_sz, Color("#9fd4ff"), 0.2, 0.0, 1.0)
	windows.append(pane)
	var frame_c: Color = theme.get("trim", Color("#222831"))
	var fp := wall_point(wall, along, sill + h * 0.5, 0.06)
	var bar := 0.06
	if yaw_is_x:
		add_box(fp + Vector3(0, h * 0.5, 0), Vector3(w + 0.12, bar, 0.05), frame_c)
		add_box(fp - Vector3(0, h * 0.5, 0), Vector3(w + 0.12, bar, 0.05), frame_c)
		add_box(fp + Vector3(w * 0.5, 0, 0), Vector3(bar, h, 0.05), frame_c)
		add_box(fp - Vector3(w * 0.5, 0, 0), Vector3(bar, h, 0.05), frame_c)
		add_box(fp, Vector3(bar * 0.6, h, 0.05), frame_c)
	else:
		add_box(fp + Vector3(0, h * 0.5, 0), Vector3(0.05, bar, w + 0.12), frame_c)
		add_box(fp - Vector3(0, h * 0.5, 0), Vector3(0.05, bar, w + 0.12), frame_c)
		add_box(fp + Vector3(0, 0, w * 0.5), Vector3(0.05, h, bar), frame_c)
		add_box(fp - Vector3(0, 0, w * 0.5), Vector3(0.05, h, bar), frame_c)
		add_box(fp, Vector3(0.05, h, bar * 0.6), frame_c)
	return pane


## day01: 0 night .. 1 midday. Called by InteriorSystem on entry.
func refresh_daylight(day01: float) -> void:
	var night_c := Color(0.10, 0.16, 0.36)
	var day_c := Color(0.72, 0.88, 1.0)
	var c := night_c.lerp(day_c, clampf(day01, 0.0, 1.0))
	var e := lerpf(0.55, 1.4, clampf(day01, 0.0, 1.0))
	for p in windows:
		if is_instance_valid(p):
			p.material_override = mat(c, 0.2, 0.0, e)


# ================================================================================================= props
## Instantiates `interiors/<model>.glb` at a local position. Collider = box from the prop AABB (unless collide == false).
func add_prop(model: String, pos: Vector3, yaw: float = 0.0, collide: bool = true) -> Node3D:
	var n: Node3D = null
	if ModelLib.exists(PROP_DIR + model):
		n = ModelLib.instance(PROP_DIR + model)
	if n == null:
		n = _fallback_prop(model)
	n.name = model.capitalize().replace(" ", "")
	n.position = pos
	n.rotation.y = yaw
	_fix_materials(n)
	add_child(n)
	if collide:
		var bb := Util.local_aabb(n)
		if bb.size.length_squared() > 0.01:
			var body := StaticBody3D.new()
			body.name = "Col"
			body.collision_layer = GC.L_WORLD
			body.collision_mask = 0
			body.set_meta(&"surface", &"wood")
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = bb.size * Vector3(0.96, 1.0, 0.96)
			cs.shape = bs
			cs.position = bb.get_center()
			body.add_child(cs)
			n.add_child(body)
	props.append(n)
	return n


## Prop whose back is flush with a wall. `along` = x for n/s walls, z for w/e walls.
func wall_prop(model: String, wall: StringName, along: float, gap: float = 0.02, collide: bool = true, lift: float = 0.0) -> Node3D:
	var back: float = float(BACK.get(model, 0.3))
	var p := wall_point(wall, along, lift, back + gap)
	return add_prop(model, p, wall_prop_yaw(wall), collide)


## The Blender "Mirror" material is near black without a reflection probe: swap it for a bright glossy glass.
func _fix_materials(n: Node3D) -> void:
	var glass := mat(Color(0.78, 0.88, 0.94), 0.08, 0.0, 0.32)
	Util.replace_material(n, "Mirror", glass)


func _fallback_prop(model: String) -> Node3D:
	push_warning("InteriorRoom: FALLBACK box for missing prop '%s%s'" % [PROP_DIR, model])
	fallback_models.append(model)
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.0, 0.6)
	mi.mesh = bm
	mi.position = Vector3(0, 0.5, 0)
	mi.material_override = mat(Color("#ff3d9a"), 0.7)
	n.add_child(mi)
	var l := Label3D.new()
	l.text = "MISSING " + model
	l.position = Vector3(0, 1.2, 0)
	l.pixel_size = 0.006
	n.add_child(l)
	return n


## Position of a named empty (UsePoint ...) of a prop expressed in ROOM-local space.
func prop_point(prop: Node3D, point_name: String, fallback: Vector3 = Vector3(0, 0, -0.9)) -> Vector3:
	var n := prop.find_child(point_name, true, false) as Node3D
	var local := n.position if n != null else fallback
	return prop.transform * local


func add_use(tag: StringName, local_pos: Vector3, text: String, cb: Callable, range_m: float = 2.0) -> InteriorDoor:
	var d := InteriorDoor.new(text, cb)
	d.name = "Use_" + String(tag)
	d.tag = tag
	d.interact_range = range_m
	d.position = local_pos
	add_child(d)
	points[tag] = d
	return d


## Door in the south wall (visual + exit interactable). `x` = centre along the wall.
func set_exit(x: float, label: String = "Exit") -> InteriorDoor:
	exit_x = x
	var h := size.z * 0.5
	var trim_c: Color = theme.get("trim", Color("#222831"))
	var door_c: Color = theme.get("door", Color("#2f9c95"))
	var dw := 1.3
	var dh := 2.25
	var z := h - 0.03
	add_box(Vector3(x, dh * 0.5, z), Vector3(dw, dh, 0.05), door_c, 0.6)
	add_box(Vector3(x, dh + 0.06, z), Vector3(dw + 0.3, 0.12, 0.08), trim_c)
	add_box(Vector3(x - dw * 0.5 - 0.07, dh * 0.5 + 0.06, z), Vector3(0.14, dh + 0.12, 0.08), trim_c)
	add_box(Vector3(x + dw * 0.5 + 0.07, dh * 0.5 + 0.06, z), Vector3(0.14, dh + 0.12, 0.08), trim_c)
	add_box(Vector3(x, 1.45, z - 0.02), Vector3(0.8, 1.15, 0.03), Color("#bfe9ff"), 0.15, 0.0, 0.7)
	add_box(Vector3(x + dw * 0.5 - 0.15, 1.0, z - 0.06), Vector3(0.05, 0.4, 0.05), Color("#d9dde2"), 0.3, 0.8)
	add_sign("EXIT", Vector3(x, dh + 0.32, h - 0.06), PI, Color("#7be495"), 64, 0.0035)
	var d := add_use(&"exit", Vector3(x, 0.0, h - 0.85), label, Callable(), 1.9)
	exit_door = d
	spawn_pos = Vector3(x, 0.08, h - 1.35)
	spawn_yaw = 0.0
	return d


# ================================================================================================= stats
## Triangles of the room itself (shell + props + decoration). The clerk (a character rig) and the weapons / vehicles shown on
## racks and in bays are reported separately by tri_report().
func count_triangles() -> int:
	return int(tri_report()["room"])


func tri_report() -> Dictionary:
	var out := {"room": 0, "clerk": 0, "display": 0}
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var t := (n as MeshInstance3D).mesh.get_faces().size() / 3
			var kind := "room"
			var p: Node = n
			while p != null and p != self:
				if p == clerk:
					kind = "clerk"
					break
				if p.has_meta(&"stat_display"):
					kind = "display"
					break
				p = p.get_parent()
			out[kind] = int(out[kind]) + t
		for c in n.get_children():
			stack.append(c)
	return out


## Triangles of everything that is NOT the bare shell (props + decoration are what the brief budgets).
func count_surfaces() -> int:
	var s := 0
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			s += maxi((n as MeshInstance3D).mesh.get_surface_count(), 1)
		for c in n.get_children():
			stack.append(c)
	return s


## Small display items (guns on a rack, parked cars in the garage) do not need to cast shadows: halves their draw cost.
static func no_shadows(root: Node) -> void:
	for mi in ModelLib.meshes(root):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Recolour glTF-named surfaces of a prop ("Shirt", "Pants"...): {"Shirt": Color}. Per-surface overrides, shared meshes untouched.
static func recolor(root: Node, colors: Dictionary) -> void:
	for mi in ModelLib.meshes(root):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null:
				continue
			var key := m.resource_name.get_slice(".", 0)
			if colors.has(key):
				mi.set_surface_override_material(i, mat(colors[key], 0.8))
