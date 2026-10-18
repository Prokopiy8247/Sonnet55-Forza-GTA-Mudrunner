extends SceneTree
## Developer loop for the generative radio (no game boot): renders phrases of every station, prints timing + statistics and
## writes WAV / spectrogram PNG files to screenshots/audio_check/.
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/audio_radio_dev.gd -GameArgs "phrases=3 plot"
## args: phrases=N (per station, default 2)  station=<id>  plot  nowav

const Music = preload("res://gta/code/audio/radio_music.gd")
const Station = preload("res://gta/code/audio/radio_station.gd")
const Synth = preload("res://gta/code/audio/synth.gd")
const An = preload("res://gta/code/audio/audio_analysis.gd")
const OUT_DIR := "res://screenshots/audio_check/"


func _initialize() -> void:
	var n_phr := 2
	var only := ""
	var do_plot := false
	var do_wav := true
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("phrases="):
			n_phr = int(s.substr(8))
		elif s.begins_with("station="):
			only = s.substr(8)
		elif s == "plot":
			do_plot = true
		elif s == "nowav":
			do_wav = false
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	for sid in Music.station_ids():
		if only != "" and String(sid) != only:
			continue
		var st := Station.new(sid)
		st.phrase_index = 1
		var mono := PackedFloat32Array()
		var t_total := 0.0
		var prev_end := PackedVector2Array()
		for p in n_phr:
			var t0 := Time.get_ticks_usec()
			var fr := st.render_phrase()
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			t_total += ms
			var dur := float(fr.size()) / float(Music.SR)
			var m := PackedFloat32Array()
			m.resize(fr.size())
			var pk := 0.0
			for i in fr.size():
				m[i] = (fr[i].x + fr[i].y) * 0.5
				pk = maxf(pk, maxf(absf(fr[i].x), absf(fr[i].y)))
			# boundary continuity: step across the phrase seam vs. typical step
			var seam := 0.0
			if p > 0 and not prev_end.is_empty():
				seam = (Vector2(fr[0]) - Vector2(prev_end[prev_end.size() - 1])).length()
			prev_end = fr
			mono.append_array(m)
			print("RADIO %s phrase %d: %.1fs audio, render %.0f ms (%.1fx realtime) peak=%.2f rms=%.3f centroid=%.0fHz seam_step=%.4f nan=%s" % [
				sid, p, dur, ms, dur * 1000.0 / maxf(ms, 1.0), pk, An.rms(m), An.spectral_centroid(m, Music.SR), seam, str(An.has_nan(m))])
		print("RADIO %s total render %.0f ms for %d phrases, cache entries=%d" % [sid, t_total, n_phr, st._cache.size()])
		if do_wav:
			Synth.save_wav_file(abs_dir + "radio_%s.wav" % sid, mono, Music.SR)
		if do_plot:
			An.plot(mono.slice(0, mini(mono.size(), Music.SR * 12)), Music.SR, 900, 120, 240, 8000.0).save_png(abs_dir + "radio_%s.png" % sid)
	quit()
