extends Node
## Audio module test (headless): powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/audio_test.gd -Seconds 90
## Boots Main, then verifies the sound bank (every contract id exists, no NaN / clipping / silence, plausible spectra, loop
## seams), the Sfx pool (polyphony, culling, priority), EngineSound, AudioSystem (buses, underwater, ducking, radio) and the
## generative radio. Key sounds are exported to screenshots/audio_check/ (WAV + spectrogram PNG) for manual inspection.
## Prints "TEST <name> PASS|FAIL <detail>" lines and a final "TEST SUMMARY".

const Synth = preload("res://gta/code/audio/synth.gd")
const An = preload("res://gta/code/audio/audio_analysis.gd")
const Music = preload("res://gta/code/audio/radio_music.gd")
const Station = preload("res://gta/code/audio/radio_station.gd")
const SoundBank = preload("res://gta/code/audio/sound_bank.gd")
const OUT_DIR := "res://screenshots/audio_check/"

## Every sound id of docs/ARCHITECTURE.md section 8.
const CONTRACT_IDS := [
	"ui_click", "ui_back", "ui_error", "ui_confirm", "ui_cash", "ui_notify", "ui_wanted_up", "ui_wanted_down", "ui_busted", "ui_wasted",
	"shot_pistol", "shot_revolver", "shot_smg", "shot_shotgun", "shot_rifle", "shot_sniper", "shot_suppressed", "shot_rocket",
	"reload_start", "reload_end", "dry_fire", "melee_swing", "melee_hit", "punch", "hit_flesh", "hit_headshot", "hit_metal",
	"hit_concrete", "hit_glass", "hit_dirt", "hit_water", "explosion_small", "explosion_big", "grenade_bounce", "glass_break",
	"step_concrete", "step_grass", "step_sand", "step_wood", "step_water", "splash", "splash_big", "jump", "land", "hurt_m", "hurt_f",
	"death_m", "death_f", "breath_hard", "gasp", "scream", "cough", "door_open", "door_close", "pickup",
	"horn_car", "horn_truck", "horn_bike", "skid", "crash_light", "crash_heavy", "siren_police", "siren_ambulance", "siren_fire",
	"door_vehicle_open", "door_vehicle_close", "ignition", "engine_off", "turbo_whistle", "thunder",
]
const PROFILES := ["car_small", "car_v6", "car_v8", "sports", "truck", "bike", "boat", "heli_rotor", "prop_plane", "jet"]

class MockPlayer:
	extends Node3D
	var current_vehicle = null


class MockVehicle:
	extends Node3D
	var engine_on := true
	var vclass: StringName = &"car"
	var is_destroyed := false


var _pass := 0
var _fail := 0
var _abs_dir := ""


func _t(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func run(main: Node) -> Variant:
	_abs_dir = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_abs_dir)
	await get_tree().process_frame
	_test_contract_ids()
	var gen_ms: float = Sfx.wait_ready()
	var baked: bool = ResourceLoader.exists(SoundBank.bake_path(&"ui_click", 0))
	_t("bank_generation_wall_time", gen_ms < (4000.0 if baked else 40000.0), "%.0f ms until all %d buffers were ready (background workers; baked files used: %s)" % [gen_ms, Sfx.sound_ids().size(), str(baked)])
	_test_bank_quality()
	_test_properties()
	_test_loops()
	_test_engine_layers()
	await _test_sfx_pool()
	await _test_engine_sound(main)
	await _test_audio_system()
	await _test_radio()
	await _test_radio_in_vehicle(main)
	await _test_vehicle_integration(main)
	_test_export()
	print("TEST SUMMARY pass=%d fail=%d" % [_pass, _fail])
	return _fail == 0


# ---- contract / bank ------------------------------------------------------------------------------------------------------
func _test_contract_ids() -> void:
	var missing: Array = []
	for id in CONTRACT_IDS:
		if not Sfx.has_sound(StringName(id)):
			missing.append(id)
	_t("contract_ids_registered", missing.is_empty(), "%d ids, missing=%s" % [CONTRACT_IDS.size(), str(missing)])
	var miss_eng: Array = []
	for p in PROFILES:
		if not Sfx.has_sound(StringName("eng_%s_0" % p)):
			miss_eng.append(p)
	_t("engine_profiles_registered", miss_eng.is_empty(), str(miss_eng))


