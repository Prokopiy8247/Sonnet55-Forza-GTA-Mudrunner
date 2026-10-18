class_name RagdollBody
extends RefCounted
## Physical ragdoll for CharacterRig, built in code from the rig skeleton: PhysicalBoneSimulator3D + one PhysicalBone3D per major
## bone (capsules / sphere / boxes, cone-twist joints for the spine, neck, shoulders and hips, hinges for elbows and knees),
## layer GC.L_RAGDOLL, mask world | vehicle | prop (no self collision, joints do the limiting).
## The body starts from the CURRENT animated pose and inherits the owner's velocity. It freezes after FREEZE_AFTER seconds (or as
## soon as it is calm): the final pose is written back into the skeleton and all physics objects are freed (zero cost).
## A static cap (MAX_LIVE) freezes the oldest ragdoll early when too many are alive.

signal settled
signal culled

const MAX_LIVE := 8
const FREEZE_AFTER := 8.0
const CALM_SPEED := 0.14
const CALM_TIME := 0.9

static var live: Array[RagdollBody] = []

# slot, mass, kind (capsule | sphere | box), radius, joint (none | cone | hinge_pos | hinge_neg), swing, twist, lo, hi
# hinge limits are flexion angles (rad); a hinge's axis is the lateral axis chosen so that flexion is positive.
const DEFS := [
	[RigSolver.HIPS, 14.0, "box", 0.0, "none", 0.0, 0.0],
	[RigSolver.SPINE, 8.0, "capsule", 0.125, "cone", 0.45, 0.35],
	[RigSolver.CHEST, 14.0, "capsule", 0.16, "cone", 0.45, 0.35],
	[RigSolver.HEAD, 5.0, "sphere", 0.115, "cone", 0.85, 0.75],
	[RigSolver.UA_R, 2.2, "capsule", 0.05, "cone", 1.5, 0.9],
	[RigSolver.LA_R, 1.9, "capsule", 0.045, "hinge_arm", 0.0, 0.0],
	[RigSolver.UA_L, 2.2, "capsule", 0.05, "cone", 1.5, 0.9],
	[RigSolver.LA_L, 1.9, "capsule", 0.045, "hinge_arm", 0.0, 0.0],
	[RigSolver.UL_R, 8.0, "capsule", 0.085, "cone", 1.1, 0.45],
	[RigSolver.LL_R, 4.5, "capsule", 0.062, "hinge_leg", 0.0, 0.0],
	[RigSolver.FOOT_R, 1.2, "box", 0.0, "cone", 0.5, 0.25],
	[RigSolver.UL_L, 8.0, "capsule", 0.085, "cone", 1.1, 0.45],
	[RigSolver.LL_L, 4.5, "capsule", 0.062, "hinge_leg", 0.0, 0.0],
	[RigSolver.FOOT_L, 1.2, "box", 0.0, "cone", 0.5, 0.25],
]

var rig: Node3D = null
var skel: Skeleton3D = null
var solver: RigSolver = null
var sim: PhysicalBoneSimulator3D = null
var bodies: Array[PhysicalBone3D] = []
var slots: Array[int] = []
var active := false
var age := 0.0
var _calm := 0.0
var _ticker: Node = null
var _frozen := false


class Ticker:
	extends Node
	var body: RagdollBody = null

	func _physics_process(dt: float) -> void:
		if body != null:
			body.tick(dt)


func start(owner_rig: Node3D, skeleton: Skeleton3D, slv: RigSolver, impulse: Vector3, hit_pos: Vector3, inherit_velocity: Vector3) -> bool:
	rig = owner_rig
	skel = skeleton
	solver = slv
	if skel == null or not skel.is_inside_tree():
		push_warning("RagdollBody: skeleton is not in the scene tree - ragdoll skipped")
		return false
	# drop stale entries (owner freed without destroy), then cap the number of live ragdolls: freeze the oldest
	for i in range(live.size() - 1, -1, -1):
		var r: RagdollBody = live[i]
		if r == null or not r.active or r.skel == null or not is_instance_valid(r.skel) or not r.skel.is_inside_tree():
			live.remove_at(i)
	while live.size() >= MAX_LIVE:
		var oldest: RagdollBody = live.pop_front()
		if oldest != null and oldest.active:
			oldest.freeze(true)
	sim = PhysicalBoneSimulator3D.new()
	sim.name = "RagdollSimulator"
	skel.add_child(sim)
	var bone_scale := skel.global_transform.basis.get_scale().x
	for d in DEFS:
		var slot: int = d[0]
		var bi: int = solver.idx[slot]
		if bi < 0:
			continue
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + RigSolver.NAMES[slot]
		sim.add_child(pb)
		pb.bone_name = skel.get_bone_name(bi)
		pb.mass = float(d[1])
		pb.collision_layer = GC.L_RAGDOLL
		pb.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP
		pb.linear_damp = 0.12
		pb.angular_damp = 2.2
		pb.friction = 0.9
		pb.bounce = 0.05
		pb.can_sleep = true
		_add_shape(pb, slot, String(d[2]), float(d[3]), bone_scale)
		bodies.append(pb)
		slots.append(slot)
	# joints (after all bodies exist)
	for i in bodies.size():
		_setup_joint(bodies[i], slots[i], DEFS[_def_index(slots[i])])
	sim.physical_bones_start_simulation()
	# initial velocity: inherited movement + hit impulse (m/s)
	var imp := impulse
	if imp.length() > 25.0:
		imp = imp.normalized() * 25.0
	for i in bodies.size():
		bodies[i].linear_velocity = inherit_velocity
	if imp.length() > 0.01:
		kick(imp, hit_pos)
	_ticker = Ticker.new()
	(_ticker as Ticker).body = self
	_ticker.name = "RagdollTicker"
	sim.add_child(_ticker)
	active = true
	age = 0.0
	live.append(self)
	return true


