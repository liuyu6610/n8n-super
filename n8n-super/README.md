# n8n-super（基于 n8nio/n8n:1.78.1 的增强镜像）

## 目标

在 `n8nio/n8n:1.78.1` 官方镜像基础上增强：

- **Python 节点**：预装社区节点 `n8n-nodes-python`（提供 `PythonFunction` 节点）
- **Python 运行环境**：内置 Python3 + venv（`/opt/n8n-python-venv`），并支持容器启动时按环境变量自动 `pip install`
- **Shell 能力**：通过内置的 **Execute Command（Command）节点** 执行 shell（需解除默认禁用，见下文安全说明）
- **ArgoCD**：预装 `argocd` CLI，可在工作流里用 Execute Command 节点调用
- **Jenkins / GitLab**：n8n 内置节点（无需额外安装）

## 适用场景（你应该选哪种方式）

- **场景A：团队多人共用同一个 n8n，但每个 workflow 的 Python 依赖不同**
  - 使用本项目的“**按依赖 hash 的独立 venv 缓存**”（默认机制）。
  - 通过 `N8N_PYTHON_REQUIREMENTS_FILE` / `N8N_PYTHON_PACKAGES` 配置依赖集合。
  - 优点：依赖不会互相覆盖；同一套依赖会复用缓存。
- **场景B：团队希望统一一套 Python 依赖（所有人都一致）**
  - 统一维护 `config/requirements.txt`（建议固定版本）。
  - 优点：可控、可审计、可复现；适合生产。
- **场景C：某个同学/某条线需要额外的工具或社区节点，不希望影响团队默认镜像**
  - 每个人构建自己的镜像 tag（例如 `n8n-super:1.78.1-zhangsan-20260101`），或基于 `n8n-super` 写自己的 Dockerfile。
  - 优点：彻底隔离；适合“个人实验/专项需求”。

## 关键设计（必须理解，否则容易踩坑）

### 1) Python 依赖是如何做到“多人不互相污染”的

本镜像里有两个层次的 venv：

- **基础 venv（Base venv）**
  - 路径：`/opt/n8n-python-venv`
  - 在镜像构建期创建，用于提供一个“稳定的 Python 运行入口”。
  - 只安装极少数基础依赖（例如 `python-fire`）。
- **独立 venv（Isolated venv，按依赖 hash）**
  - 路径：默认在 `/home/node/.n8n/pyenvs/<hash>`
  - 由 `n8n-python3-wrapper.sh` 在运行时创建/复用。
  - 每套依赖集合（requirements 内容 + pip 源参数 + packages + extra args）会得到一个唯一 hash。
  - **不同 hash -> 不同 venv**（互不影响），**相同 hash -> 复用同一 venv**（避免重复安装）。

因此：

- 你不需要为了“某个 workflow 多装几个包”去重打整个镜像。
- 也不要在运行中的容器里手工 `pip install` 到基础 venv（那样会回到“互相覆盖、不可运维”的老路）。

### 2) requirements / packages 改了为什么不一定立刻生效

独立 venv 的创建/安装是由 `python3` wrapper 在“执行 Python 时”触发的：

- 如果你只是修改了 `config/requirements.txt`，但还没有执行任何 Python 节点，那么不会触发安装。
- 一旦有 PythonFunction 执行，wrapper 会基于当前依赖集合计算 hash：
  - hash 变化 -> 新建一个目录并安装
  - hash 不变 -> 直接复用缓存

### 3) `named volume` vs `bind mount` 对社区节点的影响

`docker-compose.yml` 默认用 `named volume` 挂载 `/home/node/.n8n`，首次创建该 volume 时会继承镜像里的预装节点目录。

如果你改为 `bind mount`（把宿主机目录直接挂进去），第一次启动可能覆盖镜像内的 `/home/node/.n8n`，导致：

- UI 里看不到社区节点（因为 `/home/node/.n8n/nodes` 被你宿主机目录覆盖了）

这个是 Docker 行为，不是 n8n-super 的 bug。

## 目录结构

- `Dockerfile`：镜像构建文件
- `docker-compose.yml`：单容器模式编排（端口、数据卷、健康检查、配置注入）
- `docker-compose.queue.yml`：Queue 模式编排（web/worker/webhook + redis + postgres）
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

