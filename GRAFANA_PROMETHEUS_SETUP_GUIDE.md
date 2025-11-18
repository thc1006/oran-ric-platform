# Grafana 與 Prometheus 監控系統設置指南

**專案**: O-RAN RIC Platform (J Release)
**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-18
**版本**: 2.0.0
**Grafana 版本**: 12.2.1
**Prometheus 版本**: 2.x

---

## 📋 目錄

- [1. 監控架構概覽](#1-監控架構概覽)
- [2. Prometheus 設置](#2-prometheus-設置)
- [3. Grafana 設置](#3-grafana-設置)
- [4. 訪問監控系統](#4-訪問監控系統)
- [5. 創建第一個 Dashboard](#5-創建第一個-dashboard)
- [6. 進階查詢範例](#6-進階查詢範例)
- [7. 告警設置](#7-告警設置)
- [8. 故障排除](#8-故障排除)

---

## 1. 監控架構概覽

### 1.1 系統架構圖

```
┌──────────────────────────────────────────────────────────────┐
│                    O-RAN RIC Platform                         │
│                                                               │
│  ┌────────────────────────────────────────────────────┐     │
│  │ xApps (ricxapp namespace)                          │     │
│  │                                                     │     │
│  │  ┌──────────────┐  ┌──────────────┐              │     │
│  │  │   KPIMON     │  │ RAN Control  │              │     │
│  │  │  Port: 8080  │  │  Port: 8100  │              │     │
│  │  │  /metrics    │  │  /metrics    │              │     │
│  │  └──────┬───────┘  └──────┬───────┘              │     │
│  │         │                   │                      │     │
│  │  ┌──────────────┐  ┌──────────────┐              │     │
│  │  │   Traffic    │  │ QoE Predictor│              │     │
│  │  │   Steering   │  │  Port: 8090  │              │     │
│  │  │  Port: 8081  │  │  /metrics    │              │     │
│  │  └──────┬───────┘  └──────┬───────┘              │     │
│  │         │                   │                      │     │
│  │  ┌──────────────┐                                 │     │
│  │  │  Federated   │                                 │     │
│  │  │  Learning    │                                 │     │
│  │  │  Port: 8110  │                                 │     │
│  │  │  /metrics    │  (GPU 加速訓練)                 │     │
│  │  └──────┬───────┘                                 │     │
│  │         │                                          │     │
│  └─────────┼──────────────────────────────────────────┘     │
│            │                                                │
│            │ Prometheus 自動發現並抓取                      │
│            │ (每 15 秒一次)                                 │
│            ↓                                                │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Prometheus Server (ricplt namespace)               │    │
│  │  - 收集時間序列數據                                │    │
│  │  - 儲存 15 天歷史數據                              │    │
│  │  - 提供 PromQL 查詢介面                            │    │
│  │  - Port: 32673 (NodePort)                         │    │
│  └────────┬───────────────────────────────────────────┘    │
│           │                                                │
│           │ HTTP API (PromQL)                             │
│           ↓                                                │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Grafana (ricplt namespace)                         │    │
│  │  - 視覺化儀表板                                    │    │
│  │  - 即時圖表                                        │    │
│  │  - 告警通知                                        │    │
│  │  - Port: 30703 (NodePort)                         │    │
│  └────────────────────────────────────────────────────┘    │
│                                                            │
└──────────────────────────────────────────────────────────────┘
                           │
                           ↓
                  ┌─────────────────┐
                  │   瀏覽器訪問     │
                  │  (用戶介面)     │
                  └─────────────────┘
```

### 1.2 監控指標分類

| 類別 | Metrics 範例 | 用途 |
|------|-------------|------|
| **O-RAN 業務指標** | `fl_communication_rounds_total` | Federated Learning 通訊輪次 |
| | `fl_clients_registered_total` | 已註冊的 FL 客戶端數量 |
| | `fl_aggregations_completed_total` | 完成的聚合次數 |
| | `fl_current_round` | 當前訓練輪次 |
| | `fl_global_accuracy` | 全局模型準確度 |
| | `fl_convergence_rate` | 收斂速率 |
| | `fl_active_clients` | 活躍客戶端數 |
| | `fl_client_update_duration_seconds` | 客戶端更新延遲（histogram）|
| | `fl_aggregation_duration_seconds` | 聚合操作延遲（histogram）|
| | `fl_data_processed_bytes_total` | 已處理的數據量 |
| **應用性能** | `process_resident_memory_bytes` | 記憶體使用量 |
| | `process_cpu_seconds_total` | CPU 使用時間 |
| | `python_gc_collections_total` | Python GC 次數 |
| **服務健康** | `up` | 服務存活狀態 (1=UP, 0=DOWN) |
| **Kubernetes** | `kubelet_*`, `apiserver_*` | 集群健康狀態 |

### 1.3 數據流向

```
xApps → Prometheus → Grafana → 用戶
 ↓         ↓           ↓
暴露     收集儲存    視覺化展示
metrics   (15天)     即時監控
```

---

## 2. Prometheus 設置

### 2.1 Prometheus 配置檔案

**位置**: 透過 Helm Chart 部署，配置在 ConfigMap 中

**查看當前配置**:
```bash
kubectl get configmap -n ricplt r4-infrastructure-prometheus-server -o yaml
```

**關鍵配置參數**:

```yaml
global:
  scrape_interval: 15s      # 每 15 秒抓取一次
  scrape_timeout: 10s       # 抓取超時時間
  evaluation_interval: 15s  # 規則評估間隔

scrape_configs:
  # Kubernetes Pods 自動發現
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      # 只抓取有 prometheus.io/scrape=true annotation 的 Pods
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        regex: "true"
        action: keep

      # 使用 prometheus.io/path annotation 指定 metrics 路徑
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        regex: (.+)
        target_label: __metrics_path__
        action: replace

      # 使用 prometheus.io/port annotation 指定端口
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        regex: ([^:]+)(?::\d+)?;(\d+)
        target_label: __address__
        replacement: $1:$2
        action: replace
```

### 2.2 xApps Metrics 暴露配置

每個 xApp 需要在 Deployment YAML 中添加以下 annotations：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: federated-learning
  namespace: ricxapp
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"      # 啟用 Prometheus 抓取
        prometheus.io/port: "8110"        # Metrics 端口
        prometheus.io/path: "/ric/v1/metrics"  # Metrics 路徑
    spec:
      containers:
      - name: federated-learning
        image: localhost:5000/xapp-federated-learning:1.0.0
        ports:
        - name: http-api
          containerPort: 8110
          protocol: TCP
```

**已配置的 xApps**（實際部署狀態）:

| xApp | Pod Name | Port | Metrics Path | Status |
|------|----------|------|--------------|--------|
| **KPIMON** | kpimon-54486974b6-jmrnb | 8080 | `/ric/v1/metrics` | ✅ 運行中 |
| **RAN Control** | ran-control-68dd98746d-jlzz7 | 8100 | `/ric/v1/metrics` | ✅ 運行中 |
| **Traffic Steering** | traffic-steering-664d55cdb5-pgqp2 | 8081 | `/ric/v1/metrics` | ✅ 運行中 |
| **QoE Predictor** | qoe-predictor-55b75b5f8c-6pt7m | 8090 | `/ric/v1/metrics` | ✅ 運行中 |
| **Federated Learning** | federated-learning-58fc88ffc6-gncg5 | 8110 | `/ric/v1/metrics` | ✅ 運行中 |
| **E2 Simulator** | e2-simulator-54f6cfd7b4-kgwwj | N/A | N/A | ⚠️ 無 Prometheus 配置 |

### 2.3 驗證 Prometheus 抓取狀態

```bash
# 方法 1: 查看 Prometheus Targets 頁面
# 瀏覽器開啟: http://192.168.0.190:32673/targets

# 方法 2: 使用 API 查詢
curl -s http://192.168.0.190:32673/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "kubernetes-pods") | {pod: .labels.kubernetes_pod_name, health: .health}'

# 預期輸出:
# {
#   "pod": "federated-learning-58fc88ffc6-gncg5",
#   "health": "up"
# }
# {
#   "pod": "kpimon-54486974b6-jmrnb",
#   "health": "up"
# }
# ... (其他 xApps)
```

### 2.4 測試 Metrics 端點

```bash
# 直接訪問 xApp 的 metrics 端點
kubectl exec -n ricxapp <pod-name> -- curl -s localhost:8110/ric/v1/metrics

# 或從集群外部（如果 Pod IP 可訪問）
curl http://<pod-ip>:8110/ric/v1/metrics

# 範例輸出:
# # HELP fl_model_updates_received_total Total model updates received
# # TYPE fl_model_updates_received_total counter
# fl_model_updates_received_total 42.0
#
# # HELP process_resident_memory_bytes Resident memory size in bytes.
# # TYPE process_resident_memory_bytes gauge
# process_resident_memory_bytes 893968384.0
```

---

## 3. Grafana 設置

### 3.1 Grafana 部署

**Namespace**: `ricplt`
**Service Type**: NodePort
**Port**: 30703

**部署命令** (已完成):
```bash
# Grafana 通過 Helm Chart 部署
helm install oran-grafana grafana/grafana \
  --namespace ricplt \
  --set service.type=NodePort \
  --set adminUser=admin \
  --set adminPassword=oran-ric-admin
```

### 3.2 Grafana 配置檔案

**當前實際配置**:

```yaml
# Grafana Datasource 配置（實際部署）
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://r4-infrastructure-prometheus-server.ricplt.svc.cluster.local
        isDefault: true
        uid: PBFA97CFB590B2093
        jsonData:
          timeInterval: 15s
          pdcInjected: false
        editable: true

# Dashboard Provisioning (如果有預設 dashboards)
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: 'oran-ric-dashboards'
        orgId: 1
        folder: 'O-RAN RIC'
        type: file
        disableDeletion: false
        updateIntervalSeconds: 10
        options:
          path: /var/lib/grafana/dashboards/oran-ric
```

### 3.3 數據源配置驗證

**登入後驗證數據源**:

1. 登入 Grafana: `http://192.168.0.190:30703`
2. 左側菜單 → **Configuration** → **Data Sources**
3. 應該看到 **Prometheus** (綠色勾選，標記為 Default)

**API 驗證**:
```bash
curl -s http://admin:oran-ric-admin@192.168.0.190:30703/api/datasources | jq .

# 預期輸出:
# [
#   {
#     "id": 1,
#     "name": "Prometheus",
#     "type": "prometheus",
#     "url": "http://r4-infrastructure-prometheus-server.ricplt:80",
#     "isDefault": true
#   }
# ]
```

### 3.4 防火牆設置

**允許外部訪問** (已完成):

```bash
# 查看當前防火牆規則
sudo ufw status

# 應該包含:
# 30703/tcp    ALLOW    Anywhere    # Grafana NodePort
# 32673/tcp    ALLOW    Anywhere    # Prometheus NodePort
```

**如果需要重新配置**:
```bash
sudo ufw allow 30703/tcp comment 'Grafana NodePort'
sudo ufw allow 32673/tcp comment 'Prometheus NodePort'
sudo ufw reload
```

---

## 4. 訪問監控系統

### 4.1 Grafana Web UI

**URL**: `http://192.168.0.190:30703`

**登入資訊**:
```
Username: admin
Password: oran-ric-admin
```

**首次登入建議**:
1. ✅ 登入成功後，立即更改密碼
   - 點擊左下角頭像 → **Profile** → **Change Password**

2. ✅ 驗證數據源連接
   - **Configuration** → **Data Sources** → **Prometheus** → **Save & Test**
   - 應該看到 "Data source is working" 綠色訊息

3. ✅ 熟悉介面
   - **Dashboards**: 查看和管理儀表板
   - **Explore**: 即時查詢和探索數據
   - **Alerting**: 配置告警規則

### 4.2 Prometheus Web UI

**URL**: `http://192.168.0.190:32673`

**無需登入**

**主要功能**:
- **Graph**: 執行 PromQL 查詢並繪製圖表
- **Targets**: 查看所有抓取目標的狀態
- **Status**: 查看 Prometheus 配置和運行狀態

**快速測試**:
```promql
# 在 Prometheus Graph 頁面輸入:
up{job="kubernetes-pods"}

# 點擊 Execute，切換到 Graph tab
# 應該看到所有 xApps 的 up 狀態 (值為 1)
```

### 4.3 Port Forward 方式訪問（備選）

如果 NodePort 無法訪問，可以使用 port-forward:

```bash
# Grafana
kubectl port-forward -n ricplt svc/oran-grafana 3000:80

# Prometheus
kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80

# 然後訪問:
# Grafana: http://localhost:3000
# Prometheus: http://localhost:9090
```

---

## 5. 創建第一個 Dashboard

### 5.1 Dashboard 規劃

**建議的第一個 Dashboard: "O-RAN xApps 監控總覽"**

包含以下面板:
1. xApps 健康狀態 (Stat)
2. xApps 記憶體使用 (Time series)
3. xApps CPU 使用率 (Time series)
4. Federated Learning 訓練指標 (Time series)
5. E2 Simulator 狀態 (Stat)

### 5.2 創建 Dashboard 步驟

> **注意**: 以下步驟適用於 **Grafana 12.2.1** (2025年版本)

#### Step 1: 建立新 Dashboard

1. 登入 Grafana (`http://192.168.0.190:30703`)
   - Username: `admin`
   - Password: `oran-ric-admin`

2. 點擊左上角 **Dashboards** (或側邊欄 ☰ → **Dashboards**)

3. 點擊右上角 **New** 按鈕，選擇 **New Dashboard**

4. 在空白 Dashboard 上，點擊 **+ Add visualization**

5. 選擇數據源: **Prometheus** (應該已經是預設)

#### Step 2: 添加第一個面板 - xApps 健康狀態

**面板配置** (Grafana 12.2.1):

1. **在 Query tab 中配置查詢**:

   **Query A**:
   ```promql
   up{kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"}
   ```

2. **設置圖例格式**:
   - 在 Query 下方的 **Legend** 欄位輸入:
   ```
   {{kubernetes_pod_name}}
   ```

3. **選擇視覺化類型**:
   - 點擊右上角的視覺化選擇器（預設可能是 Time series）
   - 選擇 **Stat**

4. **配置 Panel options** (右側面板):
   - **Title**: `xApps 健康狀態`
   - **Description**: `顯示所有 xApps 的運行狀態 (1=UP, 0=DOWN)`

5. **配置 Value options**:
   - **Show**: `All values`
   - **Calculate**: `Last` (顯示最新值)

6. **配置 Standard options**:
   - **Unit**: 選擇 `Misc > none`
   - **Color scheme**: 選擇 `From thresholds (by value)`

7. **配置 Thresholds**:
   - 展開 **Thresholds** 區域
   - 點擊 **+ Add threshold**
   - 設置:
     - Base (預設): 紅色 (Red)
     - `1`: 綠色 (Green)

8. 點擊右上角 **Apply** 或 **Save** 按鈕

#### Step 3: 添加第二個面板 - 記憶體使用

**面板配置** (Grafana 12.2.1):

1. 回到 Dashboard，點擊右上角 **Add** → **Visualization**

2. **在 Query tab 配置查詢**:

   **Query A**:
   ```promql
   process_resident_memory_bytes{job="kubernetes-pods", kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"} / 1024 / 1024
   ```

3. **圖例格式**:
   ```
   {{kubernetes_pod_name}}
   ```

4. **視覺化類型**: **Time series** (預設)

5. **Panel options**:
   - **Title**: `xApps 記憶體使用`
   - **Description**: `顯示所有 xApps 的常駐記憶體使用量 (MB)`

6. **Standard options**:
   - **Unit**: 在下拉選單中搜尋 `Data > megabytes (MB)` 或直接輸入 `mbytes`
   - **Decimals**: `2`

7. **Graph styles** (在視覺化設置中):
   - **Style**: `Lines`
   - **Line width**: `2`
   - **Fill opacity**: `10`
   - **Gradient mode**: `None` 或 `Opacity`

8. **Legend** (圖例設置):
   - **Visibility**: `Show legend`
   - **Mode**: `List`
   - **Placement**: `Bottom`
   - **Values**: 勾選 `Last` 和 `Max`

9. 點擊右上角 **Apply**

#### Step 4: 添加第三個面板 - CPU 使用率

**面板配置** (Grafana 12.2.1):

1. 點擊 **Add** → **Visualization**

2. **Query A**:
   ```promql
   rate(process_cpu_seconds_total{job="kubernetes-pods", kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"}[5m]) * 100
   ```

3. **圖例**:
   ```
   {{kubernetes_pod_name}}
   ```

4. **視覺化類型**: **Time series**

5. **Panel options**:
   - **Title**: `xApps CPU 使用率`
   - **Description**: `顯示所有 xApps 的 CPU 使用百分比`

6. **Standard options**:
   - **Unit**: 搜尋 `Misc > Percent (0-100)` 或輸入 `percent`
   - **Decimals**: `2`
   - **Min**: `0`
   - **Max**: `100`

7. **Thresholds** (閾值設置):
   - 點擊 **+ Add threshold**
   - 配置:
     - Base: 綠色 (Green) - `0`
     - Threshold 1: 黃色 (Yellow) - `50`
     - Threshold 2: 紅色 (Red) - `80`

8. **Graph styles**:
   - **Line width**: `2`
   - **Fill opacity**: `10`

9. 點擊 **Apply**

#### Step 5: 添加第四個面板 - Federated Learning 訓練指標

**面板配置** (使用實際存在的 metrics):

1. 點擊 **Add** → **Visualization**

2. **配置多個查詢**:

   **Query A** - 通訊輪次增長率:
   ```promql
   rate(fl_communication_rounds_total{kubernetes_pod_name=~"federated-learning.*"}[5m])
   ```
   - **Legend**: `通訊輪次/秒`

   **Query B** - 完成的聚合速率:
   ```promql
   rate(fl_aggregations_completed_total{kubernetes_pod_name=~"federated-learning.*"}[5m])
   ```
   - **Legend**: `聚合完成/秒`

   **Query C** - 當前輪次:
   ```promql
   fl_current_round{kubernetes_pod_name=~"federated-learning.*"}
   ```
   - **Legend**: `當前輪次`

   **Query D** - 全局準確度:
   ```promql
   fl_global_accuracy{kubernetes_pod_name=~"federated-learning.*"}
   ```
   - **Legend**: `準確度`

3. **視覺化類型**: **Time series**

4. **Panel options**:
   - **Title**: `Federated Learning 訓練進度`
   - **Description**: `顯示 FL 通訊輪次、聚合速率、當前輪次和準確度`

5. **Standard options**:
   - **Unit**: `short` (因為有多種單位)
   - **Decimals**: `2`

6. **Legend**:
   - **Mode**: `List`
   - **Placement**: `Bottom`
   - **Values**: 勾選 `Last`

7. 點擊 **Apply**

#### Step 6: 儲存 Dashboard

1. 點擊右上角 **Save dashboard** 按鈕（💾 磁碟圖標）

2. **填寫儲存資訊**:
   - **Dashboard name**: `O-RAN xApps 監控總覽`
   - **Folder**: 選擇 `General` 或點擊 **New folder** 創建 `O-RAN RIC` 資料夾
   - **Description** (可選): `O-RAN RIC Platform xApps 即時監控儀表板 - 包含健康狀態、資源使用和 FL 訓練進度`

3. 點擊 **Save** 按鈕

> **提示**: Grafana 12 支援 AI 自動生成 Dashboard 標題和描述，您可以嘗試使用該功能。

### 5.3 Dashboard 優化

**調整時間範圍**:
- 右上角時間選擇器: 選擇 `Last 1 hour` 或 `Last 6 hours`
- 設置自動刷新: 選擇 `5s` 或 `10s`

**排列面板**:
- 拖曳面板到想要的位置
- 調整面板大小（拖曳右下角）
- 建議排列:
  ```
  ┌──────────────┬──────────────┐
  │ xApps 健康狀態│ FL 訓練進度   │
  ├──────────────┴──────────────┤
  │      記憶體使用              │
  ├─────────────────────────────┤
  │      CPU 使用率              │
  └─────────────────────────────┘
  ```

**添加變數 (Variables)** (進階):
1. Dashboard settings → **Variables** → **Add variable**
2. Name: `xapp`
3. Type: `Query`
4. Data source: `Prometheus`
5. Query: `label_values(up{job="kubernetes-pods"}, kubernetes_pod_name)`
6. 可以用 `$xapp` 在查詢中篩選特定 xApp

---

## 6. 進階查詢範例

### 6.1 O-RAN 業務指標

#### Federated Learning 訓練監控（實際可用的 Metrics）

```promql
# 1. 通訊輪次總數
fl_communication_rounds_total{kubernetes_pod_name=~"federated-learning.*"}

# 2. 通訊輪次增長率 (每秒)
rate(fl_communication_rounds_total{kubernetes_pod_name=~"federated-learning.*"}[5m])

# 3. 聚合完成總數
fl_aggregations_completed_total{kubernetes_pod_name=~"federated-learning.*"}

# 4. 聚合完成速率
rate(fl_aggregations_completed_total{kubernetes_pod_name=~"federated-learning.*"}[5m])

# 5. 當前訓練輪次
fl_current_round{kubernetes_pod_name=~"federated-learning.*"}

# 6. 全局模型準確度
fl_global_accuracy{kubernetes_pod_name=~"federated-learning.*"}

# 7. 收斂速率
fl_convergence_rate{kubernetes_pod_name=~"federated-learning.*"}

# 8. 活躍客戶端數
fl_active_clients{kubernetes_pod_name=~"federated-learning.*"}

# 9. 已註冊客戶端總數
fl_clients_registered_total{kubernetes_pod_name=~"federated-learning.*"}

# 10. 已處理數據量 (Bytes)
fl_data_processed_bytes_total{kubernetes_pod_name=~"federated-learning.*"}

# 11. 客戶端更新延遲 P95 (histogram metric)
histogram_quantile(0.95, rate(fl_client_update_duration_seconds_bucket{kubernetes_pod_name=~"federated-learning.*"}[5m]))

# 12. 平均客戶端更新時間
rate(fl_client_update_duration_seconds_sum{kubernetes_pod_name=~"federated-learning.*"}[5m]) /
rate(fl_client_update_duration_seconds_count{kubernetes_pod_name=~"federated-learning.*"}[5m])

# 13. 聚合操作延遲 P95
histogram_quantile(0.95, rate(fl_aggregation_duration_seconds_bucket{kubernetes_pod_name=~"federated-learning.*"}[5m]))

# 14. 平均聚合時間
rate(fl_aggregation_duration_seconds_sum{kubernetes_pod_name=~"federated-learning.*"}[5m]) /
rate(fl_aggregation_duration_seconds_count{kubernetes_pod_name=~"federated-learning.*"}[5m])
```

### 6.2 資源使用監控

#### 記憶體監控

```promql
# 1. 所有 xApps 記憶體使用 (MB) - 使用實際 Pod 名稱
process_resident_memory_bytes{job="kubernetes-pods", kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"} / 1024 / 1024

# 2. 記憶體使用 Top 5 xApps
topk(5, process_resident_memory_bytes{job="kubernetes-pods", kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"})

# 3. Federated Learning 記憶體趨勢
process_resident_memory_bytes{kubernetes_pod_name=~"federated-learning.*"}

# 4. 記憶體增長率 (MB/min)
deriv(process_resident_memory_bytes{kubernetes_pod_name=~"federated-learning.*"}[10m]) * 60 / 1024 / 1024

# 5. 虛擬記憶體使用 (GB)
process_virtual_memory_bytes{kubernetes_pod_name=~"federated-learning.*"} / 1024 / 1024 / 1024
```

#### CPU 監控

```promql
# 1. 所有 xApps CPU 使用率 (%)
rate(process_cpu_seconds_total{job="kubernetes-pods", kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"}[5m]) * 100

# 2. CPU 使用 Top 5 xApps
topk(5, rate(process_cpu_seconds_total{job="kubernetes-pods", kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"}[5m]) * 100)

# 3. xApps 平均 CPU 使用率
avg(rate(process_cpu_seconds_total{job="kubernetes-pods", kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"}[5m]) * 100)

# 4. Federated Learning CPU 使用率
rate(process_cpu_seconds_total{kubernetes_pod_name=~"federated-learning.*"}[5m]) * 100
```

#### Python 應用監控

```promql
# 1. Python GC 執行頻率
rate(python_gc_collections_total[5m])

# 2. GC 收集的物件數
rate(python_gc_objects_collected_total[5m])

# 3. 虛擬記憶體使用
process_virtual_memory_bytes{job="kubernetes-pods"} / 1024 / 1024 / 1024  # GB
```

### 6.3 服務健康監控

```promql
# 1. 所有 xApps 健康狀態
up{kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*|e2-simulator.*"}

# 2. Down 的服務數量
count(up{kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"} == 0)

# 3. 服務可用率 (過去 1 小時) - 以百分比顯示
avg_over_time(up{kubernetes_pod_name=~"federated-learning.*"}[1h]) * 100

# 4. 服務中斷次數 (過去 1 小時)
changes(up{kubernetes_pod_name=~"federated-learning.*"}[1h])

# 5. 正常運行的 xApps 數量
count(up{kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"} == 1)
```

### 6.4 多維度聚合查詢

```promql
# 1. 按 namespace 聚合記憶體
sum by (kubernetes_namespace) (process_resident_memory_bytes{job="kubernetes-pods"}) / 1024 / 1024

# 2. 按 pod 聚合 CPU
sum by (kubernetes_pod_name) (rate(process_cpu_seconds_total{job="kubernetes-pods"}[5m]) * 100)

# 3. 計算記憶體總使用量
sum(process_resident_memory_bytes{job="kubernetes-pods", kubernetes_namespace="ricxapp"}) / 1024 / 1024 / 1024  # GB

# 4. 平均響應時間 (如果有 HTTP metrics)
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
```

### 6.5 複雜業務查詢

```promql
# 1. FL 訓練效率指標 (聚合完成數/CPU時間)
rate(fl_aggregations_completed_total{kubernetes_pod_name=~"federated-learning.*"}[5m]) /
rate(process_cpu_seconds_total{kubernetes_pod_name=~"federated-learning.*"}[5m])

# 2. FL 訓練效率 (通訊輪次/CPU時間)
rate(fl_communication_rounds_total{kubernetes_pod_name=~"federated-learning.*"}[5m]) /
rate(process_cpu_seconds_total{kubernetes_pod_name=~"federated-learning.*"}[5m])

# 3. 記憶體增長速率 (MB/min)
deriv(process_resident_memory_bytes{kubernetes_pod_name=~"federated-learning.*"}[10m]) * 60 / 1024 / 1024

# 4. 預測 1 小時後的記憶體使用 (線性預測)
predict_linear(process_resident_memory_bytes{kubernetes_pod_name=~"federated-learning.*"}[30m], 3600) / 1024 / 1024

# 5. 所有 xApps 的記憶體使用比例 (%)
(process_resident_memory_bytes{job="kubernetes-pods", kubernetes_namespace="ricxapp"} /
 sum(process_resident_memory_bytes{job="kubernetes-pods", kubernetes_namespace="ricxapp"})) * 100

# 6. FL 數據處理速率 (MB/sec)
rate(fl_data_processed_bytes_total{kubernetes_pod_name=~"federated-learning.*"}[5m]) / 1024 / 1024

# 7. FL 客戶端註冊率
rate(fl_clients_registered_total{kubernetes_pod_name=~"federated-learning.*"}[5m])
```

---

## 7. 告警設置

> **重要**: 本節適用於 **Grafana 12.2.1 Unified Alerting** 系統

### 7.1 Grafana Unified Alerting 配置

**Grafana 12 告警系統架構**:
- **Alert Rules**: 定義何時觸發告警
- **Contact Points**: 定義發送告警的目的地（Email, Slack, Webhook 等）
- **Notification Policies**: 定義哪些告警發送到哪些 Contact Points

**設置告警的步驟**:
1. 配置 Contact Points (通知目的地)
2. 創建 Alert Rules (告警規則)
3. 配置 Notification Policies (可選，使用預設即可)
4. 測試告警

#### 配置 Contact Points (通知渠道)

**步驟**:

1. 點擊左側菜單 **Alerts & IRM**（或側邊欄 ☰ → **Alerting**）

2. 點擊 **Contact points** tab

3. 點擊右上角 **+ Add contact point**

4. **配置 Email 通知** (範例):
   - **Name**: `Email - Ops Team`
   - **Integration**: 選擇 **Email**
   - **Addresses**: 輸入 `ops@example.com` (多個地址用逗號分隔)
   - **Message** (可選): 自定義郵件內容
   - **Subject** (可選): 自定義主題

5. 點擊 **Test** 按鈕測試通知（會發送測試郵件）

6. 點擊 **Save contact point**

**其他支援的 Contact Points**:
- **Slack**: 需要 Webhook URL
- **Webhook**: 自定義 HTTP endpoint
- **PagerDuty**: 需要 Integration Key
- **Microsoft Teams**: 需要 Webhook URL
- **Discord**: 需要 Webhook URL

#### 創建 Alert Rules (告警規則)

**方法 1: 從 Dashboard 面板創建** (推薦，Grafana 12 新功能)

1. 開啟您的 Dashboard → 選擇 "xApps 健康狀態" 面板

2. 點擊面板標題 → 點擊三個點 **⋮** → 選擇 **More...** → **New alert rule**

3. **在 Alert Rule 創建頁面配置**:

**方法 2: 直接創建 Alert Rule** (Grafana 12 標準方式)

1. 點擊左側菜單 **Alerts & IRM** → **Alert rules**

2. 點擊右上角 **+ New alert rule**

3. **填寫 Alert Rule 配置**:

#### 告警規則範例 1: xApp Down 告警

**Section 1: Enter alert rule name**
- **Rule name**: `xApp Down Alert`

**Section 2: Set a query and alert condition**

- **Query A** (從現有 Dashboard 複製):
  ```promql
  up{kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"}
  ```

- **Expression B** - Reduce (添加 Expression):
  - **Function**: `Last`
  - **Input**: Query A
  - **Mode**: `Strict`

- **Expression C** - Threshold (添加 Expression):
  - **Input**: Expression B
  - **IS BELOW**: `1`
  - 這是 **Alert Condition** ⚠️ (點擊設為告警條件)

**Section 3: Set evaluation behavior**
- **Folder**: 選擇或創建 `O-RAN Alerts` 資料夾
- **Evaluation group**: 創建新的 `xApps Monitoring` 或使用現有
- **Evaluation interval**: `1m` (每 1 分鐘評估一次)
- **Pending period**: `2m` (持續 2 分鐘後才觸發告警)

**Section 4: Add annotations**
- **Summary**: `xApp is down`
- **Description**:
  ```
  {{ $labels.kubernetes_pod_name }} has been down for more than 2 minutes
  ```

**Section 5: Notifications**
- **Choose contact point**: 選擇 `Email - Ops Team` (或使用 Notification Policy)

**Section 6: Save and exit**
- 點擊右上角 **Save rule and exit**

#### 告警規則範例 2: 記憶體使用過高

**創建步驟** (Grafana 12):

1. **Alerts & IRM** → **Alert rules** → **+ New alert rule**

2. **Enter alert rule name**:
   - **Rule name**: `High Memory Usage - Federated Learning`

3. **Set a query and alert condition**:

   - **Query A**:
     ```promql
     process_resident_memory_bytes{kubernetes_pod_name=~"federated-learning.*"} / 1024 / 1024 / 1024
     ```

   - **Expression B** - Reduce:
     - **Function**: `Last`
     - **Input**: Query A

   - **Expression C** - Threshold:
     - **Input**: Expression B
     - **IS ABOVE**: `10` (10 GB)
     - 設為 Alert Condition ⚠️

4. **Set evaluation behavior**:
   - **Folder**: `O-RAN Alerts`
   - **Evaluation group**: `xApps Monitoring`
   - **Evaluation interval**: `1m`
   - **Pending period**: `5m`

5. **Add annotations**:
   - **Summary**: `High memory usage detected`
   - **Description**:
     ```
     Federated Learning memory usage is {{ $values.B.Value | printf "%.2f" }}GB (threshold: 10GB)
     Pod: {{ $labels.kubernetes_pod_name }}
     ```

6. **Notifications**:
   - **Contact point**: `Email - Ops Team`

7. **Save rule and exit**

#### 告警規則範例 3: CPU 使用率過高

**創建步驟** (Grafana 12):

1. **+ New alert rule**

2. **Rule name**: `High CPU Usage - xApps`

3. **Query and alert condition**:

   - **Query A**:
     ```promql
     rate(process_cpu_seconds_total{kubernetes_pod_name=~"federated-learning.*|kpimon.*|qoe-predictor.*|ran-control.*|traffic-steering.*"}[5m]) * 100
     ```

   - **Expression B** - Reduce:
     - **Function**: `Mean` (平均值)
     - **Input**: Query A

   - **Expression C** - Threshold:
     - **Input**: Expression B
     - **IS ABOVE**: `80` (80%)
     - 設為 Alert Condition ⚠️

4. **Evaluation behavior**:
   - **Folder**: `O-RAN Alerts`
   - **Evaluation group**: `xApps Monitoring`
   - **Evaluation interval**: `1m`
   - **Pending period**: `5m`

5. **Annotations**:
   - **Summary**: `High CPU usage detected`
   - **Description**:
     ```
     Average xApps CPU usage is {{ $values.B.Value | printf "%.2f" }}% (threshold: 80%)
     Affected pod: {{ $labels.kubernetes_pod_name }}
     ```

6. **Notifications**: `Email - Ops Team`

7. **Save rule and exit**

### 7.2 告警測試與驗證

#### 測試 Contact Point

1. **Alerts & IRM** → **Contact points**

2. 找到您的 Contact Point (如 `Email - Ops Team`)

3. 點擊右側的 **Test** 按鈕 (紙飛機圖標)

4. 點擊 **Send test notification**

5. 檢查郵箱是否收到測試通知

#### 測試 Alert Rule

**方法 1: 使用 Grafana UI 測試**

1. **Alerts & IRM** → **Alert rules**

2. 找到您的告警規則，點擊 **View**

3. 查看 **State history** 確認規則是否正常評估

**方法 2: 模擬真實故障**

```bash
# 模擬 xApp Down (刪除一個 Pod)
kubectl delete pod -n ricxapp federated-learning-58fc88ffc6-gncg5

# 等待 2-3 分鐘（pending period），應該收到告警通知

# 驗證告警狀態
# 在 Grafana: Alerts & IRM → Alert rules
# 應該看到告警狀態變為 Firing (紅色)

# Deployment 會自動重建 Pod，告警應該自動解除 (變為 Normal)
kubectl get pods -n ricxapp -w
```

**方法 3: 使用 Prometheus 模擬指標**

如果不想真的刪除 Pod，可以修改告警閾值來測試：
- 將記憶體閾值改為非常低的值（如 0.1 GB）
- 觸發告警後立即改回正常值
- 驗證告警通知和恢復通知

---

## 8. 故障排除

### 8.1 Grafana 無法訪問

**症狀**: 瀏覽器無法開啟 `http://192.168.0.190:30703`

**排查步驟**:

```bash
# 1. 檢查 Grafana Pod 狀態
kubectl get pods -n ricplt -l app.kubernetes.io/name=grafana

# 預期: Running 狀態

# 2. 檢查 Service
kubectl get svc -n ricplt oran-grafana

# 預期: TYPE=NodePort, PORT(S)=80:30703/TCP

# 3. 檢查防火牆
sudo ufw status | grep 30703

# 預期: 30703/tcp ALLOW

# 4. 測試本地訪問
curl -I http://localhost:30703

# 預期: HTTP/1.1 302 Found

# 5. 查看 Pod 日誌
kubectl logs -n ricplt -l app.kubernetes.io/name=grafana --tail=50

# 查找錯誤訊息
```

**常見問題**:
- Pod 未運行 → 檢查 deployment 和 image
- 防火牆阻擋 → `sudo ufw allow 30703/tcp`
- Service 配置錯誤 → 重新部署 Grafana

### 8.2 Prometheus 無數據

**症狀**: Grafana 中查詢無結果

**排查步驟**:

```bash
# 1. 驗證數據源連接
curl -s http://admin:oran-ric-admin@192.168.0.190:30703/api/datasources/1/health

# 預期: {"status":"ok"}

# 2. 檢查 Prometheus 是否運行
kubectl get pods -n ricplt -l app=prometheus

# 3. 檢查 Prometheus Targets
curl -s http://192.168.0.190:32673/api/v1/targets | jq '.data.activeTargets[] | {pod: .labels.kubernetes_pod_name, health: .health}'

# 預期: 所有 xApps 的 health="up"

# 4. 測試簡單查詢
curl -s 'http://192.168.0.190:32673/api/v1/query?query=up' | jq .

# 5. 檢查 xApp metrics 端點
kubectl exec -n ricxapp <xapp-pod> -- curl -s localhost:8110/ric/v1/metrics

# 預期: 看到 Prometheus 格式的 metrics
```

**常見問題**:
- xApp 未暴露 metrics → 檢查 Deployment annotations
- Prometheus 配置錯誤 → 檢查 ConfigMap
- 網路問題 → 檢查 NetworkPolicy

### 8.3 Metrics 缺失或不準確

**症狀**: 某些 metrics 查詢不到或值異常

**排查步驟**:

```bash
# 1. 列出所有可用的 metric 名稱
curl -s http://192.168.0.190:32673/api/v1/label/__name__/values | jq '.data[]' | grep fl_

# 2. 檢查特定 metric 的 labels
curl -s 'http://192.168.0.190:32673/api/v1/series?match[]=fl_model_updates_received_total' | jq .

# 3. 查詢該 metric 的最新值
curl -s 'http://192.168.0.190:32673/api/v1/query?query=fl_model_updates_received_total' | jq .

# 4. 檢查時間範圍
curl -s 'http://192.168.0.190:32673/api/v1/query_range?query=fl_model_updates_received_total&start=2025-11-18T00:00:00Z&end=2025-11-18T23:59:59Z&step=15s' | jq .
```

**常見原因**:
- Metric 名稱錯誤 → 檢查實際暴露的 metric 名稱
- 時間範圍不對 → 調整查詢的 start/end 時間
- 抓取間隔問題 → 檢查 scrape_interval 設置

### 8.4 Dashboard 面板無數據

**症狀**: Dashboard 面板顯示 "No data"

**排查步驟**:

1. **檢查查詢語法**:
   - 點擊面板 → Edit
   - 查看 Query inspector
   - 確認 PromQL 語法正確

2. **測試查詢**:
   - 複製查詢到 Prometheus UI
   - 執行並查看結果
   - 確認有數據返回

3. **檢查時間範圍**:
   - Dashboard 右上角時間選擇器
   - 確保時間範圍包含有數據的時段
   - 嘗試 "Last 1 hour"

4. **檢查變數**:
   - 如果使用了 variables ($xapp, $namespace)
   - 確認變數有正確的值
   - 嘗試移除變數篩選條件

### 8.5 登入失敗

**症狀**: 無法登入 Grafana

**解決方法**:

```bash
# 1. 確認正確的密碼
kubectl get secret -n ricplt oran-grafana -o jsonpath='{.data.admin-password}' | base64 -d
echo

# 輸出: oran-ric-admin

# 2. 重置密碼 (如果需要)
kubectl exec -n ricplt $(kubectl get pods -n ricplt -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') -- grafana cli admin reset-admin-password newpassword123

# 3. 檢查 Pod 健康
kubectl get pods -n ricplt -l app.kubernetes.io/name=grafana

# 4. 清除瀏覽器緩存
# Chrome: Ctrl+Shift+Del → 清除緩存
# 或使用無痕模式
```

---

## 9. 最佳實踐

### 9.1 Dashboard 設計原則

1. **分層設計**:
   - 總覽 Dashboard: 顯示所有服務的高層指標
   - 詳細 Dashboard: 每個 xApp 一個專門的 dashboard
   - 故障排查 Dashboard: 包含詳細的技術指標

2. **合理的刷新頻率**:
   - 實時監控: 5-10 秒
   - 一般監控: 30 秒 - 1 分鐘
   - 歷史分析: 不自動刷新

3. **有意義的面板標題**:
   - 使用描述性名稱
   - 包含單位
   - 添加 tooltip 說明

4. **顏色編碼一致性**:
   - 綠色: 正常
   - 黃色: 警告
   - 紅色: 嚴重

### 9.2 查詢優化

1. **使用合適的時間範圍**:
   ```promql
   # 好: 指定明確的範圍
   rate(metric[5m])

   # 避免: 範圍過大導致查詢慢
   rate(metric[1d])
   ```

2. **使用 recording rules** (對於複雜查詢):
   ```yaml
   # prometheus-rules.yaml
   groups:
     - name: xapp_metrics
       interval: 30s
       rules:
         - record: xapp:memory:total_mb
           expr: sum(process_resident_memory_bytes{job="kubernetes-pods", kubernetes_namespace="ricxapp"}) / 1024 / 1024
   ```

3. **限制返回的時間序列數**:
   ```promql
   # 使用 topk/bottomk
   topk(10, metric)

   # 使用更精確的 label 篩選
   metric{kubernetes_pod_name=~"federated.*"}
   ```

### 9.3 資料保留策略

**Prometheus 保留設置**:

```yaml
# 修改 Prometheus retention
# 在 Helm values 中設置:
server:
  retention: "15d"  # 保留 15 天

# 或通過命令行:
--storage.tsdb.retention.time=15d
--storage.tsdb.retention.size=50GB  # 磁碟空間限制
```

**建議**:
- 短期監控 (實時): 7-15 天
- 長期趨勢: 使用 Grafana 的 data export 或連接 VictoriaMetrics
- 重要業務指標: 配置額外的長期儲存

### 9.4 安全性建議

1. **更改預設密碼**:
   ```bash
   # 登入後立即更改
   # Profile → Change Password
   ```

2. **限制網路訪問**:
   ```bash
   # 只允許特定 IP 訪問
   sudo ufw delete allow 30703/tcp
   sudo ufw allow from 192.168.0.0/24 to any port 30703 comment 'Grafana - LAN only'
   ```

3. **啟用 HTTPS** (生產環境):
   ```yaml
   # 使用 Ingress + cert-manager
   # 或配置 Grafana TLS
   ```

4. **定期備份**:
   ```bash
   # 備份 Grafana dashboards
   curl -s http://admin:oran-ric-admin@192.168.0.190:30703/api/search?type=dash-db | \
     jq -r '.[] | .uid' | \
     while read uid; do
       curl -s "http://admin:oran-ric-admin@192.168.0.190:30703/api/dashboards/uid/$uid" | \
         jq . > "dashboard-$uid.json"
     done
   ```

---

## 10. 附錄

### 10.1 常用 PromQL 函數

| 函數 | 說明 | 範例 |
|------|------|------|
| `rate()` | 計算增長率 | `rate(metric[5m])` |
| `irate()` | 瞬時增長率 | `irate(metric[5m])` |
| `increase()` | 總增長量 | `increase(metric[1h])` |
| `sum()` | 求和 | `sum(metric) by (label)` |
| `avg()` | 平均值 | `avg(metric)` |
| `max()/min()` | 最大/最小值 | `max(metric)` |
| `topk()/bottomk()` | Top/Bottom N | `topk(5, metric)` |
| `histogram_quantile()` | 分位數 | `histogram_quantile(0.95, metric)` |
| `predict_linear()` | 線性預測 | `predict_linear(metric[30m], 3600)` |

### 10.2 有用的資源連結

**官方文檔**:
- Prometheus: https://prometheus.io/docs/
- Grafana: https://grafana.com/docs/
- PromQL: https://prometheus.io/docs/prometheus/latest/querying/basics/

**學習資源**:
- PromQL Cheat Sheet: https://promlabs.com/promql-cheat-sheet/
- Grafana Tutorials: https://grafana.com/tutorials/

**社群**:
- Prometheus GitHub: https://github.com/prometheus/prometheus
- Grafana GitHub: https://github.com/grafana/grafana

### 10.3 快速參考命令

```bash
# === Prometheus ===

# 查看 targets
curl -s http://192.168.0.190:32673/api/v1/targets | jq .

# 執行查詢
curl -s 'http://192.168.0.190:32673/api/v1/query?query=up' | jq .

# 查詢範圍數據
curl -s 'http://192.168.0.190:32673/api/v1/query_range?query=up&start=2025-11-18T00:00:00Z&end=2025-11-18T23:59:59Z&step=15s' | jq .

# 列出所有 metrics
curl -s http://192.168.0.190:32673/api/v1/label/__name__/values | jq .

# === Grafana ===

# 測試登入
curl -s http://admin:oran-ric-admin@192.168.0.190:30703/api/user | jq .

# 列出數據源
curl -s http://admin:oran-ric-admin@192.168.0.190:30703/api/datasources | jq .

# 列出 dashboards
curl -s http://admin:oran-ric-admin@192.168.0.190:30703/api/search?type=dash-db | jq .

# === Kubernetes ===

# 查看 Prometheus Pod
kubectl get pods -n ricplt -l app=prometheus

# 查看 Grafana Pod
kubectl get pods -n ricplt -l app.kubernetes.io/name=grafana

# 查看 xApps
kubectl get pods -n ricxapp

# 檢查 Pod annotations
kubectl get pod -n ricxapp <pod-name> -o jsonpath='{.metadata.annotations}' | jq .

# 查看 Service
kubectl get svc -n ricplt

# === xApp Metrics ===

# 直接訪問 metrics 端點
kubectl exec -n ricxapp <pod-name> -- curl -s localhost:8110/ric/v1/metrics
```

### 10.4 故障排查檢查清單

**Grafana 無法訪問**:
- [ ] Pod 是否 Running?
- [ ] Service 是否存在且類型為 NodePort?
- [ ] 防火牆是否開放 30703 端口?
- [ ] 本地是否能訪問? (`curl http://localhost:30703`)

**Prometheus 無數據**:
- [ ] Prometheus Pod 是否 Running?
- [ ] Targets 頁面是否顯示 xApps? (http://192.168.0.190:32673/targets)
- [ ] Target 健康狀態是否為 UP?
- [ ] xApp Pod 是否有正確的 annotations?

**Dashboard 無數據**:
- [ ] Grafana 數據源是否連接成功?
- [ ] PromQL 查詢語法是否正確?
- [ ] 時間範圍是否合理?
- [ ] Prometheus 是否有該 metric 數據?

**Metrics 不準確**:
- [ ] 抓取間隔是否合理? (預設 15s)
- [ ] xApp 是否正確暴露 metrics?
- [ ] metric 格式是否符合 Prometheus 規範?

---

## 結語

本指南涵蓋了在 O-RAN RIC Platform 專案中設置和使用 **Grafana 12.2.1 + Prometheus** 監控系統的完整流程。

**關鍵要點**:
1. ✅ **Grafana 12.2.1** - 使用最新 2025 年版本，支援 Unified Alerting, Dynamic Dashboards
2. ✅ **Prometheus 自動發現** - 透過 Kubernetes annotations 自動抓取所有 xApps metrics
3. ✅ **實際 Metrics 驗證** - 所有查詢範例均使用真實存在的 metrics
4. ✅ **Unified Alerting** - 新一代告警系統，支援多數據源、複雜表達式
5. ✅ **5 個 xApps 監控** - KPIMON, RAN Control, Traffic Steering, QoE Predictor, Federated Learning

**系統當前狀態** (2025-11-18):
- **Grafana**: http://192.168.0.190:30703 (admin / oran-ric-admin)
- **Prometheus**: http://192.168.0.190:32673
- **xApps**: 5 個全部運行並暴露 metrics
- **Metrics 數量**: 65+ (包含 FL 專用 metrics)

**下一步建議**:
1. 📊 創建更多專門的 dashboards（每個 xApp 一個詳細監控）
2. 🔔 配置更多告警規則（如 FL 訓練停滯、準確度下降等）
3. 📧 設置生產環境通知渠道（Email, Slack, PagerDuty）
4. 🎨 探索 Grafana 12 新功能：
   - Dashboard Outline（樹狀導航）
   - Auto-Grid Layout（自適應佈局）
   - Conditional Rendering（條件渲染）
   - AI-powered features（AI 功能）
5. 💾 考慮長期數據儲存方案（VictoriaMetrics, Thanos, Mimir）
6. 🔐 加強安全性（HTTPS, RBAC, SSO）

**Grafana 12 新功能參考**:
- Dynamic Dashboards: 條件渲染、變數驅動顯示
- Dashboard Outline: 快速導航大型儀表板
- Observability as Code: 版本控制、CI/CD 整合
- 詳見: https://grafana.com/blog/2025/05/07/dynamic-dashboards-grafana-12/

**如有問題**:
- 📖 參考本文檔 [故障排除](#8-故障排除) 章節
- 🌐 查閱 Grafana 官方文檔: https://grafana.com/docs/grafana/latest/
- 🔍 Prometheus 文檔: https://prometheus.io/docs/

---

**文檔版本**: 2.0.0 (根據實際部署環境更新)
**Grafana 版本**: 12.2.1
**最後更新**: 2025-11-18
**維護者**: 蔡秀吉 (thc1006)
**驗證狀態**: ✅ 所有指令和 metrics 已在實際環境驗證
