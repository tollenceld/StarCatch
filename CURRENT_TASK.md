# 当前任务：启动系统与卫星深度档案视觉重构

状态：已完成（2026-08-24）

## 目标

解决启动页过于简陋、中文状态基线错位，以及深度档案第一眼无法说明卫星用途的问题；在不
改变轨道事实源和性能边界的前提下，重建中英文一致的视觉层级和阅读路径。

## 已完成

- 启动页保留固定 `STARCATCH` 标题，以窄幅焦平面逐字激活，新增分段校准轨、光学边界及
  目录／轨道／姿态三项模块状态；背景沿用低密度星场，不加入大型圆环或移动准星。
- 状态点、系统名称和实时阶段改为同一基线的自适应布局，删除导致“正在检测”错位的固定
  英文宽度；首次启动介绍也全部进入 String Catalog。
- 深度档案首屏改为身份主视觉：先显示可靠任务角色、轨道层级、目标名、用途短句和可信
  身份徽标，让用户在进入参数之前知道目标是什么、用来做什么。
- 档案改为“观测／任务／数据”三视图：当前天空与轨道概览负责即时理解，任务页承载本星／
  系列资料和官方来源，数据页承载完整轨道参数、标识与来源。
- 角色文案只使用现有可靠分类和资料范围映射；未知信息不猜测。HST 等已知类型可直接显示
  “空间望远镜／Space telescope”，NORAD、LEO、AZ／EL 等标准标识保持原文。
- 摘要动效继续复用既有真实轨道运动模型；新布局未把 SGP4、IO 或目录扫描放入帧循环。

## 涉及文件

- `StarCatch/App/BootFieldView.swift`
- `StarCatch/App/BootSequenceView.swift`
- `StarCatch/Archive/SatelliteStoryView.swift`
- `StarCatch/Localization/Localizable.xcstrings`
- `StarCatch/Localization/SatelliteText.xcstrings`
- `StarCatchTests/TimeTests.swift`
- `Documentation/PROJECT_OVERVIEW.md`

## 验证

- iOS Simulator Debug 构建通过。
- `TimeTests/testBootTimelineWakesLettersAndReportsRealSystemState` 通过。
- iPhone 17 Pro / iOS 26.3 分别以简体中文和英文检查启动页与深度档案；中文用途、英文
  `Space telescope`、三视图标签、长说明和轨道数据均未出现截断或跨语言正文。
- `release_check.py --now 2026-08-21T00:00:00Z` 通过：16,395 个对象，目录年龄 0.3 天。
- String Catalog JSON 解析与 `git diff --check` 通过。

## 发布边界

- 模拟器不能替代真机的最大动态字体、VoiceOver 阅读顺序和户外低亮度检查；提交 App Store
  前仍应在 iPhone 17 Air 与 17 Pro 真机各完成一次中英文档案巡检。
- 运行时继续完全离线；本轮未修改目录、捕获阈值、轨道传播或观测记录语义。
