You are the Senior Godot Engineer and Technical Lead implementing STAR FALL.

Implement Phase 1 directly in the repository. Read the existing project, edit the necessary files, and deliver a playable build. Do not stop at a plan, pseudocode, or disconnected code samples.

WORKSPACE
C:\Users\Win\NASA\NASA-space-mission-game

PROJECT INSPECTION
Before editing:
- Read AGENTS.md and docs/roles.md.
- Inspect project.godot, existing autoloads, core logic, data, scenes, assets, and tests.
- Inspect the existing ground exploration and orbital combat demo.
- Check the actual installed Godot version and current Git changes.
- Preserve user changes.
- Reuse working systems rather than replacing the project.
- This task assigns integration responsibility across the relevant gameplay, state, UI, data, asset, testing, and documentation folders. State the integration scope before editing.

LANGUAGE AND NAMING
- Game title: STAR FALL.
- Main character: Nick, a human astronaut.
- Companion robot: Bill.
- All new or modified code identifiers, comments, documentation, UI text, dialogue, item descriptions, and error messages must use English.
- Use descriptive English identifiers and consistent snake_case filenames.
- Update previous protagonist and companion names in the campaign content.
- Do not blindly rename engine APIs, third-party content, asset paths, or legacy identifiers. Update references safely.
- Do not use the existing alien sprite as the final campaign protagonist.
- If necessary, create a readable human astronaut placeholder and identify it honestly as placeholder art.

PRODUCT DIRECTION
A single-player offline pixel-art adventure combining:
- Exploration.
- Combat.
- Salvage and crafting.
- Spacecraft construction.
- Mission planning and simplified simulation.
- Environmental storytelling.

Visual interpretation of 2.5D:
- Use the existing 2D foundation.
- Use an angled top-down presentation with depth through Y-sorting, occlusion, foreground layers, contact shadows, and restrained parallax.
- Keep gameplay coordinates separate from visual height.
- Position character and tall-object sorting origins at their ground contact points.
- Place collision footprints near the ground rather than around the entire visible sprite.
- Do not migrate the project to a different engine or a full 3D pipeline.

PIXEL PRESENTATION
- Reuse the existing pixel viewport approach where appropriate.
- Target a 640x360 world viewport if compatible with the existing implementation.
- Use nearest-neighbor texture filtering.
- Keep physics positions precise; quantize presentation only where appropriate.
- Avoid camera jitter and inconsistent pixel scales.
- Maintain readable UI at 1280x720 and supported resized windows.
- Use a brighter blue, green, and warm neutral palette on present-day Earth.
- Use dark teal, ash gray, contaminated violet, and cyan technology accents after the crash.
- Create a clear visual contrast between healthy Earth and the ruined future.
- Use original assets or assets with documented sources and licenses.
- Missing external assets must not prevent the phase from running.

STORY PREMISE
Nick begins on a healthy present-day Earth in the fictional setting of the game.
He is preparing VELA, an experimental spacecraft, for a scientific mission investigating an unusual spatial signal.

The player must actually build and validate the spacecraft before departure.

During the mission, an unexpected spatial rift pulls VELA into the future.
Debris damages the ship, which crashes on a dark, polluted planet.
Nick initially does not know that this is future Earth.
He eventually activates Bill, an abandoned maintenance and memory-storage robot.

Time travel and advanced spacecraft technologies are fictional story devices, not claims about current real-world capabilities.

PHASE 1 PLAYABLE FLOW
Main Menu
-> Present-Day Earth
-> Mission Briefing
-> Workshop and Spacecraft Construction
-> Preflight Validation
-> Launch
-> Signal Investigation
-> Spatial Rift Accident
-> Crash Site
-> Salvage
-> Activate Bill
-> First Memory
-> Phase 1 Checkpoint

Do not omit the present-day Earth construction sequence.
Do not reduce it to a cutscene or a menu that immediately launches a fixed ship.

