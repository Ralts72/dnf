extends Node
## Opt-in wall-clock frame trace. Disabled by default, with no idle sampling.
## Buffers are bounded; writing happens only on an explicit save shortcut.

const CAPACITY: int=2048
const EVENT_LIMIT: int=128
const ACTIONS: Array[String]=["stay","move","dash","attack1","attack2","attack3","hopsmash","jump","jumpattack","sit","damage1","damage2","down","guard","hardattack"]
const COLUMNS: Array[String]=["elapsed_s","wall_gap_ms","engine_delta_ms","frames_drawn","previous_process_ms","previous_physics_ms","focused","scene_id","action_id","source_frame","source_elapsed_ms","jump_height_px","effect_tracks","walk_subframe","walk_active"]
var active: bool=false
var panel: PanelContainer
var label: Label
var buffer: Array=[]
var cursor: int=0
var sample_count: int=0
var slow_count: int=0
var longest_ms: float=0.0
var session_start_usec: int=0
var session_started_unix_s: float=0.0
var previous_usec: int=0
var label_clock: float=0.0
var events: Array=[]
var last_export: String=""
var last_notice: String=""
var sampler_max_usec: int=0


static func ensure(tree: SceneTree) -> Node:
	var existing: Node=tree.root.get_node_or_null("FrameDiagnostics")
	if existing!=null:return existing
	var monitor: Node=load("res://scripts/frame_diagnostics.gd").new()
	monitor.name="FrameDiagnostics"
	tree.root.call_deferred("add_child",monitor)
	return monitor


func _ready() -> void:
	buffer.resize(CAPACITY)
	process_priority=1000000
	var layer:=CanvasLayer.new();layer.layer=90;add_child(layer)
	panel=PanelContainer.new();panel.position=Vector2(42,76)
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(.035,.06,.085,.94)
	style.border_color=Color(.39,.60,.66,.8)
	style.set_border_width_all(1);style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel",style)
	layer.add_child(panel)
	label=Label.new();label.custom_minimum_size=Vector2(310,0)
	label.add_theme_font_size_override("font_size",14)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	get_tree().root.focus_entered.connect(_focus_event.bind(true))
	get_tree().root.focus_exited.connect(_focus_event.bind(false))
	get_tree().scene_changed.connect(_scene_event)
	panel.hide();set_process(false)


func set_active(value: bool) -> void:
	active=value;panel.visible=value
	set_process(value)
	previous_usec=0
	if value:
		cursor=0;sample_count=0;slow_count=0;longest_ms=0;sampler_max_usec=0
		events.clear();last_notice="";session_start_usec=Time.get_ticks_usec();session_started_unix_s=Time.get_unix_time_from_system();label_clock=0
		_refresh_label()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode!=KEY_F12:return
	if event.ctrl_pressed or event.meta_pressed:
		if sample_count>0:save_trace()
		else:last_notice="先按 F12 开始观察"
	else:set_active(not active)
	get_viewport().set_input_as_handled()


func _focus_event(focused: bool) -> void:
	if active:_event({"type":"window_focus","focused":focused})


func _scene_event() -> void:
	if active:_event({"type":"scene_changed","scene":get_tree().current_scene.scene_file_path if get_tree().current_scene else ""})


func _event(value: Dictionary) -> void:
	value["elapsed_s"]=float(Time.get_ticks_usec()-session_start_usec)/1000000.0
	events.append(value)
	if events.size()>EVENT_LIMIT:events.pop_front()


func _process(delta: float) -> void:
	var now: int=Time.get_ticks_usec()
	if previous_usec==0:
		previous_usec=now
		return
	var gap: float=float(now-previous_usec)/1000.0;previous_usec=now
	var scene: Node=get_tree().current_scene
	var is_port: bool=scene!=null and scene.scene_file_path in ["res://scenes/west_coast_r0.tscn","res://scenes/west_coast_r1.tscn","res://scenes/tower_approach.tscn","res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"]
	var p: Node=scene.player if is_port else null
	var row:=PackedFloat64Array([float(now-session_start_usec)/1000000.0,gap,delta*1000.0,Engine.get_frames_drawn(),
		Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		1.0 if DisplayServer.window_is_focused() else 0.0,1 if is_port and scene.name=="WestCoastR1" else (0 if is_port else -1),
		ACTIONS.find(p.animation_name) if p else -1,p.frame_index if p else -1,p.elapsed_ms if p else 0,
		p.jump_motion.height_pixels if p else 0,p.action_effects.active_frames.size() if p else 0,
		p.walk_inbetweens.subframe if p and p.walk_inbetweens else 0,1.0 if p and p.walk_inbetweens and p.walk_inbetweens.active else 0.0])
	buffer[cursor]=row;cursor=(cursor+1)%CAPACITY;sample_count+=1
	longest_ms=maxf(longest_ms,gap)
	if gap>1000.0/60.0:
		slow_count+=1
		_event({"type":"slow_frame","wall_gap_ms":gap,"scene":scene.scene_file_path if scene else "",
			"action":p.animation_name if p else "","source_frame":p.frame_index if p else -1,
			"walk_subframe":p.walk_inbetweens.subframe if p and p.walk_inbetweens else 0,
			"walk_active":p.walk_inbetweens.active if p and p.walk_inbetweens else false,
			"source_position":p.world_to_source(p.position) if p and scene.name=="WestCoastR1" else (p.position if p else Vector2.ZERO),
			"focused":DisplayServer.window_is_focused(),"resource_count":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			"pipeline_counts":pipeline_counts()})
	label_clock+=delta
	if label_clock>=.25:
		label_clock=0;_refresh_label()
	sampler_max_usec=maxi(sampler_max_usec,Time.get_ticks_usec()-now)


