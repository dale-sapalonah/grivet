class_name ShoutBook
extends Resource
## The enemies' shouts and how often they come (data/ai/shouts.tres).

@export var lines: Array[ShoutLine] = []
## Nobody shouts within this many seconds of the last shout (no talking over each other).
@export var gap_seconds := 1.4
## The same soldier waits this long between shouts.
@export var soldier_gap_seconds := 7.0
## Threats and machete shouts only when the player is within this range (m) and in view.
@export var threat_range := 18.0
## Chance per second a soldier in threat range shouts (once its gaps have passed).
@export var threat_chance := 0.35
@export var volume_db := 4.0
@export var unit_size := 12.0
@export var max_distance := 70.0
## Voices are pitched per soldier between these, so they don't all sound alike.
@export var pitch_min := 0.84
@export var pitch_max := 1.0
## The words float over the shouter and show at the bottom of the screen this long.
@export var text_seconds := 2.2

@export_group("Yelled, not read")
## The recorded (or synthesised) lines are driven into saturation, with the
## lows cut and an edge added, so they sound yelled (ProceduralAudio.shouted).
@export var drive := 4.0
@export var edge := 0.6

@export_group("Pain")
## Grunts, winces and groans when hit, a cry when killed (ProceduralAudio.pain,
## a small voice synthesiser): this many takes of each.
@export var pain_variants := 4
@export var pain_volume_db := 2.0
@export var pain_unit_size := 10.0
## The same soldier makes no second pain sound within this many seconds.
@export var pain_gap_seconds := 0.6
## Hits that leave it below this share of its health groan rather than grunt.
@export var groan_below := 0.45
