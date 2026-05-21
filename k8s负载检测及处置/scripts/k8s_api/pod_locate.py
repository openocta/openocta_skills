#!/usr/bin/env python3
import argparse
import subprocess
import json
from datetime import datetime

def parse_args():
    parser = argparse.ArgumentParser(description="K8s高负载Pod定位脚本")
    parser.add_argument("action", choices=["find-high-load"], help="执行动作，仅支持find-high-load（定位高负载Pod）")
    parser.add_argument("--node-name", help="节点名称（可选，不填则查询集群所有节点）")
    parser.add_argument("--metric", default="cpu,mem", help="负载指标，支持cpu,mem（多个用逗号分隔），默认cpu,mem")
    parser.add_argument("--threshold", type=int, default=70, help="负载阈值（百分比），默认70%")
    parser.add_argument("--sort", default="desc", choices=["asc", "desc"], help="排序方式，默认降序（desc）")
    parser.add_argument("--detail", action="store_true", help="是否显示Pod关联明细（命名空间、控制器类型等）")
    return parser.parse_args()

def check_node_high_load(node_name, metric, threshold):
    """校验节点是否处于高负载状态（CPU>阈值或内存>阈值）"""
    try:
        output = subprocess.check_output(["kubectl", "top", "node", node_name, "--no-headers"]).decode().split()
        cpu_usage = float(output[2].strip("%"))
        mem_usage = float(output[5].strip("%"))
        metrics = {"cpu": cpu_usage, "mem": mem_usage}
        for m in metric.split(","):
            if metrics.get(m, 0) > threshold:
                return True, metrics
        return False, metrics
    except subprocess.CalledProcessError as e:
        return False, f"节点负载校验失败：{e.output.decode()}"

def get_high_load_pods(node_name, metric, threshold, sort):
    """获取高负载Pod列表（CPU>阈值或内存>阈值）"""
    pods = []
    # 构建查询条件（按节点筛选，无节点则查询所有）
    field_selector = f"spec.nodeName={node_name}" if node_name else ""
    cmd = ["kubectl", "top", "pods", "--all-namespaces", "--no-headers"]
    if field_selector:
        cmd.extend(["--field-selector", field_selector])
    
    try:
        output = subprocess.check_output(cmd).decode().split("\n")
        for line in output:
            if line.strip():
                parts = line.split()
                namespace = parts[0]
                pod_name = parts[1]
                cpu_usage = parts[2]
                mem_usage = parts[3]
                
                # 转换CPU/内存使用率为百分比（适配m、Mi等单位）
                cpu_usage_percent = round(float(cpu_usage.replace("m", "")) / 1000 * 100, 2) if "m" in cpu_usage else float(cpu_usage)
                mem_usage_percent = round(float(mem_usage.replace("Mi", "")) / 1024 * 100, 2) if "Mi" in mem_usage else float(mem_usage)
                
                # 筛选高负载Pod
                cpu_high = "cpu" in metric and cpu_usage_percent > threshold
                mem_high = "mem" in metric and mem_usage_percent > threshold
                if cpu_high or mem_high:
                    pod = {
                        "namespace": namespace,
                        "pod_name": pod_name,
                        "cpu_usage": cpu_usage,
                        "cpu_usage_percent": cpu_usage_percent,
                        "mem_usage": mem_usage,
                        "mem_usage_percent": mem_usage_percent,
                        "high_load_type": "cpu" if cpu_high and not mem_high else "mem" if mem_high and not cpu_high else "both",
                        "running_time": get_pod_running_time(namespace, pod_name)
                    }
                    pods.append(pod)
        
        # 排序（按CPU/内存使用率降序/升序）
        sort_key = "cpu_usage_percent" if "cpu" in metric.split(",") else "mem_usage_percent"
        pods.sort(key=lambda x: x[sort_key], reverse=(sort == "desc"))
        return pods, ""
    except subprocess.CalledProcessError as e:
        return [], f"高负载Pod查询失败：{e.output.decode()}"

def get_pod_running_time(namespace, pod_name):
    """获取Pod运行时长"""
    try:
        output = subprocess.check_output(
            ["kubectl", "get", "pod", pod_name, "-n", namespace, "-o", "jsonpath='{.status.startTime}'"],
            stderr=subprocess.STDOUT
        ).decode().strip("'")
        start_time = datetime.fromisoformat(output.replace("Z", "+00:00"))
        running_time = datetime.utcnow() - start_time
        return str(running_time).split(".")[0]  # 去掉毫秒
    except Exception as e:
        return f"获取失败：{str(e)}"

def get_pod_details(namespace, pod_name):
    """获取Pod关联明细（控制器类型、容器镜像、资源限制）"""
    try:
        output = subprocess.check_output(
            ["kubectl", "get", "pod", pod_name, "-n", namespace, "-o", "json"],
            stderr=subprocess.STDOUT
        ).decode()
        pod_json = json.loads(output)
        
        # 控制器类型（Deployment/DaemonSet等）
        controller_type = "None"
        owner_references = pod_json.get("metadata", {}).get("ownerReferences", [])
        if owner_references:
            controller_type = owner_references[0]["kind"]
        
        # 容器镜像
        containers = pod_json.get("spec", {}).get("containers", [])
        container_images = [container.get("image", "unknown") for container in containers]
        
        # 资源限制
        resources = pod_json.get("spec", {}).get("containers", [])[0].get("resources", {})
        limits = resources.get("limits", {})
        requests = resources.get("requests", {})
        
        return {
            "controller_type": controller_type,
            "container_images": container_images,
            "resources": {
                "limits": limits,
                "requests": requests
            }
        }
    except Exception as e:
        return {"error": f"明细获取失败：{str(e)}"}

def main():
    args = parse_args()
    result = {"status": "success", "data": {}, "msg": ""}
    
    # 前置校验：若指定节点，需确认节点处于高负载状态
    if args.node_name:
        is_high_load, node_metrics = check_node_high_load(args.node_name, args.metric, args.threshold)
        if not isinstance(node_metrics, dict):
            result["status"] = "failed"
            result["msg"] = node_metrics
            print(json.dumps(result, indent=2))
            exit(1)
        if not is_high_load:
            result["status"] = "failed"
            result["msg"] = f"节点{args.node_name}未处于高负载状态（CPU：{node_metrics['cpu']}%，内存：{node_metrics['mem']}%，阈值：{args.threshold}%）"
            print(json.dumps(result, indent=2))
            exit(0)
    
    # 获取高负载Pod列表
    high_load_pods, err = get_high_load_pods(args.node_name, args.metric, args.threshold, args.sort)
    if err:
        result["status"] = "failed"
        result["msg"] = err
        print(json.dumps(result, indent=2))
        exit(1)
    
    # 获取Pod关联明细（若需）
    if args.detail:
        for pod in high_load_pods:
            pod["details"] = get_pod_details(pod["namespace"], pod["pod_name"])
    
    # 标记TOP3核心高负载Pod
    top3_pods = high_load_pods[:3] if len(high_load_pods) >=3 else high_load_pods
    
    # 组装结果
    result["data"]["high_load_pod_list"] = high_load_pods
    result["data"]["top3_high_load_pods"] = top3_pods
    result["data"]["high_load_pod_count"] = len(high_load_pods)
    result["msg"] = f"共找到{len(high_load_pods)}个高负载Pod（{args.metric}使用率>{args.threshold}%）" if high_load_pods else "未找到高负载Pod"
    
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
    