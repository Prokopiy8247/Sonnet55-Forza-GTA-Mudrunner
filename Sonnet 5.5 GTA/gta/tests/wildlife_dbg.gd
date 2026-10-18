extends Node
## Dev probe: one deer walking, prints the limb rotation over time.


func run(_main: Node) -> Variant:
	for i in 60:
		await get_tree().physics_frame
	var wl := Game.sys(&"wildlife") as WildlifeSystem
	var player := Game.player as Node3D
	wl.auto_population = false
	wl.despawn_all()
	var base := Vector3(-12.0, 0.0, -125.0)
	player.teleport_to(base + Vector3(0, 0.2, 25.0), 0.0)
	for i in 20:
		await get_tree().physics_frame
	var d := wl.spawn_animal(&"deer", base, {})
	d.speed = 3.0
	WildlifeBrain.set_state(d, WildlifeBrain.S_WALK, 20.0)
	d.goal = base + Vector3(10.0, 0.0, -10.0)
	for i in 120:
		await get_tree().physics_frame
		if i % 15 == 0:
			var leg := d.parts.get("Leg_FL") as Node3D
			print("TEST DBG i=%d tier=%d state=%d speed=%.2f want=%.2f gait_amp=%.3f phase=%.2f legrot=%s anim_acc=%.3f parts=%d" % [i, d.tier, d.state, d.speed, d.want_speed, d.gait_amp, d.gait_phase, str(leg.rotation if leg != null else null), d.anim_acc, d.parts.size()])
	return true
