extends Node
## Real native keyboard actions in the visible game. No clone or frame readback
## while sampling. Timing columns describe observations, not inferred causes.

const PIPELINES: Array[String]=["PIPELINE_COMPILATIONS_CANVAS","PIPELINE_COMPILATIONS_MESH","PIPELINE_COMPILATIONS_SURFACE","PIPELINE_COMPILATIONS_DRAW","PIPELINE_COMPILATIONS_SPECIALIZATION"]
const COLUMNS: Array[String]=["elapsed_s","frame_gap_ms","engine_delta_ms","previous_process_ms","previous_physics_ms","scene_cpu_ms","scene_gpu_ms","window_cpu_ms","window_gpu_ms","pre_post_draw_wall_ms","focused","action_id","source_frame","source_elapsed_ms","source_x","source_y","jump_height_px","active_fx_tracks","render_scale","draw_calls","resource_count","static_memory_bytes","pipeline_canvas","pipeline_mesh","pipeline_surface","pipeline_draw","pipeline_specialization","phase_id","frames_drawn","walk_subframe","walk_active"]
const ACTIONS: Array[String]=["stay","move","dash","attack1","attack2","attack3","hopsmash","jump","jumpattack"]
var status: String="new"
var tag: String="r1_22_live"
var main: Node
var original: Dictionary
var original_scale: int
var plan: Array=[]
var phase_index: int=-1
var phase_start_usec: int=0
var start_usec: int=0
var previous_usec: int=0
var draw_start_usec: int=0
var draw_wall_ms: float=0.0
var rows: Array=[]
var events: Array=[]
var held: Array[int]=[]
var pulses: Dictionary={}
var pipeline_ids: Array[int]=[]
var previous_pipelines: Array[int]=[]
var previous_focused: bool=true
var previous_action: String=""
var observed_actions: Dictionary={}
var resource_start: int=0
var music_starts: int=0
var ambience_starts: int=0
var source_transitions: int=0
var update_count: int=0
var phase_ranges: Array=[]
var report: Dictionary={}
var scene_rid: RID
var window_rid: RID


