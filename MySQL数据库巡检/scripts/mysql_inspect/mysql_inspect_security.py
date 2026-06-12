#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Skill路由5：MySQL安全合规巡检
执行动作：scan
采集维度：空密码账号、全网通配符账号、binlog日志状态、文件读取权限
风险识别：弱口令风险、非法访问、数据不可恢复、文件注入风险
"""
import argparse
import pymysql

def security_scan(host, port, user, password):
    res = {
        "code": 0,
        "msg": "success",
        "data": {
            "empty_pwd_user": 0,
            "all_host_user": 0,
            "risk_config": [],
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

        # 统计空密码高危账号
        cur.execute("select count(*) from mysql.user where password='' or authentication_string='';")
        res["data"]["empty_pwd_user"] = cur.fetchone()[0]

        # 统计全网访问账号
        cur.execute("select count(*) from mysql.user where host='%';")
        res["data"]["all_host_user"] = cur.fetchone()[0]

        # 检测binlog日志状态
        cur.execute("SHOW VARIABLES LIKE 'log_bin'")
        log_bin = cur.fetchone()[1]
        if log_bin != "ON":
            res["data"]["risk_config"].append("二进制日志未开启，无法实现数据恢复与操作审计")

        # 检测local_infile高危配置
        cur.execute("SHOW VARIABLES LIKE 'local_infile'")
        local_infile = cur.fetchone()[1]
        if local_infile == "ON":
            res["data"]["risk_config"].append("local_infile功能开启，存在恶意文件注入风险")

        # 安全风险汇总
        if res["data"]["empty_pwd_user"] > 0:
            res["risk"].append("数据库存在空密码账号，极易被非法入侵，安全风险极高")
        if res["data"]["all_host_user"] > 0:
            res["risk"].append("存在全网无限制访问账号，不符合等保合规要求")
        if len(res["data"]["risk_config"]) > 0:
            res["risk"].extend(res["data"]["risk_config"])

        cur.close()
        conn.close()

    except Exception as e:
        res["code"] = 5001
        res["msg"] = f"安全巡检异常：{str(e)}"

    print(res)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", help="scan")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", default="")
    args = parser.parse_args()

    if args.action == "scan":
        security_scan(args.host, args.port, args.user, args.password)

if __name__ == "__main__":
    main()
