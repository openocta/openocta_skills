# server-patrol

Linux 服务器与网络设备（路由器、交换机、防火墙等）的**只读**健康巡检工具。通过环境变量配置目标列表，支持本机、SSH 远程与批量巡检，输出 Markdown 或 JSON 报告。

> **与 `SKILL.md` 的区别**：`README.md` 面向运维/开发者，说明如何安装、配置与使用；`SKILL.md` 面向 AI Agent，描述何时触发、分析思路与处理建议，供 Cursor / OpenOcta 等平台自动执行巡检时使用。

### **注意：该skill可搭配openocta-amc平台配置管理使用更加更佳，单独使用注意配置环境变量以及变量规范 ** 

## 功能概览

| 对象 | 检查项 |
|------|--------|
| **Linux 服务器** | 运行时间、负载、CPU、内存、磁盘、systemd 服务、Docker 容器、Kubernetes（自动检测 `kubectl`） |
| **网络设备** | Ping 连通性、TCP 端口、SNMP（可选）、SSH 只读采集（Cisco / 华为 / H3C） |

每台目标最终汇总为 **OK / WARN / CRIT** 状态；异常项附带简要处理建议。SSH/SNMP 单点失败不会阻塞其他目标。

## 目录结构

```
server-patrol/
├── README.md          # 本文件：人类可读的使用说明
├── SKILL.md           # Agent 指令：平台 Skill 运行时加载
├── config.env         # 环境变量模板（非自动加载，见下方说明）
├── scripts/
│   └── patrol.sh      # 巡检主脚本
└── reports/           # 默认报告输出目录（运行时自动创建）
```

## 快速开始

### 1. 依赖

| 类别 | 组件 | 用途 |
|------|------|------|
| 必需 | `bash`、`ping`、`ssh` | 脚本执行、连通性、远程采集 |
| 密码 SSH | `sshpass` | 非交互密码认证（Config Vault 注入密码时**必须**） |
| 可选 | `python3` | 解析 `PATROL_*_JSON` 目标列表 |
| 可选 | `nc` 或 bash `/dev/tcp` | TCP 端口探测 |
| 可选 | `snmpwalk` | SNMP 模式 |

Sophon / Runtime 镜像若使用 Vault 密码巡检，请在镜像中安装 `sshpass`（例如 Debian/Ubuntu：`apt-get install -y sshpass`）。

### 2. 配置环境变量

`patrol.sh` **只从进程环境**读取 `PATROL_*` 变量，**不会**自动 `source config.env`。

**本地调试示例（Linux + 密码）：**

```bash
cd script/skills/server-patrol   # 或 Skill 包解压目录

export PATROL_SERVER='host52|root@192.168.50.52:22|production,fenda'
export PATROL_SSH_PASSWORD='你的密码'   # 含 @ 等特殊字符时务必加引号

chmod +x scripts/patrol.sh
./scripts/patrol.sh --list       # 确认目标解析正确
./scripts/patrol.sh --servers      # 仅 Linux
```

**本地调试（Linux + 网络混合）：**

```bash
export PATROL_SERVER='web-1|ubuntu@192.168.1.100:22|production'
export PATROL_NETWORK='core-rtr|ping|192.168.1.1|network,core|22,161,443'
./scripts/patrol.sh --all
```

或一次性传入（单行命令前加 env，避免污染当前 shell）：

```bash
PATROL_SERVER='web-1|ubuntu@10.0.0.1:22|prod' \
PATROL_SSH_PASSWORD='secret' \
./scripts/patrol.sh --servers
```

**OpenOcta / AMC 部署**：将 `config.env` 打入 Skill 包；AMC 在 Sophon 握手后通过 `config_inject_token` 侧信道注入进程环境（`@config:ALIAS/field` 引用在注入前由 AMC 解析为明文，**不会**出现在对话或 LLM 上下文中）。

完整变量模板见 [`config.env`](config.env)（运维文档；**Agent 见 SKILL.md，勿读 config.env**）。

### 3. 常用命令

```bash
# 本机 Linux 巡检
./scripts/patrol.sh local

# 单台 Linux 远程（格式与 PATROL_SERVER 中 ssh 段相同）
./scripts/patrol.sh remote root@192.168.50.52:22

# 单台网络设备
./scripts/patrol.sh net ping 192.168.1.254
./scripts/patrol.sh net ssh-cisco admin@10.0.0.1:22

# 批量：Linux + 网络
./scripts/patrol.sh --all

# 仅 Linux / 仅网络
./scripts/patrol.sh --servers
./scripts/patrol.sh --network

# 按标签过滤（tags 字段逗号分隔）
./scripts/patrol.sh --servers --tag production
./scripts/patrol.sh --network --tag core

# 列出已解析目标（不发起 SSH）
./scripts/patrol.sh --list

# JSON 输出（stdout；同时写入 reports/）
./scripts/patrol.sh --all --format json
```

