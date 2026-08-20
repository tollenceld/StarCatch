#!/usr/bin/env python3
"""Fail fast when a StarCatch archive would ship with stale or incomplete assets."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAX_CATALOG_AGE_DAYS = 3.0
MIN_CATALOG_OBJECTS = 10_000
FORBIDDEN_CONTENT_MARKERS = (
    "OPERATOR TO BE VERIFIED",
    "可编辑的本地基础档案",
    "掌握更准确",
    "完整日期可在核实后补充",
    "它携带一项仍在轨道上运行的任务",
)


class ReleaseCheckError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ReleaseCheckError(message)


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReleaseCheckError(f"无法读取 {path.relative_to(ROOT)}：{error}") from error


def parse_date(value: object, label: str) -> datetime:
    require(isinstance(value, str), f"{label} 缺少 ISO-8601 日期")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ReleaseCheckError(f"{label} 日期无效：{value}") from error
    require(parsed.tzinfo is not None, f"{label} 必须包含时区")
    return parsed.astimezone(timezone.utc)


def check_info_plist() -> None:
    path = ROOT / "StarCatch/Info.plist"
    with path.open("rb") as handle:
        info = plistlib.load(handle)
    require(
        info.get("CFBundleShortVersionString") == "$(MARKETING_VERSION)",
        "Info.plist 必须从 MARKETING_VERSION 读取版本号",
    )
    require(
        info.get("CFBundleVersion") == "$(CURRENT_PROJECT_VERSION)",
        "Info.plist 必须从 CURRENT_PROJECT_VERSION 读取构建号",
    )
    require(bool(info.get("NSLocationWhenInUseUsageDescription")), "缺少定位用途说明")
    require(bool(info.get("NSMotionUsageDescription")), "缺少运动用途说明")
    require(
        info.get("NSLocationDefaultAccuracyReduced") is False,
        "低轨指向需要默认申请完整定位精度",
    )
    require(info.get("ITSAppUsesNonExemptEncryption") is False, "加密出口声明必须明确为 false")


def check_privacy_manifest() -> None:
    path = ROOT / "StarCatch/PrivacyInfo.xcprivacy"
    with path.open("rb") as handle:
        privacy = plistlib.load(handle)
    require(privacy.get("NSPrivacyTracking") is False, "隐私清单必须明确不跟踪")
    require(privacy.get("NSPrivacyCollectedDataTypes") == [], "当前版本不应声明收集数据")
    accessed = privacy.get("NSPrivacyAccessedAPITypes", [])
    defaults = next(
        (
            item
            for item in accessed
            if item.get("NSPrivacyAccessedAPIType")
            == "NSPrivacyAccessedAPICategoryUserDefaults"
        ),
        None,
    )
    require(defaults is not None, "UserDefaults 的 Required Reason API 声明缺失")
    require("CA92.1" in defaults.get("NSPrivacyAccessedAPITypeReasons", []), "UserDefaults 理由必须包含 CA92.1")


def check_localizations() -> None:
    placeholder_pattern = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|d|(?:\.\d+)?f)")

    def placeholders(value: str) -> list[str]:
        return sorted(re.sub(r"%\d+\$", "%", match.group(0)) for match in placeholder_pattern.finditer(value))

    for name in ("Localizable.xcstrings", "SatelliteText.xcstrings"):
        document = load_json(ROOT / "StarCatch/Localization" / name)
        require(document.get("sourceLanguage") == "en", f"{name} 的源语言必须为英文")
        strings = document.get("strings")
        require(isinstance(strings, dict) and strings, f"{name} 不能为空")
        for key, entry in strings.items():
            localizations = entry.get("localizations", {})
            values: dict[str, str] = {}
            for language in ("en", "zh-Hans"):
                unit = localizations.get(language, {}).get("stringUnit", {})
                value = unit.get("value")
                require(unit.get("state") == "translated", f"{name}: {key} 缺少 {language} 已翻译状态")
                require(isinstance(value, str) and value.strip(), f"{name}: {key} 缺少 {language} 文本")
                values[language] = value
            require(
                placeholders(values["en"]) == placeholders(values["zh-Hans"]),
                f"{name}: {key} 的中英文插值参数不一致",
            )

    required_info_keys = {
        "CFBundleDisplayName",
        "NSLocationWhenInUseUsageDescription",
        "NSMotionUsageDescription",
    }
    for language in ("en", "zh-Hans"):
        text = (ROOT / "StarCatch/Localization" / f"{language}.lproj/InfoPlist.strings").read_text(encoding="utf-8")
        present = set(re.findall(r'^"([^"]+)"\s*=', text, flags=re.MULTILINE))
        require(required_info_keys <= present, f"{language} InfoPlist.strings 缺少权限说明")


def check_catalog(now: datetime) -> tuple[int, float]:
    catalog = load_json(ROOT / "StarCatch/Resources/catalog.json")
    profiles = load_json(ROOT / "StarCatch/Resources/satellite_profiles.json")
    require(catalog.get("schemaVersion") == 2, "catalog.json schemaVersion 必须为 2")
    require(profiles.get("schemaVersion") == 4, "satellite_profiles.json schemaVersion 必须为 4")
    require(
        profiles.get("presentationMode") == "structured-localized",
        "卫星档案必须声明结构化本地化展示模式",
    )
    objects = catalog.get("objects")
    require(isinstance(objects, list), "catalog.json objects 必须是数组")
    require(len(objects) >= MIN_CATALOG_OBJECTS, f"轨道目录少于 {MIN_CATALOG_OBJECTS:,} 个对象")
    require("CelesTrak" in str(catalog.get("source", "")), "轨道目录缺少 CelesTrak 来源声明")

    generated = parse_date(catalog.get("generatedAt"), "catalog.generatedAt")
    snapshot = parse_date(catalog.get("snapshotEpoch"), "catalog.snapshotEpoch")
    profile_generated = parse_date(profiles.get("generatedAt"), "profiles.generatedAt")
    require(abs((generated - profile_generated).total_seconds()) < 1, "目录与档案不是同一次生成")
    require(snapshot <= now.replace(microsecond=999999), "轨道快照时间位于未来")
    age_days = (now - snapshot).total_seconds() / 86_400
    require(age_days <= MAX_CATALOG_AGE_DAYS, f"轨道快照已过期：{age_days:.1f} 天（上限 {MAX_CATALOG_AGE_DAYS:.0f} 天）")
    require(len(profiles.get("stories", [])) > 0, "逐星档案为空")
    require(len(profiles.get("familyStories", [])) > 0, "星座家族档案为空")
    require(
        all("STARCATCH_POETIC" not in item and "poetic" not in item for item in objects),
        "语言中立轨道目录不应包含旧的本地化摘要字段",
    )
    stories = profiles.get("stories", [])
    all_stories = stories + [item.get("story", {}) for item in profiles.get("familyStories", [])]
    allowed_provenance = {
        "catalog", "computed", "verifiedObject", "verifiedFamily", "classification"
    }
    for story in all_stories:
        require(story.get("scope") in {"object", "family"}, "档案缺少 object/family 资料范围")
        sources = story.get("sources", [])
        require(isinstance(sources, list) and sources, "档案缺少结构化来源")
        source_ids = {item.get("id") for item in sources if isinstance(item, dict)}
        require(None not in source_ids and len(source_ids) == len(sources), "档案来源 ID 缺失或重复")
        require(
            all(item.get("provenance") in allowed_provenance for item in sources),
            "档案来源含未知可信度类型",
        )
        claims = [story]
        claims += story.get("chapters", [])
        claims += story.get("milestones", [])
        claims += story.get("facts", [])
        for index, claim in enumerate(claims):
            ids = claim.get("leadSourceIDs") if index == 0 else claim.get("sourceIDs")
            require(isinstance(ids, list) and ids, "档案存在没有来源关联的内容")
            require(set(ids).issubset(source_ids), "档案内容关联了不存在的来源")
    leads = [str(item.get("lead", "")).strip() for item in stories]
    require(all(leads), "逐星档案存在空摘要")
    require(
        len(set(leads)) == len(leads),
        f"逐星档案摘要存在重复：{len(leads) - len(set(leads))} 条",
    )
    serialized_copy = json.dumps(
        {"stories": stories},
        ensure_ascii=False,
        separators=(",", ":"),
    )
    for marker in FORBIDDEN_CONTENT_MARKERS:
        require(marker not in serialized_copy, f"卫星资料仍含占位内容：{marker}")
    require(
        "公开 GP/OMM 条目把它记录为" not in serialized_copy,
        "资料仍把 StarCatch 分类误称为 GP/OMM 原始字段",
    )
    return len(objects), age_days


def check_icon() -> None:
    path = ROOT / "StarCatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    with path.open("rb") as handle:
        header = handle.read(26)
    require(header[:8] == b"\x89PNG\r\n\x1a\n", "App Icon 必须是 PNG")
    width, height, bit_depth, color_type = struct.unpack(">IIBB", header[16:26])
    require((width, height) == (1024, 1024), "App Icon 必须为 1024×1024")
    require(bit_depth == 8, "App Icon 必须为 8-bit PNG")
    require(color_type not in (4, 6), "App Icon 不得包含 Alpha 通道")


def check_dependency_lock() -> None:
    path = ROOT / "StarCatch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    resolved = load_json(path)
    pins = resolved.get("pins", [])
    satellite = next((pin for pin in pins if pin.get("identity") == "satellitekit"), None)
    require(satellite is not None, "Package.resolved 未锁定 SatelliteKit")
    state = satellite.get("state", {})
    require(bool(state.get("version")), "SatelliteKit 必须锁定语义版本")
    require(bool(state.get("revision")), "SatelliteKit 必须锁定提交 revision")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--now",
        help="测试用 ISO-8601 当前时间；默认使用真实 UTC 时间",
    )
    args = parser.parse_args()
    now = parse_date(args.now, "--now") if args.now else datetime.now(timezone.utc)

    try:
        check_info_plist()
        check_privacy_manifest()
        check_localizations()
        objects, age_days = check_catalog(now)
        check_icon()
        check_dependency_lock()
    except (OSError, plistlib.InvalidFileException, ReleaseCheckError) as error:
        print(f"RELEASE CHECK FAILED: {error}", file=sys.stderr)
        return 1

    print(
        "RELEASE CHECK PASSED · "
        f"{objects:,} OBJECTS · CATALOG AGE {age_days:.1f}D · "
        "PRIVACY / ICON / DEPENDENCIES VERIFIED"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
