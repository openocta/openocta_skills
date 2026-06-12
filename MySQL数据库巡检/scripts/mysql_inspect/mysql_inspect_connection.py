#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Skill路由2：MySQL连接负载专项巡检
执行动作：scan
采集维度：总会话、活跃会话、超时空闲连接、连接使用率、线程缓存命中率
风险识别：连接过载、无效连接堆积、线程频繁创建、连接泄露
"""
import argparse
import pymysql

def connection_scan(host, port, user, password, threshold):
    res = {
        "code": 0,
        "msg": "success",
        "data": {
            "threshold": threshold,
            "total_session": 0,
            "active_session": 0,
            "sleep_invalid_session": 0,
            "user_sleep_session": 0,
            "connection_usage": 0.0,
            "thread_cache_hit": 0.0,
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

        # 统计总会话数
        cur.execute("select count(*) from information_schema.processlist;")
        res["data"]["total_session"] = cur.fetchone()[0]

        # 统计活跃业务会话（排除Sleep空闲连接）
        cur.execute("select count(*) from information_schema.processlist where command<>'Sleep';")
        res["data"]["active_session"] = cur.fetchone()[0]

        # 统计超时Sleep无效连接
        sql_sleep = f"select count(*) from information_schema.processlist where command='Sleep' and time > {threshold}"
        cur.execute(sql_sleep)
        res["data"]["sleep_invalid_session"] = cur.fetchone()[0]

        # 统计User Sleep阻塞会话
        sql_usersleep = f"select count(*) from information_schema.processlist where state='User sleep' and time > {threshold}"
        cur.execute(sql_usersleep)
        res["data"]["user_sleep_session"] = cur.fetchone()[0]

        # 计算连接使用率
        cur.execute("SHOW GLOBAL STATUS LIKE 'Threads_connected'")
        current_conn = int(cur.fetchone()[1])
        cur.execute("SHOW GLOBAL VARIABLES LIKE 'max_connections'")
        max_conn = int(cur.fetchone()[1])
        usage = round(current_conn / max_conn * 100, 2)
        res["data"]["connection_usage"] = usage

        # 计算线程缓存命中率
        cur.execute("SHOW GLOBAL STATUS LIKE 'Threads_created'")
        threads_created = int(cur.fetchone()[1])
        cur.execute("SHOW GLOBAL STATUS LIKE 'Connections'")
        total_conn = int(cur.fetchone()[1])
        if total_conn > 0:
            hit = round((1 - threads_created / total_conn) * 100, 2)
            res["data"]["thread_cache_hit"] = hit

        # 负载风险判定
        if usage > 80:
            res["risk"].append("数据库连接数使用率超过80%，存在连接打满、业务阻塞风险")
        if res["data"]["sleep_invalid_session"] > 20:
            res["risk"].append("超时空闲无效连接堆积过多，占用连接资源，需定期清理")

        cur.close()
        conn.close()

    except Exception as e:
        res["code"] = 2001
        res["msg"] = f"负载巡检异常：{str(e)}"
        res["solve_tips"] = "检查数据库PROCESS查询权限、服务器网络连通性"

    print(res)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", help="scan")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--threshold", type=int, default=300)
    parser.add_argument("--password", default="")
    args = parser.parse_args()

    if args.action == "scan":
        connection_scan(args.host, args.port, args.user, args.password, args.threshold)

if __name__ == "__main__":
    main()
