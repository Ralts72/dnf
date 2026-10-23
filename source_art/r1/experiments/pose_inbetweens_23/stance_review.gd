extends RefCounted
## An authored single-transition shear of existing source layers; no new art.

func run(main: Node) -> Dictionary:
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r0.json"))
	var frames: Array=raw["animations"]["move"]["frames"]
	# Numeric visibility only: hide base-body pixels covered by original clothes.
	# This prevents raw bare legs leaking through when pants move away.
	var mask:=Image.create(320,224,false,Image.FORMAT_R8);mask.fill(Color.WHITE)
	for slot: int in [2,3,4,5]:
		var layer: Dictionary=frames[1]["layers"][slot]
		var image:=Image.new();image.load_png_from_buffer(FileAccess.get_file_as_bytes(layer["texture"]))
		for y: int in image.get_height():
			for x: int in image.get_width():
				var point:=Vector2i(x+layer["offset"][0]+133,y+layer["offset"][1]+167)
				if Rect2i(0,0,320,224).has_point(point) and image.get_pixel(x,y).a>=.25:mask.set_pixelv(point,Color.BLACK)
	var body_mask:=ImageTexture.create_from_image(mask)
	var shader:=Shader.new()
	shader.code=FileAccess.get_file_as_string("res://source_art/r1/experiments/pose_inbetweens_23/stance_shear.gdshader")
	var viewport:=SubViewport.new();viewport.size=Vector2i(2560,488)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	main.get_tree().root.add_child(viewport)
	var bg:=ColorRect.new();bg.size=Vector2(2560,488);bg.color=Color(.2,.25,.28);viewport.add_child(bg)
	for cell: int in 4:
		var canvas:=Node2D.new();canvas.position=Vector2(cell*640,32);canvas.scale=Vector2(2,2);viewport.add_child(canvas)
		var phase: float=float(cell)/3.0
		var endpoint: int=2 if cell==3 else 1
		var label:=Label.new();label.position=Vector2(cell*640+8,4);label.text=["A source 01","authored 1/3","authored 2/3","B source 02"][cell];label.add_theme_font_size_override("font_size",20);viewport.add_child(label)
		for i: int in 9:
			var is_leg: bool=i in [2,3,4,5]
			var derived: bool=cell in [1,2]
			var chosen: Dictionary=frames[2 if derived and is_leg else endpoint]["layers"][i]
			var texture: Texture2D=load(chosen["texture"])
			var rect:=TextureRect.new();rect.texture=texture;rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.stretch_mode=TextureRect.STRETCH_SCALE;rect.size=Vector2(320,224)
			var material:=ShaderMaterial.new();material.shader=shader
			material.set_shader_parameter("source_texture",texture)
			material.set_shader_parameter("source_offset",Vector2(chosen["offset"][0]+133,chosen["offset"][1]+167))
			material.set_shader_parameter("source_size",texture.get_size())
			material.set_shader_parameter("body_visibility",body_mask)
			var kind: int=1 if derived and i in [2,4] else (2 if derived and i in [3,5] else (3 if derived and i==1 else 0))
			material.set_shader_parameter("kind",kind)
			if derived and is_leg:
				var shift: Vector2=Vector2(13.3,4.5) if i in [2,3] else Vector2(-13.7,-3.6)
				material.set_shader_parameter("foot_shift",shift*(1-phase))
			rect.material=material;canvas.add_child(rect)
	for _i: int in 4:await RenderingServer.frame_post_draw
	var result: Image=viewport.get_texture().get_image()
	result.save_png("res://work/r1_23_stance_review.png")
	for cell: int in 4:result.get_region(Rect2i(cell*640,0,640,488)).save_png("res://work/r1_23_stance_%d.png"%cell)
	viewport.queue_free()
	return {"cells":4,"capture":"res://work/r1_23_stance_review.png","note":"Single transition only. Derived hips, shear, body mask and foot offsets are authored adaptations, not recovered original poses."}
