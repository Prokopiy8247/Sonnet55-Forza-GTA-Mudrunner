class_name VehicleHud
extends Control
## Driving / flying instruments (bottom-right): speed dial with RPM arc + gear for ground vehicles, speed + knots for
## boats, artificial horizon + altitude / airspeed / heading / vertical speed for helicopters and planes.
## Reads the vehicle through the VehicleBase contract; optional properties are probed defensively
## (rpm01 / rpm_ratio / engine_rpm01, gear / current_gear). Missing RPM / gear values are estimated from speed.

enum Mode { HIDDEN, GROUND, BOAT, AIR }

const DIAL_DEFAULT := {&"car": 200.0, &"bike": 200.0, &"bicycle": 40.0, &"boat": 120.0}
const ARC_START := deg_to_rad(150.0)     # bottom-left
const ARC_SWEEP := deg_to_rad(240.0)

var mode: Mode = Mode.HIDDEN
var shown := 0.0

var speed_kmh := 0.0
var dial_max := 200.0
var rpm := 0.0
var gear := 1                 # -1 reverse, 0 neutral, 1.. gears
var show_gear := true
var health_ratio := 1.0
var vclass: StringName = &"car"
var headlights := false
var siren := false
var handbrake := false
var vehicle_name := ""
# air
var altitude_agl := 0.0
var altitude_msl := 0.0
var vspeed := 0.0
var heading := 0.0
var pitch := 0.0
var roll := 0.0
var throttle := 0.0
var _t := 0.0
var _speed_smooth := 0.0
var _rpm_smooth := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(460, 380)


func clear() -> void:
	mode = Mode.HIDDEN


## Reads the vehicle state. Called every frame while the player is seated.
func read(v: Node, dt: float) -> void:
	if v == null or not is_instance_valid(v):
		mode = Mode.HIDDEN
		return
	_t += dt
	vclass = v.get("vclass") if v.get("vclass") != null else GC.VC_CAR
	vehicle_name = str(v.get("display_name")) if v.get("display_name") != null else ""
	var kmh := 0.0
	if v.has_method("get_speed_kmh"):
		kmh = float(v.get_speed_kmh())
	elif v is RigidBody3D:
		kmh = (v as RigidBody3D).linear_velocity.length() * 3.6
	_speed_smooth = Util.damp(_speed_smooth, kmh, 14.0, dt)
	speed_kmh = _speed_smooth
	var mh = v.get("max_health")
	var hh = v.get("health")
	health_ratio = clampf(float(hh) / maxf(float(mh), 1.0), 0.0, 1.0) if mh != null and hh != null else 1.0
	headlights = bool(v.get("headlights_on")) if v.get("headlights_on") != null else false
	siren = bool(v.get("siren_on")) if v.get("siren_on") != null else false
	handbrake = bool(v.get("input_handbrake")) if v.get("input_handbrake") != null else false
	match vclass:
		GC.VC_HELI, GC.VC_PLANE:
			mode = Mode.AIR
			_read_air(v)
		GC.VC_BOAT:
			mode = Mode.BOAT
			show_gear = false
			dial_max = maxf(float(DIAL_DEFAULT[&"boat"]), ceilf(speed_kmh * 1.1 / 20.0) * 20.0)
		_:
			mode = Mode.GROUND
			var base_max: float = DIAL_DEFAULT.get(vclass, 200.0)
			dial_max = maxf(base_max, ceilf(speed_kmh * 1.08 / 20.0) * 20.0)
			show_gear = vclass == GC.VC_CAR or vclass == GC.VC_BIKE
			_read_drivetrain(v, dt)


