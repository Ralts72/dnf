extends Node
## Persistent port loop; subclasses customize settings and the gain policy.

const DATA_PATH: String="res://data/port_music.json"
const BUS_NAME: StringName=&"PortMusic"
const PORT_SCENES: Array[String]=["res://scenes/west_coast_r0.tscn","res://scenes/west_coast_r1.tscn", "res://scenes/tower_approach.tscn", "res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"]
var settings: Dictionary={}
var player: AudioStreamPlayer
var volume: float=.2
var muted: bool=false
var volume_levels: Array=[]
var gain: float=0.0
var target_gain: float=0.0
var play_starts: int=0
var _started: bool=false
var _allowed: bool=false
var _fade_start: float=0.0
var _fade_elapsed: float=0.0
var _fade_duration: float=.15
var bus_name: StringName=BUS_NAME


func _data_path() -> String:
	return DATA_PATH


func _desired_gain() -> float:
	return volume if _allowed and not muted else 0.0


func _ready() -> void:
	settings=JSON.parse_string(FileAccess.get_file_as_string(_data_path()))
	volume=float(settings["default_volume"])
	volume_levels=settings["volume_levels"]
	bus_name=StringName(settings.get("bus_name",BUS_NAME))
	if AudioServer.get_bus_index(bus_name)<0:
		AudioServer.add_bus()
		var index: int=AudioServer.bus_count-1
		AudioServer.set_bus_name(index,bus_name)
		AudioServer.set_bus_send(index,&"Master")
	player=AudioStreamPlayer.new()
	player.name=str(settings.get("player_name","WestCoastMusic"))
	player.bus=bus_name
	player.volume_db=-80.0
	var stream: AudioStreamOggVorbis=(load(settings["path"]) as AudioStreamOggVorbis).duplicate()
	stream.loop=bool(settings["loop"])
	stream.loop_offset=float(settings["loop_offset_seconds"])
	player.stream=stream
	add_child(player)
	player.stream_paused=true


func _process(delta: float) -> void:
	var scene: Node=get_tree().current_scene
	# Scene replacement can leave current_scene null briefly. Keep the existing
	# port stream through that gap rather than fading or starting it again.
	if scene!=null:_allowed=scene.scene_file_path in PORT_SCENES
	var desired: float=_desired_gain()
	if not is_equal_approx(desired,target_gain):
		_fade_start=gain;_fade_elapsed=0.0
		_fade_duration=float(settings["intro_fade_seconds"] if not _started and desired>0 else settings["volume_fade_seconds"])
		target_gain=desired
	if desired>0:
		if not _started:
			player.play();_started=true;play_starts+=1
		player.stream_paused=false
	_fade_elapsed+=delta
	var t: float=clampf(_fade_elapsed/maxf(_fade_duration,.001),0.0,1.0)
	gain=lerpf(_fade_start,target_gain,t)
	player.volume_db=linear_to_db(maxf(gain,.0001))
	if gain<=.000001 and desired==0:player.stream_paused=true


func select_volume(value: float) -> void:
	if value<=0:
		muted=true
	else:
		volume=clampf(value,0.0,1.0)
		muted=false


func toggle_muted() -> void:
	muted=not muted


func capture_state() -> Dictionary:
	return {"volume":volume,"muted":muted,"gain":gain,"target_gain":target_gain,
		"position":player.get_playback_position(),"stream_paused":player.stream_paused,
		"play_starts":play_starts,"player_id":player.get_instance_id(),"tag":settings["tag"]}
