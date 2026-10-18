class_name VehicleModsVisual
extends RefCounted
## Builds / removes everything cosmetic on one vehicle from its `mods` dictionary (idempotent, incremental):
## body parts (Blender GLBs from models/vehicle_parts) mounted by body analysis, rim styles (Blender wheel GLBs),
## licence plates, livery stripes, underglow, lamp tints and horn style. Installed once as VehicleBase.visual_mods_hook by the
## GarageSystem, so it runs from VehicleBase.apply_mods() on every code path (garage, factory opts, store / deliver, pool reuse).
##
## Scene layout under VehicleBase.model:   ModParts / Part_<slot> | Livery | Plates | Underglow      (+ RimMod children of wheel nodes)
## Per-slot state lives in meta `mv_state` (slot -> key string) so a change of one option rebuilds only that option.

const CONTAINER := "ModParts"
const HIDE_RIM_SURFACES: Array[String] = ["Rim", "Chrome", "Metal"]

static var fallbacks_used: Dictionary = {}          # option key -> true (listed in the report / doc)
static var glb_used: Dictionary = {}
static var stats := {"applies": 0, "rebuilds": 0}
static var _hidden_mat: StandardMaterial3D = null
static var _glow_tex: GradientTexture2D = null
static var _plate_cache: Dictionary = {}
static var _liv_mats: Dictionary = {}


static func install() -> void:
	VehicleBase.visual_mods_hook = Callable(VehicleModsVisual, "apply")


# =====================================================================================================
# Entry point
# =====================================================================================================
static func apply(v: VehicleBase) -> void:
	if v == null or not is_instance_valid(v) or v.model == null:
		return
	stats["applies"] += 1
	var mods: Dictionary = v.mods
	var st: Dictionary = v.get_meta(&"mv_state", {})
	var cfg := VehicleModsData.vehicle_cfg(v.def_id)
	var allowed: Array = cfg.get("slots", [])
	var kind: String = String(cfg.get("kind", "car"))
	var repaint := false
	var an: Dictionary = {}
	# ---- body parts
	for slot in VehicleModsData.SLOTS:
		var want := String(mods.get("p_" + String(slot), ""))
		if want == "stock" or not allowed.has(slot):
			want = ""
		var key := String(slot)
		if String(st.get(key, "")) == want:
			continue
		st[key] = want
		stats["rebuilds"] += 1
		_remove_child(_container(v), "Part_" + key)
		if want != "":
			if an.is_empty():
				an = VehicleModsFit.analyze(v.model, v.def_id)
			var node := _build_part(v, StringName(slot), StringName(want), an)
			if node != null:
				node.name = "Part_" + key
				_container(v).add_child(node)
		repaint = true
	# ---- wheels / rims
	var rim_key := String(mods.get("rim_style", "stock"))
	if String(st.get("rims", "")) != rim_key or int(st.get("wheel_count", -1)) != v.wheels.size():
		st["rims"] = rim_key
		st["wheel_count"] = v.wheels.size()
		stats["rebuilds"] += 1
		_apply_rims(v, StringName(mods.get("rim_style", "stock")))
		if mods.get("rim_color", null) is Color:
			v.set_rim_color(mods["rim_color"])
	# ---- plates
	var plate_key := "%s|%s" % [mods.get("plate", ""), mods.get("plate_text", "")]
	if String(st.get("plate", "")) != plate_key:
		st["plate"] = plate_key
		stats["rebuilds"] += 1
		_remove_child(_container(v), "Plates")
		if String(mods.get("plate", "")) != "" and kind != "bicycle":
			if an.is_empty():
				an = VehicleModsFit.analyze(v.model, v.def_id)
			var pn := _build_plates(v, StringName(mods["plate"]), String(mods.get("plate_text", "HB 0000")), an)
			if pn != null:
				_container(v).add_child(pn)
	# ---- livery
	var liv_key := "%s|%s" % [mods.get("livery", "none"), (mods["livery_color"] as Color).to_html(false) if mods.get("livery_color", null) is Color else ""]
	if String(st.get("livery", "")) != liv_key:
		st["livery"] = liv_key
		stats["rebuilds"] += 1
		_remove_child(_container(v), "Livery")
		var lid := StringName(mods.get("livery", "none"))
		if lid != &"none" and lid != &"" and kind == "car":
			if an.is_empty():
				an = VehicleModsFit.analyze(v.model, v.def_id)
			var lcol: Color = mods["livery_color"] if mods.get("livery_color", null) is Color else Color(0.94, 0.95, 0.97)
			var ln := _build_livery(lid, lcol, an)
			if ln != null:
				_container(v).add_child(ln)
	# ---- underglow
	var ug_key := String(mods.get("underglow", "off"))
	if String(st.get("underglow", "")) != ug_key:
		st["underglow"] = ug_key
		stats["rebuilds"] += 1
		_remove_child(_container(v), "Underglow")
		if ug_key != "off" and ug_key != "" and kind != "bicycle":
			if an.is_empty():
				an = VehicleModsFit.analyze(v.model, v.def_id)
			var un := _build_underglow(v, _lookup_color(VehicleModsData.UNDERGLOW, StringName(ug_key)), an)
			if un != null:
				_container(v).add_child(un)
	# ---- lamp tints + horn (cheap, always applied)
	if v.lights != null:
		v.lights.set_tint(&"head", _lookup_color(VehicleModsData.HEADLIGHTS, StringName(mods.get("headlight", "stock"))))
		v.lights.set_tint(&"tail", _lookup_color(VehicleModsData.TAILLIGHTS, StringName(mods.get("taillight", "stock"))))
	_apply_horn(v, int(mods.get("horn", 0)))
	v.set_meta(&"mv_state", st)
	if repaint:
		v.set_paint(v.paint_primary, v.paint_secondary, v.paint_finish)


