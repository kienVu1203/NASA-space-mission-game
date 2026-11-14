# STAR FALL

A single-player, offline pixel-art adventure. Nick, a human astronaut, builds the
experimental spacecraft **VELA** in a present-day spaceport, flies out to
investigate an anomalous signal, and is pulled through a spatial rift into a
ruined, polluted world. There he meets **Bill**, an abandoned maintenance robot,
who holds one memory of a green city.

The campaign is complete and playable from the main menu to the credits:
present-day Earth, the crash site, the Forgotten City and the Silent Coast (two
shield-defense boss fights), the Dawn Tower with the Sky Remnant typing battle,
the VELA reconstruction workshop and the return-mission simulation, then final
assembly, an in-engine escape cinematic, the mission report and the credits.
Time travel, the portal and the VELA's drive are fictional story devices, not
claims about real technology.

**Everything is documented in [docs/star_fall_contract.md](docs/star_fall_contract.md)** —
architecture, data schemas, stable IDs, save format, units and test commands.

> **The repo also still contains Operation: Starfall**, a complete orbital-salvage
> satire under `scenes/starfall/`, `core/starfall/` and `data/starfall/`. It stays
> runnable (see [docs/starfall.md](docs/starfall.md)) but STAR FALL is the main scene.

## Quick facts (read this first, humans and Claude sessions)

| Item | Value |
|---|---|
| Engine | **Godot 4.0 stable**, the version installed here. Later 4.x releases will load the project. |
| Language | GDScript (static typing) |
| Renderer | Compatibility (`gl_compatibility`) |
| Target | Desktop, offline, no asset downloads |
| Resolution | 640x360 base, window opens at 1280x720, `canvas_items`, nearest filtering |
| Game type | 2D angled top-down exploration, Y-sorted, generated art and audio |
| Flow | Menu -> Earth -> Briefing -> Construction -> Preflight -> Launch -> Rift -> Crash Site -> Bill -> Memory -> Forgotten City -> Scrap King -> Archive -> Silent Coast -> Toxic Tide -> Archive -> Base -> Dawn Tower -> Sky Remnant -> Dawn Archive -> Reconstruction Workshop -> Final Assembly -> Escape -> Return Home -> Mission Report -> Credits |
| Status | **STAR FALL is complete**: Phases 1-4, main menu to credits, playable end to end |
| Also in repo | **Operation: Starfall**, a complete orbital-salvage satire in `scenes/starfall/` (see [docs/starfall.md](docs/starfall.md)) |

## Getting started

1. Install Godot **4.0** (standard, not .NET) and Git. Install VSCode with the `godot-tools` extension.
2. Clone the repo and open the folder with the Godot project manager (Import -> `project.godot`).
3. In VSCode, set `godotTools.editorPath.godot4` to your own Godot executable (a per-machine setting; do not commit it).
4. In Godot: *Editor Settings -> Text Editor -> External* -> enable **Use External Editor**, set Exec Path to your `Code.exe`, Exec Flags to `{project} --goto {file}:{line}:{col}`.
5. Keep the Godot editor open while coding in VSCode. The GDScript language server runs inside Godot (port 6008).

## Run it

Open `project.godot` in Godot 4.0 and press **F5**, or from a terminal:

```bash
godot --path .          # the main scene is scenes/star_fall/main.tscn
```

Headless checks (no display needed):

```bash
godot --headless --path . --script res://tests/star_fall/test_parse.gd
godot --headless --path . --script res://tests/star_fall/test_logic.gd
godot --headless --path . --script res://tests/star_fall/test_flow.gd
godot --headless --path . --script res://tests/star_fall/test_encounter.gd
godot --headless --path . --script res://tests/star_fall/test_phase3.gd
godot --headless --path . --script res://tests/star_fall/test_phase4.gd
```

`test_flow.gd`, `test_phase4.gd` and `capture.gd` delete
`user://star_fall_save.json`; back up a real save first.
`tests/star_fall/capture.gd` renders 46 key screens (including the Phase 4
finale) to `user://captures/` and needs a real display (`-- --shots=17,18`
re-renders just those screens). Full commands and acceptance steps are in
[docs/star_fall_contract.md](docs/star_fall_contract.md).

### Controls

