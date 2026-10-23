extends RefCounted
## Capture an actual full-frame engine render, independent of desktop window size.

func run(main: Node,prefix: String="r1_20") -> Dictionary:
	var tree: SceneTree=main.get_tree()
	var original_state: Dictionary=main.player.capture_state()
	var original_update: int=main.render_viewport.render_target_update_mode
	var original_scale: int=main.render_scale
	var original_water: Dictionary=main.water.capture_state()
	var music: Node=tree.root.get_node("PortMusic")
	var music_id: int=music.player.get_instance_id()
	var music_starts: int=music.play_starts
	var ambience: Node=tree.root.get_node("PortAmbience")
	var ambient_id: int=ambience.player.get_instance_id()
	var ambient_starts: int=ambience.play_starts
	main._set_paused(true)
	main.render_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var full:=SubViewport.new()
	full.name="R1FullFrameCapture"
	full.size=Vector2i(1920,1080)
	full.size_2d_override=Vector2i(960,540)
	full.size_2d_override_stretch=true
	full.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(full)
	var clone: Node=load("res://scenes/west_coast_r1.tscn").instantiate()
	full.add_child(clone)
	clone.set_render_scale(2)
	clone.player.restore_state(original_state)
	clone.water.restore_state(original_water)
	clone._set_paused(true)
	for _i in range(5):
		await RenderingServer.frame_post_draw
	var image: Image=full.get_texture().get_image()
	var child_image: Image=clone.render_viewport.get_texture().get_image()
	var path: String="res://docs/previews/"+prefix+"_full1080.png"
	image.save_png(path)
	var report: Dictionary={"capture":path,"full_target":image.get_size(),"scene_target":child_image.get_size(),
		"own_texture_binding":clone.render_surface.texture==clone.render_viewport.get_texture(),
		"captured_water_seconds":clone.water.seconds,"source_water_seconds":original_water["seconds"],
		"private_water_material":clone.water.water_material!=main.water.water_material,
		"single_music_player_retained":music.player.get_instance_id()==music_id and music.play_starts==music_starts,
		"single_ambient_player_retained":ambience.player.get_instance_id()==ambient_id and ambience.play_starts==ambient_starts,
		"draw_calls":clone.render_viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"note":"Native Godot full-frame output with animation paused for the snapshot. Main scene is restored afterward. Not a performance benchmark."}
	main.render_viewport.render_target_update_mode=original_update as SubViewport.UpdateMode
	main.set_render_scale(original_scale)
	main.player.restore_state(original_state)
	main.water.restore_state(original_water)
	main._set_paused(original_state["paused"])
	full.queue_free()
	await tree.process_frame
	var out:=FileAccess.open("res://docs/"+prefix+"_capture.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	return report
