extends Node
## Lane-6 visual check + reference assembly for the building kits (kit_office / kit_apartment / kit_shop / kit_industrial / kit_roof).
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\bk.png -GameArgs "--exec=res://gta/tests/buildings_preview.gd --cam=2012,9,1976,2000,6,2004 --delay=4"
## Placement rule (see docs/api/blender_buildings.md): a module is placed with its ORIGIN on the facade plane; its +Z-forward (Blender +Y)
## faces outward. Blender (x,y,z) -> Godot (x, z, -y). Faces: 0 front (rot 0), 1 right (-90), 2 back (180), 3 left (+90) walking clockwise.

const DIR := "res://gta/generated/models/buildings/"
const ORIGIN := Vector3(2000, 0, 2000)

var _kits := {}
var _root: Node3D


func _kit(id: String) -> Node3D:
	if not _kits.has(id):
		var ps := load(DIR + id + ".glb") as PackedScene
		_kits[id] = ps.instantiate() if ps != null else null
	return _kits[id]


## Place a duplicate of module `mod` of kit `kit`; (bx,by,bz) = Blender-style position, rz = Blender yaw (deg, CCW from above).
func place(parent: Node3D, kit: String, mod: String, bx: float, by: float, bz: float, rz: float) -> MeshInstance3D:
	var k := _kit(kit)
	if k == null:
		return null
	var src := k.find_child(mod, true, false) as MeshInstance3D
	if src == null:
		push_warning("buildings_preview: missing module %s/%s" % [kit, mod])
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	mi.name = mod
	parent.add_child(mi)
	mi.position = Vector3(bx, bz, -by)
	mi.rotation_degrees = Vector3(0, rz, 0)
	return mi


func _face_pos(face: int, i: int, w: int, d: int) -> Array:
	var hw := w * 2.0
	var hd := d * 4.0
	match face:
		0: return [-hw + 2 + 4 * i, 0.0, 0.0]
		1: return [hw, -2.0 - 4 * i, -90.0]
		2: return [hw - 2 - 4 * i, -hd, 180.0]
		_: return [-hw, -hd + 2 + 4 * i, 90.0]


func block(parent: Node3D, kit: String, w: int, d: int, floors: int, ground_h: float, ground_fn: Callable, upper_fn: Callable, cornice: String, cornice_corner: String) -> void:
	for face in 4:
		var n := w if face % 2 == 0 else d
		for i in n:
			var p := _face_pos(face, i, w, d)
			var corner := (i == n - 1)
			var g: String = ground_fn.call(face, i, corner)
			if g != "":
				place(parent, kit, g, p[0], p[1], 0.0, p[2])
			var z := ground_h
			for f in floors:
				var m: String = upper_fn.call(face, i, f, corner)
				if m != "":
					place(parent, kit, m, p[0], p[1], z, p[2])
				z += 3.6
			var c := cornice_corner if (corner and cornice_corner != "") else cornice
			if c != "":
				place(parent, kit, c, p[0], p[1], z, p[2])


func _apt_ground(face: int, i: int, _corner: bool) -> String:
	return "Apt_Bay_Door_Stoop" if (face == 0 and i == 1) else "Apt_Bay_Shop_Ground"


func _apt_upper(face: int, i: int, f: int, corner: bool) -> String:
	if corner:
		return "Apt_Corner_Out"
	if f == 1 and i == 2:
		return "Apt_Bay_Balcony"
	if f == 2 and i == 0 and face == 0:
		return "Apt_FireEscape_Bay"
	return "Apt_Bay_Window"


func _off_ground(face: int, i: int, corner: bool) -> String:
	if corner:
		return "Office_Podium_Base"
	return "Office_Bay_Ground_Lobby" if (face == 0 and i == 2) else "Office_Bay_Ground_Window"


func _off_upper(_face: int, _i: int, f: int, corner: bool) -> String:
	if corner:
		return "Office_Corner_Out"
	return "Office_Bay_Spandrel_Stripe" if f == 3 else "Office_Bay_Window"


