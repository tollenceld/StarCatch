# 当前任务：卫星信息系统可信分层与全量差异化

状态：已完成（2026-08-21）

## 目标

让全部随包轨道目标使用同一套“目录事实、本机推算、本星官方资料、系列官方资料、
StarCatch 分类”可信体系；连续对焦时优先展示随目标和时刻变化的真实信息，并保持
锁定摘要立即出现、深度档案可追溯、主天空 Canvas 性能不随目录规模增长。

## 已完成

- 将离线资料资源升级为 schema v3。导语、章节、事实和里程碑分别关联结构化来源 ID；
  来源记录包含 URL、可信类型、object/family 范围、获取日期和核验日期。
- 修正状态与分类语义：`ACTIVE` 不再冒充运营状态，改为“轨道在列”；未知载荷、运营方
  和用途保持未知；StarCatch 浏览分类明确标注为推断，不再描述成 GP/OMM 原始字段。
- 新增会话级 `SatelliteInsightEngine`，只在目标进入感应范围后异步生成星下点、距离
  趋势、完整过境窗口、轨道指纹、同次发射批次和系列中位数差异。缓存使用目标、粗粒度
  位置与五分钟时间桶，旧目标任务由 SwiftUI task identity 自动取消。
- 摘要卡先用已有星历和目录指纹立即出现；24 小时过境扫描在 utility 任务完成后以固定
  高度图形补齐，不在 Canvas、`body` 或点击回调同步计算。
- 微型标签保持 `COSPAR · 距离 · 轨道`。锁定摘要重构为可信状态、名称、单条当前洞察、
  微型过境弧/轨道指纹、距离/高度/速度和整合式“查看档案”。
- 深度档案固定为当前观测、轨道指纹、当前目标、任务/系列资料、历程与来源五个模块；
  使用 SwiftUI Canvas 细线图形，提供 VoiceOver 描述并适配减少动态效果。
- 大型星座共享核实后的系列背景，但每个节点的名称、NORAD/COSPAR、轨道指纹、发射批次、
  系列相对位置和实时洞察独立，不靠随机文案制造新鲜感。
- 发布资料脚本增加来源闭合、范围、可信类型、模板断言与 72 小时目录龄期门禁；14 天只
  保留为开发生成器拒绝陈旧元素的绝对上限。
- 从 CelesTrak 刷新 2026-08-20 快照：16,395 个对象；同步 3,817 份逐星档案与 8 份
  系列档案，后者覆盖 12,578 个同质节点。分类变化后移除 34 份已转入系列共享范围的
  旧生成档案，并新增 11 份当前独立目标档案。

## 主要涉及文件

- `StarCatch/Orbits/SatelliteInsights.swift`
- `StarCatch/Orbits/CatalogModels.swift`
- `StarCatch/Orbits/CatalogStore.swift`
- `StarCatch/Sky/SkySession.swift`
- `StarCatch/Sky/SkyView.swift`
- `StarCatch/Archive/SatelliteInsightVisuals.swift`
- `StarCatch/Archive/ArchiveOverlay.swift`
- `StarCatch/Archive/SatelliteStories.swift`
- `StarCatch/Archive/SatelliteStoryView.swift`
- `Scripts/satellite_content.py`
- `Scripts/satellite_knowledge.py`
- `Scripts/release_check.py`
- `StarCatch/Resources/catalog.json`
- `StarCatch/Resources/satellite_profiles.json`
- `SatelliteKnowledge/`
- `StarCatchTests/OrbitTests.swift`
- `StarCatchTests/TimeTests.swift`
- `Documentation/ARCHITECTURE.md`
- `Documentation/PROJECT_OVERVIEW.md`

## 验证

- `xcodegen generate` 通过；iOS Simulator Debug 构建成功。
- iPhone Air / iOS 26.3 模拟器安装和启动通过；截图核验锁定摘要与五段式深度档案。
- 94 项 `OrbitTests` / `TimeTests` 全部通过，新增全目录来源引用闭合、资料范围、轨道
  指纹/批次确定性，以及过境窗口、距离趋势、星下点和缓存一致性测试。
- `satellite_knowledge.py validate` 通过：3,817 份逐星档案、8 份系列档案，完整覆盖
  16,395 个目标。
- `release_check.py` 通过：16,395 个对象，目录年龄低于 72 小时，隐私、图标、依赖锁、
  schema v3 与来源关系均通过。
- 首次自动对焦 12 秒 Time Profiler 采样未发现超过 250ms 的 StarCatch micro-hang；
  洞察入口只在主线程提交任务，24 小时传播计算不在 Canvas 或卡片 `body` 中执行。
- `git diff --check` 通过。

## 精度边界与下一步

- CelesTrak GP/OMM 是平均轨道元素，不是运营遥测或碰撞评估；“轨道在列”只表示公开目录
  仍含该对象。用户主动打开的外部链接也不能被当作运行时状态证明。
- 模拟器不能验证磁力计、真北、真实握持和户外可读性。发布前仍需在 iPhone 17 系列真机
  连续对焦至少 20 个不同目标，核对卡片即时出现、后台洞察补齐、VoiceOver 和温升。
- 官方图片仍未引入：当前没有把授权不明确的媒体混入档案，也没有为无图目标保留占位框。
  后续若精选任务增加图片，必须同时保存来源、授权和署名。
