# StarCatch 项目交接入口

这是新对话需要完整读取的唯一项目交接文档。长期工作规则由 `AGENTS.md` 自动约束；两份长文档
是按需事实源，不是每个任务的必读材料。具体需求与验收标准保留在对应的 Codex 任务中，代码
进度以当前分支、提交和 diff 为准。

## 项目定位

StarCatch 是一款 iPhone 人造天体观察器：用户举起手机指向天空，应用依据设备姿态、真北方向、观察者位置和本地轨道数据，识别视野中的卫星、空间站、望远镜及轨道残骸，并以离线档案呈现。它不是相机识别器，也不依赖账户、广告、分析或运行时网络请求。

App 完整支持简体中文与英文，语言跟随 iOS 系统或单 App 语言设置，英文同时是不支持语言的回退。轨道目录保持语言中立；界面、动态洞察和自动档案在展示层按当前语言生成。

## 技术与工程结构

- 平台：iOS 17+，SwiftUI，竖屏全屏 iPhone 应用。
- 工程：`project.yml` 是 XcodeGen 唯一来源；生成的 `StarCatch.xcodeproj` 用于直接打开 Xcode。
- 运行时：CoreMotion + CoreLocation 提供指向和观察者信息；SatelliteKit 在设备本地执行 SGP4；随包数据位于 `StarCatch/Resources/`。
- 资料：`SatelliteKnowledge/` 保存逐星与星座 Markdown；`Scripts/` 负责目录更新、资料校验和构建期编译。
- 测试：`StarCatchTests/` 覆盖轨道、时间、状态机和资料完整性。

## 默认协作方式

`main` 只接收已经检查和验证的完整工作。每个独立功能默认使用一个新的 Codex 任务、Worktree
和 `codex/` 功能分支；同一功能的后续修正继续留在原任务。用户在新任务中只需说明目标、期望
行为、验收标准和明确不能改变的内容，不必重复交代项目身份、文档读取顺序、分支规范、最小
验证或合并安全规则；这些由 `AGENTS.md` 统一约束。

## 稳定边界

- App 运行时保持离线；不要新增账户、分析、广告或隐含网络路径。
- `project.yml` 是工程结构和 Info.plist 声明的唯一来源。
- 姿态、时间、捕获阶段和星历各自只有一个事实源；视图层不自行解析目录或执行 SGP4。
- 30fps 绘制路径不做文件 IO、网络请求、JSON 解码或全目录传播。
- Swift 与运行时改动按风险运行最小充分测试；姿态、真北和触觉才优先留给必要真机验收。

仓库中只保存可审阅的源文件与经过挑选的发布资产。DerivedData、Xcode 用户状态、SwiftPM/依赖构建目录、Python 缓存、日志、本机环境变量和签名/凭据文件都不应进入 Git；具体忽略规则见 [`.gitignore`](.gitignore)。

## 新任务与中断恢复

1. 执行 `git status --short --branch`。
2. 从干净 `main` 开始新功能时，使用一个新 Codex 任务、Worktree 和 `codex/` 分支。
3. 恢复已有功能分支时，先查看 `git log --oneline main..HEAD`、`git diff --stat main...HEAD`
   和未提交 diff，再阅读相关源码与测试。
4. 用 `rg -n '^##'` 查看长文档目录，只打开与任务直接相关的章节。
5. 完成后提交功能分支；经检查与验证后再明确合并到 `main`，不自动 force push。

## 文档路由

- 长期规则：[`AGENTS.md`](AGENTS.md)
- 快速运行、目录结构和设计原则：[`README.md`](README.md)
- 已实现功能、完整用户流程、数据规模和发布状态：
  [`Documentation/PROJECT_OVERVIEW.md`](Documentation/PROJECT_OVERVIEW.md)
- 状态所有权、并发、渲染性能、工程生成和分级验证：
  [`Documentation/ARCHITECTURE.md`](Documentation/ARCHITECTURE.md)
- 轨道资料更新与发布脚本：[`Scripts/README.md`](Scripts/README.md)

不要把长文档复制进本文件。只有稳定项目事实发生改变时才更新本文件；单个功能的过程记录由
Codex 任务与 Git 历史承担。
