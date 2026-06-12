#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MySQL 实例资源使用趋势分析
从 Prometheus 获取历史数据并生成趋势报告
"""

import requests
import json
from datetime import datetime, timedelta
import time

PROMETHEUS_URL = "http://192.168.50.68:9090"

def query_prometheus(query, time_range=None):
    """查询 Prometheus 数据"""
    try:
        if time_range:
            start, end, step = time_range
            url = f"{PROMETHEUS_URL}/api/v1/query_range"
            params = {
                'query': query,
                'start': start,
                'end': end,
                'step': step
            }
        else:
            url = f"{PROMETHEUS_URL}/api/v1/query"
            params = {'query': query}
        
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        return {"status": "error", "error": str(e)}

def format_timestamp(ts):
    """格式化时间戳"""
    return datetime.fromtimestamp(ts).strftime('%H:%M')

def calculate_trend(values):
    """计算趋势（上升/下降/平稳）"""
    if len(values) < 2:
        return "数据不足", 0
    
    # 取最近几个值和之前的值比较
    recent = sum(values[-3:]) / 3 if len(values) >= 3 else values[-1]
    earlier = sum(values[:3]) / 3 if len(values) >= 3 else values[0]
    
    change = ((recent - earlier) / earlier * 100) if earlier != 0 else 0
    
    if change > 10:
        return "📈 上升", change
    elif change < -10:
        return "📉 下降", change
    else:
        return "➡️ 平稳", change

def analyze_mysql_instances():
    """分析 MySQL 实例"""
    print("=" * 70)
    print("MySQL 实例资源使用趋势分析报告")
    print(f"分析时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)
    print()
    
    # 时间范围：过去1小时
    end_time = time.time()
    start_time = end_time - 3600  # 1小时
    step = "300s"  # 5分钟间隔
    
    time_range = (start_time, end_time, step)
    
    # ========== 一、实例概览 ==========
    print("【一、实例概览】")
    print("-" * 70)
    
    result = query_prometheus("mysql_up")
    instances = []
    if result.get("status") == "success":
        for item in result["data"]["result"]:
            instance = item["metric"]["instance"]
            status = "✅ 运行中" if item["value"][1] == "1" else "❌ 异常"
            instances.append(instance)
            print(f"  • {instance}: {status}")
    
    print(f"\n  共发现 {len(instances)} 个 MySQL 实例\n")
    
    # ========== 二、系统资源趋势 ==========
    print("【二、系统资源使用趋势】")
    print("-" * 70)
    
    # CPU 使用率趋势
    print("\n1️⃣  CPU 使用率趋势 (过去1小时)")
    cpu_query = 'avg by (instance)(100 - (avg by (instance)(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100))'
    result = query_prometheus(cpu_query, time_range)
    
    if result.get("status") == "success":
        for item in result["data"]["result"]:
            instance = item["metric"]["instance"]
            values = [float(v[1]) for v in item["values"] if v[1] != 'NaN']
            
            if values:
                current = values[-1]
                avg = sum(values) / len(values)
                max_val = max(values)
                min_val = min(values)
                trend, change = calculate_trend(values)
                
                status = "🔴" if current > 80 else ("🟡" if current > 60 else "🟢")
                
                print(f"\n  {instance}:")
                print(f"    当前值: {current:.2f}% {status}")
                print(f"    平均值: {avg:.2f}%")
                print(f"    最大值: {max_val:.2f}%")
                print(f"    最小值: {min_val:.2f}%")
                print(f"    趋势: {trend} ({change:+.1f}%)")
                
                # 简单的趋势图
                print(f"    最近数据点: ", end="")
                for i, v in enumerate(values[-6:]):
                    bar_len = int(v / 5)
                    print(f"{v:.1f}%{'█' * bar_len} ", end="")
                print()
    else:
        print(f"  ❌ 查询失败: {result.get('error')}")
    
    # 内存使用率趋势
    print("\n2️⃣  内存使用率趋势 (过去1小时)")
    mem_query = '(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100'
    result = query_prometheus(mem_query, time_range)
    
    if result.get("status") == "success":
        for item in result["data"]["result"]:
            instance = item["metric"]["instance"]
            values = [float(v[1]) for v in item["values"] if v[1] != 'NaN']
            
            if values:
                current = values[-1]
                avg = sum(values) / len(values)
                max_val = max(values)
                min_val = min(values)
                trend, change = calculate_trend(values)
                
                status = "🔴" if current > 85 else ("🟡" if current > 70 else "🟢")
                
                print(f"\n  {instance}:")
                print(f"    当前值: {current:.2f}% {status}")
                print(f"    平均值: {avg:.2f}%")
                print(f"    最大值: {max_val:.2f}%")
                print(f"    最小值: {min_val:.2f}%")
                print(f"    趋势: {trend} ({change:+.1f}%)")
    else:
        print(f"  ❌ 查询失败: {result.get('error')}")
    
    # 系统负载趋势
    print("\n3️⃣  系统负载趋势 (Load1)")
    load_query = 'node_load1'
    result = query_prometheus(load_query, time_range)
    
    if result.get("status") == "success":
        for item in result["data"]["result"]:
            instance = item["metric"]["instance"]
            values = [float(v[1]) for v in item["values"] if v[1] != 'NaN']
            
            if values:
                current = values[-1]
                avg = sum(values) / len(values)
                max_val = max(values)
                trend, change = calculate_trend(values)
                
                print(f"\n  {instance}:")
                print(f"    当前值: {current:.2f}")
                print(f"    平均值: {avg:.2f}")
                print(f"    最大值: {max_val:.2f}")
                print(f"    趋势: {trend} ({change:+.1f}%)")
    else:
        print(f"  ❌ 查询失败: {result.get('error')}")
    
    # ========== 三、MySQL 关键指标 ==========
    print("\n" + "=" * 70)
    print("【三、MySQL 关键指标趋势】")
    print("-" * 70)
    
    # 连接数趋势
    print("\n1️⃣  连接数趋势")
    conn_query = 'mysql_global_status_threads_connected'
    result = query_prometheus(conn_query, time_range)
    
    if result.get("status") == "success" and result["data"]["result"]:
        for item in result["data"]["result"]:
            instance = item["metric"]["instance"]
            values = [float(v[1]) for v in item["values"] if v[1] != 'NaN']
            
            if values:
                current = values[-1]
                avg = sum(values) / len(values)
                max_val = max(values)
                min_val = min(values)
                trend, change = calculate_trend(values)
                
                print(f"\n  {instance}:")
                print(f"    当前连接: {int(current)}")
                print(f"    平均连接: {avg:.1f}")
                print(f"    最大连接: {int(max_val)}")
                print(f"    最小连接: {int(min_val)}")
                print(f"    趋势: {trend} ({change:+.1f}%)")
    else:
        print("  ℹ️  未获取到连接数趋势数据")
    
    # 查询速率趋势
    print("\n2️⃣  查询速率趋势 (QPS)")
    qps_query = 'rate(mysql_global_status_questions[5m])'
    result = query_prometheus(qps_query, time_range)
    
    if result.get("status") == "success" and result["data"]["result"]:
        for item in result["data"]["result"]:
            instance = item["metric"]["instance"]
            values = [float(v[1]) for v in item["values"] if v[1] != 'NaN']
            
            if values:
                current = values[-1]
                avg = sum(values) / len(values)
                max_val = max(values)
                trend, change = calculate_trend(values)
                
                print(f"\n  {instance}:")
                print(f"    当前 QPS: {current:.2f}")
                print(f"    平均 QPS: {avg:.2f}")
                print(f"    最大 QPS: {max_val:.2f}")
                print(f"    趋势: {trend} ({change:+.1f}%)")
    else:
        print("  ℹ️  未获取到 QPS 趋势数据")
    
    # ========== 四、磁盘 I/O 趋势 ==========
    print("\n" + "=" * 70)
    print("【四、磁盘 I/O 趋势】")
    print("-" * 70)
    
    # 磁盘读取速率
    print("\n1️⃣  磁盘读取速率 (MB/s)")
    read_query = 'rate(node_disk_read_bytes_total[5m]) / 1024 / 1024'
    result = query_prometheus(read_query, time_range)
    
    if result.get("status") == "success" and result["data"]["result"]:
        instance_data = {}
        for item in result["data"]["result"]:
            instance = item["metric"]["instance"]
            device = item["metric"].get("device", "unknown")
            values = [float(v[1]) for v in item["values"] if v[1] != 'NaN']
            
            if values and instance not in instance_data:
                instance_data[instance] = {
                    'current': values[-1],
                    'avg': sum(values) / len(values),
                    'max': max(values)
                }
        
        for instance, data in instance_data.items():
            print(f"\n  {instance}:")
            print(f"    当前速率: {data['current']:.2f} MB/s")
            print(f"    平均速率: {data['avg']:.2f} MB/s")
            print(f"    最大速率: {data['max']:.2f} MB/s")
    else:
        print("  ℹ️  未获取到磁盘读取数据")
    
    # 磁盘写入速率
    print("\n2️⃣  磁盘写入速率 (MB/s)")
    write_query = 'rate(node_disk_written_bytes_total[5m]) / 1024 / 1024'
    result = query_prometheus(write_query, time_range)
    
    if result.get("status") == "success" and result["data"]["result"]:
        instance_data = {}
        for item in result["data"]["result"]:
            instance = item["metric"]["instance"]
            device = item["metric"].get("device", "unknown")
            values = [float(v[1]) for v in item["values"] if v[1] != 'NaN']
            
            if values and instance not in instance_data:
                instance_data[instance] = {
                    'current': values[-1],
                    'avg': sum(values) / len(values),
                    'max': max(values)
                }
        
        for instance, data in instance_data.items():
            print(f"\n  {instance}:")
            print(f"    当前速率: {data['current']:.2f} MB/s")
            print(f"    平均速率: {data['avg']:.2f} MB/s")
            print(f"    最大速率: {data['max']:.2f} MB/s")
    else:
        print("  ℹ️  未获取到磁盘写入数据")
    
    # ========== 五、健康度评估 ==========
    print("\n" + "=" * 70)
    print("【五、健康度评估】")
    print("-" * 70)
    
    # 获取当前值进行评估
    cpu_result = query_prometheus('avg by (instance)(100 - (avg by (instance)(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100))')
    mem_result = query_prometheus('(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100')
    conn_result = query_prometheus('mysql_global_status_threads_connected / mysql_global_variables_max_connections * 100')
    
    health_issues = []
    
    # CPU 评估
    if cpu_result.get("status") == "success":
        for item in cpu_result["data"]["result"]:
            instance = item["metric"]["instance"]
            cpu = float(item["value"][1])
            if cpu > 80:
                health_issues.append(f"🔴 {instance}: CPU 使用率过高 ({cpu:.1f}%)")
            elif cpu > 60:
                health_issues.append(f"🟡 {instance}: CPU 使用率偏高 ({cpu:.1f}%)")
    
    # 内存评估
    if mem_result.get("status") == "success":
        for item in mem_result["data"]["result"]:
            instance = item["metric"]["instance"]
            mem = float(item["value"][1])
            if mem > 85:
                health_issues.append(f"🔴 {instance}: 内存使用率过高 ({mem:.1f}%)")
            elif mem > 70:
                health_issues.append(f"🟡 {instance}: 内存使用率偏高 ({mem:.1f}%)")
    
    if health_issues:
        print("\n⚠️  发现以下问题:")
        for issue in health_issues:
            print(f"  {issue}")
    else:
        print("\n✅ 所有实例运行正常，未发现异常")
    
    # ========== 六、建议 ==========
    print("\n" + "=" * 70)
    print("【六、优化建议】")
    print("-" * 70)
    
    suggestions = []
    
    # 检查慢查询
    slow_result = query_prometheus('mysql_global_status_slow_queries')
    if slow_result.get("status") == "success":
        for item in slow_result["data"]["result"]:
            instance = item["metric"]["instance"]
            slow = int(item["value"][1])
            if slow > 1000:
                suggestions.append(f"📌 {instance}: 慢查询过多 ({slow} 条)，建议优化 SQL 或添加索引")
            elif slow > 100:
                suggestions.append(f"💡 {instance}: 存在慢查询 ({slow} 条)，建议检查慢查询日志")
    
    # 检查异常连接
    abort_result = query_prometheus('mysql_global_status_aborted_connects')
    if abort_result.get("status") == "success":
        for item in abort_result["data"]["result"]:
            instance = item["metric"]["instance"]
            aborted = int(item["value"][1])
            if aborted > 100:
                suggestions.append(f"📌 {instance}: 异常连接较多 ({aborted} 次)，建议检查连接配置或网络")
    
    if suggestions:
        for suggestion in suggestions:
            print(f"  {suggestion}")
    else:
        print("  ✅ 暂无优化建议")
    
    print("\n" + "=" * 70)
    print("报告生成完成")
    print("=" * 70)

if __name__ == "__main__":
    try:
        analyze_mysql_instances()
    except KeyboardInterrupt:
        print("\n\n报告生成已取消")
    except Exception as e:
        print(f"\n❌ 错误: {e}")
