"""Reproduce energy-tower resource budgets from the current GDScript constants.

This is a resource-only comparison, not combat AI or a win-rate simulation.
All towers are already active; population cost, combat/capture income and target value
are deliberately excluded. The 30 Hz clock matches the network rule clock.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT / "scripts/block_war/war_skill_rules.gd"
TICKS = 30
ENERGY_UNITS = 600


def constant(source: str, name: str):
    match = re.search(rf"^const {re.escape(name)}(?:\s*:[^=\n]+)?\s*:?=\s*(.+)$", source, re.M)
    if match is None:
        raise ValueError(f"Missing numeric constant: {name}")
    return ast.literal_eval(match.group(1))


def budget(profile: dict, early_rate: float, late_rate: float, acceleration: float,
           cap: float, initial: float,
           seconds: int, priority: list[int], window: bool = False,
           reserve_ultimate: bool = False) -> dict:
    energy = round(initial * ENERGY_UNITS)
    maximum = round(cap * ENERGY_UNITS)
    early_income = round(early_rate * ENERGY_UNITS / TICKS)
    late_income = round(late_rate * ENERGY_UNITS / TICKS)
    acceleration_tick = round(acceleration * TICKS)
    assert abs(early_income * TICKS / ENERGY_UNITS - early_rate) < 1e-9
    assert abs(late_income * TICKS / ENERGY_UNITS - late_rate) < 1e-9
    assert acceleration_tick / TICKS == acceleration

    def income_between(start: int, end: int) -> int:
        early_ticks = max(0, min(end, acceleration_tick) - start)
        return early_ticks * early_income + (end - start - early_ticks) * late_income
    costs = [round(value * ENERGY_UNITS) for value in profile["costs"]]
    cooldowns = [round(value * TICKS) for value in profile["cooldowns"]]
    ready = [0] * 4
    casts = [0] * 4
    first_cast = [None] * 4
    spent = 0
    overflow = 0
    # Half-open [0, seconds): a cast at the endpoint belongs to the next window.
    for tick in range(seconds * TICKS):
        if not window or tick % (60 * TICKS) < 20 * TICKS:
            for skill in priority:
                if reserve_ultimate and skill != 3:
                    until_ultimate = max(0, ready[3] - tick)
                    if energy - costs[skill] + income_between(tick, tick + until_ultimate) < costs[3]:
                        continue
                if tick >= ready[skill] and energy >= costs[skill]:
                    energy -= costs[skill]
                    spent += costs[skill]
                    casts[skill] += 1
                    ready[skill] = tick + cooldowns[skill]
                    if first_cast[skill] is None:
                        first_cast[skill] = round(tick / TICKS, 3)
        income = income_between(tick, tick + 1)
        overflow += max(0, energy + income - maximum)
        energy = min(maximum, energy + income)
    total_income = income_between(0, seconds * TICKS)
    assert round(initial * ENERGY_UNITS) + total_income == spent + overflow + energy
    return {
        "casts_qwer": casts, "first_cast_seconds_qwer": first_cast,
        "income": total_income / ENERGY_UNITS,
        "spent": spent / ENERGY_UNITS, "overflow": round(overflow / ENERGY_UNITS, 3),
        "ending_energy": round(energy / ENERGY_UNITS, 3),
    }


def audit(seconds: int = 300) -> dict:
    source = RULES.read_text(encoding="utf-8")
    initial = constant(source, "ENERGY_INITIAL")
    base = constant(source, "ENERGY_REGEN")
    late_base = constant(source, "ENERGY_LATE_REGEN")
    acceleration = constant(source, "ENERGY_ACCELERATION_TIME")
    cap = constant(source, "ENERGY_MAX")
    bonuses = constant(source, "ENERGY_TOWER_BONUSES")
    later = constant(source, "ENERGY_TOWER_LATER_BONUS")
    profiles = {
        name: {"costs": constant(source, prefix + "COSTS"),
               "cooldowns": constant(source, prefix + "COOLDOWNS")}
        for name, prefix in [("squirrel", ""), ("rabbit", "RABBIT_"),
                             ("bear", "BEAR_"), ("frog", "FROG_"), ("fox", "FOX_")]
    }
    towers = []
    for count in range(5):
        bonus = sum(bonuses[:count]) + max(0, count - len(bonuses)) * later
        marginal = 0 if count == 0 else bonuses[count - 1] if count <= len(bonuses) else later
        towers.append({"count": count, "early_rate": base + bonus, "late_rate": late_base + bonus,
                       "extra_per_minute": round(bonus * 60, 3),
                       "marginal_per_minute": round(marginal * 60, 3),
                       "early_seconds_to_30_from_empty": round(30 / (base + bonus), 3),
                       "early_seconds_to_90_from_empty": round(90 / (base + bonus), 3),
                       "late_seconds_to_30_from_empty": round(30 / (late_base + bonus), 3),
                       "late_seconds_to_90_from_empty": round(90 / (late_base + bonus), 3)})
    scenarios = [("q_only", [0], False, False), ("r_only", [3], False, False),
                 ("continuous_save_r", [3, 0, 1, 2], False, True),
                 ("continuous_qwer", [0, 1, 2, 3], False, False),
                 ("20_seconds_per_minute_rqwe", [3, 0, 1, 2], True, False)]
    results = []
    for commander, profile in profiles.items():
        profile["all_four_on_cooldown_energy_per_second"] = round(
            sum(cost / cooldown for cost, cooldown in zip(profile["costs"], profile["cooldowns"])), 6)
        for scenario, priority, window, reserve_ultimate in scenarios:
            for tower in towers:
                results.append({"commander": commander, "scenario": scenario,
                                "towers": tower["count"],
                                **budget(profile, tower["early_rate"], tower["late_rate"], acceleration, cap, initial, seconds,
                                         priority, window, reserve_ultimate)})
    return {
        "rules_sha256": hashlib.sha256(source.encode()).hexdigest(),
        "seconds": seconds, "clock_hz": TICKS, "initial_energy": initial,
        "natural_regen": {"before_acceleration": base, "after_acceleration": late_base,
                          "acceleration_seconds": acceleration},
        "assumptions": ["Resource-only: no combat, target value, win rates, or optimal-play claim.",
                        "Towers active at time zero; purchase costs and construction delay are excluded.",
                        "Every requested skill has a valid target in its opportunity window.",
                        "Greedy stated priority, except continuous_save_r reserves enough for R at cooldown expiry.",
                        "Natural regeneration switches at the configured match time; tower bonuses stay constant.",
                        "No combat or capture energy; cooldown and energy cap are enforced."],
        "profiles": profiles, "tower_rates": towers, "results": results,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write the complete reproducible JSON report")
    args = parser.parse_args()
    result = audit()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"tower_rates": result["tower_rates"], "profiles": result["profiles"]},
                     ensure_ascii=False))
    print("commander scenario towers casts_qwer spent overflow ending_energy")
    for row in result["results"]:
        if row["towers"] in [0, 1, 2]:
            print(row["commander"], row["scenario"], row["towers"], row["casts_qwer"],
                  row["spent"], row["overflow"], row["ending_energy"])


if __name__ == "__main__":
    main()
