extends Node
## STAR FALL Phase 1 Audio System.
## Dual-layer architecture:
##   1. High-fidelity 16-bit PCM WAV sample streaming (polyphonic SFX pool + ambient music)
##   2. Real-time procedural synthesizer fallback (AudioStreamGenerator) for 100% headless/fail-safe resilience.
##
## Ambience modes:
##   "none"  - silence
##   "earth" - bright wind, bird calls, distant hangar telemetry hum
##   "ruin"  - desolate sub drone, thin howling wind, hollow metallic resonance

const MIX_RATE := 22050.0
const SFX_POOL_SIZE := 16

enum Wave { SINE, SQUARE, SAW, TRI, NOISE }

var muted: bool = false
var master: float = 0.42

# Procedural synth engine
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _voices: Array = []
var _rng := RandomNumberGenerator.new()

# Ambience state
var ambience: String = "none"
var _amb_level: float = 0.0
var _amb_target: float = 0.0
var _amb_phase: float = 0.0
var _amb_phase2: float = 0.0
var _noise_lp: float = 0.0
var _noise_lp2: float = 0.0
var _bird_timer: float = 3.0
var _tick_timer: float = 4.0

# Sample library & players
var _samples: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_idx: int = 0
var _music_earth: AudioStreamPlayer
var _music_ruin: AudioStreamPlayer
var _music_earth_vol: float = 0.0
var _music_ruin_vol: float = 0.0

const SFX_MAP := {
	"ui_select": "res://assets/audio/sfx/ui_select.wav",
	"ui_confirm": "res://assets/audio/sfx/ui_confirm.wav",
	"ui_back": "res://assets/audio/sfx/ui_back.wav",
	"ui_denied": "res://assets/audio/sfx/ui_denied.wav",
	"ui_toast": "res://assets/audio/sfx/ui_toast.wav",
	"blip_nick": "res://assets/audio/sfx/blip_nick.wav",
	"blip_bill": "res://assets/audio/sfx/blip_bill.wav",
	"blip_control": "res://assets/audio/sfx/blip_control.wav",
	"ship_install": "res://assets/audio/sfx/ship_install.wav",
	"ship_remove": "res://assets/audio/sfx/ship_remove.wav",
	"fuel_tick": "res://assets/audio/sfx/fuel_tick.wav",
	"preflight_scan": "res://assets/audio/sfx/preflight_scan.wav",
	"preflight_pass": "res://assets/audio/sfx/preflight_pass.wav",
	"preflight_fail": "res://assets/audio/sfx/preflight_fail.wav",
	"step_earth_1": "res://assets/audio/sfx/step_earth_1.wav",
	"step_earth_2": "res://assets/audio/sfx/step_earth_2.wav",
	"step_ruin_1": "res://assets/audio/sfx/step_ruin_1.wav",
	"step_ruin_2": "res://assets/audio/sfx/step_ruin_2.wav",
	"interact": "res://assets/audio/sfx/interact.wav",
	"salvage_pickup": "res://assets/audio/sfx/salvage_pickup.wav",
	"repair_spark": "res://assets/audio/sfx/repair_spark.wav",
	"power_surge": "res://assets/audio/sfx/power_surge.wav",
	"bill_boot": "res://assets/audio/sfx/bill_boot.wav",
	"countdown_beep": "res://assets/audio/sfx/countdown_beep.wav",
	"launch_roar": "res://assets/audio/sfx/launch_roar.wav",
	"signal_sweep": "res://assets/audio/sfx/signal_sweep.wav",
	"signal_lock": "res://assets/audio/sfx/signal_lock.wav",
	"rift_tear": "res://assets/audio/sfx/rift_tear.wav",
	"ship_alarm": "res://assets/audio/sfx/ship_alarm.wav",
	"hull_creak": "res://assets/audio/sfx/hull_creak.wav",
	"crash_impact": "res://assets/audio/sfx/crash_impact.wav",
	"memory_chime": "res://assets/audio/sfx/memory_chime.wav",
	"checkpoint": "res://assets/audio/sfx/checkpoint.wav",
	"sfx_transition": "res://assets/audio/sfx/sfx_transition.wav",
}

