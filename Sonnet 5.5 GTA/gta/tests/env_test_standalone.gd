extends SceneTree
## Runs env_test.gd WITHOUT booting Main (so it keeps working while other agents' modules are mid-edit):
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/env_test_standalone.gd
## Creates a fake Main node, registers a real EnvironmentSystem as Game.sys("environment"), then runs the test.

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var game := root.get_node_or_null("Game")
	if game == null:
		print("TEST standalone FAIL autoload Game missing")
		quit(1)
		return
	var fake_main := Node.new()
	fake_main.name = "FakeMain"
	root.add_child(fake_main)
	var env_script = load("res://gta/code/world/environment_system.gd")
	var env: Node = env_script.new()
	env.name = "Environment"
	fake_main.add_child(env)
	game.systems[&"environment"] = env
	env.setup(fake_main)
	env.post_setup()
	await process_frame
	var test_script = load("res://gta/tests/env_test.gd")
	var test: Node = test_script.new()
	fake_main.add_child(test)
	var result = await test.run(fake_main)
	print("TEST standalone done ", result)
	quit(0 if str(result) == "PASS" else 1)
