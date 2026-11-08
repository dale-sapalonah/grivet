class_name MissionRunner
extends Node
## Plays a Mission on a campaign level (which stops moving on by itself:
## auto_advance off). The intro: the police truck drives in while the camera
## flies over the yard and the radio briefing runs (any key skips). Then the
## objectives in order (MissionState): each may bring in a stage's squad and
## radio lines; finishing one is a checkpoint (the player respawns there from
## then on, healed and re-armed). Reaching the truck at the EXTRACT objective
## plays the outro: the camera pulls back, the truck leaves, and the mission
## complete card with the stats, then back to the title. RESCUE objectives
## bring civilians into the fight; the player hurting one (a bullet or a
## grenade) fails the mission: MISSION FAILED, and any key tries again.
## The HUD reads `cinematic`, objective_text(), waypoint() and search_fraction().

signal completed
signal failed

var mission: Mission
var state: MissionState
## True during the intro and the outro: the HUD steps aside, the player can't act.
var cinematic := false
var kills := 0
var deaths := 0
var hits := 0
var elapsed := 0.0
## Seconds since the current objective began (the HUD highlights a new one).
var objective_age := 0.0
## Civilians brought in and still unhurt (the HUD and the card).
var civilians_total := 0
var civilians_hurt := 0
## Of those, by the player (any one fails the mission).
var civilians_hurt_by_player := 0

var _level: Node
var _player: Player
var _truck: PoliceTruck
var _camera := Camera3D.new()
var _overlay := CanvasLayer.new()
var _bars: Array[ColorRect] = []
var _title: Label
var _subtitle: Label
var _radio: Label
var _stats: Label
var _hint: Label
var _phase := ""
var _phase_time := 0.0
var _radio_lines: PackedStringArray = PackedStringArray()
var _radio_left := 0.0
var _skip := false
var _outro_from := Transform3D.IDENTITY

## Seconds each radio line stays up during play.
const RADIO_SECONDS := 4.0
const CIVILIAN_SCENE := preload("res://ai/civilian.tscn")
const MAN := preload("res://data/ai/civilian.tres")
const WOMAN := preload("res://data/ai/civilian_woman.tres")
## One civilian in this many (not a shield) is a child.
const CHILD_EVERY := 3
## Letterbox bar height (share of the screen).
const BARS := 0.11


func _ready() -> void:
	add_to_group("mission")
	_level = get_parent()
	_player = _level.get_node("Player") as Player
	state = MissionState.new(mission)
	_build_overlay()
	add_child(_overlay)
	_level.add_child(_camera)
	AI.soldier_died.connect(func(_soldier: Soldier) -> void: kills += 1)
	_player.health.died.connect(func(_info: Dictionary) -> void: deaths += 1)
	Ballistics.target_hit.connect(_on_target_hit)
	AI.civilian_hurt.connect(_on_civilian_hurt)
	_level.stage_finished.connect(func(index: int) -> void: state.stage_cleared(index))
	Debug.register("mission", func(_args: PackedStringArray) -> String: return _status(), "Mission status.")
	Debug.register("mission.next", _cmd_next, "Meet the current objective at once (kills its squad, or moves you there).")
	Debug.register("mission.skip", func(_args: PackedStringArray) -> String:
		_skip = true
		return "skipping", "Skip the intro or the outro.")
	_begin_intro()


func _exit_tree() -> void:
	for command in ["mission", "mission.next", "mission.skip"]:
		Debug.unregister(command)
	if AI.frozen and cinematic:
		AI.frozen = false


## The objective line for the HUD ("" when there is none).
func objective_text() -> String:
	var objective := state.current()
	return objective.text if objective != null and _phase == "play" else ""


## The current objective's waypoint, or Vector3.INF for none.
func waypoint() -> Vector3:
	var objective := state.current()
	if objective == null or _phase != "play" or objective.point == Vector3.ZERO:
		return Vector3.INF
	return objective.point


func search_fraction() -> float:
	return state.search_fraction() if _phase == "play" else 0.0


func _input(event: InputEvent) -> void:
	if not cinematic or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey or event is InputEventMouseButton:
		if (event as InputEventKey) != null and (event as InputEventKey).keycode == KEY_ESCAPE:
			return  # Esc is the pause menu's
		_skip = true


