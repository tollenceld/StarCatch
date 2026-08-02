# 当前任务：收口 Release Candidate 并统一到 main

状态：已完成（2026-08-02）

## 目标

保留当前全部产品、性能、导航、发布与商店资料改动，将开发历史安全快进到本地 `main`，并删除不再需要的本地开发/备份分支，使这台设备后续只在 `main` 上开发。

## 已完成

- 完成主天空、目标感应/对焦/锁定、详情阅读宽限、筛选、顶部状态翼、统一导航与底部控件的整体收口。
- 完成局部天空与沉浸式三维全局星图的连续尺度、地球与观察者表达、时间轴和惯性交互优化。
- 完成设置、观测记录、隐私、手册和深入档案的页面规范、对齐与返回行为统一。
- 清理不再使用的 `ArchiveField.swift`，并保留经过验证的运行时与工程结构。
- 优化目录加载、轨道传播和首个目标档案预热，避免首轮交互承担大资源初始化。
- 补齐默认近似定位、目录失败诊断、教育/观测用途声明与更新后的隐私政策。
- 新增 Archive 发布门禁，校验轨道目录时效、隐私清单、图标、版本配置和依赖锁定。
- 准备简体中文 App Store 元数据、审核答卷草案、软件物料清单、发布审计和 6 张 6.9 英寸实际界面截图。
- 核对三个本地分支：旧备份分支的最终文件树与原 `main` 完全一致；当前开发分支可从 `main` 直接 fast-forward。
- 当前成果已提交并快进到本地 `main`；另外两个本地分支已删除。
- 经用户明确授权，以普通 fast-forward 将本地 `main` 推送到 GitHub，并删除远端 `agent/consolidate-current-work`；本地与远端现在都只保留 `main`。

## 主要涉及范围

- `StarCatch/App`、`StarCatch/Sky`、`StarCatch/Archive`
- `StarCatch/Orbits`、`StarCatch/Pointing`、`StarCatch/Design`、`StarCatch/Engagement`
- `StarCatchTests`
- `AppStore`
- `Documentation`
- `Scripts/release_check.py`
- `project.yml`、`StarCatch.xcodeproj`、`Info.plist`、隐私与项目说明

## 验证

- 78 项单元测试通过，0 失败、0 跳过。
- Debug 模拟器构建运行通过；Release 模拟器构建通过。
- 无签名 iOS Device Archive 通过，并包含 dSYM、隐私清单和随包轨道资源。
- `SatelliteKnowledge` 校验通过：3,832 份逐星档案、8 份星座共享档案。
- 发布门禁通过：16,243 个对象，目录龄期 6.3 天；模拟 24.6 天旧目录时可正确阻止发布。
- 6 张商店截图均为 1320×2868 RGB JPEG。
- 已执行 `git diff --check` 并复核未跟踪文件、忽略规则和分支关系。
- 已通过 `git ls-remote --heads origin` 确认 GitHub 只存在 `refs/heads/main`，其提交与本地 `main` 一致。

## 下一步

- 后续工作直接从本地 `main` 开始，保持一次重要任务对应一个范围清晰的提交。
- 后续需要同步 GitHub 时，继续在用户明确授权后以普通 push 更新 `main`，不使用强制推送。
- 正式上架前完成有签名 Archive、Validate App、TestFlight 真机验证、商家身份和数据分发权利确认。
