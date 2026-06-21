# mysql-replication-lag-resolver

MySQL 从库延迟根因定位 + 5 阶段双重复核安全 KILL 慢 SQL。 源自金融行业 DBA 生产实践。

## 能力
- 从库延迟根因定位（Seconds_Behind_Master + processlist）
- 5 阶段双重复核 KILL：展示候选 → 用户选择 → AI 回读 → 输入 CONFIRM KILL → 执行 + 恢复监控

## 使用
将 SKILL.md 放入 OpenOcta skills 目录，配置一个 MySQL/MariaDB 的 db_* MCP 工具即可。完整 pack + 参考 MCP server：https://github.com/vicleung01/openocta-db-ops-skills

## License
Apache-2.0
