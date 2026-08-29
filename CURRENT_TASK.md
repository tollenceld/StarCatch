# 当前任务：3D 地球仪精致度、卫星拖尾与恒星背景优化

状态：已完成（2026-08-29）

## 目标

在不改变星空/地球模式解耦、地球缩放边界和唯一返回入口的前提下，把全局界面提升为
“空灵的精密线框观测仪”，加入固定真实天球、有限环境卫星拖尾，并校正 iPhone Air 顶部中轴。

## 已完成

- 地球继续按“恒星 → 背面卫星/拖尾 → 地球 → 正面卫星/拖尾 → 观察者”分层，保持地球对
  背面内容的物理遮挡；现有昼夜边界、海面反射、双层大气弧、精细海岸线和深度网格继续只在
  静止时完整呈现，交互中自动降级。
- 新增 `BrightStarStore`、`CelestialViewFrame` 与纯值 `BrightStarProjector`。NASA HEASARC BSC5P
  精简为 8,404 颗 J2000 恒星、151,282 字节的只读二进制资源；后台映射/解码一次，画布尺寸或
  进入天球改变时才重新投影，30fps Canvas 仅批量绘制缓存星点。
- 恒星天球由进入全局时的观察者经纬度、UTC 和指向固定；地球 Arcball、双指旋转、缩放、惯性
  及时间轴都不会改变恒星屏幕坐标。重新进入全局才创建新的天球相机。
- 新增 `OverviewAmbientTrailPolicy` 与独立 `overviewAmbientTrails`。从稳定全局样本中按类别确定性
  选最多 24 个目标；LIVE 且静止 0.35 秒后按 10fps 记录最多 3.2 秒 / 32 个 ECI 真值点。
- 环境拖尾保持最新真实端点与运动方向，仅把旧点屏幕距离最多放大 7 倍并限制为 22pt；交互、
  惯性、转场、非 LIVE、时间拖动和 Reduced Motion 会立即清空。锁定目标原有完整轨迹独立保留。
- `DynamicIslandWingMetrics` 改用 `islandVisualCenterY` 作为纵向事实源；iPhone Air 校正为 38pt
  中轴与 16pt 顶部 padding，30pt 可见胶囊和 44pt 触控区不变，其他 profile 数值保持原样。
- 加入星表编译脚本、数据来源说明、纯值测试，并更新产品和架构边界。

## 验证

- 星表编译两次字节一致：8,404 颗，151,282 bytes。
- iPhone Air / iOS Simulator Debug Build & Run：通过。
- 完整测试集：106/106 通过；覆盖星表解码/非法回退、J2000 投影与相机正交性、环境拖尾稳定
  选择/门控/端点/方向/22pt 上限、Air 38pt 中轴，以及既有 0.72×–2.2× 缩放与显式返回行为。
- iPhone Air 两张定向截图完成：默认静止全局、2.2× 最大局部缩放；确认固定星空、地球遮挡与
  细节、全局内缩放不退出、左上唯一返回按钮和顶部三胶囊中轴。
- String Catalog 使用 JSON 解析校验，`git diff --check` 通过；本轮未修改其语义且提交时排除
  工作区原有的两个 String Catalog 改动。

## 本次涉及文件

- `Documentation/ARCHITECTURE.md`
- `Documentation/BRIGHT_STAR_DATA.md`
- `Documentation/PROJECT_OVERVIEW.md`
- `Scripts/compile_bright_stars.py`
- `StarCatch/Resources/bright_stars_bsc5p.bin`
- `StarCatch/Sky/BrightStarField.swift`
- `StarCatch/Sky/OverviewAmbientTrailPolicy.swift`
- `StarCatch/Sky/SkyOverviewView.swift`
- `StarCatch/Sky/SkySession.swift`
- `StarCatch/Sky/SkyStatusIndicator.swift`
- `StarCatch/Sky/SkyView.swift`
- `StarCatchTests/OverviewAtmosphereTests.swift`
- `StarCatchTests/TimeTests.swift`
- `StarCatch.xcodeproj/project.pbxproj`
- `CURRENT_TASK.md`

## 下一步

1. 发布验收时只需在 iPhone Air 真机感受环境拖尾亮度与顶部中轴；不需要重复逐帧巡检。
2. Archive 前刷新轨道目录；当前快照已超过 72 小时发布门槛。

## GitHub 同步（2026-08-29）

- 检查确认本地 `main` 比 `origin/main` 多 6 个已提交 commit；工作区只保留两个既有 String Catalog 格式化变更。
- 核对本次 6 个 commit 共涉及 30 个项目文件，未发现环境变量、签名凭据、缓存、构建产物或日志；`git diff --check` 通过。
- 用户授权后，已使用普通 push 将这 6 个 commit 从 `008b363` 推送至 GitHub `main`，远端到达 `b3bcbff`。
- 未使用强制推送，未将两个未提交的 String Catalog 格式化噪声混入远端；后续继续保持 `main` 为唯一开发与发布分支。
