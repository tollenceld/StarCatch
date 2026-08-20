#!/usr/bin/env python3
"""Build StarCatch's runtime-offline orbital catalog from public CelesTrak GP data.

The script is a release-time tool only. The iOS target never performs a network
request: it decodes the generated OMM records bundled in Resources/catalog.json.
"""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from satellite_content import unique_summary


CELESTRAK_GP = "https://celestrak.org/NORAD/elements/gp.php"
MAX_ELEMENT_AGE_DAYS = 14
MAX_FUTURE_EPOCH_DAYS = 4

CATEGORY_GROUPS = {
    "exploration": (
        "stations",
        "science",
        "education",
        "engineering",
        "geodetic",
        "cubesat",
    ),
    "observation": (
        "weather",
        "resource",
        "radar",
        "sar",
        "sarsat",
        "dmc",
        "planet",
        "spire",
    ),
    "network": (
        "gnss",
        "geo",
        "tdrss",
        "argos",
        "starlink",
        "oneweb",
        "qianfan",
        "hulianwang",
        "kuiper",
        "iridium-NEXT",
        "orbcomm",
        "globalstar",
        "amateur",
        "satnogs",
        "x-comm",
        "other-comm",
    ),
}

NETWORK_TOKENS = (
    "STARLINK",
    "ONEWEB",
    "QIANFAN",
    "HULIANWANG",
    "KUIPER",
    "IRIDIUM",
    "ORBCOMM",
    "GLOBALSTAR",
    "NAVSTAR",
    "GPS ",
    "GPS-",
    "GALILEO",
    "BEIDOU",
    "GLONASS",
    "INMARSAT",
    "INTELSAT",
    "EUTELSAT",
    "SES ",
    "TDRS",
)

OBSERVATION_TOKENS = (
    "NOAA",
    "GOES",
    "METEOR",
    "METOP",
    "LANDSAT",
    "SENTINEL",
    "FENGYUN",
    "HIMAWARI",
    "WORLDVIEW",
    "RADARSAT",
    "GAOFEN",
    "YAOGAN",
    "PLEIADES",
    "CARTOSAT",
    "OCEANSAT",
    "RESOURCESAT",
    "TERRA",
    "AQUA",
    "SUOMI",
)

NAVIGATION_TOKENS = (
    "NAVSTAR",
    "GPS ",
    "GPS-",
    "GALILEO",
    "BEIDOU",
    "GLONASS",
    "QZSS",
    "IRNSS",
)

TELESCOPE_TOKENS = ("HST", "HUBBLE", "TELESCOPE", "OBSERVATORY", "CHEOPS")

