#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Skill路由6：MySQL Prometheus时序指标趋势巡检
执行动作：metrics
核心能力：复盘时段资源、流量、性能趋势，发现瞬时巡检盲区问题
采集指标：CPU/内存负载、QPS/TPS、连接波动、慢查询增量、InnoDB读写比
"""
import argparse
import requests

def prometheus_metrics_inspect(prom_url, instance_addr, time_range=24):
    res = {
        "code": 0,
        "msg": "success",
        "data": {
            "prometheus_url": prom_url,
            "instance": instance_addr,
            "stat_hours": time_range,
            "cpu_usage_avg": 0.0,
            "mem_usage_avg": 0.0,
            "qps_avg": 0,
            "tps_avg": 0,
            "conn_trend": "stable",
            "slow_query_trend": "stable",
            "innodb_read_write_ratio": 0.0,
            "risk": [],
            "trend_analysis": ""
        }
    }

    # Prometheus通用查询方法
    def query_prom(query):
        try:
            rsp = requests.get(f"{prom_url}/api/v1/query", params={"query": query}, timeout=10)
            return rsp.json()
        except Exception as e:
            res["code"] = 7001
            res["msg"] = f"Prometheus接口请求异常：{str(e)}"
            return None

    # 1. 服务器CPU平均使用率
    cpu_query = f"avg_over_time(sys_cpu_usage{{instance=~'{instance_addr}'}}[{time_range}h])"
    cpu_data = query_prom(cpu_query)
    if cpu_data and cpu_data["status"] == "success" and cpu_data["data"]["result"]:
        res["data"]["cpu_usage_avg"] = round(float(cpu_data["data"]["result"][0]["value"][1]), 2)

    # 2. 服务器内存平均使用率
    mem_query = f"avg_over_time(sys_mem_usage{{instance=~'{instance_addr}'}}[{time_range}h])"
    mem_data = query_prom(mem_query)
    if mem_data and mem_data["status"] == "success" and mem_data["data"]["result"]:
        res["data"]["mem_usage_avg"] = round(float(mem_data["data"]["result"][0]["value"][1]), 2)

    # 3. 数据库平均QPS
    qps_query = f"avg(rate(mysql_global_status_queries_total{{instance=~'{instance_addr}'}}[5m]))[{time_range}h:5m]"
    qps_data = query_prom(qps_query)
    if qps_data and qps_data["status"] == "success" and qps_data["data"]["result"]:
        res["data"]["qps_avg"] = int(float(qps_data["data"]["result"][0]["value"][1]))

    # 4. 数据库平均TPS
    tps_query = f"avg(rate(mysql_global_status_com_commit{{instance=~'{instance_addr}'}}[5m]))[{time_range}h:5m]"
    tps_data = query_prom(tps_query)
    if tps_data and tps_data["status"] == "success" and tps_data["data"]["result"]:
        res["data"]["tps_avg"] = int(float(tps_data["data"]["result"][0]["value"][1]))

    # 5. 连接数波动检测（标准差判断稳定性）
    conn_query = f"stddev_over_time(mysql_global_status_threads_connected{{instance=~'{instance_addr}'}}[{time_range}h])"
    conn_data = query_prom(conn_query)
    if conn_data and conn_data["status"] == "success" and conn_data["data"]["result"]:
        std_dev = float(conn_data["data"]["result"][0]["value"][1])
        if std_dev > 50:
            res["data"]["conn_trend"] = "fluctuating"
            res["risk"].append("数据库连接数波动剧烈，存在突发流量或连接泄露隐患")

    # 6. 时段慢查询增量统计
    slow_query = f"increase(mysql_global_status_slow_queries{{instance=~'{instance_addr}'}}[{time_range}h])"
    slow_data = query_prom(slow_query)
    if slow_data and slow_data["status"] == "success" and slow_data["data"]["result"]:
        slow_total = int(float(slow_data["data"]["result"][0]["value"][1]))
        if slow_total > 500:
            res["data"]["slow_query_trend"] = "rising"
            res["risk"].append(f"近{time_range}h慢查询累计增长{slow_total}条，数据库性能持续劣化")

    # 7. InnoDB读写比例分析
    read_query = f"sum(rate(mysql_innodb_pages_read_total{{instance=~'{instance_addr}'}}[5m]))[{time_range}h:5m]"
    write_query = f"sum(rate(mysql_innodb_pages_written_total{{instance=~'{instance_addr}'}}[5m]))[{time_range}h:5m]"
    read_data = query_prom(read_query)
    write_data = query_prom(write_query)
    if read_data and write_data and read_data["data"]["result"] and write_data["data"]["result"]:
        read_val = float(read_data["data"]["result"][0]["value"][1])
        write_val = float(write_data["data"]["result"][0]["value"][1])
        if write_val > 0:
            res["data"]["innodb_read_write_ratio"] = round(read_val / write_val, 2)

    # 资源负载风险判定
    if res["data"]["cpu_usage_avg"] > 80:
        res["risk"].append(f"近{time_range}h服务器CPU平均使用率超80%，存在严重资源瓶颈")
    if res["data"]["mem_usage_avg"] > 85:
        res["risk"].append(f"近{time_range}h服务器内存平均使用率超85%，存在OOM宕机风险")

    # 智能趋势总结
    if len(res["risk"]) == 0:
        res["data"]["trend_analysis"] = f"近{time_range}小时数据库资源负载、业务流量、性能指标整体平稳，无隐性瓶颈，业务运行稳定"
    else:
        res["data"]["trend_analysis"] = f"近{time_range}小时数据库存在多项指标异常，资源负载或业务流量波动异常，需针对性优化整改"

    print(res)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", help="metrics")
    parser.add_argument("--prom-url", required=True, help="Prometheus服务地址")
    parser.add_argument("--instance", required=True, help="MySQL实例标签 IP:3306")
    parser.add_argument("--time-range", type=int, default=24, help="统计时长（小时）")
    args = parser.parse_args()

    if args.action == "metrics":
        prometheus_metrics_inspect(args.prom_url, args.instance, args.time_range)

if __name__ == "__main__":
    main()