| Key | Action |
|---|---|
| WASD / arrows | Move (diagonals normalised) |
| Shift | Run |
| E | Interact, advance dialogue |
| Esc | Pause, back, skip a cutscene |
| Enter / Space | Confirm, advance dialogue |
| Left / Right, Q / E, V | Construction console: cycle part, adjust fuel, run preflight |

**In a Phase 2 boss fight** (Nick is fixed in place):

| Input | Action |
|---|---|
| Mouse | Rotate the shield. No button held; the shield is always active |
| Space | Counterattack, only when the charge meter above Nick is full |
| Esc | Pause: resume, restart the fight, or return to the menu |

Block hostile energy with the shield. Let the green/cyan motes reach Nick
untouched to build charge; a blocked mote gives nothing. Space fires the
counterattack and consumes the whole meter.

**In the Phase 3 typing battle** (Sky Remnant):

| Input | Action |
|---|---|
| A–Z | Type the falling words. The first letter selects a word; finishing it fires a pulse (no Enter) |
| Backspace | Release the selected word |
| Esc | Pause: resume, vocabulary journal, restart, main menu |

A wrong letter restarts that word from its first letter and never hurts Nick.
A word that reaches the red danger line costs health and comes back later.

**In the reconstruction workshop:** Up/Down choose a row, Left/Right change it
(Shift: 100 kg of propellant at a time), Enter toggles optional payload,
**V** runs the simulation, **F** fabricates, **C** scavenges common materials,
Esc leaves (the selection is kept; press E at the wreck to return).

**In final assembly:** Up/Down choose COMPLETE ASSEMBLY AND LAUNCH or GO BACK,
Enter activates, Esc goes back to the ready summary. The confirmation is one-way: it
freezes the design, writes the pre-finale checkpoint and starts the escape.

**In the escape cinematic:** Space pauses and resumes, Esc skips the rest,
Enter advances a beat. Skipping is always safe and produces exactly the same
progress, report and score as watching.

**Mission report and credits:** Up/Down scroll, Enter/Space continue, Esc also
continues. The credits end at the title.

**QA stage skip (playtesting only):** hold **I + O + P** together to advance one
campaign milestone per press (it is edge-triggered with a cooldown, so holding
the keys does not repeat). Enabled automatically in a debug build or the editor,
and in any build launched with `--qa`; it is inert in a release build.

### Reaching each Phase 2 encounter

1. **New Game** and finish Phase 1: briefing, build the VELA, preflight, launch,
   crash site, salvage, repair the junction, wake Bill, watch the memory.
2. At the Phase 1 summary press **Enter**. You enter the **Forgotten City**.
3. Walk to the checkpoint marker (the gold ring post) and press **E**. The
   control-center door will not open until you do.
4. (Optional) Visit the maintenance shrine with the green picture and the city
   salvage piles.
5. At the welded door press **E**: **Scrap King** begins after Bill's briefing.
   Win, then read the control-center archive.
6. The archive closes into the **Silent Coast**. Use the harbor checkpoint, then
   press **E** at the facility intake: **Toxic Tide** begins.
7. Win, read the environmental archive, and the campaign returns to the
   crash-site base, where both recovered components are shown fitted.
8. **Enter** on the base shows the Phase 2 summary.

### Reaching the Phase 3 encounter and workshop

1. At the Phase 2 summary press **Enter**: you arrive at the **Dawn Tower**.
   (A save from the Phase 2 build resumes at that summary through **Continue**.)
2. Walk to the survey projector on the boardwalk (green-framed panel, lower
   left) and press **E** to watch the healthy-forest memory. The tower gate
   stays shut until you do.
3. Use the gold checkpoint post (**E**). Optional: the defense console (right of
   the tower) explains the typing interface; three salvage piles add materials.
4. Press **E** at the Dawn Tower (top centre). Bill's briefing and, the first
   time, a five-line typing tutorial play over a frozen arena; then the
   **Sky Remnant** fight starts. A win takes about 3–4 minutes at a casual
   typing pace (estimated, not playtested).
5. Win, press **Enter**, read the Dawn Project archive, and the **reconstruction
   workshop** opens at the crash-site base.
6. Set the propellant (the preview shows how much the design needs), press **V**
   to simulate, revise until it passes, press **C** if salvage is short, then
   **F** to fabricate. The quickest passing design is the default selection on
   the Extended Arc with the propellant set to the "propellant needed" value.
7. The **READY FOR FINAL ASSEMBLY** summary appears; **Enter** opens the Phase 4
   **final assembly** gate.

