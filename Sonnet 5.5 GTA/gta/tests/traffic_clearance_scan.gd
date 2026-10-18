extends Node
## Scans every lane point with LaneClearance and prints the blocked / dodge spots (world-content defects next to lanes).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/traffic_clearance_scan.gd -Seconds 60 -GameArgs "--no-peds --no-traffic"


func run(_main: Node) -> void:
	for i in 12:
		await get_tree().physics_frame
	var G: LaneGraph = WorldLayout.lanes
	var t0 := Time.get_ticks_usec()
	var blocked: Array[String] = []
	var dodged: Array[String] = []
	for i in G.size():
		var s := LaneClearance.get_state(i)
		if s == LaneClearance.BLOCKED:
			blocked.append("%d %s kind=%d lim=%.1f" % [i, str(G.positions[i].snapped(Vector3(0.1, 0.1, 0.1))), G.kind[i], G.speed_limit[i]])
		elif s == LaneClearance.DODGE:
			dodged.append("%d %s kind=%d dodge=%.2f" % [i, str(G.positions[i].snapped(Vector3(0.1, 0.1, 0.1))), G.kind[i], LaneClearance.get_dodge(i)])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("CLEAR total=%d blocked=%d dodge=%d in %.0f ms" % [G.size(), blocked.size(), dodged.size(), ms])
	for l in blocked:
		print("CLEAR blocked ", l)
	for l in dodged:
		print("CLEAR dodge ", l)
	print("CLEAR done")
