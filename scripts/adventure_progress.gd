extends Node
## An adapted, independent prototype profile; never reads the client's saves.

signal progress_changed

const DATA_PATH: String = "res://data/first_route_quest.json"
const EQUIPMENT_PATH: String = "res://data/first_equipment.json"
const DEFAULT_STORAGE: String = "user://adventure/first_route_v1.json"
const STAGES: Array[String] = ["available", "active", "return", "completed"]
const ITEM_KEY: String = "3128"
const DROP_ID: String = "mirkius_first_eye_v1"
const PRACTICE_WEAPON: String = "practice_lswd0000"
const REWARD_WEAPON: String = "27304"
const PROFILE_SCHEMA: int = 6
const CHAPTER_META: Dictionary = {"stonemaster_cleared": "doll_gallery_state", "statue_cleared": "statue_gallery_state"}
const HP_POTION_KEY: String = "1106"
const HP_POTION_PRICE: int = 10
const HP_POTION_MAX: int = 4
var main: Node
var data: Dictionary = {}
var equipment_data: Dictionary = {}
var progress: Dictionary = {"schema": PROFILE_SCHEMA, "quest_stage": "available", "objective_cleared": false, "reward_granted": false, "coins": 0,
	"inventory": {"3128": 0, "1106": 0}, "first_drop": {"id": "mirkius_first_eye_v1", "state": "unearned", "region": "hall", "position": [640, 300]},
	"equipment": {"owned": {"27304": false}, "equipped_key": "practice_lswd0000"}, "chapter_flags": {"lakius_cleared": false, "stonemaster_cleared": false, "statue_cleared": false}}
var storage_path: String = DEFAULT_STORAGE
var last_error: String = ""
var loaded_from_backup: bool = false
var _storage_ready: bool = true
var _clear_seen: bool = false
var _boss_clear_seen: bool = false
var _save_attempts: int = 0
var _pending_bundle: Dictionary = {}
# Verified live events survive R/area changes without mutating an older pending bundle.
var _chapter_receipts: Dictionary = {"stonemaster_cleared": false, "statue_cleared": false}
var _chapter_attempt_due: bool = false
var _dialog_open: bool = false
var _hud: Label
var _prompt: Label
var _layer: CanvasLayer
var _body: Label
var _confirm: Button
var _close: Button


static func ensure(area: Node) -> Node:
	var tree: SceneTree = area.get_tree()
	var controller: Node = tree.root.get_node_or_null("AdventureProgress")
	if controller == null and tree.has_meta("adventure_progress_pending"):
		controller = tree.get_meta("adventure_progress_pending")
		if is_instance_valid(controller):
			controller.call_deferred("attach_area", area)
			return controller
	if controller == null:
		controller = (load("res://scripts/adventure_progress.gd") as Script).new()
		controller.name = "AdventureProgress"
		tree.set_meta("adventure_progress_pending", controller)
		# The root is still attaching this scene during its _ready callback.
		tree.root.call_deferred("add_child", controller)
		controller.call_deferred("_initialize")
		controller.call_deferred("attach_area", area)
		return controller
	controller.call("attach_area", area)
	return controller


func _initialize() -> void:
	if get_tree().has_meta("adventure_progress_pending"):
		get_tree().remove_meta("adventure_progress_pending")
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	equipment_data = JSON.parse_string(FileAccess.get_file_as_string(EQUIPMENT_PATH))
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 900
	process_physics_priority = -900
	load_progress()


func configure_storage(path: String, load_existing: bool = true) -> bool:
	if path != DEFAULT_STORAGE and not (path.begins_with("user://qa/") and not path.contains("..")):
		return _error("无法使用这个存档位置。")
	close_dialog()
	storage_path = path
	progress = _default_progress()
	_pending_bundle = {}
	_chapter_receipts = {"stonemaster_cleared": false, "statue_cleared": false}
	_chapter_attempt_due = false
	last_error = ""
	loaded_from_backup = false
	_storage_ready = true
	_clear_seen = false
	_boss_clear_seen = false
	_save_attempts = 0
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if equipment_data.is_empty():
		equipment_data = JSON.parse_string(FileAccess.get_file_as_string(EQUIPMENT_PATH))
	if load_existing:
		return load_progress()
	progress_changed.emit()
	return true