const MUSIC_MAP := {
	"title": "res://assets/audio/music/music_title.wav",
	"earth": "res://assets/audio/music/music_earth.wav",
	"construction": "res://assets/audio/music/music_construction.wav",
	"flight": "res://assets/audio/music/music_flight.wav",
	"ruin": "res://assets/audio/music/music_ruin.wav",
	"memory": "res://assets/audio/music/music_memory.wav",
	"checkpoint": "res://assets/audio/music/music_checkpoint.wav",
	"ambience_earth": "res://assets/audio/music/ambience_earth.wav",
	"ambience_ruin": "res://assets/audio/music/ambience_ruin.wav",
}

const MUSIC_EARTH_PATH := "res://assets/audio/music/ambience_earth.wav"
const MUSIC_RUIN_PATH := "res://assets/audio/music/ambience_ruin.wav"

var _music_streams: Dictionary = {}
var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _music_a_active: bool = true
var _music_vol_a: float = 0.0
var _music_vol_b: float = 0.0
var current_music: String = "none"


func _ready() -> void:
	_rng.randomize()

	# 1. Initialize fallback procedural synthesizer
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.name = "SFSynth"
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback

	# 2. Preload sample audio files
	for key in SFX_MAP:
		var stream := _try_load_stream(SFX_MAP[key])
		if stream != null:
			_samples[key] = stream

	# 3. Create polyphonic SFX player pool
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFXPlayer_%d" % i
		add_child(p)
		_sfx_pool.append(p)

	# 4. Create ambient music players
	_music_earth = AudioStreamPlayer.new()
	_music_earth.name = "MusicEarth"
	var earth_stream := _try_load_stream(MUSIC_EARTH_PATH)
	if earth_stream != null:
		if "loop_mode" in earth_stream:
			earth_stream.loop_mode = 1
		_music_earth.stream = earth_stream
	_music_earth.volume_db = -80.0
	_music_earth.finished.connect(func():
		if ambience == "earth" and not muted and _music_earth.stream != null:
			_music_earth.play()
	)
	add_child(_music_earth)

	_music_ruin = AudioStreamPlayer.new()
	_music_ruin.name = "MusicRuin"
	var ruin_stream := _try_load_stream(MUSIC_RUIN_PATH)
	if ruin_stream != null:
		if "loop_mode" in ruin_stream:
			ruin_stream.loop_mode = 1
		_music_ruin.stream = ruin_stream
	_music_ruin.volume_db = -80.0
	_music_ruin.finished.connect(func():
		if ambience == "ruin" and not muted and _music_ruin.stream != null:
			_music_ruin.play()
	)
	add_child(_music_ruin)

	# 5. Preload background music tracks & setup cross-fading BGM players
	for m_key in MUSIC_MAP:
		var m_stream := _try_load_stream(MUSIC_MAP[m_key])
		if m_stream != null:
			if "loop_mode" in m_stream:
				m_stream.loop_mode = 1
			_music_streams[m_key] = m_stream

	_music_player_a = AudioStreamPlayer.new()
	_music_player_a.name = "MusicPlayerA"
	_music_player_a.volume_db = -80.0
	_music_player_a.finished.connect(func():
		if _music_a_active and current_music != "none" and not muted and _music_player_a.stream != null:
			_music_player_a.play()
	)
	add_child(_music_player_a)

	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.name = "MusicPlayerB"
	_music_player_b.volume_db = -80.0
	_music_player_b.finished.connect(func():
		if not _music_a_active and current_music != "none" and not muted and _music_player_b.stream != null:
			_music_player_b.play()
	)
	add_child(_music_player_b)


func _try_load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			return res as AudioStream
	return null


# ---------------------------------------------------------------- controls

func set_muted(value: bool) -> void:
	muted = value
	if _player:
		_player.volume_db = -80.0 if muted else 0.0
	if _music_earth:
		_music_earth.volume_db = -80.0 if (muted or _music_earth_vol <= 0.01) else linear_to_db(_music_earth_vol * master)
	if _music_ruin:
		_music_ruin.volume_db = -80.0 if (muted or _music_ruin_vol <= 0.01) else linear_to_db(_music_ruin_vol * master)
	if _music_player_a:
		_music_player_a.volume_db = -80.0 if (muted or _music_vol_a <= 0.01) else linear_to_db(_music_vol_a * master)
	if _music_player_b:
		_music_player_b.volume_db = -80.0 if (muted or _music_vol_b <= 0.01) else linear_to_db(_music_vol_b * master)
	for p in _sfx_pool:
		if p.playing and muted:
			p.volume_db = -80.0


