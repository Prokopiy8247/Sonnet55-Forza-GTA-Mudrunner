extends Node
## Dev probe: per ground vehicle GLB -> material names per mesh, plate AABB, wheel node transforms, body extents.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/garage_probe2.gd -Seconds 25 -GameArgs "--no-traffic --no-peds --no-intro --no-vehicles"


func run(main: Node) -> String:
	await get_tree().create_timer(1.0).timeout
	var ids := ["sedan", "sports", "compact", "muscle", "suv", "pickup", "van", "taxi", "police_cruiser", "ambulance", "firetruck", "truck", "police_tactical", "motorcycle", "bicycle"]
	for id in ids:
		var m := ModelLib.instance("vehicles/" + id)
		if m == null:
			print("PROBE2 ", id, " MISSING")
			continue
		add_child(m)
		var lines: Array[String] = []
		for mi in ModelLib.meshes(m):
			var xf := Util._rel_transform(m, mi)
			var mats: Array[String] = []
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				mats.append(mat.resource_name if mat != null else "-")
			var bb := xf * mi.get_aabb()
			lines.append("   mesh %s pos=%s scale=%s aabb_pos=%s size=%s mats=%s" % [mi.name, xf.origin, xf.basis.get_scale(), bb.position, bb.size, mats])
		print("PROBE2 ", id)
		for l in lines:
			print(l)
		# plate surface extents
		for mi in ModelLib.meshes(m):
			var xf2 := Util._rel_transform(m, mi)
			for s in mi.mesh.get_surface_count():
				var mat2 := mi.mesh.surface_get_material(s)
				if mat2 != null and mat2.resource_name in ["Plate", "Rim"]:
					var arr := mi.mesh.surface_get_arrays(s)
					var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var uv = arr[Mesh.ARRAY_TEX_UV]
					var mn := Vector3(INF, INF, INF)
					var mx := Vector3(-INF, -INF, -INF)
					for p in vv:
						var q := xf2 * p
						mn = mn.min(q)
						mx = mx.max(q)
					print("   surf ", mat2.resource_name, " on ", mi.name, " verts=", vv.size(), " min=", mn, " max=", mx, " uv=", uv != null)
		m.queue_free()
	return "ok"
