extends "res://levels/campaign_level.gd"
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

@export var warehouse_light_color := Color(0.78, 0.86, 1.0)
@export var warehouse_light_energy := 1.2
## Container frames are fine detail: drawn only this close (m).
@export var frame_draw_distance := 50.0


## The port's own dressing: markings, the PMV stop and buai markets, palms,
## container frames, the warehouse, crane, distant stacks and the ship.
func _dress_level() -> void:
	for marking in MARKINGS:
		_paint_marking(marking)
	_build_bus_stop(Vector3(-22, 0, 23.6), 10.0)
	_build_market(Vector3(-28.6, 0, 19), 90.0)
	_build_palms([Vector3(-38, 0, 36), Vector3(-30, 0, 40), Vector3(-18, 0, 37), Vector3(-6, 0, 42), Vector3(9, 0, 38),
			Vector3(24, 0, 41), Vector3(-40, 0, -30), Vector3(46, 0, 38), Vector3(70, 0, -38), Vector3(88, 0, 39),
			Vector3(103, 0, 22), Vector3(103, 0, -26), Vector3(58, 0, -40)])
	_build_market(Vector3(54, 0, 27.5), 180.0)
	_build_container_frames()
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
