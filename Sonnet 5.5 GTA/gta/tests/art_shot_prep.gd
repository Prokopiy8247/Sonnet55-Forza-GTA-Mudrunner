extends Node
## Art-pass screenshot preparation (Environment/Art agent). Use with --shot and --exec:
##   tools\gd.ps1 shot -Out screenshots\art_x.png -GameArgs "--exec=res://gta/tests/art_shot_prep.gd --nohud --cam=... --time=18"
## Options (all via GameArgs): --nohud (hide Game.ui), --hideplayer (hide player node), --keepfog (default anyway),
## --env_exposure=<f> etc. are NOT supported - tune in code. Keeps the underwater overlay (CanvasLayer -50) alive.


func run(_main: Node) -> bool:
	var args := OS.get_cmdline_user_args()
	var hide_hud := false
	var hide_player := false
	for a in args:
		var s := String(a)
		if s == "--nohud":
			hide_hud = true
		elif s == "--hideplayer":
			hide_player = true
	if hide_hud:
		for l in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var cl := l as CanvasLayer
			if cl.layer >= 0:
				cl.visible = false
	if hide_player and is_instance_valid(Game.player):
		Game.player.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	return true
