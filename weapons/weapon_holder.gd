class_name WeaponHolder
extends Node3D
## The player's weapons. Sits under the Camera3D. Reads fire / aim / reload /
## inspect / switch input, runs each slot's WeaponModel, turns shots into
## Ballistics bullets from the eye along the aim (with spread), turns recoil
## kicks into aim movement, and drives the view model, flash, shot and
## mechanism sounds (timed to the view model's animation) and casings.

signal shot_fired(weapon: WeaponDefinition)
## "magazine_out", "magazine_in", "bolt_release", "rack_back", "rack_forward", "shell_insert".
signal mechanical_sound(sound: String)

## WeaponDefinition resources in slot order (keys 1, 2, 3).
@export var loadout: Array = []
@export var view_tuning: ViewModelTuning

var weapons: Array[WeaponModel] = []
var current := -1
## 0 = hip, 1 = fully aimed; blends over the weapon's ads_time.
var aim_blend := 0.0
var spread_enabled := true
## Spread cone (degrees) of the next shot; the HUD draws the crosshair from it.
var current_spread := 0.0

var _player: Player
var _view := WeaponViewModel.new()
var _audio := AudioStreamPlayer.new()
var _mechanism_audio := AudioStreamPlayer.new()
var _casings := CasingEjector.new()
var _controls := WeaponModel.Controls.new()
var _last_state: WeaponModel.State = WeaponModel.State.EQUIPPING
var _last_progress := 0.0
var _last_ammo := 0
var _rng := RandomNumberGenerator.new()
var _look_delta := Vector2.ZERO


func _ready() -> void:
	_player = _find_player()
	if not _player.is_node_ready():
		await _player.ready  # children are ready before their parents; we need its rig
	_view.tuning = view_tuning
	add_child(_view)
	_audio.max_polyphony = 8
	add_child(_audio)
	_mechanism_audio.max_polyphony = 4
	add_child(_mechanism_audio)
	_casings.exclude = [_player.get_rid()]
	add_child(_casings)
	for definition: WeaponDefinition in loadout:
		_add_weapon(definition)
	if not weapons.is_empty():
		equip(0)
	add_to_group("player_weapons")
	_register_debug_commands()


func _exit_tree() -> void:
	for command in ["give", "ammo.infinite", "spread", "recoil.show"]:
		Debug.unregister(command)


func player() -> Player:
	return _player


func current_weapon() -> WeaponModel:
	return weapons[current] if current >= 0 else null


func equip(slot: int) -> void:
	if slot < 0 or slot >= weapons.size() or slot == current:
		return
	current = slot
	var weapon := weapons[slot]
	weapon.begin_equip()
	_last_state = weapon.state
	_last_progress = 0.0
	_last_ammo = weapon.ammo
	_view.build(weapon.definition)
	_player.camera_rig().ads_fov_multiplier = weapon.definition.ads_fov_multiplier


func _unhandled_input(event: InputEvent) -> void:
	if Debug.console_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_delta += (event as InputEventMouseMotion).relative
	elif event.is_action_pressed("weapon_1"):
		equip(0)
	elif event.is_action_pressed("weapon_2"):
		equip(1)
	elif event.is_action_pressed("weapon_3"):
		equip(2)
	elif event.is_action_pressed("next_weapon") and not weapons.is_empty():
		equip(posmod(current + 1, weapons.size()))
	elif event.is_action_pressed("previous_weapon") and not weapons.is_empty():
		equip(posmod(current - 1, weapons.size()))


func _physics_process(delta: float) -> void:
	var weapon := current_weapon()
	if weapon == null or _player.model == null:
		return
	var can_act := not Debug.console_open
	_controls.trigger = can_act and Input.is_action_pressed("fire")
	_controls.reload_pressed = can_act and Input.is_action_just_pressed("reload")
	_controls.inspect_pressed = can_act and Input.is_action_just_pressed("inspect")
	if _controls.trigger and _player.model.is_sprinting():
		_player.model.interrupt_sprint()  # firing drops out of sprint
	_controls.sprinting = _player.model.is_sprinting()

	var shots := weapon.update(_controls, delta)
	var aiming := _player.model.aiming and weapon.state != WeaponModel.State.INSPECTING
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, delta / weapon.definition.ads_time)
	current_spread = weapon.spread_degrees(aim_blend, _move_fraction(),
			_stance_multiplier(weapon.definition)) if spread_enabled else 0.0
	for i in shots:
		_shoot(weapon, weapon.last_kicks[i])
	_play_mechanism_events(weapon)
	_publish_watches(weapon)


