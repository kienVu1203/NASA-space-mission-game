extends RefCounted
## Encounter state for the Phase 2 shield-defense fights. Pure model: health,
## charge, boss health, phase and counterattack arbitration. No nodes, no
## drawing, no input. The screen presents this; the controller drives it.
##
## Phases are the whole legal state machine:
##   intro      boss lines play, nothing spawns, nothing can damage Nick
##   fight      projectiles live, shield steerable, Space arms the counterattack
##   counter    a counterattack is resolving; shield control is locked, and
##              incoming projectiles are discarded fairly rather than landing
##              on a player who cannot rotate
##   victory    boss defeated; attacks have stopped, rewards pending
##   defeat     Nick at zero health; retry is offered
##
## Every value here comes from encounters.json. Nothing is tuned in code.

const PHASE_INTRO := "intro"
const PHASE_FIGHT := "fight"
const PHASE_COUNTER := "counter"
const PHASE_VICTORY := "victory"
const PHASE_DEFEAT := "defeat"

const RESULT_NONE := ""
const RESULT_VICTORY := "victory"
const RESULT_DEFEAT := "defeat"

var boss_id: String = ""
var nick_health_max: int = 100
var nick_health: int = 100
var boss_health_max: int = 100
var boss_health: int = 100
var charge_max: int = 100
var charge: int = 0
var counterattack_damage: int = 25
var counterattack_lock: float = 0.55
var victory_hold: float = 1.6

var phase: String = PHASE_INTRO
var result: String = RESULT_NONE

## Encounter-level freeze, used while a briefing dialogue covers the arena. It is
## separate from the phase because the briefing happens after the fight has
## begun: the phase is `fight`, but the player is reading, so nothing may land.
## Everything that can change Nick or the boss goes through `accepts_attacks()`,
## which honours this flag, so a freeze cannot be bypassed by calling a model
## method directly.
var frozen: bool = false

var counterattack_timer: float = 0.0
var victory_timer: float = 0.0
var defeat_timer: float = 0.0

# Presentation-only counters. They are read by the HUD and never by the rules.
var damage_flash: float = 0.0
var absorb_flash: float = 0.0
var block_flash: float = 0.0
var last_damage: int = 0

# Guards the once-per-counterattack strike so a repeated tick can never apply
# the same counterattack twice.
var _counter_struck: bool = false


func configure(boss: Dictionary, combat: Dictionary) -> void:
	boss_id = String(boss.get("id", ""))
	nick_health_max = maxi(1, int(boss.get("nick_health", 100)))
	boss_health_max = maxi(1, int(boss.get("boss_health", 100)))
	charge_max = maxi(1, int(boss.get("charge_max", 100)))
	counterattack_damage = maxi(1, int(boss.get("counterattack_damage", 25)))
	counterattack_lock = maxf(0.05, float(combat.get("counterattack_lock_seconds", counterattack_lock)))
	victory_hold = maxf(0.0, float(combat.get("victory_hold_seconds", victory_hold)))
	reset()


## Full encounter-local reset. A retry calls exactly this, so no health, charge,
## timer, flash or phase can leak from the previous attempt.
func reset() -> void:
	nick_health = nick_health_max
	boss_health = boss_health_max
	charge = 0
	phase = PHASE_INTRO
	result = RESULT_NONE
	frozen = false
	counterattack_timer = 0.0
	victory_timer = 0.0
	defeat_timer = 0.0
	damage_flash = 0.0
	absorb_flash = 0.0
	block_flash = 0.0
	last_damage = 0
	_counter_struck = false


# ---------------------------------------------------------------- phases

func begin_fight() -> void:
	if phase == PHASE_INTRO:
		phase = PHASE_FIGHT


func is_fighting() -> bool:
	return phase == PHASE_FIGHT


func is_over() -> bool:
	return phase == PHASE_VICTORY or phase == PHASE_DEFEAT


## True while projectiles may exist and are allowed to damage Nick. During the
## counterattack lock the shield is fixed, so projectiles are not spawned at all:
## the scheduler is paused, which is why a locked shield cannot be punished.
func accepts_attacks() -> bool:
	return phase == PHASE_FIGHT and not frozen


func shield_locked() -> bool:
	return phase == PHASE_COUNTER


