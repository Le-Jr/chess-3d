class_name MenuMusic
extends Node
## Background music for the main menu: a looping medieval piece in D dorian
## for lute, wooden flute, a hurdy-gurdy drone and a tabor, composed and
## synthesized in code with the voices of Sfx.
##
## To use your own track instead, put a file named `menu_music.ogg`, `.mp3`
## or `.wav` in `res://audio/` (or `user://audio/`); it is looped and played
## in place of the generated piece.
##
## Composing takes a few seconds, so it happens on a worker thread and the
## result is cached in `user://` - only the first launch has to wait. The
## music fades in when it is ready.

const MIX_RATE := 22050
const BEAT := 0.6          # seconds per quarter note (100 bpm)
const BARS := 16
const VOLUME_DB := -11.0
const CACHE_FILE := "user://menu_music_v1.pcm"
const CUSTOM_DIRS := ["res://audio", "user://audio"]
const CUSTOM_NAMES := ["menu_music.ogg", "menu_music.mp3", "menu_music.wav"]

# One bar of harmony each: the notes (MIDI numbers) the lute and bass draw on.
const CHORD_DM := [50, 57, 62, 65]
const CHORD_C := [48, 55, 60, 64]
const CHORD_F := [53, 60, 65, 69]
const CHORD_G := [55, 62, 67, 71]
const CHORD_AM := [57, 64, 69, 72]
const HARMONY := [
	CHORD_DM, CHORD_DM, CHORD_C, CHORD_DM, CHORD_F, CHORD_C, CHORD_DM, CHORD_AM,
	CHORD_DM, CHORD_DM, CHORD_C, CHORD_DM, CHORD_F, CHORD_G, CHORD_AM, CHORD_DM,
]

# The tune, as (MIDI note, length in eighth notes) pairs; 8 eighths to a bar.
# First half: the lute alone.
const LUTE_TUNE := [
	62, 2, 69, 2, 69, 1, 67, 1, 65, 2,
	64, 1, 65, 1, 67, 2, 69, 4,
	72, 2, 71, 1, 69, 1, 67, 2, 64, 2,
	65, 1, 64, 1, 62, 2, 62, 4,
	65, 2, 69, 2, 72, 2, 69, 2,
	67, 1, 69, 1, 67, 1, 64, 1, 60, 2, 64, 2,
	62, 2, 65, 1, 64, 1, 62, 2, 60, 2,
	64, 1, 65, 1, 64, 2, 57, 4,
]
# Second half: the flute sings over the lute's broken chords.
const FLUTE_TUNE := [
	69, 4, 74, 4,
	72, 2, 74, 2, 76, 4,
	76, 2, 74, 2, 72, 2, 67, 2,
	69, 3, 72, 1, 74, 4,
	77, 4, 76, 2, 72, 2,
	74, 2, 71, 2, 67, 4,
	69, 2, 72, 2, 76, 2, 72, 2,
	74, 8,
]
const ARPEGGIO := [0, 1, 2, 3, 2, 1, 2, 1]

static var _stream: AudioStream
static var _mutex := Mutex.new()
static var _started := false

var _player: AudioStreamPlayer
var _fade: Tween


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -60.0
	add_child(_player)
	set_enabled(GameSettings.music)


## Starts (or stops) the music; it fades in as soon as it is available.
func set_enabled(enabled: bool) -> void:
	if enabled:
		if _stream == null and not _started and DisplayServer.get_name() != "headless":
			_started = true
			_stream = load_custom()
			if _stream == null:
				WorkerThreadPool.add_task(_prepare, false, "Composing the menu music")
		set_process(true)
	else:
		set_process(false)
		_fade_to(-60.0, 0.4, true)


func _process(_delta: float) -> void:
	if not _mutex.try_lock():
		return
	var stream := _stream
	_mutex.unlock()
	if stream == null:
		return
	set_process(false)
	if _player.stream != stream:
		_player.stream = stream
	if not _player.playing:
		_player.volume_db = -60.0
		_player.play()
	_fade_to(VOLUME_DB, 2.5, false)