func _process(delta: float) -> void:
	_phase_time += delta
	match _phase:
		"intro":
			_update_intro()
		"play":
			_update_play(delta)
		"outro":
			_update_outro()
		"failed":
			_update_failed()
	_update_radio(delta)


# --- Intro ---------------------------------------------------------------------

func _begin_intro() -> void:
	_phase = "intro"
	_phase_time = 0.0
	cinematic = true
	_truck = PoliceTruck.new()
	_level.add_child(_truck)
	_truck.rotation_degrees.y = mission.truck_yaw_degrees
	_truck.global_position = mission.truck_from
	_set_actors_active(false)
	for mate in get_tree().get_nodes_in_group("allies"):
		(mate as Node3D).visible = false  # Kori rides in the truck
	_camera.fov = 55.0
	_camera.make_current()
	_show_bars(true)
	_title.text = mission.title
	_subtitle.text = mission.subtitle
	_title.visible = true
	_subtitle.visible = true
	_radio_lines = mission.briefing.duplicate()
	_radio_left = 0.0


func _update_intro() -> void:
	var t := clampf(_phase_time / mission.intro_seconds, 0.0, 1.0)
	# The truck drives in over the first two thirds and stops.
	_truck.global_position = mission.truck_from.lerp(mission.truck_at, smoothstep(0.0, 0.66, t))
	_camera.global_position = mission.camera_from.lerp(mission.camera_to, smoothstep(0.0, 1.0, t))
	_camera.look_at(_truck.global_position + Vector3.UP * 1.0)
	var fade := clampf((_phase_time - 4.0) / 0.6, 0.0, 1.0)
	_title.modulate.a = 1.0 - fade
	_subtitle.modulate.a = 1.0 - fade
	if t >= 1.0 or _skip:
		_begin_play()


func _begin_play() -> void:
	_skip = false
	_phase = "play"
	_phase_time = 0.0
	cinematic = false
	_title.visible = false
	_subtitle.visible = false
	_truck.global_position = mission.truck_at
	_truck.flashing = true
	_show_bars(false)
	_set_actors_active(true)
	for mate in get_tree().get_nodes_in_group("allies"):
		(mate as Node3D).visible = true
	_player.set_spawn(Transform3D(Basis(Vector3.UP, deg_to_rad(mission.player_yaw_degrees)), mission.player_start))
	_player.respawn()
	_player.camera_rig().camera.make_current()
	for mate in get_tree().get_nodes_in_group("allies"):
		(mate as Squadmate).regroup()  # out of the truck beside the player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_radio_lines.clear()
	_radio_left = 0.0
	_begin_objective()


# --- Play ----------------------------------------------------------------------

func _begin_objective() -> void:
	objective_age = 0.0
	var objective := state.current()
	if objective == null:
		return
	if objective.stage >= 0:
		_level.start_stage(objective.stage, false)
	if objective.kind == MissionObjective.Kind.RESCUE:
		_bring_civilians(objective)
	for line in objective.radio:
		_radio_lines.append(line)


func _update_play(delta: float) -> void:
	elapsed += delta
	objective_age += delta
	if _player.dead:
		return
	var done := state.current()
	if state.update(_player.global_position, delta):
		if done.kind == MissionObjective.Kind.EXTRACT or state.finished():
			_begin_outro()
			return
		if done.checkpoint:
			_checkpoint()
		_begin_objective()


## The player respawns here from now on; healed and re-armed for the next step.
func _checkpoint() -> void:
	_player.set_spawn(Transform3D(Basis(Vector3.UP, _player.rotation.y), _player.global_position))
	_player.health.revive()
	var holder := get_tree().get_first_node_in_group("player_weapons") as WeaponHolder
	if holder != null:
		holder.refill()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("announce"):
		hud.announce("CHECKPOINT", GrivetStyle.GOLD, 1.2)


# --- Civilians -----------------------------------------------------------------

