extends Node
## Lays out the parts of a kit GLB in a row (each part at its own origin) with the runtime materials, for visual inspection.
##   tools\gd.ps1 shot -Out screenshots\kit_office.png -GameArgs "--exec=res://gta/tests/content_kit_view.gd --kit=buildings/kit_office --cam=...":
## options read from the DevHarness: --kit=<rel> [--spacing=6] [--rot=0] [--only=Name1,Name2]

func run(main: Node) -> Variant:
	var harness = main.get_node_or_null("DevHarness")
	var opts: Dictionary = harness.opts if harness != null else {}
	var rel: String = String(opts.get("kit", "buildings/kit_office"))
	var spacing := float(opts.get("spacing", 6.0))
	var rot := deg_to_rad(float(opts.get("rot", 0.0)))
	var only: PackedStringArray = String(opts.get("only", "")).split(",", false)
	var world := ContentMock.make_world(main, true)
	Game.world = world
	var root := ModelLib.instance(rel)
	if root == null:
		print("KITVIEW missing ", rel)
		return false
	var parts: Array[MeshInstance3D] = ModelLib.meshes(root)
	parts.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool: return String(a.name) < String(b.name))
	var i := 0
	var holder := Node3D.new()
	world.add_child(holder)
	for mi in parts:
		if only.size() > 0 and not (String(mi.name) in only):
			continue
		var mesh := ContentLib.flatten_local(mi)
		if mesh == null:
			continue
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.name = String(mi.name)
		inst.position = Vector3(i * spacing, 0, 0)
		inst.rotation.y = rot
		holder.add_child(inst)
		print("KITVIEW ", i, " ", mi.name, " aabb=", mesh.get_aabb())
		i += 1
	root.free()
	# ground strip
	for k in 12:
		await get_tree().process_frame
	return true
