# StarCatch 工程边界

这份文档描述当前代码的职责边界与改动约束。它不是产品说明；产品体验见
`../README.md`，离线目录发布流程见 `../Scripts/README.md`。

这是按需技术事实源，不是新对话的启动必读材料。新任务先读取 `../PROJECT_CONTEXT.md`，再用
`rg -n '^##' Documentation/ARCHITECTURE.md` 定位状态所有权、渲染、并发或验证等相关章节。

## 运行时依赖方向

```text
RootView
├── 后台准备 CatalogStore ──完成后→ SkySession / EphemerisEngine / ObserverLocation
├── SkyClock
├── CaptureStateMachine
├── AppPageDestination ──→ CatalogFilterPage / ObservationHistoryPage / SettingsPage
└── SkyView（编排）
     │
     ├── SkyChromeState（纯值解释）
     ├── SkyCommandDock（纯 UI）
     ├── Projection（纯几何）
     ├── SkyRenderer（Canvas 绘制）
     ├── TrailStore（短生命周期轨迹）
     ├── BrightStarStore / BrightStarProjector（离线恒星与缓存投影）
     └── 独立 SwiftUI 控件
```

依赖只能沿图向下。轨道层不知道 SwiftUI 页面，绘制层不拥有业务状态，视图不自行
解析目录或执行 SGP4。新增功能应优先扩展现有领域对象，而不是在 `body` 中建立第二套
状态。

## 状态所有权

| 状态 | 唯一所有者 | 说明 |
| --- | --- | --- |
| 启动准备、全屏阅读与当前工具面板 | `RootView` | `AppPageDestination` 互斥表达筛选、记录和设置；`UtilityPanelLifecycle` 的取消代次隔离转场完成回调，目录不得在首帧前同步解析 |
| 设备指向、观察者、目录筛选、星历 | `SkySession` | 天空会话的共享事实源 |
| 当前/过去/未来观测时刻 | `SkyClock` | 时间轴唯一事实源 |
| 探索、聚焦、自动锁定、关闭消隐 | `CaptureStateMachine` | 1.8 秒驻留自动锁定；锁定目标只由叉号或无障碍 Escape 明确关闭 |
| 主天空局部动画、缩放、面板测量与短时 Overlay | `SkyView` | `SkyTransientOverlay?` 保证状态/方向面板互斥，只影响当前视图生命周期 |
| 当前控制层解释 | `SkyChromeState` | 从场景和捕获事实推导的纯值快照，不保存业务状态 |
| 时间/全景拖尾 | `TrailStore` | 由所属视图创建和销毁 |
| 亮星目录与天球投影 | `BrightStarStore` / `CelestialViewFrame` | 只读离线资源；进入全局时固定相机，后台解码和投影 |
| 观测记录 | `ObservationLog` | 本地持久化，不依赖页面是否打开 |

任何新的 `@State` 都应先回答：它是否只是呈现状态？如果答案是否定的，它通常应该
进入上表中的领域对象。

## 目录与轨道边界

- `CatalogModels.swift`：应用内稳定的目录模型、星座/机构语义与筛选规则。
- `CatalogStore.swift`：只接受发布脚本生成的 schema v2 资源，负责校验版本、去重、
  建立索引与 SatelliteKit 对象。主体为 OMM；active GP 分组之外的少量历史目标由
  同一 schema 中显式的策展 TLE 载荷保留，不再兼容旧版整份目录文档。
- `SatelliteStories.swift`：以 NORAD ID 连接逐星 Markdown，并让大型星座节点连接
  项目共享 Markdown；schema v3 为每条内容保留来源 ID、`object/family` 范围与可信类型。