func attach_area(area: Node) -> void:
	if not is_instance_valid(area) or not area.is_inside_tree():
		return
	close_dialog()
	for owned in [_hud, _prompt, _layer]:
		if is_instance_valid(owned):
			owned.get_parent().remove_child(owned)
			owned.queue_free()
	main = area
	_hud = null
	_prompt = null
	_layer = null
	if not _is_region_scene():
		return
	var title: Label = main.get_node("Interface/Title")
	_hud = Label.new()
	_hud.name = "QuestObjective"
	_hud.theme = title.theme
	_hud.position = Vector2(566, 44 if main.scene_file_path in ["res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"] else 8)
	_hud.size = Vector2(318, 48)
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_font_size_override("font_size", 12)
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	main.get_node("PortClip").add_child(_hud)
	_prompt = Label.new()
	_prompt.name = "LorianInteractHint"
	_prompt.theme = title.theme
	_prompt.text = "E  与萝莉安交谈"
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("font_size", 12)
	_prompt.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65))
	_prompt.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.055))
	_prompt.add_theme_constant_override("outline_size", 3)
	main.get_node("PortClip").add_child(_prompt)
	_build_dialog(title.theme)
	_refresh_ui()


func _process(_delta: float) -> void:
	if _dialog_open and (not is_instance_valid(main) or get_tree().current_scene != main):
		close_dialog()
	_observe_chapters()
	if _pending_bundle.is_empty():
		_save_observed_progress(false)
	if _dialog_open and is_instance_valid(main):
		main.player.ui_input_blocked = true
	_refresh_ui()


func _physics_process(_delta: float) -> void:
	if _dialog_open and is_instance_valid(main):
		main.player.ui_input_blocked = true
		main.player.velocity = Vector3.ZERO


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _dialog_open:
		if event.keycode in [KEY_E, KEY_ESCAPE]:
			close_dialog()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			if is_instance_valid(_confirm) and _confirm.visible:
				_confirm_dialog()
			else:
				close_dialog()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_E and can_interact():
		open_dialog()
		get_viewport().set_input_as_handled()


func can_interact() -> bool:
	if not _eligible_area() or main.scene_file_path != "res://scenes/west_coast_r1.tscn" or _dialog_open:
		return false
	var player: Node = main.player
	if player.paused or player.preview_mode or player._one_shot or player.ui_input_blocked or player.jump_motion.is_active():
		return false
	if absf(player.height_above_ground) > 0.0001:
		return false
	var travel: Node = main.get_node_or_null("WorldTravel")
	if travel != null and not bool(travel.is_ready()):
		return false
	for popup: Node in get_tree().root.find_children("*", "PopupMenu", true, false):
		if popup.visible:
			return false
	var point: Vector2 = player.world_to_source(player.position)
	var npc: Array = data.npc_source_position
	var extent: Array = data.interaction_half_extent
	return absf(point.x - float(npc[0])) <= float(extent[0]) and absf(point.y - float(npc[1])) <= float(extent[1])


func open_dialog() -> bool:
	if not can_interact() or not is_instance_valid(_layer):
		return false
	_dialog_open = true
	main.player.ui_input_blocked = true
	main.player.velocity = Vector3.ZERO
	main.player.play("stay")
	_layer.visible = true
	_refresh_ui()
	if _confirm.visible:
		_confirm.grab_focus.call_deferred()
	else:
		_close.grab_focus.call_deferred()
	return true


func close_dialog() -> void:
	if not _dialog_open:
		return
	_dialog_open = false
	if is_instance_valid(_layer):
		_layer.visible = false
	if is_instance_valid(main) and is_instance_valid(main.player):
		var travel: Node = main.get_node_or_null("WorldTravel")
		if travel == null or bool(travel.is_ready()):
			main.player.ui_input_blocked = false
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and is_instance_valid(_layer) and _layer.is_ancestor_of(focus):
		focus.release_focus()