static func _lookup_color(table: Array, id: StringName) -> Color:
	for o in table:
		if o["id"] == id:
			return o["color"]
	return Color(-1, 0, 0)


static func _apply_horn(v: VehicleBase, style: int) -> void:
	if style <= 0 or style >= VehicleModsData.HORNS.size():
		if v.has_meta(&"horn_sound"):
			v.remove_meta(&"horn_sound")
			v.remove_meta(&"horn_pitch")
		return
	var h: Dictionary = VehicleModsData.HORNS[style]
	v.set_meta(&"horn_sound", StringName(h["sound"]))
	v.set_meta(&"horn_pitch", float(h["pitch"]))


static func _container(v: VehicleBase) -> Node3D:
	var c := v.model.get_node_or_null(CONTAINER) as Node3D
	if c == null:
		c = Node3D.new()
		c.name = CONTAINER
		v.model.add_child(c)
	return c


static func _remove_child(parent: Node, child_name: String) -> void:
	var n := parent.get_node_or_null(child_name)
	if n != null:
		parent.remove_child(n)
		n.queue_free()


# =====================================================================================================
# Body parts (Blender GLBs, contract in docs/api/blender_vehicle_parts.md: origin = mount point, vehicle frame, sedan sized)
# =====================================================================================================
const WS_REF := 0.885                  # half width of the sedan the parts were authored for
static var missing_parts: Dictionary = {}


