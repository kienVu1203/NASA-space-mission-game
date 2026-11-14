extends Node
## Retro 8-bit audio synthesized at runtime. No sample files: a single
## AudioStreamGenerator is filled every frame with tone/noise voices.

const MIX_RATE := 22050.0

enum Wave { SINE, SQUARE, SAW, TRI, NOISE }

var muted: bool = false
var master: float = 0.55

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _voices: Array = []
var _rng := RandomNumberGenerator.new()

# Continuous layers.
var _thrust_target: float = 0.0
var _thrust_level: float = 0.0
var _thrust_phase: float = 0.0
var _drone_phase: float = 0.0
var _drone_level: float = 0.05
var _beam_target: float = 0.0
var _beam_level: float = 0.0
var _beam_phase: float = 0.0
var _noise_lp: float = 0.0

# Warning beeper.
var _warn_active: bool = false
var _warn_timer: float = 0.0
var _warn_pitch: float = 720.0


func _ready() -> void:
	_rng.randomize()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.name = "Synth"
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func set_muted(value: bool) -> void:
	muted = value
	if _player:
		_player.volume_db = -80.0 if muted else 0.0


func toggle_muted() -> bool:
	set_muted(not muted)
	return muted


# ---------------------------------------------------------------- public SFX

func set_thruster(level: float) -> void:
	_thrust_target = clampf(level, 0.0, 1.0)


func set_beam(level: float) -> void:
	_beam_target = clampf(level, 0.0, 1.0)


## Arms/disarms the low-resource beeper. pitch_shift makes the red state sharper.
func set_warning(active: bool, critical: bool = false) -> void:
	if active and not _warn_active:
		_warn_timer = 0.0
		_warn_active = true
		if critical:
			_warn_pitch = 1040.0
		else:
			_warn_pitch = 720.0
	elif not active:
		_warn_active = false


func sfx_blip() -> void:
	_add(Wave.SQUARE, 660.0, 990.0, 0.14, 0.05, 0.02, 0.06)


func sfx_select() -> void:
	_add(Wave.SQUARE, 440.0, 440.0, 0.10, 0.02, 0.01, 0.035)


func sfx_back() -> void:
	_add(Wave.SQUARE, 330.0, 220.0, 0.10, 0.02, 0.01, 0.06)


func sfx_clank() -> void:
	_add(Wave.NOISE, 1800.0, 900.0, 0.30, 0.005, 0.10, 0.20)
	_add(Wave.SQUARE, 220.0, 140.0, 0.16, 0.005, 0.08, 0.15)
	_add(Wave.TRI, 1180.0, 1640.0, 0.09, 0.005, 0.06, 0.22)


func sfx_denied() -> void:
	_add(Wave.SQUARE, 180.0, 120.0, 0.18, 0.01, 0.04, 0.14)


func sfx_thump() -> void:
	_add(Wave.NOISE, 400.0, 90.0, 0.42, 0.005, 0.22, 0.28)
	_add(Wave.SINE, 90.0, 45.0, 0.30, 0.005, 0.18, 0.30)


func sfx_dock() -> void:
	_add(Wave.TRI, 440.0, 660.0, 0.12, 0.02, 0.10, 0.16)
	_add(Wave.TRI, 660.0, 880.0, 0.10, 0.02, 0.10, 0.10)


func sfx_chime() -> void:
	_add(Wave.SINE, 523.25, 523.25, 0.14, 0.01, 0.30, 0.55)
	_add(Wave.SINE, 783.99, 783.99, 0.10, 0.02, 0.30, 0.50)


func sfx_beam_attach() -> void:
	_add(Wave.SAW, 300.0, 620.0, 0.09, 0.01, 0.05, 0.12)


func sfx_laser() -> void:
	_add(Wave.SAW, 180.0, 2200.0, 0.30, 0.30, 0.90, 1.60)
	_add(Wave.NOISE, 900.0, 200.0, 0.22, 0.20, 0.80, 1.40)


func sfx_specimen() -> void:
	_add(Wave.SINE, 392.0, 392.0, 0.16, 0.02, 0.40, 0.45)
	_add(Wave.SINE, 587.33, 587.33, 0.13, 0.10, 0.40, 0.55)
	_add(Wave.SINE, 880.0, 880.0, 0.09, 0.20, 0.50, 0.50)


