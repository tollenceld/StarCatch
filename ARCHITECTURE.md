# StarCatch 工程边界

这份文档描述当前代码的职责边界与改动约束。它不是产品说明；产品体验见
`README.md`，离线目录发布流程见 `Scripts/README.md`。

## 运行时依赖方向

```text
RootView
├── SkySession ── CatalogStore / EphemerisEngine / ObserverLocation
├── SkyClock
└── CaptureStateMachine
     │
     └── SkyView（编排）
          ├── Projection（纯几何）
          ├── SkyRenderer（Canvas 绘制）
          ├── TrailStore（短生命周期轨迹）
          └── 独立 SwiftUI 控件
```

依赖只能沿图向下。轨道层不知道 SwiftUI 页面，绘制层不拥有业务状态，视图不自行
解析目录或执行 SGP4。新增功能应优先扩展现有领域对象，而不是在 `body` 中建立第二套
状态。

## 状态所有权

| 状态 | 唯一所有者 | 说明 |
| --- | --- | --- |
| 启动、手册与设置页呈现 | `RootView` | APP 级页面编排 |
| 设备指向、观察者、目录筛选、星历 | `SkySession` | 天空会话的共享事实源 |
| 当前/过去/未来观测时刻 | `SkyClock` | 时间轴唯一事实源 |
| 探索、捕获、锁定、换锁、释放 | `CaptureStateMachine` | 不在视图中复制阶段状态 |
| 主天空局部动画、缩放、面板测量 | `SkyView` | 只影响当前视图生命周期 |
| 时间/全景拖尾 | `TrailStore` | 由所属视图创建和销毁 |
| 观测记录 | `ObservationLog` | 本地持久化，不依赖页面是否打开 |

任何新的 `@State` 都应先回答：它是否只是呈现状态？如果答案是否定的，它通常应该
进入上表中的领域对象。

## 目录与轨道边界

- `CatalogModels.swift`：应用内稳定的目录模型与筛选语义。
- `CatalogStore.swift`：只负责解码随包资源、去重、建立索引与 SatelliteKit 对象。
- `EphemerisEngine.swift`：负责传播调度、缓存、LIVE 插值与冻结时刻快照。
- `TrackSampler.swift` / `PassPredictor.swift`：基于星历的低频派生能力。
- `Scripts/update_catalog.py`：仅发布期联网；APP 运行时保持完全离线。

不要把 OMM/TLE 解码字段泄漏到 UI，也不要让页面直接创建 `Satellite`。

## 天空渲染边界

`SkyView` 是编排层：收集当前姿态、观测时刻和捕获阶段，并把稳定输入交给纯几何与
绘制函数。可复用控件已经拆到：

- `CatalogFilterControl.swift`
- `SkyActionControls.swift`
- `TimeDial.swift`

继续拆分时应优先提取具备明确输入/输出的独立 `View` 或纯计算类型。不要为了减少
单文件行数，把 `SkyView` 私有状态改成跨文件可写的全局状态。

每帧路径遵守三条规则：

1. 不在 Canvas 循环中做文件 IO、JSON 解码或网络调用。
2. 大目录使用批量绘制；只有捕获目标和精选对象保留独立细节。
3. SGP4 批量传播在后台任务执行，主线程只接收完整快照。

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

## 改动检查表

- 是否仍然只有一个姿态、时间和捕获阶段事实源？
- 是否把业务计算留在服务/模型，把视图保持为编排？
- 是否避免在 30fps 路径中新建昂贵对象或同步传播全目录？
- 是否保持离线运行与本地隐私承诺？
- 是否同步更新 `project.yml`、测试和相关文档？
- 是否用了与风险相称的最小验证？
