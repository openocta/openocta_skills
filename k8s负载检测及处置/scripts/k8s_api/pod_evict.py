#!/usr/bin/env python3
import argparse
import subprocess
import json
import time
import re

def parse_args():
    parser = argparse.ArgumentParser(description="K8s高负载Pod驱逐脚本（无残留配置）")
    parser.add_argument("action", choices=["preview", "execute"], help="执行动作：preview（预览）、execute（执行）")
    parser.add_argument("--pod-name", required=True, help="Pod名称")
    parser.add_argument("--namespace", default="default", help="Pod所属命名空间，默认default")
    parser.add_argument("--target-node", help="目标调度节点（可选）")
    parser.add_argument("--confirm", action="store_true", help="执行execute动作时，需加--confirm")
    return parser.parse_args()

def check_pod_status(namespace, pod_name):
    try:
        output = subprocess.check_output(
            ["kubectl", "get", "pod", pod_name, "-n", namespace, "-o", "jsonpath='{.status.phase}'"],
            stderr=subprocess.STDOUT
        ).decode().strip("'")
        return (True, "Running") if output == "Running" else (False, f"状态异常：{output}")
    except subprocess.CalledProcessError:
        return False, "Pod不存在"

def is_core_component_pod(namespace, pod_name):
    core_namespaces = ["kube-system", "kube-public", "kube-node-lease"]
    core_keywords = ["kube-apiserver", "etcd", "calico", "coredns", "kube-controller-manager", "kube-scheduler"]
    return namespace in core_namespaces or any(key in pod_name for key in core_keywords)

def convert_cpu_to_milli(cpu_str):
    if not cpu_str:
        return 0
    if cpu_str.endswith("m"):
        return int(cpu_str[:-1])
    return int(float(cpu_str) * 1000)

def convert_mem_to_mi(mem_str):
    if not mem_str:
        return 0
    mem_str = mem_str.upper()
    match = re.match(r"(\d+)([A-Z]+)", mem_str)
    if not match:
        return 0
    num, unit = match.groups()
    num = int(num)
    if unit in ["KI", "K"]:
        return num // 1024
    elif unit in ["MI", "M"]:
        return num
    elif unit in ["GI", "G"]:
        return num * 1024
    return num // 1024 // 1024

def get_pod_resource_requests(namespace, pod_name):
    try:
        pod = json.loads(subprocess.check_output(
            ["kubectl", "get", "pod", pod_name, "-n", namespace, "-o", "json"], stderr=subprocess.STDOUT))
        cpu = mem = 0
        for c in pod.get("spec", {}).get("containers", []):
            r = c.get("resources", {}).get("requests", {})
            cpu += convert_cpu_to_milli(r.get("cpu", "100m"))
            mem += convert_mem_to_mi(r.get("memory", "128Mi"))
        return {"cpu_m": cpu, "mem_mi": mem}, ""
    except:
        return {"cpu_m": 100, "mem_mi": 128}, ""

def get_node_allocatable(node):
    try:
        n = json.loads(subprocess.check_output(["kubectl", "get", "node", node, "-o", "json"], stderr=subprocess.STDOUT))
        a = n.get("status", {}).get("allocatable", {})
        return {"cpu": convert_cpu_to_milli(a.get("cpu", "1")), "mem": convert_mem_to_mi(a.get("memory", "1Gi"))}
    except:
        return {"cpu": 2000, "mem": 8192}

def get_node_used(node):
    try:
        t = subprocess.check_output(["kubectl", "top", "node", node, "--no-headers"], stderr=subprocess.STDOUT).decode().split()
        return {"cpu": int(t[1].replace("m", "")), "mem": int(t[3].replace("Mi", ""))}
    except:
        return {"cpu": 0, "mem": 0}

def check_node_ok(node, need_cpu, need_mem):
    try:
        a = get_node_allocatable(node)
        u = get_node_used(node)
        return (a["cpu"] - u["cpu"] >= need_cpu) and (a["mem"] - u["mem"] >= need_mem)
    except:
        return False

def find_best_node(need_cpu, need_mem):
    try:
        nodes = subprocess.check_output(
            ["kubectl", "get", "nodes", "-o", "jsonpath={.items[*].metadata.name}"],
            stderr=subprocess.STDOUT).decode().strip().split()
        for node in nodes:
            ready = subprocess.check_output(
                ["kubectl", "get", "node", node, "-o", "jsonpath={.status.conditions[?(@.type=='Ready')].status}"],
                stderr=subprocess.STDOUT).decode().strip() == "True"
            if ready and check_node_ok(node, need_cpu, need_mem):
                return node
        return None
    except:
        return None

def preview_evict_strategy(ns, pod, target_node):
    ok, msg = check_pod_status(ns, pod)
    if not ok:
        return {}, msg
    if is_core_component_pod(ns, pod):
        return {}, "禁止驱逐核心组件"

    req, _ = get_pod_resource_requests(ns, pod)
    if not target_node:
        target_node = find_best_node(req["cpu_m"], req["mem_mi"])
        if not target_node:
            return {}, "无满足资源需求的节点"

    return {
        "pod": pod,
        "namespace": ns,
        "action": "仅驱逐，不修改控制器，不留nodeSelector",
        "suggest_target_node": target_node,
        "pod_requests": req,
        "note": "安全无残留"
    }, ""

def approve_evict():
    print("\n===== 高危操作确认 =====")
    print("即将执行：仅删除Pod，不修改任何配置，无残留")
    inp = input("输入 approve 确认：").strip().lower()
    return inp == "approve"

def execute_evict(ns, pod, target_node):
    ok, msg = check_pod_status(ns, pod)
    if not ok:
        return {}, msg
    if is_core_component_pod(ns, pod):
        return {}, "禁止驱逐核心组件"

    req, _ = get_pod_resource_requests(ns, pod)
    if target_node and not check_node_ok(target_node, req["cpu_m"], req["mem_mi"]):
        return {}, "目标节点资源不足"

    if not approve_evict():
        return {}, "已取消"

    # 核心：只删 Pod，不做任何配置修改
    try:
        subprocess.run(["kubectl", "delete", "pod", pod, "-n", ns, "--grace-period=30"], check=True)
    except subprocess.CalledProcessError as e:
        return {}, f"驱逐失败：{str(e)}"

    time.sleep(8)
    return {
        "status": "success",
        "msg": "Pod已驱逐，将由K8s自动调度",
        "note": "无任何配置残留、无nodeSelector、无标签"
    }, ""

def main():
    args = parse_args()
    result = {"status": "success", "data": {}, "msg": ""}

    if args.action == "preview":
        data, err = preview_evict_strategy(args.namespace, args.pod_name, args.target_node)
        if err:
            result["status"] = "failed"
            result["msg"] = err
        else:
            result["data"] = data
            result["msg"] = "预览成功（无残留）"

    elif args.action == "execute":
        if not args.confirm:
            result["status"] = "failed"
            result["msg"] = "必须加 --confirm"
            print(json.dumps(result, indent=2))
            return
        data, err = execute_evict(args.namespace, args.pod_name, args.target_node)
        if err:
            result["status"] = "failed"
            result["msg"] = err
        else:
            result["data"] = data
            result["msg"] = "执行成功（无任何残留）"

    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()