class_name PedDefs
extends RefCounted
## Data tables + tunables of the pedestrian module (personalities, roles, density per district / hour). Pure data, no logic
## beyond small lookups. Documented in docs/api/pedestrians.md.

# ---- population caps / rings (metres) ------------------------------------------------------------------------------
const CAP_ACTIVE := 60            # target maximum of living walking pedestrians (x density settings)
const CAP_HARD := 90              # absolute maximum (spawn_pedestrian refuses beyond this)
const RING_MIN := 42.0            # spawn ring around the player: nobody spawns closer than this where the player could see it ...
const RING_HIDDEN_MIN := 18.0     # ... but points behind the camera / behind walls (not visible) are valid from this distance
const RING_MAX := 120.0
const RING_BANDS := [[0.50, 0.0, 48.0], [0.32, 48.0, 85.0], [0.18, 85.0, 120.0]]   # [probability, from, to]: more peds close to the player
const INSTANT_FILL_TIME := 1.6    # seconds after boot / a teleport during which the area is populated at once (also in view, from 9 m)
const INSTANT_MIN := 9.0
const DESPAWN_FAR := 150.0        # farther than this from the player -> recycled
const DESPAWN_BEHIND := 90.0      # behind the camera and invisible and farther than this -> recycled
const NEAR := 40.0                # tier 0: full simulation (avoidance 20 Hz, perception)
const MID := 90.0                 # tier 1: reduced (6 Hz decisions, no avoidance); beyond: tier 2 (despawn candidates)
const THINK_NEAR := 0.05
const THINK_MID := 0.16
const THINK_FAR := 0.5
const TICK_BUDGET_US := 1800      # soft budget of decision work per physics tick
const MAX_DEAD_BODIES := 10
const BODY_LIFETIME := 30.0       # seconds a corpse stays before fading out
const BODY_FADE := 2.2
const MAX_SPAWNS_PER_TICK := 2
const MAX_KNOCKED_PER_TIME := 8   # RagdollBody.MAX_LIVE is the real limit
const SHADOW_RANGE := 30.0       # peds farther from the camera than this cast no shadow (render budget)
const VIS_END := 112.0            # peds are not drawn beyond this distance from the camera (dithered fade over the last 10 m)

# ---- movement ---------------------------------------------------------------------------------------------------------
const TURN_RATE := 6.0            # rad/s while walking
const TURN_RATE_RUN := 9.0
const ACCEL := 5.0                # m/s^2
const DECEL := 7.0
const ARRIVE := 0.9               # node reach radius (m): rounds the corners
const SEPARATION := 1.15          # personal space (m)
const WAIT_MAX := 45.0            # max seconds waiting at a red light

# ---- personalities (data driven reactions) -----------------------------------------------------------------------------
## weight: spawn probability. alert: multiplier of the radius in which gunfire / violence is noticed.
## react: weights of the reaction chosen when something frightening is noticed (flee / cower / hands_up / fight / gawk).
## aimed: the same when the player points a gun at the ped. hit: reaction after being hurt (non lethal).
## call: probability to phone the police after witnessing a crime. walk / run: speed ranges (m/s). calm: seconds until panic is gone.
## jaywalk: chance to cross outside the crossings when there is no traffic. scream: chance to scream at the start of a panic.
const PERSONALITIES := {
	&"timid": {
		"weight": 0.20, "alert": 1.30, "react": {"flee": 0.62, "cower": 0.26, "hands_up": 0.12},
		"aimed": {"hands_up": 0.52, "cower": 0.36, "flee": 0.12}, "hit": {"flee": 0.7, "cower": 0.3},
		"call": 0.90, "walk": [1.15, 1.45], "run": [5.4, 6.4], "calm": [22.0, 30.0], "jaywalk": 0.01, "scream": 0.85, "hp": [55.0, 80.0],
	},
	&"normal": {
		"weight": 0.43, "alert": 1.0, "react": {"flee": 0.66, "cower": 0.10, "hands_up": 0.04, "gawk": 0.20},
		"aimed": {"hands_up": 0.42, "flee": 0.40, "cower": 0.18}, "hit": {"flee": 0.8, "cower": 0.2},
		"call": 0.66, "walk": [1.35, 1.75], "run": [5.8, 6.9], "calm": [16.0, 24.0], "jaywalk": 0.05, "scream": 0.55, "hp": [65.0, 100.0],
	},
	&"brave": {
		"weight": 0.12, "alert": 0.9, "react": {"flee": 0.32, "gawk": 0.46, "fight": 0.22},
		"aimed": {"flee": 0.34, "hands_up": 0.26, "fight": 0.40}, "hit": {"fight": 0.55, "flee": 0.45},
		"call": 0.80, "walk": [1.45, 1.85], "run": [6.0, 7.0], "calm": [10.0, 16.0], "jaywalk": 0.08, "scream": 0.2, "hp": [80.0, 110.0],
	},
	&"tough": {
		"weight": 0.07, "alert": 0.8, "react": {"flee": 0.18, "gawk": 0.34, "fight": 0.48},
		"aimed": {"fight": 0.30, "hands_up": 0.30, "flee": 0.40}, "hit": {"fight": 0.78, "flee": 0.22},
		"call": 0.30, "walk": [1.5, 1.95], "run": [6.2, 7.3], "calm": [8.0, 13.0], "jaywalk": 0.14, "scream": 0.08, "hp": [95.0, 130.0],
	},
	&"oblivious": {
		"weight": 0.13, "alert": 0.5, "react": {"flee": 0.60, "gawk": 0.30, "cower": 0.10},
		"aimed": {"hands_up": 0.40, "flee": 0.45, "cower": 0.15}, "hit": {"flee": 0.85, "cower": 0.15},
		"call": 0.40, "walk": [1.3, 1.7], "run": [5.6, 6.6], "calm": [14.0, 20.0], "jaywalk": 0.10, "scream": 0.5, "hp": [60.0, 95.0],
	},
	&"elderly": {
		"weight": 0.05, "alert": 1.10, "react": {"flee": 0.40, "cower": 0.45, "hands_up": 0.15},
		"aimed": {"hands_up": 0.55, "cower": 0.40, "flee": 0.05}, "hit": {"cower": 0.55, "flee": 0.45},
		"call": 0.92, "walk": [0.90, 1.15], "run": [3.2, 4.0], "calm": [28.0, 40.0], "jaywalk": 0.0, "scream": 0.7, "hp": [45.0, 65.0],
	},
}

