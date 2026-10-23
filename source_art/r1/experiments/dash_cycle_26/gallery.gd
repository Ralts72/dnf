extends RefCounted
## Show native1x bakes with nearest2x sampling; no live deformation at2x.

func run(main: Node) -> Dictionary:
	var viewport:=SubViewport.new();viewport.size=Vector2i(640,448);viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	main.get_tree().root.add_child(viewport)
	var bg:=ColorRect.new();bg.size=Vector2(640,448);bg.color=Color(.2,.25,.28);viewport.add_child(bg)
	var actor:=Sprite2D.new();actor.centered=false;actor.scale=Vector2(2,2);actor.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;viewport.add_child(actor)
	var cases: Array=[];var textures: Dictionary={}
	for frame: int in 8:
		for sub: int in 3:
			var path: String="res://source_art/r1/experiments/dash_cycle_26/baked/dash_%02d_%d.png"%[frame,sub]
			var image:=Image.new();assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK);textures[frame*3+sub]=ImageTexture.create_from_image(image)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/r1_26_cycle"))
	for facing: int in [1,-1]:
		actor.scale.x=2.0*facing;actor.position.x=0 if facing==1 else 532
		for frame: int in 8:
			for sub: int in 3:
				actor.texture=textures[frame*3+sub]
				for _i: int in 3:await RenderingServer.frame_post_draw
				var path: String="res://work/r1_26_cycle/%s_%02d_%d.png"%["r" if facing==1 else "l",frame,sub]
				viewport.get_texture().get_image().save_png(path)
				cases.append({"facing":facing,"frame":frame,"subframe":sub,"capture":path,"png_sha256":FileAccess.get_sha256(path)})
	viewport.queue_free()
	var result: Dictionary={"study":"R1/26 native1x dash bakes at2x, both facings","cases":cases,"cycle_ms":800,"nominal_lower_sample_rate_hz":30,
		"qa_source_sha256":get_script().source_code.sha256_text(),"bake_report_sha256":FileAccess.get_sha256("res://docs/r1_26_bake_checks.json"),
		"recipe_sha256":FileAccess.get_sha256("res://source_art/r1/experiments/dash_cycle_26/dash_recipe.json")}
	var out:=FileAccess.open("res://docs/r1_26_cycle_gallery.json",FileAccess.WRITE);out.store_string(JSON.stringify(result,"  "));out.close()
	return {"cases":cases.size()}