func toggle_muted() -> bool:
	set_muted(not muted)
	return muted


func set_ambience(mode: String) -> void:
	ambience = mode
	_amb_target = 0.0 if mode == "none" else 1.0

	# Start streams if available
	if mode == "earth" and _music_earth != null and _music_earth.stream != null:
		if not _music_earth.playing and not muted:
			_music_earth.play()
	elif mode == "ruin" and _music_ruin != null and _music_ruin.stream != null:
		if not _music_ruin.playing and not muted:
			_music_ruin.play()


func play_music(track_id: String, _crossfade: float = 0.8) -> void:
	if current_music == track_id and not muted:
		return
	current_music = track_id
	if track_id == "none" or track_id == "":
		return
	var stream: AudioStream = _music_streams.get(track_id, null)
	if stream == null:
		return
	if _music_a_active:
		_music_a_active = false
		if _music_player_b != null:
			_music_player_b.stream = stream
			_music_player_b.volume_db = -80.0
			if not muted:
				_music_player_b.play()
	else:
		_music_a_active = true
		if _music_player_a != null:
			_music_player_a.stream = stream
			_music_player_a.volume_db = -80.0
			if not muted:
				_music_player_a.play()


func stop_music(_fade_out: float = 0.8) -> void:
	current_music = "none"


func sfx_transition() -> void:
	play_sfx("sfx_transition", Callable(self, "_synth_transition"))


func _synth_transition() -> void:
	_add(Wave.NOISE, 440.0, 110.0, 0.16, 0.05, 0.25, 0.38)
	_add(Wave.SAW, 160.0, 70.0, 0.11, 0.04, 0.22, 0.32)


# ---------------------------------------------------------------- play router

func play_sfx(key: String, fallback_callable: Callable = Callable(), pan: float = 0.0) -> bool:
	if muted:
		return false

	if _samples.has(key) and _samples[key] != null and not _sfx_pool.is_empty():
		var p: AudioStreamPlayer = _sfx_pool[_sfx_idx]
		_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
		p.stream = _samples[key]
		p.volume_db = linear_to_db(master)
		p.play()
		return true

	# Fallback to procedural synth voice if sample unavailable
	if fallback_callable.is_valid():
		fallback_callable.call()
		return true

	return false


# ---------------------------------------------------------------- SFX API

func sfx_blip() -> void:
	play_sfx("blip_nick", _synth_blip)


func sfx_select() -> void:
	play_sfx("ui_select", _synth_select)


func sfx_confirm() -> void:
	play_sfx("ui_confirm", _synth_confirm)


func sfx_back() -> void:
	play_sfx("ui_back", _synth_back)


func sfx_denied() -> void:
	play_sfx("ui_denied", _synth_denied)


func sfx_toast() -> void:
	play_sfx("ui_toast", _synth_confirm)


func sfx_blip_nick() -> void:
	play_sfx("blip_nick", _synth_blip)


func sfx_blip_bill() -> void:
	play_sfx("blip_bill", func(): _add(Wave.SQUARE, 820.0, 940.0, 0.10, 0.003, 0.02, 0.035))


func sfx_blip_control() -> void:
	play_sfx("blip_control", func(): _add(Wave.SQUARE, 1050.0, 1100.0, 0.08, 0.002, 0.03, 0.045))


func sfx_install() -> void:
	play_sfx("ship_install", _synth_install)


func sfx_remove() -> void:
	play_sfx("ship_remove", _synth_remove)


func sfx_fuel_tick() -> void:
	play_sfx("fuel_tick", func(): _add(Wave.SINE, 650.0, 240.0, 0.08, 0.002, 0.02, 0.05))


func sfx_preflight_scan() -> void:
	play_sfx("preflight_scan", func():
		_add(Wave.SINE, 450.0, 1400.0, 0.10, 0.01, 0.06, 0.10)
		_add(Wave.TRI, 600.0, 1600.0, 0.08, 0.08, 0.06, 0.18)
	)


func sfx_preflight_pass() -> void:
	play_sfx("preflight_pass", func():
		_add(Wave.SINE, 523.25, 523.25, 0.10, 0.01, 0.15, 0.25)
		_add(Wave.SINE, 659.25, 659.25, 0.10, 0.06, 0.15, 0.30)
		_add(Wave.SINE, 783.99, 783.99, 0.10, 0.12, 0.18, 0.35)
		_add(Wave.SINE, 1046.5, 1046.5, 0.12, 0.18, 0.25, 0.50)
	)