`--list` 输出列：`TYPE`、`NAME`、`TARGET`、`TAGS`（Linux 为 `user@host:port`，网络设备含类型）。

## 配置说明

### Linux 服务器列表格式

`PATROL_SERVER` 为**分号分隔**的多条记录，每条用 **竖线 `|`** 分段：

```text
名称|user@host[:port]|tag1,tag2
名称|user@host[:port]|tag1,tag2|per-host-password   # 可选第 4 段：单机密码
```

**示例：**

```text
host52|root@192.168.50.52:22|production,fenda
web-1|ubuntu@10.0.0.1:22|prod,web
db-slave|postgres@db.internal|database|@config:DB/pass
```

**关于 `user@host:port`：**

- 这是脚本的**配置写法**，等价于手动执行 `ssh -p <port> <user>@<host>`。
- `root@192.168.50.52:22` 会解析为：`user=root`、`host=192.168.50.52`、`port=22`。
- 省略 `:port` 时默认 `22`；省略 `user@` 时使用当前环境的 `$USER`（通常为 `root`）。

**密码放在哪：**

| 方式 | 适用场景 |
|------|----------|
| 3 段 + 全局 `PATROL_SSH_PASSWORD` | **推荐**：OpenOcta Config Vault 注入 `PASSWORD` → `PATROL_SSH_PASSWORD` |
| 4 段 per-host 密码 | 单机密码不同；`@config:ALIAS/field` 由 **AMC 注入前展开**（见下方说明） |
| `PATROL_SSH_IDENTITY` 私钥 | 密钥登录；见下方 SSH 认证 |

**`@config:` 写在列表第 4 段时**：`patrol.sh` 不会自行解析 Vault；须依赖 AMC 在 Skill 注入时把 `PATROL_SERVER`（及其中嵌入的 `@config:PATROL/PASSWORD`）换成明文。若注入后仍为 `@config:...`，脚本会回退 `PATROL_SSH_PASSWORD`；全局密码也未注入则会出现 `Permission denied`。

含 `@` 等特殊字符的密码在 shell 中**必须用引号**包裹，例如 `export PATROL_SSH_PASSWORD='Databuff@123'`。脚本经 `sshpass` 传递时不会截断 `@`。

**JSON 格式（优先于列表）：**

```bash
export PATROL_SERVER_JSON='[
  {"name":"host52","host":"192.168.50.52","user":"root","port":22,"tags":["production","fenda"]}
]'
```

### Linux 告警与巡检项

| 变量 | 说明 | 默认 |
|------|------|------|
| `PATROL_DISK_WARN/CRIT` | 磁盘使用率 % | 80 / 90 |
| `PATROL_MEM_WARN/CRIT` | 内存使用率 % | 85 / 95 |
| `PATROL_LOAD_WARN/CRIT` | 1 分钟负载 | 5 / 10 |
| `PATROL_CPU_WARN` | CPU 使用率 % | 80 |
| `PATROL_SERVICES` | systemd 单元，逗号分隔（自动补 `.service`） | 空 |
| `PATROL_SSH_TIMEOUT` | SSH 连接超时（秒） | 10 |
| `PATROL_CONCURRENCY` | 批量并发（预留） | 5 |
| `PATROL_REPORT_DIR` | 报告目录 | `./reports` |

**Kubernetes（零配置）：** 远程探测会检测是否存在 `kubectl` 命令。若存在，则使用当前用户默认 kubeconfig（如 `~/.kube/config` 或 control-plane 上的 `/etc/kubernetes/admin.conf`）尝试只读采集：

- `kubectl version --client`、`kubectl config current-context`
- `kubectl get nodes` / `get pods -A` / `get ns` 及汇总计数
- `kubectl get deploy -A`、`kubectl get ds -A`（未就绪工作负载列表）
- 组件健康：`kubectl get componentstatuses`（旧集群）、`/healthz`、`/readyz?verbose`、`kube-system` 非 Running Pod
- `kubectl top nodes`、`kubectl top pods -A`（需 metrics-server；不可用时跳过）
- 非 Running/Completed/Succeeded 的 Pod、重启次数 ≥10 的 Pod

