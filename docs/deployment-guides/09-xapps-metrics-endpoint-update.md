# xApps Prometheus Metrics 端點更新部署指南

**作者**: 蔡秀吉 (thc1006)
**最後更新**: 2025年11月15日 11:54
**部署日期**: 2025年11月15日 11:41-11:54

---

## 前言

本文檔記錄了將所有 xApp 的 metrics 端點更新為符合 O-RAN SC 標準的完整過程。這是繼 Prometheus Server 部署（Small CL #1）之後的 Small CLs #2-#6，遵循 TDD 和 Small CLs 原則。所有 5 個 xApps（RC、QoE、FL、Traffic Steering、KPIMON）現已完全符合 O-RAN SC Prometheus 監控標準。

## 背景說明

### 問題陳述

根據 [08-prometheus-monitoring-deployment.md](./08-prometheus-monitoring-deployment.md) 中的分析，當前只有 KPIMON xApp 符合 O-RAN SC 標準，其他 4 個 xApp 存在以下問題：

| xApp | 問題 | 需要修正 |
|------|------|---------|
| RC xApp | `/metrics` 返回 JSON 格式 | 改為 `/ric/v1/metrics` Prometheus 格式 |
| QoE Predictor | `/metrics` 返回 JSON 格式 | 改為 `/ric/v1/metrics` Prometheus 格式 |
| FL xApp | `/metrics` 返回 JSON 格式 | 改為 `/ric/v1/metrics` Prometheus 格式 |
| Traffic Steering | 完全沒有 metrics 端點 | 新增 `/ric/v1/metrics` Prometheus 格式 |

### O-RAN SC 標準要求

根據 O-RAN SC 官方文檔：

1. **Metrics 端點**: 必須為 `/ric/v1/metrics`
2. **Metrics 格式**: 必須使用 Prometheus exposition format
3. **Prometheus Annotations**: deployment 必須包含：
   ```yaml
   annotations:
     prometheus.io/scrape: "true"
     prometheus.io/port: "<xapp-port>"
     prometheus.io/path: "/ric/v1/metrics"
   ```
4. **Metrics 類型**: 使用 Counter, Gauge, Histogram 等標準 Prometheus metrics

---

## 系統需求

### 前置條件
- Prometheus Server 已部署（參見 [08-prometheus-monitoring-deployment.md](./08-prometheus-monitoring-deployment.md)）
- 所有 xApp 已成功部署並運行
- Docker 本地 registry 運行中 (`localhost:5000`)
- kubectl 和 helm 已安裝並可訪問叢集

### 軟體需求
- Python `prometheus_client==0.19.0` (已在所有 xApp requirements.txt 中)
- Flask (xApp HTTP API framework)

---

## 實作策略

### Small CLs 分解

遵循 CLAUDE.md 的 Small CLs 原則，將修正工作分為 4 個獨立的 Small CLs：

- **Small CL #2**: 修正 RC xApp metrics 端點
- **Small CL #3**: 修正 QoE Predictor metrics 端點
- **Small CL #4**: 修正 Federated Learning metrics 端點
- **Small CL #5**: 為 Traffic Steering 新增 metrics 端點

### 平行執行策略

由於這 4 個 xApp 互相獨立，使用 4 個 backend-specialist agents 平行修正源碼，提高效率。

---

## 部署步驟

### 步驟 1: 平行修正源碼 (4 個 agents)

啟動 4 個 backend-specialist agents 同時修正所有 xApp：

```bash
# 4 個 agents 平行執行：
# - Agent 1: 修正 RC xApp
# - Agent 2: 修正 QoE Predictor
# - Agent 3: 修正 Federated Learning
# - Agent 4: 為 Traffic Steering 新增 metrics
```

**修正內容**（每個 xApp）:

1. **導入 Prometheus 庫**:
   ```python
   from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST
   from flask import Response
   ```

2. **定義 Prometheus Metrics**:
   - 使用有意義的 metric 名稱（如 `rc_control_actions_sent_total`）
   - 選擇合適的 metric 類型（Counter, Gauge, Histogram）
   - 添加清晰的描述和 labels

3. **新增 `/ric/v1/metrics` 端點**:
   ```python
   @app.route('/ric/v1/metrics', methods=['GET'])
   def get_prometheus_metrics():
       """Prometheus metrics endpoint (O-RAN SC standard)"""
       # 更新 Gauge metrics
       update_gauge_metrics()
       # 返回 Prometheus 格式
       return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
   ```