func sfx_preflight_fail() -> void:
	play_sfx("preflight_fail", func():
		_add(Wave.SAW, 466.0, 392.0, 0.14, 0.01, 0.18, 0.40)
		_add(Wave.SQUARE, 330.0, 277.0, 0.12, 0.01, 0.18, 0.40)
	)


func sfx_step() -> void:
	play_sfx("step_earth_1", _synth_step)


func sfx_step_earth(variation: int = 1) -> void:
	var key := "step_earth_2" if variation == 2 else "step_earth_1"
	play_sfx(key, _synth_step)


func sfx_step_ruin(variation: int = 1) -> void:
	var key := "step_ruin_2" if variation == 2 else "step_ruin_1"
	play_sfx(key, func():
		_add(Wave.NOISE, 800.0, 200.0, 0.07, 0.002, 0.04, 0.08)
		_add(Wave.TRI, 180.0, 75.0, 0.05, 0.005, 0.05, 0.09)
	)


func sfx_interact() -> void:
	play_sfx("interact", func():
		_add(Wave.NOISE, 1800.0, 900.0, 0.08, 0.002, 0.015, 0.03)
		_add(Wave.SINE, 880.0, 880.0, 0.09, 0.01, 0.08, 0.12)
		_add(Wave.SINE, 1320.0, 1320.0, 0.07, 0.02, 0.08, 0.12)
	)


func sfx_pickup() -> void:
	play_sfx("salvage_pickup", _synth_pickup)


func sfx_spark() -> void:
	play_sfx("repair_spark", func():
		_add(Wave.NOISE, 3500.0, 1800.0, 0.15, 0.002, 0.04, 0.12)
		_add(Wave.SAW, 120.0, 60.0, 0.10, 0.005, 0.06, 0.15)
	)


func sfx_power_up() -> void:
	play_sfx("power_surge", _synth_power_up)


func sfx_surge() -> void:
	play_sfx("power_surge", _synth_power_up)


func sfx_bill_boot() -> void:
	play_sfx("bill_boot", func():
		_add(Wave.TRI, 260.0, 580.0, 0.08, 0.02, 0.15, 0.35)
		_add(Wave.SQUARE, 392.0, 392.0, 0.09, 0.38, 0.10, 0.20)
		_add(Wave.SQUARE, 494.0, 494.0, 0.09, 0.48, 0.10, 0.20)
		_add(Wave.SQUARE, 784.0, 784.0, 0.12, 0.58, 0.25, 0.45)
	)


func sfx_countdown() -> void:
	play_sfx("countdown_beep", func(): _add(Wave.SINE, 1200.0, 1200.0, 0.12, 0.003, 0.04, 0.09))


func sfx_launch() -> void:
	play_sfx("launch_roar", _synth_launch)


func sfx_signal_sweep() -> void:
	play_sfx("signal_sweep", func(): _add(Wave.SINE, 650.0, 2200.0, 0.11, 0.04, 0.30, 0.60))


func sfx_signal_lock() -> void:
	play_sfx("signal_lock", func():
		_add(Wave.SINE, 1760.0, 1760.0, 0.12, 0.002, 0.10, 0.25)
		_add(Wave.SINE, 2637.0, 2637.0, 0.09, 0.004, 0.12, 0.25)
	)


func sfx_rift() -> void:
	play_sfx("rift_tear", _synth_rift)


func sfx_alarm() -> void:
	play_sfx("ship_alarm", func():
		_add(Wave.SQUARE, 820.0, 1040.0, 0.14, 0.01, 0.15, 0.35)
	)


func sfx_hull_creak() -> void:
	play_sfx("hull_creak", func():
		_add(Wave.SAW, 130.0, 110.0, 0.15, 0.10, 0.40, 0.80)
		_add(Wave.TRI, 390.0, 330.0, 0.08, 0.12, 0.35, 0.75)
	)


func sfx_impact() -> void:
	play_sfx("crash_impact", _synth_impact)


func sfx_memory() -> void:
	play_sfx("memory_chime", _synth_memory)