## 新版本升级 / 重新构建镜像 / 回归测试（推荐按此 SOP）

本章节用于：

- 你修改了 `Dockerfile` / `n8n-python3-wrapper.sh` / `docker-entrypoint-extra.sh` 等构建/启动关键文件
- 你希望构建一个“新版本镜像 tag”，并确保容器运行符合预期

### 0) 重要概念（避免踩坑）

- **`ARG COMMUNITY_NODES` 是构建期参数（build arg）**：只能在 `docker build` 或 `docker compose build` 时注入；容器运行后无法再改变。
- **重新 build 不等于容器自动更新**：build 完后建议使用 `docker compose up -d --force-recreate` 重新创建容器。
- **Windows PowerShell 的 curl 坑**：PowerShell 中 `curl` 通常是 `Invoke-WebRequest` 的别名，推荐用 `curl.exe` 或 `Invoke-RestMethod`。

### 1) 单容器模式（docker-compose.yml）升级流程

#### 1.1 停止旧容器

```powershell
docker compose -f docker-compose.yml down
```

#### 1.2 （可选）注入社区节点批量安装（COMMUNITY_NODES）

如果你需要在构建时批量安装社区节点：

```powershell
$env:COMMUNITY_NODES="n8n-nodes-python@0.1.4 n8n-nodes-xxx@1.2.3"
```

不设置则使用默认：`n8n-nodes-python`。

#### 1.3 构建镜像（推荐 no-cache 确保生效）

```powershell
docker compose -f docker-compose.yml build --no-cache
```

#### 1.4 启动并强制重建容器（确保使用新镜像层）

```powershell
docker compose -f docker-compose.yml up -d --force-recreate
```

#### 1.5 回归自测（必做）

健康检查（Windows 推荐 `curl.exe`）：

```powershell
curl.exe -fsS http://localhost:5678/healthz
```

核心能力自测：

```powershell
docker exec n8n-super n8n --version
docker exec n8n-super argocd version --client
docker exec n8n-super /opt/n8n-python-venv/bin/python -c "import fire; print('python-fire ok')"
docker exec n8n-super node -e "const p=require('/home/node/.n8n/nodes/node_modules/n8n-nodes-python/package.json'); console.log(p.name+'@'+p.version)"
```

Python 自动装包自测（依赖来自 `config/requirements.txt`，首次会自动安装并缓存）：

```powershell
docker exec n8n-super python3 -c "import requests; print('requests:', requests.__version__)"
```

### 2) Queue 模式（docker-compose.queue.yml）升级流程

#### 2.1 停止旧集群

```powershell
docker compose -f docker-compose.queue.yml down
```

#### 2.2 注入 COMMUNITY_NODES（可选）

```powershell
$env:COMMUNITY_NODES="n8n-nodes-python@0.1.4 n8n-nodes-xxx@1.2.3"
```

#### 2.3 构建 + 启动（强制重建）

```powershell
docker compose -f docker-compose.queue.yml build --no-cache
docker compose -f docker-compose.queue.yml up -d --force-recreate
```

#### 2.4 回归自测（Queue）

```powershell
curl.exe -fsS http://localhost:5678/healthz
docker exec n8n-web n8n --version
docker exec n8n-worker n8n --version
docker exec n8n-webhook n8n --version
```

如需更完整自测，可运行：

```bash
./scripts/test-queue.sh
```

## Python 包动态安装（启动时）

通过环境变量控制（在 `docker-compose.yml` 中设置后重启即可）：

- `N8N_PYTHON_PACKAGES`：要安装的 pip 包列表（空格分隔）
- `N8N_PYTHON_REQUIREMENTS_FILE`：requirements 文件路径（推荐挂载 `config/requirements.txt` 到容器内）
- `N8N_PYTHON_PIP_EXTRA_ARGS`：额外 pip 参数（例如私有源 `--index-url ...`）

示例：

```yaml
environment:
  N8N_PYTHON_PACKAGES: "requests==2.32.3 python-gitlab"
```

然后执行：

```powershell
docker compose up -d
```

## 企业 pip 源加速（环境变量）

