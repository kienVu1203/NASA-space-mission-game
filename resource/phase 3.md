You are the Senior Godot Gameplay Engineer and Educational Systems Designer implementing Phase 3 of STAR FALL.

Implement the phase directly in the existing repository. Deliver integrated, playable gameplay, not only a design document, pseudocode, or disconnected examples.

WORKSPACE
C:\Users\Win\NASA\NASA-space-mission-game

==================================================
1. PROJECT INSPECTION AND ESTABLISHED CONTEXT
==================================================

Before editing:
- Read applicable AGENTS.md files and docs/roles.md.
- Read README.md and docs/star_fall_contract.md if present.
- Inspect the actual implementation, current changes, data schemas, save system, and tests.
- Preserve user changes and working functionality.
- Reuse existing construction, campaign, UI, and persistence systems where appropriate.
- Do not assume that previously proposed files or APIs already exist.
- This task assigns integration responsibility across the gameplay, state, UI, data, assets, tests, and documentation necessary for Phase 3.

Established identities:
- Game title: STAR FALL.
- Protagonist: Nick, a human astronaut.
- Companion: Bill, a maintenance and memory-storage robot.
- Spacecraft: VELA.
- Presentation: pixel art with 2.5D depth on the existing 2D foundation.

All new or modified:
- Code identifiers.
- Comments.
- Documentation.
- UI.
- Dialogue.
- Vocabulary definitions.
- Error messages.

Must use English.

Preserve the previous campaign:
- Nick constructs VELA on healthy present-day Earth.
- A spatial rift causes the future crash.
- Nick meets Bill.
- Phase 2 contains two mouse-directed shield-defense robot bosses.
- The first boss rewards navigation_chip and reveals future Earth.
- The second boss rewards power_core.

Do not replace or redesign those Phase 2 encounters.

==================================================
2. PHASE 3 OBJECTIVE
==================================================

Implement:
1. Dawn Tower exploration and narrative.
2. The final shield-guarding boss.
3. A typing-based environmental-vocabulary battle.
4. The shield_emitter reward.
5. The complete spacecraft reconstruction workshop.
6. Return-mission simulation and design revision.

End at READY_FOR_FINAL_ASSEMBLY.

Do not implement the final escape cinematic or return-home ending.
Those remain Phase 4.

This prompt replaces the previously proposed movement/dodge combat for the third boss.

==================================================
3. CONFIRMED TYPING-BATTLE RULES
==================================================

The final boss appears large, fierce, and dangerous in the upper part of the screen.

The boss releases environmental vocabulary words that descend toward the bottom.

Nick stays near the bottom of the arena.

The player types the displayed words.

Rules:
- One correctly completed word fires one projectile toward the boss.
- That projectile damages the boss once.
- Individual letters update typing progress but do not fire projectiles.
- Completing a word automatically fires; Enter is not required.
- An incorrect letter resets the current target word's progress to its beginning.
- A wrong letter does not directly damage Nick.
- A word reaching the bottom before completion damages Nick.
- Missed words return to the encounter's pending queue.
- The player must eventually complete every required word in that encounter.
- Boss health reaches zero when the selected encounter vocabulary is completed and its final valid attack resolves.
- Nick has a health bar.
- Nick's defeat restarts this boss encounter, not the campaign.
- Difficulty increases from easy words to harder words within one fight.
- Do not present separate Beginner/Intermediate/Advanced mode selection.

Target a successful encounter duration of approximately 3–4 minutes.
Actual completion time may vary with typing ability, mistakes, and missed-word retries.

==================================================
4. IMPORTANT DISTINCTION: LIBRARY VERSUS ENCOUNTER
==================================================

Create a rich reusable vocabulary library.

Do not force the player to type the entire library in one fight.

Separate:
- Vocabulary library: the complete educational content collection.
- Encounter deck: a finite selection used in the current boss attempt.
- Pending queue: encounter words not yet completed.
- Active words: words currently descending.
- Completed words: successfully typed entries.
- Missed words: entries returned to the pending queue.

