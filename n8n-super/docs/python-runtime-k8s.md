# n8n-super 在 K8s（Helm n8n-code）下的 Python 运行时、pip 源与持久化指南

适用场景：使用现成的 `n8n-super` 镜像（无需重打镜像），通过 `n8n-code` Helm Chart 部署到 K8s，要求：

- Python 包运行时自动安装，可持久化复用。
- 多副本/滚动升级后 venv 不丢失。
- 可配置内网/自定义 pip 源。
- 保持 hash 隔离的 venv 机制。

---

## 0. 工作流工具选型终极速查卡（1 页）

> 如果不看长篇大论，只看这一节，足够向团队说明 n8n / Airflow 等工具的本质区别和选型逻辑。
> 更完整的对比见：`docs/workflow-tooling-comparison.md`。

### 0.1 核心定位：一句话讲透

- **n8n：神经系统（Signal / 流程自动化）**  
  事件驱动（Webhook/告警/表单/IM），处理小 JSON/消息，追求实时响应；更像“交通指挥员”。  
- **Airflow：循环系统（Data / 批处理编排）**  
  时间驱动（Schedule），处理数据集/表/文件/计算，追求稳定与吞吐；更像“重型货运火车”。  
- **Argo Workflows：K8s 容器作业编排引擎**  
  每一步一个容器/Pod，擅长并行 Job、批处理、K8s 上的 pipeline。  
- **Temporal：可恢复的长流程引擎（Durable Execution）**  
  用 SDK 写“业务流程/长事务”，可等待外部事件、故障可恢复，适合复杂可靠编排。  
- **Prefect / Dagster：Python 数据编排（偏数据工程）**  
  类 Airflow 的数据/批任务编排，但更偏 Python 开发体验与数据资产/血缘治理。  
- **Jenkins Pipeline / GitHub Actions：CI/CD 流水线**  
  构建、测试、发布、部署的“传送带”，不建议当通用运维编排平台。  
- **Rundeck / StackStorm：Runbook 自助与事件自动化**  
  把脚本/工具变成可授权的自助操作，或用事件规则做自动修复/ChatOps。

### 0.2 SRE 选型指令（If-Then）

- **如果是“发消息、调接口、搞审批、告警富化、跨系统胶水”**：用 `n8n`
- **如果是“定时跑批、同步全量数据、清洗计算、报表生成、回填重跑”**：用 `Airflow`（或 Prefect/Dagster）
- **如果是“K8s 上并行容器 Job/一次性工具/计算密集任务”**：用 `Argo Workflows`
- **如果是“微服务长流程/需要可靠恢复/可能跑很久并等待外部事件”**：用 `Temporal`
- **如果是“构建-测试-发布-部署”**：用 `Jenkins Pipeline` / `GitHub Actions`
- **如果是“运维脚本自助执行 + 权限 + 审计/或事件驱动自动化修复”**：用 `Rundeck` / `StackStorm`

### 0.3 一句话总结（给团队）

> **轻活急活（消息/API/审批/告警）走 n8n；重活慢活（数据/跑批/报表）走 Airflow；容器并行走 Argo；长事务可靠流程走 Temporal；交付流水线走 Jenkins/GitHub Actions；运维自助/自动修复走 Rundeck/StackStorm。**

---

## 1. 关键机制速览（镜像内置，无需改动）

- **python3 调用路径**：`/opt/n8n-python-venv/bin/python3` 被替换为 `n8n-python3-wrapper.sh`。
- **hash venv 缓存目录**：`N8N_PYTHON_VENV_CACHE_DIR`，默认 `/home/node/.n8n/pyenvs`。每套依赖 + pip 源参数生成一个签名目录 `<sig>`，内含独立 venv。
- **自动安装开关**：`N8N_PYTHON_AUTO_INSTALL`（默认 true）。PythonFunction / Execute Command 触发时自动 `pip install` 进入对应 hash venv。
- **依赖来源**：
  - `N8N_PYTHON_REQUIREMENTS_FILE`（默认 `/home/node/.n8n/requirements.txt`）
  - `N8N_PYTHON_PACKAGES`（逗号或空格分隔）
  - `N8N_PYTHON_PIP_EXTRA_ARGS`（传给 pip）
- **pip 源环境变量（entrypoint 会填充 PIP_*）**：
  - `N8N_PIP_INDEX_URL` / `N8N_PIP_EXTRA_INDEX_URL`
  - `N8N_PIP_TRUSTED_HOST`
  - `N8N_PIP_DEFAULT_TIMEOUT`
- **清理策略（可选）**：`N8N_PYTHON_VENV_CACHE_CLEANUP` + `N8N_PYTHON_VENV_CACHE_TTL_DAYS` 按 TTL 清理旧 venv。

