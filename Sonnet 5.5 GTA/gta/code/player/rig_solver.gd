class_name RigSolver
extends RefCounted
## Turns a RigPose (high-level channels) into bone rotations on the character Skeleton3D.
## Independent of the bone roll authored in Blender: everything is expressed as MODEL-space deltas on top of the rest
## orientation (same maths as Util.bone_set_model_delta, but cached and batched for speed). Parents are always solved
## before children. Legs and arms use analytic two-bone IK with a pole vector, the spine/neck/head use FK.

enum { HIPS, SPINE, CHEST, NECK, HEAD, SH_R, UA_R, LA_R, HAND_R, SH_L, UA_L, LA_L, HAND_L,
	UL_R, LL_R, FOOT_R, TOE_R, UL_L, LL_L, FOOT_L, TOE_L, COUNT }

const NAMES: Array[String] = ["Hips", "Spine", "Chest", "Neck", "Head", "Shoulder_R", "UpperArm_R", "LowerArm_R", "Hand_R",
	"Shoulder_L", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperLeg_R", "LowerLeg_R", "Foot_R", "Toe_R",
	"UpperLeg_L", "LowerLeg_L", "Foot_L", "Toe_L"]
const PARENT: Array[int] = [-1, 0, 1, 2, 3, 2, 5, 6, 7, 2, 9, 10, 11, 0, 13, 14, 15, 0, 17, 18, 19]
const CHILD: Array[int] = [1, 2, 3, 4, -1, 6, 7, 8, -1, 10, 11, 12, -1, 14, 15, 16, -1, 18, 19, 20, -1]

var skel: Skeleton3D = null
var valid := false
var idx := PackedInt32Array()               # slot -> skeleton bone index (-1 = missing)
var rest_head := PackedVector3Array()       # model-space joint positions at rest
var rest_basis: Array[Basis] = []           # global rest orientation per bone
var rest_dir := PackedVector3Array()        # head -> tail direction at rest (roll independent)
var len1 := PackedFloat32Array()            # upper segment length (stored at UA_x / UL_x)
var len2 := PackedFloat32Array()            # lower segment length
var hand_rest_frame: Array[Basis] = []      # [R, L] socket frame at rest (z = -finger dir, y = thumb dir)
var hand_rest_frame_t: Array[Basis] = []
var hand_dir_rest: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]
var hips_rest_local := Vector3.ZERO
var ankle_height := 0.09

# per-solve results (valid after solve())
var D: Array[Basis] = []                    # model-space delta orientation per bone
var P := PackedVector3Array()               # posed joint positions per bone (model space)
var G: Array[Basis] = []                    # D * rest (global orientation)

var support_active := false                 # a weapon with Grip_L is mounted in the right hand
var support_offset := Vector3.ZERO          # Grip_L relative to the right wrist at rest orientation (model axes)
var _blend_src: Array[Quaternion] = []      # pose to fade out from (e.g. the ragdoll pose when getting up)
var _blend_hips := Vector3.ZERO
var _blend_t := 0.0
var _blend_len := 0.5

var _frest_t: Array[Basis] = []             # transposed rest frames for UA/LA/UL/LL
var _mid := Vector3.ZERO
var _end := Vector3.ZERO
var _perp := Vector3.ZERO


