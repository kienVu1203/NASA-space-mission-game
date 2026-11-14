extends Node
## Retro audio synthesised at runtime. No sample files: one AudioStreamGenerator
## is filled every frame with one-shot voices plus two ambient layers.
##
## Ambience modes:
##   "none"  - silence
##   "earth" - bright wind, bird calls, distant machinery
##   "ruin"  - low drone, thin wind, occasional metal ticks
##   "city"  - the ruin bed plus denser, faster metal ticks (sorting machinery)
##   "coast" - the ruin bed with a slow wash and a distant pump thud

const MIX_RATE := 22050.0

enum Wave { SINE, SQUARE, SAW, TRI, NOISE }

var muted: bool = false
var master: float = 0.42

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _voices: Array = []
var _rng := RandomNumberGenerator.new()

var ambience: String = "none"
var _amb_level: float = 0.0
var _amb_target: float = 0.0
var _amb_phase: float = 0.0
var _amb_phase2: float = 0.0
var _noise_lp: float = 0.0
var _noise_lp2: float = 0.0
var _bird_timer: float = 3.0
var _tick_timer: float = 4.0


func _ready() -> void:
	_rng.randomize()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.name = "SFSynth"
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


func set_ambience(mode: String) -> void:
	ambience = mode
	_amb_target = 0.0 if mode == "none" else 1.0


# ---------------------------------------------------------------- one-shots

func sfx_blip() -> void:
	_add(Wave.SQUARE, 660.0, 880.0, 0.12, 0.005, 0.03, 0.06)


func sfx_select() -> void:
	_add(Wave.SQUARE, 440.0, 440.0, 0.09, 0.004, 0.02, 0.035)


func sfx_back() -> void:
	_add(Wave.SQUARE, 330.0, 220.0, 0.09, 0.005, 0.02, 0.07)


func sfx_denied() -> void:
	_add(Wave.SQUARE, 180.0, 120.0, 0.16, 0.01, 0.05, 0.16)


func sfx_install() -> void:
	_add(Wave.NOISE, 1500.0, 700.0, 0.22, 0.004, 0.08, 0.18)
	_add(Wave.TRI, 520.0, 780.0, 0.10, 0.01, 0.10, 0.20)
	_add(Wave.SQUARE, 260.0, 200.0, 0.06, 0.005, 0.06, 0.12)


func sfx_remove() -> void:
	_add(Wave.NOISE, 900.0, 400.0, 0.16, 0.004, 0.06, 0.14)
	_add(Wave.SQUARE, 300.0, 220.0, 0.07, 0.005, 0.05, 0.10)


func sfx_pickup() -> void:
	_add(Wave.TRI, 620.0, 940.0, 0.14, 0.01, 0.10, 0.16)
	_add(Wave.SINE, 940.0, 1240.0, 0.07, 0.03, 0.12, 0.14)


func sfx_confirm() -> void:
	_add(Wave.SINE, 523.25, 523.25, 0.12, 0.01, 0.22, 0.34)
	_add(Wave.SINE, 783.99, 783.99, 0.09, 0.04, 0.24, 0.30)


func sfx_power_up() -> void:
	_add(Wave.SAW, 90.0, 320.0, 0.10, 0.30, 0.60, 0.90)
	_add(Wave.SINE, 180.0, 720.0, 0.09, 0.40, 0.50, 0.85)
	_add(Wave.TRI, 720.0, 1080.0, 0.07, 0.55, 0.30, 0.45)


func sfx_launch() -> void:
	_add(Wave.NOISE, 200.0, 60.0, 0.40, 0.30, 1.60, 2.20)
	_add(Wave.SAW, 40.0, 80.0, 0.20, 0.40, 1.40, 2.00)


func sfx_rift() -> void:
	_add(Wave.SAW, 120.0, 1800.0, 0.20, 0.60, 1.10, 1.80)
	_add(Wave.NOISE, 500.0, 2400.0, 0.18, 0.50, 1.00, 1.70)


func sfx_impact() -> void:
	_add(Wave.NOISE, 800.0, 60.0, 0.42, 0.003, 0.30, 0.50)
	_add(Wave.SINE, 110.0, 40.0, 0.30, 0.004, 0.24, 0.45)


func sfx_memory() -> void:
	_add(Wave.SINE, 392.0, 392.0, 0.13, 0.05, 0.50, 0.80)
	_add(Wave.SINE, 587.33, 587.33, 0.10, 0.14, 0.50, 0.80)
	_add(Wave.SINE, 880.0, 880.0, 0.07, 0.24, 0.55, 0.70)


func sfx_step() -> void:
	_add(Wave.NOISE, 500.0, 240.0, 0.05, 0.002, 0.025, 0.05)


# ---------------------------------------------------------------- encounter sfx
# Phase 2 shield-defense feedback. Kept short so rapid blocks do not stack into
# a drone: the synth caps its own voice list.

## Hostile energy intercepted by the shield: bright, metallic, harmless.
func sfx_shield_block() -> void:
	_add(Wave.NOISE, 2600.0, 900.0, 0.12, 0.002, 0.05, 0.10)
	_add(Wave.SQUARE, 720.0, 480.0, 0.05, 0.002, 0.04, 0.08)


## Beneficial energy absorbed: rising, warm, distinct from a block.
func sfx_shield_absorb() -> void:
	_add(Wave.SINE, 620.0, 1240.0, 0.10, 0.01, 0.16, 0.22)
	_add(Wave.TRI, 930.0, 1390.0, 0.05, 0.02, 0.14, 0.20)


