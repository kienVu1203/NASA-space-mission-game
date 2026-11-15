You are the Senior Godot Engineer responsible for unifying controls, UI interaction, progression, audio, and presentation across all four phases of STAR FALL.

The game already runs. Apply targeted integration fixes to the existing implementation. Do not rebuild the project or replace working gameplay systems.

TARGET WORKSPACE
C:\Users\tamda\NASA-space-mission-game

==================================================
1. INSPECT BEFORE EDITING
==================================================

- Confirm that the target workspace exists.
- Read applicable AGENTS.md files, docs/roles.md, README.md, and the implementation contract if present.
- Inspect all four phases, main menu, pause menus, input registration, shortcuts, campaign state, saves, cinematics, audio, and credits.
- Check the actual Godot version and current Git changes.
- Preserve user changes.
- Follow existing project conventions.
- Do not silently edit another checkout.

This task assigns integration responsibility across the files necessary for the requested changes.

All new or modified code, comments, documentation, UI, and dialogue must use English.

Established identities:
- Game: STAR FALL.
- Protagonist: Nick.
- Companion: Bill.
- Spacecraft: VELA.
- Presentation: pixel art with 2.5D depth.

Preserve the established gameplay and story:
- Phase 1: build VELA on present-day Earth, launch, encounter the rift, crash, and activate Bill.
- Phase 2 boss 1: waste-sorting arena.
- Phase 2 boss 2: mouse-directed shield defense.
- Phase 3: environmental-vocabulary typing boss and reconstruction workshop.
- Phase 4: final assembly, departure, debris ascent, portal entry, homecoming, and credits.

==================================================
2. UNIFY MOVEMENT INPUT
==================================================

Use the same movement bindings wherever a character or controllable vehicle is allowed to move:

- W / Up Arrow: up.
- A / Left Arrow: left.
- S / Down Arrow: down.
- D / Right Arrow: right.

Requirements:
- Support normalized diagonal movement.
- Keep equivalent letter-key and arrow-key behavior.
- Avoid separate conflicting input definitions in different scenes.
- Reuse a shared input configuration or the existing appropriate abstraction.
- Do not register duplicate actions or erase another scene's shared actions during cleanup.
- Release movement safely when focus is lost.

CONTEXT-SPECIFIC BEHAVIOR

Unifying movement does not mean enabling movement in encounters designed around another input method.

Preserve:
- Exploration and waste-sorting arena: movement enabled.
- Boss 2 shield encounter: Nick remains fixed; mouse controls the shield.
- Phase 3 typing encounter: letter keys type vocabulary; they must not move Nick.
- Guided signal investigation: preserve its intended WASD/arrow reticle control.
- Noninteractive cinematics: gameplay movement disabled.

Input must be routed according to the active gameplay context.

Do not let:
- Typing "water" move Nick.
- A menu shortcut fire a weapon.
- A click on a UI button also fire into the world.
- Held movement continue after opening a modal screen.

==================================================
3. MOUSE SUPPORT FOR EVERY BUTTON
==================================================

Every visible button throughout the game must support ordinary mouse interaction.

Audit:
- Main menu.
- New Game / Continue.
- Settings.
- Story/dialogue panels.
- Sorting guide.
- Workshop and construction screens.
- Component selection and installation.
- Route and payload selection.
- Simulation controls.
- Confirmation dialogs.
- Defeat / Retry.
- Victory summaries.
- Pause menu.
- Final assembly.
- Credits and ending navigation.

Requirements:
- Buttons have correct clickable regions.
- Hover, pressed, disabled, and focus states are readable.
- Mouse clicks trigger the intended action once.
- Keyboard-focused controls remain usable.
- Sliders and other interactive settings work with the mouse.
- Overlays do not accidentally intercept valid clicks.
- Decorative controls do not block buttons underneath.
- Disabled controls cannot be activated through another input path.
- UI remains clickable after pause/resume and scene transitions.

Check coordinate handling through:
- Window scaling.
- SubViewports.
- Canvas transforms.
- Letterboxing, if applicable.

Do not require keyboard shortcuts when the corresponding visible button can reasonably be clicked.

==================================================
4. ESC IS THE UNIFIED PAUSE CONTROL
==================================================

Use Esc as the consistent pause control throughout playable sections and cinematics.

Behavior:
- Esc opens the pause menu.
- Esc closes the pause menu and resumes when appropriate.
- Within a modal/settings subpanel, Esc returns to the parent interface according to a consistent policy.
- Prevent the same key event from both closing a modal and immediately reopening pause.

The pause menu must support mouse interaction for:
- Resume.
- Settings.
- Relevant checkpoint/menu options.
- Confirmation dialogs.