你可以通过环境变量指定公司内部 pip 源（或镜像站），无需改镜像：

- `N8N_PIP_INDEX_URL`：等价于 `PIP_INDEX_URL`
- `N8N_PIP_EXTRA_INDEX_URL`：等价于 `PIP_EXTRA_INDEX_URL`
- `N8N_PIP_TRUSTED_HOST`：等价于 `PIP_TRUSTED_HOST`
- `N8N_PIP_DEFAULT_TIMEOUT`：等价于 `PIP_DEFAULT_TIMEOUT`

如果你更习惯用标准变量名，也可以直接设置 `PIP_INDEX_URL` 等，容器同样生效。

## PythonFunction 运行时自动安装依赖（推荐）

`n8n-nodes-python` 在执行代码时会调用 `python3`。本镜像在 venv 内对 `python3` 做了透明封装：

- 当 `N8N_PYTHON_AUTO_INSTALL=true` 时
- 若设置了 `N8N_PYTHON_PACKAGES` 或 `N8N_PYTHON_REQUIREMENTS_FILE`

则每次执行 Python 前会自动 `pip install`，并采用“**按依赖集合 hash 创建/复用独立 venv**”的方式实现隔离与缓存：

- 不同 workflow（不同 requirements/包列表/源参数）会落到不同 venv，避免互相污染
- 相同依赖集合复用同一个 venv，避免重复安装
- venv 缓存目录默认在 `/home/node/.n8n/pyenvs`（可配置）

示例（公司源 + 自动安装 requests）：

```yaml
environment:
  N8N_PIP_INDEX_URL: "https://pip.xxx.com/simple"
  N8N_PIP_TRUSTED_HOST: "pip.xxx.com"
  N8N_PYTHON_AUTO_INSTALL: "true"
  N8N_PYTHON_PACKAGES: "requests==2.32.3"
```

## n8n-super 启动配置文件（推荐）

由于容器级环境变量（如 pip 源、自动装包开关）通常不适合在 n8n UI 里直接修改，本项目支持在启动时加载一个配置文件，将所有“可自定义项”集中管理。

1) 在 `docker-compose.yml` 中挂载并指定：

```yaml
environment:
  N8N_SUPER_CONFIG_FILE: "/etc/n8n-super.env"
volumes:
  - ./config/n8n-super.env:/etc/n8n-super.env:ro
```

这样你只需要维护 `config/n8n-super.env`，不用频繁改 compose 或重打镜像。

### 多人/多工作流：独立 venv 缓存与清理（可选）

- `N8N_PYTHON_VENV_CACHE_DIR`
  - 独立 venv 缓存目录
  - 默认：`/home/node/.n8n/pyenvs`
- `N8N_PYTHON_VENV_CACHE_CLEANUP`
  - 是否在容器启动时清理旧缓存目录
  - 可选值：`true/false`
- `N8N_PYTHON_VENV_CACHE_TTL_DAYS`
  - 清理策略：删除缓存目录下 **mtime 超过 N 天** 的子目录
  - 仅当 `N8N_PYTHON_VENV_CACHE_CLEANUP=true` 时生效

## Shell / Execute Command 节点安全说明（重要）

n8n 默认会通过 `NODES_EXCLUDE` 禁用一些高危节点（例如 **Command**）。

本项目的 `docker-compose.yml` 里设置了：

- `NODES_EXCLUDE: "[]"`

这会**启用 Execute Command（Command）节点**，也就具备了在容器内执行任意命令的能力。

- 仅建议用于受控环境/内网/开发测试
- 生产环境务必结合权限、网络隔离、最小化暴露面等手段进行加固

## 关于数据卷与社区节点

## Queue 模式（生产推荐：Web + Worker + Webhook + Redis + Postgres）

当工作流规模达到几百、并发执行较高、或者需要更好的横向扩展能力时，建议使用 Queue 模式。

本项目提供了一个可直接运行的参考编排：`docker-compose.queue.yml`。

### 1) 启动（Linux/macOS）

```bash
chmod +x ./scripts/run.sh ./scripts/test.sh
./scripts/run.sh --queue
./scripts/test.sh --queue
```

### 2) 启动（Windows）

```powershell
.\windows\run.ps1 -Queue
.\windows\test.ps1 -Queue
```

