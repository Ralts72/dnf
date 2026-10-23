extends RefCounted
## Checks the loaded GLB, ground coverage, measured lamp projection and renders.

var checks: Array=[]
var render_cases: Array=[]


func check_result(name: String,passed: bool,details: Dictionary={}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func top_triangles(node: MeshInstance3D) -> Array:
	var triangles: Array=[]
	for surface: int in node.mesh.get_surface_count():
		var arrays: Array=node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i: int in range(0,indices.size(),3):
			var a: Vector3=node.global_transform*vertices[indices[i]]
			var b: Vector3=node.global_transform*vertices[indices[i+1]]
			var c: Vector3=node.global_transform*vertices[indices[i+2]]
			if a.y>-.1 and absf(a.y-b.y)<.00001 and absf(a.y-c.y)<.00001:
				triangles.append([a,b,c])
	return triangles


func pixel(image: Image,point: Vector2,scale: int) -> Color:
	return image.get_pixelv(Vector2i(point*scale))


func run(root: Node) -> Dictionary:
	var tree: SceneTree=root.get_tree()
	var original: Dictionary=root.player.capture_state()
	var original_scale: int=root.render_scale
	root._set_paused(true)
	root.set_render_scale(2)
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://source_art/r1/shore_reference.json"))
	var architecture: Node=root.world.get_node("PortArchitecture")
	var camera: Camera3D=root.world.get_node("Camera")
	var far: MeshInstance3D=architecture.find_child("Pier_Far_Slab",true,false)
	var middle: MeshInstance3D=architecture.find_child("Pier_Middle_Slab",true,false)
	check_result("two_loaded_native_pier_slabs",far!=null and middle!=null)
	check_result("piers_have_depth_below_water",far.get_aabb().size.y>.59 and middle.get_aabb().size.y>.59)
	check_result("piers_connected_to_near_shore",architecture.find_child("Pier_Connecting_Spine",true,false)!=null)
	var caps: Array=architecture.find_children("Quay_Coping_Diagonal*","MeshInstance3D",true,false)
	check_result("diagonal_shore_replaces_rectangular_return",caps.size()>=8
		and architecture.find_child("Quay_Retaining_Wall_Return",true,false)==null,{"diagonal_cap_meshes":caps.size()})
	var min_x: float=1000.0
	var max_x: float=-1000.0
	var min_z: float=1000.0
	var max_z: float=-1000.0
	for cap: MeshInstance3D in caps:
		var box: AABB=cap.global_transform*cap.get_aabb()
		min_x=minf(min_x,box.position.x);max_x=maxf(max_x,box.end.x)
		min_z=minf(min_z,box.position.z);max_z=maxf(max_z,box.end.z)
	check_result("shore_has_source_diagonal_depth",max_x-min_x>3.6 and max_z-min_z>1.6)
	var backwall: MeshInstance3D=architecture.find_child("Pier_Landward_Backwall",true,false)
	var cutout: bool=false
	for i: int in backwall.mesh.get_surface_count():
		var mat: StandardMaterial3D=backwall.mesh.surface_get_material(i)
		if mat.resource_name=="Source_Painted_Pier_Backwall":
			cutout=mat.transparency==2 and mat.albedo_texture.get_size()==Vector2(224,277)
	check_result("painted_landward_wall_keeps_alpha_cutout",cutout)
	var nearest: bool=true
	for node: MeshInstance3D in [far,middle,caps[0]]:
		for i: int in node.mesh.get_surface_count():
			var mat: StandardMaterial3D=node.mesh.surface_get_material(i)
			nearest=nearest and mat.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST
	check_result("masonry_materials_use_nearest_sampling",nearest)
	var lamp_errors: Array=[]
	for lamp: Dictionary in reference["measurements"]["lamps"]:
		var base: MeshInstance3D=architecture.find_child("Pier_Lamp_"+lamp["name"]+"_Base",true,false)
		var spire: MeshInstance3D=architecture.find_child("Pier_Lamp_"+lamp["name"]+"_Spire",true,false)
		var foot: Vector2=camera.unproject_position(base.global_position-Vector3.UP*.06)/2.0-Vector2(0,43)
		var bounds: AABB=spire.global_transform*spire.get_aabb()
		var top: Vector3=Vector3(bounds.get_center().x,bounds.end.y,bounds.get_center().z)
		var top_screen: Vector2=camera.unproject_position(top)/2.0-Vector2(0,43)
		var expected:=Vector2(lamp["foot"][0],lamp["foot"][1])
		var error: float=maxf(foot.distance_to(expected),absf(top_screen.y-lamp["top_y"]))
		lamp_errors.append({"name":lamp["name"],"pixel_error":error})
		check_result("lamp_source_projection_"+lamp["name"],error<.02,{"foot":foot,"top":top_screen,"error":error})
	# Intersect actual imported mortar-bed triangles below every 2px grid point in
	# the retained source walk strips. This tests the GLB, not a matching formula.
	var bed: MeshInstance3D=architecture.find_child("Mortar_Bed_Shore_Polygon",true,false)
	var triangles: Array=top_triangles(bed)
	var tested: int=0
	var uncovered: Array=[]
	for x: int in range(36,853,2):
		for y: int in range(245,346,2):
			if x>378 and y<285:
				continue
			var ground: Vector3=root.player.source_to_world(Vector2(x,y))
			var hit: bool=false
			for triangle: Array in triangles:
				if Geometry3D.segment_intersects_triangle(ground+Vector3.UP,ground-Vector3.UP,triangle[0],triangle[1],triangle[2])!=null:
					hit=true
					break
			tested+=1
			if not hit:
				uncovered.append([x,y])
	check_result("loaded_ground_covers_retained_walk_strips",tested>15000 and uncovered.is_empty(),
		{"grid_pixels":2,"points":tested,"triangles":triangles.size(),"uncovered":uncovered.slice(0,10)})
	check_result("water_extends_under_near_channel",root.world.get_node("Water").mesh.size.y>4.0
		and root.world.get_node("Water").position.y<-.25)
	await RenderingServer.frame_post_draw
	var full: Image=root.render_viewport.get_texture().get_image()
	full.save_png("res://docs/previews/r1_12_shore_visible.png")
	var hidden: Array=[]
	for node: Node in architecture.find_children("Pier_*","MeshInstance3D",true,false):
		if node.visible:
			hidden.append(node)
			node.visible=false
	await RenderingServer.frame_post_draw
	var water_only: Image=root.render_viewport.get_texture().get_image()
	water_only.save_png("res://docs/previews/r1_12_shore_hidden.png")
	for node: Node in hidden:
		node.visible=true
	var water_node: MeshInstance3D=root.world.get_node("Water")
	water_node.visible=false
	await RenderingServer.frame_post_draw
	var pier_only: Image=root.render_viewport.get_texture().get_image()
	pier_only.save_png("res://docs/previews/r1_12_shore_pier_control.png")
	water_node.visible=true
	var water_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://source_art/r1/water_reference.json"))
	for sample: Dictionary in [{"name":"Far","point":Vector2(570,146)},
		{"name":"Middle","point":Vector2(610,181)}]:
		var point: Vector2=sample["point"]+Vector2(0,43)
		var with_pier: Color=pixel(full,point,2)
		var without_pier: Color=pixel(water_only,point,2)
		var pier_control: Color=pixel(pier_only,point,2)
		var distance: float=Vector3(with_pier.r,with_pier.g,with_pier.b).distance_to(Vector3(without_pier.r,without_pier.g,without_pier.b))
		var control_distance: float=Vector3(with_pier.r,with_pier.g,with_pier.b).distance_to(Vector3(pier_control.r,pier_control.g,pier_control.b))
		var matches_water_palette: bool=water_reference["palette"].any(func(s: Dictionary):
			var c: Color=Color(s["rgba"][0]/255.0,s["rgba"][1]/255.0,s["rgba"][2]/255.0)
			return maxf(absf(c.r-without_pier.r),maxf(absf(c.g-without_pier.g),absf(c.b-without_pier.b)))<.5/255.0)
		# Compare independent renders rather than assuming stone must be brighter
		# than source-colored cyan/white water highlights. Small AO changes are lit.
		check_result("rendered_pier_over_water_"+sample["name"],distance>.02
			and control_distance<.025 and pier_control.a>.999 and matches_water_palette,
			{"point":sample["point"],"distance":distance,"pier_control_distance":control_distance,
			"pier":with_pier,"water":without_pier,"pier_control":pier_control,"source_water_palette":matches_water_palette})
	# Ships remain source-ANI props, with exact original frame timing and offsets.
	var port: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/port_r0.json"))
	for name: String in ["westnearship","westmmidship"]:
		var ship: Node=root.world.get_node("SourceProps/"+name)
		var source: Dictionary=port["objects"].filter(func(o: Dictionary):return o["name"]==name)[0]
		var expected: Array=source["sequence"]["frames"]
		var same: bool=ship.frames.size()==expected.size()
		for i: int in ship.frames.size():
			var actual_offset: Array=ship.frames[i]["offset"]
			var expected_offset: Array=expected[i]["layers"][0]["offset"]
			same=same and is_equal_approx(float(ship.frames[i]["duration_ms"]),float(expected[i]["duration_ms"])) \
				and Vector2(actual_offset[0],actual_offset[1])==Vector2(expected_offset[0],expected_offset[1])
		check_result("original_ship_timing_retained_"+name,same,{"frames":ship.frames.size()})
	root.set_render_scale(original_scale)
	root.player.restore_state(original)
	root._set_paused(original["paused"])
	var failed: Array=checks.filter(func(c: Dictionary):return not c["pass"])
	var report: Dictionary={"candidate":"R1/12","checks":checks,"failed":failed,
		"lamp_projection":lamp_errors,"ground_grid_points":tested,"ground_grid_uncovered":uncovered.size(),
		"source_script_sha256":get_script().source_code.sha256_text(),
		"glb_sha256":FileAccess.get_sha256("res://assets/r1/models/west_coast_port.glb"),
		"notes":["Native imported triangles and rendered pier/water comparisons.",
			"2px walk-grid coverage does not assert original game geometry or add far-pier navigation."]}
	var file:=FileAccess.open("res://docs/r1_12_shore_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	return {"checks":checks.size(),"failed":failed,"walk_grid_points":tested}