Do not use Space or arbitrary letter keys as alternative pause controls.

Preserve Space for the Phase 2 boss 2 counterattack.

If a cinematic currently uses Space to pause or any key to advance automatically:
- Remove conflicting bindings.
- Use Esc for pause.
- Use explicit clickable controls for any intentionally retained cinematic navigation.

Pause must stop:
- Enemy movement.
- Projectile movement.
- Spawning.
- Damage.
- Typing timers.
- Dash and bonus timers.
- Active-match elapsed time.
- Cinematic progression.
- Other gameplay-affecting updates.

Handle audio consistently during pause.
Do not leave combat effects or looping machinery playing incorrectly after a scene has stopped.

==================================================
5. REMOVE PLAYER-FACING PASS SHORTCUTS
==================================================

Remove the I, O, and P quick-pass/skip behavior.

Inspect whether these are:
- Separate keys.
- A combined chord.
- Debug actions.
- Raw key checks.
- Scene-specific shortcuts.

Remove all player-facing routes that use them to:
- Skip a boss.
- Complete a map.
- Grant victory.
- Jump to another phase.
- Grant items unexpectedly.

Do not remove legitimate alphabet input from the typing encounter.
The letters I, O, and P must still work as vocabulary letters.

Do not replace the removed shortcuts with another undocumented player-facing bypass.

DEVELOPER-ONLY PROGRESSION TOOLS

If the project already retains an intentional developer-only progression hotkey for local testing:
- Keep it unavailable in normal player builds.
- Do not use I/O/P.
- Do not create a new shortcut unless required by an existing tool.
- When it jumps forward, apply the complete prerequisite state atomically.

That prerequisite state includes:
- Authored collectible items from the prior maps being treated as completed.
- Required previous boss rewards.
- Required archives and quest flags.
- Necessary chapter unlocks.
- Correct collected-item IDs.

Avoid:
- Partial progression.
- Duplicate unique components.
- A reward existing both in inventory and as an uncollected world drop.
- A later workshop opening without required earlier items.

This developer-only completion behavior must not run during ordinary play, normal map transitions, or normal menu input.

In normal gameplay, preserve physical boss-reward pickup requirements.

==================================================
6. INCREASE BOSS 2 PROJECTILE SPEED BY 1.2x
==================================================

Apply a 20% speed increase to the second Phase 2 boss's incoming energy projectiles at every existing difficulty/health band.

Formula:
new_speed = previous_configured_speed * 1.2

Apply it equally to:
- Hostile energy.
- Beneficial energy.

Preserve their established speed parity.

Requirements:
- Adjust the authoritative data/configuration.
- Do not repeatedly multiply speed every frame.
- Do not multiply again whenever the player retries.
- Do not accidentally apply both a data multiplier and a second runtime multiplier.
- Preserve the existing health-based speed progression.
- Keep firing-frequency behavior unchanged unless a technical correction is necessary.
- Do not change the waste-sorting arena or typing encounter projectile speeds.

Verify:
- Lowest difficulty speed.
- Intermediate speeds.
- Highest difficulty speed.
- Retry behavior.
- Hostile/beneficial equality.
- Existing swept shield interception at the increased speed.

Report the before/after configured speed values.

==================================================
7. PREVENT EARLY ACCESS FROM THE OPENING MENU
==================================================

A new player must not launch the first campaign encounter directly from the opening screen.

Require the established story sequence:
1. Start on healthy Earth.
2. Receive the mission.
3. Construct VELA.
4. Complete preflight.
5. Launch.
6. Investigate the signal.
7. Experience the rift and crash.
8. Meet/activate Bill.
9. Reach the first encounter through campaign progression.

Remove or lock menu options that bypass these prerequisites.

If an Eco Arena practice entry remains:
- Keep it locked for a new profile.
- Unlock it only after completing the corresponding campaign encounter.
- Show a concise locked-state explanation.
- Keep practice progress separate from campaign progress.

A valid Continue option may resume legitimately earned progress.

Check both:
- UI availability.
- Underlying progression guards.

Hiding a button is insufficient if another input path still bypasses the story.

Do not unlock content simply because a menu was opened or a scene was previewed.

==================================================
8. IMPROVE THE ORIGINAL EARTH LAUNCH
==================================================

Make the initial Phase 1 launch from present-day Earth into space more detailed and readable.

This is the first mission launch, before the time-rift accident.

Preserve:
- Player-built VELA.
- The committed component configuration.
- Existing preflight requirements.
- The canonical spacecraft design.
- Upright orientation, nose up, engines below.

Develop the sequence through clear visual stages:

