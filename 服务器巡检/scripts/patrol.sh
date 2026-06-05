#!/usr/bin/env bash
# server-patrol: read-only Linux + network device health checks (local + SSH batch)
# Configuration: reads ONLY from PATROL_* process environment (export / AMC-Sophon injection).
# Does NOT source config.env — that file is an upload template; runtime vars come from the shell env.
# Dependencies: bash, ssh, ping; optional python3 (JSON lists), snmpwalk (SNMP mode)
set -euo pipefail

VERSION="1.3.3"

# --- defaults from env ---
PATROL_DISK_WARN="${PATROL_DISK_WARN:-80}"
PATROL_DISK_CRIT="${PATROL_DISK_CRIT:-90}"
PATROL_MEM_WARN="${PATROL_MEM_WARN:-85}"
PATROL_MEM_CRIT="${PATROL_MEM_CRIT:-95}"
PATROL_LOAD_WARN="${PATROL_LOAD_WARN:-5}"
PATROL_LOAD_CRIT="${PATROL_LOAD_CRIT:-10}"
PATROL_CPU_WARN="${PATROL_CPU_WARN:-80}"
PATROL_SERVICES="${PATROL_SERVICES:-}"
PATROL_SSH_IDENTITY="${PATROL_SSH_IDENTITY:-$HOME/.ssh/id_rsa}"
PATROL_SSH_PASSWORD="${PATROL_SSH_PASSWORD:-${PATROL_PASSWORD:-}}"
PATROL_SSH_TIMEOUT="${PATROL_SSH_TIMEOUT:-10}"
PATROL_CONCURRENCY="${PATROL_CONCURRENCY:-5}"
PATROL_REPORT_DIR="${PATROL_REPORT_DIR:-./reports}"
PATROL_SERVER="${PATROL_SERVER:-}"
PATROL_SERVER_JSON="${PATROL_SERVER_JSON:-}"
PATROL_NETWORK="${PATROL_NETWORK:-}"
PATROL_NETWORK_JSON="${PATROL_NETWORK_JSON:-}"
PATROL_NET_PORTS="${PATROL_NET_PORTS:-22,80,443}"
PATROL_PING_COUNT="${PATROL_PING_COUNT:-3}"
PATROL_PING_LOSS_WARN="${PATROL_PING_LOSS_WARN:-20}"
PATROL_PING_LOSS_CRIT="${PATROL_PING_LOSS_CRIT:-50}"
PATROL_PING_RTT_WARN="${PATROL_PING_RTT_WARN:-100}"
PATROL_PING_RTT_CRIT="${PATROL_PING_RTT_CRIT:-500}"
PATROL_SNMP_COMMUNITY="${PATROL_SNMP_COMMUNITY:-}"
PATROL_SNMP_VERSION="${PATROL_SNMP_VERSION:-2c}"
PATROL_NET_CPU_WARN="${PATROL_NET_CPU_WARN:-80}"
PATROL_NET_MEM_WARN="${PATROL_NET_MEM_WARN:-85}"

FORMAT="markdown"
FILTER_TAG=""
MODE=""
TARGET=""
SCOPE="all"

usage() {
  cat <<'EOF'
Usage:
  patrol.sh local                         Inspect localhost (Linux)
  patrol.sh remote [user@]host[:port]       Inspect one Linux host via SSH
  patrol.sh --all [--tag TAG]              Inspect servers + network devices from env
  patrol.sh --servers [--tag TAG]          Linux servers only
  patrol.sh --network [--tag TAG]          Network devices only (routers/switches)
  patrol.sh net [type] host[:port]         Inspect one network device (type: ping|ssh-cisco|ssh-huawei|ssh-h3c|snmp)
  patrol.sh --list                         Print parsed targets

Options:
  --format markdown|json                  Output format (default: markdown)
  --tag TAG                               Filter by tag (--all / --servers / --network)
  -h, --help                              Show help

Environment: PATROL_SERVER, PATROL_NETWORK, PATROL_* thresholds

PATROL_SERVER list format (semicolon-separated entries):
  name|user@host[:port]|tags[,tag2]              # password via PATROL_SSH_PASSWORD (typical + Config Vault)
  name|user@host[:port]|tags|per-host-password  # optional 4th field overrides global password

Example:
  PATROL_SERVER='host52|root@192.168.50.52:22|production,fenda'
  PATROL_SSH_PASSWORD='...'   # from Config Vault @config:PATROL/PASSWORD injection

Network types: ping, ssh-cisco, ssh-huawei, ssh-h3c, ssh-generic, snmp
EOF
}

log() { printf '%s\n' "$*" >&2; }

# Remote probe script (embedded, read-only commands only)
read -r -d '' REMOTE_PROBE <<'PROBE' || true
set -e
host=$(hostname -s 2>/dev/null || hostname)
echo "===HOST===$host"
echo "===UPTIME==="
uptime 2>/dev/null || true
echo "===LOAD==="
if [ -r /proc/loadavg ]; then awk '{print $1" "$2" "$3}' /proc/loadavg
else uptime | sed -E -n 's/.*load averages?: //p' | head -1
fi
echo "===CPU_CORES==="
nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
echo "===CPU_USAGE==="
if [ -r /proc/stat ]; then
  read -r _ u1 n1 s1 i1 iw1 irq1 sirq1 _ < /proc/stat
  t1=$((u1+n1+s1+i1+iw1+irq1+sirq1)); id1=$i1
  sleep 1
  read -r _ u2 n2 s2 i2 iw2 irq2 sirq2 _ < /proc/stat
  t2=$((u2+n2+s2+i2+iw2+irq2+sirq2)); id2=$i2
  dt=$((t2-t1)); di=$((id2-id1))
  if [ "$dt" -gt 0 ]; then echo $(( (100 * (dt - di)) / dt )); else echo 0; fi
elif [ "$(uname -s)" = "Darwin" ]; then
  ps -A -o %cpu 2>/dev/null | awk 'NR>1 {s+=$1} END { if (s>100) s=100; printf "%.0f\n", s+0}'
else echo 0; fi
echo "===MEM==="
if command -v free >/dev/null 2>&1; then
  free -m 2>/dev/null | awk '/^Mem:/ {printf "total=%s used=%s avail=%s pct=%.0f\n", $2, $3, $7, ($3/$2)*100}'
elif [ "$(uname -s)" = "Darwin" ]; then
  page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
  vm_stat | awk -v ps="$page_size" '
    /Pages free/ {free=$3} /Pages active/ {act=$3} /Pages inactive/ {inact=$3}
    /Pages wired/ {wired=$4} END {
      gsub(/\./,"",free); gsub(/\./,"",act); gsub(/\./,"",inact); gsub(/\./,"",wired)
      total=(free+act+inact+wired)*ps/1048576; used=(act+inact+wired)*ps/1048576
      if (total>0) printf "total=%.0f used=%.0f avail=%.0f pct=%.0f\n", total, used, free*ps/1048576, (used/total)*100
    }'
else echo "total=0 used=0 avail=0 pct=0"; fi
echo "===DISK==="
df -P 2>/dev/null | awk 'NR>1 && $6 ~ /^\// && $1 !~ /tmpfs|devtmpfs|overlay/ {gsub(/%/,"",$5); if ($5+0 == $5) print $6":"$5":"$4":"$2}' || true
echo "===SERVICES==="
PROBE