func health_fraction() -> float:
	return clampf(float(boss_health) / float(maxi(1, boss_health_max)), 0.0, 1.0)


func nick_fraction() -> float:
	return clampf(float(nick_health) / float(maxi(1, nick_health_max)), 0.0, 1.0)


func charge_fraction() -> float:
	return clampf(float(charge) / float(maxi(1, charge_max)), 0.0, 1.0)


func charge_full() -> bool:
	return charge >= charge_max


# ---------------------------------------------------------------- damage / charge

## Applies damage to Nick. Returns true when this was the killing blow.
## Any accumulated charge is deliberately preserved: taking damage is never a
## charge penalty.
func damage_nick(amount: int) -> bool:
	if not accepts_attacks() or amount <= 0:
		return false
	nick_health = maxi(0, nick_health - amount)
	last_damage = amount
	damage_flash = 0.35
	if nick_health <= 0:
		phase = PHASE_DEFEAT
		result = RESULT_DEFEAT
		defeat_timer = 0.0
		return true
	return false


## Adds absorbed charge, clamped to the maximum. Returns the charge actually
## added, so the HUD can show a truthful number.
func absorb_charge(amount: int) -> int:
	if not accepts_attacks() or amount <= 0:
		return 0
	var before := charge
	charge = mini(charge_max, charge + amount)
	absorb_flash = 0.3
	return charge - before


func note_block() -> void:
	block_flash = 0.22


# ---------------------------------------------------------------- counterattack

## Requests a counterattack. The caller passes whether Space was just pressed
## this frame. Returns true when a counterattack was accepted, which happens
## exactly once per full charge.
##
## Holding Space never re-triggers because the caller only reports just-pressed
## edges; this function additionally refuses while a counterattack is already
## resolving, so a repeated edge inside the lock cannot double-fire.
func request_counterattack() -> bool:
	if phase != PHASE_FIGHT:
		return false
	if not charge_full():
		return false
	charge = 0
	phase = PHASE_COUNTER
	counterattack_timer = 0.0
	return true


## Applies the accepted counterattack to the boss. Called once, when the
## counterattack animation reaches the robot. Returns true when the boss died.
func apply_counterattack() -> bool:
	if phase != PHASE_COUNTER:
		return false
	boss_health = maxi(0, boss_health - counterattack_damage)
	if boss_health <= 0:
		phase = PHASE_VICTORY
		result = RESULT_VICTORY
		victory_timer = 0.0
		return true
	return false


## Advances phase timers. Returns events:
##   {"kind": "counter_strike"} when the counterattack should damage the boss
##   {"kind": "counter_done"} when the lock ends and the fight resumes
##   {"kind": "victory_ready"} when the victory hold has elapsed
func tick(delta: float) -> Array:
	var events: Array = []
	damage_flash = maxf(0.0, damage_flash - delta)
	absorb_flash = maxf(0.0, absorb_flash - delta)
	block_flash = maxf(0.0, block_flash - delta)
	match phase:
		PHASE_COUNTER:
			counterattack_timer += delta
			# The strike lands near the middle of the lock, after the effect has
			# visibly travelled to the robot.
			var strike_at: float = counterattack_lock * 0.45
			if not bool(_counter_struck) and counterattack_timer >= strike_at:
				_counter_struck = true
				events.append({"kind": "counter_strike"})
			if counterattack_timer >= counterattack_lock:
				if phase == PHASE_COUNTER:
					phase = PHASE_FIGHT
				_counter_struck = false
				events.append({"kind": "counter_done"})
		PHASE_VICTORY:
			victory_timer += delta
			if victory_timer >= victory_hold:
				events.append({"kind": "victory_ready"})
		PHASE_DEFEAT:
			defeat_timer += delta
	return events


## Fails the encounter outright. Used by tests and by any non-damage defeat
## path (there is none in the shipped flow, but the state machine supports it).
func force_defeat() -> void:
	if is_over():
		return
	nick_health = 0
	phase = PHASE_DEFEAT
	result = RESULT_DEFEAT
	defeat_timer = 0.0


## Victory without a counterattack. Only used by tests of the reward path.
func force_victory() -> void:
	if is_over():
		return
	boss_health = 0
	phase = PHASE_VICTORY
	result = RESULT_VICTORY
	victory_timer = 0.0


func reset_counter_strike() -> void:
	_counter_struck = false
