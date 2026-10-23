extends Node
## Reapply committed equipment to each source actor, including the R0 comparison.

const SCENES: Array[String] = ["res://scenes/west_coast_r0.tscn", "res://scenes/west_coast_r1.tscn", "res://scenes/tower_approach.tscn", "res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"]
var main: Node
var progress: Node
var appearance: RefCounted
var definitions: Dictionary
var last_error: String = ""
var applied_key: String = ""
var applied_actor_id: int = 0
var apply_count: int = 0


static func ensure(area: Node) -> Node:
	var owner: Node = area.get_tree().root.get_node("AdventureProgress")
	var controller: Node = owner.get_node_or_null("EquipmentRuntime")
	if controller == null:
		controller = (load("res://scripts/equipment_runtime.gd") as Script).new()
		controller.name = "EquipmentRuntime"
		owner.add_child(controller)
		controller._setup(owner)
	controller.attach_area(area)
	return controller


func _setup(profile: Node) -> void:
	progress = profile
	definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/first_equipment.json"))
	appearance = load("res://scripts/equipment_appearance.gd").new()
	progress.progress_changed.connect(_on_progress_changed)
	get_tree().scene_changed.connect(_on_scene_changed)


func _on_scene_changed() -> void:
	attach_area(get_tree().current_scene)


func attach_area(area: Node) -> void:
	if not is_instance_valid(area) or not SCENES.has(area.scene_file_path):
		return
	main = area
	_apply_equipment()


func _on_progress_changed() -> void:
	_apply_equipment()


func _apply_equipment() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var key: String = progress.equipped_weapon_key()
	var actor_id: int = main.player.get_instance_id()
	if key == applied_key and actor_id == applied_actor_id:
		return
	var definition: Dictionary = definitions.default_appearance if key == "practice_lswd0000" else definitions.items.get(key, {})
	definition = definition.duplicate(true)
	definition["key"] = key
	if definition.is_empty() or not appearance.apply(main.player, definition):
		last_error = "装备外观未能载入。"
		return
	applied_key = key
	applied_actor_id = actor_id
	apply_count += 1
	last_error = ""


func capture_state() -> Dictionary:
	return {"applied_key": applied_key, "applied_actor_id": applied_actor_id, "apply_count": apply_count,
		"last_error": last_error, "scene": main.scene_file_path if is_instance_valid(main) else ""}