## Fades the music out (before leaving the menu).
func fade_out(time: float = 0.5) -> void:
	set_process(false)
	_fade_to(-60.0, time, true)


func _fade_to(volume_db: float, time: float, stop_after: bool) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if not is_inside_tree():
		return
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", volume_db, time)
	if stop_after:
		_fade.tween_callback(_player.stop)


# ----------------------------------------------------------------- source ---

## A track supplied by the user (see the class description), or null.
static func load_custom() -> AudioStream:
	for dir: String in CUSTOM_DIRS:
		for file_name: String in CUSTOM_NAMES:
			var path := dir.path_join(file_name)
			var stream: AudioStream = null
			if path.begins_with("res://"):
				if ResourceLoader.exists(path):
					stream = load(path) as AudioStream
			elif FileAccess.file_exists(path):
				match path.get_extension():
					"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
					"mp3": stream = AudioStreamMP3.load_from_file(path)
					"wav": stream = AudioStreamWAV.load_from_file(path)
			if stream == null:
				continue
			if stream is AudioStreamWAV:
				var wav := stream as AudioStreamWAV
				if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
					wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
					var bytes_per_frame := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) \
							* (2 if wav.stereo else 1)
					@warning_ignore("integer_division")
					wav.loop_end = wav.data.size() / bytes_per_frame
			elif "loop" in stream:
				stream.set("loop", true)
			return stream
	return null


# Worker thread: the cached piece if there is one, otherwise compose it.
static func _prepare() -> void:
	var data := PackedByteArray()
	if FileAccess.file_exists(CACHE_FILE):
		data = FileAccess.get_file_as_bytes(CACHE_FILE)
	if data.size() != expected_bytes(BARS):
		data = _to_pcm(compose(BARS))
		var file := FileAccess.open(CACHE_FILE, FileAccess.WRITE)
		if file != null:
			file.store_buffer(data)
			file.close()
	var stream := make_stream(data)
	_mutex.lock()
	_stream = stream
	_mutex.unlock()


static func expected_bytes(bars: int) -> int:
	return int(bars * 4 * BEAT * MIX_RATE) * 2