## Returns the Node3D (transform already set in model space) for slot/option, or null when the GLB is missing.
static func _build_part(v: VehicleBase, slot: StringName, opt_id: StringName, an: Dictionary) -> Node3D:
	var opt := VehicleModsData.slot_option(slot, opt_id)
	var glb_id := String(opt.get("glb", ""))
	if glb_id == "":
		return null
	var inst: Node3D = ModelLib.instance(glb_id) if ModelLib.exists(glb_id) else null
	if inst == null:
		if not missing_parts.has(glb_id):
			missing_parts[glb_id] = true
			push_warning("VehicleModsVisual: part GLB '%s' missing - option '%s/%s' is skipped" % [glb_id, slot, opt_id])
		return null
	glb_used[glb_id] = true
	var bb := Util.local_aabb(inst)
	var fit := _fit(v, slot, opt_id, an, bb)
	if fit.is_empty():
		inst.queue_free()
		return null
	var ov: Dictionary = VehicleModsData.fit_override(v.def_id, slot)
	var scale: Vector3 = fit["scale"]
	var pos: Vector3 = fit["pos"]
	var pitch: float = float(fit.get("pitch", 0.0))
	if ov.has("s"):
		scale *= float(ov["s"])
	if ov.has("sx"):
		scale.x *= float(ov["sx"])
	if ov.has("sz"):
		scale.z *= float(ov["sz"])
	pos += Vector3(float(ov.get("dx", 0.0)), float(ov.get("dy", 0.0)), float(ov.get("dz", 0.0)))
	pitch += float(ov.get("pitch", 0.0))
	var holder := Node3D.new()
	holder.name = "Part_%s" % slot
	holder.add_child(inst)
	holder.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(pitch)).scaled_local(scale), pos)
	return holder


## Mount transform of a part in model space (formulas of the Blender lane's fit tables, evaluated on the analysed body).
## `pb` = the part's own bounding box (part frame, Godot axes).
static func _fit(v: VehicleBase, slot: StringName, opt_id: StringName, an: Dictionary, pb: AABB) -> Dictionary:
	var mn: Vector3 = an["min"]
	var mx: Vector3 = an["max"]
	var ws := (mx.x - mn.x) * 0.5 / WS_REF
	var bz := mn.y + 0.07
	match slot:
		&"spoiler":
			var d := rear_deck(an)
			var z: float = float(d["z_end"]) - 0.11 - pb.end.z
			var hit := VehicleModsFit.ray_down(an, 0.0, z)
			var y: float = (hit["pos"] as Vector3).y if not hit.is_empty() else float(d["y"])
			return {"pos": Vector3(0, y, z), "scale": Vector3(ws, 1, 1)}
		&"front_bumper":
			if opt_id == &"splitter":
				return {"pos": Vector3(0, bz + 0.015, mn.z + 0.069), "scale": Vector3(ws, 1, 1)}
			return {"pos": Vector3(0, bz, mn.z - 0.016), "scale": Vector3(ws, 1, 1)}
		&"rear_bumper":
			return {"pos": Vector3(0, bz, mx.z - 0.084), "scale": Vector3(ws, 1, 1)}
		&"hood":
			var hood: Dictionary = an["hood"]
			var z0 := float(hood["z0"])
			var len_ := float(hood["z1"]) - z0
			var frac := 0.68 if opt_id == &"scoop" else 0.53
			var zc := z0 + len_ * frac
			var ya := VehicleModsFit.ray_down(an, 0.0, z0 + len_ * 0.2)
			var yb := VehicleModsFit.ray_down(an, 0.0, z0 + len_ * 0.8)
			var pitch := 0.0
			var y_c := float(hood["y"])
			if not ya.is_empty() and not yb.is_empty():
				var y_a: float = (ya["pos"] as Vector3).y
				var y_b: float = (yb["pos"] as Vector3).y
				pitch = rad_to_deg(atan2(y_a - y_b, maxf(len_ * 0.6, 0.1)))          # front lower than rear = nose-down = negative
				y_c = lerpf(y_a, y_b, (frac - 0.2) / 0.6)
			return {"pos": Vector3(0, y_c - (0.0 if opt_id == &"scoop" else 0.02), zc), "scale": Vector3(ws if opt_id == &"vents" else 1.0, 1, 1), "pitch": pitch}
		&"roof":
			var roof: Dictionary = an["roof"]
			var rlen := float(roof["z1"]) - float(roof["z0"])
			var rc := (float(roof["z0"]) + float(roof["z1"])) * 0.5
			var ry := float(roof["y"])
			match opt_id:
				&"rack":
					return {"pos": Vector3(0, ry, rc - 0.05), "scale": Vector3(ws, 1, clampf((rlen - 0.15) / 1.04, 0.6, 2.4))}
				&"light_bar":
					return {"pos": Vector3(0, ry, float(roof["z0"]) + 0.15), "scale": Vector3(ws, 1, 1)}
				&"antenna":
					return {"pos": Vector3(0.47 * ws, ry, float(roof["z1"]) - 0.30), "scale": Vector3.ONE}
				_:
					return {"pos": Vector3(0, ry, rc), "scale": Vector3.ONE}
		&"skirts":
			var wz := _wheel_z_range(v)
			var r := _wheel_radius(v)
			var length := (wz.y - wz.x) - 2.42 * r
			if length < 0.5:
				return {}
			return {"pos": Vector3(0, mn.y, (wz.x + wz.y) * 0.5), "scale": Vector3(ws, 1, length / 2.0)}
		&"exhaust":
			var ex: Vector3 = an["exhaust"]
			var ey := ex.y if bool(an["has_exhaust"]) else mn.y + 0.062
			var px := 0.0
			if opt_id == &"single":
				px = ex.x if bool(an["has_exhaust"]) else 0.56 * ws
			return {"pos": Vector3(px, ey, mx.z - 0.034), "scale": Vector3(1.0 if opt_id == &"single" else ws, 1, 1)}
		&"grille":
			return {"pos": Vector3(0, bz + 0.362, mn.z + 0.024), "scale": Vector3.ONE}
		&"mirrors":
			var door := v.model.find_child("DoorL", true, false) as Node3D
			var dp := Util._rel_transform(v.model, door).origin if door != null else Vector3(-0.885, 0.6, -0.8)
			return {"pos": Vector3(0, dp.y + 0.39, dp.z + 0.18), "scale": Vector3(ws, 1, 1)}
	return {}


