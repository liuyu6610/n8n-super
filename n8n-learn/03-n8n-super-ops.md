# n8n-super：企业 SRE 落地镜像与运维手册（运维侧唯一入口）

> 本文是对 `n8n-super/` 目录的“完整解释 + 运维手册”。
>
> 本文整合并替代：
>
> - `n8n-learn/ops.md`
> - `n8n-super/OPS.md`
>
> 镜像构建/扩展说明（如何制作你自己的 n8n-super 镜像）见：`../n8n-super/README.md`

## 1. n8n-super 解决什么问题

在企业场景里，n8n 要落地通常会遇到这类问题：

- n8n 官方镜像本身偏“平台”，缺少需要的 **CLI 工具链**（如 `argocd`、`jq`、`git`）
- 在 workflow 里执行 Python/脚本，但多人共用实例时：
  - Python 依赖版本互相覆盖
  - 环境不可复现、不可控
- 社区节点安装后容易受 volume 覆盖影响（容器启动后 UI 看不到节点）

`n8n-super` 的核心价值：把这些“落地坑”前置解决。

在 `n8nio/n8n:1.78.1` 官方镜像基础上，主要增强：

- **Python 节点**：预装社区节点 `n8n-nodes-python`（提供 `PythonFunction` 节点）
- **Python 运行环境**：内置 Python3 + venv（`/opt/n8n-python-venv`），并支持容器启动时按环境变量自动 `pip install`
- **Shell 能力**：通过内置的 **Execute Command（Command）节点** 执行 shell（需解除默认禁用，见下文安全说明）
- **ArgoCD**：预装 `argocd` CLI，可在工作流里用 Execute Command 节点调用
- **Jenkins / GitLab**：n8n 内置节点（无需额外安装）

## 2. 快速开始

### 2.1 Linux/macOS

#### 0) 前置条件

- Docker Engine
- Docker Compose v2（`docker compose version`）

#### 1) 构建镜像

```bash
chmod +x ./scripts/build.sh ./scripts/run.sh ./scripts/test.sh
./scripts/build.sh
```

#### 2) 启动

```bash
./scripts/run.sh
```

#### 3) 健康检查

```bash
curl -fsS http://localhost:5678/healthz
```

#### 4) 验证“Python 自动装包”是否生效

```bash
./scripts/test.sh
docker exec n8n-super python3 -c "import requests; print('requests:', requests.__version__)"
```

#### 5) 打开 Web UI

- `http://localhost:5678/`

### 2.2 Windows PowerShell

#### 1) 构建镜像（Windows）

```powershell
cd d:\job-test\n8n-best\n8n-super
.\windows\build.ps1
```

#### 2) 运行（Windows）

```powershell
.\windows\run.ps1
```

访问：

- Web UI：`http://localhost:5678/`
- 健康检查：`http://localhost:5678/healthz`

#### 3) 验证（Windows）

```powershell
.\windows\test.ps1
```

验证内容包括：

- `/healthz` 可用
- `n8n --version` 输出版本
- `argocd version --client` 可执行
- venv 内 `python-fire` 可导入
- `n8n-nodes-python` 包存在

## 3. 目录结构与关键文件

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

## 4. 镜像增强点（Dockerfile 做了什么）

### 4.1 系统工具链

镜像构建时安装了常用运维工具（不同基础镜像自动走 `apt-get` 或 `apk`）：

- `bash/curl/git/jq/openssh-client/rsync/tar/unzip/wget`
- `chromium`（配合 Browser 类节点/自动化场景）
- `python3` + venv/pip（支撑 `PythonFunction`/脚本能力）

### 4.2 预装 `argocd` CLI

- `ARGOCD_VERSION` 可通过 `config/build.env` 配置
- 典型用途：在 workflow 中用 `Execute Command` 节点执行 `argocd app sync/wait`

### 4.3 预装社区节点（build-time 固化）

- 默认从 `config/community-nodes.list` 安装（每行一个包，建议固定版本）
- 也可用 build-arg `COMMUNITY_NODES` 覆盖（空格分隔多个包）

> 设计动机：社区节点属于“平台能力”，必须 **可复现**，因此放到镜像构建期。

### 4.4 Python “按依赖 hash 的独立 venv 缓存”（核心设计）

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

## 5. 运行形态：单容器 vs Queue

### 5.1 单容器（`docker-compose.yml`）

适用：开发/PoC/小规模。

