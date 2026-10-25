extends "res://levels/greybox/arena.gd"
## Container terminal at dusk, the vertical slice's setting: the combat
## arena's validated layout dressed as a port yard. Everything that blocks
## movement or bullets is a CSG box in the scene (tools/gen_port.py), so the
## navmesh, cover map and ballistics see it; this script only adds what is
## seen: sandbags bag by bag, jersey barrier profiles, container frames,
## crate boards, the warehouse roof, sodium lamp heads and their lights on the "lamp_pole" poles, a quay
## crane, container stacks beyond the walls, a moored ship, the warehouse's
## lights, the parked PMV buses ("pmv_bus" bodies) and Port Moresby
## street life: shipping-line names and Tok Pisin stencils, a PMV stop, a
## buai market and coconut palms.
## Lights cast no shadows (the low sun does).

const HALO_SHADER := preload("res://levels/port/materials/halo.gdshader")
const CONCRETE_SHADER := preload("res://levels/port/materials/concrete.gdshader")
const CRATE_SHADER := preload("res://levels/port/materials/crate.gdshader")
const NOISE := preload("res://levels/port/materials/noise.tres")
const WHITE_PAINT := Color(0.85, 0.85, 0.8)
const YELLOW_PAINT := Color(0.9, 0.72, 0.15)
const RED_PAINT := Color(0.7, 0.1, 0.07)
const BLACK_PAINT := Color(0.08, 0.08, 0.08)

