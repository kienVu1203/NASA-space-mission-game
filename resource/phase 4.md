Finish STAR FALL in:
C:\Users\Win\NASA\NASA-space-mission-game

You are the Senior Game Engineer responsible for final integration, cinematics, user experience, and playable-demo delivery.

Read AGENTS.md, docs/roles.md, docs/star_fall_contract.md, and the actual current code.
Inspect the completed phases before making changes.
This task assigns integration responsibility across the relevant project folders.

Do not rebuild working architecture.
Preserve user changes.
All code, comments, documentation, UI, dialogue, and reports must use English.
The protagonist is Nick. His robot companion is Bill.
The displayed title must consistently be STAR FALL.

FULL GAME FLOW
Main Menu
-> Healthy Present-Day Earth
-> Mission Briefing
-> Original Spacecraft Construction
-> Preflight Validation
-> Launch
-> Signal Investigation
-> Rift Accident
-> Future Crash Site
-> Meet Bill
-> Forgotten City / Scrap King
-> Future-Earth Reveal
-> Silent Coast / Toxic Tide
-> Dawn Tower / Sky Remnant
-> VELA Reconstruction
-> Return-Mission Simulation
-> Final Assembly
-> Escape Cinematic
-> Return to the Present
-> Mission Report
-> Credits

The present-day shipbuilding stage is mandatory gameplay.
Do not replace it with a cinematic during final integration.

FINALE PREREQUISITES
Require:
- All three campaign bosses completed.
- All mandatory recovered components available.
- Bill's memory core and the minimum evidence archive selected.
- Final fabrication valid and completed.
- A passing simulation matching the exact current design.
- No competing cutscene or transition.

When the player selects "Complete Assembly and Launch":
1. Revalidate prerequisites.
2. Freeze the final design snapshot.
3. Save a pre-finale checkpoint.
4. Lock workshop editing and gameplay controls.
5. Animate installation of the final assembly.
6. Start the cinematic automatically.

Prevent duplicate transactions and transitions from repeated clicks.

CINEMATIC IMPLEMENTATION
Use in-engine sprites, scenes, parallax, tweens/animations, subtitles, and available audio.
Do not depend on an externally rendered video or missing files.
Implement an explicit, manageable sequence with safe skip behavior.

SCENE A: LEAVING THE CRASH SITE
- Nick transfers Bill's memory core onto VELA.
- Bill's old body powers down in the workshop.
- Briefly show the crash site and environmental systems the player actually repaired.
- Reflect saved world changes rather than inventing actions the player never performed.

SCENE B: LAUNCH
- Engine startup.
- Dust and loose scrap react.
- VELA rises above the ruined surface.
- Transition from ground-level layers into the dark atmosphere.
- Preserve readable pixel presentation.

SCENE C: DEBRIS PASSAGE
- Follow the selected mission route.
- Shields absorb remaining small impacts.
- Navigation avoids larger objects.
- Do not show an invulnerable ship smashing through every obstacle.
- Display telemetry from the locked design and simulation report.
- Do not generate meaningless random numbers disguised as engineering feedback.
- Represent route differences through pacing, visuals, or report-backed telemetry.
- Do not introduce mandatory QTEs.
- Do not randomly fail a design that passed the mission simulation.

SCENE D: SUNLIGHT
VELA emerges into warm sunlight.
Nick looks back at future Earth.

Dialogue:
Bill: "Is the sky still blue where you come from?"
Nick: "It is."
Bill: "Then keep it that way."

Allow a quiet pause.
Avoid excessive effects that weaken the moment.

SCENE E: THE PORTAL
- VELA uses its original recorded signal to identify the portal.
- The ship reaches it during the planned access window.
- The portal opens.
- VELA crosses back to the present.

Treat the portal as a fictional story mechanism.
Do not invent scientific evidence for time travel.

SCENE F: HOME
- Mission Control reacquires VELA.
- Nick sees present-day Earth, visually matching the healthy opening.
- Match selected shots to the memories discovered during the campaign.
- Nick begins transferring the archive.

Dialogue:
Mission Control: "VELA, we have your signal. What happened?"
Nick: "I have data to send. This time, we need to listen."

Show the information reaching researchers and communities.
End with the opportunity to act.
Do not imply that one person instantly solved global environmental problems.