The boss must require completion of the selected encounter deck.

A large vocabulary library must not turn the intended 3–4 minute fight into a long vocabulary examination.

==================================================
5. ENVIRONMENTAL VOCABULARY LIBRARY
==================================================

Create at least 180 unique, reviewed English vocabulary entries.

Prioritize useful, understandable vocabulary over artificial variety.
Do not inflate the count with trivial plurals, duplicate spellings, or invented words.

Cover a broad range of themes:
- Nature and living things.
- Water and oceans.
- Trees and forests.
- Waste and litter.
- Reuse and recycling.
- Energy and resources.
- Pollution.
- Habitats and wildlife.
- Conservation and restoration.
- Environmental responsibility.

Use an easy-to-hard progression within the content.

Illustrative candidates:
- Early: air, sun, tree, soil, seed, water, clean.
- Developing: reuse, waste, litter, forest, recycle, protect.
- Later: habitat, compost, conserve, restore, wildlife.
- Advanced: pollution, ecosystem, biodiversity, conservation, sustainability.

These are examples, not the complete library.
Review every final entry for spelling, meaning, relevance, and suitability.

Each entry must include:
- Stable ID.
- Typing text.
- A short original English definition.
- A short original English example sentence.
- Environmental theme/category.
- Difficulty band.
- A brief relevance note when the environmental connection is not obvious.

Difficulty must consider:
- Word length.
- Spelling complexity.
- Familiarity.
- Conceptual difficulty.

Do not classify difficulty solely by character count.
Do not claim alignment with school grades or a formal reading standard without a valid basis.

For the initial implementation:
- Use lowercase alphabetic single words.
- Exclude spaces, hyphens, apostrophes, numbers, and accented characters from typing targets.
- Keep display capitalization independent from matching.
- Use a consistent English spelling convention.

Validate:
- Unique IDs.
- Unique typing text.
- Required fields.
- Valid difficulty bands and categories.
- No empty definitions or examples.
- No invalid target characters.

Educational content must remain fully English.
Do not add Vietnamese translations.

Use reliable references to review terminology where necessary.
Write concise original definitions rather than copying long dictionary passages.
Document sources actually consulted; do not invent attribution or claim educator review that did not happen.

==================================================
6. TEACHING THROUGH PLAY
==================================================

The player should encounter meaning, not only spelling.

Implement a compact learning panel:
- Shows the selected target word.
- Shows its short English definition.
- Highlights correct progress.
- Clearly indicates a reset after an incorrect letter.

After completing a word:
- Give concise success feedback.
- Record the entry in a vocabulary journal.
- Make its definition and example sentence available for later review.

The journal must be accessible outside the fight or through a paused learning view.
Reading the journal must not expose Nick to ongoing attacks.

Keep the active battle readable.
Do not display long paragraphs beside every falling word.
Do not require memorizing definitions to attack.

Bill provides a short first-time tutorial covering:
- Select a word by typing its first letter.
- Finish it to attack.
- Wrong letters restart that word.
- Words reaching the bottom cost health.
- Missed words will return.

==================================================
7. TARGETING AND INPUT
==================================================

When no target is selected:
- A matching first letter selects an active word.
- That first letter counts toward its progress.
- If more than one word matches, use a documented deterministic priority, such as the closest to the bottom.

Prefer spawning active words with distinct first letters.
Do not compromise vocabulary variety globally just to enforce this locally.

Once selected:
- Keep focus on that target until completion, a miss, or an explicitly supported cancellation.
- Additional letters apply only to that target.

On a wrong letter:
- Reset only the selected word's progress to zero.
- Keep it selected.
- The next valid input must begin from its first letter.
- Do not reset other words or the entire encounter.
- Do not immediately interpret the incorrect key as a new target selection.
- Give brief visual/audio feedback without excessive punishment.

