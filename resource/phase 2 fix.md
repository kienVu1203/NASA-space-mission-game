You are a Senior Godot Gameplay Engineer and Educational Game Designer implementing a targeted Phase 2 revision for STAR FALL.

Modify the existing project directly. Deliver playable, integrated changes rather than only a plan, pseudocode, or disconnected examples.

TARGET WORKSPACE
C:\Users\tamda\NASA-space-mission-game

==================================================
1. INSPECT THE PROJECT BEFORE EDITING
==================================================

- Confirm that the target workspace exists.
- Read applicable AGENTS.md files, docs/roles.md, README.md, and the implementation contract if present.
- Inspect the actual campaign flow, both Phase 2 encounters, player controls, Bill, inventory, rewards, saves, assets, and tests.
- Inspect current Git changes and preserve user work.
- Follow the installed Godot version and existing repository conventions.
- Do not assume previously proposed files or APIs exist.
- Do not silently edit a different checkout if the requested workspace is unavailable.

This task assigns integration responsibility across the files necessary for this Phase 2 revision.

All new or modified code, comments, documentation, UI, and dialogue must use English.

Established identities:
- Game: STAR FALL.
- Protagonist: Nick, a human astronaut.
- Companion: Bill.
- Spacecraft: VELA.

==================================================
2. EXACT SCOPE OF THIS REVISION
==================================================

REPLACE THE FIRST PHASE 2 ENCOUNTER
Replace its existing mouse-directed shield-defense gameplay with an Educational Arena Survival encounter about waste sorting.

PRESERVE THE SECOND PHASE 2 ENCOUNTER
Keep its existing:
- Mouse-directed, always-active shield.
- Hostile and beneficial energy.
- Charge accumulation.
- Space counterattack.
- Health-based attack escalation.
- Existing shield responsiveness and swept-blocking fixes.

FIX REWARDS IN BOTH ENCOUNTERS
Both bosses must drop physical campaign components that Nick approaches and collects:
- Boss 1: navigation_chip.
- Boss 2: power_core.

Do not automatically grant these components merely because boss health reaches zero.

PRESERVE OTHER PHASES
Do not redesign Phase 1, the Phase 3 vocabulary boss, spacecraft construction, or the ending.

==================================================
3. TWO ENTRY POINTS, ONE ARENA IMPLEMENTATION
==================================================

Implement the recycling arena as a reusable mode with two entry points:

A. Campaign:
- Replaces the first Phase 2 boss encounter.
- Preserves its narrative role, Earth reveal, navigation-chip reward, and subsequent chapter unlock.

B. Standalone practice:
- Accessible from the Main Menu.
- Suggested label: "Eco Arena — 5–7 Min".
- Uses the same gameplay implementation.
- Does not modify campaign inventory, boss flags, chapters, or campaign saves.

Keep mode-specific session state separate.
Do not duplicate the arena code for these entry points.

The arena's final enemy, Junkyard Colossus, belongs to the first boss encounter.
It is not an additional campaign boss that changes the established three-component storyline.

==================================================
4. EDUCATIONAL RULES: STAR FALL'S THREE COLORS
==================================================

Present this as STAR FALL's sorting convention.

Do not claim that these bin colors are a universal international standard.

Do not display the sentence:
"Check your local sorting rules."

The learning objective is to recognize waste materials, contamination, and separation steps through a simple game convention.

Use this mapping:

GREEN — ORGANIC
- Food scraps.
- Banana peels.
- Leaves.
- Clearly food-soiled, uncoated paper packaging under the game's sorting convention.

BLUE — CLEAN PAPER AND CARDBOARD
- Clean cardboard boxes.
- Dry newspapers.
- Clean office paper and similar suitable paper items.

YELLOW — EMPTY PLASTIC AND METAL CONTAINERS
- Empty plastic bottles.
- Aluminum beverage cans.
- Empty tin cans.

Avoid teaching misleading generalizations:
- Do not state that every greasy cardboard item is universally unrecyclable.
- Do not classify every liquid as organic.
- Do not imply every type of plastic belongs in the same recycling stream.

For the two-stage bottle:
- Clearly show organic food residue or a leftover organic drink.
- First use Green to remove that content.
- Then use Yellow for the empty plastic shell.

Keep educational content consistent with this explicitly simplified game convention.

Do not add hazardous waste, batteries, glass, or other unsupported categories to this three-color activity.

==================================================
5. REQUIRED PRE-MATCH SORTING GUIDE
==================================================

Before entering the arena, show a short, simple guide.

