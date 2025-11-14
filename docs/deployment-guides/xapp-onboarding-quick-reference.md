# xApp Onboarding Quick Reference

**作者：蔡秀吉（thc1006）**
**日期：2025-11-14**

## 快速部署順序

```
階段 1: 基礎設施 (0-15分鐘)
├── InfluxDB 部署
├── Secrets 創建
└── RBAC 設置

階段 2: 獨立 xApps (15-30分鐘) [並行]
├── KPIMON
├── QoE Predictor
└── RC xApp

階段 3: 整合 xApps (30-40分鐘) [順序]
├── Traffic Steering (依賴 QoE + RC)
└── Federated Learning (可選)

階段 4: 驗證測試 (40-60分鐘)
```

## xApp 特性對照表

| xApp | RMR Port | HTTP Port | CPU Request | Memory Request | 特殊依賴 |
|------|----------|-----------|-------------|----------------|----------|
| KPIMON | 4560 | 8080 | 200m | 512Mi | InfluxDB, E2Term |
| QoE Predictor | 4570 | 8090 | 500m | 1Gi | A1 Mediator, Models |
| RC xApp | 4580 | 8100 | 300m | 512Mi | E2Term, A1 Mediator |
| Traffic Steering | 4560 | 8080 | 200m | 256Mi | QoE + RC APIs |
| Federated Learning | 4590 | 8110 | 1000m | 2Gi | RSA Keys, Storage |

## RMR 訊息類型

| 訊息類型 | Message ID | 用途 | 發送者 | 接收者 |
|---------|------------|------|--------|--------|
| RIC_SUB_REQ | 12010 | 訂閱請求 | xApp | E2Term |
| RIC_SUB_RESP | 12011 | 訂閱回應 | E2Term | xApp |
| RIC_SUB_DEL_REQ | 12012 | 刪除訂閱 | xApp | E2Term |
| RIC_SUB_DEL_RESP | 12013 | 刪除回應 | E2Term | xApp |
| RIC_INDICATION | 12050 | E2 指示 | E2Term | xApp |
| RIC_CONTROL_REQ | 12040 | 控制請求 | xApp | E2Term |
| RIC_CONTROL_ACK | 12041 | 控制確認 | E2Term | xApp |
| RIC_CONTROL_FAILURE | 12042 | 控制失敗 | E2Term | xApp |
| A1_POLICY_REQ | 20010 | A1 策略請求 | A1 Mediator | xApp |
| A1_POLICY_RESP | 20011 | A1 策略回應 | xApp | A1 Mediator |

## E2 服務模型

| xApp | Service Model | Version | RAN Function ID | 主要功能 |
|------|---------------|---------|-----------------|----------|
| KPIMON | E2SM-KPM | 3.0.0 | 2 | KPI 收集與監控 |
| RC xApp | E2SM-RC | 2.0.0 | 3 | RAN 控制與優化 |
| QoE Predictor | - | - | - | QoE 預測（不直接使用 E2） |
| Traffic Steering | - | - | - | 切換決策（間接使用） |

## Redis Database 分配

| xApp | Redis DB | TTL | 用途 |
|------|----------|-----|------|
| KPIMON | 0 | 300s | KPI 暫存 |
| QoE Predictor | 1 | 60s | 特徵與預測結果 |
| RC xApp | 2 | 3600s | 控制狀態 |
| Traffic Steering | 0 | N/A | UE 狀態 |
| Federated Learning | 3 | 86400s | 模型與梯度 |

## 一鍵部署腳本

### 完整部署

