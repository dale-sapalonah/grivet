class_name PhysicsLayers
extends RefCounted
## Collision layer bits, named in project.godot under layer_names/3d_physics.
## Movement capsules never stop bullets; bullets hit per-zone Hitbox bodies.

const WORLD := 1        ## Level geometry (CSG, static bodies, range targets).
const PLAYER := 2       ## The player's movement capsule.
const ENEMIES := 4      ## Soldier movement capsules.
const HITBOXES := 8     ## Per-zone hit shapes (head, torso, arms, legs); bullets only.
const DEBRIS := 16      ## Ragdoll parts, thrown grenades.
## Railings and fences: open bars. They stop walking bodies (and the navmesh
## treats them as walls) but not bullets, sight, cover probes or sound.
const GUARD := 32
## Market produce: bullets burst it; nothing else touches it.
const PRODUCE := 64

## What a bullet ray can strike.
const BULLETS := WORLD | HITBOXES | PRODUCE
## What walking bodies stand on and bump into.
const PLAYER_MOVEMENT := WORLD | ENEMIES | GUARD
const ENEMY_MOVEMENT := WORLD | PLAYER | ENEMIES | GUARD
## What a navmesh bakes as obstacles.
const NAV_OBSTACLES := WORLD | GUARD
## Thrown and falling things.
const DEBRIS_COLLISION := WORLD | DEBRIS
