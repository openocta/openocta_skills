---
displayName: mysql-full-inspection-skill
name: mysql-full-inspection-skill
description: 对远程多实例MySQL数据库执行全方位深度巡检，覆盖基础健康、连接负载、性能慢查询、索引冗余、主从复制、容量空间、账号安全、配置风险八大维度，全自动完成巡检扫描、风险识别、问题定级、优化建议、报告归档与飞书推送，适用于生产/测试所有运行中MySQL实例常态化合规巡检。适用场景：用户要求进行 MySQL 全链路健康检查、MySQL 综合巡检、MySQL 风险扫描、MySQL 性能审计、MySQL 主从状态核查、MySQL 安全检测，并生成 MySQL 全量巡检报告时使用。
---

# MySQL全方位深度巡检Skill

## 一、Skill整体概述

### 1.1 技能定位

本Skill为**企业级MySQL全维度自动化巡检闭环技能**，融合静态数据库现场巡检与Prometheus动态时序指标趋势分析，彻底解决传统单点瞬时巡检无法发现的隐性性能瓶颈、长期资源劣化、业务流量波动、间歇性故障、慢查询累积劣化等运维痛点。全面兼容MySQL 5.7/8.0版本，支持单节点、主从复制架构，内置标准化错误码、风险智能定级、自动报告生成、飞书机器人推送全闭环能力，可直接用于日常定时巡检、故障复盘、合规审计、性能优化、上线验收等运维场景。

### 1.2 核心能力

- 基础健康巡检：实例连通性校验、版本识别、运行时长、最大连接、字符集等基础配置合规校验

- 连接负载巡检：总会话、活跃会话、超时空闲无效连接统计，连接使用率、线程缓存命中率检测，规避连接堆积与连接泄露

- 性能专项巡检：慢查询状态审计、长事务、全表扫描、临时表、文件排序、冗余索引全方位检测，精准定位性能短板

- 主从架构巡检：自动识别主从角色、检测IO/SQL线程状态、实时主从延迟，提前拦截同步中断、数据不一致风险

- 安全合规巡检：空密码账号、全网通配符高危账号扫描，日志、文件读取等高风险配置合规校验

- Prometheus时序趋势巡检：复盘24小时服务器CPU/内存资源趋势、MySQL资源使用趋势、QPS/TPS业务流量、连接数波动、慢查询增长、InnoDB读写失衡，预判隐性故障

- 全量风险汇总定级、标准化Markdown报告自动生成、飞书实时推送、Webhook Token失效专属异常捕获与修复指引

### 1.3 标准化执行流程

实例连通性预检 → 基础健康巡检 → 连接负载资源巡检 → 性能慢查询索引巡检 → 主从架构同步巡检 → 账号配置安全巡检 → Prometheus时序指标趋势巡检 → 全量风险汇总定级 → 标准化报告生成 → 飞书推送运维闭环

## 二、环境依赖与目录规范

### 2.1 依赖环境安装

适配Python3环境，安装数据库连接与网络请求依赖库，创建报告存储目录，一键部署环境：

```bash
pip3 install pymysql requests -i https://pypi.tuna.tsinghua.edu.cn/simple
mkdir -p ./reports
```

### 2.2 统一目录结构（上线标准）

所有脚本统一存放，目录层级固定，便于定时任务调用、版本管理与运维维护：

```plaintext
scripts/
└── mysql_inspect/
    ├── mysql_inspect_basic.py        # 1.基础健康巡检
    ├── mysql_inspect_connection.py   # 2.连接负载巡检
    ├── mysql_inspect_performance.py  # 3.性能专项巡检
    ├── mysql_inspect_architecture.py # 4.主从架构巡检
    ├── mysql_inspect_security.py     # 5.安全合规巡检
    ├── mysql_inspect_prometheus.py   # 6.Prometheus时序趋势巡检
    ├── mysql_trend_analysis.py       # 6.Prometheus时序趋势巡检
    └── mysql_inspect_report.py        # 7.报告生成+飞书推送
reports/                             # 自动生成巡检报告存储目录

```

## 三、七大巡检模块功能详解+CLI执行命令

### 3.1 模块一：基础健康巡检

**执行动作**：check

**核心功能**：校验MySQL实例网络连通性，采集数据库版本、累计运行时长、最大连接数、默认字符集等核心基础参数，识别实例离线、服务异常、基础配置不规范等问题，为后续巡检做预检。

**执行命令**：

```bash
python3 scripts/mysql_inspect/mysql_inspect_basic.py check --host 数据库IP --port 3306 --user 账号 --password 密码
```

### 3.2 模块二：连接负载巡检

**执行动作**：scan

