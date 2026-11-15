You are the Senior Godot Engineer and Technical Artist responsible for fixing STAR FALL's final assembly, departure cinematic, portal transition, and homecoming.

The game already runs. Modify the existing implementation directly. Do not rebuild the project or replace functioning gameplay systems.

WORKSPACE
C:\Users\Win\NASA\NASA-space-mission-game

==================================================
1. INSPECT THE PROJECT AND REFERENCES
==================================================

Before editing:
- Read applicable AGENTS.md files, docs/roles.md, README.md, and the implementation contract if present.
- Inspect the actual workshop, final-assembly screen, cinematic controller, spacecraft assets/renderers, audio, and ending scenes.
- Check the installed Godot version and current Git changes.
- Preserve user changes.
- Follow existing ownership and resource-editing conventions.
- This task assigns integration responsibility across the files needed for these corrections.
- Keep code, comments, UI, and documentation in English.

Established identities:
- Game: STAR FALL.
- Protagonist: Nick.
- Companion: Bill.
- Spacecraft: VELA.
- Art direction: pixel art with 2.5D depth.

REFERENCE IMAGES

Reference 1 — CANONICAL SPACECRAFT DESIGN:
C:\Users\Win\AppData\Local\Temp\codex-clipboard-dcff9ce5-d219-44b2-bca1-92dd67d5952a.png

Reference 2 — inconsistent final-assembly spacecraft:
C:\Users\Win\AppData\Local\Temp\codex-clipboard-545663cf-7f86-475f-8c23-24fbcf33828a.png

Reference 3 — inconsistent, undersized horizontal ship during Bill's transfer:
C:\Users\Win\AppData\Local\Temp\codex-clipboard-ae60e4d7-6550-4e87-b40e-266f1fa67d6a.png

Reference 4 — incorrect launch orientation and insufficient debris feedback:
C:\Users\Win\AppData\Local\Temp\codex-clipboard-d05db077-3ed0-45b8-8792-97d5459a32f9.png

Reference 5 — ship remains far from the portal:
C:\Users\Win\AppData\Local\Temp\codex-clipboard-e61ce27e-d1be-4e6e-a511-2167ed852124.png

Reference 6 — homecoming environment requiring replacement:
C:\Users\Win\AppData\Local\Temp\codex-clipboard-e1168578-2c88-42fd-8f36-b74cf0acb8bc.png

Inspect these images before implementing visual changes.

Treat screenshots as visual evidence. They do not override the explicit requirements below.

==================================================
2. PRIMARY REQUIREMENT: ONE CONSISTENT VELA DESIGN
==================================================

Reference 1 is the visual source of truth.

Preserve its recognizable:
- Long gray segmented hull.
- Tapered nose.
- Rear engine assembly.
- Panel divisions.
- Component locations and installed-component appearance.
- Cyan technological accents.
- Overall proportions and silhouette.

The spacecraft must remain recognizably the same vehicle in:
1. Reconstruction workshop.
2. Final-assembly confirmation.
3. Bill's data/memory-transfer sequence.
4. Launch.
5. Debris ascent.
6. Portal approach and entry.
7. Homecoming and landing.

Do not continue using unrelated spacecraft drawings for different scenes.

Reference 2's simplified upright ship is not the target design.
Reference 3's small horizontal ship is not the target design.

IMPORTANT ORIENTATION DISTINCTION

Reference 1 shows the ship horizontally on a service support.
Use its design, not its horizontal orientation, as the canonical identity.

The workshop may retain a horizontal maintenance view if appropriate.

For parked departure, launch, ascent, portal approach, and homecoming:
- Nose points upward.
- Engines/nozzles are at the bottom.
- Landing supports/base are below the ship.
- The body retains the reference design's proportions.

Create an upright presentation of the same ship.
Do not replace it with a different rocket.

==================================================
3. CENTRALIZE SPACECRAFT PRESENTATION
==================================================

Inspect where VELA is drawn or instantiated.
Remove inconsistent scene-specific duplicates.

