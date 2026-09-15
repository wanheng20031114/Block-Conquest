"""Transform frozen corridor sources for isolated movement diagnostics.

Nothing in this module reads or writes production files. Instrumentation expects
MovementProbeCounters.enabled and its record_corridor(source, branch, usec,
rows, span_x, span_z) static method. The optional candidate only changes the
orientation of the conservative swept-grid scan; callers must opt in explicitly.
"""
from __future__ import annotations


def _once(source: str, before: str, after: str) -> str:
    count = source.count(before)
    if count != 1:
        raise ValueError(f"Expected one source anchor, found {count}: {before[:100]!r}")
    return source.replace(before, after, 1)


def _function(source: str, name: str) -> tuple[str, str, str]:
    source = source.replace("\r\n", "\n")
    marker = f"func {name}("
    if source.count(marker) != 1:
        raise ValueError(f"Expected exactly one {name} function")
    start = source.index(marker)
    end = source.find("\nfunc ", start + len(marker))
    if end < 0:
        end = len(source)
    return source[:start], source[start:end], source[end:]


def _record(branch: str, indent: str, value: str) -> str:
    return (
        f"{indent}if _probe_enabled:\n"
        f"{indent}\tMovementProbeCounters.record_corridor(probe_source, &\"{branch}\", "
        "Time.get_ticks_usec() - _probe_started, _probe_rows, _probe_span_x, _probe_span_z)\n"
        f"{indent}return {value}"
    )


def instrument_corridor(source: str) -> str:
    """Instrument every corridor exit, preserving the original boolean result.

    Accepts either the original function or optimize_corridor_short_axis output.
    rows counts rows/columns actually inspected, not the full possible span.
    Short-axis vertical degeneracy is reported as horizontal_reject as well:
    that existing bucket means a blocked axis-aligned bounding sweep.
    """
    prefix, body, suffix = _function(source, "has_clear_corridor")
    body = _once(
        body,
        "body_radius: float, certificate: Clearance = null) -> bool:\n",
        'body_radius: float, certificate: Clearance = null, probe_source: StringName = &"unspecified") -> bool:\n'
        "\tvar _probe_enabled: bool = MovementProbeCounters.enabled\n"
        "\tvar _probe_started: int = Time.get_ticks_usec() if _probe_enabled else 0\n"
        "\tvar _probe_rows: int = 0\n"
        "\tvar _probe_span_x: int = 0\n"
        "\tvar _probe_span_z: int = 0\n",
    )
    for guard in (
        "\tif _blocked_prefix.is_empty():\n",
        "\tif not from.is_finite() or not to.is_finite() or not is_finite(body_radius) or body_radius < 0.0:\n",
    ):
        body = _once(body, guard + "\t\treturn false", guard + _record("invalid", "\t\t", "false"))
    body = _once(
        body,
        "\t\t\tcorridor_cache_hits += 1\n\t\t\treturn true",
        "\t\t\tcorridor_cache_hits += 1\n" + _record("cache_hit", "\t\t\t", "true"),
    )
    bounds = "\tif low.x < 0 or low.y < 0 or high.x > _corridor_size.x or high.y > _corridor_size.y:\n"
    body = _once(
        body,
        bounds + "\t\treturn false",
        "\tif _probe_enabled:\n\t\t_probe_span_x = high.x - low.x\n\t\t_probe_span_z = high.y - low.y\n"
        + bounds + _record("bounds_reject", "\t\t", "false"),
    )
    body = _once(
        body,
        "\t\t\tcertificate.radius = body_radius\n\t\treturn true",
        "\t\t\tcertificate.radius = body_radius\n" + _record("rect_clear", "\t\t", "true"),
    )
    body = _once(
        body,
        "\t\treturn false # The bounding rectangle already is the horizontal sweep.",
        _record("horizontal_reject", "\t\t", "false"),
    )
    row = "\tfor row: int in range(low.y, high.y):\n"
    body = _once(body, row, row + "\t\tif _probe_enabled: _probe_rows += 1\n")
    blocked = "\t\tif _blocked_prefix[next + right] - _blocked_prefix[current + right] - _blocked_prefix[next + left] + _blocked_prefix[current + left] > 0:\n"
    body = _once(body, blocked + "\t\t\treturn false", blocked + _record("scan_blocked", "\t\t\t", "false"))
    # The optional candidate has one additional, transposed scan before this.
    if "# MOVEMENT_CORRIDOR_SHORT_AXIS" in body:
        body = _once(
            body,
            "\t\t\treturn false # The bounding rectangle already is the vertical sweep.",
            _record("horizontal_reject", "\t\t\t", "false"),
        )
        column = "\t\tfor column: int in range(low.x, high.x):\n"
        body = _once(body, column, column + "\t\t\tif _probe_enabled: _probe_rows += 1\n")
        blocked_x = "\t\t\tif _blocked_prefix[upper + column + 1] - _blocked_prefix[lower + column + 1] - _blocked_prefix[upper + column] + _blocked_prefix[lower + column] > 0:\n"
        body = _once(body, blocked_x + "\t\t\t\treturn false", blocked_x + _record("scan_blocked", "\t\t\t\t", "false"))
        body = _once(body, "\t\treturn true\n\tvar inverse_z:", _record("scan_clear", "\t\t", "true") + "\n\tvar inverse_z:")
    body = _once(body, "\n\treturn true\n", "\n" + _record("scan_clear", "\t", "true") + "\n")
    return prefix + body + suffix


