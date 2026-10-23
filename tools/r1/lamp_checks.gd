extends RefCounted
## Native lamp volumes/materials and moving source actors in the foreground lane.

var checks: Array=[]
var render_cases: Array=[]
var images: Dictionary={}


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)


func sample_actor(root: Node,route: String,index: int) -> Dictionary:
	var p: Node=root.player
	var path: String=p.current_frame()["texture"]
	if not images.has(path):
		var raw:=Image.new()
		raw.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		images[path]=raw
	var source: Image=images[path]
	var actual: Image=root.render_viewport.get_texture().get_image()
	var foot: Vector2=root.world.get_node("Camera").unproject_position(p.global_position)
	var scale: int=root.render_scale
	var tested: int=0
	var matching: int=0
	var boundary_samples: int=0
	var first: Array=[]
	for y: int in range(2,source.get_height()-2,5):
		for x: int in range(2,source.get_width()-2,5):
			var opaque: bool=true
			for d: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				opaque=opaque and source.get_pixel(x+d.x,y+d.y).a>.999
			if not opaque:continue
			var offset:=Vector2((x+.5-p._foot_anchor.x)*p.facing,y+.5-p._foot_anchor.y-p.jump_motion.height_pixels)
			var center: Vector2=foot+offset*scale
			var point:=Vector2i(center)
			# A sample's raster pixel center must be unambiguously inside its
			# source texel. At exactly half-pixel translations, CPU projection
			# and GPU float rounding can choose adjacent nearest-neighbour texels.
			var margin: float=scale*.5-maxf(absf(point.x+.5-center.x),absf(point.y+.5-center.y))
			if margin<.002:
				boundary_samples+=1
				continue
			var a: Color=actual.get_pixelv(point)
			var b: Color=source.get_pixel(x,y)
			var distance: float=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
			tested+=1
			if distance<.5/255.0:matching+=1
			elif first.size()<3:first.append({"png":[x,y],"screen":point,"actual":a,"source":b})
	var row: Dictionary={"route":route,"index":index,"scale":scale,"action":p.animation_name,
		"frame":p.frame_index,"foot":p.world_to_source(p.position),"height_pixels":p.jump_motion.height_pixels,
		"samples":tested,"matching":matching,"boundary_samples":boundary_samples,"first_failures":first}
	if index==10:actual.save_png("res://docs/previews/r1_11_dynamic_%s_%dx.png"%[route,scale])
	render_cases.append(row)
	return row


func route(root: Node,kind: String) -> void:
	var p: Node=root.player
	p.reset_position()
	p.position=p.source_to_world(Vector2(730 if kind=="dash_left" else 550 if kind=="walk_right" else 600,285))
	root._set_paused(false)
	var direction: Key=KEY_LEFT if kind=="dash_left" else KEY_RIGHT
	key(direction,true)
	if kind=="dash_left":key(KEY_SHIFT,true)
	if kind=="jump_right":key(KEY_SPACE,true)
	var rows: Array=[]
	for tick: int in range(120 if kind!="jump_right" else 95):
		await root.get_tree().physics_frame
		if kind=="jump_right" and tick==18:key(KEY_X,true)
		if kind=="jump_right" and tick==19:key(KEY_X,false)
		if tick%5==4:
			await RenderingServer.frame_post_draw
			rows.append(sample_actor(root,kind,rows.size()))
	key(direction,false);key(KEY_SHIFT,false);key(KEY_SPACE,false);key(KEY_X,false)
	root._set_paused(true)
	var compared: Array=rows.filter(func(row: Dictionary):return row.samples>0)
	var failures: Array=compared.filter(func(row: Dictionary):return row.samples!=row.matching or row.samples<40)
	check_result("moving_foreground_%s_%dx"%[kind,root.render_scale],failures.is_empty() and compared.size()>=rows.size()/2,
		{"rendered_frames":rows.size(),"samples":rows.reduce(func(n: int,row: Dictionary):return n+int(row.samples),0),
		"matching":rows.reduce(func(n: int,row: Dictionary):return n+int(row.matching),0),
		"unambiguous_frames":compared.size(),"boundary_frames":rows.size()-compared.size(),"failed_frames":failures.slice(0,3)})
	if kind=="jump_right":
		check_result("near_lamps_air_attack_lands_%dx"%root.render_scale,
			rows.any(func(row: Dictionary):return row.action=="jumpattack")
			and rows.any(func(row: Dictionary):return row.height_pixels>100)
			and not p.jump_motion.is_active())
	else:
		check_result("actual_%s_animation_%dx"%[kind,root.render_scale],
			rows.all(func(row: Dictionary):return row.action==("dash" if kind=="dash_left" else "move"))
			and absf(rows[-1].foot.x-rows[0].foot.x)>150)


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var original: Dictionary=root.player.capture_state()
	var original_scale: int=root.render_scale
	var architecture: Node=root.world.get_node("PortArchitecture")
	var lamps: Array=architecture.find_children("Pier_Lamp_*","MeshInstance3D",true,false)
	check_result("forty_two_native_lamp_parts",lamps.size()==42)
	var volumes: bool=true
	var source_materials: Dictionary={}
	for node: MeshInstance3D in lamps:
		var size: Vector3=node.get_aabb().size
		volumes=volumes and minf(size.x,minf(size.y,size.z))>.001
		for i: int in node.mesh.get_surface_count():
			var mat: StandardMaterial3D=node.mesh.surface_get_material(i)
			source_materials[mat.resource_name]=mat.albedo_texture!=null and mat.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST and mat.shading_mode!=BaseMaterial3D.SHADING_MODE_UNSHADED
	check_result("lamp_parts_have_three_dimensional_volume",volumes)
	check_result("four_lit_source_materials_use_nearest",source_materials.size()==4 and source_materials.values().all(func(v):return v),source_materials)
	for name: String in ["FarSmall0","FarSmall1","FarSmall2","Middle0","Middle1","Near"]:
		var hood: MeshInstance3D=architecture.find_child("Pier_Lamp_"+name+"_Hood",true,false)
		var glass: MeshInstance3D=architecture.find_child("Pier_Lamp_"+name+"_Glass",true,false)
		check_result("rounded_hood_and_bowl_"+name,hood.mesh.get_faces().size()>400 and glass.mesh.get_faces().size()>500,
			{"hood_triangle_vertices":hood.mesh.get_faces().size(),"glass_triangle_vertices":glass.mesh.get_faces().size()})
	root.player.reset_position();root._set_paused(true)
	await RenderingServer.frame_post_draw
	root.render_viewport.get_texture().get_image().save_png("res://docs/previews/r1_11_lamps_after.png")
	for scale: int in [1,2]:
		root.set_render_scale(scale)
		for kind: String in ["walk_right","dash_left","jump_right"]:await route(root,kind)
	root.set_render_scale(original_scale)
	root.player.restore_state(original)
	root._set_paused(original["paused"])
	var failed: Array=checks.filter(func(c: Dictionary):return not c["pass"])
	var report: Dictionary={"candidate":"R1/11","checks":checks,"failed":failed,"render_cases":render_cases,
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"glb_sha256":FileAccess.get_sha256("res://assets/r1/models/west_coast_port.glb"),
		"note":"Six actual-input routes in the existing near walk lane. Exact RGB compares only samples whose raster pixel center lies at least 0.002 physical pixels inside the expected source texel; nearest-neighbour boundary cases are reported separately. No navigation area added."}
	var f=FileAccess.open("res://docs/r1_11_lamp_checks.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"  "));f.close()
	return {"checks":checks.size(),"failed":failed,"render_cases":render_cases.size()}