### 3) 扩容 worker（示例）

```bash
docker compose -f docker-compose.queue.yml up -d --scale n8n-worker=3
```

## 后续上 K8s 的最优拆分建议（适配多服务/多副本）

建议按如下方式拆分，几乎可 1:1 迁移自 queue compose：

- **Postgres**
  - 生产建议使用云 RDS/自建高可用（StatefulSet 也可，但运维复杂）
- **Redis**
  - 生产建议使用 Redis 主从/哨兵或云 Redis
- **n8n-web（Deployment）**
  - 对外提供 UI/API
- **n8n-webhook（Deployment，可选）**
  - 专门承接 webhook 流量，便于独立扩容
- **n8n-worker（Deployment，可水平扩容）**
  - 执行任务的核心组件，建议基于队列长度/CPU/Mem 做 HPA
- **共享存储 /home/node/.n8n**
  - 至少需要持久化（PVC），否则 workflows/credentials 不可持久
  - 如果你做多副本，PVC 的访问模式需要评估（RWX/RWO）

关于“Python 独立 venv 缓存目录”：

- 默认在 `/home/node/.n8n/pyenvs`
- 生产建议用 PVC 持久化，避免每次重建 pod 重装依赖

`docker-compose.yml` 默认使用 **named volume** 挂载到 `/home/node/.n8n`。Docker 在首次创建该 volume 时会把镜像内已有的 `/home/node/.n8n` 内容初始化到 volume 中，因此：

- 预装的 `n8n-nodes-python` 会被保留
- n8n 配置与工作流也会持久化

如果你改成 **bind mount**（把宿主机目录直接挂进 `/home/node/.n8n`），首次启动时会覆盖镜像内内容，可能导致社区节点不在该目录下，需要你在容器内重新安装或手动复制。

## 如何扩展（强烈建议团队统一规范）

### 1) 新增 Python 包（推荐方式）

你有两种方式：

- **方式A（推荐，声明式）**：编辑 `config/requirements.txt`，然后重启容器。
- **方式B（临时）**：在 `config/n8n-super.env` 设置 `N8N_PYTHON_PACKAGES`（空格分隔），然后重启容器。

关键配置都写在 `config/n8n-super.env`：

- `N8N_PYTHON_AUTO_INSTALL="true"`
- `N8N_PYTHON_REQUIREMENTS_FILE="/home/node/.n8n/requirements.txt"`

#### 1.1 团队统一依赖（推荐生产）

- 你们把团队默认依赖放进 `config/requirements.txt`。
- 依赖建议固定版本（例如 `requests==2.32.3`），避免“今天能跑明天不能跑”。
- 使用 `docker-compose.yml` 里现成的挂载：`./config/requirements.txt:/home/node/.n8n/requirements.txt:ro`。
- `config/n8n-super.env` 中启用：
  - `N8N_PYTHON_AUTO_INSTALL="true"`
  - `N8N_PYTHON_REQUIREMENTS_FILE="/home/node/.n8n/requirements.txt"`

#### 1.2 个人临时加包（不影响团队默认依赖）

## Python 维护与装包策略（团队平台：强烈建议按此执行）

你们的目标是：

- **第一次构建镜像时**就把“团队常用包”装好（减少运行期下载/网络依赖）
- pip 源/代理是**长期固定**的，容器启动时自动注入（也允许关闭）
- 后续新增包尽量**不重建镜像**，避免发版/重建影响运行中的 workflows

### 1) 构建期预装：把常用包固化到基础 venv

本项目会在构建阶段把 `config/requirements.txt` 里的内容预装到基础 venv：

- 基础 venv 路径：`/opt/n8n-python-venv`
- 运行时独立 venv（hash）创建时使用 `--system-site-packages`，因此能“看见”基础 venv 里已安装的包。

效果：

- 大多数 workflows 常用包（例如 `requests`）**不会在运行时重复下载/安装**。
- 个别 workflow 需要特殊版本时，仍可在独立 venv 内覆盖安装，不会污染基础 venv。

构建一个“新版本镜像 tag”并预装常用包（推荐维护者执行）：

