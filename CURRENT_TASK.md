# 当前任务：Cloud Code 项目接手与运行基线

状态：已完成（2026-08-30）

## 目标

在保留工作区既有未提交改动的前提下，用低成本的静态盘点、源码链路阅读、模拟器编译运行和
自动化测试接手 StarCatch；不做无意义的真机或逐像素视觉巡检。

## 已完成

- 按 `AGENTS.md` 顺序恢复 `PROJECT_CONTEXT.md`、原 `CURRENT_TASK.md`、Git 分支和工作区状态；
  当前位于 `main`，开始时已有 9 个被修改文件，未对它们做覆盖、回滚或暂存。
- 建立仓库文件地图：3,949 个受跟踪文件，其中 50 个 Swift 源文件、3 个 Swift 测试文件、
  3,833 份 `SatelliteKnowledge` 资料文件，以及 4 个主要二进制/JSON 运行时资源。
- 逐层阅读 README、产品说明、架构边界、XcodeGen 配置、发布脚本入口、测试清单和全部 Swift
  类型/方法索引；细读启动、会话装配、目录、指向、SGP4 传播、捕获状态机、时间轴、主天空、
  三维地球、拖尾、档案与观测日志的关键实现。
- 确认运行链路：`RootView` 首帧显示无 IO 的预设轨道地球电影，同时后台解码目录并预热单目标
  传播；`SkySession` 选择真机 CoreMotion 或模拟器手动指向；`EphemerisEngine` 后台传播稳定样本，
  `SkyView` 以 30fps Canvas 消费缓存并由 `CaptureStateMachine` 管理识别/锁定；全局地球独立承载
  Arcball、缩放、±24 小时时钟、J2000 恒星与有界空间拖尾。
- 审阅现有未提交改动：主要语义是把旧启动说明/账本改为统一的约 3.2 秒轨道地球电影，并保证
  地球交互降级时仍显示编译期基础海岸线；相关文档与 `TimeTests` 已同步。两个 String Catalog 的
  大部分 diff 是 Xcode 写入 `extractionState: stale`，实际新增键只有 `00H/06H/12H/18H/24H`。
- 未运行 `xcodegen generate`：本轮没有工程结构变化，现有 `StarCatch.xcodeproj` 已直接编译通过，
  避免制造无关的生成工程 diff。

## 验证

- iPhone 17 / iOS 26.3 Simulator，Debug Build & Run：通过；App 安装并启动为
  `com.starcatch.StarCatch`，进程持续存活。
- 完整测试集：110/110 通过，0 failed，0 skipped；唯一编译警告是
  `StarCatchTests/OrbitTests.swift:723` 的 `try` 包裹了不抛错调用。
- 运行日志只有模拟器的 `IOSurfaceClientSetSurfaceNotify` 和 AppleColorEmoji fallback 提示，未发现
  App 崩溃或业务错误。
- 语义 UI 树采集不可用：本机 Xcode 的 SimulatorKit 不包含当前进程架构版本；这属于 UI 自动化
  工具环境问题，不影响构建、安装、启动或测试结论，因此未继续做截图/视觉巡检。
- 已登记的 iPhone Air Simulator 数据目录缺失，第一次启动在编译前失败；未擦除或重建该设备，
  改用健康的 iPhone 17 后一次通过。
- `git diff --check` 通过；构建与测试没有产生新的未忽略文件，只有既有 `.obsidian` 与
  `xcuserdata` 保持被忽略。

## 本次涉及文件

- `CURRENT_TASK.md`

## 下一步

1. 先由开发者确认当前 9 个未提交文件是否就是需要继续保留的 Cloud Code 启动电影改版；确认后
   可做一次范围单一的 diff 审阅并提交，避免 String Catalog 的提取状态噪声掩盖语义变化。
2. 后续功能修改应沿 `RootView → SkySession → EphemerisEngine / CaptureStateMachine → SkyView`
   的既有状态所有权扩展；不要把 IO、全目录传播或 24 小时过境扫描放进 30fps Canvas 路径。
3. 发布 Archive 前必须刷新轨道目录；当前随包快照为 2026-08-20，已超过 72 小时发布门禁，
   但不影响本地功能开发与本次运行基线。
4. 真机验证只留给姿态/真北、定位视差、触觉和最终发布验收；普通 UI 与业务改动优先使用相关
   单测加一次 Simulator Debug 编译。
