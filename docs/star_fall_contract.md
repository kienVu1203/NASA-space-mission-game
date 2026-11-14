# STAR FALL — Contract (through Phase 2)

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
  shield_duel.gd                The Phase 2 shield-defense encounter screen
  archive_screen.gd             Archive restoration (city and coast)
  progression_screen.gd         Base return and the Phase 2 summary

data/star_fall/
  ship_parts.json               Hull, mission requirements, components, salvage
  campaign.json                 Chapters, missions, memories, archives, dialogue
  encounters.json               Phase 2 boss tuning, patterns, projectile types
  sites.json                    Authored world layouts (four sites)

tests/star_fall/
  test_parse.gd                 Every script compiles
  test_logic.gd                 Validation, transactions, inventory, save/load
  test_flow.gd                  Boots the real scene, drives both phases end to end
  test_encounter.gd             Phase 2 combat rules, escalation, retry, rewards
  capture.gd                    Dev tool: renders 27 key screens to PNG
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
| `city_boss` | Duel | Scrap King. Never checkpointed mid-fight |
| `city_archive` | Archive | Control-center archive, Future Earth reveal |
| `silent_intro` | World (Silent Coast) | Coast dialogue, then exploration |
| `coast_boss` | Duel | Toxic Tide. Never checkpointed mid-fight |
| `coast_archive` | Archive | Environmental archive, Dawn Tower unlock |
| `base_return` | Progression | Crash-site base, both components shown |
| `phase_two_complete` | Checkpoint | Phase 2 summary; returns to the title |
| `complete` | Title | Return to menu with the save intact |

Chapters (`chapter_id`): `present_day_earth`, `crash_site`, `forgotten_city`,
`silent_coast`, `dawn_tower`, `return_home`. The first four are playable;
`dawn_tower` and `return_home` stay declared and `deferred` in `campaign.json`.

The chapter follows the stage automatically. `base_return`,
`phase_two_complete` and `complete` resolve back to `crash_site`, because Phase 2
ends at the base.

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
| `dawn_tower` | Declared, not playable |
| `return_home` | Declared, not playable |

**Future spacecraft components:** `navigation_chip` (Phase 2 reward),
`power_core` (Phase 2 reward), `shield_emitter` (declared, not awarded).

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
`salvage_coast_plate`, `salvage_coast_cable`.

**Quest flags, Phase 1:** `briefing_read`, `design_confirmed`,
`preflight_passed`, `launched`, `rift_seen`, `crashed`, `vela_inspected`,
`power_repaired`, `bill_active`, `memory_viewed`, `coordinates_received`.

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
  "chapters":  [{"id": "...", "name": "...", "stage": "briefing|crash_site|deferred"}],
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
| *(encounter)* Mouse | — | Rotate the shield; no button held, always active |
| *(encounter)* Space | — | Counterattack, only when the charge meter is full |
| *(archive)* Left/Right or A/D | — | Previous / next record |
| *(archive, progression)* Enter / E / Esc | — | Close the screen |

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
mission_id() / mission_data() / mission_name() -> ...
boss_for_chapter(chapter_id: String) -> Dictionary
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

## 7. Save schema (version 1 baseline; version 2 adds section 13)

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

Balanced against the shipped data, three configurations are worth knowing:

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
```

Each prints `PASS`/`FAIL` per check and a `RESULT:` line, and exits non-zero on
failure. `test_encounter.gd` is the Phase 2 combat and persistence suite; the
other three cover Phase 1 and the campaign flow through both phases.

### Screenshots (needs a display, not headless)

```bash
"$GODOT" --path . --script res://tests/star_fall/capture.gd
"$GODOT" --path . --script res://tests/star_fall/capture.gd -- --shots=17,18
```

Writes 27 PNGs to `user://captures/`. `--shots=` renders only the named screens
(by their number prefix), which is the quickest way to re-check one pose. This
is a presentation aid only; it is not evidence that the game plays correctly.

### What headless verification does and does not prove

Proven: scripts compile; validation, construction transactions, inventory and
save/load behave as specified; the real main scene boots; every screen
transition and every quest beat fires; skipping a cutscene preserves state;
Continue restores a save; the shield, projectile, scheduler, encounter and
progression models obey every rule in section 12 of the Phase 2 brief; both
Phase 2 fights can be won through their own rules and fully reset on retry.

**Not** proven: that anything looks right, that audio is audible, that the
window scales well, that the mouse aims the shield as it feels, or that the
fights are *fun* at the intended difficulty. Those require playing it.

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
- Launch: countdown, ascent, a guided signal-tuning interaction, the rift, and
  the crash transition. Esc skips the whole sequence without losing any state.
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
- **Scrap King** (`scrap_king`): a fixed-position, mouse-directed shield-defense
  encounter. Heavy industrial chassis, magnetic emitters, five health bands that
  raise firing frequency and projectile speed. Reward: `navigation_chip`.
- **Control-center archive.** Five restored records covering the waste history,
  the ignored warnings, a surface image and the matching place names. Closing
  it applies the Future Earth reveal, changes the objective to
  `return_with_evidence`, and unlocks the Silent Coast.
- **Silent Coast.** A walkable harbor with a polluted tide line, a cleanup
  facility silhouette, bollards, drums, crates, optional samples and research
  records, a coastal memory projector and a route checkpoint.
- **Toxic Tide** (`toxic_tide`): the same shield/absorption/counterattack rules
  with a distinct marine silhouette, a longer deliberate rhythm, wider spray
  patterns and heavier projectiles. Reward: `power_core`.
- **Environmental archive.** Five restored records, including the cleanup unit's
  own log. Unlocks the Dawn Tower and returns the campaign to the crash-site
  base.
- **Base return and Phase 2 summary.** The VELA recovery frame shows the
  navigation chip and power core fitted, the shield emitter still missing, the
  restored archives and the next objective. The summary returns to the title and
  keeps the save.
- **Persistence.** Save version 2 adds recovered components, restored archives
  and the active mission; version-1 saves still load. A retry of either boss
  resets only encounter-local state.

---

## 11. Phase 2 architecture

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
  `duel_finished`; `main.gd` awards the component, sets the flag and saves.
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
Phase 3.

---

## 15. Deferred scope (explicitly not built)

- Dawn Tower: its exploration, encounter, mechanics and the final ending.
- The shield emitter component.
- The Phase 3 boss and any replacement of its planned mechanics.
- The final reconstruction system and the return-home finale.
- Crafting beyond the crash-site repair cost.
- Mission planning simulation beyond preflight validation.
- Any 3D pipeline, engine migration, or external asset dependency.
- A combined test runner across both games.
- An export preset and a web build.
