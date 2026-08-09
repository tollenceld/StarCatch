# 当前任务：逐星资料真实性、唯一性与发布防回退

状态：已完成（2026-08-09）

## 目标

清除卫星资料中的模板、占位和重复内容；让用户连续切换目标时，紧凑摘要与完整档案都以当前真实轨道对象为主体，同时不为公开资料没有确认的载荷或运营方编造结论。

## 已完成

- 新增确定性资料引擎，以名称、NORAD、COSPAR 发射分件、同批对象、OMM 周期、倾角、离心率及估算近远地点生成逐星内容。
- 为可由公开任务名称可靠识别的 NASA、NOAA、ESA、EUMETSAT、GPS、Galileo、北斗、JAXA、ISRO 及主要通信星座加入具体任务说明、机构和官方来源。
- 对身份不明的条目明确公开 OMM 的资料边界，不再显示“运营方待核实”或邀请后续替换的占位段落；仍提供该对象独有且可验证的轨道与发射关系。
- 重建 3,814 份 `review_status: generated` 的逐星 Markdown，保留 18 份人工迁移/整理档案；重新编译 3,832 份逐星档案。
- 刷新 16,216 条自动首层摘要。完整 16,243 个目录对象的首层文案现在逐条唯一，且把唯一身份放在两行摘要的句首。
- 大型星座继续共享项目历史以控制包体，但每个节点的摘要、完整档案标题、项目行、身份章节和发射标记均按当前对象个性化；Starlink 等节点之间不再打开同一张完整页面。
- `sync` 现在只重建仍标记为 `generated` 的内容，人工内容不覆盖；未来 `update_catalog.py` 也会直接使用同一资料引擎。
- 校验与发布门禁新增首层摘要唯一性、逐星档案摘要唯一性、空内容及占位词检查。
- 更新资料库和发布脚本文档，说明自动内容、人工内容与大型星座背景的所有权。

## 主要涉及文件

- `Scripts/satellite_content.py`
- `Scripts/satellite_knowledge.py`
- `Scripts/update_catalog.py`
- `Scripts/release_check.py`
- `SatelliteKnowledge/Profiles/`
- `SatelliteKnowledge/Families/`
- `SatelliteKnowledge/README.md`
- `StarCatch/Resources/catalog.json`
- `StarCatch/Resources/satellite_profiles.json`
- `StarCatch/Archive/SatelliteStories.swift`
- `StarCatch/Orbits/CatalogModels.swift`
- `StarCatchTests/OrbitTests.swift`

## 验证

- `python3 Scripts/satellite_knowledge.py validate` 通过：3,832 份逐星档案、8 份星座背景档案，覆盖 16,243 个对象。
- 数据审计通过：16,243 / 16,243 条首层摘要唯一；3,832 / 3,832 条逐星档案摘要唯一；旧占位短语和 `OPERATOR TO BE VERIFIED` 均为 0。
- `python3 Scripts/release_check.py --now 2026-08-08T00:00:00+00:00` 通过，用固定时间验证新增发布门禁而不伪装刷新轨道快照。
- iPhone 17 Pro / iOS 26.3 模拟器构建通过；2 项定向测试通过，覆盖全目录首层唯一性和大型星座节点完整档案差异。
- `git diff --check` 通过。

## 下一步

- 下一次 App Store 归档前按既有发布流程刷新 CelesTrak 快照；当前任务没有联网替换轨道元素或改写快照时间。
- 若后续人工核实某颗卫星的载荷与运营方，将对应 Markdown 的 `review_status` 改为 `reviewed`，后续目录同步会保留人工资料。
