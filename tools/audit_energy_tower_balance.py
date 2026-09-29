"""Reproduce energy-tower resource budgets from the current GDScript constants.

This is a resource-only comparison, not combat AI or a win-rate simulation.
All towers are already active; population cost, capture income and target value
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
GAME = ROOT / "scripts/block_war/block_war.gd"
TICKS = 30
ENERGY_UNITS = 600


def constant(source: str, name: str):
    match = re.search(rf"^const {re.escape(name)}(?:\s*:[^=\n]+)?\s*:?=\s*(.+)$", source, re.M)
    if match is None:
        raise ValueError(f"Missing numeric constant: {name}")
    return ast.literal_eval(match.group(1))


def budget(profile: dict, rate: float, cap: float, initial: float,
           seconds: int, priority: list[int], window: bool = False,
           reserve_ultimate: bool = False) -> dict:
    energy = round(initial * ENERGY_UNITS)
    maximum = round(cap * ENERGY_UNITS)
    income = round(rate * ENERGY_UNITS / TICKS)
    assert abs(income * TICKS / ENERGY_UNITS - rate) < 1e-9
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
                    if energy - costs[skill] + income * until_ultimate < costs[3]:
                        continue
                if tick >= ready[skill] and energy >= costs[skill]:
                    energy -= costs[skill]
                    spent += costs[skill]
                    casts[skill] += 1
                    ready[skill] = tick + cooldowns[skill]
                    if first_cast[skill] is None:
                        first_cast[skill] = round(tick / TICKS, 3)
        overflow += max(0, energy + income - maximum)
        energy = min(maximum, energy + income)
    assert round(initial * ENERGY_UNITS) + income * seconds * TICKS == spent + overflow + energy
    return {
        "casts_qwer": casts, "first_cast_seconds_qwer": first_cast,
        "spent": spent / ENERGY_UNITS, "overflow": round(overflow / ENERGY_UNITS, 3),
        "ending_energy": round(energy / ENERGY_UNITS, 3),
    }


def audit(seconds: int = 300) -> dict:
    source = RULES.read_text(encoding="utf-8")
    game_source = GAME.read_text(encoding="utf-8")
    initial_match = re.search(r"^\s+var energy := ([0-9.]+)$", game_source, re.M)
    if initial_match is None:
        raise ValueError("Missing SkillState initial energy")
    initial = float(initial_match.group(1))
    base = constant(source, "ENERGY_REGEN")
    cap = constant(source, "ENERGY_MAX")
    bonuses = constant(source, "ENERGY_TOWER_BONUSES")
    later = constant(source, "ENERGY_TOWER_LATER_BONUS")
    profiles = {
        name: {"costs": constant(source, prefix + "COSTS"),
               "cooldowns": constant(source, prefix + "COOLDOWNS")}
        for name, prefix in [("squirrel", ""), ("rabbit", "RABBIT_"),
                             ("bear", "BEAR_"), ("frog", "FROG_")]
    }
    towers = []
    for count in range(5):
        bonus = sum(bonuses[:count]) + max(0, count - len(bonuses)) * later
        marginal = 0 if count == 0 else bonuses[count - 1] if count <= len(bonuses) else later
        towers.append({"count": count, "rate": base + bonus,
                       "extra_per_minute": round(bonus * 60, 3),
                       "marginal_per_minute": round(marginal * 60, 3),
                       "seconds_to_30_from_empty": round(30 / (base + bonus), 3),
                       "seconds_to_90_from_empty": round(90 / (base + bonus), 3)})
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
                                **budget(profile, tower["rate"], cap, initial, seconds,
                                         priority, window, reserve_ultimate)})
    return {
        "rules_sha256": hashlib.sha256(source.encode()).hexdigest(),
        "seconds": seconds, "clock_hz": TICKS, "initial_energy": initial,
        "assumptions": ["Resource-only: no combat, target value, win rates, or optimal-play claim.",
                        "Towers active at time zero; purchase costs and construction delay are excluded.",
                        "Every requested skill has a valid target in its opportunity window.",
                        "Greedy stated priority, except continuous_save_r reserves enough for R at cooldown expiry.",
                        "No capture energy; cooldown and energy cap are enforced."],
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
