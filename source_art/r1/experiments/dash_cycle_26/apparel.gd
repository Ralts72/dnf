extends RefCounted
## Isolated apparel alpha permits connected-component checks without the blade.

func run(main: Node) -> Dictionary:
	var script:=GDScript.new();script.source_code=FileAccess.get_file_as_string("res://source_art/r1/experiments/dash_cycle_26/actor.gd");assert(script.reload()==OK)
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,224);viewport.transparent_bg=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	main.get_tree().root.add_child(viewport);var actor: Node2D=script.new();viewport.add_child(actor);actor.apparel_only=true
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r0.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://source_art/r1/experiments/dash_cycle_26/apparel"))
	var cases: Array=[]
	for frame: int in 8:
		var expected:=Image.create(320,224,false,Image.FORMAT_RGBA8)
		for slot: int in [2,3,4,5]:
			var layer: Dictionary=raw.animations.dash.frames[frame].layers[slot]
			var image:=Image.new();image.load_png_from_buffer(FileAccess.get_file_as_bytes(layer.texture));image.convert(Image.FORMAT_RGBA8)
			expected.blend_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i(layer.offset[0]+133,layer.offset[1]+167))
		for sub: int in 3:
			actor.update_pose(frame,sub)
			for _i: int in 3:await RenderingServer.frame_post_draw
			var actual: Image=viewport.get_texture().get_image();actual.convert(Image.FORMAT_RGBA8)
			var path: String="res://source_art/r1/experiments/dash_cycle_26/apparel/dash_%02d_%d.png"%[frame,sub];actual.save_png(path)
			cases.append({"frame":frame,"subframe":sub,"endpoint_exact":actual.get_data()==expected.get_data() if sub==0 else null,"path":path,"sha256":FileAccess.get_sha256(path)})
	viewport.queue_free()
	var result: Dictionary={"cases":cases,"actor_sha256":script.source_code.sha256_text(),"qa_sha256":get_script().source_code.sha256_text(),
		"all_endpoints_exact":cases.filter(func(c):return c.subframe==0).all(func(c):return c.endpoint_exact)}
	var out:=FileAccess.open("res://docs/r1_26_apparel_bake.json",FileAccess.WRITE);out.store_string(JSON.stringify(result,"  "));out.close()
	return {"cases":cases.size(),"all_endpoints_exact":result.all_endpoints_exact}
