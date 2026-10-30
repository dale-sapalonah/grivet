extends Node
## Flashbang probe (arena): a soldier facing a bang close by is blinded for
## seconds, holds fire and can't see the player meanwhile, then recovers and
## spots them again; facing away blinds far less; the player looking at it
## whites out. Exit 0 = pass.
##
##   $GODOT --headless --path . res://tests/probes/flashbang.tscn

const LEVEL := "res://levels/greybox/arena.tscn"
const FLASH := preload("res://data/grenades/flash.tres")

var level: Node3D
var player: Player
var failures := 0


func _ready() -> void:
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player")
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await level.combat_ready
	player.health.invulnerable = true
	while AI.soldiers.size() > 1:
		AI.soldiers[0].health.take_hit(INF, DamageModel.Zone.HEAD, {})
		await get_tree().physics_frame
	var soldier: Soldier = AI.soldiers[0]
	var spot := _open_spot()
	if spot.is_empty():
		_check("found open ground for the test", false, "no 8 m clear line from the player")
		return _finish()
	soldier.global_position = spot.soldier
	await get_tree().physics_frame
	_face(soldier, player.global_position)
	var to_soldier: Vector3 = spot.soldier - player.global_position
	player.set_look(atan2(-to_soldier.x, -to_soldier.z), 0.0)
	# The bang 2.5 m in front of the soldier, between the two.
	var bang: Vector3 = spot.soldier - to_soldier.normalized() * 2.5 + Vector3.UP * 0.2
	await _flash_at(bang, soldier, player.global_position)
	var facing_blind := soldier.blind_left
	_check("a soldier facing the bang is blinded for seconds", facing_blind > 2.0, "%.2f s" % facing_blind)
	_check("the player looking at it whites out", player.blind_left > 0.5, "%.2f s" % player.blind_left)
	var ammo := soldier.weapon.ammo
	var saw := false
	var waited := 0.0
	while soldier.blind_left > 0.0 and waited < 10.0:
		_face(soldier, player.global_position)
		saw = saw or soldier.target_visible
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("blind, it never sees the player", not saw, "saw the player while blind")
	_check("blind, it holds its fire", soldier.weapon.ammo == ammo, "ammo %d -> %d" % [ammo, soldier.weapon.ammo])
	waited = 0.0
	while not soldier.target_visible and waited < 4.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("once its eyes clear it spots the player again", soldier.target_visible, "still blind after 4 s")
	# The same bang with its back turned.
	player.blind_left = 0.0
	await _flash_at(bang, soldier, soldier.global_position * 2.0 - player.global_position)
	_check("facing away blinds far less", soldier.blind_left < facing_blind * 0.6, "%.2f s vs %.2f s facing" % [soldier.blind_left, facing_blind])
	_finish()


## A flashbang at `point`, the soldier held where it stands, facing `look_at`,
## until it goes off (left alone it walks past the grenade during the fuse).
func _flash_at(point: Vector3, soldier: Soldier, look_at: Vector3) -> void:
	soldier_blind_reset()
	var grenade := Grenade.throw(FLASH, level, point, Vector3.ZERO, player)
	grenade.freeze = true  # land exactly where placed
	var stand := soldier.global_position
	while is_instance_valid(grenade) and not grenade.is_queued_for_deletion():
		soldier.global_position = stand
		_face(soldier, look_at)
		await get_tree().physics_frame


func soldier_blind_reset() -> void:
	for soldier in AI.soldiers:
		soldier.blind_left = 0.0


func _face(soldier: Soldier, point: Vector3) -> void:
	var heading := point - soldier.global_position
	soldier.rotation.y = atan2(-heading.x, -heading.z)


## A point 8 m from the player with a clear line at eye height and floor under it.
func _open_spot() -> Dictionary:
	var space := player.get_world_3d().direct_space_state
	var eye := player.global_position + Vector3.UP * 1.6
	for i in 16:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 16.0)
		var far := eye + direction * 8.0
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, far, PhysicsLayers.WORLD)).is_empty():
			continue
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(far, far + Vector3.DOWN * 3.0, PhysicsLayers.WORLD))
		if ground.is_empty():
			continue
		return {"soldier": ground.position}
	return {}


func _finish() -> void:
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
