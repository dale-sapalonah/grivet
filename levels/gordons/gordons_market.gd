extends "res://levels/campaign_level.gd"
## Gordons Market, Port Moresby, after hours: the two-storey market hall
## (concrete below, an open upper floor under a steel roof behind white
## screens cut in PNG-style motifs), the plaza with its planters, monument
## stone and mural, the PMV interchange, the car park, the wholesale sheds and
## Geauta Drive. The market is closed for the night: stalls under tarps,
## produce in sacks, no vendors. Colliders come from tools/gen_gordons.py; this
## adds only what is seen. The screen motif and the mural are original.

## The hall, as tools/gen_gordons.py lays it out.
const DECK := 4.8
const HX0 := -18.0
const HX1 := 38.0
const HZ0 := -30.0
const HZ1 := 22.0
const ROOF_EAVES := 10.4
const ROOF_RIDGE := 12.6
## The raised middle bay (its gables face north and south, like the real one).
const BAY_X0 := 2.0
const BAY_X1 := 18.0
const BAY_RIDGE := 16.0
## Tubes hang just under the deck slab.
const SLAB_UNDERSIDE := 0.45

## Posters' size against an A2-ish sheet (they read too small at 1).
@export var poster_scale := 1.45
## Cool white tubes in the hall (the sodium lamps are outside).
@export var hall_light_color := Color(0.86, 0.92, 1.0)
@export var hall_light_energy := 2.2
@export var hall_light_range := 9.0
## Sack piles: rounded sacks this close (m), simple blocks out to sack_draw_distance.
@export var sack_detail_distance := 25.0
@export var sack_draw_distance := 45.0
## Stalls and their tarps are fine detail: drawn only this close (m).
@export var stall_draw_distance := 60.0

var _screen: StandardMaterial3D
var _produce: MarketProduce
var _tube: StandardMaterial3D


func _dress_level() -> void:
	_tube = _emissive(hall_light_color, 3.0)
	_screen = _screen_material(2.4)
	_build_occluders()
	_build_roof()
	_build_screens()
	_build_hall_details()
	_build_hall_lights()
	_build_stairs()
	_build_stalls()
	_build_sacks()
	_build_trucks()
	_build_sheds()
	_build_plaza()
	_build_bus_stop(Vector3(-20, 0, 54.2), 12.0)
	_build_bus_stop(Vector3(14, 0, 54.2), 12.0)
	_build_market(Vector3(-36, 0, 50), 90.0)
	_build_market(Vector3(36, 0, 44.5), 180.0)
	_build_car_park_lines()
	_build_posters()
	_build_hills()
	_build_palms([Vector3(-20, 0, 45), Vector3(44, 0, 45), Vector3(44, 0, 20), Vector3(42, 0, -34), Vector3(-24, 0, 46),
			Vector3(-68, 0, 0), Vector3(-68, 0, 44), Vector3(66, 0, -30), Vector3(66, 0, 10), Vector3(66, 0, 52),
			Vector3(-20, 0, -48), Vector3(40, 0, -48)])
	_sign_text("GEAUTA DRAIV", self, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(64.2, 2.6, -8)), 0.32, Color(0.95, 0.95, 0.9), true)


# --- The hall -------------------------------------------------------------------------

## The deck slab hides each floor from the other: occluders let the renderer
## skip what's on the other side (the stalls and produce are most of the
## triangles). Also the admin block and the storerooms.
func _build_occluders() -> void:
	for node in $Navigation.get_children():
		var box := node as CSGBox3D
		if box == null:
			continue
		var name_text := str(box.name)
		if not (name_text.begins_with("Deck") or name_text.begins_with("Kiosk") or name_text.begins_with("Admin")):
			continue
		var shape := BoxOccluder3D.new()
		shape.size = box.size
		var occluder := OccluderInstance3D.new()
		occluder.occluder = shape
		add_child(occluder)
		occluder.global_transform = box.global_transform


