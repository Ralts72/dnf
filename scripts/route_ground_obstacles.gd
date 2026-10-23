extends RefCounted
## R2 ground footprints in world XZ metres. Native scene shapes are the only
## geometry source; this helper adds the shared .18m actor foot clearance.
## No frame callbacks, save access, actor state changes or navigation changes.

const SCENES: Dictionary = {
	"approach": "res://scenes/tower_approach_collisions.tscn",
	"hall": "res://scenes/tower_hall_collisions.tscn",
	"depths": "res://scenes/tower_depths_collisions.tscn",
	"doll_gallery": "res://scenes/tower_doll_gallery_collisions.tscn",
	"statue_gallery": "res://scenes/tower_statue_gallery_collisions.tscn",
}
const FOOT_RADIUS: float = 0.18
const PPM: float = 60.0
const GROUND_Y_PPM: float = 36.9396885195 #60*sin38
const SKIN: float = 0.0001
const EPS: float = 0.000001
const MAX_SLIDES: int = 6

var _world: Node3D
var _root: Node3D
var _region: String = ""
var _footprints: Array[Dictionary] = []


func setup(main: Node, region_id: String) -> void:
	var target_world: Node3D = main.get("world") as Node3D
	assert(target_world != null and SCENES.has(region_id))
	if is_instance_valid(_root) and (_world != target_world or _region != region_id):
		_root.get_parent().remove_child(_root)
		_root.free()
	_world = target_world
	_region = region_id
	var root_names: Dictionary = {"approach": "TowerApproachCollisions", "hall": "TowerHallCollisions", "depths": "TowerDepthsCollisions", "doll_gallery": "TowerDollGalleryCollisions", "statue_gallery": "TowerStatueGalleryCollisions"}
	var root_name: String = root_names[region_id]
	_root = _world.get_node_or_null(root_name) as Node3D
	if _root == null:
		_root = (load(str(SCENES[region_id])) as PackedScene).instantiate() as Node3D
		_world.add_child(_root)
	_footprints.clear()
	for child: Node in _root.find_children("*", "CollisionShape3D", true, false):
		var collider: CollisionShape3D = child as CollisionShape3D
		if collider.disabled or collider.shape == null:
			continue
		var pose: Transform3D = collider.transform
		var ancestor: Node = collider.get_parent()
		while ancestor != _world:
			assert(ancestor is Node3D)
			pose = (ancestor as Node3D).transform * pose
			ancestor = ancestor.get_parent()
		# These four authored footprints are upright and unscaled. Reject an
		# unsupported scene edit instead of silently reading a rotated box wrong.
		assert(pose.basis.is_equal_approx(Basis.IDENTITY))
		var item: Dictionary = {"name": str(collider.get_parent().name),
			"center": Vector2(pose.origin.x, pose.origin.z)}
		if collider.shape is CylinderShape3D:
			item["kind"] = "circle"
			item["radius"] = (collider.shape as CylinderShape3D).radius + FOOT_RADIUS + SKIN
		elif collider.shape is BoxShape3D:
			item["kind"] = "box"
			var size: Vector3 = (collider.shape as BoxShape3D).size
			# Conservative rectangular Minkowski expansion at gate corners. This
			# preserves the72.2px center passage without an elaborate corner solver.
			item["half"] = Vector2(size.x, size.z) * 0.5 + Vector2.ONE * (FOOT_RADIUS + SKIN)
		else:
			assert(false, "Route footprints support only CylinderShape3D and BoxShape3D")
			continue
		_footprints.append(item)


func constrain(previous: Vector2, requested: Vector2, bounds: Rect2) -> Vector2:
	var legal := Rect2(_metric(bounds.position), bounds.size / Vector2(PPM, GROUND_Y_PPM))
	var start: Vector2 = _recover(_metric(previous).clamp(legal.position, legal.end), legal)
	var target: Vector2 = _metric(requested).clamp(legal.position, legal.end)
	var remaining: Vector2 = target - start
	for _slide: int in MAX_SLIDES:
		if remaining.length_squared() < EPS * EPS:
			break
		var hit: Dictionary = {}
		for obstacle: Dictionary in _footprints:
			var candidate: Dictionary = _sweep(start, remaining, obstacle)
			if not candidate.is_empty() and (hit.is_empty() or float(candidate.t) < float(hit.t)):
				hit = candidate
		if hit.is_empty():
			start += remaining
			break
		var fraction: float = float(hit.t)
		# Stop before contact, then spend the remaining travel along its tangent.
		start += remaining * maxf(0.0, fraction - SKIN / remaining.length())
		remaining *= 1.0 - fraction
		var normal: Vector2 = hit.normal
		remaining -= normal * minf(0.0, remaining.dot(normal))
		remaining = (start + remaining).clamp(legal.position, legal.end) - start
	return _source(_recover(start.clamp(legal.position, legal.end), legal))


