extends Node
## Windowed probe: how loud the music really is in game. Taps the Music bus
## and the master mix (AudioEffectCapture: AudioEffectRecord's get_recording
## froze the engine here) with nobody shooting, and prints their RMS level in
## dBFS. Diagnostic: the music "played" by every check yet the player
## couldn't hear it.
##
##   $GODOT --path . res://tests/probes/music_level.tscn

const SECONDS := 8.0

var _music := AudioEffectCapture.new()
var _master := AudioEffectCapture.new()
var _sums := {"music": 0.0, "master": 0.0}
var _counts := {"music": 0, "master": 0}
var _capturing := false


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	var level: Node = load(GameMenu.MAPS[1][1]).instantiate()
	add_child(level)
	await level.combat_ready
	Debug.execute("god")
	Debug.execute("notarget")
	while MusicPlayer._covert == null:
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(5.0).timeout  # past the fade-in
	for capture: AudioEffectCapture in [_music, _master]:
		capture.buffer_length = 0.5
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"), _music)
	AudioServer.add_bus_effect(0, _master)
	_capturing = true
	await get_tree().create_timer(SECONDS).timeout
	_capturing = false
	var track: AudioStreamPlayer = MusicPlayer._track
	print("game: music bus %.1f dBFS, master mix %.1f dBFS (%s at %.1f dB, Music bus %.1f dB)" % [_db("music"), _db("master"),
			"covert" if track.stream == MusicPlayer._covert else "tension", track.volume_db,
			AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))])
	get_tree().quit(0)


func _process(_delta: float) -> void:
	if not _capturing:
		return
	for pair in [["music", _music], ["master", _master]]:
		var capture: AudioEffectCapture = pair[1]
		var frames := capture.get_buffer(capture.get_frames_available())
		for frame in frames:
			_sums[pair[0]] += frame.x * frame.x + frame.y * frame.y
		_counts[pair[0]] += frames.size() * 2


func _db(key: String) -> float:
	return linear_to_db(sqrt(_sums[key] / maxf(_counts[key], 1.0)))