Ignore non-letter gameplay input for typing progress:
- Shift.
- Ctrl.
- Alt.
- Function keys.
- Navigation keys.

Handle upper/lowercase consistently.
Do not let held-key repetition automatically complete repeated letters.
Avoid counting engine key-echo events as fresh typing input.

While the typing encounter is active:
- Letter keys are typing input.
- WASD must not move Nick.
- Phase 2 shield/counterattack bindings must not activate.
- Esc pauses.
- UI focus must not swallow valid typing or leak input into another scene.

Pause, focus loss, and modal views must stop:
- Word movement.
- Spawning.
- Damage.
- Encounter time.
- Pace estimation.

Do not count paused time as typing delay.

==================================================
8. WORD MOVEMENT AND DAMAGE
==================================================

Words descend through readable lanes or controlled positions.

Requirements:
- Prevent labels from overlapping illegibly.
- Keep all active words inside the playable region.
- Maintain a visible bottom danger line.
- Show the selected word and typed prefix clearly.
- Indicate urgency as a word approaches the bottom.
- Do not spawn words on the danger line.
- Do not spawn attacks during the tutorial or transition.

When a word reaches the bottom:
1. Register one miss.
2. Apply the configured health damage once.
3. Clear target selection if that word was selected.
4. Remove the falling instance.
5. Return the vocabulary entry to the pending queue.
6. Reintroduce it after a fair delay.

Do not immediately respawn the missed word at the bottom.
Do not permanently remove required vocabulary from the encounter.
Do not damage the boss for a missed word.
Do not create duplicate active copies of the same required entry.

Use time-based movement.
Keep damage and timing values in JSON.

Avoid simultaneous unavoidable failures caused by crowded spawns.

==================================================
9. ACCESSIBLE PACING AND PROGRESSION
==================================================

Start with:
- Short, familiar words.
- One active word at a time.
- A generous visible travel time.

Progress toward:
- Longer or less familiar vocabulary.
- Moderately increased movement/spawn pressure.
- Multiple active words only when the player can reasonably handle them.

Do not introduce a sudden difficulty cliff.

Use a finite staged deck that moves from basic to advanced vocabulary during the same fight.

For slower typists:
- Reduce concurrent pressure.
- Increase available travel time within documented limits.
- Avoid punishing repeated difficulty with further acceleration.

For faster typists:
- Reduce unnecessary empty gaps.
- Introduce the next appropriate word sooner.
- Keep the progression through vocabulary bands intact.

Measure typing pace conservatively.
Do not estimate the entire encounter from a single short word.
Use multiple observations and bounded adjustments.

Do not silently:
- Complete words for the player.
- Skip the required advanced section.
- Deal unearned boss damage.
- Remove missed words from the required deck.

The 3–4 minute duration is a pacing target, not a strict countdown.
A slower player may take longer and must still have a viable path to victory.

Estimate duration using:
- Required character count.
- Observed or configured typing pace.
- Spawn gaps.
- Mistake/reset overhead.
- Retry overhead.

Document assumptions.
Do not claim that the selected timing is suitable for children without playtesting evidence.

Keep tuning configurable so later testing with the intended audience can refine it.

==================================================
10. BOSS HEALTH AND ATTACK ACCOUNTING
==================================================

Use an explicit relationship between completed words and boss health.

A simple acceptable model:
- The encounter selects N required unique entries.
- Each successfully completed entry generates one attack.
- Each attack deals one configured damage unit.
- Initial boss health equals N multiplied by that damage unit.

Requirements:
- Missed/requeued words do not increase initial boss health.
- A required entry can only produce its completion reward once.
- Completing an already completed entry cannot deal extra damage.
- Boss death cannot happen before all required entries are completed.
- The final attack must still resolve if launched just before a transition.
- Do not strand the encounter with all words complete but nonzero boss health.

