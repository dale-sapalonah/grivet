"""Generates levels/greybox/arena.tscn (the Milestone 3 combat arena greybox).

Usage: python tools/gen_arena.py levels/greybox/arena.tscn
Doors and windows are 1.6 m gaps so the navmesh (agent radius 0.375 m) passes through.
"""
import pathlib
import sys

out = pathlib.Path(sys.argv[1])

boxes = []  # (name, center, size, material, surface)


def box(name, x, y_bottom, z, sx, sy, sz, material, surface):
    boxes.append((name, (x, y_bottom + sy / 2.0, z), (sx, sy, sz), material, surface))


# Floor and perimeter.
box("Floor", 0, -1, 0, 64, 1, 64, "Floor", "concrete")
box("WallNorth", 0, 0, -31.5, 64, 3, 1, "Wall", "concrete")
box("WallSouth", 0, 0, 31.5, 64, 3, 1, "Wall", "concrete")
box("WallWest", -31.5, 0, 0, 1, 3, 64, "Wall", "concrete")
box("WallEast", 31.5, 0, 0, 1, 3, 64, "Wall", "concrete")

# South (player side).
box("LowWallSW", -6, 0, 18, 3, 1, 0.4, "Wall", "concrete")
box("LowWallSE", 6, 0, 16, 3, 1, 0.4, "Wall", "concrete")
box("CrateSW", -14, 0, 20, 1.2, 1.2, 1.2, "Crate", "wood")
box("CrateSE", 14, 0, 21, 1.2, 1.2, 1.2, "Crate", "wood")
box("ContainerSW", -20, 0, 12, 2.44, 2.6, 6.1, "Container", "steel")

# Middle yard.
box("ContainerMidW", -8, 0, 2, 6.1, 2.6, 2.44, "Container", "steel")
box("ContainerMidE", 10, 0, -2, 2.44, 2.6, 6.1, "Container", "steel")
box("LowWallMid1", 0, 0, 6, 4, 1, 0.4, "Wall", "concrete")
box("LowWallMid2", -2, 0, -6, 4, 1, 0.4, "Wall", "concrete")
box("LowWallMid3", 18, 0, 8, 0.4, 1, 4, "Wall", "concrete")
box("BarrierMid1", 4, 0, -10, 2, 1.1, 0.6, "Wall", "concrete")
box("BarrierMid2", -16, 0, -6, 2, 1.1, 0.6, "Wall", "concrete")
box("CrateStackLow", -24, 0, -2, 1.2, 1.2, 1.2, "Crate", "wood")
box("CrateStackHigh", -24, 1.2, -2, 1.2, 1.2, 1.2, "Crate", "wood")

# North.
box("ContainerNW", -14, 0, -18, 6.1, 2.6, 2.44, "Container", "steel")
box("ContainerNWTop", -14, 2.6, -18, 6.1, 2.6, 2.44, "Container", "steel")
box("CrateN1", -6, 0, -22, 1.2, 1.2, 1.2, "Crate", "wood")
box("CrateN2", -4.6, 0, -22, 1.2, 1.2, 1.2, "Crate", "wood")
box("LowWallN", 2, 0, -20, 4, 1, 0.4, "Wall", "concrete")

# Two-room building, x 8..20, z -24..-14: doors and windows are gaps.
box("BldgSouthA", 10.05, 0, -14, 4.1, 3, 0.3, "Building", "concrete")
box("BldgSouthB", 15.0, 0, -14, 2.0, 3, 0.3, "Building", "concrete")
box("BldgSouthSill", 17, 0, -14, 2, 1, 0.3, "Building", "concrete")
box("BldgSouthHeader", 17, 2.2, -14, 2, 0.8, 0.3, "Building", "concrete")
box("BldgSouthC", 19, 0, -14, 2, 3, 0.3, "Building", "concrete")
box("BldgNorth", 14, 0, -24, 12.3, 3, 0.3, "Building", "concrete")
box("BldgWestA", 8, 0, -22.2, 0.3, 3, 3.6, "Building", "concrete")
box("BldgWestB", 8, 0, -16.2, 0.3, 3, 4.4, "Building", "concrete")
box("BldgEastA", 20, 0, -22.5, 0.3, 3, 3, "Building", "concrete")
box("BldgEastSill", 20, 0, -20, 0.3, 1, 2, "Building", "concrete")
box("BldgEastHeader", 20, 2.2, -20, 0.3, 0.8, 2, "Building", "concrete")
box("BldgEastB", 20, 0, -16.5, 0.3, 3, 5, "Building", "concrete")
box("BldgDividerA", 14, 0, -22.0, 0.3, 3, 4.0, "Building", "concrete")
box("BldgDividerB", 14, 0, -16.0, 0.3, 3, 4.0, "Building", "concrete")
box("BldgCrateW", 10, 0, -20, 1.2, 1.2, 1.2, "Crate", "wood")
box("BldgCrateE", 17, 0, -22, 1.2, 1.2, 1.2, "Crate", "wood")

