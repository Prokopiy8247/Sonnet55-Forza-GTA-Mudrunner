class_name DeathScreen
extends Control
## "KNOCKED OUT" (slow-mo, desaturated, fade to black) and "BUSTED" (police blue grade, quick fade) sequences, and the
## fade-in after Events.player_respawned. UIRoot wires Events.player_died / player_busted / player_respawned here.
## Timing uses real time (Engine.time_scale is slowed during the sequence).

enum State { IDLE, KNOCKED, BUSTED, BLACK }

const KNOCKED_FADE_AT := 2.4        # real seconds until the fade-to-black starts
const KNOCKED_FADE_TIME := 1.2
const BUSTED_FADE_AT := 1.7
const BUSTED_FADE_TIME := 0.8
const FAILSAFE := 12.0              # seconds of black without a respawn event before the screen is released

var state: State = State.IDLE
var feedback: DamageFeedback = null
var ui: Node = null                 # UIRoot (fade API)

var _t := 0.0
var _fading := false
var _slow := 1.0
var _saved_scale := 1.0
var _text_alpha := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func begin_knocked() -> void:
	_begin(State.KNOCKED, 0.28)


func begin_busted() -> void:
	_begin(State.BUSTED, 0.55)


func _begin(s: State, slow: float) -> void:
	if state != State.IDLE:
		return
	state = s
	_t = 0.0
	_fading = false
	_slow = slow
	_saved_scale = Engine.time_scale if Engine.time_scale > 0.9 else 1.0
	Engine.time_scale = slow
	if feedback != null:
		feedback.death_tint_color = Color(1.0, 0.42, 0.42) if s == State.KNOCKED else Color(0.5, 0.7, 1.0)
	if Sfx != null:
		Sfx.play_ui(&"ui_wasted" if s == State.KNOCKED else &"ui_busted")


## Called on Events.player_respawned: restore time, release the screen, fade in from black.
func on_respawned() -> void:
	Engine.time_scale = 1.0
	state = State.IDLE
	_text_alpha = 0.0
	if feedback != null:
		feedback.death_desat = 0.0
		feedback.death_tint = 0.0
	if ui != null and ui.has_method("fade"):
		ui.fade(false, 1.3)
	queue_redraw()
	set_process(true)


func is_active() -> bool:
	return state != State.IDLE


func _process(delta: float) -> void:
	if state == State.IDLE:
		if _text_alpha > 0.0:
			_text_alpha = move_toward(_text_alpha, 0.0, delta * 4.0)
			queue_redraw()
		return
	var dt := delta / maxf(Engine.time_scale, 0.05)
	dt = minf(dt, 0.1)
	_t += dt
	if state == State.KNOCKED or state == State.BUSTED:
		var k := clampf(_t / 0.7, 0.0, 1.0)
		if feedback != null:
			feedback.death_desat = k * (1.0 if state == State.KNOCKED else 0.45)
			feedback.death_tint = k * (0.85 if state == State.KNOCKED else 0.55)
		_text_alpha = clampf(_t / 0.45, 0.0, 1.0)
		var fade_at := KNOCKED_FADE_AT if state == State.KNOCKED else BUSTED_FADE_AT
		var fade_time := KNOCKED_FADE_TIME if state == State.KNOCKED else BUSTED_FADE_TIME
		if not _fading and _t >= fade_at:
			_fading = true
			if ui != null and ui.has_method("fade"):
				ui.fade(true, fade_time)
			# gently return to normal speed while the screen goes black
			Engine.time_scale = lerpf(_slow, 1.0, 0.5)
		if _fading and _t >= fade_at + fade_time:
			state = State.BLACK
			_t = 0.0
	elif state == State.BLACK:
		_text_alpha = move_toward(_text_alpha, 0.0, dt * 2.0)
		if _t > FAILSAFE:
			push_warning("DeathScreen: no player_respawned after %.0fs - releasing the screen" % FAILSAFE)
			on_respawned()
	queue_redraw()


func _draw() -> void:
	if _text_alpha <= 0.01 or state == State.IDLE:
		return
	var vp := size
	var fd := UITheme.font_display()
	var f := UITheme.font(true)
	var busted := state == State.BUSTED
	var txt := "BUSTED" if busted else "KNOCKED OUT"
	var col := Color(0.55, 0.85, 1.0) if busted else Color(1.0, 0.93, 0.93)
	var a := _text_alpha
	var sz := 150
	var track := 16.0
	var total := 0.0
	for i in txt.length():
		total += fd.get_string_size(txt[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x + track
	total -= track
	var grow := 1.0 + (1.0 - UIDraw.ease_out(_t / 0.9)) * 0.08
	draw_set_transform(Vector2(vp.x * 0.5, vp.y * 0.5), 0.0, Vector2(grow, grow))
	var x := -total * 0.5
	var y := 46.0
	for i in txt.length():
		var ch := txt[i]
		var cw := fd.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x
		UIDraw.text_shadow(self, fd, ch, Vector2(x, y), sz, Color(col.r, col.g, col.b, a))
		x += cw + track
	# accent underline: magenta for knocked out, alternating police red / blue for busted
	var lw := total * UIDraw.ease_out(_t / 0.8)
	if busted:
		var red := fmod(_t * 3.0, 2.0) < 1.0
		var half := lw * 0.5
		UIDraw.rrect(self, Rect2(-half, 74.0, half - 3.0, 7.0), Color(1, 0.23, 0.29, a * (1.0 if red else 0.3)), 3)
		UIDraw.rrect(self, Rect2(3.0, 74.0, half - 3.0, 7.0), Color(0.23, 0.48, 1.0, a * (0.3 if red else 1.0)), 3)
	else:
		UIDraw.rrect(self, Rect2(-lw * 0.5, 74.0, lw, 7.0), Color(UITheme.C_ACCENT2.r, UITheme.C_ACCENT2.g, UITheme.C_ACCENT2.b, a), 3)
	var sub := "Placed under arrest" if busted else "You went down"
	UIDraw.text_center(self, f, sub.to_upper(), Vector2(0, 118.0), 22, Color(1, 1, 1, a * 0.7))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