```bash
#!/bin/bash
# 完整 xApp 部署腳本
# 使用方法: ./deploy-all-xapps.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XAPPS_DIR="/home/thc1006/oran-ric-platform/xapps"

# 顏色定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 階段 1: 基礎設施
log_info "階段 1: 部署基礎設施"
kubectl apply -f ${XAPPS_DIR}/../platform/infrastructure/influxdb.yaml
kubectl create secret generic influxdb-secrets --from-literal=admin-password='ric-influx-2025' -n ricplt || true
kubectl wait --for=condition=ready pod -l app=influxdb -n ricplt --timeout=120s

# 階段 2: 獨立 xApps（並行）
log_info "階段 2: 部署獨立 xApps"

# 構建所有映像
log_info "構建 Docker 映像..."
cd ${XAPPS_DIR}
for xapp in kpimon-go-xapp qoe-predictor rc-xapp; do
    docker build -t localhost:5000/xapp-${xapp}:1.0.0 ${xapp}/
    docker push localhost:5000/xapp-${xapp}:1.0.0
done

# 並行部署
log_info "並行部署 KPIMON, QoE Predictor, RC xApp..."
kubectl apply -f ${XAPPS_DIR}/kpimon-go-xapp/deploy.yaml &
kubectl apply -f ${XAPPS_DIR}/qoe-predictor/deploy.yaml &
kubectl apply -f ${XAPPS_DIR}/rc-xapp/deploy.yaml &
wait

# 等待就緒
kubectl wait --for=condition=ready pod -l app=kpimon -n ricxapp --timeout=120s
kubectl wait --for=condition=ready pod -l app=qoe-predictor -n ricxapp --timeout=180s
kubectl wait --for=condition=ready pod -l app=ran-control -n ricxapp --timeout=120s

# 階段 3: 整合 xApps
log_info "階段 3: 部署整合 xApps"
docker build -t localhost:5000/xapp-traffic-steering:1.2.0 traffic-steering/
docker push localhost:5000/xapp-traffic-steering:1.2.0
kubectl apply -f ${XAPPS_DIR}/traffic-steering/deploy.yaml
kubectl wait --for=condition=ready pod -l app=traffic-steering -n ricxapp --timeout=180s

# 階段 4: Federated Learning (可選)
read -p "是否部署 Federated Learning xApp? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "部署 Federated Learning xApp..."
    docker build -t localhost:5000/xapp-federated-learning:1.0.0 federated-learning/
    docker push localhost:5000/xapp-federated-learning:1.0.0
    kubectl apply -f ${XAPPS_DIR}/federated-learning/deploy.yaml
    kubectl wait --for=condition=ready pod -l app=federated-learning -n ricxapp --timeout=300s
fi

log_info "所有 xApp 部署完成！"
kubectl get pods -n ricxapp
```

### 單一 xApp 部署

```bash
#!/bin/bash
# 單一 xApp 部署腳本
# 使用方法: ./deploy-single-xapp.sh <xapp-name>

XAPP_NAME=$1
XAPPS_DIR="/home/thc1006/oran-ric-platform/xapps"

if [ -z "$XAPP_NAME" ]; then
    echo "使用方法: $0 <xapp-name>"
    echo "可用的 xApp: kpimon, qoe-predictor, rc-xapp, traffic-steering, federated-learning"
    exit 1
fi

case $XAPP_NAME in
    kpimon)
        XAPP_DIR="kpimon-go-xapp"
        VERSION="1.0.0"
        ;;
    qoe-predictor)
        XAPP_DIR="qoe-predictor"
        VERSION="1.0.0"
        ;;
    rc-xapp|ran-control)
        XAPP_DIR="rc-xapp"
        XAPP_NAME="ran-control"
        VERSION="1.0.0"
        ;;
    traffic-steering)
        XAPP_DIR="traffic-steering"
        VERSION="1.2.0"
        ;;
    federated-learning)
        XAPP_DIR="federated-learning"
        VERSION="1.0.0"
        ;;
    *)
        echo "未知的 xApp: $XAPP_NAME"
        exit 1
        ;;
esac

echo "部署 $XAPP_NAME..."

# 構建並推送映像
cd ${XAPPS_DIR}
docker build -t localhost:5000/xapp-${XAPP_NAME}:${VERSION} ${XAPP_DIR}/
docker push localhost:5000/xapp-${XAPP_NAME}:${VERSION}

# 部署
kubectl apply -f ${XAPP_DIR}/deploy.yaml

# 等待就緒
kubectl wait --for=condition=ready pod -l app=${XAPP_NAME} -n ricxapp --timeout=180s

echo "$XAPP_NAME 部署完成！"
kubectl get pods -n ricxapp -l app=${XAPP_NAME}
```

## 驗證檢查清單

### KPIMON

