#!/usr/bin/env python3
"""Deterministic, factual copy for every object in StarCatch's offline catalog.

The public GP/OMM feed is an orbit record, not a mission encyclopedia.  This
module therefore separates claims that can be identified from an object's name
from facts derived directly from its catalog identity and mean elements.  It
never invents a payload or operator for an unidentified object.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Any, Iterable


EARTH_MU_KM3_S2 = 398_600.4418
EARTH_EQUATORIAL_RADIUS_KM = 6_378.137
CELESTRAK_SOURCE = (
    "CelesTrak · GP/OMM 轨道目录 · "
    "https://celestrak.org/NORAD/documentation/gp-data-formats.php"
)
NASA_ORBIT_SOURCE = (
    "NASA Earth Observatory · 轨道、倾角与离心率参考 · "
    "https://science.nasa.gov/earth/earth-observatory/catalog-of-earth-satellite-orbits/"
)


@dataclass(frozen=True)
class MissionRule:
    tokens: tuple[str, ...]
    summary: str
    organization: str
    source: str


# Only use program ownership that can be identified reliably from a public
# mission/constellation name.  Order matters: specific programs precede broad
# name families.
MISSION_RULES: tuple[MissionRule, ...] = (
    MissionRule(
        ("ISS (ZARYA)", "ZARYA"),
        "国际空间站是一座持续有人驻留的轨道实验室，支持微重力研究、地球观测与技术验证。",
        "INTERNATIONAL SPACE STATION PARTNERS",
        "NASA · International Space Station · https://www.nasa.gov/international-space-station/",
    ),
    MissionRule(
        ("HST", "HUBBLE"),
        "哈勃空间望远镜在大气层之外收集紫外、可见光与近红外光，持续改变人类观察宇宙的尺度。",
        "NASA · ESA",
        "NASA · Hubble Space Telescope · https://science.nasa.gov/mission/hubble/",
    ),
    MissionRule(
        ("LANDSAT",),
        "Landsat 长期记录陆地的光谱与热信息，用来辨认城市、农田、水体和森林如何变化。",
        "NASA · USGS",
        "USGS · Landsat Missions · https://www.usgs.gov/landsat-missions",
    ),
    MissionRule(
        ("SENTINEL-1",),
        "Copernicus Sentinel-1 使用雷达在昼夜和多云条件下记录陆地、海冰与海面变化。",
        "EUROPEAN UNION · ESA · COPERNICUS",
        "ESA · Sentinel-1 · https://www.esa.int/Applications/Observing_the_Earth/Copernicus/Sentinel-1",
    ),
    MissionRule(
        ("SENTINEL-2",),
        "Copernicus Sentinel-2 以多光谱影像长期记录植被、土地利用、海岸与灾害现场。",
        "EUROPEAN UNION · ESA · COPERNICUS",
        "ESA · Sentinel-2 · https://www.esa.int/Applications/Observing_the_Earth/Copernicus/Sentinel-2",
    ),
    MissionRule(
        ("SENTINEL-3",),
        "Copernicus Sentinel-3 综合测量海色、海陆表面温度与海面高度，连接海洋和陆地记录。",
        "EUROPEAN UNION · ESA · EUMETSAT",
        "ESA · Sentinel-3 · https://www.esa.int/Applications/Observing_the_Earth/Copernicus/Sentinel-3",
    ),
    MissionRule(
        ("SENTINEL-5P",),
        "Sentinel-5P 从全球尺度读取臭氧、氮氧化物、甲烷和气溶胶等大气成分。",
        "EUROPEAN UNION · ESA · COPERNICUS",
        "ESA · Sentinel-5P · https://www.esa.int/Applications/Observing_the_Earth/Copernicus/Sentinel-5P",
    ),
    MissionRule(
        ("SENTINEL-6",),
        "Sentinel-6 以雷达测高延续全球海平面高度记录，为气候研究和业务海洋学提供基准。",
        "EU · ESA · NASA · NOAA · EUMETSAT",
        "ESA · Sentinel-6 · https://www.esa.int/Applications/Observing_the_Earth/Copernicus/Sentinel-6",
    ),
    MissionRule(
        ("NOAA 20", "NOAA 21", "JPSS", "SUOMI NPP"),
        "这颗极轨气象卫星反复覆盖全球，为天气预报、灾害监测与长期气候记录提供观测。",
        "NOAA · NASA · JPSS",
        "NOAA · Joint Polar Satellite System · https://www.nesdis.noaa.gov/our-satellites/currently-flying/joint-polar-satellite-system",
    ),
    MissionRule(
        ("GOES",),
        "GOES 从地球同步轨道持续凝视同一大片区域，追踪云系、强对流与热带气旋的快速变化。",
        "NOAA · NASA",
        "NOAA · GOES-R Series · https://www.nesdis.noaa.gov/our-satellites/currently-flying/goes-r-series",
    ),
    MissionRule(
        ("TERRA",),
        "Terra 用多台仪器同时观察大气、陆地、海洋与能量交换，把地球作为相互连接的系统来阅读。",
        "NASA EARTH SCIENCE",
        "NASA · Terra · https://science.nasa.gov/mission/terra/",
    ),
    MissionRule(
        ("AQUA",),
        "Aqua 围绕地球水循环工作，观察云、降水、水汽、海冰、积雪以及海陆表面温度。",
        "NASA EARTH SCIENCE",
        "NASA · Aqua · https://science.nasa.gov/mission/aqua/",
    ),
    MissionRule(
        ("SWOT",),
        "SWOT 用宽幅雷达测高同时读取海洋与陆地水体，描绘河流、湖泊和海面高度的细微变化。",
        "NASA · CNES · CSA · UK SPACE AGENCY",
        "NASA · SWOT · https://science.nasa.gov/mission/swot/",
    ),
    MissionRule(
        ("ICESAT",),
        "ICESat 使用激光测高读取冰盖、海冰、森林与地表高度，追踪冰冻圈和地形变化。",
        "NASA EARTH SCIENCE",
        "NASA · ICESat-2 · https://science.nasa.gov/mission/icesat-2/",
    ),
    MissionRule(
        ("SMAP",),
        "SMAP 测量表层土壤水分与冻融状态，帮助理解水、能量和碳在陆地表面的交换。",
        "NASA EARTH SCIENCE",
        "NASA · SMAP · https://science.nasa.gov/mission/smap/",
    ),
    MissionRule(
        ("NAVSTAR", "GPS ", "GPS-"),
        "GPS 卫星广播精密时间与轨道信息，使接收机能够计算位置、速度与时间。",
        "UNITED STATES SPACE FORCE · GPS",
        "GPS.gov · Space Segment · https://www.gps.gov/systems/gps/space/",
    ),
    MissionRule(
        ("GALILEO",),
        "Galileo 在中地轨道广播欧洲民用全球导航信号，为定位、导航、授时与搜救服务提供空间基准。",
        "EUROPEAN UNION · EUSPA · ESA",
        "ESA · Galileo · https://www.esa.int/Applications/Satellite_navigation/Galileo",
    ),
    MissionRule(
        ("BEIDOU",),
        "北斗卫星广播导航与授时信号；不同轨道层的节点共同构成全球定位服务。",
        "BEIDOU NAVIGATION SATELLITE SYSTEM",
        "BeiDou Navigation Satellite System · http://en.beidou.gov.cn/",
    ),
    MissionRule(
        ("GLONASS",),
        "GLONASS 中轨节点广播导航与授时信号，与其他节点共同维持全球定位覆盖。",
        "GLONASS NAVIGATION SYSTEM",
        "ISS Reshetnev · GLONASS · https://www.iss-reshetnev.com/projects",
    ),
    MissionRule(
        ("MICHIBIKI", "QZS"),
        "日本准天顶卫星系统通过高仰角可见性增强定位、导航与授时服务。",
        "JAPAN QZSS",
        "Cabinet Office Japan · QZSS · https://qzss.go.jp/en/",
    ),
    MissionRule(
        ("IRNSS",),
        "NavIC 是印度区域导航系统，利用轨道节点提供定位与授时服务。",
        "ISRO · NAVIC",
        "ISRO · NavIC · https://www.isro.gov.in/Navigation.html",
    ),
    MissionRule(
        ("TDRS",),
        "TDRS 是 NASA 空间网络的数据中继节点，为近地航天器与地面之间维持高覆盖通信。",
        "NASA SPACE NETWORK",
        "NASA · Tracking and Data Relay Satellites · https://www.nasa.gov/directorates/somd/space-communications-navigation-program/tdrs/",
    ),
    MissionRule(
        ("HIMAWARI",),
        "Himawari 从地球同步轨道连续观察亚太区域的云系、大气与快速发展的天气过程。",
        "JAPAN METEOROLOGICAL AGENCY",
        "JMA · Himawari · https://www.jma.go.jp/jma/jma-eng/satellite/",
    ),
    MissionRule(
        ("METOP",),
        "Metop 从极轨测量大气温湿廓线、海面风与痕量气体，为数值天气预报提供输入。",
        "EUMETSAT · ESA",
        "EUMETSAT · Metop · https://www.eumetsat.int/metop",
    ),
    MissionRule(
        ("FENGYUN 4", "FY-4"),
        "风云四号从地球同步轨道持续观察云系、大气与强天气演变。",
        "CHINA METEOROLOGICAL ADMINISTRATION",
        "CMA · FY-4 · https://www.cma.gov.cn/en2014/satellites/",
    ),
    MissionRule(
        ("FENGYUN", "FY-"),
        "风云系列以极轨或静止轨道观测云、大气、海陆表面与空间环境，服务天气和气候业务。",
        "CHINA METEOROLOGICAL ADMINISTRATION",
        "CMA · Meteorological satellites · https://www.cma.gov.cn/en2014/satellites/",
    ),
    MissionRule(
        ("GOSAT",),
        "GOSAT 读取大气中的二氧化碳与甲烷分布，延续全球温室气体长期记录。",
        "JAXA · NIES · JAPAN MOE",
        "JAXA · GOSAT · https://global.jaxa.jp/projects/sat/gosat/",
    ),
    MissionRule(
        ("ALOS",),
        "ALOS 以雷达或光学载荷观察陆地，用于测绘、灾害响应、森林与地表变化研究。",
        "JAXA",
        "JAXA · ALOS · https://global.jaxa.jp/projects/sat/alos/",
    ),
    MissionRule(
        ("CARTOSAT", "RESOURCESAT", "OCEANSAT", "RISAT", "EOS-"),
        "这颗印度地球观测卫星服务于测绘、资源、海洋、农业或灾害等公开遥感应用。",
        "ISRO · EARTH OBSERVATION",
        "ISRO · Earth Observation Satellites · https://www.isro.gov.in/EarthObservationSatellites.html",
    ),
    MissionRule(
        ("GAOFEN",),
        "高分系列以高分辨率对地观测服务于国土、农业、环境与灾害等遥感应用。",
        "CHINA EARTH OBSERVATION PROGRAM",
        "UNOOSA · Space object registration records · https://www.unoosa.org/oosa/en/spaceobjectregister/index.html",
    ),
    MissionRule(
        ("HAIYANG",),
        "海洋系列读取海色、海面动力或海洋环境变量，为海洋研究与监测提供轨道观测。",
        "CHINA EARTH OBSERVATION PROGRAM",
        "UNOOSA · Space object registration records · https://www.unoosa.org/oosa/en/spaceobjectregister/index.html",
    ),
    MissionRule(
        ("YAOGAN",),
        "公开目录将它识别为遥感系列；未公开的具体载荷和用途不在这里推测。",
        "PUBLICLY REGISTERED REMOTE-SENSING SERIES",
        "UNOOSA · Space object registration records · https://www.unoosa.org/oosa/en/spaceobjectregister/index.html",
    ),
    MissionRule(
        ("SHIJIAN", "SHIYAN"),
        "它属于公开登记的空间技术试验系列；未公开的具体载荷不在这里推测。",
        "PUBLICLY REGISTERED TECHNOLOGY SERIES",
        "UNOOSA · Space object registration records · https://www.unoosa.org/oosa/en/spaceobjectregister/index.html",
    ),
    MissionRule(
        ("STARLINK",),
        "Starlink 是近地轨道宽带网络；单颗卫星是不断越过地平线并与其他节点接续覆盖的一部分。",
        "SPACEX · STARLINK",
        "SpaceX · Starlink · https://www.spacex.com/starlink",
    ),
    MissionRule(
        ("ONEWEB",),
        "OneWeb 节点分布在同步规划的近极轨道面，为陆地、海洋与航空连接提供低时延链路。",
        "EUTELSAT ONEWEB",
        "Eutelsat · OneWeb LEO constellation · https://www.eutelsat.com/satellite-network/oneweb-leo-constellation",
    ),
    MissionRule(
        ("IRIDIUM",),
        "Iridium 以高倾角低轨节点支持全球移动语音与数据通信，也覆盖高纬度和远洋区域。",
        "IRIDIUM COMMUNICATIONS",
        "Iridium · Network · https://www.iridium.com/network/",
    ),
    MissionRule(
        ("GLOBALSTAR",),
        "Globalstar 低轨节点把移动终端的语音或数据链路转交给可见地面网关。",
        "GLOBALSTAR",
        "Globalstar · Technology · https://www.globalstar.com/en-us/about/our-technology",
    ),
    MissionRule(
        ("ORBCOMM",),
        "ORBCOMM 轨道节点面向物联网、资产跟踪与偏远设备的窄带数据通信。",
        "ORBCOMM",
        "ORBCOMM · Satellite network · https://www.orbcomm.com/",
    ),
)


def value(record: dict[str, Any], generated: str, legacy: str, default: Any = None) -> Any:
    return record.get(generated, record.get(legacy, default))


def identity(record: dict[str, Any]) -> tuple[int, str]:
    return int(value(record, "NORAD_CAT_ID", "noradId", 0)), str(
        value(record, "OBJECT_NAME", "name", "UNIDENTIFIED OBJECT")
    )


def cospar_id(record: dict[str, Any]) -> str:
    return str(value(record, "OBJECT_ID", "cosparId", "—") or "—")


def launch_key(record: dict[str, Any]) -> str | None:
    match = re.match(r"^(\d{4}-\d{3})", cospar_id(record))
    return match.group(1) if match else None


def launch_piece(record: dict[str, Any]) -> str | None:
    match = re.match(r"^\d{4}-\d{3}([A-Z]+)$", cospar_id(record).upper())
    return match.group(1) if match else None


class CatalogContext:
    def __init__(self, records: Iterable[dict[str, Any]]) -> None:
        self.records = list(records)
        cohorts: dict[str, list[dict[str, Any]]] = {}
        for record in self.records:
            if key := launch_key(record):
                cohorts.setdefault(key, []).append(record)
        self.cohorts = {
            key: sorted(items, key=lambda item: (cospar_id(item), identity(item)[0]))
            for key, items in cohorts.items()
        }

    def cohort(self, record: dict[str, Any]) -> list[dict[str, Any]]:
        key = launch_key(record)
        return self.cohorts.get(key, []) if key else []


@dataclass(frozen=True)
class OrbitFacts:
    mean_motion: float | None
    period_minutes: float | None
    inclination_degrees: float | None
    eccentricity: float | None
    semimajor_axis_km: float | None
    mean_altitude_km: float | None
    perigee_km: float | None
    apogee_km: float | None


def _number(record: dict[str, Any], key: str) -> float | None:
    try:
        return float(record[key])
    except (KeyError, TypeError, ValueError):
        return None


def orbit_facts(record: dict[str, Any]) -> OrbitFacts:
    mean_motion = _number(record, "MEAN_MOTION")
    inclination = _number(record, "INCLINATION")
    eccentricity = _number(record, "ECCENTRICITY")
    if not mean_motion or mean_motion <= 0:
        return OrbitFacts(mean_motion, None, inclination, eccentricity, None, None, None, None)
    period_minutes = 1_440.0 / mean_motion
    radians_per_second = mean_motion * 2.0 * math.pi / 86_400.0
    semimajor_axis = (EARTH_MU_KM3_S2 / radians_per_second**2) ** (1.0 / 3.0)
    mean_altitude = semimajor_axis - EARTH_EQUATORIAL_RADIUS_KM
    perigee = None if eccentricity is None else semimajor_axis * (1.0 - eccentricity) - EARTH_EQUATORIAL_RADIUS_KM
    apogee = None if eccentricity is None else semimajor_axis * (1.0 + eccentricity) - EARTH_EQUATORIAL_RADIUS_KM
    return OrbitFacts(
        mean_motion,
        period_minutes,
        inclination,
        eccentricity,
        semimajor_axis,
        mean_altitude,
        perigee,
        apogee,
    )


def mission_rule(record: dict[str, Any]) -> MissionRule | None:
    upper = f"{identity(record)[1].upper()} "
    for rule in MISSION_RULES:
        if any(token in upper for token in rule.tokens):
            return rule
    return None


def category_title(record: dict[str, Any]) -> str:
    category = str(value(record, "STARCATCH_CATEGORY", "category", "exploration"))
    return {
        "exploration": "科学、实验或其他公开轨道对象",
        "observation": "地球与大气观测对象",
        "network": "通信或导航网络节点",
        "legacy": "轨道历史对象",
    }.get(category, "公开轨道对象")


def kind_title(record: dict[str, Any]) -> str:
    kind = str(value(record, "STARCATCH_KIND", "kind", "science"))
    return {
        "science": "科学或技术任务",
        "weather": "气象任务",
        "comms": "通信节点",
        "nav": "导航授时节点",
        "station": "载人空间设施",
        "telescope": "空间望远镜",
        "rocket_body": "火箭体",
        "debris": "轨道碎片",
    }.get(kind, "轨道对象")


def organization_for(record: dict[str, Any]) -> str:
    if rule := mission_rule(record):
        return rule.organization
    norad, _ = identity(record)
    # This label states what the record is; it deliberately does not fill an
    # unknown operator field with a guess.
    return f"PUBLIC ORBIT RECORD · N{norad}"


def mission_summary(record: dict[str, Any]) -> str:
    if rule := mission_rule(record):
        return rule.summary
    return (
        f"公开 GP/OMM 条目把它记录为{category_title(record)}；"
        "条目本身不包含足以确认载荷和运营方的任务说明，因此这里不作推测。"
    )


def period_text(minutes: float | None) -> str:
    if minutes is None:
        return "周期未包含在当前历史记录中"
    if minutes < 180:
        return f"约 {minutes:.1f} 分钟绕地一周"
    hours = minutes / 60.0
    if hours < 30:
        return f"约 {hours:.2f} 小时绕地一周"
    return f"约 {hours / 24.0:.2f} 天绕地一周"


def inclination_text(degrees: float | None) -> str:
    if degrees is None:
        return "轨道倾角未包含在当前历史记录中"
    if degrees < 5:
        return f"{degrees:.1f}° 的近赤道轨道"
    if degrees < 30:
        return f"{degrees:.1f}° 的低倾角轨道"
    if degrees < 75:
        return f"{degrees:.1f}° 的中倾角轨道"
    if degrees <= 105:
        return f"{degrees:.1f}° 的近极轨道"
    return f"{degrees:.1f}° 的逆行高倾角轨道"


def shape_text(eccentricity: float | None) -> str:
    if eccentricity is None:
        return "当前历史记录没有可用离心率"
    if eccentricity < 0.002:
        return f"离心率 {eccentricity:.5f}，轨道非常接近圆形"
    if eccentricity < 0.02:
        return f"离心率 {eccentricity:.5f}，轨道整体接近圆形"
    if eccentricity < 0.25:
        return f"离心率 {eccentricity:.4f}，近远地点差异清晰可见"
    return f"离心率 {eccentricity:.4f}，属于显著拉长的椭圆轨道"


def cohort_sentence(record: dict[str, Any], context: CatalogContext) -> str:
    cohort = context.cohort(record)
    key = launch_key(record)
    piece = launch_piece(record)
    if not key:
        return "当前条目没有完整国际编号，因此无法仅凭本地目录可靠关联同次发射对象。"
    if len(cohort) <= 1:
        suffix = f"，它是其中的 {piece} 号分件" if piece else ""
        return f"当前离线快照只保留了 {key} 这次发射的这一条在轨记录{suffix}。"
    current_index = next(
        (index for index, item in enumerate(cohort, 1) if identity(item)[0] == identity(record)[0]),
        1,
    )
    companions = [identity(item)[1] for item in cohort if identity(item)[0] != identity(record)[0]][:2]
    companion_text = "、".join(companions)
    suffix = f"；同批还可见 {companion_text}" if companion_text else ""
    piece_text = f"{piece} 号分件" if piece else f"第 {current_index} 条记录"
    return (
        f"国际编号把它标为 {key} 发射中的{piece_text}。"
        f"当前快照收录同批 {len(cohort)} 个在轨对象，它按编号排序位于第 {current_index} 位{suffix}。"
    )


def identity_sentence(record: dict[str, Any]) -> str:
    norad, _ = identity(record)
    cospar = cospar_id(record)
    facts = orbit_facts(record)
    if facts.period_minutes is None:
        return f"当前目标是 {cospar} / N{norad}；它的历史记录不再提供可用于推算的现代 OMM 元素。"
    return (
        f"当前目标是 {cospar} / N{norad}：{period_text(facts.period_minutes)}，"
        f"沿{inclination_text(facts.inclination_degrees)}运行。"
    )


def unique_summary(record: dict[str, Any]) -> str:
    # The compact card is limited to two lines.  Put the unique orbital identity
    # first so two nodes from the same program never look identical before the
    # longer mission sentence is clipped.
    return f"{identity_sentence(record)} {mission_summary(record)}"


def orbit_chapter(record: dict[str, Any]) -> str:
    facts = orbit_facts(record)
    if facts.period_minutes is None:
        return (
            "这是一条为历史阅读保留的目录记录。实时天空不会把过期元素伪装成当前位置；"
            "名称、NORAD 与国际编号仍用于说明它在轨道史中的身份。"
        )
    height = ""
    if facts.perigee_km is not None and facts.apogee_km is not None:
        if abs(facts.apogee_km - facts.perigee_km) < 40:
            height = f"平均轨道高度约 {facts.mean_altitude_km:.0f} 千米。"
        else:
            height = f"由当前平均元素估算，近地点约 {facts.perigee_km:.0f} 千米、远地点约 {facts.apogee_km:.0f} 千米。"
    return (
        f"它{period_text(facts.period_minutes)}，运行在{inclination_text(facts.inclination_degrees)}上。"
        f"{height}{shape_text(facts.eccentricity)}。这些数值描述轨道元素历元附近的结构，并不是永久不变的轨道铭牌。"
    )


def orbit_fact_pairs(record: dict[str, Any]) -> list[tuple[str, str]]:
    facts = orbit_facts(record)
    pairs: list[tuple[str, str]] = []
    if facts.period_minutes is not None:
        pairs.append(("周期", period_text(facts.period_minutes).replace("绕地一周", "")))
    if facts.inclination_degrees is not None:
        pairs.append(("倾角", f"{facts.inclination_degrees:.2f}°"))
    if facts.eccentricity is not None:
        pairs.append(("离心率", f"{facts.eccentricity:.6f}"))
    if facts.perigee_km is not None and facts.apogee_km is not None:
        pairs.append(("估算近 / 远地点", f"{facts.perigee_km:.0f} / {facts.apogee_km:.0f} KM"))
    return pairs


def sources_for(record: dict[str, Any]) -> list[str]:
    sources = [CELESTRAK_SOURCE, NASA_ORBIT_SOURCE]
    if rule := mission_rule(record):
        sources.insert(0, rule.source)
    return sources