func accept_quest() -> bool:
	if not _pending_bundle.is_empty():
		return _error("请先保存上一笔进度，再继续。")
	if progress.quest_stage != "available":
		return false
	var next: Dictionary = progress.duplicate(true)
	var cleared: bool = _encounter_cleared() or progress.first_drop.state != "unearned"
	next.quest_stage = "return" if cleared else "active"
	next.objective_cleared = cleared
	if _encounter_cleared():
		next = _clear_candidate(next)
	var saved: bool = _commit(next)
	if saved:
		close_dialog()
	return saved


func claim_reward() -> bool:
	if not _pending_bundle.is_empty():
		return _error("请先保存上一笔进度，再继续。")
	if progress.quest_stage != "return" or progress.reward_granted or not progress.objective_cleared:
		return false
	var next: Dictionary = progress.duplicate(true)
	next.quest_stage = "completed"
	next.reward_granted = true
	next.coins = int(progress.coins) + int(data.reward_coins)
	next.equipment.owned[REWARD_WEAPON] = true
	var saved: bool = _commit(next)
	if saved:
		close_dialog()
	return saved


func save_progress() -> bool:
	_observe_chapters()
	if not _pending_bundle.is_empty():
		return retry_pending_save()
	return _save_observed_progress(true)


func record_chapter_clear(key: String) -> bool:
	if not CHAPTER_META.has(key):
		return false
	if progress.chapter_flags[key]:
		return true
	if not _chapter_session_cleared(key):
		return false
	_observe_chapter(key)
	if not _pending_bundle.is_empty() or not _chapter_attempt_due:
		return false
	return _save_observed_progress(false)


func chapter_cleared(key: String, include_session: bool = true) -> bool:
	if not progress.chapter_flags.has(key):
		return false
	if progress.chapter_flags[key]:
		return true
	if not include_session:
		return false
	if key == "lakius_cleared":
		return _boss_encounter_cleared()
	return _chapter_receipts.get(key) == true or _chapter_session_cleared(key)


func _chapter_session_cleared(key: String) -> bool:
	if not CHAPTER_META.has(key):
		return false
	var state: Variant = get_tree().get_meta(CHAPTER_META[key], {})
	return state is Dictionary and typeof(state.get("cleared")) == TYPE_BOOL and state.cleared


func _observe_chapter(key: String) -> void:
	if not progress.chapter_flags[key] and not _chapter_receipts[key] and _chapter_session_cleared(key):
		_chapter_receipts[key] = true
		_chapter_attempt_due = true


func _observe_chapters() -> void:
	for key: String in CHAPTER_META:
		_observe_chapter(key)


func _has_chapter_receipts() -> bool:
	return _chapter_receipts.stonemaster_cleared or _chapter_receipts.statue_cleared


func _save_observed_progress(force: bool) -> bool:
	var first_observation: bool = _needs_clear_observation(progress) and not _clear_seen and _encounter_cleared()
	var boss_observation: bool = not progress.chapter_flags.lakius_cleared and not _boss_clear_seen and _boss_encounter_cleared()
	if not force and not first_observation and not boss_observation and not _chapter_attempt_due:
		return false
	var next: Dictionary = progress.duplicate(true)
	if first_observation or (force and _encounter_cleared()):
		_clear_seen = true
		next = _clear_candidate(next)
	if boss_observation or (force and _boss_encounter_cleared()):
		_boss_clear_seen = true
		next.chapter_flags.lakius_cleared = true
	for key: String in CHAPTER_META:
		if _chapter_receipts[key]:
			next.chapter_flags[key] = true
	# Clear before I/O, including validation/storage-ready errors that cannot
	# create a pending bundle. Only a manual save/retry may repeat a failed write.
	_chapter_attempt_due = false
	return _commit(next)


func claim_first_drop() -> bool:
	if not _pending_bundle.is_empty():
		return _error("请先保存上一笔进度，再继续。")
	if progress.first_drop.state != "pending":
		return false
	var next: Dictionary = progress.duplicate(true)
	next.first_drop.state = "claimed"
	next.inventory[ITEM_KEY] = 1
	return _commit(next)


