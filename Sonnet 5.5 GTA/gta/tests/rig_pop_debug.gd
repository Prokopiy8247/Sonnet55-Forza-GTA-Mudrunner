extends Node
## Debug: prints elbow / wrist travel per frame at the start of an action.

func run(main: Node) -> Variant:
	var r := CharacterRig.new()
	r.manual_update = true
	main.add_child(r)
	r.setup(CharacterVariants.player_default())
	r.set_locomotion(0.0)
	for i in 60:
		r.update_pose(1.0 / 60.0)
	var sk := r.get_skeleton()
	var act := &"punch"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--act="):
			act = StringName(String(a).substr(6))
	var prev_e := sk.get_bone_global_pose(sk.find_bone("LowerArm_R")).origin
	var prev_w := sk.get_bone_global_pose(sk.find_bone("Hand_R")).origin
	r.play_action(act)
	for f in 24:
		r.update_pose(1.0 / 60.0)
		var e := sk.get_bone_global_pose(sk.find_bone("LowerArm_R")).origin
		var w := sk.get_bone_global_pose(sk.find_bone("Hand_R")).origin
		print("POPDBG f=%d prog=%.2f elbow=%s d=%.3f wrist=%s d=%.3f arm_target=%s pole=%s" % [f, r.action_progress(), e, e.distance_to(prev_e), w, w.distance_to(prev_w), r.motion.pose.v[RigPose.ARM_R], r.motion.pose.v[RigPose.POLE_R]])
		prev_e = e
		prev_w = w
	r.queue_free()
	return true