## Low-pitched main roof (ridge east-west), the raised middle bay, steel
## trusses over the upper floor, gutters, and the deck's edge beams.
func _build_roof() -> void:
	var B := MeshBaker
	var steel := Color(0.78, 0.8, 0.8)
	var sheet := Color(0.55, 0.58, 0.56)
	var roof := MeshBaker.new()
	var mid_z := (HZ0 + HZ1) * 0.5
	var half := (HZ1 - HZ0) * 0.5 + 1.2  # eaves overhang
	var rise := ROOF_RIDGE - ROOF_EAVES
	var slope := atan2(rise, half)
	var length := Vector2(half, rise).length()
	for side: float in [-1.0, 1.0]:
		for part in [[HX0 - 1.2, BAY_X0], [BAY_X1, HX1 + 1.2]]:
			var width: float = part[1] - part[0]
			var center := Vector3((part[0] + part[1]) * 0.5, ROOF_EAVES + rise * 0.5, mid_z + side * half * 0.5)
			roof.add(B.box(Vector3(width, 0.08, length)), B.at(center, Vector3(rad_to_deg(slope) * side, 0, 0)), sheet)
	# The raised bay: its own gable roof, ridge north-south.
	var bay_half := (BAY_X1 - BAY_X0) * 0.5 + 0.8
	var bay_rise := BAY_RIDGE - ROOF_EAVES - 1.2
	var bay_slope := atan2(bay_rise, bay_half)
	var bay_mid := (BAY_X0 + BAY_X1) * 0.5
	for side: float in [-1.0, 1.0]:
		roof.add(B.box(Vector3(Vector2(bay_half, bay_rise).length(), 0.08, HZ1 - HZ0 + 3.0)),
				B.at(Vector3(bay_mid + side * bay_half * 0.5, ROOF_EAVES + 1.2 + bay_rise * 0.5, mid_z), Vector3(0, 0, -rad_to_deg(bay_slope) * side)), sheet)
	# Trusses across the hall every 8 m: bottom chord, rafters, and verticals.
	for i in 8:
		var x := HX0 + 8.0 * i
		var top := BAY_RIDGE - 0.4 if x >= BAY_X0 and x <= BAY_X1 else ROOF_RIDGE - 0.2
		roof.add(B.box(Vector3(0.2, 0.3, HZ1 - HZ0)), B.at(Vector3(x, ROOF_EAVES - 0.2, mid_z)), steel)
		for side: float in [-1.0, 1.0]:
			var from := Vector3(x, ROOF_EAVES - 0.1, mid_z + side * (HZ1 - HZ0) * 0.5)
			var to := Vector3(x, top, mid_z)
			roof.add(B.box(Vector3(0.18, 0.28, from.distance_to(to))), Transform3D(_look_along(to - from), (from + to) * 0.5), steel)
			for k in range(1, 5):
				var z := mid_z + side * (HZ1 - HZ0) * 0.5 * (1.0 - k / 5.0)
				var h := lerpf(ROOF_EAVES - 0.1, top, k / 5.0) - ROOF_EAVES + 0.1
				roof.add(B.box(Vector3(0.1, h, 0.1)), B.at(Vector3(x, ROOF_EAVES - 0.1 + h * 0.5, z)), steel)
	# Purlins along the hall and gutters at the eaves.
	for k in 5:
		var z := HZ0 + (HZ1 - HZ0) * (k + 0.5) / 5.0
		roof.add(B.box(Vector3(HX1 - HX0, 0.12, 0.12)), B.at(Vector3((HX0 + HX1) * 0.5, ROOF_EAVES + 0.3 + rise * (1.0 - absf(z - mid_z) / half), z)), steel)
	for z in [HZ0 - 1.2, HZ1 + 1.2]:
		roof.add(B.box(Vector3(HX1 - HX0 + 2.4, 0.22, 0.22)), B.at(Vector3((HX0 + HX1) * 0.5, ROOF_EAVES - 0.05, z)), Color(0.85, 0.86, 0.85))
	# The deck's edge beam all round, painted grey like the photos' fascia.
	for z in [HZ0, HZ1]:
		roof.add(B.box(Vector3(HX1 - HX0 + 0.4, 0.7, 0.3)), B.at(Vector3((HX0 + HX1) * 0.5, DECK - 0.35, z)), Color(0.62, 0.63, 0.62))
	for x in [HX0, HX1]:
		roof.add(B.box(Vector3(0.3, 0.7, HZ1 - HZ0 + 0.4)), B.at(Vector3(x, DECK - 0.35, (HZ0 + HZ1) * 0.5)), Color(0.62, 0.63, 0.62))
	var material := _props.duplicate() as StandardMaterial3D
	material.metallic = 0.55
	material.roughness = 0.45
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # roof sheets are seen from below
	var instance := _mesh(self, roof.commit(material), true)
	instance.name = "HallRoof"


## The white screens: a band round the upper floor from rail height to the
## eaves, and the raised bay's tall gables, cut in an original PNG-style
## motif (nested diamonds, chevrons and crosses, like tapa and carved panels).
func _build_screens() -> void:
	var screens := MeshBaker.new()
	var B := MeshBaker
	var low := DECK + 1.5
	var high := ROOF_EAVES - 0.2
	var height := high - low
	for z in [HZ0 - 0.3, HZ1 + 0.3]:
		for part in [[HX0, BAY_X0], [BAY_X1, HX1]]:
			screens.add(B.box(Vector3(part[1] - part[0], height, 0.04)), B.at(Vector3((part[0] + part[1]) * 0.5, low + height * 0.5, z)), Color.WHITE)
		# The bay's gable: a tall screen from the deck up to its ridge.
		var bay_height := BAY_RIDGE - DECK - 1.6
		screens.add(B.box(Vector3(BAY_X1 - BAY_X0, bay_height, 0.04)), B.at(Vector3((BAY_X0 + BAY_X1) * 0.5, DECK + 1.5 + bay_height * 0.5, z)), Color.WHITE)
	for x in [HX0 - 0.3, HX1 + 0.3]:
		screens.add(B.box(Vector3(0.04, height, HZ1 - HZ0)), B.at(Vector3(x, low + height * 0.5, (HZ0 + HZ1) * 0.5)), Color.WHITE)
	var instance := _mesh(self, screens.commit(_screen), true)
	instance.name = "Screens"
	# Gable tips: triangles above the bay screens, plain white cladding.
	var tips := MeshBaker.new()
	for z in [HZ0 - 0.3, HZ1 + 0.3]:
		var profile := PackedVector2Array([Vector2(BAY_X0 - 0.8, 0.0), Vector2(BAY_X1 + 0.8, 0.0), Vector2((BAY_X0 + BAY_X1) * 0.5, 1.6)])
		tips.add(MeshBaker.prism(profile, 0.1), Transform3D(Basis.IDENTITY, Vector3(0, BAY_RIDGE - 1.6, z)), Color(0.93, 0.93, 0.9))
	_mesh(self, tips.commit(_props), false).name = "GableTips"


