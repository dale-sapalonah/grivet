class_name PhonePadTuning
extends Resource
## PhonePad (phone controller) tuning: data/input/phone_pad_tuning.tres.

## The PhonePad server's localhost game socket (8081: Reef Rush's PhonePad uses
## 8080, so the two never meet). The PHONEPAD_GAME_PORT environment variable
## replaces the port.
@export var url := "ws://127.0.0.1:8081/ws?role=game"
## Seconds between connection attempts while the server isn't running.
@export var reconnect_seconds := 2.0
## No packet for this long: the phone counts as released (nothing held, no movement).
@export var timeout_ms := 500
## Mouse pixels per degree of phone turn (gyro, or the drag pad's equivalent).
## The player turns relative x mouse_sensitivity, so this scales with the
## SENSITIVITY setting, the ADS multiplier and INVERT Y like a mouse does.
## 16 at the default 0.0022 rad/px: one degree of phone turn = two degrees of view.
@export var look_pixels_per_degree := 16.0
## Seconds between health / pause updates sent to the phone's HUD meters.
@export var state_interval := 0.25

@export_group("Haptics")
## Vibration patterns in ms (on, off, on...), sent to the phone.
@export var fire_pattern: PackedInt32Array = [14]
## Fire buzzes at most this often (automatic weapons).
@export var fire_min_interval := 0.06
@export var damage_pattern: PackedInt32Array = [70]
@export var heavy_damage_pattern: PackedInt32Array = [120, 40, 60]
## Damage at or above this uses heavy_damage_pattern.
@export var heavy_damage := 35.0
@export var kill_pattern: PackedInt32Array = [25, 40, 90]
@export var death_pattern: PackedInt32Array = [300]
## A soldier dying this soon after the player's last hit on it counts as the player's kill.
@export var kill_credit_seconds := 1.5
