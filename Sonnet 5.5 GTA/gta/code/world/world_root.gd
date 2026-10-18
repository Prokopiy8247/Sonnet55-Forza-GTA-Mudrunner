class_name WorldRoot
extends Node3D
## World-Layout agent: builds the whole static world (terrain, water, roads, airport, piers, boundary), fills WorldLayout
## (graphs, lots, furniture, locations) and hands over to CityBuilder.build(self). Sets Game.world = self.
## Public: get_sector_parent(pos), get_dynamic_parent(pos), sectors (SectorManager), build_report, terrain_body.
## Lifecycle: setup(main) once in boot order, then post_setup() after ALL systems exist.

var sectors: SectorManager
var build_report: Dictionary = {}
var terrain_body: StaticBody3D
var content_root: Node3D = null


func setup(_main: Node) -> void:
	name = "World"
	Game.world = self
	var t0 := Time.get_ticks_msec()
	var marks := {}
	WorldLayout.generate()
	marks["layout"] = Time.get_ticks_msec() - t0
	var t1 := Time.get_ticks_msec()
	sectors = SectorManager.new()
	sectors.name = "SectorManager"
	add_child(sectors)
	sectors.setup(self)
	terrain_body = TerrainBuilder.build(self)
	marks["terrain"] = Time.get_ticks_msec() - t1
	t1 = Time.get_ticks_msec()
	WaterBuilder.build(self)
	marks["water"] = Time.get_ticks_msec() - t1
	t1 = Time.get_ticks_msec()
	WorldBoundary.build(self)
	marks["boundary"] = Time.get_ticks_msec() - t1
	t1 = Time.get_ticks_msec()
	var rb := RoadBuilder.new(self)
	rb.build_roads()
	marks["roads"] = Time.get_ticks_msec() - t1
	t1 = Time.get_ticks_msec()
	rb.build_grounds()
	AirportBuilder.build(rb)
	PierBuilder.build(rb)
	RailBuilder.build(rb)
	rb.flush()
	StuntBuilder.build(self)
	marks["airport_piers_flush"] = Time.get_ticks_msec() - t1
	build_report["road_stats"] = rb.stats
	t1 = Time.get_ticks_msec()
	CityBuilder.build(self)
	marks["city"] = Time.get_ticks_msec() - t1
	_fix_roof_locations()
	build_report = {"total_ms": Time.get_ticks_msec() - t0, "marks": marks}
	print("[WorldRoot] built in %d ms %s" % [build_report["total_ms"], str(marks)])


func post_setup() -> void:
	pass


## The helipad locations sit on roofs: correct their height to the real roof the building kit produced.
func _fix_roof_locations() -> void:
	for t in BuildingKit.towers:
		var lot_id := int(t.get("lot", -1))
		for lid in [&"helipad_downtown", &"helipad_hospital"]:
			var loc: Dictionary = WorldLayout.locations.get(lid, {})
			if not loc.is_empty() and int(loc.get("lot", -2)) == lot_id:
				var p: Vector3 = loc["pos"]
				loc["pos"] = Vector3(p.x, float(t["roof_y"]) + 0.4, p.z)


func get_sector_parent(pos: Vector3) -> Node3D:
	return sectors.get_sector_parent(pos)


func get_dynamic_parent(pos: Vector3) -> Node3D:
	return sectors.get_dynamic_parent(pos)
