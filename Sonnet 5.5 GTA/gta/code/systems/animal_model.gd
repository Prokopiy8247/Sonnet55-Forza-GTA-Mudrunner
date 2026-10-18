class_name AnimalModel
extends RefCounted
## Builds Animal nodes from the Blender GLBs (animals/<id>.glb): finds the articulated parts by their contract names, creates the hit
## capsule, applies per-individual coat tints (cached materials, never mutates the shared GLB materials) and provides the code fallback
## (a clearly labelled box animal) when a GLB is missing.

const PART_NAMES: Array[String] = [
	"Body", "Head", "Neck", "Tail", "Leg_FL", "Leg_FR", "Leg_BL", "Leg_BR", "Leg_L", "Leg_R", "Ear_L", "Ear_R", "Jaw", "Wing_L", "Wing_R",
	"Fin_Tail", "Fin_L", "Fin_R", "Fin_Dorsal", "Flipper_FL", "Flipper_FR", "Flipper_BL", "Flipper_BR", "Antlers",
]

static var fallbacks: Dictionary = {}          # model id -> times a fallback body was built (reported by the tests / docs)
static var _coat_cache: Dictionary = {}


## Creates a ready-to-use (hidden, unparented) Animal for the species.
static func create(sp: StringName, variant: int = 0) -> Animal:
	var d := WildlifeDefs.get_def(sp)
	if d.is_empty():
		return null
	var a := Animal.new()
	a.name = String(sp).capitalize()
	a.setup_species(sp, d)
	var sc_range: Array = d.get("scale", [1.0, 1.0])
	a.model_scale = randf_range(float(sc_range[0]), float(sc_range[1]))
	a.vroot = Node3D.new()
	a.vroot.name = "Visual"
	a.add_child(a.vroot)
	var kind: StringName = d.get("kind", &"land")
	if kind == &"bird":
		# two GLBs (wings spread / folded) toggled by the flight state
		var m_fly := _instance(String(d["model"]), a)
		var m_perch := _instance(String(d.get("model_perched", d["model"])), a)
		_attach(a, m_fly)
		_attach(a, m_perch)
		a.set_model_variant(1)
	else:
		var m := _instance(String(d["model"]), a)
		_attach(a, m)
		a.set_model_variant(0)
	a.coat = variant
	_apply_coat(a, variant)
	# hit capsule (axis along the body = Z)
	var shape: Array = d.get("shape", [0.3, 1.0, 0.5])
	var sc := a.model_scale
	var r := float(shape[0]) * sc
	var length := maxf(float(shape[1]) * sc, r * 2.0 + 0.05)
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = length
	var cs := CollisionShape3D.new()
	cs.name = "Hitbox"
	cs.shape = cap
	cs.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	cs.position = Vector3(0.0, float(shape[2]) * sc, 0.0)
	a.add_child(cs)
	a.shape_node = cs
	a.body_height = maxf(float(shape[2]) * sc * 2.0, 0.3)
	a.set_physics_process(false)
	a.set_process(false)
	return a


static func _attach(a: Animal, m: Node3D) -> void:
	m.scale = Vector3.ONE * a.model_scale
	a.vroot.add_child(m)
	var pd: Dictionary = {}
	var rd: Dictionary = {}
	for pn in PART_NAMES:
		var n := m.find_child(pn, true, false) as Node3D
		if n != null:
			pd[pn] = n
			rd[pn] = n.position
	a.models.append(m)
	a.parts_all.append(pd)
	a.rest_all.append(rd)
	for mi in ModelLib.meshes(m):
		a.mesh_list.append(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func _instance(rel: String, a: Animal) -> Node3D:
	var m := ModelLib.instance(rel)
	if m != null:
		return m
	fallbacks[rel] = int(fallbacks.get(rel, 0)) + 1
	push_warning("AnimalModel: GLB '%s' missing - using a labelled box fallback" % rel)
	var root := Node3D.new()
	root.name = "FALLBACK_" + rel.get_file()
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	var shape: Array = a.def.get("shape", [0.3, 1.0, 0.5])
	bm.size = Vector3(float(shape[0]) * 2.0, float(shape[2]) * 1.6 + 0.1, maxf(float(shape[1]), 0.3))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 1.0)
	bm.material = mat
	body.mesh = bm
	body.position = Vector3(0.0, bm.size.y * 0.5, 0.0)
	root.add_child(body)
	return root


## Per-animal coat: swaps the AnimalFur surfaces of every model of this animal for a cached tinted copy.
static func _apply_coat(a: Animal, variant: int) -> void:
	var coats = WildlifeDefs.COATS.get(a.sp, null)
	if coats == null or (coats as Array).is_empty():
		return
	var idx := variant % (coats as Array).size()
	var key := "%s#%d" % [a.sp, idx]
	var mat: Material = _coat_cache.get(key, null)
	if mat == null:
		var src: Material = null
		for m in a.models:
			src = Util.find_material(m, "AnimalFur")
			if src != null:
				break
		if src is StandardMaterial3D:
			var dup := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.albedo_color = (coats as Array)[idx]
			dup.resource_name = "AnimalFur"
			mat = dup
			_coat_cache[key] = mat
	if mat == null:
		return
	for m in a.models:
		Util.replace_material(m, "AnimalFur", mat)


## Merges every mesh below `root` into ONE ArrayMesh (a surface per distinct material), baking the node transforms relative to `root`.
## Used for static decoration and for the fish MultiMesh. Returns {mesh: ArrayMesh, materials: Array[Material]} (mesh null when empty).
static func merge_meshes(root: Node3D, skip_names: Array = []) -> Dictionary:
	var verts_by_mat: Dictionary = {}          # Material -> Array[Vector3]
	var norms_by_mat: Dictionary = {}          # Material -> Array[Vector3]
	var idx_by_mat: Dictionary = {}            # Material -> Array[int]
	var order: Array = []
	for mi in ModelLib.meshes(root):
		if mi.mesh == null or skip_names.has(String(mi.name)):
			continue
		var xf := Util._rel_transform(root, mi)
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var vtx: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if vtx.is_empty():
				continue
			var nor := PackedVector3Array()
			if arrays[Mesh.ARRAY_NORMAL] != null:
				nor = arrays[Mesh.ARRAY_NORMAL]
			var idx := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX]
			var mat: Material = mi.get_active_material(s)
			if not verts_by_mat.has(mat):
				verts_by_mat[mat] = []
				norms_by_mat[mat] = []
				idx_by_mat[mat] = []
				order.append(mat)
			var vl: Array = verts_by_mat[mat]
			var nl: Array = norms_by_mat[mat]
			var il: Array = idx_by_mat[mat]
			var base := vl.size()
			for k in vtx.size():
				vl.append(xf * vtx[k])
				if nor.size() == vtx.size():
					nl.append((nb * nor[k]).normalized())
			if idx.is_empty():
				for k in vtx.size():
					il.append(base + k)
			else:
				for k in idx:
					il.append(base + k)
	var out := ArrayMesh.new()
	var mats: Array[Material] = []
	for mat in order:
		var vl2: Array = verts_by_mat[mat]
		if vl2.is_empty():
			continue
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(vl2)
		var nl2: Array = norms_by_mat[mat]
		if nl2.size() == vl2.size():
			arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(nl2)
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array(idx_by_mat[mat])
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, mat)
		mats.append(mat)
	return {"mesh": out if out.get_surface_count() > 0 else null, "materials": mats}
