class_name PhysicsLayers
extends RefCounted
## Collision layer bits, named in project.godot under layer_names/3d_physics.
## Movement capsules never stop bullets; bullets hit per-zone Hitbox bodies.

const WORLD := 1        ## Level geometry (CSG, static bodies, range targets).
const PLAYER := 2       ## The player's movement capsule.
const ENEMIES := 4      ## Soldier movement capsules.
const HITBOXES := 8     ## Per-zone hit shapes (head, torso, arms, legs); bullets only.
const DEBRIS := 16      ## Ragdoll parts, thrown grenades.

## What a bullet ray can strike.
const BULLETS := WORLD | HITBOXES
## What walking bodies stand on and bump into.
const PLAYER_MOVEMENT := WORLD | ENEMIES
const ENEMY_MOVEMENT := WORLD | PLAYER | ENEMIES
## Thrown and falling things.
const DEBRIS_COLLISION := WORLD | DEBRIS
