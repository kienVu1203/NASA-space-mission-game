# Test checklist

Ticked items are covered by an automated headless suite; the rest need a person
at the keyboard. Commands are in `docs/star_fall_contract.md` §9.

Nine suites cover the build: `test_parse`, `test_logic`, `test_flow`,
`test_encounter`, `test_phase3`, `test_phase4`, `test_flight`,
`test_debug_jump` and `test_eco_arena`.

## Automated (run these first)

- [x] Every script parses and compiles — `tests/star_fall/test_parse.gd`
- [x] Preflight rejects the empty design with actionable messages — `test_logic.gd`
- [x] Preflight rejects a low-gain sensor on science quality — `test_logic.gd`
- [x] Preflight rejects Deep Fields on a solar array on power — `test_logic.gd`
- [x] Preflight rejects an over-fueled light-thruster build on lift — `test_logic.gd`
- [x] Preflight rejects a dry build on fuel while still passing mass — `test_logic.gd`
- [x] Two configurations pass preflight and differ in cost, mass and science — `test_logic.gd`
- [x] Previewing a design spends nothing and confirms nothing — `test_logic.gd`
- [x] An invalid design cannot be confirmed, and commits no manifest — `test_logic.gd`
- [x] A refused re-confirm leaves the stored manifest intact — `test_logic.gd`
- [x] Inventory never goes negative and never exceeds its limit — `test_logic.gd`
- [x] Salvage is refused when duplicated; unknown salvage is a no-op — `test_logic.gd`
- [x] The junction cannot be repaired without materials, and only once — `test_logic.gd`
- [x] Save/load round-trips stage, design, inventory, flags, memories — `test_logic.gd`
- [x] Loading twice replaces rather than merges state — `test_logic.gd`
- [x] Corrupt, empty and future-version saves are reported, not accepted — `test_logic.gd`
- [x] A corrupt save never wipes the live campaign — `test_logic.gd`
- [x] Save sanitiser drops negative quantities and unknown components — `test_logic.gd`
- [x] Viewing a memory sets both the list entry and the quest flag — `test_logic.gd`
- [x] Dialogue and menu models behave (typewriter, skip, disabled items) — `test_logic.gd`
- [x] Authored sites contain the required interactables — `test_logic.gd`
- [x] No save is written just by opening the main menu — `test_flow.gd`
- [x] New Game opens the briefing and locks movement — `test_flow.gd`
- [x] The briefing unlocks the console and advances the stage — `test_flow.gd`
- [x] A failed preflight on the console blocks confirmation — `test_flow.gd`
- [x] Revising the design and re-running preflight passes — `test_flow.gd`
- [x] Confirmation moves to the launch sequence — `test_flow.gd`
- [x] The launch cannot be skipped and still sets launch, rift and crash flags — `test_flow.gd`
- [x] The launch sequence saves the crash-site checkpoint — `test_flow.gd`
- [x] The launch design yields surviving science data — `test_flow.gd`
- [x] Crash-site labels contain no spoilers — `test_flow.gd`
- [x] Wreck inspection grants design-dependent salvage — `test_flow.gd`
- [x] Salvage collection removes the prop and records the id — `test_flow.gd`
- [x] Bill stays dormant until the junction is repaired — `test_flow.gd`
- [x] Activating Bill plays the memory and records it — `test_flow.gd`
- [x] The checkpoint stage, save and Continue all work — `test_flow.gd`
- [x] Esc opens the pause overlay and locks movement — `test_flow.gd`
- [x] Resume restores movement — `test_flow.gd`
- [x] Settings open inside the pause menu; Esc returns to the menu, Esc again resumes — `test_flow.gd`
- [x] Losing window focus zeroes velocity and releases movement — `test_flow.gd`

### Phase 2: encounter mechanics — `test_encounter.gd`

