#!/usr/bin/env python3
"""Compile the NASA HEASARC BSC5P TDAT table into StarCatch's binary star field.

Usage:
  python3 Scripts/compile_bright_stars.py INPUT.tdat StarCatch/Resources/bright_stars_bsc5p.bin

The input is the public HEASARC table export. Runtime code never parses this source
format; it memory-maps the compact output and projects the catalogue outside Canvas.
"""

from __future__ import annotations

import math
import pathlib
import struct
import sys


MAGIC = b"SCST"
VERSION = 1
NON_STELLAR_HR = {
    92,
    95,
    182,
    1057,
    1841,
    2472,
    2496,
    3515,
    3671,
    6309,
    6515,
    7189,
    7539,
    8296,
}


def parse_optional_float(value: str) -> float | None:
    value = value.strip()
    if not value:
        return None
    parsed = float(value)
    return parsed if math.isfinite(parsed) else None


def read_rows(path: pathlib.Path) -> list[tuple[int, float, float, float, float]]:
    fields: list[str] | None = None
    in_data = False
    rows: list[tuple[int, float, float, float, float]] = []

    with path.open("r", encoding="utf-8") as source:
        for raw_line in source:
            line = raw_line.rstrip("\n")
            if line.startswith("line[1] = "):
                fields = line.removeprefix("line[1] = ").split()
                continue
            if line == "<DATA>":
                in_data = True
                continue
            if line == "<END>":
                break
            if not in_data or not line or line.startswith("#"):
                continue
            if fields is None:
                raise ValueError("TDAT field declaration is missing")

            values = line.split("|")
            # HEASARC TDAT data rows carry one trailing, unnamed transport
            # column which is not included in `line[1]`'s field list.
            if len(values) == len(fields) + 1 and values[-1] == "":
                values = values[:-1]
            if len(values) != len(fields):
                raise ValueError(
                    f"Expected {len(fields)} fields, found {len(values)}: {line[:80]}"
                )
            record = dict(zip(fields, values))
            hr = int(record["hr"])
            ra_degrees = parse_optional_float(record["ra"])
            dec_degrees = parse_optional_float(record["dec"])
            magnitude = parse_optional_float(record["vmag"])
            bv_color = parse_optional_float(record["bv_color"])
            if (
                hr in NON_STELLAR_HR
                or ra_degrees is None
                or dec_degrees is None
                or magnitude is None
                or magnitude > 6.5
            ):
                continue
            if not 0 <= hr <= 0xFFFF:
                raise ValueError(f"HR identifier does not fit UInt16: {hr}")
            rows.append(
                (
                    hr,
                    math.radians(ra_degrees),
                    math.radians(dec_degrees),
                    magnitude,
                    bv_color if bv_color is not None else math.nan,
                )
            )

    if not 8_000 <= len(rows) <= 10_000:
        raise ValueError(f"Unexpected bright-star count: {len(rows)}")
    rows.sort(key=lambda item: item[0])
    return rows


def compile_catalog(source: pathlib.Path, destination: pathlib.Path) -> None:
    rows = read_rows(source)
    payload = bytearray(MAGIC)
    payload.extend(struct.pack("<HI", VERSION, len(rows)))
    for hr, ra, dec, magnitude, bv_color in rows:
        payload.extend(struct.pack("<Hffff", hr, ra, dec, magnitude, bv_color))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    print(f"Compiled {len(rows)} bright stars to {destination} ({len(payload)} bytes)")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: compile_bright_stars.py INPUT.tdat OUTPUT.bin")
    compile_catalog(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))


if __name__ == "__main__":
    main()
