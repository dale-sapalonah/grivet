class_name CoverMap
extends RefCounted
## Cover points found automatically, no hand placement: a grid over the
## walkable navmesh, where at each point 8 short rays at knee height look for
## something solid right next to it. A blocked direction at chest height too
## is full cover (stand behind it); knee only is half cover (crouch behind it).
## A point protects against a threat whose bearing lies within
## AiSettings.cover_protect_angle of one of its blocked directions.

const DIRECTIONS := 8


class Point:
	var position := Vector3.ZERO
	## Flat unit vectors toward the obstacle(s) beside this point.
	var directions := PackedVector2Array()
	## 1 = full height in that direction, 0 = half.
	var full := PackedByteArray()
	var reserved_by: Object = null
	## Someone failed to reach it; skipped until this time (s).
	var blocked_until := 0.0


var points: Array[Point] = []
var settings: AiSettings


func _init(ai_settings: AiSettings) -> void:
	settings = ai_settings


## Scans `bounds` (world AABB) on the navigation map. Returns points found.
func build(space: PhysicsDirectSpaceState3D, nav_map: RID, bounds: AABB) -> int:
	points.clear()
	var step := settings.cover_grid_spacing
	var x := bounds.position.x + step * 0.5
	while x < bounds.end.x:
		var z := bounds.position.z + step * 0.5
		while z < bounds.end.z:
			var probe := Vector3(x, bounds.position.y, z)
			var ground := NavigationServer3D.map_get_closest_point(nav_map, probe)
			if Vector2(ground.x - x, ground.z - z).length() <= step * 0.5:
				ground = _floor_below(space, ground)  # the navmesh floats above the real floor
				var point := _probe(space, ground)
				if point != null:
					points.append(point)
			z += step
		x += step
	return points.size()


func _probe(space: PhysicsDirectSpaceState3D, ground: Vector3) -> Point:
	var point: Point = null
	for i in DIRECTIONS:
		var angle := TAU * i / DIRECTIONS
		var flat := Vector2(sin(angle), cos(angle))
		var offset := Vector3(flat.x, 0.0, flat.y) * settings.cover_probe_length
		if not _blocked(space, ground + Vector3.UP * settings.cover_low_height, offset):
			continue
		if point == null:
			point = Point.new()
			point.position = ground
		point.directions.append(flat)
		point.full.append(1 if _blocked(space, ground + Vector3.UP * settings.cover_high_height, offset) else 0)
	return point


func _floor_below(space: PhysicsDirectSpaceState3D, near: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(near + Vector3.UP * 0.6, near + Vector3.DOWN * 1.5, PhysicsLayers.WORLD)
	var hit := space.intersect_ray(query)
	return hit.position if not hit.is_empty() else near


func _blocked(space: PhysicsDirectSpaceState3D, from: Vector3, offset: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, from + offset, PhysicsLayers.WORLD)
	return not space.intersect_ray(query).is_empty()


## 0 = exposed, half_cover_value = half cover, 1 = full cover against `threat`.
func protection(point: Point, threat: Vector3) -> float:
	var bearing := Vector2(threat.x - point.position.x, threat.z - point.position.z)
	if bearing.is_zero_approx():
		return 0.0
	bearing = bearing.normalized()
	var limit := cos(deg_to_rad(settings.cover_protect_angle))
	var best := 0.0
	for i in point.directions.size():
		if point.directions[i].dot(bearing) >= limit:
			best = maxf(best, 1.0 if point.full[i] == 1 else settings.half_cover_value)
	return best


## True when the side facing `threat` is full height.
func is_full(point: Point, threat: Vector3) -> bool:
	return is_equal_approx(protection(point, threat), 1.0)


func within(center: Vector3, radius: float) -> Array[Point]:
	var found: Array[Point] = []
	for point in points:
		if CoverScoring.flat_distance(point.position, center) <= radius:
			found.append(point)
	return found


func release(owner: Object) -> void:
	for point in points:
		if point.reserved_by == owner:
			point.reserved_by = null