## A tile of the screen motif: white panel, holes where the light comes
## through. Built once at load into a small texture (cheaper than shader maths
## on this GPU); the material maps it in world space so every panel lines up.
func _screen_material(tile_metres: float) -> StandardMaterial3D:
	var size := 128
	var image := Image.create_empty(size, size, true, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (x + 0.5) / size
			var v := (y + 0.5) / size
			image.set_pixel(x, y, Color(1, 1, 1, 0.0 if _screen_hole(u, v) else 1.0))
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.albedo_color = Color(0.95, 0.95, 0.92)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / tile_metres
	material.roughness = 0.6
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material


## The motif in one tile (u, v in 0..1): a diamond ring round a small diamond,
## chevrons in the corners and a cross bar between tiles.
func _screen_hole(u: float, v: float) -> bool:
	var du := absf(u - 0.5)
	var dv := absf(v - 0.5)
	var diamond := du + dv
	if diamond < 0.07:
		return true  # the eye
	if diamond > 0.16 and diamond < 0.25:
		return true  # the ring
	if diamond > 0.33 and diamond < 0.4 and (du < 0.08 or dv < 0.08):
		return false  # the ring's ties out to the tile edge
	if diamond > 0.33 and diamond < 0.4:
		return true  # the outer ring's arcs
	# Chevrons stacked in each corner.
	var corner := minf(du, dv)
	if diamond > 0.52 and corner > 0.06 and fmod(diamond * 12.0, 1.0) < 0.45:
		return true
	return false


## Columns' feet, the north entrance's sign, the mezzanine fascia sign and
## the ground-floor fence's rails.
func _build_hall_details() -> void:
	var B := MeshBaker
	var details := MeshBaker.new()
	var rail := Color(0.82, 0.84, 0.84)
	# Galvanised fence and upper railings: rails and posts over the collider walls.
	for node in $Navigation.get_children():
		var box := node as CSGBox3D
		if box == null:
			continue
		if not _is_railing(str(node.name)):
			continue
		box.visible = false  # the rails are the look; the box stays as the collider
		var size := box.size
		var long_x := size.x >= size.z
		var length := size.x if long_x else size.z
		var base := box.global_position - Vector3.UP * size.y * 0.5
		var along := Vector3.RIGHT if long_x else Vector3.BACK
		for y in [size.y - 0.04, size.y * 0.55, 0.12]:
			details.add(B.box(Vector3(length, 0.05, 0.05) if long_x else Vector3(0.05, 0.05, length)), B.at(base + Vector3.UP * y), rail)
		var posts := int(length / 1.5) + 1
		for i in posts:
			details.add(B.box(Vector3(0.06, size.y, 0.06)), B.at(base + along * (-length * 0.5 + i * length / maxf(posts - 1, 1)) + Vector3.UP * size.y * 0.5), rail)
		if not str(node.name).begins_with("Fence"):
			for i in int(length / 0.3):  # balusters on the upper floor's railings
				details.add(B.box(Vector3(0.02, size.y * 0.42, 0.02)), B.at(base + along * (-length * 0.5 + (i + 0.5) * 0.3) + Vector3.UP * size.y * 0.34), rail)
	var instance := _mesh(self, details.commit(_props), false)
	instance.name = "Railings"
	instance.visibility_range_end = stall_draw_distance
	# Signs: GORDONS MAKET over the south front, toilets and office on the admin block.
	var board := MeshBaker.new()
	board.add(B.box(Vector3(9.0, 0.9, 0.06)), B.at(Vector3(10, DECK - 0.35, HZ1 + 0.2)), Color(0.12, 0.38, 0.22))
	_mesh(self, board.commit(_props), false).name = "SignBoard"
	_sign_text("GORDONS MAKET", self, Transform3D(Basis.IDENTITY, Vector3(10, DECK - 0.35, HZ1 + 0.24)), 0.55, Color(0.97, 0.96, 0.9), true)
	_sign_text("OFIS", self, Transform3D(Basis.IDENTITY, Vector3(-9, 2.6, -21.3)), 0.25, Color(0.2, 0.2, 0.2), true)
	_sign_text("TOILET", self, Transform3D(Basis.IDENTITY, Vector3(-15, 2.6, -21.3)), 0.25, Color(0.2, 0.2, 0.2), true)


## The collider walls that are railings or fences (dressed as rails and posts).
func _is_railing(node_name: String) -> bool:
	if node_name.begins_with("Fence") or node_name.begins_with("UpRail") or node_name.begins_with("Well"):
		return true
	return node_name.contains("Rail") and (node_name.begins_with("Bridge") or node_name.begins_with("Tower") 			or node_name.begins_with("Landing") or node_name.begins_with("Ramp"))


## Cool white tubes under the deck (ground floor) and under the trusses
## (upper floor); a few real lights in the hall join the lamp light LOD.
func _build_hall_lights() -> void:
	var B := MeshBaker
	var tubes := MeshBaker.new()
	for i in 7:
		var x := HX0 + 4.0 + 8.0 * i
		for j in 6:
			var z := HZ0 + (HZ1 - HZ0) / 6.0 * (j + 0.5)
			tubes.add(B.box(Vector3(0.12, 0.05, 1.5)), B.at(Vector3(x, DECK - SLAB_UNDERSIDE, z)), Color.WHITE)
			tubes.add(B.box(Vector3(0.12, 0.05, 1.5)), B.at(Vector3(x, ROOF_EAVES - 0.45, z)), Color.WHITE)
	_mesh(self, tubes.commit(_tube), false).name = "HallTubes"
	for at in [Vector3(-6, DECK - 0.5, -10), Vector3(14, DECK - 0.5, -10), Vector3(30, DECK - 0.5, 4), Vector3(-6, DECK - 0.5, 12),
			Vector3(14, DECK - 0.5, 8), Vector3(-2, ROOF_EAVES - 0.6, -14), Vector3(22, ROOF_EAVES - 0.6, -14),
			Vector3(6, ROOF_EAVES - 0.6, 10), Vector3(30, ROOF_EAVES - 0.6, 10)]:
		var light := SpotLight3D.new()
		light.light_color = hall_light_color
		light.light_energy = hall_light_energy
		light.spot_range = hall_light_range
		light.spot_angle = 70.0
		light.spot_attenuation = 0.9
		light.distance_fade_enabled = true
		light.distance_fade_begin = lamp_fade_distance
		light.distance_fade_length = 10.0
		light.position = at
		light.rotation_degrees = Vector3(-90, 0, 0)
		light.add_to_group("street_light")
		add_child(light)
		_street_lights.append(light)


## Treads on the stair slopes and handrails up the stairs and the south ramp.
func _build_stairs() -> void:
	var B := MeshBaker
	var stairs := MeshBaker.new()
	var tread := Color(0.62, 0.61, 0.58)
	var rail := Color(0.82, 0.84, 0.84)
	for stair_name in ["StairW", "StairE", "TowerStair"]:
		var stair := get_node_or_null("Navigation/" + stair_name) as CSGBox3D
		if stair == null:
			continue
		stair.visible = false  # steps replace the slab's look; the slope stays the collider
		var size := stair.size
		var basis := stair.global_basis
		var top := stair.global_position + basis.y * size.y * 0.5
		var end_a := top - basis.z * size.z * 0.5
		var end_b := top + basis.z * size.z * 0.5
		var low := end_a if end_a.y < end_b.y else end_b
		var high := end_b if end_a.y < end_b.y else end_a
		var steps := maxi(int((high.y - low.y) / 0.18), 1)
		var flat := Vector3(high.x - low.x, 0.0, high.z - low.z)
		var rise := (high.y - low.y) / steps
		for i in steps:
			var at := low.lerp(high, (i + 0.5) / steps)
			stairs.add(B.box(Vector3(size.x, rise + 0.03, flat.length() / steps + 0.03)), Transform3D(Basis.looking_at(flat.normalized()), at), tread)
		for side: float in [-0.5, 0.5]:
			var a := low + basis.x * size.x * side + Vector3.UP * 0.95
			var b := high + basis.x * size.x * side + Vector3.UP * 0.95
			stairs.add(B.box(Vector3(0.05, 0.05, a.distance_to(b))), Transform3D(_look_along(b - a), (a + b) * 0.5), rail)
	var ramp := get_node_or_null("Navigation/RampSouth") as CSGBox3D
	if ramp != null:
		var size := ramp.size
		var basis := ramp.global_basis
		var top := ramp.global_position + basis.y * size.y * 0.5
		for side: float in [-0.5, 0.5]:
			var a := top - basis.x * size.x * 0.5 + basis.z * size.z * side + Vector3.UP * 1.0
			var b := top + basis.x * size.x * 0.5 + basis.z * size.z * side + Vector3.UP * 1.0
			stairs.add(B.box(Vector3(0.05, 0.05, a.distance_to(b))), Transform3D(_look_along(b - a), (a + b) * 0.5), rail)
			for k in 14:
				var p := a.lerp(b, (k + 0.5) / 14.0)
				stairs.add(B.box(Vector3(0.05, 1.0, 0.05)), B.at(p - Vector3.UP * 0.5), rail)
	_mesh(self, stairs.commit(_props), true).name = "Stairs"


# --- Stalls, sacks, trucks, sheds ------------------------------------------------------

## Every "stall_row" body: three white-framed tables under black plastic,
## baskets below. What's on them is MarketProduce (it bursts when shot).
func _build_stalls() -> void:
	var B := MeshBaker
	var rng := RandomNumberGenerator.new()
	rng.seed = 1958
	var frames := {false: MeshBaker.new(), true: MeshBaker.new()}  # per floor
	var frame := Color(0.88, 0.89, 0.88)
	var plastic := Color(0.08, 0.09, 0.1)
	for node: Node in get_tree().get_nodes_in_group("stall_row"):
		var row := node as Node3D
		if row == null or not is_ancestor_of(row):
			continue
		var baker: MeshBaker = frames[row.global_position.y > DECK]
		var size: Vector3 = row.get_meta("size")
		var base := row.global_position - Vector3.UP * size.y * 0.5
		for t in 3:
			var cx := -size.x * 0.5 + 1.2 + t * 2.4
			var top_y := 0.82
			baker.add(B.box(Vector3(2.3, 0.04, size.z)), B.at(base + Vector3(cx, top_y, 0)), frame)
			baker.add(B.box(Vector3(2.34, 0.02, size.z + 0.06)), B.at(base + Vector3(cx, top_y + 0.03, 0)), plastic)
			baker.add(B.box(Vector3(2.36, 0.25, 0.01)), B.at(base + Vector3(cx, top_y - 0.1, size.z * 0.5 + 0.03)), plastic)  # sheet hanging over
			for lx in [-1.08, 1.08]:
				for lz in [-size.z * 0.42, size.z * 0.42]:
					baker.add(B.box(Vector3(0.04, top_y, 0.04)), B.at(base + Vector3(cx + lx, top_y * 0.5, lz)), frame)
			if rng.randf() < 0.35:
				baker.add(B.cylinder(0.22, 0.17, 0.3, 7), B.at(base + Vector3(cx + rng.randf_range(-0.7, 0.7), 0.15, rng.randf_range(-0.2, 0.2))),
						Color(0.62, 0.48, 0.28))  # a basket
	var material := _props.duplicate() as StandardMaterial3D
	material.metallic = 0.1
	material.roughness = 0.75
	for upstairs in [false, true]:
		var baker: MeshBaker = frames[upstairs]
		if baker.is_empty():
			continue
		var instance := _mesh(self, baker.commit(material), true)  # the tables' stripes of shadow
		instance.name = "Stalls%s" % ("Upper" if upstairs else "Ground")
		instance.visibility_range_end = stall_draw_distance
	_produce = MarketProduce.new()
	_produce.name = "Produce"
	add_child(_produce)
	_produce.build(self)


## A new stage: the produce is back on the tables.
func _start_stage(index: int, move_player: bool) -> void:
	super(index, move_player)
	if _produce != null:
		_produce.reset()


## Every "sacks" body: woven poly sacks (white, a few blue-striped) and brown
## copra sacks, stacked like bricks, the top layer plumper. Up close, soft
## rounded sacks (SackMesh, instanced per pile); past sack_detail_distance a
## cheap pile of blocks, which reads the same from there.
func _build_sacks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var colors := [Color(0.88, 0.87, 0.82), Color(0.82, 0.8, 0.72), Color(0.5, 0.38, 0.24), Color(0.62, 0.7, 0.82)]
	var packed_mesh := SackMesh.lying(0.12)  # packed tight: squarer, so a stack end reads as sacks, not tyres
	var plump_mesh := SackMesh.lying(0.75)
	var material := _sack_material()
	for node: Node in get_tree().get_nodes_in_group("sacks"):
		var stack := node as Node3D
		if stack == null or not is_ancestor_of(stack):
			continue
		var size: Vector3 = stack.get_meta("size")
		var base := stack.global_position - Vector3.UP * size.y * 0.5
		var rows := int(round(size.y / 0.28))
		var row_height := size.y / rows
		var packed: Array = []  # [Transform3D local to the pile, Color]
		var plump: Array = []
		var blocks := MeshBaker.new()
		for row in rows:
			var along := 0.0
			var offset := 0.3 * (row % 2)
			while along < size.z - 0.2:
				for across in range(int(size.x / 0.62)):
					var center := Vector3(-size.x * 0.5 + 0.31 + across * 0.62, (row + 0.5) * row_height, -size.z * 0.5 + along + 0.45 - offset * 0.5)
					if center.z > size.z * 0.5 - 0.2:
						continue
					var tilt := Basis.from_euler(Vector3(deg_to_rad(rng.randf_range(-3, 3)), deg_to_rad(rng.randf_range(-7, 7)), deg_to_rad(rng.randf_range(-3, 3))))
					# Filled to fit: a little proud of the row so the layers press together.
					var fit := Vector3(rng.randf_range(0.95, 1.05), row_height * 1.04 / 0.32, rng.randf_range(0.88, 0.96))
					var color: Color = colors[rng.randi() % colors.size()]
					(plump if row == rows - 1 else packed).append([Transform3D(tilt.scaled(fit), center), color])
					blocks.add(MeshBaker.box(Vector3(0.6, row_height * 0.95, 0.86)), Transform3D(tilt, center), color)
				along += 0.9
		var pile := Node3D.new()
		pile.name = "SackPile"
		add_child(pile)
		pile.global_position = base
		for layer in [[packed, packed_mesh], [plump, plump_mesh]]:
			var entries: Array = layer[0]
			if entries.is_empty():
				continue
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = true
			multimesh.mesh = layer[1]
			multimesh.instance_count = entries.size()
			for i in entries.size():
				multimesh.set_instance_transform(i, entries[i][0])
				multimesh.set_instance_color(i, entries[i][1])
			var near := MultiMeshInstance3D.new()
			near.multimesh = multimesh
			near.material_override = material
			near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # thousands of sacks: no shadow pass
			near.visibility_range_end = sack_detail_distance
			pile.add_child(near)
		var far := MeshInstance3D.new()
		far.mesh = blocks.commit(_props)
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far.visibility_range_begin = sack_detail_distance
		far.visibility_range_end = sack_draw_distance
		pile.add_child(far)


## Woven sacking: matt, coloured per instance.
func _sack_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	return material


## A small flatbed truck on every "truck" body: cab, bed with a load of sacks.
func _build_trucks() -> void:
	var B := MeshBaker
	for node: Node in get_tree().get_nodes_in_group("truck"):
		var body := node as Node3D
		if body == null or not is_ancestor_of(body):
			continue
		var cab_color: Color = body.get_meta("cab_color", Color.WHITE)
		var truck := MeshBaker.new()
		truck.add(B.box(Vector3(2.0, 1.9, 1.9)), B.at(Vector3(0, 1.55, -2.55)), cab_color)  # cab
		truck.add(B.box(Vector3(1.9, 0.7, 0.05)), B.at(Vector3(0, 2.0, -3.51), Vector3(-8, 0, 0)), Color(0.08, 0.1, 0.12))  # windscreen
		truck.add(B.box(Vector3(2.2, 0.15, 5.2)), B.at(Vector3(0, 0.95, 1.0)), Color(0.25, 0.24, 0.22))  # bed
		for side: float in [-1.08, 1.08]:
			truck.add(B.box(Vector3(0.05, 0.5, 5.2)), B.at(Vector3(side, 1.27, 1.0)), Color(0.45, 0.42, 0.38))
		truck.add(B.box(Vector3(2.2, 0.5, 0.05)), B.at(Vector3(0, 1.27, 3.58)), Color(0.45, 0.42, 0.38))
		for x in [-1.0, 1.0]:
			for z in [-2.5, 0.6, 2.4]:
				truck.add(B.cylinder(0.42, 0.42, 0.3, 14), B.at(Vector3(x, 0.42, z), Vector3(0, 0, 90)), Color(0.06, 0.06, 0.06))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(body.name))
		for k in 12:
			truck.add(B.sphere(1.0, 7), B.at(Vector3(rng.randf_range(-0.7, 0.7), 1.25 + (k / 6) * 0.3, rng.randf_range(-1.2, 3.2)), Vector3.ZERO,
					Vector3(0.3, 0.17, 0.45)), Color(0.86, 0.85, 0.8))
		var instance := _mesh(self, truck.commit(_props), true)
		instance.global_transform = body.global_transform