func hp_potion_count() -> int:
	return int(progress.inventory.get(HP_POTION_KEY, 0))


func hp_potion_price() -> int:
	return HP_POTION_PRICE


func hp_potion_capacity() -> int:
	return HP_POTION_MAX


func buy_hp_potion() -> bool:
	if not _pending_bundle.is_empty():
		return _error("请先保存上一笔进度，再购买。")
	if int(progress.coins) < HP_POTION_PRICE or hp_potion_count() >= HP_POTION_MAX:
		return false
	var next: Dictionary = progress.duplicate(true)
	next.coins = int(progress.coins) - HP_POTION_PRICE
	next.inventory[HP_POTION_KEY] = hp_potion_count() + 1
	return _commit(next)


func consume_hp_potion() -> bool:
	if not _pending_bundle.is_empty():
		return _error("请先保存上一笔进度，再使用药剂。")
	if hp_potion_count() <= 0:
		return false
	var next: Dictionary = progress.duplicate(true)
	next.inventory[HP_POTION_KEY] = hp_potion_count() - 1
	# Healing is a synchronous session effect owned by the H controller. Never
	# leave a failed deduction for generic save/retry to execute without healing.
	return _commit(next, false)


func owns_weapon(key: String) -> bool:
	if key == PRACTICE_WEAPON:
		return true
	return key == REWARD_WEAPON and progress.equipment.owned[REWARD_WEAPON]


func equipped_weapon_key() -> String:
	return str(progress.equipment.equipped_key)


func weapon_damage_bonus() -> int:
	if equipped_weapon_key() != REWARD_WEAPON or not owns_weapon(REWARD_WEAPON):
		return 0
	# Only the adapted catalog value is used. Source attack72 and the source
	# minimum level are provenance, never HP damage or an equipment level gate.
	var item: Dictionary = equipment_data.get("items", {}).get(REWARD_WEAPON, {})
	var bonus: Variant = item.get("prototype_damage_bonus")
	return int(bonus) if typeof(bonus) in [TYPE_INT, TYPE_FLOAT] and float(bonus) == 4.0 else 0


func equip_weapon(key: String) -> bool:
	if not _pending_bundle.is_empty():
		return _error("请先保存上一笔进度，再继续。")
	if not owns_weapon(key):
		return false
	if equipped_weapon_key() == key:
		return true
	var next: Dictionary = progress.duplicate(true)
	next.equipment.equipped_key = key
	return _commit(next)


func retry_pending_save() -> bool:
	_observe_chapters()
	if _pending_bundle.is_empty():
		return false
	return _commit(_pending_bundle.duplicate(true))


func load_progress() -> bool:
	if not _pending_bundle.is_empty() or _has_chapter_receipts():
		return _error("还有进度尚未保存，请先重试保存。")
	loaded_from_backup = false
	if not FileAccess.file_exists(storage_path) and not FileAccess.file_exists(storage_path + ".bak"):
		_storage_ready = true
		last_error = ""
		progress_changed.emit()
		return true
	var loaded: Dictionary = _read_valid(storage_path)
	if loaded.is_empty():
		loaded = _read_valid(storage_path + ".bak")
		loaded_from_backup = not loaded.is_empty()
	if loaded.is_empty():
		_storage_ready = false
		return _error("委托存档无法读取，原文件已保留。")
	progress = loaded
	_storage_ready = true
	last_error = ""
	_clear_seen = not _needs_clear_observation(progress)
	_boss_clear_seen = progress.chapter_flags.lakius_cleared
	if progress.first_drop.state != "unearned" and not get_tree().has_meta("first_encounter_state"):
		get_tree().set_meta("first_encounter_state", {"cleared": true})
	if progress.chapter_flags.lakius_cleared and not get_tree().has_meta("tower_boss_state"):
		get_tree().set_meta("tower_boss_state", {"cleared": true})
	if progress.chapter_flags.stonemaster_cleared and not get_tree().has_meta("doll_gallery_state"):
		get_tree().set_meta("doll_gallery_state", {"cleared": true, "enemy_hp": 0})
	if progress.chapter_flags.statue_cleared and not get_tree().has_meta("statue_gallery_state"):
		get_tree().set_meta("statue_gallery_state", {"cleared": true, "enemy_hp": 0, "awakened": true})
	progress_changed.emit()
	return true