无需配置 `PATROL_KUBECONFIG`、`PATROL_K8S_NAMESPACES` 等变量。未安装 `kubectl` 或无法连接 API Server 时，报告标注为 OK（未安装）或 WARN（已安装但连不上），不阻塞其他巡检项。各子命令（`get nodes/pods`、`top` 等）**独立执行**：某一命令因 RBAC、metrics-server 未安装或 kubectl 版本差异失败时，仅跳过该项并在报告中说明原因，不影响其余 K8s 与 Linux 巡检。

### 网络设备

| 变量 | 说明 |
|------|------|
| `PATROL_NETWORK` | 分号分隔：`名称\|类型\|host或user@host[:port]\|tags\|ports或community` |
| `PATROL_NETWORK_JSON` | 同上，JSON 数组（**优先**于 `PATROL_NETWORK`） |
| `PATROL_NET_PORTS` | ping 模式默认探测端口 | 22,80,443 |
| `PATROL_PING_*` | Ping 次数与丢包/RTT 阈值 | 见 `config.env` |
| `PATROL_SNMP_COMMUNITY` / `PATROL_SNMP_VERSION` | SNMP 社区串与版本 | 2c |

**网络设备类型：**

| type | 行为 |
|------|------|
| `ping` | ICMP + TCP 端口探测 |
| `ssh-cisco` | Cisco IOS 只读命令 |
| `ssh-huawei` | 华为 VRP 只读命令 |
| `ssh-h3c` | H3C Comware 只读命令 |
| `ssh-generic` | 尝试多厂商常见命令 |
| `snmp` | SNMP sys OID 采集（失败则降级为 ping+端口） |

### SSH 认证

脚本内部等价调用：`ssh -o ConnectTimeout=… -p <port> … <user>@<host>`，远程执行嵌入式只读探测脚本。

**默认策略（`PATROL_SSH_AUTH=auto`，推荐）：**

| 条件 | 实际认证 |
|------|----------|
| 已配置 `PATROL_SSH_PASSWORD`、per-host 密码或 `PATROL_PASSWORD` | **密码**（`sshpass`，即使本机存在 `~/.ssh/id_rsa`） |
| 无密码、但 `PATROL_SSH_IDENTITY` 指向有效私钥文件 | **公钥** |
| 均无 | 失败（`auth=none`） |

> **常见误区**：手动 `ssh root@host` 可登录（交互输入密码），但脚本报 `Permission denied (publickey,…,password)`。多为本机有默认 `id_rsa` 而 Vault 密码未注入，或旧版脚本优先公钥。请确认 stderr 中 `auth=password` 且已安装 `sshpass`。

**强制策略：**

| `PATROL_SSH_AUTH` | 行为 |
|-------------------|------|
| `auto`（默认） | 有密码用密码，否则用密钥 |
| `password` | 仅密码 |
| `publickey` | 仅密钥（忽略密码） |

| 变量 | 说明 |
|------|------|
| `PATROL_SSH_IDENTITY` | 私钥路径、`~/.ssh/id_rsa`，或 Vault 注入的 PEM 全文 |
| `PATROL_SSH_PASSWORD` | 全局 SSH 密码（3 段列表时使用；需 `sshpass`） |
| `PATROL_PASSWORD` | 与 `PATROL_SSH_PASSWORD` 等价（兼容 Vault 字段命名） |
| `PATROL_SSH_AUTH` | `auto` / `password` / `publickey` |

**OpenOcta Config Vault 推荐配置（见 `config.env`）：**

```env
# Profile alias = PATROL
PATROL_SERVER=@config:PATROL/SERVER
PATROL_SSH_PASSWORD=@config:PATROL/PASSWORD
# PATROL_SSH_IDENTITY=@config:PATROL/private_key   # 可选：密钥字段
```

Vault 字段示例：

| 字段 key | 注入变量 | 示例值 |
|----------|----------|--------|
| `SERVER` | `PATROL_SERVER` | `host52\|root@192.168.50.52:22\|production,fenda` |
| `PASSWORD` | `PATROL_SSH_PASSWORD` | （明文密码，勿提交仓库） |

`host52|root@192.168.50.52:22|production,fenda` **不需要**第 4 段；运行时 `PATROL_SSH_PASSWORD` 由平台从 Vault `PASSWORD` 注入即可。

单机独立密码（列表第 4 段或 JSON `password`）：

```env
PATROL_SERVER=web-1|ubuntu@10.0.0.1:22|prod|@config:WEB1/password
```

## 报告输出

