extends Node
## Smoke run of the pedestrian module: prints the population after a few seconds. Not a test.

func run(main: Node) -> void:
	var pm: PedManager = Game.sys(&"peds")
	print("SMOKE manager=", pm)
	for i in 12:
		await get_tree().create_timer(1.0).timeout
		var hist := {}
		for p in pm.peds:
			var n: String = p.get_state_name()
			hist[n] = int(hist.get(n, 0)) + 1
		print("SMOKE t=", i + 1, " peds=", pm.peds.size(), " target=", pm.stats["target"], " states=", hist, " tick_us=", int(pm.stats["tick_us"]), " think_us=", int(pm.stats["think_us"]), " move_us=", int(pm.stats["move_us"]), " rejects=", pm.stats["visible_rejects"], " scenes=", pm.spawner.scenes)