- [x] The shield aims 360 degrees from the cursor, with no click required
- [x] A cursor inside the dead zone keeps the last valid direction
- [x] A zero-length direction never reaches the rotation maths
- [x] Shield coverage is narrower than a full circle and matches its stated angle
- [x] Every drawn arc point falls inside the collision coverage
- [x] Window scaling is removed from the cursor before it aims the shield
- [x] Pillarbox and letterbox bars are removed from the cursor
- [x] A projectile into the shield is blocked and removed
- [x] A projectile through an unprotected direction hits Nick
- [x] A fast projectile is intercepted by a swept test, not tunnelled
- [x] A shield interception never also registers as a body hit
- [x] A projectile past the shield is never blocked afterwards
- [x] Expired and offscreen projectiles are removed
- [x] A hostile shield hit costs no health and grants no charge
- [x] A hostile body hit applies that attack type's configured damage
- [x] Taking damage never consumes accumulated charge
- [x] A beneficial shield hit grants no charge and costs no health
- [x] A beneficial body hit adds charge and is never a health pickup
- [x] Charge clamps at its maximum
- [x] Full charge does not decay while the player waits
- [x] Space below full charge neither attacks nor spends charge
- [x] One full charge yields exactly one counterattack
- [x] The counterattack damages the boss exactly once
- [x] Holding Space, or a second press in the lock, never repeats the attack
- [x] No projectile spawns and no damage lands during the counterattack lock
- [x] Lower boss health raises firing frequency and projectile speed, both bounded
- [x] Escalation depends on health, never on elapsed time
- [x] Every health band escalates monotonically
- [x] The two bosses differ in health, damage, patterns and silhouette
- [x] Every spawn is preceded by its own telegraph
- [x] The active projectile count stays bounded
- [x] Beneficial energy is always available and never spawns on Nick
- [x] The same seed reproduces the same schedule
- [x] Defeat stops damage, charge and counterattacks
- [x] Retry restores health, boss health, charge, projectiles, telegraphs and escalation
- [x] Nothing spawns, lands or counterattacks while a briefing freezes the arena
- [x] The encounter model holds no campaign or inventory reference
- [x] Victory is reported once, stops combat and clears projectiles
- [x] No damage lands after victory
- [x] A component is awarded once and a replay grants no second copy
- [x] The reveal, the mission change and the Dawn Tower unlock each apply once
- [x] Phase 2 never grants the shield emitter
- [x] Phase 2 progression survives save/load without duplicating
- [x] A version-1 (Phase 1) save still loads and keeps its mission
- [x] A save missing the mission field recovers it from its flags
- [x] Phase 1 stages, salvage and the junction still work

### Phase 2: campaign flow — `test_flow.gd`

- [x] The Phase 1 summary continues into the Forgotten City
- [x] The city loads with its checkpoint, shrine, door and salvage
- [x] The control-center door refuses entry before the checkpoint
- [x] The checkpoint marks the pre-boss stage and saves
- [x] City salvage is collectable and leaves the world
- [x] The city memory plays and returns to exploration
- [x] The control-center door opens the Eco Arena in campaign mode, with a short briefing over a frozen arena
- [x] The sorting guide appears before the match; Start begins it
- [x] No reward exists before the Colossus is defeated
- [x] The Colossus defeat records `scrap_king_defeated` once and grants no chip
- [x] Save/continue before the pickup reopens the arena with the boss down, the station at 80% and both drops waiting
- [x] A wrong color cannot open the Super Core; 1 -> 2 -> 3 completes the station
- [x] The summary waits for the chip; picking up the chip awards `navigation_chip` once
- [x] Continue plays the victory scene and the archive; a replayed pickup awards no second chip
- [x] The control-center archive opens with its records
- [x] No future-Earth spoiler appears before the archive
- [x] Closing the archive applies the reveal, unlocks the coast and changes the mission
- [x] The reveal is idempotent
- [x] The coast loads with its checkpoint, projector, samples and records
- [x] Samples and records are recorded
- [x] The facility refuses entry before the checkpoint
- [x] The coastal memory plays and returns to exploration
- [x] The Toxic Tide can defeat Nick, and defeat leaves the campaign untouched
- [x] Retry fully resets the fight while keeping campaign progress
- [x] The Toxic Tide can be defeated; victory grants no power core by itself
- [x] Nick walks again on the quay; the power core drop is in the world and the facility points back at it
- [x] Save/continue keeps the uncollected drop and never replays the fight
- [x] E at the drop awards `power_core` once and removes the prop
- [x] The environmental archive applies the lesson and unlocks Dawn Tower
- [x] The base return shows both recovered components
- [x] The Phase 2 summary continues into the Dawn Tower and keeps the save
- [x] Continue restores the Phase 2 stage, components, archives and mission

