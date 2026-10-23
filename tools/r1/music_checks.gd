extends RefCounted
## Native player, mixer, looping, pause policy and persistent R0/R1 continuity.

var checks: Array=[]
var capture_samples: Array=[]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)


func signal_stats(buffer: PackedVector2Array) -> Dictionary:
	var peak: float=0.0
	var square: float=0.0
	for sample: Vector2 in buffer:
		peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		square+=sample.length_squared()
	return {"frames":buffer.size(),"peak":peak,"rms":sqrt(square/maxi(1,buffer.size()*2))}


func mix_sample(tree: SceneTree,effect: AudioEffectCapture,label: String) -> Dictionary:
	effect.clear_buffer()
	await tree.create_timer(.16).timeout
	var result: Dictionary=signal_stats(effect.get_buffer(effect.get_frames_available()))
	result["label"]=label
	capture_samples.append(result)
	return result


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var music: Node=tree.root.get_node("PortMusic")
	var original: Dictionary=root.player.capture_state()
	var original_water: Dictionary=root.water.capture_state()
	var original_music: Dictionary=music.capture_state()
	var old_audio_muted: bool=tree.get_meta("port_audio_muted",false)
	var old_audio_volume: float=tree.get_meta("port_audio_volume",.6)
	var bus: int=AudioServer.get_bus_index(music.BUS_NAME)
	var old_bus_db: float=AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_volume_db(bus,-80.0)
	var effect:=AudioEffectCapture.new()
	effect.buffer_length=1.0
	var effect_index: int=AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus,effect)
	root.player.reset_position();root._set_paused(false)
	music.select_volume(.2)
	await tree.create_timer(.75).timeout
	var length: float=music.player.stream.get_length()
	check_result("mapped_original_music_tag",music.settings["tag"]=="M_WESTCOAST")
	check_result("native_vorbis_duration_matches_source",absf(length-35.555578)<.002,{"seconds":length})
	check_result("native_stream_loops_at_zero",music.player.stream.loop and music.player.stream.loop_offset==0.0)
	check_result("separate_music_bus",music.player.bus==&"PortMusic" and AudioServer.get_bus_send(bus)==&"Master")
	check_result("one_persistent_music_player",music.get_children().filter(func(n: Node):return n is AudioStreamPlayer).size()==1)
	check_result("default_twenty_percent_gain",absf(music.gain-.2)<.0001 and absf(db_to_linear(music.player.volume_db)-.2)<.001)
	var initial_id: int=music.player.get_instance_id()
	var starts: int=music.play_starts
	var audible: Dictionary=await mix_sample(tree,effect,"music_20_percent")
	check_result("native_music_mix_is_nonzero",audible.frames>1000 and audible.peak>.001,audible)
	var position: float=music.player.get_playback_position()
	root._set_paused(true)
	var water_time: float=root.water.seconds
	await tree.create_timer(.20).timeout
	check_result("pose_pause_keeps_music_running",music.player.get_playback_position()>position+.08
		and not music.player.stream_paused)
	check_result("pose_pause_still_freezes_water",root.water.paused and root.water.seconds==water_time)
	root._set_paused(false)
	key(KEY_F9,true);key(KEY_F9,false)
	await tree.create_timer(.25).timeout
	check_result("actual_f9_mutes_music",music.muted and music.player.stream_paused and music.gain==0.0)
	var muted_position: float=music.player.get_playback_position()
	var silent: Dictionary=await mix_sample(tree,effect,"music_muted")
	check_result("muted_music_mix_is_zero",silent.peak<.000001,silent)
	check_result("muted_music_retains_position",absf(music.player.get_playback_position()-muted_position)<.01)
	check_result("music_mute_does_not_change_effects",tree.get_meta("port_audio_muted",false)==old_audio_muted
		and float(tree.get_meta("port_audio_volume",.6))==old_audio_volume)
	key(KEY_F9,true);key(KEY_F9,false)
	await tree.create_timer(.25).timeout
	check_result("actual_f9_resumes_without_restart",not music.muted and not music.player.stream_paused
		and music.play_starts==starts and music.player.get_playback_position()>muted_position+.08)
	var resumed: Dictionary=await mix_sample(tree,effect,"music_resumed")
	check_result("resumed_music_mix_is_nonzero",resumed.peak>.001,resumed)
	key(KEY_F8,true);key(KEY_F8,false)
	await tree.process_frame
	check_result("effects_mute_does_not_mute_music",not music.muted and music.gain>.19 and not music.player.stream_paused)
	key(KEY_F8,true);key(KEY_F8,false)
	await tree.process_frame
	music.select_volume(.4)
	await tree.create_timer(.2).timeout
	check_result("independent_music_forty_percent_gain",absf(music.gain-.4)<.0001
		and absf(db_to_linear(music.player.volume_db)-.4)<.001 and float(tree.get_meta("port_audio_volume",.6))==old_audio_volume)
	music.player.seek(5.0)
	await tree.create_timer(.05).timeout
	var before_switch: float=music.player.get_playback_position()
	root._switch_comparison()
	await tree.scene_changed
	var r0: Node=tree.current_scene
	await tree.create_timer(.1).timeout
	check_result("r0_keeps_same_music_player",music.player.get_instance_id()==initial_id and music.play_starts==starts)
	check_result("r0_does_not_reset_music_position",music.player.get_playback_position()>before_switch-.04
		and music.player.get_playback_position()<before_switch+.8,{"before":before_switch,"after":music.player.get_playback_position()})
	check_result("r0_menu_retains_independent_volume",r0.get_node("Interface/MusicMenu").text.contains("40%")
		and r0.get_node("Interface/AudioMenu").text.contains("60%"))
	r0._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	await tree.create_timer(.1).timeout
	check_result("r1_keeps_same_music_player",music.player.get_instance_id()==initial_id and music.play_starts==starts)
	check_result("r1_does_not_reset_music_position",music.player.get_playback_position()>before_switch-.04
		and music.player.get_playback_position()<before_switch+1.0)
	var fixture:=SubViewport.new()
	fixture.name="R1MusicCloneFixture";fixture.size=Vector2i(960,540)
	tree.root.add_child(fixture)
	var clone: Node=load("res://scenes/west_coast_r1.tscn").instantiate()
	fixture.add_child(clone);clone._set_paused(true)
	var before_clone: float=music.player.get_playback_position()
	await tree.create_timer(.1).timeout
	check_result("paused_capture_clone_does_not_pause_music",music.player.get_playback_position()>before_clone+.03 and not music.player.stream_paused)
	check_result("capture_clone_does_not_add_music_player",music.play_starts==starts and music.get_children().size()==1)
	fixture.queue_free();await tree.process_frame
	music.player.seek(length-.07)
	await tree.create_timer(.3).timeout
	var looped: float=music.player.get_playback_position()
	check_result("native_loop_wraps_to_beginning",looped>=0 and looped<.65 and music.play_starts==starts,{"position":looped,"length":length})
	check_result("loop_keeps_native_mixing",(await mix_sample(tree,effect,"after_native_loop")).peak>.001)
	var rects: Array=[]
	for name: String in ["AudioMenu","MusicMenu","Compare","Quality","MoreActions"]:
		rects.append(root.get_node("Interface/"+name).get_global_rect())
	var overlaps: int=0
	for i: int in range(rects.size()-1):
		if rects[i].intersects(rects[i+1]):overlaps+=1
	check_result("header_audio_controls_do_not_overlap",overlaps==0,{"rects":rects})
	music.select_volume(0)
	await tree.create_timer(.2).timeout
	AudioServer.remove_bus_effect(bus,effect_index)
	AudioServer.set_bus_volume_db(bus,old_bus_db)
	music.player.seek(float(original_music["position"]))
	music.select_volume(float(original_music["volume"]))
	music.muted=bool(original_music["muted"])
	tree.set_meta("port_audio_muted",old_audio_muted);tree.set_meta("port_audio_volume",old_audio_volume)
	root.player.restore_state(original);root.water.restore_state(original_water);root._set_paused(original["paused"])
	if tree.has_meta("port_compare_state"):tree.remove_meta("port_compare_state")
	var failed: Array=checks.filter(func(c: Dictionary):return not c["pass"])
	var report: Dictionary={"candidate":"R1/14","checks":checks,"failed":failed,"capture_samples":capture_samples,
		"music_player_id":initial_id,"music_play_starts":music.play_starts,"music_bus_restored_db":AudioServer.get_bus_volume_db(bus),
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"music_script_sha256":FileAccess.get_sha256("res://scripts/port_music.gd"),
		"note":"BGM is independent of pose/water pause. The music bus was attenuated 80 dB during mixer checks and its original gain/effects restored. Capture frame counts are not used to infer duration on this multichannel device."}
	var out=FileAccess.open("res://docs/r1_14_music_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "));out.close()
	return {"checks":checks.size(),"failed":failed,"capture_samples":capture_samples}
