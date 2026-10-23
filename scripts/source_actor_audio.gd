extends Node
## Action clock independent of frame seeking. Only the current scene is audible.

const DATA_PATH: String="res://data/swordman_audio.json"
const VOICES: int=8
var actor: Node
var data: Dictionary={}
var streams: Dictionary={}
var voices: Array[AudioStreamPlayer]=[]
var pending: Array=[]
var clock_ms: float=0.0
var output_enabled: bool=true
var audit: Array=[]
var event_count: int=0
var _voice_index: int=0
var _rng:=RandomNumberGenerator.new()


func setup(source_actor: Node) -> void:
	actor=source_actor
	data=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	for tag: String in data["sounds"]:
		streams[tag]=load(data["sounds"][tag]["path"])
	for i: int in VOICES:
		var voice:=AudioStreamPlayer.new()
		voice.name="Voice%d"%i
		add_child(voice)
		voices.append(voice)
	_rng.randomize()
	apply_preferences()


func apply_preferences() -> void:
	var tree:=get_tree()
	var volume: float=float(tree.get_meta("port_audio_volume",data["default_volume"]))
	var muted: bool=tree.get_meta("port_audio_muted",false)
	for voice: AudioStreamPlayer in voices:
		voice.volume_db=linear_to_db(maxf(volume,.0001))
		if muted:
			voice.stop()


func set_paused(value: bool) -> void:
	for voice: AudioStreamPlayer in voices:
		voice.stream_paused=value


func stop() -> void:
	pending.clear()
	clock_ms=0.0
	for voice: AudioStreamPlayer in voices:
		voice.stop()


func finish() -> void:
	pending.clear()


func begin_action(action: String) -> void:
	stop()
	# The prototype Upper Slash reuses Attack3's pose and existing swing cues;
	# this does not claim an original dedicated UpperSlash audio dispatcher.
	_add_action("attack3" if action == "upperslash" else action,0.0,INF)
	_dispatch_due()


func begin_jump(prep: float,flight: float) -> void:
	stop()
	for tag: String in data["jump"]["takeoff"]:
		pending.append({"at_ms":prep*1000.0,"tag":tag})
	for tag: String in data["jump"]["landing"]:
		pending.append({"at_ms":(prep+flight)*1000.0,"tag":tag})


func begin_air_attack(landing_seconds: float) -> void:
	_add_action("jumpattack",clock_ms,landing_seconds*1000.0)
	_dispatch_due()


func _add_action(action: String,start_ms: float,last_ms: float) -> void:
	for cue: Dictionary in data["actions"].get(action,[]):
		var time: float=start_ms+float(cue["at_ms"])
		if time<last_ms:
			pending.append({"at_ms":time,"tag":cue["tag"]})
	pending.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a["at_ms"]<b["at_ms"])


func advance(delta: float) -> void:
	clock_ms+=delta*1000.0
	_dispatch_due()


func _dispatch_due() -> void:
	while not pending.is_empty() and float(pending[0]["at_ms"])<=clock_ms+.000001:
		var cue: Dictionary=pending.pop_front()
		_emit(cue)


func _resolve(tag: String) -> String:
	if not data["groups"].has(tag):
		return tag
	var group: Array=data["groups"][tag]
	var total: int=0
	for item: Dictionary in group:
		total+=int(item["weight"])
	var pick: int=_rng.randi_range(1,total)
	for item: Dictionary in group:
		pick-=int(item["weight"])
		if pick<=0:
			return item["tag"]
	return group.back()["tag"]


func _emit(cue: Dictionary) -> void:
	var tag: String=_resolve(cue["tag"])
	var audible: bool=output_enabled and not actor.paused and actor.owner==get_tree().current_scene \
		and not get_tree().get_meta("port_audio_muted",false)
	if audible:
		apply_preferences()
		var voice: AudioStreamPlayer=voices[_voice_index]
		_voice_index=(_voice_index+1)%VOICES
		voice.stop()
		voice.stream=streams[tag]
		voice.stream_paused=false
		voice.play()
	event_count+=1
	audit.append({"tag":tag,"cue":cue["tag"],"scheduled_ms":cue["at_ms"],
		"dispatched_ms":clock_ms,"audible":audible})
	if audit.size()>32:
		audit.pop_front()


func capture_state() -> Dictionary:
	return {"clock_ms":clock_ms,"pending":pending.duplicate(true)}


func restore_state(state: Dictionary) -> void:
	stop()
	clock_ms=float(state.get("clock_ms",0.0))
	pending=state.get("pending",[]).duplicate(true)