func key(code: int,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func start(root: Node,name_tag: String="r1_22_live",cycles: int=2) -> Dictionary:
	main=root;tag=name_tag
	original=main.player.capture_state();original_scale=main.render_scale
	main._set_paused(false);main.player.reset_position()
	scene_rid=main.render_viewport.get_viewport_rid();window_rid=get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(scene_rid,true)
	RenderingServer.viewport_set_measure_render_time(window_rid,true)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	RenderingServer.frame_post_draw.connect(_post_draw)
	for constant: String in PIPELINES:pipeline_ids.append(ClassDB.class_get_integer_constant("Performance",constant))
	previous_pipelines=pipelines()
	resource_start=int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	source_transitions=main.player.frame_transitions
	music_starts=get_tree().root.get_node("PortMusic").play_starts
	ambience_starts=get_tree().root.get_node("PortAmbience").play_starts
	for cycle: int in cycles:
		plan.append_array([
			{"name":"idle","seconds":2.0,"keys":[]},
			{"name":"effect_first_or_repeat","seconds":2.0,"keys":[],"pulses":[[0,KEY_Q]]},
			{"name":"effect_again","seconds":2.0,"keys":[],"pulses":[[0,KEY_Q]]},
			{"name":"ground_attacks","seconds":2.5,"keys":[],"pulses":[[0,KEY_X],[.7,KEY_X],[1.4,KEY_X]]},
			{"name":"walk_right","seconds":2.2,"keys":[KEY_D]},
			{"name":"run_left","seconds":2.2,"keys":[KEY_A,KEY_SHIFT]},
			{"name":"jump_right","seconds":1.4,"keys":[KEY_D],"pulses":[[0,KEY_SPACE]]},
			{"name":"air_attack_left","seconds":1.4,"keys":[KEY_A],"pulses":[[0,KEY_SPACE],[.35,KEY_X]]},
			{"name":"toward_blue_door","seconds":1.9,"keys":[KEY_A]},
			{"name":"door_approach","seconds":2.1,"keys":[KEY_W]},
			{"name":"door_return","seconds":2.1,"keys":[KEY_S]},
			{"name":"run_street_right","seconds":3.0,"keys":[KEY_D,KEY_SHIFT]},
			{"name":"run_street_left","seconds":1.9,"keys":[KEY_A,KEY_SHIFT]},
			{"name":"light_quality","seconds":2.0,"keys":[],"pulses":[[0,KEY_F6],[.2,KEY_Q]]},
			{"name":"restore_quality","seconds":2.0,"keys":[],"pulses":[[0,KEY_F6],[.2,KEY_Q]]},
			{"name":"reset","seconds":1.0,"keys":[],"pulses":[[0,KEY_R]]}])
	process_priority=1000000
	start_usec=Time.get_ticks_usec();previous_usec=start_usec
	status="sampling"
	_next_phase()
	return snapshot()


func pipelines() -> Array[int]:
	var result: Array[int]=[]
	for id: int in pipeline_ids:result.append(int(Performance.get_monitor(id)))
	return result


func _pre_draw() -> void:draw_start_usec=Time.get_ticks_usec()
func _post_draw() -> void:draw_wall_ms=float(Time.get_ticks_usec()-draw_start_usec)/1000.0


func _next_phase() -> void:
	for code: int in held:key(code,false)
	held.clear()
	if phase_index>=0:phase_ranges[-1]["end_row"]=rows.size()
	phase_index+=1
	if phase_index>=plan.size():
		finish()
		return
	phase_start_usec=Time.get_ticks_usec();pulses.clear()
	phase_ranges.append({"index":phase_index,"name":plan[phase_index]["name"],"start_row":rows.size(),"end_row":-1})
	events.append({"type":"phase","phase":phase_index,"name":plan[phase_index]["name"],"elapsed_s":float(phase_start_usec-start_usec)/1000000.0})
	for code: int in plan[phase_index]["keys"]:
		key(code,true);held.append(code)


func _process(delta: float) -> void:
	if status!="sampling":return
	if not is_instance_valid(main):
		cancel("Main scene removed")
		return
	var now: int=Time.get_ticks_usec()
	var p: Node=main.player
	var point: Vector2=p.world_to_source(p.position)
	var focused: bool=DisplayServer.window_is_focused()
	var counts: Array[int]=pipelines()
	if counts!=previous_pipelines:
		events.append({"type":"pipeline_change","elapsed_s":float(now-start_usec)/1000000.0,"from":previous_pipelines,"to":counts,"action":p.animation_name,"phase":phase_index})
		previous_pipelines=counts
	if focused!=previous_focused:
		events.append({"type":"focus_change","elapsed_s":float(now-start_usec)/1000000.0,"focused":focused})
		previous_focused=focused
	if p.animation_name!=previous_action:
		events.append({"type":"action","elapsed_s":float(now-start_usec)/1000000.0,"action":p.animation_name,"phase":phase_index})
		previous_action=p.animation_name
	observed_actions[p.animation_name]=true
	var row: Array=[float(now-start_usec)/1000000.0,float(now-previous_usec)/1000.0,delta*1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(scene_rid),RenderingServer.viewport_get_measured_render_time_gpu(scene_rid),
		RenderingServer.viewport_get_measured_render_time_cpu(window_rid),RenderingServer.viewport_get_measured_render_time_gpu(window_rid),
		draw_wall_ms,focused,ACTIONS.find(p.animation_name),p.frame_index,p.elapsed_ms,point.x,point.y,p.jump_motion.height_pixels,
		p.action_effects.active_frames.size(),main.render_scale,
		main.render_viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),Performance.get_monitor(Performance.MEMORY_STATIC)]
	row.append_array(counts);row.append_array([phase_index,Engine.get_frames_drawn()])
	row.append_array([p.walk_inbetweens.subframe,1 if p.walk_inbetweens.active else 0])
	rows.append(row);previous_usec=now;update_count+=1
	var phase_seconds: float=float(now-phase_start_usec)/1000000.0
	var phase_pulses: Array=plan[phase_index].get("pulses",[])
	for i: int in phase_pulses.size():
		if not pulses.has(i) and phase_seconds>=phase_pulses[i][0]:
			var code: int=phase_pulses[i][1]
			key(code,true);key(code,false);pulses[i]=true
			events.append({"type":"key_pulse","elapsed_s":float(Time.get_ticks_usec()-start_usec)/1000000.0,"key":OS.get_keycode_string(code),"phase":phase_index})
	if phase_seconds>=plan[phase_index]["seconds"]:_next_phase()


