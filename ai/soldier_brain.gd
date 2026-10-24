class_name SoldierBrain
extends RefCounted
## Pure decision-making: from what a soldier knows (Facts) and what kind of
## soldier it is (EnemyProfile), pick what to do now. No nodes or physics, so
## every tactic is tested headless. The Soldier carries the action out
## (paths, cover, peeking, firing) and feeds the results back as Facts.
##
## Decisions commit for AiSettings.decision_commit_time to avoid dithering,
## except urgent switches (danger, a target appearing, a rusher in range).

enum Action {
	IDLE,           ## Unaware: hold position, look around.
	INVESTIGATE,    ## Suspicious, heard something, or contact went stale: go look.
	TAKE_COVER,     ## Get to protected cover from the target.
	ENGAGE,         ## In cover: peek and fire, hide, repeat.
	SUPPRESS,       ## Pin the target's last known position while an ally flanks.
	FLANK,          ## Move to cover that sees the target's open side.
	PUSH,           ## Rusher: bound to cover closer to the target.
	CHARGE,         ## Rusher in range: go straight in, firing.
	RETREAT,        ## Hurt: fall back to cover further away.
	RELOAD,         ## Reload behind cover.
	THROW_GRENADE,  ## Flush a camping target.
}


## What the soldier knows this moment.
class Facts:
	var awareness := 0.0
	var target_visible := false
	var time_since_seen := INF
	## Flat distance to the target's last known position (m).
	var distance := INF
	var has_noise := false
	## At its chosen cover point, protected from the target.
	var in_cover := false
	## Moving to a reserved cover point as part of a bound, flank or retreat
	## (don't interrupt it with "take cover").
	var en_route := false
	## Hiding at its cover, yet the target can see its torso (it was flanked,
	## or the cover is too low).
	var cover_compromised := false
	## Hit or nearly hit very recently.
	var under_fire := false
	## The target is looking (aiming) roughly at this soldier.
	var target_facing_me := false
	## The target is reloading or pumping: a window to close in.
	var target_reloading := false
	## Current cover was picked while retreating.
	var in_retreat_cover := false
	var suppression := 0.0
	var health_fraction := 1.0
	var ammo_fraction := 1.0
	var reloading := false
	## How long the target has stayed in roughly the same place (s).
	var target_pinned_time := 0.0
	## A flank slot is free (or already ours), an ally is engaging, and we
	## haven't just flanked.
	var can_flank := false
	var ally_flanking := false
	var grenades := 0
	var grenade_allowed := false


var settings: AiSettings
var action: Action = Action.IDLE
var time_in_action := 0.0


func _init(ai_settings: AiSettings) -> void:
	settings = ai_settings


func decide(facts: Facts, profile: EnemyProfile, delta: float) -> Action:
	time_in_action += delta
	var wanted := wanted_action(facts, profile)
	if wanted != action and (time_in_action >= settings.decision_commit_time or _urgent(wanted)):
		action = wanted
		time_in_action = 0.0
	return action


## The action the situation calls for, ignoring commitment.
func wanted_action(facts: Facts, profile: EnemyProfile) -> Action:
	var in_combat := facts.awareness >= 1.0 or facts.time_since_seen < profile.lose_target_time
	if not in_combat:
		if facts.awareness >= profile.suspicious_threshold or facts.has_noise:
			return Action.INVESTIGATE
		return Action.IDLE
	if not facts.target_visible and facts.time_since_seen > profile.lose_target_time:
		return Action.INVESTIGATE  # contact went stale: hunt the last known position

	var rusher := profile.role == EnemyProfile.Role.RUSHER
	if facts.reloading or facts.ammo_fraction <= 0.0:
		return Action.RELOAD if facts.in_cover else Action.TAKE_COVER
	if facts.in_cover and not facts.target_visible and facts.ammo_fraction < settings.reload_in_cover_below:
		return Action.RELOAD
	if profile.retreat_health > 0.0 and facts.health_fraction < profile.retreat_health \
			and not facts.in_retreat_cover:
		return Action.RETREAT
	if facts.grenades > 0 and facts.grenade_allowed and facts.target_pinned_time >= profile.grenade_camp_time \
			and facts.distance >= profile.grenade_range_min and facts.distance <= profile.grenade_range_max:
		return Action.THROW_GRENADE

	if facts.cover_compromised:
		return Action.TAKE_COVER  # cover no longer protects: move, now

	if rusher:
		# Aggressive, not suicidal: close in when the target can't punish it.
		var threatened := facts.target_visible and facts.target_facing_me
		if facts.suppression > profile.suppression_tolerance or (facts.under_fire and threatened):
			return Action.ENGAGE if facts.in_cover else Action.TAKE_COVER  # pinned: hug cover
		var opening := not threatened or facts.target_reloading or facts.distance <= settings.point_blank_range
		if facts.distance <= profile.charge_range and opening:
			return Action.CHARGE
		return Action.PUSH

	if facts.en_route and action in [Action.PUSH, Action.FLANK, Action.RETREAT]:
		return action  # finish the move already under way
	if not facts.in_cover:
		return Action.TAKE_COVER
	var steady := facts.suppression < settings.flank_max_suppression and not facts.under_fire
	if facts.distance > profile.preferred_range_max and steady:
		return Action.PUSH  # out of range: bound forward cover to cover
	if facts.can_flank and facts.target_pinned_time >= profile.flank_after_pinned and steady \
			and facts.health_fraction > settings.flank_min_health and facts.distance <= profile.preferred_range_max:
		return Action.FLANK
	if not facts.target_visible and facts.ally_flanking and facts.time_since_seen < settings.suppress_memory:
		return Action.SUPPRESS
	return Action.ENGAGE


## Switches that can't wait out the commitment window.
func _urgent(wanted: Action) -> bool:
	if action == Action.IDLE or action == Action.INVESTIGATE:
		return true  # waking up to a fight is immediate
	return wanted in [Action.TAKE_COVER, Action.CHARGE, Action.RETREAT, Action.RELOAD]
