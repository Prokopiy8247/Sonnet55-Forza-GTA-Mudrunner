class_name BuildingKit
extends RefCounted
## Building module library + procedural assembler. For every WorldLayout lot a building is assembled from 4 m bay modules
## (3.6 m floors, 4.8 m ground floors where the kit has them) and handed to ContentBatch as MultiMesh instances, so a whole
## city costs a few dozen draw calls.
## Modules come from the Blender kit GLBs (buildings/kit_*.glb; every part is registered as "K:<PartName>") and fall back to
## the code-built modules of ContentModules when a kit or part is missing (logged; ContentLib.fallbacks lists them).
##
## Kit conventions (lane6 kit scripts): module origin = bottom-centre of the FRONT plane, facade faces -Z, slab toward +Z,
## 4 m bays. Each facade row ends with a Corner_Out module on its +X end (L pier covering the building corner).

const BAY := 4.0
const FH := 3.6

## LOD distances (m): bodies stay until `NEAR_END`, the far-LOD box fades in from `FAR_BEGIN`; small details vanish at DETAIL_END.
const NEAR_END := 270.0
const FAR_BEGIN := 225.0
const DETAIL_END := 115.0

const KIT_FILES: Array[String] = ["buildings/kit_office", "buildings/kit_apartment", "buildings/kit_shop", "buildings/kit_industrial", "buildings/kit_roof"]

static var _lib_ready := false
static var stats := {"buildings": 0, "modules": 0, "kinds": {}}
static var towers: Array = []        # [{lot, pos, roof_y, w, d, floors, kind, yaw}]
static var specs: Dictionary = {}    # kind -> spec dictionary (see _build_specs)
static var kit_parts_loaded := 0


static func reset() -> void:
	_lib_ready = false
	stats = {"buildings": 0, "modules": 0, "kinds": {}}
	towers.clear()
	specs.clear()
	kit_parts_loaded = 0


static func ensure_library() -> void:
	if _lib_ready:
		return
	_lib_ready = true
	var table := {
		&"office_win": ContentModules.office_win, &"office_glass": ContentModules.office_glass, &"office_door": ContentModules.office_door,
		&"apt_win": ContentModules.apt_win, &"apt_win2": ContentModules.apt_win2, &"apt_balc": ContentModules.apt_balc, &"apt_door": ContentModules.apt_door,
		&"shop_win": ContentModules.shop_win, &"shop_door": ContentModules.shop_door, &"awning": ContentModules.awning,
		&"sign_blade": ContentModules.sign_blade, &"roof_sign": ContentModules.roof_sign, &"cap": ContentModules.cap, &"solid": ContentModules.solid,
		&"roof_slab": ContentModules.roof_slab, &"roof_ac": ContentModules.roof_ac, &"roof_tank": ContentModules.roof_tank,
		&"roof_antenna": ContentModules.roof_antenna, &"roof_stairs": ContentModules.roof_stairs, &"roof_vent": ContentModules.roof_vent,
		&"helipad": ContentModules.helipad, &"ind_bay": ContentModules.ind_bay, &"ind_door": ContentModules.ind_door, &"ind_cap": ContentModules.ind_cap,
		&"gable": ContentModules.gable_unit, &"arch": ContentModules.arch_unit, &"chimney": ContentModules.chimney_stack, &"silo": ContentModules.silo,
		&"tank": ContentModules.storage_tank, &"hangar_door": ContentModules.hangar_door, &"park_bay": ContentModules.park_bay,
	}
	var mats := ContentLib._default_materials()
	# helper geometry without a Blender counterpart is "code" (not a missing-asset fallback)
	var code_keys := [&"roof_slab", &"gable", &"arch", &"chimney", &"hangar_door", &"park_bay", &"ind_cap", &"helipad"]
	for key in table:
		var cm: ContentMesh = (table[key] as Callable).call()
		ContentLib.put(key, cm.to_mesh(mats), "code" if key in code_keys else "fallback")
	ContentLib.put(&"ind_bay_hi", ContentModules.ind_bay(true).to_mesh(mats), "fallback")
	ContentLib.put(&"post", ContentModules.unit_box(&"WallD").to_mesh(mats), "code")
	ContentLib.put(&"core", ContentModules.unit_box(&"WallA").to_mesh(mats), "code")
	ContentLib.put(&"deck", ContentModules.unit_box(&"WallD").to_mesh(mats), "code")
	ContentLib.put(&"far_box", _far_box_mesh(), "code")
	ContentLib.put(&"shadow_box", ContentLib.get_mesh(&"far_box"), "code")
	_register_kits()
	# complete houses: Blender GLB (bld_house_a..d) when present, code-built variants otherwise
	var letters := ["a", "b", "c", "d"]
	for i in 4:
		var idx := i
		ContentLib.register_glb_or(StringName("house_" + letters[i]), "buildings/bld_house_" + letters[i], func(): return ContentModules.house(idx))
	ContentLib.register_glb_optional(&"bld_duplex", "buildings/bld_duplex")
	ContentLib.register_glb_optional(&"bld_warehouse_a", "buildings/warehouse_a")
	ContentLib.register_glb_optional(&"bld_warehouse_b", "buildings/warehouse_b")
	ContentLib.register_glb_optional(&"bld_apartment_small", "buildings/bld_apartment_small")
	_build_specs()


static func _far_box_mesh() -> ArrayMesh:
	var m := ContentMesh.new()
	m.box(&"far", Vector3(0, 0.5, 0), Vector3.ONE, Color.WHITE, 8)
	return m.to_mesh({&"far": FacadeMaterials.far()})


## Registers every part of every kit GLB as "K:<PartName>" (module-local space, origin convention preserved).
static func _register_kits() -> void:
	for rel in KIT_FILES:
		if not ModelLib.exists(rel):
			push_warning("BuildingKit: kit %s missing - code-built modules are used instead" % rel)
			continue
		var parts := ContentLib.kit_parts(rel)
		for nm in parts:
			ContentLib.put(StringName("K:" + String(nm)), parts[nm], "glb:%s#%s" % [rel, nm])
			kit_parts_loaded += 1
		ContentLib.glb_loaded.append(rel)


