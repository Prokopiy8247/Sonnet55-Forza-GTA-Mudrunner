extends SceneTree
## Headless validator: loads every .gd / .tscn / .tres under res://gta (except generated models) and reports
## parse errors, missing resources and scripts that cannot instantiate.
##   powershell -NoProfile -File tools\gd.ps1 check
## Prints "VALIDATE OK ..." or "VALIDATE FAIL ..." and exits non-zero on failure.

const ROOT := "res://gta"
const SKIP_DIRS := ["res://gta/generated/models"]


func _initialize() -> void:
	var fails := 0
	var count := 0
	var paths: Array[String] = []
	_collect(ROOT, paths)
	paths.sort()
	for p in paths:
		count += 1
		var res = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REPLACE)
		if res == null:
			print("VALIDATE FAIL load: ", p)
			fails += 1
			continue
		if res is GDScript and not (res as GDScript).can_instantiate():
			# static-only helper classes (RefCounted with no instantiation need) still return true; false = errors
			print("VALIDATE FAIL cannot instantiate: ", p)
			fails += 1
		elif res is PackedScene and not (res as PackedScene).can_instantiate():
			print("VALIDATE FAIL scene cannot instantiate: ", p)
			fails += 1
	print("VALIDATE %s files=%d fails=%d" % ["OK" if fails == 0 else "FAIL", count, fails])
	quit(1 if fails > 0 else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	if dir_path in SKIP_DIRS:
		return
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.begins_with("."):
			f = d.get_next()
			continue
		var full := dir_path.path_join(f)
		if d.current_is_dir():
			_collect(full, out)
		else:
			var ext := f.get_extension()
			if ext == "gd" or ext == "tscn" or ext == "tres":
				out.append(full)
		f = d.get_next()
	d.list_dir_end()
