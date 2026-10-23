extends RefCounted
## Exhaustive bottom-edge source pixels; both qualities, facings and F5 samples.

var render_cases: Array=[]
var sources: Dictionary={}
var checks: Array=[]
var sampler: RefCounted
var framing: RefCounted

func render_case(main: Node,action: String,frame: int,sub: int,facing: int,scale: int,enabled: bool) -> void:
	var p: Node=main.player
	p.preview(action);p.frame_index=frame;p.elapsed_ms=float(sub)*100.0/3.0;p.facing=facing
	p._apply_frame();p._update_sprite_transform();p.motion_smoothing.reset()
	framing.enabled=enabled;framing.advance(0,true)
	var path: String=p.sprite.texture.resource_path
	if not sources.has(path):
		var source:=Image.new();assert(source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK);sources[path]=source
	var source: Image=sources[path]
	for _i: int in 2:await RenderingServer.frame_post_draw
	var actual: Image=main.render_viewport.get_texture().get_image()
	var foot: Vector2=main.world.get_node("Camera").unproject_position(p.position)/float(scale)
	var clipped_vertical: int=0;var clipped_horizontal: int=0
	var samples: int=0;var mismatches: int=0;var maximum: float=0
	for y: int in source.get_height():
		for x: int in source.get_width():
			if source.get_pixel(x,y).a<.999:continue
			var offset:=Vector2((float(x)+.5-133.0)*facing,float(y)+.5-167.0)
			var target:=Vector2i((foot+offset)*float(scale))
			if target.y<0 or target.y>=actual.get_height():clipped_vertical+=1;continue
			if target.x<0 or target.x>=actual.get_width():clipped_horizontal+=1;continue
			if x%4!=1 or y%4!=1 or x<1 or y<1 or x>=319 or y>=223 or not sampler.opaque_interior(source,Vector2i(x,y)):continue
			var distance: float=sampler.color_distance(source.get_pixel(x,y),actual.get_pixelv(target))
			samples+=1;maximum=maxf(maximum,distance)
			if distance>.025:mismatches+=1
	var row: Dictionary={"action":action,"frame":frame,"subframe":sub,"facing":facing,"scale":scale,"framing":enabled,"offset_y":framing.offset_y,
		"vertical_clipped_source_pixels":clipped_vertical,"horizontal_clipped_source_pixels":clipped_horizontal,"interior_samples":samples,"RGB_mismatches":mismatches,"max_RGB_distance":maximum}
	render_cases.append(row)
	if action=="sit" and facing==1 and scale==2:
		main.get_viewport().get_texture().get_image().save_png("res://docs/previews/r1_28_sit_"+("framed" if enabled else "original")+".png")
	if enabled and (clipped_vertical>0 or mismatches>0):actual.save_png("res://work/r1_28_framing_failure_%s_%d_%d_%d_%d.png"%[action,frame,sub,facing,scale])

func run(main: Node) -> Dictionary:
	var p: Node=main.player;var original: Dictionary=p.capture_state();var scale_before: int=main.render_scale
	var effects_before: bool=p.action_effects.enabled
	main._set_paused(true);p.action_effects.enabled=false
	p.position=p.source_to_world(Vector2(440,345));p.motion_smoothing.reset()
	var script:=GDScript.new();script.source_code=FileAccess.get_file_as_string("res://source_art/r1/experiments/framing_28/framing.gd");assert(script.reload()==OK)
	framing=script.new();framing.setup(main);sampler=load("res://tools/r1/pose_checks.gd").new()
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r1.json"))
	for scale: int in [1,2]:
		main.set_render_scale(scale)
		for action: String in data.animations:
			for frame: int in data.animations[action].frames.size():
				for facing: int in [1,-1]:
					for enabled: bool in [false,true]:await render_case(main,action,frame,0,facing,scale,enabled)
		for action: String in ["move","dash"]:
			for frame: int in 8:
				for sub: int in [1,2]:
					for facing: int in [1,-1]:
						for enabled: bool in [false,true]:await render_case(main,action,frame,sub,facing,scale,enabled)
	var framed: Array=render_cases.filter(func(c):return c.framing)
	var baseline: Array=render_cases.filter(func(c):return not c.framing)
	checks.append({"check":"all496_raw_and_derived_poses_covered_per_mode","pass":framed.size()==496 and baseline.size()==496,"cases_per_mode":framed.size()})
	checks.append({"check":"original_view_reproduces_vertical_clipping","pass":baseline.any(func(c):return c.vertical_clipped_source_pixels>0)})
	checks.append({"check":"framed_view_has_no_vertical_clipping","pass":framed.all(func(c):return c.vertical_clipped_source_pixels==0 and c.horizontal_clipped_source_pixels==0)})
	checks.append({"check":"framed_view_preserves_native_source_RGB","pass":framed.all(func(c):return c.interior_samples>30 and c.RGB_mismatches==0)})
	framing.restore();main.set_render_scale(scale_before);p.action_effects.enabled=effects_before;p.restore_state(original);main._set_paused(original.paused)
	checks.append({"check":"production_actor_restored","pass":p.capture_state()==original and main.render_scale==scale_before})
	var result: Dictionary={"study":"R1/28 bottom-edge framing prototype","production_candidate":"R1/27","source_ground_point":Vector2(440,345),
		"checks":checks,"failed":checks.filter(func(c):return not c.pass),"render_cases":render_cases,"qa_source_sha256":get_script().source_code.sha256_text(),
		"framing_source_sha256":script.source_code.sha256_text(),"note":"Actual R1 framebuffer at the legal street bottom. Camera angle, zoom, actor geometry, clocks and PNGs unchanged. This does not fix or validate horizontal world-edge clipping."}
	var f:=FileAccess.open("res://docs/r1_28_framing_checks.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
	return {"checks":checks.size(),"failed":result.failed,"cases":render_cases.size()}
