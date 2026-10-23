extends Node
## Finite actual-input walking with the experimental textures, not a pose clone.

var status: String="new"
var main: Node
var original: Dictionary
var images: Dictionary={}
var textures: Dictionary={}
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


func start(root: Node) -> Dictionary:
	main=root;original=main.player.capture_state()
	main._set_paused(false);main.player.reset_position()
	for frame: int in 8:
		for sub: int in 3:
			var id: String="%d_%d"%[frame,sub]
			var path: String="res://source_art/r1/experiments/walk_cycle_24/baked/move_%02d_%d.png"%[frame,sub]
			var image:=Image.new();image.load_png_from_buffer(FileAccess.get_file_as_bytes(path));images[id]=image
			textures[id]=ImageTexture.create_from_image(image)
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
	if p.animation_name!="move":return
	var sub: int=mini(2,int(floor(p.elapsed_ms*.03+.0001)))
	var id: String="%d_%d"%[p.frame_index,sub]
	var texture: Texture2D=textures[id] if sub>0 else p._textures[p.current_frame().texture]
	if p.sprite.texture!=texture:
		p.sprite.texture=texture;p.source_material.set_shader_parameter("source_texture",texture)
	selected_key=id;selected_phase=p.frame_index*3+sub


func _drawn() -> void:
	if status!="sampling" or selected_key.is_empty():return
	var p: Node=main.player
	if p.animation_name!="move":return
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
		if selected_phase==17 and p.facing==-1:main.get_viewport().get_texture().get_image().save_png("res://docs/previews/r1_24_live_walk.png")


func finish() -> void:
	status="finishing";set_process(false)
	if current_key>=0:key(current_key,false)
	RenderingServer.frame_post_draw.disconnect(_drawn)
	var seen: Dictionary={};var facings: Dictionary={}
	for row: Dictionary in records:seen[row.phase]=true;facings[row.facing]=true
	var checks: Array=[{"check":"all24_phases_during_actual_walk","pass":seen.size()==24},
		{"check":"actual_direction_keys_move_ground_point","pass":x_max-x_min>140,"source_x_min":x_min,"source_x_max":x_max},
		{"check":"both_facings_observed","pass":facings.size()==2},
		{"check":"native_position_interpolation_stays_on","pass":interpolation_frames==move_frames and move_frames>500,"active_frames":interpolation_frames,"move_frames":move_frames},
		{"check":"GPU_opaque_samples_match_during_native_interpolation","pass":spot_checks.size()==32 and spot_checks.all(func(c):return c.samples>20 and c.mismatches==0),"spot_checks":spot_checks.size()},
		{"check":"source_frame_clock_keeps_advancing","pass":main.player.frame_transitions-first_source_transitions>=60}]
	main.player.restore_state(original);main._set_paused(original.paused)
	checks.append({"check":"source_texture_restored_after_preview","pass":main.player.sprite.texture==main.player._textures[main.player.current_frame().texture]})
	report={"study":"R1/24 finite real-input walk with derived lower-body samples","checks":checks,"failed":checks.filter(func(c):return not c.pass),
		"records":records,"spot_checks":spot_checks,"duration_s":6.4,"qa_source_sha256":get_script().source_code.sha256_text(),
		"note":"Real D/A keys and production actor physics/animation clocks. Only source_texture is transiently substituted. GPU sample positions use Godot's actual interpolated global transform."}
	var output:=FileAccess.open("res://docs/r1_24_live_r1_checks.json",FileAccess.WRITE);output.store_string(JSON.stringify(report,"  "));output.close()
	status="complete"


func snapshot() -> Dictionary:
	return {"status":status,"drawn_frames":drawn_frames,"phase_changes":records.size(),"spot_checks":spot_checks.size(),"failed":report.get("failed",[])}
