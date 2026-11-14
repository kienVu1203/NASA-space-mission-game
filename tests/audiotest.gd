extends SceneTree
## Verifies the procedural synth: the generator drains as the audio thread
## consumes it, and the mixer refills it. Needs a real audio device, so run
## windowed rather than --headless.

var a
var frame: int = 0
var drained: int = -1

func _initialize() -> void:
	var AU = load("res://core/starfall/sf_audio.gd")
	a = AU.new()
	root.add_child(a)

func _process(_delta: float) -> bool:
	frame += 1
	if a == null or a._playback == null:
		return false
	# Let the audio thread drain whatever has been buffered.
	if frame == 4:
		drained = a._playback.get_frames_available()
		return false
	if frame == 12:
		print("drained to = ", drained)
		a.set_thruster(1.0)
		a.set_beam(1.0)
		a.sfx_clank()
		a.sfx_blip()
		a.sfx_laser()
		a.set_warning(true, true)
		for i in 8:
			a._process(1.0 / 60.0)
		var after: int = a._playback.get_frames_available()
		print("after mixing = ", after)
		print("PASS mixer refilled the buffer" if after < drained else "FAIL mixer produced nothing")
		print("voices = ", a._voices.size(), " thrust = %.2f" % a._thrust_level)
		a.stop_all()
		print("PASS stop_all cleared voices" if a._voices.is_empty() else "FAIL voices remain")
		print("muted toggle = ", a.toggle_muted())
		quit()
	return false