## Open-sided wholesale sheds: corrugated roofs on the posts.
func _build_sheds() -> void:
	var B := MeshBaker
	var sheds := MeshBaker.new()
	for shed: Array in [[-64.0, -52.0], [-46.0, -34.0]]:
		var mid: float = (shed[0] + shed[1]) * 0.5
		var width: float = shed[1] - shed[0]
		for side: float in [-1.0, 1.0]:
			sheds.add(B.box(Vector3(width * 0.5 + 0.6, 0.06, 34.0)), B.at(Vector3(mid + side * width * 0.25, 4.6, 22), Vector3(0, 0, -10.0 * side)),
					Color(0.5, 0.36, 0.26) if side < 0 else Color(0.56, 0.55, 0.52))
		sheds.add(B.box(Vector3(0.15, 0.25, 34.0)), B.at(Vector3(mid, 5.15, 22)), Color(0.3, 0.3, 0.3))
		for x: float in [shed[0], shed[1]]:
			sheds.add(B.box(Vector3(0.12, 0.2, 34.0)), B.at(Vector3(x, 4.15, 22)), Color(0.3, 0.3, 0.3))
	var material := _props.duplicate() as StandardMaterial3D
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(self, sheds.commit(material), true).name = "ShedRoofs"
	_sign_text("HOLSEL - BUAI, KOPRA, RAIS", self, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-34.3, 3.4, 22)), 0.3, Color(0.85, 0.75, 0.2), true)


