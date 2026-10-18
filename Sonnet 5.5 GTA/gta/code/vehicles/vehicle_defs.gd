class_name VehicleDefs
extends RefCounted
## Vehicle definition table (Vehicles agent). Public contract: get_def() / has() / ids() / traffic_ids() plus DEFS.
## Every def is a Dictionary; missing keys are filled from DEFAULTS, so any key listed in DEFAULTS can be read safely.
##
## Core keys (contract): id, name, class (GC.VC_*), model ("vehicles/<id>"), price, traffic, faction, seats,
##   top_speed_kmh, mass.   `implemented` is false only for classes whose physics do not exist yet (all current ids are implemented).
## Handling keys are documented next to DEFAULTS.  Units: metres, kg, kW, degrees, km/h unless stated.

const DEFAULTS := {
	# ---- identity -------------------------------------------------------------------------------
	"class": GC.VC_CAR, "faction": GC.F_CIVILIAN, "price": 0, "traffic": false, "traffic_weight": 1.0,
	"implemented": true, "seats": 4, "model": "",
	# ---- body (also used to build the code fallback model) -----------------------------------------
	"length": 4.5, "width": 1.8, "height": 1.45, "wheelbase": 2.7, "track": 1.55,
	"wheel_radius": 0.33, "wheel_width": 0.22,
	# ---- mass / engine -----------------------------------------------------------------------------
	"mass": 1400.0, "top_speed_kmh": 180.0, "power_kw": 100.0, "power_mult": 1.25,
	"rpm_idle": 900.0, "rpm_red": 6500.0, "gear_count": 5, "first_gear_frac": 0.28, "launch_rpm": 2600.0,
	"drive": &"fwd",                         # fwd | rwd | awd (6-wheelers: middle+rear axles when rwd)
	"engine": &"car_v6",                     # EngineSound profile ("" = silent, e.g. bicycle)
	# ---- chassis -------------------------------------------------------------------------------------
	"com": Vector3(0.0, 0.50, 0.0),          # centre of mass, vehicle space (origin = ground under wheelbase centre)
	"inertia_scale": 1.0, "gravity_scale": 1.15,
	"grip": 1.15,                            # tyre friction coefficient (mu)
	"drift_grip": 0.65,                      # grip fraction left when sliding hard (lower = more drift, less recovery)
	"front_grip": 1.0, "rear_grip": 1.0,     # axle grip multipliers (front<rear = understeer, rear<front = oversteer)
	"grip_lift": 0.75,                       # 0..1 how close to the CoM height the tyre forces act (higher = less body roll / flip)
	"steer_lock": 34.0,                      # max steering angle at standstill (deg)
	"steer_min": 4.5,                        # never less than this at speed (deg)
	"steer_gain": 1.5,                       # >1 allows a little more steering than the grip limit (understeer when pushed)
	"brake": 11.0,                           # max braking deceleration, m/s^2 (ABS limited)
	"handbrake_grip": 0.3,                   # rear grip multiplier while the handbrake is pulled
	"susp_freq": 2.0, "susp_damp": 0.5, "susp_travel": 0.28, "arb": 0.5,
	"cda": 0.7,                              # drag area (Cd*A, m^2)
	"downforce": 0.0,                        # N per (m/s)^2 pressed into the road
	# ---- damage -------------------------------------------------------------------------------------------
	"health": 1000.0, "collision_mult": 1.0, "bullet_mult": 1.2, "explosion_mult": 1.0, "runover_mult": 1.0,
	"tire_burst": true,
	# ---- camera / audio ------------------------------------------------------------------------------------
	"cam_distance": 6.2, "cam_height": 2.2, "cam_look_ahead": 3.0, "cam_fov": 75.0,
	"horn": &"horn_car", "siren": &"",       # siren: &"" | &"police" | &"ambulance" | &"fire"
	"paints": [],                            # Array[Color] random colours for traffic ("" = use default)
	# ---- two wheelers ------------------------------------------------------------------------------------------
	"lean_max": 42.0, "wheelie": false, "pedal_force": 0.0,
}

static var DEFS: Dictionary = _build()


static func _p(hex: String) -> Color:
	return Color(hex)