# Append service / process / docker checks to remote probe (read-only)
build_remote_probe() {
  local probe="$REMOTE_PROBE"
  if [ -n "$PATROL_SERVICES" ]; then
    IFS=',' read -ra svc_arr <<< "$PATROL_SERVICES"
    for s in "${svc_arr[@]}"; do
      s=$(echo "$s" | xargs)
      [ -z "$s" ] && continue
      case "$s" in *.service) ;; *) s="${s}.service" ;; esac
      probe+=$'\n'"if command -v systemctl >/dev/null 2>&1; then systemctl is-active --quiet '$s' 2>/dev/null && echo '${s}|active' || echo '${s}|inactive'; else echo '${s}|unknown'; fi"
    done
  fi
  probe+=$'\n'"echo '===SYSTEMD==='"
  probe+=$'\n'"if command -v systemctl >/dev/null 2>&1; then"
  probe+=$'\n'"  running=\$(systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | wc -l | tr -d ' ')"
  probe+=$'\n'"  failed=\$(systemctl list-units --type=service --state=failed --no-legend --no-pager 2>/dev/null | wc -l | tr -d ' ')"
  probe+=$'\n'"  echo \"summary|running=\${running}|failed=\${failed}\""
  probe+=$'\n'"  systemctl list-units --type=service --state=failed --no-legend --no-pager 2>/dev/null | awk '{print \$1\"|failed\"}' | head -20"
  probe+=$'\n'"else echo 'systemd|unavailable'; fi"
  probe+=$'\n'"echo '===PROCESSES==='"
  probe+=$'\n'"if [ \"\$(uname -s)\" = Linux ]; then"
  probe+=$'\n'"  total=\$(ps -e --no-header 2>/dev/null | wc -l | tr -d ' ')"
  probe+=$'\n'"  zombie=\$(ps aux 2>/dev/null | awk '\$8 ~ /Z/ {c++} END {print c+0}')"
  probe+=$'\n'"  echo \"summary|total=\${total}|zombie=\${zombie}\""
  probe+=$'\n'"  ps -eo comm=,pcpu=,pmem= --sort=-pcpu 2>/dev/null | head -5 | awk '{print \$1\"|cpu=\"\$2\"|mem=\"\$3}'"
  probe+=$'\n'"elif [ \"\$(uname -s)\" = Darwin ]; then"
  probe+=$'\n'"  total=\$(ps -ax 2>/dev/null | wc -l | tr -d ' ')"
  probe+=$'\n'"  zombie=\$(ps axo state 2>/dev/null | awk '\$1 ~ /Z/ {c++} END {print c+0}')"
  probe+=$'\n'"  echo \"summary|total=\${total}|zombie=\${zombie}\""
  probe+=$'\n'"  ps -arcxo comm,pcpu,pmem 2>/dev/null | tail -n +2 | head -5 | awk '{print \$1\"|cpu=\"\$2\"|mem=\"\$3}'"
  probe+=$'\n'"else echo 'processes|unavailable'; fi"
  probe+=$'\n'"echo '===DOCKER==='"
  probe+=$'\n'"if command -v docker >/dev/null 2>&1; then"
  probe+=$'\n'"  set +e"
  probe+=$'\n'"  running=\$(docker ps -q 2>/dev/null | wc -l | tr -d ' '); running=\${running:-0}"
  probe+=$'\n'"  all=\$(docker ps -aq 2>/dev/null | wc -l | tr -d ' '); all=\${all:-0}"
  probe+=$'\n'"  stopped=\$((all - running)); [ \"\$stopped\" -lt 0 ] 2>/dev/null && stopped=0"
  probe+=$'\n'"  unhealthy=0"
  probe+=$'\n'"  _uh=\$(docker ps -q --filter health=unhealthy 2>/dev/null | wc -l | tr -d ' ') && unhealthy=\${_uh:-0}"
  probe+=$'\n'"  echo \"summary|installed=1|running=\${running}|total=\${all}|stopped=\${stopped}|unhealthy=\${unhealthy}\""
  probe+=$'\n'"  if docker ps --help 2>&1 | grep -q -- '--format'; then"
  probe+=$'\n'"    docker ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}' 2>/dev/null | head -25"
  probe+=$'\n'"  else"
  probe+=$'\n'"    docker ps -a 2>/dev/null | tail -n +2 | head -25 | awk '{n=\$NF; \$1=\$NF=\"\"; sub(/^ /,\"\"); print n\"|\"substr(\$0,1,80)}'"
  probe+=$'\n'"  fi"
  probe+=$'\n'"  set -e"
  probe+=$'\n'"else echo 'summary|installed=0'; fi"
  probe+=$'\n'"echo '===K8S==='"
  probe+=$'\n'"if command -v kubectl >/dev/null 2>&1; then"
  probe+=$'\n'"  echo 'summary|installed=1'"
  probe+=$'\n'"  set +e"
  probe+=$'\n'"  _patrol_k8s_err() { head -1 | tr -d '\n' | tr '|' '/' | head -c 120; }"
  probe+=$'\n'"  kv=\$(kubectl version --client --short 2>/dev/null | head -1 | tr -d '\n')"
  probe+=$'\n'"  [ -z \"\$kv\" ] && kv=\$(kubectl version --client 2>/dev/null | awk -F: '/Client Version/ {gsub(/^[ \\t]+/,\"\",\$2); print \"Client Version:\" \$2; exit}' | tr -d '\n')"
  probe+=$'\n'"  [ -z \"\$kv\" ] && kv=unknown"
  probe+=$'\n'"  echo \"info|client=\${kv}\""
  probe+=$'\n'"  connected=0"
  probe+=$'\n'"  if kubectl get nodes >/dev/null 2>&1; then connected=1"
  probe+=$'\n'"  elif kubectl get ns default >/dev/null 2>&1; then connected=1"
  probe+=$'\n'"  elif kubectl cluster-info >/dev/null 2>&1; then connected=1"
  probe+=$'\n'"  fi"
  probe+=$'\n'"  if [ \"\$connected\" -eq 1 ]; then"
  probe+=$'\n'"    ctx=\$(kubectl config current-context 2>/dev/null || echo default)"
  probe+=$'\n'"    echo \"cluster|connected=1|context=\${ctx}\""
  probe+=$'\n'"    if kubectl get nodes --no-headers >/dev/null 2>&1; then"
  probe+=$'\n'"      nt=\$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' '); nt=\${nt:-0}"
  probe+=$'\n'"      nr=\$(kubectl get nodes --no-headers 2>/dev/null | awk '\$2==\"Ready\"' | wc -l | tr -d ' '); nr=\${nr:-0}"
  probe+=$'\n'"      nn=\$(kubectl get nodes --no-headers 2>/dev/null | awk '\$2!=\"Ready\"' | wc -l | tr -d ' '); nn=\${nn:-0}"
  probe+=$'\n'"      echo \"nodes|total=\${nt}|ready=\${nr}|notready=\${nn}\""
  probe+=$'\n'"      kubectl get nodes --no-headers 2>/dev/null | awk '{print \"node|\"\$1\"|\"\$2}'"
  probe+=$'\n'"    else"
  probe+=$'\n'"      _nr=\$(kubectl get nodes 2>&1 | _patrol_k8s_err)"
  probe+=$'\n'"      echo \"cap|nodes=skip|reason=\${_nr:-forbidden or unsupported}\""
  probe+=$'\n'"    fi"
  probe+=$'\n'"    _pod_src=custom"
  probe+=$'\n'"    _pod_raw=\$(kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,REST:.status.containerStatuses[0].restartCount --no-headers 2>/dev/null)"
  probe+=$'\n'"    if [ -z \"\$_pod_raw\" ]; then"
  probe+=$'\n'"      _pod_raw=\$(kubectl get pods -A --no-headers 2>/dev/null | awk '{print \$1\"\\t\"\$2\"\\t\"\$4\"\\t\"\$5}')"
  probe+=$'\n'"      _pod_src=legacy"
  probe+=$'\n'"    fi"
  probe+=$'\n'"    if [ -n \"\$_pod_raw\" ]; then"
  probe+=$'\n'"      pt=\$(echo \"\$_pod_raw\" | wc -l | tr -d ' '); pt=\${pt:-0}"
  probe+=$'\n'"      pr=\$(echo \"\$_pod_raw\" | awk '\$3==\"Running\"' | wc -l | tr -d ' '); pr=\${pr:-0}"
  probe+=$'\n'"      pp=\$(echo \"\$_pod_raw\" | awk '\$3==\"Pending\"' | wc -l | tr -d ' '); pp=\${pp:-0}"
  probe+=$'\n'"      pf=\$(echo \"\$_pod_raw\" | awk '\$3==\"Failed\"' | wc -l | tr -d ' '); pf=\${pf:-0}"
  probe+=$'\n'"      po=\$(echo \"\$_pod_raw\" | awk '\$3!=\"Running\" && \$3!=\"Pending\" && \$3!=\"Failed\" && \$3!=\"Completed\" && \$3!=\"Succeeded\"' | wc -l | tr -d ' '); po=\${po:-0}"
  probe+=$'\n'"      echo \"pods|total=\${pt}|running=\${pr}|pending=\${pp}|failed=\${pf}|other=\${po}\""
  probe+=$'\n'"      echo \"\$_pod_raw\" | awk '\$3!=\"Running\" && \$3!=\"Completed\" && \$3!=\"Succeeded\" {gsub(/\\t/,\"/\", \$0); print \"bad-pod|\"\$1\"/\"\$2\"|\"\$3\"|\"\$4}' | head -15"
  probe+=$'\n'"      echo \"\$_pod_raw\" | awk '\$4+0>=10 {gsub(/\\t/,\"/\", \$0); print \"restart-pod|\"\$1\"/\"\$2\"|restarts=\"\$4\"|\"\$3}' | head -10"
  probe+=$'\n'"    else"
  probe+=$'\n'"      _pr=\$(kubectl get pods -A 2>&1 | _patrol_k8s_err)"
  probe+=$'\n'"      echo \"cap|pods=skip|reason=\${_pr:-forbidden or unsupported}\""
  probe+=$'\n'"    fi"
  probe+=$'\n'"    if kubectl get ns --no-headers >/dev/null 2>&1; then"
  probe+=$'\n'"      nc=\$(kubectl get ns --no-headers 2>/dev/null | wc -l | tr -d ' '); nc=\${nc:-0}"
  probe+=$'\n'"      echo \"namespaces|count=\${nc}\""
  probe+=$'\n'"    else"
  probe+=$'\n'"      _nsr=\$(kubectl get ns 2>&1 | _patrol_k8s_err)"
  probe+=$'\n'"      echo \"cap|namespaces=skip|reason=\${_nsr:-forbidden}\""
  probe+=$'\n'"    fi"
  probe+=$'\n'"    _dep_raw=\$(kubectl get deploy -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas --no-headers 2>/dev/null)"
  probe+=$'\n'"    if [ -z \"\$_dep_raw\" ]; then"
  probe+=$'\n'"      _dep_raw=\$(kubectl get deploy -A --no-headers 2>/dev/null | awk '{print \$1\"\\t\"\$2\"\\t\"\$3}')"
  probe+=$'\n'"    fi"
  probe+=$'\n'"    if [ -n \"\$_dep_raw\" ]; then"
  probe+=$'\n'"      _dt=\$(echo \"\$_dep_raw\" | wc -l | tr -d ' '); _dt=\${_dt:-0}"
  probe+=$'\n'"      _dr=\$(echo \"\$_dep_raw\" | awk -F'\\t' 'BEGIN{c=0}{if(\$3~/\\//){split(\$3,a,\"/\");r=a[1]+0;d=a[2]+0}else{r=\$3+0;d=\$4+0}if(d==0||r>=d)c++}END{print c+0}')"
  probe+=$'\n'"      _dn=\$((_dt - _dr)); [ \"\$_dn\" -lt 0 ] 2>/dev/null && _dn=0"
  probe+=$'\n'"      echo \"deployments|total=\${_dt}|ready=\${_dr}|notready=\${_dn}\""
  probe+=$'\n'"      echo \"\$_dep_raw\" | awk -F'\\t' '{if(\$3~/\\//){split(\$3,a,\"/\");r=a[1]+0;d=a[2]+0}else{r=\$3+0;d=\$4+0}if(d>0&&r<d)print \"deploy-bad|\"\$1\"/\"\$2\"|\"r\"/\"d}' | head -15"
  probe+=$'\n'"    else"
  probe+=$'\n'"      _der=\$(kubectl get deploy -A 2>&1 | _patrol_k8s_err)"
  probe+=$'\n'"      echo \"cap|deployments=skip|reason=\${_der:-forbidden or unsupported}\""
  probe+=$'\n'"    fi"
  probe+=$'\n'"    _ds_raw=\$(kubectl get ds -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady --no-headers 2>/dev/null)"
  probe+=$'\n'"    if [ -z \"\$_ds_raw\" ]; then"
  probe+=$'\n'"      _ds_raw=\$(kubectl get ds -A --no-headers 2>/dev/null | awk '{print \$1\"\\t\"\$2\"\\t\"\$5\"\\t\"\$3}')"
  probe+=$'\n'"    fi"
  probe+=$'\n'"    if [ -n \"\$_ds_raw\" ]; then"
  probe+=$'\n'"      _dst=\$(echo \"\$_ds_raw\" | wc -l | tr -d ' '); _dst=\${_dst:-0}"
  probe+=$'\n'"      _dsr=\$(echo \"\$_ds_raw\" | awk -F'\\t' '{r=\$3+0;d=\$4+0;if(d==0||r>=d)c++}END{print c+0}')"
  probe+=$'\n'"      _dsn=\$((_dst - _dsr)); [ \"\$_dsn\" -lt 0 ] 2>/dev/null && _dsn=0"
  probe+=$'\n'"      echo \"daemonsets|total=\${_dst}|ready=\${_dsr}|notready=\${_dsn}\""
  probe+=$'\n'"      echo \"\$_ds_raw\" | awk -F'\\t' '{r=\$3+0;d=\$4+0;if(d>0&&r<d)print \"ds-bad|\"\$1\"/\"\$2\"|\"r\"/\"d}' | head -15"
  probe+=$'\n'"    else"
  probe+=$'\n'"      _dsr2=\$(kubectl get ds -A 2>&1 | _patrol_k8s_err)"
  probe+=$'\n'"      echo \"cap|daemonsets=skip|reason=\${_dsr2:-forbidden or unsupported}\""
  probe+=$'\n'"    fi"
  probe+=$'\n'"    _health_src=none"
  probe+=$'\n'"    if kubectl get cs --no-headers >/dev/null 2>&1; then"
  probe+=$'\n'"      _cst=\$(kubectl get cs --no-headers 2>/dev/null | wc -l | tr -d ' '); _cst=\${_cst:-0}"
  probe+=$'\n'"      _csh=\$(kubectl get cs --no-headers 2>/dev/null | awk '\$2==\"Healthy\"' | wc -l | tr -d ' '); _csh=\${_csh:-0}"
  probe+=$'\n'"      _csu=\$((_cst - _csh)); [ \"\$_csu\" -lt 0 ] 2>/dev/null && _csu=0"
  probe+=$'\n'"      echo \"health|source=componentstatuses|total=\${_cst}|healthy=\${_csh}|unhealthy=\${_csu}\""
  probe+=$'\n'"      kubectl get cs --no-headers 2>/dev/null | awk '{print \"component|\"\$1\"|\"\$2}' | head -12"
  probe+=$'\n'"      _health_src=componentstatuses"
  probe+=$'\n'"    fi"
  probe+=$'\n'"    _hz=\$(kubectl get --raw=/healthz 2>/dev/null | head -c 40 | tr -d '\\n')"
  probe+=$'\n'"    [ -n \"\$_hz\" ] && echo \"health|api_healthz=\${_hz}\""
  probe+=$'\n'"    _rz=\$(kubectl get --raw='/readyz?verbose' 2>/dev/null)"
  probe+=$'\n'"    if [ -n \"\$_rz\" ]; then"
  probe+=$'\n'"      _rf=\$(echo \"\$_rz\" | grep -c '\\[-\\]' 2>/dev/null || echo 0); _rf=\${_rf:-0}"
  probe+=$'\n'"      _ro=\$(echo \"\$_rz\" | grep -c '\\[+\\]' 2>/dev/null || echo 0); _ro=\${_ro:-0}"
  probe+=$'\n'"      echo \"health|readyz_pass=\${_ro}|readyz_fail=\${_rf}\""
  probe+=$'\n'"      echo \"\$_rz\" | grep '\\[-\\]' 2>/dev/null | head -5 | awk '{gsub(/^[^]]*\\] */, \"\"); gsub(/\\|/,\"/\"); print \"readyz-fail|\" substr(\$0,1,100)}'"
  probe+=$'\n'"      [ \"\$_health_src\" = none ] && _health_src=readyz"
  probe+=$'\n'"    fi"
  probe+=$'\n'"    if kubectl get pods -n kube-system --no-headers >/dev/null 2>&1; then"
  probe+=$'\n'"      _ksb=\$(kubectl get pods -n kube-system --no-headers 2>/dev/null | awk '\$3!=\"Running\" && \$3!=\"Completed\" && \$3!=\"Succeeded\"' | wc -l | tr -d ' '); _ksb=\${_ksb:-0}"
  probe+=$'\n'"      echo \"health|kube_system_bad_pods=\${_ksb}\""
  probe+=$'\n'"      kubectl get pods -n kube-system --no-headers 2>/dev/null | awk '\$3!=\"Running\" && \$3!=\"Completed\" && \$3!=\"Succeeded\" {print \"comp-pod|\"\$1\"|\"\$3\"|\"\$2}' | head -10"
  probe+=$'\n'"      [ \"\$_health_src\" = none ] && _health_src=kube-system"
  probe+=$'\n'"    else"
  probe+=$'\n'"      _kse=\$(kubectl get pods -n kube-system 2>&1 | _patrol_k8s_err)"
  probe+=$'\n'"      echo \"cap|health_kube_system=skip|reason=\${_kse:-forbidden}\""
  probe+=$'\n'"    fi"
  probe+=$'\n'"    _topn=\$(kubectl top nodes --no-headers 2>/dev/null)"
  probe+=$'\n'"    if [ -n \"\$_topn\" ]; then"
  probe+=$'\n'"      echo \"\$_topn\" | awk '{print \"top-node|\"\$1\"|\"\$2\"|\"\$3\"|\"\$4\"|\"\$5}'"
  probe+=$'\n'"    else"
  probe+=$'\n'"      _tr=\$(kubectl top nodes 2>&1 | _patrol_k8s_err)"
  probe+=$'\n'"      echo \"cap|top_nodes=skip|reason=\${_tr:-metrics-server unavailable}\""
  probe+=$'\n'"    fi"
  probe+=$'\n'"    _topp=\$(kubectl top pods -A --no-headers 2>/dev/null)"
  probe+=$'\n'"    if [ -n \"\$_topp\" ]; then"
  probe+=$'\n'"      echo \"\$_topp\" | sort -k3 -hr 2>/dev/null | head -5 | awk '{print \"top-pod|\"\$1\"/\"\$2\"|\"\$3\"|\"\$4}'"
  probe+=$'\n'"    else"
  probe+=$'\n'"      _tpr=\$(kubectl top pods -A 2>&1 | _patrol_k8s_err)"
  probe+=$'\n'"      echo \"cap|top_pods=skip|reason=\${_tpr:-metrics-server unavailable}\""
  probe+=$'\n'"    fi"
  probe+=$'\n'"  else"
  probe+=$'\n'"    _cr=\$(kubectl get nodes 2>&1 | _patrol_k8s_err)"
  probe+=$'\n'"    [ -z \"\$_cr\" ] && _cr=\$(kubectl cluster-info 2>&1 | _patrol_k8s_err)"
  probe+=$'\n'"    echo \"cluster|connected=0|reason=\${_cr:-unable to connect}\""
  probe+=$'\n'"  fi"
  probe+=$'\n'"  set -e"
  probe+=$'\n'"else echo 'summary|installed=0'; fi"
  printf '%s' "$probe"
}

