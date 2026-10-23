class_name BallisticsMath
extends RefCounted
## Pure ballistics rules shared by the simulator and its tests.


## One semi-implicit Euler step. Returns [position, velocity].
static func step(position: Vector3, velocity: Vector3, gravity: float, delta: float) -> Array[Vector3]:
	var next_velocity := velocity + Vector3.DOWN * gravity * delta
	return [position + next_velocity * delta, next_velocity]


static func damage_at(weapon: WeaponDefinition, distance: float) -> float:
	var t := inverse_lerp(weapon.damage_falloff_start, weapon.damage_falloff_end, distance)
	return weapon.damage * lerpf(1.0, weapon.min_damage_multiplier, clampf(t, 0.0, 1.0))


## Angle between the flight direction and the surface plane, in degrees.
static func grazing_angle_degrees(direction: Vector3, normal: Vector3) -> float:
	return rad_to_deg(asin(clampf(absf(direction.normalized().dot(normal.normalized())), 0.0, 1.0)))


## Largest grazing angle at which a round of `energy` (0..1) still deflects:
## light, low-momentum rounds glance off steeper surfaces than heavy ones.
static func ricochet_angle(surface: SurfaceMaterial, energy: float, light_multiplier: float,
		heavy_multiplier: float) -> float:
	return surface.ricochet_max_angle_degrees * lerpf(light_multiplier, heavy_multiplier, clampf(energy, 0.0, 1.0))


## `max_angle_degrees` below zero means the surface's own (mid-energy) angle.
static func should_ricochet(surface: SurfaceMaterial, direction: Vector3, normal: Vector3,
		max_angle_degrees: float = -1.0) -> bool:
	var limit := surface.ricochet_max_angle_degrees if max_angle_degrees < 0.0 else max_angle_degrees
	return limit > 0.0 and grazing_angle_degrees(direction, normal) < limit


## 0..1: the weapon's calibre weight scaled by the share of muzzle kinetic
## energy the round still has (after penetrations, ricochets).
static func impact_energy(weapon: WeaponDefinition, speed: float) -> float:
	var remaining := speed / weapon.muzzle_velocity
	return weapon.impact_energy * clampf(remaining * remaining, 0.0, 1.0)


static func reflect(direction: Vector3, normal: Vector3) -> Vector3:
	var n := normal.normalized()
	return direction - 2.0 * direction.dot(n) * n


static func penetration_cost(surface: SurfaceMaterial, thickness: float) -> float:
	return surface.penetration_cost_per_metre * thickness


## Uniform random direction inside a cone of `half_angle_degrees` around `forward`.
static func random_in_cone(forward: Vector3, half_angle_degrees: float, rng: RandomNumberGenerator) -> Vector3:
	if half_angle_degrees <= 0.0:
		return forward.normalized()
	var axis := forward.normalized()
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var cos_max := cos(deg_to_rad(half_angle_degrees))
	var cos_theta := lerpf(1.0, cos_max, rng.randf())
	var theta := acos(cos_theta)
	var phi := rng.randf() * TAU
	return axis.rotated(side, theta).rotated(axis, phi).normalized()
