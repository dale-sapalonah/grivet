extends Node
## Headless gunplay probe for the Milestone 2 exit check. Loads the firing
## range and shoots it with real input actions: hits at every distance, bullet
## drop and flight time, penetration per weapon and panel, ricochet, recoil
## repeatability, reloads and the shotgun pump. Exit code 0 = all passed.
##
##   $GODOT --headless --path . res://tests/probes/firing_range.tscn

const RANGE := "res://levels/greybox/firing_range.tscn"
const PHYSICS_HZ := 120
const WATCHDOG_SECONDS := 180.0
const RIFLE := 0
const SHOTGUN := 1
const PISTOL := 2
## Aim height on the 1.8 m dummies (centre).
const TARGET_CENTRE_Y := 0.9

var level: Node
var player: Player
var holder: WeaponHolder
var failures := 0
var _hits: Array[Dictionary] = []
var _impacts: Array[Dictionary] = []


func _ready() -> void:
	level = load(RANGE).instantiate()
	add_child(level)
	player = level.get_node("Player")
	holder = player.get_node("Head/CameraRig/Camera3D/WeaponHolder")
	Ballistics.target_hit.connect(func(info: Dictionary) -> void:
		info["frame"] = Engine.get_physics_frames()
		_hits.append(info))
	Ballistics.impact.connect(func(info: Dictionary) -> void: _impacts.append(info))
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
		printerr("FAIL watchdog: probe did not finish in %d s" % WATCHDOG_SECONDS)
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await _wait(0.6)
	holder.spread_enabled = false

	await _check("rifle hits the 10 / 25 / 50 / 100 m targets", func() -> String:
		await _use(RIFLE)
		var missed := PackedStringArray()
		for target_name in ["Target10", "Target25", "Target50", "Target100"]:
			var target := level.get_node(target_name) as Node3D
			_aim_at(target.global_position + Vector3(0, 0.3, 0.15))
			await _shoot_and_wait(0.4)
			if _hits_on(target).is_empty():
				missed.append(target_name)
		return "" if missed.is_empty() else "missed %s" % ", ".join(missed))

	await _check("pistol drop and flight time at 100 m match physics", func() -> String:
		await _use(PISTOL)
		var target := level.get_node("Target100") as Node3D
		var aim_point := target.global_position + Vector3(0, 0.3, 0.15)
		_aim_at(aim_point)
		var fired_frame := Engine.get_physics_frames()
		await _shoot_and_wait(0.6)
		var hits := _hits_on(target)
		if hits.is_empty():
			return "no hit"
		var hit: Dictionary = hits[0]
		var distance := player.aim_transform().origin.distance_to(aim_point)
		var flight := distance / holder.current_weapon().definition.muzzle_velocity
		var expected_drop := 0.5 * Ballistics.settings.gravity * flight * flight
		var drop := aim_point.y - (hit.position as Vector3).y
		var frames := int(hit.frame) - fired_frame
		var detail := "drop %.3f m (expected %.3f), flight %d ticks (expected %.0f)" % [
				drop, expected_drop, frames, flight * PHYSICS_HZ]
		print("  " + detail)
		var ok := absf(drop - expected_drop) < 0.05 and absf(frames - flight * PHYSICS_HZ) <= 3.0
		return "" if ok else detail)

	for case in [
			[RIFLE, "Wood5cm", true], [RIFLE, "Wood20cm", true],
			[RIFLE, "Steel5mm", true], [RIFLE, "Concrete30cm", false],
			[PISTOL, "Wood5cm", true], [PISTOL, "Wood20cm", false], [PISTOL, "Steel5mm", true],
			[RIFLE, "Steel20mm", false], [PISTOL, "Steel20mm", false], [RIFLE, "TreeTrunk", false]]:
		var weapon_name := "rifle" if case[0] == RIFLE else "pistol"
		var verb := "penetrates" if case[2] else "is stopped by"
		await _check("%s %s %s" % [weapon_name, verb, case[1]], func() -> String:
			await _use(case[0])
			var panel := level.get_node(case[1]) as Node3D
			var behind := level.get_node("Behind" + case[1]) as Node3D
			await _teleport(Vector3(panel.global_position.x, 0, -8))
			_aim_at(behind.global_position + Vector3(0, 0.1, 0.15))
			await _shoot_and_wait(0.4)
			var got_through := not _hits_on(behind).is_empty()
			return "" if got_through == case[2] else "behind-target hit = %s" % got_through)

	await _check("impacts report outcome and measured thickness", func() -> String:
		await _use(RIFLE)
		var problems := PackedStringArray()
		for case in [["Steel5mm", "penetrated", 0.005], ["Steel20mm", "stopped", 0.02],
				["Wood5cm", "penetrated", 0.05], ["TreeTrunk", "stopped", 0.5]]:
			var panel := level.get_node(case[0]) as Node3D
			await _teleport(Vector3(panel.global_position.x, 0, -8))
			_impacts.clear()
			_aim_at(Vector3(panel.global_position.x, 1.0, panel.global_position.z))
			await _shoot_and_wait(0.3)
			var first: Dictionary = _impacts[0] if not _impacts.is_empty() else {}
			if first.is_empty() or first.kind != case[1] or absf(first.thickness - case[2]) > 0.01:
				var seen := PackedStringArray()
				for impact in _impacts:
					seen.append("%s %s %.3f m%s at %s" % [impact.surface, impact.kind, impact.thickness,
							" solid" if impact.solid else "", (impact.position as Vector3).snappedf(0.01)])
				problems.append("%s: [%s]" % [case[0], "; ".join(seen)])
		return ", ".join(problems))

	await _check("rifle ricochets off the grazing steel plate", func() -> String:
		await _use(RIFLE)
		await _teleport(Vector3.ZERO)
		_aim_at((level.get_node("RicochetPlate") as Node3D).global_position)
		await _shoot_and_wait(0.4)
		var kinds := PackedStringArray()
		for impact in _impacts:
			kinds.append("%s:%s" % [impact.surface, impact.kind])
		return "" if kinds.has("steel:ricochet") else "impacts: %s" % ", ".join(kinds))

	await _check("rifle recoil pattern repeats exactly", func() -> String:
		await _use(RIFLE)
		await _teleport(Vector3.ZERO)
		holder.current_weapon().infinite_ammo = true  # both bursts must be full length
		var first := await _record_burst(Vector3(0, 1.65, -50), 0.9)
		await _wait(holder.current_weapon().definition.recoil_reset_time + 0.2)
		var second := await _record_burst(Vector3(0, 1.65, -50), 0.9)
		holder.current_weapon().infinite_ammo = false
		if first.size() < 10:
			return "only %d shots recorded" % first.size()
		if first.size() != second.size():
			return "shot counts differ: %d vs %d" % [first.size(), second.size()]
		for i in first.size():
			if not first[i].is_equal_approx(second[i]):
				return "shot %d differs: %s vs %s" % [i, first[i], second[i]]
		print("  %d shots, final climb %.2f deg up, %.2f deg sideways" % [
				first.size(), rad_to_deg(first[-1].y), rad_to_deg(-first[-1].x)])
		return "")

	await _check("empty reload refills the magazine", func() -> String:
		await _use(RIFLE)
		var weapon := holder.current_weapon()
		weapon.ammo = 2
		await _hold("fire", 0.4)
		if weapon.ammo != 0:
			return "magazine not empty: %d" % weapon.ammo
		await _tap("fire")  # trigger on empty starts the reload
		await _wait(weapon.definition.reload_empty_time + 0.2)
		var expected := weapon.definition.magazine_size
		return "" if weapon.ammo == expected else "ammo %d, expected %d" % [weapon.ammo, expected])

	await _check("tactical reload keeps the chambered round", func() -> String:
		var weapon := holder.current_weapon()
		weapon.ammo = 10
		await _tap("reload")
		await _wait(weapon.definition.reload_tactical_time + 0.2)
		var expected := weapon.definition.magazine_size + 1
		return "" if weapon.ammo == expected else "ammo %d, expected %d" % [weapon.ammo, expected])

	await _check("shotgun throws pellets and must pump", func() -> String:
		holder.spread_enabled = true
		holder._rng.seed = 1234  # repeatable pellet pattern for the probe
		await _use(SHOTGUN)
		var weapon := holder.current_weapon()
		var target := level.get_node("Target10") as Node3D
		_aim_at(target.global_position + Vector3(0, 0.3, 0.15))
		var ammo_before := weapon.ammo
		await _tap("fire")
		await _tap("fire")  # during the pump: must not fire
		await _wait(0.3)
		var pellet_hits := _hits_on(target).size()
		var fired := ammo_before - weapon.ammo
		holder.spread_enabled = false
		print("  %d of %d pellets hit at 10 m" % [pellet_hits, weapon.definition.pellets])
		var ok := pellet_hits >= weapon.definition.pellets / 2 and fired == 1
		return "" if ok else "pellet hits %d, shells used %d" % [pellet_hits, fired])

	var sounds: Array[Dictionary] = []
	Ballistics.effects().sound_scheduled.connect(func(kind: String, surface: String, delay: float) -> void:
		sounds.append({"kind": kind, "surface": surface, "delay": delay}))
	var landings: Array[String] = []
	holder.casing_ejector().casing_landed.connect(func(surface: String, _bounce: int) -> void:
		landings.append(surface))
	var mechanisms: Array[String] = []
	holder.mechanical_sound.connect(func(sound: String) -> void: mechanisms.append(sound))

	await _check("steel hit rings, heard after the speed-of-sound delay", func() -> String:
		await _use(RIFLE)
		var panel := level.get_node("Steel5mm") as Node3D
		await _teleport(Vector3(panel.global_position.x, 0, -8))
		sounds.clear()
		_aim_at(panel.global_position + Vector3(0, 0.3, 0))
		await _shoot_and_wait(0.3)
		var expected := player.aim_transform().origin.distance_to(panel.global_position) / Ballistics.settings.speed_of_sound
		for sound in sounds:
			if sound.surface == "steel" and sound.kind == "penetrated":
				return "" if absf(sound.delay - expected) < 0.01 else "delay %.3f s, expected %.3f" % [sound.delay, expected]
		return "sounds: %s" % str(sounds))

	await _check("100 m hit is heard about 0.29 s late", func() -> String:
		await _teleport(Vector3.ZERO)
		sounds.clear()
		var target := level.get_node("Target100") as Node3D
		_aim_at(target.global_position + Vector3(0, 0.3, 0.15))
		await _shoot_and_wait(0.5)
		for sound in sounds:
			if sound.surface == "flesh":
				print("  flesh hit heard %.3f s after impact" % sound.delay)
				return "" if absf(sound.delay - 100.0 / Ballistics.settings.speed_of_sound) < 0.02 \
						else "delay %.3f" % sound.delay
		return "sounds: %s" % str(sounds))

	await _check("rifle casings bounce and clink on the concrete floor", func() -> String:
		landings.clear()
		await _shoot_and_wait(1.2)
		return "" if landings.has("concrete") else "landings: %s" % str(landings))

	await _check("shotgun racks back then forward, then the hull lands", func() -> String:
		await _use(SHOTGUN)
		mechanisms.clear()
		landings.clear()
		await _shoot_and_wait(holder.current_weapon().definition.pump_time + 1.0)
		var racks := mechanisms.filter(func(sound: String) -> bool: return sound.begins_with("rack"))
		var ok := racks == ["rack_back", "rack_forward"] and landings.has("concrete")
		return "" if ok else "mechanisms %s, landings %s" % [str(mechanisms), str(landings)])

	await _check("shotgun clicks once per shell loaded", func() -> String:
		var weapon := holder.current_weapon()
		weapon.ammo = 3
		mechanisms.clear()
		await _tap("reload")
		var definition := weapon.definition
		await _wait(definition.reload_start_time + definition.shell_insert_time * 3.0 + 0.3)
		var inserts := mechanisms.count("shell_insert")
		return "" if inserts == 3 and weapon.ammo == 6 else "inserts %d, ammo %d" % [inserts, weapon.ammo])

	await _check("empty magazine reload: out, in, bolt release, in that order", func() -> String:
		await _use(RIFLE)
		var weapon := holder.current_weapon()
		weapon.ammo = 0
		mechanisms.clear()
		await _tap("reload")
		await _wait(weapon.definition.reload_empty_time + 0.2)
		var expected := ["magazine_out", "magazine_in", "bolt_release"]
		return "" if mechanisms == expected else "got %s" % str(mechanisms))

	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


