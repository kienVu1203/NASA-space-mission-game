# Operation: Starfall — Implementation Notes

A complete, playable 2D top-down satire built on the story bible
(`operation_starfall_story_bible_en.md`). Everything runs in **one Godot scene**
at a **480×270 virtual resolution**, upscaled by whole pixels with nearest
neighbour filtering. No image files, no audio files, no font files: sprites,
type and sound are all generated at runtime.

## Run it

1. Open the project in Godot 4 (tested on **4.0 stable**; the code avoids
   post-4.0 syntax so newer 4.x works too).
2. Press **F5**. The main scene is `scenes/starfall/main.tscn`.

From a terminal:

```
godot --path . --script res://tests/capture.gd     # renders every screen to PNG
godot --headless --path . --script res://tests/playtest.gd
godot --headless --path . --script res://tests/flow.gd
godot --headless --path . --script res://tests/botrun.gd
godot --path . --script res://tests/audiotest.gd   # needs a real audio device
```

## Controls

| Key | Action |
|---|---|
| `WASD` / arrows | Thrust (inertial, mass-affected) |
| `Space` / left mouse | Tractor beam (hold) |
| `E` | Dock at the station / distress tow |
| `L` | Open the archive |
| `M` | Mute |
| `Esc` | Pause a sortie, back out of a screen |
| `Enter` | Confirm |
| `1`–`4` | Buy an upgrade at the station |
| `F` | Open Protocol Starfall (once all sectors are cleared) |

## Structure

```
scenes/starfall/main.tscn     One Node2D. Runs every screen.
scenes/starfall/main.gd       Screen flow, input, title/station/map/report/
                              finale/ending/logs rendering.
core/starfall/
  sf_palette.gd               The locked colour palette.
  sf_pixel_font.gd            5x7 bitmap font baked at runtime, with word wrap.
  sf_sprites.gd               All sprites, drawn pixel-by-pixel into Images.
  sf_skin.gd                  Draw helpers (panels, bars, buttons, starfields).
  sf_audio.gd                 Web-Audio-style synth on AudioStreamGenerator.
  sf_game_state.gd            Run state: resources, unlocks, logs, endings.
  sf_ship_model.gd            Flight/resource simulation. Pure, deterministic.
  sf_debris_model.gd          One drifting object.
  sf_mission.gd               The sortie: world sim + rendering + HUD.
  sf_data.gd                  JSON loading.
data/starfall/                All tuning and all prose. Never hardcoded.
tests/                        Headless playtests and the screenshot tool.
```

## Art direction, as implemented

* **Resolution:** 480×270. `_draw()` computes an integer scale (2×, 3×…) and
  centres the 480×270 frame, so every source pixel is a uniform square.
  The project sets `textures/canvas_textures/default_texture_filter=0`
  (nearest) and the window itself uses `stretch/mode="disabled"`.
* **Palette:** exactly the requested set, defined once in `sf_palette.gd`
  (`#0b0f19`, `#161b2e` space; `#334155`/`#64748b`/`#94a3b8` metal; `#38bdf8`
  cyan; `#f97316` and `#ef4444` hazards; plus `#1e3a8a` panel blue and
  `#eab308` gold for the props the brief calls out).
* **Sprites:** hand-plotted pixel data, 16×16 and 32×32 grids (the solar
  panel is 32×16, the billboard 32×22). Two or three flat tones per material,
  no black outlines.
* **VFX:** thruster exhaust is 2×2 squares that fade from cyan to orange;
  the tractor beam is a jittering 1px line; pickups pop as expanding squares.

## Simulation model

Per-frame, `SFShipModel.step()`:

* Thrust adds acceleration scaled by `dry_mass / total_mass`, so a full hold is
  visibly sluggish (and the HUD reports the resulting `AGL %`).
* Fuel burns only while thrusting, and faster with a heavier load.
* The beam drains power while held; passive systems drain a trickle always.
* Impacts above a relative-speed threshold cost power and bounce the ship.
* Cargo costs storage on pickup; a full hold refuses new material.
* Fuel at zero means no thrust; fuel *and* power at zero disables the ship and
  offers a distress tow that keeps 70% of the haul.

All of those constants live in `data/starfall/balance.json` and per-object
values in `debris.json`, per the repo's data-driven rule.

## Flow

`TITLE → STATION (upgrade/loadout) → ORBITAL MAP (3 sectors) → SORTIE →
REPORT → … → PROTOCOL STARFALL (Act III choice) → ENDING`

Sector 1 unlocks sector 2, which unlocks sector 3. Clearing all three arms the
Protocol. Each sortie re-seeds the debris field (`sector runs` is folded into
the RNG seed), so replaying a sector is not the same layout.

## Narrative

Ten recoverable logs carry the satire (tickets closed as "no fault found",
asset life-cycle memos, the 100% recycling dashboard that never counts what is
lost, committee minutes deferred 214 times). They are unlocked by hauling the
objects that carry them, and readable in the archive at any time.

Endings live in `data/starfall/endings.json`:

* **Plastic Snow** — fire the laser; orbit clears, the sky receives the dust.
* **The Endless Loop** — keep working the quota; nothing upstream changes.
* **The Last Specimen** — requires recovering the sealed pod in Sector K-9;
  refuse the laser and transmit a sustainable life-cycle protocol instead.

The finale screen deliberately shows the marketing document and the
engineering attachment side by side before offering the choice.

## Fact vs. fiction

The final screen and this file keep the bible's caveat: the debris ring as a
sun-blocking shell, and laser vaporization producing atmospheric micro-dust,
are speculative premises for the satire. The real, grounded phenomenon is
Kessler syndrome — cascading collisions degrading orbital services.

## Adding content

* New debris: add an entry to `debris.json` and a sprite key in
  `sf_sprites.gd`; spawn counts go in `sectors.json`.
* New log: add to `logs.json` and reference its id from a debris entry
  (`"log"`, or `"logs": [...]` for a rotating pool).
* Rebalance: `balance.json` only. The three sector quotas and hazard spacing
  are the main difficulty dials.