## Rear-most upward facing paint surface on the centre line within 1.4 m of the tail (trunk lid / roof rear edge / tailgate top).
static func rear_deck(an: Dictionary) -> Dictionary:
	var mn: Vector3 = an["min"]
	var mx: Vector3 = an["max"]
	var min_y := mn.y + (mx.y - mn.y) * 0.4
	var z := mx.z - 0.05
	while z > mx.z - 1.4:
		var h := VehicleModsFit.ray_down(an, 0.0, z)
		if not h.is_empty():
			var p: Vector3 = h["pos"]
			if float((h["normal"] as Vector3).y) > 0.8 and p.y >= min_y and String(h["mat"]) != "Glass":
				return {"z_end": z, "y": p.y}
		z -= 0.03
	var trunk: Dictionary = an["trunk"]
	if not trunk.is_empty():
		return {"z_end": float(trunk["z1"]), "y": float(trunk["y"])}
	var roof: Dictionary = an["roof"]
	return {"z_end": float(roof["z1"]), "y": float(roof["y"])}


static func _wheel_z_range(v: VehicleBase) -> Vector2:
	var lo := INF
	var hi := -INF
	for w in v.wheels:
		lo = minf(lo, w.rest.z)
		hi = maxf(hi, w.rest.z)
	if lo == INF:
		return Vector2(-1.3, 1.3)
	return Vector2(lo, hi)


static func _wheel_radius(v: VehicleBase) -> float:
	return v.wheels[0].radius if not v.wheels.is_empty() else 0.33


# =====================================================================================================
# Rims (Blender wheel GLBs = tyre + rim; the stock wheel mesh is hidden, the GLB is a child of the spinning / steering wheel node)
# =====================================================================================================
static func _hidden_material() -> StandardMaterial3D:
	if _hidden_mat == null:
		_hidden_mat = StandardMaterial3D.new()
		_hidden_mat.resource_name = "RimHidden"
		_hidden_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hidden_mat.albedo_color = Color(0, 0, 0, 0)
		_hidden_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hidden_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _hidden_mat