## Painted markings: [box node under Navigation, face normal, offset along the
## face (m, from its middle), height above ground (m), text, letter height (m),
## colour]. Shipping lines and goods are made up (original IP only); the
## words are Tok Pisin and PNG place names for a Port Moresby feel.
const MARKINGS := [
	["ContainerMidW", Vector3(0, 0, 1), -0.4, 1.55, "KUMUL LAIN", 0.5, WHITE_PAINT],
	["ContainerMidW", Vector3(0, 0, 1), 2.1, 2.2, "KMLU 402117 3", 0.11, WHITE_PAINT],
	["ContainerMidE", Vector3(-1, 0, 0), 0.0, 1.6, "PASIFIK FREIT", 0.42, YELLOW_PAINT],
	["ContainerSW", Vector3(1, 0, 0), 0.0, 1.6, "NIUGINI KONTENA", 0.38, WHITE_PAINT],
	["ContainerSW", Vector3(1, 0, 0), -2.2, 2.25, "NGKU 117045 0", 0.11, WHITE_PAINT],
	["ContainerNW", Vector3(0, 0, 1), 0.0, 1.5, "MOSBI KAGO", 0.48, WHITE_PAINT],
	["ContainerNWTop", Vector3(0, 0, 1), 0.0, 4.1, "KUMUL LAIN", 0.5, WHITE_PAINT],
	["WallNorth", Vector3(0, 0, 1), -27.45, 1.5, "KUMUL LAIN", 0.5, WHITE_PAINT],
	["WallNorth", Vector3(0, 0, 1), 9.15, 4.1, "PASIFIK FREIT", 0.45, YELLOW_PAINT],
	["WallNorth", Vector3(0, 0, 1), 21.35, 1.5, "NIUGINI KONTENA", 0.38, WHITE_PAINT],
	["WallEastS", Vector3(-1, 0, 0), 3.05, 1.5, "MOSBI KAGO", 0.48, WHITE_PAINT],
	["WallEastN", Vector3(-1, 0, 0), 3.05, 4.1, "KUMUL LAIN", 0.5, WHITE_PAINT],
	["WallWest", Vector3(1, 0, 0), -9.15, 1.5, "PASIFIK FREIT", 0.45, YELLOW_PAINT],
	["WallWest", Vector3(1, 0, 0), 15.25, 4.1, "NIUGINI KONTENA", 0.38, WHITE_PAINT],
	["CrateSW", Vector3(0, 0, -1), 0.0, 0.7, "LAE > POM", 0.14, BLACK_PAINT],
	["CrateSE", Vector3(0, 0, -1), 0.0, 0.7, "RAIS 25KG", 0.14, BLACK_PAINT],
	["CrateN1", Vector3(0, 0, 1), 0.0, 0.7, "LUKAUTIM GUT", 0.11, RED_PAINT],
	["CrateN2", Vector3(0, 0, 1), 0.0, 0.75, "DISPELA SAIT
I GO ANTAP ^", 0.1, BLACK_PAINT],
	["CrateStackLow", Vector3(1, 0, 0), 0.0, 0.6, "KOPI - GOROKA", 0.11, BLACK_PAINT],
	["CrateStackHigh", Vector3(1, 0, 0), 0.0, 1.85, "TINPIS", 0.16, BLACK_PAINT],
	["BldgCrateW", Vector3(1, 0, 0), 0.0, 0.7, "KAPA - LAE", 0.13, BLACK_PAINT],
	["BldgSouthA", Vector3(0, 0, 1), 0.0, 2.45, "NIUGINI KONTENA SEVIS", 0.24, YELLOW_PAINT],
	["BldgSouthB", Vector3(0, 0, 1), 0.0, 1.65, "TAMBU
NO KEN
GO INSAIT", 0.13, RED_PAINT],
	["BarrierMid1", Vector3(0, 0, 1), 0.0, 0.6, "ISI ISI", 0.2, YELLOW_PAINT],
	["BarrierMid2", Vector3(0, 0, 1), 0.0, 0.6, "STOP", 0.22, RED_PAINT],
]

## Low-pressure sodium: nearly monochrome orange.
@export var lamp_color := Color(1.0, 0.6, 0.24)
@export var lamp_energy := 9.0
## Just past the cone's reach to the ground (8 m poles): every metre of range
## costs shading on every pixel inside it.
@export var lamp_range := 12.0
@export var lamp_angle_degrees := 60.0
@export var warehouse_light_color := Color(0.78, 0.86, 1.0)
@export var warehouse_light_energy := 1.2
@export_group("Draw distances (m)")
## Lamps beyond this fade out (their halos, heads and ground glow stay).
@export var lamp_fade_distance := 30.0
## Only this many street lamps nearest the player are real lights (each one
## costs every pixel it touches); the rest show just their glow.
@export var lamp_lit_count := 3
@export var sandbag_draw_distance := 55.0
@export var frame_draw_distance := 50.0
@export_group("")

## Stages played in order; each clears to "KLIN CHOL!" / "WARAA!".
@export var campaign: Campaign = preload("res://data/levels/campaign.tres")
var stage := 0
var _stage_live := false
## Where the player may (re)spawn: x, facing (degrees, 0 = north), z. The
## picker takes the one furthest from the enemy that no enemy can see.
@export var safe_spots: PackedVector3Array = PackedVector3Array([Vector3(0, 0, 26), Vector3(-25, 0, 26),
		Vector3(24, 0, 28), Vector3(-27, -90, 4), Vector3(27, 90, -27), Vector3(-27, -90, -27), Vector3(40, -90, 0),
		Vector3(52, 0, 29.5), Vector3(57, 180, -29), Vector3(95, 90, -28), Vector3(95, 90, 28)])
## A spot is safe when no enemy is nearer than this (m) and none can see it.
@export var safe_distance := 25.0
## Buai bundles laid out at the start of every stage (heal when chewed).
@export var buai_spots: PackedVector3Array = PackedVector3Array([Vector3(-27.4, 0, 17.4), Vector3(-6, 0, 23),
		Vector3(12, 0, 12), Vector3(-12, 0, -10), Vector3(36, 0, -2), Vector3(54, 0, 26), Vector3(60, 0, -28),
		Vector3(92, 0, -2), Vector3(80, 0, 14)])

var _lamps: Array[Light3D] = []
var _street_lights: Array[SpotLight3D] = []
var _lamps_off := false
var _lamp_timer := 0.0
var _glow_texture: GradientTexture2D
var _stencil_font: SystemFont
var _props: StandardMaterial3D
var _glow_sodium: StandardMaterial3D
var _glow_red: StandardMaterial3D
var _glow_window: StandardMaterial3D
var _halo_sodium: ShaderMaterial
var _halo_red: ShaderMaterial


func _ready() -> void:
	add_to_group("spawn_picker")
	MusicPlayer.play_set("game")
	Debug.register("env", _cmd_env, "env <property> <value>: set a WorldEnvironment property (dots for underscores, e.g. env glow.enabled false).")
	Debug.register("lamps", _cmd_lamps, "Toggle the yard's lamp and warehouse lights.")
	Debug.register("sun.shadows", _cmd_sun_shadows, "Toggle the sun's shadows.")
	Debug.register("sun.distance", _cmd_sun_distance, "sun.distance <m>: how far the sun's shadows reach.")
	Debug.register("visual", _cmd_visual, "visual <name prefix>: hide or show the level's dressing whose names start so (profiling).")
	Debug.register("stage", _cmd_stage, "stage <1-%d>: clear the field and start that stage." % campaign.stages.size())
	_props = StandardMaterial3D.new()
	_props.vertex_color_use_as_albedo = true
	_props.vertex_color_is_srgb = true
	_props.roughness = 0.7
	_props.metallic = 0.3
	_glow_sodium = _emissive(lamp_color, 8.0)
	_glow_red = _emissive(Color(1.0, 0.08, 0.05), 6.0)
	_glow_window = _emissive(Color(1.0, 0.82, 0.55), 1.6)
	_halo_sodium = _halo_material(lamp_color, 1.2)
	_halo_red = _halo_material(Color(1.0, 0.1, 0.06), 1.5)
	for pole: Node3D in get_tree().get_nodes_in_group("lamp_pole"):
		if is_ancestor_of(pole):
			_dress_pole(pole)
	for bus: Node3D in get_tree().get_nodes_in_group("pmv_bus"):
		if is_ancestor_of(bus):
			# Beside, not under, the navigation region: the bake reads colliders only.
			var pmv := PmvBus.new()
			add_child(pmv)
			pmv.global_transform = bus.global_transform
			pmv.build(bus.get_meta("livery"), str(bus.get_meta("route")), str(bus.get_meta("plate")), bus.get_meta("headlights"))
	_stencil_font = SystemFont.new()
	_stencil_font.font_names = PackedStringArray(["Stencil", "Impact", "Arial Black", "Arial"])
	for marking in MARKINGS:
		_paint_marking(marking)
	_build_bus_stop(Vector3(-22, 0, 23.6), 10.0)
	_build_market(Vector3(-28.6, 0, 19), 90.0)
	_build_palms()
	_dress_taxis()
	_dress_stores()
	_build_market(Vector3(54, 0, 27.5), 180.0)
	_build_sandbags()
	_build_jersey_barriers()
	_build_container_frames()
	_build_crate_frames()
	_build_warehouse_roof()
	_apply_pbr_textures()
	_build_crane(Vector3(-6, 0, -58))
	_build_stacks()
	_build_ship(Vector3(-100, 0, 0))
	for room in [Vector3(11, 2.7, -19), Vector3(17, 2.7, -19)]:
		var light := OmniLight3D.new()
		light.light_color = warehouse_light_color
		light.light_energy = warehouse_light_energy
		light.omni_range = 7.0
		light.position = room
		add_child(light)
		_lamps.append(light)
	super()


func _exit_tree() -> void:
	super()
	Debug.unregister("env")
	Debug.unregister("lamps")
	Debug.unregister("sun.shadows")
	Debug.unregister("sun.distance")
	Debug.unregister("visual")
	Debug.unregister("stage")


func _cmd_env(args: PackedStringArray) -> String:
	if args.size() < 2:
		return "usage: env <property> <value>"
	var environment := ($WorldEnvironment as WorldEnvironment).environment
	var property := args[0].replace(".", "_")
	if not property in environment:
		return "no environment property %s" % property
	environment.set(property, str_to_var(args[1]))
	return "%s = %s" % [property, environment.get(property)]


func _cmd_lamps(_args: PackedStringArray) -> String:
	_lamps_off = not _lamps_off
	for light in _lamps:
		light.visible = not _lamps_off
	_update_lamp_lod()
	return "lamps %s" % ("off" if _lamps_off else "on")


## Lights the street lamps nearest the player; the others keep only their glow.
func _update_lamp_lod() -> void:
	var player := get_node_or_null("Player") as Node3D
	var at := player.global_position if player != null else Vector3.ZERO
	var by_distance := _street_lights.duplicate()
	by_distance.sort_custom(func(a: SpotLight3D, b: SpotLight3D) -> bool:
		return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
	for i in by_distance.size():
		var light: SpotLight3D = by_distance[i]
		light.visible = not _lamps_off and i < lamp_lit_count 				and light.global_position.distance_to(at) < lamp_fade_distance + 10.0


## Soft round glow for the lamps' ground decals.
func _lamp_glow_texture() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1), Color(0.35, 0.35, 0.35), Color(0, 0, 0)])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(0.5, 0.0)
		_glow_texture.width = 128
		_glow_texture.height = 128
	return _glow_texture


# --- Campaign -----------------------------------------------------------------

## Where to (re)spawn the player: `preferred` (the stage start) when it is
## safe, else the candidate spot furthest from every enemy that none can see.
func pick_spawn(preferred: Transform3D) -> Transform3D:
	if AI.soldiers.is_empty() or _spot_safety(preferred.origin) >= safe_distance:
		return preferred
	var best := preferred
	var best_score := _spot_safety(preferred.origin)
	for spot in safe_spots:
		var at := Vector3(spot.x, 0.0, spot.z)
		var score := _spot_safety(at)
		if score > best_score:
			best_score = score
			best = Transform3D(Basis(Vector3.UP, deg_to_rad(spot.y)), at)
	return best