# List format: name|ssh_spec|tags[,...]  OR  name|ssh_spec|tags|password
# - 3 segments: per-host password empty; run_ssh_exec falls back to PATROL_SSH_PASSWORD / PATROL_PASSWORD
# - 4 segments: optional per-host password (overrides global)
parse_servers_from_list() {
  local list="$1"
  local IFS=';'
  read -ra entries <<< "$list"
  for entry in "${entries[@]}"; do
    entry=$(echo "$entry" | xargs)
    [ -z "$entry" ] && continue
    local name rest ssh_spec tags_spec password user host port remainder
    name="${entry%%|*}"
    rest="${entry#*|}"
    ssh_spec="${rest%%|*}"
    remainder="${rest#*|}"
    tags_spec=""
    password=""
    if [ -n "$remainder" ]; then
      if [[ "$remainder" == *"|"* ]]; then
        tags_spec="${remainder%%|*}"
        password="${remainder#*|}"
      else
        tags_spec="$remainder"
      fi
    fi
    port=22
    if [[ "$ssh_spec" == *"@"* ]]; then
      user="${ssh_spec%%@*}"
      host="${ssh_spec#*@}"
    else
      user="${USER:-root}"
      host="$ssh_spec"
    fi
    if [[ "$host" == *":"* ]]; then
      port="${host##*:}"
      host="${host%%:*}"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$user" "$host" "$port" "$tags_spec" "$password"
  done
}

parse_servers_from_json() {
  local json="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    log "ERROR: python3 required to parse PATROL_SERVER_JSON"
    return 1
  fi
  python3 - "$json" <<'PY'
import json, sys
raw = sys.argv[1]
for s in json.loads(raw):
    name = s.get("name") or s.get("host")
    host = s["host"]
    user = s.get("user") or "root"
    port = str(s.get("port", 22))
    tags = ",".join(s.get("tags") or [])
    password = s.get("password") or ""
    print(f"{name}\t{user}\t{host}\t{port}\t{tags}\t{password}")
PY
}

load_servers() {
  if [ -n "$PATROL_SERVER_JSON" ]; then
    parse_servers_from_json "$PATROL_SERVER_JSON"
  elif [ -n "$PATROL_SERVER" ]; then
    parse_servers_from_list "$PATROL_SERVER"
  fi
}

# --- network device parsing & probes ---

parse_network_from_list() {
  local list="$1"
  local IFS=';'
  read -ra entries <<< "$list"
  for entry in "${entries[@]}"; do
    entry=$(echo "$entry" | xargs)
    [ -z "$entry" ] && continue
    local name dtype conn tags extra rest
    name="${entry%%|*}"
    rest="${entry#*|}"
    dtype="${rest%%|*}"
    rest="${rest#*|}"
    conn="${rest%%|*}"
    rest="${rest#*|}"
    tags=""
    extra=""
    if [[ "$rest" == *"|"* ]]; then
      tags="${rest%%|*}"
      extra="${rest#*|}"
    else
      tags="$rest"
    fi
    local user host port
    user=""; port=""
    host="$conn"
    if [[ "$conn" == *"@"* ]]; then
      user="${conn%%@*}"
      host="${conn#*@}"
    fi
    if [[ "$host" == *":"* ]]; then
      port="${host##*:}"
      host="${host%%:*}"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$dtype" "$host" "${user:-}" "${port:-}" "$tags" "$extra"
  done
}

parse_network_from_json() {
  local json="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    log "ERROR: python3 required to parse PATROL_NETWORK_JSON"
    return 1
  fi
  python3 - "$json" <<'PY'
import json, sys
raw = sys.argv[1]
for d in json.loads(raw):
    name = d.get("name") or d.get("host")
    dtype = d.get("type", "ping")
    host = d["host"]
    user = d.get("user") or ""
    port = str(d.get("port") or "")
    tags = ",".join(d.get("tags") or [])
    extra = d.get("ports") or d.get("community") or ""
    if isinstance(extra, list):
        extra = ",".join(str(x) for x in extra)
    print(f"{name}\t{dtype}\t{host}\t{user}\t{port}\t{tags}\t{extra}")
PY
}

load_network_devices() {
  if [ -n "$PATROL_NETWORK_JSON" ]; then
    parse_network_from_json "$PATROL_NETWORK_JSON"
  elif [ -n "$PATROL_NETWORK" ]; then
    parse_network_from_list "$PATROL_NETWORK"
  fi
}

ping_host() {
  local host="$1"
  local count="$PATROL_PING_COUNT"
  local loss=100 rtt=9999
  if command -v ping >/dev/null 2>&1; then
    local ping_cmd=(ping -c "$count")
    if [ "$(uname -s)" = "Darwin" ]; then
      ping_cmd+=(-t 2)
    else
      ping_cmd+=(-W 2)
    fi
    ping_cmd+=("$host")
    if "${ping_cmd[@]}" >/tmp/patrol-ping.$$ 2>&1; then
      :
    fi
    local out
    out=$(cat /tmp/patrol-ping.$$ 2>/dev/null || true)
    rm -f /tmp/patrol-ping.$$
    if echo "$out" | grep -qE '[0-9]+ packets transmitted'; then
      loss=$(echo "$out" | sed -E -n 's/.* ([0-9.]+)% packet loss.*/\1/p' | head -1)
      loss="${loss%%.*}"
      [ -z "$loss" ] && loss=100
      rtt=$(echo "$out" | sed -E -n 's/.* = ([0-9.]+)\/.*/\1/p' | head -1)
      [ -z "$rtt" ] && rtt=$(echo "$out" | awk -F'/' '/min\/avg\/max/ {print $5; exit}')
      [ -z "$rtt" ] && rtt=9999
    fi
  fi
  printf '%s\t%s\n' "${loss:-100}" "${rtt:-9999}"
}

check_tcp_port() {
  local host="$1" port="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$host" "$port" 2>/dev/null && echo open || echo closed
  elif (echo >/dev/tcp/"$host"/"$port") 2>/dev/null; then
    echo open
  else
    echo closed
  fi
}

probe_ports() {
  local host="$1" ports_spec="$2"
  local ports="$ports_spec"
  [ -z "$ports" ] && ports="$PATROL_NET_PORTS"
  local result="" closed=0
  IFS=',' read -ra parr <<< "$ports"
  for p in "${parr[@]}"; do
    p=$(echo "$p" | xargs)
    [ -z "$p" ] && continue
    local st
    st=$(check_tcp_port "$host" "$p")
    result+="${p}:${st};"
    [ "$st" = "closed" ] && closed=$((closed + 1))
  done
  printf '%s\t%s\n' "$result" "$closed"
}

run_snmp_probe() {
  local host="$1" community="${2:-$PATROL_SNMP_COMMUNITY}"
  local out=""
  if [ -z "$community" ] || ! command -v snmpwalk >/dev/null 2>&1; then
    echo "SNMP_UNAVAILABLE"
    return 1
  fi
  local ver="-v2c"
  [ "$PATROL_SNMP_VERSION" = "1" ] && ver="-v1"
  out=$(snmpwalk $ver -c "$community" -t 2 "$host" 1.3.6.1.2.1.1 2>/dev/null | head -20 || true)
  printf '%s' "$out"
}

network_ssh_commands() {
  local dtype="$1"
  case "$dtype" in
    ssh-cisco|cisco)
      cat <<'CMD'
terminal length 0
show version | include uptime|Version|processor
show processes cpu | include CPU utilization
show memory statistics | include Used|Free|Processor
show ip interface brief
CMD
      ;;
    ssh-huawei|huawei)
      cat <<'CMD'
screen-length 0 temporary
display version
display health
display cpu-usage
display memory
display interface brief
CMD
      ;;
    ssh-h3c|h3c)
      cat <<'CMD'
screen-length disable
display version
display device manuinfo
display cpu-usage
display memory
display interface brief
CMD
      ;;
    ssh-generic|generic|*)
      cat <<'CMD'
show version 2>/dev/null || display version 2>/dev/null || cat /proc/uptime 2>/dev/null || uptime
show ip interface brief 2>/dev/null || display interface brief 2>/dev/null || ip link 2>/dev/null
CMD
      ;;
  esac
}

run_network_ssh_probe() {
  local dtype="$1" user="$2" host="$3" port="$4" password="${5:-}"
  [ -z "$user" ] && user="admin"
  local cmds
  cmds=$(network_ssh_commands "$dtype")
  run_ssh_exec "$user" "$host" "$port" "$password" 1 "$cmds"
}

