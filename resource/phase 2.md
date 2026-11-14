text
You are the Senior Godot Gameplay Engineer responsible for implementing Phase 2 of STAR FALL.

Implement the features directly in the existing repository. Deliver playable, integrated gameplay rather than a plan, pseudocode, or isolated examples.

WORKSPACE
C:\Users\Win\NASA\NASA-space-mission-game

==================================================
1. PROJECT CONTEXT AND SCOPE
==================================================

Before editing:
- Read the applicable AGENTS.md files and docs/roles.md.
- Read README.md and docs/star_fall_contract.md if present.
- Inspect the actual Phase 1 implementation, current Git changes, campaign state, save system, data schemas, and tests.
- Preserve existing user changes.
- Reuse working systems and follow the existing Godot version and project conventions.
- Do not assume that previously proposed files or APIs already exist.
- This task assigns integration responsibility across the gameplay, state, UI, data, art, tests, and documentation required for Phase 2.

All code identifiers, comments, documentation, UI text, and dialogue must use English.

Established identities:
- Game: STAR FALL.
- Protagonist: Nick, a human astronaut.
- Companion robot: Bill.
- Spacecraft: VELA.

Preserve Phase 1:
Healthy present-day Earth -> mission briefing -> playable ship construction ->
preflight validation -> launch -> investigation -> spatial rift ->
future crash site -> salvage -> activate Bill -> first memory.

Implement only:
- Forgotten City.
- Its robot boss and navigation-chip reward.
- The future-Earth reveal.
- Silent Coast.
- Its robot boss and power-core reward.
- Progression and persistence connecting these encounters.

The two Phase 2 bosses are now hostile robots.
This replaces their previously proposed mutant forms and free-movement boss combat.

Do not change the Phase 3 boss into a robot or replace its planned mechanics.
Do not implement Dawn Tower, the final reconstruction system, or the ending in this phase.

==================================================
2. REQUIRED BOSS GAMEPLAY
==================================================

Create a fixed-position, mouse-directed shield-defense encounter.

During each boss fight:
- Nick remains at the center of the gameplay arena.
- A large, aggressive robot occupies the background behind Nick.
- Projectiles enter from multiple directions and travel toward Nick.
- The player rotates a directional shield by moving the mouse.
- The shield is always active.
- No mouse button must be held to block.
- Nick cannot walk, sprint, or dodge during the encounter.

There are two projectile categories:
1. Hostile energy.
2. Beneficial energy.

The player must:
- Block hostile energy with the shield.
- Allow beneficial energy to reach Nick without touching the shield.
- Accumulate charge from beneficial energy.
- Press Space when fully charged to damage the boss.
- Repeat until the boss is defeated.

Do not require ordinary shooting.
Do not introduce an additional shield-activation button.
Do not make successful blocking automatically damage the boss.

==================================================
3. ARENA AND VISUAL COMPOSITION
==================================================

Maintain STAR FALL's pixel-art 2.5D direction.

Composition:
- The robot is visually large and threatening in the rear layer.
- Nick stands in a clearly readable central foreground/midground position.
- The shield visibly orbits Nick.
- Projectiles remain visually distinct from the environment and robot.
- The robot's body is not a collision obstacle between every projectile and Nick.
- Directional emitters, surrounding machinery, or relays can explain attacks arriving from different directions.

The robot's appearance must communicate hostility through silhouette,
animation, lighting, and attack anticipation.

Use:
- Nearest texture filtering.
- Consistent pixel scale.
- Clear depth layering.
- Restrained effects.
- Readable contact shadows.
- A stable encounter camera.

Use original or appropriately licensed assets.
If final art is unavailable, create functional, coherent pixel placeholders.
Do not block implementation on missing external assets.

Display:
- Boss health clearly near the top of the encounter.
- Nick's health in a separate, unmistakable HUD element.
- The charge meter directly above Nick's head.
- A clear "SPACE — COUNTERATTACK" indicator when charge is full.

Do not confuse the charge meter with Nick's health.

==================================================
4. MOUSE-CONTROLLED SHIELD
==================================================

