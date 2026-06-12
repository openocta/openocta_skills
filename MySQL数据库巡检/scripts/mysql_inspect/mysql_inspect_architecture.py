#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Skill路由4：MySQL主从架构巡检
执行动作：check
采集维度：主从角色、IO线程状态、SQL线程状态、主从延迟秒数
风险识别：同步中断、日志读取失败、数据回放异常、主从数据不一致
"""
import argparse
import pymysql

def repl_check(host, port, user, password):
    res = {
        "code": 0,
        "msg": "success",
        "data": {
            "is_master": False,
            "slave_io_running": "",
            "slave_sql_running": "",
            "delay_seconds": 0,
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
        cur.execute("SHOW SLAVE STATUS")
        slave_data = cur.fetchone()

        # 判断主从角色
        if not slave_data:
            res["data"]["is_master"] = True
        else:
            # 读取从库核心同步状态
            res["data"]["slave_io_running"] = slave_data[10]
            res["data"]["slave_sql_running"] = slave_data[11]
            res["data"]["delay_seconds"] = int(slave_data[44]) if slave_data[44] else 0

            # 架构风险判定
            if res["data"]["slave_io_running"] != "Yes":
                res["risk"].append("从库IO线程异常，无法拉取主库binlog日志，同步中断")
            if res["data"]["slave_sql_running"] != "Yes":
                res["risk"].append("从库SQL线程异常，日志回放失败，数据同步停滞")
            if res["data"]["delay_seconds"] > 30:
                res["risk"].append(f"主从延迟过高，当前延迟{res['data']['delay_seconds']}秒，存在数据一致性风险")

        cur.close()
        conn.close()

    except Exception as e:
        res["code"] = 4001
        res["msg"] = f"主从架构巡检异常：{str(e)}"

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
        repl_check(args.host, args.port, args.user, args.password)

if __name__ == "__main__":
    main()
