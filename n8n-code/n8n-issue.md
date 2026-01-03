# n8n 在阿里云 ECS（Docker）“离线/禁出网”部署调研与排查报告

## 0. 参考资料与可复用点（n9e 事件收集/入库）

### 0.1 n8n 自托管与源码
- 项目地址：
  - https://github.com/n8n-io/n8n.git
- 说明：
  - n8n 支持自托管（Docker/K8s/裸机均可）。
  - 生产建议固定版本（不要长期使用 `latest`），并对配置/数据库/加密密钥做可控管理。

### 0.2 事件自动响应工作流参考（Alertmanager/Incident Response）
- 文章：Alertmanager incident response automation with n8n
  - https://touilleio.medium.com/alertmanager-incident-response-automation-with-n8n-c61227e196e9
- 可复用点（迁移到 n9e 时建议保留的设计）：
  - **Webhook 接收**：统一入口（HTTP Trigger/Webhook）。
  - **事件标准化**：将告警/事件转换为统一 schema（标题、级别、标签、实例、发生时间、指纹等）。
  - **幂等/去重**：同一事件指纹在窗口内只入库/只触发一次。
  - **审计**：每次处理写入审计表（原始 payload、标准化字段、处理状态、耗时）。
  - **失败重试**：数据库/HTTP 调用失败要可重试并可追踪。

### 0.3 n8n 官方模板参考（Jira/Slack/表格等）
- 模板：Automate incident response with Jira, Slack, Google Sheets and Drive
  - https://n8n.io/workflows/9826-automate-incident-response-with-jira-slack-google-sheets-and-drive/
- 可复用点：
  - **工单/通知联动** 的流程编排思路（事件->创建工单->通知->落表->回写状态）。
  - 可以把 “写 Google Sheets” 替换为 “写 PostgreSQL/MySQL”。

### 0.4 n8n 官方/社区：创建自定义事件响应工作流
- 文章：Creating custom incident response workflows with n8n
  - https://medium.com/n8n-io/creating-custom-incident-response-workflows-with-n8n-9baef0bbedb9
- 可复用点：
  - 将响应动作拆成可复用的子流程（通知、抑制、变更执行、回滚、复盘信息收集）。

### 0.5 本次目标：仅做 n9e 事件“收集并入库”
本阶段不做自动修复/部署/审批闭环，仅完成：

- n9e webhook（或事件接口）接入
- 事件标准化
- 事件入库（PostgreSQL/MySQL 均可）
- 幂等去重 + 状态机（received/inserted/duplicate/error）

建议事件标准化后的最小字段：

- `event_source`：固定为 `n9e`
- `event_id`：来自 n9e 的事件 ID（若有）
- `fingerprint`：用于幂等去重（可由标签+告警规则+对象+时间窗口计算）
- `severity`：P0/P1/P2 或 critical/warn/info
- `title`：事件标题
- `labels`：结构化标签（JSON）
- `annotations`：补充信息（JSON）
- `starts_at` / `ends_at`
- `raw_payload`：原始 payload（JSON，审计用途）
- `received_at`：接收时间

入库策略建议：

- **唯一键**：`fingerprint`（或 `event_id`）+ 时间窗口
- **写入模式**：`INSERT ... ON CONFLICT DO NOTHING`（PostgreSQL）或 `INSERT IGNORE`/`ON DUPLICATE KEY UPDATE`（MySQL）
- **审计表**：无论是否重复，都写一条处理记录（便于追踪告警风暴时的行为）

## 1. 背景与目标

### 1.1 背景
在阿里云 ECS 上以 Docker 方式运行 n8n，期望：

- 对外（公网）可访问 n8n Web（管理界面、Webhook 接收等）。
- 对内（容器自身）**严格禁止任何外联（egress）**，杜绝容器主动下载外部内容/访问公网/访问外部 DNS 的可能性。
- 以“单个 n8n 容器”进行离线模拟验证（不接入既有 postgres，该 postgres 归其它服务使用）。

