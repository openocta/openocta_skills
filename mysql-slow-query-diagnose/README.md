# mysql-slow-query-diagnose

MySQL 慢查询诊断：索引命中率 + EXPLAIN + 覆盖索引推荐 + 预估提速倍数。 源自金融行业 DBA 生产实践。

## 能力
- 计算索引命中率（rows_sent / rows_examined）
- 读 EXPLAIN，推荐具体覆盖索引并预估提速倍数
- 定位 TOP N 慢查询并给修复建议

## 使用
将 SKILL.md 放入 OpenOcta skills 目录，配置一个 MySQL/MariaDB 的 db_* MCP 工具即可。完整 pack + 参考 MCP server：https://github.com/vicleung01/openocta-db-ops-skills

## License
Apache-2.0
