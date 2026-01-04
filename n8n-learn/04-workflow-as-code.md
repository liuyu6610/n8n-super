# Workflow-as-Code：让每个 n8n Workflow“像代码一样”可执行、可追溯、可发布、可回滚

## 1. 目标（SRE 视角的四个“必须”）

你们要的不是“把流程画出来”，而是把流程变成一种 **工程化资产**：

- **可执行**：工作流定义可被自动部署到目标环境
- **可追溯**：每次执行都有证据链（谁触发、输入参数、执行过程、输出、失败点）
- **可评审**：像代码一样走 PR/CR
- **可回滚**：变更出问题可以快速回滚到上一个稳定版本

### 1.1 什么叫 workflow 资产化（你们到底在管理什么）

n8n 的 workflow 在技术实现上是存储在数据库里的“配置 + 状态”。UI 里点保存，本质是在改数据库。

所以 workflow 资产化不是“把流程画得更规范”，而是把它当成**生产资产**来治理，至少要把下面几件事说清楚并落到制度里：

- **资产边界**：哪些东西算 workflow 的一部分（应版本化/可发布），哪些是环境差异或敏感配置（必须分离）。
- **生命周期**：怎么开发、评审、发布、变更、下线、回滚。
- **证据链**：怎么做到审计与可追溯（执行记录、runId、外部系统链接）。
- **责任归属**：owner、风险等级、runbook、权限。

建议把一个“可长期维护”的 workflow 拆成 4 类资产分别治理：

- **Workflow 定义（主资产）**：workflow JSON + 名称 + tags + folder/project + owner。
  - 这部分决定“业务逻辑”，适合进入 Git 做版本化与评审。
- **运行时依赖（平台/节点/镜像）**：n8n 版本、`n8n-super` 镜像 tag、社区节点/自研节点包版本、`Code` 节点允许的外部模块清单等。
  - 这部分决定“同一份 JSON 在目标环境是否能跑起来”。
- **敏感配置（Credentials / Variables）**：token/密码/证书等。
  - 不应进入 Git；不同环境不同值，用外部 secrets 或环境初始化方式解决。
- **运行证据链（Execution 数据）**：每次执行的输入/输出、错误点、runId、外部链接（MR/Jenkins/Argo）等。
  - 这是审计与排障的核心资产，必须可检索、可保留、可清理（prune）。

资产化落地后的“验收标准”可以这样写：

- **可复制**：任何人拿到 Git 里的定义，在 Dev/Staging 能一键导入并跑通（依赖与凭据有明确准备步骤）。
- **可发布**：有明确的“从 Dev 到 Prod”的发布动作（自动导入/启用），而不是“直接在 Prod UI 点保存”。
- **可回滚**：回滚是“回到某个 commit 对应的 workflow 定义（必要时连同平台版本一起回）”，并且有止血手段（disable）。

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

### 3.1 方案 1：n8n Enterprise 的 Source Control & Environments（n8n 内置 Git）

官方资料（建议先读这几页，都是一手说明）：