- **stdout**：Markdown（默认）或 JSON（`--format json`）
- **文件**：`PATROL_REPORT_DIR/patrol-YYYYMMDD-HHMMSS.md`（或 `.json`）
- **结构**：阈值说明 → Linux 服务器明细 → 网络设备明细 → 版本脚注
- **stderr**：进度日志（如 `Inspect linux: host52 (root@192.168.50.52:22) auth=password`），不写入报告文件

## 告警规则摘要

| 场景 | WARN | CRIT |
|------|------|------|
| Ping 丢包 | ≥ 20% | ≥ 50% |
| Ping RTT | ≥ 100 ms | ≥ 500 ms |
| TCP 端口 | 有关键端口 closed | 主机不可达 |
| Linux 磁盘/内存/负载 | 达 WARN 阈值 | 达 CRIT 阈值 |
| 网络设备 CPU/内存 | 超配置阈值 | — |
| systemd 服务 | — | 未运行 |

阈值可通过对应 `PATROL_*_WARN/CRIT` 环境变量调整。

## 故障排查

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| `--list` 为空 | `PATROL_SERVER` / JSON 未注入 | 检查 Skill `config.env`、Vault 引用、AMC 握手日志 |
| `auth=none` | 无密码且无有效私钥 | 配置 Vault `PASSWORD` 或 `PATROL_SSH_IDENTITY` |
| `auth=publickey` 但应用密码 | 设置了 `PATROL_SSH_AUTH=publickey` 或未注入密码 | 确认 `PATROL_SSH_PASSWORD`；改为 `auto` 或 `password` |
| `Permission denied (publickey,…,password)` | 密码未注入、错误，或误走公钥 | 看 `auth=`；本地用引号 export 密码验证；安装 `sshpass` |
| `sshpass not found` | Runtime 无 sshpass | 镜像安装 `sshpass` |
| 手动 SSH 通、脚本不通 | 运行脚本的环境（Sophon 容器）与手工终端不同 | 在**同一环境**测试；确认容器到目标 IP 路由/安全组 |
| 报告仅 `ssh failed` | 旧版错误覆盖（已修复） | 升级至 `1.2.1+`，查看报告 ERROR 行的详细 SSH  stderr |
| SNMP / 网络 SSH 失败 | ACL、community、厂商命令差异 | 单独 `patrol.sh net …` 调试；见 SKILL.md 处理思路 |

**最小验证流程：**

```bash
./scripts/patrol.sh --list
./scripts/patrol.sh --servers 2>&1 | grep -E 'Inspect linux|WARN|ERROR'
```

## 安全与限制

- **只读**：不执行配置写入、reload、reboot 等变更操作
- 密码、SNMP community、私钥仅通过 Config Vault → 进程环境注入；**勿**写入 Git 或 Skill 包明文
- 生产环境可优先密钥（`PATROL_SSH_AUTH=publickey` + Vault 私钥）；批量密码场景需 `sshpass` 且限制 Runtime 权限
- 不同厂商/版本的 SSH 命令集可能有差异，`ssh-generic` 采集可能不完整
- Agent 执行规范（禁止 `printenv PATROL_*`、禁止复述密钥）见 [`SKILL.md`](SKILL.md)

## 版本

当前脚本版本：**1.3.3**（见 `scripts/patrol.sh` 内 `VERSION`）

| 版本 | 变更摘要 |
|------|----------|
| 1.3.3 | SSH：`@config:` 未展开的 per-host 密码回退 `PATROL_SSH_PASSWORD`；AMC 展开 `PATROL_SERVER` 内嵌 `@config:` |
| 1.3.2 | K8s 增补 Deployment/DaemonSet 与组件健康（componentstatuses、healthz/readyz、kube-system） |
| 1.3.1 | K8s/Docker 命令容错：子命令独立失败隔离、`kubectl version`/`top`/RBAC 兼容、跳过项写入报告 |
| 1.3.0 | Linux 自动检测 `kubectl`：节点/Pod/命名空间、`kubectl top nodes/pods`、异常 Pod；无需 `PATROL_KUBECONFIG` 等配置 |
| 1.2.1 | SSH 认证：`auto` 模式下 Vault/全局密码优先于本机默认 `id_rsa`；修复失败时错误信息被覆盖 |
| 1.2.0 | Linux + 网络批量、Config Vault `@config:` 注入、Markdown/JSON 报告 |

## 相关文档

- [`SKILL.md`](SKILL.md) — Agent 触发条件、分析/处理思路、执行约束
- [`config.env`](config.env) — 可复制的配置模板与阈值默认值
