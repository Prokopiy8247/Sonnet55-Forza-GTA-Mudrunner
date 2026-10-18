class_name ContentLib
extends RefCounted
## Mesh registry + GLB flattening for the world content. Blender GLBs (buildings / props / nature) are flattened into
## ONE ArrayMesh per asset (surfaces grouped by runtime material), so thousands of instances can share one MultiMesh.
## Fallback (code-built) meshes are registered under the same keys and every fallback use is logged / listed.

static var meshes: Dictionary = {}        # StringName -> ArrayMesh
static var aabbs: Dictionary = {}         # StringName -> AABB
static var sources: Dictionary = {}       # StringName -> "glb:<rel>" | "fallback"
static var fallbacks: Array[String] = []
static var glb_loaded: Array[String] = []
static var extras: Dictionary = {}        # StringName -> Dictionary (anchors, metadata)


static func reset() -> void:
	meshes.clear()
	aabbs.clear()
	sources.clear()
	fallbacks.clear()
	glb_loaded.clear()
	extras.clear()


static func has_mesh(key: StringName) -> bool:
	return meshes.has(key)


static func get_mesh(key: StringName) -> ArrayMesh:
	return meshes.get(key)


static func put(key: StringName, mesh: ArrayMesh, src: String) -> void:
	meshes[key] = mesh
	aabbs[key] = mesh.get_aabb() if mesh != null else AABB()
	sources[key] = src
	if src == "fallback" and not fallbacks.has(String(key)):
		fallbacks.append(String(key))
	elif src != "fallback" and fallbacks.has(String(key)):
		fallbacks.erase(String(key))


## Registers `key` from the GLB `rel` (flattened) when it exists, else from the fallback builder (logged).
static func register_glb_or(key: StringName, rel: String, fallback: Callable, skip_names: Array = []) -> ArrayMesh:
	if meshes.has(key):
		return meshes[key]
	if ModelLib.exists(rel):
		var root := ModelLib.instance(rel)
		if root != null:
			var m := flatten(root, skip_names)
			root.free()
			if m != null and m.get_surface_count() > 0:
				put(key, m, "glb:" + rel)
				glb_loaded.append(rel)
				return m
	var fb = fallback.call()
	var fm: ArrayMesh = null
	if fb is ContentMesh:
		fm = (fb as ContentMesh).to_mesh(_default_materials())
	elif fb is ArrayMesh:
		fm = fb
	if fm == null:
		push_warning("ContentLib: fallback for '%s' returned nothing" % key)
		return null
	push_warning("ContentLib: GLB '%s' missing - using code-built FALLBACK for '%s'" % [rel, key])
	put(key, fm, "fallback")
	return fm


## Registers a complete model when its GLB exists (no fallback). Returns true when registered.
static func register_glb_optional(key: StringName, rel: String, skip_names: Array = [], foliage_kind: StringName = &"") -> bool:
	if meshes.has(key):
		return true
	if not ModelLib.exists(rel):
		return false
	var root := ModelLib.instance(rel)
	if root == null:
		return false
	var m := flatten(root, skip_names, foliage_kind)
	root.free()
	if m == null or m.get_surface_count() == 0:
		return false
	put(key, m, "glb:" + rel)
	glb_loaded.append(rel)
	return true


static func _default_materials() -> Dictionary:
	return {
		&"WallA": FacadeMaterials.wall(0), &"WallB": FacadeMaterials.wall(1), &"WallC": FacadeMaterials.wall(2),
		&"WallD": FacadeMaterials.wall(3), &"Roof": FacadeMaterials.wall(4), &"Trim": FacadeMaterials.wall(5),
		&"Window_office": FacadeMaterials.window(&"office"), &"Window_res": FacadeMaterials.window(&"res"),
		&"Window_shop": FacadeMaterials.window(&"shop"), &"Window_industrial": FacadeMaterials.window(&"industrial"),
		&"Window": FacadeMaterials.window(&"res"),
		&"Neon": FacadeMaterials.neon(Color.WHITE, 0.9, 4.5, true),
		&"NeonMagenta": FacadeMaterials.neon(Color("#ff3d9a")),
		&"NeonCyan": FacadeMaterials.neon(Color("#34e0ff")),
		&"NeonAmber": FacadeMaterials.neon(Color("#ffb347")),
		&"NeonRed": FacadeMaterials.neon(Color("#ff2a22"), 0.6, 4.0),
		&"LampGlow": FacadeMaterials.lamp_glow(),
		&"SignalRed": FacadeMaterials.signal_lens(1), &"SignalAmber": FacadeMaterials.signal_lens(2),
		&"SignalGreen": FacadeMaterials.signal_lens(3),
		&"Metal": FacadeMaterials.vcol(0.55, 0.45), &"V": FacadeMaterials.vcol(),
		&"Foliage": FacadeMaterials.foliage(&"tree"), &"Palm": FacadeMaterials.foliage(&"palm"),
		&"Grass": FacadeMaterials.foliage(&"grass"), &"Reed": FacadeMaterials.foliage(&"reed"),
		&"Rigid": FacadeMaterials.foliage(&"rigid"),
		&"Glass": FacadeMaterials.glass(),
	}