static func _k(part: String, fallback: StringName) -> StringName:
	var key := StringName("K:" + part)
	return key if ContentLib.has_mesh(key) else fallback


static func _has(part: String) -> bool:
	return ContentLib.has_mesh(StringName("K:" + part))


static func _height_of(key: StringName, default_h: float) -> float:
	var bb: AABB = ContentLib.aabbs.get(key, AABB())
	return default_h if bb.size.y < 0.1 else bb.end.y


## Per-family spec: which module is used where. Falls back to the code-built keys part by part.
static func _build_specs() -> void:
	specs.clear()
	specs[&"office"] = {
		"gf": 4.8 if _has("Office_Bay_Ground_Lobby") else FH,
		"door": _k("Office_Bay_Ground_Lobby", &"office_door"),
		"ground": [_k("Office_Bay_Ground_Window", &"office_glass"), _k("Office_Podium_Base", &"office_glass")],
		"upper_a": _k("Office_Bay_Window", &"office_win"),
		"upper_b": _k("Office_Bay_Spandrel_Stripe", &"office_glass"),
		"solid": _k("Office_Bay_Solid", &"solid"),
		"corner": _k("Office_Corner_Out", &""),
		"cap": _k("Office_Cornice", &"cap"),
		"crown": _k("Office_Crown_A", &""),
		"pilaster": _k("Office_Pilaster", &""),
		"balcony": &"", "awning": [], "sign": &"",
	}
	specs[&"apartment"] = {
		"gf": 4.8 if _has("Apt_Bay_Door_Stoop") else FH,
		"door": _k("Apt_Bay_Door_Stoop", &"apt_door"),
		"ground": [_k("Apt_Bay_Shop_Ground", &"apt_win")],
		"upper_a": _k("Apt_Bay_Window", &"apt_win"),
		"upper_b": _k("Apt_Bay_Window", &"apt_win2"),
		"solid": _k("Apt_Bay_Solid", &"solid"),
		"corner": _k("Apt_Corner_Out", &""),
		"cap": _k("Apt_Cornice", &"cap"),
		"crown": &"", "pilaster": &"",
		"balcony": _k("Apt_Bay_Balcony", &"apt_balc"),
		"fire_escape": _k("Apt_FireEscape_Bay", &""),
		"awning": [], "sign": &"",
	}
	specs[&"shop"] = {
		"gf": FH,
		"door": _k("Shop_Front_Door", &"shop_door"),
		"ground": [_k("Shop_Front_Glass", &"shop_win")],
		"upper_a": _k("Shop_Upper_Window", &"apt_win"),
		"upper_b": _k("Shop_Upper_Window", &"apt_win2"),
		"solid": _k("Apt_Bay_Solid", &"solid"),
		"corner": _k("Shop_Corner", &""),
		"cap": _k("Shop_Parapet", &"cap"),
		"crown": &"", "pilaster": &"", "balcony": &"",
		"awning": [_k("Shop_Awning_A", &"awning"), _k("Shop_Awning_B", &"awning")],
		"sign": _k("Shop_Sign_Board", &""),
		"blade": _k("Shop_Sign_Blade", &"sign_blade"),
	}
	for kk in [&"office", &"apartment"]:
		specs[kk]["blade"] = _k("Shop_Sign_Blade", &"sign_blade")
	specs[&"industrial"] = {
		"ih": 6.0 if _has("Ind_Wall_Corrugated") else 4.5,
		"wall": _k("Ind_Wall_Corrugated", &"ind_bay"),
		"band": _k("Ind_Wall_Windows_Band", &"ind_bay_hi"),
		"roller": _k("Ind_Door_Roller", &"ind_door"),
		"man": _k("Ind_Door_Man", &"ind_door"),
		"dock": _k("Ind_Loading_Dock", &"ind_door"),
		"corner": _k("Ind_Corner", &""),
		"cap": &"ind_cap",
	}


static func configure_lod(batch: ContentBatch) -> void:
	for key in ContentLib.meshes:
		var s := String(key)
		if key == &"far_box":
			batch.set_lod(key, FAR_BEGIN, 0.0, 30.0, false)
		elif key == &"shadow_box":
			batch.set_lod(key, 0.0, 0.0, 0.0, 2)
		elif s.begins_with("K:Roof_") or s.begins_with("K:Shop_Awning") or s.begins_with("K:Shop_Sign") or s.begins_with("K:Apt_FireEscape") \
				or key in [&"awning", &"sign_blade", &"roof_ac", &"roof_tank", &"roof_antenna", &"roof_stairs", &"roof_vent", &"roof_sign"]:
			batch.set_lod(key, 0.0, DETAIL_END, 20.0, false)
		else:
			batch.set_lod(key, 0.0, NEAR_END, 30.0, false)
	for hk in [&"K:Roof_Helipad_Pad", &"helipad"]:
		batch.set_lod(hk, 0.0, 0.0, 0.0, true)


# ---- helpers ------------------------------------------------------------------------------------------------------------
static func _c(pal: int, bright: float, bseed: float, irand: float) -> Color:
	return Color(float(pal + 1), bright, bseed, irand)


static func _ground(c: Vector2, w: float, d: float) -> Vector2:
	var lo := 1000.0
	var hi := -1000.0
	for o in [Vector2.ZERO, Vector2(w, d) * 0.5, Vector2(-w, d) * 0.5, Vector2(w, -d) * 0.5, Vector2(-w, -d) * 0.5]:
		var h := WorldLayout.terrain_height(c.x + o.x * 0.9, c.y + o.y * 0.9)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return Vector2(lo, hi)


static func _frame(lot: Dictionary) -> Dictionary:
	var rect: Rect2 = lot["rect"]
	var yaw := float(lot.get("yaw", 0.0))
	var c: Vector2 = rect.get_center()
	var swap := absf(sin(yaw)) > 0.7071
	var w := rect.size.y if swap else rect.size.x
	var d := rect.size.x if swap else rect.size.y
	var g := _ground(c, rect.size.x, rect.size.y)
	var root := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, g.x, c.y))
	return {"root": root, "w": w, "d": d, "y0": g.x, "yhi": g.y, "yaw": yaw, "c": c}


