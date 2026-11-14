# Submission

- Project description:
- Demo video link:
- Playable link:
- NASA data used:
- AI tools used:

---

## STAR FALL delivery notes (Phase 4)

### What this build is

A single-player, offline pixel-art adventure, playable end to end from the main
menu to the credits. Nick builds the VELA spacecraft, flies to an anomalous
signal, is pulled through a rift into a ruined future Earth, recovers three
components and Bill's archive, rebuilds the VELA, and flies home.

### Engine and exact run instructions

- **Engine:** Godot **4.0 stable** (`4.0.stable.official.92bee43ad`). Standard
  build, not .NET.
- **Editor:** open `project.godot` and press **F5**. The main scene is
  `scenes/star_fall/main.tscn`.
- **Command line:**

```bash
godot --path .
```

- **QA build with the stage-skip hotkey, even in an export:**

```bash
godot --path . -- --qa
```

### Controls

| Context | Keys |
|---|---|
| Exploration | WASD / arrows move, Shift runs, E interacts and advances dialogue, Esc pauses |
| Menus | Up/Down select, Enter confirm, Esc back |
| Construction | Left/Right, Q/E cycle parts; Up/Down choose fuel; V preflight; Enter confirm |
| Shield duels | Mouse rotates the shield; Space counterattacks when charged; Esc pauses |
| Typing battle | A-Z types, Backspace releases, Esc pauses |
| Workshop | Up/Down rows, Left/Right change (Shift = 100 kg), V simulate, F fabricate, C scavenge |
| Final assembly | Up/Down select, Enter activates, Esc back |
| Escape cinematic | Space pause/resume, Esc skip, Enter advance |
| Report and credits | Up/Down scroll, Enter/Space continue |
| QA (debug or `--qa`) | Hold **I + O + P** to advance one campaign milestone |

### Save behaviour

- One file: `user://star_fall_save.json`
  (`%APPDATA%\Godot\app_userdata\STAR FALL\star_fall_save.json` on Windows).
- Written at every checkpoint beat and on demand from the pause menu. Schema
  **version 4** adds the frozen finale snapshot; versions 1-3 still load.
- Opening the main menu never writes or deletes a save.
- A corrupt, empty or newer-version save is reported and left untouched.
- Continue is enabled only when the file parses and validates.
- The ending is saved, so Continue returns to the credits; New Game starts clean.
- **Pre-finale checkpoint:** `final_assembly`. Closing the game during the escape
  and choosing Continue resumes at the start of the escape, not mid-scene.

### Simulation assumptions and limitations

- **Real physics:** the ideal rocket equation, the unit definitions (kg, W, Wh,
  m/s), and the relation `energy_Wh = power_W * seconds / 3600`.
- **Invented gameplay values:** every component mass, cost, thrust, power
  output, storage figure, route delta-v, debris rating, fabrication cost and
  replenishment floor. None of it is NASA data.
- **Fiction:** time travel, the portal, the VELA drive, the surviving future
  Earth, the bosses, the Sky Remnant and the Dawn Project.
- The model is an educational abstraction. It is not a flight simulator, it does
  not model air resistance, gravity losses after ascent, staging physics or
  real-world reliability.
- The "debris impacts absorbed" figure is seeded per run and is informational;
  validity is decided by deterministic margins.
- No environmental or debris statistic is presented as measured data.

### Credits and sources

- **Engine:** Godot 4.0 stable, MIT License.
- **Art and audio:** all original, generated procedurally at runtime or by this
  repository's own Python tools (`tools/generate_phase1_audio.py`,
  `tools/generate_music.py`).
- **Third-party code:** `.claude/agents/` and `.claude/rules/` are adapted from
  Claude Code Game Studios under the MIT License (see `THIRD_PARTY_NOTICES.md`).
- **NASA data:** none is bundled. No NASA imagery, logo, dataset or endorsement
  is claimed or implied. The in-game credits state this explicitly.
- **AI tools:** Claude (Anthropic) was used for implementation, documentation and
  test authoring across all four phases. The design decisions, the fiction and
  the acceptance criteria are the team's.

### Build status: no executable

**No Windows executable was produced.** Two concrete blockers:

1. `export_presets.cfg` does not exist, and the repository rules require an
   export preset to be created through the Godot editor (Project > Export),
   not hand-written.
2. `%APPDATA%\Godot\export_templates\` is empty on this machine: no export
   templates are installed, so Godot cannot export a Windows build even if a
   preset were created.

To produce one: install the matching export templates from the Godot editor
(*Editor > Manage Export Templates*) for **4.0 stable**, create a Windows Desktop
preset via *Project > Export*, then export to `build/windows/`. That file is
git-ignored for `*.exe`.

The game is fully runnable from the editor or `godot --path .` exactly as above.

### Verification performed

Headless, on this machine, with Godot 4.0 stable:

| Suite | Result |
|---|---|
| `test_parse.gd` | 45 scripts, 0 failures |
| `test_logic.gd` | 149 checks, 0 failures |
| `test_flow.gd` | 380 checks, 0 failures |
| `test_encounter.gd` | 210 checks, 0 failures |
| `test_phase3.gd` | 172 checks, 0 failures |
| `test_phase4.gd` | 144 checks, 0 failures |

Presentation: `tests/star_fall/capture.gd` rendered the Phase 4 screens
(shots 35-45) on a real display, and they were inspected by eye for layout,
overflow and readability.

### What remains unverified

- Anything about how the game *feels*: movement weight, fight difficulty, typing
  comfort, cinematic pacing.
- The cinematic's readability and emotional beat on a real monitor, watched by a
  person from start to finish.
- Audio mix and audibility of the ending.
- Window resizing and scaling beyond the default 1280x720.
- The QA hotkey on a physical keyboard (it is verified through the system's key
  state API and the direct milestone entry point, both headless).
- A real exported executable (none was built).
- A full manual playthrough of all four phases in one sitting.

### Known issues

- The cinematic is stylised primitives, not a rendered sequence, and has no
  dedicated music track.
- The mission report has no mouse wheel support; it scrolls with Up/Down.
- The three "extra" moments in the cinematic (dust, sparks, packets) are tied to
  the scene clock and the certified impact count, not to live simulation.
- During the escape the only persistent state is the snapshot and the
  pre-finale checkpoint; the cinematic itself is not resumable mid-scene.
