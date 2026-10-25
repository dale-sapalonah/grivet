class_name Music
extends RefCounted
## Grivet's music, composed in code: two dark tactical tracks for play
## (covert_ops, tension: drones, pulsing bass, war drums, tense pads), an
## island reggae groove for the menu,
## a Port Moresby string-band loop
## (strummed guitar chords and a picked bass, kundu hand drum, a garamut slit
## gong on the downbeats, a bamboo flute line in the second half) and a night
## ambience bed (crickets, frogs, a distant harbour hum). Pure functions on
## buffers, so they build on a worker thread; the MusicPlayer autoload plays
## them on the "Music" bus.

const RATE := ProceduralAudio.MIX_RATE
const BPM := 100.0
## Samples in one cycle of the oscillators' wavetable.
const SAW_TABLE := 2048

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


## Dark tactical in-game track (24 bars at 96 BPM, 60 s), D minor: a sub
## drone, a pulsing sixteenth-note bass, dark swelling pads (Dm Bb Gm A),
## war drums with tom fills, metallic clanks, ticking hats from bar 5, a
## riser into the second half and a sparse low motif over it. Built from an
## 8-bar core (drone, bass, pads) played three times, with every hit rendered
## once and stamped where it falls: per-sample synthesis of a whole minute in
## GDScript took minutes.
static func covert_ops() -> AudioStreamWAV:
	var beat := 60.0 / 96.0
	var bar := beat * 4.0
	var core_bars := 8
	var bars := 24
	var rng := RandomNumberGenerator.new()
	rng.seed = 1606
	var saw := _saw_table()
	# Dm Bb Gm A, two bars each: [bass root, pad voices].
	var chords := [[73.42, [146.83, 174.61, 220.0]], [58.27, [116.54, 146.83, 174.61]],
			[49.0, [98.0, 116.54, 146.83]], [55.0, [110.0, 138.59, 164.81]]]
	var core := _silence(core_bars * bar)
	_drone(core, core_bars * bar, [36.71, 55.0], 0.08)
	for c in chords.size():
		var chord: Array = chords[c]
		var pad := _silence(bar * 2.0)
		for hz: float in chord[1]:
			_pad(pad, saw, 0.0, hz, bar * 2.0, 0.13, 2200.0, rng)
		_stamp(core, pad, c * 2 * bar, 1.0)
		var pulse := _silence(beat * 0.22)
		# Root plus its octave, so the line carries on small speakers too.
		_pulse(pulse, saw, 0.0, chord[0], beat * 0.22, 0.3, 1600.0)
		_pulse(pulse, saw, 0.0, float(chord[0]) * 2.0, beat * 0.22, 0.2, 1600.0)
		var high := _silence(beat * 0.22)
		_pulse(high, saw, 0.0, float(chord[0]) * 4.0, beat * 0.22, 0.3, 1600.0)
		# The arp: the chord's notes an octave up in ticking eighths (the style's signature).
		var arp_notes: Array = chord[1]
		var arp := []
		for hz: float in arp_notes:
			var note := _silence(beat * 0.4)
			_pulse(note, saw, 0.0, hz * 2.0, beat * 0.4, 0.16, 3200.0)
			arp.append(note)
		for b in [c * 2, c * 2 + 1]:
			for step in 16:
				var accent := 1.0 if step in [0, 7, 8, 14] else 0.55
				_stamp(core, high if step == 14 else pulse, b * bar + step * beat * 0.25, accent)
			if b >= 2:
				for e in 8:
					_stamp(core, arp[[0, 1, 2, 1, 0, 2, 1, 2][e]], b * bar + e * beat * 0.5, 1.0 if e % 2 == 0 else 0.7)
	var buffer := _silence(bars * bar)
	for k in bars / core_bars:
		_stamp(buffer, core, k * core_bars * bar, 1.0)
	# Drums sit under the music rather than set its level (peaks drive normalising).
	var drum_low := _hit(func(buf: PackedFloat32Array) -> void: _war_drum(buf, 0.0, 46.0, 0.55, rng), 1.2)
	var drum_mid := _hit(func(buf: PackedFloat32Array) -> void: _war_drum(buf, 0.0, 52.0, 0.4, rng), 1.2)
	var toms := []
	for t in 4:
		toms.append(_hit(func(buf: PackedFloat32Array) -> void: _war_drum(buf, 0.0, 90.0 + t * 18.0, 0.3 + t * 0.06, rng), 1.0))
	var hat_open := _hit(func(buf: PackedFloat32Array) -> void: ProceduralAudio.add_noise(buf, 0.0, 0.012, 0.11, 11000.0, 8000.0, rng), 0.1)
	var hat_tick := _hit(func(buf: PackedFloat32Array) -> void: ProceduralAudio.add_noise(buf, 0.0, 0.006, 0.07, 11000.0, 8000.0, rng), 0.06)
	var clank := _hit(func(buf: PackedFloat32Array) -> void:
			ProceduralAudio.add_ring(buf, 0.0, PackedFloat32Array([311.0, 487.0, 802.0, 1210.0]), 0.4, 0.25), 2.8)
	for b in bars:
		var start := b * bar
		if b >= 2:
			_stamp(buffer, drum_low, start, 1.0)
			_stamp(buffer, drum_mid, start + beat * 2.5, 1.0)
			if b % 4 == 3:
				for t in 4:
					_stamp(buffer, toms[t], start + beat * (3.0 + t * 0.25), 1.0)
		if b >= 4:
			for step in 16:
				_stamp(buffer, hat_tick if step % 4 else hat_open, start + step * beat * 0.25, 1.0)
		if b % 4 == 2:
			_stamp(buffer, clank, start + beat * 2.0, 1.0)
	_riser(buffer, 10 * bar, 12 * bar, rng)
	_stamp(buffer, _hit(func(buf: PackedFloat32Array) -> void: _war_drum(buf, 0.0, 38.0, 0.8, rng), 1.4), 12 * bar, 1.0)
	# The motif: low and lonely over the second half.
	for note: Array in [[12, 0, 146.83, 3.0], [13, 0, 174.61, 2.0], [13, 2, 164.81, 2.0], [14, 0, 110.0, 4.0],
			[16, 0, 146.83, 3.0], [17, 0, 174.61, 2.0], [17, 2, 196.0, 2.0], [18, 0, 220.0, 2.0], [18, 2, 207.65, 2.0], [19, 0, 146.83, 4.0],
			[20, 0, 116.54, 4.0], [22, 0, 110.0, 4.0], [23, 0, 138.59, 4.0]]:
		_pad(buffer, saw, float(note[0]) * bar + float(note[1]) * beat, note[2], float(note[3]) * beat, 0.16, 2400.0, rng)
	var stream := ProceduralAudio.to_stream(buffer)
	_loop(stream, buffer.size())
	return stream


