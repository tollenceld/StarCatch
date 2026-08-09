#!/usr/bin/env python3
"""Compile Natural Earth GeoJSON coastlines into StarCatch's compact binary asset.

Usage:
  python3 Scripts/compile_coastlines.py INPUT.geojson StarCatch/Resources/earth_coastlines_50m.bin

Natural Earth vector data is public domain. The source GeoJSON is intentionally not
bundled; only the simplified, app-specific binary output is committed.
"""

from __future__ import annotations

import json
import math
import pathlib
import struct
import sys
from typing import Iterable

Point = tuple[float, float]


def point_segment_distance(point: Point, start: Point, end: Point) -> float:
    px, py = point
    ax, ay = start
    bx, by = end
    dx = bx - ax
    dy = by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    amount = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + amount * dx), py - (ay + amount * dy))


def simplify(points: list[Point], tolerance: float) -> list[Point]:
    if len(points) <= 2:
        return points
    start = points[0]
    end = points[-1]
    distance, index = max(
        (point_segment_distance(point, start, end), index)
        for index, point in enumerate(points[1:-1], start=1)
    )
    if distance <= tolerance:
        return [start, end]
    left = simplify(points[: index + 1], tolerance)
    right = simplify(points[index:], tolerance)
    return left[:-1] + right


def source_lines(document: dict) -> Iterable[list[Point]]:
    for feature in document["features"]:
        geometry = feature["geometry"]
        coordinates = geometry["coordinates"]
        if geometry["type"] == "LineString":
            yield [(float(lon), float(lat)) for lon, lat in coordinates]
        elif geometry["type"] == "MultiLineString":
            for line in coordinates:
                yield [(float(lon), float(lat)) for lon, lat in line]


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    source = pathlib.Path(sys.argv[1])
    destination = pathlib.Path(sys.argv[2])
    document = json.loads(source.read_text(encoding="utf-8"))
    lines = [simplify(line, 0.30) for line in source_lines(document) if len(line) >= 2]

    payload = bytearray(b"SCGL")
    payload.extend(struct.pack("<HI", 1, len(lines)))
    for line in lines:
        if len(line) > 65_535:
            raise ValueError("A coastline exceeds the UInt16 point limit")
        payload.extend(struct.pack("<H", len(line)))
        for longitude, latitude in line:
            payload.extend(struct.pack("<ff", latitude, longitude))

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    print(f"wrote {destination}: {len(lines)} lines, {sum(map(len, lines))} points, {len(payload)} bytes")


if __name__ == "__main__":
    main()