def instrument_corridor_callers(path_budget_source: str, path_corridor_source: str) -> tuple[str, str]:
    """Label real call sites; preserve the existing pursuit certificate argument."""
    budget = path_budget_source.replace("\r\n", "\n")
    corridor = path_corridor_source.replace("\r\n", "\n")
    for before, after in (
        ("has_clear_corridor(unit.global_position, at, unit.radius, route.pursuit_clearance)", 'has_clear_corridor(unit.global_position, at, unit.radius, route.pursuit_clearance, &"direct_pursuit")'),
        ("has_clear_corridor(unit.global_position, route.goal, unit.radius)", 'has_clear_corridor(unit.global_position, route.goal, unit.radius, null, &"scheduler")'),
        ("has_clear_corridor(at, route.goal, unit.radius)", 'has_clear_corridor(at, route.goal, unit.radius, null, &"shared_goal")'),
        ("has_clear_corridor(at, point, unit.radius)", 'has_clear_corridor(at, point, unit.radius, null, &"shared_edge")'),
    ):
        budget = _once(budget, before, after)
    for before, after in (
        ("has_clear_corridor(at, points[last], radius)", 'has_clear_corridor(at, points[last], radius, null, &"shortcut_goal")'),
        ("has_clear_corridor(at, points[candidate], radius)", 'has_clear_corridor(at, points[candidate], radius, null, &"shortcut_waypoint")'),
        ("has_clear_corridor(at, ahead, radius)", 'has_clear_corridor(at, ahead, radius, null, &"passed_waypoint")'),
    ):
        corridor = _once(corridor, before, after)
    return budget, corridor


_SHORT_AXIS_SCAN = """\t# MOVEMENT_CORRIDOR_SHORT_AXIS: opt-in frozen-source diagnostic candidate.
\t# Transpose the same conservative swept square only for a shorter X span.
\t# The four prefix reads still sum an axis-aligned rectangle of occupied cells.
\tif high.x - low.x < high.y - low.y:
\t\tvar delta_x: float = to.x - from.x
\t\tif delta_x == 0.0:
\t\t\treturn false # The bounding rectangle already is the vertical sweep.
\t\tvar inverse_x: float = 1.0 / delta_x
\t\tvar delta_z: float = to.z - from.z
\t\tfor column: int in range(low.x, high.x):
\t\t\tvar x: float = float(column + _corridor_origin.x)
\t\t\tvar enter_x: float = (x - margin - from.x) * inverse_x
\t\t\tvar leave_x: float = (x + 1.0 + margin - from.x) * inverse_x
\t\t\tvar start_x: float = clampf(minf(enter_x, leave_x), 0.0, 1.0)
\t\t\tvar finish_x: float = clampf(maxf(enter_x, leave_x), 0.0, 1.0)
\t\t\tvar first_z: float = from.z + delta_z * start_x
\t\t\tvar last_z: float = from.z + delta_z * finish_x
\t\t\tvar bottom: int = floori(minf(first_z, last_z) - margin) - _corridor_origin.y
\t\t\tvar top: int = floori(maxf(first_z, last_z) + margin) - _corridor_origin.y + 1
\t\t\tbottom = maxi(low.y, bottom)
\t\t\ttop = mini(high.y, top)
\t\t\tvar lower: int = bottom * _corridor_stride
\t\t\tvar upper: int = top * _corridor_stride
\t\t\tif _blocked_prefix[upper + column + 1] - _blocked_prefix[lower + column + 1] - _blocked_prefix[upper + column] + _blocked_prefix[lower + column] > 0:
\t\t\t\treturn false
\t\treturn true
"""


def optimize_corridor_short_axis(source: str) -> str:
    """Opt-in prototype; keep the original O(1) checks and certificate semantics.

    Equivalence requires the same cell occupancy, square body expansion,
    finite endpoints, radius, map identity/revision, and conservative boundary
    rounding. Floating-point near-boundary cases need differential verification;
    this function alone is not a correctness or performance claim.
    """
    prefix, body, suffix = _function(source, "has_clear_corridor")
    if "MOVEMENT_CORRIDOR_SHORT_AXIS" in body or "_probe_started" in body:
        raise ValueError("Apply the candidate once, before instrumentation")
    # Preserve the original near-horizontal conservative rejection first. An
    # added epsilon on delta_x would invent an asymmetric near-vertical reject.
    body = _once(body, "\tvar inverse_z: float = 1.0 / dz\n", _SHORT_AXIS_SCAN + "\tvar inverse_z: float = 1.0 / dz\n")
    return prefix + body + suffix


def corridor_differential_sources(source: str) -> dict[str, str]:
    """Return two minimal real-source scripts for the isolated differential test.

    Extract the actual prefix-table builder and query rather than maintaining a
    separately handwritten reference implementation. No Node lifecycle, native
    navigation map, worker, or production scene is needed by this narrow oracle.
    """
    source = source.replace("\r\n", "\n")
    fields_start = source.index("var _corridor_origin := Vector2i.ZERO\n")
    fields_end = source.index("class MeshJob extends RefCounted:\n")
    fields = source[fields_start:fields_end]
    shell = "extends Node\nvar _walkable_cells: Dictionary = {}\nvar _revision: int = 0\n" + fields
    _, prefix_builder, _ = _function(source, "_rebuild_corridor_prefix")
    _, original_query, _ = _function(source, "has_clear_corridor")
    _, candidate_query, _ = _function(optimize_corridor_short_axis(source), "has_clear_corridor")
    return {
        "tests/generated/movement_corridor_reference.gd": shell + prefix_builder + "\n" + original_query + "\n",
        "tests/generated/movement_corridor_candidate.gd": shell + prefix_builder + "\n" + candidate_query + "\n",
    }
