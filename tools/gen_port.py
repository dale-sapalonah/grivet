"""Generates levels/port/port_yard.tscn: the combat arena's layout dressed as a
container terminal at dusk (the vertical slice's setting).

Usage: python tools/gen_port.py levels/port/port_yard.tscn

Same footprint, cover and spawns as tools/gen_arena.py, so the AI behaves as
tested there. The perimeter is stacked shipping containers; low walls are
sandbags; barriers and the warehouse are concrete; light poles, oil drums
and two parked PMV minibuses add cover. Every collider is a CSG box or cylinder under the navigation
region. Visual-only dressing (lamp heads and lights, crane, ship, distant
stacks) is built at runtime by levels/port/port_yard.gd.
"""
import math
import pathlib
import sys

out = pathlib.Path(sys.argv[1])

boxes = []  # (name, center, size, material, surface, instance parameters)


def box(name, x, y_bottom, z, sx, sy, sz, material, surface, **params):
    boxes.append((name, (x, y_bottom + sy / 2.0, z), (sx, sy, sz), material, surface, params))


def container(name, x, y_bottom, z, along_x, seed, cells=1, tiers=1):
    sx, sz = (6.1 * cells, 2.44) if along_x else (2.44, 6.1 * cells)
    box(name, x, y_bottom, z, sx, 2.6 * tiers, sz, "Container", "steel",
        box_size=(sx, 2.6 * tiers, sz), cells=((cells, tiers, 1) if along_x else (1, tiers, cells)), seed=seed)


def crate(name, x, y_bottom, z, seed, size=1.2):
    box(name, x, y_bottom, z, size, size, size, "Crate", "wood", box_size=(size, size, size), seed=seed)


# Ground.
box("Floor", 0, -1, 0, 64, 1, 64, "Asphalt", "concrete")

# Perimeter: two-high container walls (inner faces at +-31, like the arena's walls).
container("WallNorth", 0, 0, -32.22, True, 1, cells=11, tiers=2)
container("WallSouth", 0, 0, 32.22, True, 2, cells=11, tiers=2)
container("WallWest", -32.22, 0, 0, False, 3, cells=11, tiers=2)
container("WallEast", 32.22, 0, 0, False, 4, cells=11, tiers=2)

# South (player side).
box("LowWallSW", -6, 0, 18, 3, 1, 0.4, "Sandbag", "sandbag")
box("LowWallSE", 6, 0, 16, 3, 1, 0.4, "Sandbag", "sandbag")
crate("CrateSW", -14, 0, 20, 1)
crate("CrateSE", 14, 0, 21, 2)
container("ContainerSW", -20, 0, 12, False, 11)

# Middle yard.
container("ContainerMidW", -8, 0, 2, True, 12)
container("ContainerMidE", 10, 0, -2, False, 13)
box("LowWallMid1", 0, 0, 6, 4, 1, 0.4, "Sandbag", "sandbag")
box("LowWallMid2", -2, 0, -6, 4, 1, 0.4, "Sandbag", "sandbag")
box("LowWallMid3", 18, 0, 8, 0.4, 1, 4, "Sandbag", "sandbag")
box("BarrierMid1", 4, 0, -10, 2, 1.1, 0.6, "Barrier", "concrete")
box("BarrierMid2", -16, 0, -6, 2, 1.1, 0.6, "Barrier", "concrete")
crate("CrateStackLow", -24, 0, -2, 3)
crate("CrateStackHigh", -24, 1.2, -2, 4)

# North.
container("ContainerNW", -14, 0, -18, True, 14)
container("ContainerNWTop", -14, 2.6, -18, True, 15)
crate("CrateN1", -6, 0, -22, 5)
crate("CrateN2", -4.6, 0, -22, 6)
box("LowWallN", 2, 0, -20, 4, 1, 0.4, "Sandbag", "sandbag")

