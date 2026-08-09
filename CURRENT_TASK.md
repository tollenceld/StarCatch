# 当前任务：地球交互、星空层级与首次捕获性能

状态：已完成（2026-08-09）

## 目标

修正全局三维地球的水平直接操控方向，增强球体体积与海岸辨识度；让主天空中的不可捕获恒星随设备视角移动，并用稳定的微型结构区分不同卫星；把主要商业星座的官方页面放入资料界面；消除首次捕获时的轨道计算与触觉冷启动竞争。

## 已完成

- 修正地球水平拖动与水平惯性的符号：向右拖动时地球内容随手向右移动；已经正确的垂直方向保持不变。
- 在现有真实海岸线和经纬网之上增加海面受光、柔和昼夜分界、内侧大气边缘与海岸暗底，强化球体体积，同时维持地图低干扰层级。
- 将确定性背景星场改为批量绘制的远、中、亮恒星层；少数亮恒星具有对称短衍射线和克制冷暖差。
- 背景恒星继续使用设备姿态驱动的统一天球变换，会随手机转动进出画面；它们不进入目录、投影捕获或锁定状态机，因此不可对焦。
- 为通信网络、导航、地球观测、科学和退役目标加入不同的 3–6pt 人造微型刻度；分类由稳定目录字段决定，不随帧闪动，也不改变捕获语义。
- 从离线资料源中解析首个非 CelesTrak 的 HTTPS 官方来源，在锁定摘要和完整档案中提供明确的“官网 / 官方任务页面”入口。已覆盖 Starlink、OneWeb、Project Kuiper、Iridium、Globalstar 和 ORBCOMM。
- 启动叙事期间并行预热单目标精确星历和多时刻轨迹采样；完整目录传播与轨迹准备降为 utility 优先级，避免同首次锁定动画争抢 CPU。
- 新增可复用且预热的触觉发生器，替换捕获流程中临时创建的多个 UIKit 发生器；模拟器路径保持无操作。
- 将热更新路径中的完整档案构造改为轻量存在性检查，避免大型星座在视图刷新时反复个性化章节。

## 主要涉及文件

- `StarCatch/Sky/SkyOverviewView.swift`
- `StarCatch/Sky/SkyRenderer.swift`
- `StarCatch/Sky/StarDust.swift`
- `StarCatch/Sky/SkyView.swift`
- `StarCatch/Sky/SkySession.swift`
- `StarCatch/Sky/ObservationHaptics.swift`
- `StarCatch/Orbits/EphemerisEngine.swift`
- `StarCatch/Orbits/TrackSampler.swift`
- `StarCatch/Archive/SatelliteStories.swift`
- `StarCatch/Archive/ArchiveOverlay.swift`
- `StarCatch/Archive/SatelliteStoryView.swift`
- `StarCatch/App/RootView.swift`
- `StarCatchTests/TimeTests.swift`
- `StarCatchTests/OrbitTests.swift`

## 验证

- `xcodegen generate` 通过，生成工程仅加入 `ObservationHaptics.swift`。
- iPhone 17 Pro / iOS 26.3 模拟器 Debug 构建和启动通过。
- 模拟器人工检查全局地球与主天空：球体材质、海岸线、卫星点云、锁定卡片和背景星场均正常，无布局破坏。
- 3 项定向测试通过、0 失败：地球拖动方向、卫星视觉角色分类、离线资料与主要星座官方链接。
- `git diff --check` 通过。

## 下一步

- 真机确认首次捕获的主线程帧时间与触觉手感；模拟器无法验证 Taptic Engine 的真实冷启动收益。
- 真机在不同环境亮度下确认低层恒星与卫星微型刻度的可读性，如需调整只改透明度，不扩大捕获目标尺寸。
- 下一次资料维护时继续只收录可核验的运营方官方 HTTPS 页面；没有明确官网的对象保持离线档案，不使用聚合站冒充官方来源。