1) 更新 `config/requirements.txt`（团队常用包集合，建议固定版本）
2) 构建新镜像 tag（构建时会把 requirements 预装进基础 venv）

Windows 示例（使用固定 pip 源/代理构建期下载）：

```powershell
$env:PIP_INDEX_URL="https://pip.xxx.com/simple"
$env:PIP_TRUSTED_HOST="pip.xxx.com"
.\windows\build.ps1 -Tag "n8n-super:1.78.1-r1"
```

Linux/macOS 示例：

```bash
PIP_INDEX_URL="https://pip.xxx.com/simple" PIP_TRUSTED_HOST="pip.xxx.com" ./scripts/build.sh n8n-super:1.78.1-r1
```

### 2) 长期固定 pip 源/代理：默认自动注入，也可关闭

推荐把公司 pip 源/代理写在 `config/n8n-super.env`，由容器启动时自动注入：

- `N8N_PIP_INDEX_URL`
- `N8N_PIP_EXTRA_INDEX_URL`
- `N8N_PIP_TRUSTED_HOST`
- `N8N_PIP_DEFAULT_TIMEOUT`

该注入逻辑是“有值才注入”：

- 你设置了 `N8N_PIP_INDEX_URL` 才会映射到 `PIP_INDEX_URL`
- 如果你不想注入，把这些变量留空即可

### 3) 新增包的推荐流程：改 requirements -> 自动生成新 venv（不重建镜像）

当你们发现某些 workflows 需要新增 Python 包时，推荐流程是：

1) 在 `config/requirements.txt` 增加包并固定版本
2) 把更新后的 `requirements.txt` 通过 volume 挂载到容器内（本项目默认已挂载到 `/home/node/.n8n/requirements.txt`）
3) 重启容器或等待下一次 PythonFunction 执行

运行效果：

- `python3` wrapper 会基于 requirements 内容 hash 创建一个新的独立 venv 目录
- 旧的 venv 不会被覆盖（因此“历史依赖集合”仍然存在）

注意：

- requirements 变更会让“后续执行”落到新 venv，这是预期行为。
- 如果你们希望某个 workflow 长期绑定某套依赖，建议走 Execute Command 的“进程级注入”方式，或按业务域拆分实例。

如果某位同学临时需要一些包（例如 `pandas`），但不希望把它加入团队统一 requirements：

- 方式A：在自己的运行环境里（例如自己机器/自己 compose）设置：
  - `N8N_PYTHON_PACKAGES="pandas==<version>"`
- 方式B：不改 compose，把个人配置写到 **自己的** `n8n-super.env`（不要提交到 git），然后挂载。

注意：

- 不同同学的 `N8N_PYTHON_PACKAGES` 不会互相覆盖，因为最终落到不同 hash 的独立 venv。
- 如果你们共用同一个持久化卷 `/home/node/.n8n`，那么缓存目录默认也是共享的；共享缓存不等于互相污染（hash 隔离），但会占用空间，需要规划 TTL 清理策略。

### 2) 设置/更换 pip 源（公开/企业都适用）

在 `config/n8n-super.env` 中设置：

- `N8N_PIP_INDEX_URL`
- `N8N_PIP_TRUSTED_HOST`

### 3) 新增 n8n 社区节点（n8n-nodes-*）

社区节点是 npm 包，建议以“镜像构建时安装”的方式做可追踪版本管理。

#### 通过 Dockerfile 的 `ARG COMMUNITY_NODES` 批量安装（推荐）

`COMMUNITY_NODES` 是 **构建期参数（build arg）**，只能在构建镜像时注入：

- **方式A：docker build**

```bash
docker build \
  --build-arg COMMUNITY_NODES="n8n-nodes-python@<ver> n8n-nodes-xxx@1.2.3" \
  -t n8n-super:1.78.1 .
```

- **方式B：docker compose build（推荐团队协作）**

本项目已在 `docker-compose.yml` / `docker-compose.queue.yml` 的 `build.args` 中预留：

```yaml
build:
  context: .
  args:
    COMMUNITY_NODES: ${COMMUNITY_NODES:-n8n-nodes-python}
```

你可以：

