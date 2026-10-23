extends RefCounted
## Existing-door approach: actual keys, imported floor and visible source poses.

var checks: Array=[]
var render_cases: Array=[]
var routes: Array=[]


func check_result(label: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":label,"pass":passed,"details":details})


func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)


func point(main: Node) -> Vector2:
	return main.player.world_to_source(main.player.position) if main.name=="WestCoastR1" else main.player.position


func place(main: Node,value: Vector2) -> void:
	main.player.reset_position()
	main.player.free_control()
	main.player.position=main.player.source_to_world(value) if main.name=="WestCoastR1" else value
	main._set_paused(false)


func allowed(value: Vector2) -> bool:
	# Desired source-ground regions, independently checked against actual input.
	return (value.x>=35.99 and value.x<=378.01 and value.y>=244.99 and value.y<=345.01) or (value.x>=35.99 and value.x<=852.01 and value.y>=284.99 and value.y<=345.01) or (value.x>=43.99 and value.x<=112.01 and value.y>=215.99 and value.y<=245.01)


func travel(main: Node,codes: Array,seconds: float,label: String) -> Dictionary:
	var tree: SceneTree=main.get_tree()
	var start: Vector2=point(main)
	var points: Array=[]
	for code: Key in codes:key(code,true)
	var started: int=Time.get_ticks_usec()
	var maximum_step: float=0.0
	var previous: Vector2=start
	var all_valid: bool=true
	while float(Time.get_ticks_usec()-started)/1000000.0<seconds:
		await tree.physics_frame
		var current: Vector2=point(main)
		points.append(current)
		maximum_step=maxf(maximum_step,previous.distance_to(current))
		all_valid=all_valid and allowed(current)
		previous=current
	for code: Key in codes:key(code,false)
	await tree.physics_frame
	var result: Dictionary={"label":label,"scene":str(main.name),"start":start,"end":point(main),"samples":points.size(),"all_points_in_walk_area":all_valid,"maximum_step_pixels":maximum_step}
	routes.append(result)
	return result


func cover_floor(main: Node) -> void:
	var bed: MeshInstance3D=main.world.get_node("PortArchitecture").find_child("Mortar_Bed_Shore_Polygon",true,false)
	var faces: PackedVector3Array=bed.mesh.get_faces()
	var triangles: Array=[]
	for i: int in range(0,faces.size(),3):
		var a: Vector3=bed.global_transform*faces[i]
		var b: Vector3=bed.global_transform*faces[i+1]
		var c: Vector3=bed.global_transform*faces[i+2]
		if a.y>-.1 and b.y>-.1 and c.y>-.1:triangles.append([a,b,c])
	var tested: int=0
	var uncovered: Array=[]
	for x: int in range(44,113,2):
		for y: int in range(216,245,2):
			var foot: Vector3=main.player.source_to_world(Vector2(x,y))
			var supported: bool=false
			for t: Array in triangles:
				if Geometry3D.segment_intersects_triangle(foot+Vector3.UP,foot-Vector3.UP,t[0],t[1],t[2])!=null:
					supported=true
					break
			tested+=1
			if not supported:uncovered.append([x,y])
	check_result("loaded_ground_supports_all_door_approach_grid_points",tested==525 and uncovered.is_empty(),{"points":tested,"grid_pixels":2,"uncovered":uncovered})
	var retained: int=0
	var clipped: int=0
	var retained_uncovered: Array=[]
	var walk=load("res://scripts/demo_walk_area.gd")
	for x: int in range(36,853,2):
		for y: int in range(245,346,2):
			if x>378 and y<285:continue
			var p:=Vector2(x,y)
			retained+=1
			if walk.constrain(p,p).distance_to(p)>.001:clipped+=1
			var foot: Vector3=main.player.source_to_world(p)
			var supported: bool=false
			for t: Array in triangles:
				if Geometry3D.segment_intersects_triangle(foot+Vector3.UP,foot-Vector3.UP,t[0],t[1],t[2])!=null:supported=true;break
			if not supported:retained_uncovered.append(p)
	check_result("original_street_grid_remains_walkable_and_grounded",retained==16119 and clipped==0 and retained_uncovered.is_empty(),{"points":retained,"clipped":clipped,"uncovered":retained_uncovered})


func render_pose(main: Node,scale: int,facing: int,jumping: bool) -> void:
	main.set_render_scale(scale)
	place(main,Vector2(73,216))
	main.player.facing=facing
	if jumping:
		main.player.start_jump()
		main.player._tick_jump(.55,false)
	main._set_paused(true)
	main.player._update_sprite_transform()
	for _i: int in 2:await RenderingServer.frame_post_draw
	var image: Image=main.render_viewport.get_texture().get_image()
	var source:=Image.new()
	source.load_png_from_buffer(FileAccess.get_file_as_bytes(main.player.current_frame().texture))
	var foot: Vector2=main.world.get_node("Camera").unproject_position(main.player.position+Vector3.UP*main.player.height_above_ground)
	var tested: int=0
	var matching: int=0
	var clipped: int=0
	for y: int in range(1,source.get_height()-1,3):
		for x: int in range(1,source.get_width()-1,3):
			var opaque: bool=true
			for d: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:opaque=opaque and source.get_pixel(x+d.x,y+d.y).a>.999
			if not opaque:continue
			var offset:=Vector2((x+.5-main.player._foot_anchor.x)*facing,y+.5-main.player._foot_anchor.y)
			var target:=Vector2i(foot+offset*scale)
			if not Rect2i(Vector2i.ZERO,image.get_size()).has_point(target):clipped+=1;continue
			var a: Color=image.get_pixelv(target)
			var b: Color=source.get_pixel(x,y)
			tested+=1
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))<.5/255.0:matching+=1
	var result: Dictionary={"scale":scale,"facing":facing,"jumping":jumping,"samples":tested,"matching":matching,"clipped":clipped,"height_pixels":main.player.jump_motion.height_pixels}
	render_cases.append(result)
	check_result("door_front_pose_%dx_%d_%s"%[scale,facing,str(jumping)],tested>250 and tested==matching and clipped==0,result)