func _test_bank_quality() -> void:
	var bad: Array = []
	var total := 0
	var t_sound_max := 0.0
	for id in Sfx.sound_ids():
		for v in Sfx.get_variant_count(id):
			var w := Sfx.get_wav(id, v)
			total += 1
			if w == null or w.data.size() < 64:
				bad.append("%s#%d empty" % [id, v])
				continue
			var buf := Synth.from_wav(w)
			if An.has_nan(buf):
				bad.append("%s#%d nan" % [id, v])
			var pk := An.peak(buf)
			if pk > 1.0 or pk < 0.04:
				bad.append("%s#%d peak=%.2f" % [id, v, pk])
			if An.rms(buf) < 0.004:
				bad.append("%s#%d silent rms=%.4f" % [id, v, An.rms(buf)])
			if absf(An.dc_offset(buf)) > 0.03:
				bad.append("%s#%d dc=%.3f" % [id, v, An.dc_offset(buf)])
			var clipped := 0
			for i in buf.size():
				if absf(buf[i]) > 0.995:
					clipped += 1
			if float(clipped) / float(buf.size()) > 0.004:
				bad.append("%s#%d clipped=%.2f%%" % [id, v, 100.0 * float(clipped) / float(buf.size())])
	_t("bank_no_nan_clip_silence", bad.is_empty(), "%d buffers checked, problems=%s" % [total, str(bad.slice(0, 8))])
	_t("bank_size", total >= 200, "%d sound buffers, %d ids" % [total, Sfx.sound_ids().size()])
	var st := Sfx.stats()
	_t("bank_ready_flag", Sfx.is_bank_ready(), "gen %.0f ms" % float(st["bank_gen_ms"]))
	# timing of a single synthesis (runtime fallback path), not using baked files
	var t0 := Time.get_ticks_usec()
	SoundBank.generate(&"shot_rifle", 0)
	SoundBank.generate(&"explosion_big", 0)
	SoundBank.generate(&"step_concrete", 0)
	t_sound_max = float(Time.get_ticks_usec() - t0) / 1000.0
	_t("synthesis_speed_common_sounds", t_sound_max < 1500.0, "rifle+explosion_big+step in %.0f ms" % t_sound_max)


func _buf(id: StringName, v: int = 0) -> PackedFloat32Array:
	return Synth.from_wav(Sfx.get_wav(id, v))


