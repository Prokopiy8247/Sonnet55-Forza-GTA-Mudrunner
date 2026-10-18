extends Node
## Autoload "Game": thin hub for shared references and global state. NOT a place for gameplay logic.
## Systems are registered by Main under well-known names (see docs/ARCHITECTURE.md section 4):
##   Game.sys(&"wanted"), Game.sys(&"traffic"), ... -> returns the system Node or null if not booted.
## Always null-check: a system may be missing while others are still being built.

var main: Node = null
var player = null                    # CharacterBase of the human player (untyped on purpose)
var world: Node3D = null             # WorldRoot instance
var ui: Node = null                  # UIRoot instance
var gameplay_camera: Camera3D = null # whichever camera currently renders gameplay (owner updates it)
var systems: Dictionary = {}         # StringName -> Node

var rng := RandomNumberGenerator.new()

var settings: Dictionary = {
	"master_volume": 0.8, "music_volume": 0.6, "sfx_volume": 1.0,
	"mouse_sensitivity": 1.0, "invert_y": false, "fov": 75.0,
	"camera_shake": true, "traffic_density": 1.0, "ped_density": 1.0,
	"shadows": true, "fullscreen": false,
}

# ---- Economy -------------------------------------------------------------------------
var cash: int = 5000: set = _set_cash

# ---- World time & weather (EnvironmentSystem advances/owns these) ---------------------
var time_of_day: float = 9.5         # hours, 0..24
var time_scale: float = 60.0         # game seconds per real second (24h cycle = 24 real minutes)
var time_frozen := false
var weather: StringName = &"clear"
var rain_intensity := 0.0            # 0..1
var wetness := 0.0                   # 0..1 wet road look / reduced grip
var fog_amount := 0.0                # 0..1
var wind := Vector3(1, 0, 0.3)

# ---- Wanted mirror (WantedSystem writes, everybody reads cheaply) --------------------
var wanted_level := 0
var wanted_state: StringName = &"clear"   # &"clear" &"pursuit" &"search"

# ---- Debug / cheat toggles (DebugMenu writes, systems read) --------------------------
var cheats: Dictionary = {
	"invulnerable": false, "infinite_ammo": false, "traffic": true, "pedestrians": true,
	"wildlife": true, "show_fps": false, "show_coords": false, "never_wanted": false,
	"scuba": false, "infinite_lungs": false,
}

var paused := false

## Map waypoint set from the full-screen map (Vector3.INF = none). UIRoot writes it, GPS/minimap read it.
var waypoint := Vector3.INF
var has_waypoint := false


## Global shader parameters available to every shader as `global uniform float gta_night;` etc.
## EnvironmentSystem updates them via set_global(); registered here so they exist before ANY material is created.
const SHADER_GLOBALS := {
	"gta_night": 0.0,      # 0 = day, 1 = full night (window / neon / lamp emission)
	"gta_wetness": 0.0,    # 0 dry .. 1 soaked (roads/terrain darken + gloss)
	"gta_rain": 0.0,       # 0..1 rain intensity
	"gta_fog": 0.0,        # 0..1 extra weather fog amount
	"gta_time": 0.0,       # game seconds (wraps every 24h) for slow animated shaders
	"gta_sun_energy": 1.0, # 0..1 sun strength
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	for gname in SHADER_GLOBALS:
		RenderingServer.global_shader_parameter_add(gname, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, SHADER_GLOBALS[gname])


func set_global(gname: StringName, value: float) -> void:
	RenderingServer.global_shader_parameter_set(gname, value)


# ---- Systems registry -------------------------------------------------------------------
func sys(system_name: StringName) -> Variant:
	var s = systems.get(system_name, null)
	return s if is_instance_valid(s) else null


func has_sys(system_name: StringName) -> bool:
	return sys(system_name) != null


# ---- Helpers ----------------------------------------------------------------------------
func notify(text: String, kind: StringName = &"info") -> void:
	Events.notification.emit(text, kind)


func add_cash(amount: int) -> void:
	cash += amount


func can_afford(amount: int) -> bool:
	return cash >= amount


func spend_cash(amount: int) -> bool:
	if cash < amount:
		return false
	cash -= amount
	return true


func _set_cash(value: int) -> void:
	var old := cash
	cash = maxi(value, 0)
	if cash != old:
		Events.cash_changed.emit(cash, cash - old)


## Follows the real sun when the EnvironmentSystem exists (it knows sunrise/sunset), else a fixed clock window.
func is_night() -> bool:
	var env = sys(&"environment")
	if env != null and env.has_method("is_night"):
		return env.is_night()
	return time_of_day < 5.5 or time_of_day > 20.5


## 0 at deep night .. 1 at midday (rough sun strength, for cheap light logic)
func daylight() -> float:
	var t := time_of_day
	if t < 5.0 or t > 21.0:
		return 0.0
	return clampf(sin((t - 5.0) / 16.0 * PI) * 1.4, 0.0, 1.0)


func set_paused(value: bool) -> void:
	paused = value
	get_tree().paused = value
	Events.game_paused.emit(value)


func get_player_position() -> Vector3:
	if is_instance_valid(player):
		return player.global_position
	return Vector3.ZERO


func get_vehicles() -> Array[Node]:
	return get_tree().get_nodes_in_group(GC.G_VEHICLE)


## Nearest node of a group within max_dist (XZ-distance), or null.
func nearest_in_group(group: StringName, pos: Vector3, max_dist: float = INF, exclude: Node = null) -> Node:
	var best: Node = null
	var best_d := max_dist * max_dist
	for n in get_tree().get_nodes_in_group(group):
		if n == exclude or not (n is Node3D):
			continue
		var d := Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best = n
	return best


func get_district(pos: Vector3) -> StringName:
	return WorldLayout.district_at(pos.x, pos.z)