# Warehouse office, x 8..20, z -24..-14: doors and windows are gaps.
for name, x, y, z, sx, sy, sz in [
    ("BldgSouthA", 10.05, 0, -14, 4.1, 3, 0.3),
    ("BldgSouthB", 15.0, 0, -14, 2.0, 3, 0.3),
    ("BldgSouthSill", 17, 0, -14, 2, 1, 0.3),
    ("BldgSouthHeader", 17, 2.2, -14, 2, 0.8, 0.3),
    ("BldgSouthC", 19, 0, -14, 2, 3, 0.3),
    ("BldgNorth", 14, 0, -24, 12.3, 3, 0.3),
    ("BldgWestA", 8, 0, -22.2, 0.3, 3, 3.6),
    ("BldgWestB", 8, 0, -16.2, 0.3, 3, 4.4),
    ("BldgEastA", 20, 0, -22.5, 0.3, 3, 3),
    ("BldgEastSill", 20, 0, -20, 0.3, 1, 2),
    ("BldgEastHeader", 20, 2.2, -20, 0.3, 0.8, 2),
    ("BldgEastB", 20, 0, -16.5, 0.3, 3, 5),
    ("BldgDividerA", 14, 0, -22.0, 0.3, 3, 4.0),
    ("BldgDividerB", 14, 0, -16.0, 0.3, 3, 4.0),
]:
    box(name, x, y, z, sx, sy, sz, "Building", "concrete")
crate("BldgCrateW", 10, 0, -20, 7)
crate("BldgCrateE", 17, 0, -22, 8)

# Light poles (8 m, steel) and oil drums: (name, x, z).
poles = [("PoleNW", -28, -28), ("PoleN", 0, -29.6), ("PoleNE", 28, -28), ("PoleW", -29.6, 8),
         ("PoleE", 29.6, 6), ("PoleSW", -12, 29.6), ("PoleSE", 12, 29.6)]
drums = [("DrumSW1", -18, 16, 0), ("DrumSW2", -17.35, 16.3, 0), ("DrumSW3", -17.7, 15.6, 0),
         ("DrumE1", 22, -6, 1), ("DrumE2", 22.62, -6.3, 1),
         ("DrumW1", -27, -14, 2), ("DrumW2", -26.4, -14.25, 2), ("DrumW3", -26.75, -13.6, 2),
         ("DrumN1", 6, -27, 0), ("DrumN2", 6.62, -27.2, 1)]

# Port Moresby PMVs parked on the player's side: (name, x, z, yaw rows, livery, route, plate, headlights).
# Collision boxes with the "vehicle" surface; port_yard.gd dresses them.
buses = [
    ("PmvRoute17", -22, 27, "0, 0, -1, 0, 1, 0, 1, 0, 0", "Color(0.16, 0.6, 0.6, 1)", "17", "P 4172", True),
    ("PmvRoute4", 26, 18, "1, 0, 0, 0, 1, 0, 0, 0, 1", "Color(0.52, 0.52, 0.82, 1)", "4", "P 3908", False),
]

spawns = [
    ("RiflemanWest", -10, -21, "rifleman"),
    ("RiflemanCentre", 2, -24, "rifleman"),
    ("RiflemanBuilding", 16, -18, "rifleman"),
    ("RusherWest", -22, -24, "rusher"),
    ("RusherEast", 25, -10, "rusher"),
]

# Shader materials: (id, shader resource id, parameters).
materials = [
    ("Asphalt", "asphalt", {}),
    ("Container", "container", {}),
    ("Crate", "crate", {}),
    ("Building", "concrete", {"base_color": "Color(0.56, 0.54, 0.5, 1)"}),
]
drum_colors = ["Color(0.12, 0.22, 0.42, 1)", "Color(0.5, 0.12, 0.08, 1)", "Color(0.62, 0.48, 0.1, 1)"]


# Jersey barrier cross-section (across the barrier, height), counter-clockwise.
JERSEY = [(-0.3, 0.0), (0.3, 0.0), (0.3, 0.08), (0.16, 0.3), (0.09, 1.1), (-0.09, 1.1), (-0.16, 0.3), (-0.3, 0.08)]

# Sandbag walls and jersey barriers are static bodies (their look is built by
# port_yard.gd: real bags, a real barrier profile); everything else is CSG.
BODY_MATERIALS = ("Sandbag", "Barrier")


def body_shape(name, size, material):
    """Sub-resource text for a body's collision shape, centred on the body."""
    sx, sy, sz = size
    if material == "Barrier":
        long_x = sx >= sz
        length = sx if long_x else sz
        points = []
        for end in (-length / 2, length / 2):
            for u, v in JERSEY:
                point = (end, v - sy / 2, u) if long_x else (u, v - sy / 2, end)
                points.extend(point)
        return (f'[sub_resource type="ConvexPolygonShape3D" id="Shape{name}"]\n'
                f'points = PackedVector3Array({", ".join(f"{c:g}" for c in points)})\n')
    return f'[sub_resource type="BoxShape3D" id="Shape{name}"]\nsize = Vector3({sx:g}, {sy:g}, {sz:g})\n'


