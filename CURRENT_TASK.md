# 当前任务：启动轨道电影与交互海岸线同步

状态：已完成（2026-08-30）

## 目标

把首次与回访启动统一为轻量轨道地球电影，在真实目录后台准备期间保持连续画面；同时确保
三维地球在拖动、缩放和惯性降级期间仍保留大陆轮廓。

## 已完成

- 用 `OrbitalBootView` 统一首次与回访启动，不再强制插入首次手册或等待用户点按进入。
- 新增纯值 `BootOrbitalTimeline`、`BootCompletionPolicy` 和确定性的
  `BootOrbitalScenePreset`：启动 Canvas 使用固定 4,600 个解析轨道点、最多 24 个短拖尾和
  编译期海岸线，不读取目录、位置、真实星表或 SatelliteKit。
- 真实准备在约 3.2 秒内完成时等待电影收束；较慢时连续降速巡航，准备完成后直接进入天空；
  Reduce Motion 使用无旋转、无拖尾的静态终态。
- 地球仪交互期间使用编译期基础海岸线，静止后才切换到后台资源中的高精度海岸线，避免交互
  降级时出现空白球体。
- 更新产品说明、架构性能边界和启动/海岸线纯值测试。
- String Catalog 的现有 Xcode 提取状态和格式变化单独保存，不与功能实现混为一个提交。

## 验证

- iPhone 17 / iOS 26.3 Simulator，Debug Build & Run：通过，App 成功安装并启动。
- 完整测试集：110/110 通过，0 failed，0 skipped。
- 两个 String Catalog 均通过 JSON 解析。
- `git diff --check` 通过；新增内容未发现密钥、令牌、密码、私钥或本机配置。
- 构建和测试没有产生新的未忽略文件；`.obsidian` 与 `xcuserdata` 继续由现有规则忽略。

## 本次涉及文件

- `StarCatch/App/BootFieldView.swift`
- `StarCatch/App/BootSequenceView.swift`
- `StarCatch/App/RootView.swift`
- `StarCatch/Sky/SkyOverviewView.swift`
- `StarCatchTests/TimeTests.swift`
- `Documentation/ARCHITECTURE.md`
- `Documentation/PROJECT_OVERVIEW.md`
- `StarCatch/Localization/Localizable.xcstrings`
- `StarCatch/Localization/SatelliteText.xcstrings`
- `CURRENT_TASK.md`

## 下一步

1. 后续功能从已同步的干净 `main` 开始，优先按一个功能一个 Codex 任务/Worktree 组织。
2. 普通开发继续使用相关单测加一次 Simulator Debug 编译；姿态、真北和触觉只留给必要真机验收。
3. 发布 Archive 前刷新 2026-08-20 的轨道目录，满足 72 小时发布门禁。