> 重要：当前 wrapper 使用 `pip install --no-cache-dir`。若想复用 pip 下载缓存，需用 `N8N_PYTHON_PIP_EXTRA_ARGS="--cache-dir=..."` 追加缓存目录，但 pip 对 `--no-cache-dir` 的覆盖需自行验证；否则只持久化 venv 即可。

---

## 2. 不重打镜像的持久化思路

1) **venv 缓存持久化（必选）**  
   只要将 `/home/node/.n8n` 挂载到 PVC，`/home/node/.n8n/pyenvs` 就随之持久化。

2) **多副本注意**  
   - `main` 通常单副本：`ReadWriteOnce` OK。  
   - `worker` 多副本 + RWO：Helm 会自动用 StatefulSet + `volumeClaimTemplates`，每个 worker 一块盘，避免 RWO 冲突。  
   - `webhook` 如走 `queue` 模式多副本，同理建议每副本一块盘或使用 RWX（如 NFS/CephFS）。

3) **pip 下载缓存（可选）**  
   - 推荐先只持久化 venv，简单稳妥。  
   - 若要尝试缓存：设置 `N8N_PYTHON_PIP_EXTRA_ARGS="--cache-dir=/home/node/.cache/pip"`，并持久化 `/home/node/.cache/pip`。

---

## 3. Helm values 示例（最小可用，按需覆盖）

> 适用于 `n8n-code` Chart。复制到你的自定义 values 覆盖文件。

```yaml
image:
  # 生产建议：这里填写你们实际推送的 n8n-super 镜像仓库
  repository: nexus2.ipa.zs:5000/n8n-super
  tag: "1.78.1"
  pullPolicy: IfNotPresent

imagePullSecrets: []

serviceAccount:
  create: true
  automount: true
  annotations: {}

service:
  enabled: true
  type: ClusterIP
  port: 5678

log:
  level: info
  output:
    - console

timezone: "Asia/Shanghai"

extraEnvVars:
  TZ: "Asia/Shanghai"
  GENERIC_TIMEZONE: "Asia/Shanghai"

  # n8n 基础配置（示例：按你们域名/协议改）
  N8N_TRUST_PROXY: "true"
  N8N_PROTOCOL: "http"
  N8N_HOST: "n8n-it.saturn-res.ipa.zs"
  N8N_PUSH_BACKEND: "websocket"
  N8N_COMMUNITY_PACKAGES_ENABLED: "false"
  EXECUTIONS_MODE: "queue"

  # n8n-super：Python wrapper 行为（无需重打镜像）
  N8N_PYTHON_AUTO_INSTALL: "true"
  N8N_PYTHON_REQUIREMENTS_FILE: "/home/node/.n8n/requirements.txt"
  N8N_PYTHON_VENV_CACHE_DIR: "/home/node/.n8n/pyenvs"
  N8N_PYTHON_VENV_CACHE_CLEANUP: "false"
  # N8N_PYTHON_VENV_CACHE_TTL_DAYS: "30"  # 如需启用 TTL 清理可设置

  # n8n-super：pip 源（生产建议走内网镜像源）
  N8N_PIP_INDEX_URL: "https://your-pypi-mirror/simple"
  N8N_PIP_TRUSTED_HOST: "your-pypi-mirror"
  N8N_PIP_DEFAULT_TIMEOUT: "30"
  # N8N_PIP_EXTRA_INDEX_URL: ""

diagnostics:
  enabled: false

versionNotifications:
  enabled: false

db:
  type: postgresdb
  postgresdb:
    schema: public
    ssl:
      enabled: false

main:
  count: 1
  editorBaseUrl: "http://n8n-it.saturn-res.ipa.zs"
  resources:
    requests:
      cpu: "2"
      memory: 2Gi
    limits:
      cpu: "4"
      memory: 4Gi

  # /home/node/.n8n（同时包含 n8n-super 的 pyenvs venv 缓存目录）
  persistence:
    enabled: true
    storageClass: it
    accessMode: ReadWriteOnce
    size: 8Gi
    annotations: {}

worker:
  mode: queue
  count: 10
  resources:
    requests:
      cpu: "1"
      memory: 2Gi
    limits:
      cpu: "2"
      memory: 4Gi

  # 共享盘模式（所有 worker 共享同一个 PVC）：
  # - 前置条件：storageClass=it 必须支持 ReadWriteMany (RWX)
  # - 该 chart 在 accessMode=ReadWriteMany 时会走 Deployment，并让所有 worker 复用同一个 PVC
  persistence:
    enabled: true
    storageClass: it
    accessMode: ReadWriteMany
    size: 8Gi
    annotations: {}

webhook:
  mode: queue
  count: 2
  url: "http://n8n-it.saturn-res.ipa.zs/"
  resources:
    requests:
      cpu: "500m"
      memory: 1Gi
    limits:
      cpu: "1"
      memory: 2Gi

  persistence:
    enabled: true
    storageClass: it
    accessMode: ReadWriteOnce
    size: 8Gi
    annotations: {}

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-http-version: "1.1"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
  hosts:
    - host: n8n-it.saturn-res.ipa.zs
      paths:
        - path: /
          pathType: Prefix
  tls: []

redis:
  enabled: true
  architecture: standalone
  auth:
    enabled: true
    password: "redis"
  master:
    service:
      ports:
        redis: 6379
    resources:
      requests:
        cpu: "200m"
        memory: 512Mi
      limits:
        cpu: "1"
        memory: 1Gi
    persistence:
      enabled: true
      storageClass: it
      size: 4Gi

postgresql:
  enabled: true
  architecture: standalone
  auth:
    username: ""
    password: postgres
    database: n8n
  primary:
    service:
      ports:
        postgresql: 5432
    resources:
      requests:
        cpu: "500m"
        memory: 1Gi
      limits:
        cpu: "2"
        memory: 4Gi
    persistence:
      enabled: true
      storageClass: it
      size: 20Gi

externalRedis:
  host: ""

externalPostgresql:
  host: ""
```