func setup(skeleton: Skeleton3D) -> bool:
	skel = skeleton
	valid = false
	if skel == null:
		return false
	idx.resize(COUNT)
	var missing: Array[String] = []
	for i in COUNT:
		var bi := skel.find_bone(NAMES[i])
		if bi < 0:
			bi = _find_loose(NAMES[i])
		idx[i] = bi
		if bi < 0:
			missing.append(NAMES[i])
	if not missing.is_empty():
		push_error("RigSolver: skeleton is missing bones %s - procedural animation disabled" % [missing])
		return false
	rest_head.resize(COUNT)
	rest_dir.resize(COUNT)
	len1.resize(COUNT)
	len2.resize(COUNT)
	P.resize(COUNT)
	rest_basis.clear()
	D.clear()
	G.clear()
	_frest_t.clear()
	for i in COUNT:
		var gr := skel.get_bone_global_rest(idx[i])
		rest_head[i] = gr.origin
		rest_basis.append(gr.basis.orthonormalized())
		D.append(Basis.IDENTITY)
		G.append(Basis.IDENTITY)
		_frest_t.append(Basis.IDENTITY)
	# directions from joint positions (robust against any authored bone roll / axis convention)
	for i in COUNT:
		var c: int = CHILD[i]
		if c >= 0:
			rest_dir[i] = (rest_head[c] - rest_head[i]).normalized()
		else:
			rest_dir[i] = rest_basis[i].y.normalized()
	_fix_leaf_dirs()
	for s in 2:
		var ua := UA_R + s * 4
		var ul := UL_R + s * 4
		len1[ua] = rest_head[ua + 1].distance_to(rest_head[ua])
		len2[ua] = rest_head[ua + 2].distance_to(rest_head[ua + 1])
		len1[ul] = rest_head[ul + 1].distance_to(rest_head[ul])
		len2[ul] = rest_head[ul + 2].distance_to(rest_head[ul + 1])
		var arm_side := Vector3(0, 0, 1)
		var leg_side := Vector3(0, 0, -1)
		_frest_t[ua] = _frame(rest_dir[ua], arm_side).transposed()
		_frest_t[ua + 1] = _frame(rest_dir[ua + 1], arm_side).transposed()
		_frest_t[ul] = _frame(rest_dir[ul], leg_side).transposed()
		_frest_t[ul + 1] = _frame(rest_dir[ul + 1], leg_side).transposed()
	hand_rest_frame.clear()
	hand_rest_frame_t.clear()
	for s in 2:
		var hd: int = HAND_R + s * 4
		var fd: Vector3 = rest_dir[hd]
		hand_dir_rest[s] = fd
		var thumb := Vector3(0, 0, -1)
		thumb = (thumb - fd * thumb.dot(fd)).normalized()
		var fr := _frame_from(-fd, thumb)
		hand_rest_frame.append(fr)
		hand_rest_frame_t.append(fr.transposed())
	hips_rest_local = skel.get_bone_rest(idx[HIPS]).origin
	ankle_height = rest_head[FOOT_R].y
	valid = true
	return true


func _find_loose(bone_name: String) -> int:
	var lname := bone_name.to_lower().replace("_", "").replace(".", "")
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower().replace("_", "").replace(".", "").replace(":", "")
		if n == lname or n.ends_with(lname):
			return i
	return -1


## Leaf bones (Hand, Toe, Head) have no child to measure: use the authored bone axis when it agrees with the spec.
func _fix_leaf_dirs() -> void:
	for s in 2:
		var sx := 1.0 if s == 0 else -1.0
		var hd: int = HAND_R + s * 4
		var spec := Vector3(sx * 0.04, -0.11, 0.0).normalized()
		if rest_dir[hd].dot(spec) < 0.8:
			rest_dir[hd] = spec
		var toe: int = TOE_R + s * 4
		var spec_toe := Vector3(0, -0.01, -0.1).normalized()
		if rest_dir[toe].dot(spec_toe) < 0.8:
			rest_dir[toe] = spec_toe
	var spec_head := Vector3(0, 1, 0)
	if rest_dir[HEAD].dot(spec_head) < 0.8:
		rest_dir[HEAD] = spec_head


# ---- Maths ------------------------------------------------------------------------------------------------------
## Orthonormal frame with Y = axis and Z = side (made perpendicular to the axis); X = Y x Z.
static func _frame(axis: Vector3, side: Vector3) -> Basis:
	var y := axis
	var z := side - y * side.dot(y)
	var zl := z.length()
	if zl < 1e-5:
		z = y.cross(Vector3.RIGHT)
		if z.length() < 1e-5:
			z = y.cross(Vector3.FORWARD)
		zl = z.length()
	z /= zl
	return Basis(y.cross(z), y, z)


## Orthonormal frame with Z = zaxis and Y = up hint (made perpendicular); X = Y x Z.
static func _frame_from(zaxis: Vector3, up: Vector3) -> Basis:
	var z := zaxis
	var y := up - z * up.dot(z)
	var yl := y.length()
	if yl < 1e-5:
		y = z.cross(Vector3.RIGHT)
		if y.length() < 1e-5:
			y = z.cross(Vector3.UP)
		yl = y.length()
	y /= yl
	return Basis(y.cross(z), y, z)