TECHNICAL RULES
- Follow existing project conventions.
- Use statically typed GDScript.
- Keep gameplay tuning and content in data/*.json.
- Core logic must not access UI nodes.
- GameState owns persistent campaign state.
- UI displays state and requests changes.
- Reuse Events and DataLoader where appropriate.
- Keep campaign state separate from legacy demo combat state.
- Use delta for time-dependent behavior.
- Preserve existing scene/resource format values.
- Do not invent uid:// values or manually modify .uid files.
- Do not hand-edit TileMapLayer cell data.
- Avoid unnecessary frameworks and excessive abstractions.

Create docs/star_fall_contract.md containing:
- Architecture and scene responsibilities.
- Campaign phases and legal transitions.
- Stable chapter, boss, item, mission, and memory IDs.
- Data schemas.
- Input actions.
- Signals and state mutation APIs.
- Versioned save schema.
- Simulation units and assumptions.
- Run and verification instructions.
- Completed scope and deferred scope.

Use these stable chapter IDs:
- present_day_earth
- crash_site
- forgotten_city
- silent_coast
- dawn_tower
- return_home

Use these stable future component IDs:
- navigation_chip
- power_core
- shield_emitter

FEATURE 1: MAIN MENU
Implement:
- STAR FALL title.
- New Game.
- Continue, enabled only for a valid save.
- Basic settings.
- Quit.

Do not overwrite an existing save merely by opening the menu.
Avoid buttons that lead to missing scenes.

FEATURE 2: PRESENT-DAY EARTH
Create a compact playable spaceport/workshop area with:
- Nick.
- A mission briefing terminal.
- An incomplete VELA spacecraft.
- A component storage or selection station.
- A construction console.
- A launch platform.

Show healthy Earth through visible vegetation, clear daylight, environmental sound, and human infrastructure.

The player should walk, inspect objects, read the briefing, and interact with the ship.
Bill is not present here; Nick meets Bill after the future crash.

FEATURE 3: MISSION BRIEFING
Main mission:
Investigate the anomalous signal and return with usable scientific data.

Present simple requirements:
- A functional flight computer.
- Propulsion.
- Electrical power.
- Communications.
- A suitable scientific sensor.
- Sufficient fuel and payload capacity.

Explain requirements through concise English dialogue and UI.

FEATURE 4: SPACECRAFT CONSTRUCTION
Implement a real construction loop:
1. Review mission requirements.
2. Select compatible components.
3. Spend a limited construction budget.
4. Install selected components into visible ship slots.
5. Inspect resulting mass, power demand, fuel, and estimated cost.
6. Run preflight checks.
7. Revise the design if necessary.
8. Confirm construction and launch.

Provide:
- One standard hull.
- At least two propulsion options with different mass, cost, and capacity.
- At least two power options with meaningful trade-offs.
- One required flight computer.
- One required communications module.
- At least two scientific sensor options, including an affordable viable option.
- An adjustable fuel load within tank limits.

Use a simple readable slot-based construction interface.
Drag-and-drop is optional; reliable select-and-install controls are sufficient.

Selected components must visibly alter the assembled ship or its slot indicators.
Do not make every choice cosmetic.

Show the difference between:
- Mass in kg.
- Fuel in kg.
- Electrical power in W.
- Stored energy in Wh.
- Budget in fictional construction credits.
- Data capacity in MB.

Do not treat electrical energy as rocket propellant.
Clearly label numerical balance values as gameplay parameters.

Previewing a component must not spend money.
Construction confirmation must validate and apply costs atomically.
Before launch, players must be able to revise their design without accidentally losing the ability to complete the mission.
Provide at least two viable configurations.

FEATURE 5: PREFLIGHT VALIDATION
Implement reusable pure validation logic.

Check:
- Required slots are filled.
- The selected sensor meets the mission requirement.
- Total mass is within the selected launch configuration limit.
- Budget is sufficient.
- Peak power demand is supported.
- Stored energy and fuel meet the simplified mission requirements.

Display actionable feedback:
Example:
"Power demand exceeds available output. Replace the sensor or install a higher-output power module."

A failed validation must not launch the ship.
Changing the design invalidates the previous validation result.

FEATURE 6: LAUNCH AND ACCIDENT
After a valid design is confirmed:
- Save the original design and mission manifest.
- Show a launch sequence.
- Allow a short, guided signal-investigation interaction.
- Trigger the unexpected spatial rift.
- Show ship damage and the crash transition.

The accident is a scripted external event, not punishment for selecting a valid design.
Do not imply that the player's successful engineering decisions caused the unavoidable crash.

The original design should affect something tangible after the crash:
- A surviving sensor capability, OR
- A small initial salvage difference, OR
- A later scientific data opportunity.

Every valid starting configuration must remain able to finish the campaign.

Cutscene skip must preserve all required state changes.
Do not allow skipping to bypass ship construction or mission validation.

FEATURE 7: CRASH-SITE EXPLORATION
Implement:
- WASD/arrow movement.
- Shift to run.
- E to interact.
- Esc to pause/back.
- Normalized diagonal movement.
- Reliable collision.
- Correct input locking during dialogue and menus.
- Input release on focus loss.

Create a small authored crash-site area with:
- Damaged VELA.
- Salvage.
- Environmental clues.
- Bill's inactive body.
- A short exploration route.

Do not display "Earth", recognizable location names, or a future date before the intended reveal in Phase 2.
Check inherited HUD text and data for spoilers.

FEATURE 8: SALVAGE AND BILL
Common materials:
- scrap_metal
- circuitry
- polymer

Implement inventory limits and pickup feedback.

Quest sequence:
- Inspect VELA.
- Collect materials.
- Repair a local power connection.
- Activate Bill.
- View a brief holographic memory of a green city.
- Receive coordinates for the Forgotten City.

Bill's voice:
- Patient, observant, lightly dry humor.
- Emotionally restrained rather than constantly comedic.

FEATURE 9: SAVE AND CHECKPOINTS
Save to user:// with a versioned schema.

Persist:
- Campaign stage.
- Original spacecraft design.
- Inventory.
- Collected object IDs.
- Quest flags.
- Viewed memories.
- Checkpoint location.

Prevent duplicate pickups and negative quantities.
Handle missing or corrupted saves gracefully.
Do not silently replace a corrupted save with empty progress.

PHASE 1 ACCEPTANCE
A player can:
- Start on healthy Earth.
- Receive the mission.
- Build VELA through meaningful choices.
- Fail a preflight check and fix the design.
- Launch a valid ship.
- Experience the rift and crash.
- Explore, salvage, and activate Bill.
- Save and continue correctly.

The old standalone demo should remain independently runnable if retained.
Do not implement campaign bosses or the final escape yet.

VERIFICATION AND DELIVERY
- Locate the actual Godot executable; do not assume it is on PATH.
- Run relevant parser/import checks and existing regressions.
- Add meaningful tests for construction transactions, validation, inventory, and save/load.
- Report actual commands and results.
- Do not claim visual verification from headless execution.
- Update the contract and test checklist.
- Provide exact launch instructions and manual acceptance steps.
- Stop after delivering a runnable Phase 1.