Use three illustrated cards:
- Green / Organic.
- Blue / Clean Paper.
- Yellow / Plastic & Metal.

Each card contains:
- A large color swatch.
- A category icon.
- Two or three recognizable item examples.
- A short English explanation.
- Its keyboard shortcut: 1, 2, or 3.

Also explain briefly:
- Match the material to break armor.
- Match again to clean a dropped core.
- Separate food residue before recycling the bottle.

Use a clear Start button.
Do not make this a long story cutscene or dialogue sequence.

Allow the guide to be reopened from pause.
Retries should be fast; do not force the full guide again after every defeat.

Do not rely solely on color.
Keep category names, icons, and shapes readable.

==================================================
6. ARENA AND PIXEL-ART PRESENTATION
==================================================

Arena:
- One authored recycling arena.
- Approximately 1280x960 world space.
- 640x360 pixel world viewport where compatible with the existing project.
- Angled top-down 2.5D presentation.
- Y-sorting.
- Ground-contact shadows.
- Clear navigation around the central station and crushers.
- Nearest-neighbor texture filtering.
- Stable camera movement and consistent pixel scale.

Provide:
- A central Energy Recovery Station.
- Three color-coded recycling crushers.
- Readable entry/spawn areas.
- Space for movement and dash avoidance.

Avoid enemy spawning directly on Nick or trapping him against scenery.

Keep the HUD readable at the supported window sizes.

==================================================
7. NICK'S ARENA CONTROLS
==================================================

- WASD / Arrow Keys: normalized eight-directional movement.
- Shift: short invulnerability dash.
- Mouse: aim.
- Left Click: fire the Tri-Spectrum Blaster.
- 1: Green mode.
- 2: Blue mode.
- 3: Yellow mode.
- Mouse Wheel: cycle spectrum modes.
- Hold Right Click or E: Bill's sorting tractor beam.
- Esc: pause.

Dash:
- 1.5-second cooldown.
- Configurable duration, distance/speed, and invulnerability window.
- Must not pass through solid arena boundaries.
- Clear readiness feedback.

Do not let these controls leak into boss 2.
Do not activate boss 2's shield/counterattack systems inside the arena.

==================================================
8. HEALTH AND SHIELD
==================================================

Nick has separate health and shield values.

Rules:
- Incoming damage depletes shield first.
- Remaining damage reduces health.
- Zero shield alone does not cause defeat.
- Zero health causes defeat.
- Shield regeneration uses a configurable base rate and delay.
- Damage, regeneration, and invulnerability must resolve consistently.

Defeat:
- Stop combat and scoring updates.
- Offer Retry within approximately one second.
- Restart this encounter, not the campaign.
- Reset encounter-local health, shield, station charge, enemies, cores, timers, combo, and boss state.
- Preserve progress earned before this encounter.

==================================================
9. ENEMY MATERIAL READABILITY
==================================================

Every material needs:
- A recognizable silhouette.
- A 16x16 pixel waste-item badge.
- Material-specific hit feedback.

GREEN ENEMIES
- Round sludge/moss-like waste armor.
- Large banana peel, leaf, or vine details.
- Organic particles and a soft impact sound.

BLUE ENEMIES
- Blocky cardboard armor.
- Box-flap arms or newspaper details.
- Paper fragments and tearing feedback.

YELLOW ENEMIES
- Tall bottle/can silhouettes.
- Bottle caps, pull tabs, or cylindrical bodies.
- Crisp pixel highlights.
- Sparks and hollow metallic/plastic impact feedback.

Enemies may be waste-armored robots whose material armor creates these silhouettes.

TRICK VARIANTS
- Food-soiled uncoated pizza packaging: Green under the game's convention.
- Dry office paper or magazines: Blue.
- Crushed empty metal cans: Yellow.
- Organic-residue bottle: Green layer, then Yellow shell.

Make contamination visually obvious.
Do not rely on tiny texture details alone.

BADGES
Show the badge when:
- Nick targets an enemy.
- Nick approaches a dropped core.

During the first arena stage:
- Include a glowing matching-color border.

From the second stage onward:
- Remove that answer-revealing border.
- Keep the item icon and other readability cues.

==================================================
10. TRI-SPECTRUM COMBAT
==================================================

Matching the active material layer:
- Deals 2.5 times the configured reference armor damage.
- Produces appropriate armor-breaking feedback.
- Applies configured knockback.

Wrong spectrum:
- Deals zero armor damage.
- Produces a brief deflection effect.
- Triggers a short Bill coaching message.
- Does not flood the screen with repeated messages.