func _check(title: String, body: Callable) -> void:
	_hits.clear()
	_impacts.clear()
	var detail: String = await body.call()
	_release_all()
	if detail.is_empty():
		print("PASS %s" % title)
	else:
		failures += 1
		printerr("FAIL %s - %s" % [title, detail])


func _use(slot: int) -> void:
	if holder.current != slot:
		holder.equip(slot)
	await _wait(holder.current_weapon().definition.equip_time + 0.1)
	var weapon := holder.current_weapon()
	while weapon.state != WeaponModel.State.READY:
		await get_tree().physics_frame


func _teleport(feet: Vector3) -> void:
	player.global_position = feet
	player.velocity = Vector3.ZERO
	await _wait(0.3)


## Turns the player so the eye looks straight at `point`.
func _aim_at(point: Vector3) -> void:
	var direction := point - player.aim_transform().origin
	var yaw := atan2(-direction.x, -direction.z)
	var pitch := atan2(direction.y, Vector2(direction.x, direction.z).length())
	player.set_look(yaw, pitch)


func _shoot_and_wait(seconds: float) -> void:
	await _tap("fire")
	await _wait(seconds)


## Holds fire from a fixed aim and records the look (yaw, pitch) after every
## shot, relative to where the burst started.
func _record_burst(aim_point: Vector3, seconds: float) -> Array[Vector2]:
	_aim_at(aim_point)
	var start := Vector2(player.rotation.y, player.look_pitch())
	var looks: Array[Vector2] = []
	var record := func(_definition: WeaponDefinition) -> void:
		looks.append(Vector2(player.rotation.y, player.look_pitch()) - start)
	holder.shot_fired.connect(record)
	await _hold("fire", seconds)
	holder.shot_fired.disconnect(record)
	return looks


func _hits_on(target: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for hit in _hits:
		if hit.target == target:
			found.append(hit)
	return found


func _tap(action: String) -> void:
	await get_tree().physics_frame  # let a release from the previous step register
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)


func _wait(seconds: float) -> void:
	for i in roundi(seconds * PHYSICS_HZ):
		await get_tree().physics_frame


func _release_all() -> void:
	for action: String in InputMap.get_actions():
		Input.action_release(action)
