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

## Regression (the legacy NASA mission-planner skeleton)

- [ ] `core/calculations.gd` and `core/mission_rules.gd` still load
- [ ] `autoload/game_state.gd` still exposes `reset()` and the `budget_*` fields
- [ ] The legacy `data/*.json` files are untouched

## Web export (once a preset exists)

- [ ] Web build loads and plays