The shield direction must be determined by the vector:
Nick's screen/world position -> mouse position in the same coordinate space.

Requirements:
- Support continuous 360-degree directional control.
- The shield follows the cursor without requiring a click.
- Shield collision protects only its visible directional coverage.
- It must not behave as an invisible full-body bubble.
- Shield radius and angular coverage are configurable.
- Keep coverage narrower than a full circle so the player can deliberately admit beneficial energy.
- Preserve the last valid direction if the cursor is too close to Nick.
- Do not allow a zero-length direction vector to cause unstable rotation.

Correctly transform input through:
- Window scaling.
- Letterboxing, if applicable.
- SubViewportContainer scaling.
- Camera transforms.

Do not assume raw window mouse coordinates equal world coordinates.

Use the same authoritative direction for:
- Shield rendering.
- Collision.
- Optional aiming indicators.

Avoid visible and physical shield directions diverging.

==================================================
5. PROJECTILE INTERACTIONS
==================================================

HOSTILE ENERGY

If hostile energy contacts the shield:
- Block it.
- Remove it.
- Play readable impact feedback.
- Do not damage Nick.
- Do not generate charge.
- Do not automatically reflect damage toward the boss.

If hostile energy reaches Nick without being blocked:
- Apply its configured damage to Nick's health.
- Different attack types can deal different damage.
- Remove the projectile after a valid hit.
- Provide clear damage feedback.
- Do not deduct charge as an additional penalty.

BENEFICIAL ENERGY

If beneficial energy contacts the shield:
- Block and remove it.
- Grant no charge.
- Do not damage Nick.
- Do not apply an extra charge penalty.

If beneficial energy reaches Nick without touching the shield:
- Absorb it.
- Add its configured amount to the charge meter.
- Clamp charge to the maximum.
- Remove the projectile.
- Play distinct absorption feedback.
- Do not damage Nick.

Beneficial energy is not a health pickup by default.

READABILITY

Differentiate projectile categories using both:
- Color.
- Shape, outline, trail, or animation.

Do not rely only on red-versus-green color coding.
Hostile attack variants with different damage should also be distinguishable.

COLLISION RELIABILITY

- Handle fast-moving projectiles without tunneling.
- Evaluate shield interception and body impact in travel order.
- A projectile intercepted by the shield must not also hit Nick.
- A projectile passing through an unprotected direction must not be blocked later after it already reached Nick.
- Resolve each projectile once.
- Remove expired and offscreen projectiles.
- Clean all projectiles when the encounter ends or resets.

==================================================
6. CHARGE AND COUNTERATTACK
==================================================

Charge comes from beneficial-energy absorption.

Rules:
- The meter begins empty at encounter start.
- Correct hostile blocking grants no charge.
- Blocked beneficial energy grants no charge.
- Charge remains available while waiting.
- Full charge does not decay.
- Taking ordinary damage does not consume accumulated charge.
- The player may hold a full meter and choose when to attack.

COUNTERATTACK INPUT
- Press Space to counterattack.
- Use a just-pressed action, not continuous held-key firing.
- Pressing Space before full charge does not attack or consume charge.
- When full, one valid Space press triggers one counterattack.
- Consume the full charge once when the attack is accepted.
- Apply boss damage once.
- Prevent duplicate damage from repeated inputs or animation callbacks.

Show a strong but concise counterattack effect traveling toward or striking the robot.
The attack does not require mouse-aiming at the background robot.

Do not introduce unavoidable damage during a noninteractive attack animation.
If the sequence temporarily locks shield control, handle incoming projectiles fairly.

If a counterattack kills the boss:
- Stop encounter attacks immediately.
- Prevent Nick from dying to leftover projectiles during the victory transition.
- Process completion and rewards exactly once.

==================================================
7. HEALTH, DEFEAT, AND RETRY
==================================================

Nick has a health bar.
Damage depends on the hostile attack type.

When Nick's health reaches zero:
- End the encounter.
- Stop damage, spawning, charge gain, and counterattack input.
- Display defeat and a Retry option.

