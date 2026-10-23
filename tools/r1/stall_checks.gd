extends RefCounted
## Additional R1/02 checks in the real graphical game after runtime_checks.gd.

var checks: Array = []


func check_result(name: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check":name,"pass":passed,"details":details})


func source_opaque(image: Image,anchor: Vector2,foot: Vector2,point: Vector2i,scale: float) -> bool:
	var pixel:=Vector2i(roundi((point.x-foot.x)/scale+anchor.x),roundi((point.y-foot.y)/scale+anchor.y))
	if pixel.x<1 or pixel.y<1 or pixel.x>=image.get_width()-1 or pixel.y>=image.get_height()-1:
		return false
	# Ignore outline/AA pixels so an MSAA edge cannot masquerade as occlusion.
	for d in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if image.get_pixelv(pixel+d).a<.98:
			return false
	return true


func color_distance(a: Color,b: Color) -> float:
	return Vector3(a.r,a.g,a.b).distance_to(Vector3(b.r,b.g,b.b))


func run(root: Node,candidate: String="R1/18") -> Dictionary:
	var prefix: String=candidate.to_lower().replace("/","_")
	var tree: SceneTree=root.get_tree()
	var p: Node=root.player
	var render_scale: float=float(root.render_scale)
	var architecture: Node=root.world.get_node("PortArchitecture")
	var canopy: MeshInstance3D=architecture.find_child("Stall_Canopy",true,false)
	check_result("canopy_has_real_height_and_depth",canopy.mesh.get_aabb().size.y>.8
		and canopy.mesh.get_aabb().size.z>1.0,{"aabb_size":canopy.mesh.get_aabb().size})
	var mat: StandardMaterial3D=canopy.mesh.surface_get_material(0)
	check_result("painted_stall_uses_alpha_cutout",mat.transparency==2
		and mat.albedo_texture.get_size()==Vector2(443,230),
		{"transparency":mat.transparency,"source_texture_size":mat.albedo_texture.get_size()})
	check_result("whole_stall_billboard_removed",not root.world.get_node("SourceProps").has_node("westmobj00"))
	check_result("source_pattern_is_projected_uv",canopy.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size()>0)
	check_result("independent_drapery_and_counter",architecture.find_child("Stall_Red_Drapery",true,false)!=null
		and architecture.find_child("Stall_Counter",true,false)!=null
		and architecture.find_child("Stall_Parasol_Finial",true,false)!=null)
	check_result("native_rope_meshes_present",architecture.find_children("Stall_*_Rope*","MeshInstance3D",true,false).size()==8)

	# Actual input/physics crossing of the L-shaped source walk area.
	p.reset_position()
	p.position=p.source_to_world(Vector2(370,252))
	root._set_paused(false)
	Input.action_press("move_right")
	await tree.create_timer(.45).timeout
	Input.action_release("move_right")
	var corner: Vector2=p.world_to_source(p.position)
	check_result("upper_corner_blocks_without_vertical_snap",absf(corner.x-378)<.5
		and absf(corner.y-252)<.5,{"source_position":corner})
	Input.action_press("move_down")
	await tree.create_timer(.80).timeout
	Input.action_release("move_down")
	Input.action_press("move_right")
	await tree.create_timer(.45).timeout
	Input.action_release("move_right")
	var after_corner: Vector2=p.world_to_source(p.position)
	check_result("lower_strip_reopens_rightward_route",after_corner.x>410 and after_corner.y>285,
		{"source_position":after_corner})
	p.reset_position()
	p.position=p.source_to_world(Vector2(125,300))
	Input.action_press("move_up")
	await tree.create_timer(1.15).timeout
	Input.action_release("move_up")
	var upper: Vector2=p.world_to_source(p.position)
	check_result("left_strip_reaches_npc_back_row",absf(upper.y-245)<.5,{"source_position":upper})

	# The new sign has a real small collision volume at the edge of the upper strip.
	p.position=p.source_to_world(Vector2(302,280))
	Input.action_press("move_up")
	await tree.create_timer(.85).timeout
	Input.action_release("move_up")
	var sign_stop: Vector2=p.world_to_source(p.position)
	var sign_collider: String=""
	if p.get_slide_collision_count()>0:
		sign_collider=String(p.get_slide_collision(0).get_collider().name)
	check_result("stall_sign_blocks_native_body",sign_stop.y>248 and sign_stop.y<257
		and sign_collider=="StallSignCollision",
		{"source_position":sign_stop,"slide_collisions":p.get_slide_collision_count(),"collider":sign_collider})

	# Render a source actor behind the existing NPC, then remove only the NPC sprite.
	root._set_paused(true)
	p.preview("stay")
	p.facing=1
	p.position=p.source_to_world(Vector2(150,245))
	p._update_sprite_transform()
	var camera: Camera3D=root.world.get_node("Camera")
	var viewport: SubViewport=root.get_node("PortClip/ViewportContainer/Viewport")
	var foot: Vector2=camera.unproject_position(p.position)
	await RenderingServer.frame_post_draw
	var behind: Image=viewport.get_texture().get_image()
	behind.save_png("res://docs/previews/"+prefix+"_behind_sharan.png")
	root.npc_sr.sprite.visible=false
	await RenderingServer.frame_post_draw
	var unobstructed: Image=viewport.get_texture().get_image()
	unobstructed.save_png("res://docs/previews/"+prefix+"_without_sharan.png")
	root.npc_sr.sprite.visible=true
	p.sprite.visible=false
	await RenderingServer.frame_post_draw
	var npc_only: Image=viewport.get_texture().get_image()
	npc_only.save_png("res://docs/previews/"+prefix+"_sharan_only.png")
	p.sprite.visible=true
	var player_image: Image=p.sprite.texture.get_image()
	var npc_image: Image=root.npc_sr.sprite.texture.get_image()
	if player_image.is_compressed():
		player_image.decompress()
	if npc_image.is_compressed():
		npc_image.decompress()
	var npc_foot: Vector2=camera.unproject_position(root.npc_sr.position)
	var overlap:=0
	var npc_visible:=0
	for y in range(int(foot.y-125*render_scale),int(foot.y+15*render_scale)):
		for x in range(int(foot.x-64*render_scale),int(foot.x+64*render_scale)):
			var point:=Vector2i(x,y)
			if not source_opaque(player_image,p._foot_anchor,foot,point,render_scale):
				continue
			if not source_opaque(npc_image,root.npc_sr._foot_anchor,npc_foot,point,render_scale):
				continue
			var foreground:=npc_only.get_pixelv(point)
			var actor:=unobstructed.get_pixelv(point)
			if color_distance(foreground,actor)<.06:
				continue
			overlap+=1
			if color_distance(behind.get_pixelv(point),foreground)<.035:
				npc_visible+=1
	check_result("npc_occludes_player_in_upper_strip",overlap>10 and npc_visible>overlap*.85,
		{"distinct_opaque_overlap_pixels":overlap,"pixels_matching_npc_only":npc_visible,"foot":foot,
		"method":"Both source alpha masks across the actor body, excluding AA edges; compare combined render with separate actor/NPC renders"})

	p.reset_position()
	root._set_paused(false)
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_viewport().get_texture().get_image()
	image.save_png("res://docs/previews/r1_port.png")
	image.save_png("res://docs/previews/"+prefix+"_port.png")
	var failed:=0
	for check: Dictionary in checks:
		if not check["pass"]:
			failed+=1
	var report: Dictionary={"candidate":candidate,"coverage":"Retained R1/02 stall and walk-area checks","platform":"macOS","checks":checks,"failed":failed,
		"render_scale":render_scale,"render_viewport":viewport.size,
		"qa_source_sha256":get_script().source_code.sha256_text(),
		"note":"These supplement the core R1 checks. They do not establish historical gameplay fidelity or Windows correctness."}
	var out:=FileAccess.open("res://docs/"+prefix+"_stall_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	return report
