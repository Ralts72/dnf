extends RefCounted
## Native A/B preview frames, retaining the original800ms cycle on both sides.

func run(main: Node) -> Dictionary:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,488);viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	main.get_tree().root.add_child(viewport)
	var bg:=ColorRect.new();bg.size=Vector2(1280,488);bg.color=Color(.2,.25,.28);viewport.add_child(bg)
	var script:=GDScript.new();script.source_code=FileAccess.get_file_as_string("res://source_art/r1/experiments/dash_cycle_26/baked_actor.gd");assert(script.reload()==OK)
	var actors: Array=[]
	for side: int in 2:
		var actor: Node2D=script.new();actor.position=Vector2(side*640,40);actor.scale=Vector2(2,2);viewport.add_child(actor);actors.append(actor)
		var label:=Label.new();label.position=Vector2(16+640*side,6);label.add_theme_font_size_override("font_size",20)
		label.text=["原图：8 帧／800 ms","下肢过渡：24 采样／800 ms · 上半身原图"][side];viewport.add_child(label)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://source_art/r1/experiments/dash_cycle_26/comparison"))
	var records: Array=[]
	for i: int in 24:
		actors[0].update_pose(i/3,0);actors[1].update_pose(i/3,i%3)
		for _j: int in 3:await RenderingServer.frame_post_draw
		var path: String="res://source_art/r1/experiments/dash_cycle_26/comparison/pair_%02d.png"%i
		viewport.get_texture().get_image().save_png(path);records.append({"phase":i,"path":path,"sha256":FileAccess.get_sha256(path)})
	viewport.queue_free()
	var result: Dictionary={"records":records,"size":Vector2i(1280,488),"cycle_ms":800,"qa_sha256":get_script().source_code.sha256_text()}
	var f:=FileAccess.open("res://docs/r1_26_comparison_capture.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
	return {"captures":records.size()}
