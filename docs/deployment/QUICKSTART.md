# O-RAN RIC xApps Prometheus Metrics 快速啟動指南

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-15

## 前置需求

- Kubernetes 集群 (k3s 或其他)
- Helm 3.x
- kubectl 配置正確
- O-RAN RIC Platform 已部署

## 快速部署步驟

### 1. 部署 xApps (約 10 分鐘)

```bash
# 進入專案目錄
cd /home/thc1006/oran-ric-platform

# 執行自動化部署腳本
sudo bash scripts/redeploy-xapps-with-metrics.sh
```

腳本會自動：
- 構建所有 xApp Docker 映像
- 推送到本地 registry
- 部署到 ricxapp namespace
- 驗證 metrics 端點

### 2. 部署 E2 Simulator (約 3 分鐘)

```bash
sudo bash scripts/deployment/deploy-e2-simulator.sh
```

### 3. 配置 Prometheus Alerts (約 2 分鐘)

```bash
# 更新 Prometheus ConfigMap
kubectl create configmap r4-infrastructure-prometheus-server \
  --from-file=alerting_rules.yml=monitoring/prometheus/alerts/xapp-alerts.yml \
  --from-file=prometheus.yml=monitoring/prometheus/prometheus.yml \
  --dry-run=client -o yaml | kubectl apply -n ricplt -f -

# 重啟 Prometheus
kubectl delete pod -n ricplt -l app=prometheus,component=server
```

### 4. 驗證部署

```bash
# 檢查所有 xApp Pods
kubectl get pods -n ricxapp

# 應該顯示:
# kpimon-xxx              1/1     Running
# traffic-steering-xxx    1/1     Running
# qoe-predictor-xxx       1/1     Running
# ran-control-xxx         1/1     Running
# federated-learning-xxx  1/1     Running
# e2-simulator-xxx        1/1     Running
```

### 5. 訪問監控介面

**Prometheus UI:**
```bash
kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80
# 訪問: http://localhost:9090
```

**Grafana:**
```bash
kubectl port-forward -n ricplt svc/r4-infrastructure-grafana 3000:80
# 訪問: http://localhost:3000
# 帳號: admin
# 密碼: oran-ric-admin
```

### 6. 驗證 Metrics 資料流

```bash
# 查看 KPIMON metrics
kubectl exec -n ricxapp $(kubectl get pod -n ricxapp -l app=kpimon -o jsonpath='{.items[0].metadata.name}') -- \
  curl -s http://localhost:8080/ric/v1/metrics | grep kpimon_messages

# 應該看到遞增的計數:
# kpimon_messages_received_total 120.0
# kpimon_messages_processed_total 120.0
```

### 7. 執行自動化測試

```bash
# 安裝測試依賴 (首次)
npm install

# 執行 Grafana dashboard 測試
npm run test:grafana
```

## 預期結果

✅ **所有 xApps 正常運行**
✅ **E2 Simulator 持續發送數據**
✅ **Prometheus 成功抓取 metrics**
✅ **Grafana 顯示動態數據**
✅ **Alert rules 已載入**
✅ **自動化測試通過**

## 快速檢查指令

```bash
# 一鍵檢查所有組件狀態
kubectl get pods -n ricxapp && \
kubectl get pods -n ricplt -l app=prometheus && \
kubectl get pods -n ricplt -l app.kubernetes.io/name=grafana
```

## 如果遇到問題

請參考詳細的故障排除指南：
- [完整部署指南](./xapp-prometheus-metrics-integration.md)
- [故障排除指南](./TROUBLESHOOTING.md)

## 常用查詢

### Prometheus 查詢範例

```promql
# KPIMON 訊息接收速率
rate(kpimon_messages_received_total[5m])

# 所有 xApp 的 CPU 使用率
rate(container_cpu_usage_seconds_total{namespace="ricxapp"}[5m])

# xApp 記憶體使用量
container_memory_working_set_bytes{namespace="ricxapp"}
```

## 下一步

1. 自訂 Grafana Dashboards
2. 調整 Alert Rules 閾值
3. 整合外部告警系統 (如 Slack、Email)
4. 擴展 E2 Simulator 測試場景

---

**需要協助？**
請查看完整的部署文檔或聯繫維護者。
