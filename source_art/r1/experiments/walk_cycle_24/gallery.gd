extends RefCounted

func run(main: Node) -> Dictionary:
	var script:=GDScript.new()
	script.source_code=FileAccess.get_file_as_string("res://source_art/r1/experiments/walk_cycle_24/actor.gd")
	assert(script.reload()==OK)
	var viewport:=SubViewport.new();viewport.size=Vector2i(640,448)
	viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	main.get_tree().root.add_child(viewport)
	var bg:=ColorRect.new();bg.size=Vector2(640,448);bg.color=Color(.2,.25,.28);viewport.add_child(bg)
	var actor: Node2D=script.new();actor.scale=Vector2(2,2);viewport.add_child(actor)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/r1_24_cycle"))
	var cases: Array=[]
	for facing: int in [1,-1]:
		actor.scale.x=2.0*facing;actor.position.x=0 if facing==1 else 532
		for frame: int in 8:
			for subframe: int in 3:
				actor.update_pose(frame,subframe)
				for _i: int in 3:await RenderingServer.frame_post_draw
				var image: Image=viewport.get_texture().get_image()
				var path: String="res://work/r1_24_cycle/%s_%02d_%d.png"%["r" if facing==1 else "l",frame,subframe]
				image.save_png(path)
				cases.append({"facing":facing,"frame":frame,"subframe":subframe,"capture":path})
	viewport.queue_free()
	var result: Dictionary={"study":"R1/24 authored full walk cycle, not integrated","cases":cases,"cycle_ms":800,"nominal_samples_per_second":30,
		"qa_source_sha256":get_script().source_code.sha256_text(),"actor_source_sha256":script.source_code.sha256_text(),
		"shader_sha256":FileAccess.get_sha256("res://source_art/r1/experiments/walk_cycle_24/walk_shear.gdshader"),
		"recipe_sha256":FileAccess.get_sha256("res://source_art/r1/experiments/walk_cycle_24/walk_recipe.json")}
	var out:=FileAccess.open("res://docs/r1_24_cycle_gallery.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(result,"  "));out.close()
	return {"cases":cases.size()}