static func _count(kind: StringName) -> void:
	stats["buildings"] += 1
	var k: Dictionary = stats["kinds"]
	k[kind] = int(k.get(kind, 0)) + 1


static func _add(batch: ContentBatch, key: StringName, root: Transform3D, local: Transform3D, custom: Color) -> void:
	batch.add(key, root * local, custom)
	stats["modules"] += 1


## Far-LOD box (visible beyond FAR_BEGIN, includes the parapet) + shadows-only box (casts the building's shadow; the detailed
## modules cast none, which keeps the shadow passes down to one draw call per sector).
static func _far(batch: ContentBatch, root: Transform3D, pos: Vector3, w: float, h: float, d: float, custom: Color, parapet := 0.9) -> void:
	batch.add(&"far_box", root * _scaled(0.0, w, h + parapet, d, pos), custom)
	batch.add(&"shadow_box", root * _scaled(0.0, w, maxf(h - 0.05, 0.5), d, pos), custom)


static func _scaled(rot: float, sx: float, sy: float, sz: float, pos: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot) * Basis.from_scale(Vector3(sx, sy, sz)), pos)


## Foundation skirt when the lot sits on a slope (hides the gap between terrain and building).
static func _plinth(batch: ContentBatch, f: Dictionary, w: float, d: float, pal: int, bseed: float) -> void:
	var slope: float = float(f["yhi"]) - float(f["y0"])
	if slope < 0.25:
		return
	var root: Transform3D = f["root"]
	var h := slope + 0.6
	batch.add(&"post", root * _scaled(0.0, w, h, d, Vector3(0, -h + 0.25, 0)), _c(pal, 0.4, bseed, 0.5))


static func _floor_y(fl: int, gf: float) -> float:
	return 0.0 if fl <= 0 else gf + float(fl - 1) * FH


## Chooses the bay module of one wall cell. st: per-building style (see build_block).
static func _bay_key(spec: Dictionary, kind: StringName, fl: int, facade: int, i: int, n: int, st: Dictionary, rng: RandomNumberGenerator) -> StringName:
	if fl == 0:
		if facade == 0 and i == n / 2:
			return spec["door"]
		var g: Array = spec["ground"]
		if kind == &"shop" and facade == 0 and n > 4 and i == 1:
			return spec["door"]
		return g[(i + facade) % g.size()] if kind == &"office" else g[0]
	var a: StringName = spec["upper_a"]
	var b: StringName = spec["upper_b"]
	match kind:
		&"office":
			var band := (fl % 5 == 0)
			if rng.randf() < 0.07:
				return spec["solid"]
			return (b if (st["glass"] != band) else a)
		&"apartment":
			var bal: StringName = spec["balcony"]
			if fl >= 1 and (facade == 0 or facade == 1) and fl % 2 == 1 and st["balconies"] and i % 2 == 1 and bal != &"":
				return bal
			if facade == 1 and st["fire_escape_bay"] == i and spec.get("fire_escape", &"") != &"":
				return spec["fire_escape"]
			if rng.randf() < 0.08:
				return spec["solid"]
			return a if rng.randf() < 0.75 else b
		_:
			return a if rng.randf() < 0.8 else b


static func _pick_weighted(list: Array, rng: RandomNumberGenerator) -> StringName:
	var total := 0.0
	for e in list:
		total += float(e[1])
	var r := rng.randf() * total
	for e in list:
		r -= float(e[1])
		if r <= 0.0:
			return e[0]
	return list[list.size() - 1][0]