- `EphemerisEngine.swift`：负责传播调度、缓存、LIVE 插值与冻结时刻快照。
- `TrackSampler.swift` / `PassPredictor.swift`：基于星历的低频派生能力。
- `SatelliteInsights.swift`：为当前感应目标在 utility 任务中计算星下点、距离趋势、单次
  过境窗口、内部轨道参数、发射批次和系列中位数差异；深度档案打开后再按需生成可取消、
  可缓存的 24 小时 `PassForecast`。服务由 `SkySession` 会话级持有。
- `Scripts/update_catalog.py`：仅发布期联网；APP 运行时保持完全离线。

不要把轨道元素解码字段泄漏到 UI，也不要让页面直接创建 `Satellite`。
机构筛选只对名称能够保守辨认的公共任务归类，未知所有权保持未分类；大型星座以
`CatalogFamily` 独立采样和着色。不要根据编号臆测运营方。

SatelliteKit 在 `project.yml` 中精确锁定版本。依赖升级必须同时通过 Vallado/CelesTrak
案例 00005（近地 SGP4）与 04632（深空 SDP4）的 ECI 位置/速度回归；不能只拿应用
内部的两条计算路径互相印证。公开 GP/OMM 是平均轨道元素而非实时遥测，因此界面
只能表达预测方向，不能宣称达到碰撞分析或测量级精度。

观察方向的精度由三项共同决定：新鲜轨道元素、Core Motion 真北校准和观察者坐标。
定位样本超过五分钟或水平误差大于 10km 时必须拒绝并明确使用假定位置；误差大于
2km 时界面提示低精度。坐标只在设备内转换为拓扑方位，不进入网络或持久化路径。

## 天空渲染边界

`SkyView` 是编排层：收集当前姿态、观测时刻和捕获阶段，并把稳定输入交给纯几何、
绘制函数和纯值 Chrome 解释。可复用控件已经拆到：

- `SkyChromeState.swift`
- `SkyCommandDock.swift`
- `CatalogFilterControl.swift`（即时筛选面板）
- `ObservationHistoryPage.swift` / `SettingsPage.swift`（独立功能流）
- `SkyActionControls.swift`
- `TimeDial.swift`
- `DockMorph.swift` / `GlobalDockMorph.swift`（共享底部表面、阶段进度与固定底缘几何）
- `PointingCoordinateReadout.swift`（整数显示采样，不影响姿态精度）

底部 Dock 只服务主天空：探索态使用筛选、观测记录、全球和设置四个等权槽位，聚焦时四槽退场，
锁定时由持久目标摘要占据阅读层，不再生成捕获主动作。全球轨道页不生成命令 Dock，底部仅常驻
`TimeDial`；进出期间共享表面沿现有场景进度从 56pt 导航基座长成标尺，内容在地球获得视觉优先级后
交接；非 LIVE 的中央读数直接承担“回到此刻”。地球视场只通过双击或无障碍动作复位。
`CaptureStateMachine` 是驻留与锁定的唯一事实源：探索态进入 2.5° 后聚焦，在 1.25° 核心附近
持续约 1.8 秒自动锁定；锁定期间忽略其他候选，不因角距变化退出。叉号关闭进入 0.24 秒消隐，
同一对象必须离开 4° 后才能重新布防，其他对象可在关闭完成后立即开始驻留。页面只在阶段首次
进入 `.locked` 时写一条 `ObservationLog`，持续锁定、打开深度档案或返回都不得重复记录。

`SkyDockActivity` 只解释视线角速度和触摸时间，`SkyDockActivityController` 复用已有帧更新，
最多 10Hz 采样且只在透明度档位变化时发布。页面覆盖、捕获、模式或前后台切换时重置采样与
唤醒时限，不新增 Timer、姿态订阅或延迟完成回调。角距用 ENU 单位向量计算以正确处理方位回绕。
底部唤醒区只由根层同时监听触摸位置，不额外覆盖命中表面，以保留按钮单击与天空拖动。
`SkyFieldResetPolicy` 分别对缩放和手动偏移应用迟滞；手动复位取消惯性，真机姿态不受影响。
`SkyObservationIssue` 从传感器、权限、定位请求事实和目录龄期推导紧凑标签与完整说明；不能把
尚未请求定位当作正在定位。`ObserverLocation.isLocating` 随请求、结果、失败及停止同步更新。