Use one shared scene, renderer, or equivalent existing abstraction for:
- Base hull.
- Installed components.
- Engine nozzles.
- Engine flame.
- Shield presentation.
- Landing/parked state.

Provide explicit presentation states such as:
- maintenance
- parked
- ignition
- ascending
- portal_entry
- landed

Adapt to the existing architecture rather than forcing these exact names.

Requirements:
- Preserve the actual committed spacecraft configuration.
- Keep module visuals consistent with installed campaign items.
- Ensure final assembly and cinematic views use the same frozen design.
- Keep engine effects independent from hull geometry.
- Do not rotate the entire composition in a way that moves flames or landing supports to the wrong side.
- Avoid nonuniform scaling that distorts the ship.
- Keep pixel scale coherent and rendering crisp.

For procedurally drawn art, centralize the geometry.
For sprite-based art, reuse the same source assets and attachment rules.

Do not modify engineering validation or resource costs merely to unify artwork.

==================================================
4. FINAL-ASSEMBLY SCREEN
==================================================

Replace the inconsistent ship shown in Reference 2.

Show:
- The canonical VELA design from Reference 1.
- An upright orientation.
- Correct installed navigation, power, and shield components.
- A suitable preview scale.
- Engines off.

Preserve:
- Final prerequisites.
- Frozen-design behavior.
- Launch confirmation.
- Existing validated mission state.

Do not let the preview accidentally trigger engine, shield-impact, or flight audio.

==================================================
5. BILL TRANSFER: A PROPER DEPARTURE STATION
==================================================

Rebuild the staging shown in Reference 3.

The ship is currently too small, uses a different design, and lies horizontally.
Correct all three issues.

Create a readable departure scene:
- A repaired VELA standing upright.
- A recognizable launch/spacecraft service station.
- A substantial landing platform or launch pad.
- Rear service structures, supports, stairs, or gantry details.
- A believable access point for Nick to board.
- Bill positioned near a transfer terminal or connection.
- A visible data-transfer action or indicator.

The ship should clearly be larger than Nick and Bill.
Use a consistent scale relationship, not arbitrary per-scene sizing.
A ship height several times the character height is an appropriate starting point; verify composition at the actual viewport resolution.

PARKED STATE
During transfer:
- VELA is stationary.
- Engines are completely off.
- No rocket flame.
- No exhaust suggesting thrust.
- The ship is visibly supported by the pad/landing structure.
- The engine nozzles remain at the bottom.
- The scene must not make VELA look like a tiny object beside Bill.

SEQUENCE
Show an understandable progression:
1. Nick and Bill are beside the parked ship.
2. The transfer/core-loading action occurs.
3. A clear completion cue appears.
4. Nick approaches and boards VELA.
5. Departure preparation completes.
6. Ignition begins afterward.

Preserve the established story treatment of Bill's memory core.
Do not duplicate Bill or accidentally change his campaign state.

Avoid replacing these actions with only subtitle text.

==================================================
6. VERTICAL IGNITION AND LIFTOFF
==================================================

Correct the launch behavior visible in Reference 4.

VELA must:
- Begin upright.
- Point its nose upward.
- Ignite its bottom engines.
- Lift vertically from the platform.
- Remain upright through the initial ascent.

Do not:
- Begin horizontally and rotate into launch.
- Launch sideways.
- Produce exhaust from a side-mounted position caused by a wrong transform.
- Swap to another spacecraft asset during takeoff.

Show:
- A brief ignition buildup.
- Exhaust originating at the bottom engine nozzles.
- Smoke/dust reacting around the pad.
- Clear separation between the ship and platform.
- Upward acceleration.
- A transition from the station to the debris-filled sky.

Keep the launch understandable even without subtitles.

==================================================
7. DENSER DEBRIS AND SHIELD IMPACTS
==================================================

Increase the debris field moderately so it feels like VELA is passing through a dangerous accumulated-waste layer.

Use:
- Several debris sizes.
- Controlled foreground/background layers.
- A readable corridor around the spacecraft.
- Enough density to feel threatening without hiding the ship or HUD.

