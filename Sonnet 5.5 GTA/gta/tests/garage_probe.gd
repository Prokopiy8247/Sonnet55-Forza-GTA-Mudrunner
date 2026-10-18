extends Node
## Dev probe: prints the garage_shop landmark anchors + lot info and the dealer lot vehicles.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/garage_probe.gd -Seconds 25 -GameArgs "--no-traffic --no-peds"


func run(main: Node) -> String:
	await get_tree().create_timer(4.0).timeout
	var loc: Dictionary = WorldLayout.get_location(&"garage_shop")
	print("PROBE garage_shop loc=", loc)
	for n in get_tree().get_nodes_in_group(&"landmark_anchor"):
		if String(n.get_meta(&"landmark", "")) == "garage_shop" or String(n.get_meta(&"landmark", "")) == "safehouse":
			print("PROBE anchor ", n.name, " lm=", n.get_meta(&"landmark", ""), " pos=", (n as Node3D).global_position, " rot_y=", rad_to_deg((n as Node3D).global_rotation.y))
	for n in get_tree().get_nodes_in_group(&"location_anchor"):
		var id := String(n.get_meta(&"location_id", ""))
		if id == "garage_shop" or id == "safehouse" or id == "dealer_lot":
			print("PROBE loc_anchor ", n.name, " id=", id, " pos=", (n as Node3D).global_position, " radius=", n.get_meta(&"radius", 0.0))
	var sys = Game.sys(&"vehicles")
	if sys != null:
		print("PROBE dealer vehicles=", sys.dealer_vehicles.size())
	for lot in WorldLayout.lots:
		if lot.get("landmark", &"") == &"garage_shop" or lot.get("landmark", &"") == &"safehouse":
			print("PROBE lot ", lot)
	print("PROBE safehouse loc=", WorldLayout.get_location(&"safehouse"))
	print("PROBE ModelLib parts dir exists=", DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://gta/generated/models/vehicle_parts")))
	return "ok"
