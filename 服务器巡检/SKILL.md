---
name: server-patrol
description: Linux 与网络设备只读健康巡检；直接运行 scripts/patrol.sh，配置由平台侧信道注入，Agent 不读取环境变量
---

# 基础设施巡检 (server-patrol)

面向 **Linux 服务器** 与 **网络设备**（路由器、交换机、防火墙等）的**只读**巡检 Skill。

| 对象 | 检查项 |
|------|--------|
| Linux | uptime、负载、CPU、内存、磁盘、systemd 服务、Docker |
| 网络设备 | Ping 连通、TCP 端口、SNMP（可选）、SSH 只读命令（Cisco / 华为 / H3C） |

## 何时使用

- 「服务器巡检」「网络设备巡检」「路由器状态」「交换机健康」「定时巡检」
- **不适用**：改配置、重启设备、下发 ACL 等写操作

## 用户目标

- 一份报告汇总 Linux 与网络设备的 OK / WARN / CRIT
- 明确 unreachable、高 CPU、端口不通等风险及处理建议

## Agent 执行规则（必读）

巡检目标与凭证由 **OpenOcta 平台**在运行 `patrol.sh` 前注入进程环境（来自 Skill 包内 `config.env` + Config Vault），**不对大模型暴露**。

1. **直接运行脚本**，不要预先检查环境变量：
   - 禁止 `env`、`printenv`、`echo $PATROL_*`、`grep PATROL`
   - 禁止 `cat`/`read_file` 读取 `config.env`
   - 禁止在对话中复述密码、密钥、community 等敏感值
2. 进入 Skill 目录后执行（路径以实际挂载为准）：

```bash
chmod +x scripts/patrol.sh
./scripts/patrol.sh --list          # 查看已配置目标（无目标时再报错）
./scripts/patrol.sh --all           # 批量 Linux + 网络
./scripts/patrol.sh --servers       # 仅 Linux
./scripts/patrol.sh --network       # 仅网络设备
./scripts/patrol.sh --network --tag core
./scripts/patrol.sh --all --format json
```

3. 若 `--list` 为空或脚本报「未配置目标」，告知用户：需在控制台 Config Vault / Skill `config.env` 中配置巡检目标，**不要**自行构造 `export PATROL_*`。
4. 根据脚本 stdout / `reports/` 下报告解读结果，按下方「处理思路」给出建议。

## 分析思路

1. 运行 `./scripts/patrol.sh --list` 或 `./scripts/patrol.sh --all`
2. **Linux**：磁盘/内存/负载超阈值 → WARN/CRIT（逻辑见脚本）
3. **网络**：Ping 丢包、RTT、端口、SSH 采集 CPU/内存 → WARN/CRIT
4. 报告分「Linux 服务器」「网络设备」两节呈现

## 处理思路

| 发现 | 建议 |
|------|------|
| Ping CRIT | 查链路、ARP、ACL、设备电源 |
| 端口 closed | 确认服务监听、防火墙、安全组 |
| Cisco/华为 CPU 高 | 查会话数、路由震荡、广播风暴 |
| 接口 down | 查物理链路、光模块、对端端口 |
| Linux 磁盘/内存 CRIT | 同服务器巡检常规处理 |
| SSH/SNMP 失败 | 查凭证、SNMP ACL、管理 VLAN（勿向用户索要明文密码） |

## 输出要求

- 以脚本输出为准，分 Linux / 网络两节
- CRIT/WARN 项附简短 remediation
- SSH/SNMP 失败单独说明，不阻塞其他目标

## 注意事项

- **只读**：禁止配置写入、reload、reboot
- 网络设备 SSH 命令集因厂商/版本而异
- 运维配置格式（`PATROL_*` 列表、Config Vault 引用）见 **[README.md](./README.md)** 与 **config.env**，Agent **无需**阅读

## 能力依赖

- bash、ping、ssh；密码认证时需 **sshpass**（由运维在 Runtime 镜像中安装）
- 可选：python3、nc、snmpwalk
