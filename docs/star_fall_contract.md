# STAR FALL — Phase 1 Contract

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
  sf_campaign.gd                Campaign state, quests, salvage, save dicts (pure)
  sf_save.gd                    Versioned save/load to user:// (pure + FileAccess)
  sf_dialogue.gd                Dialogue model (pure)
  sf_menu.gd                    Menu selection model (pure)
  sf_ui.gd                      Shared UI drawing (header, HUD, dialogue, toast)

scenes/star_fall/
  main.tscn / main.gd           Campaign controller: screen flow, input, launch
  world.gd                      One authored exploration area (props, ground, camera)
  player.gd                     Nick: movement and collision
  prop.gd                       One authored world prop with a ground footprint
  hud_overlay.gd                In-world HUD, drawn on a CanvasLayer above the world
  construction_screen.gd        Spacecraft construction + preflight

data/star_fall/
  ship_parts.json               Hull, mission requirements, components, salvage
  campaign.json                 Chapters, missions, memories, dialogue, checkpoint
  sites.json                    Authored world layouts

tests/star_fall/
  test_parse.gd                 Every script compiles
  test_logic.gd                 Validation, transactions, inventory, save/load
  test_flow.gd                  Boots the real scene, drives the whole campaign
  capture.gd                    Dev tool: renders key screens to PNG
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
     -> crash_site -> memory -> checkpoint -> complete
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
| `checkpoint` | Checkpoint | Phase 1 completion summary |
| `complete` | Title | Return to menu with the save intact |

Chapters (`chapter_id`): `present_day_earth`, `crash_site`, `forgotten_city`,
`silent_coast`, `dawn_tower`, `return_home`. Only the first two are playable in
Phase 1; the rest are declared and marked `deferred` in `campaign.json`.

The chapter follows the stage automatically: everything from `flight` onward is
`crash_site`. The crash site never displays "Earth", a place name, or a date.

---

## 3. Stable IDs

Do not rename these. Saves and data files refer to them.

**Chapters**

| id | Meaning |
|---|---|
| `present_day_earth` | Spaceport workshop, present day |
| `crash_site` | Unidentified ruined site |
| `forgotten_city` | Phase 2 |
| `silent_coast` | Phase 2 |
| `dawn_tower` | Phase 2 |
| `return_home` | Phase 2 finale |

**Future spacecraft components** (declared in `campaign.json`, not implemented
in Phase 1): `navigation_chip`, `power_core`, `shield_emitter`.

**Mission:** `signal_investigation`.

**Memory:** `memory_green_city`.

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

**Quest flags:** `briefing_read`, `design_confirmed`, `preflight_passed`,
`launched`, `rift_seen`, `crashed`, `vela_inspected`, `power_repaired`,
`bill_active`, `memory_viewed`, `coordinates_received`.

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

Behaviour requirements honoured by the implementation:

- Diagonal movement is normalised, so diagonals are not faster.
- Collision is a small circle at Nick's feet against prop footprints.
- Movement is locked while a dialogue, the pause menu, or a panel screen is up.
- On application/window focus loss, all movement actions are released and the
  player's velocity is zeroed, so nothing sticks.

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

## 7. Save schema (version 1)

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
```

Each prints `PASS`/`FAIL` per check and a `RESULT:` line, and exits non-zero on
failure.

### Screenshots (needs a display, not headless)

```bash
"$GODOT" --path . --script res://tests/star_fall/capture.gd
```

Writes 14 PNGs to `user://captures/`. This is a presentation aid only; it is
not evidence that the game plays correctly.

### What headless verification does and does not prove

Proven: scripts compile; validation, construction transactions, inventory and
save/load behave as specified; the real main scene boots; every screen
transition and every quest beat fires; skipping the cutscene preserves state;
Continue restores a save.

**Not** proven: that anything looks right, that audio is audible, that the
window scales well, or that input feels good. Those require playing it.

---

## 10. Completed scope (Phase 1)

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
- Headless test suites (parse, logic, flow) and a screenshot tool.

## 11. Deferred scope (explicitly not built)

- Chapters `forgotten_city`, `silent_coast`, `dawn_tower`, `return_home`.
- Campaign bosses.
- The final escape / ending.
- Combat.
- Crafting (salvage currently feeds repair cost only).
- Mission planning simulation beyond preflight validation.
- The `navigation_chip`, `power_core` and `shield_emitter` components.
- Any 3D pipeline, engine migration, or external asset dependency.