- **直接在 compose 文件里写死**（团队统一）
- **用环境变量覆盖**（更灵活）
  - Linux/macOS:

    ```bash
    COMMUNITY_NODES="n8n-nodes-python@<ver> n8n-nodes-xxx@1.2.3" docker compose build
    ```

  - Windows PowerShell:

    ```powershell
    $env:COMMUNITY_NODES="n8n-nodes-python@<ver> n8n-nodes-xxx@1.2.3"
    docker compose build
    ```

注意：强烈建议固定版本（不要用 `latest`），保证可复现。

- **推荐做法**：修改 `Dockerfile` 中安装社区节点的 `npm install` 行，追加你要的包名，然后重新 `docker build`。
- **不推荐做法**：运行中的容器里手工 `npm install`（难审计、难复现、重建易丢失）。

安装位置：

- `/home/node/.n8n/nodes/node_modules`

### 4) 新增 CLI 工具（kubectl/helm/terraform 等）

推荐把工具安装写在 `Dockerfile`：

- 统一版本
- 统一校验（hash/版本）
- 统一镜像发布

然后在 n8n 中使用 **Execute Command** 节点调用这些工具。

## 团队协作：8 人共用一个“团队标准镜像”（推荐 SOP）

你们当前的目标是：**全员使用同一个镜像**，避免出现“每个人本地构建出来都不一样”的漂移。

### 1) 团队标准镜像的职责边界（建议统一口径）

- **镜像里固化的内容（需要重新 build + 发版）**
  - 系统工具/CLI（例如 `argocd` / `kubectl` / `helm`）
  - n8n 社区节点（npm 包，例如 `n8n-nodes-xxx`）
- **不建议固化到镜像、而是运行时配置的内容（仅修改配置文件/requirements）**
  - Python 包（通过 `N8N_PYTHON_REQUIREMENTS_FILE` / `N8N_PYTHON_PACKAGES`）
  - pip 源（`N8N_PIP_*` -> `PIP_*`）

这样做的好处是：

- 社区节点/CLI 变更可审计、可回滚（发版）
- Python 包需求变化频繁，走运行期安装 + hash 隔离更稳（不必频繁重打镜像）

### 2) 统一变更入口（8 人协作时必须明确）

- **Python 统一依赖**：只允许改 `config/requirements.txt`（建议固定版本）。
- **pip 源/自动装包策略**：只允许改 `config/n8n-super.env`。
- **社区节点（npm）**：只允许通过 `COMMUNITY_NODES`（构建期）或修改 `Dockerfile` 的安装行来变更，并固定版本。
- **镜像基础版本升级（n8n 版本）**：只允许维护者改 `Dockerfile` 的 `FROM n8nio/n8n:<version>` 并走完整回归测试。

### 3) 团队标准镜像的 tag 策略（建议）

建议用“可回滚”的 tag：

- `n8n-super:1.78.1-r1`
- `n8n-super:1.78.1-r2`

其中：

- `1.78.1` 对齐上游 n8n 版本
- `rN` 表示你们团队在该基础上的第 N 次发布

### 4) 团队镜像构建（统一方式，避免不一致）

你们可以统一由 1-2 个维护者负责 build+发版，其余同学只拉取使用。

#### 方式A：用 docker compose build（推荐本地验证）

- Windows PowerShell：

```powershell
$env:COMMUNITY_NODES="n8n-nodes-python@0.1.4"
docker compose -f docker-compose.yml build --no-cache
```

#### 方式B：用构建脚本 build（推荐做发版流水线/标准化）

说明：目前 `scripts/build.sh` 与 `windows/build.ps1` 已支持透传构建期参数：

- `COMMUNITY_NODES`
- `ARGOCD_VERSION`

Windows 示例：

```powershell
.\windows\build.ps1 -Tag "n8n-super:1.78.1-r1" -CommunityNodes "n8n-nodes-python@0.1.4" -ArgoCdVersion "v2.13.3"
```

Linux/macOS 示例：

```bash
COMMUNITY_NODES="n8n-nodes-python@0.1.4" ARGOCD_VERSION="v2.13.3" ./scripts/build.sh n8n-super:1.78.1-r1
```

### 5) 团队发布后的使用方式（推荐）

