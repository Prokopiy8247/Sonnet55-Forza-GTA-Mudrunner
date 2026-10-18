class_name ContentManager
extends Node
## The single runtime node of the world content: ticks 4x per second (no per-prop scripts).
##  * pushes the game clock into the window / far-LOD materials (lights-out hours)
##  * updates traffic-signal heads from WorldLayout.signal_state (street_furniture registers them)
##  * freezes / releases dynamic props by distance (street_furniture registers them)

const TICK := 0.25

var batch: ContentBatch = null
var signal_hooks: Array = []         # [{mm: MultiMesh, index: int, id: int, phase: int, state: int}]
var props: Array = []                # dynamic RigidBody3D props
var _t := 0.0
var _prop_t := 0.0
var _slice := 0


func setup(b: ContentBatch) -> void:
	batch = b
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_update_hour()


func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	_t = 0.0
	_update_hour()
	_update_signals()
	_prop_t += TICK
	if _prop_t >= 1.0:
		_prop_t = 0.0
		_update_props()


func _update_hour() -> void:
	FacadeMaterials.set_hour(Game.time_of_day)


## Game time used for the signal phases. The Traffic agent can override by calling set_signal_clock().
var signal_clock := Callable()

func set_signal_clock(c: Callable) -> void:
	signal_clock = c


func _signal_time() -> float:
	if signal_clock.is_valid():
		return float(signal_clock.call())
	return Time.get_ticks_msec() / 1000.0


func _update_signals() -> void:
	if signal_hooks.is_empty():
		return
	var t := _signal_time()
	for h in signal_hooks:
		var mm: MultiMesh = h["mm"]
		if mm == null:
			continue
		var st := WorldLayout.signal_state(int(h["id"]), int(h["phase"]), t)
		if st != int(h["state"]):
			h["state"] = st
			mm.set_instance_custom_data(int(h["index"]), Color(float(st), 0.0, 0.0, 0.0))


func register_signal(mm: MultiMesh, index: int, sig_id: int, phase: int) -> void:
	signal_hooks.append({"mm": mm, "index": index, "id": sig_id, "phase": phase, "state": -1})


func register_prop(p: RigidBody3D) -> void:
	props.append(p)


func _update_props() -> void:
	if props.is_empty():
		return
	var ppos := Game.get_player_position()
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		ppos = cam.global_position
	# check a slice per call to keep it cheap
	var n := props.size()
	var step := maxi(1, n / 4)
	var start := _slice
	_slice = (_slice + step) % maxi(n, 1)
	for k in step:
		var i := (start + k) % n
		var p: RigidBody3D = props[i]
		if not is_instance_valid(p):
			continue
		var d2 := p.global_position.distance_squared_to(ppos)
		if d2 > 150.0 * 150.0:
			if not p.freeze:
				p.freeze = true
				p.set_meta("far_frozen", true)
		elif p.has_meta("far_frozen") and d2 < 120.0 * 120.0:
			p.remove_meta("far_frozen")
			p.freeze = false