Do not fill the screen with uniform particles.

SHIELD CONTACT
When debris contacts the outer shield:
- Show the shield at the contact location.
- Trigger a small ripple, spark, or energy flash.
- Play a short impact sound.
- Add brief, restrained shake/recoil.

The feedback must correspond to an actual visual contact or an explicitly choreographed contact event.

Do not:
- Play unrelated collision sounds at random.
- Shake continuously without impacts.
- Show debris passing through the hull while pretending it hit the shield.
- Introduce random failure into an already validated cinematic.

IMPACT AUDIO
- Distinguish lighter and heavier impacts where practical.
- Limit overlapping voices.
- Use cooldowns or grouping to prevent harsh audio stacking.
- Respect volume and pause controls.
- Use available licensed/original audio, or create an appropriate simple original effect.
- Document any newly added external audio source.

SHAKE
- Keep the intensity modest.
- Preserve the underlying upward trajectory.
- Avoid accumulating positional drift.
- Preserve pixel readability.
- Respect reduced-motion settings.
- Use visual contact feedback even when shake is disabled.

The shield must visibly protect the canonical spacecraft's outer silhouette.

==================================================
8. SHOW THE SHIP ENTERING THE TIME PORTAL
==================================================

Reference 5 currently shows the ship far from the portal.
Replace this with a complete, readable entry sequence.

Required sequence:
1. The portal becomes identifiable and active.
2. VELA aligns with its opening.
3. The ship approaches.
4. Attraction/suction becomes visually apparent.
5. VELA crosses the portal boundary.
6. The ship becomes occluded or disappears inside the opening.
7. The scene transitions to the return journey/homecoming.

Do not end the scene while the spacecraft is still far away.

ORIENTATION
Keep VELA upright and consistent with the launch presentation.
Place the portal and trajectory to support this orientation, for example above the approaching ship.

Do not solve the portal scene by turning VELA into an unrelated horizontal aircraft.

VISUAL FEEDBACK
Use restrained:
- Directional particles moving toward the opening.
- Increasing approach speed.
- Portal rim animation.
- Occlusion or a portal mask.
- An entry sound.
- A brief transition flash or tunnel effect.

Do not heavily distort the hull or blur its pixel artwork.

TIMING
Inspect whether current cinematic timers or “next beat” controls advance before portal entry completes.

The normal sequence must wait for visible entry completion.
Preserve an intentional full-sequence skip path that safely applies the required final state.

Do not require an undocumented player action merely to make the ship enter.

==================================================
9. REMOVE NICK'S FACE CLOSE-UP
==================================================

Remove the ending shot that zooms into Nick's face.

Replace it with a wider character-scale homecoming:
1. VELA is safely landed and stationary.
2. Engines are off.
3. An access hatch or ramp opens.
4. Nick visibly exits the ship.
5. Nick walks onto the landing area.
6. Nick performs a brief happy/celebratory action.

Suitable actions include:
- Raising an arm.
- A small joyful hop.
- A short wave.
- A brief relieved celebration.

Choose an animation that fits existing character art.
The action should be visible and understandable at normal gameplay scale.

Do not replace the removed close-up with another portrait or face zoom.
Keep the focus on Nick arriving home in a living world.

==================================================
10. REDRAW THE HOME ENVIRONMENT
==================================================

Rebuild the HOME environment shown in Reference 6.
The current scene is not the desired final result.

Create a new, coherent healthy-Earth landing location in pure pixel-art 2.5D style.

Required visual elements:
- A readable landing pad in an angled/top-down composition.
- Upright canonical VELA resting on the pad.
- A ground path or ramp for Nick's exit.
- Vegetation with coherent pixel detail.
- Trees and environmental props with contact shadows.
- A small receiving station, hangar, or spaceport building.
- Foreground/background separation and correct depth ordering.
- A healthier and warmer palette than future Earth.

Use:
- Crisp pixel shapes.
- Consistent asset resolution.
- Nearest filtering.
- Limited, intentional shading.
- Ground footprints and Y-sorting.
- Layered scenery that creates depth.

