extends Node3D
## Autoloaded as `Ballistics`. Every bullet in flight, for every shooter:
## travel time and drop, penetration by surface thickness, ricochets at
## grazing angles, damage falloff, tracers and impact effects.
##
## Shooters call `Ballistics.fire(...)`. Anything with an
## `apply_damage(hit: Dictionary)` method (on the collider or a parent) takes
## damage; `target_hit` is emitted for every such hit.

signal impact(info: Dictionary)
signal target_hit(info: Dictionary)
## Every tick of every bullet's flight: the segment it covered. The AI uses
## it for near-miss suppression.
signal bullet_moved(from: Vector3, to: Vector3, shooter: Node)

const SETTINGS := preload("res://data/ballistics/ballistics_settings.tres")
const SURFACE_LOOKUP_DEPTH := 3
const EXIT_PROBE_ATTEMPTS := 4
## Sideways shift (m) for retrying an exit probe that slipped between triangles.
const EXIT_PROBE_NUDGE := 0.001


class Bullet:
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var weapon: WeaponDefinition
	var shooter: Node
	var exclude: Array[RID] = []
	var power := 0.0
	var damage_scale := 1.0
	var travelled := 0.0
	var events := 0
	var trail := PackedVector3Array()


var settings: BallisticsSettings = SETTINGS
var trace_enabled := false

var _bullets: Array[Bullet] = []
var _pool: Array[Bullet] = []
var _traces: Array[Dictionary] = []  # {"points": PackedVector3Array, "until": float}
var _tracer_mesh := ImmediateMesh.new()
var _tracer_material := StandardMaterial3D.new()
var _effects := ImpactEffects.new()


func _ready() -> void:
	var tracers := MeshInstance3D.new()
	tracers.mesh = _tracer_mesh
	tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.vertex_color_use_as_albedo = true
	_tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(tracers)
	add_child(_effects)
	_effects.setup(settings)
	get_tree().scene_changed.connect(clear)
	Debug.register("ballistics.trace", _cmd_trace,
			"Toggle persistent flight paths and a log line per hit.")


func fire(origin: Vector3, direction: Vector3, weapon: WeaponDefinition, shooter: Node,
		exclude: Array[RID] = []) -> void:
	if _bullets.size() >= settings.max_bullets:
		return
	var bullet: Bullet = _pool.pop_back() if not _pool.is_empty() else Bullet.new()
	bullet.position = origin
	bullet.velocity = direction.normalized() * weapon.muzzle_velocity
	bullet.weapon = weapon
	bullet.shooter = shooter
	bullet.exclude = exclude
	bullet.power = weapon.penetration_power
	bullet.damage_scale = 1.0
	bullet.travelled = 0.0
	bullet.events = 0
	bullet.trail = PackedVector3Array([origin]) if trace_enabled else PackedVector3Array()
	_bullets.append(bullet)


func active_bullets() -> int:
	return _bullets.size()


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var i := _bullets.size() - 1
	while i >= 0:
		var bullet := _bullets[i]
		if not _advance(bullet, space, delta):
			_retire(bullet)
			_bullets[i] = _bullets[_bullets.size() - 1]
			_bullets.pop_back()
		i -= 1


func _process(_delta: float) -> void:
	_draw_tracers()


## Moves one bullet through one tick. Returns false when it stops.
func _advance(bullet: Bullet, space: PhysicsDirectSpaceState3D, delta: float) -> bool:
	if not is_instance_valid(bullet.shooter):  # a freed object compares equal to null
		bullet.shooter = null  # the shooter died with rounds still in flight
	var stepped := BallisticsMath.step(bullet.position, bullet.velocity,
			settings.gravity * bullet.weapon.gravity_scale, delta)
	var from := bullet.position
	var to := stepped[0]
	bullet.velocity = stepped[1]
	var tick_start := from
	var alive := _fly(bullet, space, from, to)
	bullet_moved.emit(tick_start, bullet.position, _live_shooter(bullet))
	return alive