func _read_drivetrain(v: Node, dt: float) -> void:
	var r = v.get("rpm01")
	if r == null:
		r = v.get("rpm_ratio")
	if r == null:
		r = v.get("engine_rpm01")
	var g = v.get("gear")
	if g == null:
		g = v.get("current_gear")
	var fwd := 1.0
	if v.has_method("get_forward_speed"):
		fwd = float(v.get_forward_speed())
	if g != null:
		gear = int(g)
	else:
		# estimate from speed so the readout is alive even before the vehicle model exposes a gearbox
		var limits := [0.0, 28.0, 55.0, 88.0, 125.0, 165.0]
		var gi := 1
		for i in range(1, limits.size()):
			if speed_kmh >= limits[i]:
				gi = i + 1
		gear = clampi(gi, 1, 6)
		if fwd < -0.5:
			gear = -1
		elif speed_kmh < 1.0:
			gear = 0
	if r != null:
		rpm = clampf(float(r), 0.0, 1.0)
	else:
		var limits2 := [0.0, 28.0, 55.0, 88.0, 125.0, 165.0, 210.0]
		var gidx := clampi(maxi(gear, 1) - 1, 0, 5)
		var span: float = limits2[gidx + 1] - limits2[gidx]
		rpm = clampf(0.22 + 0.72 * ((speed_kmh - limits2[gidx]) / span), 0.18, 1.0) if speed_kmh > 0.5 else 0.14
	_rpm_smooth = Util.damp(_rpm_smooth, rpm, 12.0, dt)


func _read_air(v: Node) -> void:
	var n := v as Node3D
	if n == null:
		return
	var b := n.global_transform.basis
	var f := -b.z
	pitch = rad_to_deg(asin(clampf(f.y, -1.0, 1.0)))
	roll = rad_to_deg(atan2(-b.x.y, b.y.y))
	heading = fposmod(-rad_to_deg(Util.dir_to_yaw(Vector3(f.x, 0.0, f.z))), 360.0)
	altitude_msl = n.global_position.y - GC.WATER_LEVEL
	altitude_agl = maxf(n.global_position.y - WorldLayout.terrain_height(n.global_position.x, n.global_position.z), 0.0)
	if v is RigidBody3D:
		vspeed = (v as RigidBody3D).linear_velocity.y
	var th = v.get("input_throttle")
	throttle = clampf(float(th), 0.0, 1.0) if th != null else 0.0


func _process(delta: float) -> void:
	var want := 1.0 if mode != Mode.HIDDEN else 0.0
	shown = move_toward(shown, want, delta * 5.0)
	visible = shown > 0.01
	if visible:
		queue_redraw()


