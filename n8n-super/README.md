# n8n-super（基于 n8nio/n8n:1.78.1 的增强镜像）

## 目标

在 `n8nio/n8n:1.78.1` 官方镜像基础上增强：

- **Python 节点**：预装社区节点 `n8n-nodes-python`（提供 `PythonFunction` 节点）
- **Python 运行环境**：内置 Python3 + venv（`/opt/n8n-python-venv`），并支持容器启动时按环境变量自动 `pip install`
- **Shell 能力**：通过内置的 **Execute Command（Command）节点** 执行 shell（需解除默认禁用，见下文安全说明）
- **ArgoCD**：预装 `argocd` CLI，可在工作流里用 Execute Command 节点调用
- **Jenkins / GitLab**：n8n 内置节点（无需额外安装）

## 使用方式概览

- **构建期可配置项**：统一写在 `config/build.env`（build args：`ARGOCD_VERSION` / `COMMUNITY_NODES` / `PIP_*`）。
- **运行期可配置项**：统一写在 `config/n8n-super.env`（启动时加载，pip 源映射、Python 自动装包开关等）。
- **Python 依赖**：团队统一依赖建议写在 `config/requirements.txt`，通过 volume 挂载到容器内并在运行期按需安装。

## 目录结构

- `Dockerfile`：镜像构建文件
- `docker-compose.yml`：单容器模式编排（端口、数据卷、健康检查、配置注入）
- `docker-compose-queue.yml`：Queue 模式编排（web/worker/webhook + redis + postgres）
- `docker-entrypoint-extra.sh`：启动入口（加载配置文件/环境变量后转交官方 `/docker-entrypoint.sh`）
- `n8n-python3-wrapper.sh`：venv 内 `python3` wrapper（运行时按依赖 hash 创建/复用独立 venv）
- `config/`
  - `config/n8n-super.env`：启动配置注入文件（pip 源、自动装包开关、缓存目录等）
  - `config/requirements.txt`：Python 依赖示例（可替换为你的依赖集合）
- `scripts/`
  - `scripts/*.sh`：Linux/macOS 真实实现脚本
- `windows/`
  - `windows/*.ps1`：Windows/PowerShell 脚本

## 快速开始（Linux 推荐）

### 0) 前置条件

- Docker Engine
- Docker Compose v2（`docker compose version`）

### 1) 构建镜像

```bash
chmod +x ./scripts/build.sh ./scripts/run.sh ./scripts/test.sh
./scripts/build.sh
```

### 2) 启动

```bash
./scripts/run.sh
```

### 3) 健康检查

```bash
curl -fsS http://localhost:5678/healthz
```

### 4) 验证“Python 自动装包”是否生效

```bash
./scripts/test.sh
docker exec n8n-super python3 -c "import requests; print('requests:', requests.__version__)"
```

### 5) 打开 Web UI

- `http://localhost:5678/`

## 快速开始（Windows PowerShell）

### 1) 构建镜像（Windows）

```powershell
cd d:\job-test\n8n-best\n8n-super
.\windows\build.ps1
```

### 2) 运行（Windows）

```powershell
.\windows\run.ps1
```

访问：

- Web UI：`http://localhost:5678/`
- 健康检查：`http://localhost:5678/healthz`

### 3) 验证（Windows）

```powershell
.\windows\test.ps1
```

验证内容包括：

- `/healthz` 可用
- `n8n --version` 输出版本
- `argocd version --client` 可执行
- venv 内 `python-fire` 可导入
- `n8n-nodes-python` 包存在

## 配置入口（建议只改这 3 处）

- **`config/build.env`**：构建期 build args（由 `scripts/build.sh` 与 `windows/build.ps1` 自动读取）。
- **`config/n8n-super.env`**：运行期环境变量文件（由容器启动脚本加载）。
- **`config/requirements.txt`**：团队 Python 统一依赖（默认已在 compose 里挂载到容器）。

## 变更/发版逻辑（新增节点/新增 Python 包/新增工具）

### 核心原则

- **需要重建镜像**：新增/升级 **n8n 社区节点（npm 包）**、新增/升级 **系统工具/CLI**、修改 `Dockerfile`、升级基础镜像/系统依赖。
- **不需要重建镜像**：新增/升级 **Python 包**（走运行期自动安装 + venv 缓存），调整 pip 源/环境变量（一次配置长期复用）。

### 1) 新增/升级 n8n 社区节点（node 节点 / npm 包）= 必须重建镜像

#### 节点安装“定义在哪里”

- **安装定义**：`Dockerfile` 中的 `ARG COMMUNITY_NODES` + `npm install ...`
- **默认来源**：当 `COMMUNITY_NODES` 为空时，从 `config/community-nodes.list` 读取（镜像构建期 COPY 到 `/opt/n8n-super-community-nodes.list`）
- **安装落地目录**：`/home/node/.n8n/nodes/node_modules/<n8n-nodes-xxx>`

#### 推荐方式（团队统一）

1) 编辑 `config/community-nodes.list`，每行一个包（建议固定版本，例如你现在的：`n8n-nodes-browser@0.2.4`）
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