## Rows of bay modules around one tier of a building. All positions are in the building's local frame.
static func _tier(batch: ContentBatch, root: Transform3D, spec: Dictionary, kind: StringName, tw: float, td: float, f0: int, f1: int,
		pal: int, bseed: float, bright: float, st: Dictionary, rng: RandomNumberGenerator, cap_key: StringName, crown_key: StringName = &"") -> void:
	var gf: float = spec["gf"]
	var nw := maxi(2, int(round(tw / BAY)))
	var nd := maxi(2, int(round(td / BAY)))
	var bw := tw / nw
	var bd := td / nd
	var rows := [
		[0, 0.0, Vector3(-tw * 0.5 + bw * 0.5, 0, -td * 0.5), Vector3(bw, 0, 0), nw, bw / BAY],
		[1, PI, Vector3(tw * 0.5 - bw * 0.5, 0, td * 0.5), Vector3(-bw, 0, 0), nw, bw / BAY],
		[2, PI * 0.5, Vector3(-tw * 0.5, 0, td * 0.5 - bd * 0.5), Vector3(0, 0, -bd), nd, bd / BAY],
		[3, -PI * 0.5, Vector3(tw * 0.5, 0, -td * 0.5 + bd * 0.5), Vector3(0, 0, bd), nd, bd / BAY],
	]
	var corner: StringName = spec["corner"]
	var awnings: Array = spec["awning"]
	var sign_key: StringName = spec.get("sign", &"")
	var pilaster: StringName = spec["pilaster"]
	for row in rows:
		var facade: int = row[0]
		var rot: float = row[1]
		var p0: Vector3 = row[2]
		var step: Vector3 = row[3]
		var n: int = row[4]
		var sx: float = row[5]
		for fl in range(f0, f1):
			var y := _floor_y(fl, gf)
			for i in n:
				var key: StringName
				if fl >= 1 and corner != &"" and i == n - 1:
					key = corner
				else:
					key = _bay_key(spec, kind, fl, facade, i, n, st, rng)
				var pos := p0 + step * i + Vector3(0, y, 0)
				var xf := _scaled(rot, sx, 1.0, 1.0, pos)
				var irand := rng.randf()
				_add(batch, key, root, xf, _c(pal, bright, bseed, irand))
				if fl == 0 and facade == 0 and kind == &"shop":
					if not awnings.is_empty() and st["awnings"] and key != corner:
						_add(batch, awnings[(i + st["awning_off"]) % awnings.size()], root, xf, _c(pal, bright, bseed, irand))
					if sign_key != &"" and st["signs"] and i % 2 == 0:
						_add(batch, sign_key, root, xf, _c(pal, bright, bseed, irand))
				if fl == 0 and facade == 0 and st["blades"] and (i == 0 or i == n - 1):
					var side := 1.7 if i == 0 else -1.7
					var bx := Transform3D(Basis(Vector3.UP, rot), pos + Basis(Vector3.UP, rot) * Vector3(side, 0, 0))
					_add(batch, spec.get("blade", &"sign_blade"), root, bx, _c(pal, bright, bseed, irand))
				if fl >= 1 and pilaster != &"" and st["pilasters"] and i > 0 and facade <= 1 and fl < f0 + 3:
					var px := Transform3D(Basis(Vector3.UP, rot), pos + Basis(Vector3.UP, rot) * Vector3(-2.0 * sx, 0, 0))
					_add(batch, pilaster, root, px, _c(pal, bright, bseed, irand))
		# cornice / crown along the top
		var ytop := _floor_y(f1, gf)
		for i in n:
			var pos2 := p0 + step * i + Vector3(0, ytop, 0)
			_add(batch, cap_key, root, _scaled(rot, sx, 1.0, 1.0, pos2), _c(pal, bright, bseed, 0.5))
			if crown_key != &"":
				_add(batch, crown_key, root, _scaled(rot, sx, 1.0, 1.0, pos2 + Vector3(0, 1.45, 0)), _c(pal, bright, bseed, 0.5))
	# solid core behind the open-shell facade modules (nothing to see through at corners / glass reveals)
	var ybot_core := _floor_y(f0, gf)
	var ytop_core := ytop_of(spec, f1)
	_add(batch, &"core", root, _scaled(0.0, tw - 0.8, ytop_core - ybot_core + 0.2, td - 0.8, Vector3(0, ybot_core, 0)), _c(pal, bright, bseed, 0.5))
	# corner posts (cover the notch where two facades meet); with kit corner modules only the ground floor needs them
	var th := (ytop_of(spec, f1) - _floor_y(f0, gf)) + 1.2
	if corner != &"" and f0 == 0:
		th = gf + 0.2
	if corner != &"" and f0 > 0:
		th = 0.0
	if th > 0.0:
		for sx_ in [-1.0, 1.0]:
			for sz_ in [-1.0, 1.0]:
				var cp := Vector3(sx_ * (tw * 0.5 - 0.11), _floor_y(f0, gf), sz_ * (td * 0.5 - 0.11))
				_add(batch, &"post", root, _scaled(0.0, 0.5, th, 0.5, cp), _c(pal, bright, bseed, 0.5))


static func ytop_of(spec: Dictionary, f1: int) -> float:
	return _floor_y(f1, float(spec["gf"]))


static func build_block(batch: ContentBatch, lot: Dictionary, rng: RandomNumberGenerator, host_helipad: bool) -> void:
	var kind: StringName = lot.get("kind", &"office")
	var f := _frame(lot)
	var w: float = f["w"] - 1.0
	var d: float = f["d"] - 1.0
	if w < 7.5 or d < 7.5:
		return
	var spec: Dictionary = specs[kind]
	var gf: float = spec["gf"]
	var root: Transform3D = f["root"]
	var pal := clampi(int(lot.get("palette", 0)), 0, 3)
	if kind == &"apartment" and int(lot.get("floors", 4)) <= 4 and f["w"] >= 23.0 and f["d"] >= 20.0 and ContentLib.has_mesh(&"bld_apartment_small") and rng.randf() < 0.35:
		_place_complete(batch, lot, f, &"bld_apartment_small", rng, &"apartment")
		return
	var floors := int(lot.get("floors", 0))
	if floors <= 0:
		floors = maxi(1, int(round(float(lot.get("height", 10.8)) / FH)))
	floors = clampi(floors, 1, 40)
	var bseed := rng.randf()
	var bright := rng.randf()
	var nw := maxi(2, int(round(w / BAY)))
	var nd := maxi(2, int(round(d / BAY)))
	var st := {
		"glass": rng.randf() < 0.5, "balconies": rng.randf() < 0.8, "awnings": rng.randf() < 0.85, "awning_off": rng.randi() % 2,
		"signs": rng.randf() < 0.7, "blades": rng.randf() < 0.4, "pilasters": kind == &"office" and rng.randf() < 0.35,
		"fire_escape_bay": rng.randi() % maxi(nw, 1),
	}
	_count(kind)
	_plinth(batch, f, w, d, pal, bseed)
	var tw := float(nw) * BAY * clampf(w / (nw * BAY), 0.75, 1.25)
	var td := float(nd) * BAY * clampf(d / (nd * BAY), 0.75, 1.25)
	# optional set-back crown for tall towers
	var tiers: Array = [[0, floors, tw, td]]
	if floors >= 9 and nw >= 5 and nd >= 5:
		var crown := 2 + (1 if floors > 14 else 0)
		tiers = [[0, floors - crown, tw, td], [floors - crown, floors, tw - 2.0 * BAY, td - 2.0 * BAY]]
	elif floors >= 6 and nw >= 4 and nd >= 4 and rng.randf() < 0.35:
		tiers = [[0, floors - 1, tw, td], [floors - 1, floors, tw - 2.0 * BAY, td - 2.0 * BAY]]
	var style_code := 0 if kind == &"office" else 1
	var crown_key: StringName = spec["crown"]
	var top_idx := tiers.size() - 1
	var roof_y := 0.0
	var plateau_w := 0.0
	var plateau_d := 0.0
	for t in tiers.size():
		var fl0: int = tiers[t][0]
		var fl1: int = tiers[t][1]
		var ttw: float = tiers[t][2]
		var ttd: float = tiers[t][3]
		var is_top := t == top_idx
		var use_crown := is_top and crown_key != &"" and floors >= 9 and ttw >= 11.0 and ttd >= 11.0 and not host_helipad
		var cap_key: StringName = spec["cap"]
		_tier(batch, root, spec, kind, ttw, ttd, fl0, fl1, pal, bseed, bright, st, rng, cap_key, crown_key if use_crown else &"")
		var y_bot := _floor_y(fl0, gf)
		var y_top := _floor_y(fl1, gf)
		var height := y_top - y_bot
		batch.add_box_collider(root * Transform3D(Basis.IDENTITY, Vector3(0, y_bot + height * 0.5, 0)), Vector3(ttw, height + 1.0, ttd), &"concrete")
		_far(batch, root, Vector3(0, y_bot, 0), ttw - 0.4, height, ttd - 0.4, Color(float(pal + 1), bright, bseed, float(style_code + (8 if fl0 > 0 else 0))))
		# roof deck of this tier
		var deck_y := y_top + 0.04
		var inset := 0.4
		if use_crown:
			deck_y = y_top + 1.45 + 3.2
			inset = 5.6
		_add(batch, &"roof_slab", root, _scaled(0.0, ttw - inset, 1.0, ttd - inset, Vector3(0, deck_y, 0)), _c(pal, bright, bseed, 0.5))
		if is_top:
			roof_y = deck_y
			plateau_w = ttw - (5.6 if use_crown else 1.0)
			plateau_d = ttd - (5.6 if use_crown else 1.0)
	_roof_props(batch, root, f, kind, plateau_w, plateau_d, roof_y, floors, pal, bseed, bright, rng, host_helipad)
	towers.append({"lot": int(lot.get("id", -1)), "pos": Vector3(f["c"].x, f["y0"] + roof_y, f["c"].y), "roof_y": f["y0"] + roof_y, "w": plateau_w, "d": plateau_d, "floors": floors, "kind": kind, "yaw": f["yaw"]})