# =====================================================================================================================
func _draw() -> void:
	if shown < 0.01:
		return
	draw_set_transform(Vector2(0, (1.0 - shown) * 24.0), 0.0, Vector2.ONE)
	match mode:
		Mode.GROUND, Mode.BOAT:
			_draw_dial()
		Mode.AIR:
			_draw_air()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_dial() -> void:
	var a := shown
	var fd := UITheme.font_display()
	var f := UITheme.font(true)
	var c := Vector2(size.x - 170.0, size.y - 205.0)
	var r := 132.0
	# backing disc
	draw_circle(c, r + 14.0, Color(0.02, 0.03, 0.05, 0.55 * a))
	draw_arc(c, r + 14.0, 0.0, TAU, 64, Color(1, 1, 1, 0.07 * a), 1.5, true)
	# speed arc
	draw_arc(c, r, ARC_START, ARC_START + ARC_SWEEP, 64, Color(1, 1, 1, 0.13 * a), 12.0, true)
	var sp := clampf(speed_kmh / dial_max, 0.0, 1.0)
	if sp > 0.003:
		var steps := maxi(int(sp * 64.0), 2)
		var prev := Vector2.ZERO
		for i in steps + 1:
			var u := float(i) / steps * sp
			var ang := ARC_START + ARC_SWEEP * u
			var p := c + Vector2(cos(ang), sin(ang)) * r
			if i > 0:
				var col := UITheme.C_ACCENT.lerp(UITheme.C_ACCENT2, smoothstep(0.55, 1.0, u))
				draw_line(prev, p, Color(col.r, col.g, col.b, a), 12.0, true)
			prev = p
	# tick marks every 20 km/h
	var tick_step := 20.0 if dial_max <= 240.0 else 40.0
	var tk := tick_step
	while tk < dial_max - 1.0:
		var ta := ARC_START + ARC_SWEEP * (tk / dial_max)
		var d := Vector2(cos(ta), sin(ta))
		draw_line(c + d * (r - 14.0), c + d * (r - 22.0), Color(1, 1, 1, 0.35 * a), 2.0, true)
		if fmod(tk, tick_step * 2.0) < 0.5:
			UIDraw.text_center(self, f, str(int(tk)), c + d * (r - 38.0), 15, Color(1, 1, 1, 0.45 * a))
		tk += tick_step
	# RPM arc (inner) for vehicles with a drivetrain
	if mode == Mode.GROUND and vclass != GC.VC_BICYCLE:
		var rr := r - 56.0
		draw_arc(c, rr, ARC_START, ARC_START + ARC_SWEEP, 48, Color(1, 1, 1, 0.1 * a), 5.0, true)
		var red_from := 0.82
		draw_arc(c, rr, ARC_START + ARC_SWEEP * red_from, ARC_START + ARC_SWEEP, 12, Color(1, 0.3, 0.3, 0.35 * a), 5.0, true)
		var rp := clampf(_rpm_smooth, 0.0, 1.0)
		if rp > 0.01:
			var rcol := UITheme.C_WARN.lerp(UITheme.C_DANGER, smoothstep(red_from - 0.05, 1.0, rp))
			draw_arc(c, rr, ARC_START, ARC_START + ARC_SWEEP * rp, 40, Color(rcol.r, rcol.g, rcol.b, a), 5.0, true)
	# numbers
	var s := str(int(round(speed_kmh)))
	UIDraw.text_center(self, fd, s, c + Vector2(0, -8), 84, Color(1, 1, 1, a))
	UIDraw.text_center(self, f, "KM/H", c + Vector2(0, 40), 18, Color(UITheme.C_DIM.r, UITheme.C_DIM.g, UITheme.C_DIM.b, a))
	if mode == Mode.BOAT:
		UIDraw.text_center(self, f, "%d KN" % int(round(speed_kmh / 1.852)), c + Vector2(0, 66), 18, Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, a))
	elif show_gear:
		var gtxt := "R" if gear < 0 else ("N" if gear == 0 else str(gear))
		var gr := Rect2(c.x - 22.0, c.y + 56.0, 44.0, 38.0)
		UIDraw.rrect(self, gr, Color(0, 0, 0, 0.5 * a), 9, 1.5, Color(1, 1, 1, 0.35 * a))
		UIDraw.text_center(self, fd, gtxt, gr.get_center() + Vector2(0, 1), 30, Color(1, 1, 1, a) if gear >= 0 else Color(1, 0.55, 0.55, a))
	# status lights
	var iy := c.y + r + 24.0
	var ix := c.x - 90.0
	_light(Vector2(ix, iy), "LIGHTS", headlights, UITheme.C_ACCENT, a)
	_light(Vector2(ix + 62.0, iy), "BRAKE", handbrake, UITheme.C_DANGER, a)
	if siren:
		_light(Vector2(ix + 124.0, iy), "SIREN", true, UITheme.C_POLICE_BLUE if fmod(_t, 0.6) < 0.3 else UITheme.C_POLICE_RED, a)
	# health bar
	_health_bar(Rect2(c.x - 130.0, c.y + r + 44.0, 260.0, 10.0), a)
	if vehicle_name != "":
		UIDraw.text(self, f, vehicle_name.to_upper(), Vector2(c.x - 130.0, c.y + r + 76.0), 15, Color(UITheme.C_DIM.r, UITheme.C_DIM.g, UITheme.C_DIM.b, a * 0.9))


