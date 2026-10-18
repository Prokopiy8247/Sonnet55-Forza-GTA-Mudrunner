extends Node
## Dev probe: body analysis (hood / roof / trunk runs) of every ground vehicle model.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/garage_probe4.gd -Seconds 30 -GameArgs "--no-traffic --no-peds --no-intro --no-vehicles"


func run(_main: Node) -> String:
	await get_tree().create_timer(1.0).timeout
	for id in ["sedan", "compact", "sports", "muscle", "suv", "pickup", "van", "taxi", "police_cruiser", "ambulance", "firetruck", "truck", "police_tactical"]:
		var m := ModelLib.instance("vehicles/" + id)
		add_child(m)
		var an := VehicleModsFit.analyze(m, StringName("probe_" + id))
		var f := func(d: Dictionary) -> String:
			if d.is_empty():
				return "none"
			return "z %.2f..%.2f y %.3f len %.2f%s" % [d["z0"], d["z1"], d["y"], d["len"], " (synth)" if d.get("synth", false) else ""]
		print("PROBE4 %s min=%s max=%s\n   hood: %s\n   roof: %s\n   trunk: %s\n   exhaust=%s has=%s plates=%d" % [id, an["min"], an["max"], f.call(an["hood"]), f.call(an["roof"]), f.call(an["trunk"]), an["exhaust"], an["has_exhaust"], (an["plates"] as Array).size()])
		var door := m.find_child("DoorL", true, false) as Node3D
		if door != null:
			print("   DoorL pos=", Util._rel_transform(m, door).origin)
		m.queue_free()
	return "ok"