# --- Plaza, car park, skyline ---------------------------------------------------------------

## Shrubs and palms in the planters, the monument stone, the mural.
func _build_plaza() -> void:
	var B := MeshBaker
	var rng := RandomNumberGenerator.new()
	rng.seed = 2019
	var green := MeshBaker.new()
	for planter_name in ["PlanterA", "PlanterB", "PlanterC", "PlanterD", "PlanterE", "IslandA", "IslandB"]:
		var planter := get_node_or_null("Navigation/" + planter_name) as CSGBox3D
		if planter == null:
			continue
		var size := planter.size
		var top := planter.global_position + Vector3.UP * size.y * 0.5
		var count := int(size.x * size.z / 1.6)
		for k in count:
			var spot := top + Vector3(rng.randf_range(-size.x * 0.45, size.x * 0.45), 0.0, rng.randf_range(-size.z * 0.4, size.z * 0.4))
			var r := rng.randf_range(0.25, 0.5)
			green.add(B.sphere(r, 6), B.at(spot + Vector3.UP * r * 0.6, Vector3.ZERO, Vector3(1, 0.8, 1)),
					Color(0.2, 0.42, 0.16).lerp(Color(0.55, 0.5, 0.15), rng.randf() * 0.4))
		for k in int(size.x / 4.0):  # red and yellow crotons
			var spot := top + Vector3(rng.randf_range(-size.x * 0.45, size.x * 0.45), 0.25, rng.randf_range(-size.z * 0.3, size.z * 0.3))
			green.add(B.sphere(0.3, 6), B.at(spot), Color(0.75, 0.25, 0.1) if k % 2 == 0 else Color(0.85, 0.7, 0.12))
	_mesh(self, green.commit(_props), true).name = "Planting"
	# The monument: a pale boulder on its plinth.
	var stone := MeshBaker.new()
	for k in 5:
		stone.add(B.sphere(1.0, 8), B.at(Vector3(0, 1.1, 36) + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.1, 0.25), rng.randf_range(-0.2, 0.2)),
				Vector3(rng.randf_range(0, 40), rng.randf_range(0, 180), 0), Vector3(0.62, 0.5, 0.55)), Color(0.86, 0.85, 0.82))
	var monument := get_node_or_null("Navigation/MonumentStone") as CSGBox3D
	if monument != null:
		monument.visible = false
	_mesh(self, stone.commit(_props), true).name = "MonumentStone"
	_build_mural(Vector3(36, 1.8, 41.58), Vector2(11.6, 3.4))


