# StarCatch App Store 提交清单

本清单只记录仓库内可验证的交付项和必须由 App Store Connect 账号持有人完成的事项。

## 已在工程中完成

- 独立 Bundle ID 与显示名。
- 1024×1024、无透明通道的 App Icon。
- 应用内隐私说明入口。
- `PrivacyInfo.xcprivacy`：无跟踪、无收集，UserDefaults 使用理由 `CA92.1`。
- 定位用途说明、拒绝后的假定坐标降级和系统设置恢复入口。
- 本地观测记录删除入口。
- 前后台生命周期处理、目录缺失错误状态、Reduce Motion 支持。
- 真实版本号展示和非豁免加密声明。

## App Store Connect 仍需人工填写

- 正式应用名：建议 `StarCatch`。
- 副标题建议：`把真实卫星带回视野`。
- 主分类建议：教育；次分类建议：工具。
- 隐私回答：当前版本可选择“不从此 App 收集数据”，前提是发布构建保持无分析、广告和网络上传。
- 隐私政策 URL：`https://github.com/tollenceld/StarCatch/blob/main/PRIVACY_POLICY.md`。
- 支持 URL：`https://github.com/tollenceld/StarCatch/issues`；提交前仍需由账号持有人确认开发者联系邮箱与版权主体。
- 新版年龄分级问卷；当前内容预计适合最低年龄档，最终以问卷结果为准。
- 1–10 张 App Store 截图；优先提供 6.9 英寸 iPhone 规格。
- App Review 备注：说明真机使用定位与姿态，模拟器使用拖拽；拒绝定位时使用北京假定坐标。
- Signing Team、分发证书、Provisioning Profile、App Store Connect App Record 和 TestFlight 外部测试。

## 发布前产品风险

当前 TLE 数据随应用打包。LEO 轨道会随时间老化，正式长期运营前需要确定可信的在线刷新、版本更新节奏或自有数据服务；否则核心观测精度会在发布后逐渐下降。
