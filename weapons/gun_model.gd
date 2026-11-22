class_name GunModel
extends Resource
## A gun's 3D model (assets/models/weapons/*.glb, made by
## tools/blender/prepare_gun.py: muzzle toward -Z, top +Y, metres; moving
## parts as child meshes named Magazine, Pump, Slide) and the points on it the
## game needs, in the model's frame. Used for the first-person gun
## (WeaponDefinition.model) and the one a soldier carries (EnemyProfile.gun_model,
## else its weapon's).

@export var scene: PackedScene
@export_group("Points (m, model frame)")
## Where rounds leave and the flash sits.
@export var muzzle := Vector3.ZERO
## The rear sight's aiming point: aiming puts the eye behind it, on this line.
@export var sight := Vector3.ZERO
## The ejection port (casings fly out to the right from here).
@export var port := Vector3.ZERO
## The shooting hand's hold on the pistol grip (or a shotgun's wrist).
@export var grip := Vector3.ZERO
## The grip's rake: the hand tilts by this about X (degrees).
@export var grip_tilt_degrees := -18.0
## The trigger's face, where the index fingertip rests.
@export var trigger := Vector3.ZERO
## The support hand: under the handguard, on the pump (in the Pump part's
## frame), or cupping a pistol hand.
@export var support := Vector3.ZERO
## Thickness of what the support hand wraps round (handguard, pump).
@export var support_radius := 0.025
## The support hand's hold on the magazine during a reload, in the Magazine
## part's frame.
@export var magazine_hold := Vector3.ZERO
## Where a shell goes in (per-shell reloads).
@export var loading_port := Vector3.ZERO