Retry restarts the current boss fight:
- Nick returns to full encounter health.
- Boss health resets.
- Charge resets to zero.
- Projectiles, timers, temporary effects, and difficulty escalation reset.
- The encounter begins from its initial difficulty.

Do not restart the entire campaign or require repeating completed exploration.
Preserve previously earned campaign progress and earlier boss rewards.

Ensure encounter retries cannot duplicate:
- Materials.
- Unique components.
- Completion flags.
- Memories.
- Scene connections or audio players.

==================================================
8. HEALTH-BASED DIFFICULTY ESCALATION
==================================================

Both of these increase as the boss loses health:
1. Projectile movement speed.
2. Firing frequency.

Escalation is based on the fraction of boss health lost.
Do not increase difficulty solely because time has elapsed.

Implement configurable health thresholds or a bounded progression curve.

The tuning must define:
- Initial firing interval.
- Minimum firing interval.
- Initial projectile speed.
- Maximum projectile speed.
- Attack-pattern changes by health band.
- Beneficial-energy availability.
- Telegraph and spawn-warning timing.
- Maximum active projectile count.

Preserve fairness:
- Give enough warning to rotate the shield.
- Avoid simultaneous unavoidable hostile impacts from opposite directions.
- Keep beneficial energy available so the fight remains winnable.
- Do not trap the player in a permanent defense-only loop.
- Do not spawn energy directly on Nick or inside the shield.
- Keep hostile and beneficial trajectories readable when they overlap.
- Bound all escalation values.

Use coherent patterns and controlled variation rather than unrestricted random spawning.
Support a reproducible seed for testing.

==================================================
9. BOSS 1: SCRAP KING
==================================================

Chapter: Forgotten City.
Intended boss ID: scrap_king.
Reward: navigation_chip.

Inspect existing identifiers before changing them.
If placeholder IDs already exist, reconcile references and save compatibility safely.

NEW FICTION
Scrap King is a corrupted industrial salvage robot.
It once sorted and recovered electronic waste.
Its damaged control system now treats Nick as an intruder.

VISUALS
- Heavy chassis.
- Scrap-metal armor.
- Damaged screens or a threatening sensor cluster.
- Magnetic equipment and surrounding emitters.
- Large background presence.

ENCOUNTER
Teach the mechanic gradually:
- Early attacks arrive from clearly separated directions.
- Beneficial energy is introduced visibly.
- Bill explains blocking hostile energy, admitting useful energy, and Space counterattacks.
- Later health bands increase both projectile speed and firing frequency.
- Introduce readable directional sequences instead of only increasing projectile count.

ENVIRONMENT
Retain a compact Forgotten City exploration section:
- Electronic waste.
- Ruined streets.
- An abandoned control center.
- A checkpoint before the encounter.
- A green memory before the boss.

VICTORY AND REVEAL
After boss defeat:
1. Record completion once.
2. Award navigation_chip once.
3. Restore the control-center archive.
4. Show the fictional history of growing electronic waste and ignored warnings.
5. Reveal the recognizable Earth image and matching records.
6. Nick realizes this is future Earth.
7. Change the mission to returning to the present with evidence.
8. Unlock Silent Coast.

No HUD, map label, or dialogue may reveal future Earth before this sequence.

==================================================
10. BOSS 2: TOXIC TIDE
==================================================

Chapter: Silent Coast.
Intended boss ID: toxic_tide.
Reward: power_core.

NEW FICTION
Toxic Tide is a corrupted marine-cleanup and energy-management robot
occupying the abandoned coastal facility.

VISUALS
- A distinct marine-industrial silhouette.
- Energy tanks, pumping equipment, or articulated mechanical arms.
- Corroded plating.
- A different appearance and attack rhythm from Scrap King.

ENCOUNTER
Use the same core shield/absorption/counterattack rules.
Create a distinct challenge through:
- Different directional sequences.
- Different attack timing.
- Clearly distinguishable hostile attacks with different damage.
- More deliberate placement of beneficial energy.
- Faster but still fair later health bands.