- DB：默认 SQLite（在 `/home/node/.n8n`）
- 优点：简单
- 缺点：扩展性有限

### 5.2 Queue 模式（`docker-compose-queue.yml`）

适用：生产/大量 workflow/并发执行。

- `postgres`：存储 workflows/credentials/executions
- `redis`：队列后端
- `n8n-web`：UI/API
- `n8n-worker`：执行器（可水平扩容）
- `n8n-webhook`：可选，将 webhook 接收与 web 分离

> 你们的审批发布、告警闭环、批量脚本编排，最终都建议落在 Queue 模式。

## 6. 三个“统一配置入口”（团队只改这三处即可）

### 6.1 构建期：`config/build.env`

用于传递 Docker build-args：

- `ARGOCD_VERSION`
- `COMMUNITY_NODES`
- `PIP_*`（构建期 pip 源，用于基础 venv 的预装）

### 6.2 运行期：`config/n8n-super.env`

容器启动时由 `docker-entrypoint-extra.sh` 加载（并且 python wrapper 在每次运行时也会尝试加载，保证 `docker exec` 场景一致）。

已包含的关键项：

- `N8N_PIP_INDEX_URL` / `N8N_PIP_TRUSTED_HOST`
- `N8N_PYTHON_AUTO_INSTALL`（默认 `true`）
- `N8N_PYTHON_REQUIREMENTS_FILE`（默认 `/home/node/.n8n/requirements.txt`）
- `N8N_PYTHON_VENV_CACHE_DIR`（默认 `/home/node/.n8n/pyenvs`）

### 6.3 Python 依赖：`config/requirements.txt`

在 compose 里默认挂载到容器：`/home/node/.n8n/requirements.txt`。

你们可以：

- **团队统一依赖**：改这个文件（建议固定版本）
- **工作流临时依赖**：用环境变量 `N8N_PYTHON_PACKAGES`（空格分隔）

> 本仓库策略（离线/新手友好）：`config/requirements.txt` 可以维持较大集合，用于减少运行期下载失败。

## 7. 变更/发版逻辑（新增节点/新增 Python 包/新增工具）

### 7.1 核心原则

- **需要重建镜像**：新增/升级 **n8n 社区节点（npm 包）**、新增/升级 **系统工具/CLI**、修改 `Dockerfile`、升级基础镜像/系统依赖。
- **Python 包两种路径**：
  - **固化到镜像（离线/新手友好）**：新增/升级 `config/requirements.txt` 并重新 build 镜像发布新 tag（需要重建）。
  - **仅运行期按需安装（灵活）**：通过 `N8N_PYTHON_PACKAGES` / `N8N_PYTHON_REQUIREMENTS_FILE` + hash-venv 自动安装（通常不需要重建镜像）。

### 7.2 新增/升级 n8n 社区节点（node 节点 / npm 包）= 必须重建镜像

#### 节点安装“定义在哪里”

- **安装定义**：`Dockerfile` 中的 `ARG COMMUNITY_NODES` + `npm install ...`
- **默认来源**：当 `COMMUNITY_NODES` 为空时，从 `config/community-nodes.list` 读取（镜像构建期 COPY 到 `/opt/n8n-super-community-nodes.list`）
- **安装落地目录**：`/home/node/.n8n/nodes/node_modules/<n8n-nodes-xxx>`

#### 推荐方式（团队统一）

1) 编辑 `config/community-nodes.list`，每行一个包（建议固定版本）
2) 构建新镜像 tag（建议 rN 递增，便于回滚）
   - Linux/macOS：
     - `./scripts/build.sh --tag n8n-super:1.78.1-r2`
   - Windows：
     - `.\windows\build.ps1 -Tag "n8n-super:1.78.1-r2"`
3) 让运行端使用新镜像并强制重建容器
   - Linux/macOS：
     - `./scripts/run.sh --force-recreate`
     - Queue：`./scripts/run.sh --queue --force-recreate`
   - Windows：
     - `.\windows\run.ps1 -ForceRecreate`
     - Queue：`.\windows\run.ps1 -Queue -ForceRecreate`

#### 临时方式（一次性覆盖，不改列表）

如果你不想改 `config/community-nodes.list`，可以在 `config/build.env` 里设置：

- `COMMUNITY_NODES="n8n-nodes-python@0.1.4 n8n-nodes-xxx@1.2.3"`

然后走同样的 build + force-recreate。

### 7.3 新增/升级 Python 包（requests/pandas/…）= 不需要重建镜像

