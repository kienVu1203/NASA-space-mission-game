# STAR FALL — Contract (complete, through Phase 4)

This document is the contract between the code, the data, and whoever works on
the next phase. If something here and the code disagree, treat one of them as a
bug and fix it.

Game title: **STAR FALL**. Player character: **Nick**, a human astronaut.
Companion robot: **Bill**. Time travel and the VELA's drive are fictional story
devices, not claims about real technology.

---

## 1. Architecture and scene responsibilities

```
autoload/                       Global singletons (registered in project.godot)
  game_state.gd                 Owns the STAR FALL campaign object + legacy demo state
  events.gd                     Signal bus (data-only payloads, never node refs)
  data_loader.gd                Legacy JSON reader for the mission-planner demo

core/star_fall/                 Pure logic and presentation kit. No UI nodes.
  sf_palette.gd                 The locked colour palette
  sf_pixel_font.gd              5x7 bitmap font, baked at startup
  sf_sprites.gd                 Every sprite, drawn pixel-by-pixel at startup
  sf_skin.gd                    Drawing kit (panels, bars, text, shadows)
  sf_audio.gd                   Runtime synth: one-shots + ambience layers
  sf_content.gd                 Loads/indexes data/star_fall/*.json
  sf_sites.gd                   Loads data/star_fall/sites.json
  sf_design.gd                  Spacecraft design + preflight validation (pure)
  sf_encounters.gd              Loads and indexes data/star_fall/encounters.json
  sf_shield.gd                  Shield direction, coverage, window->canvas transform
  sf_projectiles.gd             Projectile field: swept collision, travel order
  sf_pattern_scheduler.gd       Spawn timing, telegraphs, health-band escalation
  sf_encounter_model.gd         Health, charge, phases, counterattack arbitration
  sf_encounter.gd               Encounter controller: glues the four above
  sf_eco_arena.gd               Eco Arena rules (Scrap King encounter and practice)
  sf_eco_sprites.gd             Eco Arena 16x16 item badges
  sf_vocabulary.gd              Phase 3: vocabulary library, validation, deck selection
  sf_typing.gd                  Phase 3: typing target selection and progress
  sf_typing_encounter.gd        Phase 3: queue, spawning, movement, health, attacks, pacing
  sf_reconstruction.gd          Phase 3: workshop selection, costs, atomic fabrication
  sf_return_sim.gd              Phase 3: return-mission simulation (pure)
  sf_finale.gd                  Phase 4: finale prerequisites, report, score (pure)
  sf_qa.gd                      Milestone planner for the headless tests (no input; the I+O+P skip is removed)
  sf_settings.gd                Local preferences file: volumes, text speed, reduced motion, practice unlock
  sf_debug_presets.gd           Debug builds: campaign states for the phase hotkeys (pure)
  sf_campaign.gd                Campaign state, quests, salvage, save dicts (pure)
  sf_save.gd                    Versioned save/load to user:// (pure + FileAccess)
  sf_dialogue.gd                Dialogue model (pure)
  sf_menu.gd                    Menu selection model (pure)
  sf_ui.gd                      Shared UI drawing (header, HUD, dialogue, toast)

scenes/star_fall/
  main.tscn / main.gd           Campaign controller: screen flow, input, launch
  world.gd                      One authored exploration area (props, ground, camera)
  player.gd                     Nick: movement and collision
  bill_companion.gd             Bill: active companion follower during exploration
  prop.gd                       One authored world prop with a ground footprint
  hud_overlay.gd                In-world HUD, drawn on a CanvasLayer above the world
  construction_screen.gd        Spacecraft construction + preflight
  shield_duel.gd                The Toxic Tide shield-defense encounter screen
  eco_arena_screen.gd           The Eco Arena screen (campaign Scrap King and practice)
  archive_screen.gd             Archive restoration (city and coast)
  progression_screen.gd         Base return and the Phase 2 summary
  typing_duel.gd                Phase 3: the Sky Remnant typing encounter screen
  reconstruction_screen.gd      Phase 3: the VELA reconstruction workshop
  final_assembly_screen.gd      Phase 4: the pre-finale gate and install animation
  cinematic_screen.gd           Phase 4: the escape cinematic (six scenes + final card)
  mission_report_screen.gd      Phase 4: the recorded-run report and the score
  credits_screen.gd             Phase 4: the credit roll and the closing message
  debug_jump.gd                 Debug builds: Ctrl+Shift+Alt phase hotkeys and help list

data/star_fall/
  ship_parts.json               Hull, mission requirements, components, salvage
  campaign.json                 Chapters, missions, memories, archives, dialogue
  encounters.json               Phase 2 boss identities; Toxic Tide duel tuning
  eco_arena.json                Eco Arena sorting content and tuning
  sites.json                    Authored world layouts (five sites)
  vocabulary.json               Phase 3: 203-entry environmental vocabulary library
  typing.json                   Phase 3: typing encounter tuning
  reconstruction.json           Phase 3: workshop options and simulation constants
  finale.json                   Phase 4: assembly copy, cinematic script, report copy,
                                score weights, credits (team first)

tests/star_fall/
  test_parse.gd                 Every script compiles
  test_logic.gd                 Validation, transactions, inventory, save/load
  test_flow.gd                  Boots the real scene, drives both phases end to end
  test_encounter.gd             Phase 2 combat rules, escalation, retry, rewards
  test_phase3.gd                Phase 3 vocabulary, typing, pacing, workshop, simulation, save
  test_phase4.gd                Phase 4 finale gate, cinematic, report, score, save, QA skip
  test_flight.gd                Phase 4 flight segments, canonical VELA renderer, shield
                                contacts, portal entry timing, presentation states, cleanup
  test_debug_jump.gd            Every debug phase jump and in-fight debug command
  test_eco_arena.gd             Eco Arena rules, screen, practice separation, pacing bot
  capture.gd                    Dev tool: renders 56 key screens to PNG
```

### Rules the architecture enforces

- `core/star_fall/` never touches a `Node`, a `CanvasItem` or an `InputEvent`.
  It answers questions; the scene layer asks them and draws the answer.
- `GameState` owns the campaign object. Screens read `GameState.campaign` and
  request changes through its methods. Screens never reference each other.
- `Events` carries notifications only. Payloads are `String`/`int`/`bool`.
- The campaign controller (`main.gd`) is the only place that maps campaign
  stages onto screens, and the only place that opens dialogues.
- World UI is drawn by `hud_overlay.gd` on a `CanvasLayer`, because a `Node2D`
  child always draws above its parent's own `_draw()`.

### Presentation

- Base resolution **640x360**, project stretch `canvas_items`, nearest-neighbour
  filtering (`rendering/textures/canvas_textures/default_texture_filter=0`).
  The window opens at 1280x720 and scales cleanly to other sizes.
- World sprite origins are **ground-contact points**. Props are Y-sorted and
  collision footprints sit at the feet, so Nick's upper body can overlap a tree
  trunk while his feet cannot pass through it.
- Gameplay coordinates are plain world pixels. There is no separate height
  axis: "2.5D" here means angled top-down art with depth cues (Y-sorting,
  contact shadows, foreground layers, restrained parallax), not a 3D pipeline.
- All sprites, the font and all audio are generated at runtime. No image,
  font or audio files are loaded, so the phase can never fail on a missing asset.
- Nick is **placeholder art**: a readable human astronaut in a warm-white suit
  with a blue visor. It is not a final character design.

---

## 2. Campaign phases and legal transitions

Stages are declared in `sf_campaign.gd` as `STAGE_*` constants and ordered in
`STAGE_ORDER`. `advance_to()` refuses an unknown id and is idempotent.

```
menu -> briefing -> construction -> launch -> flight -> crash_intro
     -> crash_site -> memory -> checkpoint
     -> city_intro -> city_boss -> city_archive
     -> silent_intro -> coast_boss -> coast_archive
     -> base_return -> phase_two_complete -> complete
     -> dawn_intro -> dawn_boss -> dawn_archive
     -> reconstruction -> ready_for_final_assembly
     -> final_assembly -> escape -> return_home
     -> mission_report -> credits
```

| Stage | Screen | What happens |
|---|---|---|
| `menu` | Title | New Game / Continue / Settings / Quit |
| `briefing` | World (spaceport) | Briefing dialogue, then the console unlocks |
| `construction` | Construction | Component install, fuel, preflight, confirm |
| `launch` | Launch | Countdown, ascent, signal tuning, rift, crash |
| `flight` | — | Reserved; the sequence runs from `launch` |
| `crash_intro` | World (crash site) | Impact dialogue, then free exploration |
| `crash_site` | World (crash site) | Inspect wreck, salvage, junction, Bill |
| `memory` | Memory | Green City hologram, coordinates received |
| `checkpoint` | Checkpoint | Phase 1 summary; continues into the city |
| `city_intro` | World (Forgotten City) | City dialogue, then exploration |
| `city_boss` | Eco Arena | Scrap King encounter. Never checkpointed mid-fight; a defeated boss with an uncollected chip reopens the arena in its reward state |
| `city_archive` | Archive | Control-center archive, Future Earth reveal |
| `silent_intro` | World (Silent Coast) | Coast dialogue, then exploration |
| `coast_boss` | Duel | Toxic Tide. Never checkpointed mid-fight; victory returns the stage to `silent_intro` with the power core on the quay |
| `coast_archive` | Archive | Environmental archive, Dawn Tower unlock |
| `base_return` | Progression | Crash-site base, both components shown |
| `phase_two_complete` | Checkpoint | Phase 2 summary; continues into the Dawn Tower |
| `complete` | Checkpoint | Legacy Phase 2 stopping point; resumes at the Phase 2 summary |
| `dawn_intro` | World (Dawn Tower) | Former forest, survey projector, checkpoint, gate; after the victory, the shield emitter drop |
| `dawn_boss` | Typing duel | Sky Remnant. Never checkpointed mid-fight |
| `dawn_archive` | Archive | Dawn Project archive; unlocks the workshop |
| `reconstruction` | Workshop | VELA reconstruction and return simulation |
| `ready_for_final_assembly` | Checkpoint | READY_FOR_FINAL_ASSEMBLY summary; opens the final-assembly gate |
| `final_assembly` | Final assembly | Prerequisite gate, frozen snapshot, pre-finale checkpoint, install animation |
| `escape` | Cinematic | Six-scene escape and the closing message; Esc pauses (SKIP SEQUENCE in the pause menu), Enter / NEXT advances a beat |
| `return_home` | Report | Mission report from the recorded run; the return objective is complete |
| `mission_report` | Report | Reserved continuation of the same screen; marks the report seen |
| `credits` | Credits | Credit roll, then the title. The ending state is saved |

Chapters (`chapter_id`): `present_day_earth`, `crash_site`, `forgotten_city`,
`silent_coast`, `dawn_tower`, `return_home`. All six are playable;
`return_home` covers the escape, the report and the credits.

The chapter follows the stage automatically. `base_return`,
`phase_two_complete`, `complete`, `reconstruction`, `ready_for_final_assembly`
and `final_assembly` resolve to `crash_site` (the base); the three `dawn_*`
stages resolve to `dawn_tower`; `escape`, `return_home`, `mission_report` and
`credits` resolve to `return_home`.

**Spoiler rule.** Until the control-center archive is closed, no HUD label,
chapter title, zone name or dialogue names Earth, a future date, or the year.
The zone headers say `FORGOTTEN CITY` and `SILENT COAST`; the mission name stays
`Signal Investigation` until the reveal changes it to `Return With Evidence`.

---

## 3. Stable IDs

Do not rename these. Saves and data files refer to them.

**Chapters**

| id | Meaning |
|---|---|
| `present_day_earth` | Spaceport workshop, present day |
| `crash_site` | Unidentified ruined site, and the Phase 2 base |
| `forgotten_city` | Phase 2, Scrap King |
| `silent_coast` | Phase 2, Toxic Tide |
| `dawn_tower` | Phase 3, Sky Remnant |
| `return_home` | Escape, report and credits |

**Future spacecraft components:** `navigation_chip` (Phase 2 reward),
`power_core` (Phase 2 reward), `shield_emitter` (Phase 3 reward).

**Missions:** `signal_investigation` (Phase 1) and `return_with_evidence`
(Phase 2, after the reveal).

**Memories:** `memory_green_city` (Phase 1), `memory_city_green` and
`memory_green_coast` (Phase 2, both optional).

**Materials:** `scrap_metal`, `circuitry`, `polymer`.

**Components (Phase 1):**

| Slot | Ids |
|---|---|
| `computer` | `flight_computer_standard` |
| `propulsion` | `propulsion_light`, `propulsion_heavy` |
| `power` | `power_solar_array`, `power_rtg_cell` |
| `communications` | `comms_standard` |
| `sensor` | `sensor_low_gain`, `sensor_spectrometer`, `sensor_deep_field` |