def look_basis_rows(direction):
    """Rows of a basis whose -Z points along `direction` (scene files store rows)."""
    length = math.sqrt(sum(c * c for c in direction))
    z = [-c / length for c in direction]
    up = [0.0, 1.0, 0.0]
    x = [up[1] * z[2] - up[2] * z[1], up[2] * z[0] - up[0] * z[2], up[0] * z[1] - up[1] * z[0]]
    xl = math.sqrt(sum(c * c for c in x))
    x = [c / xl for c in x]
    y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
    return [[x[i], y[i], z[i]] for i in range(3)]


def vec(v):
    return "Vector3(%s)" % ", ".join(f"{c:g}" for c in v)


lines = []
w = lines.append
w("[gd_scene format=3]")
w("")
w('[ext_resource type="Script" path="res://levels/port/port_yard.gd" id="1_level"]')
w('[ext_resource type="PackedScene" path="res://player/player.tscn" id="3_player"]')
w('[ext_resource type="PackedScene" path="res://ui/debug_overlay.tscn" id="4_overlay"]')
w('[ext_resource type="PackedScene" path="res://ui/hud.tscn" id="5_hud"]')
w('[ext_resource type="Texture2D" path="res://levels/port/materials/noise.tres" id="6_noise"]')
for shader in ["asphalt", "container", "crate", "concrete"]:
    w(f'[ext_resource type="Shader" path="res://levels/port/materials/{shader}.gdshader" id="shader_{shader}"]')
w("")
w('[sub_resource type="ProceduralSkyMaterial" id="SkyMaterial"]')
w("sky_top_color = Color(0.045, 0.06, 0.15, 1)")
w("sky_horizon_color = Color(0.6, 0.33, 0.22, 1)")
w("sky_curve = 0.09")
w("ground_bottom_color = Color(0.02, 0.02, 0.025, 1)")
w("ground_horizon_color = Color(0.3, 0.19, 0.15, 1)")
w("sun_angle_max = 12.0")
w("sun_curve = 0.06")
w("")
w('[sub_resource type="Sky" id="Sky"]')
w('sky_material = SubResource("SkyMaterial")')
w("")
w('[sub_resource type="Environment" id="Environment"]')
w("background_mode = 2")
w('sky = SubResource("Sky")')
w("ambient_light_source = 3")
w("ambient_light_color = Color(0.36, 0.36, 0.48, 1)")
w("ambient_light_sky_contribution = 0.55")
w("ambient_light_energy = 1.9")
w("tonemap_mode = 2")
w("tonemap_exposure = 1.15")
w("fog_enabled = true")
w("fog_light_color = Color(0.32, 0.26, 0.28, 1)")
w("fog_density = 0.009")
w("fog_sun_scatter = 0.35")
w("fog_aerial_perspective = 0.6")
w("fog_sky_affect = 0.25")
w("adjustment_enabled = true")
w("adjustment_saturation = 1.08")
w("")
w('[sub_resource type="NavigationMesh" id="NavMesh"]')
w("cell_size = 0.125")
w("cell_height = 0.125")
w("agent_height = 1.75")
w("agent_radius = 0.375")
w("agent_max_climb = 0.25")
w("agent_max_slope = 46.0")
w("geometry_parsed_geometry_type = 1")
w("geometry_collision_mask = 1")
w("")
for name, shader, params in materials:
    w(f'[sub_resource type="ShaderMaterial" id="{name}"]')
    w(f'shader = ExtResource("shader_{shader}")')
    w('shader_parameter/noise_tex = ExtResource("6_noise")')
    for key, value in params.items():
        w(f"shader_parameter/{key} = {value}")
    w("")
for name, center, size, material, surface, params in boxes:
    if material in BODY_MATERIALS:
        w(body_shape(name, size, material))
w('[sub_resource type="BoxShape3D" id="BusShape"]')
w("size = Vector3(2.05, 2.5, 7)")
w("")
w('[sub_resource type="StandardMaterial3D" id="PoleSteel"]')
w("albedo_color = Color(0.32, 0.33, 0.34, 1)")
w("metallic = 0.6")
w("roughness = 0.5")
w("")
for i, color in enumerate(drum_colors):
    w(f'[sub_resource type="StandardMaterial3D" id="Drum{i}"]')
    w(f"albedo_color = {color}")
    w("metallic = 0.4")
    w("roughness = 0.55")
    w("")
