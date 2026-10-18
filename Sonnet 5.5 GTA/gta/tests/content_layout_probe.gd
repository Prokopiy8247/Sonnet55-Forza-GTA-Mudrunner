extends Node
## Prints what the World-Layout agent produced (lots by kind, furniture by kind, nature zones, locations) - for adapting the content builders.

func run(main: Node) -> Variant:
	var kinds := {}
	var floors_max := {}
	var landmarks := {}
	var yaws := {}
	var smallest := {}
	var largest := {}
	for lot in WorldLayout.lots:
		var k: StringName = lot.get("kind", &"")
		kinds[k] = int(kinds.get(k, 0)) + 1
		floors_max[k] = maxi(int(floors_max.get(k, 0)), int(lot.get("floors", 0)))
		var r: Rect2 = lot["rect"]
		var yk := str(snappedf(float(lot.get("yaw", 0.0)), 0.01))
		yaws[yk] = int(yaws.get(yk, 0)) + 1
		smallest[k] = r.size if not smallest.has(k) or r.size.x * r.size.y < (smallest[k] as Vector2).x * (smallest[k] as Vector2).y else smallest[k]
		largest[k] = r.size if not largest.has(k) or r.size.x * r.size.y > (largest[k] as Vector2).x * (largest[k] as Vector2).y else largest[k]
		if k == &"landmark":
			landmarks[lot.get("landmark", &"")] = r
	print("PROBE lots=%d kinds=%s" % [WorldLayout.lots.size(), str(kinds)])
	print("PROBE floors_max=%s" % str(floors_max))
	print("PROBE yaws=%s" % str(yaws))
	print("PROBE smallest=%s" % str(smallest))
	print("PROBE largest=%s" % str(largest))
	print("PROBE landmarks=%s" % str(landmarks))
	var fk := {}
	var phases := {}
	for f in WorldLayout.furniture:
		var k2: StringName = f.get("kind", &"")
		fk[k2] = int(fk.get(k2, 0)) + 1
		if k2 == &"signal":
			phases[int(f.get("phase", -9))] = int(phases.get(int(f.get("phase", -9)), 0)) + 1
	print("PROBE furniture=%d kinds=%s signal_phases=%s" % [WorldLayout.furniture.size(), str(fk), str(phases)])
	print("PROBE signals=%d" % WorldLayout.signals.size())
	var zk := {}
	for z in WorldLayout.nature_zones:
		zk[z.get("kind", &"")] = int(zk.get(z.get("kind", &""), 0)) + 1
	print("PROBE nature_zones=%d kinds=%s" % [WorldLayout.nature_zones.size(), str(zk)])
	print("PROBE locations=%s" % str(WorldLayout.locations.keys()))
	print("PROBE piers=%d roads=%d" % [WorldLayout.piers.size(), WorldLayout.roads.size()])
	if CityBuilder.last_stats.size() > 0:
		print("PROBE content_stats=%s" % str(CityBuilder.last_stats))
	return true