Track pending attack resolution clearly.
The visible health bar must agree with authoritative encounter state.

After the final required word:
- Stop spawning and descending-word damage.
- Resolve the final attack.
- Play boss defeat.
- Apply campaign completion once.

==================================================
11. DAWN TOWER AND BOSS PRESENTATION
==================================================

Retain the final region's established setting:
- A former forest.
- Industrial ruins.
- The abandoned Dawn Project facility.
- A route to the shield technology.
- A checkpoint before the boss.

Before the encounter:
- Show a memory of a healthy forest.
- Establish the value of the archive and the recovered shield system.
- Introduce the typing interface through Bill and facility equipment.

Boss:
- Retain the established Sky Remnant identity unless the existing implementation requires a documented compatibility adjustment.
- Do not automatically convert it into another Phase 2 robot.
- Place it prominently in the upper screen.
- Give it a fierce silhouette, dangerous animation, and clear attack feedback.
- Preserve a readable background behind falling text.

Explain the vocabulary interaction through the game's fictional technology:
Bill identifies environmental archive terms as valid control/targeting signatures used by the facility's defense interface.

This explanation supports gameplay.
Do not represent ordinary vocabulary as real scientific hacking commands.

==================================================
12. DEFEAT, RETRY, AND REWARDS
==================================================

Nick's health reaching zero:
- Stops the encounter.
- Stops word damage and input.
- Displays Retry.
- Does not reset the campaign.

Retry:
- Restores Nick's encounter health.
- Restores boss health.
- Resets typing progress, attack projectiles, timers, and encounter-local counters.
- Reuses the attempt's selected deck for consistent practice.
- Restarts at the easy stage.
- Preserves previous chapters and earned components.

Previously encountered vocabulary may remain in a journal,
but journal progress must not count as current boss damage.

After victory:
- Award shield_emitter exactly once.
- Record the boss completion.
- Restore the final Dawn Project archive.
- Unlock the complete VELA reconstruction workshop.

The three required recovered components remain:
- navigation_chip.
- power_core.
- shield_emitter.

Saving, loading, replaying dialogue, or repeated callbacks must not duplicate rewards.

==================================================
13. RECONSTRUCTION WORKSHOP
==================================================

Complete the Phase 3 workshop after the boss.

Reuse suitable systems from original ship construction.

Differentiate the contexts:
- Original Earth construction used credits and new components.
- Future reconstruction uses salvage and limited fabrication capacity.

Provide:
- Inventory.
- Mandatory recovered components.
- Propulsion options.
- Fuel load.
- Protection upgrades.
- Data storage.
- Mandatory and optional payload.
- Route selection.
- Simulation report.

Mandatory payload:
- Bill's memory core.
- Minimum evidence archive.

Optional payload:
- Environmental samples.
- Additional scientific records.

Provide at least two viable engineering configurations with real trade-offs.
Do not create one universally superior build.
Every valid original Phase 1 build must remain able to reach a successful return configuration.

Preserve resources while previewing.
Apply actual fabrication costs atomically once.
Prevent softlocks through fair common-material replenishment.

==================================================
14. RETURN-MISSION SIMULATION
==================================================

Implement pure simulation logic independent of UI.

Use explicit units:
- Mass: kg.
- Propellant: kg.
- Power: W.
- Energy: Wh.
- Time: s with explicit conversions.
- Data: MB.
- Communication throughput: a consistent documented unit.

Electrical consumption:
energy_used_Wh = power_W * duration_s / 3600.

Fuel contributes to wet mass.
Electrical energy and propellant are separate resources.

Check:
- Required components.
- Mandatory payload.
- Launch mass compatibility.
- Fuel/delta-v under a documented simplified model.
- Peak electrical demand.
- Total energy.
- Protection for the selected debris profile.
- Data capacity.
- Local prelaunch synchronization time.
- Required reserve margins.

Communications in the future use a surviving local relay or ground station.
Do not require radio contact with present-day Earth.

