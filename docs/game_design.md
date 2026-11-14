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
- **Scrap King**: a fixed-position, mouse-directed shield-defense fight. Block
  hostile energy, admit beneficial energy, build charge, press Space to
  counterattack. Five health bands raise speed and firing rate.
- **Control-center archive**: five records, then the Future Earth reveal. The
  mission changes from investigating a signal to returning with evidence.
- **Silent Coast**: a harbor with a polluted tide, samples, records and a coastal
  memory.
- **Toxic Tide**: the same rules with a different rhythm, silhouette, damage
  mix and projectile shapes.
- **Environmental archive**, the crash-site base return, both components shown
  fitted, and the Dawn Tower unlocked.

## Nice-to-have (not built)

- Dawn Tower: the transmitter run, the shield emitter and the Phase 3 encounter.
- The final reconstruction and the return-home ending.
- Crafting beyond the crash-site repair.
- More side records and optional memory files per chapter.

## Game flow

```
Title
  -> Briefing -> Construction -> Preflight -> Launch
  -> Crash site -> Salvage -> Bill -> Memory -> Phase 1 summary
  -> Forgotten City -> Scrap King -> Control-center archive -> Reveal
  -> Silent Coast -> Toxic Tide -> Environmental archive
  -> Crash-site base -> Phase 2 summary -> Title
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

**The two bosses are different fights, not reskins.**

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
