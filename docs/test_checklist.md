# Test checklist

Ticked items are covered by an automated headless suite; the rest need a person
at the keyboard. Commands are in `docs/star_fall_contract.md` §9.

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
- [x] Skipping the cutscene still sets launch, rift and crash flags — `test_flow.gd`
- [x] Skipping the cutscene still saves the crash-site checkpoint — `test_flow.gd`
- [x] The launch design yields surviving science data — `test_flow.gd`
- [x] Crash-site labels contain no spoilers — `test_flow.gd`
- [x] Wreck inspection grants design-dependent salvage — `test_flow.gd`
- [x] Salvage collection removes the prop and records the id — `test_flow.gd`
- [x] Bill stays dormant until the junction is repaired — `test_flow.gd`
- [x] Activating Bill plays the memory and records it — `test_flow.gd`
- [x] The checkpoint stage, save and Continue all work — `test_flow.gd`
- [x] Esc opens the pause overlay and locks movement — `test_flow.gd`
- [x] Resume restores movement — `test_flow.gd`
- [x] Settings round-trips from the pause menu without stranding the player — `test_flow.gd`
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
- [x] The Scrap King encounter opens, holds during its briefing, then fights
- [x] Space during the briefing advances the dialogue and never fires a counterattack
- [x] No reward exists before the boss is defeated
- [x] The encounter is winnable through its own rules
- [x] Victory stops the encounter and grants the navigation chip once
- [x] A replayed victory awards no second chip
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
- [x] The Toxic Tide can be defeated and grants the power core once
- [x] The environmental archive applies the lesson and unlocks Dawn Tower
- [x] The base return shows both recovered components
- [x] The Phase 2 summary returns to the title and keeps the save
- [x] Continue restores the Phase 2 stage, components, archives and mission

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
- [ ] Settings: ambience toggles, text speed changes dialogue pacing
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

## Regression (the legacy NASA mission-planner skeleton)

- [ ] `core/calculations.gd` and `core/mission_rules.gd` still load
- [ ] `autoload/game_state.gd` still exposes `reset()` and the `budget_*` fields
- [ ] The legacy `data/*.json` files are untouched

## Web export (once a preset exists)

- [ ] Web build loads and plays
