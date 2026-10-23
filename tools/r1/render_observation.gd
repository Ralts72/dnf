extends Node
## Finite live observation of an independently rendered full 1080p scene.
## Poll this node's status; the JSON file alone is not a live-job status.

const ACTIONS: Array[String] = ["stay","move","dash","attack1","attack2","hopsmash"]
var status: String = "new"
var candidate: String="R1/20"
var report: Dictionary = {}
var main: Node
var full: SubViewport
var clone: Node
var original_state: Dictionary
var original_update: int
var original_scale: int
var start_usec: int
var previous_usec: int
var samples: Array[float] = []
var clips_observed: Dictionary = {}
var last_segment: int = -1
var native_draw_min: int = 1000000
var native_draw_max: int = 0
var warmup_seconds: float = 2.0
var duration_seconds: float = 30.0
var water_start_seconds: float=0.0
var music: Node
var music_player_id: int=0
var music_play_starts: int=0
var music_start_position: float=0.0
var music_start_loops: int=0
var music_active_frames: int=0
var ambience: Node
var ambient_player_id: int=0
var ambient_play_starts: int=0
var ambient_active_frames: int=0
var source_effect_active_frames: int=0
var source_effect_peak_tracks: int=0
var slow_frame_events: Array=[]


func start(root: Node,tag: String="R1/20") -> Dictionary:
	candidate=tag
	main = root
	music=get_tree().root.get_node("PortMusic")
	music_player_id=music.player.get_instance_id()
	music_play_starts=music.play_starts
	music_start_position=music.player.get_playback_position()
	music_start_loops=music.player.get_stream_playback().get_loop_count()
	ambience=get_tree().root.get_node("PortAmbience")
	ambient_player_id=ambience.player.get_instance_id()
	ambient_play_starts=ambience.play_starts
	original_state = main.player.capture_state()
	original_update = main.render_viewport.render_target_update_mode
	original_scale = main.render_scale
	main._set_paused(true)
	main.render_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	full = SubViewport.new()
	full.name = "R1Full1080Observation"
	full.size = Vector2i(1920,1080)
	full.size_2d_override = Vector2i(960,540)
	full.size_2d_override_stretch = true
	full.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(full)
	clone = load("res://scenes/west_coast_r1.tscn").instantiate()
	full.add_child(clone)
	clone.set_render_scale(2)
	clone._set_paused(false)
	clone.player.position=clone.player.source_to_world(Vector2(280,310))
	clone.player.motion_smoothing.reset()
	water_start_seconds=clone.water.seconds
	start_usec = Time.get_ticks_usec()
	previous_usec = start_usec
	status = "warming_up"
	set_process(true)
	return snapshot()


func snapshot() -> Dictionary:
	return {"status":status,"elapsed_seconds":float(Time.get_ticks_usec()-start_usec)/1000000.0,
		"sampled_frames":samples.size(),"duration_seconds":duration_seconds,"report":report}