#### 运行期安装机制是什么

1) 运行期由 `config/n8n-super.env` 控制：
   - `N8N_PYTHON_AUTO_INSTALL=true`（默认已开启）
   - `N8N_PYTHON_REQUIREMENTS_FILE=/home/node/.n8n/requirements.txt`
2) `n8n-python3-wrapper.sh` 会在每次执行 `python3` 前：
   - 根据 requirements 内容 + packages + pip 源参数计算一个 hash
   - 在 `N8N_PYTHON_VENV_CACHE_DIR` 下创建/复用独立 venv（默认 `/home/node/.n8n/pyenvs/<hash>`）
   - 同一套依赖复用缓存，避免重复下载；不同依赖互不污染

#### 团队统一依赖（推荐）

1) 编辑 `config/requirements.txt`（建议固定版本）
2) 两种生效方式（按你要达到的目标选择）：
   - **固化到镜像（离线/新手友好，推荐）**：重新 build 镜像并发布新 tag，然后 `--force-recreate` 重建容器
   - **仅运行期按需安装（灵活）**：保持 `N8N_PYTHON_AUTO_INSTALL=true`，重启容器后在下次 PythonFunction 执行时会按 hash 自动安装
3) 你也可以主动验证：
   - `docker exec n8n-super python3 -c "import requests; print(requests.__version__)"`

#### 临时给某个实例加包（不改 requirements 文件）

在 `config/n8n-super.env` 里设置（或用环境变量覆盖）：

- `N8N_PYTHON_PACKAGES="pandas==2.2.3 openpyxl==3.1.5"`

然后重启容器即可。

### 7.4 新增/升级系统工具/CLI（kubectl/helm/terraform/自研二进制）= 必须重建镜像

做法：修改 `Dockerfile` 的系统工具安装段（apt/apk），固定版本（如可行）并构建新 tag。该类工具属于“镜像能力”，不建议运行中临时安装。

### 7.5 环境变量/镜像源为什么说“一次配置长期复用”

- **pip 源**：写在 `config/n8n-super.env`（`N8N_PIP_INDEX_URL`/`N8N_PIP_TRUSTED_HOST`），容器启动与 python wrapper 都会加载并映射到 `PIP_*`。
- **build 时 pip 源**：写在 `config/build.env` 的 `PIP_*`，用于构建期预装基础依赖（例如 `config/requirements.txt` 的预装）。
- 结论：你们只需要把公司内网 pip 源在这两处配置好，后续新增 Python 包只改 requirements/变量，无需频繁折腾环境。

### 7.6 发版 tag 规范（rN 递增）

建议把镜像 tag 固定成“可回滚”的形式：

- `n8n-super:<n8nVersion>-rN`
  - 示例：`n8n-super:1.78.1-r1`、`n8n-super:1.78.1-r2`

约定：

- `<n8nVersion>`：上游 n8n 基础版本（对应 `Dockerfile` 的 `FROM n8nio/n8n:<version>`）
- `rN`：你们团队在该基础版本上的第 N 次发布，**只允许递增**

### 7.7 回滚策略（只要换回 tag + 强制重建容器）

回滚的前提是：你们每次发布都保留旧 tag（不要覆盖）。回滚动作统一为：

1) 把部署侧使用的镜像 tag 改回上一个稳定版本（例如从 `1.78.1-r3` 回到 `1.78.1-r2`）
2) 强制重建容器（确保新 tag 生效）
   - Linux/macOS：
     - `./scripts/run.sh --force-recreate`
     - Queue：`./scripts/run.sh --queue --force-recreate`
   - Windows：
     - `.\windows\run.ps1 -ForceRecreate`
     - Queue：`.\windows\run.ps1 -Queue -ForceRecreate`

## 8. Python wrapper 机制详解（排障必看）

### 8.1 hash 的输入是什么

wrapper 会把以下信息拼成一个签名并做 sha256：

- requirements 文件内容 hash（文件存在时）
- `N8N_PYTHON_PACKAGES`
- `N8N_PYTHON_PIP_EXTRA_ARGS`
- pip 源相关（`PIP_INDEX_URL`/`PIP_EXTRA_INDEX_URL`/`PIP_TRUSTED_HOST`/`PIP_DEFAULT_TIMEOUT`）

### 8.2 什么时候会触发安装

只有同时满足：

