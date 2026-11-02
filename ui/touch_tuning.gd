class_name TouchTuning
extends Resource
## On-screen controls for phones and tablets. data/ui/touch_tuning.tres is the
## source of truth. Sizes and positions are in the HUD's virtual pixels (the
## 900-px-tall canvas the mobile stretch mode scales to the screen).

@export_group("Move stick (left half of the screen)")
## The stick appears where the left thumb lands; this far is full deflection.
@export var stick_radius := 110.0
## Below this share of the radius the stick does nothing (thumb rest).
@export_range(0.0, 0.9) var stick_deadzone := 0.12
## Pushed forward past this share of the radius (and mostly forwards) the
## player sprints; pushing there again while sprinting is a tactical sprint.
@export_range(0.5, 1.0) var sprint_ring := 0.92
## How far forward the stick must point to count as sprinting (y share).
@export_range(0.0, 1.0) var sprint_forward := 0.75
## Dragging past the rim pulls the stick's base along behind the thumb.
@export var stick_follows := true
## Where the stick rests when no thumb is on it (from the bottom-left corner).
@export var stick_rest := Vector2(230.0, -230.0)

@export_group("Look (right half of the screen)")
## Radians per virtual pixel dragged (Settings.touch_sensitivity scales it).
@export var look_radians_per_pixel := 0.0042
## Aiming down sights slows the look by this much.
@export var ads_multiplier := 0.55
## A one-frame jump bigger than this (virtual px) is a dropped touch, not a flick.
@export var max_drag_per_event := 220.0
## Dragging the fire button also looks (thumb fires and steers at once).
@export var fire_button_looks := true

@export_group("Buttons")
## Right-thumb buttons, each an InputMap action (TouchButtonSpec: HOLD is
## pressed while touched, TAP is one press, TOGGLE latches until tapped again).
@export var buttons: Array[TouchButtonSpec] = []
@export var pause_button_offset := Vector2(-70.0, 70.0)  # from the top-right corner
@export var pause_button_radius := 38.0

@export_group("Look and feel")
@export var idle_alpha := 0.38
@export var pressed_alpha := 0.75
@export var ring_width := 4.0
@export var label_size := 24
## Labels shrink to fit this share of their button's width.
@export_range(0.3, 1.0) var label_fill := 0.78