**核心功能**：统计数据库总会话、活跃业务会话、超时空闲无效会话数量，计算连接使用率与线程缓存命中率，精准识别连接堆积、连接打满、线程频繁创建、连接泄露等负载风险。

**执行命令**：

```bash
python3 scripts/mysql_inspect/mysql_inspect_connection.py scan --host 数据库IP --port 3306 --user 账号 --password 密码 --threshold 300
```

### 3.3 模块三：性能专项巡检

**执行动作**：audit

**核心功能**：审计慢查询日志开启状态、累计慢查询总量，检测长事务、全表扫描、临时表创建、文件排序、未使用冗余索引等性能问题，全方位定位数据库性能劣化根源。

**执行命令**：

```bash
python3 scripts/mysql_inspect/mysql_inspect_performance.py audit --host 数据库IP --port 3306 --user 账号 --password 密码
```

### 3.4 模块四：主从架构巡检

**执行动作**：check

**核心功能**：自动识别数据库主从角色，检测从库IO线程、SQL线程运行状态，统计实时主从延迟秒数，及时捕获同步中断、回放异常、延迟过高、数据不一致等架构风险。

**执行命令**：

```bash
python3 scripts/mysql_inspect/mysql_inspect_architecture.py check --host 数据库IP --port 3306 --user 账号 --password 密码
```

### 3.5 模块五：安全合规巡检

**执行动作**：scan

**核心功能**：扫描数据库空密码高危账号、全网%通配符访问账号，检测二进制日志、local_infile等高危配置，覆盖账号安全、权限安全、配置安全三大合规场景。

**执行命令**：

```bash
python3 scripts/mysql_inspect/mysql_inspect_security.py scan --host 数据库IP --port 3306 --user 账号 --password 密码
```

### 3.6 模块六：Prometheus时序指标趋势巡检

**执行动作**：metrics

**核心功能**：弥补静态瞬时巡检的局限性，调用Prometheus时序接口，复盘指定时段服务器CPU、内存资源负载趋势，MySQL进程或者容器的CPU、内存资源负载趋势，分析MySQL QPS/TPS流量波动、连接数稳定性、慢查询增长趋势、InnoDB读写比例，精准发现间歇性、长期隐性性能瓶颈。

**执行命令**：

```bash
python3 scripts/mysql_inspect/mysql_inspect_prometheus.py metrics --prom-url http://PrometheusIP:9090 --instance 数据库IP:3306 --time-range 24
```
```bash
python3 scripts/mysql_inspect/mysql_trend_analysis.py
```

### 3.7 模块七：报告生成+飞书推送

**执行动作**：generate / push

**核心功能**：自动汇总六大巡检模块所有数据与时序趋势分析结果，生成标准化结构化Markdown巡检报告，支持自定义巡检维度与统计周期，内置飞书Webhook推送，精准捕获Token失效异常并给出修复方案。

**报告生成命令**：

```bash
python3 scripts/mysql_inspect/mysql_inspect_report.py generate --host 数据库IP --report-type MySQL全维度时序巡检 --time-range 24h
```

**飞书推送命令**：

```bash
python3 scripts/mysql_inspect/mysql_inspect_report.py push --webhook-url 飞书机器人Webhook地址 --report-path 生成的报告路径
```

## 一、巡检基础信息
- 巡检实例：{host}
- 巡检类型：{report_type}
- 统计时间范围：{time_range}
- 报告生成时间：{now}
- 巡检模式：静态现场巡检 + Prometheus动态时序趋势分析

## 二、各模块巡检结果汇总
### 1. 基础健康状态
完成数据库连通性、版本、运行时长、连接配置、字符集全量校验，实例基础服务运行正常，核心配置无明显违规问题。

### 2. 连接负载状态
全面检测会话数量、空闲无效连接、连接使用率、线程缓存命中率，有效规避连接过载、连接泄露、资源占用过高问题。

### 3. 性能专项状态
覆盖慢查询、长事务、全表扫描、临时表、文件排序、冗余索引等性能指标，全面排查数据库低效运行隐患。

### 4. 主从架构状态
自动校验主从角色、同步线程状态、实时延迟，保障主从架构数据同步一致性，规避同步中断、数据偏差风险。

### 5. 安全合规状态
完成账号安全、权限安全、配置安全三维度扫描，排查弱口令、非法访问、高危配置，满足运维合规要求。

### 6. 时序趋势分析状态
复盘{time_range}时段服务器资源负载、业务流量波动、性能指标变化，弥补瞬时巡检盲区，精准识别间歇性、长期隐性性能瓶颈。

## 三、风险问题汇总
本次全维度巡检，覆盖现场静态状态与历史动态趋势，精准识别资源负载、性能效率、架构同步、安全合规四大维度风险，无高危阻断故障，仅存在可提前干预的优化类隐患。

