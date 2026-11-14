class_name Sfx
extends Node
## Sound effects, synthesized in code (no audio files): a wooden knock for a
## move, a crash for a capture, a bell for check and a chord at the end of
## the game. Add one to the scene and call play().

enum Sound { MOVE, CAPTURE, CHECK, GAME_OVER, PROMOTE }

const MIX_RATE := 22050

static var _streams := {}

var _players := {}


func _ready() -> void:
	for sound: int in Sound.values():
		var player := AudioStreamPlayer.new()
		player.stream = stream_for(sound)
		player.volume_db = -7.0
		add_child(player)
		_players[sound] = player


func play(sound: Sound) -> void:
	if not GameSettings.sound or not _players.has(sound):
		return
	var player: AudioStreamPlayer = _players[sound]
	player.pitch_scale = randf_range(0.94, 1.06) if sound == Sound.MOVE or sound == Sound.CAPTURE else 1.0
	player.play()


## The generated stream for a sound (cached).
static func stream_for(sound: int) -> AudioStreamWAV:
	if _streams.has(sound):
		return _streams[sound]
	var samples := PackedFloat32Array()
	match sound:
		Sound.MOVE:
			samples = _knock(0.13, 170.0, 0.55, 0.9)
		Sound.CAPTURE:
			samples = _crash()
		Sound.CHECK:
			samples = _tones([880.0, 1318.5], 0.55, 7.0, 0.30)
		Sound.GAME_OVER:
			samples = _tones([196.0, 246.9, 293.7, 392.0], 1.3, 2.6, 0.22)
		Sound.PROMOTE:
			samples = _tones([659.3, 987.8, 1318.5], 0.6, 5.5, 0.26)
	var stream := _to_stream(samples)
	_streams[sound] = stream
	return stream


# A piece set down on wood: a low thump plus a short filtered click.
static func _knock(length: float, pitch: float, noise_amount: float, gain: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out := PackedFloat32Array()
	var low := 0.0
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.35)
		var thump := sin(TAU * pitch * t * (1.0 + 0.6 * exp(-t * 60.0))) * exp(-t * 38.0)
		var click := low * exp(-t * 110.0) * noise_amount
		out.append((thump * 0.8 + click) * gain)
	return out


# A capture: a heavy hit, a burst of rubble and a couple of stony clacks.
static func _crash() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var out := PackedFloat32Array()
	var low := 0.0
	var length := 0.42
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.22)
		var hit := sin(TAU * 95.0 * t * (1.0 + 0.9 * exp(-t * 40.0))) * exp(-t * 16.0)
		var rubble := low * exp(-t * 11.0) * 0.85
		var clack := 0.0
		for start: float in [0.0, 0.07, 0.13]:
			if t >= start:
				var u := t - start
				clack += sin(TAU * (1250.0 - start * 3000.0) * u) * exp(-u * 85.0) * 0.22
		out.append(clampf(hit * 0.75 + rubble + clack, -1.0, 1.0) * 0.9)
	return out


# Bell-like tones played together, each with a soft overtone.
static func _tones(pitches: Array, length: float, decay: float, gain: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		var v := 0.0
		for k in pitches.size():
			var start := 0.06 * k
			if t >= start:
				var u := t - start
				var f: float = pitches[k]
				v += (sin(TAU * f * u) + 0.3 * sin(TAU * f * 2.0 * u)) * exp(-u * decay) \
						* minf(1.0, u * 400.0)
		out.append(v * gain)
	return out


static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var fade := mini(200, samples.size())
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
