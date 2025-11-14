# O-RAN RIC Platform 快速開始指南
**作者**：蔡秀吉（thc1006）
**適用對象**：希望快速部署已驗證 xApp 的用戶

---

## 🚀 10 分鐘快速部署

本指南幫助您快速部署已經驗證成功的 KPIMON、RAN Control 和 Traffic Steering xApp。

---

## 前提條件

確保以下組件已安裝並運行：

### 必要組件

- ✅ **Kubernetes (k3s)**: v1.28+
- ✅ **Helm**: 3.x
- ✅ **Docker**: 最新版本
- ✅ **Python**: 3.11+

### 系統資源

- CPU: 8 核心以上
- 記憶體: 16GB 以上
- 磁碟: 100GB 以上

### 檢查環境

```bash
# 檢查 kubectl
kubectl version --client

# 檢查 helm
helm version

# 檢查 docker
docker --version

# 檢查 k3s 集群
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

---

## Step 1: Clone 專案

```bash
git clone https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform

# 設置環境變數
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

---

## Step 2: 部署 RIC Platform

### 2.1 創建命名空間

```bash
kubectl create namespace ricplt
kubectl create namespace ricxapp
```

### 2.2 部署基礎組件

#### 部署 Redis (dbaas)

```bash
cd ric-dep/helm/infrastructure/dbaas
helm install dbaas . -n ricplt
kubectl wait --for=condition=ready pod -l app=ricplt-dbaas -n ricplt --timeout=300s
```

#### 部署 E2 Termination

```bash
cd ../e2term
helm install e2term . -n ricplt
sleep 10
```

#### 部署 A1 Mediator

```bash
cd ../../platform/a1mediator
helm install a1mediator . -n ricplt
sleep 10
```

#### 部署 RTMgr (Routing Manager)

**重要**：確保使用正確的版本（0.9.6）

```bash
cd ../../infrastructure/rtmgr
# 編輯 values.yaml，確認 image.tag: 0.9.6
helm install rtmgr . -n ricplt
kubectl wait --for=condition=ready pod -l app=ricplt-rtmgr -n ricplt --timeout=300s
```

#### 部署 InfluxDB

```bash
cd ../3rdparty/influxdb
helm install r4-influxdb influxdata/influxdb2 \
  -n ricplt \
  --set adminUser.organization="oran" \
  --set adminUser.bucket="kpimon" \
  --set adminUser.user="admin" \
  --set adminUser.password="admin123" \
  --set persistence.enabled=true \
  --set persistence.size=10Gi

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=influxdb2 -n ricplt --timeout=300s
```

### 2.3 驗證 RIC Platform

```bash
kubectl get pods -n ricplt
```

**預期輸出**：
```
NAME                                             READY   STATUS    RESTARTS   AGE
statefulset-ricplt-dbaas-server-0                1/1     Running   0          5m
deployment-ricplt-e2term-alpha-xxx               1/1     Running   0          4m
deployment-ricplt-a1mediator-xxx                 1/1     Running   0          3m
deployment-ricplt-rtmgr-xxx                      1/1     Running   0          2m
r4-influxdb-influxdb2-0                          1/1     Running   0          1m
```

---

## Step 3: 設置 Docker Registry

如果沒有運行本地 registry：

```bash
docker run -d -p 5000:5000 --name registry --restart=always registry:2
```

驗證：
```bash
curl http://localhost:5000/v2/_catalog
```

---

## Step 4: 部署 KPIMON xApp

### 4.1 構建鏡像

```bash
cd /home/thc1006/oran-ric-platform/xapps/kpimon-go-xapp

docker build -t localhost:5000/xapp-kpimon:1.0.0 .
docker push localhost:5000/xapp-kpimon:1.0.0
```

### 4.2 部署到 Kubernetes

```bash
kubectl apply -f deploy/
```

### 4.3 驗證部署

```bash
# 檢查 Pod 狀態
kubectl get pods -n ricxapp -l app=kpimon

# 等待 Pod 就緒
kubectl wait --for=condition=ready pod -l app=kpimon -n ricxapp --timeout=300s

# 查看日誌
kubectl logs -n ricxapp -l app=kpimon --tail=20
```

**預期日誌輸出**：
```json
{"msg": "KPIMON xApp initialized"}
{"msg": "Redis connection established"}
{"msg": "InfluxDB connection established"}
{"msg": "KPIMON xApp started successfully"}
{"msg": "Sent subscription request: kpimon_1763101601"}
```

### 4.4 測試功能

```bash
# 獲取 Pod 名稱
KPIMON_POD=$(kubectl get pod -n ricxapp -l app=kpimon -o jsonpath='{.items[0].metadata.name}')

# 測試 Prometheus 指標
kubectl exec -n ricxapp $KPIMON_POD -- curl -s http://localhost:8080/metrics | grep kpimon_
```

**預期輸出**：
```
kpimon_messages_received_total 0.0
kpimon_messages_processed_total 0.0
kpimon_kpi_value
kpimon_processing_time_seconds
```

---

## Step 5: 部署 RAN Control xApp

### 5.1 構建鏡像

```bash
cd /home/thc1006/oran-ric-platform/xapps/rc-xapp

docker build -t localhost:5000/xapp-ran-control:1.0.0 .
docker push localhost:5000/xapp-ran-control:1.0.0
```

### 5.2 部署到 Kubernetes

```bash
kubectl apply -f deploy/
```

### 5.3 驗證部署

```bash
# 檢查 Pod 狀態
kubectl get pods -n ricxapp -l app=ran-control

# 等待 Pod 就緒
kubectl wait --for=condition=ready pod -l app=ran-control -n ricxapp --timeout=300s

# 查看日誌
kubectl logs -n ricxapp -l app=ran-control --tail=20
```