Use approximately 5–7 words per coaching message.

Examples:
- "Food-soiled paper uses Green. Press one!"
- "Clean paper uses Blue. Press two!"
- "Empty metal cans use Yellow. Press three!"

Rate-limit callouts and prioritize the most relevant correction.

Multi-layer enemies:
- Expose one active material layer at a time.
- Require the correct spectrum for that layer.
- Clearly show when the next layer is exposed.
- Do not damage hidden layers through the wrong outer material.

Keep projectile collision reliable at the configured speeds.
Prevent duplicate hits and stale projectiles after scene transitions.

==================================================
11. DIRTY ENERGY CORES
==================================================

Defeated enemies drop physical Energy Cores inside waste shells.

Examples:
- Organic vines around a core.
- A cardboard casing.
- A crushed can or bottle casing.

Do not automatically collect a core when its enemy dies.

STANDARD CORE
- Adds 4 percentage points to station charge after cleaning and collection.

DUAL CORE
- Adds 8 percentage points.
- Clearly indicates its required material sequence if multiple cleaning steps are needed.

WRONG-COLOR CONTACT
- Produces a harmless static spark and small nudge.
- Does not reduce health.
- Does not collect or destroy the core.
- Uses a cooldown/debounce to prevent repeated contact jitter.

CORRECT CLEANING
The player can:
- Select the matching spectrum and approach the core.
- Or hold Right Click / E to use Bill's longer-range tractor beam.

Then:
1. The correct waste shell is removed.
2. A clean core becomes visible.
3. It moves toward Nick's pack.
4. Collection resolves once.
5. Station charge updates once.

Crushers may produce pre-cleaned cores.
Those cores remain physical pickups.

Core collection must remain reliable during dash, movement, overlapping pickups, and scene cleanup.

==================================================
12. BILL'S FOLLOWING AND SORTING BEAM
==================================================

Bill remains Nick's visible companion throughout the arena.

Requirements:
- Hover near and slightly behind Nick.
- Avoid overlapping Nick.
- Avoid blocking movement.
- Do not absorb enemy projectiles or take unintended combat damage.
- Follow through normal movement and dash recovery.
- Recover safely if separated or stuck.

The sorting beam:
- Targets an eligible nearby core using a clear deterministic rule.
- Has a configurable range.
- Checks the current spectrum against the core's active shell.
- Visually connects Bill to the actual selected core.
- Stops correctly on release, pause, defeat, or invalid targets.
- Cannot collect the same core twice.

Preserve Bill's existing following behavior elsewhere in Phase 2.

==================================================
13. ECO OVERDRIVE
==================================================

Collect three distinct standard material colors consecutively without a sorting mismatch:
Green, Blue, and Yellow in any order.

Trigger Eco Overdrive for 8 seconds:
- +30% movement speed.
- +25% shield regeneration rate.
- A rainbow spectrum that automatically matches the currently exposed combat armor layer.

Rules:
- Keep the effect readable.
- Restore normal values exactly afterward.
- Do not permanently multiply stats after repeated activations.
- Define refresh/retrigger behavior explicitly.
- A mismatch breaks the relevant combo.
- One pickup must not generate multiple combo events.
- Dual cores must not masquerade as several separate pickups.

Overdrive may match the currently exposed enemy layer.
It must not skip an entire layered enemy in one unrelated hit.

IMPORTANT EXCEPTION
The final Super Core always requires manual:
1 -> 2 -> 3

Eco Overdrive cannot bypass those three educational locks.

==================================================
14. RECYCLING CRUSHERS
==================================================

Place three distinct crushers around the arena:
- Green.
- Blue.
- Yellow.

Nick can bait a charging enemy toward a crusher and dash away.

A matching crusher:
- Recycles the eligible enemy.
- Produces one pre-cleaned physical core.
- Uses the same authoritative enemy-death/drop pipeline.

A mismatched crusher must not count as successful sorting.

Avoid:
- Multiple drops from one enemy.
- Repeated damage/death callbacks.
- Crusher geometry that traps Nick.
- Removing every layer of an elite without respecting the configured rule.

Document how crushers interact with multi-layer enemies.

==================================================
15. PROGRESSION BY STATION CHARGE
==================================================

Progression is controlled by recovered energy, not fixed elapsed-time gates.

The timing below is a balancing target for a roughly 5–7 minute successful run.

STAGE 1 — WARM-UP
- Starts at 0%.
- Ends when charge reaches or exceeds 25%.
- Small single-material groups.
- Color-bordered badges.
- Target duration: approximately 0:00–1:30.

