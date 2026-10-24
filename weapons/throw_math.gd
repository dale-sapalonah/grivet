class_name ThrowMath
extends RefCounted
## Pure arc solving and blast falloff for grenades.


## Launch velocity that lands a throw from `from` on `to` under `gravity`,
## trying angles from min to max (degrees) in 5-degree steps and taking the
## first whose speed fits under max_speed. Falls back to the max-angle,
## max-speed throw toward the target when nothing fits (it falls short).
static func launch_velocity(from: Vector3, to: Vector3, gravity: float, max_speed: float,
		angle_min: float, angle_max: float) -> Vector3:
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var distance := flat.length()
	var heading := flat.normalized() if distance > 0.001 else Vector2(0, -1)
	var rise := to.y - from.y
	var angle := angle_min
	while angle <= angle_max + 0.001:
		var theta := deg_to_rad(angle)
		var denominator := 2.0 * pow(cos(theta), 2.0) * (distance * tan(theta) - rise)
		if denominator > 0.0:
			var speed := sqrt(gravity * distance * distance / denominator)
			if speed <= max_speed:
				return _velocity(heading, theta, speed)
		angle += 5.0
	return _velocity(heading, deg_to_rad(angle_max), max_speed)


static func _velocity(heading: Vector2, theta: float, speed: float) -> Vector3:
	return Vector3(heading.x * cos(theta), sin(theta), heading.y * cos(theta)) * speed


static func blast_damage(definition: GrenadeDefinition, distance: float) -> float:
	if distance >= definition.blast_radius:
		return 0.0
	return definition.max_damage * pow(1.0 - distance / definition.blast_radius, definition.falloff_power)