## The hostages and bystanders of a RESCUE objective: kneeling ones (some
## cowering), raskols each holding one as a shield, and a crowd panicking.
## Men, women in meri blouses and children (never as shields).
func _bring_civilians(objective: MissionObjective) -> void:
	var count := 0
	var stage: CampaignStage = _level.campaign.stages[objective.stage] if objective.stage >= 0 else null
	for spot in objective.shields:
		var captor := AI.spawn(objective.captor_kind, _spot_transform(spot), _level, stage)
		var held := _civilian(spot, count, false)
		held.hold(captor)
		count += 1
	for spot in objective.detained:
		var kneeling := _civilian(spot, count, count % CHILD_EVERY == 1)
		kneeling.cower = count % 2 == 0
		count += 1
	for spot in objective.panicked:
		var running := _civilian(spot, count, count % CHILD_EVERY == 2)
		running.panic()
		count += 1
	civilians_total += count


func _civilian(spot: Vector3, index: int, child: bool) -> Civilian:
	var civilian: Civilian = CIVILIAN_SCENE.instantiate()
	civilian.profile = WOMAN if index % 2 == 0 else MAN
	civilian.variant = index * 3 + 1
	civilian.child = child
	_level.add_child(civilian)
	civilian.global_transform = _spot_transform(spot)
	civilian.home = civilian.global_position
	return civilian


## Vector3(x, facing degrees, z) to a transform on the navmesh.
func _spot_transform(spot: Vector3) -> Transform3D:
	var map: RID = (_level as Node3D).get_world_3d().navigation_map
	var at := NavigationServer3D.map_get_closest_point(map, Vector3(spot.x, 0.5, spot.z))
	return Transform3D(Basis(Vector3.UP, deg_to_rad(spot.y)), Vector3(spot.x, at.y - 0.5 if at.y > 0.6 else 0.0, spot.z))


func civilians_alive() -> int:
	return get_tree().get_nodes_in_group("civilians").size()


func _on_civilian_hurt(_civilian: Node, info: Dictionary) -> void:
	if _phase != "play":
		return
	civilians_hurt += 1
	if info.get("shooter") == _player:
		civilians_hurt_by_player += 1
		fail("You hurt a civilian.")


## The mission is lost: everything stops, MISSION FAILED, any key tries again.
func fail(reason: String) -> void:
	if _phase == "failed" or _phase == "outro":
		return
	_phase = "failed"
	_phase_time = 0.0
	cinematic = true
	_set_actors_active(false)
	AI.frozen = true
	_show_bars(true)
	_radio_lines.clear()
	_radio.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = "MISSION FAILED"
	_title.add_theme_color_override("font_color", GrivetStyle.RED)
	_subtitle.text = reason
	_stats.text = ""
	_hint.text = "CLICK OR PRESS ANY KEY TO TRY AGAIN"
	_title.visible = true
	_subtitle.visible = true
	_title.modulate.a = 1.0
	_subtitle.modulate.a = 1.0
	failed.emit()


func _update_failed() -> void:
	_hint.visible = _phase_time > 1.5
	if _skip and _phase_time > 1.5:
		_phase = "done"
		AI.frozen = false
		get_tree().reload_current_scene.call_deferred()
	_skip = false


# --- Outro ---------------------------------------------------------------------

func _begin_outro() -> void:
	_phase = "outro"
	_phase_time = 0.0
	cinematic = true
	AI.frozen = true
	_outro_from = _player.camera_rig().camera.global_transform
	_set_actors_active(false)
	_camera.global_transform = _outro_from
	_camera.make_current()
	_show_bars(true)
	_radio_lines.clear()
	_radio.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var holder := get_tree().get_first_node_in_group("player_weapons") as WeaponHolder
	var shots := holder.shots_fired if holder != null else 0
	var accuracy := 100.0 * hits / shots if shots > 0 else 0.0
	_title.text = mission.complete_title
	_subtitle.text = mission.complete_subtitle
	_stats.text = "TIME  %d:%02d\nENEMIES DOWN  %d\nACCURACY  %d%%\nTIMES DOWN  %d" % [int(elapsed) / 60, int(elapsed) % 60,
			kills, roundi(accuracy), deaths]
	if civilians_total > 0:
		_stats.text += "\nCIVILIANS SAFE  %d / %d" % [civilians_alive(), civilians_total]
	completed.emit()