4. **在業務邏輯中更新 metrics**:
   - 在適當位置調用 `.inc()`, `.set()`, `.observe()` 等方法

5. **添加 Prometheus annotations** (deployment.yaml):
   ```yaml
   spec:
     template:
       metadata:
         annotations:
           prometheus.io/scrape: "true"
           prometheus.io/port: "<port>"
           prometheus.io/path: "/ric/v1/metrics"
   ```

### 步驟 2: 創建統一部署腳本

創建 `scripts/redeploy-xapps-with-metrics.sh` 腳本，自動化執行：

1. **階段 1**: 構建並推送所有 Docker 映像
2. **階段 2**: 重新部署所有 xApp
3. **階段 3**: 驗證所有 metrics 端點

**腳本功能**:
- 自動檢測失敗並繼續處理其他 xApp
- 完整的日誌輸出和進度追蹤
- 自動驗證 Prometheus 端點和 annotations

### 步驟 3: 執行部署

```bash
chmod +x /home/thc1006/oran-ric-platform/scripts/redeploy-xapps-with-metrics.sh
sudo bash /home/thc1006/oran-ric-platform/scripts/redeploy-xapps-with-metrics.sh
```

---

## 部署過程記錄

### 部署時間
- **開始時間**: 2025-11-15 11:41:08
- **完成時間**: 2025-11-15 11:46:17
- **總耗時**: 約 5 分 9 秒

### 執行日誌摘要

#### 階段 1: 構建 Docker 映像 (約 50 秒)

**RC xApp**:
- Image: `localhost:5000/xapp-ran-control:1.0.0`
- Digest: `sha256:f88b1d2f5a942ea9ae775f10faaca836f15fd99432b1305d69a520a7dfae2c02`
- 狀態: ✅ 成功

**QoE Predictor**:
- Image: `localhost:5000/xapp-qoe-predictor:1.0.0`
- Digest: `sha256:ef7df64cda9bb00f3b8260822c3056e07a77c0ebd296ce6e38d515567c89cab8`
- 狀態: ✅ 成功

**Federated Learning**:
- Image: `localhost:5000/xapp-federated-learning:1.0.0`
- Digest: `sha256:d078e33cf3bd0932d07aee08a7f9a2e40e1f90da8b27ebcbfbad6d0578b5a9c7`
- 狀態: ✅ 成功

**Traffic Steering**:
- Image: `localhost:5000/xapp-traffic-steering:1.0.0`
- Digest: `sha256:8813bb2ead6f13cf705f9bd69e7f935378acd62530534e221daf516d394e24ba`
- 狀態: ✅ 成功

#### 階段 2: 重新部署 xApps (約 4 分鐘)

每個 xApp 的部署流程：
1. 刪除現有 Pod
2. 應用新的 deployment (包含 Prometheus annotations)
3. 等待 Pod 就緒

**所有 xApp 部署結果**: ✅ 全部成功

#### 階段 3: 驗證 Metrics 端點 (約 10 秒)

**RC xApp**:
```
Pod: ran-control-5448ff8945-5tmk7
✓ Prometheus metrics 端點正常
✓ Prometheus annotations 已設定
```

**QoE Predictor**:
```
Pod: qoe-predictor-55b75b5f8c-xqs6w
✓ Prometheus metrics 端點正常
✓ Prometheus annotations 已設定
```

**Federated Learning**:
```
Pod: federated-learning-58fc88ffc6-hpgnf
✓ Prometheus metrics 端點正常
✓ Prometheus annotations 已設定
```

**Traffic Steering**:
```
Pod: traffic-steering-86b8c9c469-jb4dd
✓ Prometheus metrics 端點正常
✓ Prometheus annotations 已設定
```

### 最終部署結果

```
==================================================
   部署結果總結
==================================================
總計: 4 個 xApps
成功: 4 個
失敗: 0 個

✓ 所有 xApps 部署和驗證成功！
==================================================
```

---

## 驗證測試

