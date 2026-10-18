extends Node
## Quick layout generation smoke test: timing + graph sizes + basic height checks.


func run(_main: Node) -> bool:
	var t0 := Time.get_ticks_msec()
	WorldLayout.generate()
	print("TEST gen_time INFO ", Time.get_ticks_msec() - t0, " ms")
	print("TEST lanes INFO points=", WorldLayout.lanes.size(), " ped=", WorldLayout.ped_graph.size(), " signals=", WorldLayout.signals.size())
	print("TEST height_plateau ", "PASS" if absf(WorldLayout.terrain_height(0, 0)) < 0.01 else "FAIL", " h=", WorldLayout.terrain_height(0, 0))
	print("TEST height_peak INFO ", WorldLayout.terrain_height(215, -228))
	print("TEST water_south ", "PASS" if WorldLayout.is_water(0, 260) else "FAIL")
	print("TEST land_north ", "PASS" if not WorldLayout.is_water(0, -100) else "FAIL")
	return true
