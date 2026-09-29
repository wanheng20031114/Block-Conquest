"""Six-hero resource audit, reading current rules without changing game balance.

Exact event integration of a deliberately optimistic casting budget, not a match
or win-rate simulator. Run with --output PATH; validation lives in test_hero_energy_audit.py.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
from pathlib import Path

from audit_energy_tower_balance import RULES, constant

EPS = 1e-8
COMMANDERS = [("squirrel", ""), ("rabbit", "RABBIT_"), ("bear", "BEAR_"),
              ("frog", "FROG_"), ("fox", "FOX_"), ("pig", "PIG_")]


def load_rules():
    source = RULES.read_text(encoding="utf-8")
    profiles = {hero: {field: constant(source, prefix + field.upper())
                       for field in ("names", "costs", "cooldowns", "durations")}
                for hero, prefix in COMMANDERS}
    economy = {key: constant(source, "ENERGY_" + key.upper()) for key in
               ("max", "initial", "regen", "late_regen", "acceleration_time",
                "tower_bonuses", "tower_later_bonus", "capture_reward")}
    return profiles, economy, hashlib.sha256(source.encode()).hexdigest()


def scenario(economy, *, late=False, towers=1, losses=0.0, coefficient=0.2,
             enabled=(0, 1, 2, 3), bursts=(), reserve_r=False, seconds=300.0):
    bonus = sum(economy["tower_bonuses"][:towers])
    bonus += max(0, towers - len(economy["tower_bonuses"])) * economy["tower_later_bonus"]
    return {"start_elapsed": economy["acceleration_time"] if late else 0.0,
            "initial_energy": economy["max"] if late else economy["initial"],
            "seconds": seconds, "towers": towers, "tower_rate": bonus,
            "losses_per_second": losses, "combat_coefficient": coefficient,
            "enabled": list(enabled), "bursts": list(bursts), "reserve_r": reserve_r}


def simulate(profile, economy, case, priority):
    """Half-open time window; boundary income is credited before same-time casts.

    Reserve-R anticipates only the configured continuous income, never pulses.
    Disabled skills are excluded from eligible-CD metrics, not marked cooling.
    """
    costs, cooldowns = profile["costs"], profile["cooldowns"]
    assert len(costs) == len(cooldowns) == 4
    assert all(0 < c <= economy["max"] for c in costs)
    assert all(cd > 0 for cd in cooldowns)
    assert sorted(priority) == sorted(case["enabled"])
    assert not case["reserve_r"] or (3 in priority and priority[0] == 3)
    cap = economy["max"]
    energy = case["initial_energy"]
    assert 0 <= energy <= cap and case["seconds"] > 0
    switch = economy["acceleration_time"] - case["start_elapsed"]
    combat_rate = case["losses_per_second"] * case["combat_coefficient"]
    extra = case["tower_rate"] + combat_rate
    ready = [0.0] * 4
    times = [[] for _ in range(4)]
    phases = {}
    bursts = case["bursts"]
    assert list(bursts) == sorted(bursts, key=lambda item: item[0])
    assert all(0 <= t < case["seconds"] and amount >= 0 for t, amount, _ in bursts)
    burst_index = 0
    time = 0.0

    def future_income(start, end):
        early = max(0.0, min(end, switch) - start)
        return early * economy["regen"] + (end - start - early) * economy["late_regen"] + (end - start) * extra

    while time < case["seconds"] - EPS:
        phase = "early" if time < switch - EPS else "late"
        if phase not in phases:
            phases[phase] = {"opening_energy": energy, "seconds": 0.0,
                             "income_by_source": {k: 0.0 for k in ("natural", "tower", "combat", "combat_pulse", "capture")},
                             "spent": 0.0, "overflow": 0.0, "pulse_overflow": 0.0,
                             "full_seconds": 0.0, "all_eligible_cooling_seconds": 0.0,
                             "full_and_all_eligible_cooling_seconds": 0.0,
                             "affordable_but_cooling_seconds_qwer": [0.0] * 4,
                             "casts_qwer": [0] * 4}
        metrics = phases[phase]
        while burst_index < len(bursts) and bursts[burst_index][0] <= time + EPS:
            _, amount, source = bursts[burst_index]
            metrics["income_by_source"][source] += amount
            excess = max(0.0, energy + amount - cap)
            metrics["overflow"] += excess
            metrics["pulse_overflow"] += excess
            energy = min(cap, energy + amount)
            burst_index += 1

        def reserved(skill):
            return (case["reserve_r"] and skill != 3 and
                    energy - costs[skill] + future_income(time, max(time, ready[3])) < costs[3] - EPS)

        for skill in priority:
            if ready[skill] <= time + EPS and energy >= costs[skill] - EPS and not reserved(skill):
                energy = max(0.0, energy - costs[skill])
                metrics["spent"] += costs[skill]
                metrics["casts_qwer"][skill] += 1
                times[skill].append(time)
                ready[skill] = time + cooldowns[skill]
        rate = economy["regen" if phase == "early" else "late_regen"] + extra
        assert rate > 0
        next_time = case["seconds"]
        if switch > time + EPS:
            next_time = min(next_time, switch)
        if burst_index < len(bursts):
            next_time = min(next_time, bursts[burst_index][0])
        for skill in priority:
            if ready[skill] > time + EPS:
                next_time = min(next_time, ready[skill])
            elif not reserved(skill):
                assert energy < costs[skill] - EPS
                next_time = min(next_time, time + (costs[skill] - energy) / rate)
        dt = next_time - time
        assert dt > EPS, (time, next_time, energy, ready)
        full = max(0.0, dt - max(0.0, cap - energy) / rate)
        metrics["seconds"] += dt
        metrics["full_seconds"] += full
        if priority and all(ready[skill] > time + EPS for skill in priority):
            metrics["all_eligible_cooling_seconds"] += dt
            metrics["full_and_all_eligible_cooling_seconds"] += full
        for skill in priority:
            if ready[skill] > time + EPS:
                metrics["affordable_but_cooling_seconds_qwer"][skill] += max(0.0, dt - max(0.0, costs[skill] - energy) / rate)
        metrics["income_by_source"]["natural"] += (rate - extra) * dt
        metrics["income_by_source"]["tower"] += case["tower_rate"] * dt
        metrics["income_by_source"]["combat"] += combat_rate * dt
        metrics["overflow"] += max(0.0, energy + rate * dt - cap)
        energy = min(cap, energy + rate * dt)
        metrics["ending_energy"] = energy
        time = next_time

    for metrics in phases.values():
        metrics["income"] = sum(metrics["income_by_source"].values())
        residual = metrics["opening_energy"] + metrics["income"] - metrics["spent"] - metrics["overflow"] - metrics["ending_energy"]
        assert abs(residual) < 1e-6, residual
    result = {"priority": list(priority), "phases": phases, "ending_energy": energy,
              "casts_qwer": [len(row) for row in times],
              "first_cast_qwer": [row[0] if row else None for row in times],
              "mean_cast_interval_qwer": [(row[-1] - row[0]) / (len(row) - 1) if len(row) > 1 else None for row in times]}
    for key in ("income", "spent", "overflow", "pulse_overflow", "full_seconds", "all_eligible_cooling_seconds", "full_and_all_eligible_cooling_seconds"):
        result[key] = sum(p[key] for p in phases.values())
    return result


def compare(profile, economy, case):
    orders = list(itertools.permutations(case["enabled"]))
    if case["reserve_r"]:
        orders = [order for order in orders if order[0] == 3]
    trials = [simulate(profile, economy, case, order) for order in orders]
    # This only optimizes among fixed greedy orders. It is not optimal play.
    best = min(trials, key=lambda row: (round(row["overflow"], 8), -row["spent"], row["priority"]))
    return {"case": case, "priority_count": len(trials), "best_fixed_priority": best,
            "overflow_range": [min(r["overflow"] for r in trials), max(r["overflow"] for r in trials)],
            "casts_range_qwer": [[min(r["casts_qwer"][i] for r in trials), max(r["casts_qwer"][i] for r in trials)] for i in range(4)]}


def audit():
    profiles, economy, sha = load_rules()
    thresholds, continuous, situational, pulses, captures, reserve, candidates = [], [], [], [], [], [], []
    for hero, profile in profiles.items():
        ceiling = sum(c / cd for c, cd in zip(profile["costs"], profile["cooldowns"]))
        profile["spending_ceiling"] = ceiling
        for late, towers in itertools.product((False, True), range(3)):
            passive = scenario(economy, late=late, towers=towers)["tower_rate"] + economy["late_regen" if late else "regen"]
            thresholds.append({"hero": hero, "late": late, "towers": towers, "passive": passive,
                               "break_even_losses_per_second": {str(k): max(0.0, (ceiling - passive) / k) for k in (0.2, 0.15, 0.1)}})
            inputs = [(0, 0.2)] + list(itertools.product((2, 5, 10), (0.2, 0.15, 0.1)))
            for losses, coefficient in inputs:
                # A fox held at five stars cannot legally transfer more morale.
                enabled = (0, 2, 3) if hero == "fox" and coefficient == 0.1 else (0, 1, 2, 3)
                continuous.append({"hero": hero, **compare(profile, economy, scenario(economy, late=late, towers=towers, losses=losses, coefficient=coefficient, enabled=enabled))})
        for late, period in itertools.product((False, True), (12, 30)):
            # Same 5 losses/s mean, paid in 60- or 150-casualty pulses.
            bursts = [(period / 2 + period * i, period * 5 * 0.2, "combat_pulse")
                      for i in range(25) if period / 2 + period * i < 300]
            pulses.append({"hero": hero, "pulse_period": period, **compare(profile, economy, scenario(economy, late=late, bursts=bursts))})
        rewards = [(15.0 + 30 * i, economy["capture_reward"], "capture") for i in range(10)]
        captures.append({"hero": hero, **compare(profile, economy, scenario(economy, late=True, losses=2, bursts=rewards))})
        for losses in (0, 2, 5):
            reserve.append({"hero": hero, **compare(profile, economy, scenario(economy, losses=losses, reserve_r=True))})

    subsets = [("squirrel", "no_useful_shield", (0, 1, 3)),
               ("rabbit", "no_useful_recall", (0, 1, 3)),
               ("bear", "no_construction", (1, 2, 3)),
               ("frog", "no_useful_float", (0, 2, 3)),
               ("fox", "no_morale_transfer", (0, 2, 3)),
               ("fox", "no_morale_or_refuge", (0, 2)),
               ("fox", "no_morale_refuge_or_marches", (0,)),
               ("pig", "no_useful_formation", (0, 1, 3))]
    for hero, reason, enabled in subsets:
        for towers, losses, coefficient in itertools.product(range(3), (0, 2), (0.2, 0.1)):
            case = scenario(economy, late=True, towers=towers, losses=losses, coefficient=coefficient, enabled=enabled)
            situational.append({"hero": hero, "reason": reason,
                                "spending_ceiling": sum(profiles[hero]["costs"][i] / profiles[hero]["cooldowns"][i] for i in enabled),
                                **compare(profiles[hero], economy, case)})
    for hero, skill, value, subset in [("fox", 0, 30.0, (0, 2, 3)), ("fox", 0, 25.0, (0, 2, 3)),
                                      ("bear", 1, 25.0, (1, 2, 3)), ("pig", 2, 30.0, (0, 1, 2, 3))]:
        for enabled in sorted(set(((0, 1, 2, 3), subset))):
            for losses in (0, 2, 5):
                case = scenario(economy, late=True, losses=losses, enabled=enabled)
                profile = {**profiles[hero], "cooldowns": profiles[hero]["cooldowns"].copy()}
                profile["cooldowns"][skill] = value
                candidates.append({"hero": hero, "changed_skill": skill,
                                   "old_cd": profiles[hero]["cooldowns"][skill], "candidate_cd": value,
                                   "baseline": compare(profiles[hero], economy, case),
                                   "candidate": compare(profile, economy, case)})
    return {"rules_sha256": sha, "economy": economy, "profiles": profiles,
            "assumptions": ["Synthetic budgets, not real casualty rates, win rates, or optimal-play evidence.",
                            "Opening: elapsed 0, energy 20, observe [0,300). Late: elapsed 100, energy 100, observe [100,400).",
                            "Enabled skills always have a legal worthwhile target; buffs/ready orders are consumed appropriately.",
                            "All 24 fixed priorities compared (fewer for subsets); small-skill greedy policies can starve R.",
                            "Reserve-R anticipates continuous scenario income, excluding burst income; this is a synthetic policy.",
                            "Towers active throughout; constant morale/loss rates imposed externally, not coupled to skill effects.",
                            "For fox at coefficient 0.1 (five stars), W is disabled; four-skill thresholds remain an optimistic capacity bound.",
                            "No capture rewards in standard cases. Pulses are explicit and processed before same-time casts.",
                            "Affordable-but-cooling metrics overlap across skills; full time excludes instantaneous pulse overflow.",
                            "Only natural regeneration doubles; no game files or balance constants are changed."],
            "thresholds": thresholds, "continuous": continuous, "situational": situational,
            "pulses": pulses, "captures": captures, "reserve_r": reserve, "candidates": candidates}


def rounded(value):
    if isinstance(value, float): return round(value, 6)
    if isinstance(value, dict): return {k: rounded(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)): return [rounded(v) for v in value]
    return value


def report_json(data):
    # One complete scenario per line keeps regenerated data diffs reviewable.
    fields = []
    for key, value in data.items():
        if isinstance(value, list) and value and isinstance(value[0], dict):
            payload = "[\n    " + ",\n    ".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) for row in value) + "\n  ]"
        else:
            payload = json.dumps(value, ensure_ascii=False, indent=2).replace("\n", "\n  ")
        fields.append("  " + json.dumps(key) + ": " + payload)
    return "{\n" + ",\n".join(fields) + "\n}\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = rounded(audit())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(report_json(data), encoding="utf-8", newline="\n")
    print(json.dumps({"rules_sha256": data["rules_sha256"], "cases": {key: len(data[key]) for key in
                     ("continuous", "situational", "pulses", "captures", "reserve_r", "candidates")}}))


if __name__ == "__main__":
    main()