parse_network_ssh_output() {
  local raw="$1"
  local cpu="" mem="" uptime="" ifaces="" model=""
  cpu=$(echo "$raw" | sed -n 's/.*CPU utilization.*: *\([0-9]*\)%.*/\1/p' | head -1)
  [ -z "$cpu" ] && cpu=$(echo "$raw" | sed -n 's/.*[Cc]PU *[Uu]sage[^0-9]*\([0-9]*\).*/\1/p' | head -1)
  [ -z "$cpu" ] && cpu=$(echo "$raw" | awk '/[Cc]pu\(s\)|CPU usage|cpu-usage/ {for(i=1;i<=NF;i++) if($i~/^[0-9]+%?$/) {gsub(/%/,"",$i); print $i; exit}}' | head -1)
  mem=$(echo "$raw" | sed -n 's/.*[Uu]sed[^0-9]*\([0-9]*\)%.*/\1/p' | head -1)
  uptime=$(echo "$raw" | grep -iE 'uptime|运行时间' | head -1 | sed 's/^[[:space:]]*//')
  model=$(echo "$raw" | grep -iE 'Version|version|Software' | head -1 | sed 's/^[[:space:]]*//')
  ifaces=$(echo "$raw" | grep -iE '^[^ ]+[ ]+[0-9.]+[ ]+|^(Gigabit|Ethernet|GE|XGE|Vlan)' | head -8 | tr '\n' ';')
  printf '%s\t%s\t%s\t%s\t%s\n' "${cpu:-}" "${mem:-}" "${uptime:-}" "${ifaces:-}" "${model:-}"
}

severity_ping_loss() {
  local loss="$1"
  if [ "${loss:-100}" -ge "$PATROL_PING_LOSS_CRIT" ] 2>/dev/null; then echo CRIT
  elif [ "${loss:-100}" -ge "$PATROL_PING_LOSS_WARN" ] 2>/dev/null; then echo WARN
  else echo OK; fi
}

severity_ping_rtt() {
  local rtt="$1"
  rtt="${rtt%%.*}"
  if [ "${rtt:-0}" -ge "$PATROL_PING_RTT_CRIT" ] 2>/dev/null; then echo CRIT
  elif [ "${rtt:-0}" -ge "$PATROL_PING_RTT_WARN" ] 2>/dev/null; then echo WARN
  else echo OK; fi
}

severity_net_pct() {
  local pct="$1" warn="$2"
  pct="${pct%%.*}"
  if [ -z "$pct" ] || [ "$pct" = "" ]; then echo OK
  elif [ "$pct" -ge "$warn" ] 2>/dev/null; then echo WARN
  else echo OK; fi
}

inspect_network_one() {
  local name="$1" dtype="$2" host="$3" user="$4" port="$5" extra="$6"
  dtype=$(echo "$dtype" | tr '[:upper:]' '[:lower:]')
  local ping_loss=100 ping_rtt=9999 ports_str="" ports_closed=0
  local cpu="" mem="" uptime="" ifaces="" model="" snmp_ok=0 raw=""

  IFS=$'\t' read -r ping_loss ping_rtt <<< "$(ping_host "$host")"

  case "$dtype" in
    ping|icmp)
      IFS=$'\t' read -r ports_str ports_closed <<< "$(probe_ports "$host" "$extra")"
      ;;
    snmp)
      raw=$(run_snmp_probe "$host" "$extra") && snmp_ok=1 || raw=""
      if [ "$snmp_ok" -eq 0 ]; then
        IFS=$'\t' read -r ports_str ports_closed <<< "$(probe_ports "$host" "$PATROL_NET_PORTS")"
      fi
      ;;
    ssh-*|cisco|huawei|h3c|generic)
      if raw=$(run_network_ssh_probe "$dtype" "$user" "$host" "$port" "$extra" 2>&1); then
        IFS=$'\t' read -r cpu mem uptime ifaces model <<< "$(parse_network_ssh_output "$raw")"
      else
        printf 'NETERROR\t%s\t%s\tSSH/command failed\n' "$name" "$host"
        return 1
      fi
      ;;
    *)
      dtype="ping"
      IFS=$'\t' read -r ports_str ports_closed <<< "$(probe_ports "$host" "$extra")"
      ;;
  esac

  local ping_sev rtt_sev cpu_sev mem_sev port_sev=OK overall
  ping_sev=$(severity_ping_loss "$ping_loss")
  rtt_sev=$(severity_ping_rtt "$ping_rtt")
  cpu_sev=$(severity_net_pct "$cpu" "$PATROL_NET_CPU_WARN")
  mem_sev=$(severity_net_pct "$mem" "$PATROL_NET_MEM_WARN")
  [ "${ports_closed:-0}" -gt 0 ] && port_sev=WARN
  [ "$ping_loss" -ge 100 ] 2>/dev/null && port_sev=CRIT
  overall=$(worst "$ping_sev" "$rtt_sev" "$cpu_sev" "$mem_sev" "$port_sev")
  [ "$snmp_ok" -eq 0 ] && [ "$dtype" = "snmp" ] && overall=$(worst "$overall" WARN)

  local cpu_v="${cpu:--}" mem_v="${mem:--}" uptime_v="${uptime:--}" ifaces_v="${ifaces:--}" model_v="${model:--}"
  local snmp_v="skip"
  [ "$snmp_ok" -eq 1 ] && snmp_v="OK"

  printf 'network\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$dtype" "$host" "$overall" "$ping_loss" "$ping_rtt" \
    "$ports_str" "$ports_closed" "$cpu_v" "$mem_v" "$uptime_v" "$ifaces_v" "$model_v" "$snmp_v"
}

severity_disk() {
  local pct="${1%%%}"
  pct="${pct// /}"
  if [ "$pct" -ge "$PATROL_DISK_CRIT" ] 2>/dev/null; then echo CRIT
  elif [ "$pct" -ge "$PATROL_DISK_WARN" ] 2>/dev/null; then echo WARN
  else echo OK; fi
}

severity_mem() {
  local pct="$1"
  pct="${pct%%.*}"
  if [ "$pct" -ge "$PATROL_MEM_CRIT" ] 2>/dev/null; then echo CRIT
  elif [ "$pct" -ge "$PATROL_MEM_WARN" ] 2>/dev/null; then echo WARN
  else echo OK; fi
}

severity_load() {
  local load="$1"
  load="${load%%.*}"
  if awk -v l="$load" -v c="$PATROL_LOAD_CRIT" 'BEGIN{exit !(l>=c)}'; then echo CRIT
  elif awk -v l="$load" -v w="$PATROL_LOAD_WARN" 'BEGIN{exit !(l>=w)}'; then echo WARN
  else echo OK; fi
}

severity_cpu() {
  local pct="$1"
  if [ "$pct" -ge "$PATROL_CPU_WARN" ] 2>/dev/null; then echo WARN
  else echo OK; fi
}

worst() {
  local w=OK
  for s in "$@"; do
    case "$s" in
      CRIT) w=CRIT ;;
      WARN) [ "$w" != CRIT ] && w=WARN ;;
    esac
  done
  echo "$w"
}

run_local_probe() {
  bash -c "$(build_remote_probe)"
}

# Resolve SSH identity: file path, ~ path, or inline PEM from Config Vault (PATROL_SSH_IDENTITY).
_ssh_identity_path() {
  local identity="$PATROL_SSH_IDENTITY"
  if [[ "$identity" == -----BEGIN* ]]; then
    local tmp
    tmp=$(mktemp 2>/dev/null || mktemp -t patrol-ssh)
    chmod 600 "$tmp"
    printf '%s\n' "$identity" > "$tmp"
    echo "$tmp"
  elif [ -f "${identity/#\~/$HOME}" ]; then
    echo "${identity/#\~/$HOME}"
  fi
}

# Unresolved Config Vault DSL left in env (AMC normally expands before inject).
is_unresolved_config_ref() {
  case "${1:-}" in
    @config:*) return 0 ;;
    *) return 1 ;;
  esac
}

# Per-host password (may be empty) → PATROL_SSH_PASSWORD → PATROL_PASSWORD
# If per-host is still @config:... (nested ref not expanded), fall back to global password.
resolve_ssh_password() {
  local per_host="${1:-}"
  if [ -n "$per_host" ] && ! is_unresolved_config_ref "$per_host"; then
    printf '%s' "$per_host"
    return
  fi
  if [ -n "$per_host" ] && is_unresolved_config_ref "$per_host"; then
    log "WARN: per-host password is unresolved '${per_host}'; falling back to PATROL_SSH_PASSWORD (ensure AMC inject or PATROL_SSH_PASSWORD=@config:PATROL/PASSWORD)"
  fi
  printf '%s' "${PATROL_SSH_PASSWORD:-${PATROL_PASSWORD:-}}"
}

ssh_auth_mode_for() {
  local pass
  pass="$(resolve_ssh_password "$1")"
  local id_file
  id_file=$(_ssh_identity_path 2>/dev/null || true)
  local auth_pref="${PATROL_SSH_AUTH:-auto}"
  if [ "$auth_pref" = "publickey" ] && [ -n "$id_file" ] && [ -f "$id_file" ]; then
    printf 'publickey'
  elif [ "$auth_pref" = "password" ] && [ -n "$pass" ]; then
    printf 'password'
  elif [ -n "$pass" ] && [ "$auth_pref" != "publickey" ]; then
    # Password from Vault / PATROL_SSH_PASSWORD wins over a local default id_rsa that may not match the target.
    printf 'password'
  elif [ -n "$id_file" ] && [ -f "$id_file" ]; then
    printf 'publickey'
  elif [ -n "$pass" ]; then
    printf 'password'
  else
    printf 'none'
  fi
}

preflight_ssh_auth_hint() {
  local mode
  mode="$(ssh_auth_mode_for "")"
  if [[ "${PATROL_SERVER:-}" == *'@config:'* ]] || [[ "${PATROL_SERVER_JSON:-}" == *'@config:'* ]]; then
    log "WARN: PATROL_SERVER contains @config: references — AMC must expand them at Skill inject (OpenOcta >= embedded resolve); per-host @config falls back to PATROL_SSH_PASSWORD in patrol.sh"
  fi
  if [ "$mode" = "none" ]; then
    log "WARN: No SSH key (${PATROL_SSH_IDENTITY:-~/.ssh/id_rsa}) and PATROL_SSH_PASSWORD is empty."
    log "WARN: Remote Linux checks will fail until Config Vault injects PATROL_SSH_PASSWORD or you set PATROL_SSH_IDENTITY."
  fi
}

# SSH exec: password (Vault / PATROL_SSH_PASSWORD) when set; else key; else BatchMode probe.
# Override with PATROL_SSH_AUTH=password|publickey (default auto: password if available).
run_ssh_exec() {
  local user="$1" host="$2" port="$3" password="$4"
  local use_stdin="${5:-0}"
  local remote_script="${6:-}"
  local ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout="$PATROL_SSH_TIMEOUT")
  [ -n "$port" ] && ssh_opts+=(-p "$port")

  local pass
  pass="$(resolve_ssh_password "$password")"
  local id_file
  id_file=$(_ssh_identity_path 2>/dev/null || true)
  local auth_pref="${PATROL_SSH_AUTH:-auto}"

  local target="${user}@${host}"
  if [ -n "$pass" ] && { [ "$auth_pref" = "password" ] || [ "$auth_pref" = "auto" ]; }; then
    if ! command -v sshpass >/dev/null 2>&1; then
      log "ERROR: SSH password auth requires sshpass (install or use PATROL_SSH_IDENTITY key)"
      return 1
    fi
    SSHPASS="$pass" sshpass -e ssh "${ssh_opts[@]}" \
      -o PreferredAuthentications=password,keyboard-interactive,publickey \
      "$target" ${use_stdin:+bash -s} <<< "$remote_script"
  elif [ -n "$id_file" ] && [ -f "$id_file" ]; then
    ssh "${ssh_opts[@]}" -i "$id_file" -o BatchMode=yes -o PreferredAuthentications=publickey \
      "$target" ${use_stdin:+bash -s} <<< "$remote_script"
  elif [ -n "$pass" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
      log "ERROR: SSH password auth requires sshpass (install or use PATROL_SSH_IDENTITY key)"
      return 1
    fi
    SSHPASS="$pass" sshpass -e ssh "${ssh_opts[@]}" \
      -o PreferredAuthentications=password,keyboard-interactive,publickey \
      "$target" ${use_stdin:+bash -s} <<< "$remote_script"
  else
    ssh "${ssh_opts[@]}" -o BatchMode=yes "$target" ${use_stdin:+bash -s} <<< "$remote_script"
  fi
}

run_ssh_probe() {
  local user="$1" host="$2" port="$3" password="${4:-}"
  run_ssh_exec "$user" "$host" "$port" "$password" 1 "$(build_remote_probe)"
}

