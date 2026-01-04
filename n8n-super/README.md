# n8n-super：自定义 n8n 镜像（构建 / 扩展 / 发版指南）

本文专门说明：**如何在本仓库基础上制作你自己的 n8n 镜像**（安装工具链、固化社区节点、Python 运行时与依赖策略、发版与回滚）。

运维与机制说明（面向使用者/运维）请看：

- `../n8n-learn/03-n8n-super-ops.md`

---

## 0. TL;DR：最小改动入口（你通常只需要改这几个文件）

目标：让你读完本 README 后，**只改少数入口**即可完成“新增节点/新增工具/新增 Python 包/升级版本/发版回滚”。

建议把改动分为 4 类，对应改动点如下：

1) **新增/升级社区节点（n8n-nodes-xxx）**
   - 改：`config/community-nodes.list`
   - 然后：构建新镜像 tag → 更新 `docker-compose*.yml` 的 `image:` → `--force-recreate`

2) **新增/升级系统工具 / CLI（kubectl/helm/terraform/自研二进制等）**
   - 改：`Dockerfile`
   - 然后：构建新镜像 tag → 更新 `docker-compose*.yml` 的 `image:` → `--force-recreate`

3) **新增/升级团队默认 Python 包（偏“通用运维库”）**
   - 改：`config/requirements.txt`
   - 然后：构建新镜像 tag → 更新 `docker-compose*.yml` 的 `image:` → `--force-recreate`
   - 说明：本仓库选择“离线/新手友好”的策略：把常用依赖尽量预装进镜像，减少运行期下载失败；如果只是某条 workflow 临时依赖，仍可用运行期变量 `N8N_PYTHON_PACKAGES` 补充。

4) **升级 n8n 基础版本**
   - 改：`Dockerfile` 的 `FROM n8nio/n8n:<version>`
   - 同步改：`docker-compose*.yml` 的 `image:` tag（建议用 `n8n-super:<n8nVersion>-rN`）

验证统一用：

- Linux/macOS：`./scripts/test.sh`（必要时加 `--queue`）
- Windows：`.\windows\test.ps1`（必要时加 `-Queue`）

---

## 1. 你会得到什么（n8n-super 的目标）

在官方 `n8nio/n8n:1.78.1` 基础上，这个镜像主要增强：

- **系统工具链**：`bash/curl/git/jq/openssh-client/rsync/tar/unzip/wget`（以及浏览器运行时依赖）
- **Browser 场景**：预装 `chromium`
- **PythonFunction 场景**：预装 `python3` + venv/pip，并提供“按依赖 hash 的隔离 venv 缓存”机制（解决多人共用依赖冲突）
- **GitOps/发布类场景**：预装 `argocd` CLI（版本可控）
- **社区节点固化**：构建期安装 `config/community-nodes.list` 中的节点，并在启动时自动同步到 volume（避免“装了但 UI 看不到”）

## 2. 目录结构（你改哪里）

- `Dockerfile`
  - 镜像构建主逻辑（装系统包 / 创建基础 venv / 安装社区节点 / 安装 argocd）
- `docker-entrypoint-extra.sh`
  - 启动时加载配置文件 + 映射 pip 环境变量 + 同步社区节点 + 可选清理 venv 缓存
- `n8n-python3-wrapper.sh`
  - `python3` wrapper：按 requirements+pip 源计算 hash，并创建/复用独立 venv
- `config/`
  - `build.env`：构建期 build-arg 配置（ARGOCD_VERSION / COMMUNITY_NODES / PIP_*）
  - `community-nodes.list`：团队统一的社区节点清单（建议固定版本）
  - `requirements.txt`：团队统一 Python 依赖（建议固定版本）
  - `n8n-super.env`：运行期配置入口（启动时加载）
- `scripts/*.sh`：Linux/macOS 构建/启动/自检脚本
- `windows/*.ps1`：Windows 构建/启动/自检脚本
- `docker-compose.yml`：单容器模式（SQLite），适合开发/PoC
- `docker-compose-queue.yml`：Queue 模式（Postgres+Redis+Web/Worker/Webhook），适合生产

## 3. 快速开始（构建并跑起来）

### 3.1 Linux/macOS

