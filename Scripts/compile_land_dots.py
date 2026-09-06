#!/usr/bin/env python3
"""Compile Natural Earth land polygons into StarCatch's dotted globe asset.

Usage:
  python3 Scripts/compile_land_dots.py INPUT.{geojson,shp} \
      StarCatch/Resources/earth_land_dots_50m.bin [candidate-count]

The output contains a deterministic, approximately equal-area Fibonacci lattice.
Only samples that fall on land are kept. Each point also stores a three-level size
class; samples nearest water are rendered smallest so intricate coastlines retain a
fine edge without requiring polygon work in the app's 30fps Canvas path.

Natural Earth vector data is public domain. The source file is intentionally not
bundled; only the compact, app-specific binary output is committed.
"""

from __future__ import annotations

import json
import math
import pathlib
import struct
import sys
from dataclasses import dataclass
from typing import Iterable, Optional

Point = tuple[float, float]
Ring = list[Point]

DEFAULT_CANDIDATE_COUNT = 20_000
GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
COAST_SAMPLE_BEARINGS = tuple(index * math.pi / 4 for index in range(8))


@dataclass(frozen=True)
class BoundedRing:
    points: Ring
    bounds: tuple[float, float, float, float]


@dataclass(frozen=True)
class LandShape:
    rings: list[BoundedRing]
    bounds: tuple[float, float, float, float]


def ring_bounds(ring: Ring) -> tuple[float, float, float, float]:
    longitudes = [point[0] for point in ring]
    latitudes = [point[1] for point in ring]
    return min(longitudes), min(latitudes), max(longitudes), max(latitudes)


def make_shape(rings: Iterable[Ring]) -> Optional[LandShape]:
    usable = [ring for ring in rings if len(ring) >= 3]
    if not usable:
        return None
    bounds = [ring_bounds(ring) for ring in usable]
    return LandShape(
        rings=[
            BoundedRing(points=ring, bounds=ring_bounds_value)
            for ring, ring_bounds_value in zip(usable, bounds)
        ],
        bounds=(
            min(item[0] for item in bounds),
            min(item[1] for item in bounds),
            max(item[2] for item in bounds),
            max(item[3] for item in bounds),
        ),
    )


def geojson_shapes(path: pathlib.Path) -> list[LandShape]:
    document = json.loads(path.read_text(encoding="utf-8"))
    result: list[LandShape] = []
    for feature in document["features"]:
        geometry = feature["geometry"]
        if geometry["type"] == "Polygon":
            polygons = [geometry["coordinates"]]
        elif geometry["type"] == "MultiPolygon":
            polygons = geometry["coordinates"]
        else:
            continue
        for polygon in polygons:
            shape = make_shape(
                [[(float(lon), float(lat)) for lon, lat in ring] for ring in polygon]
            )
            if shape is not None:
                result.append(shape)
    return result


def shapefile_shapes(path: pathlib.Path) -> list[LandShape]:
    """Read Polygon records from a .shp without adding a build dependency."""
    data = path.read_bytes()
    if len(data) < 100 or struct.unpack_from(">i", data, 0)[0] != 9994:
        raise ValueError("Not a valid ESRI shapefile")

    result: list[LandShape] = []
    cursor = 100
    while cursor < len(data):
        if cursor + 8 > len(data):
            raise ValueError("Truncated shapefile record header")
        _, content_words = struct.unpack_from(">ii", data, cursor)
        cursor += 8
        content_size = content_words * 2
        end = cursor + content_size
        if content_size < 4 or end > len(data):
            raise ValueError("Truncated shapefile record")

        shape_type = struct.unpack_from("<i", data, cursor)[0]
        if shape_type == 0:
            cursor = end
            continue
        if shape_type not in (5, 15, 25):
            raise ValueError(f"Expected Polygon shapefile records, found type {shape_type}")
        if content_size < 44:
            raise ValueError("Truncated polygon record")

        min_lon, min_lat, max_lon, max_lat = struct.unpack_from("<4d", data, cursor + 4)
        part_count, point_count = struct.unpack_from("<2i", data, cursor + 36)
        parts_offset = cursor + 44
        points_offset = parts_offset + part_count * 4
        if part_count <= 0 or point_count <= 0 or points_offset + point_count * 16 > end:
            raise ValueError("Invalid polygon record counts")
        starts = list(struct.unpack_from(f"<{part_count}i", data, parts_offset))
        starts.append(point_count)
        points = [
            struct.unpack_from("<2d", data, points_offset + index * 16)
            for index in range(point_count)
        ]
        rings = [points[starts[index] : starts[index + 1]] for index in range(part_count)]
        shape = make_shape(rings)
        if shape is not None:
            result.append(
                LandShape(
                    rings=shape.rings,
                    bounds=(min_lon, min_lat, max_lon, max_lat),
                )
            )
        cursor = end

    return result


