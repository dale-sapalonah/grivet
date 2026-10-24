extends Node
## Autoloaded as `MusicPlayer`: builds Grivet's music (Music) once on a worker
## thread at startup and plays it on the "Music" bus. The title menu loops the
## island groove; in the game the groove and the string band take turns, one
## loop each, over the night ambience. Settings controls volume and mute.

@export var track_volume_db := -8.0
@export var ambience_volume_db := -14.0
@export var fade_seconds := 2.5

var _track := AudioStreamPlayer.new()
var _ambience := AudioStreamPlayer.new()
var _task := -1  # WorkerThreadPool task, waited on before we go
var _groove: AudioStreamWAV
var _band: AudioStreamWAV
var _night: AudioStreamWAV
var _set := "menu"
var _last_position := 0.0
var _fade := 0.0


func _ready() -> void:
	for player in [_track, _ambience]:
		player.bus = "Music"
		add_child(player)
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps playing under the pause menu
	if DisplayServer.get_name() == "headless":
		return  # tests and probes: no music, no build cost
	_task = WorkerThreadPool.add_task(_build, false, "music")


func _exit_tree() -> void:
	_finish_build()


## "menu" (the groove alone) or "game" (groove and string band in turn, ambience under).
func play_set(set_name: String) -> void:
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
	var band := Music.string_band()
	var night := Music.night_ambience()
	_ready_to_play.call_deferred(groove, band, night)


func _ready_to_play(groove: AudioStreamWAV, band: AudioStreamWAV, night: AudioStreamWAV) -> void:
	_finish_build()
	_groove = groove
	_band = band
	_night = night
	_begin()


func _begin() -> void:
	_track.stream = _groove
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


func _process(delta: float) -> void:
	if not _track.playing:
		return
	_fade = minf(_fade + delta / fade_seconds, 1.0)
	_track.volume_db = lerpf(-60.0, track_volume_db, sqrt(_fade))
	_ambience.volume_db = lerpf(-60.0, ambience_volume_db, sqrt(_fade))
	# In the game, swap tracks each time the current one comes round again.
	var position := _track.get_playback_position()
	if _set == "game" and position < _last_position - 1.0:
		_track.stream = _band if _track.stream == _groove else _groove
		_track.play()
		position = 0.0
	_last_position = position
