extends Node3D
## Combat arena: bakes the navigation mesh from its CSG geometry when it
## loads, builds the AI cover map from it, then spawns an enemy at every
## "enemy_spawn" marker (metadata `enemy` = rifleman / rusher).

## Emitted once enemies are in place (navmesh and cover map ready).
signal combat_ready

## Area the cover map scans.
@export var bounds := AABB(Vector3(-31, -0.5, -31), Vector3(62, 4, 62))
## Spawn the marker enemies automatically (probes may turn this off).
@export var spawn_on_ready := true

var cover_points := 0

@onready var _navigation: NavigationRegion3D = $Navigation


## Physics frames to wait for the navigation map to sync after a bake.
const MAX_SYNC_FRAMES := 240

var _iteration_before_bake := 0


func _ready() -> void:
	Debug.register("arena.reset", _cmd_reset, "Kill all enemies and respawn the arena's squad.")
	# CSG shapes build their meshes and colliders on the next frames; baking
	# before that parses nothing and yields an empty navmesh.
	await get_tree().process_frame
	await get_tree().process_frame
	_navigation.bake_finished.connect(_on_baked, CONNECT_ONE_SHOT)
	_iteration_before_bake = NavigationServer3D.map_get_iteration_id(_navigation.get_navigation_map())
	_navigation.bake_navigation_mesh(true)


func _exit_tree() -> void:
	Debug.unregister("arena.reset")


func _on_baked() -> void:
	# The navigation map picks up the new mesh on a later sync; queries before
	# that fail, so wait until its iteration moves past the pre-bake one.
	var map := _navigation.get_navigation_map()
	for i in MAX_SYNC_FRAMES:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > _iteration_before_bake:
			break
	cover_points = AI.build_cover(get_world_3d().direct_space_state, map, bounds)
	Debug.log_line("arena: navmesh %d polygons, %d cover points" % [
			_navigation.navigation_mesh.get_polygon_count(), cover_points])
	if spawn_on_ready:
		spawn_squad()
	combat_ready.emit()


func spawn_squad() -> void:
	for marker: Node3D in get_tree().get_nodes_in_group("enemy_spawn"):
		# Levels with several stages tag markers with `level`; the arena squad is level 1.
		if is_ancestor_of(marker) and int(marker.get_meta("level", 1)) == 1:
			AI.spawn(str(marker.get_meta("enemy", "rifleman")), marker.global_transform, self)


func _cmd_reset(_args: PackedStringArray) -> String:
	for soldier in AI.soldiers.duplicate():
		soldier.queue_free()
	spawn_squad()
	return "arena reset"