FAMILY_TOKENS = (
    ("starlink", ("STARLINK",)),
    ("oneweb", ("ONEWEB",)),
    ("qianfan", ("QIANFAN",)),
    ("hulianwang", ("HULIANWANG",)),
    ("kuiper", ("KUIPER",)),
    ("iridium", ("IRIDIUM",)),
    ("globalstar", ("GLOBALSTAR",)),
    ("orbcomm", ("ORBCOMM",)),
)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def fetch_group(group: str, cache_dir: Path, refresh: bool) -> list[dict[str, Any]]:
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_path = cache_dir / f"{group.lower()}.json"
    if cache_path.exists() and not refresh:
        return load_json(cache_path)

    query = urllib.parse.urlencode({"GROUP": group, "FORMAT": "JSON"})
    request = urllib.request.Request(
        f"{CELESTRAK_GP}?{query}",
        headers={"User-Agent": "StarCatch release catalog builder/1.0"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = response.read()
    cache_path.write_bytes(payload)
    time.sleep(0.15)
    return json.loads(payload)


def cached_group(group: str, cache_dir: Path) -> list[dict[str, Any]]:
    """Read optional classification cache without issuing another network request."""
    cache_path = cache_dir / f"{group.lower()}.json"
    return load_json(cache_path) if cache_path.exists() else []


def norad_id(record: dict[str, Any]) -> int:
    return int(record["NORAD_CAT_ID"])


def record_epoch(record: dict[str, Any]) -> datetime:
    value = str(record["EPOCH"]).replace("Z", "+00:00")
    parsed = datetime.fromisoformat(value)
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def contains_token(name: str, tokens: Iterable[str]) -> bool:
    upper = f"{name.upper()} "
    return any(token in upper for token in tokens)


def category_for(
    record: dict[str, Any],
    memberships: dict[str, set[int]],
) -> str:
    identifier = norad_id(record)
    if identifier in memberships["observation"]:
        return "observation"
    if identifier in memberships["network"]:
        return "network"
    if identifier in memberships["exploration"]:
        return "exploration"

    name = str(record.get("OBJECT_NAME") or "")
    if contains_token(name, OBSERVATION_TOKENS):
        return "observation"
    if contains_token(name, NETWORK_TOKENS):
        return "network"
    return "exploration"


def category_for_curated(record: dict[str, Any]) -> str:
    if record.get("status") in {"silent", "derelict", "debris"}:
        return "legacy"
    kind = record.get("kind")
    if kind == "weather":
        return "observation"
    if kind in {"comms", "nav"}:
        return "network"
    return "exploration"


def orbit_class(record: dict[str, Any]) -> str:
    mean_motion = float(record.get("MEAN_MOTION") or 0)
    eccentricity = float(record.get("ECCENTRICITY") or 0)
    if mean_motion <= 0:
        return "—"
    period_minutes = 1440 / mean_motion
    if eccentricity >= 0.25:
        return "HEO"
    if period_minutes < 225:
        return "LEO"
    if abs(period_minutes - 1436) < 150:
        return "GEO"
    if period_minutes < 1000:
        return "MEO"
    return "HEO"


def kind_for(record: dict[str, Any], category: str, memberships: dict[str, set[int]]) -> str:
    name = str(record.get("OBJECT_NAME") or "")
    identifier = norad_id(record)
    if category == "observation":
        return "weather" if contains_token(name, ("NOAA", "GOES", "METEOR", "METOP", "FENGYUN", "HIMAWARI")) else "science"
    if category == "network":
        return "nav" if contains_token(name, NAVIGATION_TOKENS) else "comms"
    if identifier in memberships.get("stations", set()):
        return "station"
    if contains_token(name, TELESCOPE_TOKENS):
        return "telescope"
    return "science"


def family_for(name: str) -> str | None:
    upper = name.upper()
    for family, tokens in FAMILY_TOKENS:
        if any(token in upper for token in tokens):
            return family
    return None


def stable_slug(name: str, identifier: int) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:36]
    return f"{slug or 'object'}-{identifier}"


def metadata_for_active(
    record: dict[str, Any],
    curated: dict[int, dict[str, Any]],
    memberships: dict[str, set[int]],
    previous: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    identifier = norad_id(record)
    curated_record = curated.get(identifier)
    previous_record = previous.get(identifier, {})
    previous_category = previous_record.get("STARCATCH_CATEGORY")
    has_current_membership = any(
        identifier in identifiers for identifiers in memberships.values()
    )
    category = (
        category_for(record, memberships)
        if has_current_membership
        else str(previous_category or category_for(record, memberships))
    )
    orbit = orbit_class(record)
    kind = str(
        previous_record.get("STARCATCH_KIND")
        or kind_for(record, category, memberships)
    )
    name = str(record.get("OBJECT_NAME") or f"NORAD {identifier}")

    if curated_record:
        category = category_for_curated(curated_record)
        kind = str(curated_record.get("kind") or kind)
        orbit = str(curated_record.get("orbitClass") or orbit)

    output = dict(record)
    output.update(
        {
            "STARCATCH_ID": curated_record.get("id") if curated_record else stable_slug(name, identifier),
            "STARCATCH_CATEGORY": category,
            "STARCATCH_KIND": kind,
            "STARCATCH_STATUS": curated_record.get("status", "active") if curated_record else "active",
            "STARCATCH_ORBIT_CLASS": orbit,
            "STARCATCH_LAUNCHED": curated_record.get("launched") if curated_record else str(record.get("OBJECT_ID") or "—")[:4],
            "STARCATCH_CURATED": curated_record is not None,
        }
    )
    if family := previous_record.get("STARCATCH_FAMILY") or family_for(name):
        output["STARCATCH_FAMILY"] = family
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--curated", type=Path, default=Path("Scripts/catalog-curated.json"))
    parser.add_argument("--output", type=Path, default=Path("StarCatch/Resources/catalog.json"))
    parser.add_argument("--active-json", type=Path)
    parser.add_argument("--cache-dir", type=Path, default=Path("/tmp/starcatch-catalog-cache"))
    parser.add_argument(
        "--refresh-active",
        action="store_true",
        help="download GROUP=active once even when an older local cache exists",
    )
    parser.add_argument("--refresh-groups", action="store_true")
    parser.add_argument("--skip-groups", action="store_true")
    args = parser.parse_args()

    curated_document = load_json(args.curated)
    curated_records = curated_document["objects"]
    curated_by_norad = {int(item["noradId"]): item for item in curated_records}
    previous_by_norad: dict[int, dict[str, Any]] = {}
    if args.output.exists():
        previous_document = load_json(args.output)
        previous_by_norad = {
            norad_id(item): item
            for item in previous_document.get("objects", [])
            if "NORAD_CAT_ID" in item
        }

    if args.active_json:
        active_records = load_json(args.active_json)
    else:
        active_records = fetch_group(
            "active",
            args.cache_dir,
            args.refresh_active or args.refresh_groups,
        )

    memberships: dict[str, set[int]] = {
        "exploration": set(),
        "observation": set(),
        "network": set(),
        "stations": set(),
    }
    if not args.skip_groups:
        for category, groups in CATEGORY_GROUPS.items():
            for group in groups:
                # CelesTrak explicitly asks clients not to repeatedly download overlapping
                # groups. Normal release refreshes fetch GROUP=active once and reuse the
                # previous catalog's classifications; group downloads are maintenance-only.
                records = (
                    fetch_group(group, args.cache_dir, True)
                    if args.refresh_groups
                    else cached_group(group, args.cache_dir)
                )
                if not records:
                    continue
                print(f"classifying {group}…", flush=True)
                identifiers = {norad_id(item) for item in records}
                memberships[category].update(identifiers)
                if group == "stations":
                    memberships["stations"].update(identifiers)

    generated_at = datetime.now(timezone.utc)
    valid_active: list[dict[str, Any]] = []
    seen: set[int] = set()
    for record in active_records:
        identifier = norad_id(record)
        if identifier in seen:
            continue
        age_days = (generated_at - record_epoch(record)).total_seconds() / 86400
        if age_days > MAX_ELEMENT_AGE_DAYS or age_days < -MAX_FUTURE_EPOCH_DAYS:
            continue
        seen.add(identifier)
        valid_active.append(
            metadata_for_active(
                record,
                curated_by_norad,
                memberships,
                previous_by_norad,
            )
        )

    # Preserve the small authored archive for inactive historically meaningful objects.
    legacy_records: list[dict[str, Any]] = []
    for record in curated_records:
        identifier = int(record["noradId"])
        if identifier in seen:
            continue
        preserved = dict(record)
        preserved.pop("poetic", None)
        # If an authored favorite is no longer in CelesTrak's active catalog, keep
        # it only as historical context. Never present an old element set as live.
        preserved["category"] = "legacy"
        if preserved.get("status") == "active":
            preserved["status"] = "silent"
        legacy_records.append(preserved)
        seen.add(identifier)

    valid_active.sort(key=norad_id)
    legacy_records.sort(key=lambda item: int(item["noradId"]))
    output = {
        "schemaVersion": 2,
        # Snapshot time describes the packaged catalog, not the newest individual
        # element epoch (some official high-orbit sets are short-term predictions).
        "snapshotEpoch": generated_at.isoformat().replace("+00:00", "Z"),
        "generatedAt": generated_at.isoformat().replace("+00:00", "Z"),
        "source": "CelesTrak GP/OMM · runtime offline snapshot",
        "objects": valid_active + legacy_records,
    }

    if len(valid_active) < 1000:
        raise RuntimeError(f"catalog unexpectedly small: {len(valid_active)} active records")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        json.dump(output, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")

    counts = {name: 0 for name in ("exploration", "observation", "network", "legacy")}
    for record in output["objects"]:
        category = record.get("STARCATCH_CATEGORY") or record.get("category")
        counts[category] += 1
    print(json.dumps({"total": len(output["objects"]), "categories": counts}, ensure_ascii=False))


if __name__ == "__main__":
    main()