FINAL MESSAGE
"You found your way back to Earth.
Help keep it a home for those who come after us."

SKIP AND RESUME
- Watching and skipping the cinematic must produce the same persistent outcome.
- Skipping must not omit flags, reports, or completion state.
- Repeated skip input must be safe.
- Pause, focus loss, and skip must not conflict.
- If the game closes during the cinematic, Continue must restore a documented safe checkpoint.
- Replaying from the pre-finale checkpoint is acceptable.
- Never leave the player in an input-locked intermediate state.
- Clean up timers, animations, audio, and connections when leaving the sequence.

MISSION REPORT
Use actual run data:
- Return objective completed.
- Archived memories recovered.
- Scientific samples returned.
- Original design and reconstructed design.
- Final launch mass.
- Selected route.
- Simulated fuel and energy reserves.
- Material efficiency.
- A concise explanation of decisions that enabled success.

If implementing an overall score:
- Publish its formula in project data/documentation.
- Use real recorded state.
- Do not reward infinite resource farming.
- Do not penalize accessibility settings or skipped cinematics.
- Support multiple successful engineering approaches.

FINAL UX PASS
- Consistent STAR FALL branding.
- Consistent Nick and Bill naming.
- English text throughout the campaign.
- Readable fonts and subtitles.
- No text overflow.
- Clear objectives without premature story spoilers.
- Menus do not trigger gameplay inputs underneath.
- Bosses stop during pause and narrative sequences.
- No duplicated audio after restart or scene changes.
- Screen shake and flashes can be reduced or disabled.
- Mouse aiming remains correct through scaled pixel viewports.
- No dead buttons or visible TODO text in the main player flow.
- New Game starts with clean campaign state.
- Continue and replay behavior remain predictable after completion.

NARRATIVE CONSISTENCY
Verify:
- Nick is human.
- Bill is first encountered in the future.
- Nick constructs VELA before the initial launch.
- The original mission has clear scientific requirements.
- The unavoidable rift is an external accident.
- The future-Earth reveal occurs after Scrap King.
- Pre-boss memories show what was beautiful.
- Post-boss records reveal the fictional history of destruction.
- Each recovered component contributes to the return design.
- Electrical power, stored energy, and propellant remain distinct.
- Monsters are consequences of the damaged world.
- Time travel, extreme mutations, and shielding are clearly fictional.

SOURCES AND CREDITS
- List original assets and external assets with actual licenses.
- Credit only NASA or partner resources genuinely used.
- Distinguish physical formulas, real datasets, invented gameplay values, and fictional story elements.
- Do not invent environmental statistics.
- Do not imply NASA endorsement.
- Use direct authoritative sources for any newly introduced factual scientific claims.

END-TO-END VERIFICATION
Check:
1. New Game through the complete ending.
2. Original spacecraft construction and failed/valid preflight states.
3. Continue at major checkpoints.
4. Each boss death/retry cycle.
5. Skipping all skippable sequences.
6. Changing a design after successful simulation.
7. Double-clicking fabrication and final launch.
8. Reloading completed boss arenas.
9. Full inventory.
10. Missing or corrupted save handling.
11. Focus loss, pause, and window resizing.
12. Starting again after the ending.
13. Retained standalone-demo regressions.

Use automated checks where meaningful and manual playtesting where required.
Do not claim visual/audio verification from headless checks.
If full playtesting is unavailable, state exactly what remains unverified.

DELIVERY
Update:
- README.md.
- docs/game_design.md.
- docs/star_fall_contract.md.
- docs/test_checklist.md.
- docs/submission.md.

Document:
- Actual engine version.
- Exact run instructions.
- Controls.
- Save behavior.
- Simulation assumptions and limitations.
- Credits and sources.
- Known issues.

If export templates and an appropriate preset are available:
- Create a Windows build in a suitable build directory.
- Follow repository rules for creating export presets through Godot Editor.
- Verify the exported build if possible.

If exporting is unavailable:
- Report the actual blocker.
- Provide precise editor-run instructions.
- Do not claim that an executable was created.

Finish with:
- Implemented scope.
- How to run.
- Actual test commands and outcomes.
- Unverified areas.
- Remaining issues, if any.

Complete the authorized integration work before returning the final report.