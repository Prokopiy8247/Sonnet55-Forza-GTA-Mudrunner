extends Node
## Top-down plan of the layout (terrain, roads, lots, furniture, lane points, locations) saved as PNG - world-fill planning aid.
##   tools\gd.ps1 exec -Script res://gta/tests/fill_map_dump.gd -Seconds 40 -GameArgs "--no-traffic --no-peds --region=-300,-300,300,300 --px=2 --out=screenshots/fill_map.png"
## Colours: lots by kind, grounds tinted, roads grey, sidewalks light, lane points red, furniture dots, locations white crosses.

const KIND_COL := {
	&"office": Color("#5a78c8"), &"apartment": Color("#c88a5a"), &"shop": Color("#d9b24a"), &"house": Color("#e08f8f"),
	&"warehouse": Color("#8a8f99"), &"factory": Color("#6e6a8f"), &"hangar": Color("#5ab0a0"), &"parking": Color("#a0a0a0"),
	&"landmark": Color("#ff4fd8"), &"park": Color("#58b058"), &"empty": Color("#d0d0b0"),
}
const FURN_COL := {
	&"lamp": Color("#ffee55"), &"bin": Color("#ff3030"), &"bench": Color("#30ff30"), &"hydrant": Color("#ff8800"), &"bollard": Color("#ff00ff"),
	&"tree_street": Color("#007a00"), &"palm": Color("#00aa55"), &"fence": Color("#ffffff"), &"signal": Color("#00ffff"),
}


func _arg(opts: Dictionary, key: String, def: String) -> String:
	return String(opts.get(key, def))


func run(_main: Node) -> bool:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			opts[s.substr(0, eq)] = s.substr(eq + 1)
	var multi := _arg(opts, "multi", "")
	if multi != "":
		# "name=x0,z0,x1,z1,px;name2=..." -> screenshots/fill/<name>.png each
		for item in multi.split(";"):
			var kv := item.split("=")
			var o2 := opts.duplicate()
			var parts := kv[1].split(",")
			o2["region"] = ",".join(parts.slice(0, 4))
			o2["px"] = parts[4] if parts.size() > 4 else "4"
			o2["out"] = "screenshots/fill/" + kv[0] + ".png"
			o2["multi"] = ""
			_render(o2)
		return true
	_render(opts)
	return true