**World objects:** spaceport — `briefing`, `construction`, `vela`, `launch`,
`crates`, `dish`. Crash site — `crash_vela`, `power_connection`, `bill_body`,
`salvage_plate`, `salvage_circuit`, `salvage_polymer`, `scrap_extra`.
Forgotten City — `memory_city_green`, `city_checkpoint`, `city_boss_gate`,
`salvage_city_scrap`, `salvage_city_boards`, `salvage_city_frame`.
Silent Coast — `coast_checkpoint`, `coast_boss_gate`, `memory_green_coast`,
`coast_records`, `sample_coast_water`, `sample_coast_sediment`,
`salvage_coast_plate`, `salvage_coast_cable`, `coast_power_core_drop` (only
between Toxic Tide's defeat and the pickup).

**Quest flags, Phase 1:** `briefing_read`, `design_confirmed`,
`preflight_passed`, `launched`, `rift_seen`, `crashed`, `vela_inspected`,
`power_repaired`, `bill_active`, `memory_viewed`, `coordinates_received`.

**Quest flags, Phase 4:** `final_assembly_complete`, `escape_seen`,
`return_objective_complete`, `mission_report_seen`, `qa_stage_skip_used`
(the last is diagnostic only and changes nothing).

**Quest flags, Phase 2:** `city_entered`, `city_checkpoint`,
`scrap_king_defeated`, `city_archive_restored`, `future_earth_revealed`,
`silent_coast_unlocked`, `coast_entered`, `coast_checkpoint`,
`toxic_tide_defeated`, `coast_archive_restored`, `coast_lesson_preserved`,
`dawn_tower_unlocked`, `base_returned`, `phase_two_complete`.

**Bosses:** `scrap_king`, `toxic_tide`. **Archives:** `city_archive`,
`coast_archive`. **Sites:** `forgotten_city`, `silent_coast`.

---

## 4. Data schemas

Every file in `data/star_fall/` is a JSON object with `schema_version` and a
`_note` describing the file. Nothing in the game is tuned in code.

### `ship_parts.json`

```jsonc
{
  "schema_version": 1,
  "program": {
    "title": "STAR FALL", "ship_name": "VELA",
    "start_credits": 100,          // construction budget, fictional credits
    "inventory_limit": 24,         // total carried items
    "walk_speed": 58.0, "run_speed": 98.0,   // world pixels per second
    "fuel_step_kg": 20.0
  },
  "hull": {
    "id": "standard_hull", "name": "...", "description": "...",
    "mass_kg": 900, "cost": 0,
    "launch_mass_limit_kg": 2000,  // hull structural limit
    "fuel_capacity_kg": 600,       // tank size
    "data_capacity_mb": 512        // recorded science
  },
  "mission_requirements": {
    "required_slots": ["computer","propulsion","power","communications","sensor"],
    "minimum_sensor_quality": 2,
    "minimum_fuel_kg": 180,
    "minimum_stored_energy_wh": 350,
    "observation_hours": 1.6       // energy window multiplier
  },
  "components": [{
    "id": "...", "slot": "...", "name": "...", "description": "...",
    "mass_kg": 0, "cost": 0,
    "power_demand_w": 0, "power_output_w": 0, "energy_storage_wh": 0,
    "thrust_capacity_kg": 0,       // propulsion only
    "sensor_quality": 0,           // sensor only
    "data_gain_mb": 0              // sensor only
  }],
  "salvage":      { "<object_id>": {"material": "...", "amount": 0} },
  "materials":    { "<material_id>": {"name": "...", "short": "..."} },
  "site_items":   { "<object_id>": {"name": "...", "interact_label": "..."} },
  "repair_cost":  { "<material_id>": 0 }
}
```

### `campaign.json`

```jsonc
{
  "schema_version": 1,
  "chapters":  [{"id": "...", "name": "...", "stage": "briefing|crash_site|forgotten_city|silent_coast|dawn_tower|deferred"}],
  "future_components": [{"id": "...", "name": "..."}],
  "missions":  [{"id": "...", "name": "...", "summary": "...", "requirements": ["..."]}],
  "memories":  [{"id": "...", "title": "...", "frame": "...", "lines": ["..."]}],
  "dialogue":  { "<key>": ["line", "..."] },
  "checkpoint": {"title": "...", "body": ["..."], "next_chapter": "..."}
}
```

`dialogue` keys used by the controller: `briefing_intro`,
`briefing_requirements`, `briefing_outro`, `construction_intro`,
`preflight_pass`, `preflight_fail`, `launch`, `rift`, `crash`,
`blueprint_memory`, `junction_repair`, `bill_activation`, `bill_idle`,
`crash_vela`, `crash_polymer`, `crash_rubble`.

### `sites.json`

```jsonc
{
  "schema_version": 1,
  "<site_id>": {
    "id": "...", "name": "...",
    "bounds": {"x": 0, "y": 0, "w": 640, "h": 360},
    "player_start": {"x": 250, "y": 270},
    "props": [{
      "sprite": "tree",              // key in sf_sprites.build_all()
      "x": 96, "y": 240,             // ground-contact point, world pixels
      "solid": [22, 10],             // ground collision footprint
      "interact": "salvage_plate",   // optional; makes the prop interactable
      "label": "Collect scrap metal",
      "lines": ["..."]               // optional inspection text
    }]
  }
}
```

---

## 5. Input actions

Declared in `project.godot`. Never read raw keycodes in gameplay code except in
the construction console and menu screens, which are panel-driven.

| Action | Keys | Used for |
|---|---|---|
| `move_up` | W, Up | Movement |
| `move_down` | S, Down | Movement |
| `move_left` | A, Left | Movement |
| `move_right` | D, Right | Movement |
| `run` | Shift | Movement speed |
| `interact` | E | World interaction, dialogue advance |
| `pause` | Esc | Pause, back, skip cutscene |
| *(UI)* Enter / Space | — | Confirm, advance dialogue |
| *(construction)* Left/Right, Q/E, V | — | Cycle part, fuel, preflight |
| *(Toxic Tide)* Mouse | — | Rotate the shield; no button held, always active |
| *(Toxic Tide)* Space | — | Counterattack, only when the charge meter is full |
| *(Eco Arena)* WASD / arrows | `move_*` | Move, diagonals normalised |
| *(Eco Arena)* Shift | — | Dash (short invulnerability, 1.5 s cooldown) |
| *(Eco Arena)* Mouse / left click | — | Aim / fire the Tri-Spectrum Blaster |
| *(Eco Arena)* 1 / 2 / 3, wheel | — | Green / Blue / Yellow spectrum |
| *(Eco Arena)* Right click / E (held) | `interact` | Bill's sorting beam |
| *(Eco Arena)* E | `interact` | Pick up the chip at Nick's feet |
| *(Eco Arena)* Esc | — | Pause: resume, sorting guide, restart, leave |
| *(archive)* Left/Right or A/D | — | Previous / next record |
| *(archive, progression)* Enter / E / Esc | — | Close the screen |
| *(typing)* A–Z | — | Type falling words; first letter selects, finishing fires |
| *(typing)* Backspace | — | Release the selected word (no penalty) |
| *(typing)* Esc | — | Pause: resume, vocabulary journal, restart, main menu |
| *(workshop)* Up/Down, Left/Right | — | Choose a row, change its option (Shift: fuel x5) |
| *(workshop)* V / F / C | — | Run simulation / fabricate / scavenge materials |
| *(final assembly)* Up/Down, Enter, Esc | — | Choose the row, activate, back |
| *(cinematic)* Esc, right click, II PAUSE badge | — | Shared pause menu (resume, skip sequence, settings, main menu) |
| *(cinematic)* Enter, NEXT badge | — | Advance a beat; CONTINUE / Enter on the closing card |
| *(cinematic, playable segments)* A / D, Left / Right, mouse | `move_left`, `move_right` | Steer across the debris corridor; line up under the portal |
| *(report, credits)* Up/Down, mouse wheel | — | Scroll |
| *(report, credits)* Enter / Space, CONTINUE / RETURN TO TITLE button | — | Continue (Esc pauses) |

Behaviour requirements honoured by the implementation:

- Diagonal movement is normalised, so diagonals are not faster.
- Collision is a small circle at Nick's feet against prop footprints.
- Movement is locked while a dialogue, the pause menu, or a panel screen is up.
- On application/window focus loss, all movement actions are released and the
  player's velocity is zeroed, so nothing sticks.
- In an encounter Nick cannot walk, sprint or dodge: there is no movement input
  path at all, so the fixed-position rule cannot be bypassed.
- The shield direction is read from the canvas-transformed mouse position, not
  from raw window pixels. While a dialogue is open over an encounter the arena
  is frozen and no combat key is consumed, so reading Bill's briefing is safe.
- Space is consumed as a just-pressed edge. Holding it never repeats a
  counterattack, and a press below full charge does nothing at all.
- In the typing encounter only fresh presses count (`echo` is ignored, so a
  held key never completes repeated letters), only `A`–`Z` reach the model
  (Shift, Ctrl, Alt, function and navigation keys never type), Ctrl/Alt/Meta
  chords are ignored, and every key is consumed by the screen so nothing leaks
  into movement, the shield duel, or the global `M` mute shortcut.

---

## 6. Signals and state mutation APIs

### `Events` (autoload)

`Emitted` means something in the shipped game fires it today. `Reserved` means
the signal is declared and documented but nothing emits it yet; do not build a
feature that assumes it fires.

| Signal | Payload | Meaning | Status |
|---|---|---|---|
| `preflight_passed` | — | Validation succeeded | Emitted |
| `preflight_failed` | `first_message: String` | Validation failed | Emitted |
| `salvage_collected` | `object_id, material: String, amount: int` | Pickup succeeded | Emitted |
| `inventory_full` | — | Pickup refused, no room | Emitted |
| `memory_viewed` | `memory_id: String` | Memory watched | Emitted |
| `game_saved` / `save_failed` | — / `reason: String` | Save outcome | Emitted |
| `campaign_stage_changed` | `previous, next: String` | Stage changed | Reserved |
| `design_changed` | — | Design edited (never on preview) | Reserved |
| `quest_flag_changed` | `flag: String, value: bool` | Flag changed | Reserved |
| `notice` | `text, tone: String` | Short on-screen notice | Reserved |

The controller already reads stage and flag transitions directly, so the
reserved signals exist for future listeners (achievements, analytics, a UI that
is not the controller) rather than for anything in Phase 1.

### `SFCampaign` (pure state, owned by `GameState`)

```gdscript
# Flow
advance_to(stage: String) -> bool
set_checkpoint(stage: String, chapter: String = "") -> void

# Flags
set_flag(flag: String, value: bool = true) -> void
has_flag(flag: String) -> bool

# Budget
spend(amount: float) -> bool
refund(amount: float) -> void

# Inventory (never negative, never over the limit)
add_material(material: String, amount: int) -> int   # returns amount accepted
remove_material(material: String, amount: int) -> bool
has_material(material: String, amount := 1) -> bool
inventory_used() / inventory_free() / inventory_limit() -> int

# Salvage (refuses duplicates)
claim_salvage(object_id: String) -> Dictionary  # {ok, material, added, message}
mark_collected(object_id: String) -> bool
is_collected(object_id: String) -> bool

# Crash-site quest
can_repair_junction() -> bool
repair_junction() -> Dictionary  # {ok, message}

# Design (preview is free; confirm is the atomic commit)
confirm_design() -> Dictionary   # {ok, checks, errors, manifest}
surviving_data_mb() -> float     # design-dependent post-crash science
crash_salvage_bonus() -> int     # design-dependent post-crash scrap

# Memory
view_memory(memory_id: String) -> bool
has_viewed_memory(memory_id: String) -> bool

# Phase 2 progression (all idempotent)
award_component(component_id: String) -> bool   # false if already recovered
has_component(component_id: String) -> bool
recovered_component_ids() -> Array
component_status() -> Array                    # every future component + recovered
restore_archive(archive_id: String) -> bool    # false if already restored
is_archive_restored(archive_id: String) -> bool
reveal_future_earth() -> bool                  # applies once; sets the mission
complete_silent_coast() -> bool                # applies once; unlocks Dawn Tower
# Phase 3 (all idempotent)
complete_boss(reward_flag, component_id) -> bool   # flag + award in one step (kept for tests; the game no longer uses it)
defeat_boss(reward_flag) -> bool               # victory only: the reward drops into the world
collect_boss_reward(reward_flag, component_id) -> bool  # the pickup; once, only after defeat
reward_state(reward_flag, component_id) -> String  # undefeated | available | collected | installed
install_component(component_id) -> bool        # recovered and not yet fitted; refused once assembled
is_component_installed(id) / installed_component_ids() / all_required_installed()
record_typing_attempt(attempt, order) -> void  # attempt history for word-order variation
complete_dawn_tower() -> bool                  # restores the archive, unlocks the workshop
record_vocabulary(entry_id) -> bool            # false if already in the journal
has_vocabulary(entry_id) -> bool
original_propulsion_id() -> String             # the day-one engine, for repair
store_reconstruction_selection(selection) -> void   # free; ignored once assembled
commit_reconstruction(selection, report) -> void    # called once by SFReconstruction.commit()
is_ready_for_final_assembly() -> bool
# Phase 4
begin_final_assembly(snapshot: Dictionary) -> bool   # false if already frozen
has_final_assembly_snapshot() -> bool
set_cinematic_skipped(value: bool) -> void
cinematic_skipped() -> bool
mark_escape_seen() -> bool
complete_return() -> bool                      # applies once; advances to return_home
is_return_complete() -> bool
mark_report_seen() -> void
is_finale_state() -> bool                      # at or past final_assembly
mark_qa_stage_skip_used() -> void              # diagnostic only
mission_id() / mission_data() / mission_name() -> ...
boss_for_chapter(chapter_id: String) -> Dictionary
```

### `SFFinale` (pure)

```gdscript
static workshop_for(campaign, reconstruction_data)          # the committed design
static stored_report(campaign) -> Dictionary                 # the certified report
static simulation_for(campaign, reconstruction_data) -> Dictionary
static prerequisites(campaign, reconstruction_data, others_clear) -> Dictionary
    # {ok: bool, checks: [{id, ok}]}
static build_report(campaign, reconstruction_data, finale_data) -> Dictionary
    # {objective_complete, memories, memory_count, samples_returned,
    #  records_returned, components, original_design, reconstructed_design,
    #  launch_mass_kg, dry_mass_kg, route_id, route_name, reserves,
    #  material_units, fabrication_units, material_cost, efficiency_kg_per_unit,
    #  debris_impacts, decisions, cinematic_skipped, score}
static score_for(campaign, report, finale_data) -> Dictionary
    # {objective, components, memories, payload, efficiency, total, formula}
static snapshot(campaign, reconstruction_data) -> Dictionary
```

### `SFQA` (pure milestone plan, tests only)

```gdscript
# The I + O + P latch (is_enabled / poll / armed / cooldown) is removed.
static next_milestone(campaign) -> String
static milestone_done(campaign, id) -> bool
static milestone_label(id) -> String
static apply_valid_day_one_design(campaign) -> bool          # QA only
static apply_valid_reconstruction(campaign, data) -> Dictionary   # QA only
```

### `SFEncounter` and its parts (pure)

```gdscript
# One fight. Owns the four parts below and the rules that span them.
setup(boss: Dictionary, all_data) -> void
reset() -> void                 # a retry: every encounter-local value
begin() -> void                 # leaves the intro phase
aim(cursor_canvas_position: Vector2) -> void
counterattack() -> bool         # one just-pressed edge; true when accepted
tick(delta: float) -> Array     # block/hit/absorb/strike/victory/defeat events
is_fighting() / is_over() / result() / phase() / health_fraction()

# SfShield: one authoritative direction, used by drawing and collision.
configure(config: Dictionary) -> void
begin_step() -> void
aim(nick_position: Vector2, cursor_position: Vector2) -> bool
set_direction(v: Vector2) -> bool
covers_point(nick_position: Vector2, point: Vector2) -> bool
outer_extent() -> float
charge_meter_offset() -> float
sweep_segments() -> Array
arc_points(nick_position: Vector2, segments: int, extra_radius: float) -> PackedVector2Array
arc_endpoints(nick_position: Vector2, extra_radius: float) -> Array
static canvas_point(mouse: Vector2, window_size: Vector2, base_size := Vector2(640, 360)) -> Vector2

# SfProjectileField: swept linear + angular motion, speed parity, one resolution per projectile.
configure(combat: Dictionary, types: Dictionary) -> void
spawn(type_id: String, position: Vector2, direction: Vector2, speed: float) -> Dictionary
sync_speeds(speed: float) -> void
update(delta: float, nick_position: Vector2, shield, body_radius: float, arena: Rect2) -> Array
active_count() -> int
clear() -> void

# SfPatternScheduler: spawn timing, telegraphs, health-band escalation.
configure(boss: Dictionary, combat: Dictionary, nick: Vector2) -> void
tick(delta: float, health_fraction: float, active_count: int) -> Array
fire_interval_for(fraction: float) -> float
projectile_speed_for(fraction: float) -> float
max_active_for(fraction: float) -> int
telegraph_for(fraction: float) -> float
band_for_fraction(fraction: float) -> Dictionary
set_seed(value: int) / seed_value() -> int
reset() -> void

# SfEncounterModel: health, charge, phases, counterattack arbitration.
configure(boss: Dictionary, combat: Dictionary) -> void
reset() -> void
begin_fight() -> void
damage_nick(amount: int) -> bool        # true on the killing blow
absorb_charge(amount: int) -> int       # charge actually added
request_counterattack() -> bool         # one per full charge, one per lock
apply_counterattack() -> bool           # true when the boss died
tick(delta: float) -> Array             # counter_strike / counter_done / victory_ready
charge_full() / charge_fraction() / health_fraction() / nick_fraction()
```

### `SFDesign` (pure)

```gdscript
set_slot(slot: String, component_id: String) -> void
clear_slot(slot: String) -> void
set_fuel(value: float, content) -> void
adjust_fuel(steps: int, content) -> void
summary(content) -> Dictionary       # every derived number, one pass
validate(content) -> Array          # one entry per check
is_valid(content) -> bool
first_blocking_failure(content) -> Dictionary
to_dict() / load_dict(data: Dictionary) -> void
```

A validation check is:

```gdscript
{"id": String, "ok": bool, "blocking": bool, "message": String, "hint": String}
```

`blocking = false` (the data-capacity check) reports a problem but never
prevents launch. A design is launchable only when every blocking check passes.

---

## 7. Save schema (v1 baseline; v2 section 13; v3/v4 section 19; v5 section 19a)

Path: `user://star_fall_save.json`. On Windows this resolves under
`%APPDATA%\Godot\app_userdata\STAR FALL\`.

```jsonc
{
  "version": 1,
  "stage": "crash_site",
  "chapter_id": "crash_site",
  "checkpoint_stage": "crash_site",
  "checkpoint_chapter": "crash_site",
  "credits": 100.0,
  "design": {"slots": {"computer": "...", "sensor": "..."}, "fuel_kg": 200.0},
  "confirmed_design": {"slots": {...}, "fuel_kg": 200.0},
  "inventory": {"scrap_metal": 4, "polymer": 2},
  "collected_items": ["salvage_plate"],
  "flags": {"briefing_read": true, "power_repaired": true},
  "viewed_memories": ["memory_green_city"],
  "mission_manifest": {"ship": "VELA", "hull": "standard_hull", "sensor_quality": 2, ...},
  "play_seconds": 0.0
}
```

Rules:

- Opening the main menu never writes or deletes a save.
- `Continue` is enabled only when the file parses and validates.
- A corrupt, empty or malformed save is **reported**, never silently replaced.
  The file is left on disk untouched.
- A save whose `version` is newer than the game reports a distinct status.
- Loading is all-or-nothing: `apply_save_dict()` runs on a live campaign only
  after the document passes structural validation.
- Unknown components are cleared; negative quantities are dropped or clamped;
  the design's fuel is clamped to the tank.
- Loading twice replaces state; it never merges, so inventory cannot duplicate.
- Version 2 adds three Phase 2 fields (section 13). Version 1 files still load:
  the missing fields fall back to safe defaults.

Load status codes: `ok`, `missing`, `corrupt`, `version`.

---

## 8. Simulation units and assumptions

| Quantity | Unit | Meaning |
|---|---|---|
| Component / hull mass | kg | Structural mass |
| Fuel | kg | **Rocket propellant.** Never electrical energy |
| Launch mass | kg | Dry mass + fuel |
| Power | W | Instantaneous electrical demand vs. supply |
| Stored energy | Wh | Battery, sized for the observation window |
| Budget | construction credits | Fictional currency |
| Data | MB | Recorded science, separate from propellant |
| Shield radius | world px | Distance from Nick at which a projectile crosses the shield |
| Shield coverage | degrees | Angular width of the shield's arc, always < 360 |
| Charge | charge points | Gained only from absorbed beneficial energy |
| Boss health | health points | Reduced only by accepted counterattacks |

Validation model (all values from `ship_parts.json`):

1. Every required slot is filled.
2. Sensor quality >= `minimum_sensor_quality`.
3. Launch mass <= min(hull limit, propulsion lift capacity).
4. Design cost <= `start_credits`.
5. Peak power demand <= power output.
6. Stored energy >= max(`minimum_stored_energy_wh`,
   `observation_hours` x peak power demand).
7. Fuel >= `minimum_fuel_kg` and <= tank capacity.
8. Data capture <= data capacity (informational only).

Balanced against the shipped data, five configurations are worth knowing:

| Config | Parts | Launch mass | Cost | Result |
|---|---|---|---|---|
| A (affordable) | light thruster, solar array, spectrometer | 1435 kg | 50 cr | **valid**, 23 MB survives |
| B (science) | heavy cluster, RTG cell, deep fields | 1825 kg | 86 cr | **valid**, 49 MB survives |
| C (underpowered) | heavy cluster, solar array, deep fields | 1750 kg | 72 cr | **fails**: power and energy |
| D (under-spec) | light thruster, solar array, low-gain | 1390 kg | 42 cr | **fails**: sensor quality |
| E (over-fueled) | config A with a 600 kg tank | 1835 kg | 50 cr | **fails**: lift capacity |

Every valid configuration can finish Phase 1 and reach the checkpoint. The
launch design changes the outcome in two measurable ways: surviving science
data (`surviving_data_mb`, keyed to sensor quality) and a small amount of extra
scrap recovered from the wreck.

The crash is a scripted external event. It is never the player's fault and the
UI never implies that a valid engineering decision caused it.

---

## 9. Running and verification

Godot in this workspace is **4.0 stable** and is not on `PATH`. Locate it, e.g.:

```
C:\Users\<you>\Downloads\Godot_v4.0-stable_win64.exe\<the executable>
```

Define it once in your shell for the commands below:

```bash
GODOT="/c/Users/<you>/Downloads/Godot_v4.0-stable_win64.exe/Godot_v4.0-stable_win64_console.exe"
```

### Run the game

- Editor: open `project.godot` in Godot 4.0 and press **F5**. The main scene is
  `scenes/star_fall/main.tscn`.
- Command line: `"$GODOT" --path .` (drop `_console` on the binary for the
  windowed build; `--path .` alone launches the project).

### Automated checks

```bash
"$GODOT" --headless --path . --script res://tests/star_fall/test_parse.gd
"$GODOT" --headless --path . --script res://tests/star_fall/test_logic.gd
"$GODOT" --headless --path . --script res://tests/star_fall/test_flow.gd
"$GODOT" --headless --path . --script res://tests/star_fall/test_encounter.gd
"$GODOT" --headless --path . --script res://tests/star_fall/test_phase3.gd
"$GODOT" --headless --path . --script res://tests/star_fall/test_phase4.gd
"$GODOT" --headless --path . --script res://tests/star_fall/test_flight.gd
"$GODOT" --headless --path . --script res://tests/star_fall/test_debug_jump.gd
"$GODOT" --headless --path . --script res://tests/star_fall/test_eco_arena.gd
```

Each prints `PASS`/`FAIL` per check and a `RESULT:` line, and exits non-zero on
failure. `test_encounter.gd` is the Phase 2 combat and persistence suite;
`test_phase3.gd` is the Phase 3 vocabulary, typing, pacing, workshop,
simulation and save suite; `test_phase4.gd` is the Phase 4 finale gate,
cinematic, report, score, save-version and QA-skip suite; `test_flight.gd`
covers the playable flight segments, the canonical VELA renderer (engine state
per presentation state, upright orientation, uniform scale, module positions),
shield contacts, the portal waiting for a visible entry, and per-scene cleanup;
`test_eco_arena.gd` is the Eco Arena rules, screen, practice-separation and
pacing-bot suite (it backs up and restores the save itself); `test_flow.gd` drives
the real main scene from the title to the credits, then walks the campaign again
with the QA skip.

**Warning:** `test_flow.gd`, `test_phase4.gd`, `test_flight.gd`,
`test_debug_jump.gd` and `capture.gd` delete
`user://star_fall_save.json`. Back up a real save before running them.

### Screenshots (needs a display, not headless)

```bash
"$GODOT" --path . --script res://tests/star_fall/capture.gd
"$GODOT" --path . --script res://tests/star_fall/capture.gd -- --shots=17,18
```

Writes 56 PNGs to `user://captures/` (01-36 the campaign and workshop, with
17-20c the Eco Arena guide, stages, boss, reward and summary and 23b the
power-core drop; 46-56 the Phase 4 finale, plus 22b). The arena shots depend
on each other: render them as `--shots=17,18,19,20,20b,20c`. The finale shots cover the eight VELA reference
frames: 36 workshop, 46/47 final assembly, 48/48b departure station and
boarding, 49b ignition, 49c vertical liftoff, 49 a shield contact in the
ascent, 50 the debris passage, 52/52b portal approach and entry, 53 home
landing with Nick stepping out, 53b Nick celebrating. `--shots=` renders only the named screens
(by their number prefix), which is the quickest way to re-check one pose. This
is a presentation aid only; it is not evidence that the game plays correctly.

### Debug hotkeys

Debug builds only (`OS.is_debug_build()`): `main.gd` adds `debug_jump.gd`,
which reads **Ctrl + Shift + Alt + key** in `_input()` (before any screen) and
consumes it. Digits 1–0 apply a preset from `sf_debug_presets.gd` (one per
phase entry point and boss fight, built cumulatively through the real campaign
methods) and resume through `_resume_from_campaign()`. V forces a win
(`SFEncounterModel.force_victory()` / `SFTypingEncounter.force_victory()`),
K heals Nick, M adds salvage, H toggles the on-screen list. The first jump of
a session copies the save to `user://star_fall_save.before_debug.json`. The
README lists every key.

The launch sequence cannot be skipped with Esc in any build (an earlier
headless-only skip was removed); use a hotkey to jump past it.

### What headless verification does and does not prove

Proven: scripts compile; validation, construction transactions, inventory and
save/load behave as specified; the real main scene boots; every screen
transition and every quest beat fires; skipping a cutscene preserves state;
Continue restores a save; the shield, projectile, scheduler, encounter and
progression models obey every rule in section 12 of the Phase 2 brief; both
Phase 2 fights can be won through their own rules and fully reset on retry;
the finale gate refuses to open on any missing prerequisite; the cinematic's
natural end and its skip both emit one outcome and apply identical state; the
report is deterministic and cannot be raised by farming; a skipped cinematic
never changes the score; a version 5 save round-trips the ending and a version 4
save still loads; and the QA skip walks the campaign in legal, resumable states
without leaving input locked.

**Not** proven: that anything looks right, that audio is audible, that the
window scales well, that the mouse aims the shield as it feels, that typing
feels responsive on a real keyboard, or that the fights are *fun* at the
intended difficulty. Those require playing it. The Phase 3 pacing numbers come
from scripted typing bots, not from people (section 17).

---

## 10. Completed scope

### Phase 1 (unchanged)

- Main menu: New Game, Continue (gated on a valid save), Settings, Quit.
- Present-day Earth: walkable spaceport with briefing terminal, VELA frame,
  assembly console, telemetry dish, crates, launch beacon, and a lit launch pad.
- Mission briefing with the six stated requirements.
- Construction loop: five slots, nine components, adjustable fuel load, live
  mass/power/energy/cost/data readout, a ship drawing that changes with the
  installed parts, preflight validation with actionable hints, and an atomic
  confirm that refuses an invalid design.
- Launch: the player-built VELA on the pad (engines off), ignition, liftoff,
  atmospheric ascent, Earth from orbit, a guided signal-tuning interaction
  (A / D reticle), the rift, and the crash transition. It cannot be skipped;
  Esc pauses it, and a save made during it replays it from the pad.
- Crash site: walkable area with the wreck, salvage, a dead power junction, and
  Bill's dormant body. Inspecting the wreck grants design-dependent salvage.
- Salvage and inventory with a hard carry limit, duplicate-proof pickups, and
  toast feedback.
- The Bill quest: inspect, salvage, repair the junction, activate Bill, watch
  the Green City memory, receive the Forgotten City coordinates.
- Versioned save at every beat; Continue restores the campaign faithfully and
  a corrupt save is reported rather than overwritten.
- Audio: dual-layer audio architecture with 43 high-fidelity 16-bit PCM WAV assets
  covering polyphonic SFX, character dialogue blips, environmental soundscapes,
  7 full background music themes (Title, Earth, Construction, Flight, Ruin, Memory,
  Checkpoint), and an instant fallback procedural synthesizer (`AudioStreamGenerator`).
- Transitions: cinematic scene transitions (smooth black alpha fades, white flash
  catastrophic rift impact, and retro shutter wipes) accompanied by spatial transition audio.
- Headless test suites (parse, logic, flow) and a screenshot tool.

### Phase 2 (this build)

- **Forgotten City.** A walkable ruined street with electronic waste, broken
  lamp posts, a maintenance shrine, a route checkpoint, optional salvage and the
  welded control-center door.
- **Scrap King** (`scrap_king`): since the Phase 2 revision, the **Eco Arena**
  waste-sorting arena survival (section 11a), ending with the Junkyard
  Colossus. Reward: `navigation_chip`, a physical pickup in the arena.
- **Control-center archive.** Five restored records covering the waste history,
  the ignored warnings, a surface image and the matching place names. Closing
  it applies the Future Earth reveal, changes the objective to
  `return_with_evidence`, and unlocks the Silent Coast.
- **Silent Coast.** A walkable harbor with a polluted tide line, a cleanup
  facility silhouette, bollards, drums, crates, optional samples and research
  records, a coastal memory projector and a route checkpoint.
- **Toxic Tide** (`toxic_tide`): the fixed-position, mouse-directed
  shield/absorption/counterattack duel with a marine silhouette, a deliberate
  rhythm, wide sprays, heavy projectiles and health-band escalation. Reward:
  `power_core`, dropped on the quay and collected with E (section 11a).
- **Environmental archive.** Five restored records, including the cleanup unit's
  own log. Unlocks the Dawn Tower and returns the campaign to the crash-site
  base.
- **Base return and Phase 2 summary.** The VELA recovery frame shows the
  navigation chip and power core fitted, the shield emitter still missing, the
  restored archives and the next objective. The summary keeps the save and (since
  Phase 3) continues into the Dawn Tower.
- **Persistence.** Save version 2 adds recovered components, restored archives
  and the active mission; version-1 saves still load. A retry of either boss
  resets only encounter-local state.

---

## 11. Phase 2 architecture

Since the Phase 2 revision only **Toxic Tide** uses this shield-duel engine in
play; the Scrap King encounter is the Eco Arena (section 11a).

The encounter is split into six parts, each pure and separately testable:

| File | Owns |
|---|---|
| `core/star_fall/sf_encounters.gd` | Loads `data/star_fall/encounters.json`. Lookups only. |
| `core/star_fall/sf_shield.gd` | The one authoritative shield direction, its coverage, and the window-to-canvas cursor transform. |
| `core/star_fall/sf_projectiles.gd` | The projectile field: swept collision, travel-order resolution, expiry, pruning. |
| `core/star_fall/sf_pattern_scheduler.gd` | Spawn timing, telegraphs, health bands, bounded escalation, seeded RNG. |
| `core/star_fall/sf_encounter_model.gd` | Nick's health, boss health, charge, phases and counterattack arbitration. |
| `core/star_fall/sf_encounter.gd` | The controller that glues the five above and enforces cross-cutting rules. |
| `scenes/star_fall/shield_duel.gd` | The duel screen: drawing, input, pause, result signal. |
| `scenes/star_fall/archive_screen.gd` | The archive restoration screen. |
| `scenes/star_fall/progression_screen.gd` | The base-return and Phase 2 summary readout. |

Rules this split enforces:

- The shield's `direction` is read by both the renderer and the collision test,
  so the visible arc and the blocked arc cannot disagree.
- Collision is swept: each frame's motion is a segment, and shield interception
  is solved before body impact, so a fast projectile is never tunnelled and a
  shield hit is never also a body hit.
- The screen never mutates campaign state. It reports one result through
  `duel_finished`; `main.gd` records the defeat and saves, and the component
  drops into the world to be picked up (section 11a).
- Rewards are idempotent in the campaign (`award_component` refuses a duplicate,
  `reveal_future_earth` and `complete_silent_coast` each apply once), so a
  replayed, skipped or restored scene produces the same state.
- A fight is never serialised mid-encounter. The checkpoint written immediately
  before the encounter is the resume point, and a retry rebuilds the encounter
  from data.

### Encounter phases

```
intro -> fight -> counter -> fight -> ... -> victory
                  |                     |
                  +-> defeat -----------+-> retry resets to intro
```

- `intro`: the briefing dialogue plays over a frozen arena. Nothing spawns.
- `fight`: projectiles live, the shield steers, Space arms the counterattack.
- `counter`: a counterattack resolves. The field is cleared and the scheduler is
  held, so a locked shield can never be punished.
- `victory`: attacks stop, live projectiles are cleared, and the result is
  reported once. Leftover projectiles cannot hurt Nick.
- `defeat`: damage, spawning, charge and counterattack input all stop; the retry
  option is offered and resets every encounter-local value.

### Progression stages

```
checkpoint -> city_intro -> [city_boss] -> city_archive
           -> silent_intro -> [coast_boss] -> coast_archive
           -> base_return -> phase_two_complete -> complete
```

`city_boss` and `coast_boss` are never checkpointed mid-fight; the checkpoint
before them is the resume point.

---

## 11a. Phase 2 revision: the Eco Arena (Scrap King) and physical boss rewards

The first Phase 2 encounter is no longer a shield duel. The **Scrap King**
encounter (boss id, flag, reward and archive unchanged) is played as the
**Eco Arena**, an educational arena survival about waste sorting. Toxic Tide
keeps the shield duel exactly as before: mouse shield, hostile and beneficial
energy, charge, Space counterattack, health-band escalation and the swept
blocking fixes are untouched.

### One implementation, two entry points

| Entry | Where | Mode | Reports to the campaign |
|---|---|---|---|
| Campaign | Forgotten City, control-center door (after the checkpoint) | `campaign` | `boss_defeated` and `reward_collected` |
| Practice | Main menu, **ECO ARENA — 5-7 MIN** (locked until the campaign defeats the Scrap King) | `practice` | nothing |

`core/star_fall/sf_eco_arena.gd` (pure rules, no nodes) and
`scenes/star_fall/eco_arena_screen.gd` (guide, camera, drawing, HUD, pause,
defeat, summary) are shared; `main.gd` only chooses the mode and connects the
two campaign signals in campaign mode. Session state lives entirely in the
model, so practice never touches `GameState.campaign` or the save file. The
practice unlock is a local preference (`practice_unlocked` in
`user://star_fall_settings.cfg`), set when the campaign records
`scrap_king_defeated` (live, or found in an existing save). The Junkyard Colossus
is the arena's final enemy inside the Scrap King encounter, not a fourth
campaign boss.

### STAR FALL's three colors

This is a simplified convention for this game, presented as STAR FALL's own,
not a universal standard. There are no hazardous, battery or glass categories.

| Key | Color / name | Shape | Items |
|---|---|---|---|
| 1 | Green / ORGANIC | round | banana peel, food scraps, leaves, food-soiled uncoated pizza box |
| 2 | Blue / CLEAN PAPER | square | clean cardboard, dry newspaper, office paper |
| 3 | Yellow / PLASTIC & METAL | tall | empty plastic bottle, drink can, tin can, crushed empty can |
| 1 then 3 | residue bottle | — | the leftover drink (Green) before the empty bottle (Yellow) |
| 1 then 2 | box full of leaves | — | the leaves (Green) before the clean box (Blue) |

Every item has a 16x16 badge (`sf_eco_sprites.gd`), shown over the targeted
enemy and beside a dirty core in beam range. Stage 1 badges carry a glowing
border in the answer color; from stage 2 the border is neutral. Category
names, icons and shapes appear on the guide, the HUD slots, the crushers and
the combo pips, so color is never the only cue.

### Rules

- **Combat.** A bolt in the matching spectrum deals `reference_damage x
  match_multiplier` (4 x 2.5) to the exposed armor layer and knocks the enemy
  back. The wrong spectrum deals zero, shows a deflection and triggers one
  rate-limited Bill callout (a trick or layered item may replace a basic one).
  Overflow damage is discarded, so one hit never reaches a hidden layer.
  Bolts use a swept segment test and resolve once. A bolt hits anywhere on
  the enemy's drawn body (`body_rect`, also used for the Colossus); touch
  damage, crushers and walls use the foot circle.
- **Cores.** Every death goes through one path (`_kill_enemy`): one core per
  enemy, never collected automatically. Standard cores are worth 4 points,
  dual cores 8 (one pickup, its shells in the enemy's layer order). Touching a
  dirty core with the wrong color gives a harmless spark and a nudge, with a
  cooldown; the matching color (touch, or Bill's beam held on Right Click / E)
  removes one shell at a time. A clean core within beam range flies into
  Nick's pack and is collected exactly once.
- **Beam target rule.** Keep the current core while it stays a dirty core in
  range; otherwise take the nearest dirty core within `beam_range` (lowest id
  breaks a tie). Releasing, pausing or being defeated stops it.
- **Crushers.** Only a *charging* enemy that reaches a crusher mouth triggers
  it. A matching crusher strips the exposed layer: a single-layer enemy (or an
  elite's last layer) is recycled through the normal death path and drops one
  pre-cleaned physical core; an elite with layers left keeps them and is
  stunned. A mismatched crusher only bounces the enemy (no damage, no drop, no
  accuracy decision).
- **Eco Overdrive.** Collecting Green, Blue and Yellow *standard* cores in a
  row (any order, no mismatch between) starts 8 s of +30% speed, +25% shield
  regeneration and a rainbow spectrum that matches the exposed combat layer.
  Values are computed from the base stats while the timer runs, so they return
  exactly afterwards; a retrigger refreshes the timer to 8 s and never stacks.
  A wrong-color hit or cleaning attempt breaks the combo; dual and super cores
  never count. Overdrive never cleans cores.
- **Health and shield.** Damage hits the shield first, then health. Zero
  shield is survivable; zero health is defeat. The shield regenerates after a
  delay. A short hurt window, the dash window and every non-fight phase block
  damage. Defeat stops everything, and Retry (after 0.5 s) resets only the
  arena and skips the guide.
- **Dash.** Shift: 0.16 s at 360 px/s, 0.24 s invulnerable, 1.5 s cooldown.
  Movement is resolved in sub-steps against the walkable rectangle, the
  station, the crushers and the boss, so a dash cannot pass a boundary.
- **Bill** hovers behind and beside Nick, keeps a minimum gap, snaps back when
  separated, is never targeted and never absorbs a shot.

### Energy-driven progression

Stages change when station charge *reaches or crosses* a threshold (24 -> 28
enters stage 2). Ordinary cores cannot raise the station above 80%.

| Stage | Charge | Content |
|---|---|---|
| 1 Warm-up | 0 -> 25 | single-material basics, bordered badges |
| 2 Look-alike traps | 25 -> 55 | pizza box (Green), office paper (Blue), crushed can (Yellow); no borders |
| 3 Multi-layer elites | 55 -> 80 | residue bottle and leaf box (dual cores) |
| Boss | 80 | the Junkyard Colossus spawns once; waves stop |

The Colossus wears Green, then Blue, then Yellow armor. It takes no damage
during its entrance or between armors, and every pending toss zone and junk
ring is cleared at each change. The Colossus' attacks are telegraphed: trash-toss
landing zones around Nick (with gaps to dash into) and a junk ring with a gap.
On defeat every enemy and projectile is cleared and two drops appear: the
three-lock **Super Core** and the **navigation chip** (a TRAINING CHIP in
practice). The Super Core always needs a manual 1 -> 2 -> 3, takes the station
from 80 to 100, and victory needs both the full station and the chip, in
either order. The summary never opens before both.

### Accuracy and rank

Eligible decisions: the first manual color decision for each enemy armor
layer (`e<id>:<layer>`) and the first cleaning decision for each core shell
(`c<id>:<shell>`). A held burst counts once; repeated pickups or callbacks
add nothing; Overdrive hits are excluded. Accuracy = correct / eligible, and
1.0 when there are no decisions. Ranks (`ranks` in data, first match wins):
**S** accuracy >= 0.90 and time <= 7:00, **A** >= 0.75 and <= 10:00, else
**B**. Time is the active match clock only: the guide, pause and reduced
motion never count. The summary names the most-mismatched item's reminder.

### Physical boss rewards and persistence

Both Phase 2 bosses now drop their component into the world. Nothing is
granted on boss death. The three facts are the existing ones from Phase 3:

| State | Derived from |
|---|---|
| undefeated | the boss flag is unset |
| available (drop in the world) | the flag is set and the component is not in `recovered_components` |
| collected | the component is in `recovered_components` |
| installed | the component is fitted in the workshop |

- **Scrap King.** The Colossus' defeat calls `defeat_boss("scrap_king_defeated")`
  and saves; picking up the chip calls `collect_boss_reward(..., "navigation_chip")`
  and saves. Leaving or reloading in between reopens the arena in its reward
  state (station at 80, boss down, Super Core and chip waiting), from the door
  or from Continue.
- **Toxic Tide.** Victory calls `defeat_boss("toxic_tide_defeated")`, returns
  the stage to `silent_intro`, frees the duel screen (and with it the
  fixed-position lock and every projectile), and the world shows the
  `coast_power_core_drop` prop below the facility gate. E collects it once,
  then the victory lines and the environmental archive follow. The facility
  door, the objective line and the route cue point at the core until then.
- **Older saves** need no migration: a save from the old build that has a boss
  flag also lists its component, so it reads as collected and nothing is
  replayed. A defeated boss whose component is missing reads as available and
  its pickup is restored (arena reward state, or the quay drop). Save version
  stays 5; no field was added.
- The QA stage skip (`_award_boss_victory`) records the defeat and collects the
  drop in one step through the same idempotent methods.

### Data: `data/star_fall/eco_arena.json`

```jsonc
{
  "world": {"width": 1280, "height": 960, "walkable": {...}, "nick_start": {...},
            "boss_spawn": {...}, "reward_spawn": {"super_core": {...}, "navigation_chip": {...}}},
  "station": {"x", "y", "solid_radius", "ring_radius"},
  "crushers": [{"id", "category", "x", "y", "solid_radius", "mouth_radius", "cooldown"}],
  "spawn_points": [{"x", "y"}],
  "categories": {"<cat>": {"name", "card_title", "key", "color", "dark", "shape", "icon",
                           "slot_lines", "explanation", "examples": ["<item>"]}},
  "category_order": ["green", "blue", "yellow"],
  "guide": {"title", "subtitle", "rules": []},
  "items": {"<item>": {"name", "category", "trick"?, "layers"?, "layer_badges"?,
                       "callout" | "layer_callouts", "reminder"}},
  "nick": {"health", "shield", "shield_regen_per_second", "shield_regen_delay", "speed",
           "radius", "hurt_invulnerable_seconds"},
  "dash": {"cooldown", "duration", "speed", "invulnerable_seconds"},
  "blaster": {"fire_interval", "projectile_speed", "projectile_radius", "projectile_life",
              "reference_damage", "match_multiplier", "knockback", "muzzle_offset"},
  "cores": {"standard_value", "dual_value", "super_value", "radius", "contact_radius",
            "beam_range", "beam_clean_seconds", "spark_cooldown", "nudge", "magnet_speed",
            "collect_radius", "chip_pickup_radius"},
  "overdrive": {"duration", "speed_multiplier", "regen_multiplier", "retrigger"},
  "bill": {"follow_distance", "side_offset", "lerp_rate", "min_gap", "recover_distance"},
  "callouts": {"cooldown", "show_seconds"},
  "pacing": {"spawn_telegraph", "min_spawn_distance", "first_spawn_delay", "seed",
             "charge_cooldown_min", "charge_cooldown_max", "charge_telegraph",
             "charge_speed", "charge_duration", "charge_trigger_range", "contact_cooldown"},
  "stages": [{"id", "name", "until", "bordered_badges", "spawn_interval",
              "group_min", "group_max", "max_alive", "pool": {"<enemy>": weight}}],
  "boss_at": 80,
  "enemies": {"<enemy>": {"item", "layers": [], "armor", "speed", "radius",
                          "contact_damage", "silhouette", "core": "standard|dual",
                          "charges", "stained"?, "elite"?}},
  "boss": {"id", "name", "layers", "layer_items", "armor", "speed", "radius",
           "contact_damage", "transition_seconds", "entry_seconds",
           "toss": {"interval", "telegraph", "radius", "damage", "targets", "spread"},
           "ring": {"interval", "count", "gap", "speed", "radius", "damage", "life", "telegraph"}},
  "ranks": [{"rank", "min_accuracy", "max_seconds"}],
  "practice_reward": {"name", "label"}, "campaign_reward": {"name", "label"}
}
```

`scrap_king` stays in `encounters.json` as the encounter's identity (id,
chapter, reward flag, component, archive). Its duel tuning is no longer
played; it remains a regression fixture for the shared duel engine.

### Pacing (measured on a bot, not on people)

`test_eco_arena.gd` plays four complete runs with a scripted bot that aims
perfectly, reacts instantly, uses the beam and dodges toss zones, at 0% and
25% wrong first choices. Measured on this build: **3:33 to 3:34** of match
time to victory, accuracy 89-93%, rank S or A, with body-sized shot hitboxes.
Human players aim, read and
walk more slowly, so a real run is expected to land in the 5-7 minute target,
but no player (and no child) has timed it yet. The pacing levers are the
stage `spawn_interval`, enemy `armor` and boss `armor` in data.

### Known limitations

- Visuals, audio, aiming feel and pacing for real players are unverified;
  the bot times above are the only measurement.
- Enemies chase in straight lines and slide around the station and crushers;
  there is no path-finding.
- A single seeded spawn sequence per attempt (`pacing.seed`); runs differ only
  through the player's actions.
- The new material and blaster sounds are short synth cues (no recorded
  samples). The blaster zap is quiet, pitched per spectrum, and gated to at
  most one per 0.12 s so held fire never stacks into a drone.
- Play Again in the campaign replays the arena for practice; the chip and the
  boss are already recorded, so it changes nothing in the campaign.

---

## 12. Phase 2 data (`data/star_fall/encounters.json`)

All tuning lives here. No script contains a balance value.

```jsonc
{
  "arena":      {"width": 640, "height": 360,
                 "nick": {"x": 320, "y": 244}, "ground_y": 300},
  "shield":     {"radius": 44.0, "coverage_degrees": 72.0, "thickness": 6.0,
                 "contact_tolerance": 3.5, "angular_tolerance_degrees": 3.5,
                 "charge_meter_margin": 16.0,
                 "min_cursor_distance": 14.0, "body_radius": 8.0,
                 "initial_direction": {"x": 0.0, "y": 1.0}},
  "combat":     {"counterattack_lock_seconds": 0.55, "victory_hold_seconds": 1.6,
                 "projectile_life_seconds": 14.0, "offscreen_margin": 48.0,
                 "min_telegraph_seconds": 0.35, "max_telegraph_seconds": 0.85},
  "projectile_types": {
    "<type_id>": {"family": "hostile|beneficial", "name": "...", "damage": 0,
                  "charge": 0, "radius": 0.0, "speed_scale": 1.0,
                  "shape": "chevron|dart|shard|blob|bolt|diamond|orb",
                  "color": "rrggbb", "outline": "rrggbb", "trail": "rrggbb"}
  },
  "bosses": [{
    "id": "scrap_king|toxic_tide", "chapter_id": "...",
    "name": "...", "subtitle": "...",
    "boss_health": 100, "nick_health": 100, "charge_max": 100,
    "counterattack_damage": 25,
    "reward_component": "navigation_chip|power_core",
    "reward_flag": "scrap_king_defeated|toxic_tide_defeated",
    "archive_id": "city_archive|coast_archive",
    "seed": 71203,
    "visual":   {"silhouette": "industrial|marine", "shell": "...", "armor": "...",
                 "armor_light": "...", "glow": "...", "eye": "...", "screen": "..."},
    "emitters": [{"id": "...", "x": 0, "y": 0, "label": "..."}],
    "beneficial": {"type": "...", "emitters": ["..."],
                   "telegraph": 1.0, "interval": 6.2},
    "limits":   {"min_fire_interval": 0.78, "max_projectile_speed": 205.0,
                 "max_active": 14, "max_volley": 3},
    "bands": [{"at_fraction": 1.0, "fire_interval": 2.35,
               "projectile_speed": 92.0, "max_active": 6, "telegraph": 1.2,
               "beneficial_interval": 6.2, "patterns": ["lane_single", "..."]}],
    "patterns": {"<name>": {"emitters": ["..."], "count": 1, "volley": 1,
                            "type": "bolt", "spread_degrees": 0.0,
                            "jitter_degrees": 6.0, "stagger": 0.0}}
  }],
  "archives": {"<id>": {"id": "...", "boss_id": "...", "title": "...",
                        "subtitle": "...", "unlock_flag": "...", "reveal_flag": "..."}}
}
```

Band semantics: `at_fraction` is the health fraction at which that band
**begins**, and the last band covers everything below its own threshold. The
scheduler picks the highest threshold at or below the current fraction, so
lower health always means a faster, harder band. Both `fire_interval` and
`projectile_speed` are clamped by the boss's `limits` block.

Archive prose (headings and lines) lives in `campaign.json` under `archives`,
next to the dialogue and memories, so all readable text is in one file.

---

## 13. Phase 2 save schema (version 2)

Version 2 adds three fields. Version 1 documents still load: missing fields
fall back to safe defaults, and the active mission is recovered from
`future_earth_revealed` when it is absent.

```jsonc
{
  "version": 2,
  "stage": "phase_two_complete",
  "chapter_id": "crash_site",
  "recovered_components": ["navigation_chip", "power_core"],
  "restored_archives": ["city_archive", "coast_archive"],
  "active_mission": "return_with_evidence",
  // ... every version 1 field, unchanged
}
```

Rules:

- A component is recorded at most once; `award_component` refuses a duplicate
  and `apply_save_dict` de-duplicates on load.
- `restored_archives` records which archive scenes have been applied. The
  outcomes themselves live in flags, so skipping the reading still counts.
- `active_mission` is `signal_investigation` or `return_with_evidence`. It
  changes exactly once, at the Future Earth reveal.
- An active projectile, telegraph or partial fight is never saved.

---

## 14. Phase 2 stable IDs

| Kind | id |
|---|---|
| Boss | `scrap_king`, `toxic_tide` |
| Reward | `navigation_chip`, `power_core` |
| Archive | `city_archive`, `coast_archive` |
| Memory | `memory_city_green`, `memory_green_coast` |
| Mission | `signal_investigation`, `return_with_evidence` |
| Stage | `city_intro`, `city_boss`, `city_archive`, `silent_intro`, `coast_boss`, `coast_archive`, `base_return`, `phase_two_complete` |
| Flag | `city_entered`, `city_checkpoint`, `scrap_king_defeated`, `city_archive_restored`, `future_earth_revealed`, `silent_coast_unlocked`, `coast_entered`, `coast_checkpoint`, `toxic_tide_defeated`, `coast_archive_restored`, `coast_lesson_preserved`, `dawn_tower_unlocked`, `base_returned`, `phase_two_complete` |
| Site | `forgotten_city`, `silent_coast` |
| World object | city — `memory_city_green`, `city_checkpoint`, `city_boss_gate`; coast — `coast_checkpoint`, `coast_boss_gate`, `memory_green_coast`, `coast_records`, `sample_coast_water`, `sample_coast_sediment` |
| Salvage | `salvage_city_scrap`, `salvage_city_boards`, `salvage_city_frame`, `salvage_coast_plate`, `salvage_coast_cable` |

`shield_emitter` remains declared and deliberately unrecovered: it belongs to
Phase 3. Eco Arena ids (item, enemy, crusher and boss ids such as
`junkyard_colossus`) live only in `eco_arena.json` and are never saved.

---

## 15. Phase 4: finale, ending and QA skip

Phase 4 turns READY_FOR_FINAL_ASSEMBLY into the end of the campaign. It adds one
data file, two pure rules modules, four screens and one save field. It does not
change any earlier phase's rules.

| File | Owns |
|---|---|
| `core/star_fall/sf_finale.gd` | Finale prerequisites, the mission report built from the recorded run, the published score |
| `core/star_fall/sf_qa.gd` | The milestone plan and two data-driven design builders, used only by the tests (the `I + O + P` skip is removed) |
| `scenes/star_fall/final_assembly_screen.gd` | The pre-finale gate, the confirm latch, the install animation |
| `scenes/star_fall/cinematic_screen.gd` | The six-scene escape, subtitles, pause and skip |
| `scenes/star_fall/mission_report_screen.gd` | Report layout, measured rows, scrolling |
| `scenes/star_fall/credits_screen.gd` | The credit roll and the closing card |
| `data/star_fall/finale.json` | All Phase 4 copy, timings, score weights, credits, QA settings |

### Rules the split enforces

- Screens own no campaign state. The final-assembly gate emits
  `assembly_started`; `main.gd` freezes the snapshot, advances the stage, writes
  the checkpoint and saves before the install animation begins.
- The cinematic emits `cinematic_finished(skipped)` exactly once, whether it ends
  naturally or is skipped. Every persistent outcome (`escape_seen`,
  `return_objective_complete`, the stage, the checkpoint, the skip record) is
  applied in `main.gd`, so watching and skipping cannot diverge.
- The final-assembly confirm is latched twice over: the screen's `_started` flag
  and `SFCampaign.begin_final_assembly()`, which refuses a second snapshot. A
  double click therefore cannot open two sequences or write two checkpoints.
- The report and the score read only recorded state. `build_report()` recomputes
  the simulation from the committed design with the same code the workshop used,
  so the report can never disagree with the report a player passed.
- The workshop is locked once `ready_for_final_assembly` is set; the finale stage
  additionally freezes it via `is_finale_state()`.

### Finale prerequisites

`SFFinale.prerequisites()` returns six checks, evaluated live on every gate
entry and again on confirmation:

| id | Condition |
|---|---|
| `bosses` | `scrap_king_defeated`, `toxic_tide_defeated`, `sky_remnant_defeated` |
| `components` | `navigation_chip`, `power_core`, `shield_emitter` all recovered |
| `fabricated` | the committed reconstruction record exists |
| `payload` | the committed design carries Bill's memory core and the evidence archive |
| `simulation` | recomputing the committed design still passes, and its signature matches the stored report |
| `clear` | no dialogue, cutscene or transition is running |

### The canonical VELA (`core/star_fall/sf_vela.gd`)

One renderer draws VELA everywhere from the workshop on: the reconstruction
workshop, the final-assembly preview and every cinematic shot. No other
drawing of the ship exists (the old side-view `vela_ship` sprites and the
nose-right flight art were removed). The design source is the workshop
drawing: long gray segmented hull, stepped tapered nose, rear engine block
with a wide nozzle bell, five panel seams, a dorsal emitter mast, cyan accents
(cockpit glass, nozzle lips, module lights) and three module positions.

- **Geometry** lives once, in ship units: `u` along the hull (0 = nozzle exit,
  `LENGTH` 97 = nose tip), `v` across it (negative = dorsal/mast side),
  `HALF_WIDTH` 9. Scale is a whole number (workshop 2, everything else 1), so
  edges stay crisp and nothing is stretched.
- **Orientation is a mapping, not a rotation.** `maintenance` maps `u` to +x
  (nose right, workshop cradle). Every other state maps `u` to -y: nose up,
  nozzles and legs at the bottom.
- **Presentation states and engines.**

  | State | Where | Engines | Legs |
  |---|---|---|---|
  | `maintenance` | workshop | off (ready glow only once assembled) | cradle |
  | `parked` | final assembly, departure station, launch t < 1 s | off | down |
  | `ignition` | launch, on the pad | on | down |
  | `ascending` | climb, debris passage, sunlight, portal approach | on | stowed |
  | `portal_entry` | portal, after capture | on | stowed |
  | `descending` | home, powered descent | on | down |
  | `landed` | home, after touchdown | off | down |

  `SFVela.engines_on(state)` is the only switch: a parked or landed ship never
  draws a flame, whatever thrust a caller passes. Flame, legs, boarding ramp and
  shield are drawn in screen space from the mapping, never by rotating the
  composition, so they cannot end up on the wrong side.
- **Modules** (`navigation_chip`, `power_core`, `shield_emitter`) sit at fixed
  ship-unit positions. The workshop places its install sockets from the same
  table, so a fitted part is in the same place in every view. Callers pass the
  fitted list from the campaign; the finale passes the frozen design's modules.
- **Hatch and ramp.** One access hatch, low on the ventral side, with a 45-degree
  boarding ramp. Nick boards through it at the departure station and leaves
  through it at home.
- **Shield.** `draw_shield()` wraps the whole silhouette (half-extents 21 x
  59.5 px at scale 1) and draws a ripple and sparks at each contact point.
- The renderer is pure presentation: it reads no campaign state and plays no
  audio, so the final-assembly preview cannot trigger engine or impact sounds.
- **Assets and sources.** No external asset was added. VELA, the departure
  station and the home spaceport are drawn in code (original). The home scene
  reuses the project's own generated `tree`, `bush`, `lamp` and `dish` sprites;
  the departure scene reuses `terminal`, `rubble`, `bill_on` / `bill_off` and
  Nick's walking sprites. Removed: the `vela_ship`, `vela_ship_gear`,
  `nick_portrait` and `nick_standing` sprites. Contact sounds reuse the existing
  `sfx_shield_block` (synth) and `sfx_impact` (project sample, synth fallback).

### Cinematic

Six scenes, each with its own duration and ordered subtitles, plus the closing
card. All copy and timing is in `finale.json`; the screen has no prose.

| Scene | What it shows | Recorded state it reads |
|---|---|---|
| A `leaving_crash_site` | Departure station: VELA parked upright on a pad with a service gantry, umbilical arm, floodlights and fuel tanks. Bill at the service terminal streams his memory core into the ship (progress readout, packets on the cable); a DONE cue; Bill's shell powers down. Nick walks to the ramp and boards; the hatch seals, the ramp and umbilical retract, the departure checks go green. Engines off throughout. | the cable is lit only if `power_repaired`; the ship carries the fitted modules |
| B `launch` | Ignition on the same pad (smoke, dust, thrown scrap, a small rumble), vertical liftoff, the camera holding the ship as the station drops away, then the junk strata streaming past with twelve choreographed shield contacts | none |
| C `debris_passage` | Playable. VELA climbs upright; bodies fall toward it. Grit and near misses meet the shield; a big body on the hull restarts the segment | the certified route, the strikes actually taken |
| D `sunlight` | Warm light, the waste-wrapped planet, Bill's last question; VELA upright on a low burn | none |
| E `portal` | Playable alignment, then an automatic capture: the ship is pulled onto the portal's axis, accelerates up into the rim, is masked at the portal plane, and only then does the flash and the transition come | none (fiction, labelled in-game) |
| F `home` | A redrawn healthy spaceport in the game's angled 2.5D pixel style (pad, service road, receiving station, tracking dish, the Earth level's trees, bushes and lamps, Y-sorted with contact shadows). VELA descends, lands, engines off; hatch opens, ramp lowers; Nick walks out and celebrates (two hops, arm up, a wave). No close-up | the memory count drives the archive packets and the lit windows |

The final card is the two-line message from the brief. No effects run over it.

**Shield contacts.** Every ripple, impact sound and shake is tied to a visible
contact. In the launch they are choreographed: `LAUNCH_CONTACTS` in
`cinematic_screen.gd` times each one from the moment its stratum reaches the
ship, and a body is drawn flying into the contact point and glancing off. In the
debris passage `SFFlight` reports a `shield` event at the real boundary point
when grit is absorbed or a large body grazes the bubble (the body is then pushed
aside, never through the hull). Light contacts play `sfx_shield_block`, heavy
ones `sfx_impact`, rate-limited (0.12 s / 0.22 s) so bursts never stack. Shake
is small, decays to zero, is recomputed every frame (no drift), never moves the
HUD and is off under reduced motion; the ripple still shows.

**Flight axes.** `SFFlight` stays axis-neutral: `x` is along-track, `y` is the
steered axis. The screen maps `x` up the screen (`screen_y = 360 - x`) and `y`
to screen x, so the playable segments fly the same upright ship as the rest of
the sequence. A / D, Left / Right or the mouse steer.

**Portal timing.** `SFFlight` reports `captured` after `align_seconds` in the
mouth (or when the navigation assist takes over) and `entered` only once
`ship_x - ship_half_length >= portal_x`, i.e. when the whole hull is through.
The screen holds the scene until `entered`, then plays a 1.2 s flash; no timer
or "next beat" key can advance the portal scene early. SKIP SEQUENCE in the
pause menu still skips the whole sequence safely.

**Cleanup.** `_next_scene()` and `_finish()` clear contacts, shake, flight
state and notices, so no effect leaks into the next beat.

**Skip and resume.** Esc, right click or the II PAUSE badge opens the shared
pause menu (focus loss also pauses); SKIP SEQUENCE there skips. Repeated skip
input is idempotent. Space and other keys do nothing. A save written during `escape` resumes at the start of
the escape; the documented safe checkpoint is `final_assembly`, and continuing
from it replays the sequence rather than resuming mid-scene. Nothing is
serialised mid-cinematic.

### Mission report and score

The report shows: return objective, archived memories, samples and records
returned, components fitted, the original and reconstructed designs, final
launch mass, selected route, simulated propellant and energy reserves, material
efficiency (dry kg per salvage unit), the decision explanations, and the score.

The score is published in `finale.json` (`report.score`) and applied by
`SFFinale.score_for()`:

```
score = 100 (return objective complete)
      + 25 per recovered component fitted
      + 15 per archived memory
      + 20 per optional payload flown (environmental samples, additional records)
      + efficiency, up to 30 = 30 * clamp(propellant_reserve_fraction / 0.5, 0, 1)
```

Rules: it reads only recorded state; it never reads inventory size or play time,
so stockpiling cannot raise it; it never penalises accessibility settings or a
skipped cinematic; and several engineering approaches reach the same total
because the efficiency term rewards margin rather than a single best build.

### Milestone driver (tests only)

The former `I + O + P` stage skip is removed: no key, chord, launch flag or
build type reaches it. `SFQA` keeps only the milestone plan (`briefing`,
`construction`, `bill`, `phase_one`, `city`, `coast`, `phase_two`, `dawn`,
`workshop`, `ready`, `finale`, `report`, `done`) and the two design builders,
and `main.gd::_apply_qa_skip()` survives as the headless test driver that walks
a campaign through the same campaign methods the normal flow uses. Only
`tests/star_fall/test_flow.gd`, `test_phase4.gd` and `capture.gd` call it.

### Dawn Tower flow

```
Phase 2 summary -> dawn_intro (world) -> survey projector (memory_healthy_forest)
  -> boardwalk checkpoint -> tower gate -> dawn_boss (typing)
  -> victory -> slope (shield emitter drop, exploration restored)
  -> pick up the emitter (E) -> dawn_archive -> reconstruction (workshop)
  -> install the three parts -> simulate -> fabricate
  -> ready_for_final_assembly (summary) -> title
```

The tower gate refuses entry, in the fiction, until the forest memory has been
seen and the checkpoint used. The defense console (optional) explains the
typing interface: the facility's defense reads environmental archive terms as
control signatures. This is the game's fiction, stated in-game as such, not a
claim about real machines.

The Sky Remnant keeps the planned non-robot identity: a living mass of smog
with wings, a skull of fused debris and ember eyes, nesting in the shield.

## 17. Phase 3: typing encounter rules and data

### Rules

- **Every correct letter fires one shot** (0.45 s flight), including the
  selecting letter and the last letter. Completing a word adds no extra shot.
  Enter is not required. Held-key echo and Ctrl/Alt chords never type.
- A wrong letter resets only the selected word to zero and keeps it selected;
  the wrong key is not reinterpreted as a new selection; it never damages Nick.
- No target: a first letter selects the matching active word **closest to the
  danger line** (largest y), ties broken by the oldest word. That letter counts.
- A word reaching the danger line: one miss, `miss_damage` once, the target is
  cleared if it was that word, the instance is removed, and the entry returns to
  the pending queue (in deck order) after `requeue_delay_seconds`. It is never
  respawned at the bottom, never removed from the deck, and never doubles up.
- **Damage model.** Boss health = (sum of the deck's word lengths) ×
  `damage_per_letter`. A shot carries damage only the first time its
  (deck entry, letter position) is typed in the attempt. Retyping a prefix
  after a wrong letter, or the already-typed letters of a requeued word, still
  fires a visible (dimmer) shot but deals nothing. A word's last position can
  only be typed by completing it, so health reaches zero exactly when every
  entry is complete and the last credited shot lands; it can never reach zero
  earlier. Victory requires every entry complete **and** every shot landed,
  fires once, and the controller defensively zeroes health then.
- **Order.** Every attempt (first entry, retry, re-entry after leaving or
  reloading) reshuffles the same deck entries *inside their stages*
  (`SFVocabulary.order_for_attempt`, seed = deck seed + attempt × 7919), so
  foundation words still open the fight. If the shuffle equals the previous
  attempt's order (saved as `typing_last_order`), the first stage with two or
  more entries is rotated by one place: bounded, never a reshuffle loop.
  Completed words are never reset mid-attempt.
- After the last word: no spawns, no word damage, the final attack resolves,
  then the boss dissolves and the result is offered.
- Nick at zero health stops everything and offers Retry (same words in a new
  order, easy stage, every encounter-local value and every shot in flight
  reset). Campaign progress and the journal stay.
- Pause, the journal, a dialogue and window focus loss stop the simulation
  entirely: words, spawns, damage, encounter time and pace measurement.

### Spawning and readability

- Four fixed lanes; one active word per lane, so labels never overlap and stay
  inside the play field. Words spawn at `spawn_y`, never near the danger line.
- When choosing the next word, up to three ready entries are considered and a
  first letter not already on screen is preferred; variety is never bought by
  skipping the stage order.
- Labels show the typed prefix in gold; urgency moves green → gold → red and
  blinks near the line. The **learning panel is bottom right** (x 352–632,
  y 290–352), below the danger line and right of Nick, so it never covers a
  falling word: it shows the selected word and its own definition (up to three
  lines), keeps them through a typing reset, shows a neutral prompt when
  nothing is selected, and carries the "WRONG LETTER - START AGAIN FROM 'X'"
  notice on its bottom line.
- Impact sound, boss flash and shake are rate-limited (one per 0.12 s), so fast
  typing gives a steady patter rather than stacked effects.

### `data/star_fall/typing.json`

```jsonc
{
  "boss":   {"id": "sky_remnant", "chapter_id": "dawn_tower", "name": "...", "subtitle": "...",
             "reward_component": "shield_emitter", "reward_flag": "sky_remnant_defeated",
             "archive_id": "dawn_archive", "seed": 51207, "visual": {...}},
  "arena":  {"spawn_y": 112, "danger_y": 278, "lanes_x": [168, 272, 376, 480],
             "nick": {"x": 320, "y": 318}, "boss_point": {"x": 320, "y": 74}},
  "health": {"nick_health": 100, "miss_damage": 12, "damage_per_letter": 2},
  "attack": {"flight_seconds": 0.45},
  "timing": {"first_spawn_delay": 1.2, "victory_hold_seconds": 1.8,
             "requeue_delay_seconds": 4.0, "lane_retry_seconds": 0.25,
             "distinct_letter_lookahead": 3},
  "deck":   {"stages": [{"band": "foundation", "count": 8, "fall_seconds": 10.5,
                         "max_active": 1, "spawn_gap": 1.6}, ...]},
  "pacing": {"reaction_seconds": 1.4, "min_observations": 4, "window": 6,
             "travel_scale_min": 0.85, "travel_scale_max": 1.7,
             "gap_scale_min": 0.5, "gap_scale_max": 1.3, "adjust_step": 0.06,
             "miss_travel_step": 0.1, "slow_ratio": 0.7, "fast_ratio": 0.35,
             "slow_clear_ratio": 0.45, "idle_gap_seconds": 0.6,
             "pressure_miss_threshold": 2, "pressure_clear_completions": 3},
  "estimate": {"assumed_chars_per_second": 1.8, "mistake_rate": 0.08, "miss_rate": 0.05}
}
```

### Pacing

The deck is 30 words in four stages (8 foundation, 8 developing, 8
intermediate, 6 advanced): one word at a time with a generous fall at first,
then up to two at once with longer falls for longer words. There is no mode
selection.

Adaptation is conservative and bounded:

- Typing speed is measured from each word's selecting key to its last key
  (resets included), over the last 6 words, and only after 4 words. One short
  word never decides anything.
- **Slower typists.** If clearing a full field (per-word time × the stage's
  `max_active`) would need more than 70% of a fall, slow mode limits the field
  to one word, and fall time and gaps stretch by one step (up to 1.7× and 1.3×).
  Slow mode clears again under 45%.
- **Faster typists.** If a word needs under 35% of a fall and nothing was
  missed recently, gaps shrink (down to 0.5×). Fall speed is never raised, so
  band progression and readability are unchanged. An empty field brings the
  next word within 0.6 s.
- **Misses** stretch fall time, restore gaps to at least 1.0×, and after two
  recent misses lower the word cap by one until three clean completions. A miss
  never makes anything faster.
- Nothing is ever completed for the player, no stage is skipped, and no boss
  damage is ever unearned.

**Duration estimate.** `SFTypingEncounter.estimate_seconds()` sums, per word,
`length / cps + reaction`, adds half a retype at the mistake rate, adds
`miss_rate × (requeue delay + fall)`, plus the opening delay. With the assumed
1.8 characters per second (about 22 words per minute, an assumed adult casual
typist, not a measured value) the shipped deck estimates **178 s (3.0 min)**.

**Measured with scripted bots** (`test_phase3.gd`, deterministic, seed 51207,
headless). These are rule checks, not playtests:

| Bot profile | Result | Fight time | Misses | Resets | Final adaptation |
|---|---|---|---|---|---|
| 5.0 cps, no errors, 0.6 s reaction | win | 63 s | 0 | 0 | gaps 0.76× |
| 1.8 cps, 1 wrong key per 25, 1.4 s reaction | win | 177 s | 0 | 9 | slow mode, fall 1.66× |
| 1.2 cps, 1 wrong key per 15, 1.8 s reaction | win | 292 s | 0 | 18 | slow mode, fall 1.7× |

No child or adult has played this encounter. The timings above say nothing
about whether the fight suits the intended audience; every value is in
`typing.json` so playtesting can retune it.

## 18. Phase 3: reconstruction workshop and return simulation

**SIMPLIFIED EDUCATIONAL GAMEPLAY MODEL.** Every component value, route
requirement and constant in `data/star_fall/reconstruction.json` is invented
for the game. None of it is NASA data.

### Workshop

Day-one construction used credits and new parts. The future workshop uses
**salvage** (scrap metal, circuitry, polymer) and a **fabrication capacity of
12 units**; propellant comes free from the Dawn depot but must still be lifted.

| Group | Options |
|---|---|
| Recovered (mandatory) | navigation chip, power core, shield emitter |
| Propulsion | repair the original day-one engine (its own stats), or the rebuilt Dawn cluster |
| Propellant | 0–900 kg in 20 kg steps |
| Protection | emitter only, armor plating (+2, heavy), shield amplifier (+2, 90 W in transit) |
| Data storage | chip store only (128 MB), compact (+256 MB), array (+768 MB) |
| Payload, mandatory | Bill's memory core, minimum evidence archive |
| Payload, optional | environmental samples (30 kg, 25 W cooling), additional records (240 MB) |
| Route | Fast Corridor, Extended Arc |

- **Installation.** The VELA is drawn in its bay with three sockets (navigation
  chip, power core, shield emitter). The component tray below shows each part
  only if Nick has it, with its state in words and a glyph (`X MISSING`,
  `+ READY`, `OK FITTED`). Choosing a ready part blinks it in its socket;
  ENTER installs it (`SFCampaign.install_component`) with a short flash, and
  the socket then shows the part. The simulation sees **installed** parts only,
  so an uninstalled part fails as "Not installed: ...", and **F** refuses until
  all three are fitted.
- The right panel always shows a free live preview (eight compact checks with
  OK/NO in words, the first failure, and per-stage use when the SIMULATE row
  is focused). The footer always states the next step. **V** certifies a report
  for the exact design; any change clears it ("the previous report no longer
  applies"), and **F** refuses a stale or failing report.
- **F** checks, in order: not already assembled, current passing report, all
  three components recovered and installed, fabrication capacity, materials. Only then are materials
  removed, once.
- **C** tops each material up to the replenish floor (8 scrap, 4 circuitry,
  3 polymer), never above it. The floor covers the cheapest passing design, so
  no run can be stranded by salvage spent earlier.

### Simulation model (`sf_return_sim.gd`)

| Quantity | Unit | Model |
|---|---|---|
| Mass | kg | dry = frame + parts + payload; wet = dry + propellant |
| Launch mass | kg | wet ≤ min(frame limit, engine thrust capacity) |
| Delta-v | m/s | `Isp × g0 × ln(wet / dry)` ≥ route delta-v × 1.10 |
| Propellant per stage | kg | each stage burns its share of route delta-v in order |
| Power | W | demand per stage; core output 220 W; peak ≤ output + 160 W buffer discharge |
| Energy | Wh | `energy_used_Wh = power_W × duration_s / 3600`; only demand above output drains the 600 Wh buffer, which must keep 20% |
| Time | s | relay sync, ascent 300 s, transit (route), rift 300 s |
| Data | MB | payload MB ≤ storage MB |
| Relay throughput | MB/s | sync time = payload MB / 0.5 MB/s, within the route's launch window |
| Protection | rating | emitter 3 + upgrade ≥ route debris rating |

Electrical energy and propellant are separate resources. Communications use the
surviving local Dawn relay; nothing contacts the present day. The seed only
varies the reported debris impact count; validity uses deterministic margins,
so identical inputs and seed always give identical reports.

The report returns overall validity, every check with a message, failures with
actionable suggestions, per-stage time / load / buffer draw / propellant, and
reserves (propellant and buffer remaining).

| Route | Delta-v | Transit | Debris rating | Launch window |
|---|---|---|---|---|
| Fast Corridor | 1500 m/s | 2400 s | 5 | 900 s |
| Extended Arc | 1100 m/s | 14400 s | 3 | 1800 s |

### Verified designs (`test_phase3.gd`)

| Design | Fab | Salvage | Wet mass |
|---|---|---|---|
| A Extended, repaired light engine, compact store, samples | 7 | 2 scrap, 3 circuitry, 3 polymer | 1473 kg |
| B Fast, rebuilt cluster, amplifier, compact store | 12 | 6 scrap, 8 circuitry, 4 polymer | 1828 kg |
| C Fast, repaired heavy engine, armor plating, compact store | 9 | 7 scrap, 3 circuitry, 1 polymer | 2133 kg |
| D Extended, repaired heavy engine, array, samples + records | 10 | 2 scrap, 6 circuitry, 4 polymer | 1745 kg |

Trade-offs, all checked by the suite: the repaired light engine cannot fly the
Fast Corridor; the amplifier build cannot also cool samples (peak power); plating
costs propellant; the Fast Corridor's relay window cannot carry the extra
records; an amplifier on the Extended Arc runs out of buffer. **Both day-one
engines** have a passing Extended Arc design whose salvage fits the replenish
floor, so every valid Phase 1 build can reach READY_FOR_FINAL_ASSEMBLY.

## 19. Phase 3 save schema (versions 3 and 4)

Version 3 adds two fields. Versions 1 and 2 load with both empty. Version 4
adds three more (below); versions 1 to 3 load with them migrated. Version 5
(section 19a) is Phase 4's. Phase 3 shipped on version 4, so a version 4
document written there loads unchanged.

```jsonc
{
  "version": 3,
  "vocabulary_journal": ["v_soil", "v_habitat"],   // learned entry ids, unique, in order
  "reconstruction": {
    "selection": {"propulsion": "repair_original", "protection": "protection_none",
                  "storage": "storage_compact", "route": "extended_arc", "fuel_kg": 460.0,
                  "optional": {"environmental_samples": true, "additional_records": false}},
    "committed": { ... same shape, present only after fabrication ... },
    "report": {"route_id": "...", "signature": "...", "seed": 30303, "totals": {...}}
  }
  // ... every version 2 field, unchanged
}
```

- Journal ids are de-duplicated on load; non-string entries are dropped.
- Unknown workshop option ids are ignored when the workshop reloads them.
- A `ready_for_final_assembly` flag without a `committed` design is cleared
  with a warning, so the workshop reopens rather than claiming an assembly with
  no record.
- An active falling word, attack or partial typing fight is never saved.

Version 4 (main): installed components and typing attempt history.

```jsonc
{
  "version": 4,
  "installed_components": ["navigation_chip", "power_core", "shield_emitter"],
  "typing_attempts": 3,                          // typing attempts started so far
  "typing_last_order": ["v_air", "v_soil", ...]  // ids of the last attempt's order
}
```

Version 5 (Phase 4) adds the frozen finale snapshot:

Code from both branches was merged with the same version number, so the
document version was raised to **5**. Versions 1-4 all still load: a document
without `finale` simply has no finale record, exactly as a Phase 4-less save
should.

```jsonc
{
  "version": 5,
  "stage": "credits",
  "chapter_id": "return_home",
  "finale": {
    "design": {...},                // the committed reconstruction design
    "report_signature": "...",      // the certified report this run launched on
    "route_id": "extended_arc",
    "launch_mass_kg": 1443.0,
    "components": ["navigation_chip", "power_core", "shield_emitter"],
    "memories": ["memory_green_city", "..."],
    "frozen": true,                 // the snapshot exists and is trusted
    "cinematic_skipped": false      // descriptive only; never read by the score
  },
  // ... every version 4 field, unchanged
}
```

Rules:

- `begin_final_assembly()` writes the snapshot at most once. A second call is
  refused, so a double confirmation cannot freeze two designs.
- A document whose stage is `final_assembly` or later but which has no frozen
  snapshot is contradictory: `apply_save_dict()` warns, moves the stage back to
  `ready_for_final_assembly`, clears `finale` and clears the four Phase 4 flags.
  The workshop reopens rather than claiming an ending with no record.
- `escape_seen`, `return_objective_complete` and `mission_report_seen` are only
  meaningful with a snapshot; they are cleared by the correction above.
- `cinematic_skipped` is stored so the report can say so plainly. No rule, no
  report value and no score term reads it.
- A save written mid-cinematic is still just an `escape`-stage document with a
  valid snapshot, which resumes at the start of the escape.
- `qa_stage_skip_used` lives in `flags` like any other flag and is diagnostic.

---

### Version 4: installed components and the typing attempt history

```jsonc
{
  "installed_components": ["navigation_chip", "power_core", "shield_emitter"],
  "typing_attempts": 3,                         // typing attempts started so far
  "typing_last_order": ["v_air", "v_soil", ...] // ids of the last attempt's order
}
```

The shield emitter's state is never one flag. It is derived from three saved
facts: `sky_remnant_defeated` (flag), `recovered_components`, and
`installed_components`:

| State | Flag | Recovered | Installed | What the player sees |
|---|---|---|---|---|
| undefeated | no | no | no | The fight at the tower gate |
| available | yes | no | no | The glowing drop below the gate (persists across revisits and save/load) |
| collected | yes | yes | no | `+ READY` in the workshop tray |
| installed | yes | yes | yes | The emitter in its socket on the VELA |

- Installed ids are kept only if they are also recovered.
- **Migration.** A version 1–4 save has no `installed_components`. If it has a
  committed (fabricated) design, every recovered component is marked installed;
  otherwise none is. A version 3 save whose victory already awarded the shield
  therefore keeps it as *collected* (or *installed* if assembled) and never has
  to fight again. A save that never earned the shield gains nothing.
- A `ready_for_final_assembly` flag is cleared with a warning if a required
  component is not installed.

## 20. Phase 3 stable IDs

| Kind | id |
|---|---|
| Chapter | `dawn_tower` |
| Boss | `sky_remnant` |
| Reward | `shield_emitter` |
| Archive | `dawn_archive` |
| Memory | `memory_healthy_forest` |
| Site | `dawn_tower` |
| Stage | `dawn_intro`, `dawn_boss`, `dawn_archive`, `reconstruction`, `ready_for_final_assembly` |
| Flag | `dawn_entered`, `dawn_checkpoint`, `typing_tutorial_seen`, `sky_remnant_defeated`, `dawn_archive_restored`, `workshop_unlocked`, `return_simulation_passed`, `ready_for_final_assembly` |
| World object | `dawn_memory`, `dawn_checkpoint`, `dawn_terminal`, `dawn_boss_gate`, `dawn_shield_drop` |
| Dialogue | `dawn_victory`, `shield_collected`, `workshop_intro` (Phase 3 additions and edits) |
| Salvage | `salvage_dawn_frame`, `salvage_dawn_cells`, `salvage_dawn_seal` |
| Vocabulary | `v_<text>` for every entry in `vocabulary.json` |
| Workshop options | `repair_original`, `rebuilt_cluster`; `protection_none`, `armor_plating`, `shield_amplifier`; `storage_none`, `storage_compact`, `storage_array`; `bill_memory_core`, `evidence_archive`, `environmental_samples`, `additional_records`; `fast_corridor`, `extended_arc` |

## 20a. Phase 4 stable IDs

| Kind | id |
|---|---|
| Stage | `final_assembly`, `escape`, `return_home`, `mission_report`, `credits` |
| Chapter | `return_home` (now playable) |
| Flag | `final_assembly_complete`, `escape_seen`, `return_objective_complete`, `mission_report_seen`, `qa_stage_skip_used` |
| Save field | `finale` |
| Data file | `data/star_fall/finale.json` |
| Report row | `objective`, `memories`, `samples`, `components`, `original`, `reconstructed`, `mass`, `route`, `propellant`, `energy`, `efficiency`, `score` |
| Prerequisite | `bosses`, `components`, `fabricated`, `payload`, `simulation`, `clear` |
| QA milestone | `briefing`, `construction`, `bill`, `phase_one`, `city`, `coast`, `phase_two`, `dawn`, `workshop`, `ready`, `finale`, `report`, `done` |

None of the earlier ids are renamed. `return_home` keeps its id and changes from
`deferred` to a playable chapter.

---

### Phase 3 completed scope

- Dawn Tower exploration: dead forest, survey projector with the healthy-forest
  memory, boardwalk checkpoint, defense console, salvage, and the tower gate.
- The Sky Remnant typing encounter with a 203-entry library, 30-word staged
  deck, one shot per correct letter with per-position damage credit, a changed
  word order on every attempt, a bottom-right definition panel, journal,
  first-time tutorial, bounded pacing, pause and retry.
- The `shield_emitter` drops onto the slope on victory and is awarded once when
  collected; the Dawn Project archive restored.
- The full reconstruction workshop with visible component installation and the
  return-mission simulation, ending at READY_FOR_FINAL_ASSEMBLY.

### Phase 4 completed scope

- **Final assembly.** A live prerequisite gate with six checks, a one-way
  confirmation, a frozen design snapshot, a pre-finale checkpoint, and an
  install animation that can be skipped without changing the outcome.
- **Escape cinematic.** Six in-engine scenes plus the closing message, all
  drawn from generated sprites and primitives, with data-driven subtitles,
  pause, focus-loss handling and an idempotent skip. Watching and skipping
  produce the same persistent state.
- **Mission report.** The recorded run: objective, memories, samples and records,
  components, both designs, launch mass, route, simulated reserves, material
  efficiency, the decision explanations, and the published score.
- **Credits.** The credit roll, the sources distinction (real physics, invented
  gameplay values, fiction) and the final message, then the title.
- **Milestone driver.** Test-only; the player-facing `I + O + P` skip is
  removed (see the integration pass below).
- **Save version 5** (Phase 4's snapshot on top of the merged version 4);
  versions 1-4 still load.
- **Reduced motion setting.** Removes screen shake and lowers flashes in both
  boss fights and in the launch transition without changing any rule.

### Phase 4 known limitations

- Visuals and audio of the cinematic have been checked only through the
  screenshot tool (`tests/star_fall/capture.gd`, shots 33-56), not by playing it
  on a real display with a person watching. Whether it *reads* well in motion,
  and how the contact sounds feel, is untested.
- The final-assembly preview shows VELA at scale 1 (about 105 px tall) so it fits
  the panel without stretching; the workshop shows the same ship at scale 2.
- The cinematic is drawn from primitives and generated sprites; it is deliberately
  stylised, not a rendered animation.
- The credits roll has no music of its own; it reuses the title theme.
- No executable was built: no export preset exists and no export templates are
  installed. See `docs/submission.md`.
- The Ctrl + Shift + Alt debug hotkeys exist in any debug build (the editor or
  `godot --path .`); an exported release build never creates them.

### Phase 3 known limitations

- Visuals, audio, input feel, UI scaling and pacing have not been checked by a
  person at the keyboard; see `docs/test_checklist.md`.
- Typing audio reuses existing UI and combat sounds; there are no new Phase 3
  sound assets.
- The Dawn Tower ground uses the existing ruin theme with new dead-tree and
  tower sprites, not a dedicated forest ground.
- The workshop is keyboard only (no mouse support), unlike the title menu.
- The Dawn Tower site has no exit, so "leaving and returning" is exercised by
  re-entering the world screen and by save/continue, not by walking out.
- Shots that deal no damage (already-credited letters) are drawn dimmer but
  share the hit sound's rate limit; whether that distinction reads well needs
  a playtest.
- The vocabulary has not been reviewed by an educator (`docs/vocabulary.md`).


## General integration pass (controls, pause, audio, progression)

This pass unified the four phases. Where an earlier section disagrees, this
section is current.

### Input by context

| Context | Movement | Other input |
|---|---|---|
| Exploration (all sites) | WASD / arrows (`move_*`), diagonals normalised, Shift run | E / Enter / Space interact, click to walk |
| Construction console, workshop, final assembly | none | mouse on every part, row and button; keyboard as listed |
| Phase 1 launch | none | signal investigation: `move_left` / `move_right` steer the reticle, E / Enter / Space or LOCK SIGNAL lock |
| Eco Arena (boss 1) | WASD / arrows | mouse aim and fire, Shift dash, 1-3 / wheel colour, right click / E beam |
| Toxic Tide (boss 2) | none (Nick fixed) | mouse shield, Space counterattack only (Enter / E never fire) |
| Sky Remnant (typing) | none | A-Z type (I, O, P are ordinary letters), Backspace |
| Escape cinematic | playable segments only: `move_left` / `move_right`, mouse | Enter / NEXT beat |

One input map in `project.godot` serves every scene; no scene registers or
erases actions. Focus loss releases every movement action; opening a pause
menu or a dialogue releases them and disables the world.

### Pause policy

- `main.gd` owns one pause menu for `MAIN_PAUSE_SCREENS` (world, launch,
  memory, summaries, archive, progression, final assembly, cinematic, report,
  credits). Esc, right click, the HUD zone badge, the checkpoint MENU button and
  the cinematic II PAUSE badge open it. It is taken in `_input()`, ahead of
  every screen.
- Opening it sets the current screen node to `PROCESS_MODE_DISABLED` (no
  process, no input: timers, spawns, cinematic clock and animations stop), stops
  the launch and memory updates and the play-time clock, releases movement, and
  calls `SFAudio.set_paused(true)` (music ducks, ambience and gameplay voices
  stop, UI sounds still play).
- Rows: RESUME, SAVE PROGRESS (world), SKIP (cinematic, memory, installation
  animation), VOCABULARY JOURNAL (world, when not empty), SETTINGS, RETURN TO
  MAIN MENU. SETTINGS opens in place; Esc there returns to the menu; Esc on the
  menu resumes. A dialogue takes Esc first, so one key never both closes a
  modal and reopens pause.
- The encounter screens keep their own menus, now mouse-operable, and also duck
  audio while paused. Esc on a victory panel pauses instead of continuing, and
  RESTART FIGHT is disabled there.
- Esc never advances a story screen, starts the next chapter or confirms a
  victory. Space never pauses.

### Mouse

`SFMenu.rects` is written by `SFUI.menu_list()` at draw time, and
`item_at() / hover() / click()` test against it, so a hit region always matches
the drawn row; a disabled row can never be clicked. Screen-space buttons are
tested in the overlay's coordinates (`main._ui_mouse()`), unaffected by the
world camera, the window scale or letterboxing. The Eco Arena blocks fire until
the button that pressed START / RESUME / RETRY is released.

### Progression and practice

- New Game always starts at the Earth briefing. The only main-menu shortcut to
  an encounter (Eco Arena practice) is locked until `scrap_king_defeated`.
- A save at `launch` / `flight` now replays the launch from the pad instead of
  skipping to the crash.
- Debug presets (`sf_debug_presets.gd`) finish every earlier map: salvage ids
  via `claim_salvage` (marked collected when the carry limit refuses), the coast
  terminal and samples, the junction via `repair_junction`, every earlier boss
  via `defeat_boss` + `collect_boss_reward`.

### Boss 2 projectile speed (x1.2, data only)

| Toxic Tide band | Before (px/s) | After (px/s) |
|---|---|---|
| 100% HP | 100.0 | 120.0 |
| 70% HP | 124.0 | 148.8 |
| 40% HP | 150.0 | 180.0 |
| 15% HP | 178.0 | 213.6 |
| `max_projectile_speed` | 200.0 | 240.0 |

Hostile and beneficial energy still share the band speed; firing intervals
are unchanged; the legacy Scrap King shield block and the Eco Arena / typing
speeds are unchanged. The speed is read from data once per spawn, so retries
never compound it (`test_encounter.gd`).

### Audio

Buses `Master`, `Music`, `SFX`, `UI` are created by `SFAudio.ensure_buses()`.
Volumes (0-1) live in `user://star_fall_settings.cfg` with text speed, reduced
motion and the practice unlock (`sf_settings.gd`); headless runs never write
that file. `play_sfx()` and every synth cue pass a per-cue rate gate. `_go()`
cuts gameplay voices on every screen change. New cues: `sfx_dash`,
`sfx_landing`.

### Presentation

- Phase 1 launch: `construction_screen.gd::draw_day_one_ship()` is now the one
  drawing of the player-built VELA, used by the console, the pad, the climb,
  the rift and the crash. Stages: pad with gantry and floodlights (engines off,
  T-3..1), ignition (flame from the bottom nozzles, pad smoke, light shake),
  liftoff, atmosphere (sky darkens, clouds pass), orbit (Earth limb), then the
  signal.
- Bill: a lighter shell, a one-pixel dark outline, reflective white-cyan
  markings (unlit while dormant), a firmer contact shadow, a pool of spill light
  and a small gold marker while dormant. Active lights only after activation.
- Credits: a TEAM section first, six names at double size, then the notes. No
  agency text anywhere in player-facing data.
