extends SceneTree
## Runs a Node-based rig test (run(main) coroutine) WITHOUT booting Main, so the rig can be tested while other modules are mid-edit:
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/rig_runner.gd -Seconds 120 -GameArgs "--test=res://gta/tests/rig_test.gd"
## Default test: res://gta/tests/rig_test.gd

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var test_path := "res://gta/tests/rig_test.gd"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--test="):
			test_path = String(a).substr(7)
	var holder := Node.new()
	holder.name = "RigRunnerMain"
	root.add_child(holder)
	var scr = load(test_path)
	if scr == null:
		print("TEST runner FAIL cannot load ", test_path)
		quit(1)
		return
	var t: Node = scr.new()
	holder.add_child(t)
	var result = await t.run(holder)
	print("RIG RUNNER RESULT ", result)
	# free everything (physics bodies included) before quitting: leaving Jolt bodies alive at exit can hang the headless process
	holder.queue_free()
	for i in 4:
		await process_frame
	quit(0)
