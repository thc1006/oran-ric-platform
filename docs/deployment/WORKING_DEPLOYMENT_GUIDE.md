# O-RAN RIC Platform 正確部署指南 (從零開始)

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-16
**測試環境**: 從全新 k3s 集群開始的完整測試
**版本**: v2.0.0

## 概述

本指南記錄了經過實際測試驗證的完整部署流程，包含所有必要步驟和常見問題的解決方案。

## 前置條件

- Kubernetes 1.28+ (已安裝 k3s)
- Helm 3.x
- Docker
- 8+ CPU cores, 16GB+ RAM, 100GB+ disk
- kubectl 配置正確

## 環境配置

### 設置 KUBECONFIG

**重要**: k3s 的 kubeconfig 在非默認位置，必須正確設置：

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 永久設置
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc
source ~/.bashrc
```

**問題來源**: k3s 將 kubeconfig 放在 `/etc/rancher/k3s/k3s.yaml`，但 kubectl 默認查找 `~/.kube/config`。

## 部署步驟

### 步驟 1: 創建命名空間

```bash
kubectl create namespace ricplt
kubectl create namespace ricxapp
kubectl create namespace ricobs
```

**驗證**:
```bash
kubectl get namespaces | grep ric
```

### 步驟 2: 部署 Prometheus

```bash
# 添加 Grafana Helm repository (Prometheus chart 已經在項目中)
helm repo update

# 部署 Prometheus
helm install r4-infrastructure-prometheus \
  ./ric-dep/helm/infrastructure/subcharts/prometheus \
  --namespace ricplt \
  --values ./config/prometheus-values.yaml
```

**驗證**:
```bash
kubectl get pods -n ricplt -l app=prometheus
```

應該看到：
- r4-infrastructure-prometheus-server-xxx (1/1 Running)
- r4-infrastructure-prometheus-alertmanager-xxx (2/2 Running)

### 步驟 3: 部署 Grafana

```bash
# 添加 Grafana Helm repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 部署 Grafana
helm install oran-grafana grafana/grafana \
  -n ricplt \
  -f ./config/grafana-values.yaml \
  --wait \
  --timeout 5m
```

**獲取 Grafana 密碼**:
```bash
kubectl get secret --namespace ricplt oran-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode && echo
```

**驗證**:
```bash
kubectl get pods -n ricplt -l app.kubernetes.io/name=grafana
```

### 步驟 4: 部署 xApps

**重要**: 必須先部署 ConfigMap 和 Service，再部署 Deployment！

```bash
# 部署 KPIMON
kubectl apply -f ./xapps/kpimon-go-xapp/deploy/ -n ricxapp

# 部署 Traffic Steering
kubectl apply -f ./xapps/traffic-steering/deploy/configmap.yaml -n ricxapp
kubectl apply -f ./xapps/traffic-steering/deploy/service.yaml -n ricxapp
kubectl apply -f ./xapps/traffic-steering/deploy/deployment.yaml -n ricxapp

# 部署 RAN Control
kubectl apply -f ./xapps/rc-xapp/deploy/configmap.yaml -n ricxapp
kubectl apply -f ./xapps/rc-xapp/deploy/service.yaml -n ricxapp
kubectl apply -f ./xapps/rc-xapp/deploy/deployment.yaml -n ricxapp

# 部署 QoE Predictor
kubectl apply -f ./xapps/qoe-predictor/deploy/configmap.yaml -n ricxapp
kubectl apply -f ./xapps/qoe-predictor/deploy/service.yaml -n ricxapp
kubectl apply -f ./xapps/qoe-predictor/deploy/deployment.yaml -n ricxapp

# 部署 Federated Learning
kubectl apply -f ./xapps/federated-learning/deploy/configmap.yaml -n ricxapp
kubectl apply -f ./xapps/federated-learning/deploy/service.yaml -n ricxapp
kubectl apply -f ./xapps/federated-learning/deploy/deployment.yaml -n ricxapp
```

**驗證**:
```bash
kubectl get pods -n ricxapp
```

應該看到所有 xApps 都在 Running 狀態 (1/1)。

**如果 Pods 卡在 ContainerCreating**:
```bash
# 檢查錯誤
kubectl describe pod -n ricxapp <pod-name>

# 如果是 ConfigMap 錯誤，重啟 deployment
kubectl rollout restart deployment/<deployment-name> -n ricxapp
```

### 步驟 5: 部署 E2 Simulator

```bash
bash ./scripts/deployment/deploy-e2-simulator.sh
```

**驗證**:
```bash
# 檢查 E2 Simulator Pod
kubectl get pods -n ricxapp -l app=e2-simulator