## Nearest enemy's distance from `at`, or a big penalty if any of them can see it.
func _spot_safety(at: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var head := at + Vector3.UP * 1.6
	var nearest := INF
	for soldier in AI.soldiers:
		nearest = minf(nearest, CoverScoring.flat_distance(soldier.global_position, at))
		var query := PhysicsRayQueryParameters3D.create(soldier.eye_point(), head, PhysicsLayers.WORLD)
		if space.intersect_ray(query).is_empty():
			return nearest - 1000.0  # in someone's sights
	return nearest

## Called once the navmesh and cover map are ready: the current stage's squad.
func spawn_squad() -> void:
	if not _stage_live:  # a `stage` jump may already have fielded one
		stage = clampi(Settings.requested_stage, 0, campaign.stages.size() - 1)
		_start_stage(stage, stage > 0)


func _process(delta: float) -> void:
	_lamp_timer -= delta
	if _lamp_timer <= 0.0:
		_lamp_timer = 0.5
		_update_lamp_lod()
	if _stage_live and AI.soldiers.is_empty():
		_stage_live = false
		_stage_cleared()


func _start_stage(index: int, move_player: bool) -> void:
	stage = index
	var definition := campaign.stages[index]
	for marker: Node3D in get_tree().get_nodes_in_group("enemy_spawn"):
		if is_ancestor_of(marker) and int(marker.get_meta("level", 1)) == definition.marker_level:
			AI.spawn(str(marker.get_meta("enemy", "rifleman")), marker.global_transform, self, definition)
	# Squad first, then the player: the spawn picker keeps them apart.
	if move_player:
		var player := $Player as Player
		player.set_spawn(Transform3D(Basis(Vector3.UP, deg_to_rad(definition.player_yaw_degrees)), definition.player_start))
		player.respawn()
		var holder := get_tree().get_first_node_in_group("player_weapons") as WeaponHolder
		if holder != null:
			holder.refill()
	_stage_live = not AI.soldiers.is_empty()
	_lay_buai()
	_announce(definition.title, GrivetStyle.WHITE, 2.6, definition.subtitle)


## Fresh buai for the stage: old bundles cleared, spit splashes kept.
func _lay_buai() -> void:
	for old in get_tree().get_nodes_in_group("buai"):
		if is_ancestor_of(old):
			old.queue_free()
	for spot in buai_spots:
		var pickup := BuaiPickup.new()
		pickup.add_to_group("buai")
		add_child(pickup)
		pickup.global_position = spot


## Everyone down: shout it, then on to the next stage (or the end).
func _stage_cleared() -> void:
	for i in campaign.cleared_shouts.size():
		_announce(campaign.cleared_shouts[i], campaign.cleared_colors[i % campaign.cleared_colors.size()], 1.4)
	var last := stage + 1 >= campaign.stages.size()
	if last:
		_announce(campaign.final_shout, GrivetStyle.GOLD, 5.0, campaign.final_subtitle)
		return
	await get_tree().create_timer(campaign.next_stage_delay).timeout
	if is_inside_tree():
		_start_stage(stage + 1, true)


func _announce(text: String, color: Color, seconds: float, subtitle: String = "") -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("announce"):
		hud.announce(text, color, seconds, subtitle)


func _cmd_stage(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_int() or args[0].to_int() < 1 or args[0].to_int() > campaign.stages.size():
		return "usage: stage <1-%d>" % campaign.stages.size()
	if cover_points == 0:
		# Still loading (no floor or navmesh yet): start there once ready.
		Settings.requested_stage = args[0].to_int() - 1
		return "stage %s once the level is ready" % args[0]
	_restart_at_stage.call_deferred(args[0].to_int() - 1)  # the console doesn't wait for async commands
	return "stage %s" % args[0]


func _restart_at_stage(index: int) -> void:
	_stage_live = false
	for soldier in AI.soldiers.duplicate():
		soldier.queue_free()
	await get_tree().process_frame
	_start_stage(index, true)


func _cmd_visual(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: visual <name prefix>"
	var count := 0
	for child in get_children():
		if child is Node3D and str(child.name).begins_with(args[0]):
			child.visible = not child.visible
			count += 1
	return "toggled %d" % count


func _cmd_sun_distance(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_float():
		return "usage: sun.distance <m> [mode 0 = one pass, 1 = two splits, 2 = four]"
	var sun := $Sun as DirectionalLight3D
	sun.directional_shadow_max_distance = args[0].to_float()
	if args.size() > 1 and args[1].is_valid_int():
		sun.directional_shadow_mode = args[1].to_int() as DirectionalLight3D.ShadowMode
	return "sun shadows reach %s m, mode %d" % [args[0], sun.directional_shadow_mode]


func _cmd_sun_shadows(_args: PackedStringArray) -> String:
	var sun := $Sun as DirectionalLight3D
	sun.shadow_enabled = not sun.shadow_enabled
	return "sun shadows %s" % ("on" if sun.shadow_enabled else "off")


## Arm, housing, glowing lens and a downward spot light on top of a pole;
## the arm reaches towards the middle of the yard.
func _dress_pole(pole: Node3D) -> void:
	var top := pole.global_position + Vector3.UP * float(pole.get("height")) * 0.5
	# Towards the middle of the yard, or over the road for street lights.
	var out: Vector3 = pole.get_meta("arm", -Vector3(top.x, 0, top.z).normalized())
	var B := MeshBaker
	var grey := Color(0.3, 0.31, 0.32)
	var head := MeshBaker.new()
	head.add(B.box(Vector3(0.08, 0.08, 1.6)), B.at(Vector3(0, 0, -0.8)), grey)  # arm
	head.add(B.box(Vector3(0.4, 0.14, 0.7)), B.at(Vector3(0, -0.02, -1.7)), grey)  # housing
	var lens := MeshBaker.new()
	lens.add(B.box(Vector3(0.32, 0.03, 0.6)), B.at(Vector3(0, -0.09, -1.7)), Color.WHITE)
	var mount := Node3D.new()
	add_child(mount)
	mount.global_transform = Transform3D(Basis.looking_at(out), top)
	_mesh(mount, head.commit(_props), false)
	_mesh(mount, lens.commit(_glow_sodium), false)
	_halo(mount, Vector3(0, -0.2, -1.7), 2.6, _halo_sodium)
	var light := SpotLight3D.new()
	light.light_color = lamp_color
	light.light_energy = lamp_energy
	light.spot_range = lamp_range
	light.spot_angle = lamp_angle_degrees
	light.spot_attenuation = 0.8
	# Lamps far from the player fade out and stop costing anything.
	light.distance_fade_enabled = true
	light.distance_fade_begin = lamp_fade_distance
	light.distance_fade_length = 10.0
	light.position = Vector3(0, -0.15, -1.7)
	light.rotation_degrees = Vector3(-90, 0, 0)
	light.add_to_group("street_light")  # Settings grades it (shadows on HIGH)
	mount.add_child(light)
	_street_lights.append(light)
	# A pool of sodium glow on the ground under the lamp, lit or not (a decal
	# costs a texture read, not a light).
	var glow := Decal.new()
	glow.size = Vector3(10.0, 6.0, 10.0)
	glow.texture_emission = _lamp_glow_texture()
	glow.emission_energy = 0.9
	glow.modulate = lamp_color
	glow.albedo_mix = 0.0
	glow.cull_mask = 1
	add_child(glow)
	glow.global_position = Vector3(mount.to_global(light.position).x, 1.0, mount.to_global(light.position).z)


## Paints one MARKINGS entry onto its box's face.
func _paint_marking(marking: Array) -> void:
	var box := get_node_or_null("Navigation/" + str(marking[0])) as Node3D
	if box == null:
		push_warning("marking on missing box %s" % marking[0])
		return
	# CSG boxes know their size; static bodies (sandbags, barriers) carry it as metadata.
	var size: Vector3 = (box as CSGBox3D).size if box is CSGBox3D else box.get_meta("size", Vector3.ZERO)
	var normal: Vector3 = marking[1]
	var basis := Basis.looking_at(-normal)
	var half_depth := absf(normal.dot(size)) * 0.5
	if box.is_in_group("jersey_barrier"):
		# The face slopes in: paint at the profile's width at that height, leaning with it.
		var height := float(marking[3]) - (box.global_position.y - size.y * 0.5)
		half_depth = lerpf(0.16, 0.09, clampf((height - 0.3) / 0.8, 0.0, 1.0))
		basis = basis * Basis(Vector3.RIGHT, -atan2(0.07, 0.8))
	var face := box.global_position + normal * (half_depth + 0.012)
	face += basis.x * float(marking[2])
	face.y = marking[3]
	var label := Label3D.new()
	label.text = marking[4]
	label.font = _stencil_font
	label.font_size = 96
	label.outline_size = 0
	label.pixel_size = float(marking[5]) / 96.0
	label.modulate = marking[6]
	label.shaded = true
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visibility_range_end = 45.0  # each label is a draw call
	label.global_transform = Transform3D(basis, face)
	add_child(label)


## PMV stop like Port Moresby's town terminals: a long curved canopy on
## yellow-painted steel posts with raking struts, next to the parked PMVs.
func _build_bus_stop(at: Vector3, length: float) -> void:
	var B := MeshBaker
	var yellow := Color(0.82, 0.66, 0.12)
	var stop := MeshBaker.new()
	var posts := int(length / 3.4) + 1
	for i in posts:
		var x := -length * 0.5 + i * length / float(posts - 1)
		stop.add(B.cylinder(0.09, 0.1, 3.0, 10), B.at(Vector3(x, 1.5, 0)), yellow)
		for side in [-1.0, 1.0]:
			stop.add(B.box(Vector3(0.08, 0.08, 1.9)), B.at(Vector3(x, 2.75, side * 0.85), Vector3(side * 22.0, 0, 0)), yellow)  # struts
	stop.add(B.box(Vector3(length, 0.12, 0.14)), B.at(Vector3(0, 3.0, 0)), Color(0.15, 0.15, 0.15))  # spine beam
	# The canopy: a shallow arch of sheet (a flattened cylinder along the stop).
	stop.add(B.cylinder(1.0, 1.0, length + 1.2, 24), B.at(Vector3(0, 3.0, 0), Vector3(0, 0, 90), Vector3(1, 0.32, 2.3)), Color(0.42, 0.43, 0.42))
	stop.add(B.box(Vector3(length - 1.0, 0.45, 0.35)), B.at(Vector3(0, 0.22, 1.2)), Color(0.5, 0.48, 0.44))  # kerb seat
	var node := Node3D.new()
	node.position = at
	add_child(node)
	_mesh(node, stop.commit(_props), true)
	_sign_text("PMV STOP", node, Transform3D(Basis.IDENTITY, Vector3(-length * 0.5 + 1.2, 2.45, 0.11)), 0.22, Color(0.1, 0.1, 0.1), true)
	_sign_text("RUT 4 - 17\nGEREHU - TAUN", node, Transform3D(Basis.IDENTITY, Vector3(-length * 0.5 + 1.2, 2.05, 0.11)), 0.1, Color(0.1, 0.1, 0.1), true)


## Roadside buai (betel nut) market: trestle tables of nut bunches, daka
## (mustard sticks) and lime tubs under a blue tarp, bilums hung on a line,
## and a hand-painted price board.
func _build_market(at: Vector3, yaw_degrees: float) -> void:
	var B := MeshBaker
	var rng := RandomNumberGenerator.new()
	rng.seed = 2975
	var timber := Color(0.36, 0.26, 0.16)
	var market := MeshBaker.new()
	for t in 2:
		var tx := -1.3 + t * 2.6
		market.add(B.box(Vector3(2.0, 0.05, 0.8)), B.at(Vector3(tx, 0.78, 0)), Color(0.45, 0.33, 0.2))  # table top
		for lx in [-0.9, 0.9]:
			for lz in [-0.34, 0.34]:
				market.add(B.box(Vector3(0.05, 0.78, 0.05)), B.at(Vector3(tx + lx, 0.39, lz)), timber)
		for i in 7:
			var spot := Vector3(tx + rng.randf_range(-0.85, 0.85), 0.84, rng.randf_range(-0.3, 0.3))
			if rng.randf() < 0.6:
				for n in 6:  # a bunch of green nuts
					market.add(B.sphere(0.03, 6), B.at(spot + Vector3(rng.randf_range(-0.05, 0.05), n * 0.012, rng.randf_range(-0.05, 0.05))),
							Color(0.3, 0.45, 0.14).lerp(Color(0.6, 0.55, 0.15), rng.randf() * 0.4))
			else:
				for n in 5:  # a bundle of daka
					market.add(B.cylinder(0.008, 0.008, 0.16, 4), B.at(spot + Vector3(n * 0.015, 0.0, 0), Vector3(0, 0, 90)), Color(0.35, 0.5, 0.18))
		market.add(B.cylinder(0.05, 0.045, 0.1, 8), B.at(Vector3(tx + 0.7, 0.86, 0.25)), Color(0.85, 0.85, 0.8))  # lime tub
	# Tarp on poles, sagging towards the front.
	for px in [-2.4, 2.4]:
		for pz in [-0.7, 0.9]:
			var pole_height := 2.4 if pz < 0.0 else 2.1
			market.add(B.cylinder(0.035, 0.04, pole_height, 6), B.at(Vector3(px, pole_height * 0.5, pz)), timber)
	market.add(B.box(Vector3(5.2, 0.03, 2.0)), B.at(Vector3(0, 2.25, 0.1), Vector3(-8, 0, 0)), Color(0.12, 0.3, 0.62))
	# Bilums on a line behind the tables: string bags in bright stripes.
	var stripes := [Color(0.8, 0.15, 0.1), Color(0.95, 0.75, 0.1), Color(0.1, 0.1, 0.1), Color(0.15, 0.5, 0.25),
			Color(0.95, 0.95, 0.9), Color(0.2, 0.3, 0.7), Color(0.7, 0.2, 0.5)]
	market.add(B.cylinder(0.006, 0.006, 4.8, 4), B.at(Vector3(0, 1.75, -0.7), Vector3(0, 0, 90)), Color(0.2, 0.18, 0.15))
	for i in 7:
		var bx := -2.0 + i * 0.66
		var height := rng.randf_range(0.38, 0.5)
		var bands := 5
		for b in bands:
			var y := 1.68 - (b + 0.5) * height / bands
			var width := 0.16 * (1.0 - 0.25 * absf(float(b) / bands - 0.6))
			market.add(B.cylinder(width, width, height / bands + 0.002, 10), B.at(Vector3(bx, y, -0.7), Vector3.ZERO, Vector3(1, 1, 0.35)),
					stripes[(i * 3 + b) % stripes.size()])
		market.add(B.box(Vector3(0.012, 0.1, 0.012)), B.at(Vector3(bx, 1.71, -0.7)), stripes[i % stripes.size()])  # strap
	# Price board on its own stake.
	market.add(B.box(Vector3(0.9, 0.55, 0.03)), B.at(Vector3(3.0, 1.15, 0.6), Vector3(0, -15, 3)), Color(0.85, 0.83, 0.75))
	market.add(B.box(Vector3(0.05, 1.0, 0.05)), B.at(Vector3(3.0, 0.5, 0.58)), timber)
	var node := Node3D.new()
	node.position = at
	node.rotation_degrees.y = yaw_degrees
	add_child(node)
	_mesh(node, market.commit(_props), true)
	var board := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(-15), deg_to_rad(3))), Vector3(3.0, 1.15, 0.62))
	_sign_text("BUAI 50t\nDAKA K1\nKAMBANG FRI", node, board, 0.09, Color(0.65, 0.08, 0.06), false)


## Coconut palms beyond the walls: leaning trunks, drooping fronds, nuts.
func _build_palms() -> void:
	var B := MeshBaker
	var rng := RandomNumberGenerator.new()
	rng.seed = 147
	var palms := MeshBaker.new()
	var spots := [Vector3(-38, 0, 36), Vector3(-30, 0, 40), Vector3(-18, 0, 37), Vector3(-6, 0, 42), Vector3(9, 0, 38),
			Vector3(24, 0, 41), Vector3(-40, 0, -30), Vector3(46, 0, 38), Vector3(70, 0, -38), Vector3(88, 0, 39),
			Vector3(103, 0, 22), Vector3(103, 0, -26), Vector3(58, 0, -40)]
	for spot: Vector3 in spots:
		var height := rng.randf_range(9.0, 14.0)
		var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.8, 2.2)
		var segments := 7
		var previous := spot
		for i in segments:
			var t := float(i + 1) / segments
			var point := spot + Vector3.UP * height * t + lean * t * t
			palms.add(B.cylinder(lerpf(0.2, 0.13, t), lerpf(0.22, 0.15, t), previous.distance_to(point) + 0.05, 8),
					Transform3D(_along(point - previous), (previous + point) * 0.5), Color(0.42, 0.37, 0.3))
			previous = point
		for f in 11:  # fronds: three bending pieces each
			var heading := f * TAU / 11.0 + rng.randf() * 0.3
			var out := Vector3(cos(heading), 0, sin(heading))
			var droop := rng.randf_range(-10.0, 25.0)
			var root := previous
			for k in 3:
				var pitch := deg_to_rad(droop + k * 28.0)
				var direction := (out * cos(pitch) + Vector3.DOWN * sin(pitch)).normalized()
				var piece := 1.3 - k * 0.15
				# A flat leaf: long along `direction`, wide sideways, thin up.
				var side := direction.cross(Vector3.UP).normalized()
				var basis := Basis(side, direction.cross(side).normalized(), -direction).orthonormalized()
				palms.add(B.box(Vector3(0.75 - k * 0.18, 0.02, piece)), Transform3D(basis, root + direction * piece * 0.5),
						Color(0.22, 0.36, 0.14).lerp(Color(0.45, 0.42, 0.18), rng.randf() * 0.5))
				root += direction * piece
		for n in 5:
			palms.add(B.sphere(0.12, 6), B.at(previous + Vector3(rng.randf_range(-0.25, 0.25), -0.3, rng.randf_range(-0.25, 0.25))), Color(0.35, 0.4, 0.12))
	var instance := _mesh(self, palms.commit(_props), false)
	instance.name = "Palms"


