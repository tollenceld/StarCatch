# 当前任务：全局三维地球、空间手感与尺度转场收口

状态：已完成（2026-08-09）

## 目标

在不增加产品功能和在线依赖的前提下，提升局部天空与全局三维地球之间的尺度连续性、地球旋转与缩放手感、海岸线精度、真实卫星密度表达，并修复全局页左上角返回翼的宽度适配。

## 已完成

- 移除局部天空与全局 Canvas 在尺度转场中的逐帧模糊合成，改为同一进度驱动的缩放与交叉淡化；转场时间曲线缩短并提高尾段连续性。
- 将地球拖动与松手惯性使用同一组角度灵敏度，惯性更新提高到 60Hz，降低旋转与缩放阻尼，并继续保留边界软减速和无反弹规则。
- 引入 Natural Earth 1:50m 公共领域海岸线，预生成 0.30° 视觉简化的 58KB 离线二进制资源；运行时在后台只解码一次，Canvas 不执行文件 IO、GeoJSON 解析或地图简化。
- 保留原有轻量内嵌轮廓作为资源准备期间的首帧回退；交互期间稳定降低海岸线点数，停止后恢复 7,030 个海岸线坐标。
- 全局地球静止时改为读取筛选后的完整轨道目录，而非大型星座代表性样本；当前模拟器帧显示 16,179 个已准备点位 / 16,243 个目录对象。
- 普通轨道对象统一为克制的白色点核，并合并成远近两类 Canvas 批次；拖动、惯性与缩放期间按稳定 NORAD 取模降采样，停止后恢复完整目录，避免随机闪烁。
- 左上角“天空”返回翼改为按图标与文字的真实内容宽度收紧，同时继续以灵动岛边缘作为对齐基准；无灵动岛紧凑布局也采用相同规则。
- `project.yml` 显式声明营销版本与构建版本占位符，重新生成并检查 `StarCatch.xcodeproj` 和 `Info.plist`。
- 新增海岸线编译脚本、数据来源与公共领域说明，以及二进制解码和渲染层级定向测试。

## 主要涉及文件

- `StarCatch/Sky/SkyOverviewView.swift`
- `StarCatch/Sky/EarthCoastlineStore.swift`
- `StarCatch/Sky/SkyView.swift`
- `StarCatch/Sky/SkyStatusIndicator.swift`
- `StarCatch/Design/Motion.swift`
- `StarCatch/Resources/earth_coastlines_50m.bin`
- `Scripts/compile_coastlines.py`
- `Documentation/NATURAL_EARTH_DATA.md`
- `StarCatchTests/TimeTests.swift`
- `project.yml`、`StarCatch.xcodeproj`、`StarCatch/Info.plist`

## 验证

- iPhone 17 Pro / iOS 26.3 Debug 模拟器构建、安装与运行通过。
- 全局星图实际运行截图复核通过：高精度海岸线、完整目录白点、观察者与视域、紧凑返回翼和时间轴均正常显示。
- 6 项定向测试通过，覆盖尺度交叉淡化、三维投影、稳定细节抽样、空间阻尼边界、缩放边界和海岸线二进制解码。
- 应用包确认包含 58KB `earth_coastlines_50m.bin`；生成脚本输出与提交资源逐字节一致。
- `git diff --check` 通过；构建仅有无 App Intents 依赖时的系统元数据跳过提示，无产品代码警告。
- 当前 Xcode 安装的 AXe / SimulatorKit 架构不兼容，无法由自动化工具注入拖拽手势或录制转场视频；真实运行、页面进入和静止细节恢复已验证，最终惯性触感仍建议在真机发布检查中复核。

## 下一步

- 在 iPhone 17 系列真机上复核快速甩动、慢速拖动、双指缩放越过尺度阈值与反向返回的触感。
- 如真机 GPU 数据显示完整目录恢复帧仍有压力，优先调整静止细节点核大小或恢复延迟，不回退到随机抽样或逐点 SwiftUI View。
- 需要同步 GitHub 时，等待用户明确授权后再普通推送 `main`，不使用强制推送。
