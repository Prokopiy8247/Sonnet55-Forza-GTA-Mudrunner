class_name CrimeRules
extends RefCounted
## Data-driven crime severity + wanted tuning (Police-A). Pure data and tiny pure functions, no scene access.
## Everything is a `static var` so tests / the debug menu can tweak it at runtime (`CrimeRules.rules[...]["heat"] = 5.0`).
##
## Heat model: every crime that "becomes known" adds heat points; stars are thresholds on heat.
##   crime rule keys:
##     heat          points added (x event severity x repeat decay)
##     min_level     after the crime the wanted level is at least this (0 = none)
##     cooldown      min seconds between two applications of the same crime id
##     broadcast     true = police learn about it without any witness (their own radio: officers / patrol cars are the victim)
##     phone         true = civilian witnesses may phone it in
##     loud          true = gunshot / blast: an indirect report may follow (6-10 s) when a pedestrian or officer is in hearing range
##     repeat_decay  heat multiplier per same-crime repeat inside REPEAT_WINDOW (sub-linear spree growth; floor REPEAT_FLOOR)
##     label         short name for toasts / debug

## Heat needed for 1..5 stars.
static var star_heat: Array[float] = [10.0, 40.0, 90.0, 160.0, 260.0]
## A level is kept until heat falls below threshold * hysteresis.
static var hysteresis := 0.80
static var heat_max := 420.0
## Unseen seconds needed to escape (index = level - 1) at multiplier 1.0.
static var escape_time: Array[float] = [15.0, 25.0, 40.0, 55.0, 75.0]
## Search area radius (m) right after contact is lost, per level, and its growth (m/s) up to search_radius_max.
static var search_base: Array[float] = [55.0, 70.0, 85.0, 100.0, 120.0]
static var search_growth := 2.4
static var search_radius_max := 240.0
## During SEARCH the heat decays by this fraction of its start value over the escape time (0.40: the level drops by one star at
## about half the escape bar, never below 1 star - the last star only goes when the escape bar is full).
static var search_decay_fraction := 0.40
static var repeat_window := 30.0
static var repeat_floor := 0.30

## Escape-speed multipliers while unseen.
static var mult_interior := 2.6        # inside an interior / far hidden room
static var mult_underwater := 2.0
static var mult_swimming := 1.25
static var mult_covered := 1.2         # roof overhead (garage, parking deck, bridge)
static var mult_vehicle_swap := 1.5    # abandoned the vehicle police identified for > vehicle_abandon_time
static var mult_appearance := 1.35     # clothes changed / vehicle repainted
static var mult_inside_area := 0.25    # still inside the search circle the police comb (unless hidden in an interior / underwater)
static var mult_max := 3.6
static var vehicle_abandon_time := 10.0

## Loudness (Events.gunshot, metres) below which a shot is "quiet" (suppressed): only direct witnesses count.
static var quiet_loudness := 24.0

static var rules: Dictionary = {
	GC.CRIME_ASSAULT: {"heat": 12.0, "min_level": 0, "cooldown": 3.0, "phone": true, "repeat_decay": 0.7, "label": "Assault"},
	GC.CRIME_MURDER: {"heat": 30.0, "min_level": 1, "cooldown": 1.5, "phone": true, "repeat_decay": 0.75, "label": "Murder"},
	GC.CRIME_SHOOTING: {"heat": 10.0, "min_level": 0, "cooldown": 8.0, "phone": true, "loud": true, "repeat_decay": 0.6, "label": "Public shooting"},
	GC.CRIME_POLICE_ASSAULT: {"heat": 24.0, "min_level": 2, "cooldown": 5.0, "broadcast": true, "phone": true, "repeat_decay": 0.6, "label": "Assault on an officer"},
	GC.CRIME_POLICE_KILL: {"heat": 70.0, "min_level": 3, "cooldown": 1.5, "broadcast": true, "phone": true, "repeat_decay": 0.8, "label": "Officer down"},
	GC.CRIME_CARJACK: {"heat": 24.0, "min_level": 1, "cooldown": 4.0, "phone": true, "repeat_decay": 0.7, "label": "Carjacking"},
	GC.CRIME_VEHICLE_THEFT: {"heat": 10.0, "min_level": 0, "cooldown": 4.0, "phone": true, "repeat_decay": 0.6, "label": "Vehicle theft"},
	GC.CRIME_POLICE_VEHICLE_THEFT: {"heat": 55.0, "min_level": 3, "cooldown": 4.0, "broadcast": true, "phone": true, "repeat_decay": 0.7, "label": "Police vehicle stolen"},
	GC.CRIME_POLICE_VEHICLE_DESTROYED: {"heat": 55.0, "min_level": 3, "cooldown": 3.0, "broadcast": true, "phone": true, "repeat_decay": 0.7, "label": "Police vehicle destroyed"},
	GC.CRIME_HIT_AND_RUN: {"heat": 16.0, "min_level": 1, "cooldown": 2.5, "phone": true, "repeat_decay": 0.7, "label": "Hit and run"},
	GC.CRIME_COLLISION: {"heat": 6.0, "min_level": 0, "cooldown": 6.0, "phone": true, "repeat_decay": 0.6, "label": "Reckless driving"},
	GC.CRIME_EXPLOSION: {"heat": 34.0, "min_level": 2, "cooldown": 6.0, "phone": true, "loud": true, "repeat_decay": 0.6, "label": "Explosion"},
	GC.CRIME_VANDALISM: {"heat": 4.0, "min_level": 0, "cooldown": 6.0, "phone": true, "repeat_decay": 0.6, "label": "Vandalism"},
	GC.CRIME_ROBBERY: {"heat": 22.0, "min_level": 1, "cooldown": 6.0, "phone": true, "repeat_decay": 0.7, "label": "Robbery"},
	GC.CRIME_RESIST_ARREST: {"heat": 12.0, "min_level": 0, "cooldown": 20.0, "broadcast": true, "repeat_decay": 0.6, "label": "Resisting arrest"},
	GC.CRIME_AIRCRAFT_THEFT: {"heat": 36.0, "min_level": 2, "cooldown": 6.0, "phone": true, "repeat_decay": 0.7, "label": "Aircraft theft"},
}

const DEFAULT_RULE := {"heat": 0.0, "min_level": 0, "cooldown": 5.0, "repeat_decay": 0.7}


static func get_rule(crime: StringName) -> Dictionary:
	if rules.has(crime):
		return rules[crime]
	return {}


static func rule_value(crime: StringName, key: String, default_value: Variant = null) -> Variant:
	var r: Dictionary = rules.get(crime, DEFAULT_RULE)
	return r.get(key, DEFAULT_RULE.get(key, default_value))


## Heat required for a level (0 -> 0).
static func heat_for_level(lvl: int) -> float:
	if lvl <= 0:
		return 0.0
	return star_heat[clampi(lvl, 1, 5) - 1]


## Level for a heat value. Rising is immediate; an already reached level `current` is kept while heat >= threshold * hysteresis.
static func level_for_heat(h: float, current: int = 0) -> int:
	var lvl := 0
	for i in 5:
		if h >= star_heat[i]:
			lvl = i + 1
	var keep := 0
	for i in 5:
		if h >= star_heat[i] * hysteresis:
			keep = i + 1
	return maxi(lvl, mini(current, keep))


static func escape_seconds(lvl: int) -> float:
	return escape_time[clampi(lvl, 1, 5) - 1]


static func search_start_radius(lvl: int) -> float:
	return search_base[clampi(lvl, 1, 5) - 1]