## A basis whose +Y runs along `axis` (for cylinders between two points).
func _along(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()


## Painted lettering on a sign or board, in `parent`'s space (+Z faces out).
func _sign_text(text: String, parent: Node3D, at: Transform3D, height: float, color: Color, stencil: bool) -> void:
	var label := Label3D.new()
	label.text = text
	if stencil:
		label.font = _stencil_font
	label.font_size = 96
	label.outline_size = 0
	label.pixel_size = height / 96.0
	label.modulate = color
	label.shaded = true
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visibility_range_end = 30.0
	label.transform = at
	parent.add_child(label)


## Sandbag walls built bag by bag: plump sacks laid like bricks, each a
## little different in size, sag and colour, on every "sandbag_wall" body.
func _build_sandbags() -> void:
	var B := MeshBaker
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var burlap := Color(0.42, 0.39, 0.31)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	for wall: Node3D in get_tree().get_nodes_in_group("sandbag_wall"):
		if not is_ancestor_of(wall):
			continue
		# One mesh per wall, so walls out of sight range aren't drawn at all.
		var bags := MeshBaker.new()
		var size: Vector3 = wall.get_meta("size")
		var long_x := size.x >= size.z
		var length := size.x if long_x else size.z
		var depth := size.z if long_x else size.x
		var base := wall.global_position - Vector3.UP * size.y * 0.5
		var bag_length := 0.52
		var rows := int(round(size.y / 0.145))
		var row_height := size.y / rows
		for row in rows:
			var offset := 0.5 * bag_length * (row % 2)
			var count := int(ceil((length + offset) / bag_length))
			for i in count + 1:
				var along := -length * 0.5 - offset + (i + 0.5) * bag_length
				var half := bag_length * 0.5 * rng.randf_range(0.95, 1.06)
				# Clip the end bags to the wall's length so none hang in mid air.
				var lo := maxf(along - half, -length * 0.5)
				var hi := minf(along + half, length * 0.5)
				if hi - lo < 0.12:
					continue
				var center := Vector3((lo + hi) * 0.5, (row + 0.5) * row_height, rng.randf_range(-0.015, 0.015))
				var scale := Vector3((hi - lo) * 0.56, row_height * 0.56, depth * 0.58)
				var turn := Vector3(rng.randf_range(-3, 3), rng.randf_range(-4, 4), rng.randf_range(-3, 3))
				var local := B.at(center, turn, scale)
				if not long_x:
					local = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO) * local
				var tone := rng.randf_range(0.82, 1.12)
				var color := Color(burlap.r * tone, burlap.g * tone, burlap.b * tone * rng.randf_range(0.9, 1.05))
				bags.add(B.sphere(1.0, 7), local, color)
		var instance := _mesh(self, bags.commit(material), true)
		instance.position = base
		instance.visibility_range_end = sandbag_draw_distance
		instance.name = "Sandbags"