func _process(delta: float) -> void:
	if _player.model == null:
		return
	_view.update_pose(delta, current_weapon(), aim_blend, _player.model.is_sprinting(), _look_delta)
	_look_delta = Vector2.ZERO


func _shoot(weapon: WeaponModel, kick: Vector2) -> void:
	var definition := weapon.definition
	var aim := _player.aim_transform()
	var forward := -aim.basis.z
	var exclude: Array[RID] = [_player.get_rid()]
	var center := BallisticsMath.random_in_cone(forward, current_spread, _rng)
	for pellet in definition.pellets:
		var direction := center
		if definition.pellets > 1:
			direction = BallisticsMath.random_in_cone(center, definition.pellet_spread_degrees, _rng)
		Ballistics.fire(aim.origin, direction, definition, _player, exclude)
	var recoil_scale := lerpf(1.0, definition.recoil_ads_multiplier, aim_blend)
	_player.add_recoil(kick.x * recoil_scale, kick.y * recoil_scale)
	_player.camera_rig().add_kick(definition.visual_kick_degrees)
	_view.kick()
	_view.flash()
	_audio.stream = ProceduralAudio.cached("shot:" + definition.id,
			func() -> AudioStreamWAV: return ProceduralAudio.gunshot(definition))
	_audio.volume_db = definition.shot_volume_db
	_audio.play()
	if definition.casing_ejects and not definition.casing_eject_on_pump:
		_eject_casing(definition)
	shot_fired.emit(definition)


## Plays mechanism sounds as the weapon's timed states cross the points where
## the view model's animation makes contact (WeaponViewModel uses the same
## ViewModelTuning timings), and throws pump hulls.
func _play_mechanism_events(weapon: WeaponModel) -> void:
	var definition := weapon.definition
	var progress := weapon.state_progress()
	if weapon.state != _last_state:
		_last_progress = 0.0
	var crossed := func(point: float) -> bool: return _last_progress < point and progress >= point
	match weapon.state:
		WeaponModel.State.PUMPING:
			if crossed.call(view_tuning.pump_back_end):
				_play_mechanism("rack_back", definition)
				if definition.casing_ejects and definition.casing_eject_on_pump:
					_eject_casing(definition)
			if crossed.call(view_tuning.pump_forward_end):
				_play_mechanism("rack_forward", definition)
		WeaponModel.State.RELOADING:
			if definition.reload_mode == WeaponDefinition.ReloadMode.PER_SHELL:
				if weapon.ammo > _last_ammo:
					_play_mechanism("shell_insert", definition)
			else:
				if crossed.call(view_tuning.magazine_out_start):
					_play_mechanism("magazine_out", definition)
				if crossed.call(view_tuning.magazine_in_end):
					_play_mechanism("magazine_in", definition)
				if weapon.reload_is_empty and crossed.call(view_tuning.bolt_release_at):
					_play_mechanism("bolt_release", definition)
	# A shell reload's last insert lands on the tick it leaves RELOADING.
	if _last_state == WeaponModel.State.RELOADING and weapon.state != WeaponModel.State.RELOADING \
			and definition.reload_mode == WeaponDefinition.ReloadMode.PER_SHELL and weapon.ammo > _last_ammo:
		_play_mechanism("shell_insert", definition)
	_last_state = weapon.state
	_last_progress = progress
	_last_ammo = weapon.ammo


func _play_mechanism(sound: String, definition: WeaponDefinition) -> void:
	_mechanism_audio.stream = ProceduralAudio.cached("%s:%s" % [sound, definition.id],
			func() -> AudioStreamWAV: return _build_mechanism(sound, definition))
	_mechanism_audio.volume_db = definition.mech_volume_db
	_mechanism_audio.play()
	mechanical_sound.emit(sound)


