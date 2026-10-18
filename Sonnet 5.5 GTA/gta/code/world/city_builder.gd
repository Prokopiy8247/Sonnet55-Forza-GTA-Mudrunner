class_name CityBuilder
extends RefCounted
## World-Content entry point. WorldRoot (World-Layout agent) calls CityBuilder.build(world) ONCE after WorldLayout.lots /
## furniture / nature_zones / locations are populated. Everything static is batched into MultiMesh instances per 100 m
## sector (see ContentBatch); the only runtime node is ContentManager (signals, window clock, dynamic props).
## Public API: build(world), last_stats, reset_cache().

const _SF := preload("res://gta/code/world/street_furniture.gd")
const _NB := preload("res://gta/code/world/nature_builder.gd")
const _LB := preload("res://gta/code/world/landmark_builder.gd")

static var last_stats: Dictionary = {}
static var last_root: Node3D = null
static var last_batch: ContentBatch = null


static func reset_cache() -> void:
	ContentLib.reset()
	BuildingKit.reset()
	_SF.reset()
	_NB.reset()
	_LB.reset()
	FillBuilder.reset()


## Frees everything the previous build created (idempotent) so build() can run again (tests / layout changes).
static func clear() -> void:
	if last_batch != null:
		for n in last_batch.owned:
			if is_instance_valid(n):
				n.queue_free()
		if is_instance_valid(last_batch.content_root):
			last_batch.content_root.queue_free()
	last_batch = null
	last_root = null
	reset_cache()


static func build(world: Node3D) -> void:
	if world == null:
		push_error("CityBuilder.build: world is null")
		return
	var t0 := Time.get_ticks_msec()
	var marks: Dictionary = {}
	clear()
	var batch := ContentBatch.new(world)
	last_batch = batch
	last_root = batch.content_root
	BuildingKit.ensure_library()
	BuildingKit.configure_lod(batch)
	marks["library"] = Time.get_ticks_msec() - t0

	var t1 := Time.get_ticks_msec()
	if WorldLayout.lots.is_empty():
		push_warning("CityBuilder: WorldLayout.lots is empty - no buildings built")
	else:
		BuildingKit.build_all(batch, WorldLayout.lots)
		_LB.build(batch)
		FillBuilder.build(batch)
	marks["buildings"] = Time.get_ticks_msec() - t1

	var mgr := ContentManager.new()
	mgr.name = "ContentManager"
	batch.content_root.add_child(mgr)
	mgr.setup(batch)

	var t2 := Time.get_ticks_msec()
	_SF.build(batch, mgr)
	marks["furniture"] = Time.get_ticks_msec() - t2
	var t3 := Time.get_ticks_msec()
	_NB.build(batch)
	marks["nature"] = Time.get_ticks_msec() - t3

	var t_flush := Time.get_ticks_msec()
	batch.flush(func(k: StringName) -> Mesh: return ContentLib.get_mesh(k))
	_SF.finish(batch, mgr)
	marks["flush"] = Time.get_ticks_msec() - t_flush

	var total := Time.get_ticks_msec() - t0
	var fb_used: Array[String] = []
	var used_keys: Dictionary = batch.stats["keys"]
	for k in used_keys:
		if ContentLib.sources.get(k, "") == "fallback":
			fb_used.append(String(k))
	last_stats = {
		"ms": total, "marks": marks, "instances": batch.stats["instances"], "multimeshes": batch.stats["multimeshes"],
		"colliders": batch.stats["colliders"], "buildings": BuildingKit.stats["buildings"], "modules": BuildingKit.stats["modules"],
		"fallbacks": fb_used.size(), "kinds": BuildingKit.stats["kinds"], "kit_parts": BuildingKit.kit_parts_loaded,
		"furniture": _SF.stats.duplicate(true), "nature": _NB.stats.duplicate(true), "landmarks": _LB.stats.duplicate(true),
	}
	print("[CityBuilder] built in %d ms: %d buildings, %d instances in %d multimeshes, %d colliders, fallbacks=%d marks=%s" % [
		total, BuildingKit.stats["buildings"], batch.stats["instances"], batch.stats["multimeshes"], batch.stats["colliders"],
		fb_used.size(), str(marks)])
	last_stats["fallback_keys"] = fb_used
	if not fb_used.is_empty():
		print("[CityBuilder] FALLBACK meshes in use (Blender GLB missing): ", fb_used)