func _test_properties() -> void:
	var sr := 22050
	# explosions: low centroid, long decay, strong low-frequency content
	for id in [&"explosion_small", &"explosion_big"]:
		var w := Sfx.get_wav(id, 0)
		var b := Synth.from_wav(w)
		var cent := An.spectral_centroid(b, w.mix_rate)
		var dec := An.decay_time(b, 30.0, w.mix_rate)
		var low := An.band_fraction(b, 20.0, 200.0, w.mix_rate)
		_t("%s_character" % id, cent < 700.0 and dec > (0.9 if id == &"explosion_small" else 2.0) and low > 0.4, "centroid=%.0fHz decay30=%.2fs low<200Hz=%.0f%%" % [cent, dec, low * 100.0])
	# gunshot: fast attack, shortish decay, bright crack relative to explosion
	var wp := Sfx.get_wav(&"shot_pistol", 0)
	var bp := Synth.from_wav(wp)
	_t("shot_pistol_envelope", An.peak_time(bp, wp.mix_rate) < 0.05 and An.decay_time(bp, 30.0, wp.mix_rate) < 0.9, "peak@%.2fs decay30=%.2fs" % [An.peak_time(bp, wp.mix_rate), An.decay_time(bp, 30.0, wp.mix_rate)])
	_t("shot_suppressed_quieter_darker", An.rms(_buf(&"shot_suppressed")) < An.rms(_buf(&"shot_rifle")), "rms %.3f vs rifle %.3f" % [An.rms(_buf(&"shot_suppressed")), An.rms(_buf(&"shot_rifle"))])
	var sub_fraction := An.band_fraction(_buf(&"explosion_big"), 20.0, 90.0, 16000)
	_t("explosion_big_subbass_tail", sub_fraction > 0.12, "20-90Hz energy %.0f%%" % (sub_fraction * 100.0))
	# sirens oscillate between two pitches
	var pt := An.pitch_track(_buf(&"siren_police"), sr, 0.08, 300.0, 3000.0)
	var lo := 99999.0
	var hi := 0.0
	for f in pt:
		lo = minf(lo, f)
		hi = maxf(hi, f)
	_t("siren_police_wail_range", pt.size() > 20 and hi / lo > 1.7, "pitch %.0f..%.0f Hz (ratio %.2f)" % [lo, hi, hi / maxf(lo, 1.0)])
	var ya := An.pitch_track(_buf(&"siren_police_yelp"), sr, 0.05, 300.0, 3000.0)
	var ylo := 99999.0
	var yhi := 0.0
	for f in ya:
		ylo = minf(ylo, f)
		yhi = maxf(yhi, f)
	_t("siren_yelp_range", ya.size() > 8 and yhi / ylo > 1.5, "pitch %.0f..%.0f Hz" % [ylo, yhi])
	var at := An.pitch_track(_buf(&"siren_ambulance"), sr, 0.1, 400.0, 2500.0)
	var lo_n := 0
	var hi_n := 0
	for f in at:
		if absf(f - 960.0) < 60.0:
			hi_n += 1
		elif absf(f - 770.0) < 60.0:
			lo_n += 1
	_t("siren_ambulance_two_tone", hi_n >= 3 and lo_n >= 3, "frames near 960Hz=%d near 770Hz=%d of %d" % [hi_n, lo_n, at.size()])
	# voices: male fundamental below female; scream higher than hurt
	var f0_m := An.autocorr_pitch(_buf(&"hurt_m"), sr, 70.0, 450.0)
	var f0_f := An.autocorr_pitch(_buf(&"hurt_f"), sr, 120.0, 700.0)
	var f0_s := An.autocorr_pitch(_buf(&"scream"), sr, 150.0, 1000.0)
	var f0_dm := An.autocorr_pitch(_buf(&"death_m"), sr, 50.0, 400.0)
	_t("voice_pitch_in_range", f0_m > 70.0 and f0_m < 260.0 and f0_f > 170.0 and f0_f < 520.0 and f0_dm > 50.0 and f0_dm < 300.0, "hurt_m %.0f death_m %.0f hurt_f %.0f" % [f0_m, f0_dm, f0_f])
	_t("voice_pitch_male_lt_female", f0_m < f0_f, "hurt_m %.0f Hz vs hurt_f %.0f Hz" % [f0_m, f0_f])
	_t("voice_scream_high", f0_s > f0_m * 1.8 and f0_s > 300.0, "scream %.0f Hz" % f0_s)
	# footsteps are short, horns sustained
	_t("footsteps_short", _buf(&"step_concrete").size() < sr * 0.4 and _buf(&"step_grass").size() < sr * 0.4, "")
	_t("horn_is_sustained_loop", Sfx.is_loop(&"horn_car") and Sfx.is_loop(&"siren_police") and Sfx.is_loop(&"skid"), "")
	# thunder and rain textures
	var cth := An.spectral_centroid(Synth.from_wav(Sfx.get_wav(&"thunder", 0)), 11025)
	_t("thunder_low_rumble", cth < 400.0, "centroid %.0f Hz" % cth)
	var cr := An.spectral_centroid(Synth.from_wav(Sfx.get_wav(&"amb_rain_heavy", 0)), 22050)
	var cs := An.spectral_centroid(Synth.from_wav(Sfx.get_wav(&"amb_sea", 0)), 16000)
	_t("rain_brighter_than_sea", cr > cs * 3.0, "rain %.0f Hz, sea %.0f Hz" % [cr, cs])


func _median_pitch(b: PackedFloat32Array) -> float:
	var pt := An.pitch_track(b, 22050, 0.04, 70.0, 700.0, 2048)
	if pt.is_empty():
		return 0.0
	var arr: Array = []
	for f in pt:
		arr.append(f)
	arr.sort()
	return float(arr[arr.size() / 2])


func _test_loops() -> void:
	var bad: Array = []
	var n := 0
	for id in Sfx.sound_ids():
		var w := Sfx.get_wav(id, 0)
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			continue
		n += 1
		var b := Synth.from_wav(w)
		# seam check on the loop region only (attack segments before loop_begin are excluded)
		var region := b.slice(w.loop_begin, w.loop_end)
		var ratio := An.loop_seam_ratio(region)
		if ratio > 1.6:
			bad.append("%s seam=%.2f" % [id, ratio])
		if w.loop_end <= w.loop_begin + 100:
			bad.append("%s bad loop points" % id)
	_t("loops_seamless", bad.is_empty(), "%d loops, problems=%s" % [n, str(bad)])


