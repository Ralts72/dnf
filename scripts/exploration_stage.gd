extends "res://scripts/west_coast_r1.gd"
## A connected area keeps the port's fixed camera and the same source actor.

@export_enum("approach", "hall", "depths", "doll_gallery", "statue_gallery") var region_id: String = "approach"
var walk_bounds: Rect2
var route_obstacles = preload("res://scripts/route_ground_obstacles.gd").new()


func _ready() -> void:
	super._ready()
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_route.json"))
	var area: Dictionary = route["regions"][region_id]
	var bounds: Array = area["walk_bounds"]
	walk_bounds = Rect2(Vector2(bounds[0], bounds[1]), Vector2(bounds[2] - bounds[0], bounds[3] - bounds[1]))
	var pan_limits: Array = area.get("horizontal_pan_limits", [])
	if pan_limits.size() == 2:
		framing.configure_horizontal_pan(float(pan_limits[0]), float(pan_limits[1]))
	player.ground_constraint = _constrain_ground
	world.get_node("PortArchitecture").hide()
	world.get_node("SourceProps").hide()
	world.get_node("StoneCollision").collision_layer = 0
	world.get_node("StallSignCollision").collision_layer = 0
	npc_lo.hide()
	npc_sr.hide()
	for actor: CharacterBody3D in [npc_lo, npc_sr]:
		actor.collision_layer = 0
		actor.collision_mask = 0
	for prop: Node in world.get_node("SourceProps").get_children():
		prop.set_process(false)
	water.hide()
	water.set_process(false)
	var content: Node3D = load("res://scenes/tower_" + region_id + "_world.tscn").instantiate()
	world.add_child(content)
	route_obstacles.setup(self, region_id)
	var background: Sprite2D = $PortClip/Far
	background.texture = load("res://assets/r2/" + ("approach/sea.png" if region_id == "approach" else "interior/far.png"))
	background.position = Vector2(0, -24) if region_id == "approach" else Vector2(0, -30)
	background.scale = Vector2.ONE if region_id == "approach" else Vector2(896.0 / 630.0, 1.0)
	# The wide hall owns its source-size distant vista inside its native world.
	background.visible = region_id not in ["depths", "doll_gallery", "statue_gallery"]
	framing.base_far = background.position
	$PortClip/SeaColor.color = Color(0.08, 0.25, 0.36) if region_id == "approach" else Color(0.12, 0.055, 0.12)
	if region_id == "depths":
		$PortClip/SeaColor.color = Color(0.045, 0.025, 0.065)
	elif region_id == "doll_gallery":
		$PortClip/SeaColor.color = Color(0.055, 0.045, 0.06)
	elif region_id == "statue_gallery":
		$PortClip/SeaColor.color = Color(0.09, 0.085, 0.075)
	var titles: Dictionary = {"approach": "天空之城  /  石道", "hall": "龙人之塔  /  门厅", "depths": "龙人之塔  /  深廊", "doll_gallery": "人偶之馆  /  前廊", "statue_gallery": "雕像回廊"}
	var subtitles: Dictionary = {"approach": "沿石道向上进入塔门", "hall": "击退龙人后，沿右侧通道深入", "depths": "鲁卡斯守在深处 · 击退后沿右侧深入", "doll_gallery": "击退人偶师，沿右侧进入雕像回廊", "statue_gallery": "沿长廊向右探索 · 留意会苏醒的石像"}
	$Interface/Title.text = titles[region_id]
	$Interface/Subtitle.text = subtitles[region_id]
	$Interface/Build.text = str(route.get("build_label", "R2   /   01"))
	$Interface/Compare.text = "港口对照 F4"
	$Interface/Compare.disabled = true
	$Interface/Compare.tooltip_text = "回到港口后，可用 F4 查看原图对照"
	preload("res://scripts/world_travel.gd").ensure(self)
	preload("res://scripts/adventure_progress.gd").ensure(self)
	framing.advance(0.0, true)
	call_deferred("_setup_route_content")


func _setup_route_content() -> void:
	if is_inside_tree() and get_tree().current_scene == self:
		if region_id == "hall":
			preload("res://scripts/first_encounter.gd").ensure(self)
		elif region_id == "depths":
			preload("res://scripts/tower_boss.gd").ensure(self)
		elif region_id == "doll_gallery":
			load("res://scripts/gallery_encounter.gd").ensure(self)
		elif region_id == "statue_gallery":
			load("res://scripts/statue_encounter.gd").ensure(self)
		preload("res://scripts/first_loot.gd").ensure(self)


func _constrain_ground(previous: Vector2, requested: Vector2) -> Vector2:
	return route_obstacles.constrain(previous, requested, walk_bounds)


func _switch_comparison() -> void:
	# The comparison is a harbor reference, not an alternate route or a teleport.
	pass


func _set_probe_visible(_enabled: bool) -> void:
	if is_instance_valid(world):
		for probe in world.get_node("PortArchitecture").find_children("Occlusion_Stone*", "MeshInstance3D", true, false):
			probe.hide()
		world.get_node("StoneCollision/Shape").set_deferred("disabled", true)
