# 当前任务：星空到 3D 地球仪缩放转场收尾

状态：已完成（2026-08-29）

## 目标

完成上一会话中断的主页面缩放改造：让局部 3D 星空经双指缩小平滑过渡到完整 3D 地球仪，
同时强化悬浮地球、轨道层和卫星群的空间质感，并保持 30fps 绘制路径的稳定边界。

## 已完成

- 用单一归一化时间轴驱动相机后退、局部天空淡出、地球尺度、垂直位移、轨道层、地表细节、
  过渡提示和最终控件，避免多组独立动画在临界点跳变。
- 延长并重新整形缩放提交动画；地球从近距离球面连续后退为完整悬浮球体，局部锁定摘要随天空
  一起退出。
- 增强地球的方向光、昼夜暗部、大气边缘、海岸线、观察者与默认视域标记；约 4,600 个真实
  目录目标以稳定样本组成多层卫星轨道场，并按任务类型绘制微型结构特征。
- 重新安排转场层级：50% 中段只显示过渡提示，地表文字延后到最终控件接管时出现；提示在
  地球建立前退出，避免文字和主体互相遮挡。
- 地球仪只传播稳定 `overviewObjects`，完整 `visibleObjects` 只用于计数；相同传播集合不再
  重启引擎或清空缓存。
- 全局空间拖尾只为当前锁定对象采样和绘制，并正确遵循实时/时间偏移状态；目标切换时清空旧
  轨迹，普通卫星不再维护无意义的历史。
- 补齐中英文过渡提示、当前位置和默认视域文案，并同步产品、架构与测试说明。

## 验证

- iPhone 17 Pro / iOS 26.3 Simulator Debug 构建、安装和启动：通过。
- 关键回归测试 3/3 通过；完整单元测试 101/101 通过。
- 定向检查过渡进度 50% 与 75%：中段无地表标签抢层，后段提示退出且地球细节、卫星点云与
  控件按顺序接管；未进行无必要的逐帧或真机视觉巡检。
- 最新运行日志未发现 fatal error、崩溃、异常或 assertion failure。
- 两个 String Catalog JSON 解析通过；`git diff --check` 通过。

## 本次涉及文件

- `Documentation/ARCHITECTURE.md`
- `Documentation/PROJECT_OVERVIEW.md`
- `StarCatch/Design/Motion.swift`
- `StarCatch/Localization/Localizable.xcstrings`
- `StarCatch/Orbits/EphemerisEngine.swift`
- `StarCatch/Sky/Projection.swift`
- `StarCatch/Sky/SkyOverviewView.swift`
- `StarCatch/Sky/SkySession.swift`
- `StarCatch/Sky/SkyView.swift`
- `StarCatchTests/TimeTests.swift`
- `CURRENT_TASK.md`

## 下一步

1. 真机姿态、持续捏合手感、最大动态字体与 VoiceOver 留到明确的发布验收阶段。
2. 若后续在较老设备发现地球仪帧率问题，再用 Instruments 针对 Canvas 投影路径采样；不要在
   没有性能证据时牺牲稳定点集或视觉层级。
3. Archive 前刷新轨道目录；当前快照为 2026-08-20，已超过 72 小时发布门槛。