```bash
chmod +x ./scripts/build.sh ./scripts/run.sh ./scripts/test.sh

# 构建（默认 tag：n8n-super:1.78.1）
./scripts/build.sh

# 启动（默认会执行 docker compose build，如已构建可加 --no-build）
./scripts/run.sh

# 自检
./scripts/test.sh
```

### 3.2 Windows PowerShell

```powershell
cd d:\job-test\n8n-best\n8n-super

# 构建（默认 tag：n8n-super:1.78.1）
.\windows\build.ps1

# 启动（默认会执行 docker compose build，如已构建可加 -NoBuild）
.\windows\run.ps1

# 自检
.\windows\test.ps1
```

访问：`http://localhost:5678/`，健康检查：`http://localhost:5678/healthz`

---

## 4. 构建参数与配置入口（建议统一在这两处改）

### 4.1 构建期（build-time）：`config/build.env`

此文件用于 build 脚本/CI 传递 build args（空值表示不传）。

- `ARGOCD_VERSION`：控制 Dockerfile 下载的 argocd 版本
- `COMMUNITY_NODES`：可选，空格分隔的 npm 包列表；为空时默认使用 `config/community-nodes.list`
- `PIP_INDEX_URL` / `PIP_EXTRA_INDEX_URL` / `PIP_TRUSTED_HOST` / `PIP_DEFAULT_TIMEOUT`
  - 仅影响构建期 pip install（基础 venv 预装）

### 4.2 运行期（runtime）：`config/n8n-super.env`

容器启动时由 `docker-entrypoint-extra.sh` 加载（`docker-compose.yml` 会把它挂载到 `/etc/n8n-super.env` 并设置 `N8N_SUPER_CONFIG_FILE=/etc/n8n-super.env`）。

你通常只需要改这几类：

- `N8N_PIP_*`：公司内网 pip 源配置（会映射为 pip 标准变量 `PIP_*`）
- `N8N_PYTHON_*`：Python 自动装包与 venv 缓存目录

重要说明（容易踩坑）：

- `docker-compose.yml` 的 `environment:` 段对同名变量有更高优先级。

当前仓库的实际情况：

- `config/n8n-super.env` 里默认 `N8N_PYTHON_AUTO_INSTALL=true`
- 但 `docker-compose.yml` 的 `environment:` 里写了：`N8N_PYTHON_AUTO_INSTALL: ${N8N_PYTHON_AUTO_INSTALL:-false}`

这意味着：

- 如果你不在宿主环境（或 `.env`）显式设置 `N8N_PYTHON_AUTO_INSTALL=true`，最终容器里会变成 `false`，导致 wrapper 不会自动装包。

推荐做法（二选一）：

1) **团队统一（推荐）**：直接把 `docker-compose.yml` 里的默认值改成 `true`。
2) **部署侧覆盖**：在运行机器上设置环境变量 `N8N_PYTHON_AUTO_INSTALL=true`（或在 `.env` 文件里设置），不改 compose。

---

## 5. 如何新增/升级社区节点（n8n-nodes-xxx）

### 5.1 推荐方式：维护 `config/community-nodes.list`

- 每行一个 npm 包，**建议固定版本**（便于复现/回滚）
- Dockerfile 在构建期会读取该文件并安装

修改后按发版流程构建新镜像即可。

### 5.2 临时覆盖（不改列表）：设置 build arg `COMMUNITY_NODES`

两种方式任选：

- 修改 `config/build.env`：
  - `COMMUNITY_NODES="n8n-nodes-python@0.1.4 n8n-nodes-ntfy@0.1.7"`
- 或构建时直接传入（Linux/macOS）：
  - `COMMUNITY_NODES="..." ./scripts/build.sh`

### 5.3 为什么需要“启动时同步”

你们通常会把 `/home/node/.n8n` 挂载为 volume 做持久化，这会覆盖镜像构建期写入的 `/home/node/.n8n/nodes`。

因此 Dockerfile 会把构建期安装的节点备份到 `/opt/n8n-super-prebuilt-nodes`，启动脚本 `docker-entrypoint-extra.sh` 会在首次启动时同步到 volume 内，确保 UI 能加载到社区节点。

---

## 6. 如何新增/升级 Python 依赖（requests/pandas/…）

### 6.1 基础机制

