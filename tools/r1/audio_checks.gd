extends RefCounted
## Action scheduling, scene transfer and real Godot mixer verification.

var checks: Array=[]
var render_cases: Array=[]
var captures: Array=[]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func tags(sfx: Node) -> Array:
	return sfx.audit.map(func(cue: Dictionary): return cue["cue"])


func quiet_reset(p: Node) -> void:
	p.reset_position()
	p.set_process(false)
	p.set_physics_process(false)
	p.action_audio.output_enabled=false
	p.action_audio.audit.clear()


func functional(root: Node,kind: String) -> void:
	var p: Node=root.player
	var s: Node=p.action_audio
	quiet_reset(p)
	p.start_jump()
	p._tick_jump(.099,false)
	check_result(kind+"_no_sound_before_takeoff",s.audit.is_empty())
	p._tick_jump(.001,false)
	check_result(kind+"_takeoff_voice_and_ground_sound_once",tags(s)==["JUMP_START","SM_JUMP"])
	p._tick_jump(.25,false)
	p.attack()
	var count: int=s.audit.size()
	p.attack()
	check_result(kind+"_air_voice_once",tags(s).back()=="R_SM_JUMP_ATK" and s.audit.size()==count)
	p._tick_jump(.149,false)
	check_result(kind+"_air_swing_waits_for_pose",s.audit.size()==count)
	p._tick_jump(.001,false)
	check_result(kind+"_air_swing_at_source_box_pose",tags(s).back()=="R_SQUARESWDC" and s.audit.size()==count+1)
	p._tick_jump(.6,false)
	p._tick_jump(.05,false)
	check_result(kind+"_landing_once_and_no_pending_tail",tags(s).count("JUMP_END")==1 and s.pending.is_empty())
	quiet_reset(p)
	p.start_jump()
	p._tick_jump(1.2,false)
	check_result(kind+"_long_tick_does_not_lose_or_duplicate_jump_cues",tags(s)==["JUMP_START","SM_JUMP","JUMP_END"])
	quiet_reset(p)
	p.start_jump()
	p.paused=true
	var held: Dictionary=p.capture_state()
	p._process(.5)
	p._physics_process(.5)
	check_result(kind+"_paused_action_and_audio_clocks_stay_together",p.capture_state()==held)
	for i: int in 7:
		p.step_frame()
	check_result(kind+"_single_step_consumes_cue_silently",s.audit.size()==2
		and s.audit.all(func(c: Dictionary): return not c["audible"]) and s.pending.size()==1)
	quiet_reset(p)
	for action: String in ["jump","jumpattack","attack1","attack2","attack3"]:
		p.preview(action)
		p._process(.9)
	check_result(kind+"_raw_pose_previews_are_silent",s.audit.is_empty() and s.pending.is_empty())
	for action: String in ["attack1","attack2","attack3"]:
		quiet_reset(p)
		p.perform(action)
		var swing_ms: float=100.0 if action=="attack3" else 150.0
		p._process((swing_ms-1.0)/1000.0)
		check_result(kind+"_"+action+"_voice_precedes_swing",s.audit.size()==1 and tags(s)[0]=="R_SM_ATK")
		p._process(.001)
		check_result(kind+"_"+action+"_swing_on_visible_stroke",s.audit.size()==2
			and is_equal_approx(s.audit[1]["scheduled_ms"],swing_ms))
		p._process(.8)
		check_result(kind+"_"+action+"_completion_has_no_replay",s.audit.size()==2 and s.pending.is_empty())
	quiet_reset(p)
	p.perform("attack1")
	p.preview("stay")
	p._process(.5)
	check_result(kind+"_preview_cancels_pending_swing",s.audit.size()==1 and s.pending.is_empty())
	quiet_reset(p)
	p.perform("attack1")
	p.free_control()
	p._process(.5)
	check_result(kind+"_escape_cancels_ground_swing",s.audit.size()==1 and s.pending.is_empty())
	quiet_reset(p)
	p.start_jump()
	p._tick_jump(.2,false)
	p.free_control()
	p._tick_jump(1.0,false)
	check_result(kind+"_escape_in_air_keeps_landing_cue",tags(s).count("JUMP_END")==1)
	quiet_reset(p)
	p.perform("attack1")
	root.preview_controls._scrub(2.0)
	check_result(kind+"_frame_seek_cancels_audio",s.pending.is_empty() and p.paused)
	quiet_reset(p)
	p.start_jump()
	p._tick_jump(1.0,false)
	p.attack()
	p._tick_jump(.1,false)
	check_result(kind+"_late_air_attack_does_not_swing_after_touchdown",tags(s).count("R_SM_JUMP_ATK")==1
		and tags(s).count("R_SQUARESWDC")==0 and tags(s).count("JUMP_END")==1)
	p.reset_position()
	check_result(kind+"_reset_clears_timeline",s.pending.is_empty() and is_zero_approx(s.clock_ms))
	if root!=root.get_tree().current_scene:
		s.output_enabled=true
		p.perform("attack1")
		check_result(kind+"_offscreen_scene_is_inaudible",not s.audit.back()["audible"])


func peak(buffer: PackedVector2Array) -> float:
	var value: float=0.0
	for sample: Vector2 in buffer:
		value=maxf(value,maxf(absf(sample.x),absf(sample.y)))
	return value