### Reaching the ending (Phase 4)

1. At the ready summary press **Enter**: the final-assembly gate lists the six
   prerequisites. They are evaluated live, so a missing boss, component,
   fabrication or stale simulation shows up here rather than mid-cinematic.
2. Press **Enter** on **COMPLETE ASSEMBLY AND LAUNCH**. This is irreversible:
   the design freezes, a pre-finale checkpoint is written, and the install
   animation plays. **Esc** skips the animation, not the sequence.
3. The **escape** plays: crash site, launch, debris passage with the certified
   telemetry, sunlight, the portal, home. **Space** pauses, **Esc** skips.
4. The **mission report** shows the recorded run and the published score.
5. The **credits** roll, then the game returns to the title. **Continue** after
   the ending returns to the credits, and **New Game** starts clean.

For rapid playtesting, hold **I + O + P** to jump one milestone at a time; see
the controls table above and `docs/test_checklist.md`.

## Project structure

```
autoload/         game_state.gd (owns the campaign), events.gd (signal bus), data_loader.gd
core/star_fall/   Pure logic + presentation kit, no nodes: design and preflight
                  validation, campaign state, save/load, content loading, palette,
                  bitmap font, generated sprites, synth audio, shared UI drawing,
                  and the Phase 2 encounter parts (shield, projectiles, pattern
                  scheduler, encounter model, encounter controller) and the
                  Phase 3 parts (vocabulary, typing, typing encounter,
                  reconstruction rules, return simulation)
scenes/star_fall/ main.tscn + main.gd (flow controller), world.gd, player.gd,
                  prop.gd, hud_overlay.gd, construction_screen.gd,
                  shield_duel.gd, archive_screen.gd, progression_screen.gd,
                  typing_duel.gd, reconstruction_screen.gd,
                  final_assembly_screen.gd, cinematic_screen.gd,
                  mission_report_screen.gd, credits_screen.gd
data/star_fall/   ship_parts.json, campaign.json, encounters.json, sites.json,
                  vocabulary.json, typing.json, reconstruction.json,
                  finale.json: all tuning and prose
tests/star_fall/  test_parse.gd, test_logic.gd, test_flow.gd, test_encounter.gd,
                  test_phase3.gd, test_phase4.gd, capture.gd
docs/             star_fall_contract.md (source of truth), vocabulary.md, game_design.md,
                  starfall.md, test_checklist.md, roles.md
core/starfall/    Operation: Starfall: palette, font, sprites, synth, ship and debris models
scenes/starfall/  Operation: Starfall: its own 480x270 screens
data/starfall/    Operation: Starfall: balance, debris, sectors, logs, endings, upgrades
tests/            Operation: Starfall suites (playtest, flow, botrun), synth check, capture tool
core/             Legacy mission-planner skeleton: calculations.gd, mission_rules.gd
data/             Legacy empty JSON files, untouched
assets/           Placeholder folders and CREDITS.md (neither game loads asset files)
```

## Roles and folder ownership

Each person edits **only their own folders**. Need a change elsewhere? Ask the owner. Full table, including which Claude agents each role uses, is in [docs/roles.md](docs/roles.md).

| # | Role | Owns |
|---|---|---|
| 1 | Tech Lead | `autoload/`, `core/`, `scenes/`, `tests/`, `project.godot` |
| 2 | Design UI | `scenes/design/` |
| 3 | Simulation | `scenes/simulation/`, `scenes/result/` |
| 4 | Data and Science | `data/`, `tools/` |
| 5 | Art and Audio | `assets/` |
| 6 | Producer / QA / Pitch | `docs/`, `README.md`, `export_presets.cfg` |

## Architecture rules

- Screens never call each other. They read and write state through `GameState` and communicate through signals on `Events`.
- `core/star_fall/` is pure logic with no scene or UI access, so it is easy to test. The scene layer asks it questions and draws the answers.
- Game values (cost, mass, power, fuel, probabilities) live in `data/star_fall/*.json`, never hardcoded in scripts. Balance changes should only ever touch JSON.
- UI displays state and requests changes; it never owns campaign state.
- Saving goes through `sf_save.gd` only. A corrupt save is reported, never silently replaced.
- Autoloads are registered in `project.godot` as `GameState`, `Events`, `DataLoader`.
- The legacy NASA mission-planner skeleton (`core/calculations.gd`, `core/mission_rules.gd`, `data/destinations.json`, …) is untouched and still loads. STAR FALL's campaign state is deliberately separate from its `budget_*` demo fields.