parse_probe_output() {
  local raw="$1"
  local server_name="$2"
  local -a disk_lines=()
  local -a svc_lines=()
  local -a docker_lines=()
  local -a failed_units=()
  local -a top_procs=()
  local hostname="" uptime_line="" load1="" cores="" cpu_pct="" mem_line=""
  local sd_running="" sd_failed="" proc_total="" proc_zombie=""
  local docker_running=0 docker_total=0 docker_stopped=0 docker_unhealthy=0 docker_installed=0
  local k8s_installed=0 k8s_connected=0 k8s_client="" k8s_context="" k8s_disconnect_reason=""
  local k8s_nodes_total=0 k8s_nodes_ready=0 k8s_nodes_notready=0
  local k8s_pods_total=0 k8s_pods_running=0 k8s_pods_pending=0 k8s_pods_failed=0 k8s_pods_other=0 k8s_ns_count=0
  local k8s_deploy_total=0 k8s_deploy_ready=0 k8s_deploy_notready=0
  local k8s_ds_total=0 k8s_ds_ready=0 k8s_ds_notready=0
  local k8s_health_unhealthy=0 k8s_kube_system_bad=0
  local -a k8s_node_lines=() k8s_top_node_lines=() k8s_top_pod_lines=() k8s_bad_pod_lines=() k8s_cap_lines=()
  local -a k8s_deploy_bad_lines=() k8s_ds_bad_lines=() k8s_component_lines=() k8s_comp_pod_lines=() k8s_readyz_fail_lines=()

  local section=""
  while IFS= read -r line; do
    case "$line" in
      ===HOST===*) hostname="${line#===HOST===}" ;;
      ===UPTIME===) section="uptime" ;;
      ===LOAD===) section="load" ;;
      ===CPU_CORES===) section="cores" ;;
      ===CPU_USAGE===) section="cpu" ;;
      ===MEM===) section="mem" ;;
      ===DISK===) section="disk" ;;
      ===SERVICES===) section="services" ;;
      ===SYSTEMD===) section="systemd" ;;
      ===PROCESSES===) section="processes" ;;
      ===DOCKER===) section="docker" ;;
      ===K8S===) section="k8s" ;;
      *)
        case "$section" in
          uptime) uptime_line="$line" ;;
          load) load1=$(echo "$line" | awk '{print $1}') ;;
          cores) cores="$line" ;;
          cpu) cpu_pct="$line" ;;
          mem) mem_line="$line" ;;
          disk) [ -n "$line" ] && disk_lines+=("$line") ;;
          services) [[ "$line" == *"|"* ]] && svc_lines+=("$line") ;;
          systemd)
            if [[ "$line" == summary\|running=* ]]; then
              sd_running=$(echo "$line" | sed -n 's/.*running=\([0-9]*\).*/\1/p')
              sd_failed=$(echo "$line" | sed -n 's/.*failed=\([0-9]*\).*/\1/p')
            elif [[ "$line" == *"|failed" ]]; then
              failed_units+=("${line%%|*}")
            fi
            ;;
          processes)
            if [[ "$line" == summary\|total=* ]]; then
              proc_total=$(echo "$line" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
              proc_zombie=$(echo "$line" | sed -n 's/.*zombie=\([0-9]*\).*/\1/p')
            elif [[ "$line" == *"|cpu="* ]] && [[ "$line" == *"|mem="* ]]; then
              local pcpu pmem pname rest
              IFS='|' read -r pname rest <<< "$line"
              pcpu=$(echo "$rest" | sed -n 's/.*cpu=\([0-9.]*\).*/\1/p')
              pmem=$(echo "$rest" | sed -n 's/.*mem=\([0-9.]*\).*/\1/p')
              [ -n "$pname" ] && [ -n "$pcpu" ] && top_procs+=("${pname}:${pcpu}%/${pmem}%")
            fi
            ;;
          docker)
            if [[ "$line" == summary\|* ]]; then
              docker_installed=$(echo "$line" | sed -n 's/.*installed=\([0-9]*\).*/\1/p')
              docker_running=$(echo "$line" | sed -n 's/.*running=\([0-9]*\).*/\1/p')
              docker_total=$(echo "$line" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
              docker_stopped=$(echo "$line" | sed -n 's/.*stopped=\([0-9]*\).*/\1/p')
              docker_unhealthy=$(echo "$line" | sed -n 's/.*unhealthy=\([0-9]*\).*/\1/p')
            elif [[ "$line" == *"|"* ]]; then
              docker_lines+=("$line")
            fi
            ;;
          k8s)
            if [[ "$line" == summary\|installed=* ]]; then
              k8s_installed=$(echo "$line" | sed -n 's/.*installed=\([0-9]*\).*/\1/p')
            elif [[ "$line" == info\|client=* ]]; then
              k8s_client="${line#info|client=}"
            elif [[ "$line" == cluster\|connected=* ]]; then
              k8s_connected=$(echo "$line" | sed -n 's/.*connected=\([0-9]*\).*/\1/p')
              k8s_context=$(echo "$line" | sed -n 's/.*context=\([^|]*\).*/\1/p')
              k8s_disconnect_reason=$(echo "$line" | sed -n 's/.*reason=\(.*\)/\1/p')
            elif [[ "$line" == nodes\|* ]]; then
              k8s_nodes_total=$(echo "$line" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
              k8s_nodes_ready=$(echo "$line" | sed -n 's/.*ready=\([0-9]*\).*/\1/p')
              k8s_nodes_notready=$(echo "$line" | sed -n 's/.*notready=\([0-9]*\).*/\1/p')
            elif [[ "$line" == pods\|* ]]; then
              k8s_pods_total=$(echo "$line" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
              k8s_pods_running=$(echo "$line" | sed -n 's/.*running=\([0-9]*\).*/\1/p')
              k8s_pods_pending=$(echo "$line" | sed -n 's/.*pending=\([0-9]*\).*/\1/p')
              k8s_pods_failed=$(echo "$line" | sed -n 's/.*failed=\([0-9]*\).*/\1/p')
              k8s_pods_other=$(echo "$line" | sed -n 's/.*other=\([0-9]*\).*/\1/p')
            elif [[ "$line" == namespaces\|* ]]; then
              k8s_ns_count=$(echo "$line" | sed -n 's/.*count=\([0-9]*\).*/\1/p')
            elif [[ "$line" == deployments\|* ]]; then
              k8s_deploy_total=$(echo "$line" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
              k8s_deploy_ready=$(echo "$line" | sed -n 's/.*ready=\([0-9]*\).*/\1/p')
              k8s_deploy_notready=$(echo "$line" | sed -n 's/.*notready=\([0-9]*\).*/\1/p')
            elif [[ "$line" == daemonsets\|* ]]; then
              k8s_ds_total=$(echo "$line" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
              k8s_ds_ready=$(echo "$line" | sed -n 's/.*ready=\([0-9]*\).*/\1/p')
              k8s_ds_notready=$(echo "$line" | sed -n 's/.*notready=\([0-9]*\).*/\1/p')
            elif [[ "$line" == health\|* ]]; then
              local _hu _kf _kb
              _hu=$(echo "$line" | sed -n 's/.*unhealthy=\([0-9]*\).*/\1/p')
              _kf=$(echo "$line" | sed -n 's/.*readyz_fail=\([0-9]*\).*/\1/p')
              _kb=$(echo "$line" | sed -n 's/.*kube_system_bad_pods=\([0-9]*\).*/\1/p')
              [ -n "$_hu" ] && [ "${_hu:-0}" -gt "${k8s_health_unhealthy:-0}" ] 2>/dev/null && k8s_health_unhealthy="$_hu"
              [ -n "$_kf" ] && [ "${_kf:-0}" -gt "${k8s_health_unhealthy:-0}" ] 2>/dev/null && k8s_health_unhealthy="$_kf"
              [ -n "$_kb" ] && k8s_kube_system_bad="$_kb"
            elif [[ "$line" == node\|* ]]; then
              k8s_node_lines+=("$line")
            elif [[ "$line" == top-node\|* ]]; then
              k8s_top_node_lines+=("$line")
            elif [[ "$line" == top-pod\|* ]]; then
              k8s_top_pod_lines+=("$line")
            elif [[ "$line" == bad-pod\|* ]] || [[ "$line" == restart-pod\|* ]]; then
              k8s_bad_pod_lines+=("$line")
            elif [[ "$line" == deploy-bad\|* ]]; then
              k8s_deploy_bad_lines+=("$line")
            elif [[ "$line" == ds-bad\|* ]]; then
              k8s_ds_bad_lines+=("$line")
            elif [[ "$line" == component\|* ]]; then
              k8s_component_lines+=("$line")
              [[ "$line" != *"|Healthy" ]] && k8s_health_unhealthy=$((k8s_health_unhealthy + 1))
            elif [[ "$line" == comp-pod\|* ]]; then
              k8s_comp_pod_lines+=("$line")
            elif [[ "$line" == readyz-fail\|* ]]; then
              k8s_readyz_fail_lines+=("$line")
            elif [[ "$line" == cap\|* ]]; then
              k8s_cap_lines+=("$line")
            fi
            ;;
        esac
        ;;
    esac
  done <<< "$raw"

  local mem_pct=0
  if [[ "$mem_line" == *"pct="* ]]; then
    mem_pct=$(echo "$mem_line" | sed -n 's/.*pct=\([0-9.]*\).*/\1/p')
  fi

  local disk_worst=OK mem_sev=OK load_sev=OK cpu_sev=OK svc_worst=OK proc_sev=OK docker_sev=OK k8s_sev=OK
  mem_sev=$(severity_mem "${mem_pct:-0}")
  load_sev=$(severity_load "${load1:-0}")
  cpu_sev=$(severity_cpu "${cpu_pct:-0}")

  local -a disk_report=()
  for dl in ${disk_lines[@]+"${disk_lines[@]}"}; do
    local mp pct avail size
    IFS=':' read -r mp pct avail size <<< "$dl"
    pct="${pct%%%}"
    local sev
    sev=$(severity_disk "$pct")
    disk_report+=("${mp}:${pct}:${sev}")
    disk_worst=$(worst "$disk_worst" "$sev")
  done

  local -a inactive_svcs=()
  for sl in ${svc_lines[@]+"${svc_lines[@]}"}; do
    local sn st
    IFS='|' read -r sn st <<< "$sl"
    if [ "$st" = "inactive" ]; then
      inactive_svcs+=("$sn")
      svc_worst=CRIT
    elif [ "$st" = "unknown" ] && [ "$svc_worst" = "OK" ]; then
      svc_worst=WARN
    fi
  done

  if [ "${sd_failed:-0}" -gt 0 ] 2>/dev/null || [ "${#failed_units[@]}" -gt 0 ]; then
    svc_worst=CRIT
  fi
  if [ "${proc_zombie:-0}" -gt 0 ] 2>/dev/null; then
    proc_sev=WARN
  fi
  if [ "${docker_installed:-0}" -eq 1 ]; then
    if [ "${docker_unhealthy:-0}" -gt 0 ] 2>/dev/null; then
      docker_sev=CRIT
    elif [ "${docker_stopped:-0}" -gt 0 ] 2>/dev/null; then
      docker_sev=WARN
    fi
  fi

  if [ "${k8s_installed:-0}" -eq 1 ]; then
    if [ "${k8s_connected:-0}" -ne 1 ]; then
      k8s_sev=WARN
    elif [ "${k8s_nodes_notready:-0}" -gt 0 ] 2>/dev/null; then
      k8s_sev=CRIT
    elif [ "${k8s_pods_failed:-0}" -gt 0 ] 2>/dev/null || [ "${#k8s_bad_pod_lines[@]}" -gt 0 ]; then
      k8s_sev=CRIT
    elif [ "${k8s_health_unhealthy:-0}" -gt 0 ] 2>/dev/null || [ "${k8s_kube_system_bad:-0}" -gt 0 ] 2>/dev/null \
      || [ "${#k8s_comp_pod_lines[@]}" -gt 0 ] || [ "${#k8s_readyz_fail_lines[@]}" -gt 0 ]; then
      k8s_sev=CRIT
    elif [ "${k8s_deploy_notready:-0}" -gt 0 ] 2>/dev/null || [ "${k8s_ds_notready:-0}" -gt 0 ] 2>/dev/null \
      || [ "${#k8s_deploy_bad_lines[@]}" -gt 0 ] || [ "${#k8s_ds_bad_lines[@]}" -gt 0 ]; then
      k8s_sev=WARN
    elif [ "${k8s_pods_pending:-0}" -gt 0 ] 2>/dev/null || [ "${k8s_pods_other:-0}" -gt 0 ] 2>/dev/null; then
      k8s_sev=WARN
    fi
  fi

  local overall
  overall=$(worst "$disk_worst" "$mem_sev" "$load_sev" "$cpu_sev" "$svc_worst" "$proc_sev" "$docker_sev" "$k8s_sev")

  local disk_json=""
  for dr in ${disk_report[@]+"${disk_report[@]}"}; do disk_json+="${dr};"; done

  local systemd_summary="running=${sd_running:-0},failed=${sd_failed:-0}"
  local failed_units_str proc_top_str docker_list_str
  failed_units_str=$(IFS=,; echo "${failed_units[*]-}")
  [ -z "$failed_units_str" ] && failed_units_str="-"
  proc_top_str=$(IFS=,; echo "${top_procs[*]-}")
  local proc_summary="total=${proc_total:-0},zombie=${proc_zombie:-0},top=${proc_top_str:--}"
  local docker_summary="installed=${docker_installed:-0},running=${docker_running:-0},total=${docker_total:-0},stopped=${docker_stopped:-0},unhealthy=${docker_unhealthy:-0}"
  docker_list_str=""
  for dl in ${docker_lines[@]+"${docker_lines[@]}"}; do docker_list_str+="${dl};"; done
  [ -z "$docker_list_str" ] && docker_list_str="-"

  local k8s_summary k8s_detail_str k8s_item
  k8s_summary="installed=${k8s_installed:-0},connected=${k8s_connected:-0},nodes_total=${k8s_nodes_total:-0},nodes_ready=${k8s_nodes_ready:-0},nodes_notready=${k8s_nodes_notready:-0},pods_total=${k8s_pods_total:-0},pods_running=${k8s_pods_running:-0},pods_pending=${k8s_pods_pending:-0},pods_failed=${k8s_pods_failed:-0},pods_other=${k8s_pods_other:-0},namespaces=${k8s_ns_count:-0},deploy_total=${k8s_deploy_total:-0},deploy_notready=${k8s_deploy_notready:-0},ds_total=${k8s_ds_total:-0},ds_notready=${k8s_ds_notready:-0},health_unhealthy=${k8s_health_unhealthy:-0},kube_system_bad=${k8s_kube_system_bad:-0}"
  if [ "${k8s_installed:-0}" -eq 1 ]; then
    k8s_detail_str="client=${k8s_client:-};context=${k8s_context:-};reason=${k8s_disconnect_reason:-}"
    for k8s_item in ${k8s_node_lines[@]+"${k8s_node_lines[@]}"} ${k8s_top_node_lines[@]+"${k8s_top_node_lines[@]}"} \
      ${k8s_top_pod_lines[@]+"${k8s_top_pod_lines[@]}"} ${k8s_bad_pod_lines[@]+"${k8s_bad_pod_lines[@]}"} \
      ${k8s_deploy_bad_lines[@]+"${k8s_deploy_bad_lines[@]}"} ${k8s_ds_bad_lines[@]+"${k8s_ds_bad_lines[@]}"} \
      ${k8s_component_lines[@]+"${k8s_component_lines[@]}"} ${k8s_comp_pod_lines[@]+"${k8s_comp_pod_lines[@]}"} \
      ${k8s_readyz_fail_lines[@]+"${k8s_readyz_fail_lines[@]}"} ${k8s_cap_lines[@]+"${k8s_cap_lines[@]}"}; do
      [ -n "$k8s_item" ] && k8s_detail_str+="${k8s_item};"
    done
  else
    k8s_detail_str="-"
  fi

  local inactive_out
  inactive_out=$(IFS=,; echo "${inactive_svcs[*]-}")
  [ -z "$inactive_out" ] && inactive_out="-"

  printf 'linux\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$server_name" "$hostname" "$overall" "$uptime_line" "$load1" "$cores" \
    "$cpu_pct" "$mem_pct" "$disk_json" "${#svc_lines[@]}" \
    "$inactive_out" "${docker_running:-0}" \
    "$systemd_summary" "$failed_units_str" "$proc_summary" "$docker_summary" "$docker_list_str" \
    "$k8s_summary" "$k8s_detail_str"
}

inspect_one() {
  local name="$1" user="$2" host="$3" port="$4" local_mode="$5" password="${6:-}"
  local raw
  if [ "$local_mode" = "1" ]; then
    raw=$(run_local_probe 2>&1) || { printf 'LINUXERROR\t%s\t%s\tlocal probe failed\n' "$name" "$name"; return 1; }
  else
    local auth_mode hint=""
    auth_mode="$(ssh_auth_mode_for "$password")"
    if [ "$auth_mode" = "none" ]; then
      hint=" (no SSH key and PATROL_SSH_PASSWORD empty; check Config Vault PASSWORD → PATROL_SSH_PASSWORD injection)"
    fi
    raw=$(run_ssh_probe "$user" "$host" "$port" "$password" 2>&1) || {
      printf 'LINUXERROR\t%s\t%s\tSSH failed%s: %s\n' "$name" "$name" "$hint" "$(echo "$raw" | tail -1 | tr '\t' ' ')"
      return 1
    }
  fi
  parse_probe_output "$raw" "$name"
}

emit_markdown_header() {
  printf '# 基础设施巡检报告\n\n'
  printf '生成时间: %s\n\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  printf 'Linux 阈值: 磁盘 %s%%/%s%% | 内存 %s%%/%s%% | 负载 %s/%s | CPU WARN=%s%%\n' \
    "$PATROL_DISK_WARN" "$PATROL_DISK_CRIT" \
    "$PATROL_MEM_WARN" "$PATROL_MEM_CRIT" \
    "$PATROL_LOAD_WARN" "$PATROL_LOAD_CRIT" "$PATROL_CPU_WARN"
  printf '网络阈值: Ping 丢包 WARN/CRIT=%s%%/%s%% | RTT WARN/CRIT=%sms/%sms | CPU WARN=%s%%\n\n' \
    "$PATROL_PING_LOSS_WARN" "$PATROL_PING_LOSS_CRIT" \
    "$PATROL_PING_RTT_WARN" "$PATROL_PING_RTT_CRIT" "$PATROL_NET_CPU_WARN"
}

emit_markdown_linux_row() {
  local line="$1"
  if [[ "$line" == LINUXERROR* ]]; then
    IFS=$'\t' read -r _ name _ msg <<< "$line"
    printf '### %s — **ERROR**\n\n- %s\n\n' "$name" "$msg"
    return
  fi
  IFS=$'\t' read -r _ name hostname overall uptime load cores cpu mem disk_json svc_count inactive docker_cnt \
    systemd_summary failed_units proc_summary docker_summary docker_list k8s_summary k8s_detail <<< "$line"
  [ "$failed_units" = "-" ] && failed_units=""
  [ "$docker_list" = "-" ] && docker_list=""
  [ "$inactive" = "-" ] && inactive=""
  [ "$k8s_detail" = "-" ] && k8s_detail=""
  printf '### %s (%s) — **%s**\n\n' "$name" "$hostname" "$overall"
  printf '| 检查项 | 状态 | 详情 |\n|--------|------|------|\n'
  printf '| 运行时间 | OK | `%s` |\n' "$uptime"
  local load_sev; load_sev=$(severity_load "${load:-0}")
  printf '| 负载 (1m) | %s | %s（%s 核） |\n' "$load_sev" "$load" "$cores"
  local cpu_sev; cpu_sev=$(severity_cpu "${cpu:-0}")
  printf '| CPU 使用率 | %s | %s%% |\n' "$cpu_sev" "$cpu"
  local mem_sev; mem_sev=$(severity_mem "${mem:-0}")
  printf '| 内存使用率 | %s | %s%% |\n' "$mem_sev" "$mem"
  if [ -n "$disk_json" ]; then
    IFS=';' read -ra parts <<< "$disk_json"
    for p in "${parts[@]}"; do
      [ -z "$p" ] && continue
      IFS=':' read -r mp dp sev <<< "$p"
      printf '| 磁盘 %s | %s | %s%% |\n' "$mp" "$sev" "$dp"
    done
  fi

  local proc_total proc_zombie proc_top
  proc_total=$(echo "$proc_summary" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
  proc_zombie=$(echo "$proc_summary" | sed -n 's/.*zombie=\([0-9]*\).*/\1/p')
  proc_top=$(echo "$proc_summary" | sed -n 's/.*top=\(.*\)/\1/p')
  local proc_sev=OK
  [ "${proc_zombie:-0}" -gt 0 ] 2>/dev/null && proc_sev=WARN
  printf '| 进程总数 | %s | %s |\n' "$proc_sev" "${proc_total:-未知}"
  printf '| 僵尸进程 | %s | %s |\n' "$proc_sev" "${proc_zombie:-0}"
  if [ -n "$proc_top" ] && [ "$proc_top" != "-" ]; then
    printf '| CPU Top5 进程 | OK | %s |\n' "$(echo "$proc_top" | tr ',' '; ')"
  fi

  local sd_running sd_failed
  sd_running=$(echo "$systemd_summary" | sed -n 's/.*running=\([0-9]*\).*/\1/p')
  sd_failed=$(echo "$systemd_summary" | sed -n 's/.*failed=\([0-9]*\).*/\1/p')
  local sd_sev=OK
  [ "${sd_failed:-0}" -gt 0 ] 2>/dev/null && sd_sev=CRIT
  [ -n "$failed_units" ] && sd_sev=CRIT
  printf '| systemd 运行中 | OK | %s 个服务 |\n' "${sd_running:-0}"
  printf '| systemd 失败 | %s | failed=%s' "$sd_sev" "${sd_failed:-0}"
  [ -n "$failed_units" ] && printf '：`%s`' "$failed_units"
  printf ' |\n'

  if [ "${svc_count:-0}" -gt 0 ]; then
    local svc_sev=OK
    [ -n "$inactive" ] && svc_sev=CRIT
    printf '| 指定服务 (PATROL_SERVICES) | %s | 检查 %s 个' "$svc_sev" "$svc_count"
    [ -n "$inactive" ] && printf '，未运行: `%s`' "$inactive"
    printf ' |\n'
  fi

  local d_installed d_running d_total d_stopped d_unhealthy
  d_installed=$(echo "$docker_summary" | sed -n 's/.*installed=\([0-9]*\).*/\1/p')
  d_running=$(echo "$docker_summary" | sed -n 's/.*running=\([0-9]*\).*/\1/p')
  d_total=$(echo "$docker_summary" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
  d_stopped=$(echo "$docker_summary" | sed -n 's/.*stopped=\([0-9]*\).*/\1/p')
  d_unhealthy=$(echo "$docker_summary" | sed -n 's/.*unhealthy=\([0-9]*\).*/\1/p')
  local d_sev=OK
  [ "${d_unhealthy:-0}" -gt 0 ] 2>/dev/null && d_sev=CRIT
  [ "$d_sev" = OK ] && [ "${d_stopped:-0}" -gt 0 ] 2>/dev/null && d_sev=WARN
  if [ "${d_installed:-0}" -eq 0 ]; then
    printf '| Docker | OK | 未安装或未在 PATH 中 |\n'
  else
    printf '| Docker 容器 | %s | 运行 %s / 总计 %s / 已停止 %s' "$d_sev" "${d_running:-0}" "${d_total:-0}" "${d_stopped:-0}"
    [ "${d_unhealthy:-0}" -gt 0 ] 2>/dev/null && printf ' / 不健康 %s' "$d_unhealthy"
    printf ' |\n'
    if [ -n "$docker_list" ]; then
      local container_detail=""
      IFS=';' read -ra dparts <<< "$docker_list"
      for dp in "${dparts[@]}"; do
        [ -z "$dp" ] && continue
        local dname dstat dimg
        IFS='|' read -r dname dstat dimg <<< "$dp"
        container_detail+="${dname}: ${dstat}"
        [ -n "$dimg" ] && container_detail+=" (${dimg})"
        container_detail+="; "
      done
      printf '| 容器列表 | %s | %s |\n' "$d_sev" "$(echo "$container_detail" | sed 's/; $//')"
    elif [ "${d_total:-0}" -eq 0 ]; then
      printf '| 容器列表 | OK | 无容器 |\n'
    fi
  fi

  local k8s_installed k8s_connected k8s_nt k8s_nr k8s_nn k8s_pt k8s_pr k8s_pp k8s_pf k8s_po k8s_ns k8s_sev k8s_client k8s_ctx
  local k8s_dt k8s_dn k8s_dst k8s_dsn k8s_hu k8s_ksb
  k8s_installed=$(echo "$k8s_summary" | sed -n 's/.*installed=\([0-9]*\).*/\1/p')
  k8s_connected=$(echo "$k8s_summary" | sed -n 's/.*connected=\([0-9]*\).*/\1/p')
  k8s_nt=$(echo "$k8s_summary" | sed -n 's/.*nodes_total=\([0-9]*\).*/\1/p')
  k8s_nr=$(echo "$k8s_summary" | sed -n 's/.*nodes_ready=\([0-9]*\).*/\1/p')
  k8s_nn=$(echo "$k8s_summary" | sed -n 's/.*nodes_notready=\([0-9]*\).*/\1/p')
  k8s_pt=$(echo "$k8s_summary" | sed -n 's/.*pods_total=\([0-9]*\).*/\1/p')
  k8s_pr=$(echo "$k8s_summary" | sed -n 's/.*pods_running=\([0-9]*\).*/\1/p')
  k8s_pp=$(echo "$k8s_summary" | sed -n 's/.*pods_pending=\([0-9]*\).*/\1/p')
  k8s_pf=$(echo "$k8s_summary" | sed -n 's/.*pods_failed=\([0-9]*\).*/\1/p')
  k8s_po=$(echo "$k8s_summary" | sed -n 's/.*pods_other=\([0-9]*\).*/\1/p')
  k8s_ns=$(echo "$k8s_summary" | sed -n 's/.*namespaces=\([0-9]*\).*/\1/p')
  k8s_dt=$(echo "$k8s_summary" | sed -n 's/.*deploy_total=\([0-9]*\).*/\1/p')
  k8s_dn=$(echo "$k8s_summary" | sed -n 's/.*deploy_notready=\([0-9]*\).*/\1/p')
  k8s_dst=$(echo "$k8s_summary" | sed -n 's/.*ds_total=\([0-9]*\).*/\1/p')
  k8s_dsn=$(echo "$k8s_summary" | sed -n 's/.*ds_notready=\([0-9]*\).*/\1/p')
  k8s_hu=$(echo "$k8s_summary" | sed -n 's/.*health_unhealthy=\([0-9]*\).*/\1/p')
  k8s_ksb=$(echo "$k8s_summary" | sed -n 's/.*kube_system_bad=\([0-9]*\).*/\1/p')
  k8s_client=$(echo "$k8s_detail" | sed -n 's/.*client=\([^;]*\).*/\1/p')
  k8s_ctx=$(echo "$k8s_detail" | sed -n 's/.*context=\([^;]*\).*/\1/p')
  k8s_sev=OK
  if [ "${k8s_installed:-0}" -eq 0 ]; then
    printf '| Kubernetes | OK | 未安装 kubectl |\n'
  elif [ "${k8s_connected:-0}" -ne 1 ]; then
    k8s_sev=WARN
    local k8s_reason
    k8s_reason=$(echo "$k8s_detail" | sed -n 's/.*reason=\([^;]*\).*/\1/p')
    printf '| Kubernetes | %s | kubectl 已安装但无法连接集群' "$k8s_sev"
    [ -n "$k8s_client" ] && printf '（%s）' "$k8s_client"
    [ -n "$k8s_reason" ] && printf '：%s' "$k8s_reason"
    printf ' |\n'
  else
    [ "${k8s_nn:-0}" -gt 0 ] 2>/dev/null && k8s_sev=CRIT
    [ "$k8s_sev" = OK ] && { [ "${k8s_pf:-0}" -gt 0 ] 2>/dev/null || [ "${k8s_po:-0}" -gt 0 ] 2>/dev/null \
      || [ "${k8s_hu:-0}" -gt 0 ] 2>/dev/null || [ "${k8s_ksb:-0}" -gt 0 ] 2>/dev/null; } && k8s_sev=CRIT
    [ "$k8s_sev" = OK ] && { [ "${k8s_dn:-0}" -gt 0 ] 2>/dev/null || [ "${k8s_dsn:-0}" -gt 0 ] 2>/dev/null; } && k8s_sev=WARN
    [ "$k8s_sev" = OK ] && [ "${k8s_pp:-0}" -gt 0 ] 2>/dev/null && k8s_sev=WARN
    printf '| Kubernetes 集群 | %s | context=`%s`' "$k8s_sev" "${k8s_ctx:-default}"
    [ -n "$k8s_client" ] && printf ' | %s' "$k8s_client"
    printf ' |\n'
    printf '| K8s 节点 | %s | 总计 %s / Ready %s / NotReady %s |\n' "$k8s_sev" "${k8s_nt:-0}" "${k8s_nr:-0}" "${k8s_nn:-0}"
    printf '| K8s Pod | %s | 总计 %s / Running %s / Pending %s / Failed %s / 其他 %s |\n' \
      "$k8s_sev" "${k8s_pt:-0}" "${k8s_pr:-0}" "${k8s_pp:-0}" "${k8s_pf:-0}" "${k8s_po:-0}"
    printf '| K8s 命名空间 | OK | %s 个 |\n' "${k8s_ns:-0}"
    if ! echo "$k8s_detail" | grep -q 'cap|deployments=skip'; then
      local dep_sev=OK
      [ "${k8s_dn:-0}" -gt 0 ] 2>/dev/null && dep_sev=WARN
      printf '| K8s Deployment | %s | 总计 %s / 就绪 %s / 未就绪 %s |\n' \
        "$dep_sev" "${k8s_dt:-0}" "$((${k8s_dt:-0} - ${k8s_dn:-0}))" "${k8s_dn:-0}"
    fi
    if ! echo "$k8s_detail" | grep -q 'cap|daemonsets=skip'; then
      local ds_sev=OK
      [ "${k8s_dsn:-0}" -gt 0 ] 2>/dev/null && ds_sev=WARN
      printf '| K8s DaemonSet | %s | 总计 %s / 就绪 %s / 未就绪 %s |\n' \
        "$ds_sev" "${k8s_dst:-0}" "$((${k8s_dst:-0} - ${k8s_dsn:-0}))" "${k8s_dsn:-0}"
    fi
    if [ "${k8s_hu:-0}" -gt 0 ] 2>/dev/null || [ "${k8s_ksb:-0}" -gt 0 ] 2>/dev/null; then
      printf '| K8s 组件健康 | CRIT | 异常组件/检查 %s 项，kube-system 非 Running Pod %s 个 |\n' "${k8s_hu:-0}" "${k8s_ksb:-0}"
    else
      printf '| K8s 组件健康 | OK | componentstatuses / healthz / readyz / kube-system 检查通过 |\n'
    fi
    if [ -n "$k8s_detail" ]; then
      local k8s_nodes_txt="" k8s_topn_txt="" k8s_topp_txt="" k8s_bad_txt="" k8s_cap_txt="" \
        k8s_dep_bad_txt="" k8s_ds_bad_txt="" k8s_comp_txt="" k8s_comp_pod_txt="" k8s_rz_fail_txt="" part
      IFS=';' read -ra kparts <<< "$k8s_detail"
      for part in "${kparts[@]}"; do
        [ -z "$part" ] && continue
        case "$part" in
          client=*|context=*|reason=*) ;;
          node\|*)
            k8s_nodes_txt+="${part#node|}; "
            ;;
          top-node\|*)
            k8s_topn_txt+="${part#top-node|}; "
            ;;
          top-pod\|*)
            k8s_topp_txt+="${part#top-pod|}; "
            ;;
          bad-pod\|*|restart-pod\|*)
            k8s_bad_txt+="${part}; "
            ;;
          deploy-bad\|*)
            k8s_dep_bad_txt+="${part#deploy-bad|}; "
            ;;
          ds-bad\|*)
            k8s_ds_bad_txt+="${part#ds-bad|}; "
            ;;
          component\|*)
            k8s_comp_txt+="${part#component|}; "
            ;;
          comp-pod\|*)
            k8s_comp_pod_txt+="${part#comp-pod|}; "
            ;;
          readyz-fail\|*)
            k8s_rz_fail_txt+="${part#readyz-fail|}; "
            ;;
          cap\|top_nodes=skip\|*)
            k8s_cap_txt+="top nodes 跳过: ${part#cap|top_nodes=skip|reason=}; "
            ;;
          cap\|top_pods=skip\|*)
            k8s_cap_txt+="top pods 跳过: ${part#cap|top_pods=skip|reason=}; "
            ;;
          cap\|nodes=skip\|*)
            k8s_cap_txt+="nodes 跳过: ${part#cap|nodes=skip|reason=}; "
            ;;
          cap\|pods=skip\|*)
            k8s_cap_txt+="pods 跳过: ${part#cap|pods=skip|reason=}; "
            ;;
          cap\|namespaces=skip\|*)
            k8s_cap_txt+="namespaces 跳过: ${part#cap|namespaces=skip|reason=}; "
            ;;
          cap\|deployments=skip\|*)
            k8s_cap_txt+="deployments 跳过: ${part#cap|deployments=skip|reason=}; "
            ;;
          cap\|daemonsets=skip\|*)
            k8s_cap_txt+="daemonsets 跳过: ${part#cap|daemonsets=skip|reason=}; "
            ;;
          cap\|health_kube_system=skip\|*)
            k8s_cap_txt+="kube-system 健康检查跳过: ${part#cap|health_kube_system=skip|reason=}; "
            ;;
        esac
      done
      [ -n "$k8s_nodes_txt" ] && printf '| K8s 节点列表 | OK | %s |\n' "$(echo "$k8s_nodes_txt" | sed 's/; $//')"
      [ -n "$k8s_comp_txt" ] && printf '| 控制面组件 (cs) | OK | %s |\n' "$(echo "$k8s_comp_txt" | sed 's/; $//')"
      [ -n "$k8s_rz_fail_txt" ] && printf '| readyz 失败项 | CRIT | %s |\n' "$(echo "$k8s_rz_fail_txt" | sed 's/; $//')"
      [ -n "$k8s_comp_pod_txt" ] && printf '| kube-system 异常 Pod | CRIT | %s |\n' "$(echo "$k8s_comp_pod_txt" | sed 's/; $//')"
      [ -n "$k8s_dep_bad_txt" ] && printf '| 未就绪 Deployment | WARN | %s |\n' "$(echo "$k8s_dep_bad_txt" | sed 's/; $//')"
      [ -n "$k8s_ds_bad_txt" ] && printf '| 未就绪 DaemonSet | WARN | %s |\n' "$(echo "$k8s_ds_bad_txt" | sed 's/; $//')"
      [ -n "$k8s_topn_txt" ] && printf '| kubectl top nodes | OK | %s |\n' "$(echo "$k8s_topn_txt" | sed 's/; $//')"
      [ -n "$k8s_topp_txt" ] && printf '| kubectl top pods (Top5) | OK | %s |\n' "$(echo "$k8s_topp_txt" | sed 's/; $//')"
      [ -n "$k8s_cap_txt" ] && printf '| K8s 子命令兼容 | OK | %s（单项失败不影响其余巡检） |\n' "$(echo "$k8s_cap_txt" | sed 's/; $//')"
      if [ -n "$k8s_bad_txt" ]; then
        printf '| 异常 Pod | CRIT | %s |\n' "$(echo "$k8s_bad_txt" | sed 's/; $//')"
      fi
    fi
  fi
  printf '\n'
}

