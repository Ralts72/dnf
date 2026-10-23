extends RefCounted
## Render actor motion in fixed 40ms steps; these are engine frames, not a
## recording of desktop frame times. Environment shader TIME remains live.

func run(main: Node,prefix: String="r1_06") -> Dictionary:
	var tree: SceneTree=main.get_tree()
	var original: Dictionary=main.player.capture_state()
	var original_update: int=main.render_viewport.render_target_update_mode
	var original_scale: int=main.render_scale
	main._set_paused(true)
	main.render_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var full:=SubViewport.new()
	full.name="R1MotionDemoCapture"
	full.size=Vector2i(960,540)
	full.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(full)
	var clone: Node=load("res://scenes/west_coast_r1.tscn").instantiate()
	full.add_child(clone)
	clone.set_render_scale(2)
	clone.player.reset_position()
	clone._set_paused(false)
	clone.set_process(false)
	var actors: Array=[clone.player,clone.npc_lo,clone.npc_sr]
	for actor: Node in actors:
		actor.set_process(false)
		actor.set_physics_process(false)
	var props: Array=clone.world.get_node("SourceProps").get_children()
	for prop: Node in props:
		prop.set_process(false)
	var directory: String="res://work/"+prefix+"_motion_frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var states: Array=[]
	for index: int in range(48):
		if index==6:
			clone.player.start_jump()
		if clone.player.jump_motion.is_airborne() and clone.player.jump_motion.elapsed>=.34 and not clone.player.jump_motion.air_attack_used:
			clone.player.attack()
		if clone.player.jump_motion.is_active():
			clone.player._tick_jump(.04,false)
		else:
			clone.player._process(.04)
		for actor: Node in [clone.npc_lo,clone.npc_sr]:
			actor._process(.04)
		for prop: Node in props:
			prop._process(.04)
		clone._process(.04)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var frame: Image=full.get_texture().get_image()
		frame.save_png(directory+"/%03d.png"%index)
		states.append({"frame":index,"duration_ms":40,"phase":clone.player.jump_motion.phase,
			"height":clone.player.jump_motion.height_pixels,"action":clone.player.animation_name,
			"source_frame":clone.player.frame_index})
	var report: Dictionary={"candidate":"R1/06","frames_directory":directory,"frames":states,
		"size":full.size,"scene_render_size":clone.render_viewport.size,"frame_duration_ms":40,
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"notes":["Native Godot offscreen output. Actors and original prop animations use fixed 40ms steps.",
			"Environment shader TIME follows capture wall time. This is a motion demonstration, not a frame-rate benchmark."]}
	main.render_viewport.render_target_update_mode=original_update as SubViewport.UpdateMode
	main.set_render_scale(original_scale)
	main.player.restore_state(original)
	main._set_paused(original["paused"])
	full.queue_free()
	await tree.process_frame
	var out:=FileAccess.open("res://docs/"+prefix+"_motion_capture.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	return {"frames":states.size(),"directory":directory,"size":report["size"]}