# ---------------------------------------------------------------- synthesis

func _add(wave: int, f0: float, f1: float, amp: float, attack: float, decay: float, dur: float) -> void:
	if _voices.size() > 24:
		return
	_voices.append({
		"wave": wave, "f0": f0, "f1": f1, "amp": amp,
		"attack": maxf(0.001, attack), "decay": maxf(0.001, decay),
		"dur": maxf(0.02, dur), "t": 0.0, "phase": 0.0, "lp": 0.0,
	})


func _process(delta: float) -> void:
	if _playback == null:
		if _player != null and _player.playing:
			_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
		return

	# Smooth the continuous layers.
	_thrust_level = lerpf(_thrust_level, _thrust_target, clampf(delta * 12.0, 0.0, 1.0))
	_beam_level = lerpf(_beam_level, _beam_target, clampf(delta * 10.0, 0.0, 1.0))

	# Warning beeper cadence.
	if _warn_active:
		_warn_timer += delta
		if _warn_timer >= 0.95:
			_warn_timer = 0.0
			_add(Wave.SQUARE, _warn_pitch, _warn_pitch, 0.10, 0.005, 0.03, 0.10)
			_add(Wave.SQUARE, _warn_pitch * 0.5, _warn_pitch * 0.5, 0.05, 0.005, 0.03, 0.10)

	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	var inv := 1.0 / MIX_RATE

	for i in frames:
		var s := 0.0

		# Low-frequency thruster hum: detuned saw + filtered noise.
		if _thrust_level > 0.002:
			_thrust_phase = fmod(_thrust_phase + inv * (46.0 + _thrust_level * 22.0), 1.0)
			var saw := _thrust_phase * 2.0 - 1.0
			_noise_lp = lerpf(_noise_lp, _rng.randf_range(-1.0, 1.0), 0.08)
			s += (saw * 0.55 + _noise_lp * 0.45) * _thrust_level * 0.30

		# Tractor beam: quick cyclic whine.
		if _beam_level > 0.002:
			_beam_phase = fmod(_beam_phase + inv * (170.0 + sin(_beam_phase * TAU * 3.0) * 30.0), 1.0)
			var sq := 1.0 if _beam_phase < 0.5 else -1.0
			s += sq * 0.055 * _beam_level

		# Station ambience.
		_drone_phase = fmod(_drone_phase + inv * 55.0, 1.0)
		s += (_drone_phase * 2.0 - 1.0) * _drone_level * 0.35

		# One-shot voices.
		var kill: Array = []
		for vi in _voices.size():
			var v: Dictionary = _voices[vi]
			var t: float = float(v["t"])
			var dur: float = float(v["dur"])
			if t >= dur:
				kill.append(vi)
				continue
			var prog: float = t / dur
			var freq: float = lerpf(float(v["f0"]), float(v["f1"]), prog)
			var phase: float = float(v["phase"])
			phase = fmod(phase + inv * freq, 1.0)
			v["phase"] = phase
			var sample := 0.0
			match int(v["wave"]):
				Wave.SINE:
					sample = sin(phase * TAU)
				Wave.SQUARE:
					sample = 1.0 if phase < 0.5 else -1.0
				Wave.SAW:
					sample = phase * 2.0 - 1.0
				Wave.TRI:
					sample = 1.0 - 4.0 * absf(phase - 0.5)
				Wave.NOISE:
					var lp: float = float(v["lp"])
					lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.35)
					v["lp"] = lp
					sample = lp
			var env := 1.0
			var atk: float = float(v["attack"])
			var dec: float = float(v["decay"])
			if t < atk:
				env = t / atk
			else:
				env = exp(-(t - atk) / dec)
			s += sample * env * float(v["amp"])
			v["t"] = t + inv
		for k in range(kill.size() - 1, -1, -1):
			_voices.remove_at(int(kill[k]))

		s = clampf(s * master, -1.0, 1.0)
		buffer[i] = Vector2(s, s)

	_playback.push_buffer(buffer)


func stop_all() -> void:
	_voices.clear()
	_thrust_target = 0.0
	_beam_target = 0.0
	_warn_active = false
	_thrust_level = 0.0
	_beam_level = 0.0
