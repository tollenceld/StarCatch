# StarCatch — 人造天体观察器

一台安静、深邃、克制、精密的深空仪器。举起手机指向真实天空，那个方向上真实存在的人造物（卫星、退役航天器、火箭残骸）会从黑暗中缓慢浮现，以遥测档案的形式呈现。

完整功能、数据规模、用户流程、技术架构与上架状态见
[`Documentation/PROJECT_OVERVIEW.md`](Documentation/PROJECT_OVERVIEW.md)。

## 运行

```bash
brew install xcodegen   # 首次
xcodegen generate
open StarCatch.xcodeproj
```

- **真机**（推荐）：Xcode Signing 面板选择你的 Team → 运行。使用 CoreMotion 真北姿态 + 定位，指向真实天空。
- **模拟器**：直接运行。拖拽模拟指向（水平 = 方位角，竖直 = 仰角）。初始指向东南方仰角 30°，向左/右轻拖即可遇到 GEO 带对象（北斗 G8、Himawari-9 等）。

## 体验链路

唤醒（产品名称、用途与本地目录整体淡入，可随时轻触跳过）→ 首启观测手册（可随时继续或跳过）→ 探索 → 准星进入中心 2.5° 感应范围（点位增亮，瞬时档案随视线出现；移开后快速消失）。设置中的“确认捕获”默认关闭，因此主视野没有底部捕获按钮；开启后，主按钮只负责“捕获卫星 / 切换捕获”，旁边的独立按钮负责“取消捕获”。

每个完整即时信息面板都会在画面下方中部唤出“深入档案”：单体卫星读取按 NORAD 独立维护的 Markdown，页面离线保存任务背景、关键节点、工程意义与来源；Starlink、OneWeb、千帆、国网、Kuiper、Iridium、Globalstar 与 Orbcomm 的任意节点进入各自项目的共享档案，避免把同一段文字复制成上万份。实时 SGP4 读数始终来自当前节点。左侧筛选以少数常用“观察镜片”为第一层，再按“任务、运营者或轨道网络”进入更多角度；主天空中的每一个点始终对应一颗真实卫星。

**时间维度**：点按左上角入口进入全局星图后，屏幕下缘才出现观测时钟（TimeDial）。左右拨动刻度改变观测时刻（±24h），整片星图按 SGP4 推算到对应时刻，并实时留下轨迹。点按“返回此刻”或拖回零点时，天体按距离在线性时间内返回 LIVE，最远 24 小时偏移也不超过 2.4 秒；从非 LIVE 状态退出全局星图时也会先启动回归。主天空保持实时指向，承担即时识别与用户可选的持续捕获。

每次锁定自动落观测日志（本地 UserDefaults），并保存当时的时间与轨道读数；右上角设置页显示识别摘要，点按后进入独立记录页，再点某个对象可查看任务信息、观测时间和当时的方位、仰角、高度、距离与速度。

隐私：位置、姿态、设置与观测记录只在设备上使用或保存；应用不含账户、广告、分析或跟踪。仪器面板可查看完整隐私说明并清除本地观测记录。

## 数据

`StarCatch/Resources/catalog.json` 是随包发布的 schema v2 CelesTrak GP/OMM 离线快照，当前包含 16,243 个轨道目标；不在 active GP 分组中的少量历史目标以同一 schema 内的策展 TLE 载荷保留，运行时不再兼容旧版整份小目录文档。构建测试核对唯一 NORAD/COSPAR 标识、元素历元时效、代表性物理量和档案覆盖是否确实存在于目录；这不等同于替代官方运营方对任务状态的持续公告。SGP4（SatelliteKit）在本地推算方位、高度、速度与距离，APP 运行时不请求轨道网络数据。

人工编写的逐星档案位于 [`SatelliteKnowledge`](SatelliteKnowledge/README.md)。它是可直接用 Obsidian 打开的 Markdown 资料库；Xcode 构建会自动校验并编译为紧凑 JSON，APP 运行时按 NORAD 编号读取。数千份源笔记不会进入安装包，也不会拖慢启动时的文件扫描。

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
.
├── Documentation/       架构、完整项目说明与 App Store 提交清单
├── SatelliteKnowledge/  Obsidian 可编辑的逐星与星座 Markdown
├── Scripts/             发布期目录生成、资料校验与编译
├── StarCatch/
│   ├── App/             App 生命周期、启动与隐私页面
│   ├── Archive/         即时信息、深入档案、设置与观测记录
│   ├── Design/          Palette、Typography、Motion
│   ├── Engagement/      CaptureStateMachine
│   ├── Orbits/          目录、SGP4 调度、轨迹、过境与观测日志
│   ├── Pointing/        真机姿态、模拟器指向与观察者位置
│   ├── Sky/             主天空、投影、绘制、筛选、全局星图与时间轴
│   ├── Resources/       构建后的 catalog.json 与 satellite_profiles.json
│   └── Shaders/         Grain.metal
├── StarCatchTests/      轨道、状态、时间和资料完整性测试
└── project.yml          XcodeGen 工程结构唯一来源
```

更具体的状态所有权、并发边界、工程生成与验证约束见
[`Documentation/ARCHITECTURE.md`](Documentation/ARCHITECTURE.md)。

## 设计原则（改动时对表）

- 单色相暖灰阶 + 唯一暗琥珀 `signal`；全局禁蓝青，饱和度 ≤ 25%
- 层级靠透明度四档（0.15/0.4/0.7/0.95），不靠颜色
- 主要线条保持 0.5pt、butt cap；微交互快速确认，内容与空间转换使用较慢缓动；无 spring
- 信息渐显不弹出；不做打字机/乱码效果；不游戏化
