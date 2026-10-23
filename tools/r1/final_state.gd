extends RefCounted
## Read the fresh live candidate, including actual model texture bytes.

func run(main: Node,candidate: String="R1/27") -> Dictionary:
	var tree: SceneTree=main.get_tree()
	var p: Node=main.player
	var music: Node=tree.root.get_node("PortMusic")
	var ambience: Node=tree.root.get_node("PortAmbience")
	var code: Array=[]
	var diagnostic: Node=tree.root.get_node("FrameDiagnostics")
	for object: Object in [main,p,p.action_effects,p.motion_smoothing,p.walk_inbetweens,main.preview_controls,music,ambience,diagnostic]:
		var script: Script=object.get_script()
		code.append({"path":script.resource_path,"loaded_sha256":script.source_code.sha256_text(),
			"disk_sha256":FileAccess.get_sha256(script.resource_path)})
	var shader: Shader=p.action_effects.surfaces[0].material_override.shader
	code.append({"path":shader.resource_path,"loaded_sha256":shader.code.sha256_text(),"disk_sha256":FileAccess.get_sha256(shader.resource_path)})
	var textures: Dictionary={}
	for object: MeshInstance3D in main.world.get_node("PortArchitecture").find_children("*","MeshInstance3D",true,false):
		for i: int in object.mesh.get_surface_count():
			var material: StandardMaterial3D=object.mesh.surface_get_material(i)
			if material!=null and material.albedo_texture!=null:textures[material.albedo_texture.resource_path]=material.albedo_texture
	var mismatch: Array=[]
	var pixels: int=0
	var compressed_count: int=0
	for path: String in textures:
		var expected:=Image.new()
		expected.load_png_from_buffer(FileAccess.get_file_as_bytes(path));expected.convert(Image.FORMAT_RGBA8)
		var actual: Image=textures[path].get_image()
		if actual.is_compressed():
			compressed_count+=1
			actual.decompress()
		actual.convert(Image.FORMAT_RGBA8)
		if actual.get_size()!=expected.get_size() or actual.get_data()!=expected.get_data():mismatch.append(path)
		pixels+=expected.get_width()*expected.get_height()
	var normal_input: bool=Input.get_vector("move_left","move_right","move_up","move_down")==Vector2.ZERO
	var walk_mismatches: Array=[]
	var walk_pixels: int=0
	var walk_mips: int=0
	var walk_compressed: int=0
	for path: String in p.walk_inbetweens.textures:
		var expected:=Image.new();expected.load_png_from_buffer(FileAccess.get_file_as_bytes(path));expected.convert(Image.FORMAT_RGBA8)
		var actual: Image=p.walk_inbetweens.textures[path].get_image()
		if actual.has_mipmaps():walk_mips+=1
		if actual.is_compressed():walk_compressed+=1;actual.decompress()
		actual.convert(Image.FORMAT_RGBA8)
		if actual.get_data()!=expected.get_data():walk_mismatches.append(path)
		walk_pixels+=expected.get_width()*expected.get_height()
	for action: String in ["run","jump","attack"]:normal_input=normal_input and not Input.is_action_pressed(action)
	var point: Vector2=p.world_to_source(p.position)
	var music_bus: int=AudioServer.get_bus_index(music.bus_name)
	var ambient_bus: int=AudioServer.get_bus_index(ambience.bus_name)
	var report: Dictionary={"candidate":candidate,"scene":main.scene_file_path,"build":main.get_node("Interface/Build").text,
		"root_children":tree.root.get_children().map(func(n: Node):return n.name),
		"player_at_default_start":point.distance_to(Vector2(440,320))<.001,"source_position":point,
		"paused":p.paused,"preview":p.preview_mode,"one_shot":p._one_shot,"jump_active":p.jump_motion.is_active(),
		"ui_input_blocked":p.ui_input_blocked,"markers":p.markers_visible,"movement_input_clear":normal_input,
		"water_paused":main.water.paused,"render_scale":main.render_scale,
		"probe_disabled":main.world.get_node("StoneCollision/Shape").disabled,
		"source_effect_enabled":p.action_effects.enabled,"effect_toggle_enabled":main.preview_controls.effects_toggle.button_pressed,
		"active_effect_tracks":p.action_effects.active_frames,"source_effect_textures":p.action_effects.textures.size(),
		"effect_data_matches_disk":p.action_effects.actions==JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_effects.json"))["actions"],
		"code_hashes":code,"code_matches_disk":code.all(func(r: Dictionary):return r.loaded_sha256==r.disk_sha256),
		"model_texture_count":textures.size(),"model_texture_rgba_pixels":pixels,"model_texture_rgba_mismatches":mismatch,
		"model_texture_vram_compressed":compressed_count,"meshes":main.world.get_node("PortArchitecture").find_children("*","MeshInstance3D",true,false).size(),
		"glb_sha256":FileAccess.get_sha256("res://assets/r1/models/west_coast_port.glb"),
		"music":music.capture_state(),"ambience":ambience.capture_state(),
		"music_stream_loop":music.player.stream.loop,"ambient_stream_loop":ambience.player.stream.loop,
		"music_bus_db":AudioServer.get_bus_volume_db(music_bus),"music_bus_effects":AudioServer.get_bus_effect_count(music_bus),
		"ambient_bus_db":AudioServer.get_bus_volume_db(ambient_bus),"ambient_bus_effects":AudioServer.get_bus_effect_count(ambient_bus),
		"effects_muted":tree.get_meta("port_audio_muted",false),"effects_volume":tree.get_meta("port_audio_volume",.6),
		"physics_ticks_per_second":Engine.physics_ticks_per_second,
		"walk_inbetweens_enabled":p.walk_inbetweens.enabled,"walk_inbetweens_active":p.walk_inbetweens.active,
		"walk_subframe":p.walk_inbetweens.subframe,"walk_toggle_enabled":main.preview_controls.walk_toggle.button_pressed,
		"walk_texture_count":p.walk_inbetweens.textures.size(),"walk_texture_RGBA_pixels":walk_pixels,"walk_texture_RGBA_mismatches":walk_mismatches,
		"walk_texture_mipmaps":walk_mips,"walk_texture_compressed":walk_compressed,
		"walk_data_matches_disk":p.walk_inbetweens.data==JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_walk_inbetweens.json")),
		"dash_data_matches_disk":p.walk_inbetweens.clips.dash==JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_dash_inbetweens.json")),
		"locomotion_texture_counts":p.walk_inbetweens.texture_counts(),
		"frame_diagnostics_active":diagnostic.active,
		"frame_diagnostics_sampling":diagnostic.is_processing(),
		"frame_diagnostics_visible":diagnostic.panel.visible,
		"frame_diagnostics_count":tree.root.get_children().filter(func(n: Node):return n.name=="FrameDiagnostics").size(),
		"motion_smoothing_enabled":p.motion_smoothing.enabled,
		"motion_toggle_enabled":main.preview_controls.motion_toggle.button_pressed,
		"native_actor_interpolation_active":p.is_physics_interpolated_and_enabled(),
		"native_tree_interpolation_active":tree.is_physics_interpolation_enabled(),
		"scene_interpolation_mode":main.physics_interpolation_mode,
		"sprite_position":p.sprite.position,"sprite_offset":p.sprite.offset,
		"physics_interpolation":ProjectSettings.get_setting("physics/common/physics_interpolation",false)}
	var out:=FileAccess.open("res://docs/"+candidate.to_lower().replace("/","_")+"_final_state.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "));out.close()
	return report
