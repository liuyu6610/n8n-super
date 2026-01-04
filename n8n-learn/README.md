# n8n 入门（通用版）：先把全网常用玩法讲清楚，再讲我们怎么用

这份文档会先用“互联网通用视角”把 n8n 的真实常用方案讲清楚（包括 AI/Agent/RAG 等当下最常见的玩法），然后再落到我们团队的内网约束与 `n8n-super` 的落地方式。

官方资料：

- [n8n 官方文档](https://docs.n8n.io/)
- [n8n 模板库（Workflows）](https://n8n.io/workflows/)
- [n8n Integrations（官方集成目录）](https://n8n.io/integrations/)
- [n8n 官方仓库（GitHub）](https://github.com/n8n-io/n8n)

本仓库相关：

- [n8n-super 运维说明](./03-n8n-super-ops.md)
- [周二宣讲材料：审批发布改造蓝图](./02-team-meeting.md)
- [Workflow-as-Code：工作流像代码一样维护](./04-workflow-as-code.md)

---

## 0. 先把 n8n 跑起来（官方 Quick Start）

你如果是第一次接触 n8n，建议先按官方方式跑一个本地实例，把 UI 跑起来再开始学概念。

### 0.1 方式 A：npx（最快，适合本地体验）

前置：需要安装 Node.js。

```bash
npx n8n
```

### 0.2 方式 B：Docker（更接近真实自托管）

```bash
docker volume create n8n_data
docker run -it --rm --name n8n -p 5678:5678 \
  -v n8n_data:/home/node/.n8n \
  docker.n8n.io/n8nio/n8n
```

然后在浏览器打开：`http://localhost:5678`。

> 我们团队落地会优先使用 `n8n-super`（更适合企业内网），但**学习阶段**建议先按官方方式跑起来，认清基本界面与概念。

## 1. n8n 到底是什么（按互联网主流说法）

**n8n 是一个“工作流自动化 / 集成编排平台（workflow automation）”。**

官方仓库 README 的表述（翻译+归纳）：

- 给技术团队的“安全工作流自动化平台”（Secure Workflow Automation for Technical Teams）
- “既有代码的灵活性，又有无代码的速度”（flexibility of code + speed of no-code）
- 400+ 集成、原生 AI 能力（AI-native）、可自托管或使用云版本，并强调数据与部署可控
- 许可协议为 fair-code（Sustainable Use License / Enterprise License）

你可以把它理解成：

- **触发器（Trigger）**：什么时候开始
- **动作（Action）**：要做什么（HTTP/DB/消息/文件/脚本等）
- **控制流（Control Flow）**：条件、循环、等待、错误分支
- **执行记录（Execution）**：每次运行的全链路输入/输出与耗时

互联网里大家用 n8n 的核心原因通常不是“低代码很爽”，而是：

- **连接很多系统**：官方集成 + 社区节点 + HTTP 通用能力（可连接几乎任何 API）
- **迭代快**：画节点就能改流程，不用每次写服务发布
- **更像产品级平台**：有凭据管理、执行记录、错误处理、权限控制（取决于版本/部署形态）

### 1.1 节点生态与可定制化（为什么 n8n 的“连接能力”很强）

n8n 的核心不是“某几个节点”，而是它的 **节点生态 + 可扩展机制**。

- **官方集成（Integrations）**：
  - 官方仓库 README 提到 n8n 提供 **400+ integrations**（见 [n8n 官方仓库（GitHub）](https://github.com/n8n-io/n8n)）。
  - 官方 Integrations 目录会动态更新并展示当前集成数量，例如页面展示为 **1313 integrations**（见 [n8n Integrations（官方集成目录）](https://n8n.io/integrations/)）。
  - 实践理解：这类节点一般把某个系统的 API 做成“可配置的动作”，你只需要填参数和凭据。
- **核心节点（Core Nodes）**：
  - `Set` / `Merge` / `IF` / `Switch` / `Wait` / `Split in Batches` / `Error Trigger` 等，属于“通用编排能力”，负责数据加工与控制流。
  - 实践理解：这些节点更像“语言特性”，决定你的 workflow 是否可维护。
- **社区节点（Community Nodes）**：
  - 社区节点是基于 npm 的扩展包，自托管实例可以通过 UI 或命令行安装（见 [Install and manage community nodes](https://docs.n8n.io/integrations/community-nodes/installation/)）。
  - 是否允许加载/安装社区节点由环境变量控制：`N8N_COMMUNITY_PACKAGES_ENABLED`（见 [Nodes environment variables](https://docs.n8n.io/hosting/configuration/environment-variables/nodes/)）。
  - 手工安装参考（适合 queue 模式/私有包等场景）：[Manually install community nodes from npm](https://docs.n8n.io/integrations/community-nodes/installation/manual-install/).
- **没有专用节点也能接入任何系统**：
  - `HTTP Request` 本质就是“通用连接器”：只要目标系统提供 HTTP API（REST/JSON 等），就能接入。
  - 实践理解：先用 `HTTP Request` 把流程跑通，再决定要不要“沉淀成社区节点/自研节点”。
- **`Code` 节点（JavaScript）增强可编程性**：
  - `Code` 节点可以写 JS 做复杂转换/聚合/校验。
  - 出于安全原因，默认不能随意 `import` 外部 npm 模块；如果确实需要，可通过环境变量 `NODE_FUNCTION_ALLOW_EXTERNAL` 控制允许的模块列表（见 [Enable modules in Code node](https://docs.n8n.io/hosting/configuration/configuration-examples/modules-in-code-node)）。
- **自研节点（企业内网/私有系统的最佳长期方案）**：
  - n8n 提供官方“创建自定义节点”的文档入口（见 [Creating nodes](https://docs.n8n.io/integrations/creating-nodes/overview/)）。
  - 官方也提供 starter 项目便于快速开始（见 [n8n-nodes-starter](https://github.com/n8n-io/n8n-nodes-starter)）。
  - 实践理解：当某个内部系统要长期复用（统一鉴权、统一错误处理、统一参数模板），自研节点比“到处复制 HTTP Request 节点”更可维护。

风险提醒（强烈建议团队统一口径）：

- 供应链风险：社区节点/外部 npm 模块本质是第三方代码，建议白名单、固定版本、按需审计。
- 生产治理：能用 Credentials 管的不要写死在节点参数里；启用高风险能力（如外部模块、命令执行）要有最小权限与审计。

---

## 2. 全网最常见的 n8n 使用场景全景图（你在网上看到的大多在这里）

### 2.1 系统集成 / 数据同步（最主流）

典型流：

- `Schedule Trigger` / `Webhook Trigger`
- 拉数据（CRM/工单/表格/数据库/接口）
- 清洗/转换（`Set` / `Code (JS)` / `Merge` / `Split in Batches`）
- 写回（表格/数据库/Notion/工单/消息）

常见例子（模板库里非常多）：

- CRM → 邮件/Slack 跟进
- 表格 → 数据库 / 报表
- 工单系统 → 通知 → 回写状态

### 2.2 通知与运营自动化

- 告警事件 → 组装消息 → 发到 Slack/飞书/钉钉/邮件
- 每日/每周 Digest（日报/周报/摘要）
- 新线索/新表单 → 自动分配 → 通知

### 2.3 审批/人机协作（Human-in-the-loop）

互联网里常见“AI + 人审”或者“自动化 + 人确认”的通用拓扑：

- 触发（Webhook/定时）
- 自动预处理（校验、提取字段、查上下文）
- 发起审批（Slack/邮件/钉钉/表单）
- **等待**审批结果（`Wait` / 轮询 / 回调）
- 继续执行（发布/写库/发通知）

### 2.4 AI 自动化（当下最常见的增量玩法）

你提到“正常使用更多的是 AI 的加入”，确实如此：近两年 n8n 的公开模板里，AI 相关占比非常高，常见范式主要是下面三类。

#### 2.4.1 LLM 辅助内容处理（总结/分类/生成）

- 邮件/工单/IM 消息 → 摘要 → 结构化输出（JSON）
- 文本分类/打标签（紧急程度、主题）
- 自动草拟回复（先 Draft，再人工确认发送）

#### 2.4.2 AI Agent 调用工具（Tool-using Agent）

常见组合是：

- Chat 入口（Chat Trigger 或者 IM 入口）
- AI Agent（可调用“工具”）
- 工具包括：HTTP 请求、数据库查询、搜索、创建工单、发消息等

这种玩法的关键不是“聊天”，而是 **Agent 具备执行能力**，能在你允许的边界内完成多步操作。

#### 2.4.3 RAG（知识库问答 / 内部文档机器人）

公开资料里最常见的 RAG 拓扑是：

- **离线/定时 Ingestion**
  - 文档源（Drive/Confluence/网页/API）
  - 分片（chunk）
  - Embedding
  - 写入向量库（Pinecone/Qdrant/Weaviate/Supabase 等）
- **在线 Query**
  - Chat Trigger
  - 检索相关片段
  - LLM 生成回答（带引用/上下文）

#### 2.4.4 更细的落地模式（从“辅助”到“自动执行”逐步升级）

- **模式 A：LLM → 结构化 JSON → 后续自动化（推荐起步，最稳）**
  - 适用：从工单/审批/告警文本里提取字段、生成“机器可读”的输入。
  - 关键：让 LLM 输出固定 JSON（字段名固定、可选值有限），然后用 `IF`/`Code (JS)` 做校验与兜底。
  - 典型拓扑：触发 → 预清洗（`Set`/`Code`）→ LLM 提取（提示词里明确 JSON schema）→ 校验（缺字段/不合法走人工分支）→ 执行动作（写库/调用 API/发通知）。

- **模式 B：LLM 生成草稿 + 人审（Human-in-the-loop）**
  - 适用：公告、发布说明、工单回复、周报/日报等“可以先草拟再确认”的内容。
  - 典型拓扑：触发 → 拉上下文 → LLM 生成 Draft → 发到群/审批 → `Wait` → 人工确认后再发送/写回。

- **模式 C：LLM 分类/路由（Routing）**
  - 适用：告警分流、工单分派、决定走哪条自动化分支。
  - 典型拓扑：触发 → LLM 分类（返回 label）→ `Switch`/`IF` 路由到不同分支。

- **模式 D：Agent + 工具（Tool-using Agent，强能力但要强治理）**
  - 适用：需要多步查询/写入的复杂任务（例如“查某应用近期发布 + 生成变更摘要 + 创建工单”）。
  - 推荐做法：
    - 工具清单必须最小化（只给必须的 API）。
    - 对“有副作用”的工具（发布/回滚/改配置/删资源）前加审批闸门（先发摘要，人工确认后再执行）。
    - 每次执行产出可审计的 action log（写到工单/消息/数据库），避免“黑盒执行”。

#### 2.4.5 风险点与治理建议（生产环境必看）

- **数据泄露/合规**：不要把密钥、token、个人信息、业务敏感字段直接送进模型；必要时先脱敏；优先走内网模型/网关；明确数据留存与审计口径。
- **Prompt Injection（提示词注入）**：RAG 场景里“文档内容”本质是外部输入，可能夹带恶意指令；提示词里要明确“把检索内容当作资料，不当作指令”；对工具调用加 allowlist。
- **幻觉与不确定性**：LLM 输出必须校验；关键决策不要只依赖 LLM；对自动化动作加幂等、回滚、错误分支（Error Workflow）。
- **成本/延迟/限流**：用 `Split in Batches` 控并发；对相同输入做缓存/去重；重试要带指数退避；对外部接口错误要分级处理。
- **权限与审计**：Agent/自动执行必须使用最小权限 Credentials；把“输入、模型输出、关键决策、执行结果”记录到可追溯载体（工单/日志/表）。

#### 2.4.6 我们团队内网场景的推荐用法（可落地清单）

- **调用方式**：优先用 `HTTP Request` 调用内网 LLM 网关/自建模型服务（即使是 OpenAI-compatible 协议也一样），避免节点里直连公网。
- **推荐起步 3 个场景**：
  - **审批文本结构化**：钉钉审批 → 提取应用/环境/版本/窗口 → 规则校验 → 输出“发布计划摘要”给审批人确认。
  - **发布过程总结**：拉 Jenkins/GitLab/ArgoCD 日志/状态 → LLM 总结失败原因/关键链接 → 发到群里辅助排障（不直接触发变更）。
  - **运维知识问答（RAG）**：把 runbook/OPS 文档定时入库 → Chat 问答 → 返回引用片段；按团队/系统做索引隔离。
- **强约束**：任何“会改线上状态”的动作（发布/回滚/执行命令/改配置）都必须经过人审或二次确认。

---

## 3. 你必须真正理解的 n8n 运行机制（否则你会觉得“画完也不靠谱”）

### 3.1 数据流：Items / JSON / Binary

- n8n 节点之间传递的是 **一组 items**
- 每个 item 里通常是 `json`（也可以带二进制文件 binary）
- 你写表达式经常用 `{{$json.xxx}}` 取字段

### 3.2 Expressions（表达式）与“把上游输出喂给下游”

- 节点参数里可以写表达式引用上游输出
- 能力很强，但也容易写出“读不懂的工作流”
- 建议：关键节点前用 `Set` 把字段标准化

### 3.3 Credentials（凭据）

- **不要把 token/密码写进节点参数/JSON**
- 用 Credentials 统一托管
- 需要跨环境时，建议配合 Workflow-as-Code 的凭据策略

### 3.4 Execution（执行记录）就是你的“黑盒观测窗口”

- 每次执行会记录每个节点的输入/输出
- 排障的核心路径：

1. 看哪个节点报错
2. 看它的输入是不是符合预期
3. 看外部系统返回什么

### 3.5 Webhook vs Polling：互联网常见的两条路

- **Webhook**：实时、低延迟、效率高，但要求外部系统能打到 n8n
- **Polling（轮询）**：定时去查外部系统的“新增/变更”，适合网络隔离/无 webhook 的系统

轮询不是“低级”，在企业网络里非常常见；关键在于：

- 幂等去重
- 轮询窗口与分页
- 降低外部 API 压力（频率/批量/缓存）

---

## 4. 全网最常见的 6 种工作流拓扑模板（照着套就能做出 80% 自动化）

### 4.1 定时同步（Schedule → ETL → 落库/表格/通知）

- `Schedule Trigger`
- `HTTP Request` / DB 节点 拉取
- `Code (JS)` 清洗
- DB/表格/Notion 写入
- 通知

### 4.2 事件驱动（Webhook → 校验 → 执行 → 回写）

- `Webhook Trigger`
- 校验签名/鉴权
- 解析 payload
- 调用下游系统
- `Respond to Webhook` 返回结果

### 4.3 轮询触发（Schedule → Query list → 去重 → 执行）

- `Schedule Trigger`
- `HTTP Request` 查询待处理列表
- 去重（按 id / 时间窗口 / 状态机）
- 执行动作

### 4.4 批处理（分页/分批执行，避免一把梭）

- `Split in Batches` 分批
- 每批执行
- 失败重试/错误分支

### 4.5 人工确认（自动处理 + 发审批 + 等结果）

- 自动预处理
- 发审批（IM/邮件/表单）
- `Wait` 或“轮询审批状态”
- 继续执行 / 回滚

### 4.6 AI 加持（LLM 总结/分类/生成 + 人审）

- 触发（新邮件/新工单/新表单）
- LLM 总结/分类
- 生成草稿
- 人审（审批或手工确认）
- 发送/写回

---

## 5. 你要把 workflow 做到“可长期维护”，必须补齐这些工程化要点

### 5.1 输入契约（Input Contract）

- 必填字段
- 字段命名规范
- 字段类型与默认值
- 开头用 `Set`/`Code (JS)` 做标准化

### 5.2 幂等与去重（轮询/重试/手工重跑都会触发它）

- 给每次业务执行生成 `runId`
- 先查状态，再执行动作（避免重复创建/重复发布）
- 输出明确的“已处理/跳过”日志

### 5.3 错误处理（互联网里最常见的两种模式）

- **节点级错误分支**：对可预期失败用 “Continue (using error output)” 分叉
- **全局错误兜底**：用 `Error Trigger` 单独做“报警与收敛”

同时建议：

- 配置重试（Max Tries / Wait）
- 失败时记录：workflowId、executionId、错误信息、输入摘要、外部系统响应

### 5.4 安全与权限（越像平台，越要管住）

- Credentials 最小权限
- 不把敏感信息写到 workflow 节点参数/日志
- 对 `Execute Command` 类能力保持高警惕（生产慎用，必须有审计/隔离）

---

## 6. 模板库与导入导出：最快的学习路线（官方模板 + Zie619 大库 + CLI）

你几乎不需要从 0 “凭空画”一个复杂工作流。互联网里更主流的做法是：

- **找模板**：先找一个最接近的 workflow
- **导入跑通**：先让它在你的环境里能执行（哪怕先用 mock 数据）
- **替换成你的输入/输出契约**：用 `Set`/`Code` 在入口统一字段
- **替换凭据与环境参数**：把 token/base_url/项目名等改成你的
- **补齐工程化能力**：幂等、错误分支、告警、审计

### 6.1 官方模板库（n8n.io/workflows + UI 内置 Templates）

- 入口：
  - [n8n 模板库（Workflows）](https://n8n.io/workflows/)
- 特点：
  - 质量相对稳定，适合做“标准答案”参考
  - 覆盖大量 AI/Agent/RAG 示例，适合直接照着搭骨架
- 推荐学习顺序（零基础）：
  - 先从你熟悉的系统入手（例如 HTTP API / GitLab / IM）
  - 优先学会 `HTTP Request`、`Set`、`Merge`、`Split in Batches`
  - 再学 `IF`、错误分支、重试、`Wait`

### 6.2 Zie619/n8n-workflows（超大工作流集合）

这是目前社区里规模非常大的 workflow 集合之一（按其 README 统计）：

- **仓库**：[Zie619/n8n-workflows](https://github.com/Zie619/n8n-workflows)
- **在线浏览（支持搜索与直接下载 JSON）**：[zie619.github.io/n8n-workflows](https://zie619.github.io/n8n-workflows)
- **规模**：
  - 4,343 workflows
  - 365 integrations
  - 15 categories

它的工作流文件主要在：

- `workflows/<Integration>/xxxx_*.json`（按集成/应用维度组织）

推荐用法：

1. 在网页里按关键词搜索（系统名、节点名、触发方式）
2. 下载 JSON
3. 在你的 n8n 里导入
4. 按需替换/安装缺失节点（尤其是社区节点）
5. 重新绑定 Credentials 并跑通执行记录

### 6.3 导入模板后的“必做检查清单”（不做就容易踩坑）

- **触发器是否符合网络现实**：
  - 外网能打进来：Webhook
  - 外网打不进来：Schedule + Polling（我们团队更常见）
- **Credentials 是否已经重绑**：
  - 模板通常只包含“凭据引用”，不包含真实密钥
- **环境参数是否抽象成变量**：
  - base_url、project、namespace、token 等建议集中在开头 `Set`
- **幂等/去重是否补齐**：
  - 尤其是轮询和重试场景
- **错误处理是否明确**：
  - 节点级错误分支 + 全局告警
- **节点可用性**：
  - 缺失社区节点时，需要安装对应包或替换为通用 HTTP 实现

### 6.4 UI 导入/导出（零基础必会）

#### 6.4.1 导出（Download JSON）

- 打开某个 workflow
- 右上角三点菜单（...）
- 选择 `Download`，得到一个 workflow JSON 文件

#### 6.4.2 导入（Import from File / Paste JSON）

- 在画布/工作流菜单中选择 `Import from File`
- 选择本地 JSON 文件导入
- 或使用 `Paste JSON` 直接粘贴

小技巧：

- 复制/粘贴节点：可以把某个 workflow 的部分节点复制到另一个 workflow 里复用
- 导入后先在“未激活”状态下用测试数据跑通，再激活

### 6.5 CLI 导入/导出（自托管/容器场景：备份、迁移、Git 化）

适合：

- 批量备份（全量 workflows / credentials）
- 环境迁移（dev → prod）
- Workflow-as-Code（导出到 Git 做 diff/review）

在容器里执行 CLI（示例）：

```bash
docker exec -u node -it <n8n-container-name> n8n --help
```

#### 6.5.1 导出 workflows（推荐分文件，方便 git diff）

```bash
docker exec -u node -it <n8n-container-name> n8n export:workflow --backup --output=/home/node/.n8n/backups/workflows
```

说明：

- `--backup` 会启用适合备份的参数组合（等价于 `--all --pretty --separate`）
- `--separate` 会把每个 workflow 单独导出为一个 JSON 文件（更适合版本管理）
- `--output` 对于 `--separate` 来说应为目录路径；不加 `--separate` 时则是输出文件路径

导入：

```bash
docker exec -u node -it <n8n-container-name> n8n import:workflow --separate --input=/home/node/.n8n/backups/workflows
```

#### 6.5.2 导出 credentials（高敏感：谨慎使用）

加密导出（默认）：

```bash
docker exec -u node -it <n8n-container-name> n8n export:credentials --backup --output=/home/node/.n8n/backups/credentials
```

明文导出（`--decrypted`）：

```bash
docker exec -u node -it <n8n-container-name> n8n export:credentials --all --decrypted --output=/home/node/.n8n/backups/credentials-decrypted.json
```

注意：

- **明文凭据等同于密钥泄露**：禁止提交 Git，建议只在受控环境临时使用，并配合加密存储与访问审计。
- 不同版本对 “分文件 + 明文导出 + 导入” 的兼容性存在历史差异；做迁移前请先在测试环境演练。

---

## 7. 从 0 到 1：如何编写并上线一个可维护的 workflow（详细教程）

这一节会用“通用流程骨架”的方式，从 0 带你走一遍：

- **怎么拆需求**（写清输入/输出/边界）
- **怎么画工作流**（先跑通，再工程化）
- **怎么调试**（Execution、Pin Data、最小复现）
- **怎么上线**（激活、监控、回滚）

你可以把它当成一个可复制的模板：换掉外部系统与字段，就能落到你自己的场景。

### 7.1 开始之前：先写一份“流程规格说明”（不然你会越画越乱）

在拖节点之前，建议先写一段规格说明（1-2 页足够）。最常用的结构是：

- **业务目标**：这条自动化要解决什么问题？成功判定标准是什么？
- **触发方式**：Webhook / Schedule / Manual / 外部消息？为什么选它？
- **输入契约（Input Contract）**：需要哪些字段？类型是什么？缺字段怎么处理？
- **输出/副作用**：要写哪些系统？会产生哪些副作用（建工单、发布、发消息）？
- **幂等与去重策略**：用什么字段作为 idempotency key？重复触发会怎样？
- **失败策略**：哪些错误可重试？哪些需要人工介入？
- **权限与凭据**：需要哪些 token？怎么做最小权限？
- **可观测性**：失败通知发到哪里？如何定位到具体请求/节点？
- **频率与成本**：轮询频率、接口限流、执行时长上限

把这些写清楚，你后面“拖节点”会非常顺。

### 7.2 推荐开发姿势：先用 `Manual Trigger` 把主干跑通

真实项目里最常见的开发方式是：

- 开发阶段：
  - 用 `Manual Trigger` 启动
  - 在入口 `Set` 一份固定输入（或用 Pin Data 固定上游输出）
  - 先跑通“主干路径”
- 上线阶段：
  - 再把 `Manual Trigger` 换成真实触发器（Webhook/Schedule/IM 等）
  - 补齐错误分支、告警、幂等、权限

好处：

- 你可以把问题快速缩小到“某个节点/某段数据”
- 不会被外部系统不稳定、网络波动、权限不足拖慢

### 7.3 一个可维护 workflow 的“通用骨架”（建议固定成团队范式）

大多数可长期维护的工作流，结构都类似：

- **Trigger**：触发器（Manual/Webhook/Schedule）
- **Normalize**：入口标准化（`Set`/`Code` 把字段统一成你的契约）
- **Validate**：输入校验（缺字段、类型不对就尽早失败）
- **Enrich**：补充上下文（查 DB/接口，合并更多字段）
- **Do**：执行核心动作（发布/写库/创建工单）
- **Notify**：结果通知（成功/失败/部分成功）
- **Observe**：关键节点输出可读字段（`runId`、`app`、`env`）便于排障

你在模板库里看到的复杂工作流，通常也是这个骨架不断“加分支/加循环/加子流程”演化出来的。

### 7.4 入口标准化：用 `Set` 把输入变成稳定的 JSON

新手最容易踩的坑是：

- 上游字段名一会叫 `app`，一会叫 `application`
- 上游返回结构改了，下游一片红
- 每个节点都在写表达式取字段，越改越难维护

推荐做法：

- 在 workflow 开头用 `Set` 统一字段命名、默认值
- 能用 `Set` 就少用 `Code`（`Set` 更可视化、更容易 review）
- 入口只对外暴露“你定义的契约”，后面节点只认这一套

示例（输入契约的样子，后续节点只依赖这份 JSON）：

```json
{
  "runId": "<uuid>",
  "env": "prod",
  "app": "demo-service",
  "namespace": "demo",
  "action": "deploy",
  "params": {
    "imageTag": "v1.2.3"
  },
  "requester": {
    "name": "alice",
    "id": "123"
  }
}
```

### 7.5 Expressions（表达式）：你至少要会的 3 种“取字段”方式

- **当前 item**（最常用）：
  - `{{$json["env"]}}`
  - `{{$json["params"]["imageTag"]}}`
- **引用某个上游节点输出**（多分支合流后常用）：
  - `{{$node["Normalize"].json["app"]}}`
- **取某节点的第 N 条 item**（当你明确知道要哪一条）：
  - `{{$items("Query")[0].json["id"]}}`

实操建议：

- 字段名里出现 `-`、`.`、空格时优先用 bracket 形式（`["field"]`）
- 大量表达式会降低可读性：关键字段尽量在 `Set` 集中成“可读变量”

### 7.6 外部系统调用：`HTTP Request` 节点的通用套路

建议你把 `HTTP Request` 当成“万能连接器”：缺少专用节点时，直接用 HTTP 也能把流程跑起来。

常见配置要点：

- **认证方式**：能用 Credentials 就用 Credentials，不要把 token 写到节点参数里
- **参数注入**：Query/Headers/Body 用表达式引用入口契约字段
- **返回解析**：确认 Response format 与接口一致（JSON/文本/二进制）
- **分页与批处理**：列表接口配合 `Split in Batches` 做分批
- **限流与重试**：对 429/5xx 做重试（Max Tries / Wait），必要时配合 `Wait` 退避

### 7.7 处理“列表数据”：Items 模型 + `Split in Batches`

当上游输出是一组 items 时：

- n8n 会对每个 item 执行后续节点（可以理解成隐式 map）
- items 很大时必须控制批次，否则容易超时/打爆外部 API/历史膨胀

推荐模式：

- 列表查询 → `Split in Batches`（例如每批 50）→ 批内处理 → 合并结果/通知

### 7.8 控制流：`IF` / `Switch` / `Merge` / `Wait`

- **`IF`**：二选一分支
- **`Switch`**：多分支（按状态码/类型/环境分流）
- **`Merge`**：把分支结果合并（注意 items 对齐）
- **`Wait`**：等待外部事件或人工确认（也可用轮询实现）

> 我们团队内网场景里，“外部回调直达”经常不可行，所以 `Schedule Trigger` + 轮询会更常见。

### 7.9 需要写代码时：`Code` 节点（JavaScript）的使用边界

`Code` 节点适合做：

- 复杂转换（`Set`/表达式写不动的）
- 聚合/拆分 items
- 自定义校验/格式化

你需要知道两件事：

- **Run Once for All Items**：默认模式，代码只跑一次，输入是一组 items
- **Run Once for Each Item**：每个 item 跑一次，更像 map

经验：

- 能用 `Set` 做的别用 `Code`
- 需要单元测试/复杂依赖/高风险操作的，尽量下沉成独立服务/脚本，再由 n8n 调用

### 7.10 调试与排障：Execution 是你的第一现场

建议按固定顺序排障：

1. 在 Executions 里定位失败节点
2. 看失败节点的输入是不是你以为的结构（大量问题在这里）
3. 看外部系统响应（状态码、错误字段、限流信息）
4. 最小化复现：用 `Manual Trigger` + 固定输入只跑到失败节点
5. 修复后再跑全链路

常见好用技巧：

- Pin Data 固定输入，避免每次都重新拉外部数据
- 在关键节点输出可读字段（`runId`、`app`、`env`、`action`）

### 7.11 上线前 Checklist（建议照着打钩）

- **触发器**：是否符合网络现实（Webhook 还是 Polling）
- **输入契约**：入口是否已经标准化且有校验
- **幂等/去重**：重复触发是否安全
- **错误处理**：节点级错误分支 + 全局告警是否具备
- **凭据**：最小权限、是否支持环境隔离
- **可观测性**：失败能否定位到哪个系统/哪个请求
- **数据与历史**：执行历史是否会无限增长（需要配置保留策略）
- **回滚**：关键动作是否可回滚/可重试/可人工接管

### 7.12 复用与模块化：把“大工作流”拆成“可复用组件”

当 workflow 变复杂后，建议逐步演进：

- 把通用子能力抽成子 workflow（例如：参数校验、通知、回滚）
- 用 `Execute Workflow`（或等价能力）复用
- 把 workflow JSON 导出到 Git 做 review

这部分的工程化方案详见：

- [Workflow-as-Code：工作流像代码一样维护](./04-workflow-as-code.md)

---

## 8. 部署与扩展：为什么很多公司最后会走 Queue 模式

通用认知（不绑定我们团队）：

- 单实例简单，但并发能力有限
- 业务多、执行多、历史多 → 通常要：
  - 队列（Redis）
  - Web/Worker 分离并水平扩容

---

## 9. 回到我们团队：为什么我们文档看起来和“互联网玩法”不一样

你看到的差异，本质来自两点：

- **网络与安全边界不同**：很多公开模板默认能被外网 webhook 打到，企业内网经常做不到
- **运维可控性要求更高**：我们需要可复现、可审计、可回滚

### 9.1 我们的推荐落地：n8n-super

- 解决企业内网工具链缺失
- 解决多人共用时 Python 依赖冲突（按依赖 hash 的 venv 缓存隔离）
- 解决社区节点“装了但 UI 看不到”（volume 覆盖 + 启动同步）

详见：

- [n8n-super 运维说明](./03-n8n-super-ops.md)

### 9.2 我们的第一个重点流程：审批发布（受网络限制时用轮询触发）

- 钉钉/外部系统回调无法直达内网 n8n → 优先用 `Schedule Trigger` 轮询审批结果
- 如果未来要实时：再评估 DMZ/网关转发方案

详见：

- [周二宣讲材料：审批发布改造蓝图](./02-team-meeting.md)

### 9.3 工作流像代码一样维护

- 把 workflow 导出到 Git
- 做 diff、review、回滚
- 结合 CI 做 lint/校验

详见：

- [Workflow-as-Code：工作流像代码一样维护](./04-workflow-as-code.md)