static func _apply_rims(v: VehicleBase, style: StringName) -> void:
	var rd := VehicleModsData.rim_def(style)
	var glb_id := String(rd.get("glb", ""))
	var want := glb_id != "" and style != &"stock"
	if want and not ModelLib.exists(glb_id):
		if not missing_parts.has(glb_id):
			missing_parts[glb_id] = true
			push_warning("VehicleModsVisual: wheel GLB '%s' missing - rim style '%s' skipped" % [glb_id, style])
		want = false
	var bike: bool = v.vclass == GC.VC_BIKE or v.vclass == GC.VC_BICYCLE
	if bike and style != &"mc_sport":
		want = false
	for w in v.wheels:
		var mi := w.node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var old := mi.get_node_or_null("RimMod")
		if old != null:
			mi.remove_child(old)
			old.queue_free()
		for i in mi.mesh.get_surface_count():
			var ov := mi.get_surface_override_material(i)
			if ov != null and ov.resource_name == "RimHidden":
				mi.set_surface_override_material(i, null)
		if not want:
			continue
		var inst := ModelLib.instance(glb_id)
		if inst == null:
			continue
		glb_used[glb_id] = true
		var ref_r := 0.31 if style == &"mc_sport" else 0.34
		var ref_w := 0.17 if style == &"mc_sport" else 0.24
		var s := w.radius / ref_r
		var sx := clampf(w.width / ref_w, 0.8, 1.3)
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, _hidden_material())
		var holder := Node3D.new()
		holder.name = "RimMod"
		holder.scale = Vector3(sx, s, s)
		holder.add_child(inst)
		mi.add_child(holder)


# =====================================================================================================
# Plates
# =====================================================================================================
static func _build_plates(v: VehicleBase, style: StringName, text: String, an: Dictionary) -> Node3D:
	var clusters: Array = an["plates"]
	if clusters.is_empty():
		return null
	var sd: Dictionary = {}
	for p in VehicleModsData.PLATES:
		if p["id"] == style:
			sd = p
	if sd.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Plates"
	var mat := _plate_material(sd, text)
	for c in clusters:
		var mn: Vector3 = c["min"]
		var mx: Vector3 = c["max"]
		var ex := mx.x - mn.x
		var ey := mx.y - mn.y
		var w := minf(ex, ey * 2.0)
		if w < 0.1:
			continue
		var q := QuadMesh.new()
		q.size = Vector2(w, w * 0.5)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cx := (mn.x + mx.x) * 0.5
		var cy := (mn.y + mx.y) * 0.5
		if bool(c["front"]):
			mi.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(cx, cy, mn.z - 0.004))
		else:
			mi.transform = Transform3D(Basis.IDENTITY, Vector3(cx, cy, mx.z + 0.004))
		root.add_child(mi)
	if root.get_child_count() == 0:
		root.queue_free()
		return null
	return root


static func _plate_material(sd: Dictionary, text: String) -> StandardMaterial3D:
	var key := "%s|%s" % [sd["id"], text]
	if _plate_cache.has(key):
		return _plate_cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "PlateMod"
	m.albedo_texture = VehicleModsDecals.plate_texture(sd, text)
	m.roughness = 0.45
	m.metallic = 0.1
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if String(sd["id"]) == "neon":
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = 0.55
	_plate_cache[key] = m
	return m


# =====================================================================================================
# Livery
# =====================================================================================================
static func _livery_material(c: Color) -> StandardMaterial3D:
	var key := c.to_html(false)
	if _liv_mats.has(key):
		return _liv_mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "Livery"
	m.albedo_color = c
	m.roughness = 0.38
	m.metallic = 0.05
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	_liv_mats[key] = m
	return m


