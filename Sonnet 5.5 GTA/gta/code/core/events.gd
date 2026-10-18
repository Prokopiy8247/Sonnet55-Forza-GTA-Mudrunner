extends Node
## Autoload "Events": the global signal bus. Systems talk through these signals so modules never need
## direct references to each other. Additive changes only: agents may append new signals at the bottom
## of the relevant section but must never rename/remove existing ones.

# ---- Combat / damage -------------------------------------------------------------------
signal character_damaged(character: Node, amount: float, info: Dictionary)
signal character_died(character: Node, killer: Node, info: Dictionary)
signal gunshot(position: Vector3, loudness: float, source: Node)       # loudness = audible radius (m)
signal explosion(position: Vector3, radius: float, source: Node)
signal projectile_impact(position: Vector3, normal: Vector3, surface: StringName, source: Node)
signal weapon_fired(character: Node, weapon_id: StringName)
signal weapon_changed(character: Node, weapon_id: StringName)
signal ammo_changed(character: Node, weapon_id: StringName, in_mag: int, reserve: int)
signal hit_marker(kill: bool)                                           # player landed a hit
signal player_hurt(amount: float, info: Dictionary)                     # for screen feedback

# ---- Crime / police ---------------------------------------------------------------------
## Emit when a crime happens. info keys (all optional): victim: Node, witnesses: Array, severity: float,
## weapon: StringName, vehicle: Node. WantedSystem decides who knows about it.
signal crime_committed(crime: StringName, position: Vector3, perpetrator: Node, info: Dictionary)
signal crime_reported(crime: StringName, position: Vector3, perpetrator: Node)
signal wanted_changed(level: int, state: StringName)                    # state: &"clear" &"pursuit" &"search"
signal wanted_search_progress(progress: float)                          # 0..1 escape progress while unseen
signal player_busted()
signal player_died()
signal player_respawned(position: Vector3)

# ---- Vehicles ------------------------------------------------------------------------------
signal vehicle_entered(vehicle: Node, character: Node, seat: int)
signal vehicle_exited(vehicle: Node, character: Node)
signal vehicle_damaged(vehicle: Node, amount: float, info: Dictionary)
signal vehicle_destroyed(vehicle: Node, killer: Node)
signal vehicle_collision(vehicle: Node, other: Node, impulse: float)
signal vehicle_spawned(vehicle: Node)
signal vehicle_removed(vehicle: Node)
signal vehicle_horn(vehicle: Node)

# ---- World / time -------------------------------------------------------------------------
signal time_changed(hour: float)
signal hour_changed(hour: int)
signal weather_changed(weather: StringName)
signal district_changed(district: StringName)
signal sector_activated(sector_id: Vector2i)
signal sector_deactivated(sector_id: Vector2i)

# ---- Economy / UI / interaction ------------------------------------------------------------
signal cash_changed(amount: int, delta: int)
signal notification(text: String, kind: StringName)                     # kind: &"info" &"good" &"warn" &"bad"
signal subtitle(text: String, seconds: float)
signal interaction_prompt(text: String)                                 # "" hides the prompt
signal menu_opened(menu_id: StringName)
signal menu_closed(menu_id: StringName)
signal pickup_collected(kind: StringName, amount: int)
signal skill_changed(skill: StringName, value: float)
signal radio_station_changed(station: StringName)
signal photo_taken(path: String)

# ---- Lifecycle ---------------------------------------------------------------------------------
signal game_ready()                                                    # all systems booted
signal game_paused(paused: bool)
signal save_requested()
signal load_completed()
signal settings_changed()

# ---- Activities (ActivitySystem, optional free-roam activities; additive, wave 3) ------------------------
signal activity_started(activity_id: StringName)
signal activity_finished(activity_id: StringName, result: Dictionary)   # result: medal, value, cash, ...
signal activity_aborted(activity_id: StringName, reason: String)