### 2) 新增/升级 Python 包（requests/pandas/…）= 不需要重建镜像

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
2) 重启容器即可（不需要 build 镜像）
   - 单容器：`./scripts/run.sh --force-recreate`
   - Queue：`./scripts/run.sh --queue --force-recreate`
3) 等下一次 PythonFunction 执行时会自动安装；你也可以主动验证：
   - `docker exec n8n-super python3 -c "import requests; print(requests.__version__)"`

#### 临时给某个实例加包（不改 requirements 文件）

在 `config/n8n-super.env` 里设置（或用环境变量覆盖）：

- `N8N_PYTHON_PACKAGES="pandas==2.2.3 openpyxl==3.1.5"`

然后重启容器即可。

### 3) 新增/升级系统工具/CLI（kubectl/helm/terraform/自研二进制）= 必须重建镜像

做法：修改 `Dockerfile` 的系统工具安装段（apt/apk），固定版本（如可行）并构建新 tag。该类工具属于“镜像能力”，不建议运行中临时安装。

### 4) 环境变量/镜像源为什么说“一次配置长期复用”

- **pip 源**：写在 `config/n8n-super.env`（`N8N_PIP_INDEX_URL`/`N8N_PIP_TRUSTED_HOST`），容器启动与 python wrapper 都会加载并映射到 `PIP_*`。
- **build 时 pip 源**：写在 `config/build.env` 的 `PIP_*`，用于构建期预装基础依赖（例如 `config/requirements.txt` 的预装）。
- 结论：你们只需要把公司内网 pip 源在这两处配置好，后续新增 Python 包只改 requirements/变量，无需频繁折腾环境。

### 5) 发版 tag 规范（rN 递增）

建议把镜像 tag 固定成“可回滚”的形式：

- `n8n-super:<n8nVersion>-rN`
  - 示例：`n8n-super:1.78.1-r1`、`n8n-super:1.78.1-r2`

约定：

- `<n8nVersion>`：上游 n8n 基础版本（对应 `Dockerfile` 的 `FROM n8nio/n8n:<version>`）
- `rN`：你们团队在该基础版本上的第 N 次发布，**只允许递增**

### 6) 回滚策略（只要换回 tag + 强制重建容器）

回滚的前提是：你们每次发布都保留旧 tag（不要覆盖）。回滚动作统一为：

1) 把部署侧使用的镜像 tag 改回上一个稳定版本（例如从 `1.78.1-r3` 回到 `1.78.1-r2`）
2) 强制重建容器（确保新 tag 生效）
   - Linux/macOS：
     - `./scripts/run.sh --force-recreate`
     - Queue：`./scripts/run.sh --queue --force-recreate`
   - Windows：
     - `.\windows\run.ps1 -ForceRecreate`
     - Queue：`.\windows\run.ps1 -Queue -ForceRecreate`

### 7) 变更记录模板（建议每次发版必填）

你可以把下面这段复制到你们的 PR/工单/发版记录中：

```text
[release]
tag: n8n-super:1.78.1-rN
date: YYYY-MM-DD
owner: <name>

changes:
- community_nodes:
  - added: <pkg@ver>, <pkg@ver>
  - updated: <pkg@oldver -> pkg@newver>
  - removed: <pkg@ver>
- python_requirements:
  - added: <pkg==ver>
  - updated: <pkg==oldver -> pkg==newver>
  - removed: <pkg==ver>
- tools:
  - added/updated: <tool@ver or url>

build:
- build_env:
  - ARGOCD_VERSION=<...>
  - COMMUNITY_NODES=<...>
  - PIP_INDEX_URL=<...>

verification:
- single:
  - healthz: ok
  - n8n --version: <...>
  - argocd version --client: <...>
- queue:
  - healthz: ok
  - web/worker/webhook: ok

rollback:
- previous_tag: n8n-super:1.78.1-r(N-1)
- command: run.sh --force-recreate (or --queue)
```

## （升级 / 启动 / 自检 / Queue / 回滚）

### Linux/macOS

```bash
chmod +x ./scripts/build.sh ./scripts/run.sh ./scripts/test.sh

./scripts/build.sh
./scripts/run.sh --force-recreate
./scripts/test.sh

./scripts/run.sh --queue --force-recreate
./scripts/test.sh --queue
```

### Windows PowerShell

```powershell
cd d:\job-test\n8n-best\n8n-super

.\windows\build.ps1
.\windows\run.ps1 -ForceRecreate
.\windows\test.ps1

.\windows\run.ps1 -Queue -ForceRecreate
.\windows\test.ps1 -Queue
```

### 回滚/重建要点

- **镜像更新但容器没换**：加 `--force-recreate`（Windows 对应 `-ForceRecreate`）。
- **使用已发布 tag**：加 `--pull`（Windows 对应 `-Pull`）。

## 安全提示

- `docker-compose.yml` 中 `NODES_EXCLUDE: "[]"` 会启用 `Command` 节点（可执行任意命令）。生产使用请结合权限、网络隔离与审计。

## FAQ

- **Queue 文件名**：本仓库 Queue 编排为 `docker-compose-queue.yml`。
- **容器异常**：先看 `docker logs --tail 200 <container>`。