继续拆分时应优先提取具备明确输入/输出的独立 `View` 或纯计算类型。不要为了减少
单文件行数，把 `SkyView` 私有状态改成跨文件可写的全局状态。

每帧路径遵守三条规则：

1. 不在 Canvas 循环中做文件 IO、JSON 解码或网络调用。
2. 主天空大目录（含精选对象）使用批量绘制；只有捕获目标及短暂消隐中的候选保留独立聚焦细节。
3. SGP4 批量传播在后台任务执行，主线程只接收完整快照。
4. 24 小时过境扫描和系列比较不得进入 SwiftUI `body`、Canvas 或首次对焦路径；摘要卡先用
   已缓存星历出现，完整 `PassForecast` 只在深度档案固定区域异步补齐。
5. 档案时间带和过境曲线只读取不可变预测值；每秒更新当前时刻线、倒计时和真实位置，
   不在帧循环中传播轨道。页面隐藏或目标切换时必须取消旧预测任务。
6. `SkyPresentationMode` 是场景模式的唯一事实源；天空越过 0.52× 后进入 `previewingGlobal`，
   原始倍率至 0.32× 映射到完整旅程。松手达到 50% 进入 `enteringGlobal`，否则由 `cancellingGlobal`
   回到 0.52×；全球内部捏合不退出。`ScaleJourneyProgress` 同时承接手势和单调前台时钟补全，
   不因手势交接重新挂载全球场景。后台取消悬空手势并按位置阈值选择目的地，恢复后再收束。
7. 地球仪只能传播会话级稳定 `overviewObjects`；完整 `visibleObjects` 只用于结果计数。入口预热、
   捏合、拖动和静止状态不得切换点集。非锁定历史轨迹仅允许 `overviewTrailObjects` 中最多 24 个
   确定性目标在 LIVE、静止、非 Reduced Motion 时以 10fps 有界采样；任一交互或时间移动必须清空。
8. 共享场景背景复用主天空的确定性 StarDust 与设备方向响应，不随地球 Arcball 或缩放旋转，
   不在交接点换背景身份。BrightStarStore / J2000 投影工具继续保留，但不另行绘制第二套背景。
