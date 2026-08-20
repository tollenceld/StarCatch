# StarCatch 1.0 发布就绪审计

审计日期：2026-08-21
范围：iOS 工程、运行时数据、隐私、依赖、性能边界、商店材料、审核演示与账号侧发布条件。

## 结论

StarCatch 已达到 **Release Candidate** 工程状态：Release 模拟器构建、无签名 iOS Archive、78 项单元测试和发布门禁均通过；核心体验、权限降级、错误页、隐私清单、许可、商店文本与 6.9 英寸截图已具备。

它还不能被仓库单方面认定为“可以点击发布”。剩余阻断项需要 Apple Developer / App Store Connect 账号持有人、真机或发行主体身份才能完成。

## 仓库内已验证

- 运行时无账号、广告、分析、跟踪、支付、推送或业务后端；轨道计算与记录均在设备上完成。
- 定位仅请求 When In Use；为避免低轨视差默认申请完整精度，所有计算仍在设备内，
  用户选择近似位置时会显示低精度提示，拒绝后有明确假定坐标降级。
- `PrivacyInfo.xcprivacy` 声明不跟踪、不收集，并为 UserDefaults 提供 `CA92.1` 理由。
- App Icon 为 1024×1024 RGB PNG，无 Alpha；应用只支持 iPhone 竖屏。
- SatelliteKit 锁定至 2.1.2 和固定 revision；第三方软件与数据物料已记录。
- 16,395 个对象的随包目录已于 2026-08-20 刷新；超过 72 小时将自动阻止 Archive。
- 3,817 份逐星档案与 8 份系列档案使用 schema v3；每条导语、事实、章节和里程碑都关联结构化来源与 object/family 范围。
- 目录损坏时显示可理解的错误、诊断和支持入口，不会只剩空天空。
- Release 构建使用优化、Whole Module Optimization、dSYM、Dead Code Stripping 与产品验证。
- 商店描述、关键词、审核步骤、隐私/年龄答卷草案和 1320×2868 演示截图已准备。

## P0：提交前必须由发行方完成

1. **签名与上传**：确认 Bundle ID、分发证书、Provisioning Profile、App Store Connect App Record，完成有签名 Archive、Validate App 与 TestFlight 安装。
2. **真机验收**：至少覆盖一台 iPhone 17 系列设备的允许定位、拒绝定位、近似/精确位置、姿态、前后台恢复、离线、低电量和温升；模拟器不能证明磁航向精度与持续帧率。
3. **轨道数据刷新**：上传候选构建当天更新目录。72 小时门禁避免误发旧包，14 天仅作为开发数据绝对失效上限；两者都不能解决已安装版本继续老化，仍需确定版本更新节奏。
4. **公开支持身份**：提供可联系邮箱及适用地区要求的商家名称、地址或电话。GitHub Issues 可作为工单渠道，但不应是唯一商家联系证明。
5. **内容权利**：由发行主体确认 CelesTrak 数据在商业 App 中随包分发的权利与更新责任；署名和遵守查询频率不等同于法律确认。
6. **App Store Connect 合规**：完成最新版年龄分级、App Privacy、出口合规、价格和销售范围、税务/银行协议、版权主体，以及欧盟 DSA 商家身份。若选择中国大陆销售，还需单独确认 ICP/许可与当地内容要求。
7. **审核信息一致**：将仓库内更新后的隐私政策发布到公开 URL；核对 App 内、产品页和问卷对位置、离线目录与数据收集的表述完全一致。

## P1：首发后优先安排

- 为目录刷新建立明确负责人、日历和失败告警；每个候选版本保留来源日期和生成日志。
- 在真实设备用 Instruments 记录首次进入天空、第一次对焦、连续旋转地球 60 秒及内存警告后的表现。
- 完成 VoiceOver 与最大辅助字号矩阵后，再在 Product Page 声明对应辅助功能。
- 使用 TestFlight 分阶段收集方向偏差、目标匹配和机型温升；不要引入用户追踪来替代匿名、主动反馈。
- 若未来建设在线目录服务，先设计缓存、签名、回滚、隐私和 CelesTrak 查询频率，再修改“不收集数据”的声明。

## 官方要求基线

- Apple 当前提交 SDK 要求：[Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)
- 审核规则：[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- 版本所需字段：[Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- 隐私披露：[Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- 截图规格：[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- 年龄分级：[Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)
- 数据来源使用策略：[CelesTrak Usage Policy](https://celestrak.org/usage-policy.php)
