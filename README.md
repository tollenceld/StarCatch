# StarCatch — 人造天体观察器

一台安静、深邃、克制、精密的深空仪器。举起手机指向真实天空，那个方向上真实存在的人造物（卫星、退役航天器、火箭残骸）会从黑暗中缓慢浮现，以遥测档案的形式呈现。

## 运行

```bash
brew install xcodegen   # 首次
xcodegen generate
open StarCatch.xcodeproj
```

- **真机**（推荐）：Xcode Signing 面板选择你的 Team → 运行。使用 CoreMotion 真北姿态 + 定位，指向真实天空。
- **模拟器**：直接运行。拖拽模拟指向（水平 = 方位角，竖直 = 仰角）。初始指向东南方仰角 30°，向左/右轻拖即可遇到 GEO 带对象（北斗 G8、Himawari-9 等）。

## 体验链路

唤醒（仪器上电，可随时轻触跳过）→ 首启观测手册（可随时继续或跳过）→ 探索（星尘 + 微弱点位）→ 靠近对象方向（点位增亮、刻度环合拢、扫描带掠过）→ 停留（锁定，触觉反馈，信号线生长，档案逐行浮现）→ 转开设备（档案随目标离开视野，边缘保留方向提示）→ 转回目标或使用“结束观测”。持续对准另一目标会完成换锁并替换当前档案。

**时间维度**：屏幕下缘是观测时钟（TimeDial），持续以低强度拖动提示和中心把手表明交互。左右拨动刻度改变观测时刻（±24h），整片天空按 SGP4 推算到对应时刻——拖动全览时暂时冻结捕捉，松手回到指向视野后，历史或未来时刻仍可锁定对象、查看档案并接收边缘方向提示。点按“返回此刻”或拖回零点时，天体沿回归轨迹返回 LIVE，天空球以缩放、虚化和淡出消散。

每次锁定自动落观测日志（本地 UserDefaults），并保存当时的时间与轨道读数；右上角设置页显示识别摘要，点按后进入独立记录页，再点某个对象可查看任务信息、观测时间和当时的方位、仰角、高度、距离与速度。

隐私：位置、姿态、设置与观测记录只在设备上使用或保存；应用不含账户、广告、分析或跟踪。仪器面板可查看完整隐私说明并清除本地观测记录。

## 数据

`StarCatch/Resources/catalog.json` 是随包发布的 CelesTrak GP/OMM 离线快照；当前快照包含 16,019 个轨道目标及少量人工编写的任务档案元数据。SGP4（SatelliteKit）在本地推算方位、高度、速度与距离，APP 运行时不请求轨道网络数据。

轨道元素会随时间漂移，随包快照必须作为发布资产维护。统一使用 `Scripts/update_catalog.py` 更新并校验目录，不要手工替换单个对象；完整流程与时效约束见 `Scripts/README.md`。

## 开源与第三方声明

StarCatch 的原创代码和项目材料采用 [MIT License](LICENSE) 发布。项目使用采用 MIT License 的 [SatelliteKit](https://github.com/gavineadie/SatelliteKit) 在设备本地执行 SGP4 轨道传播。

随包轨道目录由 [CelesTrak](https://celestrak.org/) GP/OMM 数据生成。更新数据时请遵循其 [Usage Policy](https://celestrak.org/usage-policy.php) 与查询频率要求；完整归属说明见 [NOTICE](NOTICE)。

## 测试

```bash
xcodebuild -project StarCatch.xcodeproj -scheme StarCatch \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

含轨道推算的物理合理性检验（ISS 高度/速度、GEO 静止性）。`testPrintCurrentSky` 可打印当前北京视角全部对象 az/el，便于调试指向。

## 结构

```
StarCatch/
├── App/          StarCatchApp RootView BootSequenceView(启动唤醒序列)
├── Design/       Palette(色彩) Typography(字体) Motion(动效) —— 全部视觉规范常量
├── Sky/          SkyView(编排) SkyRenderer(绘制) Projection(gnomonic投影) StarDust SkySession
│                 SkyClock TimeDial TrailStore CatalogFilterControl SkyActionControls
├── Shaders/      Grain.metal —— 胶片颗粒 + 阈下扫描线
├── Pointing/     MotionPointingProvider(真机) ManualPointingProvider(模拟器) ObserverLocation
├── Orbits/       CatalogModels CatalogStore EphemerisEngine(SGP4调度+任意时刻快照) TrackSampler
│                 PassPredictor(过境预报) ObservationLog(观测日志)
├── Engagement/   CaptureStateMachine —— 四态 + 迟滞 + 换锁 + 主动释放
├── Archive/      ArchiveOverlay ArchiveField ArchiveTopBar
│                 ManualBookView(FIELD MANUAL 分页手册)
│                 InstrumentPanel(右上设置入口唤出的单屏偏好+观测摘要)
└── Resources/    catalog.json
```

更具体的状态所有权、并发边界、工程生成与验证约束见 [`ARCHITECTURE.md`](ARCHITECTURE.md)。

## 设计原则（改动时对表）

- 单色相暖灰阶 + 唯一暗琥珀 `signal`；全局禁蓝青，饱和度 ≤ 25%
- 层级靠透明度四档（0.15/0.4/0.7/0.95），不靠颜色
- 主要线条保持 0.5pt、butt cap；微交互快速确认，内容与空间转换使用较慢缓动；无 spring
- 信息渐显不弹出；不做打字机/乱码效果；不游戏化