## Eco Arena automated checks — `test_eco_arena.gd`

### Data and sorting

- [x] Three categories only; every item has a category and a 16x16 badge
- [x] Pizza box Green, office paper Blue, crushed can Yellow, residue bottle Green then Yellow
- [x] No hazardous, battery or glass category; no "check your local sorting rules" line; presented as STAR FALL's convention
- [x] Bill's callouts are 4-8 words; each guide card has 2-3 examples
- [x] Matching spectrum: 2.5x reference damage and knockback; wrong spectrum: zero damage, deflection, one callout
- [x] Two-stage bottle needs Green then Yellow; overflow never reaches the hidden layer
- [x] The shot hitbox covers the drawn body: a bolt through the top of a bottle hits, one just above misses

### Cores and crushers

- [x] One enemy, one drop (a repeated death callback adds none); cores are never auto-collected
- [x] Wrong-color contact sparks and nudges, costs no health, never collects; lingering does not spam
- [x] Correct cleaning collects once (+4); a repeated collect callback adds nothing
- [x] The beam picks the nearest dirty core in range, collects without duplicates, ignores cores out of range, stops on release
- [x] Dual cores open one step at a time and add 8 as one pickup
- [x] A matching crusher recycles a charging enemy into one pre-cleaned core that waits for Nick
- [x] A mismatched crusher only bounces; an elite loses only its exposed layer

### Progression, boss, Super Core

- [x] 24 -> 28 crosses into stage 2; stage 2 removes badge borders; ordinary recovery caps at 80
- [x] The boss spawns once; waves stop; no damage during its entrance; Green -> Blue -> Yellow cannot be skipped
- [x] Boss defeat clears every threat and drops the Super Core and the chip
- [x] The Super Core needs a manual 1 -> 2 -> 3 even in Overdrive and adds the last 20
- [x] Victory needs both objectives in either order and resolves once; the reward resume state is correct

### Health and bonuses

- [x] Shield first, then health; zero shield survivable; zero health is defeat and stops the clock
- [x] Dash invulnerability, 1.5 s cooldown, no passing the boundary or the station
- [x] Overdrive: +30% speed, +25% regen, refresh without stacking, exact restore, exposed-layer-only rainbow, excluded from accuracy
- [x] Retry clears every encounter-local value

### Accuracy, Bill, screen, practice

- [x] Zero decisions is safe; a held burst counts once; later hits never overwrite the first try; shells count separately
- [x] The reminder targets the most-mismatched item; rank thresholds come from data
- [x] Bill trails without overlapping, recovers when separated, never absorbs a shot
- [x] The main menu entry opens practice; the guide stops the clock and can be reopened from pause; pause stops the arena
- [x] Defeat offers a fast retry without the guide
- [x] Practice reaches the same summary, writes nothing to the campaign and leaves the save file byte-for-byte unchanged
- [x] A practice restart after the boss replays the whole arena
- [x] Four scripted bot runs finish the arena (measured 3:33-3:34 of match time; a bot, not players)

## Eco Arena manual checks (need a display and a person)

- [ ] Pixel readability of every enemy silhouette and badge at 1280x720 and at other window sizes
- [ ] Contamination (pizza box grease, juice in the bottle, leaves in the box) is obvious at a glance
- [ ] Bill's following looks natural through movement and dashes; the beam line hits the selected core
- [ ] Aiming, firing rate and dash feel; the DASH meter reads clearly
- [ ] Drops are visible and reachable everywhere, including near crushers and walls
- [ ] HUD and guide layout do not overlap at supported window sizes
- [ ] The three material hit sounds are distinct and not annoying when repeated
- [ ] A real run lands near 5-7 minutes and feels fair (not yet timed with players)
- [ ] The power core on the Silent Coast quay is easy to see and pick up

## Phase 4 automated checks — `test_phase4.gd` (and `test_flow.gd`)

### Finale data and prerequisites

- [x] `finale.json` loads; six cinematic scenes, a final message, score weights and credits; the removed QA block is gone
- [x] Every scene has ordered, non-empty subtitles that end inside its duration
- [x] A complete run meets all six prerequisites
- [x] A missing boss, a missing component, a stale design or a running sequence each blocks the gate

### Escape cinematic