func mixer(root: Node) -> void:
	var tree: SceneTree=root.get_tree()
	var p: Node=root.player
	var s: Node=p.action_audio
	quiet_reset(p)
	s.output_enabled=true
	tree.set_meta("port_audio_muted",false)
	tree.set_meta("port_audio_volume",.6)
	s.apply_preferences()
	var bus_index: int=AudioServer.bus_count
	AudioServer.add_bus(bus_index)
	AudioServer.set_bus_name(bus_index,"R1AudioCheck")
	# Capture is before the bus fader. Tests exercise decoding without a loud audition.
	AudioServer.set_bus_volume_db(bus_index,-80.0)
	var effect:=AudioEffectCapture.new()
	effect.buffer_length=1.0
	AudioServer.add_bus_effect(bus_index,effect)
	for voice: AudioStreamPlayer in s.voices:
		voice.bus="R1AudioCheck"
	for tag: String in s.streams:
		var voice: AudioStreamPlayer=s.voices[0]
		effect.clear_buffer()
		voice.stream=s.streams[tag]
		voice.play()
		await tree.create_timer(voice.stream.get_length()+.06).timeout
		var samples: PackedVector2Array=effect.get_buffer(effect.get_frames_available())
		var value: float=peak(samples)
		captures.append({"tag":tag,"peak":value,"frames":samples.size(),"length":voice.stream.get_length()})
		check_result("mixer_decodes_"+tag,value>.001 and not voice.stream.loop,{"peak":value,"frames":samples.size()})
	var voice: AudioStreamPlayer=s.voices[0]
	voice.stream=s.streams["SM_JUMP_ATK_02"]
	voice.play()
	await tree.create_timer(.06).timeout
	p.paused=true
	await tree.create_timer(.06).timeout
	effect.clear_buffer()
	await tree.create_timer(.1).timeout
	var paused_peak: float=peak(effect.get_buffer(effect.get_frames_available()))
	check_result("mixer_pause_is_silent",paused_peak<.00001,{"peak":paused_peak})
	p.paused=false
	effect.clear_buffer()
	await tree.create_timer(.12).timeout
	var resumed_peak: float=peak(effect.get_buffer(effect.get_frames_available()))
	check_result("mixer_resumes_existing_voice",resumed_peak>.001,{"peak":resumed_peak})
	root.preview_controls._select_audio(0)
	check_result("mute_stops_existing_voices",s.voices.all(func(v: AudioStreamPlayer): return not v.playing))
	p.perform("attack1")
	p._process(.2)
	check_result("muted_actions_consume_cues_without_playing",s.audit.size()==2
		and s.audit.all(func(c: Dictionary): return not c["audible"]))
	root.preview_controls.toggle_audio()
	check_result("unmute_does_not_replay_consumed_cues",s.voices.all(func(v: AudioStreamPlayer): return not v.playing)
		and s.pending.is_empty())
	for index: int in [1,2,3]:
		root.preview_controls._select_audio(index)
		check_result("volume_preset_"+str(index),is_equal_approx(db_to_linear(s.voices[0].volume_db),[0.0,.3,.6,1.0][index]))
	s.stop()
	for v: AudioStreamPlayer in s.voices:
		v.bus="Master"
	AudioServer.remove_bus(bus_index)


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var original_volume: float=float(tree.get_meta("port_audio_volume",.6))
	var original_mute: bool=tree.get_meta("port_audio_muted",false)
	functional(root,"R1")
	var clone: Node=load("res://scenes/west_coast_r0.tscn").instantiate()
	tree.root.add_child(clone)
	functional(clone,"R0")
	clone.queue_free()
	await tree.process_frame
	quiet_reset(root.player)
	root.player.perform("attack1")
	root.player._process(.05)
	root._set_paused(true)
	var expected: Dictionary=root.player.capture_state()["audio"]
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	root.player.set_process(false)
	root.player.set_physics_process(false)
	root.player.action_audio.output_enabled=false
	check_result("F4_r1_to_r0_transfers_pending_audio_once",root.player.capture_state()["audio"]==expected
		and root.player.action_audio.audit.is_empty())
	root._switch_comparison()
	await tree.scene_changed
	root=tree.current_scene
	quiet_reset(root.player)
	# Restore the captured timeline without restarting the already consumed voice.
	var state: Dictionary=tree.get_meta("port_compare_state")
	root.player.restore_state(state)
	check_result("F4_r0_to_r1_transfers_audio_clock",root.player.capture_state()["audio"]==expected
		and root.player.action_audio.audit.is_empty())
	root.player.paused=false
	root.player._process(.1)
	check_result("F4_only_future_swing_plays",tags(root.player.action_audio)==["R_SQUARESWDA"])
	var menu: Control=root.get_node("Interface/AudioMenu")
	var compare: Control=root.get_node("Interface/Compare")
	check_result("audio_menu_fits_header",menu.get_rect().end.x<compare.get_rect().position.x
		and menu.get_rect().position.x>200.0,{"rect":str(menu.get_rect())})
	await mixer(root)
	tree.set_meta("port_audio_volume",original_volume)
	tree.set_meta("port_audio_muted",original_mute)
	root.player.action_audio.apply_preferences()
	root.player.action_audio.output_enabled=true
	root.player.reset_position()
	root.player.set_process(true)
	root.player.set_physics_process(true)
	root._set_paused(false)
	root.preview_controls.sync()
	var failed: Array=checks.filter(func(c: Dictionary): return not c["pass"])
	var report: Dictionary={"candidate":"R1/07","checks":checks,"failed":failed,"mixer_captures":captures,
		"mix_rate":AudioServer.get_mix_rate(),"source_script_sha256":get_script().source_code.sha256_text(),
		"note":"Real Godot mixer capture; audio QA bus fader -80 dB. Speaker hardware/listening not certified."}
	var output:=FileAccess.open("res://docs/r1_07_audio_checks.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	return {"checks":checks.size(),"failed":failed,"mixer_files":captures.size()}