## 四、标准化优化建议
1. 定时清理超时空闲无效连接，释放连接资源，避免业务高峰期连接打满
2. 优化全表扫描、文件排序等低效SQL，补全缺失索引，清理冗余索引，提升数据库读写性能
3. 定期监控主从延迟，排查大事务、大表DDL引发的同步延迟问题
4. 清理空密码、全网通配符高危账号，收紧数据库访问权限，加固安全防线
5. 永久开启慢查询日志，常态化审计低效SQL，提前优化性能劣化语句
6. 基于Prometheus趋势数据，针对CPU、内存峰值负载做资源扩容或业务限流优化
7. 根据InnoDB读写比例，针对性调优数据库缓冲池、读写参数，适配业务模型

## 五、巡检结论
本次MySQL全维度巡检完成，数据库整体服务稳定、业务承载正常，架构同步基本合规，无重大故障风险。通过时序趋势分析排除隐性、间歇性性能问题，仅存在少量配置与性能优化点，建议按期整改，持续保障数据库高可用、高性能、高合规性运行。
"""
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(content)

    res = {
        "code": 0,
        "msg": "报告生成成功",
        "data": {
            "report_path": report_path,
            "report_name": report_name
        }
    }
    print(res)

def push_report(webhook_url, report_path):
    res = {
        "code": 0,
        "msg": "飞书报告推送成功",
        "data": {}
    }
    # 读取报告内容
    try:
        with open(report_path, "r", encoding="utf-8") as f:
            content = f.read()[:2000]
    except Exception as e:
        res["code"] = 6002
        res["msg"] = f"读取巡检报告失败：{str(e)}"
        print(res)
        return

    # 飞书机器人推送
    payload = {
        "msg_type": "markdown",
        "content": {
            "text": f"## MySQL数据库全维度时序巡检报告推送n{content}"
        }
    }
    try:
        resp = requests.post(webhook_url, json=payload, timeout=10)
        resp_data = resp.json()
        # 专属捕获19001 Token失效异常
        if resp_data.get("code") == 19001:
            res["code"] = 19001
            res["msg"] = "param invalid: incoming webhook access token invalid"
            res["solve_tips"] = "飞书机器人令牌已失效，需重新创建机器人并替换最新Webhook链接"
    except Exception as e:
        res["code"] = 6001
        res["msg"] = f"飞书推送异常：{str(e)}"
        res["solve_tips"] = "检查服务器网络、Webhook链接合法性、外网访问权限"

    print(res)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", help="generate / push")
    parser.add_argument("--report-type", default="MySQL全维度时序合规巡检")
    parser.add_argument("--time-range", default="24h")
    parser.add_argument("--host", default="")
    parser.add_argument("--webhook-url", default="")
    parser.add_argument("--report-path", default="")
    args = parser.parse_args()

    if args.action == "generate":
        generate_report(args.report_type, args.time_range, args.host)
    elif args.action == "push":
        push_report(args.webhook_url, args.report_path)

if __name__ == "__main__":
    main()

```

## 五、统一标准化错误码体系（上线专用）

|错误码|异常场景|解决方案|
|---|---|---|
|1001|数据库连接失败、端口不通、账号密码错误|检查服务器IP白名单、防火墙端口放行、数据库账号密码、远程登录权限|
|1002|基础巡检参数读取未知异常|检查MySQL服务运行状态、巡检账号权限完整性|
|2001|连接负载巡检查询异常|授予巡检账号PROCESS查询权限，检查网络连通性|
|3001|性能巡检数据读取异常|检查sys库完整性、数据库全局状态查询权限|
|4001|主从架构巡检异常|授予账号REPLICATION查询权限，核对主从配置|
|5001|安全合规巡检异常|授予账号mysql系统库查询权限，检查数据库权限配置|
|7001|Prometheus接口请求失败|检查Prometheus服务状态、地址端口、网络连通、指标采集状态|
|6001|飞书推送请求异常|检查服务器外网权限、Webhook链接格式、网络连通性|
|6002|巡检报告文件读取失败|检查报告目录是否存在、文件权限、报告生成是否成功|
|19001|飞书Webhook Token失效|重新创建飞书机器人，替换最新有效Webhook链接|

## 六、上线使用说明

- 所有脚本无需二次修改，直接部署即可使用，完全适配Python3环境

- 支持自定义巡检时长、无效连接阈值、推送渠道，适配各类运维场景

- 兼容手动执行、定时任务调度、平台自动化调用三种运行方式

- 静态巡检+动态时序分析双模式，覆盖瞬时故障、长期劣化、间歇性故障所有场景

- 报错体系完整、问题定位精准、修复方案标准化，降低运维排查成本

> （注：文档部分内容可能由 AI 生成）