func jump_route(main: Node,label: String) -> void:
	place(main,Vector2(73,222))
	key(KEY_W,true)
	key(KEY_SPACE,true)
	await main.get_tree().physics_frame
	key(KEY_SPACE,false)
	var highest: float=0.0
	var minimum: float=INF
	var started: int=Time.get_ticks_usec()
	while float(Time.get_ticks_usec()-started)/1000000.0<1.35:
		await main.get_tree().physics_frame
		highest=maxf(highest,main.player.jump_motion.height_pixels)
		minimum=minf(minimum,point(main).y)
	key(KEY_W,false)
	await main.get_tree().physics_frame
	check_result(label+"_jump_respects_door_foot_boundary",highest>100 and minimum>=215.99 and not main.player.jump_motion.is_active() and absf(point(main).y-216)<.05,{"height_pixels":highest,"minimum_ground_y":minimum,"landed":point(main)})


func run(main: Node) -> Dictionary:
	var tree: SceneTree=main.get_tree()
	var original: Dictionary=main.player.capture_state()
	var original_scale: int=main.render_scale
	var original_water: Dictionary=main.water.capture_state()
	cover_floor(main)
	place(main,Vector2(73,300))
	var route: Dictionary=await travel(main,[KEY_W],2.0,"R1_walk_to_door")
	check_result("R1_real_w_key_reaches_door_front",absf(route.end.y-216)<.05 and absf(route.end.x-73)<.05 and route.all_points_in_walk_area,route)
	var threshold: MeshInstance3D=main.world.get_node("PortArchitecture").find_child("Blue_Gate_Threshold",true,false)
	var front: float=main.player.world_to_source((threshold.global_transform*threshold.get_aabb()).end).y
	check_result("logical_foot_stops_in_front_of_threshold",point(main).y-front>1 and point(main).y-front<3,{"foot_y":point(main).y,"threshold_front_y":front})
	main.get_viewport().get_texture().get_image().save_png("res://docs/previews/r1_18_door_walk.png")
	place(main,Vector2(73,230))
	route=await travel(main,[KEY_D],.65,"door_right_side")
	check_result("door_right_side_slides_without_downward_snap",absf(route.end.x-112)<.05 and absf(route.end.y-230)<.05 and route.all_points_in_walk_area,route)
	place(main,Vector2(73,230))
	route=await travel(main,[KEY_A],.65,"door_left_side")
	check_result("door_left_side_slides_without_downward_snap",absf(route.end.x-44)<.05 and absf(route.end.y-230)<.05 and route.all_points_in_walk_area,route)
	place(main,Vector2(112,230))
	route=await travel(main,[KEY_D,KEY_S],1.0,"leave_door_diagonally")
	check_result("diagonal_exit_reopens_existing_street",route.end.x>130 and route.end.y>245 and route.all_points_in_walk_area and route.maximum_step_pixels<4,route)
	place(main,Vector2(73,216))
	var down: Dictionary=await travel(main,[KEY_S],1.65,"return_from_door_down")
	var across: Dictionary=await travel(main,[KEY_D],1.4,"return_to_front_street")
	check_result("actual_keys_return_from_door_to_front_street",across.end.y>300 and across.end.x>180 and down.all_points_in_walk_area and across.all_points_in_walk_area,{"down":down,"across":across})
	place(main,Vector2(125,260))
	route=await travel(main,[KEY_W],.8,"outside_door_corridor")
	check_result("upper_street_stays_closed_beside_door",absf(route.end.y-245)<.05 and absf(route.end.x-125)<.05,route)
	await jump_route(main,"R1")
	for scale: int in [1,2]:
		for facing: int in [1,-1]:
			for jumping: bool in [false,true]:await render_pose(main,scale,facing,jumping)
	place(main,Vector2(73,216))
	main.set_render_scale(original_scale)
	main._switch_comparison()
	await tree.scene_changed
	main=tree.current_scene
	check_result("F4_retains_door_position_in_R0",main.name=="WestCoastR0" and point(main).distance_to(Vector2(73,216))<.05)
	place(main,Vector2(73,300))
	route=await travel(main,[KEY_W],2.0,"R0_walk_to_door")
	check_result("R0_real_w_key_matches_door_limit",absf(route.end.y-216)<.05 and absf(route.end.x-73)<.05 and route.all_points_in_walk_area,route)
	await jump_route(main,"R0")
	main._switch_comparison()
	await tree.scene_changed
	main=tree.current_scene
	check_result("F4_returns_to_same_door_foot",main.name=="WestCoastR1" and point(main).distance_to(Vector2(73,216))<.05)
	main.set_render_scale(original_scale)
	main.player.restore_state(original)
	main.water.restore_state(original_water)
	main._set_paused(original.paused)
	for code: Key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SPACE]:key(code,false)
	var failed: Array=checks.filter(func(c: Dictionary):return not c.pass)
	var report: Dictionary={"candidate":"R1/18","checks":checks,"failed":failed,"routes":routes,"render_cases":render_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),"walk_script_sha256":FileAccess.get_sha256("res://scripts/demo_walk_area.gd"),
		"note":"Actual physical-key events and physics, actual imported floor triangles and native pose RGB. The added approach is an adaptation inside existing geometry."}
	var out:=FileAccess.open("res://docs/r1_18_door_approach_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases}