func capture_state() -> Dictionary:
	return {"progress": progress.duplicate(true), "storage_path": storage_path, "last_error": last_error,
		"storage_ready": _storage_ready, "loaded_from_backup": loaded_from_backup,
		"save_attempts": _save_attempts,
		"pending_save": not _pending_bundle.is_empty(),
		"chapter_receipts": _chapter_receipts.duplicate(true), "chapter_attempt_due": _chapter_attempt_due,
		"dialog_open": _dialog_open, "encounter_cleared": _encounter_cleared(),
		"region_scene": main.scene_file_path if is_instance_valid(main) else ""}


func _commit(next: Dictionary, retain_on_failure: bool = true) -> bool:
	_save_attempts += 1
	if not retain_on_failure and not _pending_bundle.is_empty():
		return _error("请先保存上一笔进度，再继续。")
	if not _pending_bundle.is_empty() and _pending_bundle != next:
		return _error("请先保存上一笔进度，再继续。")
	if not _storage_ready or not _valid(next):
		return _error("委托进度尚未保存，请先检查存档。")
	# Retryable operations keep their exact candidate across R/reset. A
	# synchronous consumable deduction opts out before any write attempt.
	if retain_on_failure:
		_pending_bundle = next.duplicate(true)
	var folder: String = ProjectSettings.globalize_path(storage_path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return _error("暂时无法保存委托进度，请稍后重试。")
	var temporary: String = storage_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error("暂时无法保存委托进度，请稍后重试。")
	file.store_string(JSON.stringify(next) + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or _read_valid(temporary).is_empty():
		return _error("委托进度保存失败，请重试。")
	if FileAccess.file_exists(storage_path):
		var primary_valid: bool = not _read_valid(storage_path).is_empty()
		var copy_target: String = storage_path + ".bak.tmp" if primary_valid else storage_path + ".invalid." + str(Time.get_ticks_usec())
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(storage_path), ProjectSettings.globalize_path(copy_target)) != OK:
			return _error("无法保留旧存档，本次进度尚未保存。")
		if primary_valid and DirAccess.rename_absolute(ProjectSettings.globalize_path(copy_target), ProjectSettings.globalize_path(storage_path + ".bak")) != OK:
			return _error("无法备份委托存档，请重试。")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(storage_path)) != OK:
		return _error("无法更新委托存档，请重试。")
	progress = next.duplicate(true)
	_pending_bundle = {}
	last_error = ""
	loaded_from_backup = false
	_clear_seen = not _needs_clear_observation(progress)
	_boss_clear_seen = progress.chapter_flags.lakius_cleared
	for key: String in CHAPTER_META:
		if progress.chapter_flags[key]:
			_chapter_receipts[key] = false
	# A successful exact retry settles only its own receipts. Other verified
	# events get a separate single attempt on the next process tick.
	_chapter_attempt_due = _has_chapter_receipts()
	_refresh_ui()
	progress_changed.emit()
	return true


func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 16384:
		return {}
	var parser: JSON = JSON.new()
	var result: Error = parser.parse(file.get_as_text())
	file.close()
	if result != OK:
		return {}
	var parsed: Variant = parser.data
	return _normalize(parsed) if parsed is Dictionary else {}


func _valid(value: Dictionary) -> bool:
	return _schema_is(value, PROFILE_SCHEMA) and _valid_equipment(value) and _valid_chapters(value, false)


func _valid_five(value: Dictionary) -> bool:
	return _schema_is(value, 5) and _valid_equipment(value) and _valid_chapters(value, true)


func _valid_chapters(value: Dictionary, legacy: bool) -> bool:
	if not value.get("chapter_flags") is Dictionary or value.chapter_flags.size() != (1 if legacy else 3):
		return false
	var keys: Array = ["lakius_cleared"] if legacy else ["lakius_cleared", "stonemaster_cleared", "statue_cleared"]
	for key: String in keys:
		if typeof(value.chapter_flags.get(key)) != TYPE_BOOL:
			return false
	# Later victories are independent receipts, never evidence to mint old loot.
	return not value.chapter_flags.lakius_cleared or value.first_drop.state != "unearned"


