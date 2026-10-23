extends Node
## Finite native-clock A/B review; restores the production scene on completion.

var status: String="new"
var main: Node
var original: Dictionary
var original_update: int
var board: SubViewport
var layer: CanvasLayer
var source_actor: Node2D
var derived_actor: Node2D
var start_usec: int=0
var duration: float=4.8
var current_id: int=-1
var current_cycle: int=0
var previous_drawn_id: int=-1
var transitions: Array=[]
var frame_gaps: Array[float]=[]
var last_draw_usec: int=0
var report: Dictionary={}


func start(root: Node) -> Dictionary:
	main=root;original=main.player.capture_state()
	original_update=main.render_viewport.render_target_update_mode
	main._set_paused(true)
	main.render_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	board=SubViewport.new();board.size=Vector2i(1280,448)
	board.world_2d=World2D.new();board.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(board)
	var bg:=ColorRect.new();bg.size=Vector2(1280,448);bg.color=Color(.2,.25,.28);board.add_child(bg)
	var script:=GDScript.new()
	script.source_code=FileAccess.get_file_as_string("res://source_art/r1/experiments/dash_cycle_26/baked_actor.gd")
	assert(script.reload()==OK)
	source_actor=script.new();source_actor.scale=Vector2(2,2);board.add_child(source_actor)
	derived_actor=script.new();derived_actor.scale=Vector2(2,2);derived_actor.position.x=640;board.add_child(derived_actor)
	layer=CanvasLayer.new();layer.layer=80;get_tree().root.add_child(layer)
	var plate:=ColorRect.new();plate.position=Vector2(32,92);plate.size=Vector2(896,374);plate.color=Color(.04,.065,.08);plate.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(plate)
	var view:=TextureRect.new();view.position=Vector2(32,132);view.size=Vector2(896,313.6);view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	view.texture=board.get_texture();view.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;view.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(view)
	for side: int in 2:
		var title:=Label.new();title.position=Vector2(48+448*side,102);title.add_theme_font_size_override("font_size",16)
		title.text=["奔跑原图：8 帧／800 ms","分层过渡：24 个采样／800 ms"][side];layer.add_child(title)
	start_usec=Time.get_ticks_usec();last_draw_usec=start_usec
	RenderingServer.frame_post_draw.connect(_drawn)
	status="sampling"
	return snapshot()


func _process(_delta: float) -> void:
	if status!="sampling":return
	var elapsed: float=float(Time.get_ticks_usec()-start_usec)/1000000.0
	if elapsed>=duration:
		finish()
		return
	var ms: float=fmod(elapsed*1000.0,800.0)
	var frame: int=mini(7,int(ms/100.0))
	var sub: int=mini(2,int(fmod(ms,100.0)/(100.0/3.0)))
	var id: int=3*frame+sub
	if id!=current_id:
		if frame!=source_actor.frame_index:source_actor.update_pose(frame,0)
		derived_actor.update_pose(frame,sub)
		current_id=id;current_cycle=int(elapsed/.8)


func _drawn() -> void:
	if status!="sampling" or current_id<0:return
	var now: int=Time.get_ticks_usec()
	frame_gaps.append(float(now-last_draw_usec)/1000.0);last_draw_usec=now
	if current_id!=previous_drawn_id:
		var elapsed: float=float(now-start_usec)/1000.0
		transitions.append({"phase_id":current_id,"cycle":current_cycle,"drawn_at_ms":elapsed,
			"nominal_start_ms":current_cycle*800.0+current_id*100.0/3.0,
			"lag_ms":elapsed-(current_cycle*800.0+current_id*100.0/3.0)})
		previous_drawn_id=current_id


func finish() -> void:
	status="finishing";set_process(false)
	RenderingServer.frame_post_draw.disconnect(_drawn)
	await RenderingServer.frame_post_draw
	board.get_texture().get_image().save_png("res://docs/previews/r1_26_playback_board.png")
	var seen: Dictionary={}
	var skipped: Array=[]
	for i: int in transitions.size():
		var row: Dictionary=transitions[i];seen[row.phase_id]=true
		if i>0 and row.phase_id!=(int(transitions[i-1].phase_id)+1)%24:skipped.append(row)
	var checks: Array=[{"check":"all_24_samples_observed","pass":seen.size()==24},
		{"check":"no_phase_skipped_in_native_draw_callbacks","pass":skipped.is_empty()},
		{"check":"at_least_five_complete_cycles","pass":transitions.size()>=120},
		{"check":"nominal_source_cycle_stays_800ms","pass":derived_actor.recipe.cycle_ms==800 and derived_actor.recipe.original_frame_ms==100},
		{"check":"both_review_actors_still_present","pass":is_instance_valid(source_actor) and is_instance_valid(derived_actor)}]
	report={"study":"R1/26 finite native-clock dash comparison","status":"complete","checks":checks,
		"failed":checks.filter(func(c):return not c.pass),"transitions":transitions,"frame_gaps_ms":frame_gaps,"skipped":skipped,
		"duration_s":duration,"qa_source_sha256":get_script().source_code.sha256_text(),
		"actor_source_sha256":derived_actor.get_script().source_code.sha256_text(),
		"note":"Native frame_post_draw state association. Exact frame colors are tested independently by the 48-case gallery. This is not display presentation or a full-game benchmark."}
	main.render_viewport.render_target_update_mode=original_update as SubViewport.UpdateMode
	main.player.restore_state(original);main._set_paused(original.paused)
	layer.queue_free();board.queue_free()
	var output:=FileAccess.open("res://docs/r1_26_playback_checks.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	status="complete"


func snapshot() -> Dictionary:
	return {"status":status,"elapsed_s":float(Time.get_ticks_usec()-start_usec)/1000000.0,"drawn_frames":frame_gaps.size(),"phase_transitions":transitions.size(),
		"failed":report.get("failed",[])}