### （可选）挂载 pip.conf（集中管控）
先在集群创建 ConfigMap `pip-conf`（含 key `pip.conf`），再在 values 增加：

```yaml
main:
  volumes:
    - name: pip-conf
      configMap:
        name: pip-conf
  volumeMounts:
    - name: pip-conf
      mountPath: /etc/pip.conf
      subPath: pip.conf
      readOnly: true

worker:
  volumes:
    - name: pip-conf
      configMap:
        name: pip-conf
  volumeMounts:
    - name: pip-conf
      mountPath: /etc/pip.conf
      subPath: pip.conf
      readOnly: true

webhook:
  volumes:
    - name: pip-conf
      configMap:
        name: pip-conf
  volumeMounts:
    - name: pip-conf
      mountPath: /etc/pip.conf
      subPath: pip.conf
      readOnly: true
```

---

## 4. pip 源优先级与安全

优先级（高→低）：容器内已有 `PIP_*` > `N8N_PIP_*` > `pip.conf` > pip 默认源。  
安全建议：

- 优先 https 源，减少 `trusted-host`。
- 若必须 http 内网源，仅信任特定域名，不要用通配。
- 若源带鉴权，放 Secret + `extraSecretNamesForEnvFrom` 注入，不要明文写 values。

---

## 5. 验证步骤

1) **确认 env**  
   `env | grep -E 'N8N_PIP_|PIP_|N8N_PYTHON_'`
2) **触发一次 PythonFunction**（含依赖），检查 venv：  
   `ls -lah /home/node/.n8n/pyenvs`，应出现新的 `<sig>` 目录。
3) **重启/滚动升级后复查**  
   目录仍在即持久化生效。
4) **多副本**  
   - StatefulSet worker：每个 Pod 有自己的 PVC。  
   - 若改用 RWX 共享盘，需确保底层存储支持并发写（NFS/CephFS）。
5) **pip 源生效**  
   查看 `PIP_INDEX_URL`，或执行一次 `pip install -v <pkg>` 观察源地址。
6) **（可选）pip 缓存**  
   若启用 `--cache-dir`，检查 `/home/node/.cache/pip` 是否生成文件；若未生效则保持默认（只持久化 venv）。

---

## 6. 常见问题

- **为什么还会重新下载？**  
  首次出现新依赖组合会生成新 venv；同一组合复用已有 venv，不会重复安装。
- **pip 缓存复用不了？**  
  由于 wrapper 带 `--no-cache-dir`，`N8N_PYTHON_PIP_EXTRA_ARGS` 可能被覆盖，请按第 5.6 步验证；不行就只持久化 venv。
- **webhook 是否要开持久化？**  
  `regular` 模式复用 main；`queue` 模式有独立 Pod，建议也开。
- **可否清理旧 venv？**  
  设置 `N8N_PYTHON_VENV_CACHE_CLEANUP=true` 和 `N8N_PYTHON_VENV_CACHE_TTL_DAYS`，由 entrypoint 定期清理。

---

## 7. 落地步骤快速表

1) 准备自定义 values 覆盖文件（参考第 3 节）。  
2) `helm upgrade --install ... -f your-values.yaml`。  
3) 触发一次 PythonFunction，确认 `/home/node/.n8n/pyenvs/<sig>` 生成。  
4) 重启/升级后确认 venv 仍在。  
5) 如需集中管控 pip 源，创建 `pip-conf` ConfigMap 并挂载 `/etc/pip.conf`。  

完成后，Python 包无需重打镜像即可持久化复用，hash venv 确保隔离。