## The quieter dark track (16 bars at 70 BPM, about 55 s): a drone, a
## heartbeat on the low drum, tremolo strings swelling and fading, and
## distant metallic pings with long tails. For between the fights.
static func tension() -> AudioStreamWAV:
	var beat := 60.0 / 70.0
	var bar := beat * 4.0
	var bars := 16
	var rng := RandomNumberGenerator.new()
	rng.seed = 1942
	var saw := _saw_table()
	var buffer := _silence(bars * bar)
	var drone := _silence(bars * bar * 0.5)
	_drone(drone, bars * bar * 0.5, [36.71, 73.42, 77.78], 0.06)  # the minor second rubs
	_stamp(buffer, drone, 0.0, 1.0)
	_stamp(buffer, drone, bars * bar * 0.5, 1.0)
	var lub := _hit(func(buf: PackedFloat32Array) -> void: _war_drum(buf, 0.0, 50.0, 0.35, rng), 1.2)
	var dub := _hit(func(buf: PackedFloat32Array) -> void: _war_drum(buf, 0.0, 58.0, 0.22, rng), 1.2)
	var roots := [146.83, 146.83, 155.56, 146.83, 130.81, 146.83, 116.54, 110.0]
	var strings := {}  # root -> two bars of tremolo minor triad, rendered once
	for b in bars:
		var start := b * bar
		for q in [0.0, 2.0]:  # heartbeat: lub-dub on beats 1 and 3
			_stamp(buffer, lub, start + q * beat, 1.0)
			_stamp(buffer, dub, start + (q + 0.28) * beat, 1.0)
		if b % 2 == 0:
			var root: float = roots[(b / 2) % roots.size()]
			if not strings.has(root):
				var chord := _silence(bar * 2.0)
				for hz in [root, root * 1.189, root * 1.498]:  # minor triad
					_tremolo(chord, saw, 0.0, hz * 2.0, bar * 2.0, 0.1, rng)
				strings[root] = chord
			_stamp(buffer, strings[root], start, 1.0)
		if b % 3 == 1:
			var hz := rng.randf_range(900.0, 1300.0)
			var ping := _hit(func(buf: PackedFloat32Array) -> void:
					ProceduralAudio.add_ring(buf, 0.0, PackedFloat32Array([hz, hz * 1.52, hz * 2.37]), 1.4, 0.12), 6.0)
			_stamp(buffer, ping, start + rng.randf_range(0.5, 2.5) * beat, 1.0)
	var stream := ProceduralAudio.to_stream(buffer)
	_loop(stream, buffer.size())
	return stream


## `seconds` of silence to render into.
static func _silence(seconds: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(seconds * RATE) + 1)
	return buffer


## One sound rendered once (`render` draws into a fresh buffer `seconds` long).
static func _hit(render: Callable, seconds: float) -> PackedFloat32Array:
	var buffer := _silence(seconds)
	render.call(buffer)
	return buffer


## Mixes `sound` into `buffer` at `at` seconds (clipped at the end).
static func _stamp(buffer: PackedFloat32Array, sound: PackedFloat32Array, at: float, gain: float) -> void:
	var start := int(at * RATE)
	for n in mini(sound.size(), buffer.size() - start):
		buffer[start + n] += sound[n] * gain


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


