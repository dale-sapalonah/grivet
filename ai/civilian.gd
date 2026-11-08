class_name Civilian
extends CharacterBody3D
## An innocent caught in a raskol hold-up (hostage missions). DETAINED:
## kneeling, hands up behind the head, cowering at gunfire. PANIC: running
## and screaming between random spots near home, away from gunfire. SHIELD:
## held tight in front of and a little to the left of its captor (a Soldier
## with `hostage` set), turning with it; when the captor falls it is freed
## and panics. Any damage is reported (AI.civilian_hurt): a mission fails
## when the player's side caused it. Tuning: AiSettings civilian_* / shield_*.

enum State { DETAINED, PANIC, SHIELD }

@export var profile: EnemyProfile

var state: State = State.DETAINED
## SHIELD: who holds it.
var captor: Soldier
var home := Vector3.ZERO
var variant := 0
## A child: the body at CHILD_SCALE (hit shapes and capsule to match).
var child := false
## Detained, cowering (arms over the head, folded down) rather than hands on the head.
var cower := false

const CHILD_SCALE := 0.64

var _settings: AiSettings
var _rng := RandomNumberGenerator.new()
var _zone_shapes: Dictionary = {}
var _target := Vector3.INF
var _path := PackedVector3Array()
var _path_index := 0
var _repath_left := 0.0
var _scream_left := 0.0
var _crouch := 0.0
var _pose_delta := 0.0
var _voice := AudioStreamPlayer3D.new()

const PATH_CORNER_RADIUS := 0.4

@onready var health: Health = $Health
@onready var hitbox: Hitbox = $Hitbox
@onready var mannequin: Mannequin = $Mannequin