STAGE 2 — LOOK-ALIKE TRAPS
- Begins after the first threshold.
- Ends at or above 55%.
- Remove badge color borders.
- Introduce clearly signposted trick items.
- Target cumulative time: approximately 1:30–3:30.

STAGE 3 — MULTI-LAYER ELITES
- Continues until 80%.
- Introduce sequential material layers and dual cores.
- Target cumulative time: approximately 3:30–5:00.

Because normal cores add 4% and dual cores add 8%, intermediate thresholds may be crossed rather than reached exactly.
For example, 24% -> 28% can trigger Stage 2.
Do not invent fractional core values solely to force 25% or 55%.

PRE-BOSS CAP
- Ordinary core recovery cannot raise the station above 80%.
- Spawn the final arena boss at 80%.
- Prevent duplicate boss spawning.
- Keep the player able to complete the encounter if unused cores remain.

Do not require waiting until exactly five minutes to spawn the boss.

==================================================
16. FINAL ARENA BOSS: JUNKYARD COLOSSUS
==================================================

A large waste-armored robot with three sequential armor stages:
1. Green.
2. Blue.
3. Yellow.

Requirements:
- Threatening but readable silhouette.
- Telegraph trash-toss and other configured attacks.
- Clear active armor identity.
- A reasonable escape route during attacks.
- Safe transitions between armor stages.
- No unavoidable attacks during modal UI or noninteractive transitions.

Defeating the boss:
- Stops its attacks.
- Resolves existing enemy/projectile threats safely for reward collection.
- Drops the three-lock Super Core.
- Drops the campaign Navigation Chip as a separate visible reward.

Do not grant either drop through an invisible automatic inventory update.

==================================================
17. SUPER CORE, CHIP PICKUP, AND VICTORY ORDER
==================================================

The intended campaign sequence is:

Defeat Junkyard Colossus
-> Super Core and Navigation Chip appear
-> Nick manually unlocks the Super Core using Green, Blue, Yellow
-> Nick collects the Super Core
-> Station charge increases from 80% to 100%
-> Nick collects the Navigation Chip
-> Show the summary
-> Continue the established campaign narrative.

The Navigation Chip:
- Has a clear visual highlight.
- Is reachable.
- Uses the existing interaction/pickup conventions.
- Is awarded once.
- Remains available if Nick leaves and returns before collection.

Do not open the summary at 100% if the campaign chip still needs to be collected.

If the player reaches the chip before completing the Super Core, handle that order safely:
- Preserve the required remaining objective.
- Do not lose either pickup.
- Do not bypass station completion.

Victory requires both:
- Station fully charged through the Super Core.
- Required encounter reward collected.

In standalone practice:
- Use equivalent visible completion behavior.
- Do not write the practice reward into campaign inventory.

==================================================
18. PHYSICAL POWER CORE FROM BOSS 2
==================================================

Fix the second Phase 2 boss reward without changing its combat.

After defeat:
- Stop hostile energy spawning.
- Safely remove remaining damaging projectiles.
- Release Nick's fixed-position encounter lock.
- Restore exploration movement.
- Spawn a visible, reachable power_core pickup.
- Show a short pickup prompt.
- Require Nick to collect it.

Do not:
- Automatically grant power_core on boss death.
- Transition away before Nick can pick it up.
- Leave Nick unable to move.
- Award duplicates after revisiting or loading.

For both bosses, persist:
- Boss defeated.
- Reward available in the world.
- Reward collected.

Reconcile older saves safely:
- Preserve legitimately owned components.
- Do not force a replay merely because the old implementation awarded a component automatically.
- If a defeated boss has no owned reward, restore the appropriate uncollected pickup.

==================================================
19. CAMPAIGN STORY CONTINUITY
==================================================

The new arena replaces the first boss's gameplay, not its narrative purpose.

Preserve:
- The navigation-chip reward identity.
- The first boss's environmental archive.
- The future-Earth reveal.
- Silent Coast unlock.
- Boss 2's power-core reward and archive.
- Dawn Tower unlock after the second encounter.

The arena itself uses short coaching rather than heavy dialogue.
The campaign-only reveal can occur after the reward and summary in the established narrative flow.

Standalone practice should not replay or mutate campaign story flags.

==================================================
20. MINIMALIST HUD AND SUMMARY
==================================================

IN-MATCH HUD
Top-left:
- HP.
- Shield.
- Active-match elapsed time.

Top-right:
- Station charge.
- Three-color combo pips.
- Overdrive timer while active.

