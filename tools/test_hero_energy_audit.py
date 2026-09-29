"""Independent budget checks: python -m unittest discover -s tools -p test_hero_energy_audit.py."""
import unittest

from audit_hero_energy_balance import audit, load_rules, scenario, simulate
from audit_skill_cooldown_balance import simulate as old_simulate


def tick_reference(profile, economy, case, priority, hz=420):
    """Small fixed-step oracle, independent of the production event scheduler.

    Fixtures use rates whose affordability times align with this grid. This is
    not used as a general exact reference for arbitrary floating-point inputs.
    """
    energy, spent, overflow = case["initial_energy"], 0.0, 0.0
    deadlines, casts = [0] * 4, [0] * 4
    burst_index = 0
    threshold = round((economy["acceleration_time"] - case["start_elapsed"]) * hz)
    extra = case["tower_rate"] + case["losses_per_second"] * case["combat_coefficient"]
    for tick in range(round(case["seconds"] * hz)):
        while burst_index < len(case["bursts"]) and round(case["bursts"][burst_index][0] * hz) == tick:
            amount = case["bursts"][burst_index][1]
            overflow += max(0.0, energy + amount - economy["max"])
            energy = min(economy["max"], energy + amount)
            burst_index += 1
        for i in priority:
            cost = profile["costs"][i]
            if tick < deadlines[i] or energy < cost - 1e-7:
                continue
            if case["reserve_r"] and i != 3:
                until = max(tick, deadlines[3])
                early_ticks = max(0, min(until, threshold) - tick)
                expected = ((economy["regen"] + extra) * early_ticks +
                            (economy["late_regen"] + extra) * (until - tick - early_ticks)) / hz
                if energy - cost + expected < profile["costs"][3] - 1e-7:
                    continue
            energy -= cost
            spent += cost
            casts[i] += 1
            deadlines[i] = tick + round(profile["cooldowns"][i] * hz)
        income = (economy["regen" if tick < threshold else "late_regen"] + extra) / hz
        overflow += max(0.0, energy + income - economy["max"])
        energy = min(economy["max"], energy + income)
    return {"ending_energy": energy, "spent": spent, "overflow": overflow, "casts_qwer": casts}


class BudgetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profiles, cls.economy, _ = load_rules()

    def test_all_six_and_closed_form(self):
        self.assertEqual(set(self.profiles), {"squirrel", "rabbit", "bear", "frog", "fox", "pig"})
        profile = {"costs": [25.0] * 4, "cooldowns": [40.0] * 4}
        for rate, expected_overflow, expected_full in ((2.5, 0, 0), (5.0, 700, 140)):
            case = scenario(self.economy, late=True, towers=0, losses=(rate - 2) / 0.2)
            result = simulate(profile, self.economy, case, (0, 1, 2, 3))
            self.assertEqual(result["casts_qwer"], [8] * 4)
            self.assertAlmostEqual(result["overflow"], expected_overflow)
            self.assertAlmostEqual(result["full_seconds"], expected_full)

    def test_cross_boundary_without_spending(self):
        case = scenario(self.economy, towers=0, enabled=(), seconds=120)
        case["initial_energy"] = 0
        result = simulate(self.profiles["fox"], self.economy, case, ())
        self.assertAlmostEqual(result["phases"]["early"]["income"], 100)
        self.assertAlmostEqual(result["phases"]["late"]["income"], 40)
        self.assertAlmostEqual(result["overflow"], 40)
        self.assertAlmostEqual(result["all_eligible_cooling_seconds"], 0)

    def test_subset_measures_only_eligible_skills(self):
        case = scenario(self.economy, late=True, enabled=(0,), towers=0, seconds=35)
        result = simulate(self.profiles["fox"], self.economy, case, (0,))
        self.assertEqual(result["casts_qwer"], [1, 0, 0, 0])
        self.assertAlmostEqual(result["full_seconds"], 22.5)
        self.assertAlmostEqual(result["full_and_all_eligible_cooling_seconds"], 22.5)

    def test_instantaneous_pulse_can_overflow_without_full_wait(self):
        case = scenario(self.economy, late=True, enabled=(0,), seconds=1, bursts=[(0, 10, "capture")])
        result = simulate(self.profiles["fox"], self.economy, case, (0,))
        self.assertEqual(result["pulse_overflow"], 10)
        self.assertEqual(result["full_seconds"], 0)

    def test_boundary_pulse_belongs_to_late_phase(self):
        case = scenario(self.economy, towers=0, enabled=(), seconds=101, bursts=[(100, 10, "capture")])
        result = simulate(self.profiles["fox"], self.economy, case, ())
        self.assertEqual(result["phases"]["early"]["income_by_source"]["capture"], 0)
        self.assertEqual(result["phases"]["late"]["income_by_source"]["capture"], 10)

    def test_old_constant_rate_solver_agrees(self):
        for hero, profile in self.profiles.items():
            for rate in (2, 2.5, 2.9, 3.5, 3.75, 4.5):
                with self.subTest(hero=hero, rate=rate):
                    case = scenario(self.economy, late=True, towers=0, losses=(rate - 2) / 0.2)
                    result = simulate(profile, self.economy, case, (0, 1, 2, 3))
                    previous = old_simulate(profile["costs"], profile["cooldowns"], rate, (0, 1, 2, 3))
                    for key in ("income", "spent", "overflow", "ending_energy", "full_seconds"):
                        self.assertAlmostEqual(result[key], previous[key], places=5)
                    self.assertEqual(result["casts_qwer"], previous["casts"])

    def test_independent_fixed_step_across_boundary_and_reservation(self):
        for hero, profile in self.profiles.items():
            for reserve in (False, True):
                with self.subTest(hero=hero, reserve=reserve):
                    case = scenario(self.economy, reserve_r=reserve)
                    order = (3, 0, 1, 2) if reserve else (0, 1, 2, 3)
                    result = simulate(profile, self.economy, case, order)
                    reference = tick_reference(profile, self.economy, case, order)
                    self.assertEqual(result["casts_qwer"], reference["casts_qwer"])
                    for key in ("spent", "overflow", "ending_energy"):
                        self.assertAlmostEqual(result[key], reference[key], places=5)

    def test_independent_fixed_step_with_combat_and_capture_pulses(self):
        for hero, profile in self.profiles.items():
            with self.subTest(hero=hero):
                case = scenario(self.economy, late=True, bursts=[(30, 10, "capture"), (90, 24, "combat_pulse")])
                result = simulate(profile, self.economy, case, (3, 2, 0, 1))
                reference = tick_reference(profile, self.economy, case, (3, 2, 0, 1))
                self.assertEqual(result["casts_qwer"], reference["casts_qwer"])
                for key in ("spent", "overflow", "ending_energy"):
                    self.assertAlmostEqual(result[key], reference[key], places=5)

    def test_scenario_legality_and_equal_pulse_inputs(self):
        result = audit()
        for row in result["continuous"]:
            if row["hero"] == "fox" and row["case"]["combat_coefficient"] == 0.1:
                self.assertEqual(row["best_fixed_priority"]["casts_qwer"][1], 0)
        for row in result["pulses"]:
            self.assertEqual(sum(amount for _, amount, _ in row["case"]["bursts"]), 300)
        for row in result["captures"]:
            self.assertEqual(sum(amount for _, amount, _ in row["case"]["bursts"]), 100)


if __name__ == "__main__":
    unittest.main()
