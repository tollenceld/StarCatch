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
- 默认请求完整位置精度，因为近地轨道目标会随观察者位置产生明显视差；坐标仅在
  设备内计算真北与拓扑方位，不上传或持久化，用户仍可在系统中选择近似位置。
- Archive 自动发布检查：目录时效、资源 schema、隐私清单、图标和依赖锁定不合格时直接阻止归档。
- 目录损坏或缺失时提供用户可见诊断和支持入口。
- 应用内明确标注“仅供教育与观测，不用于导航、碰撞规避或安全决策”。
- `AppStore/Metadata/zh-Hans` 已准备产品描述、关键词、审核说明和答卷草案。

## App Store Connect 仍需人工填写

- 正式应用名：建议 `StarCatch`。
- 副标题建议：`把真实卫星带回视野`。
- 主分类建议：教育；次分类建议：工具。
- 隐私回答：当前版本可选择“不从此 App 收集数据”，前提是发布构建保持无分析、广告和网络上传。
- 隐私政策 URL：`https://github.com/tollenceld/StarCatch/blob/main/PRIVACY_POLICY.md`。
- 支持 URL：当前临时使用 `https://github.com/tollenceld/StarCatch/issues`。正式提交前应提供包含可联系邮箱的公开支持页，并由账号持有人确认版权主体和适用地区要求的商家联系方式。
- 新版年龄分级问卷；当前内容预计适合最低年龄档，最终以问卷结果为准。
- 1–10 张 App Store 截图；优先提供 6.9 英寸 iPhone 规格。
- App Review 备注：说明真机使用定位与姿态，模拟器使用拖拽；拒绝定位时使用北京假定坐标。
- Signing Team、分发证书、Provisioning Profile、App Store Connect App Record 和 TestFlight 外部测试。
- App Store Connect 中的价格与销售范围、税务和银行协议、出口合规问卷。
- 欧盟数字服务法（DSA）商家身份；如在中国大陆提供，还需由发行主体确认 ICP/当地许可与内容合规。
- 确认 CelesTrak 数据用于商用 App 随包分发的权利与持续更新责任；仓库内署名不能替代发行主体的法律判断。
- 在至少一台真机完成定位允许/拒绝、姿态、前后台恢复、低电量与离线回归。
- 通过 TestFlight 内测验证安装、升级和观测记录迁移，再选择分阶段发布或手动发布。

## 发布前产品风险

当前 TLE 数据随应用打包。Archive 已禁止使用超过 14 天的快照，但上架审核和已安装版本会继续消耗时间，因此发行主体仍需确定稳定的版本更新节奏或后续数据服务；否则核心观测精度会在发布后逐渐下降。

## 每个候选版本的最小门禁

```bash
python3 Scripts/update_catalog.py
python3 Scripts/satellite_knowledge.py validate
python3 Scripts/release_check.py
```

随后用 Xcode 的 Release 配置执行测试、Archive 和 Validate App。上传后不要直接发布：先在 TestFlight 安装上传构建，逐项复核权限、目录日期、隐私链接、支持链接和商店截图。
