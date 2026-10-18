extends Node
## Screenshot / smoke helper for the world content. Uses the real world when WorldLayout.lots is populated, else the mock.
##   tools\gd.ps1 shot -Out screenshots\content_a.png -GameArgs "--exec=res://gta/tests/content_showcase.gd --cam=60,22,40,60,8,-20 --time=15 --delay=2"

func run(main: Node) -> Variant:
	var real: bool = WorldLayout.lots.size() > 0 and Game.world != null
	if not real:
		ContentMock.fill(true)
		var world := ContentMock.make_world(main, true)
		Game.world = world
		CityBuilder.build(world)
	else:
		# real world: make sure the night factor follows the clock when the Environment agent is not driving it yet
		var env = Game.sys(&"environment")
		if env == null or not env.has_method("set_weather"):
			var tod: float = Game.time_of_day
			var night := clampf(smoothstep(19.0, 21.5, tod) + (1.0 - smoothstep(4.5, 6.5, tod)), 0.0, 1.0)
			Game.set_global(&"gta_night", night)
	# wait a few frames so every material compiled and the fade ranges settled
	for i in 12:
		await get_tree().process_frame
	print("SHOWCASE real_world=%s stats=%s" % [str(real), str(CityBuilder.last_stats)])
	return true
