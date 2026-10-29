extends Node
## Autoloaded as `MusicPlayer`: builds Grivet's music (Music) once on a worker
## thread at startup and plays it on the "Music" bus. The title menu loops the
## island groove; in the game the two dark tactical tracks (covert ops, then
## the quieter tension) take turns, one loop each, over the night ambience.
## Settings controls volume and mute.

@export var track_volume_db := -8.0
## The game's tracks play this much louder than the menu's: measured, the game set sat
## at -25 dBFS under gunfire peaks near 0 and the player couldn't hear it at +3, nor
## at +8 (about 6 dB under the same track played on its own). Above 0 dB the
## Music bus limiter keeps the peaks from clipping.
@export var game_boost_db := 13.0
@export var limiter_ceiling_db := -1.0
@export var ambience_volume_db := -14.0
@export var fade_seconds := 2.5

var _track := AudioStreamPlayer.new()
var _ambience := AudioStreamPlayer.new()
var _task := -1  # WorkerThreadPool task, waited on before we go
var _groove: AudioStreamWAV
var _covert: AudioStreamWAV
var _tension: AudioStreamWAV
var _night: AudioStreamWAV
var _set := "menu"
var _last_position := 0.0
var _fade := 0.0
var _bus_state := ""  # Music bus volume and mute as last logged


func _ready() -> void:
	for player in [_track, _ambience]:
		player.bus = "Music"
		add_child(player)
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps playing under the pause menu
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = limiter_ceiling_db
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"), limiter)
	if DisplayServer.get_name() == "headless":
		return  # tests and probes: no music, no build cost
	_task = WorkerThreadPool.add_task(_build, false, "music")


func _exit_tree() -> void:
	_finish_build()


## "menu" (the groove alone) or "game" (the dark tracks in turn, ambience under).
func play_set(set_name: String) -> void:
	print("music play_set %s (was %s, built %s, playing %s)" % [set_name, _set, _groove != null, _track.playing])
	if set_name == _set and _track.playing:
		return
	_set = set_name
	if _groove != null:
		_begin()


func _finish_build() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Worker thread: compose, then hand the streams to the main thread.
func _build() -> void:
	var groove := Music.island_groove()
	var covert := Music.covert_ops()
	var tension := Music.tension()
	var night := Music.night_ambience()
	_ready_to_play.call_deferred(groove, covert, tension, night)


func _ready_to_play(groove: AudioStreamWAV, covert: AudioStreamWAV, tension: AudioStreamWAV, night: AudioStreamWAV) -> void:
	_finish_build()
	_groove = groove
	_covert = covert
	_tension = tension
	_night = night
	_begin()


func _begin() -> void:
	_track.stream = _covert if _set == "game" else _groove
	_track.volume_db = -60.0
	_track.play()
	if _set == "game":
		_ambience.stream = _night
		_ambience.volume_db = -60.0
		_ambience.play()
	else:
		_ambience.stop()
	_last_position = 0.0
	_fade = 0.0
	_report("start")


## One line in the game log per start or swap, so a playtest's log says what
## the music did (the player reported none while every probe heard it).
func _report(event: String) -> void:
	var bus := AudioServer.get_bus_index("Music")
	print("music %s: set %s, %s, Music bus %.1f dB%s, master %.1f dB%s, output '%s' (%s, %d Hz)" % [event, _set,
			"groove" if _track.stream == _groove else ("covert" if _track.stream == _covert else "tension"),
			AudioServer.get_bus_volume_db(bus), " MUTED" if AudioServer.is_bus_mute(bus) else "",
			AudioServer.get_bus_volume_db(0), " MUTED" if AudioServer.is_bus_mute(0) else "",
			AudioServer.output_device, ["stereo", "surround 3.1", "surround 5.1", "surround 7.1"][AudioServer.get_speaker_mode()],
			AudioServer.get_mix_rate()])
	var buses := []
	for b in AudioServer.bus_count:
		buses.append("%d %s %.1f dB%s -> %s" % [b, AudioServer.get_bus_name(b), AudioServer.get_bus_volume_db(b),
				" MUTED" if AudioServer.is_bus_mute(b) else "", AudioServer.get_bus_send(b)])
	print("music buses: %s; track on '%s' at %.1f dB" % [" | ".join(buses), _track.bus, _track.volume_db])


func _process(delta: float) -> void:
	var bus := AudioServer.get_bus_index("Music")
	var bus_state := "%.1f dB%s" % [AudioServer.get_bus_volume_db(bus), " MUTED" if AudioServer.is_bus_mute(bus) else ""]
	if bus_state != _bus_state:
		print("music bus now %s (was %s; settings music_volume %s, music_on %s; set %s, playing %s)" % [bus_state, _bus_state,
				Settings.get_value("music_volume"), Settings.get_value("music_on"), _set, _track.playing])
		_bus_state = bus_state
	if not _track.playing:
		return
	_fade = minf(_fade + delta / fade_seconds, 1.0)
	_track.volume_db = lerpf(-60.0, track_volume_db + (game_boost_db if _set == "game" else 0.0), sqrt(_fade))
	_ambience.volume_db = lerpf(-60.0, ambience_volume_db, sqrt(_fade))
	# In the game, swap tracks each time the current one comes round again.
	var position := _track.get_playback_position()
	if _set == "game" and position < _last_position - 1.0:
		_track.stream = _tension if _track.stream == _covert else _covert
		_track.play()
		_report("swap")
		position = 0.0
	_last_position = position
