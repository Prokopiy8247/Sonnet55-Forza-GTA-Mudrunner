extends SceneTree
## Fast developer loop for the procedural sound bank (no game boot, no autoloads):
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/audio_dev.gd -GameArgs "ids=shot_pistol,explosion_big plot wav"
## args: ids=a,b,c | all | prefix=<text>   plot (spectrogram PNG)   wav (export WAV)   no-stats
## Output goes to screenshots/audio_check/. Prints one STAT line per sound: duration, peak, rms, centroid, zcr, decay, seam.

const SoundBank = preload("res://gta/code/audio/sound_bank.gd")
const Synth = preload("res://gta/code/audio/synth.gd")
const An = preload("res://gta/code/audio/audio_analysis.gd")
const OUT_DIR := "res://screenshots/audio_check/"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var want: Array = []
	var do_plot := false
	var do_wav := false
	var stats := true
	var prefix := ""
	var all := false
	var zoom_a := -1.0
	var zoom_b := -1.0
	for a in args:
		var s := String(a)
		if s.begins_with("ids="):
			for part in s.substr(4).split(","):
				want.append(StringName(part))
		elif s == "all":
			all = true
		elif s.begins_with("prefix="):
			prefix = s.substr(7)
		elif s == "plot":
			do_plot = true
		elif s == "wav":
			do_wav = true
		elif s.begins_with("zoom="):
			var zp := s.substr(5).split("-")
			zoom_a = float(zp[0])
			zoom_b = float(zp[1])
		elif s == "no-stats":
			stats = false
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	SoundBank.init_registry()
	var ids: Array = []
	if all:
		ids = SoundBank.ids().duplicate()
	elif prefix != "":
		for id in SoundBank.ids():
			if String(id).begins_with(prefix):
				ids.append(id)
	else:
		ids = want
	print("DEV registry ids=", SoundBank.ids().size(), " selected=", ids.size(), " fingerprint=", SoundBank.fingerprint())
	if args.has("table"):
		# one DOC line per id: id | category | variants | loop | seconds | sample rate | bus | range | unit | peak
		for id in SoundBank.ids():
			var m := SoundBank.meta(id)
			var r := SoundBank.render(id, 0)
			var dur: float = float(r["buf"].size()) / float(r["sr"])
			print("DOC|%s|%s|%d|%s|%.2f|%d|%s|%d|%d|%.2f" % [id, m["cat"], int(m["var"]), "loop" if r["loop"] else "-", dur, int(r["sr"]), m["bus"], int(m.get("range", 0)), int(m["unit"]), float(m["peak"])])
		quit()
		return
	var t_all := Time.get_ticks_usec()
	var total_audio_s := 0.0
	for id in ids:
		var nvar := SoundBank.variant_count(id)
		for v in nvar:
			var t0 := Time.get_ticks_usec()
			var r := SoundBank.render(id, v)
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			if r.is_empty():
				print("STAT ", id, " v", v, " EMPTY")
				continue
			var buf: PackedFloat32Array = r["buf"]
			var sr: int = r["sr"]
			total_audio_s += float(buf.size()) / float(sr)
			if stats:
				var dur := float(buf.size()) / float(sr)
				var line := "STAT %s v%d %.2fs sr=%d gen=%.0fms peak=%.2f rms=%.3f cent=%.0fHz zcr=%.0f decay30=%.2fs" % [
					id, v, dur, sr, ms, An.peak(buf), An.rms(buf), An.spectral_centroid(buf, sr), An.zero_cross_rate(buf, sr), An.decay_time(buf, 30.0, sr)]
				if r["loop"]:
					line += " LOOP seam=%.2f edge=%.2f" % [An.loop_seam_ratio(buf), An.seam_energy_ratio(buf)]
				if An.has_nan(buf):
					line += " NAN!"
				print(line)
			if v == 0 or do_wav:
				var base := "%s%s%s" % [abs_dir, String(id), "" if v == 0 else "_%d" % v]
				if do_wav:
					Synth.save_wav_file(base + ".wav", buf, sr)
				if do_plot:
					var pb := buf
					if zoom_a >= 0.0:
						pb = buf.slice(int(zoom_a * sr), int(zoom_b * sr))
					An.plot(pb, sr).save_png(base + ".png")
	print("DEV total %.0f ms for %.1f s of audio" % [float(Time.get_ticks_usec() - t_all) / 1000.0, total_audio_s])
	quit()
