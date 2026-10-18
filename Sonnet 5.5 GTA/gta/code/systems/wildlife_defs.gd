class_name WildlifeDefs
extends RefCounted
## Data tables of the wildlife module: species (behaviour + gait numbers + model ids), region spawn tables and tunables.
## Everything the behaviour code needs is looked up here, so adding a species = adding a row (and a GLB under animals/).
##
## Species keys
##   model      GLB id below res://gta/generated/models/ (animals/<id>)
##   kind       &"land" (walks, grazes, flees) | &"bird" (walks/pecks, takes off, flies, lands) | &"swim" (sharks, dolphins, turtles)
##   hip        leg pivot height L (m) from docs/api/blender_animals.md: gait phase speed = TAU * v / (4 * L * sin(A))
##   walk/trot/run  ground speeds (m/s); amp_*  leg swing amplitude (rad) per gait
##   flee_r     distance at which a walking player is noticed (scaled by the player's speed / stance / vehicle)
##   health     hit points (apply_damage), mass is irrelevant (everything is kinematic)
##   shape      [capsule radius, capsule length (along the body), centre height] for the hit box (layer GC.L_ANIMAL)
##   bold       0..1: chance that a wounded animal fights back instead of fleeing (boar, coyote, dog)
##   bite       damage of one bite/charge when it fights back (0 = never)
##   voice      Sfx id played now and then (only when Sfx.has_sound)

const CAP_LAND := 30               # active land + air animals (architecture section 9)
const CAP_FISH := 40               # fish instances (MultiMesh)
const RING_MIN := 42.0             # spawn ring around the player (hidden spawns)
const RING_MAX := 118.0
const RING_INSTANT_MIN := 22.0     # first fill after boot / teleport may be in view from here
const NEAR := 58.0                 # full simulation + limb animation
const MID := 112.0                 # reduced simulation, no limb animation
const DESPAWN_FAR := 150.0         # despawn beyond (always)
const DESPAWN_HIDDEN := 100.0      # despawn beyond when out of view
const BODY_LIFETIME := 38.0        # corpses stay this long, then sink
const GRAVITY := 20.0

