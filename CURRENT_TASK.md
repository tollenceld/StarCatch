# 当前任务：项目接手盘点与运行基线

状态：已完成（2026-08-29）

## 目标

在不进行真机验收或大规模视觉巡检的前提下，恢复项目上下文、遍历工程结构与关键内容，
跑通模拟器应用和自动化验证，并记录后续开发可复用的接手基线。

## 已完成

- 读取 `AGENTS.md`、`PROJECT_CONTEXT.md`、产品全景、架构边界、README、XcodeGen 配置、
  发布脚本说明及当前任务记录。
- 建立全仓库文件索引；对大型同构资料与资源采用计数、结构检查、校验器和抽样阅读，完整
  盘点应用源码、测试入口、核心模型、状态所有权、并发边界和运行流程。
- 确认当前规模：45 个应用 Swift 文件、2 个测试文件、约 21,355 行 Swift；离线目录
  16,395 个对象；3,817 份逐星档案和 8 份星座共享档案。
- 确认运行链路：`RootView` 后台准备目录与档案 → `SkySession` 装配姿态、位置和星历 →
  `EphemerisEngine` 后台批量传播 → `SkyView` / `SkyOverviewView` 绘制 →
  `CaptureStateMachine` 管理感应、确认、换锁和释放 → 档案、时间轴与本地观测日志。
- 在 iPhone 17 Pro / iOS 26.3 Simulator 上完成 Debug 构建、安装和启动；主天空成功聚焦
  北斗目标，档案摘要与实时轨道读数出现；全局地球仪也成功启动并显示约 4,600 个传播目标。
- 保留接手时已有的 10 个未提交文件，不覆盖、不回滚，也不把它们混入本次交接提交。

## 验证

- `xcodebuild` / XcodeBuildMCP Debug Build & Run：通过。
- 完整单元测试：101 项中 100 项通过，1 项失败。
  - 失败项：`TimeTests.testLocalSkyAvoidsFullCatalogPropagationUntilOverviewNeedsIt`。
  - 原因已定位：当前未提交实现把全局星图传播集合改为稳定上限 `overviewObjects`（4,600），
    但旧断言仍要求 `visibleObjects`（16,395）；同文件新增测试已经断言新的 4,600 上限行为。
- `python3 Scripts/satellite_knowledge.py validate`：通过，覆盖 3,817 份逐星档案和 8 份
  星座档案。
- 两个 String Catalog JSON 解析、`Info.plist`、Privacy Manifest、`git diff --check`：通过。
- 运行日志未发现 fatal error、未捕获异常、崩溃或 assertion failure。
- 模拟器可访问性树抓取受本机 Xcode `SimulatorKit` 架构不匹配影响；已用两张定向截图完成
  启动确认，没有继续消耗时间做视觉巡检。

## 接手时已有的未提交工作

工作区已有一组连贯的“局部天空到地球仪单调转场与传播上限”改动，涉及：

- `Documentation/ARCHITECTURE.md`
- `Documentation/PROJECT_OVERVIEW.md`
- `StarCatch/Design/Motion.swift`
- `StarCatch/Localization/Localizable.xcstrings`
- `StarCatch/Localization/SatelliteText.xcstrings`
- `StarCatch/Sky/Projection.swift`
- `StarCatch/Sky/SkyOverviewView.swift`
- `StarCatch/Sky/SkySession.swift`
- `StarCatch/Sky/SkyView.swift`
- `StarCatchTests/TimeTests.swift`

这些文件未由本次盘点修改或提交。

## 下一步

1. 完成上述已有改动的收尾：把旧传播测试的期望从 `visibleObjects` 同步为
   `overviewObjects`，再重跑完整 101 项测试并审阅整组 diff。
2. 决定是否将该组地球仪改动作为独立提交；在此之前不要继续叠加无关功能。
3. 发布前刷新轨道目录。当前快照为 2026-08-20，已超过 Archive 发布门槛的 72 小时，
   但仍处于开发校验的 14 天绝对上限内。
4. 真机姿态精度、磁场环境、最大动态字体和 VoiceOver 留到明确的发布验收阶段，不作为
   日常开发的默认验证步骤。

## 本次涉及文件

- `CURRENT_TASK.md`
