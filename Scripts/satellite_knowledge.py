#!/usr/bin/env python3
"""Generate, validate and compile StarCatch's Markdown satellite knowledge base."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "StarCatch" / "Resources" / "catalog.json"
KNOWLEDGE = ROOT / "SatelliteKnowledge"
PROFILES = KNOWLEDGE / "Profiles"
FAMILIES = KNOWLEDGE / "Families"
DEFAULT_OUTPUT = ROOT / "StarCatch" / "Resources" / "satellite_profiles.json"

REQUIRED_METADATA = ("type", "schema", "norad", "catalog_name", "eyebrow", "organization", "program")
REQUIRED_SECTIONS = ("摘要", "正文", "时间线", "事实", "来源")

# 这些是大量同构节点组成的通信星座。它们继续留在真实轨道目录和天空中，
# 但不生成数千份近乎相同的人工资料文件。
FAMILY_TOKENS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("starlink", ("STARLINK",)),
    ("oneweb", ("ONEWEB",)),
    ("qianfan", ("QIANFAN",)),
    ("hulianwang", ("HULIANWANG",)),
    ("kuiper", ("KUIPER",)),
    ("iridium", ("IRIDIUM",)),
    ("globalstar", ("GLOBALSTAR",)),
    ("orbcomm", ("ORBCOMM",)),
)

FAMILY_TITLES = {
    "starlink": "Starlink",
    "oneweb": "OneWeb",
    "qianfan": "千帆",
    "hulianwang": "国网",
    "kuiper": "Project Kuiper",
    "iridium": "Iridium",
    "globalstar": "Globalstar",
    "orbcomm": "Orbcomm",
}

# 高重复星座不建立数千份同质逐星档案，而是让每个真实轨道节点共同指向一份
# 可编辑的项目档案。这里仅负责首次生成；已经存在的 Markdown 永远不会被覆盖。
FAMILY_ARCHIVES = {
    "starlink": {
        "eyebrow": "LOW EARTH ORBIT NETWORK",
        "organization": "SPACEX",
        "program": "STARLINK CONSTELLATION",
        "lead": "低轨宽带网络。大量节点分布在多个轨道壳层，以连续接力覆盖地面终端。",
        "chapters": [
            ("一张持续移动的网络", "Starlink 不是一颗卫星的任务，而是由许多近地轨道节点共同组成的通信系统。单个节点不断越过地平线，网络通过其他节点接续覆盖。"),
            ("如何阅读这枚节点", "你此刻对准的是这个系统中的一枚真实卫星。不同编号拥有各自的轨道位置，但它们共享同一项目目的，因此都进入这份星座档案。"),
        ],
        "milestones": [
            ("部署阶段", "系统通过批量发射把卫星送入多个近地轨道面"),
            ("运行阶段", "轨道节点与地面终端和网关共同建立宽带链路"),
            ("此刻", "本地轨道快照继续分别推算每枚可识别节点的位置"),
        ],
        "facts": [("任务", "低轨宽带通信"), ("形态", "多轨道面大型星座"), ("档案范围", "Starlink 项目共同介绍")],
        "sources": ["SpaceX · Starlink public program information", "CelesTrak GP/OMM offline snapshot"],
    },
    "oneweb": {
        "eyebrow": "POLAR COMMUNICATION NETWORK",
        "organization": "EUTELSAT ONEWEB",
        "program": "ONEWEB CONSTELLATION",
        "lead": "低轨通信网络。卫星沿近极轨道分布，为地面与移动终端建立广域连接。",
        "chapters": [
            ("越过高纬度的轨道网", "OneWeb 的节点沿高倾角轨道反复覆盖地球。它们不是彼此独立的任务，而是共同承担连接地面站、企业与移动用户的网络角色。"),
            ("如何阅读这枚节点", "天空中的每个 OneWeb 点位都对应一个独立轨道对象；深入档案则聚焦它们共同构成的系统，避免用相同文字伪装成不同故事。"),
        ],
        "milestones": [
            ("部署阶段", "卫星被分批送入高倾角近地轨道"),
            ("运行阶段", "多个轨道面协同形成连续通信覆盖"),
            ("此刻", "每枚节点仍以独立轨道点位接受观测"),
        ],
        "facts": [("任务", "低轨宽带通信"), ("形态", "高倾角多轨道面星座"), ("档案范围", "OneWeb 项目共同介绍")],
        "sources": ["Eutelsat OneWeb public program information", "CelesTrak GP/OMM offline snapshot"],
    },
    "qianfan": {
        "eyebrow": "EMERGING ORBITAL NETWORK",
        "organization": "QIANFAN CONSTELLATION",
        "program": "千帆星座",
        "lead": "正在扩展的低轨通信星座。目录中的每个点都是同一网络的一枚独立轨道节点。",
        "chapters": [
            ("一项正在形成的系统", "千帆以大量近地轨道卫星构成通信网络。观测时看到的长带状点位来自相邻轨道面，而不是同一颗卫星的重复绘制。"),
            ("如何阅读这枚节点", "每个编号仍保留自己的轨道身份和实时位置；项目背景、共同任务与系统形态集中在这份共享档案中。"),
        ],
        "milestones": [
            ("部署阶段", "系统以批次方式建立近地轨道节点"),
            ("扩展阶段", "新增轨道面逐步改变天空中的点位密度"),
            ("此刻", "APP 使用离线元素分别推算已收录节点"),
        ],
        "facts": [("任务", "低轨卫星互联网"), ("形态", "分批部署的大型星座"), ("档案范围", "千帆项目共同介绍")],
        "sources": ["Public Qianfan constellation program information", "CelesTrak GP/OMM offline snapshot"],
    },
    "hulianwang": {
        "eyebrow": "NATIONAL ORBITAL NETWORK",
        "organization": "CHINA SATNET",
        "program": "国网低轨卫星互联网",
        "lead": "低轨卫星互联网系统。节点共同组成覆盖网络，而不是彼此重复的独立科学任务。",
        "chapters": [
            ("作为一个整体阅读", "国网节点属于同一卫星互联网体系。它们沿不同轨道运动，通过系统协作形成覆盖，因此项目背景比单个编号更适合作为深入阅读主体。"),
            ("如何阅读这枚节点", "主天空仍把每枚卫星画成真实点位；进入深入档案后，内容转向整个系统的任务语境，同时保留当前节点的即时轨道读数。"),
        ],
        "milestones": [
            ("部署阶段", "低轨通信节点按计划进入不同轨道面"),
            ("组网阶段", "节点共同形成面向地面的通信覆盖"),
            ("此刻", "本地目录按真实编号保存已公开的轨道对象"),
        ],
        "facts": [("任务", "低轨卫星互联网"), ("形态", "多节点通信星座"), ("档案范围", "国网项目共同介绍")],
        "sources": ["Public China SatNet program information", "CelesTrak GP/OMM offline snapshot"],
    },
    "kuiper": {
        "eyebrow": "LOW EARTH ORBIT BROADBAND",
        "organization": "AMAZON PROJECT KUIPER",
        "program": "PROJECT KUIPER",
        "lead": "近地轨道宽带星座。多轨道面的节点共同向地面网关与用户终端传递数据。",
        "chapters": [
            ("从节点到网络", "Project Kuiper 通过近地轨道卫星、地面网关与用户终端共同建立宽带系统。天空中的单颗节点只是这套基础设施的一部分。"),
            ("如何阅读这枚节点", "不同 Kuiper 编号的实时位置各不相同，但项目历史和共同功能相同，因此任意节点都进入同一份系统档案。"),
        ],
        "milestones": [
            ("验证阶段", "原型与早期节点用于验证轨道和通信系统"),
            ("部署阶段", "网络节点逐步进入计划轨道面"),
            ("此刻", "已公开轨道对象由本地快照独立推算"),
        ],
        "facts": [("任务", "低轨宽带通信"), ("形态", "卫星、网关与用户终端系统"), ("档案范围", "Project Kuiper 共同介绍")],
        "sources": ["Amazon Project Kuiper public program information", "CelesTrak GP/OMM offline snapshot"],
    },
    "iridium": {
        "eyebrow": "GLOBAL MOBILE CONSTELLATION",
        "organization": "IRIDIUM COMMUNICATIONS",
        "program": "IRIDIUM CONSTELLATION",
        "lead": "全球移动通信星座。极轨节点通过系统协作，为高纬度与远洋区域维持连接。",
        "chapters": [
            ("越过世界尽头的链路", "Iridium 以高倾角低轨卫星服务移动语音与数据通信。相邻节点依次掠过观察者上空，使偏远陆地、海洋和高纬度区域也能建立链路。"),
            ("如何阅读这枚节点", "每个 Iridium 点位都拥有独立轨道编号；深入档案讲述的是它们共同承担的移动通信网络。"),
        ],
        "milestones": [
            ("初代系统", "全球低轨移动通信网络建立"),
            ("更新阶段", "后续节点延续并更新星座能力"),
            ("此刻", "可公开识别的节点继续分别出现在本地天空"),
        ],
        "facts": [("任务", "全球移动语音与数据"), ("形态", "高倾角低轨星座"), ("档案范围", "Iridium 系统共同介绍")],
        "sources": ["Iridium public constellation information", "CelesTrak GP/OMM offline snapshot"],
    },
    "globalstar": {
        "eyebrow": "MOBILE SATELLITE NETWORK",
        "organization": "GLOBALSTAR",
        "program": "GLOBALSTAR CONSTELLATION",
        "lead": "移动卫星通信网络。低轨节点把语音与数据链路转交给可见的地面站。",
        "chapters": [
            ("卫星与地面共同完成的网络", "Globalstar 的低轨卫星负责把移动终端信号转交给覆盖范围内的地面网关。它的服务能力来自轨道节点与地面设施的共同布局。"),
            ("如何阅读这枚节点", "单个节点的编号、位置和速度保持独立；共同任务与系统结构则集中在这份星座档案中。"),
        ],
        "milestones": [
            ("部署阶段", "低轨节点进入多个轨道面"),
            ("运行阶段", "卫星把移动链路转交给地面网关"),
            ("此刻", "公开轨道节点继续由 APP 分别推算"),
        ],
        "facts": [("任务", "移动卫星通信"), ("形态", "低轨节点与地面网关"), ("档案范围", "Globalstar 系统共同介绍")],
        "sources": ["Globalstar public constellation information", "CelesTrak GP/OMM offline snapshot"],
    },
    "orbcomm": {
        "eyebrow": "MACHINE DATA NETWORK",
        "organization": "ORBCOMM",
        "program": "ORBCOMM CONSTELLATION",
        "lead": "面向物联网与资产通信的低轨网络，以窄带数据连接偏远区域的终端。",
        "chapters": [
            ("为机器传递短消息", "Orbcomm 的轨道节点主要服务资产跟踪、传感器与机器数据通信。它关注的不是大带宽画面，而是让远离常规网络的设备保持联系。"),
            ("如何阅读这枚节点", "天空中的节点各有真实轨道身份；深入档案使用一份共同说明，表达它们在同一窄带通信系统中的角色。"),
        ],
        "milestones": [
            ("部署阶段", "窄带通信节点进入近地轨道"),
            ("运行阶段", "轨道节点连接偏远资产与地面网络"),
            ("此刻", "每个公开节点仍以独立点位接受观测"),
        ],
        "facts": [("任务", "物联网与资产通信"), ("形态", "低轨窄带数据星座"), ("档案范围", "Orbcomm 系统共同介绍")],
        "sources": ["ORBCOMM public network information", "CelesTrak GP/OMM offline snapshot"],
    },
}

CATEGORY_TITLES = {
    "exploration": "探索与科学",
    "observation": "地球与大气观测",
    "network": "通信与导航网络",
    "legacy": "轨道历史与遗迹",
}

KIND_TITLES = {
    "science": "科学任务",
    "weather": "气象任务",
    "comms": "通信任务",
    "nav": "导航授时",
    "station": "载人空间设施",
    "telescope": "空间望远镜",
    "rocket_body": "火箭体",
    "debris": "轨道碎片",
}

PUBLIC_SUMMARY_RULES: tuple[tuple[tuple[str, ...], str], ...] = (
    (("LANDSAT",), "持续记录陆地表面的光谱与热信息，用于辨认城市、农田、水体和森林如何变化。"),
    (("NOAA 20", "NOAA 21", "JPSS", "SUOMI NPP"), "从极轨反复覆盖全球，为天气预报、灾害监测和长期气候记录提供大气与地表观测。"),
    (("GOES", "HIMAWARI", "FENGYUN 4"), "从地球同步轨道持续凝视同一片区域，追踪云系、强对流与热带气旋的快速变化。"),
    (("METOP",), "欧洲极轨气象任务，测量大气温湿廓线、海面风与痕量气体，为数值天气预报提供输入。"),
    (("SENTINEL-1",), "Copernicus 雷达观测任务，可穿透云层并在昼夜条件下记录陆地、海冰与海面变化。"),
    (("SENTINEL-2",), "Copernicus 多光谱成像任务，长期记录植被、土地利用、海岸和灾害现场。"),
    (("SENTINEL-3",), "面向海洋与陆地的综合观测任务，测量海表温度、海色、地表温度与高度。"),
    (("SENTINEL-5P",), "从全球尺度读取大气成分，追踪臭氧、氮氧化物、甲烷和气溶胶等关键变量。"),
    (("SENTINEL-6",), "以雷达测高延续全球海平面高度记录，为气候与业务海洋学提供长期基准。"),
    (("GALILEO", "BEIDOU", "NAVSTAR", "GLONASS", "MICHIBIKI", "IRNSS"), "在中地轨道广播精密时间与轨道信息，参与全球定位、导航和授时。"),
    (("SWOT",), "用宽幅雷达测高同时读取海洋与陆地水体，描绘河流、湖泊和海面高度的细微变化。"),
    (("ICESAT",), "用激光测高读取冰盖、海冰、森林与地表高度，追踪冰冻圈和地形的长期变化。"),
    (("SMAP",), "测量表层土壤水分与冻融状态，帮助理解水、能量和碳在陆地表面的交换。"),
    (("GOSAT",), "面向温室气体观测，读取大气中的二氧化碳与甲烷分布，并延续长期全球记录。"),
    (("ALOS",), "以雷达或光学载荷观察陆地，用于测绘、灾害响应、森林与地表变化研究。"),
    (("GCOM-",), "日本全球变化观测任务，持续读取水循环、气候与地表环境的关键变量。"),
    (("CARTOSAT",), "印度高分辨率制图任务，为地形测绘、城市规划和土地信息提供立体影像。"),
    (("RESOURCESAT",), "印度资源观测任务，记录农业、林业、水体与土地利用的长期变化。"),
    (("OCEANSAT",), "印度海洋观测任务，读取海色、海面风与海洋生物生产力等环境信息。"),
    (("METEOR-M",), "俄罗斯极轨气象任务，获取云层、大气与地表资料，服务天气与环境监测。"),
    (("ELEKTRO-L",), "俄罗斯地球同步气象任务，持续观察大范围云系与快速发展的天气过程。"),
    (("KANOPUS",), "俄罗斯对地观测任务，以高分辨率影像支持灾害、环境与地表变化监测。"),
    (("TDRS",), "NASA 空间网络的数据中继节点，为近地轨道航天器与地面之间维持高覆盖通信。"),
    (("INTELSAT", "EUTELSAT", "INMARSAT", "TELSTAR"), "地球同步通信节点，将广播、数据或移动链路跨越地平线连接到远方地面站。"),
    (("GAOFEN",), "高分辨率对地观测任务，用于国土、农业、环境与灾害等遥感应用。"),
    (("HAIYANG",), "海洋观测任务，读取海色、海面动力或海洋环境变量，服务海洋研究与监测。"),
    (("ZIYUAN",), "资源与测绘遥感任务，以地表影像支持国土调查、制图和环境观察。"),
    (("YAOGAN",), "公开目录将其识别为遥感系列；资料只陈述可核实的轨道身份，不推断未公开载荷。"),
    (("SHIJIAN", "SHIYAN"), "技术试验系列。它验证空间技术或载荷能力；未公开的具体用途不在这里推测。"),
)

ORGANIZATION_RULES: tuple[tuple[tuple[str, ...], str], ...] = (
    (("NAVSTAR",), "UNITED STATES SPACE FORCE · GPS"),
    (("GLONASS",), "GLONASS NAVIGATION SYSTEM"),
    (("MICHIBIKI",), "JAPAN QZSS"),
    (("IRNSS",), "ISRO · NAVIC"),
    (("LANDSAT",), "NASA · USGS"),
    (("NOAA", "JPSS", "SUOMI NPP", "GOES"), "NOAA · NASA"),
    (("SENTINEL",), "COPERNICUS · ESA"),
    (("METOP", "METEOSAT"), "EUMETSAT · ESA"),
    (("GALILEO",), "EUROPEAN UNION · ESA"),
    (("HIMAWARI",), "JAPAN METEOROLOGICAL AGENCY"),
    (("GOSAT",), "JAXA · NIES · JAPAN MOE"),
    (("ALOS", "GCOM-"), "JAXA"),
    (("CARTOSAT", "RESOURCESAT", "OCEANSAT", "INSAT", "RISAT", "EOS-"), "ISRO · EARTH OBSERVATION"),
    (("METEOR-M", "ELEKTRO-L", "KANOPUS"), "ROSCOSMOS · EARTH OBSERVATION"),
    (("TDRS",), "NASA SPACE NETWORK"),
    (("INTELSAT",), "INTELSAT"),
    (("EUTELSAT",), "EUTELSAT"),
    (("INMARSAT",), "INMARSAT"),
    (("FENGYUN",), "CHINA METEOROLOGICAL ADMINISTRATION"),
    (("BEIDOU",), "BEIDOU NAVIGATION SYSTEM"),
    (("GAOFEN", "HAIYANG", "ZIYUAN"), "CHINA EARTH OBSERVATION PROGRAM"),
    (("YAOGAN",), "CHINA REMOTE SENSING PROGRAM"),
    (("SHIJIAN", "SHIYAN"), "CHINA SPACE TECHNOLOGY PROGRAM"),
)


def catalog_document() -> dict:
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def catalog_objects() -> list[dict]:
    return catalog_document()["objects"]


def value(record: dict, generated: str, legacy: str):
    return record.get(generated, record.get(legacy))


def identity(record: dict) -> tuple[int, str]:
    return int(value(record, "NORAD_CAT_ID", "noradId")), str(value(record, "OBJECT_NAME", "name"))


def family_for(record: dict) -> str | None:
    explicit = record.get("STARCATCH_FAMILY")
    if explicit:
        return str(explicit)
    upper = identity(record)[1].upper()
    for family, tokens in FAMILY_TOKENS:
        if any(token in upper for token in tokens):
            return family
    return None


def eligible_records(records: list[dict]) -> list[dict]:
    return [record for record in records if family_for(record) not in FAMILY_TITLES]


def profile_paths() -> list[Path]:
    return sorted(path for path in PROFILES.rglob("*.md") if not path.name.startswith("_"))


def family_profile_paths() -> list[Path]:
    return sorted(path for path in FAMILIES.glob("*.md") if not path.name.startswith("_"))


def front_matter(text: str) -> tuple[dict[str, str], list[str]]:
    lines = text.replace("\r\n", "\n").splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError("缺少文件头起始标记 ---")
    try:
        end = next(index for index, line in enumerate(lines[1:], 1) if line.strip() == "---")
    except StopIteration as error:
        raise ValueError("缺少文件头结束标记 ---") from error
    result: dict[str, str] = {}
    for line in lines[1:end]:
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        result[key.strip()] = raw.strip().strip("\"'")
    return result, lines[end + 1:]


def section_map(lines: list[str]) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    current: str | None = None
    for line in lines:
        if line.startswith("## "):
            current = line[3:].strip()
            result.setdefault(current, [])
        elif current is not None:
            result[current].append(line)
    return result


def paragraph(lines: list[str]) -> str:
    groups: list[str] = []
    current: list[str] = []
    for line in lines + [""]:
        if line.strip():
            current.append(line.strip())
        elif current:
            groups.append(" ".join(current))
            current = []
    return "\n\n".join(groups)


def list_values(lines: list[str]) -> list[str]:
    return [line.strip()[2:].strip() for line in lines if line.strip().startswith("- ")]


def pair_values(lines: list[str]) -> list[tuple[str, str]]:
    result: list[tuple[str, str]] = []
    for item in list_values(lines):
        if "|" not in item:
            continue
        left, right = item.split("|", 1)
        if left.strip() and right.strip():
            result.append((left.strip(), right.strip()))
    return result


def chapters(lines: list[str]) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    title: str | None = None
    body: list[str] = []
    for line in lines + ["### __END__"]:
        if line.startswith("### "):
            if title is not None:
                text = paragraph(body)
                if text:
                    result.append({"id": f"chapter-{len(result)}", "title": title, "body": text})
            title = line[4:].strip()
            body = []
        elif title is not None:
            body.append(line)
    return result


def parsed_story(
    metadata: dict[str, str],
    body: list[str],
    *,
    norad: int,
) -> tuple[dict | None, list[str]]:
    errors: list[str] = []
    sections = section_map(body)
    missing_sections = [section for section in REQUIRED_SECTIONS if section not in sections]
    if missing_sections:
        errors.append(f"缺少章节 {', '.join(missing_sections)}")
    if errors:
        return None, errors

    lead = paragraph(sections["摘要"])
    chapter_values = chapters(sections["正文"])
    milestone_values = pair_values(sections["时间线"])
    fact_values = pair_values(sections["事实"])
    source_values = list_values(sections["来源"])
    if not lead:
        errors.append("摘要不能为空")
    if not chapter_values:
        errors.append("正文至少需要一个三级标题和一段内容")
    if not milestone_values:
        errors.append("时间线至少需要一条“时间 | 事件”")
    if not fact_values:
        errors.append("事实至少需要一条“字段 | 内容”")
    if not source_values:
        errors.append("来源至少需要一项")
    if errors:
        return None, errors

    story = {
        "noradID": norad,
        "eyebrow": metadata["eyebrow"],
        "organization": metadata["organization"],
        "program": metadata["program"],
        "lead": lead,
        "chapters": chapter_values,
        "milestones": [
            {"id": f"milestone-{index}", "time": time, "event": event}
            for index, (time, event) in enumerate(milestone_values)
        ],
        "facts": [
            {"id": f"fact-{index}", "label": label, "value": item_value}
            for index, (label, item_value) in enumerate(fact_values)
        ],
        "sources": source_values,
    }
    return story, []


def parse_profile(path: Path) -> tuple[dict | None, list[str]]:
    try:
        metadata, body = front_matter(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        return None, [str(error)]
    missing = [field for field in REQUIRED_METADATA if not metadata.get(field)]
    if missing:
        return None, [f"缺少字段 {', '.join(missing)}"]
    try:
        norad = int(metadata.get("norad", "").replace("_", ""))
    except ValueError:
        return None, ["NORAD 编号无效"]
    return parsed_story(metadata, body, norad=norad)


def parse_family_profile(path: Path) -> tuple[dict | None, list[str]]:
    try:
        metadata, body = front_matter(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        return None, [str(error)]
    required = ("type", "schema", "family", "eyebrow", "organization", "program")
    missing = [field for field in required if not metadata.get(field)]
    if missing:
        return None, [f"缺少字段 {', '.join(missing)}"]
    family = metadata["family"]
    if family not in FAMILY_ARCHIVES:
        return None, [f"未知星座 family: {family}"]
    story, errors = parsed_story(metadata, body, norad=0)
    if errors or story is None:
        return None, errors
    return {"family": family, "story": story}, []


def slug(name: str) -> str:
    return re.sub(r"[^A-Z0-9]+", "-", name.upper()).strip("-")[:48] or "OBJECT"


def profile_path(norad: int, name: str) -> Path:
    lower = (norad // 10_000) * 10_000
    upper = lower + 9_999
    bucket = PROFILES / f"N{lower:05d}-N{upper:05d}"
    return bucket / f"NORAD-{norad:05d}-{slug(name)}.md"


def summary_for(record: dict) -> str:
    name = identity(record)[1].upper()
    if name == "TERRA":
        return "以多台仪器同时观察大气、陆地、海洋与能量交换，把地球作为相互连接的系统来阅读。"
    if name == "AQUA":
        return "围绕地球水循环工作，观察云、降水、水汽、海冰、积雪以及海陆表面温度。"
    for tokens, summary in PUBLIC_SUMMARY_RULES:
        if any(token in name for token in tokens):
            return summary
    return str(value(record, "STARCATCH_POETIC", "poetic") or "它仍在轨道上，以自己的周期穿过观察者此刻的天空。")


def organization_for(record: dict) -> str:
    name = identity(record)[1].upper()
    if name in {"TERRA", "AQUA"} or "ICESAT" in name or "SMAP" in name:
        return "NASA EARTH SCIENCE"
    for tokens, organization in ORGANIZATION_RULES:
        if any(token in name for token in tokens):
            return organization
    return "OPERATOR TO BE VERIFIED"


def render_generated_profile(record: dict) -> str:
    norad, name = identity(record)
    cospar = str(value(record, "OBJECT_ID", "cosparId") or "—")
    orbit = str(value(record, "STARCATCH_ORBIT_CLASS", "orbitClass") or "—")
    category = str(value(record, "STARCATCH_CATEGORY", "category") or "exploration")
    status = str(value(record, "STARCATCH_STATUS", "status") or "active")
    kind = str(value(record, "STARCATCH_KIND", "kind") or "science")
    launched = str(value(record, "STARCATCH_LAUNCHED", "launched") or cospar[:4] or "—")
    summary = summary_for(record)
    category_title = CATEGORY_TITLES.get(category, category.upper())
    kind_title = KIND_TITLES.get(kind, kind.upper())
    eyebrow = {
        "observation": "EARTH OBSERVATION ARCHIVE",
        "network": "ORBITAL NETWORK ARCHIVE",
        "legacy": "ORBITAL HERITAGE ARCHIVE",
    }.get(category, "SCIENCE AND EXPLORATION ARCHIVE")
    epoch = str(record.get("EPOCH") or "历史 TLE")[:10]
    return f"""---