# ---- GLB flattening ------------------------------------------------------------------------------------
static func _rel(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _skipped(nm: String, skip_names: Array) -> bool:
	if nm.begins_with("Collision") or nm.ends_with("_col") or nm.begins_with("Col_"):
		return true
	for s in skip_names:
		if nm == String(s) or nm.begins_with(String(s)):
			return true
	return false


static func is_foliage_name(n: String) -> bool:
	var b := FacadeMaterials.base_name(n)
	return b.begins_with("Leaf") or b.begins_with("PalmLeaf") or b.begins_with("Reed") or b.begins_with("Cattail")


class _Group extends RefCounted:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var mname := ""
	var src: Material = null


static func _append_surface(g: _Group, mi: MeshInstance3D, s: int, xf: Transform3D) -> void:
	var arrays: Array = mi.mesh.surface_get_arrays(s)
	var vtx: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nor = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var idx = arrays[Mesh.ARRAY_INDEX]
	var has_idx: bool = idx != null and idx.size() > 0
	var has_n: bool = nor != null and nor.size() == vtx.size()
	var has_uv: bool = uvs != null and uvs.size() == vtx.size()
	var count: int = idx.size() if has_idx else vtx.size()
	var nb := xf.basis.inverse().transposed()
	var k := 0
	while k + 2 < count:
		var i0: int = idx[k] if has_idx else k
		var i1: int = idx[k + 1] if has_idx else k + 1
		var i2: int = idx[k + 2] if has_idx else k + 2
		var p0: Vector3 = xf * vtx[i0]
		var p1: Vector3 = xf * vtx[i1]
		var p2: Vector3 = xf * vtx[i2]
		g.v.append(p0)
		g.v.append(p1)
		g.v.append(p2)
		if has_n:
			g.n.append((nb * (nor[i0] as Vector3)).normalized())
			g.n.append((nb * (nor[i1] as Vector3)).normalized())
			g.n.append((nb * (nor[i2] as Vector3)).normalized())
		else:
			var fn := (p1 - p0).cross(p2 - p0).normalized()
			# Godot front faces are clockwise: geometric normal points away from the viewer -> flip for the shading normal
			fn = -fn
			g.n.append(fn)
			g.n.append(fn)
			g.n.append(fn)
		if has_uv:
			g.uv.append(uvs[i0])
			g.uv.append(uvs[i1])
			g.uv.append(uvs[i2])
		else:
			g.uv.append(Vector2.ZERO)
			g.uv.append(Vector2.ZERO)
			g.uv.append(Vector2.ZERO)
		k += 3


static func _build(groups: Dictionary, fkind: StringName = &"", fheight: float = 1.0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# every surface rendered by the wall shader (WallA..D, Roof, Trim, Concrete, Metal, generic colours...) is merged into ONE
	# surface with the slot / colour baked into the vertex colour -> far fewer draw calls per module
	var wv := PackedVector3Array()
	var wn := PackedVector3Array()
	var wuv := PackedVector2Array()
	var wc := PackedColorArray()
	var others: Array = []
	var fv := PackedVector3Array()
	var fn := PackedVector3Array()
	var fuv := PackedVector2Array()
	var fc := PackedColorArray()
	for key in groups:
		var g: _Group = groups[key]
		if g.v.is_empty():
			continue
		if fkind != &"" and is_foliage_name(g.mname):
			# foliage: one merged surface, colour + wind-sway weight (by height) baked into the vertex colour
			var base := Color(0.3, 0.5, 0.25)
			if g.src is BaseMaterial3D:
				base = (g.src as BaseMaterial3D).albedo_color
			base = base.srgb_to_linear()
			for i in g.v.size():
				var yy: float = g.v[i].y
				var wgt := clampf((yy - 0.25) / maxf(fheight, 0.5), 0.0, 1.0)
				wgt = pow(wgt, 1.2) if fkind == &"tree" or fkind == &"palm" else clampf(yy / maxf(fheight, 0.3), 0.0, 1.0)
				fc.append(Color(base.r, base.g, base.b, wgt))
			fv.append_array(g.v)
			fn.append_array(g.n)
			fuv.append_array(g.uv)
			continue
		var mat := FacadeMaterials.for_glb(g.mname, g.src)
		var wi := FacadeMaterials.wall_info(mat)
		if wi.is_empty():
			others.append([key, g, mat])
			continue
		var slot_v: int = wi["slot"]
		var col := Color.WHITE
		if slot_v >= 6:
			col = (wi["color"] as Color).srgb_to_linear()
		col.a = float(slot_v) / 8.0
		var carr := PackedColorArray()
		carr.resize(g.v.size())
		carr.fill(col)
		wv.append_array(g.v)
		wn.append_array(g.n)
		wuv.append_array(g.uv)
		wc.append_array(carr)
	if not wv.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = wv
		arrays[Mesh.ARRAY_NORMAL] = wn
		arrays[Mesh.ARRAY_TEX_UV] = wuv
		arrays[Mesh.ARRAY_COLOR] = wc
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var si := mesh.get_surface_count() - 1
		mesh.surface_set_material(si, FacadeMaterials.wall_merged())
		mesh.surface_set_name(si, "walls")
	if not fv.is_empty():
		var arrays_f: Array = []
		arrays_f.resize(Mesh.ARRAY_MAX)
		arrays_f[Mesh.ARRAY_VERTEX] = fv
		arrays_f[Mesh.ARRAY_NORMAL] = fn
		arrays_f[Mesh.ARRAY_TEX_UV] = fuv
		arrays_f[Mesh.ARRAY_COLOR] = fc
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_f)
		var sif := mesh.get_surface_count() - 1
		mesh.surface_set_material(sif, FacadeMaterials.foliage(fkind))
		mesh.surface_set_name(sif, "foliage")
	for o in others:
		var g2: _Group = o[1]
		var arrays2: Array = []
		arrays2.resize(Mesh.ARRAY_MAX)
		arrays2[Mesh.ARRAY_VERTEX] = g2.v
		arrays2[Mesh.ARRAY_NORMAL] = g2.n
		arrays2[Mesh.ARRAY_TEX_UV] = g2.uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays2)
		var si2 := mesh.get_surface_count() - 1
		mesh.surface_set_material(si2, o[2])
		mesh.surface_set_name(si2, String(o[0]))
	return mesh


