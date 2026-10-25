extends SceneTree
## Builds the dark in-game tracks, reports build time, and saves them as WAV
## for listening outside the game (diagnostic, not part of the suite).
##   $GODOT --headless --path . -s res://tests/probes/music_timing.gd -- out=<dir>


func _init() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.trim_prefix("out=")
	var started := Time.get_ticks_msec()
	var covert := Music.covert_ops()
	print("covert_ops: %.1f s long, built in %d ms" % [ProceduralAudio.duration(covert), Time.get_ticks_msec() - started])
	started = Time.get_ticks_msec()
	var tension := Music.tension()
	print("tension: %.1f s long, built in %d ms" % [ProceduralAudio.duration(tension), Time.get_ticks_msec() - started])
	covert.save_to_wav(out.path_join("grivet_covert_ops.wav"))
	tension.save_to_wav(out.path_join("grivet_tension.wav"))
	print("saved")
	quit(0)
