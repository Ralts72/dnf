extends Node
## Explicit live handle for the exhaustive render check (longer than game_eval's
## eight-second reply ceiling). Keep runtime mutations idle until it completes.

var status: String="new"
var qa: RefCounted
var result: Dictionary={}
var started_usec: int
var completed_usec: int
var check_script_path: String
var candidate_tag: String=""


func start(root: Node,path: String="res://tools/r1/pose_checks.gd",candidate: String="") -> Dictionary:
	check_script_path=path
	candidate_tag=candidate
	var source: GDScript=load(path)
	source.source_code=FileAccess.get_file_as_string(path)
	var error: int=source.reload()
	if error!=OK:
		status="failed"
		result={"script_reload_error":error}
		return snapshot()
	qa=source.new()
	started_usec=Time.get_ticks_usec()
	status="running"
	_run(root)
	return snapshot()


func _run(root: Node) -> void:
	result=await qa.run(root) if candidate_tag.is_empty() else await qa.run(root,candidate_tag)
	completed_usec=Time.get_ticks_usec()
	status="complete"


func snapshot() -> Dictionary:
	var now: int=completed_usec if completed_usec>0 else Time.get_ticks_usec()
	var rendered: int=0
	if qa and qa.get_property_list().any(func(p: Dictionary): return p["name"]=="render_cases"):
		rendered=qa.get("render_cases").size()
	return {"status":status,"elapsed_seconds":float(now-started_usec)/1000000.0,
		"check_script":check_script_path,
		"render_cases_completed":rendered,
		"qa_source_sha256":qa.get_script().source_code.sha256_text() if qa else "",
		"result":result}
