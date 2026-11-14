class_name Sfx
extends Node
## Sound effects with a medieval voice, all synthesized in code (no audio
## files): a heavy piece set down on oak, steel on steel for a capture, a
## church bell for check, a lute for promotion, and war drums, a horn call
## and a tolling bell for checkmate - played in a stone hall (a small
## reverb). Add one to the scene and call play().
##
## The sounds take a moment to compute, so they are generated on a worker
## thread when the first Sfx enters the tree; a sound that is not ready yet
## is simply skipped.

enum Sound { MOVE, CAPTURE, CHECK, GAME_OVER, PROMOTE, CHECKMATE, START, SELECT }

const MIX_RATE := 22050

# Pitches (Hz) of the D dorian notes used below.
const D2 := 73.42
const A2 := 110.0
const D3 := 146.83
const F3 := 174.61
const G3 := 196.0
const A3 := 220.0
const C4 := 261.63
const D4 := 293.66
const E4 := 329.63
const F4 := 349.23
const G4 := 392.0
const A4 := 440.0
const C5 := 523.25
const D5 := 587.33

static var _streams := {}
static var _mutex := Mutex.new()
static var _warming := false

var _players := {}


func _ready() -> void:
	for sound: int in Sound.values():
		var player := AudioStreamPlayer.new()
		player.volume_db = -6.0
		add_child(player)
		_players[sound] = player
	warm_up()


func play(sound: Sound) -> void:
	if not GameSettings.sound or not _players.has(sound):
		return
	var player: AudioStreamPlayer = _players[sound]
	if player.stream == null:
		# Never wait for the generator: skip the sound if it is still busy.
		if not _mutex.try_lock():
			return
		player.stream = _streams.get(sound)
		_mutex.unlock()
		if player.stream == null:
			return
	var varied := sound == Sound.MOVE or sound == Sound.CAPTURE or sound == Sound.SELECT
	player.pitch_scale = randf_range(0.93, 1.07) if varied else 1.0
	player.play()


## Starts generating the sounds in the background (once). Call it early -
## the menu does - so they are ready by the time they are needed.
static func warm_up() -> void:
	if not _warming:
		_warming = true
		WorkerThreadPool.add_task(_generate_all, false, "Synthesizing sound effects")


# The sounds needed first come first.
static func _generate_all() -> void:
	for sound: int in [Sound.SELECT, Sound.MOVE, Sound.START, Sound.CAPTURE, Sound.CHECK,
			Sound.PROMOTE, Sound.CHECKMATE, Sound.GAME_OVER]:
		stream_for(sound)


## The generated stream for a sound (cached; blocks while it is computed).
static func stream_for(sound: int) -> AudioStreamWAV:
	_mutex.lock()
	if not _streams.has(sound):
		_streams[sound] = _to_stream(_normalize(_synthesize(sound), _peak_for(sound)))
	var stream: AudioStreamWAV = _streams[sound]
	_mutex.unlock()
	return stream


static func _peak_for(sound: int) -> float:
	match sound:
		Sound.SELECT: return 0.22
		Sound.MOVE: return 0.62
		Sound.CHECK, Sound.PROMOTE, Sound.GAME_OVER: return 0.60
		Sound.START: return 0.70
	return 0.92