const SPECIES := {
	&"deer": {
		"model": "animals/deer", "kind": &"land", "hip": 1.14, "len": 2.0, "scale": [0.92, 1.06],
		"walk": 1.0, "trot": 3.4, "run": 9.2, "amp_walk": 0.30, "amp_trot": 0.45, "amp_run": 0.65,
		"flee_r": 30.0, "health": 55.0, "shape": [0.30, 1.7, 1.0], "herd": true, "graze": true, "neck": true,
		"bold": 0.0, "bite": 0.0, "voice": &"", "name": "Deer",
	},
	&"deer_buck": {
		"model": "animals/deer_buck", "kind": &"land", "hip": 1.14, "len": 2.0, "scale": [1.0, 1.1],
		"walk": 1.0, "trot": 3.4, "run": 9.6, "amp_walk": 0.30, "amp_trot": 0.45, "amp_run": 0.65,
		"flee_r": 34.0, "health": 75.0, "shape": [0.32, 1.7, 1.05], "herd": true, "graze": true, "neck": true,
		"bold": 0.0, "bite": 0.0, "voice": &"", "name": "Buck",
	},
	&"boar": {
		"model": "animals/boar", "kind": &"land", "hip": 0.46, "len": 1.5, "scale": [0.9, 1.15],
		"walk": 1.1, "trot": 3.0, "run": 7.2, "amp_walk": 0.30, "amp_trot": 0.45, "amp_run": 0.62,
		"flee_r": 15.0, "health": 90.0, "shape": [0.26, 1.1, 0.45], "herd": true, "graze": true, "neck": false,
		"bold": 0.7, "bite": 13.0, "voice": &"", "name": "Boar",
	},
	&"coyote": {
		"model": "animals/coyote", "kind": &"land", "hip": 0.48, "len": 1.3, "scale": [0.92, 1.05],
		"walk": 1.3, "trot": 3.6, "run": 8.8, "amp_walk": 0.30, "amp_trot": 0.45, "amp_run": 0.65,
		"flee_r": 26.0, "health": 45.0, "shape": [0.17, 0.95, 0.42], "herd": false, "graze": true, "neck": false,
		"bold": 0.4, "bite": 6.0, "voice": &"", "name": "Coyote", "predator": true,
	},
	&"rabbit": {
		"model": "animals/rabbit", "kind": &"land", "hip": 0.16, "len": 0.5, "scale": [0.9, 1.1],
		"walk": 1.2, "trot": 2.6, "run": 7.5, "amp_walk": 0.55, "amp_trot": 0.7, "amp_run": 0.8,
		"flee_r": 13.0, "health": 8.0, "shape": [0.10, 0.3, 0.13], "herd": false, "graze": true, "neck": false,
		"bold": 0.0, "bite": 0.0, "voice": &"", "name": "Rabbit", "hop": true,
	},
	&"cat": {
		"model": "animals/cat", "kind": &"land", "hip": 0.215, "len": 0.7, "scale": [0.9, 1.08],
		"walk": 0.8, "trot": 2.4, "run": 6.4, "amp_walk": 0.32, "amp_trot": 0.46, "amp_run": 0.66,
		"flee_r": 9.0, "health": 14.0, "shape": [0.10, 0.45, 0.17], "herd": false, "graze": false, "neck": false,
		"bold": 0.1, "bite": 3.0, "voice": &"", "name": "Cat",
	},
	&"dog": {
		"model": "animals/dog", "kind": &"land", "hip": 0.5, "len": 1.2, "scale": [0.88, 1.12],
		"walk": 1.2, "trot": 3.4, "run": 7.4, "amp_walk": 0.30, "amp_trot": 0.45, "amp_run": 0.65,
		"flee_r": 7.0, "health": 40.0, "shape": [0.17, 0.9, 0.38], "herd": false, "graze": false, "neck": false,
		"bold": 0.35, "bite": 5.0, "voice": &"dog_bark", "name": "Dog", "tail_wag": true,
	},
	&"cow": {
		"model": "animals/cow", "kind": &"land", "hip": 1.04, "len": 2.4, "scale": [0.95, 1.05],
		"walk": 0.7, "trot": 2.3, "run": 5.6, "amp_walk": 0.28, "amp_trot": 0.42, "amp_run": 0.58,
		"flee_r": 7.0, "health": 140.0, "shape": [0.40, 1.9, 0.95], "herd": true, "graze": true, "neck": false,
		"bold": 0.0, "bite": 0.0, "voice": &"cow_moo", "name": "Cow",
	},
	&"horse": {
		"model": "animals/horse", "kind": &"land", "hip": 1.12, "len": 2.2, "scale": [0.95, 1.05],
		"walk": 1.3, "trot": 4.0, "run": 10.5, "amp_walk": 0.30, "amp_trot": 0.45, "amp_run": 0.65,
		"flee_r": 11.0, "health": 110.0, "shape": [0.30, 1.5, 0.95], "herd": true, "graze": true, "neck": true,
		"bold": 0.0, "bite": 0.0, "voice": &"", "name": "Horse",
	},
	&"crow": {
		"model": "animals/bird_small", "model_perched": "animals/bird_small_perched", "kind": &"bird", "hip": 0.05, "len": 0.22, "scale": [0.95, 1.2],
		"walk": 0.7, "trot": 1.4, "run": 2.0, "amp_walk": 0.5, "amp_trot": 0.6, "amp_run": 0.7, "fly": 8.0,
		"flee_r": 8.5, "health": 4.0, "shape": [0.07, 0.2, 0.08], "herd": false, "graze": false, "neck": false,
		"bold": 0.0, "bite": 0.0, "voice": &"bird", "name": "Crow",
	},
	&"seagull": {
		"model": "animals/seagull", "model_perched": "animals/seagull_perched", "kind": &"bird", "hip": 0.1, "len": 0.45, "scale": [0.95, 1.12],
		"walk": 0.8, "trot": 1.6, "run": 2.2, "amp_walk": 0.5, "amp_trot": 0.6, "amp_run": 0.7, "fly": 9.0,
		"flee_r": 5.5, "health": 5.0, "shape": [0.10, 0.4, 0.12], "herd": false, "graze": false, "neck": false,
		"bold": 0.0, "bite": 0.0, "voice": &"gull", "name": "Seagull",
	},
	&"shark": {
		"model": "animals/shark", "kind": &"swim", "hip": 0.0, "len": 3.2, "scale": [0.85, 1.12],
		"walk": 1.6, "trot": 3.4, "run": 9.0, "health": 220.0, "shape": [0.42, 2.6, 0.0], "bite": 24.0, "name": "Shark", "voice": &"",
		"flee_r": 0.0, "bold": 1.0,
	},
	&"dolphin": {
		"model": "animals/dolphin", "kind": &"swim", "hip": 0.0, "len": 2.0, "scale": [0.9, 1.1],
		"walk": 2.0, "trot": 4.6, "run": 8.0, "health": 120.0, "shape": [0.3, 1.6, 0.0], "bite": 0.0, "name": "Dolphin", "voice": &"dolphin",
		"flee_r": 0.0, "bold": 0.0,
	},
	&"sea_turtle": {
		"model": "animals/sea_turtle", "kind": &"swim", "hip": 0.0, "len": 0.86, "scale": [0.9, 1.35],
		"walk": 0.45, "trot": 0.9, "run": 2.2, "health": 40.0, "shape": [0.3, 0.8, 0.0], "bite": 0.0, "name": "Sea turtle", "voice": &"",
		"flee_r": 4.0, "bold": 0.0,
	},
}