func _process(_delta: float) -> void:
	if status not in ["warming_up","sampling"]:
		return
	if not is_instance_valid(main) or not is_instance_valid(clone):
		cancel("Scene removed during observation")
		return
	var now: int = Time.get_ticks_usec()
	var elapsed: float = float(now-start_usec)/1000000.0
	var segment: int = int(maxf(0.0,elapsed-warmup_seconds)/2.0)
	if segment != last_segment:
		var action: String = ACTIONS[segment%ACTIONS.size()]
		clone.player.preview(action)
		last_segment = segment
		if elapsed >= warmup_seconds:
			clips_observed[action] = true

	if elapsed < warmup_seconds:
		previous_usec = now
		return
	status = "sampling"
	clips_observed[clone.player.animation_name] = true
	var visible_tracks: int=clone.player.action_effects.active_frames.size()
	if visible_tracks>0:source_effect_active_frames+=1
	source_effect_peak_tracks=maxi(source_effect_peak_tracks,visible_tracks)
	var frame_ms: float=float(now-previous_usec)/1000.0
	samples.append(frame_ms)
	if frame_ms>1000.0/60.0:
		slow_frame_events.append({"frame_ms":frame_ms,"sample_elapsed_seconds":elapsed-warmup_seconds,
			"clip":clone.player.animation_name,"pose_time_ms":clone.player.action_effects.pose_time_ms(),
			"active_effect_tracks":visible_tracks,"previous_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0})
	if music.player.playing and not music.player.stream_paused and music.gain>.05:
		music_active_frames+=1
	if ambience.player.playing and not ambience.player.stream_paused and ambience.gain>.005:
		ambient_active_frames+=1
	previous_usec = now
	var draws: int = clone.render_viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	native_draw_min = mini(native_draw_min,draws)
	native_draw_max = maxi(native_draw_max,draws)
	if elapsed >= warmup_seconds+duration_seconds:
		status = "finishing"
		set_process(false)
		finish()


func _physics_process(_delta: float) -> void:
	if status not in ["warming_up","sampling"] or not is_instance_valid(clone):return
	# Exercise native interpolation with transforms written only at physics ticks.
	# This remains deterministic pose placement, not a navigation simulation.
	var elapsed: float=float(Time.get_ticks_usec()-start_usec)/1000000.0
	clone.player.position=clone.player.source_to_world(Vector2(280+200*sin(elapsed*.55),310+12*sin(elapsed*.7)))
	clone.player.facing=1 if last_segment%2==0 else -1


func finish() -> void:
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var total: float = 0.0
	var over_budget: int = 0
	for ms: float in samples:
		total += ms
		if ms > 1000.0/60.0:
			over_budget += 1
	var count: int = samples.size()
	var middle: int = count>>1
	var median: float = (sorted[middle-1]+sorted[middle])*.5 if count%2==0 else sorted[middle]
	var p95: float = sorted[int(ceil((count-1)*.95))]
	var observation: Dictionary = {"frames":count,"elapsed_sample_seconds":total/1000.0,
		"mean_ms":total/count,"median_ms":median,"p95_ms":p95,"max_ms":sorted[-1],
		"fps_from_mean":1000.0/(total/count),"frames_over_16_67_ms":over_budget,
		"percent_over_16_67_ms":100.0*over_budget/count}
	await RenderingServer.frame_post_draw
	var full_image: Image = full.get_texture().get_image()
	var child_size: Vector2i = clone.render_viewport.get_texture().get_image().get_size()
	full_image.save_png("res://docs/previews/"+candidate.to_lower().replace("/","_")+"_after_observation.png")
	var checks: Array = [
		{"check":"full_1080_native_targets","pass":full_image.get_size()==Vector2i(1920,1080) and child_size==Vector2i(1792,808)},
		{"check":"all_six_clips_observed","pass":clips_observed.size()==6},
		{"check":"source_effect_tracks_rendered_during_observation","pass":source_effect_active_frames>0 and source_effect_peak_tracks==2},
		{"check":"full_3d_pass_active","pass":native_draw_min>100},
		{"check":"native_motion_interpolation_active","pass":clone.player.is_physics_interpolated_and_enabled()},
		{"check":"main_3d_disabled","pass":main.render_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED},
		{"check":"sample_duration_at_least_30_seconds","pass":total>=duration_seconds*1000.0},
		{"check":"p95_within_60fps_frame_budget","pass":p95<=1000.0/60.0},
		{"check":"water_clock_advances_during_observation","pass":clone.water.seconds-water_start_seconds>=duration_seconds},
		{"check":"music_remains_active_during_observation","pass":music_active_frames==samples.size()},
		{"check":"one_music_player_retained_during_observation","pass":music.player.get_instance_id()==music_player_id and music.play_starts==music_play_starts},
		{"check":"ambient_remains_active_during_observation","pass":ambient_active_frames==samples.size()},
		{"check":"one_ambient_player_retained_during_observation","pass":ambience.player.get_instance_id()==ambient_player_id and ambience.play_starts==ambient_play_starts}]
	var failed: int = 0
	for item: Dictionary in checks:
		if not item["pass"]:
			failed += 1
	report = {"candidate":candidate,"platform":"macOS","godot":Engine.get_version_info()["string"],
		"observation":observation,"checks":checks,"failed":failed,"clips":clips_observed.keys(),
		"native_motion_interpolation_active":clone.player.is_physics_interpolated_and_enabled(),
		"draw_calls_min":native_draw_min,"draw_calls_max":native_draw_max,
		"source_effect_active_frames":source_effect_active_frames,"source_effect_peak_tracks":source_effect_peak_tracks,
		"slow_frame_events":slow_frame_events,
		"full_target":full_image.get_size(),"scene_target":child_size,"warmup_seconds":warmup_seconds,
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"water_elapsed_seconds":clone.water.seconds-water_start_seconds,
		"music_active_frames":music_active_frames,"music_player_id":music_player_id,"music_play_starts":music.play_starts,
		"ambient_active_frames":ambient_active_frames,"ambient_player_id":ambient_player_id,"ambient_play_starts":ambience.play_starts,
		"music_elapsed_seconds":(music.player.get_stream_playback().get_loop_count()-music_start_loops)*music.player.stream.get_length()+music.player.get_playback_position()-music_start_position,
		"notes":["30 seconds in the current Mac session; not long-term stability or Windows validation.",
			"Frame intervals include the offscreen full scene; the visible main 3D pass was disabled.",
			"Six source poses, both facings, changing positions, NPC animations, ship motion, shadows and water remain active.",
			"Physics-tick pose placement with native interpolation is a rendering load; navigation logic is tested separately."]}
	var out: FileAccess = FileAccess.open("res://docs/"+candidate.to_lower().replace("/","_")+"_render_observation.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	out = FileAccess.open("res://docs/"+candidate.to_lower().replace("/","_")+"_render_observation_samples.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(samples,"  "))
	out.close()
	restore_main()
	status = "complete"


func restore_main() -> void:
	if is_instance_valid(main):
		main.render_viewport.render_target_update_mode = original_update as SubViewport.UpdateMode
		main.set_render_scale(original_scale)
		main.player.restore_state(original_state)
		main._set_paused(original_state["paused"])
	if is_instance_valid(full):
		full.queue_free()


func cancel(reason: String) -> Dictionary:
	set_process(false)
	restore_main()
	status = "cancelled"
	report = {"reason":reason}
	return snapshot()
