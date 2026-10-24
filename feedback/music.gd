class_name Music
extends RefCounted
## Grivet's music, composed in code: an island reggae groove (menu and game),
## a Port Moresby string-band loop
## (strummed guitar chords and a picked bass, kundu hand drum, a garamut slit
## gong on the downbeats, a bamboo flute line in the second half) and a night
## ambience bed (crickets, frogs, a distant harbour hum). Pure functions on
## buffers, so they build on a worker thread; the MusicPlayer autoload plays
## them on the "Music" bus.

const RATE := ProceduralAudio.MIX_RATE
const BPM := 100.0

## Chords in G: string frequencies, low to high.
const CHORDS := {
	"G": [98.0, 196.0, 246.94, 293.66, 392.0],
	"C": [130.81, 164.81, 196.0, 261.63, 329.63],
	"D": [146.83, 220.0, 293.66, 369.99, 440.0],
	"Em": [82.41, 164.81, 246.94, 329.63, 392.0],
}
const PROGRESSION := ["G", "G", "C", "D", "G", "G", "C", "D", "Em", "C", "G", "D", "Em", "C", "D", "G"]
## Eighth-note strums per bar: 1 = down, -1 = up, 0 = rest (the island lilt).
const STRUM := [1, 0, 1, -1, 0, -1, 1, -1]
## Kundu hits per bar on sixteenths: [step, loudness].
const KUNDU := [[0, 1.0], [3, 0.55], [6, 0.7], [8, 0.9], [10, 0.5], [11, 0.6], [14, 0.75]]
## Flute phrase over the second half: [bar, beat, frequency, beats long].
const FLUTE := [[8, 0, 587.33, 1.5], [8, 1.5, 659.26, 0.5], [8, 2, 587.33, 2], [9, 0, 493.88, 1], [9, 1, 440.0, 1],
		[9, 2, 392.0, 2], [10, 0, 440.0, 1.5], [10, 1.5, 493.88, 0.5], [10, 2, 587.33, 2], [11, 0, 440.0, 4],
		[12, 0, 587.33, 1], [12, 1, 659.26, 1], [12, 2, 783.99, 2], [13, 0, 659.26, 1.5], [13, 1.5, 587.33, 0.5],
		[13, 2, 493.88, 2], [14, 0, 440.0, 2], [14, 2, 493.88, 2], [15, 0, 392.0, 4]]


