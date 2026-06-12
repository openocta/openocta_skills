#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Skill路由1：MySQL基础健康巡检
执行动作：check
采集维度：连通性、版本、运行时长、最大连接数、默认字符集
异常覆盖：数据库离线、连接拒绝、基础参数读取异常
"""
import argparse
import pymysql

def basic_check(host, port, user, password):
    res = {
        "code": 0,
        "msg": "success",
        "data": {
            "host": host,
            "port": port,
            "status": "online",
            "version": "",
            "uptime": "",
            "max_connections": 0,
            "charset": "",
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

        # 获取数据库版本
        cur.execute("SELECT VERSION()")
        res["data"]["version"] = cur.fetchone()[0]

        # 获取服务运行时长
        cur.execute("SHOW GLOBAL STATUS LIKE 'Uptime'")
        res["data"]["uptime"] = f"{cur.fetchone()[1]}s"

        # 获取最大连接数配置
        cur.execute("SHOW GLOBAL VARIABLES LIKE 'max_connections'")
        res["data"]["max_connections"] = int(cur.fetchone()[1])

        # 获取默认字符集
        cur.execute("SHOW VARIABLES LIKE 'character_set_server'")
        res["data"]["charset"] = cur.fetchone()[1]

        cur.close()
        conn.close()

    except pymysql.err.OperationalError:
        res["code"] = 1001
        res["msg"] = "数据库连接失败"
        res["data"]["status"] = "offline"
        res["solve_tips"] = "检查服务器IP白名单、端口放行状态、数据库账号密码、远程访问权限"
    except Exception as e:
        res["code"] = 1002
        res["msg"] = f"基础巡检未知异常：{str(e)}"

    print(res)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", help="check")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", default="")
    args = parser.parse_args()

    if args.action == "check":
        basic_check(args.host, args.port, args.user, args.password)

if __name__ == "__main__":
    main()
