extends RefCounted
## Loaded prop geometry, ship projection and upright character depth tests.

var checks: Array=[]
var render_cases: Array=[]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func rgb_distance(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))


func actor_case(root: Node,scale: int,facing: int,action: String,frame: int,behind: bool=false) -> void:
	root.set_render_scale(scale)
	var p: Node=root.player
	p.reset_position()
	p.preview(action)
	p.position=p.source_to_world(Vector2(653,250 if behind else 285))
	p.facing=facing
	p.frame_index=frame
	p._apply_frame()
	p._update_sprite_transform()
	root._set_paused(true)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image=root.render_viewport.get_texture().get_image()
	var hidden: Image
	var dock: Array=root.world.get_node("PortArchitecture").find_children("Dock_*","MeshInstance3D",true,false)
	if behind:
		for node: MeshInstance3D in dock:node.visible=false
		await RenderingServer.frame_post_draw
		hidden=root.render_viewport.get_texture().get_image()
		for node: MeshInstance3D in dock:node.visible=true
	var source:=Image.new()
	source.load_png_from_buffer(FileAccess.get_file_as_bytes(p.current_frame()["texture"]))
	var foot: Vector2=root.world.get_node("Camera").unproject_position(p.position)
	var tested: int=0
	var matching: int=0
	var blocked_by_dock: int=0
	for y: int in range(1,source.get_height()-1,3):
		for x: int in range(1,source.get_width()-1,3):
			var opaque: bool=true
			for d: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				opaque=opaque and source.get_pixel(x+d.x,y+d.y).a>.999
			if not opaque:continue
			var offset:=Vector2((x+.5-p._foot_anchor.x)*facing,y+.5-p._foot_anchor.y)
			var target:=Vector2i(foot+offset*scale)
			var expected: Color=source.get_pixel(x,y)
			var matches: bool=rgb_distance(image.get_pixelv(target),expected)<.5/255.0
			tested+=1
			if matches:matching+=1
			if behind and not matches and rgb_distance(hidden.get_pixelv(target),expected)<.5/255.0:
				blocked_by_dock+=1
	var label: String="behind" if behind else "front"
	var result: Dictionary={"side":label,"scale":scale,"facing":facing,"action":action,"frame":frame,
		"samples":tested,"matching":matching,"blocked_by_dock":blocked_by_dock}
	render_cases.append(result)
	check_result("actor_%s_%s_%dx_%d"%[label,action,scale,facing],
		tested>250 and (blocked_by_dock>20 if behind else matching==tested),result)
	image.save_png("res://docs/previews/r1_18_actor_%s_%s_%dx_%d.png"%[label,action,scale,facing])


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var original: Dictionary=root.player.capture_state()
	var original_scale: int=root.render_scale
	root.player.reset_position()
	root._set_paused(true)
	var architecture: Node=root.world.get_node("PortArchitecture")
	var dock: Array=architecture.find_children("Dock_*","MeshInstance3D",true,false)
	check_result("seventeen_native_dock_meshes",dock.size()==17,{"meshes":dock.size()})
	for item: Dictionary in [{"name":"Dock_Mooring_Core","width":13.0,"height":9.0},{"name":"Dock_Mooring_Limestone_Cap","width":28.0,"height":7.0}]:
		var obj: MeshInstance3D=architecture.find_child(item.name,true,false)
		var arrays: Array=obj.mesh.surface_get_arrays(0)
		var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		var projection: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
		check_result(item.name+"_uses_projected_uv",uv==projection and uv.size()>0)
		var minimum:=Vector2(INF,INF)
		var maximum:=Vector2(-INF,-INF)
		for value: Vector2 in uv:
			minimum=minimum.min(value)
			maximum=maximum.max(value)
		var span: Vector2=maximum-minimum
		var world_bounds: AABB=obj.global_transform*obj.get_aabb()
		var actual_pixels:=Vector2(span.x*item.width,span.y*item.height)
		var expected_pixels:=Vector2(world_bounds.size.x*60,world_bounds.size.y*60*cos(deg_to_rad(38)))
		check_result(item.name+"_texture_density_matches_scaled_volume",actual_pixels.distance_to(expected_pixels)<.02,
			{"uv_pixels":actual_pixels,"world_size_pixels":expected_pixels})
	for name: String in ["Left","Right","Upper"]:
		var body: MeshInstance3D=architecture.find_child("Dock_Barrel_"+name+"_Body",true,false)
		var box: AABB=body.global_transform*body.get_aabb()
		check_result("barrel_volume_"+name,box.size.y>.5 and box.size.x>.35 and box.size.z>.22,{"bounds":box})
		check_result("three_native_hoops_"+name,architecture.find_children("Dock_Barrel_"+name+"_Hoop_*","MeshInstance3D",true,false).size()==3)
	var left: MeshInstance3D=architecture.find_child("Dock_Barrel_Left_Body",true,false)
	var upper: MeshInstance3D=architecture.find_child("Dock_Barrel_Upper_Body",true,false)
	var left_box: AABB=left.global_transform*left.get_aabb()
	var upper_box: AABB=upper.global_transform*upper.get_aabb()
	check_result("upper_barrel_supported_by_lower_stack",absf(upper_box.position.y-left_box.end.y)<.001)
	var core: MeshInstance3D=architecture.find_child("Dock_Mooring_Core",true,false)
	var cap: MeshInstance3D=architecture.find_child("Dock_Mooring_Limestone_Cap",true,false)
	var core_box: AABB=core.global_transform*core.get_aabb()
	var cap_box: AABB=cap.global_transform*cap.get_aabb()
	check_result("mooring_core_contacts_ground_and_cap",absf(core_box.position.y-.025)<.001
		and absf(core_box.end.y-cap_box.position.y)<.001)
	check_result("coil_and_loose_tail_have_native_geometry",architecture.find_child("Dock_Rope_Coil",true,false).mesh.get_faces().size()>1000
		and architecture.find_child("Dock_Rope_Tail",true,false).mesh.get_faces().size()>100)
	var filters: bool=true
	for node: MeshInstance3D in dock:
		for i: int in node.mesh.get_surface_count():
			var mat: StandardMaterial3D=node.mesh.surface_get_material(i)
			if mat.albedo_texture:
				filters=filters and mat.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST
	check_result("dock_textures_use_nearest_sampling",filters)
	var ship: Node=root.world.get_node("SourceProps/westnearship")
	var ship_frame: int=ship.frame_index
	var ship_elapsed: float=ship.elapsed_ms
	var depth: float=ship.view_depth_offset
	var camera: Camera3D=root.world.get_node("Camera")
	var expected_anchor: Vector2=ship.source_anchor+Vector2(0,43)
	var projection_error: float=(camera.unproject_position(ship.global_position)/root.render_scale).distance_to(expected_anchor)
	check_result("ship_depth_preserves_source_anchor",projection_error<.02,{"pixel_error":projection_error,"depth":depth})
	var port: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/port_r0.json"))
	var original_ship: Dictionary=port["objects"].filter(func(o: Dictionary):return o["name"]=="westnearship")[0]
	var source_frames: Array=original_ship["sequence"]["frames"]
	var timing: bool=ship.frames.size()==8
	var maximum: float=0.0
	for i: int in ship.frames.size():
		ship.frame_index=i;ship.elapsed_ms=0.0;ship._apply_frame()
		var offset: Array=source_frames[i]["layers"][0]["offset"]
		var expected_center: Vector2=expected_anchor+Vector2(offset[0],offset[1])+ship.image_size/2.0
		maximum=maxf(maximum,(camera.unproject_position(ship.get_node("Sprite").global_position)/root.render_scale).distance_to(expected_center))
		ship.paused=false
		ship._process(float(source_frames[i]["duration_ms"])/1000.0+.000001)
		ship.paused=true
		timing=timing and ship.frame_index==(i+1)%ship.frames.size() and ship.elapsed_ms<.01
	check_result("all_eight_ship_frame_projections_retained",maximum<.02,{"maximum_pixel_error":maximum})
	check_result("all_eight_source_ship_durations_retained",timing)
	ship.frame_index=0;ship.elapsed_ms=0.0;ship._apply_frame()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var with_ship: Image=root.render_viewport.get_texture().get_image()
	var raw:=Image.new()
	raw.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/r0/port/westnearship/image/000.png"))
	var ship_samples: int=0
	var ship_matching: int=0
	var origin: Vector2=expected_anchor+Vector2(ship.frames[0]["offset"][0],ship.frames[0]["offset"][1])
	for y: int in range(1,raw.get_height()-1,5):
		for x: int in range(1,raw.get_width()-1,5):
			var screen: Vector2=origin+Vector2(x+.5,y+.5)
			if screen.x<700 or screen.x>895 or screen.y<103 or screen.y>253:continue
			var opaque: bool=true
			for d: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				opaque=opaque and raw.get_pixel(x+d.x,y+d.y).a>.999
			if not opaque:continue
			ship_samples+=1
			if rgb_distance(with_ship.get_pixelv(Vector2i(screen*root.render_scale)),raw.get_pixel(x,y))<.5/255.0:ship_matching+=1
	check_result("visible_ship_interiors_keep_source_rgb",ship_samples>150 and ship_matching==ship_samples,{"samples":ship_samples,"matching":ship_matching})
	ship.visible=false
	await RenderingServer.frame_post_draw
	var hidden_ship: Image=root.render_viewport.get_texture().get_image()
	ship.visible=true;ship.view_depth_offset=0.0
	await RenderingServer.frame_post_draw
	var old_depth: Image=root.render_viewport.get_texture().get_image()
	ship.view_depth_offset=depth
	var clear: int=0
	var previously_blocked: int=0
	for source_point: Vector2 in [Vector2(702,258),Vector2(704,252),Vector2(707,257)]:
		var pixel:=Vector2i((source_point+Vector2(0,43))*root.render_scale)
		var expected: Color=hidden_ship.get_pixelv(pixel)
		if rgb_distance(with_ship.get_pixelv(pixel),expected)<.03:clear+=1
		if rgb_distance(old_depth.get_pixelv(pixel),expected)>.2:previously_blocked+=1
	check_result("rope_tail_is_in_front_of_ship",clear==3 and previously_blocked>=2,{"clear_probes":clear,"blocked_with_original_depth":previously_blocked})
	check_result("player_and_npcs_have_upright_surfaces",[root.player,root.npc_lo,root.npc_sr].all(func(p: Node):
		return p.sprite.rotation.length()<.0001 and absf(p.sprite.scale.y-1.0/cos(p.ELEVATION))<.0001))
	check_result("contact_shadows_below_feet_above_paving",[root.player,root.npc_lo,root.npc_sr].all(func(p: Node):
		return p.get_node("ContactShadow").global_position.y>.012 and p.get_node("ContactShadow").global_position.y<p.global_position.y))
	for scale: int in [1,2]:
		for facing: int in [1,-1]:
			await actor_case(root,scale,facing,"stay",0)
	await actor_case(root,2,1,"attack1",3)
	await actor_case(root,2,-1,"damage1",0)
	await actor_case(root,2,1,"stay",0,true)
	ship.frame_index=ship_frame;ship.elapsed_ms=ship_elapsed;ship._apply_frame()
	ship.view_depth_offset=depth
	root.set_render_scale(original_scale)
	root.player.restore_state(original)
	root._set_paused(original["paused"])
	var failed: Array=checks.filter(func(c: Dictionary):return not c["pass"])
	var report: Dictionary={"candidate":"R1/18","checks":checks,"failed":failed,"render_cases":render_cases,
		"glb_sha256":FileAccess.get_sha256("res://assets/r1/models/west_coast_port.glb"),
		"source_script_sha256":get_script().source_code.sha256_text(),
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"note":"The behind-props pose is a paused renderer fixture outside normal navigation; no new walk area is opened."}
	var file:=FileAccess.open("res://docs/r1_18_mooring_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases}