func _def_index(slot: int) -> int:
	for i in DEFS.size():
		if DEFS[i][0] == slot:
			return i
	return 0


func _add_shape(pb: PhysicalBone3D, slot: int, kind: String, radius: float, sc: float) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	pb.add_child(cs)
	var rb: Basis = solver.rest_basis[slot]
	var dir_world: Vector3 = solver.rest_dir[slot]
	var dir_local: Vector3 = rb.transposed() * dir_world       # bone axis expressed in the bone's own frame
	var length := _bone_length(slot)
	match kind:
		"capsule":
			var shape := CapsuleShape3D.new()
			var h := maxf(length + radius, radius * 2.05)
			if slot == RigSolver.LA_R or slot == RigSolver.LA_L:
				h = length + 0.12                      # include the hand
			if slot == RigSolver.CHEST:
				h = length + radius * 0.6
			shape.radius = radius
			shape.height = h
			cs.shape = shape
			var yb := Basis(Quaternion(Vector3.UP, dir_local))
			var centre := dir_local * (h * 0.5 - radius * 0.5 if slot != RigSolver.CHEST else length * 0.55)
			cs.transform = Transform3D(yb, centre)
		"sphere":
			var shape := SphereShape3D.new()
			shape.radius = radius
			cs.shape = shape
			cs.transform = Transform3D(Basis.IDENTITY, rb.transposed() * (Vector3(0, 0.14, 0)))
		"box":
			var shape := BoxShape3D.new()
			if slot == RigSolver.HIPS:
				shape.size = Vector3(0.32, 0.20, 0.20)
				cs.shape = shape
				cs.transform = Transform3D(Basis.IDENTITY, rb.transposed() * Vector3(0, -0.02, 0))
			else:
				shape.size = Vector3(0.10, 0.075, 0.27)
				cs.shape = shape
				cs.transform = Transform3D(Basis.IDENTITY, rb.transposed() * Vector3(0, -0.04, -0.07))
				# the foot box is axis aligned in MODEL space: rotate it into the bone frame
				cs.transform = Transform3D(rb.transposed(), rb.transposed() * Vector3(0, -0.04, -0.07))


func _bone_length(slot: int) -> float:
	var c: int = RigSolver.CHILD[slot]
	if c >= 0:
		return solver.rest_head[c].distance_to(solver.rest_head[slot])
	return 0.2


func _setup_joint(pb: PhysicalBone3D, slot: int, d: Array) -> void:
	var jt := String(d[4])
	if jt == "none":
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		return
	var rb: Basis = solver.rest_basis[slot]
	if jt == "cone":
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		# twist axis (joint X) along the bone direction
		var dir_local: Vector3 = (rb.transposed() * solver.rest_dir[slot]).normalized()
		var fr := _basis_x_along(dir_local)
		pb.joint_offset = Transform3D(fr, Vector3.ZERO)
		pb.set("joint_constraints/swing_span", rad_to_deg(float(d[5])))
		pb.set("joint_constraints/twist_span", rad_to_deg(float(d[6])))
		pb.set("joint_constraints/bias", 0.3)
		pb.set("joint_constraints/softness", 0.8)
		pb.set("joint_constraints/relaxation", 1.0)
	else:
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
		# hinge axis (joint Z) = lateral axis chosen so that flexion is positive:
		# elbows flex by rotating about +X (forearm swings forward), knees by rotating about -X (shin swings back)
		var axis_model := Vector3.RIGHT if jt == "hinge_arm" else Vector3.LEFT
		var axis_local: Vector3 = (rb.transposed() * axis_model).normalized()
		var fr := _basis_z_along(axis_local)
		pb.joint_offset = Transform3D(fr, Vector3.ZERO)
		pb.set("joint_constraints/angular_limit_enabled", true)
		# the PhysicalBone3D joint properties are expressed in DEGREES
		pb.set("joint_constraints/angular_limit_lower", 0.0)
		pb.set("joint_constraints/angular_limit_upper", 135.0 if jt == "hinge_leg" else 140.0)