### 1.2 目标（验收标准）
- **镜像层面**：启动阶段不拉取镜像（避免启动时下载）。
- **网络层面**：容器无法向外发起连接（HTTP/HTTPS/DNS 等均不应成功）。
- **可访问性**：宿主机本机 `127.0.0.1:5678` 能访问 n8n；外部访问能力由云侧安全组/防火墙单独控制，不应被 egress 规则影响。
- **证据链**：提供可审计证据（iptables 规则、计数器、出网失败验证输出）。


## 2. 环境信息（已确认事实）

### 2.1 Docker 默认 bridge 网段
```bash
docker network inspect bridge --format '{{(index .IPAM.Config 0).Subnet}}'
```
输出（已确认）：

- `172.17.0.0/16`

### 2.2 镜像已在本机
```bash
docker images
```
输出（已确认）：

- `docker.n8n.io/n8nio/n8n:latest`（已存在于宿主机镜像缓存）
- `postgres:16.3`（其它服务使用，不纳入本次 n8n 离线验证范围）


## 3. 方案设计与关键点

### 3.1 为什么用 `iptables DOCKER-USER`
Docker 会自动维护 NAT/转发规则。`DOCKER-USER` 链是 Docker 官方推荐的可控入口链：

- 适合对“容器转发流量”做统一拦截。
- 不会被 Docker 频繁重写（相比直接改 DOCKER / FORWARD 更稳）。

本方案通过在 `DOCKER-USER` 对 **n8n 专用网段** 进行 egress `DROP`，从网络层硬性阻断容器对外连接。

### 3.2 “公网可访问”与“容器不能出网”不冲突
- 公网访问 n8n：属于 **外部 -> 宿主机 -> 容器** 的入站转发流量。
- 容器出网下载：属于 **容器 -> 外部** 的出站转发流量。

本方案保留：

- `ESTABLISHED,RELATED` 返回流量（保证入站连接的返回包正常发回）。

因此：

- 禁出网不会影响你从外部访问 n8n（只要云侧安全组/防火墙放行对应端口）。


## 4. 实施过程（可复现步骤）

### 4.1 创建 n8n 专用网络（避免影响其它业务容器网段）
```bash
docker network create \
  --driver bridge \
  --subnet 172.31.0.0/16 \
  --gateway 172.31.0.1 \
  n8n-net

docker network inspect n8n-net --format '{{(index .IPAM.Config 0).Subnet}} {{(index .IPAM.Config 0).Gateway}}'
```
输出（已确认）：

- `172.31.0.0/16 172.31.0.1`

### 4.2 启动前下发禁出网规则（最关键：防止容器启动后立刻外联）
```bash
N8N_SUBNET="172.31.0.0/16"

iptables -I DOCKER-USER 1 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -I DOCKER-USER 2 -s ${N8N_SUBNET} -d ${N8N_SUBNET} -j RETURN
iptables -I DOCKER-USER 3 -s ${N8N_SUBNET} -j DROP

iptables -L DOCKER-USER -n --line-numbers
iptables -S DOCKER-USER
```
规则输出（已确认）：

```text
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -s 172.31.0.0/16 -d 172.31.0.0/16 -j RETURN
-A DOCKER-USER -s 172.31.0.0/16 -j DROP
-A DOCKER-USER -j RETURN
```

### 4.3 启动 n8n（单容器、sqlite、禁止启动时拉镜像）
启动关键点：

- `--pull=never`：启动时绝不拉取镜像层。
- `--network n8n-net`：将容器置于 172.31.0.0/16 专用网段。
- `-p 5678:5678`：对宿主机发布端口（入站访问）。
- 关闭诊断/版本通知等非必要功能（减少不必要外联尝试）。

命令示例：

