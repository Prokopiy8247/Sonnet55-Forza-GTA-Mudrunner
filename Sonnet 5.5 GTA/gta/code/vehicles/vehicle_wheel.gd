class_name VehicleWheel
extends RefCounted
## Per-wheel runtime state of a raycast-suspension vehicle (CarVehicle / BikeVehicle). Pure data, no logic.

var node: Node3D = null            # visual wheel node from the model (may be null for the physics-only case)
var wname: StringName = &""
var rest_basis := Basis.IDENTITY   # wheel node basis in the model (preserved; steering/spin are applied on top)

# ---- geometry (vehicle space) -----------------------------------------------------------------------------
var rest := Vector3.ZERO           # wheel centre at static equilibrium
var hp := Vector3.ZERO             # ray origin (suspension top) = rest + up * eq_len
var radius := 0.33
var width := 0.22
var front := true
var side := -1.0                   # -1 left / +1 right / 0 centre (bikes)
var steered := false
var driven := false
var braked := true
var handbrake := false             # rear wheels lock with the handbrake
var axle := 0                      # 0 = front ... n-1 = rearmost

# ---- suspension -----------------------------------------------------------------------------------------------
var max_len := 0.28                # full droop length (hp -> wheel centre)
var eq_len := 0.22                 # length at static equilibrium
var free_len := 0.28               # spring is unloaded at this length (eq_len + static compression)
var k := 30000.0                   # spring N/m
var c_bump := 2500.0
var c_reb := 3300.0

# ---- dynamic ------------------------------------------------------------------------------------------------------
var grounded := false
var length := 0.28
var prev_length := 0.28
var normal_force := 0.0
var contact := Vector3.ZERO
var normal := Vector3.UP
var spin := 0.0                    # visual rotation angle, rad (positive = rolling forward)
var w := 0.0                       # angular velocity, rad/s (positive = rolling forward)
var steer_angle := 0.0             # rad, positive = right
var slip := 0.0                    # 0..1 skid intensity (lateral slide / wheelspin / lock-up)
var slip_lat := 0.0
var surface: StringName = &"road"
var surface_mult := 1.0
var collider_id := 0
var flat := false                  # punctured
var skid_active := false
var skid_last := Vector3.ZERO
var skid_normal := Vector3.UP
var smoke_acc := 0.0
