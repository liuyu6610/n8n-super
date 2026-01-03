# Workflow-as-Code：让每个 n8n Workflow“像代码一样”可执行、可追溯、可发布、可回滚

## 1. 目标（SRE 视角的四个“必须”）

你们要的不是“把流程画出来”，而是把流程变成一种 **工程化资产**：

- **可执行**：工作流定义可被自动部署到目标环境
- **可追溯**：每次执行都有证据链（谁触发、输入参数、执行过程、输出、失败点）
- **可评审**：像代码一样走 PR/CR
- **可回滚**：变更出问题可以快速回滚到上一个稳定版本

## 2. 关键前提：n8n 是“有状态系统”，必须先选“权威源（Source of Truth）”

Workflow-as-Code 的核心不是“能导出 JSON”，而是你们要先规定：

- **到底是 UI 里那份工作流是权威，还是 Git 里的 JSON 是权威？**

建议两种成熟模式（二选一，别混用）：

- **模式 A（推荐生产）**：Git 为权威（GitOps）
  - UI 只用于查看/排障/临时验证
  - 工作流变更必须在 Dev 环境编辑 → 导出入库 → PR → 合并 → 自动发布到 Prod
- **模式 B（团队初期过渡）**：UI 为权威
  - 先允许在 UI 改
  - 但要求“改完必须导出提交 Git”，Git 作为备份/审计

你们“审批+发布”这种关键链路，最终一定要走 **模式 A**。

## 3. 两套落地方案（按是否有 Enterprise 能力划分）

### 3.1 方案 1：n8n Enterprise 的 Source Control & Environments（有证书就用）

特点：

- n8n 内置 Git 连接（push/pull）
- 支持环境概念（不同实例绑定不同分支）
- 支持 **Protected instance**（保护生产环境，防止 UI 直接改）

注意：

- n8n 的 source control **不是完整 Git**，不要假设 PR/merge 都在 n8n 内完成
- 仍建议 GitLab/GitHub 上做评审与合并

适用：

- 你们已经采购/计划采购 Enterprise
- 希望“平台内”有更强的变更管控能力

### 3.2 方案 2：开源可用的 CLI + GitOps（无 Enterprise 也能落地）

核心手段：

- 用 n8n CLI 导出/导入工作流 JSON
- Git 版本化
- CI 校验 + 自动导入到目标环境

n8n 官方 CLI 支持：

- 导出 workflow：`n8n export:workflow`
- 导入 workflow：`n8n import:workflow`

Docker 场景下执行方式（官方推荐形式）：

- `docker exec -u node -it <container> <n8n-cli-command>`

你们的 `n8n-super` 是 Docker 形态，这条路径完全适配。

## 4. 工作流资产化：目录结构与命名规范（建议团队统一）

### 4.1 推荐仓库结构

建议在 Git 仓库中维护：

- `workflows/`
  - `dev/`（开发环境工作流 JSON）
  - `prod/`（生产环境工作流 JSON）
  - 或者按业务域：`workflows/release/`、`workflows/alerts/`、`workflows/ops/`
- `docs/`（说明文档/运行手册/排障）
- `policies/`（可选：lint 规则、节点白名单/黑名单、字段规范）

你们当前仓库里 `n8n-super/workflows/` 已经有示例（自检 workflow）。后续可以把“生产工作流”也按上面方式收敛。

### 4.2 Workflow 命名规范（建议）

把“流程类型 + 场景 + 环境”放进名字里，便于搜索与审计：

- `SRE.Release.AppA.Prod`（发布）
- `SRE.Alert.N9E.DedupeRouter`（告警归并路由）
- `SRE.Bootstrap.OSInit.Batch`（装机初始化）

### 4.3 Tag 规范（强烈建议在 workflow 上打 Tag）

推荐至少包含：

- `owner:<team>` / `owner:<person>`
- `service:<svc>`
- `env:dev|staging|prod`
- `risk:low|medium|high`
- `runbook:<url>`（或 `runbook:xxx`）

Tag 是后续做“监控统计、失败聚合、权限治理”的基础。

## 5. 可追溯：每个 workflow 必须“自带 TraceId/RunId”

### 5.1 统一字段（建议标准化）

每次执行建议至少生成并贯穿：

- `runId`：全链路唯一 ID（建议：`timestamp + 业务关键字段`）
- `ticketId`：审批单/工单 ID（钉钉/工单系统）
- `service` / `env`
- `operator`：触发人（或触发系统）

### 5.2 在执行记录里落“自定义执行数据”（推荐）

n8n 支持在执行过程中写入自定义执行数据（Custom execution data），用于把关键字段写入 execution 证据链。

建议在工作流的最开始，用一个 `Code (JS)` 节点写入：

- `runId`
- `ticketId`
- `service/env`
- 关键外部链接（MR 链接、Jenkins 构建链接、Argo App 链接）

后续排障时，你可以通过 execution 直接找到这些字段。

### 5.3 通知与回写必须带 execution 关联信息

无论成功还是失败，通知/回填建议带：

- `runId`
- 关键外部链接（MR、Jenkins、Argo）
- n8n executionId（或可点击的 execution 链接，若你们有统一入口域名）

## 6. 可发布：导出/导入工作流（CLI 规范化）

### 6.1 导出（建议 `--separate` / `--backup`）

