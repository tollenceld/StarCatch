# 当前任务：准星识别、轨道数据与首次对焦严格校验

状态：已完成（2026-08-12）

## 目标

从公开轨道数据、SGP4/SDP4 传播、观察者坐标、设备姿态、天球投影、候选选择、
捕获迟滞与锁定资料链路逐层检查“准星对准卫星 → 显示数据”的真实性、稳定性和
首次运行性能；修复能由代码和模拟器证明的问题，并明确必须依赖真机的验证边界。

## 已完成

- 从 CelesTrak `GROUP=active` 刷新随包 GP/OMM 目录，目录由 16,235 更新为
  16,325 个当前活动对象；同步并重编译 3,840 份逐星档案与 8 份星座共享档案。
- 发布脚本默认只刷新一次 active 集合，并复用上一版分类；重叠分组改为显式
  `--refresh-groups` 维护操作，避免违反 CelesTrak 的重复下载约束。
- SatelliteKit 精确锁定 2.1.2；新增 Vallado/CelesTrak 案例 00005（近地 SGP4）
  和 04632（深空 SDP4）的位置/速度标准向量回归，避免应用内部路径互相印证。
- 单颗摘要的高度改为 WGS 地理高度；批量天空点继续使用低成本球面高度，避免
  数千对象的地理迭代进入绘制路径。距离、方位、仰角与速度继续来自同一观测时刻。
- Core Motion 低通改为使用真实单调时间戳和角速度自适应时间常数：静止时抑制
  微抖，转动时快速跟随，消除固定 150ms 滤波造成的明显视觉滞后。
- 定位默认申请完整精度但仍尊重系统的近似位置选择；拒绝过旧、无效或水平误差
  大于 10km 的缓存样本，误差大于 2km 时在主天空明确提示。坐标仍只在设备内计算。
- 捕获扫描由 10Hz 提升至 30Hz；候选选择先比较单位向量点积，只对最终目标执行
  `acos`，在提高扫过可靠性的同时控制主线程三角函数成本。
- 扩展天空倍率下的捕获角度与实际投影倍率保持一致；不再因 0.52× 广角而缩小
  准星的屏幕命中半径。
- 传感器尚未产生第一帧、处于 idle/starting/unavailable 时不再使用占位方向触发
  假识别；模拟器手动指向和真机 tracking 状态保持正常捕获。
- 保留并验证原有 2.5° 进入、1.25° 核心、4° 退出、0.75 秒退出驻留、当前目标
  粘性、锁定不自动解除和详情三秒保留，邻近对象和手抖不会造成资料闪换。
- 局部天空只传播实际绘制/捕获的确定性样本；进入全局星图时才切到完整筛选目录。
  第一颗候选进入感应后在 utility 后台精算遥测，启动叙事期间预热精算、轨迹与触觉。
- 隐私说明、App Store 提交说明、发布审计和发布校验已同步完整定位精度的必要性与
  本地计算边界。

## 主要涉及文件

- `StarCatch/Pointing/MotionPointingProvider.swift`
- `StarCatch/Pointing/ObserverLocation.swift`
- `StarCatch/Sky/Projection.swift`
- `StarCatch/Sky/SkyView.swift`
- `StarCatch/Sky/SkySession.swift`
- `StarCatch/Engagement/CaptureStateMachine.swift`
- `StarCatch/Orbits/EphemerisEngine.swift`
- `StarCatch/App/RootView.swift`
- `Scripts/update_catalog.py`
- `Scripts/release_check.py`
- `StarCatch/Resources/catalog.json`
- `StarCatch/Resources/satellite_profiles.json`
- `SatelliteKnowledge/`
- `StarCatchTests/OrbitTests.swift`
- `StarCatchTests/TimeTests.swift`
- `project.yml`
- `Documentation/ARCHITECTURE.md`
- `Documentation/PROJECT_OVERVIEW.md`
- `Documentation/APP_STORE_SUBMISSION.md`
- `Documentation/RELEASE_READINESS_AUDIT.md`
- `PRIVACY_POLICY.md`

## 验证

- `xcodegen generate` 通过，工程与 `project.yml` 同步。
- iPhone 17 Pro / iOS 26.3 模拟器 Debug 构建、安装、启动和自动首轮对焦通过；截图中
  准星、目标编号、AZ/EL、轨道分类、距离、高度、速度和锁定摘要一致出现。
- 全量 91 项单元测试通过，包含近地/深空标准向量、目录新鲜度、直接传播对照、
  投影方向、倍率命中半径、手抖、目标粘性、锁定稳定、详情保留和首次精算预热。
- Time Profiler 对自动首轮对焦记录 8 秒，未检测到超过 250ms 的 micro-hang；热路径
  只看到 Canvas 批量绘制和缓存插值，没有文件 IO、网络或同步全目录传播。
- Simulator 不支持 Animation Hitches 模板；该项没有伪造结论。
- `satellite_knowledge.py validate` 通过：3,840 份逐星档案、8 份共享档案，后者覆盖
  12,485 个同质节点。
- `release_check.py` 通过：16,325 个对象，目录年龄 0.0 天，隐私、图标、依赖锁均通过。
- `git diff --check` 通过。

## 精度边界与下一步

- CelesTrak 公共 GP/OMM 是平均轨道元素，不是实时测量或碰撞评估数据；即使标准传播
  正确，误差仍会随元素龄期增长。发布检查继续以 14 天为硬上限，实际发布应尽量当天刷新。
- 模拟器不能验证磁力计干扰、真北校准、手机壳磁性、真实握持与 Core Location 的现场
  精度。发布前必须在至少一台 iPhone 17 系列真机，以开阔环境和一颗可独立核对的亮星/卫星
  完成允许完整定位、选择近似定位、拒绝定位、画 8 字校准、缓慢扫过和快速扫过测试。
- 真机验收时应记录系统水平精度、目标角距和目录 epoch；若持续存在同向固定偏差，优先排查
  磁航向与握持姿态，而不是放大捕获阈值掩盖误差。