spawns = [
    ("RiflemanWest", -10, -21, "rifleman"),
    ("RiflemanCentre", 2, -24, "rifleman"),
    ("RiflemanBuilding", 16, -18, "rifleman"),
    ("RusherWest", -22, -24, "rusher"),
    ("RusherEast", 25, -10, "rusher"),
]

materials = {
    "Floor": ((0.42, 0.42, 0.42), (0.3, 0.3, 0.3)),
    "Wall": ((0.62, 0.62, 0.6), (0.45, 0.45, 0.43)),
    "Building": ((0.72, 0.7, 0.64), (0.55, 0.53, 0.48)),
    "Container": ((0.22, 0.38, 0.32), (0.14, 0.25, 0.2)),
    "Crate": ((0.62, 0.45, 0.27), (0.42, 0.3, 0.17)),
}

lines = []
w = lines.append
w("[gd_scene format=3]")
w("")
w('[ext_resource type="Script" path="res://levels/greybox/arena.gd" id="1_arena"]')
w('[ext_resource type="Shader" path="res://levels/greybox/grid.gdshader" id="2_grid"]')
w('[ext_resource type="PackedScene" path="res://player/player.tscn" id="3_player"]')
w('[ext_resource type="PackedScene" path="res://ui/debug_overlay.tscn" id="4_overlay"]')
w('[ext_resource type="PackedScene" path="res://ui/hud.tscn" id="5_hud"]')
w("")
w('[sub_resource type="ProceduralSkyMaterial" id="SkyMaterial"]')
w("sky_top_color = Color(0.32, 0.42, 0.55, 1)")
w("sky_horizon_color = Color(0.62, 0.64, 0.66, 1)")
w("ground_horizon_color = Color(0.62, 0.64, 0.66, 1)")
w("")
w('[sub_resource type="Sky" id="Sky"]')
w('sky_material = SubResource("SkyMaterial")')
w("")
w('[sub_resource type="Environment" id="Environment"]')
w("background_mode = 2")
w('sky = SubResource("Sky")')
w("ambient_light_source = 3")
w("tonemap_mode = 2")
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
for name, (base, line) in materials.items():
    w(f'[sub_resource type="ShaderMaterial" id="{name}"]')
    w('shader = ExtResource("2_grid")')
    w(f"shader_parameter/base_color = Color({base[0]}, {base[1]}, {base[2]}, 1)")
    w(f"shader_parameter/line_color = Color({line[0]}, {line[1]}, {line[2]}, 1)")
    w("")
w('[node name="Arena" type="Node3D"]')
w('script = ExtResource("1_arena")')
w("")
w('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
w('environment = SubResource("Environment")')
w("")
w('[node name="Sun" type="DirectionalLight3D" parent="."]')
w("transform = Transform3D(0.866, -0.383, 0.3215, 0, 0.643, 0.766, -0.5, -0.663, 0.557, 0, 10, 0)")
w("shadow_enabled = true")
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
for name, (x, y, z), (sx, sy, sz), material, surface in boxes:
    w(f'[node name="{name}" type="CSGBox3D" parent="Navigation"]')
    w(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, {y:g}, {z:g})")
    w("use_collision = true")
    w(f"size = Vector3({sx:g}, {sy:g}, {sz:g})")
    w(f'material = SubResource("{material}")')
    w(f'metadata/surface = "{surface}"')
    w("")
w('[node name="EnemySpawns" type="Node3D" parent="."]')
w("")
for name, x, z, kind in spawns:
    w(f'[node name="{name}" type="Marker3D" parent="EnemySpawns" groups=["enemy_spawn"]]')
    w(f"transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, {x:g}, 0, {z:g})")
    w(f'metadata/enemy = "{kind}"')
    w("")
out.write_text("\n".join(lines), encoding="utf-8")
print(f"wrote {out} with {len(boxes)} boxes and {len(spawns)} spawns")