A. READY ON THE PAD
- VELA stands on a recognizable launch platform.
- Nearby support structures establish scale.
- Engines are off.
- Show a brief launch-ready cue.

B. IGNITION
- Engines ignite at the bottom nozzles.
- Show a short buildup of exhaust and pad smoke.
- Add restrained ignition sound and vibration.

C. LIFTOFF
- VELA separates from the platform vertically.
- Exhaust and smoke react below.
- Camera framing makes the upward departure understandable.

D. ATMOSPHERIC ASCENT
- Ground and launch infrastructure recede.
- Transition through appropriate sky/cloud layers.
- Maintain the same spacecraft design and orientation.

E. SPACE
- Transition to a darker orbital environment.
- Establish Earth below or behind the spacecraft.
- Continue into the existing scientific signal investigation.

Use a compact cinematic rather than a long mandatory cutscene.
Avoid adding heavy dialogue.

Ensure:
- No asset swap during the sequence.
- No horizontal starting pose.
- No flame while the ship is parked.
- Engine audio transitions correctly.
- Pause and any retained skip control preserve the correct campaign state.

==================================================
9. REMOVE NASA INFORMATION FROM THE GAME
==================================================

Remove NASA-related information from all player-facing game presentation.

Audit:
- Main menu.
- Window title.
- Loading screens.
- HUD.
- Mission briefings.
- Dialogue.
- Tutorials.
- Workshops.
- Simulation screens.
- Reports.
- Ending screens.
- Credits.
- Visible links.
- Logos and text embedded in textures.
- Exported application display metadata.

The player-facing identity must be STAR FALL.

Do not replace NASA references with another invented endorsement or agency affiliation.

If an asset contains an unwanted logo or requires a player-facing attribution incompatible with this requirement:
- Replace the asset with a suitable original or appropriately licensed alternative.
- Preserve required license records.
- Do not falsely claim third-party work is original.

This task does not require renaming the user's local repository path or performing unrelated filesystem changes.

Search text and inspect visible art.
A text-only search cannot detect a logo embedded in an image.

==================================================
10. ENDING CREDITS: SIX TEAM MEMBERS
==================================================

After the homecoming and ending message, present a readable credits sequence containing these six names exactly, in this order:

DAM TRONG TAM
VU TRUNG KIEN
NGUYEN VU KHOI
NGUYEN CHAN TAI
NGUYEN LE KHOI HIEU
NGUYEN THAI DUONG

Requirements:
- Preserve spelling and capitalization.
- Do not invent job titles or assign roles.
- Use a clean pixel-compatible font.
- Ensure every name is fully visible.
- Use a comfortable scrolling speed or equivalent readable sequence.
- Keep text within safe screen margins.
- Include mouse-operable ending navigation.
- Esc must follow the unified pause/back policy.
- Do not place NASA information in this sequence.

Preserve campaign completion, mission results, and save behavior.
Replaying credits must not grant rewards again.

==================================================
11. UNIFY BASIC AUDIO ACROSS THE GAME
==================================================

Audit the entire game and establish a coherent basic audio system.

Use shared audio buses or the appropriate existing structure for:
- Master.
- Music.
- SFX.
- UI.

Persist volume settings.
Make settings sliders mouse-operable.

Provide consistent sounds for:
- UI hover where appropriate.
- Button confirmation.
- Back/cancel.
- Invalid action.
- Item pickup.
- Component installation.
- Objective completion.
- Player damage.
- Dash.
- Weapon firing.
- Shield block.
- Beneficial-energy absorption.
- Boss counterattack.
- Typing success and error.
- Boss defeat.
- Ship ignition and flight.
- Shield/debris contact.
- Portal entry.
- Landing.
- Victory/defeat.

Use a coherent restrained sound palette.
Reuse shared feedback where appropriate rather than layering unrelated effects.

Requirements:
- No missing audio references.
- No duplicate music players after scene transitions.
- No repeated button sound from one action.
- Rate-limit rapid typing/fire/impact sounds.
- Avoid clipping and harsh stacking.
- Fade or transition music/ambience appropriately.
- Stop scene-owned loops on exit.
- Respect pause, mute, and saved volume values.
- Keep sound effects subordinate to readability.

Use original or appropriately licensed assets.
Document actual sources.
Do not introduce copyrighted audio without permission.

Do not claim audio quality has been verified solely because files load.

==================================================
12. MAKE BILL STAND OUT AT THE FUTURE CRASH SITE
==================================================

Bill currently blends into the ground after Nick lands on ruined Earth.

Improve Bill's visual readability:
- Stronger silhouette separation.
- A small contrasting outline or rim highlight.
- A clear contact shadow.
- Distinctive cyan/white markings.
- Local environmental lighting or a restrained objective indicator.
- Correct depth sorting.