type: satellite-profile
schema: 1
norad: {norad}
catalog_name: {name}
eyebrow: {eyebrow}
organization: {organization_for(record)}
program: {name}
review_status: generated
---

# {name}

## 摘要

{summary}

## 正文

### 任务与身份

公开轨道目录将 {name} 记录为 {category_title}中的{kind_title}。它的 NORAD 编号是 {norad}，国际编号是 {cospar}。这份文字是可编辑的本地基础档案；当你掌握更准确的任务、载荷或历史资料时，可以直接替换这一段。

### 如何阅读它

StarCatch 使用随 APP 打包的轨道元素计算它在指定时间相对观察者的方位、仰角、高度、距离与速度。这里保存的是不会随每次轨道更新而丢失的任务说明，动态读数不需要手工维护。

## 时间线

- {launched} | 目录记录的发射年份或日期；完整日期可在核实后补充
- {epoch} | 当前随包轨道元素的历元日期

## 事实

- NORAD | {norad}
- COSPAR | {cospar}
- 分类 | {category_title}
- 类型 | {kind_title}
- 轨道 | {orbit}
- 状态 | {status.upper()}

## 来源

- CelesTrak GP/OMM 离线快照
"""


def render_family_profile(family: str) -> str:
    archive = FAMILY_ARCHIVES[family]
    title = FAMILY_TITLES[family]
    chapter_text = "\n\n".join(
        f"### {heading}\n\n{body}" for heading, body in archive["chapters"]
    )
    milestone_text = "\n".join(
        f"- {time} | {event}" for time, event in archive["milestones"]
    )
    fact_text = "\n".join(
        f"- {label} | {item_value}" for label, item_value in archive["facts"]
    )
    source_text = "\n".join(f"- {source}" for source in archive["sources"])
    return f"""---