static func _build_livery(id: StringName, col: Color, an: Dictionary) -> Node3D:
	var mn: Vector3 = an["min"]
	var mx: Vector3 = an["max"]
	var off := 0.012
	var meshes: Array[ArrayMesh] = []
	var z0 := mn.z + 0.28
	var z1 := mx.z - 0.12
	match id:
		&"racing_twin":
			for sx in [-1.0, 1.0]:
				var m1 := VehicleModsFit.drape_top(an, sx * 0.06, sx * 0.2, z0, z1, off)
				if m1 != null:
					meshes.append(m1)
		&"racing_single":
			var m2 := VehicleModsFit.drape_top(an, -0.22, 0.22, z0, z1, off)
			if m2 != null:
				meshes.append(m2)
		&"hood_band":
			var hood: Dictionary = an["hood"]
			var trunk: Dictionary = an["trunk"]
			var mh := VehicleModsFit.drape_top(an, -0.3, 0.3, float(hood["z0"]), float(hood["z1"]), off)
			if mh != null:
				meshes.append(mh)
			if not trunk.is_empty():
				var mt := VehicleModsFit.drape_top(an, -0.3, 0.3, float(trunk["z0"]), float(trunk["z1"]), off)
				if mt != null:
					meshes.append(mt)
		&"side_line", &"double_side":
			var h := mx.y - mn.y
			for side in [-1.0, 1.0]:
				var ms := VehicleModsFit.drape_side(an, side, mn.y + h * 0.36, mn.y + h * 0.36 + 0.07, mn.z + 0.5, mx.z - 0.5, off)
				if ms != null:
					meshes.append(ms)
				if id == &"double_side":
					var ms2 := VehicleModsFit.drape_side(an, side, mn.y + h * 0.36 + 0.12, mn.y + h * 0.36 + 0.15, mn.z + 0.5, mx.z - 0.5, off)
					if ms2 != null:
						meshes.append(ms2)
		_:
			return null
	if meshes.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Livery"
	for m in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _livery_material(col)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


# =====================================================================================================
# Underglow
# =====================================================================================================
static func _build_underglow(_v: VehicleBase, col: Color, an: Dictionary) -> Node3D:
	if col.r < 0.0 or col.a <= 0.0:
		return null
	var mn: Vector3 = an["min"]
	var mx: Vector3 = an["max"]
	var root := Node3D.new()
	root.name = "Underglow"
	if _glow_tex == null:
		_glow_tex = GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.95))
		g.set_color(1, Color(1, 1, 1, 0.0))
		g.add_point(0.55, Color(1, 1, 1, 0.55))
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	# glow on the road
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2((mx.x - mn.x) + 1.5, (mx.z - mn.z) + 1.6)
	plane.mesh = pm
	var m := StandardMaterial3D.new()
	m.resource_name = "Underglow"
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _glow_tex
	m.albedo_color = Color(col.r, col.g, col.b, 0.8)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material_override = m
	plane.position = Vector3(0, 0.045, 0)
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plane)
	# the neon tube ring (Blender part `underglow_strip`, NeonCyan material recoloured)
	var glb_id := "vehicle_parts/underglow_strip"
	var ring: Node3D = ModelLib.instance(glb_id) if ModelLib.exists(glb_id) else null
	var nm := StandardMaterial3D.new()
	nm.resource_name = "NeonCyan"
	nm.albedo_color = col
	nm.emission_enabled = true
	nm.emission = col
	nm.emission_energy_multiplier = 3.0
	nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if ring != null:
		glb_used[glb_id] = true
		Util.replace_material(ring, "NeonCyan", nm)
		var ws := (mx.x - mn.x) * 0.5 / WS_REF
		var holder := Node3D.new()
		holder.add_child(ring)
		holder.transform = Transform3D(Basis.IDENTITY.scaled_local(Vector3(ws, 1, (mx.z - mn.z) / 4.763)), Vector3(0, mn.y - 0.025, (mn.z + mx.z) * 0.5))
		root.add_child(holder)
	else:
		missing_parts[glb_id] = true
	var lamp := OmniLight3D.new()
	lamp.name = "UnderglowLight"
	lamp.light_color = col
	lamp.light_energy = 1.6
	lamp.omni_range = 4.8
	lamp.omni_attenuation = 1.4
	lamp.position = Vector3(0, 0.22, 0)
	lamp.shadow_enabled = false
	root.add_child(lamp)
	return root
