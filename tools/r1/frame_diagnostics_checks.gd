extends RefCounted
## Native shortcut, bounded trace, persistence and non-interference checks.

var checks: Array=[]
var exports: Array=[]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func key(code: int,pressed: bool,ctrl: bool=false) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed;event.ctrl_pressed=ctrl
	Input.parse_input_event(event);Input.flush_buffered_events()


func exported(diag: Node) -> Dictionary:
	var path: String=diag.last_export
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	exports.append({"path":path,"sha256":FileAccess.get_sha256(path),"rows":report.retained_rows})
	return report


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var diag: Node=tree.root.get_node("FrameDiagnostics")
	var original: Dictionary=root.player.capture_state()
	var bootstrap: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/r1_25_diagnostics_bootstrap.json"))
	check_result("default_hidden_and_no_sampling",not bootstrap.default.active and not bootstrap.default.processing and not bootstrap.default.visible and bootstrap.default.samples==0)
	check_result("real_F12_starts_visible_sampling",bootstrap.after_F12.active and bootstrap.after_F12.processing and bootstrap.after_F12.visible and bootstrap.after_F12.samples>0)
	check_result("real_move_cadence_distinguishes_source_and_derived","原图 10.0 / 下肢 30.0" in bootstrap.after_F12.text)
	check_result("live_trace_has_wrapped_at_native_render_rate",diag.sample_count>diag.CAPACITY and diag.recent_rows().size()==diag.CAPACITY,
		{"session_samples":diag.sample_count,"retained_rows":diag.recent_rows().size(),"capacity":diag.CAPACITY})
	var before_export: String=diag.last_export
	key(KEY_F12,true,true);key(KEY_F12,false,true)
	await tree.process_frame
	check_result("actual_Ctrl_F12_exports_native_user_file",diag.last_export!=before_export and FileAccess.file_exists(diag.last_export),{"path":diag.last_export})
	var report: Dictionary=exported(diag)
	check_result("export_retains_exact_bounded_tail",report.retained_rows==diag.CAPACITY and report.rows.size()==diag.CAPACITY and report.overwritten_rows==report.session_sample_count-diag.CAPACITY)
	check_result("trace_columns_and_positive_ordered_times",report.schema==2 and report.columns.size()==15 and report.rows.all(func(r):return r.size()==15 and r[1]>0.0)
		and report.rows[-1][0]>report.rows[0][0])
	check_result("trace_has_walk_phase_and_session_epoch",report.session_started_unix_s>0 and "walk_subframe" in report.columns and "walk_active" in report.columns)
	check_result("trace_hash_identifies_loaded_sampler",report.source_sha256==diag.get_script().source_code.sha256_text()
		and report.source_sha256==FileAccess.get_sha256("res://scripts/frame_diagnostics.gd"))
	check_result("event_buffer_bounded",report.events.size()<=128)
	check_result("panel_does_not_capture_mouse",diag.panel.mouse_filter==Control.MOUSE_FILTER_IGNORE and diag.label.mouse_filter==Control.MOUSE_FILTER_IGNORE)
	root._set_paused(true)
	root.player.preview("move")
	await tree.create_timer(.12).timeout
	var pose: Dictionary=root.player.capture_state()
	var samples: int=diag.sample_count
	await tree.create_timer(.2).timeout
	check_result("sampler_keeps_rendering_when_actor_is_paused",diag.sample_count>samples and root.player.capture_state()==pose)
	check_result("pause_is_visible_in_cadence_label","已暂停" in diag.cadence())
	root.player.preview("stay")
	check_result("source_idle_average_cadence_8_3hz","8.3 次/秒" in diag.cadence())
	root.player.preview("dash")
	check_result("source_dash_average_cadence_10hz","10.0 次/秒" in diag.cadence())
	root.player.reset_position();root._set_paused(false)
	root.player.start_jump();root.player._tick_jump(.35,false);root._set_paused(true)
	check_result("jump_uses_phase_label_not_long_raw_hold_rate","随跳跃阶段切换" in diag.cadence())
	var expected: Dictionary=root.player.capture_state()
	var id: int=diag.get_instance_id()
	root._switch_comparison();await tree.scene_changed;root=tree.current_scene
	await tree.create_timer(.12).timeout
	check_result("F4_retains_one_active_sampler",tree.root.get_node("FrameDiagnostics").get_instance_id()==id and diag.active
		and tree.root.get_children().filter(func(n):return n.name=="FrameDiagnostics").size()==1)
	check_result("F4_keeps_actor_jump_and_pause_state",root.player.capture_state()==expected)
	check_result("R0_is_in_native_trace",diag.recent_rows().any(func(r):return r[7]==0))
	check_result("F4_scene_change_is_traced",diag.events.any(func(e):return e.type=="scene_changed" and e.scene=="res://scenes/west_coast_r0.tscn"))
	root._switch_comparison();await tree.scene_changed;root=tree.current_scene
	key(KEY_F12,true);key(KEY_F12,false)
	await tree.process_frame
	samples=diag.sample_count
	await tree.create_timer(.2).timeout
	check_result("actual_F12_stops_all_hidden_sampling",not diag.active and not diag.panel.visible and not diag.is_processing() and diag.sample_count==samples)
	before_export=diag.last_export
	key(KEY_F12,true,true);key(KEY_F12,false,true);await tree.process_frame
	check_result("closed_trace_can_be_saved_without_restarting",diag.last_export!=before_export and not diag.active and not diag.is_processing())
	var closed: Dictionary=exported(diag)
	check_result("closed_export_contains_both_scenes",closed.rows.any(func(r):return r[7]==0) and closed.rows.any(func(r):return r[7]==1))
	key(KEY_F12,true);key(KEY_F12,false);await tree.process_frame
	check_result("reopening_starts_new_bounded_session",diag.active and diag.sample_count<20 and diag.events.is_empty())
	key(KEY_F12,true);key(KEY_F12,false);await tree.process_frame
	root.player.restore_state(original);root._set_paused(original.paused)
	if tree.has_meta("port_compare_state"):tree.remove_meta("port_compare_state")
	check_result("restored_free_player_and_native_interpolation",not root.player.paused and not root.player.preview_mode
		and root.player.motion_smoothing.enabled and root.player.is_physics_interpolated_and_enabled())
	var failed: Array=checks.filter(func(c):return not c.pass)
	var result: Dictionary={"candidate":"R1/25","checks":checks,"failed":failed,"exports":exports,"qa_source_sha256":get_script().source_code.sha256_text(),
		"note":"Actual F12 and Ctrl-F12 events, actual 60s bounded trace, pause and F4 checks. No synthetic buffer filling."}
	var output:=FileAccess.open("res://docs/r1_25_diagnostics_checks.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"  "));output.close()
	return {"checks":checks.size(),"failed":failed,"exports":exports}
