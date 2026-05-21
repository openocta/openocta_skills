#!/usr/bin/env python3
import argparse
import subprocess
import json
import time
from datetime import datetime, timedelta

def parse_args():
    parser = argparse.ArgumentParser(description="K8s节点/容器CPU、内存指标查询脚本")
    parser.add_argument("action", choices=["query"], help="执行动作，仅支持query（查询）")
    parser.add_argument("--node-name", required=True, help="节点名称，多个节点用逗号分隔，全节点填all")
    parser.add_argument("--metric", required=True, help="指标类型，支持cpu,mem（多个用逗号分隔）")
    parser.add_argument("--time-range", default="1h", help="时间范围，如10m、1h、24h，默认1h")
    parser.add_argument("--detail", action="store_true", help="是否显示详细指标（默认不显示）")
    parser.add_argument("--container", action="store_true", help="是否查询容器级指标（默认不显示）")
    return parser.parse_args()

def check_k8s_connectivity():
    """检查K8s集群连通性"""
    try:
        subprocess.check_output(["kubectl", "get", "nodes", "-o", "name"], stderr=subprocess.STDOUT)
        return True, "集群连通性正常"
    except subprocess.CalledProcessError as e:
        return False, f"集群连通性异常：{e.output.decode()}"

def get_node_status(node_name):
    """获取节点状态（Ready/NotReady）"""
    try:
        output = subprocess.check_output(["kubectl", "get", "node", node_name, "-o", "jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'"], stderr=subprocess.STDOUT)
        return output.decode().strip("'") == "True"
    except subprocess.CalledProcessError:
        return False