Replace the flat, inconsistent placeholder composition rather than only recoloring it.

Avoid:
- Smooth vector-looking circles and blobs.
- A flat side-view background behind angled gameplay props.
- Mixed art scales.
- Blurry filtering.
- Oversized sky decoration dominating the landing scene.
- Floating trees, buildings, or spacecraft.
- Incorrect overlap between Nick, the ramp, the ship, and the pad.
- A cinematic style that looks unrelated to the rest of STAR FALL.

The ending must feel like returning to a believable, living Earth spaceport.

Preserve the environmental message and valid dialogue.
Present it with restrained subtitles that do not obscure Nick's exit and celebration.

==================================================
11. CINEMATIC STATE AND CLEANUP
==================================================

Keep presentation state explicit and reversible.

Verify:
- Engine effects are off during transfer and after landing.
- Engine effects begin only during ignition/flight.
- Shield-impact effects stop outside the debris sequence.
- Portal effects stop after the transition.
- Audio does not continue across unrelated scenes.
- Camera shake returns to zero.
- Scene scale, rotation, and offsets do not leak into the next beat.
- Nick's visibility and input locks are correct.
- Bill/core state remains consistent.
- Retry, replay, pause, and skip do not duplicate characters, rewards, or completion events.

Use existing campaign state APIs.
Do not let visual fixes overwrite the frozen spacecraft design or mission report.

Preserve final results, credits, and completion persistence.

==================================================
12. VISUAL ACCEPTANCE CHECKLIST
==================================================

Compare the updated game against the supplied references.

A. WORKSHOP
- Reference 1 remains the source of the spacecraft's identity.
- Installed modules are represented consistently.

B. FINAL ASSEMBLY
- Same ship.
- Upright.
- Correct proportions.
- Engines off.

C. BILL TRANSFER
- Same ship.
- Upright and substantially larger than the characters.
- Proper departure platform/station.
- Transfer and boarding are visible.
- Engines off.

D. LAUNCH
- Ship starts upright.
- Bottom engines ignite.
- Vertical liftoff.
- No horizontal starting pose or asset swap.

E. DEBRIS ASCENT
- Moderately denser debris.
- Visible shield contacts.
- Contact-linked impact sounds.
- Brief controlled shake.

F. PORTAL
- Ship visibly approaches and enters.
- Suction is understandable.
- Transition occurs after entry.
- Same upright spacecraft.

G. HOME
- Entire environment redrawn in consistent pixel-art 2.5D.
- Same upright ship, landed with engines off.
- Nick exits and celebrates.
- No face close-up.

==================================================
13. VERIFICATION AND DELIVERY
==================================================

Run relevant existing checks and add focused regression coverage where useful.

Verify:
- Shared spacecraft renderer/state consistency.
- Engine state at each cinematic stage.
- Cinematic transitions and portal-entry completion.
- Pause/resume/skip behavior.
- Cleanup of effects and audio.
- Correct final campaign state.
- No regressions in workshop configuration or simulation.

Perform graphical verification where available.
Capture updated reference frames for:
1. Reconstruction workshop.
2. Final assembly.
3. Bill transfer and departure station.
4. Vertical liftoff.
5. Debris/shield impact.
6. Portal entry.
7. Home landing.
8. Nick's exit and celebration.

Inspect the captures and correct visible inconsistencies before delivery.

Headless checks do not prove art consistency, animation quality, or audio behavior.
If graphical/audio verification is unavailable, state exactly what remains unverified.

Update relevant documentation to identify:
- The canonical VELA asset/renderer.
- Orientation and engine-state conventions.
- Revised cinematic sequence.
- New or replaced assets and their sources.

Final report:
- Root causes found.
- Changes implemented.
- Main files changed.
- Canonical ship asset/scene used.
- Tests and actual results.
- Screenshots or capture paths, if produced.
- Remaining limitations.

Complete the requested fixes directly.
Do not stop after describing how they could be implemented.