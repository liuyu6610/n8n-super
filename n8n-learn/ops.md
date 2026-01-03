# n8n-super：企业 SRE 落地镜像与运维说明（彻底讲清楚）

> 本文是对 `n8n-super/` 目录的“完整解释 + 运维手册”。
>
>- 镜像目标：让 n8n 更适合在企业内网承担 **审批/发布/告警闭环/脚本编排**。
>- 设计原则：**可复现、可运维、可回滚、可审计**。

## 1. n8n-super 解决什么问题

在企业 SRE 场景里，n8n 要落地通常会遇到这类问题：

- n8n 官方镜像本身偏“平台”，缺少你们需要的 **CLI 工具链**（如 `argocd`、`jq`、`git`）
- 你们会在 workflow 里执行 Python/脚本，但多人共用实例时：
  - Python 依赖版本互相覆盖
  - 环境不可复现、不可控
- 社区节点安装后容易受 volume 覆盖影响（容器启动后 UI 看不到节点）

`n8n-super` 的核心价值：把这些“落地坑”前置解决。

## 2. 目录结构与关键文件

- `Dockerfile`
  - 基于 `n8nio/n8n:1.78.1` 增强构建
- `docker-entrypoint-extra.sh`
  - 容器启动入口包装：加载配置 → 同步社区节点 → 最终 `exec /docker-entrypoint.sh`
- `n8n-python3-wrapper.sh`
  - 把 venv 内 `python3` 替换为 wrapper，实现“按依赖 hash 的独立 venv 缓存”
- `docker-compose.yml`
  - 单容器模式（SQLite），适合 PoC/开发/小规模
- `docker-compose-queue.yml`
  - Queue 模式（Postgres + Redis + web/worker/webhook），适合生产
- `config/`
  - `build.env`：构建期 build-arg 配置入口
  - `community-nodes.list`：构建期安装的社区节点清单（建议固定版本）
  - `n8n-super.env`：运行期配置入口（启动时加载）
  - `requirements.txt`：团队 Python 依赖（通过 volume 挂载/或构建期预装）
- `scripts/*.sh` & `windows/*.ps1`
  - 构建/启动/自检脚本（跨平台）
- `workflows/n8n-super-full-test.json`
  - 覆盖性自检工作流（验证社区节点是否可加载）

## 3. 镜像增强点（Dockerfile 做了什么）

### 3.1 系统工具链

镜像构建时安装了常用运维工具（不同基础镜像自动走 `apt-get` 或 `apk`）：

- `bash/curl/git/jq/openssh-client/rsync/tar/unzip/wget`
- `chromium`（配合 Browser 类节点/自动化场景）
- `python3` + venv/pip（支撑 `PythonFunction`/脚本能力）

### 3.2 预装 `argocd` CLI

- `ARGOCD_VERSION` 可通过 `config/build.env` 配置
- 典型用途：在 workflow 中用 `Execute Command` 节点执行 `argocd app sync/wait`

### 3.3 预装社区节点（build-time 固化）

- 默认从 `config/community-nodes.list` 安装（每行一个包，建议固定版本）
- 也可用 build-arg `COMMUNITY_NODES` 覆盖（空格分隔多个包）

> 设计动机：社区节点属于“平台能力”，必须 **可复现**，因此放到镜像构建期。

### 3.4 Python “按依赖 hash 的独立 venv 缓存”（核心设计）

这是 `n8n-super` 最关键的增强点：

- 镜像构建时创建 **基础 venv**：`/opt/n8n-python-venv`
- 基础 venv 内安装 `python-fire` 等基础依赖
- 然后把基础 venv 内的 `python3` 替换为 `n8n-python3-wrapper.sh`
  - 原始解释器重命名为 `python3-real`

运行时：每次执行 `python3`，wrapper 会根据依赖集合计算 hash，并创建/复用独立 venv：

- `N8N_PYTHON_VENV_CACHE_DIR/<hash>`
- 创建 venv 使用 `--system-site-packages` 继承基础 venv 的 site-packages

这样做的好处：

- 不同 workflow 的 Python 依赖互不污染
- 相同依赖集合复用缓存，避免重复下载
- 可控（可清理、可审计、可复现）

## 4. 运行形态：单容器 vs Queue

### 4.1 单容器（`docker-compose.yml`）

适用：开发/PoC/小规模。

- DB：默认 SQLite（在 `/home/node/.n8n`）
- 优点：简单
- 缺点：扩展性有限

### 4.2 Queue 模式（`docker-compose-queue.yml`）

适用：生产/大量 workflow/并发执行。

- `postgres`：存储 workflows/credentials/executions
- `redis`：队列后端
- `n8n-web`：UI/API
- `n8n-worker`：执行器（可水平扩容）
- `n8n-webhook`：可选，将 webhook 接收与 web 分离

> 你们的审批发布、告警闭环、批量脚本编排，最终都建议落在 Queue 模式。

## 5. 三个“统一配置入口”（团队只改这三处即可）

### 5.1 构建期：`config/build.env`

用于传递 Docker build-args：

- `ARGOCD_VERSION`
- `COMMUNITY_NODES`
- `PIP_*`（构建期 pip 源，用于基础 venv 的预装）

### 5.2 运行期：`config/n8n-super.env`

容器启动时由 `docker-entrypoint-extra.sh` 加载（并且 python wrapper 在每次运行时也会尝试加载，保证 `docker exec` 场景一致）。

已包含的关键项：

- `N8N_PIP_INDEX_URL` / `N8N_PIP_TRUSTED_HOST`
- `N8N_PYTHON_AUTO_INSTALL`（默认 `true`）
- `N8N_PYTHON_REQUIREMENTS_FILE`（默认 `/home/node/.n8n/requirements.txt`）
- `N8N_PYTHON_VENV_CACHE_DIR`（默认 `/home/node/.n8n/pyenvs`）

