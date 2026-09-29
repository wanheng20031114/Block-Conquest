"""Audit cooldown spending ceilings and energy overflow without changing rules.

Synthetic scenarios start after 100 match seconds, with 100 energy and all skills
ready. Targets are always valid for the enabled skills. Loss rates and morale
tiers are imposed inputs, not observed match statistics or an optimal-play claim.
"""
from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path

from audit_energy_tower_balance import RULES, constant

EPSILON = 1e-8
COMMANDERS = [("squirrel", ""), ("rabbit", "RABBIT_"), ("bear", "BEAR_"),
              ("frog", "FROG_"), ("fox", "FOX_")]


def simulate(costs, cooldowns, rate, priority, seconds=300.0, bursts=()):
    """Exact event integration for a fixed greedy priority, with conserved energy."""
    energy = 100.0
    ready = [0.0] * 4
    casts = [0] * 4
    time = spent = overflow = income = 0.0
    full_seconds = cooling_seconds = high_cooling_seconds = 0.0
    burst_index = 0
    while time < seconds - EPSILON:
        while burst_index < len(bursts) and bursts[burst_index][0] <= time + EPSILON:
            amount = bursts[burst_index][1]
            income += amount
            overflow += max(0.0, energy + amount - 100.0)
            energy = min(100.0, energy + amount)
            burst_index += 1
        for skill in priority:
            if ready[skill] <= time + EPSILON and energy + EPSILON >= costs[skill]:
                energy = max(0.0, energy - costs[skill])
                spent += costs[skill]
                casts[skill] += 1
                ready[skill] = time + cooldowns[skill]
        next_time = seconds
        if burst_index < len(bursts):
            next_time = min(next_time, bursts[burst_index][0])
        for skill in priority:
            if ready[skill] > time + EPSILON:
                next_time = min(next_time, ready[skill])
            else:
                assert energy < costs[skill]
                next_time = min(next_time, time + (costs[skill] - energy) / rate)
        delta = next_time - time
        assert delta > 0.0
        full_time = max(0.0, delta - max(0.0, 100.0 - energy) / rate)
        full_seconds += full_time
        if all(deadline > time + EPSILON for deadline in ready):
            cooling_seconds += delta
            high_cooling_seconds += max(0.0, delta - max(0.0, 80.0 - energy) / rate)
        earned = rate * delta
        income += earned
        overflow += max(0.0, energy + earned - 100.0)
        energy = min(100.0, energy + earned)
        time = next_time
    assert abs(100.0 + income - spent - overflow - energy) < 1e-5
    return {"priority": list(priority), "casts": casts, "income": round(income, 6),
            "spent": spent, "overflow": round(overflow, 6), "ending_energy": round(energy, 6),
            "full_seconds": round(full_seconds, 6),
            "all_four_cooling_seconds": round(cooling_seconds, 6),
            "energy_at_least_80_all_four_cooling_seconds": round(high_cooling_seconds, 6)}


def compare_priorities(profile, rate, enabled=(0, 1, 2, 3), bursts=()):
    trials = [simulate(profile["costs"], profile["cooldowns"], rate, order, bursts=bursts)
              for order in itertools.permutations(enabled)]
    best = min(trials, key=lambda row: (row["overflow"], -row["spent"]))
    return {"best_of_fixed_priorities": best,
            "fixed_priority_count": len(trials),
            "overflow_range": [min(row["overflow"] for row in trials), max(row["overflow"] for row in trials)],
            "high_energy_all_four_cooling_range_seconds": [
                min(row["energy_at_least_80_all_four_cooling_seconds"] for row in trials),
                max(row["energy_at_least_80_all_four_cooling_seconds"] for row in trials)]}


def audit():
    source = RULES.read_text(encoding="utf-8")
    profiles = {name: {"costs": constant(source, prefix + "COSTS"),
                       "cooldowns": constant(source, prefix + "COOLDOWNS")}
                for name, prefix in COMMANDERS}
    late = constant(source, "ENERGY_LATE_REGEN")
    bonuses = constant(source, "ENERGY_TOWER_BONUSES")
    thresholds, continuous, situational, burst_results = [], [], [], []
    for name, profile in profiles.items():
        ceiling = sum(cost / cooldown for cost, cooldown in zip(profile["costs"], profile["cooldowns"]))
        profile["all_skill_cost_sum"] = sum(profile["costs"])
        profile["maximum_spending_per_second"] = ceiling
        for towers in range(3):
            natural = late + sum(bonuses[:towers])
            thresholds.append({"commander": name, "towers": towers, "passive_rate": natural,
                               "losses_per_second_to_exceed_ceiling": {
                                   str(coefficient): max(0.0, (ceiling - natural) / coefficient)
                                   for coefficient in (0.2, 0.15, 0.1)}})
            for coefficient in (0.2, 0.15, 0.1):
                for losses in (0, 2, 5, 10):
                    rate = natural + losses * coefficient
                    continuous.append({"commander": name, "towers": towers, "coefficient": coefficient,
                                       "losses_per_second": losses, "income_per_second": rate,
                                       **compare_priorities(profile, rate)})
        # Same 5 losses/second average: 60 casualties every 12 seconds, at 0.2 each.
        bursts = [(6.0 + 12.0 * i, 12.0) for i in range(25)]
        burst_results.append({"commander": name, "towers": 1, "coefficient": 0.2,
                              "casualties_per_pulse": 60, "pulse_seconds": 12,
                              **compare_priorities(profile, late + bonuses[0], bursts=bursts)})
    for name, enabled, reason in [("bear", (1, 2, 3), "no_construction_for_q"),
                                   ("fox", (0, 2, 3), "w_has_no_transferable_morale"),
                                   ("fox", (0, 2), "w_unavailable_and_r_has_no_refuge")]:
        profile = profiles[name]
        ceiling = sum(profile["costs"][i] / profile["cooldowns"][i] for i in enabled)
        for towers in range(3):
            rate = late + sum(bonuses[:towers])
            situational.append({"commander": name, "reason": reason, "enabled": enabled,
                                "towers": towers, "maximum_spending_per_second": ceiling,
                                "income_per_second": rate, **compare_priorities(profile, rate, enabled)})
    return {"assumptions": [
        "Synthetic resource audit; runtime combat, target value and win rates are not modeled.",
        "Start after 100 match seconds at 100 energy; all cooldowns initially ready; observe 300 seconds.",
        "All enabled skills always have valid targets, are cast immediately when ready and affordable.",
        "Compare all fixed skill priorities; best fixed priority is not a globally optimal policy.",
        "Casualty rates/morale are fixed scenario inputs; tower capture rewards are excluded.",
        "Overflow differs from all-four-on-cooldown time; disabled situational skills remain ready."],
        "profiles": profiles, "thresholds": thresholds, "continuous": continuous,
        "bursts": burst_results, "situational": situational}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"profiles": result["profiles"], "continuous_scenarios": len(result["continuous"]),
                      "burst_scenarios": len(result["bursts"]), "situational_scenarios": len(result["situational"])}))
    for row in result["continuous"]:
        if row["towers"] == 1 and row["coefficient"] == 0.2:
            print(row["commander"], row["losses_per_second"], row["income_per_second"],
                  json.dumps(row["best_of_fixed_priorities"]))


if __name__ == "__main__":
    main()