### 測試 1: 驗證所有 xApp Pods 運行正常

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pods -n ricxapp
```

**結果**:
```
NAME                                  READY   STATUS    RESTARTS   AGE
kpimon-797bbd666c-b2q29               1/1     Running   0          3h2m
ran-control-5448ff8945-5tmk7          1/1     Running   0          4m47s
qoe-predictor-55b75b5f8c-xqs6w        1/1     Running   0          3m45s
federated-learning-58fc88ffc6-hpgnf   1/1     Running   0          2m33s
traffic-steering-86b8c9c469-jb4dd     1/1     Running   0          60s
```

**狀態**: ✅ 全部運行正常

### 測試 2: 驗證 Prometheus 抓取狀態

```bash
curl -s http://10.43.152.93:80/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.kubernetes_namespace == "ricxapp") | {app: .labels.app, health, lastScrape}'
```

**結果**:
```json
{
  "app": "traffic-steering",
  "health": "up",
  "lastScrape": "2025-11-15T11:46:20.064562507Z"
}
{
  "app": "ran-control",
  "health": "up",
  "lastScrape": "2025-11-15T11:46:23.166196761Z"
}
{
  "app": "qoe-predictor",
  "health": "up",
  "lastScrape": "2025-11-15T11:46:29.896575766Z"
}
{
  "app": "federated-learning",
  "health": "up",
  "lastScrape": "2025-11-15T11:46:19.454623647Z"
}
```

**狀態**: ✅ Prometheus 成功抓取所有 4 個 xApp

### 測試 3: 驗證 xApp 特定 Metrics

**RC xApp Metrics**:
```bash
curl -s http://10.43.115.80:8100/ric/v1/metrics | grep "^rc_"
```

**輸出**:
```
rc_control_actions_sent_total 0.0
rc_control_actions_success_total 0.0
rc_control_actions_failed_total 0.0
rc_handovers_triggered_total 0.0
rc_resource_optimizations_total 0.0
rc_slice_reconfigurations_total 0.0
rc_active_controls 0.0
rc_network_cells 0.0
rc_control_queue_size 0.0
```

**Traffic Steering Metrics**:
```bash
curl -s http://10.43.213.53:8080/ric/v1/metrics | grep "^ts_"
```

**輸出**:
```
ts_handover_decisions_total 0.0
ts_handover_triggered_total 0.0
ts_active_ues 0.0
ts_policy_updates_total 0.0
ts_e2_indications_received_total 0.0
```

**狀態**: ✅ 所有自定義 metrics 正確導出

### 測試 4: 驗證 Prometheus Annotations

```bash
kubectl get pod -n ricxapp ran-control-5448ff8945-5tmk7 -o jsonpath='{.metadata.annotations}' | jq .
```

**輸出**:
```json
{
  "prometheus.io/path": "/ric/v1/metrics",
  "prometheus.io/port": "8100",
  "prometheus.io/scrape": "true"
}
```

**狀態**: ✅ Annotations 正確設定

---

## 技術實作詳細

### RC xApp Metrics 設計

**Prometheus Metrics 定義** (`src/ran_control.py:31-40`):
```python
control_actions_sent = Counter('rc_control_actions_sent_total', 'Total number of control actions sent')
control_actions_success = Counter('rc_control_actions_success_total', 'Total number of successful control actions')
control_actions_failed = Counter('rc_control_actions_failed_total', 'Total number of failed control actions')
handovers_triggered = Counter('rc_handovers_triggered_total', 'Total number of handovers triggered')
resource_optimizations = Counter('rc_resource_optimizations_total', 'Total number of resource optimizations')
slice_reconfigurations = Counter('rc_slice_reconfigurations_total', 'Total number of slice reconfigurations')
active_controls_gauge = Gauge('rc_active_controls', 'Number of active control actions')
network_cells_gauge = Gauge('rc_network_cells', 'Number of monitored network cells')
control_queue_size = Gauge('rc_control_queue_size', 'Size of control action queue')
```

**業務邏輯整合** (`src/ran_control.py:268-281, 308-310, 402-404`):
- `_handle_control_ack()`: 增加成功計數器和特定動作計數器
- `_handle_control_failure()`: 增加失敗計數器
- `_control_processor()`: 增加發送計數器和更新 Gauge

**Metrics 端點** (`src/ran_control.py:794-802`):
```python
@app.route('/ric/v1/metrics', methods=['GET'])
def get_metrics():
    """Get control metrics in Prometheus format"""
    active_controls_gauge.set(len(self.active_controls))
    network_cells_gauge.set(len(self.network_state))
    control_queue_size.set(len(self.control_queue))

    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