Preserve the pixel-art style.
Do not simply enlarge Bill until he dominates the scene.

STORY CONSISTENCY
Before Nick repairs the power connection:
- Bill remains inactive.
- Do not show behavior suggesting he has already been activated.
- Use reflective markings, environmental lighting, or an external marker to improve visibility.

After activation:
- Bill's active lights and following behavior may become visible.
- Maintain the existing companion relationship.
- Avoid duplicating Bill after reload or transitions.

Verify the result against the actual crash-site palette, not only on a blank background.

==================================================
13. PRESERVE PREVIOUSLY FIXED BEHAVIOR
==================================================

Do not regress:

PHASE 1
- Playable original spacecraft construction.
- Preflight validation.
- External-rift accident.
- Nick and Bill's established introduction.

PHASE 2
- Waste-sorting arena for boss 1.
- Shield-defense encounter for boss 2.
- Correct shield sweep collision.
- Matching hostile/beneficial projectile speeds.
- Charge meter outside the shield.
- Physical navigation_chip and power_core drops.
- Nick collecting those rewards before progression.

PHASE 3
- Randomized easy-to-hard vocabulary order.
- One projectile per accepted correct letter.
- Wrong-letter reset behavior.
- Left-side English definition panel.
- Physical shield pickup.
- Visual VELA reconstruction.
- Validated return-mission configuration.

PHASE 4
- One consistent VELA design.
- Engines off during transfer and after landing.
- Upright vertical launch.
- Debris/shield contact feedback.
- Visible portal entry.
- Pixel-art 2.5D homecoming.
- Nick exiting the ship and celebrating.
- No face close-up.

==================================================
14. SAVE AND STATE COMPATIBILITY
==================================================

Inspect existing saves before adding or changing:
- Practice unlocks.
- Input settings.
- Audio settings.
- Credits completion.
- Developer progression utilities.

Preserve legitimately earned progress.
Do not force existing players to replay completed chapters unnecessarily.

Keep normal gameplay distinct from developer-only testing tools.

Do not let:
- Settings changes grant inventory.
- Esc trigger a chapter transition.
- Menu clicks activate debug progression.
- Practice sessions overwrite campaign saves.
- Repeated loading duplicate rewards.

==================================================
15. VERIFICATION
==================================================

Run relevant parser/import checks and automated regressions using the actual installed Godot executable.

Verify across all four phases:

INPUT
- WASD and arrow movement behave consistently where movement is enabled.
- Typing does not move Nick.
- Boss 2 remains fixed-position.
- UI input does not trigger gameplay.
- Focus loss releases held actions.

MOUSE
- Every visible button can be clicked.
- Pause-menu buttons work.
- Settings sliders work.
- Resizing and viewport scaling preserve hit regions.
- One click triggers one action.

PAUSE
- Esc pauses and resumes consistently.
- Space no longer pauses.
- Combat, timers, cinematics, and audio follow the pause policy.
- Closing a modal does not immediately reopen pause.

PROGRESSION
- I/O/P cannot bypass content in normal play.
- I/O/P still work as typing letters.
- New profiles cannot access the first encounter before the story prerequisites.
- Practice unlocks only after the required completion.
- Retained developer-only jumps apply complete prerequisite state without duplicate items.

BOSS 2
- Every configured projectile speed is multiplied by 1.2 once.
- Hostile and beneficial speeds remain equal.
- Retry does not compound the multiplier.
- Swept shield blocking still works.

PRESENTATION
- Initial Earth launch is coherent and upright.
- Bill is distinguishable on the crash-site ground.
- All six credit names are correct and readable.
- No NASA information appears in player-facing screens or assets.

AUDIO
- Saved volume settings work.
- No duplicate loops or stacked scene music.
- Rapid effects remain controlled.
- Pause and scene exit clean up audio correctly.

Run graphical/manual checks where available.
Report separately what was automated, visually inspected, and heard.

Do not claim full visual/audio verification from headless execution.

==================================================
16. DELIVERY
==================================================

Update:
- README.md.
- Control documentation.
- Audio/settings documentation.
- Progression and practice-unlock rules.
- Relevant test checklist.
- Current implementation status.

Final report:
- Root causes identified.
- Changes implemented.
- Main files changed.
- Final controls by gameplay context.
- Boss 2 speed values before/after.
- Removed or restricted shortcuts.
- Audio changes.
- Tests and actual outcomes.
- Visual/audio checks performed.
- Remaining limitations.

Complete the authorized fixes and integration work before returning the report.
Do not stop after proposing a plan.