## Nick takes a hit: low and blunt, no high frequencies to grate over time.
func sfx_player_hurt() -> void:
	_add(Wave.SQUARE, 220.0, 90.0, 0.14, 0.003, 0.10, 0.18)
	_add(Wave.NOISE, 700.0, 180.0, 0.10, 0.003, 0.08, 0.14)


## Charge reaches full: a clean two-note ready chime.
func sfx_charge_ready() -> void:
	_add(Wave.SINE, 660.0, 660.0, 0.10, 0.01, 0.20, 0.26)
	_add(Wave.SINE, 990.0, 990.0, 0.08, 0.05, 0.24, 0.30)


## Counterattack launch and its travel toward the robot.
func sfx_counterattack() -> void:
	_add(Wave.SAW, 180.0, 900.0, 0.14, 0.01, 0.22, 0.32)
	_add(Wave.NOISE, 400.0, 2400.0, 0.10, 0.01, 0.16, 0.26)


## Counterattack impact on the boss chassis.
func sfx_counter_hit() -> void:
	_add(Wave.NOISE, 1800.0, 120.0, 0.26, 0.002, 0.20, 0.34)
	_add(Wave.SINE, 150.0, 55.0, 0.20, 0.003, 0.18, 0.30)


## Boss defeated: a long power-down, not an explosion.
func sfx_boss_down() -> void:
	_add(Wave.SAW, 300.0, 40.0, 0.16, 0.02, 0.90, 1.30)
	_add(Wave.NOISE, 900.0, 100.0, 0.12, 0.02, 0.70, 1.10)
	_add(Wave.SINE, 220.0, 110.0, 0.10, 0.10, 0.80, 1.20)


## Encounter failure sting.
func sfx_defeat() -> void:
	_add(Wave.SQUARE, 240.0, 70.0, 0.16, 0.01, 0.35, 0.55)
	_add(Wave.SAW, 130.0, 45.0, 0.12, 0.03, 0.40, 0.60)


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

	_amb_level = lerpf(_amb_level, _amb_target, clampf(delta * 2.0, 0.0, 1.0))

	if ambience == "earth" and _amb_level > 0.01:
		_bird_timer -= delta
		if _bird_timer <= 0.0:
			_bird_timer = _rng.randf_range(2.4, 6.5)
			var base: float = _rng.randf_range(1500.0, 2400.0)
			_add(Wave.SINE, base, base * 1.35, 0.030, 0.02, 0.06, 0.11)
			_add(Wave.SINE, base * 1.1, base * 1.5, 0.020, 0.03, 0.05, 0.09)
	elif ambience == "ruin" and _amb_level > 0.01:
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			_tick_timer = _rng.randf_range(3.5, 9.0)
			_add(Wave.NOISE, 2200.0, 1400.0, 0.025, 0.002, 0.05, 0.08)
			_add(Wave.TRI, 260.0, 180.0, 0.018, 0.01, 0.18, 0.24)
	elif ambience == "city" and _amb_level > 0.01:
		# Sorting machinery that never got switched off.
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			_tick_timer = _rng.randf_range(1.1, 3.4)
			_add(Wave.NOISE, 1900.0, 1100.0, 0.022, 0.002, 0.05, 0.09)
			_add(Wave.TRI, 320.0, 240.0, 0.016, 0.01, 0.14, 0.18)
	elif ambience == "coast" and _amb_level > 0.01:
		# A slow wash over the ruin bed, and a pump thud deep under it.
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			_tick_timer = _rng.randf_range(2.8, 5.5)
			_add(Wave.SINE, 78.0, 52.0, 0.06, 0.02, 0.35, 0.55)
			_add(Wave.NOISE, 900.0, 300.0, 0.018, 0.01, 0.30, 0.50)

	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	var inv := 1.0 / MIX_RATE

	for i in frames:
		var s := 0.0

		if _amb_level > 0.002:
			if ambience == "earth":
				# Bright airy wind plus a low machine hum.
				_noise_lp = lerpf(_noise_lp, _rng.randf_range(-1.0, 1.0), 0.11)
				_amb_phase = fmod(_amb_phase + inv * 0.22, 1.0)
				var swell: float = 0.55 + 0.45 * sin(_amb_phase * TAU)
				s += _noise_lp * 0.020 * swell
				_amb_phase2 = fmod(_amb_phase2 + inv * 58.0, 1.0)
				s += (_amb_phase2 * 2.0 - 1.0) * 0.010
			elif ambience == "ruin" or ambience == "city":
				_noise_lp2 = lerpf(_noise_lp2, _rng.randf_range(-1.0, 1.0), 0.035)
				s += _noise_lp2 * 0.030
				_amb_phase2 = fmod(_amb_phase2 + inv * 41.0, 1.0)
				s += sin(_amb_phase2 * TAU) * 0.022
				_amb_phase = fmod(_amb_phase + inv * 27.5, 1.0)
				s += sin(_amb_phase * TAU) * 0.014
			elif ambience == "coast":
				# Wider, slower noise so it reads as water rather than wind, plus a
				# low swell that rises and falls.
				_noise_lp2 = lerpf(_noise_lp2, _rng.randf_range(-1.0, 1.0), 0.020)
				s += _noise_lp2 * 0.034
				_amb_phase = fmod(_amb_phase + inv * 0.14, 1.0)
				s += sin(_amb_phase * TAU) * 0.020
				_amb_phase2 = fmod(_amb_phase2 + inv * 33.0, 1.0)
				s += sin(_amb_phase2 * TAU) * 0.010
			s *= _amb_level

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
	ambience = "none"
	_amb_target = 0.0
	_amb_level = 0.0
