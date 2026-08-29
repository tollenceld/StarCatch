# 当前任务：解耦局部星空与 3D 地球仪交互

状态：已完成（2026-08-29）

## 目标

让双指缩放只控制当前模式的观察尺度；局部星空必须通过明确入口进入 3D 地球仪，地球仪必须
通过左上返回退出，彻底消除缩放阈值附近的页面误切换。

## 已完成

- 用 `SkyPresentationMode` 统一表达局部、进入全局、全局、退出全局四个互斥阶段，移除多组可能
  组合出非法状态的提交与返回布尔值。
- 主天空保留 0.52×–4× 缩放。越过最广视场后的 0.10 额外行程只产生最多 2% 弹性阻力和一次
  触感，达到阈值后激活“进入全局轨道”按钮，不再直接渲染巨大地球。
- 新增 48pt 玻璃胶囊入口；入口显示时暂时接管底部槽位，捕获事实仍然保留。局部视场放大到
  0.60× 以上后入口自动退出。
- 点击入口才播放既有 0.92 秒单调相机转场；转场结束前地球仪不接收手势。
- 地球仪缩放改为独立的 0.72×–2.2× 范围，删除放大越界返回回调和返回进度；缩放与惯性到达
  边界后只在当前模式收束。
- 移除全局星图的左边缘返回手势；左上“天空”是唯一可见返回入口，VoiceOver Escape 作为无
  障碍等效动作。返回同时恢复 LIVE、1× 默认星空、原有锁定摘要和捕获状态。
- 入口激活时只预热已有离线稳定轨道集合，不创建地球 Canvas，也不增加文件 IO 或网络行为。
- 补齐中英文入口文案，并同步产品和架构说明。

## 验证

- iPhone 17 Pro / iOS 26.3 Simulator Debug Build & Run：通过。
- 入口门槛、回差、独立缩放边界、显式模式状态与相机时间轴关键测试：4/4 通过。
- 完整单元测试：102/102 通过。
- 定向截图确认：最广星空只显示独立入口；2.2× 地球局部仍保留左上返回；自动进入/退出调试
  路径最终恢复 1× 局部星空和锁定摘要。
- 最新运行日志未发现 fatal error、崩溃、异常或 assertion failure。
- String Catalog JSON 与 `git diff --check`：通过。
- 本机 Xcode 的 SimulatorKit 架构不匹配导致 AX 手势/语义树不可用，因此没有伪造按钮点击或
  VoiceOver 自动化结论；相关路径由纯值测试、编译和定向调试状态覆盖。

## 本次涉及文件

- `Documentation/ARCHITECTURE.md`
- `Documentation/PROJECT_OVERVIEW.md`
- `StarCatch/Design/Motion.swift`
- `StarCatch/Localization/Localizable.xcstrings`
- `StarCatch/Sky/Projection.swift`
- `StarCatch/Sky/SkyActionControls.swift`
- `StarCatch/Sky/SkyOverviewView.swift`
- `StarCatch/Sky/SkyView.swift`
- `StarCatchTests/TimeTests.swift`
- `CURRENT_TASK.md`

## 下一步

1. 发布验收时用真机确认持续捏合阻力、触感强度、动态字体和 VoiceOver Escape。
2. Archive 前刷新轨道目录；当前快照为 2026-08-20，已超过 72 小时发布门槛。
