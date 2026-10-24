class_name PbrLibrary
extends RefCounted
## Authored PBR textures, if any, for the procedural surfaces: drop files in
##   assets/textures/<slot>/normal.png     (OpenGL-style normal map, tiling)
##   assets/textures/<slot>/roughness.png  (greyscale, white = rough)
## for slots container, concrete, asphalt, dirt and weapon_metal, and the
## matching materials pick them up at load (1K or 2K, power-of-two, tiling).
## No files = the procedural look only. Every pack needs a row in
## Docs/AssetLicences.md.

const ROOT := "res://assets/textures/%s/%s.png"
## Per slot: [normal strength, roughness mix, repeats per metre].
const SLOTS := {
	"container": [0.6, 0.5, 0.35],
	"concrete": [0.5, 0.6, 0.5],
	"asphalt": [0.4, 0.5, 0.5],
	"dirt": [0.5, 0.6, 0.6],
	"weapon_metal": [1.0, 1.0, 4.0],
}


## Fills a port surface ShaderMaterial's detail slots from `slot`'s files.
static func apply_shader(material: ShaderMaterial, slot: String) -> bool:
	var normal := _load(slot, "normal")
	if material == null or normal == null:
		return false
	var settings: Array = SLOTS[slot]
	material.set_shader_parameter("detail_normal", normal)
	material.set_shader_parameter("detail_strength", settings[0])
	material.set_shader_parameter("detail_tiling", settings[2])
	var roughness := _load(slot, "roughness")
	if roughness != null:
		material.set_shader_parameter("detail_roughness", roughness)
		material.set_shader_parameter("detail_roughness_mix", settings[1])
	return true


## Fills a StandardMaterial3D (the guns) from `slot`'s files.
static func apply_standard(material: StandardMaterial3D, slot: String) -> bool:
	var normal := _load(slot, "normal")
	if material == null or normal == null:
		return false
	var settings: Array = SLOTS[slot]
	material.normal_enabled = true
	material.normal_texture = normal
	material.normal_scale = settings[0]
	material.uv1_triplanar = true  # the view model's primitives have no authored UVs
	material.uv1_scale = Vector3.ONE * settings[2]
	var roughness := _load(slot, "roughness")
	if roughness != null:
		material.roughness_texture = roughness
	return true


static func _load(slot: String, map: String) -> Texture2D:
	var path := ROOT % [slot, map]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
