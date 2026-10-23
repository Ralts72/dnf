extends RefCounted
## Live stereo mix, source-position gain, F8/F9 independence and persistent loops.

var checks: Array=[]
var capture_samples: Array=[]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)


func mix_sample(tree: SceneTree,effect: AudioEffectCapture,label: String) -> Dictionary:
	effect.clear_buffer();await tree.create_timer(.16).timeout
	var buffer: PackedVector2Array=effect.get_buffer(effect.get_frames_available())
	var peak: float=0.0
	var square: float=0.0
	for sample: Vector2 in buffer:
		peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)));square+=sample.length_squared()
	var row: Dictionary={"label":label,"frames":buffer.size(),"peak":peak,"rms":sqrt(square/maxi(1,buffer.size()*2))}
	capture_samples.append(row)
	return row


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var ambience: Node=tree.root.get_node("PortAmbience")
	var music: Node=tree.root.get_node("PortMusic")
	var original: Dictionary=root.player.capture_state()
	var original_water: Dictionary=root.water.capture_state()
	var original_ambience: Dictionary=ambience.capture_state()
	var original_music: Dictionary=music.capture_state()
	var old_muted: bool=tree.get_meta("port_audio_muted",false)
	var old_volume: float=tree.get_meta("port_audio_volume",.6)
	var bus: int=AudioServer.get_bus_index(ambience.bus_name)
	var old_bus_db: float=AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_volume_db(bus,-80.0)
	var effect:=AudioEffectCapture.new();effect.buffer_length=1.0
	var effect_index: int=AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus,effect)
	tree.set_meta("port_audio_muted",false);tree.set_meta("port_audio_volume",.6)
	ambience.muted=false;ambience.select_volume(.35)
	root.player.reset_position();root._set_paused(false)
	root.player.position=root.player.source_to_world(Vector2(650,285))
	await tree.create_timer(1.1).timeout
	var player_id: int=ambience.player.get_instance_id()
	var music_id: int=music.player.get_instance_id()
	var starts: int=ambience.play_starts
	var near_gain: float=ambience.gain
	check_result("mapped_ambient_tag",ambience.settings["tag"]=="AMB_PORT_01")
	check_result("native_duration_forty_seconds",absf(ambience.player.stream.get_length()-40.0)<.002)
	check_result("native_loop_at_zero",ambience.player.stream.loop and ambience.player.stream.loop_offset==0.0)
	check_result("separate_ambient_bus",ambience.player.bus==&"PortAmbience" and bus!=AudioServer.get_bus_index(music.bus_name))
	check_result("single_ambient_player",ambience.get_children().size()==1 and ambience.play_starts==1)
	check_result("near_shore_mix_is_quiet",near_gain>.05 and near_gain<.3,{"gain":near_gain,"distance":ambience.source_distance})
	var audible: Dictionary=await mix_sample(tree,effect,"near_shore")
	check_result("native_ambient_mix_is_nonzero",audible.frames>1000 and audible.peak>.0001,audible)
	root.player.position=root.player.source_to_world(Vector2(100,300))
	await tree.create_timer(.35).timeout
	var far_gain: float=ambience.gain
	check_result("street_is_quieter_than_shore",near_gain>far_gain*1.7 and far_gain>0,
		{"near_gain":near_gain,"far_gain":far_gain,"far_distance":ambience.source_distance})
	root.player.position=root.player.source_to_world(Vector2(650,285))
	await tree.create_timer(.35).timeout
	check_result("return_to_shore_restores_mix_without_restart",absf(ambience.gain-near_gain)<.001 and ambience.play_starts==starts)
	tree.set_meta("port_audio_volume",.3)
	await tree.create_timer(.25).timeout
	check_result("effects_volume_scales_ambience",absf(ambience.gain-near_gain*.5)<.001)
	tree.set_meta("port_audio_volume",.6)
	await tree.create_timer(.2).timeout
	key(KEY_F8,true);key(KEY_F8,false)
	await tree.create_timer(.25).timeout
	check_result("actual_f8_mutes_ambient",tree.get_meta("port_audio_muted",false) and ambience.player.stream_paused and ambience.gain==0.0)
	var paused_position: float=ambience.player.get_playback_position()
	var silent: Dictionary=await mix_sample(tree,effect,"effects_muted")
	check_result("muted_ambient_mix_is_zero",silent.peak<.000001,silent)
	check_result("mute_keeps_ambient_position",absf(ambience.player.get_playback_position()-paused_position)<.01)
	check_result("effects_mute_keeps_music_playing",not music.muted and not music.player.stream_paused)
	key(KEY_F8,true);key(KEY_F8,false)
	await tree.create_timer(.25).timeout
	check_result("actual_f8_resumes_same_ambient_player",not ambience.player.stream_paused and ambience.player.get_instance_id()==player_id and ambience.play_starts==starts)
	check_result("resume_restores_ambient_mix",(await mix_sample(tree,effect,"effects_resumed")).peak>.0001)
	key(KEY_F9,true);key(KEY_F9,false)
	await tree.create_timer(.25).timeout
	check_result("music_mute_does_not_mute_ambient",music.muted and not ambience.player.stream_paused and ambience.gain>.03)
	key(KEY_F9,true);key(KEY_F9,false)
	await tree.create_timer(.2).timeout
	var before_pause: float=ambience.player.get_playback_position()
	key(KEY_F2,true);key(KEY_F2,false)
	await tree.process_frame
	var water_time: float=root.water.seconds
	await tree.create_timer(.2).timeout
	check_result("pose_pause_keeps_environment_running",root.player.paused and ambience.player.get_playback_position()>before_pause+.08 and not ambience.player.stream_paused)
	check_result("pose_pause_keeps_water_frozen",root.water.paused and root.water.seconds==water_time)
	key(KEY_F2,true);key(KEY_F2,false)
	ambience.player.seek(5.0)
	await tree.create_timer(.05).timeout
	var before_switch: float=ambience.player.get_playback_position()
	root._switch_comparison();await tree.scene_changed
	var r0: Node=tree.current_scene
	await tree.create_timer(.2).timeout
	check_result("r0_keeps_same_ambient_and_music_players",ambience.player.get_instance_id()==player_id and music.player.get_instance_id()==music_id and ambience.play_starts==starts)
	check_result("r0_retains_equivalent_source_distance_mix",absf(ambience.gain-near_gain)<.001,{"r0_gain":ambience.gain,"r1_gain":near_gain})
	check_result("r0_keeps_ambient_progress",ambience.player.get_playback_position()>before_switch-.04 and ambience.player.get_playback_position()<before_switch+.8)
	r0._switch_comparison();await tree.scene_changed
	root=tree.current_scene
	await tree.create_timer(.2).timeout
	check_result("r1_keeps_same_ambient_and_progress",ambience.player.get_instance_id()==player_id and ambience.play_starts==starts and ambience.player.get_playback_position()>before_switch-.04)
	var fixture:=SubViewport.new();fixture.name="R1AmbienceCloneFixture";fixture.size=Vector2i(960,540)
	tree.root.add_child(fixture)
	var clone: Node=load("res://scenes/west_coast_r1.tscn").instantiate();fixture.add_child(clone);clone._set_paused(true)
	await tree.create_timer(.2).timeout
	check_result("capture_clone_does_not_change_distance_mix",absf(ambience.gain-near_gain)<.001 and ambience.get_children().size()==1)
	fixture.queue_free();await tree.process_frame
	ambience.player.seek(39.93);await tree.create_timer(.3).timeout
	check_result("ambient_loop_wraps_without_restart",ambience.player.get_playback_position()<.65 and ambience.play_starts==starts)
	check_result("loop_keeps_native_ambient_mix",(await mix_sample(tree,effect,"after_native_loop")).peak>.0001)
	ambience.select_volume(0);await tree.create_timer(.2).timeout
	AudioServer.remove_bus_effect(bus,effect_index);AudioServer.set_bus_volume_db(bus,old_bus_db)
	ambience.player.seek(original_ambience.position);ambience.select_volume(original_ambience.volume);ambience.muted=original_ambience.muted
	music.select_volume(original_music.volume);music.muted=original_music.muted
	tree.set_meta("port_audio_muted",old_muted);tree.set_meta("port_audio_volume",old_volume)
	root.player.restore_state(original);root.water.restore_state(original_water);root._set_paused(original.paused)
	if tree.has_meta("port_compare_state"):tree.remove_meta("port_compare_state")
	var failed: Array=checks.filter(func(c: Dictionary):return not c["pass"])
	var report: Dictionary={"candidate":"R1/14","checks":checks,"failed":failed,"capture_samples":capture_samples,
		"near_gain":near_gain,"far_gain":far_gain,"ambient_player_id":player_id,"ambient_play_starts":ambience.play_starts,
		"qa_source_sha256":get_script().source_code.sha256_text(),"ambient_script_sha256":FileAccess.get_sha256("res://scripts/port_ambience.gd"),
		"note":"Native ambient bus mix captured before its temporary 80 dB attenuation; gain/effects restored. Stereo source recording stays unchanged; only gain depends on the active player's source position."}
	var out=FileAccess.open("res://docs/r1_14_ambience_checks.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	return {"checks":checks.size(),"failed":failed,"capture_samples":capture_samples}