- 构建期会创建基础 venv：`/opt/n8n-python-venv`
  - 预装 `python-fire`
  - 预装 `config/requirements.txt`（用于团队常用包，提升首次运行体验）
- 运行期执行 `python3` 时会走 `n8n-python3-wrapper.sh`
  - 根据 `N8N_PYTHON_REQUIREMENTS_FILE` + `N8N_PYTHON_PACKAGES` + pip 源参数计算 hash
  - 在 `N8N_PYTHON_VENV_CACHE_DIR/<hash>` 创建/复用独立 venv（互不污染）

### 6.2 团队统一依赖（推荐）

- 编辑 `config/requirements.txt`
- 构建并发布新镜像（建议走 tag 递增）

说明：

- `config/requirements.txt` 会在构建期预装到基础 venv（`/opt/n8n-python-venv`），适合离线/新手环境。
- 运行期如仍需额外依赖，可继续使用 `N8N_PYTHON_PACKAGES` 或 `N8N_PYTHON_REQUIREMENTS_FILE` 触发 hash-venv 安装。

### 6.3 临时给某个实例加包（不改镜像）

- 在运行环境设置：`N8N_PYTHON_PACKAGES="pandas==2.2.3 openpyxl==3.1.5"`
- 并确保：
  - `N8N_PYTHON_AUTO_INSTALL=true`
  - `N8N_PYTHON_VENV_CACHE_DIR` 有写权限

### 6.4 venv 缓存清理（可选）

启动时可按 TTL 清理缓存目录：

- `N8N_PYTHON_VENV_CACHE_CLEANUP=true`
- `N8N_PYTHON_VENV_CACHE_TTL_DAYS=30`

建议在低峰期重启执行，TTL 不当可能误删正在使用的 venv。

---

## 7. 如何新增/升级系统工具 / CLI

建议把系统工具作为“镜像能力”固化在 Dockerfile：

- Debian 系列：`apt-get install ...`
- Alpine 系列：`apk add ...`

实践建议：

- 尽量固定版本（或至少固定上游镜像版本）
- 企业内网建议走制品库/代理源，并做校验（sha256）

---

## 8. 发版与回滚（镜像 tag 管理）

推荐 tag 规范：

- `n8n-super:<n8nVersion>-rN`
  - 示例：`n8n-super:1.78.1-r1`、`n8n-super:1.78.1-r2`

典型流程：

1) 修改：`Dockerfile` / `config/community-nodes.list` / `config/requirements.txt`
2) 构建新 tag：
   - Linux/macOS：`./scripts/build.sh --tag n8n-super:1.78.1-r2`
   - Windows：`.\windows\build.ps1 -Tag "n8n-super:1.78.1-r2"`
3) 将部署侧 `docker-compose.yml` / `docker-compose-queue.yml` 里的 `image:` 改为新 tag
4) 启动时强制重建容器（确保新 tag 生效）：
   - Linux/macOS：`./scripts/run.sh --no-build --force-recreate`
   - Windows：`.\windows\run.ps1 -NoBuild -ForceRecreate`

回滚：把 `image:` 换回旧 tag，再 `--force-recreate`。

### 8.1 发布时你需要改哪几处

发布新版本时，建议你始终遵循下面的“最小改动面”原则：

- **改动功能**：只改 `Dockerfile` / `config/community-nodes.list` / `config/requirements.txt`
- **改动版本**：只改 `docker-compose.yml`、`docker-compose-queue.yml` 里的 `image:` tag（或由部署系统注入）

### 8.2 建议的发布验收清单（Checklist）

- `./scripts/test.sh` / `.\windows\test.ps1` 全绿
- UI 能看到社区节点（尤其是 `n8n-nodes-python`、`n8n-nodes-dingtalk`、`n8n-nodes-browser`）
- 执行一次 `workflows/n8n-super-full-test.json`（只要能跑过关键节点即可）
- 生产环境确认：是否真的需要 `NODES_EXCLUDE: "[]"`（启用 `Execute Command`）

---

## 9. 升级 n8n 基础版本（n8nio/n8n）

这是最常见但也最敏感的变更类型之一（兼容性/数据迁移/节点行为可能变化）。建议你按下面步骤做：