func _light(p: Vector2, text: String, on: bool, col: Color, a: float) -> void:
	var f := UITheme.font(true)
	var c := col if on else Color(1, 1, 1, 0.22)
	draw_circle(p + Vector2(0, 0), 4.0, Color(c.r, c.g, c.b, (1.0 if on else 0.6) * a * (c.a if not on else 1.0)))
	UIDraw.text(self, f, text, Vector2(p.x + 8.0, p.y + 5.0), 12, Color(c.r, c.g, c.b, (0.95 if on else 0.9) * a * (c.a if not on else 1.0)))


func _health_bar(r: Rect2, a: float) -> void:
	var col := UITheme.C_OK.lerp(UITheme.C_DANGER, 1.0 - smoothstep(0.15, 0.7, health_ratio))
	UIDraw.rrect(self, r.grow(2.0), Color(0, 0, 0, 0.5 * a), 8)
	UIDraw.rrect(self, r, Color(1, 1, 1, 0.1 * a), 5)
	UIDraw.rrect(self, Rect2(r.position, Vector2(maxf(r.size.x * health_ratio, 6.0), r.size.y)), Color(col.r, col.g, col.b, a), 5)
	# wrench-ish glyph at the left end
	var w := r.position + Vector2(-18.0, r.size.y * 0.5)
	draw_line(w + Vector2(-5, 5), w + Vector2(5, -5), Color(col.r, col.g, col.b, a), 3.0, true)
	draw_circle(w + Vector2(5, -5), 3.4, Color(col.r, col.g, col.b, a))


# ---- Aircraft ----------------------------------------------------------------------------------------------------------
func _draw_air() -> void:
	var a := shown
	var fd := UITheme.font_display()
	var f := UITheme.font(true)
	var panel := Rect2(size.x - 440.0, size.y - 250.0, 440.0, 250.0)
	UIDraw.rrect(self, panel.grow(2.0), Color(0, 0, 0, 0.22 * a), 20)
	UIDraw.rrect(self, panel, Color(0.035, 0.05, 0.075, 0.82 * a), 18, 1, Color(1, 1, 1, 0.1 * a))
	# artificial horizon
	var hc := panel.position + Vector2(112.0, 122.0)
	var hr := 82.0
	_draw_horizon(hc, hr, a)
	# heading ribbon text
	var card := _cardinal(heading)
	UIDraw.text(self, f, "HDG", Vector2(panel.position.x + 18.0, panel.position.y + 30.0), 15, Color(UITheme.C_DIM.r, UITheme.C_DIM.g, UITheme.C_DIM.b, a))
	UIDraw.text_shadow(self, fd, "%03d %s" % [int(round(heading)) % 360, card], Vector2(panel.position.x + 62.0, panel.position.y + 33.0), 26, Color(1, 1, 1, a))
	# readouts on the right
	var rx := panel.position.x + 226.0
	UIDraw.text(self, f, "ALTITUDE", Vector2(rx, panel.position.y + 40.0), 15, Color(UITheme.C_DIM.r, UITheme.C_DIM.g, UITheme.C_DIM.b, a))
	UIDraw.text_shadow(self, fd, "%d m" % int(altitude_agl), Vector2(rx, panel.position.y + 86.0), 48, Color(1, 1, 1, a))
	UIDraw.text(self, f, "AIRSPEED", Vector2(rx, panel.position.y + 118.0), 15, Color(UITheme.C_DIM.r, UITheme.C_DIM.g, UITheme.C_DIM.b, a))
	UIDraw.text_shadow(self, fd, "%d km/h" % int(round(speed_kmh)), Vector2(rx, panel.position.y + 158.0), 40, Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, a))
	# vertical speed
	var vs_col := UITheme.C_OK if vspeed >= 0.0 else UITheme.C_WARN
	UIDraw.text(self, f, "V/S", Vector2(rx, panel.position.y + 190.0), 15, Color(UITheme.C_DIM.r, UITheme.C_DIM.g, UITheme.C_DIM.b, a))
	UIDraw.text_shadow(self, fd, "%+.1f m/s" % vspeed, Vector2(rx + 48.0, panel.position.y + 192.0), 24, Color(vs_col.r, vs_col.g, vs_col.b, a))
	if vclass == GC.VC_PLANE:
		var tr := Rect2(panel.end.x - 30.0, panel.position.y + 30.0, 10.0, 130.0)
		UIDraw.rrect(self, tr, Color(1, 1, 1, 0.12 * a), 5)
		UIDraw.rrect(self, Rect2(tr.position.x, tr.end.y - tr.size.y * throttle, tr.size.x, maxf(tr.size.y * throttle, 5.0)), Color(UITheme.C_WARN.r, UITheme.C_WARN.g, UITheme.C_WARN.b, a), 5)
		UIDraw.text_center(self, f, "THR", Vector2(tr.get_center().x, tr.end.y + 14.0), 12, Color(UITheme.C_DIM.r, UITheme.C_DIM.g, UITheme.C_DIM.b, a))
	_health_bar(Rect2(panel.position.x + 40.0, panel.end.y - 34.0, 210.0, 10.0), a)
	if vehicle_name != "":
		UIDraw.text(self, f, vehicle_name.to_upper(), Vector2(panel.position.x + 270.0, panel.end.y - 26.0), 15, Color(UITheme.C_DIM.r, UITheme.C_DIM.g, UITheme.C_DIM.b, a))