- `N8N_PYTHON_AUTO_INSTALL=true`
- 且 `N8N_PYTHON_REQUIREMENTS_FILE` 或 `N8N_PYTHON_PACKAGES` 非空

否则直接用基础 venv 的真实解释器执行（`python3-real`）。

### 8.3 并发安全

- 同一 hash 的 venv 创建/安装使用 lock 目录互斥（避免并发踩踏）

### 8.4 缓存清理

`docker-entrypoint-extra.sh` 支持启动时按 TTL 清理（可选）：

- `N8N_PYTHON_VENV_CACHE_CLEANUP=true`
- `N8N_PYTHON_VENV_CACHE_TTL_DAYS=30`

注意事项：

- 这是启动时清理，建议在低峰期重启
- TTL 设置不当可能删到正在使用的 venv（虽然概率不高，但要认识风险）

## 9. 社区节点管理（为什么会“安装了但 UI 看不到”）

### 9.1 根因：volume 覆盖

你们在 compose 中通常会把 `/home/node/.n8n` 挂载为 volume 持久化。

- 镜像构建时安装到 `/home/node/.n8n/nodes` 的内容会被 volume 覆盖

### 9.2 n8n-super 的解决方式：启动时同步

`docker-entrypoint-extra.sh` 在启动时：

- 把构建期备份的 `/opt/n8n-super-prebuilt-nodes` 同步到：
  - `/home/node/.n8n/nodes`
  - `/home/node/.n8n/custom`

并使用 marker 文件避免每次重复同步。

### 9.3 兼容性补丁（钉钉节点）

启动脚本里包含一个一次性 patch：

- `n8n-nodes-dingtalk` 节点内部引用的 credential 名称不一致
- 脚本会替换 dist 文件里的 credential name，避免节点加载异常

## 10. 安全提示

### 10.1 `Execute Command` 风险

`docker-compose.yml` 中 `NODES_EXCLUDE: "[]"` 会启用 `Execute Command`。

- 这意味着工作流可以执行任意命令

建议：

- 生产优先走“受控执行器”（Jenkins/AWX/Agent）
- 如果一定要启用：
  - 网络隔离（只允许访问必要内网系统）
  - 账号最小权限
  - 强制审计（执行记录 + 外部日志）

### 10.2 凭据治理

- 不把 token/密码写入 workflow JSON
- 使用 n8n Credentials
- 如具备企业能力可接外部 Secrets（参考 n8n 官方 External Secrets）

## 11. 可观测性与运维

- **健康检查**：`/healthz`（compose 已内置 healthcheck）
- **队列健康检查**：`QUEUE_HEALTH_CHECK_ACTIVE=true`（你们 compose 已开启）
- **Prometheus 指标**：n8n 支持 `/metrics`（官方示例为 `N8N_METRICS=true`）
- **日志**：可通过 n8n 环境变量控制日志级别与输出（建议接入日志平台）

## 12. 常用运维动作

### 12.1 Windows 快速运行

- 构建：`windows/build.ps1`
- 启动：`windows/run.ps1`
- 自检：`windows/test.ps1`

### 12.2 Linux/macOS 快速运行

- 构建：`scripts/build.sh`
- 启动：`scripts/run.sh`
- 自检：`scripts/test.sh`

### 12.3 升级 / 启动 / 自检 / Queue / 回滚

#### Linux/macOS

```bash
chmod +x ./scripts/build.sh ./scripts/run.sh ./scripts/test.sh

./scripts/build.sh
./scripts/run.sh --force-recreate
./scripts/test.sh

./scripts/run.sh --queue --force-recreate
./scripts/test.sh --queue
```

#### Windows PowerShell

```powershell
cd d:\job-test\n8n-best\n8n-super

.\windows\build.ps1
.\windows\run.ps1 -ForceRecreate
.\windows\test.ps1

.\windows\run.ps1 -Queue -ForceRecreate
.\windows\test.ps1 -Queue
```

#### 回滚/重建要点

- **镜像更新但容器没换**：加 `--force-recreate`（Windows 对应 `-ForceRecreate`）。
- **使用已发布 tag**：加 `--pull`（Windows 对应 `-Pull`）。

## 13. FAQ / 排障

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
- **[Queue 文件名]**
  - 本仓库 Queue 编排为 `docker-compose-queue.yml`
- **[容器异常]**
  - 先看 `docker logs --tail 200 <container>`

## 14. 相关文档

- **工作流像代码一样维护（Workflow-as-Code）**：见 `./04-workflow-as-code.md`。