func sfx_checkpoint() -> void:
	play_sfx("checkpoint", func():
		_add(Wave.SQUARE, 698.0, 698.0, 0.10, 0.005, 0.08, 0.14)
		_add(Wave.SQUARE, 880.0, 880.0, 0.10, 0.08, 0.08, 0.14)
		_add(Wave.SQUARE, 1046.0, 1046.0, 0.10, 0.16, 0.08, 0.14)
		_add(Wave.SQUARE, 1397.0, 1397.0, 0.14, 0.24, 0.22, 0.45)
	)


# ---------------------------------------------------------------- procedural synths (fallbacks)

func _synth_blip() -> void:
	_add(Wave.SQUARE, 660.0, 880.0, 0.12, 0.005, 0.03, 0.06)

func _synth_select() -> void:
	_add(Wave.SQUARE, 440.0, 440.0, 0.09, 0.004, 0.02, 0.035)

func _synth_back() -> void:
	_add(Wave.SQUARE, 330.0, 220.0, 0.09, 0.005, 0.02, 0.07)

func _synth_denied() -> void:
	_add(Wave.SQUARE, 180.0, 120.0, 0.16, 0.01, 0.05, 0.16)

func _synth_install() -> void:
	_add(Wave.NOISE, 1500.0, 700.0, 0.22, 0.004, 0.08, 0.18)
	_add(Wave.TRI, 520.0, 780.0, 0.10, 0.01, 0.10, 0.20)
	_add(Wave.SQUARE, 260.0, 200.0, 0.06, 0.005, 0.06, 0.12)

func _synth_remove() -> void:
	_add(Wave.NOISE, 900.0, 400.0, 0.16, 0.004, 0.06, 0.14)
	_add(Wave.SQUARE, 300.0, 220.0, 0.07, 0.005, 0.05, 0.10)

func _synth_pickup() -> void:
	_add(Wave.TRI, 620.0, 940.0, 0.14, 0.01, 0.10, 0.16)
	_add(Wave.SINE, 940.0, 1240.0, 0.07, 0.03, 0.12, 0.14)

func _synth_confirm() -> void:
	_add(Wave.SINE, 523.25, 523.25, 0.12, 0.01, 0.22, 0.34)
	_add(Wave.SINE, 783.99, 783.99, 0.09, 0.04, 0.24, 0.30)

func _synth_power_up() -> void:
	_add(Wave.SAW, 90.0, 320.0, 0.10, 0.30, 0.60, 0.90)
	_add(Wave.SINE, 180.0, 720.0, 0.09, 0.40, 0.50, 0.85)
	_add(Wave.TRI, 720.0, 1080.0, 0.07, 0.55, 0.30, 0.45)

func _synth_launch() -> void:
	_add(Wave.NOISE, 200.0, 60.0, 0.40, 0.30, 1.60, 2.20)
	_add(Wave.SAW, 40.0, 80.0, 0.20, 0.40, 1.40, 2.00)

func _synth_rift() -> void:
	_add(Wave.SAW, 120.0, 1800.0, 0.20, 0.60, 1.10, 1.80)
	_add(Wave.NOISE, 500.0, 2400.0, 0.18, 0.50, 1.00, 1.70)

func _synth_impact() -> void:
	_add(Wave.NOISE, 800.0, 60.0, 0.42, 0.003, 0.30, 0.50)
	_add(Wave.SINE, 110.0, 40.0, 0.30, 0.004, 0.24, 0.45)

func _synth_memory() -> void:
	_add(Wave.SINE, 392.0, 392.0, 0.13, 0.05, 0.50, 0.80)
	_add(Wave.SINE, 587.33, 587.33, 0.10, 0.14, 0.50, 0.80)
	_add(Wave.SINE, 880.0, 880.0, 0.07, 0.24, 0.55, 0.70)

func _synth_step() -> void:
	_add(Wave.NOISE, 500.0, 240.0, 0.05, 0.002, 0.025, 0.05)


# ---------------------------------------------------------------- synthesis core

func _add(wave: int, f0: float, f1: float, amp: float, attack: float, decay: float, dur: float) -> void:
	if _voices.size() > 24:
		return
	_voices.append({
		"wave": wave, "f0": f0, "f1": f1, "amp": amp,
		"attack": maxf(0.001, attack), "decay": maxf(0.001, decay),
		"dur": maxf(0.02, dur), "t": 0.0, "phase": 0.0, "lp": 0.0,
	})