The fight must not feel like Scrap King with only a different sprite and more health.

ENVIRONMENT
Retain Silent Coast exploration:
- A ruined harbor and marine facility.
- Polluted water and debris.
- Walkable routes.
- Optional samples and research records.
- A checkpoint before the encounter.
- Memories of a healthy coast.

Any local environmental puzzle should support exploration or clearly affect the encounter.
Do not require the player to leave the center or walk during the fixed-position fight.

VICTORY
- Award power_core once.
- Restore the environmental archive.
- Preserve the environmental lesson through the facility's history and records.
- Unlock Dawn Tower.
- Allow return to the crash-site base.
- Show the two recovered components in the campaign's repair/progression interface.

Do not grant shield_emitter here.
Do not implement or replace the third boss.

==================================================
11. ARCHITECTURE, DATA, AND PERSISTENCE
==================================================

Separate responsibilities:
- Encounter controller: lifecycle and legal transitions.
- Pattern scheduler: spawn timing and health-based progression.
- Projectile logic: movement and collision resolution.
- Shield logic: cursor direction and coverage.
- State/model: health, charge, boss health, and outcome.
- HUD: state presentation and action requests.
- Campaign integration: rewards, chapters, memories, and saves.

Follow existing architecture rather than creating parallel state systems.

Use typed GDScript.
Keep pure calculations independent of UI.
Use delta for time-dependent movement and timers.

Store tuning and content in JSON:
- Boss health.
- Nick's encounter health.
- Projectile speed and damage.
- Spawn timing.
- Shield radius and coverage.
- Charge values and maximum.
- Counterattack damage.
- Health-based escalation.
- Pattern definitions.
- Dialogue.
- Reward IDs.

Save persistent campaign progress, not active projectile instances.
Prefer a pre-encounter checkpoint over serializing a partially completed fight.
Document the selected behavior.

Skipping post-boss scenes must produce the same rewards and progression as watching them.

Keep the initial VELA design and Phase 1 progression intact.
Avoid spending campaign construction resources merely to retry a fight.

==================================================
12. VERIFICATION
==================================================

Run the smallest relevant existing checks, then verify the new encounter behavior.

Meaningful automated checks should include:
- Mouse-to-shield direction with scaled viewports.
- Shield interception before body impact.
- Fast-projectile collision.
- Hostile shield hit: no health loss and no charge.
- Hostile body hit: configured health loss.
- Beneficial shield hit: no charge.
- Beneficial body hit: charge increases.
- Charge clamps at maximum.
- Full charge persists while waiting.
- Space below full charge does nothing.
- One valid Space press consumes charge and damages the boss once.
- Holding Space does not trigger repeated attacks.
- Lower boss health increases both firing frequency and projectile speed.
- Defeat and retry fully reset encounter-local state.
- Boss death stops further damage and grants one reward.
- Scene skipping and save/load preserve correct progression.
- Phase 1 still works.

Perform manual or graphical verification when available:
- Nick remains centered.
- Shield matches cursor direction.
- Background boss is readable.
- Projectile types are distinguishable.
- Charge appears above Nick.
- Telegraphs and later difficulty remain fair.
- UI works at supported window sizes.
- Pause and focus loss do not create invisible hits or stuck input.

Do not claim visual or audio verification from headless checks.
Do not modify or disable tests merely to hide regressions.

==================================================
13. DELIVERY AND STOPPING POINT
==================================================

Update:
- README.md.
- Relevant game-design documentation.
- docs/star_fall_contract.md, if present or appropriate to create.
- Test checklist.
- Current implementation status.

Document that this mechanic applies only to the two Phase 2 bosses.
Keep completed behavior separate from future plans.

Final report:
- What was implemented.
- Important files changed.
- Exact instructions to run and reach each encounter.
- Controls.
- Actual verification commands and results.
- Visual/manual checks performed.
- Remaining limitations.

Deliver a playable Phase 2 connecting both robot encounters to the existing campaign.
Stop after navigation_chip and power_core are earned and Dawn Tower is unlocked.