extends SceneTree
## Loads and compiles every STAR FALL script, so a syntax or dependency error
## fails loudly in CI instead of at runtime.
##
##   Godot --headless --path . --script res://tests/star_fall/test_parse.gd

const SCRIPTS := [
	"res://autoload/game_state.gd",
	"res://autoload/events.gd",
	"res://autoload/data_loader.gd",
	"res://core/star_fall/sf_palette.gd",
	"res://core/star_fall/sf_pixel_font.gd",
	"res://core/star_fall/sf_sprites.gd",
	"res://core/star_fall/sf_skin.gd",
	"res://core/star_fall/sf_audio.gd",
	"res://core/star_fall/sf_content.gd",
	"res://core/star_fall/sf_sites.gd",
	"res://core/star_fall/sf_design.gd",
	"res://core/star_fall/sf_campaign.gd",
	"res://core/star_fall/sf_save.gd",
	"res://core/star_fall/sf_dialogue.gd",
	"res://core/star_fall/sf_menu.gd",
	"res://core/star_fall/sf_ui.gd",
	"res://core/star_fall/sf_encounters.gd",
	"res://core/star_fall/sf_shield.gd",
	"res://core/star_fall/sf_projectiles.gd",
	"res://core/star_fall/sf_pattern_scheduler.gd",
	"res://core/star_fall/sf_encounter_model.gd",
	"res://core/star_fall/sf_encounter.gd",
	"res://core/star_fall/sf_vocabulary.gd",
	"res://core/star_fall/sf_typing.gd",
	"res://core/star_fall/sf_typing_encounter.gd",
	"res://core/star_fall/sf_return_sim.gd",
	"res://core/star_fall/sf_reconstruction.gd",
	"res://scenes/star_fall/player.gd",
	"res://scenes/star_fall/prop.gd",
	"res://scenes/star_fall/world.gd",
	"res://scenes/star_fall/construction_screen.gd",
	"res://scenes/star_fall/shield_duel.gd",
	"res://scenes/star_fall/archive_screen.gd",
	"res://scenes/star_fall/progression_screen.gd",
	"res://scenes/star_fall/typing_duel.gd",
	"res://scenes/star_fall/reconstruction_screen.gd",
	"res://scenes/star_fall/main.gd",
]

var fails: int = 0


# Autoloads (Events, GameState) are only registered once the tree is running,
# so compile the scripts on the first frame instead of in _init().
func _process(_delta: float) -> bool:
	for path in SCRIPTS:
		var script = load(String(path))
		# can_instantiate() is false for a script that failed to compile.
		# Do not call reload(): autoload scripts already have live instances,
		# and reloading those returns ERR_ALREADY_IN_USE rather than a verdict.
		var ok: bool = script != null and script.can_instantiate()
		print(("PASS  " if ok else "FAIL  ") + String(path))
		if not ok:
			fails += 1
	print("")
	print("RESULT: %d script(s), %d failure(s)" % [SCRIPTS.size(), fails])
	quit(1 if fails > 0 else 0)
	return true