func _valid_equipment(value: Dictionary, legacy: bool = false) -> bool:
	if not _valid_quest(value, legacy) or not _valid_loot(value, legacy):
		return false
	if not value.get("equipment") is Dictionary or value.equipment.size() != 2:
		return false
	var equipment: Dictionary = value.equipment
	if not equipment.get("owned") is Dictionary or equipment.owned.size() != 1 or not equipment.owned.has(REWARD_WEAPON):
		return false
	if typeof(equipment.owned[REWARD_WEAPON]) != TYPE_BOOL or equipment.owned[REWARD_WEAPON] != value.reward_granted:
		return false
	if typeof(equipment.get("equipped_key")) != TYPE_STRING or not equipment.equipped_key in [PRACTICE_WEAPON, REWARD_WEAPON]:
		return false
	return equipment.equipped_key == PRACTICE_WEAPON or equipment.owned[REWARD_WEAPON]


func _valid_loot(value: Dictionary, legacy: bool = false) -> bool:
	if not _valid_quest(value, legacy):
		return false
	if not value.get("inventory") is Dictionary or value.inventory.size() != (1 if legacy else 2) or not value.inventory.has(ITEM_KEY):
		return false
	if not legacy:
		var potions: Variant = value.inventory.get(HP_POTION_KEY)
		if typeof(potions) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(potions)) or float(potions) != floorf(float(potions)) or float(potions) < 0.0 or float(potions) > HP_POTION_MAX:
			return false
		if (not value.reward_granted and float(potions) != 0.0) or float(potions) > (40.0 - float(value.coins)) / HP_POTION_PRICE:
			return false
	var count: Variant = value.inventory[ITEM_KEY]
	if typeof(count) not in [TYPE_INT, TYPE_FLOAT] or not float(count) in [0.0, 1.0]:
		return false
	if not value.get("first_drop") is Dictionary:
		return false
	var drop: Dictionary = value.first_drop
	if typeof(drop.get("id")) != TYPE_STRING or typeof(drop.get("region")) != TYPE_STRING or typeof(drop.get("state")) != TYPE_STRING:
		return false
	if drop.id != DROP_ID or drop.region != "hall":
		return false
	if not drop.state in ["unearned", "pending", "claimed"]:
		return false
	var point: Variant = drop.get("position")
	if not point is Array or point.size() != 2:
		return false
	for component: Variant in point:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			return false
	if float(point[0]) < 120.0 or float(point[0]) > 776.0 or float(point[1]) < 245.0 or float(point[1]) > 345.0:
		return false
	if float(count) != (1.0 if drop.state == "claimed" else 0.0):
		return false
	if value.quest_stage == "active" and drop.state != "unearned":
		return false
	return not value.objective_cleared or drop.state != "unearned"


func _valid_quest(value: Dictionary, legacy: bool = false) -> bool:
	if typeof(value.get("quest_stage")) != TYPE_STRING or not value.quest_stage in STAGES:
		return false
	if typeof(value.get("reward_granted")) != TYPE_BOOL or typeof(value.get("coins")) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	if typeof(value.get("objective_cleared")) != TYPE_BOOL:
		return false
	if (value.quest_stage in ["return", "completed"]) != value.objective_cleared:
		return false
	var granted: bool = value.reward_granted
	if (value.quest_stage == "completed") != granted:
		return false
	if legacy:
		return float(value.coins) == (float(data.get("reward_coins", 40)) if granted else 0.0)
	var coins: float = float(value.coins)
	return is_finite(coins) and coins >= 0.0 and coins <= 40.0 and fmod(coins, HP_POTION_PRICE) == 0.0 and (granted or coins == 0.0)


func _schema_is(value: Dictionary, version: int) -> bool:
	return typeof(value.get("schema")) in [TYPE_INT, TYPE_FLOAT] and float(value.schema) == float(version)


