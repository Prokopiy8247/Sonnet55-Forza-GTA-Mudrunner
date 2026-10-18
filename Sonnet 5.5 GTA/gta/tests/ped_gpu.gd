extends Node
## Render cost probe of the pedestrians (needs a real renderer, run through `tools\gd.ps1 shot`):
##   tools\gd.ps1 shot -Out screenshots\peds\gpu.png -GameArgs "--exec=res://gta/tests/ped_gpu.gd --delay=4 --time=12 --no-traffic --no-peds"
## Prints PROBE lines with draw calls / primitives per configuration.

var pm: PedManager


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _dc() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


func _prims() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


func _avg_dc() -> Array:
	var d := 0.0
	var p := 0.0
	var n := 20
	for i in n:
		await get_tree().process_frame
		d += float(_dc())
		p += float(_prims())
	return [d / n, p / n]


func run(_main: Node) -> Variant:
	pm = Game.sys(&"peds")
	pm.auto_population = false
	pm.clear_all(true)
	var player: Node3D = Game.player
	var base := Vector3(-30.0, 0.1, 36.0)
	player.teleport_to(base + Vector3(0, 0, 14))
	await _frames(40)
	var b0: Array = await _avg_dc()
	print("PROBE baseline draw_calls=%.0f prims=%.0f" % [b0[0], b0[1]])
	var crowd := pm.spawn_crowd(base, 40.0, 40)
	await _frames(60)
	var b1: Array = await _avg_dc()
	var meshes := 0
	var surfaces := 0
	for p in crowd:
		for mi in ModelLib.meshes((p as Pedestrian).rig.model):
			if mi.visible:
				meshes += 1
				surfaces += mi.mesh.get_surface_count() if mi.mesh != null else 0
	var cam := Game.gameplay_camera
	var vis := 0
	for p in crowd:
		if cam.is_position_in_frustum((p as Pedestrian).global_position + Vector3(0, 1, 0)):
			vis += 1
	print("PROBE %d peds (%d in frustum): draw_calls=%.0f prims=%.0f  (+%.0f dc, +%.0f prims) meshes=%d surfaces=%d" % [crowd.size(), vis, b1[0], b1[1], b1[0] - b0[0], b1[1] - b0[1], meshes, surfaces])
	# no shadows on any ped mesh
	for p in crowd:
		for mi in ModelLib.meshes((p as Pedestrian).rig.model):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await _frames(10)
	var b2: Array = await _avg_dc()
	print("PROBE no ped shadows: draw_calls=%.0f prims=%.0f (-%.0f dc)" % [b2[0], b2[1], b1[0] - b2[0]])
	for p in crowd:
		for mi in ModelLib.meshes((p as Pedestrian).rig.model):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pm.clear_all(true)
	return null