const ROOF_PROPS := [
	["K:Roof_AC_A", &"roof_ac", 5.0], ["K:Roof_AC_B", &"roof_ac", 2.0], ["K:Roof_Tank", &"roof_tank", 1.5], ["K:Roof_Vent_Row", &"roof_vent", 2.0],
	["K:Roof_Solar_Panels", &"roof_ac", 1.2], ["K:Roof_Stairs_Box", &"roof_stairs", 1.5], ["K:Roof_Antenna_A", &"roof_antenna", 1.2], ["K:Roof_Antenna_B", &"roof_antenna", 0.8],
]


static func _prop(entry: Array) -> StringName:
	var kk := StringName(entry[0])
	return kk if ContentLib.has_mesh(kk) else StringName(entry[1])


static func _prop_radius(key: StringName) -> float:
	var bb: AABB = ContentLib.aabbs.get(key, AABB(Vector3.ZERO, Vector3(2, 1, 2)))
	return maxf(bb.size.x, bb.size.z) * 0.5


static func _roof_props(batch: ContentBatch, root: Transform3D, f: Dictionary, kind: StringName, tw: float, td: float, roof_y: float,
		floors: int, pal: int, bseed: float, bright: float, rng: RandomNumberGenerator, host_helipad: bool) -> void:
	var y := roof_y + 0.02
	if host_helipad:
		var hk: StringName = &"K:Roof_Helipad_Pad" if ContentLib.has_mesh(&"K:Roof_Helipad_Pad") else &"helipad"
		var native := 12.0 if hk == &"K:Roof_Helipad_Pad" else 19.0
		var sc := clampf(minf(tw, td) / (native + 1.5), 0.5, 1.0)
		batch.add(hk, root * Transform3D(Basis.from_scale(Vector3(sc, 1.0, sc)), Vector3(0, y, 0)), _c(pal, 0.5, bseed, 0.5))
		for sx_ in [-1.0, 1.0]:
			var ak: StringName = &"K:Roof_Antenna_A" if ContentLib.has_mesh(&"K:Roof_Antenna_A") else &"roof_antenna"
			_add(batch, ak, root, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(sx_ * (tw * 0.5 - 1.2), y, td * 0.5 - 1.2)), _c(pal, bright, bseed, rng.randf()))
		return
	var hx := tw * 0.5 - 2.0
	var hz := td * 0.5 - 2.0
	if hx < 1.0 or hz < 1.0:
		return
	var n_props := 2 + int(rng.randf() * mini(4, int(tw * td / 60.0)))
	var placed: Array[Vector3] = []
	var tries := 0
	while placed.size() < n_props and tries < 30:
		tries += 1
		var entry: Array = ROOF_PROPS[rng.randi() % ROOF_PROPS.size()]
		var key := _prop(entry)
		if float(entry[2]) < rng.randf() * 5.0:
			continue
		if (key == &"K:Roof_Stairs_Box" or key == &"roof_stairs") and (floors < 3 or tw < 8.0):
			continue
		var r := _prop_radius(key)
		if r > minf(hx, hz) * 0.9:
			continue
		var p := Vector3(rng.randf_range(-hx + r * 0.5, hx - r * 0.5), y, rng.randf_range(-hz + r * 0.5, hz - r * 0.5))
		var ok := true
		for q in placed:
			if absf(q.x - p.x) < r + 1.8 and absf(q.z - p.z) < r + 1.8:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		_add(batch, key, root, Transform3D(Basis(Vector3.UP, float(rng.randi() % 4) * PI * 0.5), p), _c(pal, bright, bseed, rng.randf()))
	if (kind == &"shop" or kind == &"office") and rng.randf() < 0.3 and tw > 9.0:
		var bk: StringName = &"K:Roof_Billboard_Frame" if ContentLib.has_mesh(&"K:Roof_Billboard_Frame") else &"roof_sign"
		_add(batch, bk, root, Transform3D(Basis.IDENTITY, Vector3(0, y, -td * 0.5 + 1.2)), _c(pal, bright, bseed, rng.randf()))


# ---- Houses ----------------------------------------------------------------------------------------------------------------
static func build_house(batch: ContentBatch, lot: Dictionary, rng: RandomNumberGenerator) -> void:
	var f := _frame(lot)
	var w: float = f["w"]
	var d: float = f["d"]
	if w < 6.0 or d < 6.0:
		return
	var letters := ["a", "b", "c", "d"]
	var key := StringName("house_" + letters[rng.randi() % 4])
	if ContentLib.has_mesh(&"bld_duplex") and w >= 17.0 and d >= 14.0 and rng.randf() < 0.3:
		key = &"bld_duplex"
	_place_complete(batch, lot, f, key, rng, &"house")


