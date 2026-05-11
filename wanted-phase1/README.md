# 第一期征集主题（占位）

本目录下的子目录是 **主题占位**，内容可为空或仅为提纲；**请勿直接在 `wanted-phase1/` 内提交完整 PR**。正确做法是：

1. 将与你主题匹配的子目录 **整体复制到仓库根目录**（并可按需改名，例如 `k8s_skill` → `k8s_incident_runbook`）。
2. 按 [`template/README.md`](../template/README.md) 的要求补全 `SKILL.md`、`README.md`、`mate.json`（含 **author / affiliation**）。
3. 向主仓库提交 Pull Request。

## 当前占位主题

| 目录 | 征集方向（示例） |
|------|------------------|
| [`k8s_skill/`](k8s_skill/) | 集群排障、Workload 观测、网络与存储常见问题、安全变更注意事项等 |
| [`prometheus_skill/`](prometheus_skill/) | PromQL 范式、告警治理、Recording rule、联邦与高可用运维等 |
| [`zabbix_skill/`](zabbix_skill/) | 模板与触发器、采集排障、性能调优、迁移与升级检查清单等 |

若你的专长不在上列主题，仍可从 [`template/`](../template/) 新建任意目录贡献。