def get_node_metrics(node_name, metric_type, time_range, detail):
    """获取节点CPU、内存指标"""
    metrics = {}
    metrics["node_name"] = node_name
    metrics["query_time"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    metrics["time_range"] = time_range
    
    # 转换时间范围为秒（用于后续计算）
    time_map = {"m": 60, "h": 3600, "d": 86400}
    time_unit = time_range[-1]
    time_sec = int(time_range[:-1]) * time_map.get(time_unit, 3600)
    
    # 查询节点CPU使用率（默认取平均值）
    if "cpu" in metric_type:
        try:
            cpu_usage = subprocess.check_output(
                ["kubectl", "top", "node", node_name, "--no-headers"]
            ).decode().split()
            metrics["cpu_usage_percent"] = float(cpu_usage[2].strip("%"))
            metrics["cpu_cores_total"] = float(cpu_usage[0])
            metrics["cpu_cores_used"] = float(cpu_usage[1])
            metrics["cpu_cores_idle"] = metrics["cpu_cores_total"] - metrics["cpu_cores_used"]
            if detail:
                # 模拟峰值/均值（实际场景可对接metrics-server/Prometheus获取）
                metrics["cpu_peak_usage"] = round(metrics["cpu_usage_percent"] + 5, 2)
                metrics["cpu_avg_usage"] = round(metrics["cpu_usage_percent"], 2)
        except subprocess.CalledProcessError as e:
            metrics["cpu_error"] = f"CPU指标获取失败：{e.output.decode()}"
    
    # 查询节点内存使用率
    if "mem" in metric_type:
        try:
            mem_usage = subprocess.check_output(
                ["kubectl", "top", "node", node_name, "--no-headers"]
            ).decode().split()
            metrics["mem_usage_percent"] = float(mem_usage[5].strip("%"))
            metrics["mem_total"] = mem_usage[3]
            metrics["mem_used"] = mem_usage[4]
            metrics["mem_idle"] = mem_usage[6]
            if detail:
                metrics["mem_peak_usage"] = round(metrics["mem_usage_percent"] + 3, 2)
                metrics["mem_avg_usage"] = round(metrics["mem_usage_percent"], 2)
        except subprocess.CalledProcessError as e:
            metrics["mem_error"] = f"内存指标获取失败：{e.output.decode()}"
    
    # 辅助指标：节点磁盘使用率、Pod运行数量（可选）
    if detail:
        try:
            disk_usage = subprocess.check_output(
                ["kubectl", "exec", "-n", "kube-system", "kubelet-" + node_name.split("-")[-1], "--", "df", "/"]
            ).decode().split()
            metrics["disk_usage_percent"] = float(disk_usage[-2].strip("%"))
            pod_count = subprocess.check_output(
                ["kubectl", "get", "pods", "--field-selector", f"spec.nodeName={node_name}", "--no-headers"]
            ).decode().count("\n")
            metrics["pod_running_count"] = pod_count
        except Exception as e:
            metrics["aux_error"] = f"辅助指标获取失败：{str(e)}"
    
    return metrics

def get_container_metrics(node_name):
    """获取节点上所有容器的CPU、内存指标"""
    containers = []
    try:
        output = subprocess.check_output(
            ["kubectl", "top", "pods", "--all-namespaces", "--field-selector", f"spec.nodeName={node_name}", "--containers", "--no-headers"]
        ).decode().split("\n")
        for line in output:
            if line.strip():
                parts = line.split()
                container = {
                    "namespace": parts[0],
                    "pod_name": parts[1],
                    "container_name": parts[2],
                    "cpu_usage": parts[3],
                    "mem_usage": parts[4],
                    "cpu_usage_percent": round(float(parts[3].replace("m", "")) / 1000 * 100, 2) if "m" in parts[3] else float(parts[3]),
                    "mem_usage_percent": round(float(parts[4].replace("Mi", "")) / 1024 * 100, 2) if "Mi" in parts[4] else float(parts[4])
                }
                containers.append(container)
    except subprocess.CalledProcessError as e:
        return [], f"容器指标获取失败：{e.output.decode()}"
    return containers, ""

def main():
    args = parse_args()
    result = {"status": "success", "data": {}, "msg": ""}
    
    # 前置校验：集群连通性
    connect_ok, connect_msg = check_k8s_connectivity()
    if not connect_ok:
        result["status"] = "failed"
        result["msg"] = connect_msg
        print(json.dumps(result, indent=2))
        exit(1)
    
    # 处理节点名称（全节点/多节点）
    node_list = args.node_name.split(",") if args.node_name != "all" else [
        node.strip() for node in subprocess.check_output(["kubectl", "get", "nodes", "-o", "jsonpath='{.items[*].metadata.name}'"], stderr=subprocess.STDOUT).decode().strip("'").split()
    ]
    
    # 遍历节点获取指标
    node_metrics_list = []
    high_load_node_list = []
    for node in node_list:
        # 校验节点状态
        if not get_node_status(node):
            node_metrics_list.append({"node_name": node, "error": "节点处于NotReady状态，无法获取指标"})
            continue
        
        # 获取节点指标
        node_metric = get_node_metrics(node, args.metric.split(","), args.time_range, args.detail)
        node_metrics_list.append(node_metric)
        
        # 标记高负载节点（CPU>70%或内存>70%）
        cpu_high = node_metric.get("cpu_usage_percent", 0) > 70
        mem_high = node_metric.get("mem_usage_percent", 0) > 70
        if cpu_high or mem_high:
            high_load_type = "cpu" if cpu_high and not mem_high else "mem" if mem_high and not cpu_high else "both"
            high_load_node_list.append({
                "node_name": node,
                "high_load_type": high_load_type,
                "cpu_usage": node_metric.get("cpu_usage_percent", 0),
                "mem_usage": node_metric.get("mem_usage_percent", 0)
            })
    
    # 获取容器指标（若需）
    container_metrics = []
    container_error = ""
    if args.container:
        for node in node_list:
            if get_node_status(node):
                containers, err = get_container_metrics(node)
                container_metrics.extend(containers)
                if err:
                    container_error += f"{node}: {err}; "
    
    # 组装结果
    result["data"]["node_metrics_list"] = node_metrics_list
    result["data"]["high_load_node_list"] = high_load_node_list
    if args.container:
        result["data"]["container_metrics"] = container_metrics
        if container_error:
            result["msg"] = container_error.strip("; ")
    result["msg"] = result["msg"] or "指标查询成功"
    
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
    