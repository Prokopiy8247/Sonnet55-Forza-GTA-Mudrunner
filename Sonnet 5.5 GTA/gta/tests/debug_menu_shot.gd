extends Node
## Screenshot helper for the benchmark menu:
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\debug\tab1.png -Resolution 1920x1080 -GameArgs "--exec=res://gta/tests/debug_menu_shot.gd --tab=1 --no-intro --delay=3 --no-traffic --no-peds"
## Options: --tab=<0..6>  --drive=<vehicle id> (open the menu while driving that vehicle)


func run(_main: Node) -> String:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--") and s.find("=") > 0:
			opts[s.substr(2, s.find("=") - 2)] = s.substr(s.find("=") + 1)
	Game.ui.capture_when_idle = false
	if opts.has("drive"):
		DebugCmds.spawn_vehicle(StringName(opts["drive"]), {"enter": true})
		await get_tree().create_timer(1.5, true, false, true).timeout
	var dm = Game.sys(&"debug")
	dm.open(int(opts.get("tab", 0)))
	await get_tree().create_timer(0.6, true, false, true).timeout
	print("TEST debug_menu_shot PASS tab %s" % opts.get("tab", 0))
	return "ok"