func _draw_horizon(c: Vector2, r: float, a: float) -> void:
	var sky := Color(0.18, 0.5, 0.82, a)
	var ground := Color(0.42, 0.28, 0.17, a)
	draw_circle(c, r + 5.0, Color(0.02, 0.03, 0.05, 0.9 * a))
	draw_circle(c, r, sky)
	# horizon normal rotated by roll; offset by pitch (1 deg = 1.6 px)
	var rr := deg_to_rad(roll)
	var up := Vector2(-sin(rr), -cos(rr))         # world-up as seen from the cockpit (rotates against the roll)
	var off := pitch * 1.6                        # horizon moves down when pitching up
	var n := -up                                  # points to the ground side
	var poly := PackedVector2Array()
	var steps := 48
	var pts: Array[Vector2] = []
	for i in steps:
		var ang := TAU * float(i) / steps
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	# signed distance along n with the horizon line at distance `off` along n (pitch up => horizon lower => ground smaller)
	var dists: Array[float] = []
	for p in pts:
		dists.append(p.dot(n) - off)
	for i in steps:
		var j := (i + 1) % steps
		var di := dists[i]
		var dj := dists[j]
		if di >= 0.0:
			poly.append(c + pts[i])
		if (di >= 0.0) != (dj >= 0.0):
			var tt := di / (di - dj)
			poly.append(c + pts[i].lerp(pts[j], tt))
	if poly.size() >= 3 and Geometry2D.triangulate_polygon(poly).size() >= 3:
		draw_colored_polygon(poly, ground)
	# horizon line + pitch ladder
	var lc := n * off
	var tang := Vector2(-n.y, n.x)
	draw_line(c + lc - tang * r, c + lc + tang * r, Color(1, 1, 1, 0.85 * a), 1.6, true)
	for k in [-20, -10, 10, 20]:
		var lp := lc + up * (float(k) * 1.6)
		if lp.length() < r - 12.0:
			draw_line(c + lp - tang * 14.0, c + lp + tang * 14.0, Color(1, 1, 1, 0.6 * a), 1.4, true)
	# fixed aircraft symbol
	draw_line(c + Vector2(-26, 0), c + Vector2(-9, 0), Color(1, 0.85, 0.3, a), 3.4, true)
	draw_line(c + Vector2(9, 0), c + Vector2(26, 0), Color(1, 0.85, 0.3, a), 3.4, true)
	draw_circle(c, 3.0, Color(1, 0.85, 0.3, a))
	draw_arc(c, r, 0.0, TAU, 56, Color(1, 1, 1, 0.5 * a), 2.0, true)


func _cardinal(deg: float) -> String:
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[int(round(deg / 45.0)) % 8]
