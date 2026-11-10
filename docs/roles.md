# Roles, folders and Claude agents

Agents live in `.claude/agents/`. Claude Code cannot restrict them per person, so this table is a team convention. Each agent file also states its scope.
Call one with: `Use the ui-programmer agent to ...`

| # | Role | Owns (only edit these) | Agents to use |
|---|---|---|---|
| 1 | Tech Lead | `autoload/`, `core/`, `scenes/main/`, `tests/` | `lead-programmer`, `godot-specialist`, `godot-gdscript-specialist` |
| 2 | Design UI | `scenes/design/` | `ui-programmer`, `ux-designer`, `godot-gdscript-specialist` |
| 3 | Simulation | `scenes/simulation/`, `scenes/result/` | `gameplay-programmer`, `systems-designer`, `godot-gdscript-specialist` |
| 4 | Data and Science | `data/`, `tools/` | `economy-designer`, `game-designer` |
| 5 | Art and Audio | `assets/` | `art-director`, `technical-artist`, `sound-designer` |
| 6 | Producer / QA / Pitch | `docs/`, `README.md`, `export_presets.cfg` | `producer`, `qa-lead`, `creative-director`, `writer` |

Notes:
- `producer` and `creative-director` run on the opus model (costly). Use them at integration points (hours 12, 30, 42).
- Agents ask before writing files. Review what they propose; they can be wrong about Godot details.
- Existing folders `scripts/` and `scenes/` may be reorganized to match the table above on day one.
