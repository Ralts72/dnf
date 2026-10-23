extends SceneTree
## Isolated native-scene/math checks only. No main scene, autoload, input, profile,
## save or live-game job is needed. Run in a scratch project with these new files.

const Obstacles = preload("res://scripts/route_ground_obstacles.gd")
const Y_PPM: float = 36.9396885195
var checks: Array[Dictionary] = []

class Fixture:
	extends Node
	var world: Node3D
	func _init() -> void:
		world = Node3D.new()
		world.name = "World"
		add_child(world)


func _initialize() -> void:
	run.call_deferred()


func verify(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"check": label, "pass": passed, "details": details})
	if not passed:
		push_error(label + ": " + str(details))


func inside_bounds(point: Vector2, bounds: Rect2) -> bool:
	return point.x >= bounds.position.x - .002 and point.x <= bounds.end.x + .002 \
		and point.y >= bounds.position.y - .002 and point.y <= bounds.end.y + .002


func clear(helper: RefCounted, point: Vector2, bounds: Rect2) -> bool:
	if not inside_bounds(point, bounds):
		return false
	var metric := Vector2((point.x - 448.0) / 60.0, (point.y - 159.0) / Y_PPM - 1.6)
	for item: Dictionary in helper.capture_state().footprints:
		var offset: Vector2 = metric - Vector2(item.center)
		if item.kind == "circle" and offset.length() < float(item.radius) - .00002:
			return false
		if item.kind == "box":
			var half: Vector2 = item.half
			if absf(offset.x) < half.x - .00002 and absf(offset.y) < half.y - .00002:
				return false
	return true


func solve_case(helper: RefCounted, bounds: Rect2, label: String, previous: Vector2, requested: Vector2) -> Vector2:
	var result: Vector2 = helper.constrain(previous, requested, bounds)
	verify(label, result.is_finite() and clear(helper, result, bounds),
		{"previous": previous, "requested": requested, "result": result})
	return result


