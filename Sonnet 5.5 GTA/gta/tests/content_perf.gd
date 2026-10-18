extends Node
## Measures render cost of the current view (needs a real renderer: run with `tools\gd.ps1 game`):
##   tools\gd.ps1 game -Seconds 25 -GameArgs "--exec=res://gta/tests/content_perf.gd --cam=0,2.2,60,0,9,-30 --time=15"
## Prints PERFRT with the averaged CPU / GPU render time (ms), draw calls, objects, primitives and fps over 150 frames.

func run(main: Node) -> Variant:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 60:
		await get_tree().process_frame
	var cpu := 0.0
	var gpu := 0.0
	var dc := 0.0
	var obj := 0.0
	var prim := 0.0
	var n := 150
	for i in n:
		await get_tree().process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	print("PERFRT cpu_ms=%.2f gpu_ms=%.2f draw_calls=%d objects=%d prims=%d fps=%d traffic=%s peds=%s" % [
		cpu / n, gpu / n, int(dc / n), int(obj / n), int(prim / n), Engine.get_frames_per_second(),
		str(Game.cheats.get("traffic", true)), str(Game.cheats.get("pedestrians", true))])
	return true