## The string-band loop (16 bars, about 38 s), seamless when looped.
static func string_band() -> AudioStreamWAV:
	var beat := 60.0 / BPM
	var bar := beat * 4.0
	var length := bar * PROGRESSION.size()
	var buffer := PackedFloat32Array()
	buffer.resize(int(length * RATE) + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1975  # Independence
	for b in PROGRESSION.size():
		var chord: Array = CHORDS[PROGRESSION[b]]
		var bar_start := b * bar
		# Guitar: strums; upstrokes lighter and top strings only.
		for e in STRUM.size():
			var stroke: int = STRUM[e]
			if stroke == 0:
				continue
			var at := bar_start + e * beat * 0.5 + rng.randf_range(0.0, 0.01)
			var strings := chord.slice(1) if stroke > 0 else chord.slice(2)
			if stroke < 0:
				strings.reverse()
			for s in strings.size():
				_pluck(buffer, at + s * 0.012, strings[s], (0.32 if stroke > 0 else 0.2) * rng.randf_range(0.85, 1.0), 0.9, rng)
		# Bass: root on 1 and 3, the fifth leading back.
		_pluck(buffer, bar_start, chord[0], 0.55, 1.2, rng)
		_pluck(buffer, bar_start + beat * 2.0, chord[0] * 1.5, 0.4, 1.0, rng)
		# Kundu: membrane thump with a skin slap.
		for hit: Array in KUNDU:
			var at: float = bar_start + float(hit[0]) * beat * 0.25
			var loud: float = hit[1]
			ProceduralAudio.add_thump(buffer, at, 105.0 + rng.randf_range(-6.0, 6.0), 0.07, 0.55 * loud)
			ProceduralAudio.add_noise(buffer, at, 0.02, 0.18 * loud, 2400.0, 700.0, rng)
		# Garamut: a deep wooden tock every other downbeat.
		if b % 2 == 0:
			ProceduralAudio.add_ring(buffer, bar_start, PackedFloat32Array([68.0, 141.0, 233.0]), 0.25, 0.7)
	for note: Array in FLUTE:
		var at: float = float(note[0]) * bar + float(note[1]) * beat
		_flute(buffer, at, note[2], float(note[3]) * beat, rng)
	var stream := ProceduralAudio.to_stream(buffer)
	_loop(stream, buffer.size())
	return stream


## Island reggae groove (16 bars at 92 BPM, about 42 s): steppers kick on
## every beat, rim snare on the backbeat, swung hats, a syncopated bass, guitar
## skanks on the offbeats and a synth hook in the second half. Am F C G.
static func island_groove() -> AudioStreamWAV:
	var beat := 60.0 / 92.0
	var bar := beat * 4.0
	var chords := [["Am", 110.0, [220.0, 261.63, 329.63]], ["F", 87.31, [174.61, 220.0, 261.63]],
			["C", 130.81, [261.63, 329.63, 392.0]], ["G", 98.0, [196.0, 246.94, 293.66]]]
	var bars := 16
	var buffer := PackedFloat32Array()
	buffer.resize(int(bars * bar * RATE) + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 92
	var hook := [[0.0, 440.0, 0.5], [0.75, 523.25, 0.25], [1.0, 587.33, 0.5], [1.5, 523.25, 0.5], [2.0, 440.0, 1.0],
			[3.5, 392.0, 0.5]]
	for b in bars:
		var chord: Array = chords[b % 4]
		var root: float = chord[1]
		var start := b * bar
		for q in 4:
			var at := start + q * beat
			ProceduralAudio.add_thump(buffer, at, 52.0, 0.11, 1.0)  # steppers kick
			if q == 1 or q == 3:  # rim snare on the backbeat
				ProceduralAudio.add_noise(buffer, at, 0.06, 0.55, 6000.0, 1400.0, rng)
				ProceduralAudio.add_thump(buffer, at, 190.0, 0.03, 0.35)
			for e in 2:  # swung hats
				var hat := at + e * beat * 0.58
				ProceduralAudio.add_noise(buffer, hat, 0.018 if e == 0 else 0.045, 0.16, 11000.0, 7000.0, rng)
			# Skank: a short choked chord on each offbeat.
			for n in (chord[2] as Array).size():
				_pluck_short(buffer, at + beat * 0.5 + n * 0.006, chord[2][n], 0.22, 0.12, rng)
		# Bass: root, a pickup to the fifth, octave on the "and" of 3.
		for note: Array in [[0.0, root, 0.9], [1.5, root * 1.5, 0.45], [2.5, root * 2.0, 0.4], [3.0, root, 0.8]]:
			_bass(buffer, start + float(note[0]) * beat, float(note[1]), float(note[2]) * beat)
		if b >= 8:
			for note: Array in hook:
				_lead(buffer, start + float(note[0]) * beat, float(note[1]) * (1.0 if b % 2 == 0 else 1.122), float(note[2]) * beat)
	var stream := ProceduralAudio.to_stream(buffer)
	_loop(stream, buffer.size())
	return stream


## Night bed (12 s loop): crickets in pulsing trains, the odd frog, a low hum.
static func night_ambience() -> AudioStreamWAV:
	var length := 12.0
	var buffer := PackedFloat32Array()
	buffer.resize(int(length * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	for cricket in 5:
		var hz := rng.randf_range(4200.0, 5600.0)
		var at := rng.randf_range(0.0, 0.6)
		while at < length - 0.2:
			for pulse in rng.randi_range(3, 5):
				ProceduralAudio.add_ring(buffer, at + pulse * 0.035, PackedFloat32Array([hz]), 0.008, 0.06)
			at += rng.randf_range(0.35, 0.9)
	for frog in 9:
		var at := rng.randf_range(0.0, length - 0.5)
		ProceduralAudio.add_sweep(buffer, at, 420.0, 260.0, 0.12, 0.25)
	# Harbour hum: two low steady partials, phase-continuous across the loop.
	for i in buffer.size():
		var t := float(i) / RATE
		buffer[i] += 0.035 * sin(TAU * 55.0 * t) + 0.02 * sin(TAU * 82.5 * t)
	var stream := ProceduralAudio.to_stream(buffer)
	_loop(stream, buffer.size())
	return stream


## Karplus-Strong plucked string: a burst of noise circulating in a delay line
## one period long, softened a little each pass.
static func _pluck(buffer: PackedFloat32Array, at: float, hz: float, amplitude: float, seconds: float,
		rng: RandomNumberGenerator) -> void:
	var start := int(at * RATE)
	var period := maxi(2, int(RATE / hz))
	var line := PackedFloat32Array()
	line.resize(period)
	var previous := 0.0
	for i in period:
		previous = previous * 0.5 + rng.randf_range(-1.0, 1.0) * 0.5  # a softer pick
		line[i] = previous
	var length := mini(buffer.size() - start, int(seconds * RATE))
	var damping := 0.996
	var index := 0
	for n in length:
		var next_index := index + 1 if index + 1 < period else 0
		var value := line[index]
		buffer[start + n] += value * amplitude
		line[index] = (value + line[next_index]) * 0.5 * damping
		index = next_index


## Bamboo flute: a breathy sine with gentle vibrato and a soft attack.
static func _flute(buffer: PackedFloat32Array, at: float, hz: float, seconds: float, rng: RandomNumberGenerator) -> void:
	var start := int(at * RATE)
	var length := mini(buffer.size() - start, int(seconds * RATE))
	var phase := 0.0
	for n in length:
		var t := float(n) / RATE
		var envelope := minf(t / 0.06, 1.0) * minf((seconds - t) / 0.12, 1.0)
		phase += TAU * hz * (1.0 + 0.006 * sin(TAU * 5.0 * t)) / RATE
		var tone := sin(phase) + 0.25 * sin(phase * 2.0)
		buffer[start + n] += (tone * 0.2 + rng.randf_range(-1.0, 1.0) * 0.02) * envelope


## A muted guitar stab: a plucked string choked after `seconds`.
static func _pluck_short(buffer: PackedFloat32Array, at: float, hz: float, amplitude: float, seconds: float,
		rng: RandomNumberGenerator) -> void:
	var start := int(at * RATE)
	var mark := buffer.size()
	var scratch := PackedFloat32Array()
	scratch.resize(int(seconds * RATE) + 64)
	_pluck(scratch, 0.0, hz, amplitude, seconds, rng)
	for n in mini(scratch.size(), mark - start):
		var fade := 1.0 - smoothstep(seconds * 0.6, seconds, float(n) / RATE)
		buffer[start + n] += scratch[n] * fade


## Round electric bass: sine plus a little second harmonic, plucked envelope.
static func _bass(buffer: PackedFloat32Array, at: float, hz: float, seconds: float) -> void:
	var start := int(at * RATE)
	var length := mini(buffer.size() - start, int(seconds * RATE))
	var phase := 0.0
	for n in length:
		var t := float(n) / RATE
		phase += TAU * hz / RATE
		var envelope := minf(t / 0.01, 1.0) * exp(-t * 2.2) * minf((seconds - t) / 0.03, 1.0)
		buffer[start + n] += (sin(phase) + 0.3 * sin(phase * 2.0)) * 0.55 * envelope


## Synth lead: a band-limited saw (six harmonics) with vibrato and a soft attack.
static func _lead(buffer: PackedFloat32Array, at: float, hz: float, seconds: float) -> void:
	var start := int(at * RATE)
	var length := mini(buffer.size() - start, int(seconds * RATE))
	var phase := 0.0
	for n in length:
		var t := float(n) / RATE
		phase += TAU * hz * (1.0 + 0.008 * sin(TAU * 5.5 * t)) / RATE
		var saw := 0.0
		for k in range(1, 7):
			saw += sin(phase * k) / k
		var envelope := minf(t / 0.02, 1.0) * minf((seconds - t) / 0.06, 1.0)
		buffer[start + n] += saw * 0.13 * envelope


static func _loop(stream: AudioStreamWAV, samples: int) -> void:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