## Wraps 16-bit mono PCM in a stream that loops over its whole length.
static func make_stream(pcm: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = pcm
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	@warning_ignore("integer_division")
	stream.loop_end = pcm.size() / 2
	return stream


static func _to_pcm(samples: PackedFloat32Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return data


# ------------------------------------------------------------ composition ---

## The piece as samples (-1..1), `bars` bars long, written so that the end
## runs straight back into the beginning: notes and reverb that ring past
## the last bar are folded onto the first.
static func compose(bars: int = BARS) -> PackedFloat32Array:
	var eighth := BEAT * 0.5
	var bar := BEAT * 4.0
	var total := int(bars * bar * MIX_RATE)
	var mix := PackedFloat32Array()
	mix.resize(total)

	# Drone: the open fifth D-A of a hurdy-gurdy, under everything.
	_add_drone(mix, _midi(38), 0.085)
	_add_drone(mix, _midi(45), 0.060)
	_add_drone(mix, _midi(50), 0.030)

	for b in bars:
		var chord: Array = HARMONY[b % HARMONY.size()]
		var start := b * bar
		var second_half := (b % HARMONY.size()) >= 8
		# Bass: the root on one, the fifth on three.
		_add(mix, Sfx._pluck(_midi(chord[0] - 12), 1.3, 0.30), start, 0.50)
		_add(mix, Sfx._pluck(_midi(chord[1] - 12), 1.0, 0.30), start + BEAT * 2.0, 0.36)
		# Tabor: a soft pulse that fills out after the first four bars.
		_add(mix, _tabor(88.0, 0.40), start, 0.34)
		if b % HARMONY.size() >= 4:
			_add(mix, _tabor(88.0, 0.30), start + BEAT * 2.0, 0.22)
			_add(mix, _tabor(260.0, 0.10), start + BEAT * 1.5, 0.10)
			_add(mix, _tabor(260.0, 0.10), start + BEAT * 3.5, 0.12)
		if second_half:
			# The lute breaks the chord into eighths.
			for k in ARPEGGIO.size():
				var note: int = chord[ARPEGGIO[k]]
				_add(mix, Sfx._pluck(_midi(note), 0.75, 0.50), start + k * eighth,
						0.30 if k % 2 == 0 else 0.22)

	# The tunes.
	var t := 0.0
	for i in range(0, LUTE_TUNE.size(), 2):
		var length: float = LUTE_TUNE[i + 1] * eighth
		if t < bars * bar:
			_add(mix, Sfx._pluck(_midi(LUTE_TUNE[i]), minf(length + 0.55, 1.5), 0.62), t, 0.62)
		t += length
	t = 8 * bar
	for i in range(0, FLUTE_TUNE.size(), 2):
		var length: float = FLUTE_TUNE[i + 1] * eighth
		if t < bars * bar:
			_add(mix, _flute(_midi(FLUTE_TUNE[i]), length), t, 0.36)
		t += length

	# A stone hall, with its tail carried over the loop point.
	var wet := Sfx._reverb(mix, 0.42, 2.0)
	for i in range(total, wet.size()):
		wet[i - total] += wet[i]
	wet.resize(total)
	return Sfx._normalize(wet, 0.80)


static func _midi(note: int) -> float:
	return 440.0 * pow(2.0, (note - 69) / 12.0)


# Adds `src` at `at` seconds, wrapping past the end back to the start.
static func _add(mix: PackedFloat32Array, src: PackedFloat32Array, at: float, gain: float) -> void:
	var total := mix.size()
	var index := int(at * MIX_RATE) % total
	for i in src.size():
		mix[index] += src[i] * gain
		index += 1
		if index == total:
			index = 0


# A buzzing, slowly breathing string tone. The pitch is nudged so a whole
# number of cycles fits the piece and the loop point is seamless.
static func _add_drone(mix: PackedFloat32Array, pitch: float, gain: float) -> void:
	var total := mix.size()
	var seconds := float(total) / MIX_RATE
	var step := TAU * roundf(pitch * seconds) / total
	var swell := TAU * roundf(0.11 * seconds) / total
	for i in total:
		var p := step * i
		var v := sin(p) + 0.50 * sin(p * 2.0) + 0.34 * sin(p * 3.0) + 0.20 * sin(p * 4.0) \
				+ 0.12 * sin(p * 5.0)
		mix[i] += v * gain * (0.78 + 0.22 * sin(swell * i))


# A small drum struck with one stick.
static func _tabor(pitch: float, length: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pitch)
	var out := PackedFloat32Array()
	var low := 0.0
	var phase := 0.0
	var count := int(length * MIX_RATE)
	for i in count:
		var t := float(i) / MIX_RATE
		phase += TAU * pitch * (1.0 + 0.8 * exp(-t * 40.0)) / MIX_RATE
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.25)
		var fade := minf(1.0, (count - i) / 300.0)
		out.append((sin(phase) * exp(-t * 13.0) + low * exp(-t * 60.0) * 0.5) * fade)
	return out


# A wooden flute: a nearly pure tone with a breath of noise, a soft start
# and a vibrato that comes in on held notes.
static func _flute(pitch: float, length: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pitch * 7.0)
	var out := PackedFloat32Array()
	var phase := 0.0
	var breath := 0.0
	var sound := length * 0.94
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		var attack := minf(1.0, t / 0.06)
		var release := clampf((sound - t) / 0.09, 0.0, 1.0)
		var vibrato := 1.0 + 0.006 * sin(TAU * 5.0 * t) * clampf((t - 0.25) * 3.0, 0.0, 1.0)
		phase += TAU * pitch * vibrato / MIX_RATE
		breath = lerpf(breath, rng.randf_range(-1.0, 1.0), 0.5)
		var tone := sin(phase) + 0.22 * sin(phase * 2.0) + 0.09 * sin(phase * 3.0)
		out.append((tone + breath * (0.10 + 0.35 * exp(-t * 30.0))) * attack * release)
	return out