func snapshot() -> Dictionary:
	return {"status":status,"elapsed_s":float(Time.get_ticks_usec()-start_usec)/1000000.0,"rows":rows.size(),"phase":phase_index,
		"phase_name":plan[phase_index]["name"] if phase_index>=0 and phase_index<plan.size() else "finished","report":report}


func restore() -> void:
	for code: int in held:key(code,false)
	held.clear()
	if RenderingServer.frame_pre_draw.is_connected(_pre_draw):RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	if RenderingServer.frame_post_draw.is_connected(_post_draw):RenderingServer.frame_post_draw.disconnect(_post_draw)
	if is_instance_valid(main):
		RenderingServer.viewport_set_measure_render_time(scene_rid,false)
		RenderingServer.viewport_set_measure_render_time(window_rid,false)
		main.set_render_scale(original_scale)
		main.player.restore_state(original);main._set_paused(original.paused)


func finish() -> void:
	status="finishing"
	set_process(false)
	var maximum: float=0.0
	var slow: int=0
	for row: Array in rows:
		maximum=maxf(maximum,row[1])
		if row[1]>1000.0/60.0:slow+=1
	var p: Node=main.player
	report={"study":"Live native input observation","production_candidate":"","tag":tag,"columns":COLUMNS,
		"frame_rows":rows.size(),"events":events,"phase_ranges":phase_ranges,"plan":plan,"observed_actions":observed_actions.keys(),
		"max_frame_gap_ms":maximum,"frames_over_16_67_ms":slow,"source_transitions":p.frame_transitions-source_transitions,
		"scene_target":main.render_viewport.size,"native_window":DisplayServer.window_get_size(),"native_interpolation":p.is_physics_interpolated_and_enabled(),
		"resource_start":resource_start,"resource_end":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"music_starts_before":music_starts,"music_starts_after":get_tree().root.get_node("PortMusic").play_starts,
		"ambience_starts_before":ambience_starts,"ambience_starts_after":get_tree().root.get_node("PortAmbience").play_starts,
		"pipeline_columns":PIPELINES,"qa_source_sha256":get_script().source_code.sha256_text(),
		"notes":["Visible native scene and real InputEventKey actions. No position writes or frame readback during sampling.",
			"CPU/GPU fields come from Godot viewport timing. They can lag; correlation does not prove a stall cause.",
			"Events and full samples buffered in memory; file writes happen after timing has stopped.",
			"First row includes monitor startup and is excluded from subsequent steady-state statistics."]}
	report["production_candidate"]="R1/"+main.get_node("Interface/Build").text.get_slice("/",1).strip_edges()
	report["production_build_label"]=main.get_node("Interface/Build").text
	report["action_names"]=ACTIONS
	report["derived_locomotion_actions"]=p.walk_inbetweens.clips.keys()
	var diagnostic: Node=get_tree().root.get_node_or_null("FrameDiagnostics")
	report["diagnostics_active"]=diagnostic.active if diagnostic else false
	if diagnostic!=null and diagnostic.active:diagnostic._event({"type":"qa_report_io","tag":tag,"note":"QA buffer writes after measured frames; may cause a subsequent diagnostic wall gap."})
	var output:=FileAccess.open("res://docs/"+tag+"_observation.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	output=FileAccess.open("res://docs/"+tag+"_samples.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(rows));output.close()
	restore()
	status="complete"


func cancel(reason: String) -> Dictionary:
	set_process(false)
	restore();status="cancelled";report={"reason":reason}
	return snapshot()