emit_markdown_network_row() {
  local line="$1"
  if [[ "$line" == NETERROR* ]]; then
    IFS=$'\t' read -r _ name host msg <<< "$line"
    printf '### %s (%s) — **ERROR**\n\n- %s\n\n' "$name" "$host" "$msg"
    return
  fi
  IFS=$'\t' read -r _ name dtype host overall ping_loss ping_rtt ports_str ports_closed cpu mem uptime ifaces model snmp <<< "$line"
  printf '### %s (%s) [%s] — **%s**\n\n' "$name" "$host" "$dtype" "$overall"
  printf '| 检查项 | 状态 | 详情 |\n|--------|------|------|\n'
  local ping_sev rtt_sev
  ping_sev=$(severity_ping_loss "$ping_loss")
  rtt_sev=$(severity_ping_rtt "$ping_rtt")
  printf '| Ping 丢包 | %s | %s%% |\n' "$ping_sev" "$ping_loss"
  printf '| Ping RTT | %s | %s ms |\n' "$rtt_sev" "$ping_rtt"
  if [ -n "$ports_str" ]; then
    local port_sev=OK
    [ "${ports_closed:-0}" -gt 0 ] && port_sev=WARN
    [ "$ping_loss" -ge 100 ] 2>/dev/null && port_sev=CRIT
    printf '| TCP 端口 | %s | %s |\n' "$port_sev" "$(echo "$ports_str" | tr ';' ' ')"
  fi
  if [ -n "$cpu" ] && [ "$cpu" != "-" ]; then
    local cpu_sev; cpu_sev=$(severity_net_pct "$cpu" "$PATROL_NET_CPU_WARN")
    printf '| CPU | %s | %s%% |\n' "$cpu_sev" "$cpu"
  fi
  if [ -n "$mem" ] && [ "$mem" != "-" ]; then
    local mem_sev; mem_sev=$(severity_net_pct "$mem" "$PATROL_NET_MEM_WARN")
    printf '| 内存 | %s | %s%% |\n' "$mem_sev" "$mem"
  fi
  [ -n "$uptime" ] && [ "$uptime" != "-" ] && printf '| 运行时间 | OK | `%s` |\n' "$uptime"
  [ -n "$model" ] && [ "$model" != "-" ] && printf '| 型号/版本 | OK | `%s` |\n' "$model"
  [ -n "$ifaces" ] && [ "$ifaces" != "-" ] && printf '| 接口摘要 | OK | %s |\n' "$(echo "$ifaces" | tr ';' ' ' | head -c 200)"
  [ "$snmp" = "OK" ] && printf '| SNMP | OK | sys OID 采集成功 |\n'
  printf '\n'
}

