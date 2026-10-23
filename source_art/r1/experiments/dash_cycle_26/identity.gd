extends RefCounted

func run(main: Node) -> Dictionary:
	var script:=GDScript.new();script.source_code=FileAccess.get_file_as_string("res://source_art/r1/experiments/dash_cycle_26/actor.gd");assert(script.reload()==OK)
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,224);viewport.transparent_bg=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	main.get_tree().root.add_child(viewport);var actor: Node2D=script.new();viewport.add_child(actor);actor.identity_test=true
	var cases: Array=[]
	for frame: int in 8:
		actor.update_pose(frame,1)
		for _i: int in 3:await RenderingServer.frame_post_draw
		var actual: Image=viewport.get_texture().get_image();actual.convert(Image.FORMAT_RGBA8)
		var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json")).animations.dash.frames[frame]
		var expected:=Image.new();expected.load_png_from_buffer(FileAccess.get_file_as_bytes(raw.texture));expected.convert(Image.FORMAT_RGBA8)
		var mismatches: int=0;var examples: Array=[]
		for y: int in 224:
			for x: int in 320:
				if actual.get_pixel(x,y)!=expected.get_pixel(x,y):
					mismatches+=1
					if examples.size()<8:examples.append({"pixel":Vector2i(x,y),"actual":actual.get_pixel(x,y),"expected":expected.get_pixel(x,y)})
		actual.save_png("res://work/r1_26_identity_%d.png"%frame)
		cases.append({"frame":frame,"mismatches":mismatches,"examples":examples})
	viewport.queue_free()
	var result: Dictionary={"cases":cases,"qa_sha256":get_script().source_code.sha256_text(),"actor_sha256":script.source_code.sha256_text(),
		"shader_sha256":FileAccess.get_sha256("res://source_art/r1/experiments/dash_cycle_26/dash_skin.gdshader"),
		"recipe_sha256":FileAccess.get_sha256("res://source_art/r1/experiments/dash_cycle_26/dash_recipe.json")}
	var f:=FileAccess.open("res://docs/r1_26_identity_checks.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
	return {"cases":cases}
