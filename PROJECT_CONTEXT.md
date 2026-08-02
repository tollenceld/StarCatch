# StarCatch 稳定项目背景

## 项目定位

StarCatch 是一款 iPhone 人造天体观察器：用户举起手机指向天空，应用依据设备姿态、真北方向、观察者位置和本地轨道数据，识别视野中的卫星、空间站、望远镜及轨道残骸，并以离线档案呈现。它不是相机识别器，也不依赖账户、广告、分析或运行时网络请求。

## 技术与工程结构

- 平台：iOS 17+，SwiftUI，竖屏全屏 iPhone 应用。
- 工程：`project.yml` 是 XcodeGen 唯一来源；生成的 `StarCatch.xcodeproj` 用于直接打开 Xcode。
- 运行时：CoreMotion + CoreLocation 提供指向和观察者信息；SatelliteKit 在设备本地执行 SGP4；随包数据位于 `StarCatch/Resources/`。
- 资料：`SatelliteKnowledge/` 保存逐星与星座 Markdown；`Scripts/` 负责目录更新、资料校验和构建期编译。
- 测试：`StarCatchTests/` 覆盖轨道、时间、状态机和资料完整性。

## 重要约束

状态所有权、并发边界、渲染性能、工程生成和分级验证规则集中记录在 [`Documentation/ARCHITECTURE.md`](Documentation/ARCHITECTURE.md)。产品功能、目录规模和发布背景集中记录在 [`Documentation/PROJECT_OVERVIEW.md`](Documentation/PROJECT_OVERVIEW.md)；不要在本文件复制那两份长文档。

仓库中只保存可审阅的源文件与经过挑选的发布资产。DerivedData、Xcode 用户状态、SwiftPM/依赖构建目录、Python 缓存、日志、本机环境变量和签名/凭据文件都不应进入 Git；具体忽略规则见 [`.gitignore`](.gitignore)。

## 交接入口

- 长期规则：[`AGENTS.md`](AGENTS.md)
- 当前任务：[`CURRENT_TASK.md`](CURRENT_TASK.md)
- 产品与架构：[`Documentation/PROJECT_OVERVIEW.md`](Documentation/PROJECT_OVERVIEW.md)、[`Documentation/ARCHITECTURE.md`](Documentation/ARCHITECTURE.md)
- 常用入口：[`README.md`](README.md)
