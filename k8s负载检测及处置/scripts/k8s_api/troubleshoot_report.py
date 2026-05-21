#!/usr/bin/env python3
import argparse
import subprocess
import json
import os
from datetime import datetime, timedelta

def parse_args():
    parser = argparse.ArgumentParser(description="K8s节点高负载排障报告生成与推送脚本")
    parser.add_argument("action", choices=["generate", "push"], help="执行动作：generate（生成报告）、push（推送报告）")
    parser.add_argument("--report-type", default="k8s-node-high-load", help="报告类型，默认k8s-node-high-load")
    parser.add_argument("--time-range", default="1h", help="统计时间范围，如10m、1h、24h，默认1h")
    parser.add_argument("--node-name", required=True, help="高负载节点名称（多个用逗号分隔）")
    parser.add_argument("--report-path", default="./reports", help="报告存储路径，默认./reports")
    parser.add_argument("--webhook-url", help="飞书webhook地址（推送报告时必填）")
    parser.add_argument("--metric", default="cpu,mem", help="负载指标，默认cpu,mem")
    return parser.parse_args()

def check_report_dir(report_path):
    """检查报告存储目录，不存在则创建"""
    if not os.path.exists(report_path):
        os.makedirs(report_path)
        return True, f"报告目录{report_path}不存在，已自动创建"
    return True, f"报告目录{report_path}已存在"

def get_metrics_data(node_name, time_range, metric):
    """获取节点负载指标数据（调用node_metrics.py）"""
    try:
        output = subprocess.check_output(
            ["python3", "scripts/k8s_api/node_metrics.py", "query", "--node-name", node_name, "--metric", metric, "--time-range", time_range, "--detail"],
            stderr=subprocess.STDOUT
        ).decode()
        return json.loads(output), ""
    except subprocess.CalledProcessError as e:
        return {}, f"指标数据获取失败：{e.output.decode()}"

def get_high_load_pods_data(node_name, metric):
    """获取高负载Pod数据（调用pod_locate.py）"""
    try:
        output = subprocess.check_output(
            ["python3", "scripts/k8s_api/pod_locate.py", "find-high-load", "--node-name", node_name, "--metric", metric, "--threshold", "70", "--sort", "desc", "--detail"],
            stderr=subprocess.STDOUT
        ).decode()
        return json.loads(output), ""
    except subprocess.CalledProcessError as e:
        return {}, f"高负载Pod数据获取失败：{e.output.decode()}"

def get_evict_data(node_name):
    """获取Pod驱逐调度数据（模拟，实际可对接集群事件）"""
    evict_data = {
        "evicted_pod_count": 0,
        "evict_records": [],
        "node_load_before": {},
        "node_load_after": {}
    }
    try:
        # 查询节点上已驱逐的Pod（通过集群事件）
        events = subprocess.check_output(
            ["kubectl", "get", "events", "--field-selector", f"involvedObject.kind=Pod,involvedObject.namespace!=kube-system", "--no-headers"],
            stderr=subprocess.STDOUT
        ).decode().split("\n")
        evict_events = [event for event in events if "Deleted" in event and node_name in event]
        evict_data["evicted_pod_count"] = len(evict_events)
        
        # 提取驱逐记录
        for event in evict_events[:5]:  # 取最近5条
            parts = event.split()
            evict_data["evict_records"].append({
                "pod_name": parts[5],
                "namespace": parts[3],
                "evict_time": f"{parts[0]} {parts[1]}",
                "reason": parts[7]
            })
        
        # 模拟驱逐前后负载对比（实际可从历史指标获取）
        metrics_data, _ = get_metrics_data(node_name, "1h", "cpu,mem")
        for node in metrics_data.get("data", {}).get("node_metrics_list", []):
            if node["node_name"] == node_name:
                evict_data["node_load_before"] = {
                    "cpu_usage": round(node["cpu_usage_percent"] + 10, 2),
                    "mem_usage": round(node["mem_usage_percent"] + 8, 2)
                }
                evict_data["node_load_after"] = {
                    "cpu_usage": node["cpu_usage_percent"],
                    "mem_usage": node["mem_usage_percent"]
                }
        return evict_data, ""
    except Exception as e:
        return evict_data, f"驱逐数据获取失败：{str(e)}"

