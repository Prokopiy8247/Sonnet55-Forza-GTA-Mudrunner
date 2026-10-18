class_name LayoutHills
extends RefCounted
## Terrain carving data for the hill roads: the road bed is cut into the NE hills with a graded profile.


static func carve_paths() -> Array:
	var out: Array = []
	for e in LayoutRoadNet.edges:
		if not bool(e["hill"]):
			continue
		var dense := LayoutGeo.resample(e["pts"], 2.0)
		out.append({"pts": dense, "half": float(e["hw"]) + 0.6, "max_grade": 0.105, "end_free": true, "edge": e["id"]})
	return out