## Traces one tick's segment through surfaces. Returns false when the bullet stops.
func _fly(bullet: Bullet, space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	while true:
		var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.BULLETS, bullet.exclude)
		query.hit_back_faces = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			bullet.travelled += from.distance_to(to)
			bullet.position = to
			if trace_enabled:
				bullet.trail.append(to)
			return bullet.travelled < bullet.weapon.max_range
		var point: Vector3 = hit.position
		var remaining := point.distance_to(to)
		bullet.travelled += from.distance_to(point)
		if trace_enabled:
			bullet.trail.append(point)
		var next := _hit_surface(bullet, hit, bullet.velocity.normalized(), space)
		bullet.events += 1
		if next.is_empty() or bullet.events > settings.max_surface_events:
			bullet.position = point  # where it stopped (end of this tick's segment)
			return false
		from = next.from
		to = from + (next.direction as Vector3) * remaining
		if trace_enabled:
			bullet.trail.append(from)
	return false


## Applies damage, ricochet or penetration for one surface. Returns
## {"from", "direction"} to keep flying, or {} when the bullet stops.
func _hit_surface(bullet: Bullet, hit: Dictionary, direction: Vector3,
		space: PhysicsDirectSpaceState3D) -> Dictionary:
	var collider: Object = hit.collider
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var surface := surface_of(collider)
	var energy := BallisticsMath.impact_energy(bullet.weapon, bullet.velocity.length())

	var target := _damageable(collider)
	if target != null:
		var info := {
			"target": target,
			"shooter": _live_shooter(bullet),
			"weapon": bullet.weapon,
			"damage": BallisticsMath.damage_at(bullet.weapon, bullet.travelled) * bullet.damage_scale,
			"distance": bullet.travelled,
			"position": point,
			"normal": normal,
			"direction": direction,
			"shape": hit.get("shape", -1),  # which hit zone on a Hitbox
			"energy": energy,
		}
		target.call("apply_damage", info)
		target_hit.emit(info)
		_log("%s hit %s: %.1f damage at %.1f m" % [
				bullet.weapon.display_name, target.name, info.damage, info.distance])
	elif BallisticsMath.should_ricochet(surface, direction, normal, BallisticsMath.ricochet_angle(
			surface, energy, settings.ricochet_light_angle_multiplier, settings.ricochet_heavy_angle_multiplier)):
		var bounced := BallisticsMath.reflect(direction, normal)
		bullet.velocity = bounced * bullet.velocity.length() * surface.ricochet_speed_retention
		bullet.damage_scale *= surface.ricochet_damage_retention
		_report(point, normal, direction, surface, "ricochet", 0.0, false, energy, bullet)
		return {"from": point + normal * settings.surface_epsilon, "direction": bounced}

	# Measure what the round met: a far side within max_thickness, or solid.
	var exit := _find_exit(space, point, direction, collider, surface.max_thickness)
	var solid := exit.is_empty()
	var thickness := surface.max_thickness if solid else point.distance_to(exit.position)
	var cost := BallisticsMath.penetration_cost(surface, thickness)
	var penetrates := not solid and bullet.power >= cost
	_report(point, normal, direction, surface, "penetrated" if penetrates else "stopped",
			thickness, solid, energy, bullet)
	if not penetrates:
		_log("%s stopped in %s (%s, needs %.0f, had %.0f)" % [bullet.weapon.display_name, surface.id,
				"solid" if solid else "%.0f mm" % (thickness * 1000.0), cost, bullet.power])
		return {}
	var exit_point: Vector3 = exit.position
	bullet.power -= cost
	bullet.damage_scale *= surface.damage_retention
	bullet.velocity *= surface.velocity_retention
	bullet.travelled += thickness
	_report(exit_point, exit.normal, direction, surface, "exit", thickness, false,
			BallisticsMath.impact_energy(bullet.weapon, bullet.velocity.length()), bullet)
	return {"from": exit_point + direction * settings.surface_epsilon, "direction": direction}


## Casts back from max_thickness ahead to find where the bullet would leave
## `collider`. Empty when the slab is thicker than that. A ray that lands
## exactly on the edge between two collision triangles (a shot down the
## centre line of a faceted cylinder) can miss both, so a miss is retried
## with the ray nudged by EXIT_PROBE_NUDGE before calling the material solid.
func _find_exit(space: PhysicsDirectSpaceState3D, entry: Vector3, direction: Vector3,
		collider: Object, max_thickness: float) -> Dictionary:
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(direction).normalized()
	for nudge in [Vector3.ZERO, side * EXIT_PROBE_NUDGE, up * EXIT_PROBE_NUDGE]:
		var start: Vector3 = entry + nudge
		var exclude: Array[RID] = []
		for attempt in EXIT_PROBE_ATTEMPTS:
			var query := PhysicsRayQueryParameters3D.create(start + direction * max_thickness,
					start, PhysicsLayers.BULLETS, exclude)
			query.hit_back_faces = false
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				break
			if hit.collider == collider:
				return hit
			exclude.append(hit.rid)
	return {}