func capture_state() -> Dictionary:
	return {"region": _region, "obstacle_count": _footprints.size(),
		"actor_radius_m": FOOT_RADIUS, "footprints": _footprints.duplicate(true)}


func _metric(point: Vector2) -> Vector2:
	return Vector2((point.x - 448.0) / PPM, (point.y - 159.0) / GROUND_Y_PPM - 1.6)


func _source(point: Vector2) -> Vector2:
	return Vector2(point.x * PPM + 448.0, (point.y + 1.6) * GROUND_Y_PPM + 159.0)


func _inside(point: Vector2, item: Dictionary) -> bool:
	var delta: Vector2 = point - Vector2(item.center)
	if item.kind == "circle":
		return delta.length_squared() < float(item.radius) * float(item.radius)
	var half: Vector2 = item.half
	return absf(delta.x) < half.x and absf(delta.y) < half.y


func _clear(point: Vector2, bounds: Rect2) -> bool:
	if point.x < bounds.position.x - EPS or point.x > bounds.end.x + EPS \
		or point.y < bounds.position.y - EPS or point.y > bounds.end.y + EPS:
		return false
	for item: Dictionary in _footprints:
		if _inside(point, item):
			return false
	return true


func _recover(point: Vector2, bounds: Rect2) -> Vector2:
	if _clear(point, bounds):
		return point
	var choices: Array[Vector2] = []
	for item: Dictionary in _footprints:
		if not _inside(point, item):
			continue
		var center: Vector2 = item.center
		if item.kind == "circle":
			var radius: float = float(item.radius) + SKIN
			var direction: Vector2 = (point - center).normalized()
			if direction == Vector2.ZERO:
				direction = Vector2.DOWN
			choices.append(center + direction * radius)
			for axis: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				choices.append(center + axis * radius)
			# A radial correction can leave a nearby walk bound. Include exact
			# circle/bound intersections instead of repeating push+clamp forever.
			for x: float in [bounds.position.x, bounds.end.x]:
				var square: float = radius * radius - (x - center.x) * (x - center.x)
				if square >= 0.0:
					choices.append(Vector2(x, center.y + sqrt(square)))
					choices.append(Vector2(x, center.y - sqrt(square)))
			for y: float in [bounds.position.y, bounds.end.y]:
				var square: float = radius * radius - (y - center.y) * (y - center.y)
				if square >= 0.0:
					choices.append(Vector2(center.x + sqrt(square), y))
					choices.append(Vector2(center.x - sqrt(square), y))
		else:
			var half: Vector2 = Vector2(item.half) + Vector2.ONE * SKIN
			choices.append(Vector2(center.x - half.x, point.y))
			choices.append(Vector2(center.x + half.x, point.y))
			choices.append(Vector2(point.x, center.y - half.y))
			choices.append(Vector2(point.x, center.y + half.y))
	var best: Vector2 = bounds.get_center()
	var best_distance: float = INF
	for candidate: Vector2 in choices:
		if _clear(candidate, bounds) and point.distance_squared_to(candidate) < best_distance:
			best = candidate
			best_distance = point.distance_squared_to(candidate)
	# The two authored footprints per region are disjoint; their nearest valid
	# face/arc always exists. Bounds center is a safe fallback for malformed edits.
	assert(_clear(best, bounds), "Route obstacles leave no safe recovery point")
	return best


func _sweep(start: Vector2, motion: Vector2, item: Dictionary) -> Dictionary:
	var center: Vector2 = item.center
	if item.kind == "circle":
		var offset: Vector2 = start - center
		var a: float = motion.length_squared()
		var b: float = offset.dot(motion)
		var square: float = b * b - a * (offset.length_squared() - float(item.radius) * float(item.radius))
		if square < 0.0 or a < EPS * EPS:
			return {}
		var fraction: float = (-b - sqrt(square)) / a
		if fraction < -EPS or fraction > 1.0:
			return {}
		fraction = maxf(0.0, fraction)
		var normal: Vector2 = (offset + motion * fraction).normalized()
		return {"t": fraction, "normal": normal} if motion.dot(normal) < -EPS else {}
	var half: Vector2 = item.half
	var near_time: float = 0.0
	var far_time: float = 1.0
	var normal := Vector2.ZERO
	for axis: int in 2:
		var offset: float = start[axis] - center[axis]
		if absf(motion[axis]) < EPS:
			if absf(offset) > half[axis]:
				return {}
			continue
		var first: float = (-half[axis] - offset) / motion[axis]
		var last: float = (half[axis] - offset) / motion[axis]
		if first > last:
			var swap: float = first
			first = last
			last = swap
		if first >= near_time:
			near_time = first
			normal = Vector2.ZERO
			normal[axis] = -signf(motion[axis])
		far_time = minf(far_time, last)
		if near_time > far_time:
			return {}
	if near_time < -EPS or near_time > 1.0 or motion.dot(normal) >= -EPS:
		return {}
	return {"t": maxf(0.0, near_time), "normal": normal}