9. 启动由 RootView 唯一持有的 ObservationEstablishment 编排：信号 0.15s、地球 0.55s、
   网络 0.60s、Observer 0.25s、推进 1.05s。单调时钟只在前台推进；数据迟到只延长网络阶段，
   不重播、不补转圈。8s 无可用星历则进入可操作天空，目录错误直接显示数据不可用。
   ObservationSceneFrame 由 SkySession 从 EphemerisEngine 缓存装配，包含同一时刻、观察者版本
   （完整 Coordinates 值）、设备方向、稳定 ID、ECI 与 az/el/range。首次真实帧前不绘制卫星；
   启动与全球均使用最多约 4,600 个 overviewObjects，末段并入已有 displayObjects，不重新抽样。
   点亮次序按轨道倾角组与 ID 预计算；最多六条静态参考弧不是预测轨迹，不冒充星链赤道带。
   ObservationCameraState 将压缩半径连续还原到物理 ECI，并沿观察者法线推进、转向 ENU。
   全球端精确复用原投影，本地端复用 Projection 的基向量、roll、视场与裁切；地球轮廓在齐次
   坐标中裁切，表面、大陆、轨道和目标共享相机。不使用整屏黑场或两页完整星空交叉溶解。
   ObservationSceneRenderer 共享地球材质、点阵、参考弧、Observer 和四档点云；
   30fps Canvas 只读取缓存并批量合并 Path，不做目录 IO、SGP4 或 SatelliteKit 对象构造。
   首次定位授权仅在进入天空后请求；已授权提前单次请求，网络后最多等 0.8s，超时明确显示
   假定上海坐标且无确认触觉。真实 Observer 只确认一次；推进期间冻结位置版本，迟到坐标交接后
   释放。方向由会话预热，不可用时保留手动/未校准提示。启动禁止捕获采样、自动锁定和记录。
   SkyView 在目录准备后即挂载，接管后保持同一实例；轨迹、洞察、档案预热不阻塞首帧。
   正式全球进入反向复用相机；退出从当前旋转/缩放对准 Observer 后推进。历史返回由已有时钟
   驱动，在历史与实时两份真实快照间按 ID 做球面呈现插值，回到 LIVE 后再推进；
   SkyPresentationMode + 前台帧时钟完成转场，不使用游离延迟回调。
   Reduce Motion 关闭旋转、推进与呼吸，使用 0.16s 就地交接。
   `ObservationJourneyContext` 固定起始指向、视场和 Observer 版本；`ObservationGlobePose` 在全球
   失去交互权时保存当前构图，阻止旋转或惯性改写旅程起点。共享相机中段以 12° 地平线视线引导，
   地表、目标与背景使用同一镜头，末段接回最新传感器指向，不写回业务姿态。地表球半径逐渐匹配
   当地 WGS84 海平面半径，保持近地镜头在表面之外；全球和局部投影端点保持原有映射。
   Reduce Motion 的手势预览不显示飞行，松手后才做短交接；旅程期间不累计捕获，回天空重置采样时钟。
10. 地球大陆不能因拖动、缩放或惯性而消失。主表面使用构建期从 Natural Earth 陆地多边形生成的
    等面积点阵；运行时只旋转预计算单位球方向并按海岸邻近等级批量填充 Path。资源加载或损坏时
    使用现有海岸线回退；两者都不把琥珀交互色用作大陆主色。
11. 全球卫星场必须按背面、地球盘面、外侧壳层和近景四档批量绘制；地球盘面上的前景卫星只能
    使用低对比测量点，完整微型轮廓只分配给策展目标与确定性稀疏样本。地球前景边缘在卫星层后
    重新描画，以稳定遮挡关系；不得用切换对象集合制造层次。
12. 筛选、记录或设置面板展开时保留主天空实例、绘制表面与冻结观测时刻，暂停捕获采样、
    高频姿态与 Timeline 帧更新，不替换为黑色 View。收回后重置采样时钟，隐藏间隔不算驻留。
    面板最终高度为底缘到顶部安全区的 84%，保持 18pt 留白与 24pt 圆角；下拉关闭只附着顶栏，
    不能与正文 List 的滚动或 swipeActions 竞争。筛选只修改既有筛选事实，不触发目录 IO 或逐帧传播。
    筛选、记录、全球、设置四个底栏目的根页必须复用同一向下返回天空控件、44pt 热区、水平锚点、
    顶部下拉阈值和 VoiceOver Escape 语义；详情子页仍使用左箭头与左缘返回，不能混用根页关闭语义。
13. 全球默认镜头把观察者经度置于中央经线，使地轴屏幕投影竖直、赤道与纬线水平；假定坐标为上海。
    空闲展示旋转复用既有 30fps `TimelineView`，每帧只计算一次沿地球局部极轴的四元数并组合进
    统一场景姿态；不得新增 Timer 或 CADisplayLink。地球手势与时间轴惯性期间保持暂停，结束
    2 秒后连续恢复；Reduce Motion 下必须保持静止，J2000 背景恒星始终不参与该旋转。

## 本地化与资料边界