为了让 workflow 像代码一样管理，推荐 **一 workflow 一个 JSON 文件**。

- `--separate`：拆分成多个文件
- `--backup`：等价于 `--all --pretty --separate`，适合备份/入库

> 注意：导出的 workflow JSON 会包含 workflow 的 ID。导入时如果目标库里存在相同 ID，会被覆盖。

### 6.2 导入（建议只导入 workflow，不导入凭据）

导入策略建议：

- 仅导入 workflow JSON
- 凭据在目标环境预置（Credentials），workflow 只引用凭据名

这样可以避免把敏感信息带入 Git。

### 6.3 “启用/禁用”与变更生效

n8n CLI 支持修改 workflow 的 active 状态（例如 `n8n update:workflow`）。

注意：官方说明这类操作是直接改数据库，**n8n 运行中可能需要重启才完全生效**。

工程化建议：

- 发布流程本身尽量减少“改 active”，而是：
  - prod 只发布“已验证的 workflow”，保持 active 稳定
  - 需要紧急止血时，用 disable 作为兜底

## 7. 可评审：CI 校验（Workflow Lint）怎么做

你们可以在 CI 做两类检查：

### 7.1 结构与安全检查（静态）

- JSON 可解析（格式正确）
- 必须包含 Tag（owner/env/risk）
- 禁用或审核高危节点（例如 `Execute Command`）
- 不允许出现疑似敏感信息（token、password、Authorization header）

### 7.2 工程一致性检查（规范）

- 是否包含“Init/Meta”节点（生成 runId、写入 custom execution data）
- 是否包含统一的错误分支（失败通知、回写）
- 是否包含超时/重试策略

> 这部分最适合你们 SRE 团队做成统一规范：把“好的流程模板”标准化。

## 8. 可回滚：两级回滚策略

### 8.1 Workflow 回滚（业务级）

- 回滚到 Git 上一个 tag/commit
- 重新导入 workflow
- 必要时先 `disable` 当前 workflow（止血）

### 8.2 平台回滚（系统级）

- `n8n-super` 镜像按 tag 发布（`<n8nVersion>-rN`）
- 回滚只需要把部署侧镜像 tag 改回旧版本并重建

> 两者要分开：工作流回滚解决“流程逻辑错误”，镜像回滚解决“平台能力变更导致的问题”。

## 9. 可审计：执行数据保留与清理（生产必须配置）

你们需要在“可追溯”和“存储成本”之间取平衡。

建议在生产环境明确：

- 成功执行保留多少
- 失败执行保留多少
- 执行数据是否自动清理（prune）

n8n 支持通过环境变量配置执行数据保留与清理（例如开启 prune、最大保留时间等）。

工程建议（示例策略）：

- 成功执行：只保留必要信息（或不保留详细数据）
- 失败执行：保留全部（便于排障）
- 保留 7 天或 14 天（按你们审计要求）
- 上限条数控制（避免 DB 膨胀）

## 10. 凭据与变量：怎么做到“像代码一样”，但不泄露敏感信息

### 10.1 结论：尽量不要把凭据提交 Git

除非你们有非常明确的安全方案（加密、密钥托管、审计），否则不建议把 credentials 导出到 Git。

### 10.2 可选方案（按企业成熟度从低到高）

- **方案 A（最常见）**：各环境手工/一次性初始化 Credentials
  - Git 里只管理 workflow
- **方案 B（凭据覆盖/外部注入）**：通过文件/接口覆盖 credential 数据
  - 适合多实例/queue 模式，需要考虑同步
- **方案 C（External Secrets，Enterprise）**：对接 Vault/ASM/KeyVault 等
  - workflow 中用表达式引用 secret

无论哪种方案，都应做到：

- workflow JSON 不出现明文 token
- 权限最小化（GitLab/Jenkins/Argo/钉钉各自用专用账号）

## 11. 推荐的团队运行方式（落地到你们的组织协作）

### 11.1 三套环境（强烈建议）

- Dev：允许快速迭代与试错
- Staging：模拟生产验证（含真实权限的“最小子集”）
- Prod：只允许发布，不允许直接在 UI 修改

### 11.2 发布流程（建议）

- 在 Dev 里改 workflow → 导出为 JSON → 提交 PR
- CI 校验通过 → 合并到主分支
- CD 自动导入到 Staging → 自动跑验证 workflow
- 人工确认 → promote 到 Prod（导入/启用）

## 12. 最小可行落地清单（你们可以按这个推进）

- **[规范]** 统一命名与 Tag（owner/env/risk/runbook）
- **[模板]** 统一 Init 节点：runId + custom execution data
- **[Git]** 建一个 workflow 仓库（或在现有仓库新增 `workflows/`）
- **[导出]** 定义导出路径与频率（至少每次变更后导出）
- **[CI]** 加静态检查（JSON、敏感信息、禁用节点）
- **[发布]** 定义导入到 Staging/Prod 的机制
- **[审计]** 配置执行数据保留与 prune
- **[回滚]** 约定 rollback 流程（workflow 回滚 + 镜像回滚）

---

如果你希望我把上述方案进一步“落地成脚本/流水线”（例如：新增 `export/import` 脚本、GitLab CI 模板、节点黑名单校验脚本），我可以在 `n8n-super/scripts/` 和 `windows/` 同步补齐一套可直接用的实现。