1) 改 `Dockerfile`
   - 把 `FROM n8nio/n8n:1.78.1` 改为目标版本（例如 `1.79.0`）
2) 重新构建新 tag
   - Linux/macOS：`./scripts/build.sh --tag n8n-super:1.79.0-r1`
   - Windows：`.\windows\build.ps1 -Tag "n8n-super:1.79.0-r1"`
3) 更新 compose 使用的镜像 tag
   - `docker-compose.yml` 的 `image:`
   - `docker-compose-queue.yml` 的 `image:`（web/worker/webhook）
4) 强制重建容器
   - Linux/macOS：`./scripts/run.sh --no-build --force-recreate`
   - Windows：`.\windows\run.ps1 -NoBuild -ForceRecreate`
5) 跑自检
   - Linux/macOS：`./scripts/test.sh`
   - Windows：`.\windows\test.ps1`

建议：

- 先在测试环境演练一次升级与回滚
- 如果你从 SQLite 迁移到 Postgres，优先在 Queue 模式上做（避免“边跑边迁移”的复杂性）

---

## 10. 常见场景：我到底要改哪里（按场景给最短路径）

### 10.1 我想新增一个社区节点

你只需要：

1) 改 `config/community-nodes.list`
   - 每行一个包名，建议固定版本
2) 构建新镜像 tag
3) 更新 `docker-compose*.yml` 的 `image:` 并 `--force-recreate`

说明：

- Dockerfile 构建期会把节点安装到 `/home/node/.n8n/nodes`，并备份到 `/opt/n8n-super-prebuilt-nodes`
- 启动时 `docker-entrypoint-extra.sh` 会把备份同步到 volume（否则 volume 会覆盖构建期安装目录）

### 10.2 我想新增一个系统工具（kubectl/helm/terraform/自研二进制）

你只需要：

1) 改 `Dockerfile` 的系统包安装段（apt/apk）
2) 构建新 tag
3) 更新 `docker-compose*.yml` 的 `image:` 并 `--force-recreate`

### 10.3 我想让某条 workflow 临时多装几个 Python 包（不改镜像）

你只需要：

1) 在运行环境设置：
   - `N8N_PYTHON_AUTO_INSTALL=true`
   - `N8N_PYTHON_PACKAGES="xxx==1.2.3 yyy==4.5.6"`
2) 重启容器（或至少确保新的环境变量生效）

注意：

- 这会按“依赖集合 hash”生成独立 venv 缓存目录，互不污染
- 该方式更适合“个别 workflow 临时依赖”，不建议把所有业务依赖都塞成全局默认

### 10.4 我想把团队通用 Python 包固化到镜像（提升首次运行体验）

你只需要：

1) 改 `config/requirements.txt`
2) 构建新 tag
3) 更新 `docker-compose*.yml` 的 `image:` 并 `--force-recreate`

建议：

- 本仓库选择“离线/新手友好”的策略：团队默认依赖允许维持较大集合（减少运行期下载失败/提升首次运行体验）。
- 如果你后续要做“生产瘦身”，再把大依赖从 `config/requirements.txt` 迁移到运行期按需（`N8N_PYTHON_PACKAGES`）即可。

### 10.5 我只是想换一个 argocd 版本

你只需要：

1) 改 `config/build.env` 的 `ARGOCD_VERSION`
2) 构建新 tag
3) 更新 `docker-compose*.yml` 的 `image:` 并 `--force-recreate`

---

## 11. 自检（验收镜像是否可用）

- Linux/macOS：`./scripts/test.sh`
- Windows：`.\windows\test.ps1`

自检覆盖：

- `/healthz` 可用
- `n8n --version`
- `argocd version --client`
- `/opt/n8n-python-venv` 内 `python-fire` 可导入
- `n8n-nodes-python` 包存在

---

## 10. 安全提示（生产必看）

- `docker-compose.yml` 里 `NODES_EXCLUDE: "[]"` 会启用 `Execute Command`。
- 该能力可执行任意命令，生产环境建议：
  - 网络隔离（只允许访问必要内网系统）
  - 最小权限运行
  - 强制审计（执行记录 + 外部日志）
  - 高风险动作优先走“受控执行器”（Jenkins/AWX/自研 Agent），n8n 做控制面与编排