static func _build() -> Dictionary:
	var table := {}
	var civ := [_p("#c43a3a"), _p("#2f6fb5"), _p("#e8e4da"), _p("#2a2d33"), _p("#d9a441"), _p("#4b8a5f"), _p("#8d94a0"), _p("#7a3f8f")]
	var bright := [_p("#ff3d9a"), _p("#34e0ff"), _p("#ffb347"), _p("#e8e4da"), _p("#2a2d33"), _p("#c43a3a")]
	var rows := {
		&"compact": {
			"name": "Pebble Compact", "price": 9500, "traffic": true, "traffic_weight": 1.4, "seats": 4,
			"length": 3.75, "width": 1.68, "height": 1.46, "wheelbase": 2.4, "track": 1.46, "wheel_radius": 0.30, "wheel_width": 0.20,
			"mass": 1050.0, "top_speed_kmh": 165.0, "power_kw": 66.0, "rpm_red": 6800.0, "gear_count": 5, "drive": &"fwd",
			"engine": &"car_small", "com": Vector3(0, 0.46, -0.08), "grip": 1.15, "drift_grip": 0.7, "steer_lock": 38.0,
			"brake": 10.5, "cda": 0.62, "health": 800.0, "cam_distance": 5.5, "cam_height": 2.0, "paints": civ,
		},
		&"sedan": {
			"name": "Marlin Sedan", "price": 14500, "traffic": true, "traffic_weight": 2.0, "seats": 4,
			"length": 4.6, "width": 1.82, "height": 1.45, "wheelbase": 2.75, "track": 1.56, "wheel_radius": 0.33,
			"mass": 1450.0, "top_speed_kmh": 190.0, "power_kw": 110.0, "rpm_red": 6500.0, "gear_count": 5, "drive": &"fwd",
			"engine": &"car_v6", "com": Vector3(0, 0.50, -0.10), "grip": 1.1, "drift_grip": 0.65, "front_grip": 0.97, "paints": civ,
		},
		&"sports": {
			"name": "Vanta GT", "price": 98000, "traffic": false, "seats": 2,
			"length": 4.45, "width": 1.92, "height": 1.2, "wheelbase": 2.65, "track": 1.62, "wheel_radius": 0.34, "wheel_width": 0.27,
			"mass": 1350.0, "top_speed_kmh": 248.0, "power_kw": 360.0, "rpm_red": 8400.0, "launch_rpm": 4200.0, "gear_count": 6, "first_gear_frac": 0.26,
			"drive": &"rwd", "engine": &"sports", "com": Vector3(0, 0.38, 0.05), "grip": 1.55, "drift_grip": 0.8, "rear_grip": 1.0,
			"steer_lock": 30.0, "steer_gain": 1.7, "brake": 13.5, "susp_freq": 2.4, "susp_travel": 0.22, "cda": 0.62, "downforce": 0.9,
			"grip_lift": 0.85, "health": 900.0, "cam_distance": 6.0, "cam_height": 1.9, "cam_fov": 78.0, "paints": bright,
		},
		&"muscle": {
			"name": "Brute Coupe", "price": 54000, "traffic": true, "traffic_weight": 0.5, "seats": 4,
			"length": 4.95, "width": 1.93, "height": 1.34, "wheelbase": 2.85, "track": 1.6, "wheel_radius": 0.35, "wheel_width": 0.26,
			"mass": 1750.0, "top_speed_kmh": 218.0, "power_kw": 300.0, "rpm_red": 6200.0, "launch_rpm": 3200.0, "gear_count": 5,
			"drive": &"rwd", "engine": &"car_v8", "com": Vector3(0, 0.46, -0.15), "grip": 1.2, "drift_grip": 0.5, "rear_grip": 0.88,
			"steer_lock": 32.0, "brake": 11.5, "cda": 0.75, "health": 1100.0, "horn": &"horn_car", "paints": civ + [_p("#ffb347")],
		},
		&"suv": {
			"name": "Ridgeback SUV", "price": 38000, "traffic": true, "traffic_weight": 1.4, "seats": 4,
			"length": 4.75, "width": 1.97, "height": 1.78, "wheelbase": 2.85, "track": 1.68, "wheel_radius": 0.38, "wheel_width": 0.25,
			"mass": 2100.0, "top_speed_kmh": 185.0, "power_kw": 175.0, "rpm_red": 6000.0, "gear_count": 6, "drive": &"awd",
			"engine": &"car_v6", "com": Vector3(0, 0.72, -0.05), "grip": 1.05, "drift_grip": 0.6, "grip_lift": 0.5, "susp_freq": 1.6,
			"susp_travel": 0.36, "arb": 0.8, "steer_lock": 33.0, "cda": 0.95, "health": 1250.0, "cam_distance": 7.0, "cam_height": 2.6, "paints": civ,
		},
		&"pickup": {
			"name": "Hauler Pickup", "price": 31000, "traffic": true, "traffic_weight": 1.2, "seats": 3,
			"length": 5.25, "width": 1.97, "height": 1.78, "wheelbase": 3.2, "track": 1.68, "wheel_radius": 0.38, "wheel_width": 0.25,
			"mass": 2050.0, "top_speed_kmh": 178.0, "power_kw": 165.0, "rpm_red": 5800.0, "gear_count": 5, "drive": &"rwd",
			"engine": &"car_v8", "com": Vector3(0, 0.74, 0.1), "grip": 1.0, "drift_grip": 0.6, "grip_lift": 0.55, "susp_freq": 1.6, "susp_travel": 0.36,
			"arb": 0.8, "cda": 0.95, "health": 1250.0, "cam_distance": 7.2, "cam_height": 2.7, "paints": civ,
		},
		&"van": {
			"name": "Courier Van", "price": 24000, "traffic": true, "traffic_weight": 1.0, "seats": 3,
			"length": 5.0, "width": 1.96, "height": 2.15, "wheelbase": 3.1, "track": 1.68, "wheel_radius": 0.34, "wheel_width": 0.22,
			"mass": 2400.0, "top_speed_kmh": 160.0, "power_kw": 120.0, "rpm_red": 5600.0, "gear_count": 5, "drive": &"rwd",
			"engine": &"car_v6", "com": Vector3(0, 0.88, 0.0), "grip": 1.0, "drift_grip": 0.58, "grip_lift": 0.5, "susp_freq": 1.5,
			"arb": 1.0, "steer_lock": 34.0, "cda": 1.35, "health": 1150.0, "cam_distance": 7.6, "cam_height": 3.0, "paints": civ,
		},
		&"police_cruiser": {
			"name": "Patrol Cruiser", "price": 0, "traffic": false, "faction": GC.F_POLICE, "seats": 4,
			"length": 4.75, "width": 1.86, "height": 1.48, "wheelbase": 2.8, "track": 1.58, "wheel_radius": 0.34, "wheel_width": 0.24,
			"mass": 1750.0, "top_speed_kmh": 218.0, "power_kw": 230.0, "rpm_red": 6600.0, "launch_rpm": 3000.0, "gear_count": 6, "drive": &"rwd",
			"engine": &"car_v8", "com": Vector3(0, 0.50, -0.05), "grip": 1.3, "drift_grip": 0.72, "steer_lock": 33.0, "brake": 12.5,
			"health": 1500.0, "collision_mult": 0.8, "bullet_mult": 0.9, "siren": &"police", "susp_freq": 2.1, "paints": [_p("#14171d")],
		},
		&"taxi": {
			"name": "City Cab", "price": 0, "traffic": true, "traffic_weight": 0.7, "seats": 4,
			"length": 4.6, "width": 1.82, "height": 1.5, "wheelbase": 2.75, "track": 1.56, "wheel_radius": 0.33,
			"mass": 1500.0, "top_speed_kmh": 178.0, "power_kw": 100.0, "rpm_red": 6200.0, "gear_count": 5, "drive": &"fwd",
			"engine": &"car_small", "com": Vector3(0, 0.50, -0.10), "grip": 1.1, "drift_grip": 0.65, "paints": [_p("#ffb347")],
		},
		&"ambulance": {
			"name": "Rescue Ambulance", "price": 0, "traffic": false, "faction": GC.F_CIVILIAN, "seats": 3,
			"length": 5.4, "width": 2.0, "height": 2.35, "wheelbase": 3.3, "track": 1.7, "wheel_radius": 0.36, "wheel_width": 0.24,
			"mass": 3200.0, "top_speed_kmh": 170.0, "power_kw": 150.0, "rpm_red": 5200.0, "gear_count": 5, "drive": &"rwd",
			"engine": &"truck", "com": Vector3(0, 0.95, 0.0), "grip": 1.0, "drift_grip": 0.55, "grip_lift": 0.45, "susp_freq": 1.4, "arb": 1.1,
			"brake": 10.0, "cda": 1.5, "health": 1300.0, "siren": &"ambulance", "horn": &"horn_truck", "cam_distance": 8.0, "cam_height": 3.2,
			"paints": [_p("#f2f2ee")],
		},
		&"firetruck": {
			"name": "Blaze Engine", "price": 0, "traffic": false, "seats": 3,
			"length": 8.6, "width": 2.5, "height": 3.3, "wheelbase": 4.6, "track": 2.0, "wheel_radius": 0.52, "wheel_width": 0.32,
			"mass": 12000.0, "top_speed_kmh": 118.0, "power_kw": 270.0, "power_mult": 1.5, "rpm_red": 3200.0, "launch_rpm": 1500.0, "rpm_idle": 650.0,
			"gear_count": 6, "first_gear_frac": 0.2, "drive": &"rwd", "engine": &"truck", "com": Vector3(0, 1.25, 0.2), "inertia_scale": 1.3,
			"grip": 0.95, "drift_grip": 0.5, "grip_lift": 0.4, "steer_lock": 30.0, "steer_min": 3.5, "brake": 8.0, "susp_freq": 1.2, "susp_travel": 0.34,
			"arb": 1.6, "cda": 3.8, "health": 2600.0, "collision_mult": 0.5, "runover_mult": 1.6, "siren": &"fire", "horn": &"horn_truck",
			"cam_distance": 11.5, "cam_height": 4.4, "cam_look_ahead": 4.0, "cam_fov": 72.0, "paints": [_p("#c92a2a")],
		},
		&"truck": {
			"name": "Freight Truck", "price": 62000, "traffic": true, "traffic_weight": 0.5, "seats": 2,
			"length": 7.8, "width": 2.5, "height": 3.5, "wheelbase": 4.2, "track": 1.95, "wheel_radius": 0.5, "wheel_width": 0.3,
			"mass": 8500.0, "top_speed_kmh": 118.0, "power_kw": 230.0, "power_mult": 1.5, "rpm_red": 3000.0, "launch_rpm": 1400.0, "rpm_idle": 650.0,
			"gear_count": 6, "first_gear_frac": 0.2, "drive": &"rwd", "engine": &"truck", "com": Vector3(0, 1.3, 0.2), "inertia_scale": 1.3,
			"grip": 0.95, "drift_grip": 0.5, "grip_lift": 0.4, "steer_lock": 31.0, "steer_min": 3.5, "brake": 8.0, "susp_freq": 1.2, "susp_travel": 0.34,
			"arb": 1.5, "cda": 4.2, "health": 2200.0, "collision_mult": 0.55, "runover_mult": 1.5, "horn": &"horn_truck",
			"cam_distance": 11.0, "cam_height": 4.2, "cam_look_ahead": 4.0, "cam_fov": 72.0, "paints": [_p("#3a5ea8"), _p("#e8e4da"), _p("#4b8a5f"), _p("#d9a441")],
		},
		&"police_tactical": {
			"name": "Bulwark Tactical", "price": 0, "traffic": false, "faction": GC.F_POLICE, "seats": 4,
			"length": 5.7, "width": 2.25, "height": 2.35, "wheelbase": 3.4, "track": 1.85, "wheel_radius": 0.46, "wheel_width": 0.3,
			"mass": 6200.0, "top_speed_kmh": 142.0, "power_kw": 220.0, "power_mult": 1.5, "rpm_red": 4400.0, "launch_rpm": 1800.0, "gear_count": 5,
			"first_gear_frac": 0.24, "drive": &"awd", "engine": &"truck", "com": Vector3(0, 0.95, 0.0), "inertia_scale": 1.2,
			"grip": 1.05, "drift_grip": 0.6, "grip_lift": 0.5, "steer_lock": 30.0, "brake": 9.0, "susp_freq": 1.4, "susp_travel": 0.32, "arb": 1.4,
			"cda": 2.2, "health": 3200.0, "collision_mult": 0.4, "bullet_mult": 0.25, "explosion_mult": 0.6, "runover_mult": 1.4,
			"siren": &"police", "horn": &"horn_truck", "cam_distance": 8.6, "cam_height": 3.3, "paints": [_p("#1c2026")],
		},
		&"motorcycle": {
			"name": "Zephyr 600", "class": GC.VC_BIKE, "price": 18500, "traffic": false, "seats": 2,
			"length": 2.1, "width": 0.8, "height": 1.3, "wheelbase": 1.45, "track": 0.0, "wheel_radius": 0.32, "wheel_width": 0.16,
			"mass": 290.0, "top_speed_kmh": 205.0, "power_kw": 95.0, "power_mult": 1.3, "rpm_idle": 1200.0, "rpm_red": 11000.0, "launch_rpm": 5000.0,
			"gear_count": 6, "first_gear_frac": 0.24, "drive": &"rwd", "engine": &"bike", "com": Vector3(0, 0.58, 0.0), "inertia_scale": 0.9,
			"grip": 1.35, "drift_grip": 0.78, "grip_lift": 0.9, "steer_lock": 32.0, "steer_min": 3.5, "brake": 10.0, "susp_freq": 2.4,
			"susp_travel": 0.2, "cda": 0.45, "health": 650.0, "collision_mult": 0.5, "horn": &"horn_bike", "lean_max": 44.0, "wheelie": true,
			"cam_distance": 4.6, "cam_height": 1.8, "cam_look_ahead": 2.4, "cam_fov": 78.0, "paints": bright,
		},
		&"bicycle": {
			"name": "City Cruiser Bike", "class": GC.VC_BICYCLE, "price": 450, "traffic": false, "seats": 1,
			"length": 1.8, "width": 0.6, "height": 1.1, "wheelbase": 1.05, "track": 0.0, "wheel_radius": 0.34, "wheel_width": 0.06,
			"mass": 95.0, "top_speed_kmh": 32.0, "power_kw": 0.0, "rpm_idle": 0.0, "rpm_red": 1.0, "gear_count": 1, "drive": &"rwd", "engine": &"",
			"com": Vector3(0, 0.62, 0.0), "inertia_scale": 0.9, "grip": 1.1, "drift_grip": 0.7, "grip_lift": 0.9, "steer_lock": 40.0,
			"steer_min": 6.0, "brake": 5.5, "susp_freq": 2.6, "susp_travel": 0.1, "cda": 0.5, "health": 220.0, "collision_mult": 0.1, "horn": &"horn_bike",
			"lean_max": 30.0, "pedal_force": 260.0, "cam_distance": 3.9, "cam_height": 1.6, "cam_look_ahead": 2.0, "cam_fov": 72.0, "paints": bright,
		},
		# ---- air / sea (Air&Sea agent): physics in speedboat -> BoatVehicle, heli_* -> HeliVehicle, plane_* -> PlaneVehicle ----
		# Extra keys: gravity_scale 1.0, lod_mult (LOD radius multiplier for audio / visuals), com, inertia (principal moments),
		# col_boxes [[centre, size], ...] (collision, vehicle space), gear (heli skid ground points), rotor_* / tail_rotor_*,
		# wing_area / stall_kmh / thrust_n / thrust_v0 / pitch_rate ... (planes), hull / thrust / turn keys (boat) - see the classes.
		&"speedboat": {
			"name": "Tide Runner", "class": GC.VC_BOAT, "price": 52000, "seats": 4, "mass": 1100.0, "top_speed_kmh": 110.0,
			"length": 6.34, "width": 2.4, "height": 1.89, "engine": &"boat", "paints": bright, "gravity_scale": 1.0, "lod_mult": 2.2,
			"com": Vector3(0, 0.02, 0.35), "inertia": Vector3(2400, 2600, 1000), "health": 900.0, "collision_mult": 0.8,
			"col_boxes": [[Vector3(0, 0.35, 0.1), Vector3(2.2, 1.3, 5.9)]],
			"thrust_n": 7600.0, "turn_rate": 1.15, "cam_distance": 9.6, "cam_height": 3.6, "cam_look_ahead": 5.0, "cam_fov": 72.0,
			"wheel_radius": 0.3, "horn": &"horn_car",
		},
		&"heli_civil": {
			"name": "Skylark Helicopter", "class": GC.VC_HELI, "price": 320000, "seats": 4, "mass": 1500.0, "top_speed_kmh": 230.0,
			"length": 10.6, "width": 2.5, "height": 3.36, "engine": &"heli_rotor", "paints": bright, "gravity_scale": 1.0, "lod_mult": 2.6,
			"com": Vector3(0, 1.3, -0.15), "inertia": Vector3(4400, 4300, 2300), "health": 1000.0, "collision_mult": 1.3,
			"col_boxes": [[Vector3(0, 1.35, -1.0), Vector3(1.9, 2.0, 4.6)], [Vector3(0, 2.45, 4.4), Vector3(0.5, 0.6, 5.6)]],
			"gear": [Vector3(-1.18, 0, -1.9), Vector3(1.18, 0, -1.9), Vector3(-1.18, 0, 0.9), Vector3(1.18, 0, 0.9)],
			"rotor_radius": 5.2, "tail_rotor_radius": 0.8, "thrust_g": 1.75, "climb_rate": 7.5, "spool_up": 3.4, "spool_down": 9.0,
			"cam_distance": 17.0, "cam_height": 6.0, "cam_look_ahead": 5.0, "cam_fov": 72.0,
		},
		&"heli_police": {
			"name": "Patrol Helicopter", "class": GC.VC_HELI, "faction": GC.F_POLICE, "seats": 4, "mass": 1700.0,
			"top_speed_kmh": 240.0, "length": 12.1, "width": 2.76, "height": 3.51, "engine": &"heli_rotor", "siren": &"",
			"gravity_scale": 1.0, "lod_mult": 2.6, "com": Vector3(0, 1.35, -0.15), "inertia": Vector3(5200, 5000, 2700), "health": 1400.0,
			"collision_mult": 1.1, "bullet_mult": 0.8, "paints": [_p("#14171d")],
			"col_boxes": [[Vector3(0, 1.4, -1.0), Vector3(2.2, 2.1, 5.2)], [Vector3(0, 2.5, 5.0), Vector3(0.5, 0.65, 6.2)]],
			"gear": [Vector3(-1.3, 0, -2.5), Vector3(1.3, 0, -2.5), Vector3(-1.3, 0, 1.4), Vector3(1.3, 0, 1.4)],
			"rotor_radius": 4.06, "tail_rotor_radius": 0.59, "thrust_g": 1.85, "climb_rate": 8.5, "yaw_rate": 1.9, "spool_up": 3.0, "spool_down": 8.0,
			"drag_fwd2": 0.0005, "cam_distance": 18.0, "cam_height": 6.2, "cam_look_ahead": 5.0, "cam_fov": 72.0,
		},
		&"plane_prop": {
			"name": "Sparrow Prop Plane", "class": GC.VC_PLANE, "price": 180000, "seats": 4, "mass": 1100.0, "top_speed_kmh": 260.0,
			"length": 8.42, "width": 10.91, "height": 2.86, "engine": &"prop_plane", "paints": bright, "gravity_scale": 1.0, "lod_mult": 3.0,
			"com": Vector3(0, 1.0, 0.05), "inertia": Vector3(3800, 7200, 5400), "health": 900.0, "collision_mult": 1.2,
			"col_boxes": [[Vector3(0, 1.3, 1.0), Vector3(1.3, 1.6, 7.2)], [Vector3(0, 2.3, 0.3), Vector3(10.6, 0.3, 1.8)],
				[Vector3(0, 1.35, 4.8), Vector3(3.4, 0.25, 0.9)], [Vector3(0, 2.2, 5.0), Vector3(0.2, 1.4, 0.9)]],
			"wing_area": 12.0, "stall_kmh": 96.0, "cl_slope": 5.0, "alpha0": -0.07, "flap_alpha": 0.17, "cd0": 0.056, "induced_k": 0.06,
			"thrust_n": 10400.0, "thrust_v0": 100.0, "rot_rate": 0.7, "engine_lag": 1.1, "pitch_rate": 0.95, "roll_rate": 2.2, "yaw_rate": 0.55,
			"hard_landing": 3.2, "crash_landing": 9.5, "prop_radius": 0.95,
			"cam_distance": 15.0, "cam_height": 4.6, "cam_look_ahead": 5.0, "cam_fov": 72.0,
		},
		&"plane_jet": {
			"name": "Falcon Jet", "class": GC.VC_PLANE, "price": 900000, "seats": 2, "mass": 6500.0, "top_speed_kmh": 900.0,
			"length": 13.5, "width": 9.65, "height": 4.125, "engine": &"jet", "paints": bright, "gravity_scale": 1.0, "lod_mult": 3.0,
			"com": Vector3(0, 1.7, -0.1), "inertia": Vector3(50000, 70000, 38000), "health": 1400.0, "collision_mult": 1.0,
			"col_boxes": [[Vector3(0, 1.9, -0.3), Vector3(1.7, 1.9, 12.6)], [Vector3(0, 1.4, 1.2), Vector3(9.4, 0.3, 3.2)],
				[Vector3(0, 3.1, 5.9), Vector3(0.3, 2.1, 1.4)], [Vector3(0, 4.04, 6.1), Vector3(3.8, 0.2, 0.8)]],
			"wing_area": 28.0, "stall_kmh": 160.0, "rot_rate": 1.0, "rot_speed_k": 0.93, "climb_deg": 12.0, "cl_slope": 4.6, "alpha0": -0.06, "flap_alpha": 0.10, "bank_limit_deg": 68.0, "cd0": 0.021, "induced_k": 0.07,
			"thrust_n": 110000.0, "thrust_v0": 320.0, "engine_lag": 1.6, "pitch_rate": 1.1, "roll_rate": 3.2, "yaw_rate": 0.6,
			"afterburner": 1.0, "hard_landing": 3.8, "crash_landing": 10.5,
			"cam_distance": 22.0, "cam_height": 6.2, "cam_look_ahead": 7.0, "cam_fov": 74.0,
		},
	}
	for id in rows:
		var d: Dictionary = DEFAULTS.duplicate()
		d.merge(rows[id], true)
		d["id"] = id
		if String(d["model"]) == "":
			d["model"] = "vehicles/" + String(id)
		table[id] = d
	return table