Bottom-center:
- Three spectrum slots.
- Keyboard shortcuts.
- Material icons.
- Current selection.

WORLD DISPLAY
- Central station floor ring.
- Readable station percentage.
- Brief reward/objective indicators.

Avoid long persistent text and overlapping callouts.

SUMMARY
Show:
- Completion time.
- First-try sorting accuracy.
- Rank S, A, or B.
- One targeted reminder for the most frequently mismatched item.
- Play Again.
- A suitable campaign Continue or standalone Main Menu option.

Define accuracy fairly:
- Record the first manual color decision for each enemy armor layer.
- Record the first manual cleaning decision for each relevant core shell.
- Count correct decisions against eligible decisions.
- Do not count every projectile in a held burst as a separate first attempt.
- Exclude automatic Overdrive matches from manual first-try accuracy.
- Do not inflate accuracy through repeated pickup callbacks.
- Handle zero eligible decisions without division errors.

Keep ranking thresholds configurable and document them.
Do not penalize pause, reduced-motion settings, or reopening the guide.

==================================================
21. ARCHITECTURE AND PERSISTENCE
==================================================

Follow existing architecture:
- Typed GDScript.
- Tuning and content in data/*.json.
- Pure rules independent of UI.
- Shared state changed through explicit APIs/signals.
- Delta-based movement and timers.
- Separate encounter/session state from persistent campaign state.

Configure through data:
- Sorting categories and item definitions.
- Enemy armor layers.
- Damage and movement.
- Core values.
- Stage thresholds.
- Dash settings.
- Overdrive settings.
- Bill callouts.
- Spawn pacing.
- Accuracy/rank thresholds.

Keep all drops, deaths, collection, and progression transitions idempotent.

Pause must stop:
- Enemies.
- Projectiles.
- Core interactions.
- Dash/Overdrive timing.
- Damage.
- Active-match timer.

Clean up scene connections, timers, enemies, effects, and audio on retry or exit.

Do not overwrite campaign progress from standalone practice.

==================================================
22. VERIFICATION
==================================================

Run the actual Godot parser/import checks and relevant regressions.
Find the real executable; do not assume it is on PATH.

Add meaningful checks for:

SORTING
- Correct spectrum damages the exposed layer.
- Wrong spectrum deals zero armor damage.
- Two-stage bottles require Green then Yellow.
- Multi-layer elites respect layer order.
- The guide appears and can be reopened.

CORES
- One enemy produces one valid drop.
- Wrong-color contact cannot collect a dirty core.
- Correct cleaning collects once.
- Tractor-beam collection cannot duplicate rewards.
- Standard/dual values update charge correctly.
- Crushers create one pre-cleaned drop.

PROGRESSION
- Threshold crossing works with 4%/8% increments.
- Ordinary recovery caps at 80%.
- Boss spawns once.
- Super Core requires manual 1 -> 2 -> 3.
- Super Core completes the remaining 20%.
- Summary waits for required physical reward collection.

HEALTH AND BONUSES
- Zero shield is survivable while health remains.
- Zero health causes defeat.
- Dash invulnerability and cooldown work.
- Overdrive restores original stats after expiration.
- Retry clears encounter-local state.

INTEGRATION
- Main Menu practice entry works.
- Practice does not modify campaign saves.
- Campaign boss 1 awards navigation_chip only after pickup.
- Boss 2 awards power_core only after pickup.
- Uncollected rewards survive save/load and revisits.
- The Earth reveal and chapter unlocks remain correct.
- Existing Phase 1, boss 2 combat, and Phase 3 functionality remain intact.

Perform graphical/manual verification when available:
- Pixel readability.
- Material silhouettes.
- Badge visibility.
- Bill following.
- Aiming and dash feel.
- Clear physical drops.
- Reachable pickups.
- HUD and guide layout.
- Fair pacing.

Report measured run duration and testing conditions.
Do not claim child-user testing, visual verification, or completed regressions that were not performed.

==================================================
23. DELIVERY
==================================================

Update:
- README.md.
- Relevant design/implementation documentation.
- Sorting content and data schemas.
- Test checklist.
- Current implementation status.

Document:
- STAR FALL's color convention.
- Energy-driven progression.
- Standalone/campaign separation.
- Physical reward persistence.
- Accuracy calculation.
- Known limitations.

Final report:
- What changed.
- Main files changed.
- How to launch standalone practice.
- How to reach the campaign encounter.
- Controls.
- Actual test commands and results.
- Manual verification performed.
- Remaining issues.

Complete the authorized implementation and fixes before returning the report.
Do not stop after merely proposing the changes.