### 5.3 Python 依赖：`config/requirements.txt`

在 compose 里默认挂载到容器：`/home/node/.n8n/requirements.txt`。

你们可以：

- **团队统一依赖**：改这个文件（建议固定版本）
- **工作流临时依赖**：用环境变量 `N8N_PYTHON_PACKAGES`（空格分隔）

> 推荐策略：基础依赖尽量少，把“业务依赖”交给运行时 hash-venv 机制按需安装。

## 6. Python wrapper 机制详解（排障必看）

### 6.1 hash 的输入是什么

wrapper 会把以下信息拼成一个签名并做 sha256：

- requirements 文件内容 hash（文件存在时）
- `N8N_PYTHON_PACKAGES`
- `N8N_PYTHON_PIP_EXTRA_ARGS`
- pip 源相关（`PIP_INDEX_URL`/`PIP_EXTRA_INDEX_URL`/`PIP_TRUSTED_HOST`/`PIP_DEFAULT_TIMEOUT`）

### 6.2 什么时候会触发安装

只有同时满足：

- `N8N_PYTHON_AUTO_INSTALL=true`
- 且 `N8N_PYTHON_REQUIREMENTS_FILE` 或 `N8N_PYTHON_PACKAGES` 非空

否则直接用基础 venv 的真实解释器执行（`python3-real`）。

### 6.3 并发安全

- 同一 hash 的 venv 创建/安装使用 lock 目录互斥（避免并发踩踏）

### 6.4 缓存清理

`docker-entrypoint-extra.sh` 支持启动时按 TTL 清理（可选）：

- `N8N_PYTHON_VENV_CACHE_CLEANUP=true`
- `N8N_PYTHON_VENV_CACHE_TTL_DAYS=30`

注意事项：

- 这是启动时清理，建议在低峰期重启
- TTL 设置不当可能删到正在使用的 venv（虽然概率不高，但要认识风险）

## 7. 社区节点管理（为什么会“安装了但 UI 看不到”）

### 7.1 根因：volume 覆盖

你们在 compose 中通常会把 `/home/node/.n8n` 挂载为 volume 持久化。

- 镜像构建时安装到 `/home/node/.n8n/nodes` 的内容会被 volume 覆盖

### 7.2 n8n-super 的解决方式：启动时同步

`docker-entrypoint-extra.sh` 在启动时：

- 把构建期备份的 `/opt/n8n-super-prebuilt-nodes` 同步到：
  - `/home/node/.n8n/nodes`
  - `/home/node/.n8n/custom`

并使用 marker 文件避免每次重复同步。

### 7.3 兼容性补丁（钉钉节点）

启动脚本里包含一个一次性 patch：

- `n8n-nodes-dingtalk` 节点内部引用的 credential 名称不一致
- 脚本会替换 dist 文件里的 credential name，避免节点加载异常

## 8. 安全提示（生产必须做的事）

### 8.1 `Execute Command` 风险

`docker-compose.yml` 中 `NODES_EXCLUDE: "[]"` 会启用 `Execute Command`。

- 这意味着工作流可以执行任意命令

建议：

- 生产优先走“受控执行器”（Jenkins/AWX/Agent）
- 如果一定要启用：
  - 网络隔离（只允许访问必要内网系统）
  - 账号最小权限
  - 强制审计（执行记录 + 外部日志）

### 8.2 凭据治理

- 不把 token/密码写入 workflow JSON
- 使用 n8n Credentials
- 如具备企业能力可接外部 Secrets（参考 n8n 官方 External Secrets）

## 9. 可观测性与运维

- **健康检查**：`/healthz`（compose 已内置 healthcheck）
- **队列健康检查**：`QUEUE_HEALTH_CHECK_ACTIVE=true`（你们 compose 已开启）
- **Prometheus 指标**：n8n 支持 `/metrics`（官方示例为 `N8N_METRICS=true`）
- **日志**：可通过 n8n 环境变量控制日志级别与输出（建议接入日志平台）

## 10. 常用运维动作

### 10.1 Windows 快速运行

- 构建：`windows/build.ps1`
- 启动：`windows/run.ps1`
- 自检：`windows/test.ps1`

### 10.2 Linux/macOS 快速运行

- 构建：`scripts/build.sh`
- 启动：`scripts/run.sh`
- 自检：`scripts/test.sh`

### 10.3 发版与回滚

推荐 tag 规范：`n8n-super:<n8nVersion>-rN`（只增不减，便于回滚）。

回滚动作：

- 换回旧 tag
- `--force-recreate`（确保容器真正换镜像）

## 11. FAQ / 排障

- **[启动后 UI 看不到社区节点]**
  - 看 `docker logs` 是否有 `[n8n-super] Syncing prebuilt community nodes` 日志
  - 检查 `/home/node/.n8n/nodes` 是否存在 `node_modules/n8n-nodes-xxx`
- **[Python 包安装失败]**
  - 先确认 pip 源：`N8N_PIP_INDEX_URL` / `N8N_PIP_TRUSTED_HOST`
  - 检查 venv 缓存目录权限：`/home/node/.n8n/pyenvs`
- **[venv 缓存太大]**
  - 开启 TTL 清理（启动时）或手工清理过期 hash 目录
- **[Queue 模式 worker 不执行]**
  - 看 redis/postgres 健康状态
  - 检查 `EXECUTIONS_MODE=queue` 与 redis 配置是否一致

---

后续建议：

- **工作流像代码一样维护（Workflow-as-Code）**：见 `../n8n-learn/04-workflow-as-code.md`。
