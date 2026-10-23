extends RefCounted
## Native controls, source clocks, both locomotion clips and raw R0 transfer.

var checks: Array=[]
var boundary_cases: Array=[]
var pointer_cases: Array=[]

func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})

func input_key(code: int,pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()

func key(code: int) -> void:
	input_key(code,true);input_key(code,false)

func click(control: Control,tree: SceneTree) -> void:
	var position: Vector2=tree.root.get_stretch_transform()*control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=position;motion.global_position=position
	Input.parse_input_event(motion);Input.flush_buffered_events()
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=position;event.global_position=position
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event);Input.flush_buffered_events();await tree.process_frame

func selected(p: Node) -> bool:
	var frame: Dictionary=p.current_frame()
	var path: String=frame.texture
	if p.walk_inbetweens.active and p.walk_inbetweens.subframe>0:
		path=p.walk_inbetweens.clips[p.animation_name].frames[p.frame_index].intermediates[p.walk_inbetweens.subframe-1]
	return p.sprite.texture.resource_path==path and p.source_material.get_shader_parameter("source_texture")==p.sprite.texture

func run(root: Node,candidate: String="R1/27") -> Dictionary:
	var tree: SceneTree=root.get_tree();var p: Node=root.player
	var original: Dictionary=p.capture_state();var enabled: bool=p.walk_inbetweens.enabled
	check_result("default_R1_enabled",enabled and p.walk_inbetweens.spatial and root.preview_controls.walk_toggle.button_pressed)
	var counts: Dictionary=p.walk_inbetweens.texture_counts()
	check_result("both_clips_preload16_each",counts.size()==2 and counts.move==16 and counts.dash==16 and p.walk_inbetweens.textures.size()==32,{"counts":counts})
	var exact: int=0;var pixels: int=0;var mips: int=0;var compressed: int=0
	for path: String in p.walk_inbetweens.textures:
		var expected:=Image.new();expected.load_png_from_buffer(FileAccess.get_file_as_bytes(path));expected.convert(Image.FORMAT_RGBA8)
		var actual: Image=p.walk_inbetweens.textures[path].get_image()
		if actual.has_mipmaps():mips+=1
		if actual.is_compressed():compressed+=1;actual.decompress()
		actual.convert(Image.FORMAT_RGBA8)
		if actual.get_data()==expected.get_data():exact+=1
		pixels+=expected.get_width()*expected.get_height()
	check_result("all32_imported_RGBA_buffers_exact",exact==32 and pixels==2293760,{"textures":exact,"pixels":pixels})
	check_result("derived_imports_no_mipmaps_or_VRAM_compression",mips==0 and compressed==0)
	for action: String in ["move","dash"]:
		root._set_paused(true);p.preview(action)
		var clip: Dictionary=p.walk_inbetweens.clips[action]
		for frame: int in 8:
			for row: Array in [[0.0,0],[33.32,0],[33.334,1],[66.65,1],[66.668,2],[99.999,2]]:
				p.frame_index=frame;p.elapsed_ms=row[0];var before: Dictionary=p.capture_state()
				p._apply_frame();p._update_sprite_transform()
				var path: String=p.current_frame().texture if row[1]==0 else clip.frames[frame].intermediates[row[1]-1]
				boundary_cases.append({"action":action,"frame":frame,"elapsed_ms":row[0],"expected_subframe":row[1],"actual_subframe":p.walk_inbetweens.subframe,
					"path":p.sprite.texture.resource_path,"pass":p.walk_inbetweens.subframe==row[1] and p.sprite.texture.resource_path==path and selected(p) and p.capture_state()==before})
		check_result(action+"_48_boundaries_preserve_clock",boundary_cases.filter(func(c):return c.action==action).all(func(c):return c.pass))
		p.frame_index=5;p.elapsed_ms=66.667;p._apply_frame();var state: Dictionary=p.capture_state()
		key(KEY_F5);await tree.process_frame
		check_result(action+"_F5_restores_raw_without_clock_change",not p.walk_inbetweens.enabled and not root.preview_controls.walk_toggle.button_pressed and selected(p) and p.capture_state()==state)
		key(KEY_F5);await tree.process_frame
		check_result(action+"_F5_restores_same_derived_phase",p.walk_inbetweens.enabled and p.walk_inbetweens.subframe==2 and selected(p) and p.capture_state()==state)
		var derived: String=p.sprite.texture.resource_path
		await click(root.preview_controls.walk_toggle,tree)
		var off: bool=not p.walk_inbetweens.enabled and not root.preview_controls.walk_toggle.button_pressed and p.sprite.texture==p._textures[p.current_frame().texture] and p.capture_state()==state
		await click(root.preview_controls.walk_toggle,tree)
		var on: bool=p.walk_inbetweens.enabled and root.preview_controls.walk_toggle.button_pressed and p.sprite.texture.resource_path==derived and p.capture_state()==state
		pointer_cases.append({"action":action,"off":off,"on":on,"logical_center":root.preview_controls.walk_toggle.get_global_rect().get_center()})
		check_result(action+"_native_pointer_toggles_both_directions",off and on)
		key(KEY_F2);await tree.process_frame;await tree.create_timer(.12).timeout;key(KEY_F2);await tree.process_frame
		var paused: Dictionary=p.capture_state();await tree.create_timer(.1).timeout
		check_result(action+"_F2_freezes_phase_and_clock",p.paused and p.capture_state()==paused)
		key(KEY_F3);await tree.process_frame
		check_result(action+"_F3_steps_source_frame",p.paused and p.frame_index==(int(paused.frame)+1)%8 and p.walk_inbetweens.subframe==0 and is_zero_approx(p.elapsed_ms) and selected(p))
		p.frame_index=4;p.elapsed_ms=40;p._apply_frame();var facing: int=p.facing;var texture: Texture2D=p.sprite.texture
		key(KEY_F7);await tree.process_frame
		check_result(action+"_F7_retains_phase_and_texture",p.facing==-facing and p.sprite.texture==texture and p.walk_inbetweens.subframe==1 and p.elapsed_ms==40)
		root.preview_controls._scrub(2)
		check_result(action+"_scrub_selects_original_frame",p.paused and p.frame_index==2 and p.elapsed_ms==0 and p.walk_inbetweens.subframe==0 and selected(p))
		p.frame_index=6;p.elapsed_ms=66.667;p._apply_frame();state=p.capture_state();derived=p.sprite.texture.resource_path
		root._switch_comparison();await tree.scene_changed;root=tree.current_scene;p=root.player
		check_result(action+"_F4_R0_preserves_clock_and_choice",p.capture_state()==state and p.walk_inbetweens.enabled and not p.walk_inbetweens.active)
		check_result(action+"_R0_remains_raw_without_derived_loads",p.walk_inbetweens.textures.is_empty() and p.walk_inbetweens.clips.is_empty() and root.preview_controls.walk_toggle.disabled)
		key(KEY_F5);await tree.process_frame
		check_result(action+"_R0_F5_does_not_change_R1_choice",p.walk_inbetweens.enabled and p.capture_state()==state)
		check_result(action+"_R0_cadence_stays_raw","原图平均 10.0" in tree.root.get_node("FrameDiagnostics").cadence())
		root._switch_comparison();await tree.scene_changed;root=tree.current_scene;p=root.player
		check_result(action+"_F4_restores_exact_derived_image",p.capture_state()==state and p.sprite.texture.resource_path==derived and selected(p))
		root.preview_controls.toggle_walk_inbetweens()
		root._switch_comparison();await tree.scene_changed;root=tree.current_scene
		root._switch_comparison();await tree.scene_changed;root=tree.current_scene;p=root.player
		check_result(action+"_disabled_choice_survives_F4",not p.walk_inbetweens.enabled and not root.preview_controls.walk_toggle.button_pressed and selected(p))
		root.preview_controls._select_walk_inbetweens(true)
		check_result(action+"_F12_distinguishes10_and30Hz","原图 10.0 / 下肢 30.0" in tree.root.get_node("FrameDiagnostics").cadence())
	for action: String in ["stay","attack1","hopsmash","jump","jumpattack"]:
		p.preview(action);p.elapsed_ms=40;p._apply_frame()
		check_result("raw_"+action,not p.walk_inbetweens.active and selected(p))
	p.reset_position();p.free_control();root._set_paused(false)
	input_key(KEY_D,true);await tree.create_timer(.15).timeout
	check_result("actual_walk_uses_move_samples",p.animation_name=="move" and p.walk_inbetweens.active and selected(p))
	input_key(KEY_SHIFT,true);await tree.create_timer(.15).timeout
	check_result("actual_shift_switches_to_dash_samples",p.animation_name=="dash" and p.walk_inbetweens.active and selected(p))
	key(KEY_SPACE);await tree.create_timer(.2).timeout
	check_result("actual_run_jump_disables_samples",p.jump_motion.is_active() and p.jump_motion.height_pixels>0 and not p.walk_inbetweens.active and selected(p))
	var launch_speed: float=float(p.jump_motion.config.air_move_speed_px_s)*float(p.jump_motion.config.run_jump_multiplier)
	check_result("run_jump_keeps_source_air_launch_speed",is_equal_approx(p.jump_motion.travel_speed,launch_speed),{"expected":launch_speed,"actual":p.jump_motion.travel_speed})
	root._set_paused(true);var airborne: Dictionary=p.capture_state()
	key(KEY_F5);await tree.process_frame;key(KEY_F5);await tree.process_frame
	check_result("airborne_F5_preserves_jump_clock",p.capture_state()==airborne and p.walk_inbetweens.enabled and not p.walk_inbetweens.active and selected(p))
	root._set_paused(false);input_key(KEY_SHIFT,false);await tree.create_timer(1.2).timeout
	check_result("landing_returns_to_walking_samples",not p.jump_motion.is_active() and p.animation_name=="move" and p.walk_inbetweens.active and selected(p))
	input_key(KEY_SHIFT,true);await tree.create_timer(.1).timeout;key(KEY_X);await tree.create_timer(.1).timeout
	check_result("dash_to_attack_uses_raw_source",p.animation_name=="attack1" and not p.walk_inbetweens.active and selected(p))
	await tree.create_timer(.65).timeout
	check_result("attack_completion_returns_to_dash_samples",p.animation_name=="dash" and p.walk_inbetweens.active and selected(p))
	input_key(KEY_D,false);input_key(KEY_SHIFT,false);await tree.create_timer(.05).timeout
	check_result("release_returns_to_raw_idle",p.animation_name=="stay" and not p.walk_inbetweens.active and selected(p))
	var help_rect: Rect2=root.get_node("Interface/Help").get_global_rect();var toggle: Rect2=root.preview_controls.walk_toggle.get_global_rect()
	check_result("footer_controls_fit",help_rect.end.x<toggle.position.x and help_rect.end.y<=540 and toggle.end.x<=root.preview_controls.motion_toggle.get_global_rect().position.x and toggle.end.y<=540)
	p.restore_state(original);root._set_paused(original.paused);root.preview_controls._select_walk_inbetweens(enabled)
	if tree.has_meta("port_compare_state"):tree.remove_meta("port_compare_state")
	var failed: Array=checks.filter(func(c):return not c.pass)
	var report: Dictionary={"candidate":candidate,"checks":checks,"failed":failed,"boundary_cases":boundary_cases,"pointer_cases":pointer_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),"helper_sha256":p.walk_inbetweens.get_script().source_code.sha256_text(),
		"note":"Native key/mouse events, both clips and actual walk/run/jump/attack transitions. No QA texture substitution; source clocks and raw R0 retained."}
	var f:=FileAccess.open("res://docs/"+candidate.to_lower().replace("/","_")+"_locomotion_checks.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	return {"checks":checks.size(),"failed":failed,"boundary_cases":boundary_cases.size()}