## Coat variants (tints of the `AnimalFur` material per species, applied per animal as a shared cached material).
const COATS := {
	&"dog": [Color("#9a6a3a"), Color("#d9c9a8"), Color("#3a3430"), Color("#b98a4c")],
	&"cat": [Color("#c9772e"), Color("#4a4642"), Color("#d8d4cc"), Color("#8a8076")],
	&"cow": [Color("#ece6da"), Color("#d9d2c4"), Color("#bfae98")],
	&"rabbit": [Color("#9d8e7c"), Color("#b3a58f"), Color("#d6cfc2")],
	&"deer": [Color("#a97c54"), Color("#b98b5e"), Color("#9a6f48")],
	&"boar": [Color("#4a3e36"), Color("#5c4a3c"), Color("#3a322e")],
	&"seagull": [Color("#f0f2f4"), Color("#e4e8ec")],
}

## Regions (see WildlifeRegions.classify). Each row: species, weight, group min/max, only: &"any"/&"day"/&"night", max_active (per species cap).
## `target` = how many land animals this region wants around the player at most (the global cap still applies).
const REGION_TABLE := {
	&"hills": {"target": 14, "rows": [
		{"sp": &"deer", "w": 4.0, "min": 2, "max": 5, "buck": true, "cap": 12},
		{"sp": &"boar", "w": 2.0, "min": 1, "max": 3, "cap": 6},
		{"sp": &"coyote", "w": 1.4, "min": 1, "max": 2, "cap": 3},
		{"sp": &"rabbit", "w": 3.0, "min": 1, "max": 3, "cap": 8},
		{"sp": &"crow", "w": 2.0, "min": 1, "max": 3, "cap": 6},
	]},
	&"woods": {"target": 14, "rows": [
		{"sp": &"deer", "w": 4.0, "min": 2, "max": 5, "buck": true, "cap": 12},
		{"sp": &"boar", "w": 2.4, "min": 1, "max": 3, "cap": 6},
		{"sp": &"coyote", "w": 1.2, "min": 1, "max": 2, "cap": 3},
		{"sp": &"rabbit", "w": 3.0, "min": 1, "max": 3, "cap": 8},
		{"sp": &"crow", "w": 1.6, "min": 1, "max": 3, "cap": 6},
	]},
	&"park": {"target": 12, "rows": [
		{"sp": &"deer", "w": 3.0, "min": 2, "max": 4, "buck": true, "cap": 10},
		{"sp": &"rabbit", "w": 3.4, "min": 1, "max": 3, "cap": 8},
		{"sp": &"crow", "w": 2.6, "min": 1, "max": 3, "cap": 6},
		{"sp": &"dog", "w": 0.8, "min": 1, "max": 1, "cap": 2},
		{"sp": &"seagull", "w": 0.6, "min": 1, "max": 2, "cap": 4},
	]},
	&"beach": {"target": 10, "rows": [
		{"sp": &"seagull", "w": 6.0, "min": 1, "max": 4, "cap": 12, "perch": true},
		{"sp": &"crow", "w": 0.8, "min": 1, "max": 2, "cap": 4},
	]},
	&"harbour": {"target": 10, "rows": [
		{"sp": &"seagull", "w": 4.5, "min": 1, "max": 3, "cap": 12, "perch": true},
		{"sp": &"dog", "w": 1.4, "min": 1, "max": 1, "cap": 3},
		{"sp": &"cat", "w": 2.0, "min": 1, "max": 2, "cap": 4},
		{"sp": &"crow", "w": 2.4, "min": 1, "max": 3, "cap": 6},
	]},
	&"industrial": {"target": 8, "rows": [
		{"sp": &"dog", "w": 1.6, "min": 1, "max": 1, "cap": 3},
		{"sp": &"cat", "w": 2.0, "min": 1, "max": 2, "cap": 4},
		{"sp": &"crow", "w": 3.0, "min": 1, "max": 4, "cap": 6},
		{"sp": &"seagull", "w": 0.8, "min": 1, "max": 2, "cap": 4},
	]},
	&"residential": {"target": 9, "rows": [
		{"sp": &"cat", "w": 3.0, "min": 1, "max": 1, "cap": 5},
		{"sp": &"dog", "w": 2.0, "min": 1, "max": 1, "cap": 3},
		{"sp": &"crow", "w": 2.6, "min": 1, "max": 3, "cap": 6},
		{"sp": &"rabbit", "w": 0.6, "min": 1, "max": 2, "cap": 3},
	]},
	&"pasture": {"target": 8, "rows": [
		{"sp": &"cow", "w": 5.0, "min": 3, "max": 5, "cap": 6},
		{"sp": &"horse", "w": 1.2, "min": 1, "max": 2, "cap": 2},
		{"sp": &"crow", "w": 1.0, "min": 1, "max": 2, "cap": 3},
	]},
}


static func get_def(sp: StringName) -> Dictionary:
	return SPECIES.get(sp, {})


static func species_ids() -> Array:
	return SPECIES.keys()
