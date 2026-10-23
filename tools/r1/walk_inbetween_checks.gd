extends RefCounted
## Real input/UI, phase boundaries, source imports and raw R0 comparison.

var checks: Array=[]
var boundary_cases: Array=[]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func key(code: int) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events()
	event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=false
	Input.parse_input_event(event);Input.flush_buffered_events()


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree();var p: Node=root.player
	var original: Dictionary=p.capture_state()
	var enabled: bool=p.walk_inbetweens.enabled
	check_result("default_R1_enabled",enabled and p.walk_inbetweens.spatial and root.preview_controls.walk_toggle.button_pressed)
	check_result("16_runtime_textures_preloaded",p.walk_inbetweens.textures.size()==16)
	var exact: int=0;var pixels: int=0;var mips: int=0;var compressed: int=0
	for path: String in p.walk_inbetweens.textures:
		var expected:=Image.new();expected.load_png_from_buffer(FileAccess.get_file_as_bytes(path));expected.convert(Image.FORMAT_RGBA8)
		var actual: Image=p.walk_inbetweens.textures[path].get_image()
		if actual.has_mipmaps():mips+=1
		if actual.is_compressed():compressed+=1;actual.decompress()
		actual.convert(Image.FORMAT_RGBA8)
		if actual.get_data()==expected.get_data():exact+=1
		pixels+=expected.get_width()*expected.get_height()
	check_result("16_imported_RGBA_buffers_exact",exact==16 and pixels==1146880,{"textures":exact,"pixels":pixels})
	check_result("derived_imports_no_mipmaps_or_VRAM_compression",mips==0 and compressed==0,{"mips":mips,"compressed":compressed})
	root._set_paused(true);p.preview("move")
	for frame: int in 8:
		for row: Array in [[0.0,0],[33.32,0],[33.334,1],[66.65,1],[66.668,2],[99.999,2]]:
			p.frame_index=frame;p.elapsed_ms=row[0]
			var before: Dictionary=p.capture_state();p._apply_frame();p._update_sprite_transform()
			var expected_path: String=p.current_frame().texture if row[1]==0 else p.walk_inbetweens.data.frames[frame].intermediates[row[1]-1]
			boundary_cases.append({"frame":frame,"elapsed_ms":row[0],"expected_subframe":row[1],"actual_subframe":p.walk_inbetweens.subframe,
				"path":p.sprite.texture.resource_path,"pass":p.walk_inbetweens.subframe==row[1] and p.sprite.texture.resource_path==expected_path
				and p.source_material.get_shader_parameter("source_texture")==p.sprite.texture and p.capture_state()==before})
	check_result("all48_phase_boundaries_preserve_source_clock",boundary_cases.all(func(c):return c.pass),{"cases":boundary_cases.size()})
	p.frame_index=5;p.elapsed_ms=66.667;p._apply_frame()
	var state: Dictionary=p.capture_state()
	key(KEY_F5);await tree.process_frame
	check_result("actual_F5_restores_source_without_clock_change",not p.walk_inbetweens.enabled and not root.preview_controls.walk_toggle.button_pressed
		and p.sprite.texture==p._textures[p.current_frame().texture] and p.capture_state()==state)
	key(KEY_F5);await tree.process_frame
	check_result("actual_F5_reenables_same_intermediate",p.walk_inbetweens.enabled and root.preview_controls.walk_toggle.button_pressed
		and p.walk_inbetweens.subframe==2 and p.capture_state()==state)
	var click: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/r1_25_walk_click.json"))
	check_result("actual_pointer_checkbox_path",not click.before_enabled and click.after_enabled and click.actor_state_unchanged and click.checkbox
		and click.before_texture!=click.after_texture,click)
	key(KEY_F2);await tree.process_frame
	await tree.create_timer(.12).timeout
	key(KEY_F2);await tree.process_frame
	var paused: Dictionary=p.capture_state();await tree.create_timer(.1).timeout
	check_result("actual_F2_freezes_intermediate_and_clock",p.paused and p.capture_state()==paused)
	key(KEY_F3);await tree.process_frame
	check_result("actual_F3_steps_original_frame_and_phase_zero",p.paused and p.frame_index==(int(paused.frame)+1)%8 and p.walk_inbetweens.subframe==0 and is_zero_approx(p.elapsed_ms)
		and p.sprite.texture==p._textures[p.current_frame().texture])
	p.frame_index=4;p.elapsed_ms=40;p._apply_frame()
	var facing: int=p.facing;var texture: Texture2D=p.sprite.texture
	key(KEY_F7);await tree.process_frame
	check_result("actual_F7_keeps_phase_texture_and_time",p.facing==-facing and p.sprite.texture==texture and p.walk_inbetweens.subframe==1 and p.elapsed_ms==40)
	root.preview_controls._scrub(2)
	check_result("scrub_locates_raw_frame",p.paused and p.frame_index==2 and p.walk_inbetweens.subframe==0 and p.elapsed_ms==0)
	for action: String in ["stay","dash","attack1","hopsmash","jump"]:
		p.preview(action);p.elapsed_ms=40;p._apply_frame()
		check_result("no_substitution_"+action,not p.walk_inbetweens.active and p.sprite.texture==p._textures[p.current_frame().texture])
	p.preview("move");p.frame_index=6;p.elapsed_ms=66.667;p._apply_frame()
	state=p.capture_state();var expected_path: String=p.sprite.texture.resource_path
	root._switch_comparison();await tree.scene_changed;root=tree.current_scene;p=root.player
	check_result("F4_R0_preserves_pose_time_and_enabled_preference",p.capture_state()==state and p.walk_inbetweens.enabled and not p.walk_inbetweens.active)
	check_result("R0_stays_raw_and_loads_no_derived_textures",not p.walk_inbetweens.spatial and p.walk_inbetweens.textures.is_empty() and root.preview_controls.walk_toggle.disabled)
	key(KEY_F5);await tree.process_frame
	check_result("F5_in_raw_R0_does_not_change_R1_choice",p.walk_inbetweens.enabled and p.capture_state()==state)
	root._switch_comparison();await tree.scene_changed;root=tree.current_scene;p=root.player
	check_result("F4_R1_restores_exact_intermediate",p.capture_state()==state and p.walk_inbetweens.enabled and p.sprite.texture.resource_path==expected_path)
	root.preview_controls.toggle_walk_inbetweens()
	root._switch_comparison();await tree.scene_changed;root=tree.current_scene
	root._switch_comparison();await tree.scene_changed;root=tree.current_scene;p=root.player
	check_result("F4_retains_disabled_preference",not p.walk_inbetweens.enabled and not root.preview_controls.walk_toggle.button_pressed and p.sprite.texture==p._textures[p.current_frame().texture])
	root.preview_controls._select_walk_inbetweens(true)
	check_result("F12_distinguishes_source_and_lower_body_rates","原图 10.0 / 下肢 30.0" in tree.root.get_node("FrameDiagnostics").cadence())
	var help_rect: Rect2=root.get_node("Interface/Help").get_global_rect()
	var walk_rect: Rect2=root.preview_controls.walk_toggle.get_global_rect()
	var motion_rect: Rect2=root.preview_controls.motion_toggle.get_global_rect()
	check_result("footer_help_and_three_controls_fit",help_rect.end.x<walk_rect.position.x and help_rect.end.y<=540 and walk_rect.end.x<=motion_rect.position.x and walk_rect.end.y<=540,
		{"help":help_rect,"walk":walk_rect,"motion":motion_rect})
	p.restore_state(original);root._set_paused(original.paused);root.preview_controls._select_walk_inbetweens(enabled)
	if tree.has_meta("port_compare_state"):tree.remove_meta("port_compare_state")
	var failed: Array=checks.filter(func(c):return not c.pass)
	var report: Dictionary={"candidate":"R1/25","checks":checks,"failed":failed,"boundary_cases":boundary_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),"helper_sha256":p.walk_inbetweens.get_script().source_code.sha256_text(),
		"note":"Actual function-key events, separately verified native pointer click, exact imported RGBA bytes and F4 state paths. R0 stays raw."}
	var out:=FileAccess.open("res://docs/r1_25_walk_checks.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	return {"checks":checks.size(),"failed":failed,"boundary_cases":boundary_cases.size()}