**預期日誌輸出**：
```json
{"msg": "Redis connection established"}
{"msg": "RAN Control xApp initialized"}
{"msg": "RAN Control xApp started successfully"}
```
```
* Running on http://0.0.0.0:8100
```

### 5.4 測試功能

```bash
# 獲取 Pod 名稱
RC_POD=$(kubectl get pod -n ricxapp -l app=ran-control -o jsonpath='{.items[0].metadata.name}')

# 測試健康檢查
kubectl exec -n ricxapp $RC_POD -- curl http://localhost:8100/health/alive
# 預期：{"status":"alive"}

kubectl exec -n ricxapp $RC_POD -- curl http://localhost:8100/health/ready
# 預期：{"status":"ready"}

# 測試指標端點
kubectl exec -n ricxapp $RC_POD -- curl http://localhost:8100/metrics
```

**預期輸出**：
```json
{
  "control_actions_sent": 0,
  "control_actions_success": 0,
  "control_actions_failed": 0,
  "handovers_triggered": 0,
  "resource_optimizations": 0,
  "slice_reconfigurations": 0
}
```

---

## Step 6: 部署 Traffic Steering xApp

### 6.1 構建鏡像

```bash
cd /home/thc1006/oran-ric-platform/xapps/traffic-steering

# 首次構建建議使用 --no-cache
docker build --no-cache -t localhost:5000/xapp-traffic-steering:1.0.0 .
docker push localhost:5000/xapp-traffic-steering:1.0.0
```

### 6.2 部署到 Kubernetes

```bash
kubectl apply -f deploy/
```

### 6.3 驗證部署

```bash
# 檢查 Pod 狀態
kubectl get pods -n ricxapp -l app=traffic-steering

# 等待 Pod 就緒
kubectl wait --for=condition=ready pod -l app=traffic-steering -n ricxapp --timeout=300s

# 查看日誌
kubectl logs -n ricxapp -l app=traffic-steering --tail=30
```

**預期日誌輸出**：
```json
{"msg": "Traffic Steering xApp initialized"}
{"msg": "Starting Traffic Steering xApp"}
```
```
* Running on http://0.0.0.0:8080
* Running on http://10.42.0.142:8080
```
```json
{"msg": "E2 subscription request sent"}
```

### 6.4 測試功能

```bash
# 獲取 Pod 名稱
TS_POD=$(kubectl get pod -n ricxapp -l app=traffic-steering -o jsonpath='{.items[0].metadata.name}')

# 測試健康檢查
kubectl exec -n ricxapp $TS_POD -- curl http://localhost:8080/ric/v1/health/alive
# 預期：{"status":"alive"}

kubectl exec -n ricxapp $TS_POD -- curl http://localhost:8080/ric/v1/health/ready
# 預期：{"status":"ready"}
```

**重要提示**：Traffic Steering xApp 使用了組合模式（composition）而非繼承，這是 ricxappframe 3.2.2 的正確使用方式。詳見 [traffic-steering-deployment.md](traffic-steering-deployment.md)。

---

## Step 7: 驗證完整部署

```bash
# 檢查所有 Pod
kubectl get pods -n ricplt
kubectl get pods -n ricxapp

# 檢查所有服務
kubectl get svc -n ricplt
kubectl get svc -n ricxapp
```

**預期輸出（ricxapp）**：
```
NAME                           READY   STATUS    RESTARTS   AGE
kpimon-xxx                     1/1     Running   0          5m
ran-control-xxx                1/1     Running   0          3m
```

---

## 🎯 部署完成！

恭喜！您已經成功部署了：

### ✅ RIC Platform 組件
- Redis (dbaas)
- E2 Termination
- A1 Mediator
- RTMgr (Routing Manager)
- InfluxDB

### ✅ xApps
- **KPIMON xApp** - KPI 監控與異常檢測
- **RAN Control xApp** - RAN 控制與優化

---

## 📚 下一步

### 查看詳細文檔

- **完整部署指南**: [deployment-guide-complete.md](deployment-guide-complete.md)
- **KPIMON 詳細說明**: [xapps/kpimon-go-xapp/README.md](../xapps/kpimon-go-xapp/README.md)
- **RC xApp 詳細說明**: [xapps/rc-xapp/README.md](../xapps/rc-xapp/README.md)

### 問題排查

如遇到問題：

1. **查看 Pod 日誌**
   ```bash
   kubectl logs -n ricxapp <pod-name>
   ```

2. **檢查 Pod 詳細信息**
   ```bash
   kubectl describe pod -n ricxapp <pod-name>
   ```

3. **查看事件**
   ```bash
   kubectl get events -n ricxapp --sort-by='.lastTimestamp'
   ```

4. **參考問題排查指南**
   - [deployment-guide-complete.md#7-常見問題與解決方案](deployment-guide-complete.md#7-常見問題與解決方案)

---

## 🔧 常見問題

### Q1: KPIMON 顯示 "Failed to send message type 12010"

**A**: 這是正常情況，因為沒有實際的 E2 節點連接。重要的是程式碼正常執行到了發送階段。

### Q2: InfluxDB 連接失敗

**A**: 檢查 InfluxDB Pod 是否運行：
```bash
kubectl get pods -n ricplt | grep influxdb
```

### Q3: RTMgr ImagePullBackOff

**A**: 確保 `ric-dep/helm/infrastructure/rtmgr/values.yaml` 中的版本是 **0.9.6**（不是 0.3.8）

### Q4: RC xApp Flask API 未啟動

**A**: 檢查 config.json 是否包含 `http_port: 8100`

---

## 📧 需要幫助？

- **GitHub Issues**: https://github.com/thc1006/oran-ric-platform/issues
- **作者**: 蔡秀吉（thc1006）

---

**文檔結束**
