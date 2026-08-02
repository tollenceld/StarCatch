# StarCatch 软件与数据物料清单

本文件记录 1.0 版本随 App 分发或参与构建的第三方组件，供发布审核与后续安全更新使用。

## 运行时依赖

| 组件 | 锁定版本 | 用途 | 许可 | 是否联网 |
| --- | --- | --- | --- | --- |
| [SatelliteKit](https://github.com/gavineadie/SatelliteKit) | 2.1.2 / `9a87cdb80344f26e81bc5fc82fdf9a3350478603` | SGP4 轨道传播与坐标计算 | MIT | 否 |

实际锁定值以 `StarCatch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 为准。发布检查会验证版本与 revision 均存在。

## 随包数据

| 数据 | 来源 | 处理方式 | 运行时更新 |
| --- | --- | --- | --- |
| NORAD GP/OMM 轨道元素 | [CelesTrak](https://celestrak.org/) | 发布前拉取、校验并编译为离线 `catalog.json` | 否 |
| 天体与星座说明 | 仓库内 `SatelliteKnowledge` | Markdown 编译为 `satellite_profiles.json` | 否 |

CelesTrak 的署名和使用说明见仓库根目录 `NOTICE`。正式发布前，内容权利与商用分发判断仍需由发行主体确认。

## Apple 系统框架

SwiftUI、CoreLocation、CoreMotion、Combine 与 Foundation 均来自 iOS SDK，不作为第三方 SDK 单独列出。当前版本未集成账号、广告、分析、崩溃上报、支付或远程推送 SDK。

## 更新责任

- 每次升级 Swift Package 后，复核许可、隐私清单与 Required Reason API。
- 每次 Archive 前运行 `python3 Scripts/release_check.py`；脚本也会由 Archive 构建阶段自动执行。
- 轨道快照超过 14 天时禁止归档，应先运行 `python3 Scripts/update_catalog.py`。