emit_markdown_results() {
  local -a lines=("$@")
  local has_linux=0 has_net=0
  for line in "${lines[@]}"; do
    [[ "$line" == linux* || "$line" == LINUXERROR* ]] && has_linux=1
    [[ "$line" == network* || "$line" == NETERROR* ]] && has_net=1
  done
  if [ "$has_linux" -eq 1 ]; then
    printf '## Linux 服务器\n\n'
    for line in "${lines[@]}"; do
      [[ "$line" == linux* || "$line" == LINUXERROR* ]] && emit_markdown_linux_row "$line"
    done
  fi
  if [ "$has_net" -eq 1 ]; then
    printf '## 网络设备（路由器 / 交换机 / 防火墙）\n\n'
    for line in "${lines[@]}"; do
      [[ "$line" == network* || "$line" == NETERROR* ]] && emit_markdown_network_row "$line"
    done
  fi
}

emit_json_results() {
  local -a lines=("$@")
  printf '{"version":"%s","generated_at":"%s","results":[' "$VERSION" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local first=1
  for line in "${lines[@]}"; do
    [ $first -eq 1 ] && first=0 || printf ','
    if [[ "$line" == LINUXERROR* ]]; then
      IFS=$'\t' read -r _ name _ msg <<< "$line"
      printf '{"kind":"linux","name":"%s","status":"ERROR","error":"%s"}' "$name" "$(echo "$msg" | sed 's/"/\\"/g')"
    elif [[ "$line" == NETERROR* ]]; then
      IFS=$'\t' read -r _ name host msg <<< "$line"
      printf '{"kind":"network","name":"%s","host":"%s","status":"ERROR","error":"%s"}' "$name" "$host" "$(echo "$msg" | sed 's/"/\\"/g')"
    elif [[ "$line" == network* ]]; then
      IFS=$'\t' read -r _ name dtype host overall ping_loss ping_rtt ports_str ports_closed cpu mem uptime ifaces model snmp <<< "$line"
      printf '{"kind":"network","name":"%s","type":"%s","host":"%s","status":"%s","ping_loss":%s,"ping_rtt":%s,"cpu_pct":"%s","mem_pct":"%s"}' \
        "$name" "$dtype" "$host" "$overall" "${ping_loss:-100}" "${ping_rtt:-0}" "${cpu:-}" "${mem:-}"
    else
      IFS=$'\t' read -r _ name hostname overall uptime load cores cpu mem disk_json svc_count inactive docker_cnt \
        systemd_summary failed_units proc_summary docker_summary docker_list k8s_summary k8s_detail <<< "$line"
      [ "$failed_units" = "-" ] && failed_units=""
      [ "$docker_list" = "-" ] && docker_list=""
      [ "$inactive" = "-" ] && inactive=""
      [ "$k8s_detail" = "-" ] && k8s_detail=""
      printf '{"kind":"linux","name":"%s","hostname":"%s","status":"%s","load":%s,"cpu_pct":%s,"mem_pct":%s,"inactive_services":"%s","systemd":"%s","failed_units":"%s","processes":"%s","docker":"%s","containers":"%s","kubernetes":"%s","k8s_detail":"%s"}' \
        "$name" "$hostname" "$overall" "${load:-0}" "${cpu:-0}" "${mem:-0}" "${inactive:-}" \
        "$(echo "$systemd_summary" | sed 's/"/\\"/g')" \
        "$(echo "$failed_units" | sed 's/"/\\"/g')" \
        "$(echo "$proc_summary" | sed 's/"/\\"/g')" \
        "$(echo "$docker_summary" | sed 's/"/\\"/g')" \
        "$(echo "$docker_list" | sed 's/"/\\"/g')" \
        "$(echo "$k8s_summary" | sed 's/"/\\"/g')" \
        "$(echo "$k8s_detail" | sed 's/"/\\"/g')"
    fi
  done
  printf ']}\n'
}