func _test_engine_layers() -> void:
	# every engine layer's strongest periodicity must sit near the anchor frequency it was rendered at
	var BankEngine = load("res://gta/code/audio/bank_engine.gd")
	var bad: Array = []
	var checked := 0
	for p in PROFILES:
		if String(p) == "jet" or String(p) == "heli_rotor" or String(p) == "bike":
			continue   # noise-based jet, sub-audio blade-pass rotor and uneven-firing twin: no clean line at the anchor
		var prof: Dictionary = BankEngine.PROFILES[StringName(p)]
		for i in int(prof["layers"]):
			var w := Sfx.get_wav(StringName("eng_%s_%d" % [p, i]), 0)
			var b := Synth.from_wav(w)
			var fa: float = BankEngine.anchor_hz(StringName(p), i)
			# autocorrelation-free check: energy at fa multiples versus neighbours via DFT of a 4096 window
			var mag := An.spectrum(b, 2048, 4096)
			var hz_bin := float(w.mix_rate) / 4096.0
			var best_k := 1
			var best_v := 0.0
			var lim := mini(int(900.0 / hz_bin), 2047)
			for k in range(2, lim):
				if mag[k] > best_v:
					best_v = mag[k]
					best_k = k
			var f_peak := float(best_k) * hz_bin
			# the strongest line must be a low harmonic (1..8) of the firing frequency (or the pipe resonance)
			var ratio := f_peak / fa
			var near_harm := absf(ratio - roundf(ratio)) < 0.2 or ratio < 1.2
			checked += 1
			if not near_harm or ratio > 12.0:
				bad.append("%s_%d fa=%.0f peak=%.0f" % [p, i, fa, f_peak])
	_t("engine_layers_periodic_at_anchor", bad.size() <= 3, "%d layers, off-anchor: %s" % [checked, str(bad)])
	# loudness balance between layers of one profile (RMS target)
	var spread := 0.0
	for p in PROFILES:
		var BankE = load("res://gta/code/audio/bank_engine.gd")
		var n_l: int = int(BankE.PROFILES[StringName(p)]["layers"])
		var lo := 9.0
		var hi := 0.0
		for i in n_l:
			var r := An.rms(_buf(StringName("eng_%s_%d" % [p, i])))
			lo = minf(lo, r)
			hi = maxf(hi, r)
		spread = maxf(spread, hi / maxf(lo, 1e-6))
	_t("engine_layers_balanced", spread < 1.6, "max RMS ratio between layers %.2f" % spread)