static func get_def(id: StringName) -> Dictionary:
	return DEFS.get(id, {})


static func has(id: StringName) -> bool:
	return DEFS.has(id)


static func ids() -> Array:
	return DEFS.keys()


## Ids whose physics exist today (ground vehicles; air / sea classes arrive later).
static func implemented_ids() -> Array:
	var out: Array = []
	for id in DEFS:
		if DEFS[id].get("implemented", false):
			out.append(id)
	return out


static func is_implemented(id: StringName) -> bool:
	return DEFS.has(id) and DEFS[id].get("implemented", false)


## Ids of vehicles that may spawn as ordinary civilian traffic.
static func traffic_ids() -> Array:
	var out: Array = []
	for id in DEFS:
		if DEFS[id].get("traffic", false) and DEFS[id].get("implemented", false):
			out.append(id)
	return out


## Weighted random pick among traffic vehicles (uses Game.rng).
static func random_traffic_id() -> StringName:
	var ids_: Array = traffic_ids()
	var total := 0.0
	for id in ids_:
		total += float(DEFS[id].get("traffic_weight", 1.0))
	var r: float = Game.rng.randf() * total
	for id in ids_:
		r -= float(DEFS[id].get("traffic_weight", 1.0))
		if r <= 0.0:
			return id
	return &"sedan"