- **团队只用一个镜像 tag**：在 `docker-compose.yml` 里把 `image:` 固定到团队发布的 tag（例如 `n8n-super:1.78.1-r1`）。
- 其他同学只需要：
  - `docker compose pull`（如果你们推送到了镜像仓库）
  - `docker compose up -d --force-recreate`

### 6) 发版回归测试（强制执行）

- 单容器模式：
  - Linux/macOS：`./scripts/test.sh`
  - Windows：`.\windows\test.ps1`
- Queue 模式：
  - Linux/macOS：`./scripts/test.sh --queue`
  - Windows：`.\windows\test.ps1 -Queue`

## 后续：如何编写你自己的 Dockerfile（在 n8n-super 基础上扩展）

当你需要把某些能力固化到镜像里（离线环境、强审计、严格可复现），推荐用继承方式：

```dockerfile
FROM n8n-super:1.78.1

USER root

# 示例：安装额外系统工具（建议固定版本/校验）
RUN set -eux; \
  if command -v apt-get >/dev/null 2>&1; then \
    apt-get update && apt-get install -y --no-install-recommends \
      netcat-traditional \
    && rm -rf /var/lib/apt/lists/*; \
  elif command -v apk >/dev/null 2>&1; then \
    apk add --no-cache \
      netcat-openbsd \
    ; \
  else \
    echo "Unsupported base image" >&2; \
    exit 1; \
  fi

USER node
```

说明：

- “只需要加 Python 包”的需求，优先用运行期 hash 隔离安装（`N8N_PYTHON_PACKAGES` / requirements 文件），通常不需要写 Dockerfile。
- 你要固化到镜像里的东西，通常是：
  - 系统包/CLI 工具（kubectl/helm/terraform/企业自研二进制）
  - 社区节点（npm 包），且需要固定版本、可审计

## 推荐的团队落地规范（建议写进你们团队 SOP）

- **默认镜像**：由少数维护者维护（固定版本、回归测试、发布 tag）。
- **个人需求优先用运行期 Python hash 隔离**：用 `N8N_PYTHON_PACKAGES` 或个人 requirements 文件。
- **确需固化的东西才重打个人镜像**：统一 tag 命名规则，避免覆盖。
- **不要在运行中的容器里手工装依赖**：不可复现，重建易丢。
- **生产建议用 Queue 模式 + Postgres/Redis**：见 `docker-compose.queue.yml`。

## 生产使用建议

- **强烈建议启用认证与访问控制**：不要裸奔暴露到公网。
- **谨慎启用 Command 节点**：`NODES_EXCLUDE: "[]"` 会启用 `Command`（可执行任意命令）。
- **数据持久化与备份**：`/home/node/.n8n` 请做定期备份（workflows/credentials/配置）。
- **依赖供应链风险**：自动 `pip install` 本质会从外部源拉包，建议企业环境使用内网镜像源 + 版本锁定。

## 团队共用同一 n8n 实例（多 workflow、多维护人）的运维要点

你们的形态是：

- **同一个 n8n 实例里有很多 workflows**
- 不同 workflows 由不同人维护，部分 workflows 可能多人共管

这类“平台型 n8n”运维要点和个人自测完全不同，建议至少做到以下几条：

### 0) Workflow 治理规范（建议团队统一，否则会迅速失控）

- **命名规范**：建议按业务域/项目/用途分层，例如：`ops/backup/postgres-daily`、`data/etl/user-sync`。
- **Tag/归属**（n8n UI 支持 workflow tags）：
  - `owner:<name>`（主维护人）
  - `team:<name>`（归属团队）
  - `env:prod|staging|dev`（运行环境）
  - `tier:critical|normal`（重要程度）
- **变更流程**：
  - 关键 workflows（`tier:critical`）必须走评审（至少 1 人 review）。
  - 禁止在生产实例上“随手改完就走”，至少要求变更备注（改了什么、为什么、回滚点）。
- **凭据（Credentials）管理**：
  - 凭据尽量按“系统/业务域”拆分，不要所有 workflows 共用一个万能账号。
  - 变更凭据要有影响面评估：哪些 workflows 依赖这个 credential。
  - 生产环境建议接入更强的密钥管理（后续 K8s 可用 Secret/外部密钥系统）。