```bash
# ✓ Pod 運行
kubectl get pod -l app=kpimon -n ricxapp

# ✓ 健康檢查
curl http://localhost:8080/health/alive

# ✓ E2 訂閱
curl http://localhost:8080/api/v1/subscriptions

# ✓ InfluxDB 連線
curl http://localhost:8080/api/v1/influxdb/status

# ✓ KPI 資料寫入
influx query 'from(bucket:"kpimon") |> range(start: -5m) |> limit(n:5)'
```

### QoE Predictor

```bash
# ✓ Pod 運行
kubectl get pod -l app=qoe-predictor -n ricxapp

# ✓ 健康檢查
curl http://localhost:8090/health/ready

# ✓ 模型狀態
curl http://localhost:8090/api/v1/models/status

# ✓ 預測測試
curl -X POST http://localhost:8090/api/v1/predict \
  -H "Content-Type: application/json" \
  -d '{"service":"video_quality","features":{"throughput_dl":50}}'

# ✓ A1 Policy
curl http://localhost:8090/api/v1/policies
```

### RC xApp

```bash
# ✓ Pod 運行
kubectl get pod -l app=ran-control -n ricxapp

# ✓ 健康檢查
curl http://localhost:8100/health/ready

# ✓ E2 連線
curl http://localhost:8100/api/v1/e2/connections

# ✓ 控制能力
curl http://localhost:8100/api/v1/e2/control-styles

# ✓ 統計資訊
curl http://localhost:8100/api/v1/stats/control
```

### Traffic Steering

```bash
# ✓ Pod 運行
kubectl get pod -l app=traffic-steering -n ricxapp

# ✓ 健康檢查
curl http://localhost:8080/ric/v1/health/alive

# ✓ 依賴連線
curl http://localhost:8080/api/v1/dependencies/status

# ✓ UE 監控
curl http://localhost:8080/api/v1/ues

# ✓ 切換統計
curl http://localhost:8080/api/v1/stats
```

### Federated Learning

```bash
# ✓ Pod 運行
kubectl get pod -l app=federated-learning -n ricxapp

# ✓ 健康檢查
curl http://localhost:8110/health/ready

# ✓ 聚合器狀態
curl http://localhost:8110/api/v1/aggregator/status

# ✓ 客戶端註冊
curl http://localhost:8110/api/v1/clients

# ✓ 訓練狀態
curl http://localhost:8110/api/v1/training/status
```

## 常見問題速查

### Pod 無法啟動

```bash
# 檢查事件
kubectl describe pod <pod-name> -n ricxapp

# 常見原因與解決方案：
# - ImagePullBackOff → 檢查映像是否推送到 registry
# - CrashLoopBackOff → 查看日誌 kubectl logs <pod> --previous
# - Pending → 檢查資源是否充足 kubectl describe node
```

### RMR 連線問題

```bash
# 檢查路由表
kubectl exec -it deployment/<xapp> -n ricxapp -- cat /app/config/rmr-routes.txt

# 測試 E2Term 連線
kubectl exec -it deployment/<xapp> -n ricxapp -- \
  nc -zv e2term-rmr.ricplt 4560

# 檢查網路策略
kubectl get networkpolicy -n ricxapp
```

### 服務間通訊問題

```bash
# DNS 解析測試
kubectl exec -it deployment/<xapp> -n ricxapp -- \
  nslookup <service-name>.ricxapp

# HTTP 連線測試
kubectl run curl-test --rm -it --image=curlimages/curl -- \
  curl -v http://<service-name>.ricxapp:8080/health/alive

# 檢查 Service
kubectl get svc -n ricxapp
kubectl describe svc <service-name> -n ricxapp
```

### 資源不足

```bash
# 檢查資源使用
kubectl top pods -n ricxapp
kubectl top nodes

# 檢查 OOM 事件
kubectl get events -n ricxapp | grep OOM

# 增加資源限制
kubectl patch deployment <xapp> -n ricxapp -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "<xapp>",
          "resources": {
            "limits": {"memory": "4Gi", "cpu": "2000m"}
          }
        }]
      }
    }
  }
}'
```

## 效能基準

| xApp | 訊息處理速率 | 平均延遲 | 記憶體使用 | CPU 使用 |
|------|-------------|----------|-----------|----------|
| KPIMON | >5000 msg/s | <10ms | ~800Mi | ~400m |
| QoE Predictor | >1000 pred/s | <50ms | ~1.5Gi | ~800m |
| RC xApp | >2000 ctrl/s | <100ms | ~600Mi | ~500m |
| Traffic Steering | >500 eval/s | <20ms | ~300Mi | ~250m |
| Federated Learning | 1 round/min | N/A | ~3Gi | ~2000m |

## 監控指標

### Prometheus 查詢

```promql
# KPIMON - KPI 收集速率
rate(kpimon_messages_received_total[5m])

# QoE Predictor - 預測成功率
rate(qoe_predictions_success_total[5m]) / rate(qoe_predictions_total[5m])

# RC xApp - 控制成功率
rate(rc_control_success_total[5m]) / rate(rc_control_total[5m])

# Traffic Steering - 切換決策率
rate(ts_handover_triggered_total[5m])

# 資源使用
container_memory_working_set_bytes{namespace="ricxapp"}
rate(container_cpu_usage_seconds_total{namespace="ricxapp"}[5m])
```

## 除錯技巧

### 進入容器除錯

```bash
# 進入運行中的容器
kubectl exec -it deployment/<xapp> -n ricxapp -- /bin/bash

# 檢查進程
ps aux | grep python

# 檢查端口監聽
netstat -tuln

# 檢查環境變數
env | grep -E "RMR|INFLUX|REDIS"

# 測試本地連線
curl http://localhost:8080/health/alive
```

### 日誌分析

```bash
# 即時日誌
kubectl logs -f deployment/<xapp> -n ricxapp

# 錯誤日誌
kubectl logs deployment/<xapp> -n ricxapp | grep -i error

# 特定時間範圍
kubectl logs deployment/<xapp> -n ricxapp --since=10m

# 多個副本聚合
kubectl logs -l app=<xapp> -n ricxapp --all-containers=true
```

### 網路除錯

```bash
# 啟動除錯 Pod
kubectl run netdebug --rm -it --image=nicolaka/netshoot -n ricxapp -- /bin/bash

# 在除錯 Pod 中執行：
# - DNS 測試
nslookup redis-service.ricplt

# - 端口掃描
nmap -p 4560,6379,8086 e2term-rmr.ricplt

# - HTTP 測試
curl -v http://qoe-predictor-service.ricxapp:8090/health/alive

# - TCP 連線測試
nc -zv redis-service.ricplt 6379
```

## 備份與恢復

### 備份配置

```bash
# 備份所有 xApp 配置
kubectl get configmap -n ricxapp -o yaml > xapp-configmaps-backup.yaml
kubectl get secret -n ricxapp -o yaml > xapp-secrets-backup.yaml
kubectl get deployment -n ricxapp -o yaml > xapp-deployments-backup.yaml
kubectl get service -n ricxapp -o yaml > xapp-services-backup.yaml

# 備份 PVC 資料
kubectl get pvc -n ricxapp
# 針對每個 PVC 進行備份
```

### 恢復配置

```bash
# 恢復配置
kubectl apply -f xapp-configmaps-backup.yaml
kubectl apply -f xapp-secrets-backup.yaml
kubectl apply -f xapp-deployments-backup.yaml
kubectl apply -f xapp-services-backup.yaml
```

## 升級策略

### 滾動升級

```bash
# 更新映像版本
kubectl set image deployment/<xapp> \
  <xapp>=localhost:5000/xapp-<xapp>:<new-version> \
  -n ricxapp

# 檢查升級狀態
kubectl rollout status deployment/<xapp> -n ricxapp

# 查看歷史
kubectl rollout history deployment/<xapp> -n ricxapp

# 回滾
kubectl rollout undo deployment/<xapp> -n ricxapp
```

### 藍綠部署

```bash
# 部署新版本（不同名稱）
kubectl apply -f <xapp>-v2-deployment.yaml

# 測試新版本
kubectl port-forward deployment/<xapp>-v2 -n ricxapp 8080:8080

# 切換服務
kubectl patch service <xapp>-service -n ricxapp -p '
{
  "spec": {
    "selector": {
      "app": "<xapp>",
      "version": "2.0.0"
    }
  }
}'

# 清理舊版本
kubectl delete deployment <xapp>-v1 -n ricxapp
```

---

**文件版本**：1.0.0
**最後更新**：2025-11-14
**維護者**：蔡秀吉（thc1006）