Provide at least two route profiles:
- A faster route with greater debris exposure.
- An extended route with different time/resource demands.

Return structured results:
- Overall validity.
- Per-stage resource consumption.
- Remaining reserves.
- Clear failure reasons.
- Actionable suggestions.

Simulation does not consume construction resources.
Identical inputs and seed must produce reproducible results.
Changing the design invalidates the previous passing report.

Keep the model clearly labeled as simplified educational gameplay.
Do not label invented component values or route requirements as NASA data.

==================================================
15. ARCHITECTURE AND DATA
==================================================

Use the existing campaign architecture.

Separate:
- Vocabulary catalog and validation.
- Encounter deck selection.
- Typing target/progress logic.
- Word spawning and movement.
- Health and damage accounting.
- Projectile presentation.
- Boss lifecycle.
- Learning journal.
- Campaign reward integration.
- Workshop rules.
- Mission simulation.

Use typed GDScript.
Keep gameplay/content tuning in JSON.
Core calculations must not access UI nodes.
Use signals and campaign APIs for state changes.

Do not overengineer.
Prefer small testable systems with explicit responsibilities.

Save persistent progression and journal entries.
Use a pre-boss checkpoint for encounter retries.
Avoid serializing active falling words and transient attack effects unless there is a justified existing system.

Inspect save compatibility before adding fields.
Document migrations if necessary.

==================================================
16. VERIFICATION
==================================================

Vocabulary checks:
- At least 180 unique valid entries.
- Complete definitions, examples, themes, and bands.
- No invalid typing characters.
- Encounter selection includes the required easy-to-hard progression.
- No duplicate required entries in one deck.

Typing checks:
- First letter selects a valid target.
- Correct letters advance only that target.
- Wrong letters reset that word to zero.
- Reset does not damage Nick directly.
- Case handling is consistent.
- Held keys do not autocomplete targets.
- Completed words fire exactly one attack.
- Individual letters do not fire.

Encounter checks:
- Missed words apply damage once and return to the queue.
- Completed words cannot be rewarded twice.
- Boss health matches required completion accounting.
- Final completion cannot leave an unwinnable state.
- Retry resets the fight while preserving campaign progress.
- Pause and focus loss stop the encounter safely.
- Slow and fast simulated typing profiles remain viable.

Campaign/workshop checks:
- shield_emitter granted once.
- Skip and save/load preserve progression.
- Missing components reject final assembly.
- Invalid mass, energy, or fuel configurations fail clearly.
- At least two complete return designs pass.
- Design changes invalidate stale reports.
- Phase 1 and Phase 2 regressions remain intact.

Manually verify when possible:
- Readability.
- Word overlap.
- Input responsiveness.
- Boss composition.
- Pixel presentation.
- UI scaling.
- Pacing.

Report measured encounter duration and the typing assumptions used.
Do not present automated pace simulation as child-user testing.
Do not claim visual/audio verification from headless execution.

==================================================
17. DELIVERY AND STOPPING POINT
==================================================

Update:
- README.md.
- Game-design documentation.
- Vocabulary content/schema documentation.
- docs/star_fall_contract.md if present or appropriate.
- Test checklist.
- Current implementation status.

Document:
- Vocabulary library size.
- Encounter selection rules.
- Wrong-key reset behavior.
- Miss/requeue behavior.
- Pacing assumptions.
- Workshop and simulation limitations.
- Actual content sources.

Final report:
- Implemented features.
- Main files changed.
- Exact run and encounter-access instructions.
- Controls.
- Actual test commands and results.
- Measured pacing observations.
- Unverified areas and remaining limitations.

Stop when:
- Dawn Tower and its typing boss are playable.
- The player receives shield_emitter.
- The full reconstruction workshop works.
- A valid return design reaches READY_FOR_FINAL_ASSEMBLY.

Do not implement the Phase 4 escape cinematic in this task.