## One cycle of a soft saw (eight harmonics), for cheap oscillators: a table
## read per sample instead of a sum of sines.
static func _saw_table() -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(SAW_TABLE)
	for i in SAW_TABLE:
		var phase := TAU * i / SAW_TABLE
		var value := 0.0
		for k in range(1, 9):
			value += sin(phase * k) / k
		table[i] = value * 0.55
	return table


## A drone that loops seamlessly: each partial is nudged to a whole number of
## cycles over the loop, with a slow swell.
static func _drone(buffer: PackedFloat32Array, length: float, partials: Array, amplitude: float) -> void:
	var tuned := []
	for hz: float in partials:
		tuned.append(round(hz * length) / length)
	for i in buffer.size():
		var t := float(i) / RATE
		var swell := 0.75 + 0.25 * sin(TAU * t / length * 2.0)
		var value := 0.0
		for p in tuned.size():
			value += sin(TAU * float(tuned[p]) * t) / (p + 1)
		buffer[i] += value * amplitude * swell


## A short choked pulse of the saw through a one-pole low-pass (the bass ostinato).
static func _pulse(buffer: PackedFloat32Array, table: PackedFloat32Array, at: float, hz: float, seconds: float,
		amplitude: float, cutoff: float) -> void:
	var start := int(at * RATE)
	var length := mini(buffer.size() - start, int(seconds * RATE))
	var step := hz * SAW_TABLE / RATE
	var phase := 0.0
	var low := 0.0
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	for n in length:
		var t := float(n) / RATE
		low += a * (table[int(phase) % SAW_TABLE] - low)
		phase += step
		buffer[start + n] += low * amplitude * minf(t / 0.003, 1.0) * exp(-t * 9.0)


## A slow-swelling pad voice: two detuned saws through a low-pass.
static func _pad(buffer: PackedFloat32Array, table: PackedFloat32Array, at: float, hz: float, seconds: float,
		amplitude: float, cutoff: float, rng: RandomNumberGenerator) -> void:
	var start := int(at * RATE)
	var length := mini(buffer.size() - start, int(seconds * RATE))
	var steps := [hz * (1.0 - 0.003) * SAW_TABLE / RATE, hz * (1.0 + 0.003) * SAW_TABLE / RATE]
	var phases := [rng.randf() * SAW_TABLE, rng.randf() * SAW_TABLE]
	var low := 0.0
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var attack := seconds * 0.35
	var release := seconds * 0.4
	for n in length:
		var t := float(n) / RATE
		var raw := table[int(phases[0]) % SAW_TABLE] + table[int(phases[1]) % SAW_TABLE]
		phases[0] += steps[0]
		phases[1] += steps[1]
		low += a * (raw - low)
		var envelope := minf(t / attack, 1.0) * minf((seconds - t) / release, 1.0)
		buffer[start + n] += low * amplitude * envelope


## Tremolo strings: a pad voice whose level flutters at 7 Hz.
static func _tremolo(buffer: PackedFloat32Array, table: PackedFloat32Array, at: float, hz: float, seconds: float,
		amplitude: float, rng: RandomNumberGenerator) -> void:
	var scratch := PackedFloat32Array()
	scratch.resize(int(seconds * RATE) + 1)
	_pad(scratch, table, 0.0, hz, seconds, amplitude, 1400.0, rng)
	var start := int(at * RATE)
	for n in mini(scratch.size(), buffer.size() - start):
		buffer[start + n] += scratch[n] * (0.6 + 0.4 * sin(TAU * 7.0 * float(n) / RATE))


## A big low drum: a pitch-dropping body, a skin slap and a short room tail.
static func _war_drum(buffer: PackedFloat32Array, at: float, hz: float, loudness: float, rng: RandomNumberGenerator) -> void:
	ProceduralAudio.add_thump(buffer, at, hz, 0.16, 0.9 * loudness)
	ProceduralAudio.add_noise(buffer, at, 0.025, 0.3 * loudness, 1800.0, 120.0, rng)
	ProceduralAudio.add_noise(buffer, at + 0.02, 0.18, 0.08 * loudness, 600.0, 0.0, rng)


## Rising noise swell (filtered breath getting brighter) from `from` to `to` seconds.
static func _riser(buffer: PackedFloat32Array, from: float, to: float, rng: RandomNumberGenerator) -> void:
	var start := int(from * RATE)
	var length := mini(buffer.size() - start, int((to - from) * RATE))
	var low := 0.0
	for n in length:
		var t := float(n) / length
		var a := 1.0 - exp(-TAU * lerpf(200.0, 5000.0, t * t) / RATE)
		low += a * (rng.randf_range(-1.0, 1.0) - low)
		buffer[start + n] += low * 0.35 * t * t


static func _loop(stream: AudioStreamWAV, samples: int) -> void:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