func _update_outro() -> void:
	# The camera rises and pulls back over the truck; the truck leaves after a beat.
	var t := clampf(_phase_time / 6.0, 0.0, 1.0)
	var wide := mission.outro_camera
	_camera.global_position = _outro_from.origin.lerp(wide, smoothstep(0.0, 1.0, t))
	var drive := maxf(_phase_time - 1.5, 0.0)
	var forward := -_truck.global_basis.z
	_truck.global_position = mission.truck_at + forward * drive * drive * 1.2
	_camera.look_at(_truck.global_position + Vector3.UP * 1.0)
	var shown := _phase_time > 2.0
	_title.visible = shown
	_subtitle.visible = shown
	_title.modulate.a = 1.0
	_subtitle.modulate.a = 1.0
	_stats.visible = _phase_time > 2.8
	_hint.visible = _phase_time > 3.5
	if _skip and _phase_time > 3.5:
		_finish()
	_skip = false


func _finish() -> void:
	_phase = "done"
	AI.frozen = false
	Settings.requested_mission = null
	get_tree().change_scene_to_file.call_deferred("res://ui/main_menu.tscn")


# --- Shared --------------------------------------------------------------------

## The player and the squadmate stand still and unseen-to-themselves during a
## cutscene (no input, no physics); the enemy is frozen.
func _set_actors_active(active: bool) -> void:
	var mode := Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_player.process_mode = mode
	for mate in get_tree().get_nodes_in_group("allies"):
		mate.process_mode = mode
	AI.frozen = not active


func _on_target_hit(info: Dictionary) -> void:
	if _phase == "play" and info.get("shooter") == _player:
		hits += 1


func _update_radio(delta: float) -> void:
	_radio_left -= delta
	if _radio_left > 0.0:
		return
	if _radio_lines.is_empty():
		_radio.text = ""
		return
	_radio.text = _radio_lines[0]
	_radio_lines.remove_at(0)
	# The briefing spreads over the intro; in play each line holds RADIO_SECONDS.
	_radio_left = mission.intro_seconds / maxf(mission.briefing.size(), 1.0) if _phase == "intro" else RADIO_SECONDS


func _show_bars(on: bool) -> void:
	for bar in _bars:
		bar.visible = on


func _build_overlay() -> void:
	_overlay.layer = 5
	var heavy := GrivetStyle.heavy()
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0 - BARS
		bar.anchor_bottom = BARS if top else 1.0
		bar.visible = false
		_overlay.add_child(bar)
		_bars.append(bar)
	_title = _centred(GrivetStyle.label("", heavy, 120, GrivetStyle.GOLD, 18), 0.32)
	_subtitle = _centred(GrivetStyle.label("", heavy, 40, GrivetStyle.WHITE, 8), 0.45)
	_stats = _centred(GrivetStyle.label("", heavy, 34, GrivetStyle.WHITE, 8), 0.62)
	_hint = _centred(GrivetStyle.label("CLICK OR PRESS ANY KEY", heavy, 24, GrivetStyle.ORANGE, 6), 0.8)
	_radio = _centred(GrivetStyle.label("", heavy, 28, Color(0.75, 0.95, 0.75), 7), 0.935)  # under the shout subtitles
	for label in [_title, _subtitle, _stats, _hint]:
		label.visible = false


func _centred(label: Label, at: float) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_right = 1.0
	label.anchor_top = at
	label.anchor_bottom = at
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(label)
	return label


func _status() -> String:
	var objective := state.current()
	return "%s: %s, objective %d/%d %s, %.0f s, kills %d, hits %d, deaths %d" % [mission.title, _phase, state.index + 1,
			mission.objectives.size(), objective.text if objective != null else "-", elapsed, kills, hits, deaths]


func _cmd_next(_args: PackedStringArray) -> String:
	var objective := state.current()
	if objective == null or _phase != "play":
		return "no objective in play"
	if objective.kind in [MissionObjective.Kind.CLEAR, MissionObjective.Kind.RESCUE]:
		for soldier in AI.soldiers.duplicate():
			soldier.health.take_hit(INF, DamageModel.Zone.HEAD, {})
		return "cleared the squad"
	_player.global_position = objective.point
	if objective.kind == MissionObjective.Kind.SEARCH:
		state.searched = objective.seconds
	return "moved to %s" % objective.point
