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


def poetic_for(name: str, identifier: int, category: str, kind: str, orbit: str) -> str:
    if name.upper().startswith("STARLINK"):
        variants = (
            "它是低轨通信星座的一枚节点；锁定它，会看见同一网络在天空中的尺度。",
            "它与数千枚同伴共享低轨壳层，把连续链路铺过地平线。",
            "这一枚高速越过天空的节点，以邻近卫星接力维持星座覆盖。",
            "它的名字来自编号；真正的身份，是一张全球低轨网络中的坐标。",
        )
        return variants[identifier % len(variants)]
    if kind == "station":
        return "有人生活与工作的轨道空间，正从这片天空经过。"
    if kind == "telescope":
        return "它在大气层之外收集光线，把更远处交还给地面。"
    if category == "observation":
        return "它反复越过地球，保存云层、海洋与陆地正在发生的变化。"
    if category == "network" and kind == "nav":
        return "它以稳定的轨道节奏参与定位与授时。"
    if category == "network":
        return "它是轨道网络中的一个节点，让信号跨越地平线。"
    if orbit == "GEO":
        return "它在遥远的同步轨道上，长久守住近似固定的方位。"
    return "它携带一项仍在轨道上运行的任务，按自己的周期越过天空。"


def stable_slug(name: str, identifier: int) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:36]
    return f"{slug or 'object'}-{identifier}"


def metadata_for_active(
    record: dict[str, Any],
    curated: dict[int, dict[str, Any]],
    memberships: dict[str, set[int]],
) -> dict[str, Any]:
    identifier = norad_id(record)
    curated_record = curated.get(identifier)
    category = category_for(record, memberships)
    orbit = orbit_class(record)
    kind = kind_for(record, category, memberships)
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
            "STARCATCH_POETIC": curated_record.get("poetic") if curated_record else poetic_for(name, identifier, category, kind, orbit),
            "STARCATCH_CURATED": curated_record is not None,
        }
    )
    if name.upper().startswith("STARLINK"):
        output["STARCATCH_FAMILY"] = "starlink"
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--curated", type=Path, default=Path("Scripts/catalog-curated.json"))
    parser.add_argument("--output", type=Path, default=Path("StarCatch/Resources/catalog.json"))
    parser.add_argument("--active-json", type=Path)
    parser.add_argument("--cache-dir", type=Path, default=Path("/tmp/starcatch-catalog-cache"))
    parser.add_argument("--refresh-groups", action="store_true")
    parser.add_argument("--skip-groups", action="store_true")
    args = parser.parse_args()

    curated_document = load_json(args.curated)
    curated_records = curated_document["objects"]
    curated_by_norad = {int(item["noradId"]): item for item in curated_records}

    if args.active_json:
        active_records = load_json(args.active_json)
    else:
        active_records = fetch_group("active", args.cache_dir, args.refresh_groups)

    memberships: dict[str, set[int]] = {
        "exploration": set(),
        "observation": set(),
        "network": set(),
        "stations": set(),
    }
    if not args.skip_groups:
        for category, groups in CATEGORY_GROUPS.items():
            for group in groups:
                print(f"classifying {group}…", flush=True)
                records = fetch_group(group, args.cache_dir, args.refresh_groups)
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
        valid_active.append(metadata_for_active(record, curated_by_norad, memberships))

    # Preserve the small authored archive for inactive historically meaningful objects.
    legacy_records: list[dict[str, Any]] = []
    for record in curated_records:
        identifier = int(record["noradId"])
        if identifier in seen:
            continue
        preserved = dict(record)
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
