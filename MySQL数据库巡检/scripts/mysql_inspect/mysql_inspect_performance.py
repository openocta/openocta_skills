#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Skill路由3：MySQL性能专项巡检
执行动作：audit
采集维度：慢查询状态、长事务、全表扫描、临时表、文件排序、冗余索引
风险识别：低效SQL、事务阻塞、索引失效、性能劣化隐患
"""
import argparse
import pymysql

def perf_audit(host, port, user, password):
    res = {
        "code": 0,
        "msg": "success",
        "data": {
            "slow_query_log_open": False,
            "slow_query_total": 0,
            "long_transaction_count": 0,
            "full_scan_count": 0,
            "tmp_table_count": 0,
            "filesort_count": 0,
            "unused_index_count": 0,
            "risk": []
        }
    }
    try:
        conn = pymysql.connect(
            host=host,
            port=int(port),
            user=user,
            password=password,
            connect_timeout=15
        )
        cur = conn.cursor()

        # 检测慢查询日志开启状态
        cur.execute("SHOW VARIABLES LIKE 'slow_query_log'")
        res["data"]["slow_query_log_open"] = (cur.fetchone()[1] == "ON")

        # 统计累计慢查询总数
        cur.execute("SHOW GLOBAL STATUS LIKE 'Slow_queries'")
        res["data"]["slow_query_total"] = int(cur.fetchone()[1])

        # 统计全表扫描次数
        cur.execute("SHOW GLOBAL STATUS LIKE 'Select_scan'")
        res["data"]["full_scan_count"] = int(cur.fetchone()[1])

        # 统计临时表创建次数
        cur.execute("SHOW GLOBAL STATUS LIKE 'Created_tmp_tables'")
        res["data"]["tmp_table_count"] = int(cur.fetchone()[1])

        # 统计文件排序次数
        cur.execute("SHOW GLOBAL STATUS LIKE 'Sort_files'")
        res["data"]["filesort_count"] = int(cur.fetchone()[1])

        # 统计超时未提交长事务（60s以上）
        long_trans_sql = """
        select count(*) from information_schema.processlist
        where command='Query' and time > 60 and state not in ('User sleep','Sleep');
        """
        cur.execute(long_trans_sql)
        res["data"]["long_transaction_count"] = cur.fetchone()[0]

        # 统计未使用冗余索引
        try:
            cur.execute("select count(*) from sys.schema_unused_indexes;")
            res["data"]["unused_index_count"] = cur.fetchone()[0]
        except:
            res["data"]["unused_index_count"] = 0

        # 性能风险判定
        if not res["data"]["slow_query_log_open"]:
            res["risk"].append("慢查询日志未开启，无法审计低效SQL，存在性能盲区")
        if res["data"]["full_scan_count"] > 1000:
            res["risk"].append("全表扫描次数过多，大量SQL索引失效，严重影响数据库性能")
        if res["data"]["long_transaction_count"] > 0:
            res["risk"].append("存在未提交长事务，易引发锁等待、死锁、主从延迟问题")
        if res["data"]["unused_index_count"] > 5:
            res["risk"].append("存在大量冗余未使用索引，占用磁盘空间、降低写入性能")

        cur.close()
        conn.close()

    except Exception as e:
        res["code"] = 3001
        res["msg"] = f"性能巡检异常：{str(e)}"

    print(res)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", help="audit")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", default="")
    args = parser.parse_args()

    if args.action == "audit":
        perf_audit(args.host, args.port, args.user, args.password)

if __name__ == "__main__":
    main()