```bash
docker rm -f n8n 2>/dev/null || true

docker run -d --name n8n --restart unless-stopped --pull=never --network n8n-net -p 5678:5678 \
  -e N8N_HOST="0.0.0.0" \
  -e N8N_PORT="5678" \
  -e N8N_PROTOCOL="http" \
  -e N8N_TRUST_PROXY="true" \
  -e N8N_DIAGNOSTICS_ENABLED="false" \
  -e N8N_VERSION_NOTIFICATIONS_ENABLED="false" \
  -e N8N_HIRING_BANNER_ENABLED="false" \
  -e EXTERNAL_FRONTEND_HOOKS_URLS="" \
  -e N8N_TEMPLATES_ENABLED="false" \
  -e GENERIC_TIMEZONE="Asia/Shanghai" \
  docker.n8n.io/n8nio/n8n:latest
```


## 5. 验证与证据链（核心）

### 5.1 容器出网失败验证（功能性证据）
在容器内尝试访问外网：

```bash
docker exec -it n8n sh -lc 'wget -T 3 -O- https://www.baidu.com >/dev/null 2>&1 && echo "UNEXPECTED: allowed" || echo "OK: blocked"'
```
输出（已确认）：

- `OK: blocked`

含义：容器无法建立 HTTPS 对外连接。


### 5.2 本机访问 n8n 服务正常（不影响入站）
```bash
curl -sS -I http://127.0.0.1:5678/ | head -n 5
```
输出（已确认）：

- `HTTP/1.1 200 OK`

含义：服务在宿主机本机访问正常，禁出网不影响入站访问链路。


### 5.3 监听验证
```bash
ss -lntp | grep 5678 || netstat -lntp | grep 5678
```
输出（已确认）：

- `LISTEN 0 1024 0.0.0.0:5678 ... docker-proxy`

含义：宿主机 5678 已监听并被 docker-proxy 接管。


### 5.4 出网拦截计数器（审计证据：命中 DROP）
#### 5.4.1 清零计数器
```bash
iptables -Z DOCKER-USER
```

#### 5.4.2 查看计数器
```bash
iptables -L DOCKER-USER -n -v --line-numbers
```
输出（已确认，关键证据）：

- `DROP` 规则命中：`pkts=10 bytes=600`

示例：

```text
num   pkts bytes target  ... source          destination
3       10   600 DROP    ... 172.31.0.0/16   0.0.0.0/0
```

含义（审计口径）：

- `172.31.0.0/16` 网段内（即 n8n 容器）确实发生了对外发包/出网尝试。
- 这些出网包被 `DOCKER-USER` 的 `DROP` 规则明确丢弃。
- 因此“容器通过网络下载外部内容”的前提（成功建立对外连接）不存在。


## 6. 发现的问题与排查建议

### 6.1 宿主机访问自身公网 IP:5678 超时（回环/云侧链路问题）
现象：

```bash
curl -sS -I http://47.242.227.231:5678/ | head -n 5
```
输出（已确认）：

- `curl: (7) Failed to connect ... Connection timed out`


- 安全组规则设置修改之后正常

## 6. 回滚与持久化

### 6.1 回滚 DOCKER-USER 规则
先查看行号：

```bash
iptables -L DOCKER-USER -n --line-numbers
```
倒序删除前三条（示例）：

```bash
iptables -D DOCKER-USER 3
iptables -D DOCKER-USER 2
iptables -D DOCKER-USER 1
```

### 6.2 规则持久化（重启不丢）
说明：不同发行版略有差异。

- CentOS/RHEL：`iptables-services` + `iptables-save > /etc/sysconfig/iptables`
- Ubuntu/Debian：`iptables-persistent` + `iptables-save > /etc/iptables/rules.v4`


## 7. 最终结论（可用于审计/验收）
- n8n 容器运行在独立 Docker bridge 网段 `172.31.0.0/16`。
- 宿主机 `iptables DOCKER-USER` 对该网段实施 egress `DROP`，从网络层硬性阻断容器对外连接。
- 功能验证显示外网访问失败：`wget https://www.baidu.com` => `OK: blocked`。
- 审计证据显示 `DROP` 规则命中计数增长（如 `pkts=10 bytes=600`），证明容器对外发包被明确丢弃。

因此：在规则生效期间，容器无法建立对外连接，**不具备下载外部内容的网络条件**。