func _normalize(value: Dictionary) -> Dictionary:
	if _valid(value):
		return value
	if _valid_five(value):
		return _upgrade_five(value)
	if _schema_is(value, 4) and _valid_equipment(value, true):
		if not value.get("chapter_flags") is Dictionary or value.chapter_flags.size() != 1 or typeof(value.chapter_flags.get("lakius_cleared")) != TYPE_BOOL:
			return {}
		if value.chapter_flags.lakius_cleared and value.first_drop.state == "unearned":
			return {}
		var previous: Dictionary = value.duplicate(true)
		previous.schema = 5
		previous.inventory[HP_POTION_KEY] = 0
		return _upgrade_five(previous) if _valid_five(previous) else {}
	if _schema_is(value, 3) and _valid_equipment(value, true):
		var previous: Dictionary = value.duplicate(true)
		previous.schema = 5
		previous.inventory[HP_POTION_KEY] = 0
		previous.chapter_flags = {"lakius_cleared": false}
		return _upgrade_five(previous) if _valid_five(previous) else {}
	var legacy_one: bool = _schema_is(value, 1) and _valid_quest(value, true)
	var legacy_two: bool = _schema_is(value, 2) and _valid_loot(value, true)
	if not legacy_one and not legacy_two:
		return {}
	var converted: Dictionary = value.duplicate(true)
	converted.schema = 5
	if legacy_one:
		converted.inventory = {ITEM_KEY: 0}
		converted.first_drop = {"id": DROP_ID, "state": "pending" if value.objective_cleared else "unearned", "region": "hall", "position": [640, 300]}
	converted.inventory[HP_POTION_KEY] = 0
	# A legitimate historical completion gains ownership, while the accepted
	# default appearance stays unchanged. Loading never writes or auto-equips.
	converted.equipment = {"owned": {REWARD_WEAPON: bool(value.reward_granted)}, "equipped_key": PRACTICE_WEAPON}
	converted.chapter_flags = {"lakius_cleared": false}
	return _upgrade_five(converted) if _valid_five(converted) else {}


func _upgrade_five(value: Dictionary) -> Dictionary:
	var upgraded: Dictionary = value.duplicate(true)
	upgraded.schema = PROFILE_SCHEMA
	upgraded.chapter_flags.stonemaster_cleared = false
	upgraded.chapter_flags.statue_cleared = false
	return upgraded if _valid(upgraded) else {}


func _default_progress() -> Dictionary:
	return {"schema": PROFILE_SCHEMA, "quest_stage": "available", "objective_cleared": false, "reward_granted": false, "coins": 0,
		"inventory": {ITEM_KEY: 0, HP_POTION_KEY: 0}, "first_drop": {"id": DROP_ID, "state": "unearned", "region": "hall", "position": [640, 300]},
		"equipment": {"owned": {REWARD_WEAPON: false}, "equipped_key": PRACTICE_WEAPON}, "chapter_flags": {"lakius_cleared": false, "stonemaster_cleared": false, "statue_cleared": false}}


func _needs_clear_observation(value: Dictionary) -> bool:
	return value.first_drop.state == "unearned" or value.quest_stage == "active"


func _clear_candidate(value: Dictionary) -> Dictionary:
	var next: Dictionary = value.duplicate(true)
	if not _encounter_cleared():
		return next
	if next.first_drop.state == "unearned":
		var session: Dictionary = get_tree().get_meta("first_encounter_state", {})
		var raw: Variant = session.get("enemy_position", Vector2(640, 300))
		var point: Vector2 = Vector2(640, 300)
		if raw is Vector2 and is_finite(raw.x) and is_finite(raw.y):
			point = raw
		next.first_drop.state = "pending"
		next.first_drop.position = [clampf(point.x, 120.0, 776.0), clampf(point.y, 245.0, 345.0)]
	if next.quest_stage == "active":
		next.quest_stage = "return"
		next.objective_cleared = true
	return next


func _encounter_cleared() -> bool:
	var state: Variant = get_tree().get_meta("first_encounter_state", {})
	return state is Dictionary and typeof(state.get("cleared")) == TYPE_BOOL and state.cleared


