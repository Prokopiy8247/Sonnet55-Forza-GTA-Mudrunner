extends Node
## Screenshot helper (used with `tools\gd.ps1 shot ... -GameArgs "--exec=res://gta/tests/traffic_shot_prep.gd --wait=14 --cap=34"`):
## raises the traffic cap so the junction looks busy, then waits N real seconds so the ring fills and the cars drive into view.
## Options: --wait=S (default 12)  --cap=N (default 34)  --density=F (settings multiplier, default 1.4)


func _arg(name: String, default_value: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + name + "="):
			return s.substr(name.length() + 3)
	return default_value


func run(_main: Node) -> void:
	var tm = Game.sys(&"traffic")
	if tm != null:
		tm.cap_override = int(_arg("cap", "34"))
	Game.settings["traffic_density"] = float(_arg("density", "1.4"))
	var t := float(_arg("wait", "12"))
	await get_tree().create_timer(t).timeout
	if tm != null:
		print("SHOTPREP traffic stats: ", tm.get_stats())
