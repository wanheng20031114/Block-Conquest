"""Shared offline surface sampling for authored uplands, roads and planting."""
import math


def height_at(layout, x, z):
    height = 0.0
    for (rx, rz, width, depth), start, end, axis in layout.get("heights", []):
        if rx - 1e-7 <= x <= rx + width + 1e-7 and rz - 1e-7 <= z <= rz + depth + 1e-7:
            t = (x - rx) / width if axis == 0 else (z - rz) / depth
            height = max(height, start + (end - start) * max(0.0, min(1.0, t)))
    return height


def supported_footprint(layout, x, z, radius, tolerance=0.15):
    center = height_at(layout, x, z)
    return all(abs(height_at(layout, x + dx * radius, z + dz * radius) - center) <= tolerance
               for dx, dz in ((-1, -1), (-1, 1), (1, -1), (1, 1), (0, -1), (0, 1), (-1, 0), (1, 0)))


def surface_segment_clear(layout, segment):
    """Split at exact zone borders, rejecting jumps instead of stepping over cliffs."""
    if not layout.get("heights"):
        return True
    ax, az, bx, bz = segment
    length = math.hypot(bx - ax, bz - az)
    if length < 1e-6:
        return True
    cuts = {0.0, 1.0}
    for (x, z, w, d), *_ in layout["heights"]:
        for a, delta, edges in ((ax, bx - ax, (x, x + w)), (az, bz - az, (z, z + d))):
            if abs(delta) > 1e-8:
                cuts.update((edge - a) / delta for edge in edges if 0 < (edge - a) / delta < 1)
    cuts = sorted(cuts)
    for t in cuts:
        epsilon = min(1e-5, 0.0001 / length)
        low, high = max(0, t - epsilon), min(1, t + epsilon)
        before = height_at(layout, ax + (bx - ax) * low, az + (bz - az) * low)
        after = height_at(layout, ax + (bx - ax) * high, az + (bz - az) * high)
        if abs(after - before) > 0.001:
            return False
    for low, high in zip(cuts, cuts[1:]):
        a, b = low + (high - low) * 0.001, high - (high - low) * 0.001
        first = height_at(layout, ax + (bx - ax) * a, az + (bz - az) * a)
        last = height_at(layout, ax + (bx - ax) * b, az + (bz - az) * b)
        if abs(last - first) > length * (b - a) * 0.5 + 0.001:
            return False
    return True