static func _synthesize(sound: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	match sound:
		Sound.MOVE:
			# A carved piece set down on an oak board.
			_mix(out, _thunk(118.0, 0.24), 0.0, 1.0)
			return _reverb(out, 0.10, 0.25)
		Sound.SELECT:
			# A piece lifted: a light knock and a muted string.
			_mix(out, _thunk(310.0, 0.07), 0.0, 0.5)
			_mix(out, _pluck(D5, 0.22, 0.35), 0.0, 0.6)
			return out
		Sound.CAPTURE:
			# Steel on steel, the blow itself, and the victim breaking.
			_mix(out, _clang(1180.0, 0.75, 21), 0.0, 1.0)
			_mix(out, _clang(1730.0, 0.50, 22), 0.035, 0.55)
			_mix(out, _drum(74.0, 0.45, 23), 0.0, 1.0)
			_mix(out, _rubble(0.42, 24), 0.03, 0.75)
			return _reverb(out, 0.26, 0.7)
		Sound.CHECK:
			# One stroke of a church bell: a warning.
			_mix(out, _bell(D4, 2.1, 1.5, 31), 0.0, 1.0)
			return _reverb(out, 0.30, 0.9)
		Sound.PROMOTE:
			# A lute flourish rising in open fifths, with a small bell on top.
			var t := 0.0
			for note: float in [D4, A4, D5, A4 * 2.0]:
				_mix(out, _pluck(note, 0.95, 0.6), t, 0.9)
				t += 0.085
			_mix(out, _bell(D5 * 2.0, 0.9, 4.5, 41), 0.30, 0.22)
			return _reverb(out, 0.28, 0.8)
		Sound.START:
			# The armies take the field: two drum strokes and a short horn call.
			_mix(out, _drum(64.0, 0.6, 51), 0.0, 1.0)
			_mix(out, _drum(64.0, 0.6, 52), 0.26, 0.8)
			_mix(out, _horn(D3, 0.26), 0.42, 0.55)
			_mix(out, _horn(A3, 0.70), 0.66, 0.60)
			return _reverb(out, 0.30, 1.0)
		Sound.GAME_OVER:
			# A draw: the lute lets a phrase fall and a far bell answers.
			var t := 0.0
			for note: float in [A4, G4, F4, D4]:
				_mix(out, _pluck(note, 1.3, 0.5), t, 0.9)
				t += 0.24
			_mix(out, _pluck(D3, 1.6, 0.4), t - 0.24, 0.8)
			_mix(out, _bell(A3, 1.6, 2.2, 61), t + 0.05, 0.28)
			return _reverb(out, 0.32, 1.1)
		Sound.CHECKMATE:
			# The king falls: war drums, a tolling bell and a horn fanfare.
			_mix(out, _drum(52.0, 1.1, 71), 0.0, 1.0)
			_mix(out, _clang(820.0, 0.9, 72), 0.0, 0.35)
			_mix(out, _bell(D3, 3.6, 0.85, 73), 0.05, 0.85)
			_mix(out, _drum(52.0, 0.9, 74), 0.62, 0.75)
			_mix(out, _drum(58.0, 0.9, 75), 0.92, 0.85)
			_mix(out, _horn(D3, 0.34), 1.05, 0.50)
			_mix(out, _horn(D3, 0.16), 1.43, 0.50)
			_mix(out, _horn(A3, 0.42), 1.62, 0.58)
			_mix(out, _horn(D4, 1.25), 2.06, 0.62)
			_mix(out, _horn(A3, 1.25), 2.06, 0.34)
			_mix(out, _drum(52.0, 1.2, 76), 2.06, 1.0)
			_mix(out, _bell(D3, 2.6, 1.0, 77), 2.10, 0.65)
			return _reverb(out, 0.34, 1.6)
	return out


# ----------------------------------------------------------------- voices ---

# Adds `src` into `out` starting `at` seconds in, growing `out` as needed.
static func _mix(out: PackedFloat32Array, src: PackedFloat32Array, at: float, gain: float) -> void:
	var offset := int(at * MIX_RATE)
	if out.size() < offset + src.size():
		out.resize(offset + src.size())
	for i in src.size():
		out[offset + i] += src[i] * gain


# Wood: a low thump with two short resonances and the click of contact.
static func _thunk(pitch: float, length: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out := PackedFloat32Array()
	var low := 0.0
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.30)
		var body := sin(TAU * pitch * t * (1.0 + 0.5 * exp(-t * 70.0))) * exp(-t * 30.0)
		var wood := sin(TAU * pitch * 3.42 * t) * exp(-t * 58.0) * 0.34 \
				+ sin(TAU * pitch * 6.15 * t) * exp(-t * 85.0) * 0.18
		out.append(body + wood + low * exp(-t * 120.0) * 0.55)
	return out


# A struck blade: inharmonic partials that ring and beat, behind the hiss of
# the edges scraping.
static func _clang(pitch: float, length: float, random_seed: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var ratios := [1.0, 1.505, 2.32, 2.76, 3.41, 4.13, 5.43, 6.79]
	var phases := PackedFloat32Array()
	var detune := PackedFloat32Array()
	for k in ratios.size():
		phases.append(rng.randf() * TAU)
		detune.append(rng.randf_range(0.994, 1.006))
	var out := PackedFloat32Array()
	var previous := 0.0
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		var v := 0.0
		for k in ratios.size():
			var ratio: float = ratios[k]
			v += sin(TAU * pitch * ratio * detune[k] * t + phases[k]) \
					* exp(-t * (5.0 + 2.6 * ratio)) / (1.0 + 0.35 * k)
		# High-passed noise: the scrape of the first contact.
		var noise := rng.randf_range(-1.0, 1.0)
		var hiss := (noise - previous) * exp(-t * 46.0) * 0.9
		previous = noise
		out.append((v * 0.55 + hiss) * minf(1.0, t * 3000.0))
	return out


# A big skin drum: a tone that drops as it sounds, and the slap of the stick.
static func _drum(pitch: float, length: float, random_seed: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var out := PackedFloat32Array()
	var low := 0.0
	var phase := 0.0
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		phase += TAU * pitch * (1.0 + 1.3 * exp(-t * 26.0)) / MIX_RATE
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.16)
		var tone := (sin(phase) + 0.28 * sin(phase * 1.59)) * exp(-t * 5.2)
		out.append(tone + low * exp(-t * 34.0) * 0.7)
	return out


# Stone and metal breaking up: a decaying rumble with a few sharp chips.
static func _rubble(length: float, random_seed: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var out := PackedFloat32Array()
	var low := 0.0
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.20)
		var chips := 0.0
		for start: float in [0.05, 0.11, 0.19, 0.27]:
			if t >= start:
				var u := t - start
				chips += sin(TAU * (2100.0 - start * 4200.0) * u) * exp(-u * 95.0) * 0.20
		out.append(low * exp(-t * 10.0) + chips)
	return out


# A cast bell: hum, prime, tierce, quint and nominal with their own decays,
# the low partials ringing longest.
static func _bell(pitch: float, length: float, decay: float, random_seed: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var ratios := [0.5, 1.0, 1.19, 1.5, 2.0, 2.51, 2.66, 3.01, 4.17, 5.43]
	var levels := [0.55, 1.0, 0.72, 0.36, 0.82, 0.24, 0.30, 0.20, 0.13, 0.08]
	var out := PackedFloat32Array()
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		var v := 0.0
		for k in ratios.size():
			var ratio: float = ratios[k]
			var level: float = levels[k]
			# A slow beat on each partial, as in a real, slightly uneven bell.
			var beat := 1.0 + 0.10 * sin(TAU * (0.7 + 0.31 * k) * t)
			v += sin(TAU * pitch * ratio * t) * level * beat * exp(-t * decay * (0.45 + 0.62 * ratio))
		var strike := rng.randf_range(-1.0, 1.0) * exp(-t * 240.0) * 0.6
		out.append((v + strike) * minf(1.0, t * 2500.0))
	return out


# A war horn: a buzzing tone that swells, brightens and wavers.
static func _horn(pitch: float, length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var phase := 0.0
	var count := int(length * MIX_RATE)
	for i in count:
		var t := float(i) / MIX_RATE
		var attack := minf(1.0, t / 0.07)
		var release := minf(1.0, (length - t) / 0.12)
		var envelope := attack * attack * (3.0 - 2.0 * attack) * maxf(release, 0.0)
		# The pitch scoops up into the note, then a slow vibrato sets in.
		var bend := 1.0 - 0.035 * exp(-t * 26.0) + 0.004 * sin(TAU * 5.2 * t) * minf(1.0, t * 3.0)
		phase += TAU * pitch * bend / MIX_RATE
		var bright := 0.45 + 0.55 * attack
		var v := 0.0
		for n in range(1, 10):
			v += sin(phase * n) * pow(bright, n - 1) / pow(n, 0.85)
		out.append(v * envelope * 0.5)
	return out


# A plucked gut string (Karplus-Strong): a burst of noise circulating in a
# delay line that slowly averages itself into a tone.
static func _pluck(pitch: float, length: float, brightness: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pitch * 10.0)
	var period := maxi(2, roundi(MIX_RATE / pitch))
	var line := PackedFloat32Array()
	var smooth := 0.0
	for i in period:
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), brightness)
		line.append(smooth)
	var out := PackedFloat32Array()
	var count := int(length * MIX_RATE)
	var index := 0
	for i in count:
		var next := (index + 1) % period
		var v := line[index]
		line[index] = (v + line[next]) * 0.4985
		index = next
		out.append(v * minf(1.0, (count - i) / 600.0))
	return out


# ------------------------------------------------------------------- room ---

# A small stone hall: four feedback combs into two allpass filters (a
# Schroeder reverb), mixed under the dry sound. Adds `tail` seconds.
static func _reverb(dry: PackedFloat32Array, wet: float, tail: float) -> PackedFloat32Array:
	var total := dry.size() + int(tail * MIX_RATE)
	var feedback := 0.80 if tail > 0.5 else 0.68
	var comb_sum := PackedFloat32Array()
	comb_sum.resize(total)
	for delay: int in [557, 617, 673, 743]:
		var buffer := PackedFloat32Array()
		buffer.resize(delay)
		var damp := 0.0
		var index := 0
		for i in total:
			var delayed := buffer[index]
			# Stone absorbs the highs a little on every reflection.
			damp = lerpf(delayed, damp, 0.32)
			buffer[index] = (dry[i] if i < dry.size() else 0.0) + damp * feedback
			comb_sum[i] += delayed
			index += 1
			if index == delay:
				index = 0
	for delay: int in [278, 113]:
		var buffer := PackedFloat32Array()
		buffer.resize(delay)
		var index := 0
		for i in total:
			var delayed := buffer[index]
			var input := comb_sum[i]
			buffer[index] = input + delayed * 0.5
			comb_sum[i] = delayed - input * 0.5
			index += 1
			if index == delay:
				index = 0
	var out := PackedFloat32Array()
	out.resize(total)
	for i in total:
		out[i] = (dry[i] if i < dry.size() else 0.0) + comb_sum[i] * wet * 0.25
	return out


static func _normalize(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var loudest := 0.0
	for v in samples:
		loudest = maxf(loudest, absf(v))
	if loudest > 1e-6:
		var gain := peak / loudest
		for i in samples.size():
			samples[i] *= gain
	return samples


static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var fade := mini(400, samples.size())
	for i in samples.size():
		var v := samples[i]
		# Short fade-out so the sound never ends on a click.
		if i >= samples.size() - fade:
			v *= float(samples.size() - 1 - i) / fade
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
