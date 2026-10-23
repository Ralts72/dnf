extends RefCounted
## Render the real actor material into an isolated native viewport for review.

var render_cases: Array=[]


func run(main: Node) -> Dictionary:
	var tree: SceneTree=main.get_tree()
	var p: Node=main.player
	var original: Dictionary=p.capture_state()
	var enabled: bool=p.pose_inbetweens.enabled
	main._set_paused(true)
	p.pose_inbetweens.set_enabled(true)
	var viewport:=SubViewport.new()
	viewport.name="PoseFlowGallery"
	viewport.size=Vector2i(640,448)
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.size=224.0/60.0
	var target:=Vector3(27.0/60.0,.025+55.0/(60.0*cos(p.ELEVATION)),0)
	camera.position=target+Vector3(0,sin(p.ELEVATION),cos(p.ELEVATION))*10.0
	viewport.add_child(camera)
	camera.look_at(target,Vector3.UP)
	camera.current=true
	var sprite:=Sprite3D.new()
	sprite.pixel_size=1.0/60.0
	sprite.scale.y=1.0/cos(p.ELEVATION)
	sprite.position=Vector3(0,.025,0)
	sprite.offset=Vector2(27,55)
	sprite.material_override=p.source_material
	sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(sprite)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/r1_21_gpu"))
	for action: String in ["move","dash"]:
		p.preview(action)
		p.facing=1
		for frame: int in 8:
			for subframe: int in 3:
				p.frame_index=frame
				p.elapsed_ms=float(subframe)*100.0/3.0+.001
				p._apply_frame();p._update_sprite_transform()
				sprite.texture=p.sprite.texture
				for _i: int in 3:await RenderingServer.frame_post_draw
				var image: Image=viewport.get_texture().get_image()
				var path: String="res://work/r1_21_gpu/%s_%02d_%d.png"%[action,frame,subframe]
				image.save_png(path)
				render_cases.append({"action":action,"frame":frame,"subframe":subframe,"phase":p.pose_inbetweens.phase,"capture":path})
	viewport.queue_free()
	await tree.process_frame
	p.pose_inbetweens.set_enabled(enabled)
	p.restore_state(original);main._set_paused(original.paused)
	var report: Dictionary={"candidate":"R1/21","render_cases":render_cases,"qa_source_sha256":get_script().source_code.sha256_text(),
		"note":"Real Godot source material, fixed native camera and transparent 2x target. No CPU image interpolation is used."}
	var out:=FileAccess.open("res://work/r1_21_gpu_gallery.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "));out.close()
	return {"render_cases":render_cases.size()}