# ---- Customization upgrade effects (data-driven; Garage system supplies the mods dict) -------------------------------
## mods keys -> integer levels. Effects are multipliers applied on top of the base def by VehicleBase.apply_mods().
##   engine 0..4: +power, brakes 0..3: +brake, suspension 0..3: stiffer + grip, transmission 0..3: faster shifts + a little power,
##   turbo 0..1: +power (+whistle), armor 0..5: damage reduction, tires 0..3: grip (level 3 = bullet-proof tyres),
##   spoiler 0..3: downforce, weight 0..2: lighter
const MOD_EFFECTS := {
	"engine": {"power": [1.0, 1.08, 1.16, 1.25, 1.35]},
	"brakes": {"brake": [1.0, 1.1, 1.2, 1.32]},
	"suspension": {"grip": [1.0, 1.02, 1.04, 1.06], "susp_freq": [1.0, 1.08, 1.16, 1.24]},
	"transmission": {"shift_time": [1.0, 0.8, 0.6, 0.45], "power": [1.0, 1.02, 1.04, 1.06]},
	"turbo": {"power": [1.0, 1.14]},
	"armor": {"damage_taken": [1.0, 0.9, 0.8, 0.7, 0.6, 0.5]},
	"tires": {"grip": [1.0, 1.03, 1.06, 1.08]},
	"spoiler": {"downforce": [0.0, 0.35, 0.7, 1.2]},
	"weight": {"mass": [1.0, 0.94, 0.88]},
}
