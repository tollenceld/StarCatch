# StarCatch App Store 交付包

这里保存可直接用于 App Store Connect 的文本、审核说明和截图规划。它们不进入 App 安装包。

## 提交顺序

1. 更新轨道目录并运行 `python3 Scripts/release_check.py`。
2. 使用 Release 配置完成 Archive；构建阶段会再次执行发布检查。
3. 在真机验证首次权限、拒绝权限、后台恢复、锁定和全局星图。
4. 按 `Screenshots/zh-Hans/README.md` 生成 6.9 英寸主截图。
5. 将 `Metadata/zh-Hans` 与 `Metadata/en-US` 中的字段分别复制到 App Store Connect。
6. 由账号持有人完成签名、隐私答卷、年龄分级、出口合规、版权主体、支持联系方式和地区合规。

不应把 GitHub Issues 当作最终商家联系方式的唯一证明。正式支持页需要由发行主体确认可公开的电子邮箱，以及适用地区要求的商家名称、地址或电话。