## Pasted-up posters on the walls round the market: festivals, a string band
## night, a rugby league derby and city notices, in Tok Pisin. All made up
## (no real brands, teams or people). [position, facing, design].
const POSTERS := [
	[Vector3(-69.97, 1.7, -22.0), Vector3(1, 0, 0), "hiri"], [Vector3(-69.97, 1.6, -20.9), Vector3(1, 0, 0), "stringband"],
	[Vector3(-69.97, 1.7, -4.0), Vector3(1, 0, 0), "klin"], [Vector3(-69.97, 1.6, 14.0), Vector3(1, 0, 0), "ragbi"],
	[Vector3(-69.97, 1.65, 15.2), Vector3(1, 0, 0), "spet"], [Vector3(-69.97, 1.7, 32.0), Vector3(1, 0, 0), "bilum"],
	[Vector3(-32.0, 1.7, 61.97), Vector3(0, 0, -1), "vout"], [Vector3(-30.8, 1.6, 61.97), Vector3(0, 0, -1), "stringband"],
	[Vector3(-8.0, 1.7, 61.97), Vector3(0, 0, -1), "ragbi"], [Vector3(16.0, 1.65, 61.97), Vector3(0, 0, -1), "hiri"],
	[Vector3(17.2, 1.7, 61.97), Vector3(0, 0, -1), "spet"], [Vector3(34.0, 1.7, 61.97), Vector3(0, 0, -1), "klin"],
	[Vector3(33.0, 1.7, 42.03), Vector3(0, 0, 1), "bilum"], [Vector3(38.5, 1.6, 42.03), Vector3(0, 0, 1), "vout"],
	[Vector3(69.97, 1.7, -30.0), Vector3(-1, 0, 0), "ragbi"], [Vector3(69.97, 1.7, 24.0), Vector3(-1, 0, 0), "hiri"],
	# Clusters: the same spots plastered again, a sheet or two along.
	[Vector3(-69.96, 1.75, -2.9), Vector3(1, 0, 0), "vout"], [Vector3(-69.96, 1.7, 33.2), Vector3(1, 0, 0), "spet"],
	[Vector3(-29.6, 1.75, 61.96), Vector3(0, 0, -1), "klin"], [Vector3(-6.8, 1.65, 61.96), Vector3(0, 0, -1), "bilum"],
	[Vector3(35.2, 1.75, 61.96), Vector3(0, 0, -1), "stringband"], [Vector3(69.96, 1.65, -28.8), Vector3(-1, 0, 0), "vout"],
	[Vector3(69.96, 1.75, 25.2), Vector3(-1, 0, 0), "stringband"], [Vector3(34.2, 1.75, 42.04), Vector3(0, 0, 1), "spet"],
]


