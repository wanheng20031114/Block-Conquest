"""Apply one local-read candidate to a disposable PathBudget source string.

This module never opens or changes the production GDScript. Call the transform
before adding profiling wrappers. Exact matching rejects stale or already
transformed input instead of silently constructing a different experiment.

Only a fresh, active native-route sample uses the new locals. Map iteration and
footprint revision validation still precede the existing per-tick sample cache.
No navigation setting, position, or radius is retained across calls or ticks.
"""

from __future__ import annotations


_ORIGINAL = """\tif route.sampled_tick == tick: return route.next
\tvar end_distance: float = route.agent.target_desired_distance
\tif not route.path.is_empty() and route.path[-1].distance_squared_to(route.goal) > end_distance * end_distance:
\t\tend_distance = route.agent.path_desired_distance
\tvar lookahead: float = maxf(unit.radius, unit.speed * 0.25)
\t# The authored footprint cache certifies layer 1 only. Other native layers
\t# retain their own corridor without taking shortcuts through this cache.
\tvar navigation: ConstructionNavigation = _walkability if route.agent.navigation_layers == 1 else null
\troute.next = route.corridor.next_position(unit.global_position, route.agent.path_desired_distance, end_distance, lookahead, navigation, unit.radius)
\tif route.corridor.distance_squared_to_segment(unit.global_position) >= route.agent.path_max_distance * route.agent.path_max_distance:
\t\t_enqueue(unit.get_instance_id(), route)
\t\treturn unit.global_position
\troute.finished = route.corridor.finished
\troute.sampled_tick = tick
\treturn route.next
"""


_CANDIDATE = """\tif route.sampled_tick == tick: return route.next
\t# Reuse native property reads only inside this synchronous route sample.
\tvar agent: NavigationAgent3D = route.agent
\tvar waypoint_distance: float = agent.path_desired_distance
\tvar end_distance: float = agent.target_desired_distance
\tif not route.path.is_empty() and route.path[-1].distance_squared_to(route.goal) > end_distance * end_distance:
\t\tend_distance = waypoint_distance
\tvar radius: float = unit.radius
\tvar lookahead: float = maxf(radius, unit.speed * 0.25)
\t# The authored footprint cache certifies layer 1 only. Other native layers
\t# retain their own corridor without taking shortcuts through this cache.
\tvar navigation: ConstructionNavigation = _walkability if agent.navigation_layers == 1 else null
\tvar at: Vector3 = unit.global_position
\troute.next = route.corridor.next_position(at, waypoint_distance, end_distance, lookahead, navigation, radius)
\tvar maximum_distance: float = agent.path_max_distance
\tif route.corridor.distance_squared_to_segment(at) >= maximum_distance * maximum_distance:
\t\t_enqueue(unit.get_instance_id(), route)
\t\treturn at
\troute.finished = route.corridor.finished
\troute.sampled_tick = tick
\treturn route.next
"""


def optimize_path_sampling(source: str) -> str:
    """Return the strict local-read experiment without changing any file.

    LF and CRLF input are supported while preserving the source's line endings.
    Missing or repeated match sites raise ValueError; transformations are not
    idempotent so an accidentally repeated build step cannot go unnoticed.
    """
    newline = "\r\n" if "\r\n" in source else "\n"
    original = _ORIGINAL.replace("\n", newline)
    candidate = _CANDIDATE.replace("\n", newline)
    if source.count(original) != 1:
        raise ValueError("Expected exactly one unchanged PathBudget sampling block")
    return source.replace(original, candidate, 1)