static func _basis_x_along(x: Vector3) -> Basis:
	var ref := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var z := x.cross(ref).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


static func _basis_z_along(z: Vector3) -> Basis:
	var ref := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


## Extra velocity kick (m/s) concentrated on the body part nearest to `hit_pos`.
func kick(impulse: Vector3, hit_pos: Vector3) -> void:
	if bodies.is_empty():
		return
	var imp := impulse
	if imp.length() > 25.0:
		imp = imp.normalized() * 25.0
	var best := 0
	var best_d := INF
	if hit_pos != Vector3.ZERO:
		for i in bodies.size():
			var d := bodies[i].global_position.distance_squared_to(hit_pos)
			if d < best_d:
				best_d = d
				best = i
	var total_mass := 0.0
	for pb in bodies:
		total_mass += pb.mass
	for i in bodies.size():
		var w := 0.55 if hit_pos == Vector3.ZERO else (1.0 if i == best else 0.35)
		bodies[i].apply_central_impulse(imp * bodies[i].mass * w)
	if hit_pos != Vector3.ZERO:
		# a little spin from the off-centre hit
		var rel := hit_pos - bodies[best].global_position
		bodies[best].apply_impulse(imp * bodies[best].mass * 0.5, rel.limit_length(0.3))


func get_center() -> Vector3:
	if not bodies.is_empty() and is_instance_valid(bodies[0]):
		return bodies[0].global_position
	if rig != null and is_instance_valid(rig):
		return rig.global_position
	return Vector3.ZERO


func tick(dt: float) -> void:
	if not active:
		return
	age += dt
	if age > 0.8:
		var fastest := 0.0
		for pb in bodies:
			fastest = maxf(fastest, pb.linear_velocity.length() + pb.angular_velocity.length() * 0.05)
		if fastest < CALM_SPEED:
			_calm += dt
		else:
			_calm = 0.0
		if _calm >= CALM_TIME or age >= FREEZE_AFTER:
			freeze(false)
	# keep it from falling out of the world
	if bodies.size() > 0 and is_instance_valid(bodies[0]) and bodies[0].global_position.y < -80.0:
		freeze(false)


## Bakes the current physical pose into the skeleton and frees every physics object. `early` = culled by the live cap.
func freeze(early: bool) -> void:
	if not active or skel == null or not is_instance_valid(skel):
		return
	var snap := capture_pose()
	active = false
	live.erase(self)
	_destroy_nodes()
	_frozen = true
	if not snap.is_empty():
		var q: Array = snap["q"]
		for i in RigSolver.COUNT:
			skel.set_bone_pose_rotation(solver.idx[i], q[i])
		skel.set_bone_pose_position(solver.idx[RigSolver.HIPS], snap["hips"])
	if early:
		culled.emit()
	else:
		settled.emit()


## Local bone rotations (per solver slot) + hips position of the pose the ragdoll currently shows. Read straight from the
## physics bodies (bones without a body keep their animated local pose), so it does not depend on skeleton update timing.
func capture_pose() -> Dictionary:
	if skel == null or not is_instance_valid(skel) or solver == null or not solver.valid:
		return {}
	var inv := skel.global_transform.affine_inverse()
	var body_of := {}
	for i in bodies.size():
		if is_instance_valid(bodies[i]):
			body_of[slots[i]] = bodies[i]
	var gp: Array[Transform3D] = []
	for i in RigSolver.COUNT:
		var par: int = RigSolver.PARENT[i]
		if body_of.has(i):
			var xf: Transform3D = inv * (body_of[i] as PhysicalBone3D).global_transform
			xf.basis = xf.basis.orthonormalized()
			gp.append(xf)
		else:
			var local := skel.get_bone_pose(solver.idx[i])
			local.basis = local.basis.orthonormalized()
			gp.append(local if par < 0 else gp[par] * local)
	var q: Array[Quaternion] = []
	for i in RigSolver.COUNT:
		var par: int = RigSolver.PARENT[i]
		var local_xf: Transform3D = gp[i] if par < 0 else gp[par].affine_inverse() * gp[i]
		q.append(local_xf.basis.orthonormalized().get_rotation_quaternion())
	return {"q": q, "hips": gp[0].origin}


## World position of a simulated bone (falls back to the rig position).
func part_position(slot: int) -> Vector3:
	for i in bodies.size():
		if slots[i] == slot and is_instance_valid(bodies[i]):
			return bodies[i].global_position
	return get_center()


func destroy() -> void:
	active = false
	live.erase(self)
	_destroy_nodes()


func _destroy_nodes() -> void:
	bodies.clear()
	slots.clear()
	if sim != null and is_instance_valid(sim):
		sim.physical_bones_stop_simulation()
		if sim.get_parent() != null:
			sim.get_parent().remove_child(sim)
		sim.queue_free()
	sim = null
	_ticker = null
