extends SceneTree
## CLI baking tool for the procedural sound bank (optional - the game synthesises everything at runtime when no bake exists).
## Renders every sound variant of the SoundBank and stores it as a compressed AudioStreamWAV resource in
## res://gta/generated/audio/<id>_<variant>.res, tagged with the fingerprint of the recipe sources. Sfx loads these instead
## of synthesising (about 25 s of CPU saved at boot); stale files (recipes edited after the bake) are ignored automatically.
##
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/code/editor/audio_bake.gd -Seconds 240 -GameArgs "all"
##   ... -GameArgs "ids=shot_pistol,explosion_big"      bake only some ids
##   ... -GameArgs "clean"                              delete baked files that no longer match the registry / fingerprint
##   ... -GameArgs "wipe"                               delete every baked file
## Prints BAKE lines and a final "BAKE DONE n files, x KB".

const SoundBank = preload("res://gta/code/audio/sound_bank.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "all"
	var only: Array = []
	for a in args:
		var s := String(a)
		if s.begins_with("ids="):
			mode = "ids"
			for part in s.substr(4).split(","):
				only.append(StringName(part))
		elif s == "clean" or s == "wipe" or s == "all":
			mode = s
	SoundBank.init_registry()
	if mode == "wipe" or mode == "clean":
		_clean(mode == "wipe")
		quit()
		return
	var t0 := Time.get_ticks_msec()
	var count := 0
	var bytes := 0
	var fails := 0
	for id in SoundBank.ids():
		if mode == "ids" and not only.has(id):
			continue
		for v in SoundBank.variant_count(id):
			var err := SoundBank.bake(id, v)
			if err != OK:
				fails += 1
				print("BAKE FAIL ", id, " v", v, " err=", err)
				continue
			count += 1
			var path := ProjectSettings.globalize_path(SoundBank.bake_path(id, v))
			if FileAccess.file_exists(path):
				bytes += FileAccess.open(path, FileAccess.READ).get_length()
	print("BAKE DONE %d files, %d KB, %d failures, %.1f s, fingerprint=%s" % [count, bytes / 1024, fails, float(Time.get_ticks_msec() - t0) / 1000.0, SoundBank.fingerprint()])
	quit(1 if fails > 0 else 0)


func _clean(wipe: bool) -> void:
	var dir := DirAccess.open(SoundBank.BAKE_DIR)
	if dir == null:
		print("BAKE nothing to clean")
		return
	var valid := {}
	for id in SoundBank.ids():
		for v in SoundBank.variant_count(id):
			valid[SoundBank.bake_path(id, v).get_file()] = true
	var removed := 0
	var fp := SoundBank.fingerprint()
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.get_extension() == "res":
			var stale := wipe or not valid.has(f)
			if not stale:
				var res = ResourceLoader.load(SoundBank.BAKE_DIR + f, "", ResourceLoader.CACHE_MODE_IGNORE)
				stale = not (res is AudioStreamWAV) or (fp != "" and (res as AudioStreamWAV).get_meta("fp", "") != fp)
			if stale:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(SoundBank.BAKE_DIR + f))
				removed += 1
		f = dir.get_next()
	dir.list_dir_end()
	print("BAKE clean removed %d files" % removed)
