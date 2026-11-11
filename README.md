# NASA Space Mission Game

A 2D strategy game where players design, manage and simulate a complete space mission: choosing objectives, spacecraft, instruments and launch vehicle under budget, mass and power limits, then seeing how those trade-offs shape the outcome.

Built for the **NASA Space Apps Challenge** (48-hour hackathon, team of 6). The official brief and datasets are released on event day, so the game logic and data are placeholders until then.

## Quick facts (read this first, humans and Claude sessions)

| Item | Value |
|---|---|
| Engine | **Godot 4.7.2 stable** (everyone must use this exact version) |
| Language | GDScript (static typing) |
| Renderer | Compatibility (`gl_compatibility`), required for web export |
| Target | Web (HTML5), exported and hosted on itch.io or GitHub Pages |
| Resolution | 1280x720, stretch mode `canvas_items` |
| Game type | 2D, UI-driven strategy (Control nodes, no physics) |
| Flow | Main -> Design -> Simulation -> Result |
| Status | Skeleton only: folders, autoloads and starter scripts exist; no scenes yet |

## Getting started

1. Install Godot **4.7.2** (standard, not .NET) and Git. Install VSCode with the `godot-tools` extension.
2. Clone the repo and open the folder with the Godot project manager (Import -> `project.godot`).
3. In VSCode, set `godotTools.editorPath.godot4` to your own Godot executable (a per-machine setting; do not commit it).
4. In Godot: *Editor Settings -> Text Editor -> External* -> enable **Use External Editor**, set Exec Path to your `Code.exe`, Exec Flags to `{project} --goto {file}:{line}:{col}`.
5. Keep the Godot editor open while coding in VSCode. The GDScript language server runs inside Godot (port 6008).

## Project structure

```
autoload/    Global singletons: game_state.gd, events.gd (signal bus), data_loader.gd
core/        Pure logic with no UI access: calculations.gd (delta-v), mission_rules.gd
scenes/      main/  design/  simulation/  result/   (one folder per screen)
data/        JSON game data + schema.md (replace with NASA data on event day)
tools/       Python scripts that fetch/convert NASA data into data/*.json
assets/      ui/ (Theme, icons), sprites/, backgrounds/, fonts/, audio/, CREDITS.md
tests/       Optional tests for core/
docs/        roles.md, game_design.md, test_checklist.md, submission.md, pitch/
.claude/     Claude Code subagents (agents/), rules (rules/), deny-list (settings.json)
```

## Roles and folder ownership

Each person edits **only their own folders**. Need a change elsewhere? Ask the owner. Full table, including which Claude agents each role uses, is in [docs/roles.md](docs/roles.md).

| # | Role | Owns |
|---|---|---|
| 1 | Tech Lead | `autoload/`, `core/`, `scenes/main/`, `tests/`, `project.godot` |
| 2 | Design UI | `scenes/design/` |
| 3 | Simulation | `scenes/simulation/`, `scenes/result/` |
| 4 | Data and Science | `data/`, `tools/` |
| 5 | Art and Audio | `assets/` |
| 6 | Producer / QA / Pitch | `docs/`, `README.md`, `export_presets.cfg` |

## Architecture rules

- Screens never call each other. They read and write state through `GameState` and communicate through signals on `Events`.
- Game values (cost, mass, power, delta-v, probabilities) live in `data/*.json`, never hardcoded in scripts. Real NASA data will replace the placeholder files on event day, so only the JSON should need to change.
- `core/` is pure functions with no scene or UI access, so formulas are easy to test and reuse.
- UI only displays state and requests changes. Use `Container` nodes (not hand-placed positions) and the shared Theme in `assets/ui/`.
- Autoloads are registered in `project.godot` as `GameState`, `Events`, `DataLoader`.

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
- `.vscode/` holds per-machine paths and should not be committed.
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

- **Git LFS:** add rules to `.gitattributes` (suggested: `*.png *.jpg *.ogg *.wav *.glb`) before the first large asset is committed.
- **`export_presets.cfg`:** create via *Project -> Export* (Web preset) and do a trial export + upload to itch.io well before event day.
- **Scenes:** no `.tscn` files yet. Each owner creates their screen in their own folder.
- **Data:** `data/*.json` are empty arrays; `data/schema.md` is a draft to be updated in the first 3 hours of the event.
- **`.editorconfig`** and a `.vscode/` entry in `.gitignore` were discussed but not added.

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

Third-party notices are in `THIRD_PARTY_NOTICES.md`; asset credits are in `assets/CREDITS.md`. NASA data and any AI tool usage must be declared in `docs/submission.md`.