func _ik(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> void:
	var d := target - root
	var dist := d.length()
	if dist < 1e-5:
		d = Vector3(0, -1, 0)
		dist = 1e-5
	var dir := d / dist
	var dd := clampf(dist, absf(l1 - l2) + 0.02, (l1 + l2) * 0.9995)
	var a := (l1 * l1 - l2 * l2 + dd * dd) / (2.0 * dd)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := pole - dir * pole.dot(dir)
	var pl := perp.length()
	if pl < 1e-4:
		perp = dir.cross(Vector3.RIGHT)
		pl = perp.length()
		if pl < 1e-4:
			perp = dir.cross(Vector3.UP)
			pl = perp.length()
	perp /= pl
	_mid = root + dir * a + perp * h
	_end = root + dir * dd
	_perp = perp


# ---- Solve ------------------------------------------------------------------------------------------------------------
func solve(p: RigPose, dt: float = 0.0166) -> void:
	if not valid:
		return
	var hips_pos: Vector3 = p.v[RigPose.HIPS_POS]
	var dh := Basis.from_euler(p.v[RigPose.HIPS_ROT])
	if p.f[RigPose.F_GROUND] > 0.5:
		for _it in 2:
			var worst := 0.0
			for s in 2:
				var ul := UL_R + s * 4
				var root: Vector3 = rest_head[HIPS] + hips_pos + dh * (rest_head[ul] - rest_head[HIPS])
				var tgt: Vector3 = p.v[RigPose.LEG_R + s]
				worst = maxf(worst, root.distance_to(tgt) - (len1[ul] + len2[ul]) * 0.985)
			if worst > 0.001:
				hips_pos.y -= worst * 1.15
			else:
				break
	P[HIPS] = rest_head[HIPS] + hips_pos
	D[HIPS] = dh
	D[SPINE] = dh * Basis.from_euler(p.v[RigPose.SPINE_ROT])
	P[SPINE] = P[HIPS] + dh * (rest_head[SPINE] - rest_head[HIPS])
	D[CHEST] = D[SPINE] * Basis.from_euler(p.v[RigPose.CHEST_ROT])
	P[CHEST] = P[SPINE] + D[SPINE] * (rest_head[CHEST] - rest_head[SPINE])
	D[NECK] = D[CHEST] * Basis.from_euler(p.v[RigPose.NECK_ROT])
	P[NECK] = P[CHEST] + D[CHEST] * (rest_head[NECK] - rest_head[CHEST])
	D[HEAD] = D[NECK] * Basis.from_euler(p.v[RigPose.HEAD_ROT])
	P[HEAD] = P[NECK] + D[NECK] * (rest_head[HEAD] - rest_head[NECK])
	_solve_arm(p, 0)
	_solve_arm(p, 1)
	_solve_leg(p, 0, dh)
	_solve_leg(p, 1, dh)
	_write(hips_pos)
	if _blend_t > 0.0:
		_blend_t = maxf(_blend_t - dt / _blend_len, 0.0)


func _solve_arm(p: RigPose, s: int) -> void:
	var sh: int = SH_R + s * 4
	var ua := sh + 1
	var la := sh + 2
	var hd := sh + 3
	var cb: Basis = D[CHEST]
	var local_t: Vector3 = p.v[RigPose.ARM_R + s]
	var tgt: Vector3 = P[NECK] + cb * local_t
	if s == 1 and support_active and p.f[RigPose.F_SUPPORT] > 0.01:
		# left palm on the weapon's Grip_L (computed from the already solved right hand)
		var grip: Vector3 = P[HAND_R] + D[HAND_R] * support_offset
		var hdir_l: Vector3 = (cb * p.v[RigPose.HDIR_L]).normalized()
		var snapped: Vector3 = grip - hdir_l * 0.05
		tgt = tgt.lerp(snapped, p.f[RigPose.F_SUPPORT])
		local_t = cb.transposed() * (tgt - P[NECK])
	# shoulder girdle follows the reach a little (raise / protract when the arm goes up or forward)
	var dev: Vector3 = (local_t - (rest_head[hd] - rest_head[NECK])).limit_length(0.8)
	var sdir: Vector3 = (rest_dir[sh] + dev * 0.30).normalized()
	D[sh] = cb * Basis(Quaternion(rest_dir[sh].normalized(), sdir.normalized()))
	P[sh] = P[CHEST] + cb * (rest_head[sh] - rest_head[CHEST])
	P[ua] = P[sh] + D[sh] * (rest_head[ua] - rest_head[sh])
	_ik(P[ua], tgt, len1[ua], len2[ua], cb * p.v[RigPose.POLE_R + s])
	var mid := _mid
	var endp := _end
	var perp := _perp
	var a1 := (mid - P[ua]).normalized()
	var a2 := (endp - mid).normalized()
	D[ua] = _frame(a1, perp) * _frest_t[ua]
	D[la] = _frame(a2, perp) * _frest_t[la]
	P[la] = mid
	P[hd] = endp
	var ovr: float = p.f[RigPose.F_HOVR_R + s]
	if ovr < 0.002:
		D[hd] = D[la]
	else:
		var hdir: Vector3 = (cb * p.v[RigPose.HDIR_R + s]).normalized()
		var hup: Vector3 = cb * p.v[RigPose.HUP_R + s]
		var over: Basis = _frame_from(-hdir, hup) * hand_rest_frame_t[s]
		if ovr > 0.998:
			D[hd] = over
		else:
			D[hd] = Basis(Quaternion(D[la].orthonormalized()).slerp(Quaternion(over.orthonormalized()), ovr))


func _solve_leg(p: RigPose, s: int, dh: Basis) -> void:
	var ul: int = UL_R + s * 4
	var ll := ul + 1
	var ft := ul + 2
	var toe := ul + 3
	P[ul] = P[HIPS] + dh * (rest_head[ul] - rest_head[HIPS])
	_ik(P[ul], p.v[RigPose.LEG_R + s], len1[ul], len2[ul], p.v[RigPose.KNEE_R + s])
	var mid := _mid
	var endp := _end
	var perp := _perp
	D[ul] = _frame((mid - P[ul]).normalized(), perp) * _frest_t[ul]
	D[ll] = _frame((endp - mid).normalized(), perp) * _frest_t[ll]
	P[ll] = mid
	P[ft] = endp
	D[ft] = Basis.from_euler(p.v[RigPose.FOOT_R + s])
	D[toe] = D[ft] * Basis(Vector3.RIGHT, p.f[RigPose.F_TOE_R + s])
	P[toe] = endp + D[ft] * (rest_head[toe] - rest_head[ft])


func _write(hips_pos: Vector3) -> void:
	var blending := _blend_t > 0.0 and _blend_src.size() == COUNT
	var bw := smoothstep(0.0, 1.0, _blend_t)
	for i in COUNT:
		var gb: Basis = D[i] * rest_basis[i]
		G[i] = gb
		var par: int = PARENT[i]
		var lb: Basis = gb if par < 0 else G[par].transposed() * gb
		var q := lb.get_rotation_quaternion()
		if blending:
			q = q.slerp(_blend_src[i], bw)
		skel.set_bone_pose_rotation(idx[i], q)
	var hp: Vector3 = hips_rest_local + (P[HIPS] - rest_head[HIPS])
	if blending:
		hp = hp.lerp(_blend_hips, bw)
	skel.set_bone_pose_position(idx[HIPS], hp)


## Fade from a captured pose (see RagdollBody.capture_pose) into the animated pose over `length` seconds.
func begin_blend_from(snap: Dictionary, length: float = 0.5) -> void:
	if snap.is_empty():
		return
	_blend_src.clear()
	for q in snap["q"]:
		_blend_src.append(q)
	_blend_hips = snap["hips"]
	_blend_t = 1.0
	_blend_len = length


## Writes the rest pose (T/A-pose) - used when animation is disabled.
func write_rest() -> void:
	if skel == null:
		return
	skel.reset_bone_poses()


# ---- Queries (skeleton / model space) ----------------------------------------------------------------------------------
func head_center() -> Vector3:
	return P[HEAD] + D[HEAD] * ((rest_head[HEAD] + Vector3(0, 0.14, 0)) - rest_head[HEAD])


func eye_position() -> Vector3:
	return P[HEAD] + D[HEAD] * Vector3(0, 0.15, -0.09)
