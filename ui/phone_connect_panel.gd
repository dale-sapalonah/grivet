class_name PhoneConnectPanel
extends VBoxContainer
## The menu's PHONE CONTROLLER page: starts the PhonePad server if it isn't
## running (PhonePad.start_server), asks it for the controller links
## (localhost-only /api/controller-links, QR modules included) and draws one QR
## code per network, USB tether first. Scanning one opens the controller page
## in the phone's browser. The status line turns green once a phone connects.

const RETRY_SECONDS := 1.0
## The server takes a few seconds to come up (it asks Windows for adapter names).
const GIVE_UP_SECONDS := 25.0

var _font: Font
var _status: Label
var _codes: HBoxContainer
var _request := HTTPRequest.new()
var _waiting := 0.0
var _retry_left := 0.0
var _active := false
var _have_links := false
var _error := ""


func _init(font: Font) -> void:
	_font = font
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 12)
	process_mode = Node.PROCESS_MODE_ALWAYS  # works from the pause menu
	add_child(GrivetStyle.label("PHONE CONTROLLER", font, 80, GrivetStyle.WHITE, 14))
	_status = GrivetStyle.label("", font, 26, GrivetStyle.WHITE, 6)
	add_child(_status)
	_codes = HBoxContainer.new()
	_codes.alignment = BoxContainer.ALIGNMENT_CENTER
	_codes.add_theme_constant_override("separation", 40)
	add_child(_codes)
	var hint := GrivetStyle.label("SCAN WITH THE PHONE CAMERA, ACCEPT THE CERTIFICATE WARNING ONCE, TAP FPS",
			font, 20, Color(GrivetStyle.WHITE, 0.75), 4)
	add_child(hint)
	_request.timeout = 3.0
	_request.request_completed.connect(_on_links)
	add_child(_request)


## Called when the page is shown.
func open() -> void:
	_active = true
	_have_links = false
	_error = PhonePad.start_server()
	_waiting = 0.0
	_retry_left = 0.0
	for child in _codes.get_children():
		child.queue_free()


## Called when the page is hidden.
func close() -> void:
	_active = false
	_request.cancel_request()


func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree():
		return
	if _error != "":
		_set_status(_error, GrivetStyle.RED)
		return
	if PhonePad.controllers > 0:
		_set_status("PHONE CONNECTED - GO BACK AND PLAY", Color(0.35, 0.9, 0.45))
	elif _have_links:
		_set_status("WAITING FOR THE PHONE...", GrivetStyle.WHITE)
	if _have_links:
		return
	_waiting += delta
	if _waiting < GIVE_UP_SECONDS:
		_set_status("STARTING PHONEPAD...", GrivetStyle.WHITE)
	elif PhonePad.is_connected_to_server():
		_set_status("ANOTHER APP'S PHONEPAD HOLDS GRIVET'S PORT: CLOSE IT, THEN TRY AGAIN", GrivetStyle.RED)
	else:
		_set_status("PHONEPAD DIDN'T START: RUN Play Grivet with Phone.bat", GrivetStyle.RED)
	_retry_left -= delta
	if _retry_left <= 0.0 and _request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_retry_left = RETRY_SECONDS
		_request.request(PhonePad.links_url())


func _on_links(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _active or result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	# Only Grivet's own server: another PhonePad's links open another game's page.
	if PhonePad.server_app != "grivet":
		return
	var links: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not links is Array:
		return
	_have_links = true
	if (links as Array).is_empty():
		_error = "NO USB TETHER OR WI-FI FOUND: TURN ON USB TETHERING, THEN RESTART PHONEPAD"
		return
	for link: Variant in links:
		if link is Dictionary:
			_codes.add_child(_entry(link))


func _entry(link: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	column.add_child(GrivetStyle.label(str(link.get("label", "")).to_upper(), _font, 30, GrivetStyle.ORANGE, 6))
	var view := QrView.new()
	view.modules = PackedStringArray(link.get("qr", []))
	column.add_child(view)
	column.add_child(GrivetStyle.label(str(link.get("url", "")), _font, 18, GrivetStyle.WHITE, 4))
	return column


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


## Draws QR modules ("1" dark) on white with the standard 4-module quiet zone.
class QrView:
	extends Control

	const SIZE := 300.0
	const QUIET := 4

	var modules := PackedStringArray()

	func _init() -> void:
		custom_minimum_size = Vector2(SIZE, SIZE)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
		if modules.is_empty():
			return
		var count := modules.size() + QUIET * 2
		var cell := floorf(minf(size.x, size.y) / count)  # whole pixels keep edges sharp
		var origin := ((size - Vector2.ONE * cell * count) * 0.5).floor() + Vector2.ONE * cell * QUIET
		for y in modules.size():
			var row := modules[y]
			for x in row.length():
				if row[x] == "1":
					draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell)), Color.BLACK)