## Jersey barriers: the real stepped concrete profile on every "jersey_barrier"
## body (its collision shape is the same profile).
func _build_jersey_barriers() -> void:
	var profile := PackedVector2Array([Vector2(-0.3, 0.0), Vector2(0.3, 0.0), Vector2(0.3, 0.08), Vector2(0.16, 0.3),
			Vector2(0.09, 1.1), Vector2(-0.09, 1.1), Vector2(-0.16, 0.3), Vector2(-0.3, 0.08)])
	var barriers := MeshBaker.new()
	for barrier: Node3D in get_tree().get_nodes_in_group("jersey_barrier"):
		if not is_ancestor_of(barrier):
			continue
		var size: Vector3 = barrier.get_meta("size")
		var long_x := size.x >= size.z
		var base := barrier.global_position - Vector3.UP * size.y * 0.5
		var turn := Basis(Vector3.UP, PI * 0.5) if long_x else Basis.IDENTITY  # the prism runs along Z
		var white := Color(0.93, 0.93, 0.9)
		barriers.add(MeshBaker.prism(profile, size.x if long_x else size.z), Transform3D(turn, base), white)
		# Painted hazard band near the top.
		var band := PackedVector2Array([Vector2(-0.112, 0.75), Vector2(0.112, 0.75), Vector2(0.101, 0.95), Vector2(-0.101, 0.95)])
		barriers.add(MeshBaker.prism(band, (size.x if long_x else size.z) + 0.004), Transform3D(turn, base), Color(0.85, 0.62, 0.1))
	var material := ShaderMaterial.new()
	material.shader = CONCRETE_SHADER
	material.set_shader_parameter("noise_tex", NOISE)
	material.set_shader_parameter("panel_width", 0.0)
	material.set_shader_parameter("base_color", Color(0.6, 0.59, 0.55))
	material.set_shader_parameter("use_vertex_color", true)
	_mesh(self, barriers.commit(material), true).name = "JerseyBarriers"


