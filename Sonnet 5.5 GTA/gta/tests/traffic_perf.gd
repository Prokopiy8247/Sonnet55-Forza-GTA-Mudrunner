extends Node
## Windowed A/B performance probe (needs a real renderer):
##   powershell -NoProfile -File tools\gd.ps1 game -Seconds 80 -GameArgs "--time=8 --teleport=-27,1,-11,0 --exec=res://gta/tests/traffic_perf.gd"
## Phase A: traffic ON at the 28-car cap (warm-up, then a 10 s measurement); phase B: all traffic cars removed (spawning off), same measurement.
## Prints PERFAB lines with the average / minimum fps, draw calls and the traffic tick cost. (The machine is shared with other agents, so
## the absolute numbers are noisy; the difference between A and B is what counts.)


func _measure(label: String, secs: float) -> void:
	var t := 0.0
	var n := 0
	var fps_sum := 0.0
	var fps_min := 9999.0
	var dc_sum := 0.0
	var ms_sum := 0.0
	var tm = Game.sys(&"traffic")
	while t < secs:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		var fps := Engine.get_frames_per_second()
		fps_sum += fps
		fps_min = minf(fps_min, fps)
		dc_sum += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		ms_sum += 1000.0 / maxf(float(fps), 1.0)
		n += 1
	var active := 0
	if tm != null:
		active = tm.get_active_count()
	print("PERFAB %s: avg_fps=%.1f min_fps=%.1f avg_frame_ms=%.1f draw_calls=%.0f traffic_active=%d traffic_tick_us=%.0f" % [label, fps_sum / n, fps_min, ms_sum / n, dc_sum / n, active, (tm.stats["tick_us_avg"] if tm != null else 0.0)])


func run(_main: Node) -> void:
	var tm = Game.sys(&"traffic")
	if tm == null:
		print("PERFAB no traffic")
		return
	tm.cap_override = 28
	Game.settings["traffic_density"] = 1.4
	await get_tree().create_timer(14.0).timeout
	await _measure("A traffic ON (28 cap)", 10.0)
	tm.spawn_enabled = false
	tm.clear_traffic()
	await get_tree().create_timer(4.0).timeout
	await _measure("B traffic OFF", 10.0)
	tm.spawn_enabled = true
	await get_tree().create_timer(10.0).timeout
	await _measure("C traffic ON again", 10.0)
	print("PERFAB DONE")