# ---- looks (outfit styles) -> see PedVariants ---------------------------------------------------------------------------------
const LOOKS: Array[StringName] = [&"business", &"casual", &"worker", &"beach", &"jogger", &"tourist", &"elder", &"shop", &"taxi", &"plain"]

# ---- density per district: [night 0-5, morning 5-9, day 9-17, evening 17-21, late 21-24] ----------------------------------------
const DENSITY := {
	&"downtown": [0.16, 0.75, 1.0, 0.85, 0.35],
	&"residential": [0.06, 0.45, 0.38, 0.50, 0.14],
	&"industrial": [0.04, 0.55, 0.55, 0.22, 0.05],
	&"waterfront": [0.05, 0.30, 0.45, 0.40, 0.10],
	&"beach": [0.03, 0.22, 0.95, 0.80, 0.16],
	&"park_hills": [0.03, 0.55, 0.60, 0.50, 0.06],
	&"airport": [0.04, 0.30, 0.34, 0.26, 0.06],
	&"sea": [0.0, 0.0, 0.0, 0.0, 0.0],
}


static func density(district: StringName, hour: float) -> float:
	var row: Array = DENSITY.get(district, DENSITY[&"residential"])
	var idx := 0
	if hour >= 5.0 and hour < 9.0:
		idx = 1
	elif hour >= 9.0 and hour < 17.0:
		idx = 2
	elif hour >= 17.0 and hour < 21.0:
		idx = 3
	elif hour >= 21.0:
		idx = 4
	return float(row[idx])


static func pick_personality(rng: RandomNumberGenerator, look: StringName = &"") -> StringName:
	var total := 0.0
	for k in PERSONALITIES:
		total += _pw(k, look)
	var t := rng.randf() * total
	for k in PERSONALITIES:
		t -= _pw(k, look)
		if t <= 0.0:
			return k
	return &"normal"


static func _pw(k: StringName, look: StringName) -> float:
	var w: float = PERSONALITIES[k]["weight"]
	if look == &"elder":
		return 1.0 if k == &"elderly" else 0.0
	if look == &"worker" and k == &"tough":
		w *= 2.2
	if look == &"jogger" and (k == &"oblivious" or k == &"normal"):
		w *= 1.4
	if look == &"business" and k == &"tough":
		w *= 0.4
	if k == &"elderly" and look != &"elder":
		return 0.0
	return w


## Weighted choice from a {name: weight} dictionary.
static func weighted(d: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var total := 0.0
	for k in d:
		total += float(d[k])
	if total <= 0.0:
		return &""
	var t := rng.randf() * total
	for k in d:
		t -= float(d[k])
		if t <= 0.0:
			return StringName(k)
	return StringName(d.keys()[0])
