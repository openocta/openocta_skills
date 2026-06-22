# mysql-deadlock-analyzer

MySQL 死锁全链路分析：InnoDB status → 锁链 → 模式分类（AB-BA/Gap Lock/FK）→ 修复建议。 源自金融行业 DBA 生产实践。

## 能力
- 从 InnoDB status 提取 LATEST DETECTED DEADLOCK
- 解析锁链与当前锁等待（performance_schema / information_schema，兼容 MySQL 5.6+）
- 死锁模式分类（AB-BA / Gap Lock / FK）并给修复建议

## 使用
将 SKILL.md 放入 OpenOcta skills 目录，配置一个 MySQL/MariaDB 的 db_* MCP 工具即可。完整 pack + 参考 MCP server：https://github.com/vicleung01/openocta-db-ops-skills

## License
Apache-2.0