func run() -> void:
	var hall_fixture := Fixture.new()
	var approach_fixture := Fixture.new()
	var hall = Obstacles.new()
	var approach = Obstacles.new()
	hall.setup(hall_fixture, "hall")
	approach.setup(approach_fixture, "approach")
	var hall_bounds := Rect2(120, 245, 656, 100)
	var approach_bounds := Rect2(36, 236, 816, 109)
	verify("each_native_scene_has_two_static_bodies_and_two_shapes",
		hall_fixture.world.find_children("*", "StaticBody3D", true, false).size() == 2 \
		and approach_fixture.world.find_children("*", "StaticBody3D", true, false).size() == 2 \
		and hall_fixture.world.find_children("*", "CollisionShape3D", true, false).size() == 2 \
		and approach_fixture.world.find_children("*", "CollisionShape3D", true, false).size() == 2)
	verify("all_native_bodies_match_actor_collision_layer", _body_layers(hall_fixture) and _body_layers(approach_fixture))
	var hall_state: Dictionary = hall.capture_state()
	var first: Dictionary = hall_state.footprints[0]
	var second: Dictionary = hall_state.footprints[1]
	verify("hall_native_shapes_resolve_plan_source_centers_and_radius",
		_source(first.center).distance_to(Vector2(140,239)) < .001 \
		and _source(second.center).distance_to(Vector2(760,239)) < .001 \
		and absf(float(first.radius) - .6401) < .00001)
	var approach_state: Dictionary = approach.capture_state()
	verify("gate_native_shapes_resolve_plan_source_centers_and_extents",
		_source(approach_state.footprints[0].center).distance_to(Vector2(372,230)) < .001 \
		and _source(approach_state.footprints[1].center).distance_to(Vector2(488,230)) < .001 \
		and Vector2(approach_state.footprints[0].half).distance_to(Vector2(.3651,.3951)) < .00001)
	var open: Vector2 = hall.constrain(Vector2(440,315), Vector2(455,324), hall_bounds)
	verify("unobstructed_motion_keeps_requested_foot", open.distance_to(Vector2(455,324)) < .001)
	for x: float in [140.0,760.0]:
		var stopped: Vector2 = solve_case(hall, hall_bounds, "hall_column_front_stops_" + str(x), Vector2(x,300), Vector2(x,245))
		verify("hall_column_front_stop_uses_world_metric_" + str(x), absf(stopped.x-x) < .01 and stopped.y > 262.63 and stopped.y < 262.68)
		var recovered: Vector2 = solve_case(hall, hall_bounds, "static_overlap_recovers_" + str(x), Vector2(x,245), Vector2(x,245))
		verify("static_overlap_front_recovery_is_local_" + str(x), absf(recovered.x-x) < .01 and recovered.y < 262.7)
	solve_case(hall, hall_bounds, "bound_clamp_cannot_reinsert_left_column", Vector2(119,259), Vector2(120,259))
	solve_case(hall, hall_bounds, "bound_clamp_cannot_reinsert_right_column", Vector2(777,259), Vector2(776,259))
	solve_case(hall, hall_bounds, "left_top_walk_corner_overlap_recovers", Vector2(120,245), Vector2(120,245))
	solve_case(hall, hall_bounds, "right_top_walk_corner_overlap_recovers", Vector2(776,245), Vector2(776,245))
	var upper_slide: Vector2 = solve_case(hall, hall_bounds, "circle_upper_bound_intersection_blocks", Vector2(200,245), Vector2(130,245))
	verify("upper_bound_contact_redirects_outside_circle", upper_slide.x > 170.0 and upper_slide.y > 245.0)
	var circle_push: Vector2 = solve_case(hall, hall_bounds, "clear_endpoints_cannot_tunnel_circle", Vector2(200,260), Vector2(120,260))
	verify("circle_segment_routes_around_front_instead_of_straight_through", circle_push.y > 262.64 and circle_push.distance_to(Vector2(120,260)) > 8.0)
	var short_push: Vector2 = solve_case(approach, approach_bounds, "short_push_cannot_cross_gate_base", Vector2(348,240), Vector2(356,240))
	verify("short_push_stops_on_original_side", short_push.x > 350.05 and short_push.x < 350.11)
	var fast_push: Vector2 = solve_case(approach, approach_bounds, "clear_endpoints_cannot_tunnel_gate_base", Vector2(330,240), Vector2(430,240))
	verify("full_segment_sweep_keeps_entry_side", fast_push.x < 350.11)
	var slide: Vector2 = solve_case(approach, approach_bounds, "box_block_slides_along_side", Vector2(345,255), Vector2(380,236))
	verify("box_front_slide_keeps_tangential_travel", slide.y > 244.58 and slide.y < 244.62 and slide.x > 379.9)
	var side_slide: Vector2 = solve_case(approach, approach_bounds, "box_side_keeps_vertical_tangent", Vector2(345,240), Vector2(380,236))
	verify("box_side_slide_keeps_tangential_travel", side_slide.x < 350.11 and side_slide.y < 236.01)
	solve_case(approach, approach_bounds, "box_corner_diagonal_stays_outside", Vector2(350.088,244.60), Vector2(390,236))
	var circle_slide: Vector2 = solve_case(hall, hall_bounds, "circle_block_slides_tangentially", Vector2(190,275), Vector2(130,245))
	verify("circle_slide_makes_progress_without_teleport", circle_slide.distance_to(Vector2(190,275)) > 10.0 and circle_slide.x > 145.0)
	for x: float in [398.0,430.0,462.0]:
		var gate: Vector2 = solve_case(approach, approach_bounds, "original_hall_door_lane_open_" + str(x), Vector2(x,270), Vector2(x,236))
		verify("door_trigger_endpoint_preserved_" + str(x), gate.distance_to(Vector2(x,236)) < .001)
	verify("hall_return_threshold_open", hall.constrain(Vector2(440,320), Vector2(440,345), hall_bounds).distance_to(Vector2(440,345)) < .001)
	verify("approach_harbor_exit_open", approach.constrain(Vector2(816,320), Vector2(852,320), approach_bounds).distance_to(Vector2(852,320)) < .001)
	solve_case(approach, approach_bounds, "gate_base_static_overlap_recovers", Vector2(372,236), Vector2(372,236))
	for side: int in [-1,1]:
		var position := Vector2(440,300)
		var valid: bool = true
		for _step: int in 600:
			position = hall.constrain(position, position + Vector2(side*.9,-.35), hall_bounds)
			valid = valid and clear(hall,position,hall_bounds)
		verify("repeated_diagonal_slide_at_bound_" + str(side), valid, {"result": position})
	var random := RandomNumberGenerator.new()
	random.seed = 304
	for region: String in ["hall","approach"]:
		var helper = hall if region == "hall" else approach
		var bounds: Rect2 = hall_bounds if region == "hall" else approach_bounds
		var valid: bool = true
		for _case: int in 500:
			var previous := Vector2(random.randf_range(bounds.position.x-3,bounds.end.x+3),random.randf_range(bounds.position.y-3,bounds.end.y+3))
			var requested := previous + Vector2(random.randf_range(-100,100),random.randf_range(-80,80))
			var result: Vector2 = helper.constrain(previous,requested,bounds)
			valid = valid and result.is_finite() and clear(helper,result,bounds)
		verify("seeded_bound_overlap_and_sweep_invariants_" + region, valid, {"cases":500,"seed":304})
	hall.setup(hall_fixture,"hall")
	verify("setup_reuses_existing_scene_without_duplicate_bodies", hall_fixture.world.get_child_count() == 1 and hall.capture_state().obstacle_count == 2)
	# Native editable resources remain the authority: changing the instantiated
	# source shape must change the helper after setup, without a second radius table.
	var edited: CollisionShape3D = hall_fixture.world.get_node("TowerHallCollisions/ColumnLeft/Shape")
	edited.shape = edited.shape.duplicate()
	(edited.shape as CylinderShape3D).radius = .60
	hall.setup(hall_fixture,"hall")
	verify("reads_edited_native_shape_instead_of_duplicate_constants", absf(float(hall.capture_state().footprints[0].radius)-.7801) < .00001)
	var failures: int = 0
	for item: Dictionary in checks:
		if not item["pass"]:
			failures += 1
	print(JSON.stringify({"scope":"isolated native-scene/math; no save/runtime/main scene", "checks":checks,"passed":checks.size()-failures,"failed":failures}))
	hall_fixture.free()
	approach_fixture.free()
	quit(0 if failures == 0 else 1)


func _source(point: Vector2) -> Vector2:
	return Vector2(point.x*60.0+448.0,(point.y+1.6)*Y_PPM+159.0)


func _body_layers(fixture: Node) -> bool:
	for body: Node in fixture.world.find_children("*","StaticBody3D",true,false):
		if body.collision_layer != 1 or body.collision_mask != 1:
			return false
	return true