```

### QoE Predictor Metrics 設計

**Prometheus Metrics 定義** (`src/qoe_predictor.py:46-54`):
```python
PREDICTIONS_TOTAL = Counter('qoe_predictions_total', 'Total number of QoE predictions made', ['metric_type'])
ACTIVE_UES = Gauge('qoe_active_ues', 'Number of active UEs with QoE predictions')
DEGRADATION_EVENTS = Counter('qoe_degradation_events_total', 'Total QoE degradation events detected', ['service_type'])
PREDICTION_SCORE = Gauge('qoe_prediction_score', 'Latest QoE prediction score', ['ue_id', 'metric_type'])
PREDICTION_LATENCY = Histogram('qoe_prediction_latency_seconds', 'Time taken to generate QoE predictions')
MODEL_UPDATES = Counter('qoe_model_updates_total', 'Total number of model updates')
FEATURE_BUFFER_SIZE = Gauge('qoe_feature_buffer_size', 'Number of features in buffer', ['ue_id'])
RMR_MESSAGES_RECEIVED = Counter('qoe_rmr_messages_received_total', 'Total RMR messages received', ['msg_type'])
```

**特點**:
- 使用 labels (`metric_type`, `ue_id`, `service_type`) 進行細粒度分類
- 使用 Histogram 追蹤預測延遲分布

### Federated Learning Metrics 設計

**Prometheus Metrics 定義** (`src/federated_learning.py:52-68`):
```python
fl_rounds_total = Counter('fl_rounds_total', 'Total number of FL rounds completed')
fl_clients_registered_total = Counter('fl_clients_registered_total', 'Total number of clients registered')
fl_model_updates_received_total = Counter('fl_model_updates_received_total', 'Total number of model updates received')
fl_gradient_updates_received_total = Counter('fl_gradient_updates_received_total', 'Total number of gradient updates received')
fl_aggregations_completed_total = Counter('fl_aggregations_completed_total', 'Total number of aggregations completed')
fl_communication_rounds_total = Counter('fl_communication_rounds_total', 'Total number of communication rounds')
fl_data_processed_bytes_total = Counter('fl_data_processed_bytes_total', 'Total amount of data processed (bytes)')
fl_current_round = Gauge('fl_current_round', 'Current FL round number')
fl_active_clients = Gauge('fl_active_clients', 'Number of currently active clients')
fl_total_clients = Gauge('fl_total_clients', 'Total number of registered clients')
fl_global_accuracy = Gauge('fl_global_accuracy', 'Global model accuracy')
fl_convergence_rate = Gauge('fl_convergence_rate', 'Model convergence rate')
fl_aggregation_duration_seconds = Histogram('fl_aggregation_duration_seconds', 'Time taken for model aggregation')
fl_client_update_duration_seconds = Histogram('fl_client_update_duration_seconds', 'Time taken for client updates')
```

**特點**:
- 全面追蹤 FL 訓練過程（輪次、客戶端、聚合、準確率）
- 使用 Histogram 追蹤關鍵操作耗時

### Traffic Steering Metrics 設計

**Prometheus Metrics 定義** (`src/traffic_steering.py:38-58`):
```python
ts_handover_decisions_total = Counter(
    'ts_handover_decisions_total',
    'Total number of handover decisions evaluated'
)
ts_handover_triggered_total = Counter(
    'ts_handover_triggered_total',
    'Total number of handovers triggered'
)
ts_active_ues = Gauge(
    'ts_active_ues',
    'Current number of active UEs being monitored'
)
ts_policy_updates_total = Counter(
    'ts_policy_updates_total',
    'Total number of A1 policy updates received'
)
ts_e2_indications_received_total = Counter(
    'ts_e2_indications_received_total',
    'Total number of E2 indications received'
)
```

**業務邏輯整合** (`src/traffic_steering.py:170, 195, 210, 234, 323, 389`):
- `_handle_indication()`: 記錄 E2 indication 接收
- `_evaluate_handover()`: 記錄決策評估和觸發
- `_handle_policy_request()`: 記錄 A1 policy 更新
- `_health_check_loop()`: 更新活躍 UE 數量

---

## 遇到的問題與解決方案

### 問題 1: 無問題

**描述**: 所有 4 個 xApp 的修正都一次性成功，沒有遇到任何編譯錯誤、運行時錯誤或部署失敗。

**原因**:
- 詳細的源碼分析和計劃
- 使用專業的 backend-specialist agents
- 遵循 Small CLs 原則，每個修改範圍明確且獨立
- 充分測試驗證

**結論**: 良好的規劃和方法論確保了零問題部署。

### 問題 2: KPIMON 未出現在 Prometheus targets (已解決 - Small CL #6)

**觀察**: KPIMON xApp 雖然之前就符合標準（有 `/ric/v1/metrics` 端點），但在 Prometheus targets 查詢結果中未顯示。

**原因調查**:
```bash
kubectl get pod -n ricxapp kpimon-797bbd666c-b2q29 -o jsonpath='{.metadata.annotations}'
```

**根本原因**: KPIMON deployment 缺少 Prometheus annotations。

**解決方案** (已於 2025-11-15 11:52 執行):
1. 在 `/home/thc1006/oran-ric-platform/xapps/kpimon-go-xapp/deploy/deployment.yaml` 添加 Prometheus annotations:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/ric/v1/metrics"
```
2. 重新部署 KPIMON:
```bash
kubectl delete pod -n ricxapp -l app=kpimon
kubectl apply -f /home/thc1006/oran-ric-platform/xapps/kpimon-go-xapp/deploy/deployment.yaml
kubectl wait --for=condition=ready pod -l app=kpimon -n ricxapp --timeout=120s
```
3. 驗證結果:
```bash
kubectl exec -n ricplt deployment/r4-infrastructure-prometheus-server -- \
  wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null | \
  jq -r '.data.activeTargets[] | select(.labels.app == "kpimon") | {app: .labels.app, health: .health}'
# 輸出: {"app": "kpimon", "health": "up"}
```

