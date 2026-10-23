extends RefCounted
## Native RGBA bake. The original PNGs remain the source endpoint assets.

func run(main: Node) -> Dictionary:
	var script:=GDScript.new();script.source_code=FileAccess.get_file_as_string("res://source_art/r1/experiments/walk_cycle_24/actor.gd")
	assert(script.reload()==OK)
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,224);viewport.transparent_bg=true
	viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	main.get_tree().root.add_child(viewport)
	var actor: Node2D=script.new();viewport.add_child(actor)
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://source_art/r1/experiments/walk_cycle_24/baked"))
	var records: Array=[]
	for frame: int in 8:
		for sub: int in 3:
			actor.update_pose(frame,sub)
			for _i: int in 3:await RenderingServer.frame_post_draw
			var image: Image=viewport.get_texture().get_image();image.convert(Image.FORMAT_RGBA8)
			var path: String="res://source_art/r1/experiments/walk_cycle_24/baked/move_%02d_%d.png"%[frame,sub]
			assert(image.save_png(path)==OK)
			var reloaded:=Image.new();assert(reloaded.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK)
			reloaded.convert(Image.FORMAT_RGBA8)
			var expected:=Image.new()
			var exact: bool=true
			if sub==0:
				expected.load_png_from_buffer(FileAccess.get_file_as_bytes(source.animations.move.frames[frame].texture));expected.convert(Image.FORMAT_RGBA8)
				exact=image.get_data()==expected.get_data()
			records.append({"frame":frame,"subframe":sub,"path":path,"png_sha256":FileAccess.get_sha256(path),
				"size":image.get_size(),"png_roundtrip_exact":reloaded.get_data()==image.get_data(),"original_endpoint_rgba_exact":exact if sub==0 else null})
	viewport.queue_free()
	var result: Dictionary={"study":"R1/24 native transparent bake","records":records,"endpoint_full_rgba_exact":records.filter(func(r):return r.subframe==0).all(func(r):return r.original_endpoint_rgba_exact),
		"all_png_roundtrips_exact":records.all(func(r):return r.png_roundtrip_exact),"qa_source_sha256":get_script().source_code.sha256_text()}
	var output:=FileAccess.open("res://docs/r1_24_bake_checks.json",FileAccess.WRITE);output.store_string(JSON.stringify(result,"  "));output.close()
	return {"frames":records.size(),"endpoint_full_rgba_exact":result.endpoint_full_rgba_exact,"png_roundtrips_exact":result.all_png_roundtrips_exact}
