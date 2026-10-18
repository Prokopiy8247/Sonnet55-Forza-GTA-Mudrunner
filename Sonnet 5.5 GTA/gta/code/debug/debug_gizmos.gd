class_name DebugGizmos
extends Node3D
## Diagnostic line drawing for the benchmark menu: wanted debug (last-known marker + search circle + police sight cones),
## lane graph and pedestrian graph around the player. One ImmediateMesh rebuilt at 4 Hz, and ONLY while a cheat flag is on
## (Game.cheats dbg_wanted / dbg_lanes / dbg_peds); otherwise process is off and the mesh is hidden (zero cost).

const RADIUS := 70.0
const CHEATS: Array[String] = ["dbg_wanted", "dbg_lanes", "dbg_peds"]

var _mi: MeshInstance3D
var _mesh: ImmediateMesh
var _acc := 0.0
var active := false


func _ready() -> void:
	name = "DebugGizmos"
	_mesh = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.extra_cull_margin = 4000.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = false
	m.render_priority = 10
	_mi.material_override = m
	_mi.top_level = true
	add_child(_mi)
	_mi.visible = false
	set_process(false)


## Called by the menu whenever one of the cheat flags changed.
func refresh_state() -> void:
	active = false
	for k in CHEATS:
		if bool(Game.cheats.get(k, false)):
			active = true
	set_process(active)
	if _mi != null:
		_mi.visible = active
	if not active and _mesh != null:
		_mesh.clear_surfaces()
	_acc = 1.0


func _process(dt: float) -> void:
	_acc += dt
	if _acc < 0.25:
		return
	_acc = 0.0
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var p = Game.player
	if not is_instance_valid(p):
		return
	var pos: Vector3 = p.global_position
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var verts := 0
	if bool(Game.cheats.get("dbg_lanes", false)):
		var g: LaneGraph = WorldLayout.lanes
		for i in g.points_in_radius(pos, RADIUS):
			var a: Vector3 = g.positions[i] + Vector3(0, 0.35, 0)
			var col := Color(1.0, 0.24, 0.6) if g.kind[i] == LaneGraph.KIND_CONNECTOR else (Color(1.0, 0.7, 0.28) if g.signal_id[i] >= 0 else Color(0.2, 0.88, 1.0))
			for j in g.next[i]:
				_line(a, g.positions[j] + Vector3(0, 0.35, 0), col)
				verts += 2
			if g.signal_id[i] >= 0:
				_line(a, a + Vector3(0, 2.5, 0), Color(1.0, 0.7, 0.28))
				verts += 2
	if bool(Game.cheats.get("dbg_peds", false)):
		var pg: PedGraph = WorldLayout.ped_graph
		for i in pg.points_in_radius(pos, RADIUS):
			var a2: Vector3 = pg.positions[i] + Vector3(0, 0.3, 0)
			var col2 := Color(0.48, 0.9, 0.58) if pg.zone[i] != PedGraph.ZONE_CROSSING else Color(1.0, 1.0, 1.0)
			for j in pg.links[i]:
				if j > i:
					_line(a2, pg.positions[j] + Vector3(0, 0.3, 0), col2)
					verts += 2
	if bool(Game.cheats.get("dbg_wanted", false)) and Game.wanted_level > 0:
		var w = Game.sys(&"wanted")
		if w != null and w.has_method("get_last_known_position"):
			var lk: Vector3 = w.get_last_known_position()
			var rad: float = maxf(float(w.get_search_radius()), 8.0) if w.has_method("get_search_radius") else 20.0
			var gy := lk.y + 0.5
			var amber := Color(1.0, 0.7, 0.28)
			_line(Vector3(lk.x, gy, lk.z), Vector3(lk.x, gy + 40.0, lk.z), amber)
			var segs := 48
			for s in segs:
				var a0 := TAU * float(s) / segs
				var a1 := TAU * float(s + 1) / segs
				_line(Vector3(lk.x + cos(a0) * rad, gy, lk.z + sin(a0) * rad), Vector3(lk.x + cos(a1) * rad, gy, lk.z + sin(a1) * rad), amber)
				verts += 2
			verts += 2
		for n in get_tree().get_nodes_in_group(GC.G_POLICE):
			if not (n is Node3D) or not is_instance_valid(n):
				continue
			var np: Vector3 = (n as Node3D).global_position
			if np.distance_to(pos) > 220.0:
				continue
			var f := -(n as Node3D).global_transform.basis.z
			f.y = 0.0
			f = f.normalized()
			var base := np + Vector3(0, 1.2, 0)
			var red := Color(1.0, 0.23, 0.29)
			var reach := 30.0
			_line(base, base + f * reach, red)
			_line(base, base + f.rotated(Vector3.UP, 0.6) * reach * 0.8, red.darkened(0.3))
			_line(base, base + f.rotated(Vector3.UP, -0.6) * reach * 0.8, red.darkened(0.3))
			verts += 6
	if verts == 0:
		_line(pos, pos + Vector3(0, 0.01, 0), Color(0, 0, 0, 0))       # a surface needs at least one line
	_mesh.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)