## Places one complete GLB building (houses, duplex, small apartment block) centred in its lot, toward the back so a yard remains in front.
static func _place_complete(batch: ContentBatch, lot: Dictionary, f: Dictionary, key: StringName, rng: RandomNumberGenerator, kind: StringName) -> void:
	var w: float = f["w"]
	var d: float = f["d"]
	var root: Transform3D = f["root"]
	var bb: AABB = ContentLib.aabbs.get(key, AABB(Vector3(-4, 0, -4), Vector3(8, 6, 8)))
	var s := clampf(minf((w - 1.5) / maxf(bb.size.x, 1.0), (d - 2.0) / maxf(bb.size.z, 1.0)), 0.8, 1.35)
	var pal := clampi(int(lot.get("palette", 0)), 0, 3)
	var bseed := rng.randf()
	var bright := rng.randf()
	_count(kind)
	var slack := d - bb.size.z * s
	var cz := slack * 0.22
	var cx := -(bb.position.x + bb.size.x * 0.5) * s
	cz += -(bb.position.z + bb.size.z * 0.5) * s
	var xf := Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(cx, 0, cz))
	_add(batch, key, root, xf, _c(pal, bright, bseed, rng.randf()))
	_plinth(batch, f, bb.size.x * s, bb.size.z * s, pal, bseed)
	batch.add_box_collider(root * Transform3D(Basis.IDENTITY, Vector3(0, bb.size.y * s * 0.5, cz)), Vector3(bb.size.x * s * 0.98, bb.size.y * s, bb.size.z * s * 0.98), &"concrete")
	var far_h := bb.size.y * s
	_far(batch, root, Vector3(0, 0, cz), bb.size.x * s - 0.4, far_h - 0.4, bb.size.z * s - 0.4, Color(float(pal + 1), bright, bseed, 3.0), 0.0)


# ---- Industrial ---------------------------------------------------------------------------------------------------------------
static func _ind_tier(batch: ContentBatch, root: Transform3D, spec: Dictionary, tw: float, td: float, rows_n: int, pal: int, bseed: float, bright: float,
		door_pat: Dictionary, rng: RandomNumberGenerator, skip_front_center: float = 0.0) -> void:
	var ih: float = spec["ih"]
	var nw := maxi(2, int(round(tw / BAY)))
	var nd := maxi(2, int(round(td / BAY)))
	var bw := tw / nw
	var bd := td / nd
	var corner: StringName = spec["corner"]
	var rows := [
		[0, 0.0, Vector3(-tw * 0.5 + bw * 0.5, 0, -td * 0.5), Vector3(bw, 0, 0), nw, bw / BAY],
		[1, PI, Vector3(tw * 0.5 - bw * 0.5, 0, td * 0.5), Vector3(-bw, 0, 0), nw, bw / BAY],
		[2, PI * 0.5, Vector3(-tw * 0.5, 0, td * 0.5 - bd * 0.5), Vector3(0, 0, -bd), nd, bd / BAY],
		[3, -PI * 0.5, Vector3(tw * 0.5, 0, -td * 0.5 + bd * 0.5), Vector3(0, 0, bd), nd, bd / BAY],
	]
	for row in rows:
		var facade: int = row[0]
		var rot: float = row[1]
		var p0: Vector3 = row[2]
		var step: Vector3 = row[3]
		var n: int = row[4]
		var sx: float = row[5]
		for r in rows_n:
			for i in n:
				var pos := p0 + step * i + Vector3(0, r * ih, 0)
				if facade == 0 and r == 0 and skip_front_center > 0.0 and absf(pos.x) < skip_front_center:
					continue
				var key: StringName = spec["wall"]
				if r == rows_n - 1 and rng.randf() < 0.55:
					key = spec["band"]
				if facade == 0 and r == 0 and door_pat.has(i):
					key = spec["roller"] if (i + door_pat.size()) % 3 != 0 else spec["dock"]
				elif facade == 2 and r == 0 and i == n / 2 and rng.randf() < 0.6:
					key = spec["man"]
				if corner != &"" and i == n - 1:
					key = corner
				_add(batch, key, root, _scaled(rot, sx, 1.0, 1.0, pos), _c(pal, bright, bseed, rng.randf()))
	if corner == &"":
		var th := rows_n * ih + 0.5
		for sx_ in [-1.0, 1.0]:
			for sz_ in [-1.0, 1.0]:
				_add(batch, &"post", root, _scaled(0.0, 0.45, th, 0.45, Vector3(sx_ * (tw * 0.5 - 0.1), 0, sz_ * (td * 0.5 - 0.1))), _c(pal, bright, bseed, 0.5))


