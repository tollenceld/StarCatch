# StarCatch 工作规则

本文件只记录跨模型、跨会话都必须遵守的长期规则。稳定项目背景与文档路由集中在
`PROJECT_CONTEXT.md`；具体需求、验收标准和讨论保留在对应的 Codex 任务中，代码进度以功能
分支、提交和工作区 diff 为准。

## 新会话与模型切换

每次模型切换或新会话开始后，按以下顺序恢复上下文，不要预读整个资料库：

1. 读取 `AGENTS.md` 与 `PROJECT_CONTEXT.md`。
2. 执行 `git status --short --branch`，确认当前分支、已修改文件和未跟踪文件。
3. 若不在 `main`，用 `git log --oneline main..HEAD` 与 `git diff --stat main...HEAD` 恢复已提交
   进度，再检查未提交 diff。
4. 只阅读当前任务涉及的源码、测试和长文档章节；先用 `rg` 定位标题或符号，不要默认完整读取
   `Documentation/PROJECT_OVERVIEW.md` 或 `Documentation/ARCHITECTURE.md`。

## Git 与仓库安全

- 当前仓库已有 Git 历史；保留已有提交，不重复初始化，不使用 `git reset --hard`、强制 checkout 或强制 push。
- 默认只进行本地 Git 操作。没有明确授权时，不 fetch、pull、push，不创建或修改 GitHub 远端内容。
- 一个独立功能默认对应一个 Codex 任务、一个 Worktree 和一个 `codex/` 功能分支；不要把无关修改
  混入同一分支。
- 提交前先检查 diff，按任务范围选择性暂存；不得把密钥、环境变量、本机配置、缓存、构建产物或日志提交进去。
- 完成可独立审阅的工作后创建清晰、范围单一的提交；提交信息与 diff 应足以恢复代码进度，
  不再维护容易过期的全局“当前任务”文档。
- 若工作区已有其他人的未提交改动，保留它们并与当前任务分开；不要为了得到“干净状态”而覆盖、回滚或偷偷提交。

## 默认功能开发流程

- 一个新的独立功能、优化、Bug 修复或重构，默认从干净且已同步的 `main` 新建 Codex 任务和
  Worktree；不要直接在 `main` 开发，也不要在旧功能对话中追加无关任务。
- 首次提交前创建 `codex/` 分支，按 `codex/feat-*`、`codex/fix-*`、`codex/refactor-*` 或
  `codex/chore-*` 命名。属于同一功能的补充、测试和审查修改继续留在原任务与分支。
- 开工前先界定目标、验收标准和不得改变的范围；只读取相关源码、测试和文档章节。用户只需
  描述本次需求，不必重复粘贴本文件中的恢复、Git、Worktree 和验证规则。
- 实现后按风险执行最小充分测试，检查相对 `main` 的完整 diff，提交到功能分支并汇报结果。
- 功能分支不会自动合并或 push。用户确认后，才将它普通合并到 `main` 并按授权 push；禁止
  force push。完成集成后确认 `main` 与远端同步、工作区干净，再归档对应任务和 Worktree。

## 项目事实源与工程边界

- `project.yml` 是 XcodeGen 工程结构和 Info.plist 声明的事实源；改动工程结构后重新生成并检查生成结果。
- 产品、数据和运行流程以 `Documentation/PROJECT_OVERVIEW.md` 为按需事实源；状态所有权、并发和
  性能边界以 `Documentation/ARCHITECTURE.md` 为按需事实源。先查看目录，只读与任务相关的章节。
- 应用是 iOS 17+ SwiftUI 项目，运行时使用本地轨道快照和 SatelliteKit；保持离线运行与本地隐私承诺。
- `SatelliteKnowledge/` 是资料源，`Scripts/` 是目录/资料校验与发布辅助脚本。不要在 30fps 绘制路径中加入文件 IO、网络请求或全目录传播。

## 验证与交接

- 文档或配置改动至少执行 `git diff --check`，并检查 Git 状态与忽略规则。
- Swift、工程或运行时改动按 `Documentation/ARCHITECTURE.md` 的分级验证规则选择最小充分测试。
- 交接时在当前 Codex 任务中说明状态、涉及文件、验证结果和下一步；新对话优先从 Git 分支、
  提交与 diff 恢复事实，不复制已能从仓库直接获得的信息。
