class_name SurfaceMaterial
extends Resource
## How bullets treat one kind of surface, and how it sounds and breaks when
## hit. Colliders opt in with the metadata `surface = "<id>"` (on the collider
## or a parent); anything untagged uses BallisticsSettings.default_surface.
##
## Impact sound and debris are driven by physics, not a fixed sample: the
## outcome (penetrated / stopped / ricochet), the struck object's areal
## density (density x thickness the bullet met) and the energy the round
## still carries. See ProceduralAudio.impact and ImpactEffects.

## How the material responds acoustically and physically to a hit.
enum AcousticType {
	METAL,    ## Rings: thin plate clangs, thick plate thunks, glancing hits resonate.
	WOOD,     ## Thin boards splinter; dense wood absorbs with a dull thud.
	MASONRY,  ## Shatters at the point of impact; powder or rubble with calibre.
	SOFT,     ## Absorbs: a muffled thump (bodies, earth).
}

@export var id := ""
@export var acoustic_type: AcousticType = AcousticType.MASONRY
## kg per cubic metre.
@export var density := 2400.0
## Penetration power spent per metre of this material (see WeaponDefinition.penetration_power).
@export var penetration_cost_per_metre := 1000.0
## Thickest slab the exit probe looks through (m); thicker counts as solid.
@export var max_thickness := 1.0
@export var damage_retention := 0.6
@export var velocity_retention := 0.7
## Shots grazing the surface at less than this angle bounce off (0 = never),
## for a mid-energy round; light rounds deflect at steeper angles and heavy
## ones at shallower (BallisticsSettings.ricochet_*_angle_multiplier).
@export var ricochet_max_angle_degrees := 0.0
@export var ricochet_speed_retention := 0.6
@export var ricochet_damage_retention := 0.5
@export var impact_color := Color(0.6, 0.6, 0.6)
@export var dust_color := Color(0.6, 0.6, 0.6, 0.5)

@export_group("Impact sound")
@export var impact_volume_db := -6.0
## Areal density (kg/m², density x thickness) from which the struck object
## behaves as thick and dense: less ring and splinter, more thud.
@export var areal_density_thick := 150.0
@export_subgroup("Metal")
## Ring pitch for thin plate and for thick plate (stiffer = higher, tighter).
@export var ring_low_hz := 450.0
@export var ring_high_hz := 1600.0
## Ring decay time constants (s): thin plate rings longer than thick.
@export var ring_decay_thin := 0.2
@export var ring_decay_thick := 0.05
## Glancing hits excite the plate without dumping energy into it: longer resonance.
@export var ricochet_ring_multiplier := 3.0
@export_subgroup("Wood")
## Hollow knock of a thin board.
@export var panel_knock_hz := 380.0
## Fibre breaks in the splinter crackle of a thin board hit by a heavy round.
@export var splinter_count := 14
## Pitch of the dull thud from dense wood.
@export var thud_hz := 140.0
@export_subgroup("Masonry")
## Debris grains (powder) for the lightest and heaviest rounds...
@export var crumble_grains_light := 12
@export var crumble_grains_heavy := 60
## ...and how long the debris keeps falling (s).
@export var crumble_seconds_light := 0.15
@export var crumble_seconds_heavy := 0.6
## Larger rubble chunks knocked loose by the heaviest rounds.
@export var chunk_count := 6

@export_group("Casings landing here")
## 0 = casings land silently (dirt, bodies); 1 = concrete; above 1 rings brighter.
@export var casing_brightness := 1.0


## 0 = thin / light, 1 = thick / dense, from the thickness the bullet met.
## `solid` means the exit probe found no far side within max_thickness.
func mass_factor(thickness: float, solid: bool) -> float:
	if solid:
		return 1.0
	return clampf(density * thickness / areal_density_thick, 0.0, 1.0)