# ---- Sfx pool -------------------------------------------------------------------------------------------------------------
func _test_sfx_pool() -> void:
	Sfx.stop_all()
	await get_tree().process_frame
	Sfx.listener_pos = Vector3.ZERO
	Sfx.listener_valid = true
	var s0 := Sfx.stats()
	# polyphony per id (pistol poly=4): spam 40 within one frame
	var started := 0
	for i in 40:
		if Sfx.play_3d(&"shot_pistol", Vector3(2.0 + float(i) * 0.1, 0, 0), 0.0, 1.0, 100.0) != null:
			started += 1
	await get_tree().process_frame
	var st := Sfx.stats()
	_t("polyphony_per_id_cap", int(st["active_3d"]) <= 6, "active=%d (cap 4 per id + steals), accepted=%d of 40" % [int(st["active_3d"]), started])
	# distance culling
	var far_p: AudioStreamPlayer3D = Sfx.play_3d(&"shot_pistol", Vector3(500, 0, 0), 0.0, 1.0, 80.0)
	_t("distance_culling", far_p == null, "beyond max_distance returns null")
	# unknown ids are silent, not fatal
	var unk: AudioStreamPlayer3D = Sfx.play_3d(&"does_not_exist_zzz", Vector3.ZERO)
	_t("unknown_id_tolerated", unk == null and not Sfx.has_sound(&"does_not_exist_zzz"), "")
	# pool saturation with footsteps then a high priority explosion must still start
	Sfx.stop_all()
	await get_tree().process_frame
	for i in 80:
		Sfx.play_3d(&"step_concrete", Vector3(3.0 + float(i % 10), 0, float(i / 10)), 0.0, 1.0, 100.0)
		Sfx.play_3d(&"hit_metal", Vector3(4.0 + float(i % 7), 0, float(i / 7)), 0.0, 1.0, 100.0)
		Sfx.play_3d(&"splash", Vector3(5.0 + float(i % 5), 0, float(i / 5)), 0.0, 1.0, 100.0)
		Sfx.play_3d(&"crash_light", Vector3(6.0 + float(i % 5), 0, float(i / 5)), 0.0, 1.0, 100.0)
	var boom: AudioStreamPlayer3D = Sfx.play_3d(&"explosion_big", Vector3(30, 0, 0), 0.0, 1.0, 400.0)
	_t("priority_explosion_always_plays", boom != null and boom.playing, "")
	var st2 := Sfx.stats()
	_t("pool_never_exceeds_size", int(st2["active_3d"]) <= Sfx.POOL_3D, "active=%d / %d" % [int(st2["active_3d"]), Sfx.POOL_3D])
	# 2D / UI
	Sfx.play_ui(&"ui_click")
	var p2: AudioStreamPlayer = Sfx.play_2d(&"pickup", -3.0, 1.0)
	_t("play_2d_ui", p2 != null and p2.playing, "")
	# get_stream returns playable streams (randomizer for multi variant)
	var gs := Sfx.get_stream(&"step_concrete")
	var gl := Sfx.get_stream(&"siren_police")
	_t("get_stream_types", gs is AudioStreamRandomizer and gl is AudioStreamWAV and (gl as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED, "%s / %s" % [gs, gl])
	_t("aliases_resolve", Sfx.has_sound(&"shot_carbine") and Sfx.has_sound(&"explosion"), "")
	# horn one-shot auto stops after its oneshot length
	var horn: AudioStreamPlayer3D = Sfx.play_3d(&"horn_car", Vector3(5, 0, 0))
	_t("looping_sound_oneshot_playing", horn != null and horn.playing, "")
	await get_tree().create_timer(0.9).timeout
	_t("looping_sound_oneshot_stops", horn != null and not horn.playing, "horn stops after its one-shot length")
	Sfx.stop_all()
	_t("stats_report", int(s0["sounds"]) > 100, str(Sfx.stats()))


# ---- EngineSound ------------------------------------------------------------------------------------------------------------
func _test_engine_sound(main: Node) -> void:
	var holder := Node3D.new()
	holder.name = "AudioTestHolder"
	main.add_child(holder)
	holder.global_position = Vector3(8, 0, 0)
	Sfx.listener_pos = Vector3.ZERO
	Sfx.listener_valid = true
	var problems: Array = []
	var worst_update_us := 0.0
	for p in PROFILES:
		var snd := EngineSound.create(StringName(p))
		holder.add_child(snd)
		await get_tree().process_frame
		snd.start()
		var spent := 0
		var n := 0
		for k in 240:
			var rpm := float(k) / 239.0
			var t0 := Time.get_ticks_usec()
			snd.update(rpm, 0.2 + 0.8 * rpm)
			spent += Time.get_ticks_usec() - t0
			n += 1
			if k % 40 == 0:
				await get_tree().process_frame
		var us := float(spent) / float(n)
		worst_update_us = maxf(worst_update_us, us)
		# at redline the highest loops must be playing with an upward pitch shift, at idle the lowest loop at about 1.0
		var players: Array = []
		for c in snd.get_children():
			if c is AudioStreamPlayer3D:
				players.append(c)
		if players.is_empty():
			problems.append("%s no players" % p)
			snd.queue_free()
			continue
		var active := 0
		var max_pitch := 0.0
		for pl in players:
			if not pl.stream_paused:
				active += 1
				max_pitch = maxf(max_pitch, pl.pitch_scale)
		if active < 1 or active > 3 or max_pitch > 2.7:
			problems.append("%s active=%d pitch=%.2f" % [p, active, max_pitch])
		snd.stop()
		snd.queue_free()
	_t("engine_sound_profiles_run", problems.is_empty(), str(problems))
	_t("engine_update_cheap", worst_update_us < 60.0, "worst %.1f us per update()" % worst_update_us)
	# crossfade monotonic: pitch of the dominant layer increases with rpm inside one layer's range
	var e := EngineSound.create(&"car_v6")
	holder.add_child(e)
	await get_tree().process_frame
	e.start()
	e._fade = 1.0
	var pitches: Array = []
	for k in 6:
		e.update(0.08 + 0.02 * float(k), 0.5)
		for c in e.get_children():
			if c is AudioStreamPlayer3D and not c.stream_paused and c.volume_db > -12.0:
				pitches.append(c.pitch_scale)
				break
		await get_tree().process_frame
	_t("engine_pitch_follows_rpm", pitches.size() >= 3 and pitches[pitches.size() - 1] >= pitches[0], str(pitches))
	e.queue_free()
	# distance culling pauses everything
	var far := EngineSound.create(&"car_small")
	holder.add_child(far)
	holder.global_position = Vector3(900, 0, 0)
	await get_tree().process_frame
	far.start()
	for k in 12:
		far.update(0.5, 0.5)
	var any_playing := false
	for c in far.get_children():
		if c is AudioStreamPlayer3D and not c.stream_paused:
			any_playing = true
	_t("engine_distance_cull", not any_playing, "far engines are paused")
	far.queue_free()
	holder.queue_free()


# ---- AudioSystem / buses / radio ------------------------------------------------------------------------------------------
func _test_audio_system() -> void:
	var asys = Game.sys(&"audio")
	_t("audio_system_booted", asys != null, "")
	if asys == null:
		return
	for bn in ["Master", "SFX", "Engine", "Voice", "Ambience", "Music", "Radio", "UI"]:
		if AudioServer.get_bus_index(bn) < 0:
			_t("bus_" + bn, false, "missing")
			return
	_t("buses_created", true, "Master SFX Engine Voice Ambience Music Radio UI")
	# settings -> bus volume
	Game.settings["master_volume"] = 0.5
	Events.settings_changed.emit()
	var mdb := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	_t("settings_master_volume", absf(mdb - linear_to_db(0.5)) < 0.1, "%.2f dB" % mdb)
	Game.settings["master_volume"] = 0.8
	Events.settings_changed.emit()
	# underwater low-pass
	asys.set_underwater(true)
	for i in 70:
		await get_tree().process_frame
	var fx: Dictionary = Sfx.get_bus_fx("SFX")
	var sfx_idx := AudioServer.get_bus_index("SFX")
	var lp_on := AudioServer.is_bus_effect_enabled(sfx_idx, int(fx["lp_idx"]))
	var cutoff: float = (fx["lp"] as AudioEffectLowPassFilter).cutoff_hz
	_t("underwater_lowpass_on", lp_on and cutoff < 2500.0, "enabled=%s cutoff=%.0f Hz" % [str(lp_on), cutoff])
	var bed: float = float(asys.get_status()["beds"]["underwater"])
	_t("underwater_bed_fades_in", bed > 0.3, "bed volume %.2f" % bed)
	asys.set_underwater(false)
	for i in 160:
		await get_tree().process_frame
	_t("underwater_lowpass_off", not AudioServer.is_bus_effect_enabled(sfx_idx, int(fx["lp_idx"])), "")
	# menu ducking
	Events.menu_opened.emit(&"test_menu")
	for i in 40:
		await get_tree().process_frame
	var duck_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience"))
	Events.menu_closed.emit(&"test_menu")
	_t("menu_ducks_ambience", duck_db < -9.0, "Ambience bus %.1f dB while a menu is open" % duck_db)
	for i in 60:
		await get_tree().process_frame
	# ambience beds follow the context
	var status: Dictionary = asys.get_status()
	_t("ambience_status", status.has("beds") and status["beds"].size() >= 10, str(status["beds"]))
	# safety net: an explosion event with no sound played by gameplay code triggers one
	Sfx.stop_all()
	Sfx.listener_pos = Vector3.ZERO
	Sfx.listener_valid = true
	Events.explosion.emit(Vector3(15, 0, 0), 9.0, null)
	await get_tree().create_timer(0.1).timeout
	_t("safety_net_explosion", Sfx.was_played_recently(&"explosion", Vector3(15, 0, 0), 1.0, 20.0), "")
	var before := int(Sfx.stats()["played"])
	Sfx.play_3d(&"explosion_small", Vector3(15, 0, 3), 0.0, 1.0, 300.0)
	Events.explosion.emit(Vector3(15, 0, 3), 3.0, null)
	await get_tree().create_timer(0.1).timeout
	var after := int(Sfx.stats()["played"])
	_t("safety_net_no_double", after - before == 1, "plays added: %d" % (after - before))
	Sfx.stop_all()
	# helpers
	var pos: Vector3 = asys.position_around_listener(20.0, 40.0, 0.0, 5.0)
	var rel: float = Vector2(pos.x - Sfx.listener_pos.x, pos.z - Sfx.listener_pos.z).length()
	_t("listener_helpers", rel >= 19.0 and rel <= 41.0, "%.1f m from the listener" % rel)


func _test_radio() -> void:
	var asys = Game.sys(&"audio")
	if asys == null:
		return
	var stations: Array = asys.get_stations()
	_t("radio_stations_available", stations.size() >= 4, str(stations))
	var heard: Array = []
	var cb := func(sname: StringName) -> void: heard.append(sname)
	Events.radio_station_changed.connect(cb)
	asys.set_station(&"halcyon_fm")
	await get_tree().create_timer(0.3).timeout
	asys.radio_next()
	await get_tree().create_timer(0.3).timeout
	asys.radio_prev()
	await get_tree().create_timer(0.3).timeout
	_t("radio_next_prev_events", asys.get_station() == &"halcyon_fm" and heard.size() >= 2, "heard=%s now=%s" % [str(heard), asys.get_station()])
	_t("radio_remembers_station", String(Game.settings.get("radio_station", "")) == "halcyon_fm", "")
	Events.radio_station_changed.disconnect(cb)
	asys.radio_off()
	_t("radio_off", asys.get_station() == &"off" and not asys.is_radio_playing(), "")
	asys.set_station(&"lofi_harbor")
	# every station renders phrases offline: speed, level, no NaN, seam continuity
	for sid in Music.station_ids():
		var st := Station.new(sid)
		st.phrase_index = 1
		var t0 := Time.get_ticks_usec()
		var f1 := st.render_phrase()
		var f2 := st.render_phrase()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var dur := float(f1.size() + f2.size()) / float(Music.SR)
		var m := PackedFloat32Array()
		m.resize(f1.size() + f2.size())
		var pk := 0.0
		var steps := PackedFloat32Array()
		for i in f1.size():
			m[i] = (f1[i].x + f1[i].y) * 0.5
			pk = maxf(pk, absf(f1[i].x))
		for i in f2.size():
			m[f1.size() + i] = (f2[i].x + f2[i].y) * 0.5
			pk = maxf(pk, absf(f2[i].x))
		var seam_step := absf(m[f1.size()] - m[f1.size() - 1])
		var typical := 0.0
		for i in range(1, 20000):
			typical = maxf(typical, absf(m[i] - m[i - 1]))
		_t("radio_%s_render" % sid, pk > 0.2 and pk <= 1.0 and not An.has_nan(m) and An.rms(m) > 0.05 and dur / (ms / 1000.0) > 0.8, "%.1fs audio in %.0f ms (%.1fx realtime) peak=%.2f rms=%.3f" % [dur, ms, dur / (ms / 1000.0), pk, An.rms(m)])
		_t("radio_%s_phrase_seam" % sid, seam_step <= maxf(typical * 1.5, 0.05), "seam step %.4f vs local max step %.4f" % [seam_step, typical])
		if sid == &"halcyon_fm" or sid == &"lofi_harbor" or sid == &"calle_funk":
			Synth.save_wav_file(_abs_dir + "radio_%s_test.wav" % sid, m, Music.SR)
		var cent := An.spectral_centroid(m, Music.SR)
		_t("radio_%s_tonal_balance" % sid, cent > 80.0 and cent < 3000.0, "centroid %.0f Hz" % cent)
	# the live station queue fills in the background
	asys.set_station(&"calle_funk")
	var t_wait := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_wait < 20000 and asys.radio.buffered_seconds() < 5.0:
		await get_tree().process_frame
	var waited := float(Time.get_ticks_msec() - t_wait) / 1000.0
	_t("radio_background_queue", asys.radio.buffered_seconds() >= 5.0, "%.1f s buffered after %.1f s wall" % [asys.radio.buffered_seconds(), waited])
	asys.radio_off()


# ---- exports -------------------------------------------------------------------------------------------------------------------
func _test_export() -> void:
	var ids := ["shot_pistol", "shot_rifle", "shot_shotgun", "shot_suppressed", "explosion_small", "explosion_big", "siren_police", "siren_police_yelp",
		"siren_ambulance", "siren_fire", "hurt_m", "hurt_f", "death_m", "scream", "horn_car", "skid", "crash_heavy", "step_concrete", "step_grass",
		"amb_sea", "amb_city", "amb_rain_heavy", "thunder", "ignition", "eng_car_v8_1", "eng_sports_2", "eng_heli_rotor_1", "eng_jet_1", "ui_cash", "ui_wanted_up"]
	var n := 0
	for id in ids:
		var w := Sfx.get_wav(StringName(id), 0)
		if w == null:
			continue
		var b := Synth.from_wav(w)
		Synth.save_wav_file(_abs_dir + "%s.wav" % id, b, w.mix_rate)
		if n < 12:
			An.plot(b, w.mix_rate).save_png(_abs_dir + "%s.png" % id)
		n += 1
	_t("wav_export", n == ids.size(), "%d files in screenshots/audio_check/" % n)


# ---- radio activation with a mock player / vehicle ----------------------------------------------------------------------------
func _wait_wall(ms: int, cond: Callable) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _test_radio_in_vehicle(main: Node) -> void:
	var asys = Game.sys(&"audio")
	if asys == null:
		return
	var radio = asys.radio
	var old_player = Game.player
	var mp := MockPlayer.new()
	var mv := MockVehicle.new()
	main.add_child(mp)
	main.add_child(mv)
	Game.player = mp
	asys.set_station(&"halcyon_fm")
	# 1) on foot far away: silent
	mp.global_position = Vector3(200, 0, 0)
	mv.global_position = Vector3.ZERO
	for i in 20:
		await get_tree().process_frame
	_t("radio_silent_on_foot", radio.gain < 0.05 and not asys.is_radio_playing(), "gain %.2f" % radio.gain)
	# 2) in the vehicle with the engine on: full level, generator running, frames pushed
	mp.current_vehicle = mv
	Events.vehicle_entered.emit(mv, mp, 0)
	var ok1: bool = await _wait_wall(15000, func() -> bool: return radio.gain > 0.95 and asys.is_radio_playing() and radio._cur_pos > 4000)
	_t("radio_plays_in_vehicle", ok1, "gain=%.2f playing=%s fed=%d frames, queued %.1fs" % [radio.gain, str(asys.is_radio_playing()), radio._cur_pos, radio.buffered_seconds()])
	var fx: Dictionary = Sfx.get_bus_fx("Radio")
	_t("radio_clear_inside_vehicle", not AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("Radio"), int(fx["lp_idx"])) and radio.muffle < 0.05, "muffle %.2f" % radio.muffle)
	# 3) engine off: radio dies
	mv.engine_on = false
	for i in 90:
		await get_tree().process_frame
	_t("radio_stops_when_engine_off", radio.gain < 0.05, "gain %.2f" % radio.gain)
	mv.engine_on = true
	# 4) player steps out next to the car: muffled and quiet
	mp.current_vehicle = null
	mp.global_position = Vector3(6, 0, 0)
	var ok4: bool = await _wait_wall(8000, func() -> bool: return radio.muffle > 0.95 and radio.gain > 0.05 and radio.gain < 0.6)
	_t("radio_muffled_outside", ok4, "gain %.2f muffle %.2f cutoff %.0f Hz" % [radio.gain, radio.muffle, (fx["lp"] as AudioEffectLowPassFilter).cutoff_hz])
	# 5) walks away: fades out completely
	mp.global_position = Vector3(90, 0, 0)
	var ok5: bool = await _wait_wall(8000, func() -> bool: return radio.gain < 0.02)
	_t("radio_fades_with_distance", ok5, "gain %.2f" % radio.gain)
	# bicycles never get a radio
	mv.vclass = &"bicycle"
	mp.current_vehicle = mv
	mp.global_position = Vector3.ZERO
	for i in 60:
		await get_tree().process_frame
	_t("radio_not_on_bicycle", radio.gain < 0.05, "gain %.2f" % radio.gain)
	Game.player = old_player
	mp.queue_free()
	mv.queue_free()
	asys.radio_off()