### 1) 强制固定加密密钥（否则重建/迁移会出事故）

n8n 的 credentials 是加密存储的。多人共用实例时，必须固定 `N8N_ENCRYPTION_KEY`（或者你们当前版本对应的加密 key 环境变量），否则：

- 容器重建/迁移后可能无法解密历史 credentials

建议做法：

- 单机/compose：把 key 固定写在 `config/n8n-super.env`（或单独的 secret 文件），并确保所有副本一致。
- K8s：用 Secret 管理，并注入到所有 n8n 组件（web/worker/webhook）。

### 2) 推荐默认形态：Queue + Postgres + Redis

多人共用、workflow 数量上来后，不建议长期使用 SQLite 单实例形态。

- 生产推荐：`docker-compose.queue.yml`（web/worker/webhook + postgres + redis）
- 后续上 K8s 基本可 1:1 迁移为 Deployment/StatefulSet

### 3) 备份/恢复的“最小集合”

- **如果你用 SQLite 单容器模式**：核心是 `/home/node/.n8n`（包含 SQLite DB、workflows、credentials 等）
- **如果你用 Postgres（推荐）**：
  - 备份 Postgres 数据库（RDS/自建都要有备份策略）
  - `/home/node/.n8n` 仍要持久化（至少包含部分运行时数据与自定义目录）

### 4) 团队升级/回滚的推荐命令（避免“镜像更新了但容器没换”）

本仓库脚本已支持 `--pull` 与 `--force-recreate`：

- Linux/macOS（单容器）：

```bash
./scripts/run.sh --pull --force-recreate
```

- Linux/macOS（Queue）：

```bash
./scripts/run.sh --queue --pull --force-recreate
```

- Windows（单容器）：

```powershell
.\windows\run.ps1 -Pull -ForceRecreate
```

- Windows（Queue）：

```powershell
.\windows\run.ps1 -Queue -Pull -ForceRecreate
```

### 5) Python 依赖：按 workflow 定制的现实限制与可行方案

你们常见诉求是：不同 workflows 需要不同 Python 包。

本镜像的 `python3` wrapper 能做到“**按依赖集合 hash 创建独立 venv 缓存**”，但前提是：**运行该 Python 进程时能指定 requirements/packages**。

需要明确的一点：

- **PythonFunction（n8n-nodes-python）节点执行 Python 时，环境变量来自容器/进程环境**。
- 也就是说：如果你们希望“不同 workflow 用不同 requirements 文件”，仅靠 UI 直接切换 `N8N_PYTHON_REQUIREMENTS_FILE` 做不到（它是容器级变量，不是 workflow 级变量）。

推荐的落地方案（按优先级）：

- **方案A（团队推荐）**：统一维护一份团队级 `config/requirements.txt`
  - 覆盖 80% 场景，最稳定、最可控。
- **方案B（确需隔离且依赖差异大）**：用 **Execute Command** 节点执行 Python
  - 在命令里为该进程注入 `N8N_PYTHON_PACKAGES` / `N8N_PYTHON_REQUIREMENTS_FILE`，实现“每个 workflow 自己决定依赖集合”。
  - 这种方式依赖 Command 节点能力，注意安全隔离与权限。
- **方案C（长期演进）**：按业务域拆分多个 n8n 实例（或多 namespace/多 release）
  - 当 workflows 数量、依赖差异、权限边界变得复杂时，这是最清晰的治理方式。

## FAQ / 排障

### A) 容器反复重启

```bash
docker logs --tail 200 n8n-super
```

常见原因：

- `config/n8n-super.env` 行尾是 CRLF/BOM 或者格式不规范（本项目已做清理兼容，但仍建议用 UTF-8 + LF）

### B) Python 自动安装不生效

检查：

- `config/n8n-super.env` 中 `N8N_PYTHON_AUTO_INSTALL="true"`
- `config/requirements.txt` 已挂载到容器：`/home/node/.n8n/requirements.txt`

验证：

```bash
docker exec n8n-super python3 -c "import requests; print(requests.__version__)"
```

### C) 社区节点在 UI 里搜不到

排查：

- 确认容器目录存在：`/home/node/.n8n/nodes/node_modules`
- 看启动日志里是否有 community packages 相关报错