## Flattens every MeshInstance3D below `root` (node transforms baked in) into one ArrayMesh grouped by runtime material.
static func flatten(root: Node3D, skip_names: Array = [], foliage_kind: StringName = &"") -> ArrayMesh:
	var groups := {}
	for mi in ModelLib.meshes(root):
		if mi.mesh == null or _skipped(String(mi.name), skip_names):
			continue
		var xf := _rel(root, mi)
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			var mname := src.resource_name if src != null else "Default"
			var key := FacadeMaterials.base_name(mname)
			var g: _Group = groups.get(key)
			if g == null:
				g = _Group.new()
				g.mname = mname
				g.src = src
				groups[key] = g
			_append_surface(g, mi, s, xf)
	var max_y := 1.0
	if foliage_kind != &"":
		for key in groups:
			for p in (groups[key] as _Group).v:
				max_y = maxf(max_y, p.y)
	return _build(groups, foliage_kind, max_y)


## One MeshInstance3D flattened in ITS OWN LOCAL SPACE (node transform ignored) - for building kit modules whose origin
## convention (bottom-centre of the front plane) is the object origin.
static func flatten_local(mi: MeshInstance3D) -> ArrayMesh:
	var groups := {}
	if mi.mesh == null:
		return null
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s)
		var mname := src.resource_name if src != null else "Default"
		var key := FacadeMaterials.base_name(mname)
		var g: _Group = groups.get(key)
		if g == null:
			g = _Group.new()
			g.mname = mname
			g.src = src
			groups[key] = g
		_append_surface(g, mi, s, Transform3D.IDENTITY)
	return _build(groups)


## All named MeshInstance3D parts of a kit GLB (name -> local-space ArrayMesh). Empty when the GLB does not exist.
static func kit_parts(rel: String) -> Dictionary:
	var out := {}
	if not ModelLib.exists(rel):
		return out
	var root := ModelLib.instance(rel)
	if root == null:
		return out
	for mi in ModelLib.meshes(root):
		var nm := String(mi.name)
		if _skipped(nm, []):
			continue
		var m := flatten_local(mi)
		if m != null and m.get_surface_count() > 0:
			out[nm] = m
	root.free()
	return out


## Empties (Node3D without mesh) of a GLB as name -> Transform3D relative to the root. Used for anchors (Door, RoofHelipad...).
static func empties(root: Node3D) -> Dictionary:
	var out := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != root and n is Node3D and not (n is MeshInstance3D) and not (n is Skeleton3D):
			out[String(n.name)] = _rel(root, n as Node3D)
		for c in n.get_children():
			stack.append(c)
	return out