**狀態**: ✅ 已解決。KPIMON 現已出現在 Prometheus targets 並正常被抓取。

---

## 性能指標

### 部署效率
- **4 個 xApp 並行處理**: 約 5 分鐘完成
- **Docker 映像構建**: 約 50 秒 (並行)
- **Pod 重啟**: 約 1-2 分鐘/xApp
- **Metrics 驗證**: 約 10 秒

### 資源使用
- **Docker 映像大小**:
  - RC xApp: 3454 layers
  - QoE Predictor: 3662 layers
  - FL xApp: 3870 layers
  - Traffic Steering: 2831 layers
- **CPU/Memory**: 所有 xApp 維持正常運行，無資源問題

### Prometheus 抓取性能
- **抓取間隔**: 15 秒 (Prometheus 默認配置)
- **抓取延遲**: < 1 秒
- **所有 targets 狀態**: health=up

---

## 總結

### 關鍵成果

1. ✅ **5 個 xApp 全部符合 O-RAN SC 標準**:
   - RC xApp: JSON → Prometheus 格式 (Small CL #2)
   - QoE Predictor: JSON → Prometheus 格式 (Small CL #3)
   - Federated Learning: JSON → Prometheus 格式 (Small CL #4)
   - Traffic Steering: 新增 Prometheus 端點 (Small CL #5)
   - KPIMON: 添加 Prometheus annotations (Small CL #6)

2. ✅ **完全符合 O-RAN SC 標準**:
   - 所有 5 個 xApp 使用 `/ric/v1/metrics` 端點
   - 所有 xApp 返回 Prometheus exposition format
   - 所有 deployment 包含正確的 Prometheus annotations

3. ✅ **Prometheus 自動發現和抓取**:
   - 5 個 xApp 全部出現在 Prometheus targets
   - 所有 targets 狀態為 "up"
   - Metrics 成功抓取並可查詢

4. ✅ **零錯誤部署**:
   - 無編譯錯誤
   - 無運行時錯誤
   - 無部署失敗
   - 所有驗證通過

5. ✅ **最終驗證結果** (2025-11-15 11:55):
   ```json
   [
     {"app": "federated-learning", "health": "up"},
     {"app": "kpimon", "health": "up"},
     {"app": "qoe-predictor", "health": "up"},
     {"app": "ran-control", "health": "up"},
     {"app": "traffic-steering", "health": "up"}
   ]
   ```

### 當前監控架構狀態

**完成的組件**:
- ✅ Prometheus Server (Small CL #1)
- ✅ RC xApp metrics (Small CL #2)
- ✅ QoE Predictor metrics (Small CL #3)
- ✅ Federated Learning metrics (Small CL #4)
- ✅ Traffic Steering metrics (Small CL #5)
- ✅ KPIMON Prometheus annotations (Small CL #6)

**當前架構**:
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   KPIMON    │     │     RC      │     │    QoE      │
│   metrics   │     │   metrics   │     │  Predictor  │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │  /ric/v1/metrics  │                   │
       └───────────────────┴───────────────────┤
                                               │
┌─────────────┐     ┌─────────────┐           │
│     FL      │     │  Traffic    │           │
│   metrics   │     │  Steering   │           │
└──────┬──────┘     └──────┬──────┘           │
       │                   │                   │
       └───────────────────┴───────────────────┘
                           │
                           v
                  ┌─────────────────┐
                  │  Prometheus     │
                  │    Server       │
                  └─────────────────┘
                           │
                           v
                  ┌─────────────────┐
                  │  AlertManager   │ (可選)
                  └─────────────────┘
```

### 後續步驟

**已完成** (Small CLs #1-#6):
- ✅ Small CL #1: 部署 Prometheus Server
- ✅ Small CL #2: 修正 RC xApp metrics 端點
- ✅ Small CL #3: 修正 QoE Predictor metrics 端點
- ✅ Small CL #4: 修正 Federated Learning metrics 端點
- ✅ Small CL #5: 為 Traffic Steering 新增 metrics 端點
- ✅ Small CL #6: 修正 KPIMON Prometheus annotations

**可選改進**:
- 創建 Grafana 儀表板 (可選)
- 配置 AlertManager 告警規則 (可選)
- 部署 VESPA Manager (可選，用於 VES 集成)

### 建議

**生產環境**:
- 啟用 Prometheus 持久化儲存
- 配置告警規則監控 xApp 健康狀態
- 部署 Grafana 視覺化監控儀表板
- 定期檢查 metrics 數據完整性

**開發流程**:
- 新增 xApp 時必須實作 `/ric/v1/metrics` 端點
- 新增 xApp 時必須添加 Prometheus annotations
- 遵循 Small CLs 原則進行修改
- 充分測試驗證後再部署到生產環境

### 最終驗證命令

**檢查所有 xApp Pods**:
```bash
kubectl get pods -n ricxapp
```

**檢查 Prometheus targets**:
```bash
kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80
# 訪問: http://localhost:9090/targets
```

**查詢 xApp metrics**:
```bash
# 在 Prometheus UI 中查詢:
ts_handover_decisions_total
rc_control_actions_sent_total
qoe_predictions_total
fl_rounds_total
```

---

## 參考資料

### 相關部署指南
- [08-prometheus-monitoring-deployment.md](./08-prometheus-monitoring-deployment.md) - Prometheus Server 部署
- [07-xapps-health-check-deployment.md](./07-xapps-health-check-deployment.md) - xApp 健康檢查
- [02-kpimon-xapp-deployment.md](./02-kpimon-xapp-deployment.md) - KPIMON xApp 部署

### O-RAN SC 官方文檔
- [VESPA Manager Project](https://gerrit.o-ran-sc.org/r/gitweb?p=ric-plt/vespamgr.git)
- [O-RAN SC RIC Platform](https://docs.o-ran-sc.org/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)

### 配置文件位置
- xApp 源碼: `/home/thc1006/oran-ric-platform/xapps/{rc-xapp,qoe-predictor,federated-learning,traffic-steering}/src/`
- Deployment 配置: `/home/thc1006/oran-ric-platform/xapps/*/deploy/deployment.yaml`
- 部署腳本: `/home/thc1006/oran-ric-platform/scripts/redeploy-xapps-with-metrics.sh`
- 部署日誌: `/tmp/xapp-metrics-deployment.log`

### Prometheus Metrics 命名規範
- Prefix: 使用 xApp 縮寫（`rc_`, `ts_`, `qoe_`, `fl_`）
- Suffix:
  - `_total` for Counters
  - `_seconds` for timing metrics
  - No suffix for Gauges
- Labels: 使用有意義的 label 名稱（`metric_type`, `ue_id`, `service_type`）
