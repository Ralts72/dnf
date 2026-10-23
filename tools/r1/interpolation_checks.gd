extends RefCounted
## Actual rendered marker positions at low TPS expose interpolation directly.
## The marker uses the character's visual hierarchy; no synthetic lerp is used.

var checks: Array=[]
var render_cases: Array=[]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func point(root: Node) -> Vector2:
	return root.player.world_to_source(root.player.position) if root.name=="WestCoastR1" else root.player.position


func marker_for(root: Node,kind: String) -> Node:
	if kind=="R1":
		var marker:=MeshInstance3D.new()
		var mesh:=QuadMesh.new();mesh.size=Vector2(.1,.1)
		marker.mesh=mesh
		var material:=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=Color(1,0,1)
		marker.material_override=material
		marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.rotation.x=-root.player.ELEVATION
		marker.position=Vector3(0,140.0/60.0,0)
		root.player.sprite.add_child(marker)
		return marker
	var marker:=ColorRect.new()
	marker.color=Color(1,0,1)
	marker.position=Vector2(-3,-143);marker.size=Vector2(6,6)
	marker.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.player.facing_root.add_child(marker)
	return marker


func centroid(root: Node,kind: String,marker: Node) -> Dictionary:
	var viewport: Viewport=root.render_viewport if kind=="R1" else root.get_viewport()
	var image: Image=viewport.get_texture().get_image()
	var center: Vector2
	if kind=="R1":center=root.world.get_node("Camera").unproject_position(marker.global_position)
	else:center=root.get_viewport().get_stretch_transform()*(point(root)+Vector2(32-root.framing.offset_x,105-root.framing.offset_y-140))
	var total:=Vector2.ZERO
	var weight: float=0.0
	var pixels: int=0
	# At 10 TPS and 100 px/s the interpolated image may trail logic by 10 px.
	for y: int in range(maxi(0,int(center.y)-18),mini(image.get_height(),int(center.y)+18)):
		for x: int in range(maxi(0,int(center.x)-35),mini(image.get_width(),int(center.x)+18)):
			var c: Color=image.get_pixel(x,y)
			if c.r>.8 and c.b>.8 and c.g<.15:
				var w: float=minf(c.r,c.b)-c.g
				total+=Vector2(x+.5,y+.5)*w;weight+=w;pixels+=1
	return {"x":total.x/weight if weight>0 else -10000.0,"y":total.y/weight if weight>0 else -10000.0,"pixels":pixels}


func moving_pixels(root: Node,kind: String,enabled: bool) -> Dictionary:
	var p: Node=root.player
	var label: String=kind+"_"+str(Engine.physics_ticks_per_second)+"tps"
	p.reset_position();root._set_paused(false)
	root.preview_controls._select_motion_smoothing(enabled)
	if kind=="R1":root.set_render_scale(2)
	var marker: Node=marker_for(root,kind)
	p.motion_smoothing.reset()
	for _i: int in 3:await root.get_tree().physics_frame
	key(KEY_D,true)
	var rows: Array=[]
	for i: int in (84 if Engine.physics_ticks_per_second==60 else 42):
		await RenderingServer.frame_post_draw
		var center: Dictionary=centroid(root,kind,marker)
		rows.append({"physics_frame":Engine.get_physics_frames(),"logical_x":point(root).x,
			"fraction":Engine.get_physics_interpolation_fraction(),"render_x":center.x,"pixels":center.pixels})
	key(KEY_D,false)
	for _i: int in 3:await root.get_tree().physics_frame
	var between_tick_pairs: int=0
	var moved_between: int=0
	var max_between: float=0.0
	for i: int in range(1,rows.size()):
		if rows[i].physics_frame==rows[i-1].physics_frame and is_equal_approx(rows[i].logical_x,rows[i-1].logical_x):
			between_tick_pairs+=1
			var distance: float=absf(rows[i].render_x-rows[i-1].render_x)
			max_between=maxf(max_between,distance)
			if distance>.1:moved_between+=1
	var settled: Dictionary=centroid(root,kind,marker)
	var destination: Vector2=point(root)
	key(KEY_R,true);key(KEY_R,false)
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var reset: Dictionary=centroid(root,kind,marker)
	var expected_x: float
	if kind=="R1":expected_x=root.world.get_node("Camera").unproject_position(marker.global_position).x
	else:expected_x=(root.get_viewport().get_stretch_transform()*(point(root)+Vector2(32-root.framing.offset_x,105-root.framing.offset_y-140))).x
	check_result(label+"_reset_snaps_native_render_"+str(enabled),absf(reset.x-expected_x)<.8 and point(root).distance_to(Vector2(440,320))<.01,
		{"actual_marker_x":reset.x,"target_x":expected_x,"pre_reset_logical":destination})
	var record: Dictionary={"scene":kind,"enabled":enabled,"temporary_physics_ticks":Engine.physics_ticks_per_second,
		"rows":rows,"between_tick_pairs":between_tick_pairs,"render_moved_between_tick_pairs":moved_between,
		"maximum_between_tick_pixels":max_between,"settled_marker":settled}
	render_cases.append(record)
	check_result(label+"_actual_marker_found_"+str(enabled),rows.all(func(r: Dictionary):return r.pixels>=20))
	check_result(label+"_native_render_"+("interpolates_between_ticks" if enabled else "holds_between_ticks"),
		between_tick_pairs>15 and (moved_between>15 if enabled else moved_between==0),
		{"between_tick_pairs":between_tick_pairs,"render_moved_between_tick_pairs":moved_between,"maximum_between_tick_pixels":max_between})
	marker.queue_free()
	await root.get_tree().process_frame
	return record