func pipeline_counts() -> Dictionary:
	return {"canvas":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS),
		"mesh":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
		"surface":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
		"draw":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
		"specialization":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)}


func recent_rows() -> Array:
	var result: Array=[]
	var count: int=mini(sample_count,CAPACITY)
	for i: int in count:result.append(buffer[(cursor-count+i+CAPACITY)%CAPACITY])
	return result


func statistics(rows: Array) -> Dictionary:
	if rows.is_empty():return {"fps":0.0,"p95_ms":0.0,"count":0}
	var values: Array[float]=[]
	var total: float=0
	for row: PackedFloat64Array in rows:values.append(row[1]);total+=row[1]
	values.sort()
	return {"fps":1000.0*values.size()/total if total>0 else 0.0,"p95_ms":values[ceili((values.size()-1)*.95)],"count":rows.size()}


func cadence() -> String:
	var scene: Node=get_tree().current_scene
	if scene==null or scene.scene_file_path not in ["res://scenes/west_coast_r0.tscn","res://scenes/west_coast_r1.tscn","res://scenes/tower_approach.tscn","res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"]:return "场景切换中"
	var p: Node=scene.player
	var title: String=preload("res://scripts/source_preview_controls.gd").ACTION_NAMES[p.animation_name]
	if p.paused:title="已暂停 · "+title
	if p.jump_motion.is_active():return title+" · 随跳跃阶段切换"
	if p.walk_inbetweens and p.walk_inbetweens.active:return title+" · 原图 10.0 / 下肢 30.0 次/秒"
	var frames: Array=p._animations[p.animation_name]["frames"]
	var duration: float=0
	for frame: Dictionary in frames:duration+=float(frame["duration_ms"])
	return "%s · 原图平均 %.1f 次/秒"%[title,1000.0*frames.size()/duration]


func _refresh_label() -> void:
	var elapsed: float=float(Time.get_ticks_usec()-session_start_usec)/1000000.0
	var recent: Array=recent_rows().filter(func(row: PackedFloat64Array):return elapsed-row[0]<=1.0)
	var summary: Dictionary=statistics(recent)
	label.text="帧率观察  F12 关闭\n渲染 %.0f FPS · 最近1秒 P95 %.2f ms\n%s\n本次超过 16.7 ms：%d 帧 · 最长 %.2f ms\nCtrl / ⌘ + F12 保存最近记录"%[summary.fps,summary.p95_ms,cadence(),slow_count,longest_ms]
	if not last_notice.is_empty():label.text+="\n"+last_notice
	label.tooltip_text=ProjectSettings.globalize_path(last_export) if not last_export.is_empty() else ""


func save_trace() -> Dictionary:
	if sample_count==0:return {"error":"No sampled frames"}
	var rows: Array=recent_rows()
	var scene: Node=get_tree().current_scene
	var report: Dictionary={"schema":2,"created_at":Time.get_datetime_string_from_system(),"session_started_unix_s":session_started_unix_s,"godot":Engine.get_version_info()["string"],
		"scene":scene.scene_file_path if scene else "","columns":COLUMNS,"actions":ACTIONS,"rows":rows,"events":events.duplicate(true),
		"build":scene.get_node("Interface/Build").text if scene and scene.has_node("Interface/Build") else "",
		"walk_source_data_sha256":FileAccess.get_sha256("res://data/swordman_walk_inbetweens.json"),
		"dash_source_data_sha256":FileAccess.get_sha256("res://data/swordman_dash_inbetweens.json"),
		"session_sample_count":sample_count,"retained_rows":rows.size(),"overwritten_rows":maxi(0,sample_count-CAPACITY),
		"session_slow_frames":slow_count,"session_longest_ms":longest_ms,"retained_statistics":statistics(rows),
		"sampler_max_usec":sampler_max_usec,"native_window":DisplayServer.window_get_size(),"pipelines_at_save":pipeline_counts(),
		"source_sha256":get_script().source_code.sha256_text(),
		"notes":["Wall gaps sampled only while F12 observation is enabled. Session totals and retained-window statistics have different scopes.",
			"Main-loop wall gaps do not prove display presentation, GPU duration, or a specific cause.",
			"At most 2048 rows and 128 events. No screenshot or automatic disk writes during observation.",
			"The explicit export itself happens after this snapshot and may delay a subsequent frame."]}
	DirAccess.make_dir_recursive_absolute("user://diagnostics")
	last_export="user://diagnostics/frame_trace_%d.json"%Time.get_ticks_usec()
	var output:=FileAccess.open(last_export,FileAccess.WRITE)
	if output==null:
		last_notice="保存失败："+str(FileAccess.get_open_error())
		return {"error":last_notice}
	output.store_string(JSON.stringify(report));output.close()
	last_notice="已保存到用户目录 diagnostics/"
	_event({"type":"explicit_export","path":last_export})
	if active:_refresh_label()
	return {"path":last_export,"absolute_path":ProjectSettings.globalize_path(last_export),"rows":rows.size()}