static func build_industrial(batch: ContentBatch, lot: Dictionary, rng: RandomNumberGenerator) -> void:
	var kind: StringName = lot.get("kind", &"warehouse")
	var f := _frame(lot)
	var w: float = f["w"] - 1.0
	var d: float = f["d"] - 1.0
	if w < 10.0 or d < 10.0:
		return
	var spec: Dictionary = specs[&"industrial"]
	var ih: float = spec["ih"]
	var root: Transform3D = f["root"]
	var pal := clampi(int(lot.get("palette", 3)), 0, 3)
	if kind == &"warehouse" and rng.randf() < 0.5:
		# complete Blender warehouse when the lot is big enough
		for wk in [&"bld_warehouse_a", &"bld_warehouse_b"]:
			var wbb: AABB = ContentLib.aabbs.get(wk, AABB())
			if ContentLib.has_mesh(wk) and w >= wbb.size.x * 0.95 and d >= wbb.size.z * 0.95:
				_place_complete(batch, lot, f, wk, rng, &"warehouse")
				return
	var bseed := rng.randf()
	var bright := rng.randf()
	_count(kind)
	var height := float(lot.get("height", 9.0))
	var rows_n := clampi(int(height / ih + 0.35), 1, 3)
	var yard := 0.0
	if kind == &"factory" and d > 30.0:
		yard = minf(12.0, d * 0.3)
	var td := (d - yard)
	var nw := maxi(2, int(round(w / BAY)))
	var nd := maxi(2, int(round(td / BAY)))
	var tw := float(nw) * BAY * clampf(w / (nw * BAY), 0.8, 1.2)
	var tdd := float(nd) * BAY * clampf(td / (nd * BAY), 0.8, 1.2)
	var body_z := yard * 0.5   # body sits toward the back (+Z), yard in front
	var body_root := root * Transform3D(Basis.IDENTITY, Vector3(0, 0, body_z))
	var doors := {}
	var n_doors := clampi(int(tw / 14.0), 1, 4)
	for k in n_doors:
		doors[clampi(int((k + 0.5) / n_doors * nw), 0, nw - 1)] = true
	_plinth(batch, f, tw, tdd, pal, bseed)
	_ind_tier(batch, body_root, spec, tw, tdd, rows_n, pal, bseed, bright, doors, rng)
	var top := rows_n * ih
	var ridge_x := tw >= tdd
	var rise := clampf(minf(tw, tdd) * 0.12, 1.4, 3.4)
	var saw: StringName = &"K:Ind_Roof_Sawtooth_Bay"
	if ContentLib.has_mesh(saw):
		# sawtooth roof bays: 4 m wide x 12 m deep, eave line at the front edge of each row
		var n_rows := maxi(1, int(round(tdd / 12.0)))
		var sz := tdd / n_rows
		var bwr := tw / nw
		_add(batch, &"roof_slab", body_root, _scaled(0.0, tw, 1.0, tdd, Vector3(0, top + 0.02, 0)), _c(pal, bright, bseed, 0.5))
		for r in n_rows:
			for i in nw:
				var sp := Vector3(-tw * 0.5 + bwr * 0.5 + i * bwr, top, -tdd * 0.5 + r * sz)
				_add(batch, saw, body_root, Transform3D(Basis.from_scale(Vector3(bwr / BAY, 1.0, sz / 12.0)), sp), _c(pal, bright, bseed, rng.randf()))
		rise = 1.9
	else:
		var gable_xf := Transform3D(Basis(Vector3.UP, 0.0 if ridge_x else PI * 0.5) * Basis.from_scale(Vector3((tw + 0.8) if ridge_x else (tdd + 0.8), rise, (tdd + 0.8) if ridge_x else (tw + 0.8))), Vector3(0, top + 0.05, 0))
		_add(batch, &"gable", body_root, gable_xf, _c(pal, bright, bseed, 0.5))
	batch.add_box_collider(root * Transform3D(Basis.IDENTITY, Vector3(0, top * 0.5 + rise * 0.3, body_z)), Vector3(tw, top + rise * 0.6, tdd), &"concrete")
	_far(batch, root, Vector3(0, 0, body_z), tw - 0.4, top + rise * 0.5, tdd - 0.4, Color(float(pal + 1), bright, bseed, 2.0), 0.0)
	if kind == &"factory":
		var cx := tw * 0.5 - 3.5
		_add(batch, &"chimney", body_root, Transform3D(Basis.IDENTITY, Vector3(cx, 0.0, -tdd * 0.5 - 2.5)), _c(pal, bright, bseed, 0.5))
		batch.add_cyl_collider((root * Transform3D(Basis.IDENTITY, Vector3(cx, 0, body_z - tdd * 0.5 - 2.5))).origin, 1.6, 22.0, &"concrete")
		var tank_x := cx - 8.5
		var sk: StringName = &"K:Ind_Silo_Small" if ContentLib.has_mesh(&"K:Ind_Silo_Small") else &"silo"
		var i := 0
		while -tw * 0.5 + 5.0 + i * 6.0 < tank_x - 6.0 and i < 3:
			var sp := Vector3(-tw * 0.5 + 5.0 + i * 6.0, 0.0, -tdd * 0.5 - 3.5)
			_add(batch, sk, body_root, Transform3D(Basis.IDENTITY, sp), _c(pal, bright, bseed, 0.5))
			batch.add_cyl_collider((body_root * Transform3D(Basis.IDENTITY, sp)).origin, 2.4, 9.0, &"metal")
			i += 1
		if yard > 8.0:
			var tp := Vector3(tank_x, 0.0, -tdd * 0.5 - yard * 0.45)
			var tk: StringName = &"K:Ind_Tank" if ContentLib.has_mesh(&"K:Ind_Tank") else &"tank"
			_add(batch, tk, body_root, Transform3D(Basis.IDENTITY, tp), _c(pal, bright, bseed, 0.5))
			batch.add_cyl_collider((body_root * Transform3D(Basis.IDENTITY, tp)).origin, 2.8, 6.2, &"metal")
	var rk: StringName = &"K:Roof_AC_B" if ContentLib.has_mesh(&"K:Roof_AC_B") else &"roof_ac"
	_add(batch, rk, body_root, Transform3D(Basis(Vector3.UP, 0.0), Vector3(rng.randf_range(-tw * 0.3, tw * 0.3), top + rise * 0.55, tdd * 0.05)), _c(pal, bright, bseed, 0.5))


