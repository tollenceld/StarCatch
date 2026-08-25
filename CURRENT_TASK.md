# 当前任务：启动动画与卫星档案二次重构

状态：已完成（2026-08-25）

## 目标

以选定的“星历账本”生成图为视觉事实源，将启动页改成一次性系统验证，并让卫星深度档案
默认展示真实、可选择的未来 24 小时过境信息；删除用户可见的“轨道指纹”和静态椭圆补位。

## 已完成

- 将选定生成图保存为 `Documentation/DesignReferences/starcatch-ephemeris-ledger-reference.png`，
  仅用于设计对照，不加入运行时资源。
- 新增 `BootPreparationState`，由 `RootView` 在目录、轨道引擎和观测模型真实可用时逐项更新。
- 启动时间轴改为单调的一次性字形注册：不使用 blur、扫光、移动圆点或取余循环；数据延迟
  时保持稳定画面，完成后停留并让文字退场，同一片星场承接主天空。
- 深度档案导航改为“此刻／任务／数据”轻量下划线；默认页先显示用途与可信身份，再显示
  未来 24 小时地平线上方过境、可选择窗口、升起/最高点/落下曲线、方位与实时读数。
- 新增 `PassForecast` 与 `SatelliteInsightEngine.forecast`：60 秒粗采样、二分地平线交点、最多
  八个窗口、起落方位、15 分钟缓存；只在打开档案时以 utility 任务运行，关闭或切换目标取消。
- GEO / 近静止目标显示站位摘要；无未来过境显示明确空状态。摘要卡只有真实过境窗口时才
  显示紧凑过境弧。
- 删除 `OrbitFingerprintView` 和所有用户可见的“轨道指纹”文案；内部 `OrbitFingerprint`
  继续作为数值计算模型，数据页改为纯轨道参数表。
- 补齐中英文启动、预测、空状态、时间与辅助功能文案；清除了 Xcode 自动提取造成的无意义
  String Catalog 格式噪声，只保留本轮语义变化。

## 涉及文件

- `StarCatch/App/BootFieldView.swift`
- `StarCatch/App/BootSequenceView.swift`
- `StarCatch/App/RootView.swift`
- `StarCatch/Archive/ArchiveOverlay.swift`
- `StarCatch/Archive/SatelliteInsightVisuals.swift`
- `StarCatch/Archive/SatelliteStoryView.swift`
- `StarCatch/Orbits/SatelliteInsights.swift`
- `StarCatch/Sky/SkyView.swift`
- `StarCatch/Localization/Localizable.xcstrings`
- `StarCatch/Localization/SatelliteText.xcstrings`
- `StarCatchTests/TimeTests.swift`
- `Documentation/PROJECT_OVERVIEW.md`
- `Documentation/ARCHITECTURE.md`
- `Documentation/DesignReferences/starcatch-ephemeris-ledger-reference.png`
- `design-qa.md`

## 验证

- iPhone 17 Pro Simulator / iOS 26.3.1 Debug 构建通过。
- 定向测试 4 项通过：启动阶段映射、时间轴稳定不循环、完整 24 小时预测的确定性与事实边界，
  以及 GEO 静止目标不生成伪造过境曲线。
- 两个 String Catalog JSON 解析通过，中英文无空翻译；源码与文档中无“轨道指纹”用户文案。
- `git diff --check` 通过。
- 启动完成态与 HST 档案“此刻”页已和选定参考图进行两轮同屏视觉对照；首轮中文标题换行
  问题已修复，最终 `design-qa.md` 结果为 `passed`。

## 发布边界

- 本轮未修改目录快照、捕获阈值、手机姿态、筛选、观测日志或网络行为。
- 模拟器不能代替 iPhone 17 Air / 17 Pro 真机的最大动态字体、VoiceOver、Reduce Motion 和
  首次冷启动性能取样；Archive 前仍需刷新至 72 小时内目录并执行完整发布检查。