func _build_mechanism(sound: String, definition: WeaponDefinition) -> AudioStreamWAV:
	match sound:
		"magazine_out":
			return ProceduralAudio.magazine_out(definition)
		"magazine_in":
			return ProceduralAudio.magazine_in(definition)
		"bolt_release":
			return ProceduralAudio.bolt_release(definition)
		"rack_back":
			return ProceduralAudio.rack_back(definition)
		"rack_forward":
			return ProceduralAudio.rack_forward(definition)
	return ProceduralAudio.shell_insert(definition)


func _eject_casing(definition: WeaponDefinition) -> void:
	var port := _view.ejection_port()
	var jitter := Vector3(randf_range(0.85, 1.15), randf_range(0.85, 1.15), randf_range(0.7, 1.3))
	var throw := port.basis * (definition.casing_eject_velocity * jitter)
	_casings.eject(definition, port, throw + _player.velocity)


## For probes: casings report where they land.
func casing_ejector() -> CasingEjector:
	return _casings


func _add_weapon(definition: WeaponDefinition) -> int:
	weapons.append(WeaponModel.new(definition))
	Ballistics.effects().prioritize_energy(definition.impact_energy)  # its hit sounds get built first
	return weapons.size() - 1


func _move_fraction() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length() / _player.tuning.walk_speed


func _stance_multiplier(definition: WeaponDefinition) -> float:
	match _player.model.stance:
		MovementModel.Stance.CROUCH:
			return definition.spread_crouch_multiplier
		MovementModel.Stance.PRONE:
			return definition.spread_prone_multiplier
	return 1.0


func _find_player() -> Player:
	var node := get_parent()
	while node != null and not node is Player:
		node = node.get_parent()
	return node as Player


func _publish_watches(weapon: WeaponModel) -> void:
	if not Debug.show_watches:
		return
	Debug.watch("weapon", "%s %s" % [weapon.definition.display_name, WeaponModel.State.keys()[weapon.state]])
	Debug.watch("ammo", "%d / %d" % [weapon.ammo, weapon.reserve])
	Debug.watch("recoil index", weapon.recoil_index)
	Debug.watch("spread", "%.2f deg (aim %.2f)" % [current_spread, aim_blend])
	Debug.watch("bullets in flight", Ballistics.active_bullets())


func _register_debug_commands() -> void:
	Debug.register("give", _cmd_give, "give <weapon id>: add or switch to a weapon (data/weapons/<id>.tres).")
	Debug.register("ammo.infinite", _cmd_infinite_ammo, "Toggle infinite ammo for every carried weapon.")
	Debug.register("spread", _cmd_spread, "Toggle spread (off = every shot goes dead centre).")
	Debug.register("recoil.show", _cmd_recoil_show, "Toggle the weapon readout (ammo, recoil index, spread).")


func _cmd_give(args: PackedStringArray) -> String:
	if args.size() != 1:
		return "usage: give <weapon id>"
	for slot in weapons.size():
		if weapons[slot].definition.id == args[0]:
			equip(slot)
			return "switched to %s" % weapons[slot].definition.display_name
	var path := "res://data/weapons/%s.tres" % args[0]
	if not ResourceLoader.exists(path):
		return "no weapon file %s" % path
	var definition := load(path) as WeaponDefinition
	if definition == null:
		return "%s is not a WeaponDefinition" % path
	equip(_add_weapon(definition))
	return "gave %s" % definition.display_name


func _cmd_infinite_ammo(_args: PackedStringArray) -> String:
	var enable := weapons.is_empty() or not weapons[0].infinite_ammo
	for weapon in weapons:
		weapon.infinite_ammo = enable
	return "infinite ammo %s" % ("ON" if enable else "OFF")


func _cmd_spread(_args: PackedStringArray) -> String:
	spread_enabled = not spread_enabled
	return "spread %s" % ("ON" if spread_enabled else "OFF")


func _cmd_recoil_show(_args: PackedStringArray) -> String:
	Debug.show_watches = not Debug.show_watches
	if not Debug.show_watches:
		Debug.watches.clear()
	return "weapon readout %s" % ("ON" if Debug.show_watches else "OFF")