## Each design: an original poster texture (drawn into an image at load) and
## its lettering over it.
func _build_posters() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	var textures := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1975
	for poster: Array in POSTERS:
		var design: String = poster[2]
		if not textures.has(design):
			textures[design] = _poster_texture(design)
		var normal: Vector3 = poster[1]
		var quad := QuadMesh.new()
		quad.size = Vector2(0.62, 0.88)
		var instance := MeshInstance3D.new()
		instance.mesh = quad
		var material := StandardMaterial3D.new()
		material.albedo_texture = textures[design]
		material.roughness = 0.9
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = 40.0
		instance.name = "Poster"
		add_child(instance)
		# Pasted up by hand: a little askew.
		var basis := Basis.looking_at(-normal).rotated(normal, deg_to_rad(rng.randf_range(-4.0, 4.0)))
		instance.global_transform = Transform3D(basis.scaled(Vector3.ONE * poster_scale), poster[0])
		for line: Array in _poster_lines(design):
			var label := Label3D.new()
			label.text = line[0]
			label.font = font
			label.font_size = 64
			label.pixel_size = float(line[2]) / 64.0
			label.outline_size = 0
			label.modulate = line[3]
			label.shaded = true
			label.double_sided = false
			label.visibility_range_end = 25.0
			label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			label.width = 560.0
			label.autowrap_mode = TextServer.AUTOWRAP_WORD
			instance.add_child(label)
			label.position = Vector3(0, float(line[1]), 0.004)


## [text, height on the poster (m from its middle), letter height, colour].
func _poster_lines(design: String) -> Array:
	var black := Color(0.08, 0.06, 0.05)
	var white := Color(0.97, 0.95, 0.88)
	var gold := Color(0.98, 0.78, 0.15)
	match design:
		"hiri":
			return [["HIRI MOALE", 0.33, 0.085, gold], ["FESTIVAL", 0.24, 0.06, white], ["ELA BICH  -  SEPTEMBA", -0.36, 0.035, white]]
		"stringband":
			return [["STRING BAND", 0.33, 0.07, black], ["NAIT", 0.25, 0.06, Color(0.75, 0.1, 0.08)],
					["LIVE - FRAIDE 7PM\nKOKI CLUB  K10", -0.3, 0.035, black]]
		"klin":
			return [["KEEP POM", 0.32, 0.08, white], ["KLIN!", 0.22, 0.09, gold], ["TROIM PIPIA LONG BIN", -0.36, 0.035, white]]
		"spet":
			return [["NOKEN", 0.33, 0.08, Color(0.75, 0.08, 0.06)], ["SPET BUAI", 0.24, 0.065, black], ["NCD PAIN K50", -0.36, 0.035, black]]
		"ragbi":
			return [["RAGBI LIG", 0.34, 0.075, gold], ["GEREHU\nvs\nBOROKO", -0.02, 0.06, white], ["SATADE 3PM  -  LLOYD ROBSON OVAL", -0.37, 0.028, white]]
		"bilum":
			return [["BILUM", 0.34, 0.085, black], ["FESTIVAL", 0.25, 0.055, Color(0.7, 0.12, 0.35)], ["KAM LUKIM!", -0.36, 0.04, black]]
		"vout":
			return [["VOUT", 0.32, 0.1, white], ["LONG GUTPELA LIDA", 0.2, 0.04, white], ["NOKEN SALIM VOUT BILONG YU", -0.36, 0.03, gold]]
	return []


func _poster_texture(design: String) -> ImageTexture:
	var w := 124
	var h := 176
	var image := Image.create_empty(w, h, true, Image.FORMAT_RGB8)
	var background := {"hiri": Color(0.62, 0.1, 0.08), "stringband": Color(0.95, 0.85, 0.55), "klin": Color(0.12, 0.42, 0.25),
			"spet": Color(0.95, 0.93, 0.86), "ragbi": Color(0.1, 0.12, 0.3), "bilum": Color(0.98, 0.8, 0.2), "vout": Color(0.12, 0.25, 0.55)}
	image.fill(background.get(design, Color.WHITE))
	for y in h:
		for x in w:
			var u := (x + 0.5) / w
			var v := (y + 0.5) / h  # 0 at the top
			var color := image.get_pixel(x, y)
			match design:
				"hiri":
					# A lakatoi: crab-claw sails over a canoe hull, on a black band of sea.
					if v > 0.78:
						color = Color(0.08, 0.06, 0.05)
					for sail in 2:
						var cx := 0.35 + sail * 0.3
						var d := Vector2(u - cx, (v - 0.52) * 0.9)
						if d.length() < 0.17 and d.length() > 0.08 and d.y < 0.05:
							color = Color(0.98, 0.78, 0.15)
					if v > 0.66 and v < 0.72 and absf(u - 0.5) < 0.38 - (v - 0.66) * 2.0:
						color = Color(0.3, 0.18, 0.1)
				"stringband":
					# A guitar silhouette.
					var body := Vector2((u - 0.5) * 1.1, v - 0.62)
					if body.length() < 0.17 or Vector2(u - 0.5, (v - 0.47) * 1.3).length() < 0.11:
						color = Color(0.35, 0.18, 0.08)
					if absf(u - 0.5) < 0.03 and v > 0.18 and v < 0.55:
						color = Color(0.2, 0.12, 0.06)
					if Vector2(u - 0.5, v - 0.6).length() < 0.05:
						color = Color(0.08, 0.06, 0.05)
				"klin":
					# A rubbish bin and a sweep of the broom.
					if absf(u - 0.5) < 0.16 - (v - 0.45) * 0.1 and v > 0.45 and v < 0.75:
						color = Color(0.9, 0.9, 0.85)
					if absf(u - 0.5) < 0.19 and absf(v - 0.44) < 0.02:
						color = Color(0.9, 0.9, 0.85)
				"spet":
					# A red buai splash under a no-entry ring.
					var c := Vector2(u - 0.5, (v - 0.56) * 0.8)
					if c.length() < 0.16 and fmod(atan2(c.y, c.x) * 3.0 + 10.0, 1.0) < 0.7:
						color = Color(0.7, 0.08, 0.06)
					if c.length() > 0.24 and c.length() < 0.29:
						color = Color(0.75, 0.08, 0.06)
					if absf(c.x + c.y) < 0.025 and c.length() < 0.27:
						color = Color(0.75, 0.08, 0.06)
				"ragbi":
					# Gold and red diagonal bands and a ball.
					if fmod(u + v * 0.7, 0.5) < 0.08:
						color = Color(0.7, 0.12, 0.08)
					if Vector2((u - 0.5) * 1.6, v - 0.7).length() < 0.1:
						color = Color(0.55, 0.32, 0.15)
				"bilum":
					# Bilum stripes in a zigzag weave.
					var band := int((v + absf(fmod(u * 6.0, 2.0) - 1.0) * 0.05) * 14.0)
					if v > 0.32 and v < 0.78:
						color = [Color(0.8, 0.15, 0.1), Color(0.1, 0.1, 0.1), Color(0.15, 0.5, 0.25), Color(0.95, 0.95, 0.9),
								Color(0.2, 0.3, 0.7)][band % 5]
				"vout":
					# A ballot box with a paper going in.
					if absf(u - 0.5) < 0.2 and v > 0.5 and v < 0.76:
						color = Color(0.95, 0.95, 0.9)
					if absf(u - 0.5) < 0.12 and v > 0.4 and v < 0.52 and absf(u - 0.5 - (0.52 - v) * 0.3) < 0.08:
						color = Color(0.98, 0.78, 0.15)
			# Weathering: a faded, stained edge.
			var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			if edge < 0.03:
				color = color.lerp(Color(0.85, 0.82, 0.72), 0.5)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## A painted kumul (bird of paradise) on the mural wall's plaza side: an