## One impact event. `kind` is the outcome: "penetrated", "stopped",
## "ricochet", or "exit" (the far face of a penetration). `thickness` is what
## the round met (m); `solid` means no far side within max_thickness;
## `energy` is BallisticsMath.impact_energy at that moment.
func _report(position: Vector3, normal: Vector3, direction: Vector3, surface: SurfaceMaterial,
		kind: String, thickness: float, solid: bool, energy: float, bullet: Bullet) -> void:
	var info := {"position": position, "normal": normal, "direction": direction,
			"surface": surface.id, "kind": kind, "thickness": thickness, "solid": solid,
			"energy": energy, "shooter": _live_shooter(bullet), "weapon": bullet.weapon}
	impact.emit(info)
	_effects.handle_impact(surface, info)


## The bullet's shooter, or null once it is gone (died, or its level was
## freed): checked at every report, since a hit earlier in the same tick can
## free it, and listeners must never be handed a freed object.
func _live_shooter(bullet: Bullet) -> Node:
	if not is_instance_valid(bullet.shooter):  # a freed object compares equal to null
		bullet.shooter = null
	return bullet.shooter


## Drops every round in flight (their world is gone: the scene changed).
func clear() -> void:
	_bullets.clear()


## The SurfaceMaterial for a collider (its `surface` metadata, or a parent's).
func surface_of(collider: Object) -> SurfaceMaterial:
	return settings.surface(_surface_id(collider))


## Impact effects, for probes and tests to listen to.
func effects() -> ImpactEffects:
	return _effects


func _surface_id(collider: Object) -> String:
	var node := collider as Node
	for depth in SURFACE_LOOKUP_DEPTH:
		if node == null:
			break
		if node.has_meta("surface"):
			return str(node.get_meta("surface"))
		node = node.get_parent()
	return ""


func _damageable(collider: Object) -> Node:
	var node := collider as Node
	for depth in SURFACE_LOOKUP_DEPTH:
		if node == null:
			break
		if node.has_method("apply_damage"):
			return node
		node = node.get_parent()
	return null


func _retire(bullet: Bullet) -> void:
	if trace_enabled and bullet.trail.size() > 1:
		_traces.append({"points": bullet.trail,
				"until": Time.get_ticks_msec() / 1000.0 + settings.trace_persist_seconds})
	bullet.shooter = null
	bullet.weapon = null
	_pool.append(bullet)


func _draw_tracers() -> void:
	_tracer_mesh.clear_surfaces()
	var now := Time.get_ticks_msec() / 1000.0
	_traces = _traces.filter(func(trace: Dictionary) -> bool: return trace.until > now)
	if _bullets.is_empty() and _traces.is_empty():
		return
	_tracer_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _tracer_material)
	for bullet in _bullets:
		var length := minf(settings.tracer_length, bullet.travelled)
		_tracer_mesh.surface_set_color(Color(settings.tracer_color, 0.0))
		_tracer_mesh.surface_add_vertex(bullet.position - bullet.velocity.normalized() * length)
		_tracer_mesh.surface_set_color(settings.tracer_color)
		_tracer_mesh.surface_add_vertex(bullet.position)
	for trace in _traces:
		var points: PackedVector3Array = trace.points
		for p in points.size() - 1:
			_tracer_mesh.surface_set_color(settings.tracer_color)
			_tracer_mesh.surface_add_vertex(points[p])
			_tracer_mesh.surface_add_vertex(points[p + 1])
	_tracer_mesh.surface_end()


func _log(line: String) -> void:
	if trace_enabled:
		Debug.log_line(line)


func _cmd_trace(_args: PackedStringArray) -> String:
	trace_enabled = not trace_enabled
	if not trace_enabled:
		_traces.clear()
	return "ballistics trace %s" % ("ON" if trace_enabled else "OFF")
