extends RefCounted
## Actual render-target, sampling, scene-instance and full-1080 checks.

var checks: Array=[]
var raw_samples: Dictionary={}


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func color_distance(a: Color,b: Color) -> float:
	return Vector3(a.r,a.g,a.b).distance_to(Vector3(b.r,b.g,b.b))


func opaque_interior(image: Image,point: Vector2i) -> bool:
	for d in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if image.get_pixelv(point+d).a<.98:
			return false
	return true


func observe(tree: SceneTree,label: String,frames: int,warmup: int=45) -> Dictionary:
	for _i in range(warmup):
		await tree.process_frame
	var samples: Array[float]=[]
	var previous:=Time.get_ticks_usec()
	for _i in range(frames):
		await tree.process_frame
		var now:=Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous=now
	raw_samples[label]=samples
	var sorted:=samples.duplicate()
	sorted.sort()
	var total:=0.0
	var over_budget:=0
	for ms in samples:
		total+=ms
		if ms>1000.0/60.0:
			over_budget+=1
	var middle:=frames>>1
	var median: float=(sorted[middle-1]+sorted[middle])*.5 if frames%2==0 else sorted[middle]
	return {"frames":frames,"mean_ms":total/frames,"median_ms":median,
		"p95_ms":sorted[int(ceil((frames-1)*.95))],"max_ms":sorted[-1],
		"fps_from_mean":1000.0/(total/frames),"frames_over_16_67_ms":over_budget}


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var original_scale: int=root.render_scale
	var original_state: Dictionary=root.player.capture_state()
	root._set_paused(true)
	root.player.preview("attack2")
	root.player.frame_index=3
	root.player.elapsed_ms=0.0
	root.player._apply_frame()
	var pose: Dictionary=root.player.capture_state()
	var camera: Camera3D=root.world.get_node("Camera")
	var camera_size: float=camera.size
	var images: Dictionary={}
	var observations: Dictionary={}
	for scale in [1,2]:
		root.set_render_scale(scale)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image=root.render_viewport.get_texture().get_image()
		images[scale]=image
		image.save_png("res://docs/previews/r1_03_scale_%d.png"%scale)
		var expected: Vector2i=Vector2i(896,404)*int(scale)
		check_result("native_render_dimensions_%dx"%scale,root.render_viewport.size==expected
			and image.get_size()==expected and is_equal_approx(root.render_viewport.scaling_3d_scale,1.0),
			{"viewport":root.render_viewport.size,"image":image.get_size(),"internal_3d_scale":root.render_viewport.scaling_3d_scale})
		var projected: Vector2=camera.unproject_position(root.player.position)/float(scale)
		check_result("composition_and_pose_preserved_%dx"%scale,
			projected.distance_to(pose["position"]+Vector2(-root.framing.offset_x,43-root.framing.offset_y))<.02
			and is_equal_approx(camera.size,camera_size)
			and root.player.frame_index==pose["frame"] and root.player.paused,
			{"foot_logical":projected,"frame":root.player.frame_index,"camera_size":camera.size})
		check_result("surface_bound_to_own_viewport_%dx"%scale,
			root.render_surface.texture==root.render_viewport.get_texture()
			and root.render_surface.size==Vector2(896,404))
		observations["main_%dx"%scale]=await observe(tree,"main_%dx"%scale,120)

	# Compare opaque source-art interiors at corresponding low/high render pixels.
	# This catches accidental linear filtering or changing the actor's scale.
	var source: Image=root.player.sprite.texture.get_image()
	if source.is_compressed():
		source.decompress()
	var foot: Vector2=camera.unproject_position(root.player.position)/2.0
	var compared:=0
	var matching:=0
	var max_delta:=0.0
	for y in range(1,source.get_height()-1):
		for x in range(1,source.get_width()-1):
			if not opaque_interior(source,Vector2i(x,y)):
				continue
			var logical: Vector2=foot+Vector2(x,y)-root.player._foot_anchor+Vector2(.5,.5)
			var a:=Vector2i(floori(logical.x),floori(logical.y))
			var b:=Vector2i(floori(logical.x*2),floori(logical.y*2))
			var delta:=color_distance(images[1].get_pixelv(a),images[2].get_pixelv(b))
			compared+=1
			max_delta=maxf(max_delta,delta)
			if delta<.015:
				matching+=1
	check_result("opaque_character_pixels_keep_color",compared>500 and matching>compared*.99,
		{"compared_pixels":compared,"matching_pixels":matching,"max_rgb_distance":max_delta})

	# A/B scene switching must retain the selected quality as well as the pose.
	root.set_render_scale(1)
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	check_result("quality_survives_r0_round_trip",root.render_scale==1
		and root.player.frame_index==pose["frame"] and root.player.paused)
	root.set_render_scale(2)
	await RenderingServer.frame_post_draw

	# Render the complete UI + far art + 3D scene into a real 1920x1080 target.
	# Disable only the existing main 3D pass while timing the offscreen target.
	var main_view: SubViewport=root.render_viewport
	var saved_update: int=main_view.render_target_update_mode
	main_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var full:=SubViewport.new()
	full.name="R1Full1080Validation"
	full.size=Vector2i(1920,1080)
	full.size_2d_override=Vector2i(960,540)
	full.size_2d_override_stretch=true
	full.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(full)
	var clone: Node=load("res://scenes/west_coast_r1.tscn").instantiate()
	full.add_child(clone)
	clone.set_render_scale(2)
	check_result("offscreen_scene_has_own_bindings",clone.render_surface.texture==clone.render_viewport.get_texture()
		and clone.player.source_material!=root.player.source_material)
	var original_sampler: Texture2D=root.player.source_material.get_shader_parameter("source_texture")
	clone.player.preview("attack1")
	clone.player.step_frame()
	check_result("offscreen_animation_does_not_change_main_sampler",
		root.player.source_material.get_shader_parameter("source_texture")==original_sampler
		and clone.player.source_material.get_shader_parameter("source_texture")!=original_sampler)
	clone._set_paused(false)
	observations["full_1080"]=await observe(tree,"full_1080",180,60)
	clone.player.reset_position()
	clone._set_paused(false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var final_image:=full.get_texture().get_image()
	var child_image: Image=clone.render_viewport.get_texture().get_image()
	final_image.save_png("res://docs/previews/r1_03_full1080.png")
	final_image.save_png("res://docs/previews/r1_port.png")
	check_result("full_1080_is_native_engine_output",final_image.get_size()==Vector2i(1920,1080)
		and child_image.get_size()==Vector2i(1792,808),
		{"full_frame":final_image.get_size(),"scene_render":child_image.get_size(),"logical_canvas":full.size_2d_override})
	var consistent:=0
	var sampled:=0
	# Interior scene samples verify that the high-resolution child, not a cached
	# main-view texture, was composited at the expected full-frame offset.
	for yy in range(100,780,100):
		for xx in range(100,1700,150):
			var child_color:=child_image.get_pixel(xx,yy)
			if child_color.a<.99:
				continue
			sampled+=1
			if color_distance(child_color,final_image.get_pixel(xx+64,yy+124))<.02:
				consistent+=1
	check_result("full_frame_contains_own_high_resolution_scene",sampled>15 and consistent>sampled*.95,
		{"samples":sampled,"matching":consistent})
	var child_draws: int=clone.render_viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	check_result("full_scene_render_pass_is_active",child_draws>100,
		{"visible_3d_draw_calls":child_draws,"main_3d_disabled_during_measurement":main_view.render_target_update_mode==SubViewport.UPDATE_DISABLED})
	var target_observation: Dictionary=observations["full_1080"]
	check_result("short_1080_observation_meets_60fps_budget",target_observation["p95_ms"]<=1000.0/60.0,
		{"p95_ms":target_observation["p95_ms"],"fps_from_mean":target_observation["fps_from_mean"]})

	main_view.render_target_update_mode=saved_update as SubViewport.UpdateMode
	full.queue_free()
	await tree.process_frame
	root.set_render_scale(original_scale)
	root.player.restore_state(original_state)
	root._set_paused(original_state["paused"])
	if tree.has_meta("port_compare_state"):
		tree.remove_meta("port_compare_state")
	var failed:=0
	for item: Dictionary in checks:
		if not item["pass"]:
			failed+=1
	var report: Dictionary={"candidate":"R1/03","platform":"macOS","checks":checks,"failed":failed,
		"observations":observations,"qa_source_sha256":get_script().source_code.sha256_text(),
		"notes":["Full 1920x1080 engine render; the active window retains a static UI while its 3D pass is disabled during the offscreen measurement.",
			"Warmups excluded. Samples are process-frame intervals in the current Mac session, not a long-term or Windows benchmark.",
			"The offscreen actor animates during the timed sample. No image enlargement is used to create the full frame."]}
	var out:=FileAccess.open("res://docs/r1_03_quality_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out=FileAccess.open("res://docs/r1_03_frame_samples.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(raw_samples,"  "))
	return report