save_report() {
  local content="$1"
  mkdir -p "$PATROL_REPORT_DIR"
  local ts file
  ts=$(date '+%Y%m%d-%H%M%S')
  if [ "$FORMAT" = "json" ]; then
    file="${PATROL_REPORT_DIR}/patrol-${ts}.json"
  else
    file="${PATROL_REPORT_DIR}/patrol-${ts}.md"
  fi
  printf '%s' "$content" > "$file"
  log "Report saved: $file"
}

match_tag() {
  local tags="$1"
  local want="$2"
  [ -z "$want" ] && return 0
  IFS=',' read -ra tarr <<< "$tags"
  for t in "${tarr[@]}"; do
    [ "$(echo "$t" | xargs)" = "$want" ] && return 0
  done
  return 1
}

run_linux_batch() {
  local -a servers=()
  while IFS= read -r row; do
    [ -n "$row" ] && servers+=("$row")
  done < <(load_servers || true)
  if [ "${#servers[@]}" -gt 0 ]; then
    preflight_ssh_auth_hint
  fi
  if [ "${#servers[@]}" -eq 0 ] && [ "$1" = "fallback_local" ]; then
    log "No PATROL_SERVER configured, falling back to local"
    local line
    line=$(inspect_one "localhost" "$USER" "127.0.0.1" "22" "1") || line=$'LINUXERROR\tlocalhost\tlocalhost\tprobe failed'
    results+=("$line")
    return
  fi
  for row in "${servers[@]}"; do
    IFS=$'\t' read -r name user host port tags password <<< "$row"
    match_tag "$tags" "$FILTER_TAG" || continue
    log "Inspect linux: $name ($user@$host:$port) auth=$(ssh_auth_mode_for "$password")"
    local line
    line=$(inspect_one "$name" "$user" "$host" "$port" "0" "$password") || true
    [ -z "$line" ] && line=$'LINUXERROR\t'"$name"$'\t'"$name"$'\tssh failed'
    results+=("$line")
  done
}

run_network_batch() {
  local -a devices=()
  while IFS= read -r row; do
    [ -n "$row" ] && devices+=("$row")
  done < <(load_network_devices || true)
  if [ "${#devices[@]}" -eq 0 ]; then
    return 0
  fi
  for row in "${devices[@]}"; do
    IFS=$'\t' read -r name dtype host user port tags extra <<< "$row"
    match_tag "$tags" "$FILTER_TAG" || continue
    local line
    line=$(inspect_network_one "$name" "$dtype" "$host" "$user" "$port" "$extra") || true
    [ -n "$line" ] && results+=("$line")
  done
}

# --- main ---
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --tag) FILTER_TAG="$2"; shift 2 ;;
    --all) MODE="all"; shift ;;
    --servers) MODE="all"; SCOPE="servers"; shift ;;
    --network) MODE="all"; SCOPE="network"; shift ;;
    --list) MODE="list"; shift ;;
    local) MODE="local"; shift ;;
    remote) MODE="remote"; TARGET="${2:-}"; shift 2 ;;
    net) MODE="net"; NET_TYPE="${2:-ping}"; TARGET="${3:-}"; shift; [ $# -gt 0 ] && shift || true ;;
    *) log "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

[ -z "$MODE" ] && { usage; exit 1; }

if [ "$MODE" = "list" ]; then
  printf 'TYPE\tNAME\tTARGET\tTAGS\n'
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    IFS=$'\t' read -r name user host port tags password <<< "$row"
    printf 'linux\t%s\t%s@%s:%s\t%s\n' "$name" "$user" "$host" "$port" "$tags"
  done < <(load_servers || true)
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    IFS=$'\t' read -r name dtype host user port tags extra <<< "$row"
    conn="$host"
    [ -n "$user" ] && conn="${user}@${host}"
    [ -n "$port" ] && conn="${conn}:${port}"
    printf 'network\t%s\t%s (%s)\t%s\n' "$name" "$conn" "$dtype" "$tags"
  done < <(load_network_devices || true)
  exit 0
fi

results=()

if [ "$MODE" = "local" ]; then
  line=$(inspect_one "localhost" "$USER" "127.0.0.1" "22" "1") || line=$'LINUXERROR\tlocalhost\tlocalhost\tprobe failed'
  results+=("$line")
elif [ "$MODE" = "remote" ]; then
  [ -z "$TARGET" ] && { log "remote requires user@host"; exit 1; }
  user="${USER:-root}"; host="$TARGET"; port=22
  if [[ "$TARGET" == *"@"* ]]; then user="${TARGET%%@*}"; host="${TARGET#*@}"; fi
  if [[ "$host" == *":"* ]]; then port="${host##*:}"; host="${host%%:*}"; fi
  line=$(inspect_one "$host" "$user" "$host" "$port" "0") || true
  [ -z "$line" ] && line=$'LINUXERROR\t'"$host"$'\t'"$host"$'\tssh failed'
  results+=("$line")
elif [ "$MODE" = "net" ]; then
  [ -z "$TARGET" ] && { log "net requires host"; usage; exit 1; }
  user=""; host="$TARGET"; port=""
  if [[ "$TARGET" == *"@"* ]]; then user="${TARGET%%@*}"; host="${TARGET#*@}"; fi
  if [[ "$host" == *":"* ]]; then port="${host##*:}"; host="${host%%:*}"; fi
  line=$(inspect_network_one "$host" "${NET_TYPE:-ping}" "$host" "$user" "$port" "") || true
  [ -n "$line" ] && results+=("$line")
elif [ "$MODE" = "all" ]; then
  if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "servers" ]; then
    run_linux_batch fallback_local
  fi
  if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "network" ]; then
    run_network_batch
  fi
fi

output=""
if [ "$FORMAT" = "json" ]; then
  output=$(emit_json_results "${results[@]}")
  printf '%s\n' "$output"
else
  { emit_markdown_header
    emit_markdown_results "${results[@]}"
    printf '%s\n\n' '---'
    printf '*server-patrol v%s*\n' "$VERSION"
  } | tee /tmp/patrol-out.$$
  output=$(cat /tmp/patrol-out.$$)
  rm -f /tmp/patrol-out.$$
fi

save_report "$output"