func _ready() -> void:
	_settings = AI.settings
	_rng.randomize()
	health.setup(profile.health)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	hitbox.health = health
	hitbox.body = self
	mannequin.build(profile, variant)
	if child:
		mannequin.scale = Vector3.ONE * CHILD_SCALE
		var body := $Collision as CollisionShape3D
		var capsule := (body.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		capsule.radius *= CHILD_SCALE
		capsule.height *= CHILD_SCALE
		body.shape = capsule
		body.position.y *= CHILD_SCALE
	for part_name: String in Mannequin.PARTS:
		var zone := CollisionShape3D.new()
		zone.shape = _scaled(mannequin.shapes[part_name][0], CHILD_SCALE if child else 1.0)
		zone.set_meta("zone", Mannequin.PARTS[part_name][1])
		zone.set_meta("part", part_name)
		hitbox.add_child(zone)
		_zone_shapes[part_name] = zone
	collision_layer = PhysicsLayers.ENEMIES
	collision_mask = PhysicsLayers.ENEMY_MOVEMENT
	_voice.bus = &"Voices"
	_voice.position = Vector3(0, 1.5, 0)
	_voice.unit_size = 9.0
	add_child(_voice)
	_scream_left = _rng.randf_range(0.5, _settings.civilian_scream_max)
	add_to_group("civilians")


## Where a blast or a shot would strike the body (Grenade checks the line).
func aim_point() -> Vector3:
	return mannequin.parts.torso.global_position + Vector3.UP * 0.2


## Held by `soldier` as a shield (it stops moving and keeps this in front).
func hold(soldier: Soldier) -> void:
	state = State.SHIELD
	captor = soldier
	soldier.hostage = self
	# Held this close their bodies overlap: without this the physics shoves
	# the captor backwards every frame and he skates off with the hostage.
	add_collision_exception_with(soldier)
	soldier.add_collision_exception_with(self)


func panic() -> void:
	state = State.PANIC
	captor = null
	_target = Vector3.INF


## A loud sound (AI.make_noise): the detained cower, the panicked run from it.
func hear(position: Vector3, radius: float) -> void:
	if state == State.PANIC and global_position.distance_to(position) < radius:
		var away := (global_position - position)
		away.y = 0.0
		_set_destination(global_position + away.normalized() * _settings.civilian_panic_radius * 0.8)


func _physics_process(delta: float) -> void:
	match state:
		State.SHIELD:
			_follow_captor()
			return
		State.PANIC:
			_run(delta)
		State.DETAINED:
			velocity = Vector3(0, velocity.y, 0)
	if not is_on_floor():
		velocity.y -= Ballistics.settings.gravity * delta
	move_and_slide()


func _follow_captor() -> void:
	if not is_instance_valid(captor) or captor.dead:
		panic()  # freed
		return
	var basis := captor.global_basis
	global_position = captor.global_position - basis.z * _settings.shield_forward - basis.x * _settings.shield_side
	rotation.y = captor.rotation.y
	velocity = Vector3.ZERO


func _run(delta: float) -> void:
	_repath_left -= delta
	_scream_left -= delta
	if _scream_left <= 0.0:
		_scream_left = _rng.randf_range(_settings.civilian_scream_min, _settings.civilian_scream_max)
		_scream()
	if _target == Vector3.INF or _repath_left <= 0.0 or _path_index >= _path.size():
		var angle := _rng.randf() * TAU
		_set_destination(home + Vector3(cos(angle), 0, sin(angle)) * _rng.randf_range(3.0, _settings.civilian_panic_radius))
	while _path_index < _path.size() and CoverScoring.flat_distance(global_position, _path[_path_index]) < PATH_CORNER_RADIUS:
		_path_index += 1
	var desired := Vector3.ZERO
	if _path_index < _path.size():
		var next := _path[_path_index]
		desired = Vector3(next.x - global_position.x, 0, next.z - global_position.z).normalized()
	var horizontal := Vector3(velocity.x, 0, velocity.z).move_toward(desired * _settings.civilian_run_speed, 14.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if horizontal.length() > 0.3:
		rotation.y = rotate_toward(rotation.y, atan2(-horizontal.x, -horizontal.z), 8.0 * delta)


## `shape` grown or shrunk by `factor` (a child's hit zones).
static func _scaled(shape: Shape3D, factor: float) -> Shape3D:
	if is_equal_approx(factor, 1.0):
		return shape
	var copy := shape.duplicate() as Shape3D
	if copy is BoxShape3D:
		(copy as BoxShape3D).size *= factor
	elif copy is CapsuleShape3D:
		(copy as CapsuleShape3D).radius *= factor
		(copy as CapsuleShape3D).height *= factor
	elif copy is SphereShape3D:
		(copy as SphereShape3D).radius *= factor
	return copy


func _set_destination(point: Vector3) -> void:
	var map := get_world_3d().navigation_map
	_target = NavigationServer3D.map_get_closest_point(map, point)
	_path = NavigationServer3D.map_get_path(map, global_position, _target, true)
	_path_index = 0
	_repath_left = _settings.civilian_repath_seconds


func _scream() -> void:
	var book := _settings.shouts
	if book == null or not bool(Settings.get_value("voices_on")):
		return
	var stream := ProceduralAudio.fetch("pain:scream:%d" % (_rng.randi() % maxi(book.pain_variants, 1)))
	if stream == null:
		return
	_voice.stream = stream
	_voice.volume_db = book.pain_volume_db - 2.0
	_voice.pitch_scale = _rng.randf_range(0.9, 1.15)
	_voice.play()


func _process(delta: float) -> void:
	if health.model.dead:
		return
	# Level of detail: far ones drop their shadow; a kneeling hostage hardly
	# moves, so it poses one frame in four; far panickers every other frame; a
	# shield every frame (the shot past it must land where it is drawn).
	_pose_delta += delta
	var target := AI.target()
	var distance_squared := global_position.distance_squared_to(target.global_position) if target != null else 0.0
	mannequin.cast_shadows(distance_squared < _settings.shadow_lod_distance * _settings.shadow_lod_distance)
	var every := 1
	if state == State.DETAINED and _crouch >= 1.0:
		every = 4
	elif state == State.PANIC and distance_squared > _settings.pose_lod_distance * _settings.pose_lod_distance:
		every = 2
	if (Engine.get_process_frames() + get_instance_id()) % every != 0:
		return
	delta = _pose_delta
	_pose_delta = 0.0
	var kneel := state == State.DETAINED
	_crouch = move_toward(_crouch, 1.0 if kneel else 0.0, delta * 4.0)
	mannequin.arms_pose = {State.DETAINED: "cower" if cower else "hands_up", State.PANIC: "panic", State.SHIELD: "held"}[state]
	mannequin.pose(delta, _crouch, 0.0, Vector2(velocity.x, velocity.z).length(), false, _crouch if cower else 0.0)
	var to_local := hitbox.global_transform.affine_inverse()
	for part_name: String in _zone_shapes:
		var part: Node3D = mannequin.parts[part_name]
		var placed: Transform3D = to_local * part.global_transform * mannequin.shapes[part_name][1]
		placed.basis = placed.basis.orthonormalized()  # a child's scale is in the shape itself
		_zone_shapes[part_name].transform = placed


func _on_damaged(info: Dictionary) -> void:
	AI.civilian_hurt.emit(self, info)
	mannequin.flinch(info.get("direction", Vector3.ZERO), 3.0)
	if not health.model.dead and state != State.SHIELD:
		state = State.PANIC
		_scream_left = 0.0


func _on_died(info: Dictionary) -> void:
	if is_instance_valid(captor):
		captor.hostage = null
	remove_from_group("civilians")
	if child:
		# Scaled bodies make poor ragdolls: a child just falls where it stood.
		set_physics_process(false)
		hitbox.collision_layer = 0
		var fall := create_tween()
		fall.tween_property(mannequin, "rotation:x", -PI * 0.5, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	var direction: Vector3 = info.get("direction", Vector3.ZERO)
	var ragdoll := Ragdoll.from_mannequin(mannequin, get_parent(), velocity, "torso", direction * 1.5)
	ragdoll.freeze_after = AI.settings.corpse_freeze_after
	AI.add_corpse(ragdoll)
	queue_free()