def source_shapes(path: pathlib.Path) -> list[LandShape]:
    if path.suffix.lower() == ".shp":
        return shapefile_shapes(path)
    return geojson_shapes(path)


def point_in_ring(longitude: float, latitude: float, ring: Ring) -> bool:
    inside = False
    previous_lon, previous_lat = ring[-1]
    for current_lon, current_lat in ring:
        crosses = (current_lat > latitude) != (previous_lat > latitude)
        if crosses:
            intersection = previous_lon + (
                (latitude - previous_lat)
                * (current_lon - previous_lon)
                / (current_lat - previous_lat)
            )
            if longitude < intersection:
                inside = not inside
        previous_lon, previous_lat = current_lon, current_lat
    return inside


def contains_land(longitude: float, latitude: float, shapes: list[LandShape]) -> bool:
    for shape in shapes:
        min_lon, min_lat, max_lon, max_lat = shape.bounds
        if not (min_lon <= longitude <= max_lon and min_lat <= latitude <= max_lat):
            continue
        inside = False
        for ring in shape.rings:
            ring_min_lon, ring_min_lat, ring_max_lon, ring_max_lat = ring.bounds
            if ring_min_lon <= longitude <= ring_max_lon and ring_min_lat <= latitude <= ring_max_lat:
                if point_in_ring(longitude, latitude, ring.points):
                    inside = not inside
        if inside:
            return True
    return False


def wrap_longitude(longitude: float) -> float:
    return (longitude + 180) % 360 - 180


def has_water_neighbor(
    longitude: float,
    latitude: float,
    angular_distance: float,
    shapes: list[LandShape],
) -> bool:
    longitude_scale = max(0.18, math.cos(math.radians(latitude)))
    for bearing in COAST_SAMPLE_BEARINGS:
        sample_latitude = max(
            -89.999,
            min(89.999, latitude + math.sin(bearing) * angular_distance),
        )
        sample_longitude = wrap_longitude(
            longitude + math.cos(bearing) * angular_distance / longitude_scale
        )
        if not contains_land(sample_longitude, sample_latitude, shapes):
            return True
    return False


def land_samples(
    shapes: list[LandShape],
    candidate_count: int,
) -> list[tuple[float, float, int]]:
    result: list[tuple[float, float, int]] = []
    for index in range(candidate_count):
        z = 1 - 2 * (index + 0.5) / candidate_count
        latitude = math.degrees(math.asin(z))
        longitude = wrap_longitude(math.degrees(index * GOLDEN_ANGLE))
        if not contains_land(longitude, latitude, shapes):
            continue

        if has_water_neighbor(longitude, latitude, 1.35, shapes):
            size_class = 0
        elif has_water_neighbor(longitude, latitude, 3.1, shapes):
            size_class = 1
        else:
            size_class = 2
        result.append((latitude, longitude, size_class))
    return result


def encode(samples: list[tuple[float, float, int]]) -> bytes:
    payload = bytearray(b"SCLD")
    payload.extend(struct.pack("<HI", 1, len(samples)))
    for latitude, longitude, size_class in samples:
        payload.extend(struct.pack("<ffB", latitude, longitude, size_class))
    return bytes(payload)


def main() -> None:
    if len(sys.argv) not in (3, 4):
        raise SystemExit(__doc__)
    source = pathlib.Path(sys.argv[1])
    destination = pathlib.Path(sys.argv[2])
    candidate_count = int(sys.argv[3]) if len(sys.argv) == 4 else DEFAULT_CANDIDATE_COUNT
    if candidate_count <= 0:
        raise ValueError("candidate-count must be positive")

    shapes = source_shapes(source)
    if not shapes:
        raise ValueError("No land polygons found")
    samples = land_samples(shapes, candidate_count)
    payload = encode(samples)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    counts = {size_class: 0 for size_class in range(3)}
    for _, _, size_class in samples:
        counts[size_class] += 1
    print(
        f"wrote {destination}: {len(samples)} land dots from {candidate_count} candidates, "
        f"classes {counts}, {len(payload)} bytes"
    )


if __name__ == "__main__":
    main()