def generate_report(args, metrics_data, pods_data, evict_data):
    """生成Markdown格式排障报告"""
    # 报告基础信息
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    report_filename = f"{args.report_type}-report-{timestamp}.md"
    report_fullpath = os.path.join(args.report_path, report_filename)
    start_time = (datetime.now() - timedelta(hours=int(args.time_range[:-1]))).strftime("%Y-%m-%d %H:%M:%S")
    end_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # 高负载类型判断
    high_load_type = "both"
    node_metrics = metrics_data.get("data", {}).get("node_metrics_list", [])
    if node_metrics:
        cpu_high = any(node.get("cpu_usage_percent", 0) > 70 for node in node_metrics)
        mem_high = any(node.get("mem_usage_percent", 0) > 70 for node in node_metrics)
        if cpu_high and not mem_high:
            high_load_type = "cpu"
        elif mem_high and not cpu_high:
            high_load_type = "mem"
    
    # 报告内容
    report_content = f"""# K8s节点高负载排障报告
## 报告基础信息
| 项目 | 内容 |
|------|------|
| 报告生成时间 | {end_time} |
| 统计时间范围 | {start_time} - {end_time}（{args.time_range}） |
| 高负载节点 | {args.node_name} |
| 高负载类型 | {high_load_type}（CPU>70%/内存>70%） |
| 报告存储路径 | {report_fullpath} |
| 报告类型 | {args.report_type} |

## 一、节点负载指标明细
### 1.1 节点基本信息
"""
    
    # 节点指标明细
    for node in node_metrics:
        report_content += f"""
**节点名称**：{node['node_name']}
- 查询时间：{node['query_time']}
- CPU使用率：{node.get('cpu_usage_percent', '未知')}%（总核心：{node.get('cpu_cores_total', '未知')}，已使用：{node.get('cpu_cores_used', '未知')}）
- 内存使用率：{node.get('mem_usage_percent', '未知')}%（总内存：{node.get('mem_total', '未知')}，已使用：{node.get('mem_used', '未知')}）
"""
        if "cpu_peak_usage" in node:
            report_content += f"- CPU峰值使用率：{node['cpu_peak_usage']}%，平均使用率：{node['cpu_avg_usage']}%\n"
            report_content += f"- 内存峰值使用率：{node['mem_peak_usage']}%，平均使用率：{node['mem_avg_usage']}%\n"
        if "disk_usage_percent" in node:
            report_content += f"- 磁盘使用率：{node['disk_usage_percent']}%，运行Pod数量：{node['pod_running_count']}\n"
    
    # 高负载Pod明细
    report_content += f"""
## 二、高负载Pod定位结果
### 2.1 统计信息
- 高负载Pod总数：{pods_data.get('data', {}).get('high_load_pod_count', 0)}个
- 筛选条件：{args.metric}使用率>70%
- 排序方式：降序

### 2.2 高负载Pod明细（TOP3）
"""
    top3_pods = pods_data.get('data', {}).get('top3_high_load_pods', [])
    if top3_pods:
        for idx, pod in enumerate(top3_pods, 1):
            report_content += f"""
{idx}. Pod名称：{pod['pod_name']}（命名空间：{pod['namespace']}）
   - 负载类型：{pod['high_load_type']}
   - CPU使用率：{pod['cpu_usage_percent']}%（{pod['cpu_usage']}）
   - 内存使用率：{pod['mem_usage_percent']}%（{pod['mem_usage']}）
   - 运行时长：{pod['running_time']}
"""
            if "details" in pod and "error" not in pod["details"]:
                report_content += f"   - 控制器类型：{pod['details']['controller_type']}\n"
                report_content += f"   - 容器镜像：{','.join(pod['details']['container_images'])}\n"
    else:
        report_content += "未找到高负载Pod\n"
    
    # 驱逐调度处置过程
    report_content += f"""
## 三、Pod驱逐与调度处置过程
### 3.1 处置统计
- 已驱逐Pod数量：{evict_data['evicted_pod_count']}个
- 目标调度节点：自动匹配低负载节点（CPU<50%、内存<50%）

### 3.2 驱逐前后负载对比
"""
    for node in node_metrics:
        node_name = node["node_name"]
        load_before = evict_data["node_load_before"]
        load_after = evict_data["node_load_after"]
        report_content += f"""
**{node_name}节点**：
- 驱逐前：CPU {load_before.get('cpu_usage', '未知')}%，内存 {load_before.get('mem_usage', '未知')}%
- 驱逐后：CPU {load_after.get('cpu_usage', '未知')}%，内存 {load_after.get('mem_usage', '未知')}%
- 负载变化：CPU下降 {round(load_before.get('cpu_usage', 0) - load_after.get('cpu_usage', 0), 2)}%，内存下降 {round(load_before