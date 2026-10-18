extends Node
## Scratch helper for the Environment agent: waits, then prints the environment / lamp / rain stats. Use with the real
## world (no test city): --exec=res://gta/tests/env_dbg.gd --time=22 --cam=x,y,z,tx,ty,tz  (the harness takes the shot afterwards)

func run(_main: Node) -> String:
	var env := Game.sys(&"environment") as EnvironmentSystem
	if env == null:
		return "no env"
	Game.cheats["invulnerable"] = true
	await get_tree().create_timer(3.0).timeout
	print("TEST dbg stats ", env.get_stats())
	var cnt := get_tree().get_nodes_in_group("street_lamp").size()
	print("TEST dbg street_lamp nodes in the world: ", cnt, " world_children=", Game.world.get_child_count() if Game.world != null else -1)
	return "ok"