func _render(opts: Dictionary) -> void:
	var rg := _arg(opts, "region", "-300,-300,300,300").split(",")
	var x0 := float(rg[0])
	var z0 := float(rg[1])
	var x1 := float(rg[2])
	var z1 := float(rg[3])
	var px := float(_arg(opts, "px", "2"))
	var out := _arg(opts, "out", "screenshots/fill_map.png")
	var layers := _arg(opts, "layers", "terrain,roads,lots,furn,lanes,locs,grid")
	var w := int((x1 - x0) * px)
	var h := int((z1 - z0) * px)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color("#3a6a3a"))
	var to_px := func(p: Vector2) -> Vector2: return Vector2((p.x - x0) * px, (p.y - z0) * px)
	if layers.contains("terrain"):
		for iy in h:
			for ix in w:
				var wx := x0 + (float(ix) + 0.5) / px
				var wz := z0 + (float(iy) + 0.5) / px
				var ht := WorldLayout.terrain_height(wx, wz)
				var c := Color("#4f8a4a")
				if ht < GC.WATER_LEVEL:
					c = Color("#2f6f9f").lerp(Color("#18304f"), clampf((-ht - 1.5) / 14.0, 0.0, 1.0))
					if WorldLayout.on_pier(wx, wz):
						c = Color("#8a6a3a")
				else:
					var sf := WorldLayout.surface_at(wx, wz)
					if sf == &"sand":
						c = Color("#e0cf90")
					elif sf == &"rock":
						c = Color("#8a8070").lerp(Color.WHITE, clampf(ht / 90.0, 0.0, 0.5))
					elif sf == &"concrete":
						c = Color("#7a8a7a")
					else:
						c = Color("#4f8a4a").lerp(Color("#2f5a2f"), clampf(ht / 55.0, 0.0, 0.8))
				img.set_pixel(ix, iy, c)
	if layers.contains("roads"):
		for e in LayoutRoadNet.edges:
			var pts := LayoutGeo.resample(e["pts"], 1.5)
			var hw: float = e["hw"]
			var sw: float = e["sw"]
			for p in pts:
				_disc(img, to_px.call(p), (hw + sw) * px, Color("#b8b8b0"))
			for p in pts:
				_disc(img, to_px.call(p), hw * px, Color("#33363b"))
	if layers.contains("lots"):
		for lot in WorldLayout.lots:
			var r: Rect2 = lot["rect"]
			var col: Color = KIND_COL.get(lot["kind"], Color.WHITE)
			if lot["kind"] == &"empty" or lot["kind"] == &"park":
				col.a = 0.55
			else:
				col.a = 0.85
			_rect(img, to_px.call(r.position), to_px.call(r.end), col)
			# front edge marker
			var side: String = lot["side"]
			var fe := Rect2()
			match side:
				"n": fe = Rect2(r.position.x, r.position.y, r.size.x, 1.0)
				"s": fe = Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0)
				"e": fe = Rect2(r.end.x - 1.0, r.position.y, 1.0, r.size.y)
				"w": fe = Rect2(r.position.x, r.position.y, 1.0, r.size.y)
			_rect(img, to_px.call(fe.position), to_px.call(fe.end), Color(1, 1, 1, 0.9))
	if layers.contains("lanes"):
		for i in WorldLayout.lanes.size():
			var p3: Vector3 = WorldLayout.lanes.positions[i]
			_disc(img, to_px.call(Vector2(p3.x, p3.z)), 1.2, Color("#ff2020"))
	if layers.contains("furn"):
		for f in WorldLayout.furniture:
			var p3b: Vector3 = f["pos"]
			var c2: Color = FURN_COL.get(f["kind"], Color("#ffffff"))
			_disc(img, to_px.call(Vector2(p3b.x, p3b.z)), 1.5, c2)
	if layers.contains("locs"):
		for id in WorldLayout.locations:
			var p3c: Vector3 = WorldLayout.locations[id]["pos"]
			var q: Vector2 = to_px.call(Vector2(p3c.x, p3c.z))
			for k in range(-5, 6):
				_px(img, Vector2(q.x + k, q.y), Color.WHITE)
				_px(img, Vector2(q.x, q.y + k), Color.WHITE)
	if layers.contains("grid"):
		var gx := ceilf(x0 / 50.0) * 50.0
		while gx <= x1:
			var major := int(gx) % 100 == 0
			for iy in h:
				var cc := img.get_pixel(int((gx - x0) * px), iy) if int((gx - x0) * px) < w else Color.BLACK
				_px(img, Vector2((gx - x0) * px, iy), cc.lerp(Color.BLACK, 0.55 if major else 0.25))
			gx += 50.0
		var gz := ceilf(z0 / 50.0) * 50.0
		while gz <= z1:
			var major2 := int(gz) % 100 == 0
			for ix in w:
				var cc2 := img.get_pixel(ix, int((gz - z0) * px)) if int((gz - z0) * px) < h else Color.BLACK
				_px(img, Vector2(ix, (gz - z0) * px), cc2.lerp(Color.BLACK, 0.55 if major2 else 0.25))
			gz += 50.0
	var abs_path := out
	if not out.is_absolute_path():
		abs_path = ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := img.save_png(abs_path)
	print("TEST fill_map_dump ", "PASS" if err == OK else "FAIL", " ", abs_path, " ", w, "x", h)


func _px(img: Image, p: Vector2, c: Color) -> void:
	var ix := int(p.x)
	var iy := int(p.y)
	if ix < 0 or iy < 0 or ix >= img.get_width() or iy >= img.get_height():
		return
	if c.a < 1.0:
		c = img.get_pixel(ix, iy).lerp(Color(c.r, c.g, c.b), c.a)
	img.set_pixel(ix, iy, c)


func _disc(img: Image, p: Vector2, r: float, c: Color) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy <= r * r:
				_px(img, Vector2(p.x + dx, p.y + dy), c)


func _rect(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	for iy in range(int(a.y), int(b.y) + 1):
		for ix in range(int(a.x), int(b.x) + 1):
			_px(img, Vector2(ix, iy), c)
