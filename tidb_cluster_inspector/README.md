# tidb_cluster_inspector

TiDB 集群系统性巡检与深度诊断 Skill。通过只读 SQL（不依赖外部 CLI / PD API）对 TiDB 集群做 8 维度体检，把一次半小时的人工巡检压缩成 AI 辅助的快速诊断。兼容 TiDB v4.0+。

## 覆盖维度
1. 集群拓扑（cluster_info）
2. 节点健康
3. 慢查询（slow_query / cluster_slow_query）
4. 热点 Region（TIDB_HOT_REGIONS，按热度排序）
5. TiKV 存储（tikv_store_status）
6. PD 调度配置
7. Leader 倾斜（按 store 统计 leader 占比，发现调度不均）
8. TopSQL 归因（CLUSTER_STATEMENTS_SUMMARY，按总耗时 / 执行次数 / 内存排序 + 复合 TOP5）

## 边界（诚实标注）
以下能力超出只读 SQL 范围，需 PD API 或写权限，本 skill 不执行、仅建议：region 预打散（pd-ctl / tidba split）、runaway 限流（resource group）、多数派 DOWN region 检测（PD region-peer API）、原生 CPU topsql（需 tidb_enable_top_sql）。

## 使用
将 SKILL.md 放入 OpenOcta skills 目录，配置一个能连 TiDB 的 db_query MCP 工具即可。任意 db_* MCP server 均可，或使用参考实现：https://github.com/vicleung01/openocta-db-ops-skills （含参考 MCP server + 完整 8-skill pack）

## License
Apache-2.0
