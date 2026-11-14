Paste this prompt into VS Code. It updates the existing Phase 3 implementation, including replacing whole-word firing with *one bullet per correctly typed letter*.

```text
You are a Senior Godot Gameplay Engineer fixing and polishing the existing Phase 3 implementation of STAR FALL.

The game already runs. Inspect and modify the existing implementation rather than rebuilding the project.

WORKSPACE
C:\Users\Win\NASA\NASA-space-mission-game

==================================================
1. INITIAL INSPECTION AND SCOPE
==================================================

Before editing:
- Read applicable AGENTS.md files, docs/roles.md, README.md, and the implementation contract if present.
- Inspect the current Phase 3 boss, vocabulary system, projectiles, rewards, inventory, workshop, and save logic.
- Check the actual Godot version and current Git changes.
- Preserve user changes and working Phase 1/Phase 2 functionality.
- Reuse existing scenes, assets, state APIs, and patterns where practical.
- Do not assume previously proposed files or APIs actually exist.

This task assigns integration responsibility across the files necessary for the requested fixes.

All new or modified code, comments, UI, dialogue, and documentation must use English.

Established identities:
- Game: STAR FALL.
- Player: Nick.
- Companion: Bill.
- Spaceship: VELA.
- Presentation: pixel art with 2.5D depth.

IMPORTANT DESIGN CHANGES
The requirements below supersede earlier instructions that:
- Fired only one bullet after completing an entire word.
- Reused an identical word order on every retry.
- Automatically awarded the final shield without a physical pickup.

Implement the following changes together.

==================================================
2. PHYSICAL SHIELD DROP AFTER THE BUTTERFLY BOSS
==================================================

After Nick defeats the butterfly monster:
- Play the existing defeat sequence.
- Stop all remaining boss attacks and falling-word damage.
- Spawn a visible shield pickup in the world.
- Return control to Nick so he can approach and collect it.
- Allow the collected shield to be installed into VELA.

Use the existing shield component identity, such as shield_emitter, rather than creating a disconnected second reward.

The visible pickup should clearly resemble the recovered shield technology.

PICKUP PRESENTATION
- Place it at a reachable, walkable position.
- Do not spawn it inside the boss, scenery, or an inaccessible collision area.
- Add a restrained glow, bob, or highlight consistent with the pixel-art style.
- Show a short interaction prompt when Nick is nearby.
- Use the project's existing interaction control, normally E.
- Update the objective to clearly direct the player toward the reward.

RESTORE EXPLORATION
The boss encounter currently keeps Nick fixed in place.
After victory:
- Release encounter movement/input locks.
- Remove or disable encounter-only collision and UI as appropriate.
- Restore ordinary exploration controls.
- Keep Bill's established companion behavior working.

PERSISTENT REWARD STATES
Represent these states explicitly:
1. Boss undefeated.
2. Boss defeated, shield available in the world.
3. Shield collected.
4. Shield installed in VELA.

Do not collapse all four states into a single boss-completed flag.

Requirements:
- Award the shield only when Nick collects it.
- Grant it once.
- Remove the world pickup after collection.
- Preserve an uncollected drop across save/load and area revisits.
- Preserve the collected or installed state across save/load.
- Do not respawn a collected shield.
- Do not remove access to an uncollected shield when the player leaves the area.
- Do not require another boss victory just to recover an uncollected reward.
- Prevent final mission readiness if the required shield is missing or uninstalled.

Keep story progression and reward collection consistent without creating a softlock.

==================================================
3. RANDOMIZE WORD ORDER ON EVERY ENCOUNTER
==================================================

Each new boss attempt must use a changed word order.

This includes:
- Entering the fight for the first time.
- Retrying after defeat.
- Starting another valid attempt after leaving the encounter.

Preserve the established easy-to-hard progression.

Implementation:
- Shuffle entries within the appropriate progression bands or stages.
- Do not place advanced vocabulary at the beginning simply because the entire list was shuffled.
- Avoid returning the identical complete order on consecutive attempts when another valid ordering exists.
- Use a bounded strategy; do not repeatedly shuffle forever.
- Keep a reproducible seed or debug override for tests.

Preserve existing rules:
- A word that reaches the bottom damages Nick.
- That word returns to the pending queue.
- Required words are not permanently discarded.
- Completed entries are not duplicated or rewarded again.

Randomization must not:
- Change required reward conditions.
- Duplicate vocabulary IDs.
- Omit required words accidentally.
- Reset completed words in the middle of an active attempt.
- Cause illegible word overlap.

If the selected vocabulary set remains the same, its sequence must still vary between attempts.

==================================================
4. ADD FOUR ENVIRONMENTAL VOCABULARY ENTRIES
==================================================

Inspect the actual vocabulary library first.

Add approximately 3–4 entries; target four genuinely new entries.

Do not rebuild the entire library or inflate it with duplicate forms.

Choose useful, age-appropriate environment-related words that are absent from the existing collection.

Possible candidates, only if not already present:
- refill
- repair
- wetland
- upcycle

Choose other suitable entries if these already exist.

Each new entry must follow the existing schema and include:
- Stable unique ID.
- Correct English spelling.
- Short original English definition.
- Short original English example.
- Environmental category.
- Suitable difficulty band.

Keep typing targets compatible with the current input system.
Preserve the established spelling convention.

Ensure the new entries are eligible for actual encounter selection.
Adding unreachable entries to JSON is insufficient.

Validate the complete library for duplicate IDs and duplicate typing text.

==================================================
5. FIRE ONE BULLET PER CORRECT LETTER
==================================================

Replace the existing full-word firing behavior.

NEW BEHAVIOR
Every correct letter accepted toward the active word must immediately fire one projectile from Nick toward the boss.

Example:
For "water":
- W: fire one projectile.
- A: fire one projectile.
- T: fire one projectile.
- E: fire one projectile.
- R: fire one projectile and complete the word.

Do not fire an additional bonus projectile when the word completes.

Wrong letters:
- Reset the selected word's typing progress to its beginning.
- Do not generate a valid attack.
- Do not directly reduce Nick's health.
- Preserve the existing word-reset rule.

INPUT RELIABILITY
- A physical keypress must not generate duplicate projectiles through multiple callbacks.
- Ignore held-key echo as fresh typing input.
- Preserve case-insensitive matching.
- Ensure text input does not leak into movement controls.
- Preserve pause, focus-loss, and UI input locks.

PROJECTILE PRESENTATION
- Fire immediately when the correct letter is accepted.
- Make the projectile visible traveling toward the butterfly boss.
- Use a clear impact point.
- Clean up projectiles on defeat, retry, and scene transitions.
- Avoid excessive flashes, audio stacking, or particle clutter when typing quickly.

DAMAGE ACCOUNTING
Update boss health and attack accounting for per-letter firing.

Preserve the requirement that the selected vocabulary must be completed to finish the encounter.

Prevent repeated prefixes from becoming an exploit:
- Resetting a word after a mistake must not allow unlimited damage by repeatedly typing its first letters.
- Requeued words must not grant duplicate damage credit for already credited letter positions.

One acceptable approach:
- Associate damage credit with encounter-entry ID and letter index.
- Every correct accepted letter still produces a visible projectile.
- A previously credited position cannot grant additional progression damage.
- Initialize required boss damage from the selected encounter's valid letter positions.

Use an equivalent simple, reliable model if better suited to the existing implementation.

Ensure:
- Boss health cannot reach zero before the required vocabulary is completed.
- The final required attack can resolve.
- The encounter cannot remain stuck after all required words are completed.
- Rapid typing and projectiles in flight do not produce duplicate victory callbacks.
- Successful completion stops further falling-word damage.

Document the final damage model.

==================================================
6. DISPLAY WORD MEANING ON THE LEFT
==================================================

During the boss fight, display the active target word's meaning in a dedicated panel on the left side.

The panel should contain:
- The selected word.
- Its short English definition.
- Optionally, a concise example if it fits without clutter.

Requirements:
- Update immediately when the selected target changes.
- Keep the definition visible while typing and after a typing reset.
- Show a simple neutral prompt when no word is selected.
- Keep falling words, Nick, and the boss unobstructed.
- Reserve layout space so words do not travel behind the learning panel.
- Use clear text hierarchy and readable wrapping.
- Support the minimum and resized window layouts.
- Keep all educational text in English.

Use the vocabulary entry's actual definition.
Do not display an unrelated definition after a target completes or is missed.

Do not pause the fight automatically every time a definition changes.

==================================================
7. REDESIGN THE VELA RECONSTRUCTION WORKSHOP
==================================================

Make this section visually communicate ship repair and component installation.

The player should see:
- A prominent representation of VELA.
- Visible attachment points or repair slots.
- Visual representations of the actual collected components.
- Clear missing, available, and installed states.

Use the current ship art and pixel-art style where practical.

The workshop must show real campaign state.
Do not display collected-item visuals for items the player does not possess.

VISUAL REPAIR INTERACTION
Provide a clear way to:
1. Select a recovered component.
2. Preview its installation location on VELA.
3. Confirm installation.
4. Show the corresponding repaired or attached ship part.

At minimum, represent:
- Navigation chip.
- Power core.
- Shield emitter.

Installation may use simple select-and-confirm controls.
Do not introduce complex drag-and-drop solely for presentation.

The shield collected after the butterfly boss must appear here as an available component and then visibly become installed.

Use a concise installation animation, highlight, or before/after change.
The scene should feel like repairing the ship rather than only editing a spreadsheet.

PRESERVE FUNCTIONAL SYSTEMS
Keep the existing:
- Inventory and fabrication transactions.
- Component requirements.
- Payload choices.
- Propulsion and fuel configuration.
- Route selection.
- Mission simulation.
- Validation and readiness conditions.

Do not sacrifice engineering functionality to make the screen decorative.

==================================================
8. REDUCE WORKSHOP TEXT CLUTTER
==================================================

Remove the gray subtitle/description directly underneath:
"Vela Reconstruction Workshop"

Identify the actual label or generated UI element and remove that specific secondary text.

Keep a clean title and a visually organized repair area.

Reduce excessive always-visible text by using:
- Component icons.
- Short names.
- Compact stat labels.
- Selection-based detail panels.
- Tooltips or expandable explanations where appropriate.
- Status indicators paired with icons or text.

Do not rely solely on color for component status.

Keep essential information accessible:
- What is missing.
- What can be installed.
- What is installed.
- What resources are required.
- Why a configuration fails.
- What the player must do next.

Avoid long paragraphs and repeated instructions in the main workshop view.
Keep validation failures concise and actionable.

Ensure the new layout does not overlap or clip at supported window sizes.

==================================================
9. STATE, SAVE, AND INTEGRATION
==================================================

Follow existing project architecture:
- Persistent state belongs to the campaign model.
- UI displays state and requests validated changes.
- Pure rules remain independent of UI nodes.
- Gameplay tuning and vocabulary remain data-driven.
- Use typed GDScript and delta-based timing.

Inspect save compatibility before adding:
- Shield drop state.
- Shield collection state.
- Installation state.
- Encounter-order history or attempt counters.
- Per-letter encounter accounting.

Migrate old saves where necessary.

For an older save where the shield was already legitimately awarded:
- Preserve ownership.
- Do not force the player to defeat the boss again.
- Map it to an appropriate available/installed state.

Do not invent completed progression for saves that never earned the shield.

Do not modify the Phase 2 shield-defense mechanics in this task.

==================================================
10. VERIFICATION
==================================================

Run relevant existing checks and add focused regressions.

Verify:
1. Boss defeat creates one reachable shield pickup.
2. Nick regains exploration control after victory.
3. Collecting the shield grants it once.
4. Save/load preserves an uncollected drop.
5. Save/load preserves collected and installed states.
6. Leaving and returning does not lose or duplicate the shield.
7. Workshop installation updates the ship visually and persistently.
8. New attempts change vocabulary order while retaining easy-to-hard progression.
9. New vocabulary entries are valid and selectable.
10. Each correct accepted letter fires one projectile.
11. Word completion does not add an extra projectile.
12. Wrong letters reset the current word without firing.
13. Held-key echo does not create repeated shots.
14. Mistakes and requeues cannot farm boss damage.
15. Final completion resolves correctly with projectiles still in flight.
16. The left panel always matches the selected word.
17. The gray workshop subtitle is removed.
18. Workshop controls, simulation, and validation still function.
19. Phase 1 and Phase 2 regressions remain intact.

Perform graphical/manual checks when available for:
- Pickup visibility and reachability.
- Per-letter firing feedback.
- Definition-panel readability.
- Workshop repair presentation.
- Window resizing and UI overlap.

Do not claim visual verification from headless execution.

==================================================
11. DELIVERY
==================================================

Update relevant documentation and the current implementation status.

Final report:
- Root causes found.
- Changes implemented.
- Main files changed.
- Four vocabulary entries added.
- Per-letter damage-accounting behavior.
- Save compatibility handling.
- Exact run and reproduction instructions.
- Actual test commands and results.
- Visual checks performed.
- Remaining limitations.