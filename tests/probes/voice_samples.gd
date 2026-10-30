extends SceneTree
## Writes the enemy voices as WAVs for listening outside the game: every shout
## line as yelled in game (ProceduralAudio.shouted) and every pain take
## (ProceduralAudio.pain). Diagnostic, not part of the suite.
##   $GODOT --headless --path . -s res://tests/probes/voice_samples.gd -- out=<dir>


func _init() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.trim_prefix("out=")
	var book: ShoutBook = load("res://data/ai/shouts.tres")
	var started := Time.get_ticks_msec()
	for line in book.lines:
		var yelled := ProceduralAudio.shouted(line.voice as AudioStreamWAV, book.drive, book.edge)
		yelled.save_to_wav(out.path_join("shout_%s.wav" % line.voice.resource_path.get_file().get_basename()))
	print("shouts: %d in %d ms" % [book.lines.size(), Time.get_ticks_msec() - started])
	started = Time.get_ticks_msec()
	for kind in ["grunt", "wince", "groan", "death"]:
		for variant in book.pain_variants:
			ProceduralAudio.pain(kind, variant).save_to_wav(out.path_join("pain_%s_%d.wav" % [kind, variant]))
	print("pain: %d in %d ms" % [4 * book.pain_variants, Time.get_ticks_msec() - started])
	quit(0)
