# n8n-super（基于 n8nio/n8n:1.78.1 的增强镜像）

## 目标

在 `n8nio/n8n:1.78.1` 官方镜像基础上增强：

- **Python 节点**：预装社区节点 `n8n-nodes-python`（提供 `PythonFunction` 节点）
- **Python 运行环境**：内置 Python3 + venv（`/opt/n8n-python-venv`），并支持容器启动时按环境变量自动 `pip install`
- **Shell 能力**：通过内置的 **Execute Command（Command）节点** 执行 shell（需解除默认禁用，见下文安全说明）
- **ArgoCD**：预装 `argocd` CLI，可在工作流里用 Execute Command 节点调用
- **Jenkins / GitLab**：n8n 内置节点（无需额外安装）

## 目录结构

- `Dockerfile`：镜像构建文件
- `docker-compose.yml`：运行编排（端口、数据卷、健康检查、配置注入）
- `docker-entrypoint-extra.sh`：启动入口（加载配置文件/环境变量后转交官方 `/docker-entrypoint.sh`）
- `n8n-super.env`：启动配置注入文件（pip 源、自动装包开关、依赖文件路径等）
- `requirements.txt`：Python 依赖示例（可替换为你的依赖集合）
- `n8n-python3-wrapper.sh`：venv 内 `python3` wrapper（实现运行前按需 `pip install`）
- `build.ps1` / `run.ps1` / `test.ps1`：Windows (PowerShell) 构建、运行、验证脚本
- `build.sh` / `run.sh` / `test.sh`：Linux/macOS Shell 脚本用法

## 快速开始（Linux 推荐）

### 0) 前置条件

- Docker Engine
- Docker Compose v2（`docker compose version`）

### 1) 构建镜像

```bash
chmod +x ./build.sh ./run.sh ./test.sh
./build.sh
```

### 2) 启动

```bash
./run.sh
```

### 3) 健康检查

```bash
curl -fsS http://localhost:5678/healthz
```

### 4) 验证“Python 自动装包”是否生效

```bash
./test.sh
docker exec n8n-super python3 -c "import requests; print('requests:', requests.__version__)"
```

### 5) 打开 Web UI

- `http://localhost:5678/`

## 快速开始（Windows PowerShell）

### 1) 构建镜像（Windows）

```powershell
cd d:\job-test\n8n-best\n8n-super
.\build.ps1
```

### 2) 运行（Windows）

```powershell
.\run.ps1
```

访问：

- Web UI：`http://localhost:5678/`
- 健康检查：`http://localhost:5678/healthz`

### 3) 验证（Windows）

```powershell
.\test.ps1
```

验证内容包括：

- `/healthz` 可用
- `n8n --version` 输出版本
- `argocd version --client` 可执行
- venv 内 `python-fire` 可导入
- `n8n-nodes-python` 包存在

## Python 包动态安装（启动时）

通过环境变量控制（在 `docker-compose.yml` 中设置后重启即可）：

- `N8N_PYTHON_PACKAGES`：要安装的 pip 包列表（空格分隔）
- `N8N_PYTHON_REQUIREMENTS_FILE`：requirements.txt 路径
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

则每次执行 Python 前会自动 `pip install`，并用 **lock + stamp** 避免每次重复安装。

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

1) 复制示例文件：`n8n-super.env.example` -> `n8n-super.env`

2) 在 `docker-compose.yml` 中挂载并指定：

```yaml
environment:
  N8N_SUPER_CONFIG_FILE: "/etc/n8n-super.env"
volumes:
  - ./n8n-super.env:/etc/n8n-super.env:ro
```

这样你只需要维护 `n8n-super.env`，不用频繁改 compose 或重打镜像。

## Shell / Execute Command 节点安全说明（重要）

n8n 默认会通过 `NODES_EXCLUDE` 禁用一些高危节点（例如 **Command**）。

本项目的 `docker-compose.yml` 里设置了：

- `NODES_EXCLUDE: "[]"`

这会**启用 Execute Command（Command）节点**，也就具备了在容器内执行任意命令的能力。

- 仅建议用于受控环境/内网/开发测试
- 生产环境务必结合权限、网络隔离、最小化暴露面等手段进行加固

## 关于数据卷与社区节点

`docker-compose.yml` 默认使用 **named volume** 挂载到 `/home/node/.n8n`。Docker 在首次创建该 volume 时会把镜像内已有的 `/home/node/.n8n` 内容初始化到 volume 中，因此：

- 预装的 `n8n-nodes-python` 会被保留
- n8n 配置与工作流也会持久化

如果你改成 **bind mount**（把宿主机目录直接挂进 `/home/node/.n8n`），首次启动时会覆盖镜像内内容，可能导致社区节点不在该目录下，需要你在容器内重新安装或手动复制。

## 如何扩展（强烈建议团队统一规范）

### 1) 新增 Python 包（推荐方式）

你有两种方式：

- **方式A（推荐，声明式）**：编辑 `requirements.txt`，然后重启容器。
- **方式B（临时）**：在 `n8n-super.env` 设置 `N8N_PYTHON_PACKAGES`（空格分隔），然后重启容器。

关键配置都写在 `n8n-super.env`：

- `N8N_PYTHON_AUTO_INSTALL="true"`
- `N8N_PYTHON_REQUIREMENTS_FILE="/home/node/.n8n/requirements.txt"`

### 2) 设置/更换 pip 源（公开/企业都适用）

在 `n8n-super.env` 中设置：

- `N8N_PIP_INDEX_URL`
- `N8N_PIP_TRUSTED_HOST`

本项目默认使用清华 TUNA：

- `https://pypi.tuna.tsinghua.edu.cn/simple`

### 3) 新增 n8n 社区节点（n8n-nodes-*）

社区节点是 npm 包，建议以“镜像构建时安装”的方式做可追踪版本管理。

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

## 生产使用建议

- **强烈建议启用认证与访问控制**：不要裸奔暴露到公网。
- **谨慎启用 Command 节点**：`NODES_EXCLUDE: "[]"` 会启用 `Command`（可执行任意命令）。
- **数据持久化与备份**：`/home/node/.n8n` 请做定期备份（workflows/credentials/配置）。
- **依赖供应链风险**：自动 `pip install` 本质会从外部源拉包，建议企业环境使用内网镜像源 + 版本锁定。

## FAQ / 排障

### A) 容器反复重启

```bash
docker logs --tail 200 n8n-super
```

常见原因：

- `n8n-super.env` 行尾是 CRLF/BOM 或者格式不规范（本项目已做清理兼容，但仍建议用 UTF-8 + LF）

### B) Python 自动安装不生效

检查：

- `n8n-super.env` 中 `N8N_PYTHON_AUTO_INSTALL="true"`
- `requirements.txt` 已挂载到容器：`/home/node/.n8n/requirements.txt`

验证：

```bash
docker exec n8n-super python3 -c "import requests; print(requests.__version__)"
```

### C) 社区节点在 UI 里搜不到

排查：

- 确认容器目录存在：`/home/node/.n8n/nodes/node_modules`
- 看启动日志里是否有 community packages 相关报错