- `Localizable.xcstrings` 管理 App 界面，`SatelliteText.xcstrings` 管理卫星状态、洞察和自动档案。
- `SupportedLanguage` 只把系统 Locale 映射为 `en` 或 `zh-Hans`，不得保存第二份用户选择。
- `catalog.json` 是语言中立轨道事实源，不得重新写入本地化摘要或观测故事。
- `SatelliteInsightSnapshot` 只保存数值事实；所有句子由展示格式器按当前语言生成。
- 观测日志只持久化身份与轨道快照。旧 JSON 的额外文本字段由 Codable 忽略，不得继续展示。

## Swift 并发约束

- 会发布 UI 状态的服务标记 `@MainActor`。
- `Task.detached` 只接收值语义快照，不捕获可变 UI 状态。
- 后台结果回到 `MainActor` 后，先验证观察者/请求时刻仍然有效，再替换缓存。
- 所有长任务必须响应取消；筛选或观察者变化不能让旧任务覆盖新结果。

## 工程生成

`project.yml` 是 Xcode 工程结构和 Info.plist 声明的来源。增加、删除或移动源文件后运行：

```bash
xcodegen generate
```

提交前确认生成后的 `StarCatch.xcodeproj/project.pbxproj` 只包含预期文件和设置变化。
不要只在 Xcode Build Settings 中手改可由 `project.yml` 表达的配置，否则下一次生成会
丢失该改动。

## 分级验证

按改动风险选择最低但足够的验证，不默认全量运行：

1. 纯文档/注释：`git diff --check`。
2. 视图拆分、重命名、工程配置：一次 Simulator Debug 编译。
3. 状态机、时间或轨道计算：相关 `-only-testing` 用例 + 一次编译。
4. 姿态、手势、动效或性能：先做针对性测试，再进行一次模拟器或真机检查。

如果同一运行时验证连续失败，应停止重复尝试，改用纯逻辑测试、日志或真机验证。
默认仅用 iPhone 17 做一轮必要交互检查，视觉取样限于关键帧，不默认扩展机型或完整截图矩阵。

## 仓库卫生

- `audit/`、DerivedData、Xcode `xcuserdata`、`.DS_Store`、Python 字节码和 Obsidian
  工作区状态都属于可再生的本机产物，不得作为工程源文件保存。
- `SatelliteKnowledge/Profiles` 与 `Families` 是文字资料源；编译出的
  `StarCatch/Resources/satellite_profiles.json` 是受校验的运行时产物。
- `project.yml` 是工程结构唯一来源，`StarCatch.xcodeproj` 是为了直接打开 Xcode
  而保留的生成结果。二者改变时必须一起验证。
- 经过挑选的商店截图只存入仓库根目录 `AppStore/Screenshots`；临时截图、模拟器窗口图和对比图不得堆积在 `StarCatch` 源码目录。

## 暂缓的高风险重构

以下问题真实存在，但不能在普通清理中机械修改：

1. `SkyView.swift` 同时编排 30fps Canvas、捕获关系、空间档案、缩放和全局星图，
   文件较大。拆分前需要为姿态变化、锁定/离屏/回归和时间轴建立可重复的视觉基线；
   不能通过放宽 `private` 或跨文件共享可变状态来追求行数下降。
2. 设置与观测记录已经拆成独立 `NavigationStack` 功能流，并分别使用轻量 `SettingsRoute` 和
   `ObservationRoute`。后续修改仍需保持清空记录、动态字体、原生列表手势和“目录中已不存在的
   历史对象”回退测试。
3. 离线轨道快照的长期更新方式属于产品决策：随 App 版本更新、增加受控联网刷新，
   或建设自有数据服务会改变隐私、审核和运维边界，本轮不替用户选择。

## 改动检查表

- 是否仍然只有一个姿态、时间和捕获阶段事实源？
- 是否把业务计算留在服务/模型，把视图保持为编排？
- 是否避免在 30fps 路径中新建昂贵对象或同步传播全目录？
- 是否保持离线运行与本地隐私承诺？
- 是否同步更新 `project.yml`、测试和相关文档？
- 是否用了与风险相称的最小验证？
