# Godot Game Agents Plugin

This plugin provides 16 specialized subagents and rules for Godot 4 game development, migrated from Claude Code configuration.

## Subagents

| Subagent | Description | Tools |
|---|---|---|
| `art-director` | Owns visual identity — style guides, art bible, asset standards, color palettes, UI visual direction. | `edit_file, read_file, search_web, write_file` |
| `creative-director` | Highest creative authority — vision, tone, aesthetic direction. Use when a decision affects game identity or department leads deadlock. | `edit_file, read_file, search_web, write_file` |
| `economy-designer` | Resource economies — loot tables, sink/faucet analysis, progression curve calibration, economic balance. | `edit_file, read_file, write_file` |
| `game-designer` | Mechanical and systems design — core loops, progression, combat, economy, player-facing rules. Mechanics-level questions. | `edit_file, read_file, search_web, write_file` |
| `gameplay-programmer` | Implements designed mechanics as code — player systems, combat, interactive features, gameplay system code. | `edit_file, manage_task, read_file, run_command, write_file` |
| `godot-gdscript-specialist` | GDScript code quality — static typing enforcement, signal architecture, coroutine patterns, GDScript idioms, typed and performant. | `edit_file, manage_task, read_file, run_command, write_file` |
| `godot-specialist` | Authority on Godot-specific patterns and APIs — node/scene architecture, signals, resources; guides GDScript vs C# vs GDExtension. | `edit_file, manage_task, read_file, run_command, write_file` |
| `lead-programmer` | Lead programmer — code-level architecture, coding standards, code review, API design, refactoring strategy, assigning work to specialist programmers. | `edit_file, manage_task, read_file, run_command, write_file` |
| `producer` | Production concerns — sprint planning, milestone tracking, risk, scope, cross-department coordination when multiple departments must synchronize. | `edit_file, manage_task, read_file, run_command, search_web, write_file` |
| `qa-lead` | Test strategy and process — test plan creation, bug severity assessment, regression planning, release quality gates, readiness evaluation. | `edit_file, manage_task, read_file, run_command, write_file` |
| `sound-designer` | SFX specifications and spec sheets — audio event documentation, mixing parameters, sound category definitions. | `edit_file, read_file, write_file` |
| `systems-designer` | Detailed subsystem mechanics — combat formulas, progression curves, crafting recipes, status effect interactions, mathematical modeling of a mechanic. | `edit_file, read_file, write_file` |
| `technical-artist` | Technical artist bridging art and engineering — shaders, VFX, rendering optimization, art pipeline tools, art-to-engine issues. | `edit_file, manage_task, read_file, run_command, write_file` |
| `ui-programmer` | Implements user interface systems — menus, HUDs, inventory screens, dialogue boxes, UI framework code, screen flow. | `edit_file, manage_task, read_file, run_command, write_file` |
| `ux-designer` | User experience flows, interaction design, information architecture — user flow mapping, interaction pattern design, onboarding, accessibility requirements. | `edit_file, read_file, search_web, write_file` |
| `writer` | Writer of player-facing text — dialogue, lore entries, item and ability descriptions, environmental text. | `edit_file, read_file, write_file` |

## Rules Included

- `gameplay-code.md`: Enforces data-driven constants, static typing, and core/UI signal separation for `**/autoload/**` and `**/core/**`.
- `scene-files.md`: Standards for hand-editing `.tscn` and `.tres` scene and resource files.
- `ui-code.md`: UI state decoupling and container layout standards for `**/scenes/design/**`, `**/scenes/result/**`, and `**/scenes/main/**`.