w('[node name="PortYard" type="Node3D"]')
w('script = ExtResource("1_level")')
w("")
w('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
w('environment = SubResource("Environment")')
w("")
# Setting sun (12 degrees up) in the west-south-west: long shadows across the yard to the north-east.
rows = look_basis_rows([0.86, -0.21, -0.46])
flat = ", ".join(f"{c:.4f}" for row in rows for c in row)
w('[node name="Sun" type="DirectionalLight3D" parent="."]')
w(f"transform = Transform3D({flat}, 0, 20, 0)")
w("light_color = Color(1, 0.58, 0.34, 1)")
w("light_energy = 1.25")
w("shadow_enabled = true")
w("shadow_bias = 0.04")
w("shadow_normal_bias = 1.5")
w("directional_shadow_mode = 1")
w("directional_shadow_max_distance = 60.0")
w("")
w('[node name="Player" parent="." instance=ExtResource("3_player")]')
w("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 26)")
w("")
w('[node name="HUD" parent="." instance=ExtResource("5_hud")]')
w("")
w('[node name="DebugOverlay" parent="." instance=ExtResource("4_overlay")]')
w("")
w('[node name="Navigation" type="NavigationRegion3D" parent="."]')
w('navigation_mesh = SubResource("NavMesh")')
w("")
for name, (x, y, z), (sx, sy, sz), material, surface, params in boxes:
    if material in BODY_MATERIALS:
        group = "sandbag_wall" if material == "Sandbag" else "jersey_barrier"
        w(f'[node name="{name}" type="StaticBody3D" parent="Navigation" groups=["{group}"]]')
        w(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, {y:g}, {z:g})")
        w(f'metadata/surface = "{surface}"')
        w(f"metadata/size = Vector3({sx:g}, {sy:g}, {sz:g})")
        w("")
        w(f'[node name="Shape" type="CollisionShape3D" parent="Navigation/{name}"]')
        w(f'shape = SubResource("Shape{name}")')
        w("")
        continue
    w(f'[node name="{name}" type="CSGBox3D" parent="Navigation"]')
    w(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, {y:g}, {z:g})")
    for key, value in params.items():
        w(f"instance_shader_parameters/{key} = {vec(value) if isinstance(value, tuple) else f'{value:g}'}")
    w("use_collision = true")
    w(f"size = Vector3({sx:g}, {sy:g}, {sz:g})")
    w(f'material = SubResource("{material}")')
    w(f'metadata/surface = "{surface}"')
    w("")
for name, x, z in poles:
    w(f'[node name="{name}" type="CSGCylinder3D" parent="Navigation" groups=["lamp_pole"]]')
    w(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, 4, {z:g})")
    w("use_collision = true")
    w("radius = 0.12")
    w("height = 8.0")
    w("sides = 10")
    w('material = SubResource("PoleSteel")')
    w('metadata/surface = "steel"')
    w("")
for name, x, z, color in drums:
    w(f'[node name="{name}" type="CSGCylinder3D" parent="Navigation"]')
    w(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, 0.44, {z:g})")
    w("use_collision = true")
    w("radius = 0.29")
    w("height = 0.88")
    w("sides = 14")
    w(f'material = SubResource("Drum{color}")')
    w('metadata/surface = "steel"')
    w("")
for name, x, z, rows, livery, route, plate, headlights in buses:
    w(f'[node name="{name}" type="StaticBody3D" parent="Navigation" groups=["pmv_bus"]]')
    w(f"transform = Transform3D({rows}, {x:g}, 0, {z:g})")
    w('metadata/surface = "vehicle"')
    w(f"metadata/livery = {livery}")
    w(f'metadata/route = "{route}"')
    w(f'metadata/plate = "{plate}"')
    w(f"metadata/headlights = {'true' if headlights else 'false'}")
    w("")
    w(f'[node name="Shape" type="CollisionShape3D" parent="Navigation/{name}"]')
    w("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.25, 0)")
    w('shape = SubResource("BusShape")')
    w("")
w('[node name="EnemySpawns" type="Node3D" parent="."]')
w("")
for name, x, z, kind in spawns:
    w(f'[node name="{name}" type="Marker3D" parent="EnemySpawns" groups=["enemy_spawn"]]')
    w(f"transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, {x:g}, 0, {z:g})")
    w(f'metadata/enemy = "{kind}"')
    w("")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(lines), encoding="utf-8")
print(f"wrote {out} with {len(boxes)} boxes, {len(poles)} poles, {len(drums)} drums, {len(buses)} buses and {len(spawns)} spawns")
