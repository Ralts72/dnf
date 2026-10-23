extends RefCounted
## Height and pose clock shared by R0 and R1. Ground navigation is separate.

var configured: bool=false
var config: Dictionary={}
var jump_frames: Array=[]
var attack_frames: Array=[]
var elapsed: float=-1.0
var air_attack_started: float=-1.0
var air_attack_used: bool=false
var travel_speed: float=0.0
var height_pixels: float=0.0
var vertical_speed: float=0.0
var phase: String="grounded"
var prep_seconds: float
var landing_seconds: float
var apex_seconds: float
var flight_seconds: float
var attack_seconds: float


func configure(data: Dictionary,jump: Array,attack: Array) -> void:
	config=data["mapping"]
	jump_frames=jump
	attack_frames=attack
	prep_seconds=float(jump_frames[int(config["takeoff_frame"])]["duration_ms"])/1000.0
	landing_seconds=float(jump_frames[int(config["landing_frame"])]["duration_ms"])/1000.0
	apex_seconds=float(config["takeoff_speed_px_s"])/float(config["gravity_px_s2"])
	flight_seconds=apex_seconds*2.0
	attack_seconds=0.0
	for frame: Dictionary in attack_frames:
		attack_seconds+=float(frame["duration_ms"])/1000.0
	configured=true
	reset()


func is_active() -> bool:
	return elapsed>=0.0


func is_airborne() -> bool:
	return phase in ["rising","falling"]


func reset() -> void:
	elapsed=-1.0
	air_attack_started=-1.0
	air_attack_used=false
	travel_speed=float(config.get("air_move_speed_px_s",0.0))
	height_pixels=0.0
	vertical_speed=0.0
	phase="grounded"


func begin(running: bool) -> bool:
	if not configured or is_active():
		return false
	reset()
	elapsed=0.0
	travel_speed*=float(config["run_jump_multiplier"]) if running else 1.0
	_update_height()
	return true


func begin_air_attack() -> bool:
	if not is_airborne() or air_attack_used:
		return false
	air_attack_started=elapsed
	air_attack_used=true
	return true


func advance(delta: float) -> void:
	if not is_active():
		return
	elapsed+=delta
	if elapsed+0.000000001>=prep_seconds+flight_seconds+landing_seconds:
		reset()
	else:
		_update_height()


func _update_height() -> void:
	if elapsed<0.0:
		phase="grounded"
		height_pixels=0.0
		vertical_speed=0.0
		return
	if elapsed<prep_seconds-0.000000001:
		phase="takeoff"
		height_pixels=0.0
		vertical_speed=0.0
		return
	var flight: float=maxf(0.0,elapsed-prep_seconds)
	if flight>=flight_seconds-0.000000001:
		phase="landing"
		height_pixels=0.0
		vertical_speed=0.0
		return
	phase="rising" if flight<apex_seconds-0.000000001 else "falling"
	vertical_speed=float(config["takeoff_speed_px_s"])-float(config["gravity_px_s2"])*flight
	height_pixels=maxf(0.0,float(config["takeoff_speed_px_s"])*flight-float(config["gravity_px_s2"])*flight*flight*.5)


func _sample(frames: Array,first: int,last: int,time_seconds: float) -> Dictionary:
	var ms: float=maxf(time_seconds,0.0)*1000.0
	for index: int in range(first,last+1):
		var duration: float=frames[index]["duration_ms"]
		if ms<duration or index==last:
			return {"frame":index,"elapsed_ms":minf(ms,duration)}
		ms-=duration
	return {"frame":last,"elapsed_ms":0.0}


func pose() -> Dictionary:
	if is_airborne() and air_attack_started>=0.0 and elapsed-air_attack_started<attack_seconds:
		var air_pose: Dictionary=_sample(attack_frames,0,attack_frames.size()-1,elapsed-air_attack_started)
		air_pose["action"]="jumpattack"
		return air_pose
	var result: Dictionary
	match phase:
		"takeoff":
			result=_sample(jump_frames,int(config["takeoff_frame"]),int(config["takeoff_frame"]),elapsed)
		"rising":
			result=_sample(jump_frames,int(config["rising_frames"][0]),int(config["rising_frames"][1]),elapsed-prep_seconds)
		"falling":
			result=_sample(jump_frames,int(config["falling_frames"][0]),int(config["falling_frames"][1]),elapsed-prep_seconds-apex_seconds)
		_:
			result=_sample(jump_frames,int(config["landing_frame"]),int(config["landing_frame"]),elapsed-prep_seconds-flight_seconds)
	result["action"]="jump"
	return result


func height_ratio() -> float:
	if not configured:
		return 0.0
	var peak: float=float(config["takeoff_speed_px_s"])*apex_seconds*.5
	return clampf(height_pixels/peak,0.0,1.0)


func capture_state() -> Dictionary:
	return {"elapsed":elapsed,"air_attack_started":air_attack_started,
		"air_attack_used":air_attack_used,"travel_speed":travel_speed}


func restore_state(state: Dictionary) -> void:
	elapsed=float(state.get("elapsed",-1.0))
	air_attack_started=float(state.get("air_attack_started",-1.0))
	air_attack_used=state.get("air_attack_used",false)
	travel_speed=float(state.get("travel_speed",config.get("air_move_speed_px_s",0.0)))
	_update_height()