type: constellation-profile
schema: 1
family: {family}
eyebrow: {archive["eyebrow"]}
organization: {archive["organization"]}
program: {archive["program"]}
review_status: generated
---

# {title}

## 摘要

{archive["lead"]}

## 正文

{chapter_text}

## 时间线

{milestone_text}

## 事实

{fact_text}

## 来源

{source_text}
"""


def sync_family_profiles() -> int:
    FAMILIES.mkdir(parents=True, exist_ok=True)
    created = 0
    for family in FAMILY_ARCHIVES:
        path = FAMILIES / f"{family}.md"
        if path.exists():
            continue
        path.write_text(render_family_profile(family), encoding="utf-8")
        created += 1
    return created


def existing_profiles_by_norad() -> dict[int, Path]:
    result: dict[int, Path] = {}
    for path in profile_paths():
        try:
            metadata, _ = front_matter(path.read_text(encoding="utf-8"))
            norad = int(metadata.get("norad", "").replace("_", ""))
        except (OSError, UnicodeError, ValueError):
            continue
        result.setdefault(norad, path)
    return result


def sync_profiles() -> int:
    records = catalog_objects()
    eligible = eligible_records(records)
    eligible_ids = {identity(record)[0] for record in eligible}
    existing = existing_profiles_by_norad()

    excluded_existing = [(norad, path) for norad, path in existing.items() if norad not in eligible_ids]
    if excluded_existing:
        print("以下档案属于已排除的同质星座，请先移除：", file=sys.stderr)
        for norad, path in excluded_existing:
            print(f"- N{norad} {path}", file=sys.stderr)
        return 1

    # 将既有精选档案放入相同的 NORAD 分卷；只移动，不改写人工内容。
    for norad, old_path in list(existing.items()):
        record = next(record for record in eligible if identity(record)[0] == norad)
        target = profile_path(norad, identity(record)[1])
        if old_path != target:
            target.parent.mkdir(parents=True, exist_ok=True)
            old_path.replace(target)
            existing[norad] = target

    created = 0
    for record in eligible:
        norad, name = identity(record)
        if norad in existing:
            continue
        path = profile_path(norad, name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render_generated_profile(record), encoding="utf-8")
        existing[norad] = path
        created += 1

    write_index(eligible, existing)
    write_exclusions(records)
    created_families = sync_family_profiles()
    print(
        f"SatelliteKnowledge: 保留 {len(eligible)} 颗，新增 {created} 份逐星档案；"
        f"新增 {created_families} 份星座共享档案，覆盖 {len(records) - len(eligible)} 个同质节点"
    )
    return 0


def write_index(records: list[dict], paths: dict[int, Path]) -> None:
    lines = [
        "# 全部可编辑卫星",
        "",
        f"本索引由 `Scripts/satellite_knowledge.py sync` 自动生成，共 {len(records)} 颗。不要手工编辑索引；请点击链接修改对应档案。",
        "",
    ]
    current_bucket = ""
    for record in sorted(records, key=lambda item: identity(item)[0]):
        norad, name = identity(record)
        path = paths[norad]
        bucket = path.parent.name
        if bucket != current_bucket:
            lines += [f"## {bucket}", ""]
            current_bucket = bucket
        relative = path.relative_to(KNOWLEDGE).with_suffix("").as_posix()
        lines.append(f"- [[{relative}|{name} · N{norad}]]")
    lines.append("")
    (KNOWLEDGE / "INDEX.md").write_text("\n".join(lines), encoding="utf-8")


def write_exclusions(records: list[dict]) -> None:
    counts = Counter(family_for(record) for record in records if family_for(record) in FAMILY_TITLES)
    lines = [
        "# 已排除的高重复星座",
        "",
        "这些节点继续存在于 APP 的真实轨道目录与天空中，但不创建逐星 Markdown，避免产生大量内容完全相同的文件。任意节点的“深入档案”会进入 `Families/` 中对应的项目共享档案。",
        "",
        "| 星座 | 排除数量 |",
        "| --- | ---: |",
    ]
    for family, count in counts.most_common():
        lines.append(f"| {FAMILY_TITLES[family]} | {count} |")
    lines += ["", f"合计：{sum(counts.values())} 颗。", ""]
    (KNOWLEDGE / "EXCLUDED_CONSTELLATIONS.md").write_text("\n".join(lines), encoding="utf-8")


def validate_profiles(require_complete_coverage: bool = True) -> tuple[list[dict], list[str]]:
    records = catalog_objects()
    by_norad = {identity(record)[0]: record for record in records}
    eligible_ids = {identity(record)[0] for record in eligible_records(records)}
    stories: list[dict] = []
    errors: list[str] = []
    seen: dict[int, Path] = {}
    for path in profile_paths():
        story, parse_errors = parse_profile(path)
        if parse_errors:
            errors.extend(f"{path.relative_to(ROOT)}: {error}" for error in parse_errors)
            continue
        assert story is not None
        norad = story["noradID"]
        if norad not in by_norad:
            errors.append(f"{path.relative_to(ROOT)}: NORAD {norad} 不在本地轨道目录中")
        elif norad not in eligible_ids:
            errors.append(f"{path.relative_to(ROOT)}: NORAD {norad} 属于已排除的高重复星座")
        if norad in seen:
            errors.append(f"{path.relative_to(ROOT)}: NORAD {norad} 与 {seen[norad].relative_to(ROOT)} 重复")
        else:
            seen[norad] = path
            stories.append(story)
    if require_complete_coverage:
        missing = sorted(eligible_ids - set(seen))
        extra = sorted(set(seen) - eligible_ids)
        if missing:
            errors.append(f"缺少 {len(missing)} 颗应保留卫星的档案；前 10 项：{missing[:10]}")
        if extra:
            errors.append(f"存在 {len(extra)} 颗不应编译的档案；前 10 项：{extra[:10]}")
    return sorted(stories, key=lambda item: item["noradID"]), errors


def validate_family_profiles() -> tuple[list[dict], list[str]]:
    records: list[dict] = []
    errors: list[str] = []
    seen: dict[str, Path] = {}
    for path in family_profile_paths():
        record, parse_errors = parse_family_profile(path)
        if parse_errors:
            errors.extend(f"{path.relative_to(ROOT)}: {error}" for error in parse_errors)
            continue
        assert record is not None
        family = record["family"]
        if family in seen:
            errors.append(
                f"{path.relative_to(ROOT)}: family {family} 与 "
                f"{seen[family].relative_to(ROOT)} 重复"
            )
        else:
            seen[family] = path
            records.append(record)
    missing = sorted(set(FAMILY_ARCHIVES) - set(seen))
    extra = sorted(set(seen) - set(FAMILY_ARCHIVES))
    if missing:
        errors.append(f"缺少星座共享档案：{', '.join(missing)}")
    if extra:
        errors.append(f"存在未知星座共享档案：{', '.join(extra)}")
    return sorted(records, key=lambda item: item["family"]), errors


def validate() -> int:
    stories, errors = validate_profiles()
    family_stories, family_errors = validate_family_profiles()
    errors += family_errors
    if errors:
        print("SatelliteKnowledge 校验失败：", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    excluded = len(catalog_objects()) - len(stories)
    print(
        f"SatelliteKnowledge: {len(stories)} 份逐星档案和 "
        f"{len(family_stories)} 份星座共享档案校验通过；后者覆盖 {excluded} 个同质节点"
    )
    return 0


def compile_profiles(output: Path) -> int:
    stories, errors = validate_profiles()
    family_stories, family_errors = validate_family_profiles()
    errors += family_errors
    if errors:
        print("SatelliteKnowledge 编译失败：", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    document = {
        "schemaVersion": 2,
        # 使用轨道目录快照时间，保证相同 Markdown 输入得到字节稳定的产物。
        "generatedAt": catalog_document().get("generatedAt"),
        "source": "SatelliteKnowledge/Profiles + Families Markdown",
        "stories": stories,
        "familyStories": family_stories,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.write_text(json.dumps(document, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    temporary.replace(output)
    print(
        f"SatelliteKnowledge: 已编译 {len(stories)} 份逐星档案和 "
        f"{len(family_stories)} 份星座共享档案 → {output}"
    )
    return 0


def find_record(query: str) -> dict | None:
    records = catalog_objects()
    if query.isdigit():
        identifier = int(query)
        return next((record for record in records if identity(record)[0] == identifier), None)
    normalized = query.casefold().strip()
    exact = [record for record in records if identity(record)[1].casefold() == normalized]
    if len(exact) == 1:
        return exact[0]
    matches = [record for record in records if normalized in identity(record)[1].casefold()]
    if len(matches) == 1:
        return matches[0]
    if matches:
        print("名称对应多颗卫星，请使用其中一个 NORAD 编号重新执行：")
        for record in matches[:30]:
            identifier, name = identity(record)
            print(f"  {identifier:>6}  {name}")
    return None


def locate_profile(query: str) -> int:
    record = find_record(query)
    if record is None:
        print("没有找到唯一目标。", file=sys.stderr)
        return 2
    norad, name = identity(record)
    family = family_for(record)
    if family in FAMILY_TITLES:
        path = FAMILIES / f"{family}.md"
        print(f"{name} 使用 {FAMILY_TITLES[family]} 的共享档案：{path}")
        return 0 if path.exists() else 3
    existing = existing_profiles_by_norad().get(norad)
    if existing:
        print(existing)
        return 0
    path = profile_path(norad, name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_generated_profile(record), encoding="utf-8")
    print(path)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("sync", help="为全部非同质星座对象生成并整理 Markdown")
    subparsers.add_parser("validate", help="校验内容、NORAD 唯一性和全量覆盖")
    compile_parser = subparsers.add_parser("compile", help="将 Markdown 编译成 APP 运行时 JSON")
    compile_parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    locate = subparsers.add_parser("locate", help="查找某颗卫星的 Markdown 文件")
    locate.add_argument("query")
    args = parser.parse_args()
    if args.command == "sync":
        return sync_profiles()
    if args.command == "validate":
        return validate()
    if args.command == "compile":
        return compile_profiles(args.output)
    return locate_profile(args.query)


if __name__ == "__main__":
    raise SystemExit(main())
