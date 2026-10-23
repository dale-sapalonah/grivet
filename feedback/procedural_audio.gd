class_name ProceduralAudio
extends RefCounted
## Placeholder sound synthesis: gunshots, material impacts, ricochets,
## casings and weapon mechanics, built from noise bursts, damped modal rings
## and thumps. Every recipe reads its character from data (WeaponDefinition,
## SurfaceMaterial). Real recordings replace these in Milestone 5; callers
## only ever see AudioStreams, so nothing else changes then.

const MIX_RATE := 22050
const PEAK := 0.85

static var _cache: Dictionary = {}


## Builds once per key, then reuses (generation costs a few milliseconds).
## Main thread only; background builders hand results over with store().
static func cached(key: String, builder: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = builder.call()
	return _cache[key]


static func has(key: String) -> bool:
	return _cache.has(key)


static func store(key: String, stream: AudioStreamWAV) -> void:
	_cache[key] = stream


# --- Recipes -----------------------------------------------------------------

static func gunshot(weapon: WeaponDefinition) -> AudioStreamWAV:
	var rng := _rng("shot:" + weapon.id)
	var length := weapon.shot_sound_length
	var buffer := _buffer(length)
	add_noise(buffer, 0.0, length / 9.0, 0.6, 7000.0, 0.0, rng)
	add_thump(buffer, 0.0, weapon.shot_thump_hz, length / 5.0, 0.8)
	add_noise(buffer, 0.01, length / 3.0, 0.25, 900.0, 0.0, rng)  # muffled tail
	return to_stream(buffer)


## Cache key for an impact sound with mass and energy already quantized.
static func impact_key(surface: SurfaceMaterial, outcome: String, mass: float, energy: float,
		variant: int) -> String:
	return "impact:%s:%s:%.2f:%.2f:%d" % [surface.id, outcome, mass, energy, variant]


## A bullet strike, built from what physically happens:
##   outcome - "penetrated", "stopped" or "ricochet"
##   mass    - 0 thin/light .. 1 thick/dense/solid (SurfaceMaterial.mass_factor)
##   energy  - 0..1 the round's remaining energy (BallisticsMath.impact_energy)
## Pure function of its inputs (safe to call from a worker thread).
static func impact(surface: SurfaceMaterial, outcome: String, mass: float, energy: float,
		variant: int) -> AudioStreamWAV:
	var rng := _rng(impact_key(surface, outcome, mass, energy, variant))
	match surface.acoustic_type:
		SurfaceMaterial.AcousticType.METAL:
			return _metal_impact(surface, outcome, mass, energy, rng)
		SurfaceMaterial.AcousticType.WOOD:
			return _wood_impact(surface, outcome, mass, energy, rng)
		SurfaceMaterial.AcousticType.MASONRY:
			return _masonry_impact(surface, outcome, energy, rng)
	return _soft_impact(energy, rng)


## Steel: a struck plate, not a bell. Inharmonic plate modes whose pitch rises
## and decay shortens with areal density (thin sheet rings briefly, thick
## plate barely rings and thunks instead). A round passing through leaves
## with much of the energy (short punch, weaker ring); a stopped round
## splatters; a glancing hit excites the plate without dumping energy into
## it, so it resonates longer, with a scrape along the face.
static func _metal_impact(surface: SurfaceMaterial, outcome: String, mass: float, energy: float,
		rng: RandomNumberGenerator) -> AudioStreamWAV:
	var ricochet := outcome == "ricochet"
	var ring_hz := lerpf(surface.ring_low_hz, surface.ring_high_hz, mass) * rng.randf_range(0.97, 1.03)
	var decay := lerpf(surface.ring_decay_thin, surface.ring_decay_thick, mass)
	if ricochet:
		decay *= surface.ricochet_ring_multiplier
	var buffer := _buffer(minf(decay * 6.0 + 0.06, 1.5))
	add_noise(buffer, 0.0, 0.003, 0.8, 9000.0, 1800.0, rng)  # hard contact
	var ring_level := lerpf(1.0, 0.3, mass) * lerpf(0.6, 1.0, energy)
	if outcome == "penetrated":
		ring_level *= 0.7
	var modes := PackedFloat32Array()
	for ratio in [1.0, 1.59, 2.14, 2.65, 3.16, 3.5]:
		modes.append(ring_hz * ratio * rng.randf_range(0.99, 1.01))
	add_ring(buffer, 0.0, modes, decay, ring_level)
	if ricochet:
		add_noise(buffer, 0.0, 0.03, 0.35, 6000.0, 1800.0, rng, 0.01)  # scrape along the face
	else:
		add_thump(buffer, 0.0, lerpf(200.0, 120.0, mass), 0.03,
				lerpf(0.25, 1.0, mass) * lerpf(0.6, 1.0, energy))
		if outcome == "penetrated":
			add_noise(buffer, 0.0, 0.0025, 1.0, 10000.0, 3000.0, rng)  # punch-through crack
		else:
			add_noise(buffer, 0.001, 0.012, 0.5, 4000.0, 800.0, rng)  # lead splatter
	return to_stream(buffer)


## Wood: a thin board knocks hollowly and splinters, a crackle of fibres
## breaking in quick succession (more with heavier rounds and when the round
## tears through). Dense wood (a trunk, a pillar) takes the round with a
## dull, low thud and little high end.
static func _wood_impact(surface: SurfaceMaterial, outcome: String, mass: float, energy: float,
		rng: RandomNumberGenerator) -> AudioStreamWAV:
	var thin := 1.0 - mass
	var buffer := _buffer(0.35)
	add_noise(buffer, 0.0, 0.004, 0.7, 6000.0, 800.0, rng)  # initial crack
	if thin > 0.0:
		var knock := surface.panel_knock_hz * rng.randf_range(0.95, 1.05)
		add_ring(buffer, 0.0, PackedFloat32Array([knock, knock * 2.3, knock * 3.9]),
				lerpf(0.03, 0.06, thin), 0.8 * thin)
	var splinters := surface.splinter_count * thin * lerpf(0.4, 1.0, energy)
	if outcome == "penetrated":
		splinters *= 1.3
	add_grains(buffer, 0.002, 0.07, roundi(splinters), 0.002, 0.006, 1500.0, 8000.0, 0.3, 0.8, rng)
	add_thump(buffer, 0.0, lerpf(surface.thud_hz * 1.6, surface.thud_hz, mass), 0.04, lerpf(0.35, 1.0, mass))
	add_noise(buffer, 0.0, 0.03, 0.5 * mass, 900.0, 0.0, rng)  # dense, muffled body
	return to_stream(buffer)


## Concrete: shatters at the point of impact (a sharp crack and the body of
## the break), dust bursts out (a short hiss), then debris patters down.
## Light rounds mostly powder it: a little fine grit. Heavy rounds crack it
## into rubble: much more grit, falling for longer, plus larger chunks.
static func _masonry_impact(surface: SurfaceMaterial, outcome: String, energy: float,
		rng: RandomNumberGenerator) -> AudioStreamWAV:
	var debris := 0.3 if outcome == "ricochet" else 1.0  # a glancing hit only scuffs
	var seconds := lerpf(surface.crumble_seconds_light, surface.crumble_seconds_heavy, energy) * debris
	var buffer := _buffer(seconds + 0.2)
	add_noise(buffer, 0.0, 0.0025, lerpf(0.6, 1.0, energy), 10000.0, 1200.0, rng)  # shatter
	add_noise(buffer, 0.0, 0.006, 0.6, 3500.0, 300.0, rng)  # body of the break
	add_thump(buffer, 0.0, 100.0 * rng.randf_range(0.9, 1.1), 0.04, 0.6)
	add_noise(buffer, 0.005, lerpf(0.04, 0.12, energy) * debris, 0.25, 5000.0, 1500.0, rng, 0.01)  # powder
	var grains := roundi(lerpf(surface.crumble_grains_light, surface.crumble_grains_heavy, energy) * debris)
	add_grains(buffer, 0.01, seconds, grains, 0.0015, 0.004, 1500.0, lerpf(7000.0, 4000.0, energy), 0.15, 0.5, rng)
	var chunks := roundi(surface.chunk_count * smoothstep(0.4, 1.0, energy) * debris)
	for i in chunks:
		var at := 0.03 + seconds * rng.randf() * 0.8
		var hz := rng.randf_range(700.0, 1300.0)
		add_ring(buffer, at, PackedFloat32Array([hz, hz * 1.7]), 0.008, rng.randf_range(0.3, 0.6))
		add_noise(buffer, at, 0.003, 0.3, 5000.0, 500.0, rng)
	return to_stream(buffer)


## Bodies and earth absorb the round: a muffled thump.
static func _soft_impact(energy: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var buffer := _buffer(0.3)
	add_thump(buffer, 0.0, 80.0 * rng.randf_range(0.9, 1.1), 0.07, 1.0)
	add_noise(buffer, 0.0, 0.05, lerpf(0.4, 0.7, energy), 700.0, 0.0, rng)
	return to_stream(buffer)


static func ricochet(variant: int) -> AudioStreamWAV:
	var rng := _rng("ricochet:%d" % variant)
	var buffer := _buffer(0.45)
	add_noise(buffer, 0.0, 0.006, 0.7, 8000.0, 1500.0, rng)
	add_sweep(buffer, 0.01, rng.randf_range(3000.0, 3800.0), rng.randf_range(900.0, 1300.0), 0.4, 0.6)
	return to_stream(buffer)


## Metallic click: the building block of every mechanism sound.
static func add_click(buffer: PackedFloat32Array, at: float, hz: float, amplitude: float,
		rng: RandomNumberGenerator) -> void:
	add_noise(buffer, at, 0.004, amplitude * 0.8, 9000.0, 1500.0, rng)
	add_ring(buffer, at, PackedFloat32Array([hz, hz * 1.63, hz * 2.71]), 0.014, amplitude)


static func magazine_out(weapon: WeaponDefinition) -> AudioStreamWAV:
	var rng := _rng("mag_out:" + weapon.id)
	var buffer := _buffer(0.16)
	add_click(buffer, 0.0, weapon.mech_click_hz, 0.8, rng)
	add_noise(buffer, 0.015, 0.06, 0.3, 2500.0, 300.0, rng, 0.03)  # magazine sliding out
	return to_stream(buffer)


static func magazine_in(weapon: WeaponDefinition) -> AudioStreamWAV:
	var rng := _rng("mag_in:" + weapon.id)
	var buffer := _buffer(0.2)
	add_noise(buffer, 0.0, 0.04, 0.25, 2000.0, 300.0, rng, 0.04)  # sliding in
	add_thump(buffer, 0.06, 170.0, 0.03, 0.9)
	add_click(buffer, 0.06, weapon.mech_click_hz * 0.9, 1.0, rng)
	return to_stream(buffer)


static func bolt_release(weapon: WeaponDefinition) -> AudioStreamWAV:
	var rng := _rng("bolt:" + weapon.id)
	var buffer := _buffer(0.22)
	add_click(buffer, 0.0, weapon.mech_click_hz * 1.2, 0.6, rng)
	add_ring(buffer, 0.0, PackedFloat32Array([weapon.mech_click_hz * 0.35]), 0.08, 0.25)  # spring
	add_thump(buffer, 0.03, 210.0, 0.03, 0.9)
	add_click(buffer, 0.03, weapon.mech_click_hz, 1.0, rng)
	return to_stream(buffer)


## Pump pulled back: slide rasp ending on the rear stop.
static func rack_back(weapon: WeaponDefinition) -> AudioStreamWAV:
	var rng := _rng("rack_back:" + weapon.id)
	var buffer := _buffer(0.24)
	add_noise(buffer, 0.0, 0.05, 0.4, 3200.0, 700.0, rng, 0.09)
	add_thump(buffer, 0.11, 140.0, 0.04, 0.8)
	add_ring(buffer, 0.11, PackedFloat32Array([weapon.mech_click_hz * 0.7, weapon.mech_click_hz * 1.2]), 0.03, 0.8)
	add_click(buffer, 0.11, weapon.mech_click_hz, 0.6, rng)
	return to_stream(buffer)


## Pump driven home: the heavier "CHK" that locks the breech.
static func rack_forward(weapon: WeaponDefinition) -> AudioStreamWAV:
	var rng := _rng("rack_forward:" + weapon.id)
	var buffer := _buffer(0.24)
	add_noise(buffer, 0.0, 0.04, 0.35, 3000.0, 700.0, rng, 0.06)
	add_thump(buffer, 0.07, 115.0, 0.05, 1.0)
	add_ring(buffer, 0.07, PackedFloat32Array([weapon.mech_click_hz * 0.8, weapon.mech_click_hz * 1.5,
			weapon.mech_click_hz * 2.4]), 0.04, 1.0)
	add_click(buffer, 0.075, weapon.mech_click_hz * 1.8, 0.7, rng)
	return to_stream(buffer)


static func shell_insert(weapon: WeaponDefinition) -> AudioStreamWAV:
	var rng := _rng("shell_insert:" + weapon.id)
	var buffer := _buffer(0.12)
	add_thump(buffer, 0.0, 260.0, 0.025, 0.7)
	add_click(buffer, 0.0, weapon.mech_click_hz * 0.6, 0.5, rng)
	add_noise(buffer, 0.03, 0.03, 0.2, 1500.0, 200.0, rng, 0.02)
	return to_stream(buffer)


## A spent case landing on `surface`: a few bouncing tinks, or null when the
## surface swallows the sound (casing_brightness 0, e.g. dirt or bodies).
static func casing_clink(weapon: WeaponDefinition, surface: SurfaceMaterial) -> AudioStreamWAV:
	if surface.casing_brightness <= 0.0:
		return null
	var rng := _rng("casing:%s:%s" % [weapon.id, surface.id])
	var brightness := surface.casing_brightness
	var hz := weapon.casing_clink_hz * lerpf(0.6, 1.0, minf(brightness, 1.0))
	var decay := 0.05 * brightness
	var buffer := _buffer(0.4)
	var at := 0.0
	var amplitude := 1.0
	for bounce in 3:
		add_noise(buffer, at, 0.003, amplitude * 0.5, 9000.0, 2000.0, rng)
		add_ring(buffer, at, PackedFloat32Array([hz, hz * 2.32, hz * 3.86]), decay, amplitude)
		hz *= rng.randf_range(0.99, 1.02)
		at += rng.randf_range(0.07, 0.11) * (1.0 - bounce * 0.3)
		amplitude *= 0.45
	return to_stream(buffer)


# --- Building blocks -----------------------------------------------------------

## Damped modal ring: each partial is quieter and dies faster than the last.
## Partials at or above Nyquist are skipped (they would alias).
static func add_ring(buffer: PackedFloat32Array, at: float, partials: PackedFloat32Array,
		decay: float, amplitude: float) -> void:
	var start := int(at * MIX_RATE)
	for p in partials.size():
		if partials[p] >= MIX_RATE * 0.5:
			continue
		var tau := decay / (1.0 + p * 0.5)
		var length := mini(buffer.size() - start, int(tau * 7.0 * MIX_RATE))
		# Sine by rotation recurrence and envelope by repeated multiply: far
		# cheaper than sin() and exp() per sample.
		var w := TAU * partials[p] / MIX_RATE
		var coefficient := 2.0 * cos(w)
		var previous := -sin(w)
		var current := 0.0
		var envelope := amplitude * pow(0.6, p)
		var fade := exp(-1.0 / (tau * MIX_RATE))
		for i in length:
			buffer[start + i] += current * envelope
			var next := coefficient * current - previous
			previous = current
			current = next
			envelope *= fade


## Noise burst through one-pole low/high-pass filters with an optional linear
## attack and exponential decay. highpass_hz 0 = no high-pass.
static func add_noise(buffer: PackedFloat32Array, at: float, decay: float, amplitude: float,
		lowpass_hz: float, highpass_hz: float, rng: RandomNumberGenerator, attack: float = 0.0) -> void:
	if amplitude <= 0.0 or decay <= 0.0:
		return
	var start := int(at * MIX_RATE)
	var attack_samples := int(attack * MIX_RATE)
	var low_a := 1.0 - exp(-TAU * lowpass_hz / MIX_RATE)
	var high_a := 1.0 - exp(-TAU * highpass_hz / MIX_RATE) if highpass_hz > 0.0 else 0.0
	var low := 0.0
	var high_state := 0.0
	var length := mini(buffer.size() - start, attack_samples + int(decay * 7.0 * MIX_RATE))
	var envelope := amplitude
	var fade := exp(-1.0 / (decay * MIX_RATE))
	for i in length:
		low += low_a * (rng.randf_range(-1.0, 1.0) - low)
		high_state += high_a * (low - high_state)
		if i < attack_samples:
			buffer[start + i] += (low - high_state) * amplitude * float(i) / attack_samples
		else:
			buffer[start + i] += (low - high_state) * envelope
			envelope *= fade


## Many tiny bursts scattered over `spread` seconds, front-loaded: splinters
## cracking, grit and powder pattering down. Later grains are quieter.
static func add_grains(buffer: PackedFloat32Array, at: float, spread: float, count: int,
		decay_min: float, decay_max: float, highpass_hz: float, lowpass_hz: float,
		amplitude_min: float, amplitude_max: float, rng: RandomNumberGenerator) -> void:
	for i in count:
		var position := pow(rng.randf(), 2.0)
		add_noise(buffer, at + spread * position, rng.randf_range(decay_min, decay_max),
				rng.randf_range(amplitude_min, amplitude_max) * (1.0 - 0.6 * position),
				lowpass_hz, highpass_hz, rng)


## Low sine body whose pitch drops from 1.6x to `hz` (a felt thud).
static func add_thump(buffer: PackedFloat32Array, at: float, hz: float, decay: float, amplitude: float) -> void:
	var start := int(at * MIX_RATE)
	var phase := 0.0
	var length := mini(buffer.size() - start, int(decay * 7.0 * MIX_RATE))
	for i in length:
		var t := float(i) / MIX_RATE
		var freq := hz * (1.0 + 0.6 * exp(-t / (decay * 0.5)))
		phase += TAU * freq / MIX_RATE
		buffer[start + i] += sin(phase) * amplitude * exp(-t / decay)


## Falling whine (ricochet), fading out over `length`.
static func add_sweep(buffer: PackedFloat32Array, at: float, from_hz: float, to_hz: float,
		length: float, amplitude: float) -> void:
	var start := int(at * MIX_RATE)
	var count := mini(buffer.size() - start, int(length * MIX_RATE))
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		var freq := lerpf(from_hz, to_hz, t) * (1.0 + 0.02 * sin(t * 70.0))
		phase += TAU * freq / MIX_RATE
		buffer[start + i] += sin(phase) * amplitude * (1.0 - t) * minf(t * 40.0, 1.0)


static func to_stream(buffer: PackedFloat32Array) -> AudioStreamWAV:
	var loudest := 0.0
	for sample in buffer:
		loudest = maxf(loudest, absf(sample))
	var scale := PEAK / loudest if loudest > 0.0 else 0.0
	var data := PackedByteArray()
	data.resize(buffer.size() * 2)
	for i in buffer.size():
		data.encode_s16(i * 2, int(clampf(buffer[i] * scale, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Seconds of sound from 16-bit mono data, for tests.
static func duration(stream: AudioStreamWAV) -> float:
	return stream.data.size() / 2.0 / stream.mix_rate


## RMS level of a stream between two times (seconds), for tests.
static func rms(stream: AudioStreamWAV, from: float, to: float) -> float:
	var first := int(from * stream.mix_rate)
	var last := mini(int(to * stream.mix_rate), stream.data.size() / 2)
	if last <= first:
		return 0.0
	var total := 0.0
	for i in range(first, last):
		var sample := stream.data.decode_s16(i * 2) / 32767.0
		total += sample * sample
	return sqrt(total / (last - first))


static func _buffer(seconds: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(maxi(1, int(seconds * MIX_RATE)))
	return buffer


static func _rng(key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng
