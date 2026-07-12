#!/bin/bash
NS=${1:-wm-dev}
MON_NS=${2:-monitoring}
echo "================================================"
echo "TC Dashboard Diagnostic — namespace=$NS"
echo "================================================"

echo ""
echo "[1] Terracotta pods + labels"
kubectl get pods -n "$NS" -l app=terracotta --show-labels 2>&1

echo ""
echo "[2] Containers per TC pod (looking for jmx-exporter)"
kubectl get pod -n "$NS" -l app=terracotta -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.containers[*].name}{"\n"}{end}' 2>&1

echo ""
echo "[3] Container ports (looking for port name 'jmx-metrics' on 9404)"
kubectl get pod -n "$NS" -l app=terracotta -o jsonpath='{range .items[*]}{.metadata.name}{": "}{range .spec.containers[*]}{.name}{"="}{range .ports[*]}{.name}":"}{.containerPort}{" "}{end}{end}{"\n"}{end}' 2>&1

echo ""
echo "[4] Resource limits on TC containers"
kubectl get pod -n "$NS" -l app=terracotta -o jsonpath='{range .items[*]}{.metadata.name}{": "}{range .spec.containers[*]}{.name}{"="}{.resources.limits}{" "}{end}{"\n"}{end}' 2>&1

echo ""
echo "[5] PodMonitor / ServiceMonitor resources that could target TC"
kubectl get podmonitor,servicemonitor -A 2>&1 | grep -iE "NAME|terra|tc"

echo ""
echo "[6] PodMonitor spec — selector, port, relabelings"
for pm in $(kubectl get podmonitor -A -o jsonpath='{range .items[?(@.spec.selector.matchLabels.app=="terracotta")]}{.metadata.namespace}/{.metadata.name} {end}' 2>&1); do
  echo "  --- $pm ---"
  kubectl get podmonitor -n "${pm%%/*}" "${pm##*/}" -o yaml 2>&1 | grep -A2 -E "selector:|port:|path:|relabelings:|matchLabels:" | head -20
done

echo ""
echo "[7] Prometheus pod discovery — are PodMonitors selected by the Prometheus CR?"
kubectl get prometheus -n "$MON_NS" -o jsonpath='{.items[*].spec.podMonitorSelector}{"\n"}' 2>&1
kubectl get prometheus -n "$MON_NS" -o jsonpath='{.items[*].spec.podMonitorNamespaceSelector}{"\n"}' 2>&1

echo ""
echo "[8] Live scrape — can a TC pod's /metrics endpoint be hit?"
TC_POD=$(kubectl get pods -n "$NS" -l app=terracotta -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$TC_POD" ]; then
  kubectl exec -n "$NS" "$TC_POD" -c jmx-exporter -- sh -c "wget -qO- http://localhost:9404/metrics 2>&1 | head -20" 2>&1 || echo "  (jmx-exporter container not present — exporter sidecar missing)"
fi

echo ""
echo "[9] Prometheus target status"
kubectl port-forward -n "$MON_NS" svc/prometheus-operated 9090:9090 >/dev/null 2>&1 &
PF=$!
sleep 3
curl -s 'http://localhost:9090/api/v1/targets?state=active' 2>&1 | \
  python -c "
import sys, json
try:
  d=json.load(sys.stdin)
  targets=[t for t in d['data']['activeTargets'] if 'terra' in str(t.get('labels',{})).lower() or 'tc' in str(t.get('labels',{})).lower()]
  for t in targets:
    print(f\"  job={t['labels'].get('job','?')} health={t['health']} url={t['scrapeUrl']} err={t.get('lastError','')[:120]}\")
  if not targets: print('  NO TC TARGETS IN PROMETHEUS — PodMonitor not discovered')
except Exception as e:
  print(f'  ERROR parsing: {e}')
" 2>&1
kill $PF 2>/dev/null

echo ""
echo "[10] Is the metric in Prometheus TSDB?"
kubectl port-forward -n "$MON_NS" svc/prometheus-operated 9090:9090 >/dev/null 2>&1 &
PF=$!
sleep 3
echo "  jvm_memory_used_bytes for TC pods:"
curl -sG 'http://localhost:9090/api/v1/query' --data-urlencode 'query=count(jvm_memory_used_bytes{pod=~"terracotta-.*"})' 2>&1 | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print('  series count:', r[0]['value'][1] if r else 0)" 2>&1
echo "  kube_pod_container_resource_limits for TC pods:"
curl -sG 'http://localhost:9090/api/v1/query' --data-urlencode 'query=count(kube_pod_container_resource_limits{pod=~"terracotta-.*",resource="memory"})' 2>&1 | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print('  series count:', r[0]['value'][1] if r else 0)" 2>&1
kill $PF 2>/dev/null

echo ""
echo "[11] Grafana variable values in use (requires manually checking URL in screenshot)"
echo "  Check dashboard URL — \$namespace should be '$NS'"
echo "  Check dashboard variables — \$terracotta_pod_pattern should match 'terracotta-.*'"

echo ""
echo "================================================"
echo "Done — paste all output back to support"
echo "================================================"
