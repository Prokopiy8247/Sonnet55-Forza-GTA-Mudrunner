class_name RigPose
extends RefCounted
## Flat container of the animation "channels" that RigMotion generates and RigSolver turns into bone rotations.
## Conventions (rig model space: +X right, +Y up, -Z forward, origin between the feet):
##  - *_ROT channels are Euler angles (pitch X, yaw Y, roll Z) in radians, expressed as MODEL-space deltas on top of the
##    rest orientation (+pitch = limb swings forward / head looks up, +yaw = turn left).
##  - ARM / POLE / HDIR / HUP are expressed in CHEST space: origin = neck base, axes = the (posed) chest orientation.
##  - LEG / KNEE / FOOT are expressed in MODEL space (feet are planted on the ground, so they must not follow the hips).

const HIPS_POS := 0     # offset from rest hips position
const HIPS_ROT := 1
const SPINE_ROT := 2    # local to parent (rest-model axes)
const CHEST_ROT := 3
const NECK_ROT := 4
const HEAD_ROT := 5
const ARM_R := 6        # wrist target, chest space
const ARM_L := 7
const POLE_R := 8       # elbow pole direction, chest space
const POLE_L := 9
const HDIR_R := 10      # hand forward direction (where fingers / weapon barrel point), chest space
const HDIR_L := 11
const HUP_R := 12       # hand "thumb up" direction (weapon top), chest space
const HUP_L := 13
const LEG_R := 14       # ankle target, model space
const LEG_L := 15
const KNEE_R := 16      # knee pole direction, model space
const KNEE_L := 17
const FOOT_R := 18      # foot euler (pitch, yaw, roll), model-space delta
const FOOT_L := 19
const VCOUNT := 20

const F_HOVR_R := 0     # 0 = hand follows forearm, 1 = hand uses HDIR/HUP
const F_HOVR_L := 1
const F_TOE_R := 2      # toe flex (radians, + = toes up)
const F_TOE_L := 3
const F_GROUND := 4     # 1 = auto-lower hips so legs never overextend (feet planted), 0 = leave hips alone
const F_SUPPORT := 5    # 1 = left wrist snaps to the weapon's Grip_L (two-handed hold)
const FCOUNT := 6

var v := PackedVector3Array()
var f := PackedFloat32Array()


func _init() -> void:
	v.resize(VCOUNT)
	f.resize(FCOUNT)
	f[F_GROUND] = 1.0


func copy_from(o: RigPose) -> void:
	for i in VCOUNT:
		v[i] = o.v[i]
	for i in FCOUNT:
		f[i] = o.f[i]


## this = lerp(this, o, t)
func mix(o: RigPose, t: float) -> void:
	if t <= 0.0:
		return
	if t >= 1.0:
		copy_from(o)
		return
	for i in VCOUNT:
		v[i] = v[i].lerp(o.v[i], t)
	for i in FCOUNT:
		f[i] = lerpf(f[i], o.f[i], t)