# ---- real vehicle smoke test: sirens + engine sound hookup ---------------------------------------------------------------------
func _test_vehicle_integration(main: Node) -> void:
	var asys = Game.sys(&"audio")
	if asys == null or Game.sys(&"vehicles") == null:
		_t("vehicle_integration_skipped", true, "no vehicle system")
		return
	var v = VehicleFactory.spawn(&"police_cruiser", Transform3D(Basis.IDENTITY, Vector3(6, 1.0, 6)), {})
	if v == null:
		_t("vehicle_integration_skipped", true, "VehicleFactory returned null")
		return
	await get_tree().process_frame
	Sfx.listener_pos = Vector3.ZERO
	v.engine_on = true
	v.siren_on = true
	var ok: bool = await _wait_wall(8000, func() -> bool: return not asys._siren_players.is_empty() or asys._has_siren_player(v))
	_t("vehicle_siren_hookup", ok, "siren players=%d" % asys._siren_players.size())
	var has_engine: bool = await _wait_wall(8000, func() -> bool: return asys._vehicle_has_engine_sound(v))
	_t("vehicle_engine_sound_hookup", has_engine, "EngineSound present (own or auto-attached): %s, foreign=%s" % [str(has_engine), str(asys._foreign_engine_seen)])
	v.siren_on = false
	await _wait_wall(5000, func() -> bool: return asys._siren_players.is_empty())
	_t("vehicle_siren_stops", asys._siren_players.is_empty(), "")
	if is_instance_valid(v):
		v.queue_free()