## Steel frames on every container box: corner posts, top and bottom rails and
## corner castings standing proud of the walls, so stacks have real edges.
## Drawn with the box's own material and instance parameters, so frames take
## each container's paint.
func _build_container_frames() -> void:
	for node in $Navigation.get_children():
		var box := node as CSGBox3D
		if box == null or not node.name.begins_with("Container") and not node.name.begins_with("Wall"):
			continue
		var size := box.size
		var cells: Vector3 = box.get_instance_shader_parameter("cells")
		var cell := size / cells
		var frame := MeshBaker.new()
		var out := 0.025  # how far the frame stands proud
		for ix in int(cells.x):
			for iy in int(cells.y):
				for iz in int(cells.z):
					var lo := -size * 0.5 + Vector3(ix, iy, iz) * cell
					var hi := lo + cell
					_container_cell_frame(frame, lo, hi, out)
		var instance := MeshInstance3D.new()
		instance.mesh = frame.commit(box.material)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # thin: not worth a shadow pass
		instance.name = "ContainerFrame%s" % box.name
		instance.visibility_range_end = frame_draw_distance  # fine detail: only up close
		add_child(instance)
		instance.global_transform = box.global_transform
		for parameter in ["box_size", "cells", "seed"]:
			instance.set_instance_shader_parameter(parameter, box.get_instance_shader_parameter(parameter))


func _container_cell_frame(frame: MeshBaker, lo: Vector3, hi: Vector3, out: float) -> void:
	var B := MeshBaker
	var white := Color.WHITE
	var size := hi - lo
	var mid := (lo + hi) * 0.5
	var post := 0.16
	for x in [lo.x, hi.x]:
		for z in [lo.z, hi.z]:
			var inward := Vector3(-signf(x - mid.x), 0, -signf(z - mid.z))
			var center := Vector3(x, mid.y, z) + inward * (post * 0.5 - out)
			frame.add(B.box(Vector3(post, size.y - 0.02, post)), B.at(center), white)  # corner post
			for y in [lo.y + 0.09, hi.y - 0.09]:
				frame.add(B.box(Vector3(0.18, 0.18, 0.18)), B.at(Vector3(center.x, y, center.z) - inward * 0.012), white)  # casting
	for y in [lo.y + 0.07, hi.y - 0.07]:
		for z in [lo.z, hi.z]:
			frame.add(B.box(Vector3(size.x - 0.2, 0.13, 0.06)), B.at(Vector3(mid.x, y, z - signf(z - mid.z) * (0.03 - out))), white)  # rails along X
		for x in [lo.x, hi.x]:
			frame.add(B.box(Vector3(0.06, 0.13, size.z - 0.2)), B.at(Vector3(x - signf(x - mid.x) * (0.03 - out), y, mid.z)), white)  # rails along Z


## Proud frame boards and a diagonal brace on each side of every crate, drawn
## with the crate's own material.
func _build_crate_frames() -> void:
	var B := MeshBaker
	for node in $Navigation.get_children():
		var box := node as CSGBox3D
		if box == null or not (box.material is ShaderMaterial and (box.material as ShaderMaterial).shader == CRATE_SHADER):
			continue
		var s := box.size
		var h := s * 0.5
		var board := 0.09
		var proud := 0.018
		var frame := MeshBaker.new()
		for axis in 3:
			for side in [-1.0, 1.0]:
				# Face with normal along `axis`; its two in-plane axes.
				var u := (axis + 1) % 3
				var v := (axis + 2) % 3
				var normal := Vector3.ZERO
				normal[axis] = side
				var face := normal * (h[axis] + proud * 0.5)
				for edge in [-1.0, 1.0]:
					var along_u := Vector3.ZERO
					along_u[u] = 1.0
					var along_v := Vector3.ZERO
					along_v[v] = 1.0
					var size_u := Vector3.ONE * proud
					size_u[u] = s[u]
					size_u[v] = board
					frame.add(B.box(size_u), B.at(face + along_v * edge * (h[v] - board * 0.5)), Color.WHITE)
					var size_v := Vector3.ONE * proud
					size_v[v] = s[v] - board * 2.0
					size_v[u] = board
					frame.add(B.box(size_v), B.at(face + along_u * edge * (h[u] - board * 0.5)), Color.WHITE)
				if axis != 1:  # diagonal brace on the side faces
					var length := Vector2(s[u], s[v]).length() - board * 2.0
					var angle := atan2(s[v], s[u])
					var brace_size := Vector3.ONE * proud
					brace_size[u] = length
					brace_size[v] = board
					var rotation := Vector3.ZERO
					rotation[axis] = rad_to_deg(angle) * (1.0 if axis == 2 else -1.0)
					frame.add(B.box(brace_size), B.at(face, rotation), Color.WHITE)
		var instance := MeshInstance3D.new()
		instance.mesh = frame.commit(box.material)
		add_child(instance)
		instance.global_transform = box.global_transform
		for parameter in ["box_size", "seed"]:
			instance.set_instance_shader_parameter(parameter, box.get_instance_shader_parameter(parameter))


