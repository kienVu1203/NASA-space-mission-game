# Game design

## One-sentence description

Nick builds the VELA, answers a signal that should not exist, and wakes up in a
ruined city where the only way home is to recover the record of what happened
from the machines that are still running.

## Minimum features

Phase 1 (shipped):

- A present-day spaceport to explore, with a briefing, an assembly console and a
  launch pad.
- Ship construction with five slots, nine components, adjustable fuel and a
  preflight check that can be failed and revised.
- A scripted launch, rift and crash that cannot be lost.
- Crash-site exploration, salvage, inventory limits and the Bill quest.
- A first memory, a checkpoint and a save that survives Continue.

Phase 2 (shipped):

- **Forgotten City**: a walkable ruined street with waste, a green memory, a
  route checkpoint and the control center.
- **Scrap King (Eco Arena)**: an educational arena survival about waste
  sorting in the Scrap King's yard. Match the Tri-Spectrum Blaster (Green
  organic, Blue clean paper, Yellow plastic & metal, STAR FALL's own simple
  convention) to each enemy's waste armor, clean the dropped energy cores with
  the same colors (by touch or Bill's beam), bait chargers into crushers, and
  charge the station to 80%. The Junkyard Colossus then drops a three-lock
  Super Core and the navigation chip, which Nick picks up. The same arena is
  on the main menu as a practice mode that never touches the campaign.
- **Control-center archive**: five records, then the Future Earth reveal. The
  mission changes from investigating a signal to returning with evidence.
- **Silent Coast**: a harbor with a polluted tide, samples, records and a coastal
  memory.
- **Toxic Tide**: a fixed-position, mouse-directed shield-defense fight. Block
  hostile energy, admit beneficial energy, build charge, press Space to
  counterattack. Health bands raise speed and firing rate. The power core
  drops onto the quay and is picked up after the fight.
- **Environmental archive**, the crash-site base return, both components shown
  fitted, and the Dawn Tower unlocked.

Phase 3 (shipped):

- **Dawn Tower**: a dead forest below the Dawn Project transmitter, a survey
  projector holding a memory of the healthy forest, a boardwalk checkpoint, a
  defense console and salvage.
- **Sky Remnant**: a typing battle against a smog-born guardian. Environmental
  vocabulary falls from the boss; every correct letter fires a shot back. Reward:
  `shield_emitter`.
- **Vocabulary journal**: every word typed is kept with its meaning, readable in
  the paused fight and from the exploration pause menu.
- **Dawn Project archive**, then the **reconstruction workshop** at the base:
  salvage, limited fabrication, an engine, a route, protection, storage and
  payload, checked by a return-mission simulation.

Phase 4 (shipped):

- **Final assembly.** A prerequisite gate before the finale: all three bosses,
  all three components, the mandatory payload, a valid fabrication and a passing
  simulation that matches the frozen design. Confirming is one-way.
- **Escape cinematic.** Six in-engine scenes — leaving the crash site, launch,
  debris passage, sunlight, the portal, home — plus the closing message.
  Subtitles are data; Space pauses; Esc skips with an identical outcome.
- **Mission report and score.** Built only from the recorded run, with the score
  formula published in `finale.json`.
- **Credits**, then the title. The ending state is saved.

## Nice-to-have (not built)

- More side records and optional memory files per chapter.
- A voiced or externally rendered cinematic (the shipped one is in-engine).
- A Windows export build (no export templates were available; see
  `docs/submission.md`).

## Game flow

```
Title
  -> Briefing -> Construction -> Preflight -> Launch
  -> Crash site -> Salvage -> Bill -> Memory -> Phase 1 summary
  -> Forgotten City -> Scrap King -> Control-center archive -> Reveal
  -> Silent Coast -> Toxic Tide -> Environmental archive
  -> Crash-site base -> Phase 2 summary
  -> Dawn Tower -> Forest memory -> Sky Remnant -> Dawn Project archive
  -> Reconstruction workshop -> Simulation -> READY_FOR_FINAL_ASSEMBLY
  -> Final assembly -> Escape (6 scenes) -> Return home
  -> Mission report -> Credits -> Title
```

## Phase 2 combat design

**Why this shape.** The brief asks for a fixed-position defense encounter, not a
shooter and not free movement. Nick stands at the center of a 640x360 arena; a
large robot occupies the rear layer. Two projectile families arrive:

- **Hostile energy** (orange/red, angular shapes): block it with the shield. If
  it reaches Nick it deals that attack type's damage.
- **Beneficial energy** (green/cyan, diamond and orb shapes): deliberately let it
  reach Nick. It charges the meter above his head. Blocking it wastes it.

The shield is a narrow arc (84 degrees by default) pointed by the mouse, always
active. The player must therefore rotate continuously rather than sit behind a
bubble. Charge is not a reward for blocking: it comes only from motes, so the
fight is about reading the arena and choosing what to admit.

Space spends the whole meter on a counterattack that damages the robot. The meter
does not decay, damage does not consume it, and nothing else damages the boss, so
the player always chooses when to attack.

**Difficulty.** Both firing interval and projectile speed are read from the
boss's current health band, never from elapsed time. Bands are bounded by each
boss's `limits`, and the active projectile count is capped. The scheduler keeps
beneficial energy flowing at every band, including the hardest, so the fight can
never become a permanent defense-only loop.

**Fairness.** Every projectile is telegraphed from its own emitter. Escalation is
gradual and visible on the boss health bar as band ticks. Defeat offers a retry
that resets only encounter-local state. Losing to a boss never costs campaign
progress.

**The two bosses are different fights, not reskins.** (Since the Phase 2
revision the Scrap King is fought in the Eco Arena; the Scrap King column
below now describes only the shield-duel engine's regression fixture.)

| | Scrap King | Toxic Tide |
|---|---|---|
| Health | 100, 25 per counterattack (4 hits) | 132, 33 per counterattack (4 hits) |
| Silhouette | Heavy industrial chassis, planted legs | Marine tank body, articulated arms, hose |
| Signature patterns | Lane pairs, staggered cross, magnetic salvos | Tide sweeps, wide sprays, heavy globs |
| Rhythm | Slower, heavier, more projectiles per volley | Shorter warning, wider spread, faster late |
| Beneficial source | Emitters at left and right | Low pump manifolds |

## Phase 2 progression design

The chapter order is fixed and gates are explicit:

- The **checkpoint** must be used before a boss door opens. The refusal is
  diegetic ("not without a saved route"), and the checkpoint is the resume point.
- A boss grants a **unique component** exactly once. Replaying the result cannot
  duplicate it.
- The **archive** is the story payoff. Closing it applies the outcome, whether
  the player read every record or none. Skipping costs nothing but the prose.
- The **Future Earth reveal** changes the active mission and unlocks the Silent
  Coast. Nothing before it names Earth or a date.
- The **Silent Coast outcome** unlocks Dawn Tower and returns the campaign to the
  crash-site base, where the recovery frame shows what has been earned.

## Phase 3 typing battle design

**Why typing.** The third boss replaces the earlier movement and dodge idea with
a typing fight, so the final encounter teaches something: the player reads and
types real environmental vocabulary, and each word carries a short meaning.
The fiction: the Dawn Project defense console accepts archive terms as control
signatures. The game says this is how the facility was built, not how real
machines work.

**The loop.** The Sky Remnant sheds words that fall toward a red danger line.
Typing a word's first letter selects it; every correct letter fires one shot, which
damages the boss once when it lands. A wrong letter only restarts that word,
with a clear notice and no damage. A word that reaches the line costs health
and returns to the queue a few seconds later, so nothing required is ever lost.

**Library versus deck.** The library has 203 entries; one fight uses a
30-word deck in four stages from familiar to advanced. Boss health is exactly
30 pulses, so the health bar is the deck: the boss falls when the last word
lands, never earlier, and the fight can never stall with every word done.

**Accessible pacing.** One word at a time with long falls to start; up to two
later. The game measures typing pace over several words and only ever adjusts
within bounds: slower typists get one word at a time and longer falls, faster
typists get shorter gaps. Misses never speed anything up. Nothing is ever typed
for the player, and the advanced stage is never skipped. The 3–4 minute length
is a target for an assumed casual typist, not a timer; a slower player takes
longer and can still win.

**Learning without lecturing.** The learning panel shows the selected word and
one line of meaning; nothing long sits beside the falling words. Definitions,
examples and "why it matters" notes live in the journal, which can be read at
any time without being attacked.

## Phase 3 reconstruction design

**Different from day one.** Day one used credits and new parts. The future uses
salvage and a small fabricator, so the question is what to build from what was
found, not what to buy.

**Real trade-offs, no best build.**

- The **Fast Corridor** is short but violent: more delta-v, dense debris that
  needs plating (heavy, more propellant) or an amplifier (light, but power
  hungry), and a short relay window that cannot carry extra records.
- The **Extended Arc** is quiet but long: little protection and delta-v, but
  four hours of electrical load that punish power-hungry choices.
- **Repairing the day-one engine** is cheap, and its performance is whatever the
  player launched with. A light engine can fly the Extended Arc but not the Fast
  Corridor. The **rebuilt cluster** flies either, at a high fabrication cost.

**Fairness.** Simulating is free and repeatable; fabrication spends salvage
once and only for a design with a current passing report. Scavenging tops
common materials up to a floor that always covers a passing design, so no run
can be stranded. Every valid day-one build can reach a passing return.

**Honesty.** The panel says it on screen: a simplified educational model with
invented values, not NASA data.

## Phase 4 design

**Why the finale is a gate, not a cutscene.** The brief asks for revalidated
prerequisites, a frozen snapshot, a saved checkpoint and locked controls before
the escape. So READY_FOR_FINAL_ASSEMBLY opens a screen that *shows* the six
checks and only then offers one irreversible action. The confirmation latches
twice (screen flag + campaign method), which is what makes a double click
harmless.

**Why the cinematic is in-engine.** It is drawn from generated sprites and
primitives, so it cannot fail on a missing video file, it scales with the pixel
viewport, and it can be skipped without any cleanup problem. Its copy and
timings live in `finale.json`.

**Why the scenes read recorded state.** Scene A lights the junction only if the
player repaired it. Scene C's telemetry is the certified simulation of the
frozen design: route, mass, delta-v, propellant and buffer reserves, peak power
and the debris impact count. No number on screen is invented at playback time,
and nothing randomly fails a design that passed.

**Why the report is recomputed.** The report runs the same simulation code the
workshop certified, from the committed design. If the two ever disagreed, the
report would be describing a ship the player did not fly.

**Score, published.** 100 for the return objective, 25 per component, 15 per
memory, 20 per optional payload flown, and up to 30 efficiency points from the
propellant reserve (full marks at half a tank left). It never reads inventory
size, play time, settings or skipped cinematics, so farming cannot inflate it
and accessibility choices cannot deflate it. Several designs reach a high total
because the efficiency term rewards margin.

**Why skipping is safe.** The cinematic reports one outcome; the controller
applies every flag and save once. Focus loss pauses rather than letting it run
unseen. A save written during the escape resumes at the start of the escape, and
the documented safe checkpoint is the pre-finale one.

**QA stage skip.** `I + O + P` advances one milestone per press for playtesting.
It builds real designs through the real validators, applies real boss rewards
and real fabrications, and saves at every step, so a skipped run is
indistinguishable in rules from a played one. It is enabled only in debug
builds, the editor, or with `--qa`.
