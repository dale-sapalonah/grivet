class_name PhonePadProtocol
extends RefCounted
## PhonePad wire format and receive-side bookkeeping, kept free of autoloads so
## it tests headless. The PhonePad autoload (core/phone_pad.gd) feeds it the
## binary packets the phone sends through tools/phonepad/server.js.
##
## v2 (FPS mode, 120 Hz), 14 bytes little-endian:
##   u8 type=2 | u16 seq | u16 buttons (BIT_*) | i16 move x | i16 move y (+-32767)
##   | i16 look dx | i16 look dy (1/100 degree of phone turn, summed on the phone since
##   the last packet that went out) | u8 flags (bit0 gyro, bit1 lean by tilt, bit2 look touch)
## v1 (Gamepad / Remote modes, 60 Hz), 15 bytes: u8 type=1 | u16 seq | u8 buttons
##   (A 1, B 2, X 4, Y 8, PAUSE 16, END 32) | u8 flags | u8 gesture | u8 gesture seq
##   | i16 stick x | i16 stick y | i16 tilt x | i16 tilt y. Mapped onto the same actions.

const V2_SIZE := 14
const V1_SIZE := 15
const LOOK_UNITS_PER_DEGREE := 100.0
const AXIS_SCALE := 32767.0

const BIT_FIRE := 1 << 0
const BIT_AIM := 1 << 1
const BIT_JUMP := 1 << 2
const BIT_CROUCH := 1 << 3
const BIT_PRONE := 1 << 4
const BIT_SPRINT := 1 << 5
const BIT_RELOAD := 1 << 6
const BIT_MELEE := 1 << 7
const BIT_GRENADE := 1 << 8
const BIT_FLASHBANG := 1 << 9
const BIT_NEXT_WEAPON := 1 << 10
const BIT_PREVIOUS_WEAPON := 1 << 11
const BIT_PAUSE := 1 << 12
const BIT_LEAN_LEFT := 1 << 13
const BIT_LEAN_RIGHT := 1 << 14
const BIT_PLATE := 1 << 15

## Button bit -> Grivet action (core/input_bindings.gd).
const ACTIONS := {
	BIT_FIRE: &"fire", BIT_AIM: &"aim", BIT_JUMP: &"jump", BIT_CROUCH: &"crouch",
	BIT_PRONE: &"prone", BIT_SPRINT: &"sprint", BIT_RELOAD: &"reload", BIT_MELEE: &"melee",
	BIT_GRENADE: &"grenade", BIT_FLASHBANG: &"flashbang", BIT_NEXT_WEAPON: &"next_weapon",
	BIT_PREVIOUS_WEAPON: &"previous_weapon", BIT_PAUSE: &"pause", BIT_LEAN_LEFT: &"lean_left",
	BIT_LEAN_RIGHT: &"lean_right", BIT_PLATE: &"plate",
}
## v1 buttons -> v2 bits: A jump, B fire, X reload, Y sprint, PAUSE pause (END unused).
const V1_BUTTONS := {1: BIT_JUMP, 2: BIT_FIRE, 4: BIT_RELOAD, 8: BIT_SPRINT, 16: BIT_PAUSE}

## Packets this far behind the newest seq are stale (reordered) and dropped;
## anything further back is a reloaded phone page starting again.
const STALE_WINDOW := 1000


class Packet:
	var version := 0
	var seq := 0
	var buttons := 0
	var move := Vector2.ZERO
	## Degrees of phone turn (mouse convention: +x right, +y down).
	var look := Vector2.ZERO
	var flags := 0


## Held buttons from the newest packet.
var held := 0
## Buttons seen pressed in any packet since the last take(): a tap that starts and
## ends between two game ticks still counts once.
var latched := 0
var move := Vector2.ZERO
## Look not yet applied, summed over every packet (never per frame).
var look := Vector2.ZERO
var packets := 0
## Every degree of look received, applied or not (probes and the `phone` command).
var look_received := Vector2.ZERO
var dropped := 0
var last_seq := -1
var last_packet_ms := -1
var last_version := 0


## Parses one binary message; null if it is not a PhonePad packet.
static func decode(data: PackedByteArray) -> Packet:
	if data.is_empty():
		return null
	var packet := Packet.new()
	packet.version = data[0]
	if packet.version == 2 and data.size() >= V2_SIZE:
		packet.seq = data.decode_u16(1)
		packet.buttons = data.decode_u16(3)
		packet.move = Vector2(data.decode_s16(5), data.decode_s16(7)) / AXIS_SCALE
		packet.look = Vector2(data.decode_s16(9), data.decode_s16(11)) / LOOK_UNITS_PER_DEGREE
		packet.flags = data[13]
		return packet
	if packet.version == 1 and data.size() >= V1_SIZE:
		packet.seq = data.decode_u16(1)
		var v1: int = data[3]
		for bit: int in V1_BUTTONS:
			if v1 & bit:
				packet.buttons |= V1_BUTTONS[bit]
		packet.move = Vector2(data.decode_s16(7), data.decode_s16(9)) / AXIS_SCALE
		packet.flags = data[4]
		return packet
	return null


## Builds a v2 packet (tests and probes play the phone with it).
static func encode_v2(seq: int, buttons: int, move_axis: Vector2, look_degrees: Vector2, flags: int = 1) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(V2_SIZE)
	data[0] = 2
	data.encode_u16(1, seq & 0xffff)
	data.encode_u16(3, buttons & 0xffff)
	data.encode_s16(5, roundi(clampf(move_axis.x, -1.0, 1.0) * AXIS_SCALE))
	data.encode_s16(7, roundi(clampf(move_axis.y, -1.0, 1.0) * AXIS_SCALE))
	data.encode_s16(9, clampi(roundi(look_degrees.x * LOOK_UNITS_PER_DEGREE), -32767, 32767))
	data.encode_s16(11, clampi(roundi(look_degrees.y * LOOK_UNITS_PER_DEGREE), -32767, 32767))
	data[13] = flags
	return data


## True when seq `a` comes after `b` on the u16 wrap.
static func seq_after(a: int, b: int) -> bool:
	var diff := (a - b) & 0xffff
	return diff != 0 and diff < 0x8000


## Takes in one binary message; false if it was not a packet or was stale.
func receive(data: PackedByteArray, now_ms: int) -> bool:
	var packet := decode(data)
	if packet == null:
		return false
	if last_seq >= 0 and not seq_after(packet.seq, last_seq) and ((last_seq - packet.seq) & 0xffff) < STALE_WINDOW:
		dropped += 1
		return false
	last_seq = packet.seq
	last_packet_ms = now_ms
	last_version = packet.version
	packets += 1
	held = packet.buttons
	latched |= packet.buttons
	move = packet.move
	look += packet.look
	look_received += packet.look
	return true


## True while packets keep coming (the phone is released after `timeout_ms` of silence).
func is_live(now_ms: int, timeout_ms: int) -> bool:
	return last_packet_ms >= 0 and now_ms - last_packet_ms <= timeout_ms


## The buttons to hold this tick (held plus latched taps); clears the latch.
func take_buttons(now_ms: int, timeout_ms: int) -> int:
	var out := held | latched
	latched = 0
	if not is_live(now_ms, timeout_ms):
		held = 0
		move = Vector2.ZERO
		return 0
	return out


## Look to apply now, in degrees of phone turn; clears it.
func take_look() -> Vector2:
	var out := look
	look = Vector2.ZERO
	return out


func reset() -> void:
	held = 0
	latched = 0
	move = Vector2.ZERO
	look = Vector2.ZERO
	last_seq = -1
	last_packet_ms = -1