func run(main: Node) -> void:
	_root = Node3D.new()
	_root.name = "KitPreview"
	main.add_child(_root)
	_root.global_position = ORIGIN
	# ground + sun so the preview reads in any environment
	var ground := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(160, 0.4, 160)
	ground.mesh = bm
	ground.position = Vector3(0, -0.2, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.36, 0.38)
	ground.material_override = gm
	_root.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 150, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	_root.add_child(sun)
	# apartment block (4 x 3 bays, 4 floors) at x -24
	var apt := Node3D.new()
	apt.position = Vector3(-24, 0, 0)
	_root.add_child(apt)
	block(apt, "kit_apartment", 4, 3, 4, 4.8, _apt_ground, _apt_upper, "Apt_Cornice", "Apt_Cornice_Corner")
	# office tower (5 x 3 bays, 7 floors) at x +8
	var off := Node3D.new()
	off.position = Vector3(8, 0, 0)
	_root.add_child(off)
	block(off, "kit_office", 5, 3, 7, 4.8, _off_ground, _off_upper, "Office_Cornice", "")
	# shop strip (4 bays, 2 storeys) at x +36, with awnings / signs
	var shp := Node3D.new()
	shp.position = Vector3(36, 0, 0)
	_root.add_child(shp)
	var mods := ["Shop_Front_Glass", "Shop_Front_Door", "Shop_Front_Glass", "Shop_Corner"]
	for i in 4:
		var x := -6.0 + 4 * i
		place(shp, "kit_shop", mods[i], x, 0.0, 0.0, 0.0)
		place(shp, "kit_shop", "Shop_Upper_Window", x, 0.0, 3.6, 0.0)
		place(shp, "kit_shop", "Shop_Parapet", x, 0.0, 7.2, 0.0)
	place(shp, "kit_shop", "Shop_Awning_A", -6.0, 0.0, 0.0, 0.0)
	place(shp, "kit_shop", "Shop_Awning_B", -2.0, 0.0, 0.0, 0.0)
	place(shp, "kit_shop", "Shop_Sign_Board", 2.0, 0.0, 0.1, 0.0)
	place(shp, "kit_shop", "Shop_Sign_Blade", 4.0, 0.0, 0.0, 0.0)
	# industrial shed (5 bays) + silo/tank at x +36, z -> behind (negative by)
	var ind := Node3D.new()
	ind.position = Vector3(36, 0, 36)
	_root.add_child(ind)
	var front := ["Ind_Wall_Windows_Band", "Ind_Door_Man", "Ind_Door_Roller", "Ind_Loading_Dock", "Ind_Corner"]
	for i in 5:
		place(ind, "kit_industrial", front[i], -8.0 + 4 * i, 0.0, 0.0, 0.0)
		place(ind, "kit_industrial", "Ind_Roof_Sawtooth_Bay", -8.0 + 4 * i, 0.0, 6.0, 0.0)
	place(ind, "kit_industrial", "Ind_Silo_Small", 16.0, -4.0, 0.0, 0.0)
	place(ind, "kit_industrial", "Ind_Tank", 24.0, -4.0, 0.0, 0.0)
	# rooftop props on a slab (kit_roof) at x -24, z +36
	var roof := Node3D.new()
	roof.position = Vector3(-24, 0, 36)
	_root.add_child(roof)
	var names := ["Roof_AC_A", "Roof_AC_B", "Roof_Tank", "Roof_Antenna_A", "Roof_Antenna_B", "Roof_Stairs_Box", "Roof_Vent_Row", "Roof_Solar_Panels", "Roof_Billboard_Frame", "Roof_Chimney"]
	for i in names.size():
		place(roof, "kit_roof", names[i], -14.0 + 3.2 * i, 0.0, 0.0, 0.0)
	place(roof, "kit_roof", "Roof_Helipad_Pad", 0.0, -14.0, 0.0, 0.0)
	# complete houses in a row at z -40 (front faces -Z in Godot = +Y in Blender)
	var hx := -50.0
	for id in ["bld_house_a", "bld_house_b", "bld_house_c", "bld_house_d", "bld_duplex"]:
		var ps := load(DIR + id + ".glb") as PackedScene
		if ps != null:
			var inst := ps.instantiate() as Node3D
			inst.position = Vector3(hx, 0, -40)
			_root.add_child(inst)
		hx += 18.0
	var aps := load(DIR + "bld_apartment_small.glb") as PackedScene
	if aps != null:
		var ai := aps.instantiate() as Node3D
		ai.position = Vector3(-70, 0, 0)
		_root.add_child(ai)
	await get_tree().process_frame
	await get_tree().process_frame
	print("TEST buildings_preview PASS placed kit assemblies at ", ORIGIN)
