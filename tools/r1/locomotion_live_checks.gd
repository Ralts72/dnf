extends Node
## Finite actual-input locomotion through the production texture selector.

var status: String="new"
var main: Node
var action: String="move"
const STUDIES: Dictionary={"move":"res://source_art/r1/experiments/walk_cycle_24","dash":"res://source_art/r1/experiments/dash_cycle_26"}
var original: Dictionary
var images: Dictionary={}
var original_texture: Texture2D
var selection_failures: Array=[]
var sampler: RefCounted
var started_usec: int=0
var direction_segment: int=-1
var current_key: int=-1
var selected_key: String=""
var selected_phase: int=-1
var records: Array=[]
var spot_checks: Array=[]
var checked_poses: Dictionary={}
var first_source_transitions: int=0
var move_frames: int=0
var interpolation_frames: int=0
var drawn_frames: int=0
var x_min: float=INF
var x_max: float=-INF
var report: Dictionary={}


func key(code: int,pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()


func start(root: Node,clip_name: String="move") -> Dictionary:
	action=clip_name
	assert(action in STUDIES)
	main=root;original=main.player.capture_state();original_texture=main.player.sprite.texture
	main._set_paused(false);main.player.reset_position()
	main.player.position=main.player.source_to_world(Vector2(440,295));main.player.motion_smoothing.reset()
	key(KEY_SHIFT,action=="dash")
	for frame: int in 8:
		for sub: int in 3:
			var id: String="%d_%d"%[frame,sub]
			var path: String=STUDIES[action]+"/baked/"+action+"_%02d_%d.png"%[frame,sub]
			var image:=Image.new();image.load_png_from_buffer(FileAccess.get_file_as_bytes(path));images[id]=image
			
	sampler=load("res://tools/r1/pose_checks.gd").new()
	first_source_transitions=main.player.frame_transitions
	process_priority=1000000
	RenderingServer.frame_post_draw.connect(_drawn)
	started_usec=Time.get_ticks_usec();status="sampling"
	return snapshot()


func _process(_delta: float) -> void:
	if status!="sampling":return
	var elapsed: float=float(Time.get_ticks_usec()-started_usec)/1000000.0
	if elapsed>=6.4:
		finish()
		return
	var segment: int=int(elapsed/1.6)
	if segment!=direction_segment:
		if current_key>=0:key(current_key,false)
		current_key=KEY_D if segment%2==0 else KEY_A
		key(current_key,true);direction_segment=segment
	var p: Node=main.player
	if p.animation_name!=action:return
	var sub: int=p.walk_inbetweens.subframe
	var id: String="%d_%d"%[p.frame_index,sub]
	var expected_path: String=p.current_frame().texture if sub==0 else p.walk_inbetweens.clips[action].frames[p.frame_index].intermediates[sub-1]
	if not p.walk_inbetweens.active or p.sprite.texture.resource_path!=expected_path or p.source_material.get_shader_parameter("source_texture")!=p.sprite.texture:
		selection_failures.append({"frame":p.frame_index,"subframe":sub,"actual":p.sprite.texture.resource_path,"expected":expected_path})
	selected_key=id;selected_phase=p.frame_index*3+sub


func _drawn() -> void:
	if status!="sampling" or selected_key.is_empty():return
	var p: Node=main.player
	if p.animation_name!=action:return
	var elapsed: float=float(Time.get_ticks_usec()-started_usec)/1000000.0
	drawn_frames+=1;move_frames+=1
	if p.is_physics_interpolated_and_enabled():interpolation_frames+=1
	var position: Vector2=p.world_to_source(p.position)
	x_min=minf(x_min,position.x);x_max=maxf(x_max,position.x)
	if records.is_empty() or records[-1].phase!=selected_phase:
		records.append({"elapsed_s":elapsed,"phase":selected_phase,"facing":p.facing,"source_x":position.x})
	var spot_key: String="%d:%d"%[p.facing,selected_phase]
	if selected_phase%3>0 and not checked_poses.has(spot_key):
		checked_poses[spot_key]=true
		var actual: Image=main.render_viewport.get_texture().get_image()
		var source: Image=images[selected_key]
		var foot: Vector2=main.world.get_node("Camera").unproject_position(p.get_global_transform_interpolated().origin)/float(main.render_scale)
		var samples: int=0;var mismatches: int=0;var maximum: float=0
		for y: int in range(1,223,8):
			for x: int in range(1,319,8):
				var pixel:=Vector2i(x,y)
				if not sampler.opaque_interior(source,pixel):continue
				var offset: Vector2=Vector2(x+.5,y+.5)-Vector2(133,167);offset.x*=p.facing
				var target:=Vector2i((foot+offset)*main.render_scale)
				var difference: float=sampler.color_distance(source.get_pixelv(pixel),actual.get_pixelv(target))
				samples+=1;maximum=maxf(maximum,difference)
				if difference>.025:mismatches+=1
		spot_checks.append({"elapsed_s":elapsed,"phase":selected_phase,"facing":p.facing,"samples":samples,"mismatches":mismatches,"max_rgb_distance":maximum,
			"interpolated_foot":foot,"logical_ground":position})
		if selected_phase==17 and p.facing==-1:main.get_viewport().get_texture().get_image().save_png("res://docs/previews/r1_27_live_"+action+".png")


func finish() -> void:
	status="finishing";set_process(false)
	if current_key>=0:key(current_key,false)
	key(KEY_SHIFT,false)
	RenderingServer.frame_post_draw.disconnect(_drawn)
	var seen: Dictionary={};var facings: Dictionary={}
	for row: Dictionary in records:seen[row.phase]=true;facings[row.facing]=true
	var checks: Array=[{"check":"all24_phases_during_actual_locomotion","pass":seen.size()==24},
		{"check":"actual_direction_keys_move_ground_point","pass":x_max-x_min>(280 if action=="dash" else 140),"source_x_min":x_min,"source_x_max":x_max},
		{"check":"both_facings_observed","pass":facings.size()==2},
		{"check":"native_position_interpolation_stays_on","pass":interpolation_frames==move_frames and move_frames>500,"active_frames":interpolation_frames,"move_frames":move_frames},
		{"check":"GPU_opaque_samples_match_during_native_interpolation","pass":spot_checks.size()==32 and spot_checks.all(func(c):return c.samples>20 and c.mismatches==0),"spot_checks":spot_checks.size()},
		{"check":"source_frame_clock_keeps_advancing","pass":main.player.frame_transitions-first_source_transitions>=60}]
	main.player.restore_state(original);main._set_paused(original.paused)
	checks.append({"check":"source_texture_restored_after_preview","pass":main.player.sprite.texture==original_texture})
	checks.append({"check":"production_sampler_selects_every_locomotion_texture","pass":selection_failures.is_empty(),"failures":selection_failures})
	report={"study":"R1/27 finite real-input locomotion with derived lower-body samples","action":action,"checks":checks,"failed":checks.filter(func(c):return not c.pass),
		"records":records,"spot_checks":spot_checks,"duration_s":6.4,"qa_source_sha256":get_script().source_code.sha256_text(),
		"note":"Real D/A keys (plus Shift for dash), production actor physics/animation clocks. Initial placement at(440,295) prevents viewport clipping; no position writes after start. Production walk sampler selects all textures; QA does not bind or substitute a display texture. GPU sample positions use Godot's actual interpolated global transform."}
	var output:=FileAccess.open("res://docs/r1_27_"+action+"_live_r1_checks.json",FileAccess.WRITE);output.store_string(JSON.stringify(report,"  "));output.close()
	status="complete"


func snapshot() -> Dictionary:
	return {"status":status,"drawn_frames":drawn_frames,"phase_changes":records.size(),"spot_checks":spot_checks.size(),"failed":report.get("failed",[])}
