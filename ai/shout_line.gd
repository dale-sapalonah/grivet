class_name ShoutLine
extends Resource
## One thing an enemy can shout: the Tok Pisin text (shown on screen), when
## it is said, and its voice (assets/audio/voice/<id>.wav).

## spot: first sight of the player. threat: the player close and in view.
## melee: a machete man closing in. grenade: throwing one. blind: flashbanged.
@export_enum("spot", "threat", "melee", "grenade", "blind") var situation := "spot"
@export var text := ""
## English, for the line list (not shown in game).
@export var meaning := ""
@export var voice: AudioStream