func _process(delta: float) -> void:
	# 1. Cross-fade streaming background music tracks
	var target_a := 1.0 if (_music_a_active and current_music != "none" and not muted) else 0.0
	var target_b := 1.0 if (not _music_a_active and current_music != "none" and not muted) else 0.0
	_music_vol_a = lerpf(_music_vol_a, target_a, clampf(delta * 2.5, 0.0, 1.0))
	_music_vol_b = lerpf(_music_vol_b, target_b, clampf(delta * 2.5, 0.0, 1.0))

	if _music_player_a != null and _music_player_a.stream != null:
		if _music_vol_a <= 0.01:
			_music_player_a.volume_db = -80.0
			if target_a <= 0.01 and _music_player_a.playing:
				_music_player_a.stop()
		else:
			_music_player_a.volume_db = linear_to_db(_music_vol_a * master)

	if _music_player_b != null and _music_player_b.stream != null:
		if _music_vol_b <= 0.01:
			_music_player_b.volume_db = -80.0
			if target_b <= 0.01 and _music_player_b.playing:
				_music_player_b.stop()
		else:
			_music_player_b.volume_db = linear_to_db(_music_vol_b * master)

	# Cross-fade streaming ambient music tracks
	var target_earth_vol := 1.0 if (ambience == "earth" and not muted) else 0.0
	var target_ruin_vol := 1.0 if (ambience == "ruin" and not muted) else 0.0
	_music_earth_vol = lerpf(_music_earth_vol, target_earth_vol, clampf(delta * 2.0, 0.0, 1.0))
	_music_ruin_vol = lerpf(_music_ruin_vol, target_ruin_vol, clampf(delta * 2.0, 0.0, 1.0))

	if _music_earth != null and _music_earth.stream != null:
		if _music_earth_vol <= 0.01:
			_music_earth.volume_db = -80.0
		else:
			_music_earth.volume_db = linear_to_db(_music_earth_vol * master)

	if _music_ruin != null and _music_ruin.stream != null:
		if _music_ruin_vol <= 0.01:
			_music_ruin.volume_db = -80.0
		else:
			_music_ruin.volume_db = linear_to_db(_music_ruin_vol * master)

	# 2. Procedural synthesizer engine (active voices and fallback ambience)
	if _playback == null:
		if _player != null and _player.playing:
			_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
		return

	_amb_level = lerpf(_amb_level, _amb_target, clampf(delta * 2.0, 0.0, 1.0))

	# Only run procedural ambience if music streams are not active/available
	var need_synth_ambience := (_music_earth == null or _music_earth.stream == null) if ambience == "earth" else ((_music_ruin == null or _music_ruin.stream == null) if ambience == "ruin" else false)

	if need_synth_ambience:
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

	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	var inv := 1.0 / MIX_RATE

	for i in frames:
		var s := 0.0

		if need_synth_ambience and _amb_level > 0.002:
			if ambience == "earth":
				_noise_lp = lerpf(_noise_lp, _rng.randf_range(-1.0, 1.0), 0.11)
				_amb_phase = fmod(_amb_phase + inv * 0.22, 1.0)
				var swell: float = 0.55 + 0.45 * sin(_amb_phase * TAU)
				s += _noise_lp * 0.020 * swell
				_amb_phase2 = fmod(_amb_phase2 + inv * 58.0, 1.0)
				s += (_amb_phase2 * 2.0 - 1.0) * 0.010
			elif ambience == "ruin":
				_noise_lp2 = lerpf(_noise_lp2, _rng.randf_range(-1.0, 1.0), 0.035)
				s += _noise_lp2 * 0.030
				_amb_phase2 = fmod(_amb_phase2 + inv * 41.0, 1.0)
				s += sin(_amb_phase2 * TAU) * 0.022
				_amb_phase = fmod(_amb_phase + inv * 27.5, 1.0)
				s += sin(_amb_phase * TAU) * 0.014
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
	current_music = "none"
	_amb_target = 0.0
	_amb_level = 0.0
	_music_earth_vol = 0.0
	_music_ruin_vol = 0.0
	_music_vol_a = 0.0
	_music_vol_b = 0.0
	if _music_earth:
		_music_earth.stop()
	if _music_ruin:
		_music_ruin.stop()
	if _music_player_a:
		_music_player_a.stop()
	if _music_player_b:
		_music_player_b.stop()
	for p in _sfx_pool:
		p.stop()
