extends "res://tests/framework/suite.gd"

const P := preload("res://core/phone_pad_protocol.gd")


func test_v2_round_trip() -> void:
	var data := P.encode_v2(513, P.BIT_FIRE | P.BIT_PLATE, Vector2(0.5, -1.0), Vector2(1.25, -0.5), 5)
	assert_eq(data.size(), P.V2_SIZE)
	var packet := P.decode(data)
	assert_eq(packet.version, 2)
	assert_eq(packet.seq, 513)
	assert_eq(packet.buttons, P.BIT_FIRE | P.BIT_PLATE)
	assert_true(absf(packet.move.x - 0.5) < 0.001 and absf(packet.move.y + 1.0) < 0.001, "move %s" % packet.move)
	assert_true(packet.look.is_equal_approx(Vector2(1.25, -0.5)), "look %s" % packet.look)
	assert_eq(packet.flags, 5)


func test_v1_maps_to_actions() -> void:
	var data := PackedByteArray()
	data.resize(P.V1_SIZE)
	data[0] = 1
	data.encode_u16(1, 7)
	data[3] = 1 | 2 | 16  # A, B, PAUSE
	data.encode_s16(7, 32767)
	data.encode_s16(9, 0)
	var packet := P.decode(data)
	assert_eq(packet.version, 1)
	assert_eq(packet.buttons, P.BIT_JUMP | P.BIT_FIRE | P.BIT_PAUSE)
	assert_true(absf(packet.move.x - 1.0) < 0.001, "move %s" % packet.move)


func test_rejects_junk() -> void:
	assert_eq(P.decode(PackedByteArray()), null)
	assert_eq(P.decode(PackedByteArray([2, 0, 0])), null)
	assert_eq(P.decode(PackedByteArray([9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])), null)


func test_tap_between_ticks_is_latched() -> void:
	var receiver := P.new()
	receiver.receive(P.encode_v2(1, P.BIT_RELOAD, Vector2.ZERO, Vector2.ZERO), 1000)
	receiver.receive(P.encode_v2(2, 0, Vector2.ZERO, Vector2.ZERO), 1004)
	assert_eq(receiver.take_buttons(1005, 500), P.BIT_RELOAD, "the tap shows once")
	assert_eq(receiver.take_buttons(1013, 500), 0, "then it is released")


func test_look_sums_per_packet() -> void:
	var receiver := P.new()
	for i in 6:
		receiver.receive(P.encode_v2(i + 1, 0, Vector2.ZERO, Vector2(0.5, -0.25)), 1000 + i)
	assert_true(receiver.take_look().is_equal_approx(Vector2(3.0, -1.5)), "summed")
	assert_eq(receiver.take_look(), Vector2.ZERO)


func test_silence_releases_everything() -> void:
	var receiver := P.new()
	receiver.receive(P.encode_v2(1, P.BIT_FIRE, Vector2(0, 1), Vector2.ZERO), 1000)
	assert_eq(receiver.take_buttons(1400, 500), P.BIT_FIRE)
	assert_eq(receiver.take_buttons(1600, 500), 0, "500 ms of silence releases")
	assert_eq(receiver.move, Vector2.ZERO)


func test_stale_packets_dropped_and_wrap_handled() -> void:
	var receiver := P.new()
	assert_true(receiver.receive(P.encode_v2(65535, P.BIT_AIM, Vector2.ZERO, Vector2.ZERO), 1000))
	assert_true(receiver.receive(P.encode_v2(0, P.BIT_FIRE, Vector2.ZERO, Vector2.ZERO), 1001), "wraps")
	assert_true(not receiver.receive(P.encode_v2(65534, P.BIT_JUMP, Vector2.ZERO, Vector2.ZERO), 1002), "stale")
	assert_eq(receiver.held, P.BIT_FIRE)
	assert_true(receiver.receive(P.encode_v2(30000, 0, Vector2.ZERO, Vector2.ZERO), 1003), "reloaded page")


func test_level_flag_decodes_and_latches() -> void:
	var data := P.encode_v2(1, P.BIT_FIRE, Vector2.ZERO, Vector2.ZERO, 1 | P.FLAG_LEVEL)
	assert_eq(P.decode(data).buttons, P.BIT_FIRE | P.BIT_LEVEL)
	var receiver := P.new()
	receiver.receive(data, 1000)
	receiver.receive(P.encode_v2(2, 0, Vector2.ZERO, Vector2.ZERO, 1), 1004)
	assert_eq(receiver.take_buttons(1005, 500) & P.BIT_LEVEL, P.BIT_LEVEL, "a one-packet LEVEL tap still counts")
