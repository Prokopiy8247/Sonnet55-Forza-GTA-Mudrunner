class_name ModelLib
extends RefCounted
## Loads Blender-exported GLB models from res://gta/generated/models/.
## Relative ids look like "vehicles/sedan", "weapons/pistol", "characters/human".
## Blender convention: +Y forward, Z up -> after glTF export the model faces -Z in Godot (Godot forward).
## When a model is missing, instance() returns null and logs once; callers build a fallback and the
## final QA pass treats any fallback use as an unfinished asset (see ModelLib.missing).

const ROOT := "res://gta/generated/models/"

static var _cache: Dictionary = {}
static var missing: Dictionary = {}    # rel id -> times requested while missing


static func path(rel: String) -> String:
	return ROOT + rel + ".glb"


static func exists(rel: String) -> bool:
	return ResourceLoader.exists(path(rel))


static func load_scene(rel: String) -> PackedScene:
	if _cache.has(rel):
		return _cache[rel]
	var p := path(rel)
	var scene: PackedScene = null
	if ResourceLoader.exists(p):
		scene = load(p) as PackedScene
	if scene == null:
		if not missing.has(rel):
			push_warning("ModelLib: missing model '%s' (%s)" % [rel, p])
		missing[rel] = int(missing.get(rel, 0)) + 1
	else:
		_cache[rel] = scene
	return scene


## Instantiates the model scene root (a Node3D) or null when the asset does not exist.
static func instance(rel: String) -> Node3D:
	var scene := load_scene(rel)
	if scene == null:
		return null
	return scene.instantiate() as Node3D


## First MeshInstance3D descendant whose name matches (exact, case-sensitive) or null.
static func find_mesh(root: Node, node_name: String) -> MeshInstance3D:
	var n := root.find_child(node_name, true, false)
	return n as MeshInstance3D


## All MeshInstance3D descendants.
static func meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
