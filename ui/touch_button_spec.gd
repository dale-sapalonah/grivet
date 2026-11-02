class_name TouchButtonSpec
extends Resource
## One on-screen button (see TouchTuning.buttons).

enum Mode { HOLD, TAP, TOGGLE }

## The InputMap action it presses (fire, aim, reload, jump, ...).
@export var action := ""
@export var label := ""
## Centre, in virtual pixels from the bottom-right corner of the screen.
@export var offset := Vector2.ZERO
@export var radius := 60.0
@export var mode: Mode = Mode.HOLD