func _boss_encounter_cleared() -> bool:
	var state: Variant = get_tree().get_meta("tower_boss_state", {})
	return state is Dictionary and typeof(state.get("cleared")) == TYPE_BOOL and state.cleared


func _eligible_area() -> bool:
	return _is_region_scene() and get_tree().current_scene == main


func _is_region_scene() -> bool:
	return is_instance_valid(main) and main.scene_file_path in ["res://scenes/west_coast_r1.tscn", "res://scenes/tower_approach.tscn", "res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"]


func _error(message: String) -> bool:
	last_error = message
	_refresh_ui()
	return false


func _confirm_dialog() -> void:
	if not last_error.is_empty():
		save_progress()
	elif progress.quest_stage == "available":
		accept_quest()
	elif progress.quest_stage == "return":
		claim_reward()
	_refresh_ui()


func _build_dialog(theme: Theme) -> void:
	_layer = CanvasLayer.new()
	_layer.name = "QuestDialog"
	_layer.layer = 110
	_layer.visible = false
	add_child(_layer)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(shade)
	var panel: PanelContainer = PanelContainer.new()
	panel.theme = theme
	panel.position = Vector2(260, 150)
	panel.custom_minimum_size = Vector2(440, 240)
	var frame: StyleBoxFlat = StyleBoxFlat.new()
	frame.bg_color = Color(0.055, 0.08, 0.11, 0.97)
	frame.border_color = Color(0.64, 0.50, 0.29, 0.95)
	frame.set_border_width_all(1)
	frame.set_content_margin_all(18.0)
	panel.add_theme_stylebox_override("panel", frame)
	shade.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var heading: Label = Label.new()
	heading.text = str(data.npc_name) + " · " + str(data.title)
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color(0.95, 0.85, 0.63))
	column.add_child(heading)
	_body = Label.new()
	_body.custom_minimum_size = Vector2(376, 92)
	_body.add_theme_font_size_override("font_size", 14)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_body)
	var buttons: HBoxContainer = HBoxContainer.new()
	column.add_child(buttons)
	_confirm = Button.new()
	_confirm.pressed.connect(_confirm_dialog)
	buttons.add_child(_confirm)
	_close = Button.new()
	_close.pressed.connect(close_dialog)
	buttons.add_child(_close)
	var shortcuts: Label = Label.new()
	shortcuts.text = "Enter 确认  ·  E / Esc 关闭"
	shortcuts.add_theme_font_size_override("font_size", 11)
	shortcuts.modulate = Color(0.76, 0.79, 0.80)
	column.add_child(shortcuts)


func _refresh_ui() -> void:
	if data.is_empty():
		return
	var stage: Dictionary = data.stages[progress.quest_stage]
	if is_instance_valid(_hud):
		_hud.visible = _eligible_area() and bool(main.get_node("Interface").get("visible"))
		_hud.text = str(stage.objective)
		if progress.quest_stage == "completed":
			_hud.text = "鲁卡斯已击退 · 可原路返港" if progress.chapter_flags.lakius_cleared else "继续向塔内深处探索"
		if int(progress.coins) > 0:
			_hud.text += " · 金币 " + str(progress.coins)
		if not last_error.is_empty():
			_hud.text += " · 进度未保存"
	if is_instance_valid(_prompt):
		_prompt.visible = can_interact() and bool(main.get_node("Interface").get("visible"))
		if is_instance_valid(main) and main.get("framing") != null:
			var point: Vector2 = Vector2(data.npc_source_position[0], data.npc_source_position[1])
			point += Vector2(-_prompt.size.x * 0.5, 43.0 - main.npc_lo._foot_anchor.y - 24.0)
			_prompt.position = point - Vector2(main.framing.offset_x, main.framing.offset_y)
	if _dialog_open and is_instance_valid(_body):
		_body.text = str(stage.dialog) if last_error.is_empty() else last_error
		_confirm.visible = stage.has("confirm") or not last_error.is_empty()
		_confirm.text = "重试保存" if not last_error.is_empty() else str(stage.get("confirm", ""))
		_close.text = str(stage.close)