func controls(root: Node,kind: String) -> void:
	var p: Node=root.player
	p.reset_position();root._set_paused(false)
	root.preview_controls._select_motion_smoothing(true)
	check_result(kind+"_native_interpolation_enabled",p.is_physics_interpolated_and_enabled() and root.physics_interpolation_mode==Node.PHYSICS_INTERPOLATION_MODE_OFF)
	key(KEY_F11,true);key(KEY_F11,false)
	await root.get_tree().process_frame
	check_result(kind+"_F11_disables_interpolation",not p.motion_smoothing.enabled and not p.is_physics_interpolated_and_enabled() and not root.preview_controls.motion_toggle.button_pressed)
	key(KEY_F11,true);key(KEY_F11,false)
	await root.get_tree().process_frame
	check_result(kind+"_F11_restores_interpolation",p.motion_smoothing.enabled and p.is_physics_interpolated_and_enabled() and root.preview_controls.motion_toggle.button_pressed)
	p.start_jump();p._tick_jump(.35,false)
	root._set_paused(true)
	check_result(kind+"_pause_snaps_and_stops_interpolation",not p.is_physics_interpolated_and_enabled() and p.paused and absf(p.jump_motion.height_pixels-80.625)<.001)
	var height: float=p.jump_motion.height_pixels
	p.step_frame()
	check_result(kind+"_paused_step_changes_height_without_render_delay",p.jump_motion.height_pixels>height and not p.is_physics_interpolated_and_enabled())
	var local_transform: Transform3D=p.sprite.transform if kind=="R1" else Transform3D.IDENTITY
	root.preview_controls.turn_around()
	if kind=="R1":check_result("R1_turn_changes_geometry_without_interpolating_transform",p.sprite.transform==local_transform and p.sprite.flip_h and p.sprite.offset.x<0)
	else:check_result("R0_turn_is_instant_in_facing_child",p.facing_root.scale.x==-1 and p.visual.scale==Vector2.ONE
		and not p.facing_root.is_physics_interpolated_and_enabled())
	root._set_paused(false)
	check_result(kind+"_resume_restores_native_interpolation",p.is_physics_interpolated_and_enabled())
	p.reset_position()
	var toggle: Control=root.get_node("Interface/MotionToggle")
	var effect_toggle: Control=root.get_node("Interface/EffectsToggle")
	check_result(kind+"_motion_toggle_fits_footer",toggle.get_global_rect().end.x<=effect_toggle.get_global_rect().position.x
		and toggle.get_global_rect().end.y<=540 and root.get_node("Interface/Help").get_global_rect().end.x<toggle.get_global_rect().position.x)


func run(root: Node,candidate: String="R1/20") -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var original: Dictionary=root.player.capture_state()
	var original_scale: int=root.render_scale
	var original_ticks: int=Engine.physics_ticks_per_second
	var original_enabled: bool=root.player.motion_smoothing.enabled
	await controls(root,"R1")
	Engine.physics_ticks_per_second=10
	await moving_pixels(root,"R1",false)
	await moving_pixels(root,"R1",true)
	Engine.physics_ticks_per_second=original_ticks
	await moving_pixels(root,"R1",false)
	await moving_pixels(root,"R1",true)
	root.player.start_jump();root.player._tick_jump(.35,false);root._set_paused(true)
	var expected: Dictionary=root.player.capture_state()
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	check_result("F4_retains_paused_jump_and_smoothing_preference",root.player.capture_state()==expected and root.player.motion_smoothing.enabled
		and not root.player.is_physics_interpolated_and_enabled())
	await controls(root,"R0")
	Engine.physics_ticks_per_second=10
	await moving_pixels(root,"R0",false)
	await moving_pixels(root,"R0",true)
	Engine.physics_ticks_per_second=original_ticks
	await moving_pixels(root,"R0",false)
	await moving_pixels(root,"R0",true)
	root._set_paused(true)
	root.preview_controls._select_motion_smoothing(false)
	expected=root.player.capture_state()
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	check_result("F4_back_retains_disabled_smoothing",root.player.capture_state()==expected and not root.player.motion_smoothing.enabled
		and not root.preview_controls.motion_toggle.button_pressed)
	root.preview_controls._select_motion_smoothing(original_enabled)
	root.player.restore_state(original);root.set_render_scale(original_scale);root._set_paused(original.paused)
	if tree.has_meta("port_compare_state"):tree.remove_meta("port_compare_state")
	check_result("production_tick_rate_restored",Engine.physics_ticks_per_second==60)
	var failed: Array=checks.filter(func(c: Dictionary):return not c.pass)
	var report: Dictionary={"candidate":candidate,"checks":checks,"failed":failed,"render_cases":render_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"note":"Actual GPU readback of markers inside the character visual hierarchy. Both production 60 TPS and temporary 10 TPS are tested. Production 60 TPS is restored. OFF and ON use identical InputEventKey movement and unchanged source animation timing."}
	var out:=FileAccess.open("res://docs/"+candidate.to_lower().replace("/","_")+"_interpolation_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "));out.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases.size()}
