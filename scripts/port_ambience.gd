extends "res://scripts/port_music.gd"
## Stereo port bed shares the proven loop/fade lifecycle, with effects controls.

var distance_factor: float=.35
var source_distance: float=0.0


func _data_path() -> String:
	return "res://data/port_ambience.json"


func _desired_gain() -> float:
	var tree:=get_tree()
	var scene: Node=tree.current_scene
	if scene != null and scene.scene_file_path in ["res://scenes/tower_hall.tscn", "res://scenes/tower_depths.tscn", "res://scenes/tower_doll_gallery.tscn", "res://scenes/tower_statue_gallery.tscn"]:
		distance_factor = 0.0
		return 0.0
	if scene!=null and _allowed:
		var point: Vector2=scene.player.world_to_source(scene.player.position) if scene.name=="WestCoastR1" else scene.player.position
		var nearest: float=INF
		var shore: Array=settings["shore_points"]
		for i: int in range(shore.size()-1):
			var a:=Vector2(shore[i][0],shore[i][1]);var b:=Vector2(shore[i+1][0],shore[i+1][1])
			nearest=minf(nearest,point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)))
		source_distance=nearest
		var t: float=clampf((nearest-float(settings["near_distance_pixels"]))/(float(settings["far_distance_pixels"])-float(settings["near_distance_pixels"])),0.0,1.0)
		distance_factor=lerpf(1.0,float(settings["far_gain_factor"]),t)
	if not _allowed or muted or tree.get_meta("port_audio_muted",false):return 0.0
	return volume*clampf(float(tree.get_meta("port_audio_volume",.6)),0.0,1.0)*distance_factor


func capture_state() -> Dictionary:
	var state: Dictionary=super.capture_state()
	state["distance_factor"]=distance_factor
	state["source_distance_pixels"]=source_distance
	return state