- [Source control and environments](https://docs.n8n.io/source-control-environments/)
- [Set up source control](https://docs.n8n.io/source-control-environments/setup/)
- [Git and n8n](https://docs.n8n.io/source-control-environments/understand/git/)
- [Push and pull](https://docs.n8n.io/source-control-environments/using/push-pull/)
- [Branch patterns](https://docs.n8n.io/source-control-environments/understand/patterns/)

#### 3.1.1 能解决什么问题（从“导出 JSON”升级成“平台内 GitOps”）

- **平台内直接 Push / Pull**：n8n 在 UI 里直接把 workflow 变更 push 到 Git，再从 Git pull 回实例。
- **把环境概念产品化**：不同 n8n 实例可以绑定不同 Git branch，形成 Dev/Test/Prod 环境链路。
- **保护生产**：支持 **Protected instance**，防止用户在生产实例直接编辑 workflow。

#### 3.1.2 可用性与权限边界（谁能配置、谁能 Push/Pull）

官方说明要点：

- **可用性**：Enterprise 功能。
- **启用/配置权限**：必须是 n8n instance owner 或 instance admin。
- **Pull（从 Git 拉到实例）**：必须是 instance owner 或 instance admin。
- **Push（从实例推到 Git）**：instance owner / instance admin / project admin 都可以。

#### 3.1.3 在哪里配置（UI 路径与认证方式）

配置入口（官方指引）：

- `Settings > Environments` → `Connect`
- 选择连接方式：
  - **SSH**：填写仓库 SSH URL；n8n 会提供 SSH key；用它去 Git 平台创建 deploy key（要求写权限）。
  - **HTTPS**：填写仓库 HTTPS URL；使用 Git 平台的 Personal Access Token（PAT）做认证。
- 在 `Instance settings` 里选择当前实例绑定的 branch
- 可选：
  - 勾选 **Protected instance**（阻止在该实例直接改 workflow，适合 Prod）
  - 给实例设置颜色（在菜单里辅助识别环境）
- `Save settings`

#### 3.1.4 Push / Pull 到底做了什么（n8n commit 什么、覆盖什么）

官方关键结论（非常重要，别靠猜）：

- **Commit 在 n8n 里等价于一次 Push**：在 n8n 中，commit 和 push 同时发生。
- **Push 的是“当前保存版本”，不是“已发布版本”**：你需要在目标环境再单独 publish。
- **Pull 会覆盖本地未推送的更改**：如果本地改了但没 push，pull 时会被覆盖。

n8n 会把下面这些内容写入 Git：

- **Workflows**（可以选择要 push 哪些 workflow）
  - 包括 workflow 的 tags
  - 包括 workflow owner 的 email（用于跨实例映射归属）
- **Credential stubs（凭据存根）**
  - 提交 ID / name / type
  - 其它字段只有在字段是 expression 时才会包含
- **Variable stubs（变量存根）**：提交 ID 与 name
- **Projects**
- **Folders**

Pull 的行为与注意事项：

- Pull 时如果引入了新的变量/凭据存根，n8n 会提示你需要先补齐值才能使用。
- Git 仓库里删除了 workflow/credential/variable/tag 时，本地不会自动删除；pull 后 n8n 会提示是否删除“过期资源”。
- Pull 已发布 workflow 时，n8n 会在拉取过程中临时 unpublish 再 publish，可能导致该 workflow 有几秒钟不可用。
- 跨实例 pull 时，workflow/credential 的 owner 可能会变化：n8n 会尝试按用户 email 或项目名匹配；匹配不到时可能改归属到当前 pull 的人（或创建同名 project）。

#### 3.1.5 冲突与覆盖（它不是完整 Git，必须按规则用）

官方明确：

- n8n 的 source control **不是完整 Git**，不要指望在 n8n 内完成 PR/merge。
- **仍建议在 GitLab/GitHub 上做评审与合并**（PR/MR），把“合并动作”留在 Git 平台。
- n8n 会自动处理 credentials / variables 的 merge 行为，但 **无法检测 workflows 的冲突**。
- 对 workflow 冲突，你需要在 push/pull 时明确选择怎么处理（本地覆盖 Git 或 Git 覆盖本地）。

为了避免数据丢失，官方给的实践建议可以总结成一句话：

- **让 workflow 的流向保持单向**：例如只在 Dev 改 → push 到 Dev branch → 在 Git 平台走 PR 合并到 Prod branch → Prod 实例 pull。
- 不要在同一个实例同时“既 push 又 pull”（官方不推荐）。
- 不要“一把梭 push 全部 workflows”，只 push 需要的那批。
- 谨慎手工编辑 Git 仓库里的这些文件，避免产生不可预期差异。

#### 3.1.6 推荐的分支/实例模式（和你们的 GitLab 流程对齐）

官方推荐的一个安全模式是 **多实例 + 多分支**：

- Dev 实例 ↔ `dev` 分支（只 push）
- Prod 实例 ↔ `prod` 分支（只 pull）
- 通过 Git 平台的 PR/MR 把 `dev` 合并到 `prod`，然后 Prod 实例 pull

优点：多一道 PR 审查闸门，降低误操作进入生产的风险。

#### 3.1.7 团队统一操作模板：每次修改都入库（Dev Push → MR → Prod Pull）

目标：任何人只要按步骤做，就能保证“改动一定入库”、并且不会绕过评审进入生产。

角色建议（最少三类）：

- 开发者：在 Dev 实例编辑 workflow，并 Push 到 Git（需要 instance owner/admin 或 project admin 权限）。
- 审核者：在 Git 平台评审 MR（至少 1 人）。
- 发布者：在 Prod 实例 Pull 并启用（必须 instance owner/admin；Prod 建议开启 Protected instance）。

前置约束（写进团队制度）：

- Prod 实例必须开启 Protected instance：禁止在 Prod UI 直接编辑。
- workflow 变更只允许在 Dev 实例进行；不允许在 Prod 做“临时热修”后再补入库。
- 一个 workflow 同一时间只允许 1 人修改（可以用约定的 Tag/备注做“占用/加锁”）。

每次修改 SOP（建议 5 分钟内完成入库）：

1. 在 Dev 实例完成修改：保存 → 手动执行/最小验证 → 确认 Tags（owner/env/risk/runbook）齐全。
2. 立刻 Push 到 Git（n8n 菜单里的 Push）：
   - 只勾选本次涉及的 workflow（new/modified/deleted），不要全选。
   - 填写 commit message（示例模板见下）。
   - 点击 `Commit and Push`。
3. 在 Git 平台创建 MR：`dev` → `prod`（或你们约定的主干分支）：
   - MR 描述至少包含：变更点、验证方式、风险等级、回滚方案。
4. MR 合并后，发布者在 Prod 实例执行 Pull：
   - n8n 菜单点 Pull（必要时选择 `Pull and override`，以 Git 为准）。
   - 如果提示有新的 credential/variable stubs：先在 Prod 补齐值再启用 workflow。
5. 在 Prod 做上线确认：
   - 检查 workflow 是否处于“启用/发布”状态（Push 的是保存版本，不等于已发布）。
   - 跑一次最小验证（或观察首条执行），确认无误。

提交信息模板（commit message）：

- `feat(workflow): <service> <what> [ticket]`
- `fix(workflow): <service> <what> [ticket]`
- `chore(workflow): <service> <what> [ticket]`

MR 描述模板（建议复制粘贴）：

- 目标/背景：
- 变更点：
- 影响范围：
- 风险评估（risk: low/medium/high）：
- 验证方式：
- 回滚方式：

注意事项：

- 如果你确实需要 Pull（例如共享一个 Dev 实例）：先 Push 你当前改动，再 Pull，避免覆盖丢失。
- n8n 无法检测 workflow 冲突：多人同时改同一 workflow，后 Push 的会覆盖 Git 版本。

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

#### 3.2.1 团队统一操作模板：每次修改都入库（CLI 导出 + Git 提交）

适用：没有 Enterprise，或不启用 Source Control 功能，但仍希望所有 workflow 变更可追溯、可评审、可回滚。

推荐做法：开发仍在 Dev UI；“入库动作”由 CLI 导出到固定目录，然后提交 Git。

1. 在 Dev 实例改完 workflow 并保存，记录 workflow ID。
2. 导出到容器临时目录，再拷贝到本机 Git 仓库（Docker 示例，推荐）：
   - 按 ID 导出（推荐用于每次变更）：
     - `docker exec -u node -it <n8n-container-name> sh -lc "mkdir -p /tmp/n8n-export && n8n export:workflow --id=<ID> --output=/tmp/n8n-export/workflow.json"`
     - `docker cp <n8n-container-name>:/tmp/n8n-export/workflow.json workflows/dev/<workflow>.json`
   - 全量备份（适合定时备份/大版本升级）：
     - `docker exec -u node -it <n8n-container-name> sh -lc "mkdir -p /tmp/n8n-backups/latest && n8n export:workflow --backup --output=/tmp/n8n-backups/latest/"`
     - `docker cp <n8n-container-name>:/tmp/n8n-backups/latest backups/latest`
3. `git add/commit/push`，并走 MR/CR（commit message / MR 模板可复用 3.1.7）。
4. 合并后在目标环境导入（Docker 示例）：
   - 单文件：
     - `docker exec -u node -it <n8n-container-name> sh -lc "mkdir -p /tmp/n8n-import"`
     - `docker cp workflows/prod/<workflow>.json <n8n-container-name>:/tmp/n8n-import/workflow.json`
     - `docker exec -u node -it <n8n-container-name> n8n import:workflow --input=/tmp/n8n-import/workflow.json`
   - 目录（配合 `--backup`/`--separate`）：
     - `docker exec -u node -it <n8n-container-name> sh -lc "mkdir -p /tmp/n8n-import/latest"`
     - `docker cp backups/latest <n8n-container-name>:/tmp/n8n-import/latest`
     - `docker exec -u node -it <n8n-container-name> n8n import:workflow --separate --input=/tmp/n8n-import/latest/`
5. 在目标环境启用并验证（同 3.1.7 的上线确认）。

注意：

- CLI 导出会包含 workflow/credential 的 ID；导入时如果目标库存在相同 ID 可能覆盖，需要提前规划。
- 不要把 credentials 明文导出入库（除非有严格的加密/审计方案）。

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