# 查看日誌確認正在發送數據
kubectl logs -n ricxapp -l app=e2-simulator | tail -20
```

應該看到類似輸出：
```
=== Simulation Iteration 3 ===
Generated KPI indication for cell_002/ue_010
Generated QoE metrics for ue_002: QoE=59.5
```

### 步驟 6: 訪問 Grafana

```bash
# 設置 port-forward
kubectl port-forward -n ricplt svc/oran-grafana 3000:80
```

訪問 http://localhost:3000
- 用戶名: `admin`
- 密碼: (使用步驟 3 獲取的密碼，默認為 `oran-ric-admin`)

## 驗證部署

### 檢查所有組件狀態

```bash
# 一鍵檢查所有組件
cat > /tmp/check-deployment.sh <<'EOF'
#!/bin/bash
echo "=== RIC Platform Pods ==="
kubectl get pods -n ricplt

echo -e "\n=== xApp Pods ==="
kubectl get pods -n ricxapp

echo -e "\n=== Services ==="
kubectl get svc -n ricxapp
kubectl get svc -n ricplt
EOF

chmod +x /tmp/check-deployment.sh
bash /tmp/check-deployment.sh
```

### 驗證 Prometheus Metrics

```bash
# 檢查 KPIMON metrics
kubectl exec -n ricxapp $(kubectl get pod -n ricxapp -l app=kpimon -o jsonpath='{.items[0].metadata.name}') -- \
  curl -s http://localhost:8080/ric/v1/metrics | grep kpimon_messages

# 應該看到遞增的計數
```

### 訪問 Prometheus UI

```bash
kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80
```

訪問 http://localhost:9090

測試查詢：
```promql
kpimon_messages_received_total
rate(kpimon_messages_received_total[5m])
```

## 常見問題

### 問題 1: kubectl 無法連接

**錯誤**:
```
The connection to the server localhost:8080 was refused
```

**解決**:
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### 問題 2: Pod 卡在 ContainerCreating - ConfigMap not found

**錯誤**:
```
MountVolume.SetUp failed for volume "config-volume" : configmap "xxx-config" not found
```

**解決**:
必須先創建 ConfigMap，再創建 Deployment：
```bash
kubectl apply -f xapps/<xapp-name>/deploy/configmap.yaml -n ricxapp
kubectl apply -f xapps/<xapp-name>/deploy/deployment.yaml -n ricxapp

# 或者重啟 deployment
kubectl rollout restart deployment/<deployment-name> -n ricxapp
```

### 問題 3: xApp 目錄名稱混亂

**問題**: 腳本使用 `ran-control` 但實際目錄是 `rc-xapp`

**解決**: 使用正確的目錄名：
- `xapps/rc-xapp/` (正確)
- `xapps/kpimon-go-xapp/` (正確)
- `xapps/traffic-steering/` (正確)
- `xapps/qoe-predictor/` (正確)
- `xapps/federated-learning/` (正確)

### 問題 4: redeploy-xapps-with-metrics.sh 腳本不完整

**問題**: 腳本只部署 Deployment，缺少 ConfigMap 和 Service

**解決**: 手動依次部署 ConfigMap → Service → Deployment

## 部署清單

完成部署後，應該有以下組件運行：

### ricplt namespace:
- ✅ oran-grafana (1/1)
- ✅ r4-infrastructure-prometheus-server (1/1)
- ✅ r4-infrastructure-prometheus-alertmanager (2/2)

### ricxapp namespace:
- ✅ kpimon (1/1)
- ✅ traffic-steering (1/1)
- ✅ ran-control (1/1)
- ✅ qoe-predictor (0/1 或 1/1) *
- ✅ federated-learning (0/1 或 1/1) *
- ✅ e2-simulator (1/1)

\* QoE Predictor 和 Federated Learning 可能需要額外配置

## 下一步

1. 導入 Grafana Dashboards
2. 配置 Prometheus Alert Rules
3. 運行自動化測試
4. 根據需求調整 xApp 配置

## 文檔問題摘要

經測試發現以下文檔問題需要修復：

1. **README.md**: 缺少 RIC Platform 部署步驟，直接跳到 xApps
2. **QUICKSTART.md**: 未提及 KUBECONFIG 配置
3. **deploy-ric-platform.sh**: 引用不存在的路徑
4. **redeploy-xapps-with-metrics.sh**: 缺少 ConfigMap/Service 部署
5. 目錄名稱不一致 (ran-control vs rc-xapp)

## 參考資料

- [完整部署日誌](/home/thc1006/oran-ric-platform/DEPLOYMENT_ISSUES_LOG.md)
- [原始 README](/home/thc1006/oran-ric-platform/README.md)
- [故障排除指南](/home/thc1006/oran-ric-platform/docs/deployment/TROUBLESHOOTING.md)

---

**維護者**: 蔡秀吉 (thc1006)
**最後更新**: 2025-11-16
**測試狀態**: ✅ 已驗證可用
