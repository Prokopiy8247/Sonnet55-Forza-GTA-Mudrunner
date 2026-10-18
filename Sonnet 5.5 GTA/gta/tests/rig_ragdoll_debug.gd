extends Node
## Debug helper for the ragdoll: prints body positions over time. Run via rig_runner.gd --test=res://gta/tests/rig_ragdoll_debug.gd

func run(main: Node) -> Variant:
	var stage := Node3D.new()
	main.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = GC.L_WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	floor_body.add_child(cs)
	stage.add_child(floor_body)
	var r := CharacterRig.new()
	r.manual_update = true
	stage.add_child(r)
	r.setup(CharacterVariants.player_default())
	for i in 10:
		r.update_pose(1.0 / 60.0)
	await get_tree().process_frame
	r.start_ragdoll(Vector3(0, 0, -3), Vector3.ZERO)
	var rb: RagdollBody = r._ragdoll
	print("RAGDOLL bodies=", rb.bodies.size() if rb != null else -1, " active=", rb.active if rb != null else false)
	if rb == null:
		return false
	for pb in rb.bodies:
		print("  ", pb.name, " pos=", pb.global_position, " joint=", pb.joint_type, " layer=", pb.collision_layer, " mask=", pb.collision_mask)
	var sk := r.get_skeleton()
	var solver: RigSolver = r.solver
	for k in 12:
		for j in 15:
			await get_tree().physics_frame
		# joint flexion in rest-model axes: direction of the lower segment as seen from the upper segment (from the physics bodies)
		if rb.active:
			var line := "FLEX"
			for pair in [[RigSolver.UL_R, RigSolver.LL_R, "kneeR"], [RigSolver.UL_L, RigSolver.LL_L, "kneeL"], [RigSolver.UA_R, RigSolver.LA_R, "elbowR"], [RigSolver.UA_L, RigSolver.LA_L, "elbowL"]]:
				var up_b: PhysicalBone3D = null
				var lo_b: PhysicalBone3D = null
				for i in rb.slots.size():
					if rb.slots[i] == pair[0]:
						up_b = rb.bodies[i]
					if rb.slots[i] == pair[1]:
						lo_b = rb.bodies[i]
				if up_b == null or lo_b == null:
					continue
				var d_up: Basis = up_b.global_transform.basis * solver.rest_basis[pair[0]].transposed()
				var d_lo: Basis = lo_b.global_transform.basis * solver.rest_basis[pair[1]].transposed()
				var seg_dir: Vector3 = d_lo * solver.rest_dir[pair[1]]          # lower segment direction in world
				var local_dir: Vector3 = d_up.transposed() * seg_dir            # ... as seen from the upper segment's rest frame
				line += " %s(z=%.2f ang=%.0f)" % [pair[2], local_dir.z, rad_to_deg(acos(clampf(local_dir.dot(solver.rest_dir[pair[1]]), -1.0, 1.0)))]
			print(line)
		if rb.bodies.size() > 3:
			var hips: PhysicalBone3D = rb.bodies[0]
			var head: PhysicalBone3D = rb.bodies[3]
			print("t=%.2f hips=%s v=%s head=%s active=%s" % [float(k + 1) * 15.0 / 60.0, hips.global_position, hips.linear_velocity, head.global_position, rb.active])
		else:
			print("t=%.2f frozen/destroyed active=%s" % [float(k + 1) * 15.0 / 60.0, rb.active])
	if OS.get_cmdline_user_args().has("--cleanup"):
		stage.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		print("RAGDOLL cleanup done")
	return true
