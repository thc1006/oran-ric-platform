# O-RAN RIC xApps Prometheus Metrics 故障排除指南

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-15

## 目錄

1. [xApp Pod 問題](#xapp-pod-問題)
2. [Metrics 數據問題](#metrics-數據問題)
3. [E2 Simulator 問題](#e2-simulator-問題)
4. [Prometheus 問題](#prometheus-問題)
5. [Grafana 問題](#grafana-問題)
6. [測試失敗問題](#測試失敗問題)

---

## xApp Pod 問題

### 問題: Pod 處於 CrashLoopBackOff 狀態

**症狀:**
```bash
kubectl get pods -n ricxapp
# kpimon-xxx   0/1   CrashLoopBackOff
```

**診斷步驟:**

1. 查看 Pod 日誌
```bash
kubectl logs -n ricxapp <pod-name> --previous
```

2. 查看 Pod 事件
```bash
kubectl describe pod -n ricxapp <pod-name>
```

**常見原因與解決方案:**

#### 原因 1: SDL 連接失敗

日誌顯示:
```
Failed to connect to SDL: Connection refused
```

解決:
```bash
# 檢查 Redis (SDL backend) 是否運行
kubectl get pods -n ricplt | grep redis

# 如果沒有運行，重新部署 RIC Platform
```

#### 原因 2: 端口衝突

日誌顯示:
```
OSError: [Errno 98] Address already in use
```

解決:
檢查 deployment.yaml 中的端口配置，確保沒有重複。

#### 原因 3: 未捕獲的異常

解決:
在可能失敗的外部服務調用周圍添加 try-except：

```python
try:
    self.sdl.set(namespace, data)
except Exception as e:
    logger.warning(f"SDL operation failed: {e}")
```

### 問題: Readiness Probe 失敗

**症狀:**
```
Readiness probe failed: dial tcp 10.42.0.x:8080: connect: connection refused
```

**診斷:**

檢查配置一致性：

```bash
# 1. 檢查 deployment.yaml 中的 containerPort
kubectl get deployment -n ricxapp <xapp-name> -o yaml | grep containerPort

# 2. 檢查 readinessProbe 端口
kubectl get deployment -n ricxapp <xapp-name> -o yaml | grep -A 5 readinessProbe

# 3. 檢查 Service 端口
kubectl get svc -n ricxapp <xapp-name> -o yaml | grep port
```

**解決:**

確保以下端口一致：
- `deployment.yaml`: `containerPort`
- `deployment.yaml`: `readinessProbe.httpGet.port`
- `deployment.yaml`: `livenessProbe.httpGet.port`
- `deployment.yaml`: `prometheus.io/port` annotation
- `service.yaml`: `targetPort`

---

## Metrics 數據問題

### 問題: Prometheus Counters 保持在 0

**症狀:**
Prometheus 查詢結果顯示 0：

```promql
kpimon_messages_received_total
# 結果: 0
```

**診斷步驟:**

1. **檢查 E2 Simulator 是否運行**

```bash
kubectl logs -n ricxapp e2-simulator-xxx | grep "Simulation Iteration"
```

應該看到持續的迭代輸出。

2. **檢查 xApp 是否收到數據**

```bash
kubectl logs -n ricxapp kpimon-xxx | grep -i "indication"
```

3. **檢查代碼是否遞增 counter**

確認 `/e2/indication` endpoint 中有：

```python
MESSAGES_RECEIVED.inc()
MESSAGES_PROCESSED.inc()
```

**解決方案:**

如果缺少 counter 遞增，添加：

```python
@app.route('/e2/indication', methods=['POST'])
def e2_indication():
    # 添加這一行
    MESSAGES_RECEIVED.inc()

    # ... 處理邏輯 ...

    # 處理完成後添加這一行
    MESSAGES_PROCESSED.inc()

    return jsonify({"status": "success"}), 200
```

### 問題: Prometheus 沒有抓取 xApp metrics

**症狀:**
Prometheus Targets 頁面顯示 xApp 為 DOWN 或不存在。

**診斷:**

```bash
# 檢查 Pod annotations
kubectl get pod -n ricxapp <xapp-pod> -o yaml | grep -A 3 annotations
```

應該有：
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/ric/v1/metrics"
```

**解決:**

更新 deployment.yaml 添加正確的 annotations。

---

## E2 Simulator 問題

### 問題: E2 Simulator 無法連接到 xApp

**症狀:**
E2 Simulator 日誌顯示：

```
Connection error for kpimon (xApp may not have REST endpoint yet)
```

**診斷步驟:**

1. **檢查 xApp Service 是否存在**

```bash
kubectl get svc -n ricxapp | grep kpimon
```

2. **檢查端口配置**

```bash
# E2 Simulator 配置
kubectl exec -n ricxapp e2-simulator-xxx -- cat /app/e2_simulator.py | grep -A 5 "'kpimon'"

# 應該顯示:
# 'kpimon': {
#     'host': 'kpimon.ricxapp.svc.cluster.local',
#     'port': 8081,
#     'endpoint': '/e2/indication'
# }
```

3. **測試連接**

```bash
kubectl exec -n ricxapp e2-simulator-xxx -- \
  curl -X POST http://kpimon.ricxapp.svc.cluster.local:8081/e2/indication \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

**解決:**

確保：
- xApp Service 暴露正確的端口
- E2 Simulator 配置使用正確的 service name 和 port
- xApp 實作了 `/e2/indication` endpoint

---

## Prometheus 問題

### 問題: Alert Rules 未載入

**症狀:**
訪問 http://localhost:9090/alerts 看不到任何規則。

**診斷:**

```bash
# 檢查 Prometheus ConfigMap
kubectl get configmap -n ricplt r4-infrastructure-prometheus-server -o yaml | grep -A 5 alerting_rules

# 檢查 Prometheus Pod 日誌
kubectl logs -n ricplt -l app=prometheus,component=server | grep -i "rule\|alert"
```

**解決:**

1. 確認 ConfigMap 包含 alert rules：

```bash
kubectl create configmap r4-infrastructure-prometheus-server \
  --from-file=alerting_rules.yml=monitoring/prometheus/alerts/xapp-alerts.yml \
  --from-file=prometheus.yml=monitoring/prometheus/prometheus.yml \
  --dry-run=client -o yaml | kubectl apply -n ricplt -f -
```

2. 重啟 Prometheus:

```bash
kubectl delete pod -n ricplt -l app=prometheus,component=server
```

### 問題: Prometheus 查詢緩慢

**診斷:**

檢查 Prometheus 資源使用：

```bash
kubectl top pod -n ricplt -l app=prometheus,component=server
```

**解決:**

增加 Prometheus 資源限制：

```yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

---

## Grafana 問題

### 問題: Dashboard 顯示 "No data"

**診斷步驟:**

1. **驗證 Prometheus 有數據**

訪問 Prometheus UI，手動執行查詢：

```promql
kpimon_messages_received_total
```

2. **檢查 Grafana 數據源配置**

Grafana > Configuration > Data Sources > Prometheus

確認 URL 正確：`http://r4-infrastructure-prometheus-server.ricplt.svc.cluster.local`

3. **檢查 Dashboard 查詢語法**

點擊 Panel > Edit，查看查詢是否正確。

**解決:**

- 如果 Prometheus 有數據但 Grafana 沒有：檢查數據源配置
- 如果 Prometheus 沒有數據：參考 [Metrics 數據問題](#metrics-數據問題)

---

## 測試失敗問題

### 問題: Playwright 測試失敗 - "Missing X server"

**症狀:**
```
Missing X server or $DISPLAY
Looks like you launched a headed browser without having a XServer running.
```

**解決:**

更新 `playwright.config.js`，添加新版 headless 模式：

```javascript
projects: [
  {
    name: 'chromium',
    use: {
      ...devices['Desktop Chrome'],
      launchOptions: {
        args: [
          '--headless=new',
          '--no-sandbox',
          '--disable-setuid-sandbox',
          '--disable-dev-shm-usage',
          '--disable-gpu'
        ]
      }
    }
  }
]
```

### 問題: 測試連接 Grafana 超時

**診斷:**

```bash
# 檢查 Grafana 是否運行
kubectl get pods -n ricplt -l app.kubernetes.io/name=grafana

# 測試連接
curl -I http://localhost:3000
```

**解決:**

確保 port-forward 正在運行：

```bash
kubectl port-forward -n ricplt svc/r4-infrastructure-grafana 3000:80
```

---

## 通用除錯技巧

### 1. 檢查所有組件狀態

```bash
# 一鍵檢查腳本
cat > /tmp/check-status.sh <<'EOF'
#!/bin/bash
echo "=== xApp Pods ==="
kubectl get pods -n ricxapp

echo -e "\n=== Prometheus ==="
kubectl get pods -n ricplt -l app=prometheus

echo -e "\n=== Grafana ==="
kubectl get pods -n ricplt -l app.kubernetes.io/name=grafana

echo -e "\n=== Services ==="
kubectl get svc -n ricxapp
EOF

bash /tmp/check-status.sh
```

### 2. 收集完整日誌

```bash
# 收集所有 xApp 日誌
for pod in $(kubectl get pods -n ricxapp -o name); do
  echo "=== $pod ==="
  kubectl logs -n ricxapp $pod --tail=50
done > /tmp/xapp-logs.txt
```

### 3. 驗證網路連通性

```bash
# 從一個 xApp Pod 測試連接其他服務
kubectl exec -n ricxapp kpimon-xxx -- sh -c "
  echo '=== DNS Resolution ==='
  nslookup kpimon.ricxapp.svc.cluster.local

  echo '=== Service Connectivity ==='
  curl -s http://kpimon.ricxapp.svc.cluster.local:8081/ric/v1/health/alive
"
```

---

## 需要更多協助？

如果以上步驟無法解決問題：

1. 查看完整的[部署指南](./xapp-prometheus-metrics-integration.md)
2. 檢查 O-RAN SC 官方文檔
3. 收集日誌並報告 issue

**收集除錯資訊範本:**

```bash
# 執行此腳本收集所有相關資訊
kubectl get pods -n ricxapp -o wide > debug-info.txt
kubectl get pods -n ricplt -o wide >> debug-info.txt
kubectl logs -n ricxapp <problem-pod> >> debug-info.txt
kubectl describe pod -n ricxapp <problem-pod> >> debug-info.txt
```

---

**維護者**: 蔡秀吉 (thc1006)
**最後更新**: 2025-11-15