## Conventions

**Git** (step-by-step commands: [docs/git_guide.md](docs/git_guide.md))
- Never push directly to `main`. Work on a personal branch (`feature/<name>`), open a small PR, merge often (at least a few times a day). Do not let a branch live more than about 3 hours.
- Commit scene (`.tscn`) and `.uid` files together with their scripts. Never edit or delete `.uid` files.
- `.tscn` files conflict badly. One person per scene. If two people must touch one scene, talk first.
- `project.godot` is changed only by the Tech Lead (autoloads, renderer, input map).

**GDScript**
- Indent with **tabs** (Godot default). Do not mix tabs and spaces.
- Use static typing: `var x: int`, `func f(a: float) -> void`.
- Names: `snake_case` for files, functions and variables; `PascalCase` for `class_name` and node names; `UPPER_SNAKE` for constants.
- One script per scene, named after the scene (`design_screen.tscn` / `design_screen.gd`).

**Assets**
- Record every third-party asset (name, author, URL, license) in `assets/CREDITS.md`. Use only assets whose license allows reuse.
- Use lowercase `snake_case` file names, no spaces.
- Enable Git LFS before committing large binaries (see "Not set up yet").

**Local files**
- `.vscode/` holds per-machine paths and is listed in `.gitignore`; never force-add it.
- Editor Settings in Godot are per machine; only Project Settings (`project.godot`) are shared.

## Claude Code subagents

16 subagents in `.claude/agents/` are adapted from [Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) (MIT, see `THIRD_PARTY_NOTICES.md`). Hooks, skills and the original settings were deliberately **not** copied.

- Call one by name, e.g. "Use the ui-programmer agent to explain Container nodes".
- Claude Code cannot restrict agents per person. The role-to-agent table in `docs/roles.md` is a team convention, and each agent file states its scope.
- `producer` and `creative-director` run on a costlier model. Use them only at integration points (hours 12, 30, 42).
- The agents originate from a larger studio template and may mention ADRs, GDDs, sprints or `/slash` skills. None of these exist here; ignore them.
- Agents can be wrong about Godot details. Test what they produce in the editor.
- `.claude/settings.json` only blocks dangerous commands (`rm -rf`, force push, `reset --hard`, `git clean -f`, reading `.env`).

## Not set up yet

- **`export_presets.cfg`:** no export preset exists. The game runs from the
  editor or `godot --path .`; an export target still has to be created.
- **Git LFS:** not enabled. The game currently ships no binary assets, so
  nothing large needs it yet.
- **`.editorconfig`** was discussed but not added (optional, e.g.
  `indent_style = tab`).
- **Windows export build:** no export preset exists and no export templates are
  installed on this machine, so no executable was produced. The game runs from
  the editor or `godot --path .`. See `docs/submission.md` for the exact
  blocker and what would be needed.
- **Combined test runner:** there is no single script that runs both games'
  suites. Run STAR FALL's six from the "Run it" section and Operation:
  Starfall's from [docs/starfall.md](docs/starfall.md).

## Event-day timeline (48h)

| Hours | Goal |
|---|---|
| 0-3 | Read brief and data. Write a one-sentence game description, feature list (must/nice), and finalize `GameState` + JSON schema. |
| 3-12 | Everyone builds their own part independently. |
| 12-14 | **First integration:** play one full run, even if ugly. |
| 14-30 | Fill out gameplay, balance numbers, add events and result screen. QA tests hourly. |
| 30-36 | **Feature freeze.** Bug fixes and polish only. |
| 36-42 | Final art/audio, in-game instructions, export web build and deploy. |
| 42-46 | Demo video, submission text, slides. |
| 46-48 | Submit early; do not wait for the last minutes. |

Before the event: everyone finishes the official Godot "Your first 2D game" tutorial and learns `Control`/`Container` nodes and Themes; the Producer rehearses the full export and itch.io upload.

## Credits

Third-party notices are in `THIRD_PARTY_NOTICES.md`; asset credits are in `assets/CREDITS.md`. The in-game credits screen carries the same distinctions (real physics vs. invented gameplay values vs. fiction). NASA data and any AI tool usage must be declared in `docs/submission.md`.
