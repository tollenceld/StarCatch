# StarCatch 工作规则

本文件是跨模型、跨会话都必须遵守的项目级规则。它只记录长期有效的约束；具体任务的进度放在 `CURRENT_TASK.md`，稳定项目背景放在 `PROJECT_CONTEXT.md`。

## 新会话与模型切换

每次模型切换或新会话开始后，按以下顺序恢复上下文：

1. 读取 `AGENTS.md`、`PROJECT_CONTEXT.md`、`CURRENT_TASK.md`。
2. 执行 `git status --short --branch`，确认当前分支、已修改文件和未跟踪文件。
3. 再阅读当前任务涉及的源码、测试和项目文档；不要假设上一个模型的工作区是干净的。

## Git 与仓库安全

- 当前仓库已有 Git 历史；保留已有提交，不重复初始化，不使用 `git reset --hard`、强制 checkout 或强制 push。
- 默认只进行本地 Git 操作。没有明确授权时，不 fetch、pull、push，不创建或修改 GitHub 远端内容。
- 提交前先检查 diff，按任务范围选择性暂存；不得把密钥、环境变量、本机配置、缓存、构建产物或日志提交进去。
- 每次完成重要任务后，更新 `CURRENT_TASK.md`，然后创建一个清晰、范围单一的提交。
- 若工作区已有其他人的未提交改动，保留它们并与当前任务分开；不要为了得到“干净状态”而覆盖、回滚或偷偷提交。

## 项目事实源与工程边界

- `project.yml` 是 XcodeGen 工程结构和 Info.plist 声明的事实源；改动工程结构后重新生成并检查生成结果。
- 产品、数据和运行流程以 `Documentation/PROJECT_OVERVIEW.md` 为准；状态所有权、并发和性能边界以 `Documentation/ARCHITECTURE.md` 为准。
- 应用是 iOS 17+ SwiftUI 项目，运行时使用本地轨道快照和 SatelliteKit；保持离线运行与本地隐私承诺。
- `SatelliteKnowledge/` 是资料源，`Scripts/` 是目录/资料校验与发布辅助脚本。不要在 30fps 绘制路径中加入文件 IO、网络请求或全目录传播。

## 验证与交接

- 文档或配置改动至少执行 `git diff --check`，并检查 Git 状态与忽略规则。
- Swift、工程或运行时改动按 `Documentation/ARCHITECTURE.md` 的分级验证规则选择最小充分测试。
- `CURRENT_TASK.md` 必须说明当前状态、已完成内容、涉及文件、验证结果和下一步；如果任务被阻塞，记录具体原因，不写模糊的“继续处理”。
