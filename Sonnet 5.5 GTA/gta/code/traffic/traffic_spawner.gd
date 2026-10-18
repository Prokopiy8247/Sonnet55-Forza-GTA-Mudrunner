class_name TrafficSpawner
extends RefCounted
## Spawn policy of civilian traffic: WHERE (lane points in a ring around the player, outside the camera view or behind occluders,
## free of other vehicles, not in water), WHAT (vehicle mix by district / road type, curated "Halcyon" colours) and HOW MANY
## (density by district x time of day x settings). TrafficManager owns the cars; this class only decides.

## Curated paint palette: sun-bleached pastels, deep charcoal, a few saturated accents (art direction section 1).
const PALETTE: Array[Color] = [
	Color("#e8e4da"), Color("#e8e4da"), Color("#2a2d33"), Color("#2a2d33"), Color("#8d94a0"), Color("#4a4f58"),
	Color("#3aa6a0"), Color("#e0705a"), Color("#d9a441"), Color("#6fb7e8"), Color("#26407a"), Color("#4b8a5f"),
	Color("#8e2f3f"), Color("#9c88c8"), Color("#8fd3b6"), Color("#efe3c0"), Color("#c43a3a"), Color("#2f6fb5"),
]
const ACCENT_PALETTE: Array[Color] = [Color("#ff3d9a"), Color("#34e0ff"), Color("#ffb347"), Color("#7be495")]

## weights per district: vehicle id -> weight
const MIX := {
	&"downtown": {&"taxi": 2.4, &"sedan": 2.0, &"compact": 1.7, &"suv": 1.0, &"van": 0.8, &"pickup": 0.3, &"muscle": 0.25, &"truck": 0.12},
	&"industrial": {&"truck": 2.1, &"van": 1.9, &"pickup": 2.0, &"sedan": 0.7, &"suv": 0.5, &"compact": 0.35, &"taxi": 0.1, &"muscle": 0.2},
	&"residential": {&"compact": 2.3, &"suv": 1.8, &"sedan": 1.7, &"pickup": 1.0, &"van": 0.6, &"taxi": 0.15, &"muscle": 0.25, &"truck": 0.05},
	&"arterial": {&"muscle": 1.1, &"sports": 0.9, &"sedan": 1.5, &"suv": 1.2, &"compact": 0.8, &"taxi": 0.8, &"pickup": 0.6, &"van": 0.5, &"truck": 0.4},
	&"default": {&"sedan": 1.6, &"compact": 1.3, &"suv": 1.2, &"pickup": 1.0, &"van": 0.8, &"taxi": 0.5, &"muscle": 0.2, &"truck": 0.2},
}

## relative traffic intensity per district (1 = busiest)
const DISTRICT_DENSITY := {
	&"downtown": 1.0, &"industrial": 0.8, &"residential": 0.6, &"waterfront": 0.5, &"airport": 0.45, &"beach": 0.5, &"park_hills": 0.35,
}

## hour -> traffic multiplier (rush hours busy, night quiet), linearly interpolated
const HOURLY: Array = [[0.0, 0.30], [4.0, 0.22], [6.0, 0.50], [8.0, 1.0], [10.0, 0.78], [12.0, 0.88], [15.0, 0.80], [17.5, 1.0],
	[20.0, 0.66], [22.0, 0.46], [24.0, 0.30]]

var _ids_ok: Dictionary = {}


static func time_factor(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	for i in range(1, HOURLY.size()):
		var a: Array = HOURLY[i - 1]
		var b: Array = HOURLY[i]
		if h <= float(b[0]):
			var t := (h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return lerpf(float(a[1]), float(b[1]), t)
	return 0.3


static func district_factor(d: StringName) -> float:
	return float(DISTRICT_DENSITY.get(d, 0.4))


## Target number of active traffic cars for the current situation.
static func target_count(hard_cap: int, player_pos: Vector3, hour: float, setting: float) -> int:
	var d := WorldLayout.district_at(player_pos.x, player_pos.z)
	var df := district_factor(d)
	var f := time_factor(hour) * (0.55 + 0.45 * df) * clampf(setting, 0.0, 1.6)
	return clampi(int(roundf(float(hard_cap) * f)), 0, 40)


func pick_vehicle(pos: Vector3, lane_kind: int, rng: RandomNumberGenerator) -> StringName:
	var d: StringName = WorldLayout.district_at(pos.x, pos.z)
	var key: StringName = &"default"
	if lane_kind == LaneGraph.KIND_HIGHWAY:
		key = &"arterial"
	elif MIX.has(d):
		key = d
	var table: Dictionary = MIX[key]
	var total := 0.0
	for id in table:
		if _usable(id):
			total += float(table[id])
	if total <= 0.0:
		return &"sedan"
	var r := rng.randf() * total
	for id in table:
		if not _usable(id):
			continue
		r -= float(table[id])
		if r <= 0.0:
			return id
	return &"sedan"


func _usable(id: StringName) -> bool:
	if _ids_ok.has(id):
		return _ids_ok[id]
	var ok: bool = VehicleDefs.has(id) and VehicleDefs.is_implemented(id) and not (VehicleDefs.get_def(id).get("faction", GC.F_CIVILIAN) == GC.F_POLICE)
	_ids_ok[id] = ok
	return ok


## Paint options for VehicleFactory.spawn: {"paint", "paint2", "finish"}; taxis / trucks keep their authored colours.
func pick_paint(id: StringName, rng: RandomNumberGenerator) -> Dictionary:
	var def := VehicleDefs.get_def(id)
	var paints: Array = def.get("paints", [])
	var opts := {}
	if id == &"taxi" or (paints.size() == 1):
		opts["finish"] = &"gloss"
		return opts
	var c: Color
	if id == &"muscle" and rng.randf() < 0.35:
		c = ACCENT_PALETTE[rng.randi() % ACCENT_PALETTE.size()]
	elif id == &"truck" or id == &"van":
		c = (paints[rng.randi() % paints.size()] if not paints.is_empty() else PALETTE[rng.randi() % PALETTE.size()])
		if id == &"van" and rng.randf() < 0.6:
			c = PALETTE[rng.randi() % PALETTE.size()]
	else:
		c = PALETTE[rng.randi() % PALETTE.size()]
	# small per-car variation so identical palette entries are not clones
	c = c.lightened(rng.randf_range(-0.05, 0.06)) if rng.randf() < 0.5 else c.darkened(rng.randf_range(0.0, 0.08))
	opts["paint"] = c
	opts["paint2"] = c.darkened(0.55)
	var fr := rng.randf()
	opts["finish"] = &"metallic" if fr < 0.30 else (&"pearl" if fr < 0.38 else &"gloss")
	return opts