## A flat concrete roof slab with a parapet over the warehouse office (visual:
## its walls carry the collision), so its rooms are dark inside at dusk.
func _build_warehouse_roof() -> void:
	var B := MeshBaker
	var roof := MeshBaker.new()
	var lo := Vector3(7.85, 3.0, -24.15)
	var hi := Vector3(20.15, 3.0, -13.85)
	var mid := (lo + hi) * 0.5
	var size := hi - lo
	roof.add(B.box(Vector3(size.x + 0.3, 0.22, size.z + 0.3)), B.at(Vector3(mid.x, 3.11, mid.z)), Color.WHITE)
	roof.add(B.box(Vector3(size.x + 0.3, 0.35, 0.15)), B.at(Vector3(mid.x, 3.39, lo.z - 0.075)), Color.WHITE)
	roof.add(B.box(Vector3(size.x + 0.3, 0.35, 0.15)), B.at(Vector3(mid.x, 3.39, hi.z + 0.075)), Color.WHITE)
	roof.add(B.box(Vector3(0.15, 0.35, size.z + 0.3)), B.at(Vector3(lo.x - 0.075, 3.39, mid.z)), Color.WHITE)
	roof.add(B.box(Vector3(0.15, 0.35, size.z + 0.3)), B.at(Vector3(hi.x + 0.075, 3.39, mid.z)), Color.WHITE)
	roof.add(B.box(Vector3(1.4, 0.8, 1.0)), B.at(Vector3(11.0, 3.62, -20.0)), Color(0.75, 0.75, 0.72))  # air-con unit
	var material: Material = $Navigation/BldgNorth.material
	_mesh(self, roof.commit(material), true).name = "WarehouseRoof"


## Kamfot taxis on every "taxi" body.
func _dress_taxis() -> void:
	for body: Node3D in get_tree().get_nodes_in_group("taxi"):
		if is_ancestor_of(body):
			var taxi := KamfotTaxi.new()
			add_child(taxi)
			taxi.global_transform = body.global_transform
			taxi.build(str(body.get_meta("plate", "T 0000")))


## Shopfronts on every "store" block: a painted signboard over a door and
## barred windows facing the road, a corrugated-iron roof with an awning.
func _dress_stores() -> void:
	var B := MeshBaker
	var stores := MeshBaker.new()
	for node: Node in get_tree().get_nodes_in_group("store"):
		var store := node as CSGBox3D
		if store == null or not is_ancestor_of(store):
			continue
		var size := store.size
		var center := store.global_position
		var facing := Vector3(1, 0, 0) if center.x < 65.0 else Vector3(-1, 0, 0)  # towards the road
		var front := center + facing * (size.x * 0.5)
		var along := Vector3(0, 0, 1)
		var top := center.y + size.y * 0.5
		var iron := Color(0.48, 0.47, 0.45)
		var rust := Color(0.42, 0.22, 0.12)
		# Roof sheet, a little proud all round, and a front awning on posts.
		stores.add(B.box(Vector3(size.x + 0.5, 0.08, size.z + 0.5)), B.at(Vector3(center.x, top + 0.04, center.z)), iron)
		stores.add(B.box(Vector3(1.6, 0.06, size.z)), B.at(front + facing * 0.8 + Vector3(0, 2.75 - center.y, 0), Vector3(0, 0, -8.0 * facing.x)), rust)
		for z in [-size.z * 0.5 + 0.3, size.z * 0.5 - 0.3]:
			stores.add(B.cylinder(0.05, 0.05, 2.7, 6), B.at(front + facing * 1.5 + along * z + Vector3(0, 1.35 - center.y, 0)), iron)
		# Door and barred windows.
		stores.add(B.box(Vector3(0.06, 2.1, 1.2)), B.at(front + facing * 0.02 + Vector3(0, 1.05 - center.y, 0)), Color(0.12, 0.1, 0.08))
		for z in [-size.z * 0.3, size.z * 0.3]:
			stores.add(B.box(Vector3(0.05, 0.9, 1.4)), B.at(front + facing * 0.02 + along * z + Vector3(0, 1.6 - center.y, 0)), Color(0.08, 0.09, 0.1))
			for bar in 5:
				stores.add(B.box(Vector3(0.04, 0.95, 0.03)), B.at(front + facing * 0.05 + along * (z - 0.56 + bar * 0.28) + Vector3(0, 1.6 - center.y, 0)), Color(0.3, 0.3, 0.3))
		# Signboard over the door.
		var board_color: Color = store.get_meta("sign_color", Color.WHITE)
		stores.add(B.box(Vector3(0.08, 0.7, size.z * 0.8)), B.at(front + facing * 0.06 + Vector3(0, 2.95 - center.y, 0)), Color(0.92, 0.9, 0.82))
		var label := Label3D.new()
		label.text = str(store.get_meta("sign", ""))
		label.font = _stencil_font
		label.font_size = 96
		label.outline_size = 0
		label.pixel_size = 0.42 / 96.0
		label.modulate = board_color.darkened(0.3) if board_color.get_luminance() > 0.6 else board_color
		label.shaded = true
		label.double_sided = false
		label.global_transform = Transform3D(Basis.looking_at(-facing), front + facing * 0.11 + Vector3(0, 2.95 - center.y, 0))
		add_child(label)
		if str(store.get_meta("sign", "")).begins_with("MARASIN"):
			# A green cross for the medicine store.
			stores.add(B.box(Vector3(0.08, 0.5, 0.16)), B.at(front + facing * 0.08 + along * (size.z * 0.5 - 0.6) + Vector3(0, 1.9 - center.y, 0)), Color(0.1, 0.6, 0.25))
			stores.add(B.box(Vector3(0.08, 0.16, 0.5)), B.at(front + facing * 0.08 + along * (size.z * 0.5 - 0.6) + Vector3(0, 1.9 - center.y, 0)), Color(0.1, 0.6, 0.25))
	_mesh(self, stores.commit(_props), true).name = "Shopfronts"


## Authored normal/roughness maps, if any are in assets/textures/ (PbrLibrary).
func _apply_pbr_textures() -> void:
	var slots := {"Floor": "asphalt", "TownRoad": "asphalt", "WallNorth": "container", "BldgNorth": "concrete",
			"TownDirtW": "dirt", "TradeStoa": "concrete"}
	for node_name: String in slots:
		var box := get_node_or_null("Navigation/" + node_name) as CSGBox3D
		if box != null:
			PbrLibrary.apply_shader(box.material as ShaderMaterial, slots[node_name])