## original mural, not a copy of the market's real one.
func _build_mural(center: Vector3, size: Vector2) -> void:
	var w := 256
	var h := 76
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	image.fill(Color(0.16, 0.42, 0.26))
	for y in h:
		for x in w:
			var u := float(x) / w * size.x / size.y  # square units
			var v := float(y) / h
			var color := Color(0.16, 0.42, 0.26).lerp(Color(0.1, 0.3, 0.32), v)
			# Plumes: long orange-gold streams flowing back and down from the body.
			var body := Vector2(1.55, 0.45)
			var p := Vector2(u, v)
			for k in 7:
				var angle := 0.25 + k * 0.1
				var root := body + Vector2(-0.12, 0.08)
				var t := (root.x - p.x) / 1.1
				if t > 0.0 and t < 1.0:
					var stream_y := root.y + sin(angle) * t * 0.9 + t * t * 0.25
					if absf(p.y - stream_y) < 0.03 * (1.0 - t * 0.6):
						color = Color(0.95, 0.55, 0.12).lerp(Color(0.98, 0.82, 0.25), t)
			# Body, head and beak.
			if (p - body).length() < 0.16:
				color = Color(0.45, 0.25, 0.12)
			if (p - (body + Vector2(0.18, -0.12))).length() < 0.085:
				color = Color(0.95, 0.8, 0.2)
			if p.x > body.x + 0.24 and p.x < body.x + 0.36 and absf(p.y - (body.y - 0.12) - (p.x - body.x - 0.24) * 0.3) < 0.025:
				color = Color(0.75, 0.75, 0.7)
			if (p - (body + Vector2(0.2, -0.14))).length() < 0.015:
				color = Color(0.05, 0.05, 0.05)
			# A band of zigzags along the foot, like a woven border.
			if v > 0.88 and fmod(absf(u * 6.0 - floor(u * 6.0) - 0.5) * 2.0 + (v - 0.88) * 8.0, 1.0) < 0.35:
				color = Color(0.92, 0.9, 0.84)
			image.set_pixel(x, y, color)
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.roughness = 0.9
	var quad := QuadMesh.new()
	quad.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.material_override = material
	instance.name = "Mural"
	add_child(instance)
	instance.global_transform = Transform3D(Basis(Vector3.UP, PI), center)  # faces the plaza (-z)


## Painted bays in the car park.
func _build_car_park_lines() -> void:
	var B := MeshBaker
	var lines := MeshBaker.new()
	for row_z in [-46.0, -30.0]:
		for i in 18:
			var x := -66.0 + i * 2.6
			lines.add(B.box(Vector3(0.1, 0.01, 5.0)), B.at(Vector3(x, 0.006, row_z)), Color(0.85, 0.85, 0.8))
	var material := _props.duplicate() as StandardMaterial3D
	material.metallic = 0.0
	material.roughness = 0.9
	var instance := _mesh(self, lines.commit(material), false)
	instance.name = "CarParkLines"
	instance.visibility_range_end = 60.0


## Port Moresby's dry, grassy hills round the skyline, with the odd tree.
func _build_hills() -> void:
	var B := MeshBaker
	var rng := RandomNumberGenerator.new()
	rng.seed = 7731
	var hills := MeshBaker.new()
	for k in 14:
		var angle := k * TAU / 14.0 + rng.randf_range(-0.15, 0.15)
		var distance := rng.randf_range(260.0, 420.0)
		var at := Vector3(cos(angle), 0, sin(angle)) * distance
		var height := rng.randf_range(35.0, 90.0)
		hills.add(B.sphere(1.0, 10, true), B.at(at, Vector3(0, rng.randf_range(0, 180), 0), Vector3(rng.randf_range(90, 160), height, rng.randf_range(60, 120))),
				Color(0.42, 0.38, 0.24).lerp(Color(0.3, 0.34, 0.2), rng.randf()))
	var instance := _mesh(self, hills.commit(_props), false)
	instance.name = "Hills"


## A basis whose -Z runs along `direction` (for beams between two points).
func _look_along(direction: Vector3) -> Basis:
	var up := Vector3.UP if absf(direction.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(direction.normalized(), up)