- [x] Space does not pause; Esc asks for the shared pause menu and never skips
- [x] A paused scene does not advance and emits no outcome; focus loss pauses
- [x] Skipping emits the outcome exactly once, however many times it is pressed
- [x] Watching the whole sequence finishes it at the final message with skipped = false
- [x] Watching and skipping apply the same flags, stage and checkpoint (`test_flow.gd`)

### Canonical VELA and the finale presentation — `test_flight.gd`

- [x] Engines are on only in `ignition`, `ascending`, `portal_entry` and `descending`; off in `maintenance`, `parked` and `landed`
- [x] Every finale state points the nose straight up; only the workshop view is horizontal
- [x] Scale is uniform at 1x and 2x; a parked ship's legs reach the ground
- [x] The workshop sockets keep their Phase 3 positions (taken from the renderer's module table)
- [x] The flight lanes' hull length and shield match the drawn ship
- [x] The departure ship is parked with engines off; the launch opens parked, ignites on the pad, climbs upright
- [x] Home opens on the powered descent and is landed, engines off, after touchdown; the face close-up is gone
- [x] Grit and near misses report shield contacts on the shield boundary; contacts never count as strikes
- [x] A near miss grazes once and is pushed away from the hull; grit off the ship's line makes no contact
- [x] The portal captures first and reports the crossing only after the hull is through (about 2 s later); steering cannot pull a captured ship off the axis
- [x] The portal scene never advances before the crossing
- [x] Every ascent contact happens with the shield up, inside the scene; contacts and shake are cleared at the next beat
- [x] Pause freezes the ascent; skip from the ascent is safe and final

### Mission report and score

- [x] The report carries the objective, memories, components, both designs, mass, route, reserves and decisions
- [x] The score counts the objective, three components and every archived memory
- [x] The score equals the sum of its published terms
- [x] The report is deterministic for the same state
- [x] Skipping the cinematic never changes the score
- [x] Stockpiling salvage cannot raise the score
- [x] The report cites the simulation's debris impact count

### Persistence

- [x] The snapshot is taken once; a second call is refused
- [x] The return objective completes once
- [x] A version 5 save round-trips stage, chapter, snapshot, objective, skip record and report record
- [x] A version 4 save (no finale record) still loads at the ready point
- [x] Loading twice never duplicates components
- [x] A version 3 save still loads, at the ready point, with its components
- [x] A finale stage without a snapshot is corrected back to the ready point and reported
- [x] The Phase 3 ready-flag rule still applies

### Milestone driver (tests only; the `I + O + P` skip is removed)

- [x] The planner has no key poll and no build/launch-flag switch; the controller no longer polls I + O + P
- [x] The next milestone follows the campaign stage, not the open screen
- [x] The driver leaves a live screen, a valid checkpoint and a resumable save at every step
- [x] The walked run has a valid day-one design, all three components, a fabrication and a snapshot
- [x] The walked run completes the return and produces a report with a positive score

### End-to-end (headless)

- [x] The real main scene plays from the title through final assembly, the escape, the report and the credits
- [x] A double confirmation starts exactly one installation
- [x] Skipping the install animation starts the cinematic exactly once
- [x] Continue after the ending shows the credits; New Game clears the finale
- [x] No dead screen or stuck input after any transition

## Manual (a person must play it)

- [ ] The window opens at 1280x720 and the pixel art is crisp, not blurry
- [ ] Resizing the window keeps the UI readable and the scale consistent
- [ ] Walking with WASD/arrows feels correct; diagonals are not faster
- [ ] Shift actually runs, and collision against props is reliable
- [ ] Nick cannot walk through the VELA frame, trees, or the wreck
- [ ] Nick's head overlaps a tree trunk when he stands behind it
- [ ] The interaction prompt appears only when near an interactable
- [ ] Esc pauses the world; the pause menu fully responds
- [ ] Dialogue locks movement, and Esc closes it without losing flags
- [ ] Alt-tabbing away at speed does not leave Nick sliding
- [ ] Ambient audio differs audibly between the spaceport and the crash site
- [ ] The launch sequence plays: countdown, ascent, tuning, rift, crash
- [ ] The signal-tuning step is understandable and completable
- [ ] The crash site reads as dark and polluted; Earth reads as bright and alive
- [ ] Nothing on the crash site names Earth or shows a future date
- [ ] The ship drawing visibly changes when components are swapped
- [ ] The construction screen text never overlaps at 1280x720
- [ ] Settings: each volume slider is audible on its bus, text speed changes dialogue pacing, values survive a restart
- [ ] Quit from the main menu exits cleanly

### Phase 2 manual checks

- [ ] The mouse rotates the shield smoothly through the full 360 degrees, with no click
- [ ] The drawn shield arc and the blocked projectiles agree at every angle
- [ ] A projectile visibly stops at the shield, never in front of or behind it
- [ ] Hostile and beneficial projectiles are distinguishable by shape, not only colour
- [ ] The two hostile damage variants are distinguishable from each other
- [ ] Nick stays centred; the robot reads as a large background presence
- [ ] The charge meter above Nick is never mistaken for his health bar
- [ ] SPACE - COUNTERATTACK appears exactly when the meter fills
- [ ] The counterattack visibly travels to the robot and lands once
- [ ] The fight speeds up as the boss loses health, and stays survivable
- [ ] Telegraphs give enough warning to rotate the shield at the hardest band
- [ ] Losing (or quitting to the pause menu) and retrying does not cost campaign progress
- [ ] The Forgotten City reads as a sorted, abandoned street, not a flat ash plain
- [ ] The Silent Coast reads as a harbour: quay, tide stain, facility silhouette
- [ ] The control-center archive's reveal lands as a realisation, not a HUD label
- [ ] Nothing before the archive names Earth or shows a date
- [ ] The base return shows both components fitted and the emitter still missing
- [ ] Alt-tabbing mid-fight pauses rather than letting attacks land

### Phase 3 automated checks

- [x] The vocabulary library has at least 180 unique, valid entries with definitions, examples, bands and categories — `test_phase3.gd`
- [x] The validator rejects duplicate ids or text, empty fields, unknown bands or categories, and invalid characters — `test_phase3.gd`
- [x] A deck is finite, repeats no entry, and runs from foundation to advanced — `test_phase3.gd`
- [x] A first letter selects the lowest matching word; correct letters advance only it — `test_phase3.gd`
- [x] A wrong letter resets only that word, keeps it selected, and does not hurt Nick — `test_phase3.gd`
- [x] Upper and lower case match; digits, spaces, accents, chords, function keys and held-key echo do not type — `test_phase3.gd`, `test_flow.gd`
- [x] Every correct letter fires exactly one shot; completion adds none; a wrong letter fires none and resets the word — `test_phase3.gd`, `test_flow.gd`
- [x] Retyped prefixes and requeued words never earn duplicate damage (per-position credit) — `test_phase3.gd`
- [x] Shots still in flight resolve into exactly one victory; victory stops word damage — `test_phase3.gd`
- [x] Every attempt changes the word order, keeps the same words and the easy-to-hard stages, and persists its history — `test_phase3.gd`, `test_flow.gd`
- [x] The four new vocabulary entries are valid and reachable by deck selection — `test_phase3.gd`
- [x] A missed word damages once, clears the target, requeues after a delay, and never doubles up — `test_phase3.gd`
- [x] A completed entry cannot pay out twice; boss health equals total letters x damage per letter — `test_phase3.gd`
- [x] The boss cannot die before the last entry, and the final attack still lands — `test_phase3.gd`
- [x] Active words never share a lane — `test_phase3.gd`
- [x] Retry restores both health bars, keeps the words in a new order, clears shots, restarts at the easy stage, keeps the journal — `test_phase3.gd`, `test_flow.gd`
- [x] Pause, the journal, a dialogue and focus loss freeze words, time and damage — `test_flow.gd`
- [x] Fast, target and slow scripted typists can all win — `test_phase3.gd`
- [x] Victory drops one shield emitter on open ground and restores exploration; the pickup grants it once and is removed — `test_flow.gd`
- [x] The four shield states (undefeated, available, collected, installed) survive save/load, re-entry and migration from save version 3 — `test_phase3.gd`, `test_flow.gd`
- [x] The workshop installs each recovered part once; uninstalled parts fail the simulation and block fabrication — `test_phase3.gd`, `test_flow.gd`
- [x] The simulation uses `Wh = W x s / 3600`, is deterministic for a seed, and reports per-stage use and reserves — `test_phase3.gd`
- [x] Missing components, mass, delta-v, energy, peak power, protection, data and relay-sync failures are reported with suggestions — `test_phase3.gd`
- [x] Four distinct designs pass; trade-offs prevent a single best build — `test_phase3.gd`
- [x] Both day-one engines have a passing, always-affordable return design — `test_phase3.gd`
- [x] Simulating is free; fabrication is atomic, needs a current passing report, and happens once — `test_phase3.gd`, `test_flow.gd`
- [x] A design change invalidates the previous report — `test_phase3.gd`, `test_flow.gd`
- [x] Scavenging tops materials up to the floor and never above it — `test_phase3.gd`
- [x] Version 1 to 3 saves still load (migrated); version 4 keeps the journal, workshop record, installed parts and attempt history — `test_phase3.gd`
- [x] The real main scene plays from the title to READY_FOR_FINAL_ASSEMBLY, and Continue resumes there — `test_flow.gd`
- [x] Every Ctrl+Shift+Alt debug jump lands on its screen with a consistent campaign; V, K, M and H work — `test_debug_jump.gd`

### Phase 4 manual checks

- [ ] The final-assembly gate is readable at 1280x720 and at other window sizes; no prerequisite line overflows
- [ ] Confirming final assembly feels final: the design visibly locks and the install animation reads
- [ ] The install animation can be skipped without leaving the screen stuck
- [ ] The escape reads as six distinct beats, not one long fade
- [ ] VELA is recognisably the same ship in the workshop, final assembly, departure, launch, debris, sunlight, portal and home (compare captures 36, 46, 48-53b)
- [ ] Final assembly shows VELA upright with the three fitted modules and no flame; no engine or impact sound plays on that screen
- [ ] Scene A: VELA stands upright on the pad, several times taller than Nick and Bill, engines cold; the transfer readout fills and turns DONE; Bill's shell goes dark; Nick walks to the ramp and boards; the hatch and umbilical close before ignition
- [ ] Scene A visibly reflects the repaired junction (lit cable)
- [ ] Scene B: ignition builds on the pad (smoke, dust, thrown scrap), then the ship lifts straight up with the flame under the nozzles; no sideways start, no asset swap
- [ ] Scene B: each shield ripple coincides with a body hitting the bubble; heavier hits sound heavier; the shake is brief and stops; with reduced motion the ripples still show and nothing shakes
- [ ] The debris passage shows shielding and navigation, not invulnerable smashing; A / D, Left / Right and the mouse steer; grit sparks on the shield rather than passing through the hull
- [ ] Contact sounds never stack into noise during a burst of grit, and stop when the scene ends or is paused
- [ ] The portal: the opening is clearly active, lining up under it locks, the ship is visibly pulled in and disappears through the rim, and only then does the flash come
- [ ] Home: the spaceport reads as the same pixel-art world as the opening Earth level (trees, bushes, lamps, crisp shapes, contact shadows, correct overlap of Nick, ramp, ship and pad); VELA lands with engines off; the ramp lowers; Nick walks out and celebrates; there is no face close-up
- [ ] Subtitles never cover Nick's exit or celebration
- [ ] The sunlight beat has room to breathe; Bill's three lines land
- [ ] The portal is clearly a story device, not presented as science
- [ ] The home scene visually matches the opening Earth and the memories found
- [ ] The final message is readable and quiet
- [ ] Esc pauses mid-cinematic; SKIP SEQUENCE skips without a flicker or stuck input; Space does nothing
- [ ] Focus loss during the cinematic pauses it
- [ ] The mission report scrolls smoothly and nothing overlaps; the "more below" hint is noticed
- [ ] The score and its formula are understandable without reading the docs
- [ ] The credits scroll smoothly and the closing card is reached
- [ ] Continue after the credits returns to the credits; New Game starts clean
- [ ] The reduced-motion setting visibly removes shake and lowers flashes, and changes no outcome
- [ ] Holding I + O + P anywhere does nothing (in the typing fight they are ordinary letters)

### Phase 3 manual checks

- [ ] Falling words are readable at 1280x720 and at other window sizes; no label overlaps another
- [ ] The typed prefix, the selected word and the reset notice are obvious at a glance
- [ ] Typing feels immediate on a real keyboard; held keys never auto-type
- [ ] The Sky Remnant reads as large, fierce and alive (wings, eyes, jaw), and pulses visibly land
- [ ] The danger line and word urgency colours are clear, including for colour-blind players (blinking near the line)
- [ ] The first fight with the tutorial is understandable without the README
- [ ] Measured fight length for real players (record typing speed, misses, time)
- [ ] Slow typists can finish; fast typists are not bored
- [ ] Typing and success sounds are audible and not irritating over ~30 words
- [ ] The vocabulary journal is readable and easy to browse
- [ ] The Dawn Tower slope reads as a dead forest with a tower, not a generic ruin
- [ ] The workshop report is understandable: what failed and what to change
- [ ] The READY FOR FINAL ASSEMBLY summary is clearly the end of this build
- [ ] After the victory the shield emitter drop is easy to spot, bobs gently, and the E prompt appears when Nick is close
- [ ] Per-letter shots feel immediate; fast typing does not stack flashes or sounds; dim (no-damage) shots read as such
- [ ] The bottom-right definition panel is readable for the longest words and definitions, and never hides a falling word or Nick
- [ ] The workshop reads as repairing the ship: socket preview, install flash, fitted part visible
- [ ] Workshop and typing screens do not overlap or clip at 1280x720, at the minimum window size and when resized
- [ ] An educator has reviewed the vocabulary (spelling, meaning, suitability, bands)

## General integration pass

Automated:

- [x] Esc opens the pause menu on the world and the launch; a paused launch does not advance — `test_flow.gd`
- [x] Esc pauses the installation and the cinematic; the pause menu offers SKIP — `test_flow.gd`
- [x] A click on a pause row hits that row; a click outside every row does nothing — `test_flow.gd`
- [x] Space does not pause; I, O and P do not skip a milestone in exploration — `test_flow.gd`
- [x] Settings list four volume sliders, text speed, reduced motion and back; sliders step by 0.1 — `test_flow.gd`
- [x] Settings round-trip through their own file and never touch the campaign — `test_flow.gd`
- [x] Eco Arena practice is locked on a new profile; the row and a direct call both refuse — `test_flow.gd`, `test_eco_arena.gd`
- [x] A save that beat the Scrap King unlocks practice; practice still never writes the save — `test_eco_arena.gd`
- [x] Toxic Tide speeds are exactly 1.2x the old bands (120 / 148.8 / 180 / 213.6, cap 240); retries never compound; hostile = beneficial; the swept shield blocks at 213.6 — `test_encounter.gd`
- [x] The cinematic: only Enter / NEXT advance a beat; letters, Space and scene clicks do nothing; PAUSE and Esc ask for the pause menu — `test_flight.gd`
- [x] Debug jumps finish every earlier map: salvage ids, coast extras, boss rewards collected (never a waiting drop), no duplicate component — `test_debug_jump.gd`

Manual (needs a display and speakers):

- [ ] Every visible button and menu row reacts to hover and a single click, at 1280x720, maximised and after resizing
- [ ] UI stays clickable after pause / resume and after every scene transition
- [ ] Right click and the zone badge open the pause menu in exploration; the checkpoint MENU button opens it on summaries
- [ ] Settings sliders follow a mouse drag; volumes are audible per bus and survive a restart
- [ ] Pause ducks the music, silences ambience and combat sounds, and menu sounds still play
- [ ] Rapid fire, typing and shield impacts never stack into a harsh drone; no clipping
- [ ] No sound continues after leaving a fight or the cinematic
- [ ] Phase 1 launch reads clearly: pad and gantry, ignition smoke, liftoff, clouds, Earth limb; VELA upright, same design as the console, no flame on the pad
- [ ] Bill is easy to find on the crash-site ash before activation, shows no lights while dormant, and lights up only after activation
- [ ] The credits open with the six team names, fully visible, spelled exactly as listed
- [ ] No NASA name, logo or link appears anywhere in the game
- [ ] Boss 2 at the new speed is still fair to block at every health band

## Regression (the legacy NASA mission-planner skeleton)

- [ ] `core/calculations.gd` and `core/mission_rules.gd` still load
- [ ] `autoload/game_state.gd` still exposes `reset()` and the `budget_*` fields
- [ ] The legacy `data/*.json` files are untouched

## Export

- [ ] A Windows export preset exists and the build launches (blocked: no export
      templates are installed on the delivery machine; see `docs/submission.md`)
- [ ] Web build loads and plays