## Ship-to-shore gantry crane looming over the north wall, boom out over the
## yard, red aviation lights on top.
func _build_crane(base: Vector3) -> void:
	var B := MeshBaker
	var steel := Color(0.22, 0.27, 0.33)
	var crane := MeshBaker.new()
	for x in [-9.0, 9.0]:
		for z in [-7.0, 7.0]:
			crane.add(B.box(Vector3(1.2, 34, 1.2)), B.at(Vector3(x, 17, z)), steel)  # legs
		crane.add(B.box(Vector3(1.0, 1.4, 16)), B.at(Vector3(x, 1.2, 0)), steel)  # sill beam
		crane.add(B.box(Vector3(0.5, 0.5, 19)), B.at(Vector3(x, 18, 0), Vector3(47, 0, 0)), steel)  # bracing
		crane.add(B.box(Vector3(1.6, 2.4, 90)), B.at(Vector3(x * 0.5, 35, 20)), steel)  # boom girders
	for z in [-7.0, 7.0]:
		crane.add(B.box(Vector3(19.2, 2.0, 1.2)), B.at(Vector3(0, 33.5, z)), steel)  # portal beams
		crane.add(B.box(Vector3(19.2, 1.2, 1.0)), B.at(Vector3(0, 12, z)), steel)
	crane.add(B.box(Vector3(10, 1.0, 1.0)), B.at(Vector3(0, 35, 64)), steel)  # boom tip
	crane.add(B.box(Vector3(2.0, 14, 2.0)), B.at(Vector3(0, 43, -2)), steel)  # A-frame
	crane.add(B.box(Vector3(0.4, 0.4, 60)), B.at(Vector3(0, 42, 26), Vector3(-12, 0, 0)), steel)  # boom stay
	crane.add(B.box(Vector3(3.5, 3, 4)), B.at(Vector3(0, 31.5, 30)), Color(0.55, 0.52, 0.45))  # trolley cab
	var lights := MeshBaker.new()
	for at in [Vector3(0, 50.2, -2), Vector3(-9, 34.6, -7), Vector3(9, 34.6, 7), Vector3(0, 36, 64)]:
		lights.add(B.sphere(0.35, 8), B.at(at), Color.WHITE)
	var node := Node3D.new()
	node.position = base
	add_child(node)
	_mesh(node, crane.commit(_props), false)
	_mesh(node, lights.commit(_glow_red), false)
	for at in [Vector3(0, 50.2, -2), Vector3(-9, 34.6, -7), Vector3(9, 34.6, 7), Vector3(0, 36, 64)]:
		_halo(node, at, 5.0, _halo_red)


## Container stacks beyond the perimeter, two to five high, for the skyline.
func _build_stacks() -> void:
	var material: Material = $Navigation/WallNorth.material
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rows := [
		[Vector3(-46, 0, 0), Vector3(0, 0, 1)], [Vector3(-56, 0, 0), Vector3(0, 0, 1)],
		[Vector3(108, 0, 0), Vector3(0, 0, 1)], [Vector3(117, 0, 0), Vector3(0, 0, 1)],  # beyond the town
		[Vector3(0, 0, -44), Vector3(1, 0, 0)], [Vector3(0, 0, 44), Vector3(1, 0, 0)],
		[Vector3(66, 0, -44), Vector3(1, 0, 0)], [Vector3(66, 0, 44), Vector3(1, 0, 0)],
	]
	for row in rows:
		var origin: Vector3 = row[0]
		var along: Vector3 = row[1]
		for i in range(-4, 5):
			var tiers := rng.randi_range(2, 5)
			var size := Vector3(6.1, 2.6 * tiers, 2.44) if along.x > 0.5 else Vector3(2.44, 2.6 * tiers, 6.1)
			var box := BoxMesh.new()
			box.size = size
			var instance := MeshInstance3D.new()
			instance.mesh = box
			instance.material_override = material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.position = origin + along * (i * 6.5) + Vector3(0, size.y * 0.5, 0)
			instance.name = "DistantStack"
			add_child(instance, true)
			instance.set_instance_shader_parameter("box_size", size)
			instance.set_instance_shader_parameter("cells", Vector3(1, tiers, 1))
			instance.set_instance_shader_parameter("seed", rng.randf() * 50.0)


## A moored ship's hull and bridge to the west, lit windows on the bridge.
func _build_ship(at: Vector3) -> void:
	var B := MeshBaker
	var ship := MeshBaker.new()
	ship.add(B.box(Vector3(26, 16, 170)), B.at(Vector3(0, 6, 0)), Color(0.08, 0.1, 0.12))  # hull
	ship.add(B.box(Vector3(26.2, 2.5, 170.2)), B.at(Vector3(0, -0.5, 0)), Color(0.3, 0.07, 0.05))  # boot top
	ship.add(B.box(Vector3(20, 18, 14)), B.at(Vector3(0, 23, 60)), Color(0.72, 0.7, 0.64))  # bridge
	ship.add(B.box(Vector3(28, 1.2, 6)), B.at(Vector3(0, 32, 58)), Color(0.72, 0.7, 0.64))  # bridge wings
	ship.add(B.box(Vector3(3, 12, 3)), B.at(Vector3(0, 38, 64)), Color(0.25, 0.22, 0.2))  # funnel
	for i in range(-5, 6):
		var tiers := 2 + absi(i * 7) % 3
		ship.add(B.box(Vector3(22, 2.6 * tiers, 12)), B.at(Vector3(0, 14 + 1.3 * tiers, i * 13 - 20)),
				Color(0.2 + 0.1 * float(absi(i) % 3), 0.16, 0.14))  # deck cargo
	var windows := MeshBaker.new()
	for floor_y in [17.0, 21.0, 25.0, 29.0]:
		for z in range(54, 67, 2):
			if (int(floor_y) + z) % 3 != 0:
				windows.add(B.box(Vector3(0.2, 1.0, 1.2)), B.at(Vector3(10.05, floor_y, z)), Color.WHITE)
	var lights := MeshBaker.new()
	lights.add(B.sphere(0.4, 8), B.at(Vector3(0, 44.5, 64)), Color.WHITE)
	var node := Node3D.new()
	node.position = at
	add_child(node)
	_mesh(node, ship.commit(_props), false)
	_mesh(node, windows.commit(_glow_window), false)
	_mesh(node, lights.commit(_glow_red), false)
	_halo(node, Vector3(0, 44.5, 64), 6.0, _halo_red)


func _mesh(parent: Node3D, mesh: Mesh, shadows: bool) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _halo(parent: Node3D, at: Vector3, size: float, material: ShaderMaterial) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var instance := _mesh(parent, quad, false)
	instance.material_override = material
	instance.position = at


func _halo_material(color: Color, intensity: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HALO_SHADER
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("intensity", intensity)
	return material


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