static func build_hangar(batch: ContentBatch, lot: Dictionary, rng: RandomNumberGenerator) -> void:
	var f := _frame(lot)
	var w: float = f["w"] - 1.0
	var d: float = f["d"] - 1.0
	if w < 12.0 or d < 10.0:
		return
	var spec: Dictionary = specs[&"industrial"]
	var ih: float = spec["ih"]
	var root: Transform3D = f["root"]
	var pal := clampi(int(lot.get("palette", 3)), 0, 3)
	var bseed := rng.randf()
	var bright := rng.randf()
	_count(&"hangar")
	var rows_n := 2 if ih < 5.0 else 1
	var nw := maxi(3, int(round(w / BAY)))
	var nd := maxi(2, int(round(d / BAY)))
	var tw := float(nw) * BAY * clampf(w / (nw * BAY), 0.8, 1.2)
	var td := float(nd) * BAY * clampf(d / (nd * BAY), 0.8, 1.2)
	var door_w := tw * 0.78
	_plinth(batch, f, tw, td, pal, bseed)
	_ind_tier(batch, root, spec, tw, td, rows_n, pal, bseed, bright, {}, rng, door_w * 0.5)
	var top := rows_n * ih
	var rise := clampf(tw * 0.22, 3.0, 7.0)
	_add(batch, &"arch", root, Transform3D(Basis.from_scale(Vector3(tw + 0.6, rise, td + 0.8)), Vector3(0, top, 0)), _c(pal, bright, bseed, 0.5))
	var dh := minf(top + rise * 0.35, top + 1.0)
	_add(batch, &"hangar_door", root, Transform3D(Basis.from_scale(Vector3(door_w, dh, 1.0)), Vector3(0, 0, -td * 0.5)), _c(pal, bright, bseed, 0.5))
	batch.add_box_collider(root * Transform3D(Basis.IDENTITY, Vector3(0, top * 0.5 + rise * 0.3, 0)), Vector3(tw, top + rise * 0.6, td), &"concrete")
	_far(batch, root, Vector3.ZERO, tw - 0.4, top + rise * 0.55, td - 0.4, Color(float(pal + 1), bright, bseed, 2.0), 0.0)


# ---- Parking structure ----------------------------------------------------------------------------------------------------------
static func build_parking(batch: ContentBatch, lot: Dictionary, rng: RandomNumberGenerator) -> void:
	var f := _frame(lot)
	var w: float = f["w"] - 1.0
	var d: float = f["d"] - 1.0
	if w < 12.0 or d < 12.0:
		return
	var root: Transform3D = f["root"]
	var pal := clampi(int(lot.get("palette", 3)), 0, 3)
	var bseed := rng.randf()
	var bright := rng.randf()
	_count(&"parking")
	var floors := clampi(int(lot.get("floors", 4)), 2, 8)
	var nw := maxi(3, int(round(w / BAY)))
	var nd := maxi(3, int(round(d / BAY)))
	var tw := float(nw) * BAY
	var td := float(nd) * BAY
	var rows := [
		[0.0, Vector3(-tw * 0.5 + BAY * 0.5, 0, -td * 0.5), Vector3(BAY, 0, 0), nw],
		[PI, Vector3(tw * 0.5 - BAY * 0.5, 0, td * 0.5), Vector3(-BAY, 0, 0), nw],
		[PI * 0.5, Vector3(-tw * 0.5, 0, -td * 0.5 + BAY * 0.5), Vector3(0, 0, BAY), nd],
		[-PI * 0.5, Vector3(tw * 0.5, 0, -td * 0.5 + BAY * 0.5), Vector3(0, 0, BAY), nd],
	]
	_plinth(batch, f, tw, td, pal, bseed)
	for row in rows:
		var rot: float = row[0]
		var p0: Vector3 = row[1]
		var step: Vector3 = row[2]
		var n: int = row[3]
		for fl in floors:
			for i in n:
				_add(batch, &"park_bay", root, _scaled(rot, 1.0, 1.0, 1.0, p0 + step * i + Vector3(0, fl * FH, 0)), _c(pal, bright, bseed, 0.5))
	for fl in floors + 1:
		_add(batch, &"deck", root, _scaled(0.0, tw - 0.3, 0.32, td - 0.3, Vector3(0, fl * FH - 0.02, 0)), _c(pal, bright, bseed, 0.5))
	var gx := int(tw / 8.0)
	var gz := int(td / 8.0)
	for ix in range(1, gx):
		for iz in range(1, gz):
			_add(batch, &"post", root, _scaled(0.0, 0.5, floors * FH, 0.5, Vector3(-tw * 0.5 + ix * tw / gx, 0, -td * 0.5 + iz * td / gz)), _c(pal, bright, bseed, 0.5))
	batch.add_box_collider(root * Transform3D(Basis.IDENTITY, Vector3(0, floors * FH * 0.5, 0)), Vector3(tw, floors * FH, td), &"concrete")
	_far(batch, root, Vector3.ZERO, tw - 0.4, floors * FH, td - 0.4, Color(float(pal + 1), bright, bseed, 4.0), 0.0)


# ---- Entry ------------------------------------------------------------------------------------------------------------------------
## Picks the lot that hosts the downtown helipad (the lot containing `helipad_downtown`, else the tallest office tower).
static func pick_helipad_lot(lots: Array) -> int:
	var loc: Dictionary = WorldLayout.get_location(&"helipad_downtown")
	if not loc.is_empty():
		var p: Vector3 = loc["pos"]
		for lot in lots:
			var rect: Rect2 = lot["rect"]
			if rect.has_point(Vector2(p.x, p.z)) and lot.get("kind", &"") in [&"office", &"apartment", &"shop"]:
				return int(lot.get("id", -1))
	var best := -1
	var best_f := 0
	for lot in lots:
		if lot.get("kind", &"") == &"office":
			var fl := int(lot.get("floors", 0))
			if fl > best_f:
				best_f = fl
				best = int(lot.get("id", -1))
	return best


static func build_all(batch: ContentBatch, lots: Array) -> void:
	ensure_library()
	towers.clear()
	var heli_lot := pick_helipad_lot(lots)
	var rng := RandomNumberGenerator.new()
	for lot in lots:
		var kind: StringName = lot.get("kind", &"empty")
		rng.seed = hash(int(lot.get("id", 0)) * 7919 + 13)
		if lot.has("hero") and FillBuilder.place_hero_lot(batch, lot, rng):   # world-fill: complete Blender hero building on this lot
			continue
		match kind:
			&"office", &"apartment", &"shop":
				build_block(batch, lot, rng, int(lot.get("id", -1)) == heli_lot)
			&"house":
				build_house(batch, lot, rng)
			&"warehouse", &"factory":
				build_industrial(batch, lot, rng)
			&"hangar":
				build_hangar(batch, lot, rng)
			&"parking":
				build_parking(batch, lot, rng)
			_:
				pass
