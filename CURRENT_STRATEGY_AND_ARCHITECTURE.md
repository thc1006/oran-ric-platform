# O-RAN RIC Platform 當前策略與架構說明

**專案**: O-RAN RIC Platform (J Release)
**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-18
**文檔版本**: 1.0.0

---

## 📋 目錄

- [1. 整體架構策略](#1-整體架構策略)
- [2. E2 Simulator 策略](#2-e2-simulator-策略)
- [3. 切片 (Network Slicing) 策略](#3-切片-network-slicing-策略)
- [4. KPM 數據回傳策略](#4-kpm-數據回傳策略)
- [5. Metrics 收集策略](#5-metrics-收集策略)
- [6. 數據流向圖](#6-數據流向圖)
- [7. 未來規劃](#7-未來規劃)

---

## 1. 整體架構策略

### 1.1 設計理念

```
┌─────────────────────────────────────────────────────────────┐
│           模擬環境 (Simulation Environment)                  │
│                                                              │
│  目標：在沒有真實 RAN 設備的情況下，                         │
│        完整驗證 O-RAN RIC Platform 的功能                    │
│                                                              │
│  策略：使用 E2 Simulator 模擬真實 E2 Node 的行為             │
│        生成符合 O-RAN 標準的 E2 消息                         │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 核心組件關係

```
┌──────────────────┐         ┌──────────────────┐
│  E2 Simulator    │────────>│    5 xApps       │
│  (模擬 E2 Node)  │  HTTP   │  (Near-RT RIC)   │
└──────────────────┘         └──────────────────┘
        │                             │
        │                             │
        ↓                             ↓
   E2 消息生成                   業務邏輯處理
   - KPI 指標                    - KPI 監控
   - Handover 事件               - 流量導向
   - QoE 數據                    - QoE 預測
   - Control 事件                - RAN 控制
                                 - 聯邦學習
                                        │
                                        ↓
                                 ┌──────────────────┐
                                 │   Prometheus     │
                                 │  (Metrics 收集)  │
                                 └──────────────────┘
                                        │
                                        ↓
                                 ┌──────────────────┐
                                 │    Grafana       │
                                 │  (視覺化監控)    │
                                 └──────────────────┘
```

### 1.3 當前狀態

| 組件 | 狀態 | 說明 |
|------|------|------|
| **E2 Simulator** | ✅ 運行中 | 模擬 3 個 Cell、20 個 UE |
| **KPIMON** | ✅ 運行中 | 接收並處理 KPI 數據 |
| **Traffic Steering** | ✅ 運行中 | 接收 Handover 事件 |
| **QoE Predictor** | ✅ 運行中 | 接收 QoE Metrics |
| **RAN Control** | ✅ 運行中 | 接收 Control 事件 |
| **Federated Learning** | ✅ 運行中 | CPU 版本（GPU 版本已配置） |
| **Prometheus** | ✅ 運行中 | 收集所有 xApps Metrics |
| **Grafana** | ✅ 運行中 | 可視化監控 |

---

## 2. E2 Simulator 策略

### 2.1 模擬策略概覽

**目標**: 模擬真實 gNodeB (E2 Node) 的行為，生成符合 O-RAN 標準的 E2 消息

**執行頻率**: 每 5 秒一個迭代週期

**模擬範圍**:
- **3 個 Cell**: `cell_001`, `cell_002`, `cell_003`
- **20 個 UE**: `ue_001` ~ `ue_020`

### 2.2 數據生成策略

#### 2.2.1 KPI 指標生成 (E2SM-KPM)

**目標 xApp**: KPIMON

**生成頻率**: 每個迭代週期必定生成（100%）

**數據內容**:

| KPI 名稱 | 範圍 | 單位 | 說明 |
|----------|------|------|------|
| `DRB.PacketLossDl` | 0.1% - 5% | % | 下行封包遺失率 |
| `DRB.PacketLossUl` | 0.1% - 5% | % | 上行封包遺失率 |
| `DRB.UEThpDl` | 10 - 100 | Mbps | 下行吞吐量 |
| `DRB.UEThpUl` | 5 - 50 | Mbps | 上行吞吐量 |
| `RRU.PrbUsedDl` | 30% - 85% | % | 下行 PRB 使用率 |
| `RRU.PrbUsedUl` | 20% - 70% | % | 上行 PRB 使用率 |
| `UE.RSRP` | -120 ~ -80 | dBm | 參考信號接收功率 |
| `UE.RSRQ` | -15 ~ -5 | dB | 參考信號接收質量 |
| `UE.SINR` | 5 ~ 25 | dB | 信號與干擾加噪聲比 |
| `RRC.ConnEstabSucc` | 95% - 99.9% | % | RRC 連接建立成功率 |

**數據格式**:
```json
{
  "timestamp": "2025-11-18T15:30:45.123456",
  "cell_id": "cell_001",
  "ue_id": "ue_015",
  "measurements": [
    {"name": "DRB.PacketLossDl", "value": 2.3},
    {"name": "DRB.UEThpDl", "value": 75.5},
    ...
  ],
  "indication_sn": 1700318445123,
  "indication_type": "report"
}
```

**傳送方式**: HTTP POST 到 `http://kpimon.ricxapp.svc.cluster.local:8081/e2/indication`

#### 2.2.2 Handover 事件生成

**目標 xApp**: Traffic Steering

**生成頻率**: 30% 機率（隨機觸發）

**觸發邏輯**:
```python
if random.random() < 0.3:
    # 生成 Handover 事件
```

**數據內容**:
- **Source Cell**: 隨機選擇 3 個 Cell 之一
- **Target Cell**: 與 Source Cell 不同的另一個 Cell
- **UE ID**: 20 個 UE 中隨機選擇
- **觸發條件**: A3 Event (Coverage-based handover)

**數據格式**:
```json
{
  "timestamp": "2025-11-18T15:30:45.123456",
  "event_type": "handover_request",
  "ue_id": "ue_015",
  "source_cell": "cell_001",
  "target_cell": "cell_003",
  "rsrp": -95.5,
  "rsrq": -12.3,
  "trigger": "A3_event"
}
```

**意義**: 模擬 UE 在不同 Cell 之間移動時的切換場景

#### 2.2.3 QoE Metrics 生成

**目標 xApp**: QoE Predictor

**生成頻率**: 每個迭代週期必定生成（100%）

**計算邏輯**:
```python
# 基礎分數 100
qoe_score = 100.0

# 封包遺失懲罰（0-2%）
qoe_score -= packet_loss * 5.0

# 延遲懲罰（超過 50ms 才開始懲罰）
qoe_score -= max(0, (latency - 50.0) / 2.0)

# Jitter 懲罰
qoe_score -= jitter * 2.0

# 最終分數範圍 0-100
qoe_score = max(0.0, min(100.0, qoe_score))
```

**數據內容**:
| 指標 | 範圍 | 單位 | 說明 |
|------|------|------|------|
| `video_bitrate_mbps` | 2.0 - 10.0 | Mbps | 視頻串流碼率 |
| `packet_loss_percent` | 0.0 - 2.0 | % | 封包遺失率 |
| `latency_ms` | 10.0 - 100.0 | ms | 端到端延遲 |
| `jitter_ms` | 1.0 - 20.0 | ms | 延遲抖動 |
| `qoe_score` | 0 - 100 | score | 綜合 QoE 分數 |

**數據格式**:
```json
{
  "timestamp": "2025-11-18T15:30:45.123456",
  "ue_id": "ue_015",
  "cell_id": "cell_001",
  "metrics": {
    "video_bitrate_mbps": 8.5,
    "packet_loss_percent": 0.5,
    "latency_ms": 45.2,
    "jitter_ms": 5.3,
    "qoe_score": 87.5
  }
}
```

#### 2.2.4 Control 事件生成

**目標 xApp**: RAN Control

**生成頻率**: 20% 機率（隨機觸發）

**事件類型**:
1. **Load Balancing** (負載均衡)
2. **Interference Mitigation** (干擾緩解)
3. **Power Control** (功率控制)

**數據格式**:
```json
{
  "timestamp": "2025-11-18T15:30:45.123456",
  "cell_id": "cell_002",
  "event_type": "interference_mitigation",
  "trigger_condition": {
    "prb_usage": 85.3,
    "active_ues": 35
  }
}
```

### 2.3 當前日誌範例

```
2025-11-18 07:53:38,762 - __main__ - INFO - === Simulation Iteration 872 ===
2025-11-18 07:53:38,765 - __main__ - INFO - Generated KPI indication for cell_002/ue_006
2025-11-18 07:53:38,767 - __main__ - INFO - Generated handover event: cell_003 -> cell_002
2025-11-18 07:53:38,769 - __main__ - INFO - Generated QoE metrics for ue_009: QoE=57.1
2025-11-18 07:53:38,769 - __main__ - INFO - Waiting 5 seconds...
```

**解讀**:
- ✅ 成功生成 KPI 數據 (cell_002/ue_006)
- ✅ 觸發了 Handover 事件 (cell_003 → cell_002)
- ✅ 生成 QoE 數據 (ue_009, 分數 57.1)
- ⏱️ 等待 5 秒後進入下一個迭代

---

## 3. 切片 (Network Slicing) 策略

### 3.1 當前狀態

**實現狀態**: 🟡 **部分實現**

**位置**: RAN Control xApp

**實現層級**:
- ✅ **控制邏輯**: 已實現切片控制算法
- ✅ **E2 接口**: 支援 SLICE_CONTROL 控制動作
- ⚠️ **實際切片**: 需要真實 E2 Node 支援
- ⚠️ **切片數據**: E2 Simulator 目前未生成切片相關數據

### 3.2 切片控制策略 (RC xApp)

**控制風格**: E2SM-RC Control Style 4

**監控指標**:
- **SLA 違規閾值**: 95%（當達標率低於 95% 時觸發調整）
- **資源效率目標**: 80%

**控制邏輯**:
```python
def optimize_slice_resources(self, slice_info: Dict) -> Dict:
    """
    Network Slice 資源優化

    策略：
    1. 監控各切片的 SLA 達標率
    2. 檢測資源使用效率
    3. SLA 違規時動態調整資源份額
    """

    slice_id = slice_info.get('slice_id')
    sla_achievement = slice_info.get('sla_achievement', 1.0)
    current_resources = slice_info.get('allocated_prbs', 0)

    # 檢查 SLA 違規
    if sla_achievement < self.config['optimization']['slice']['sla_violation_threshold']:
        # 增加資源分配
        adjustment = {
            'action': 'increase_allocation',
            'slice_id': slice_id,
            'additional_prbs': int(current_resources * 0.2),  # 增加 20%
            'reason': 'sla_violation'
        }
    else:
        # 檢查資源使用效率
        efficiency = slice_info.get('resource_efficiency', 1.0)
        if efficiency < self.config['optimization']['slice']['resource_efficiency_target']:
            adjustment = {
                'action': 'reduce_allocation',
                'slice_id': slice_id,
                'reduction_prbs': int(current_resources * 0.1),  # 減少 10%
                'reason': 'low_efficiency'
            }
        else:
            adjustment = {
                'action': 'maintain',
                'slice_id': slice_id,
                'reason': 'optimal'
            }

    return adjustment
```

**A1 Policy 支援**:
```json
{
  "policy_type": "slice_policy",
  "parameters": {
    "slice_id": "slice_001",
    "sla_target": {
      "throughput_mbps": 100,
      "latency_ms": 10,
      "reliability": 0.999
    },
    "resource_allocation": {
      "min_prbs": 50,
      "max_prbs": 200
    }
  }
}
```

### 3.3 切片數據模型

**標準切片類型** (根據 3GPP TS 23.501):

| 切片類型 | SST | SD | 典型應用 | 特性 |
|----------|-----|----|---------|----|
| **eMBB** | 1 | 1 | 高清視頻、AR/VR | 高吞吐量 |
| **URLLC** | 2 | 2 | 工業控制、自駕車 | 低延遲、高可靠 |
| **mMTC** | 3 | 3 | IoT 感測器 | 大連接數 |

**切片數據結構** (規劃中):
```json
{
  "slice_id": "slice_001",
  "sst": 1,
  "sd": "000001",
  "type": "eMBB",
  "sla": {
    "throughput_dl_mbps": 100,
    "throughput_ul_mbps": 50,
    "latency_ms": 20,
    "reliability": 0.99
  },
  "allocated_resources": {
    "prbs": 150,
    "percentage": 30.0
  },
  "active_ues": 25,
  "sla_achievement": 0.97
}
```

### 3.4 未來增強

**階段 1** (短期):
- [ ] E2 Simulator 增加切片數據生成
- [ ] 模擬 3 種切片類型的資源競爭
- [ ] 生成切片級別的 KPI 數據

**階段 2** (中期):
- [ ] 實現切片間的動態資源調度
- [ ] 添加切片隔離驗證
- [ ] 實現切片 SLA 監控

**階段 3** (長期):
- [ ] 接入真實 E2 Node
- [ ] 實現端到端切片編排
- [ ] 與核心網切片互通

---

## 4. KPM 數據回傳策略

### 4.1 數據流向

```
┌──────────────────┐
│  E2 Simulator    │
│  (E2 Node)       │
└────────┬─────────┘
         │
         │ HTTP POST /e2/indication
         │ (每 5 秒)
         ↓
┌──────────────────┐
│     KPIMON       │
│  (RIC xApp)      │
└────────┬─────────┘
         │
         │ 1. 接收 KPI 數據
         │ 2. 解析並驗證
         │ 3. 儲存到 Redis
         │ 4. 更新 Prometheus Metrics
         ↓
┌──────────────────┐
│     Redis        │
│  (RIC Platform)  │
└──────────────────┘
         │
         │ 讀取
         ↓
┌──────────────────┐
│  其他 xApps      │
│  (可選訂閱)      │
└──────────────────┘
```

### 4.2 KPIMON 處理策略

**接收端點**: `/e2/indication`

**處理流程**:

```python
@app.route('/e2/indication', methods=['POST'])
def handle_e2_indication():
    """
    處理 E2 Indication 消息

    步驟：
    1. 接收並驗證 JSON 數據
    2. 提取 KPI 測量值
    3. 更新 Prometheus metrics
    4. 儲存到 Redis (供其他 xApps 使用)
    5. 執行異常檢測 (如果啟用)
    """

    data = request.json

    # 1. 驗證
    if not data or 'measurements' not in data:
        return jsonify({'error': 'Invalid data'}), 400

    # 2. 提取測量值
    cell_id = data.get('cell_id', 'unknown')
    ue_id = data.get('ue_id', 'unknown')

    # 3. 更新 Prometheus metrics
    for measurement in data['measurements']:
        kpi_gauge.labels(
            cell_id=cell_id,
            kpi_type=measurement['name']
        ).set(measurement['value'])

    # 4. 儲存到 Redis
    redis_key = f"kpi:{cell_id}:{ue_id}"
    redis_client.setex(redis_key, 60, json.dumps(data))

    # 5. 更新計數器
    messages_received.inc()
    messages_processed.inc()

    return jsonify({'status': 'success'}), 200
```

### 4.3 當前 KPI Metrics

**實際 Prometheus Metrics** (從 KPIMON 暴露):

```prometheus
# 消息統計
kpimon_messages_received_total 886.0
kpimon_messages_processed_total 886.0

# KPI 值 (最新)
kpimon_kpi_value{cell_id="cell_001",kpi_type="DRB.PacketLossDl"} 3.995
kpimon_kpi_value{cell_id="cell_001",kpi_type="DRB.UEThpDl"} 64.15
kpimon_kpi_value{cell_id="cell_001",kpi_type="DRB.UEThpUl"} 9.85
kpimon_kpi_value{cell_id="cell_001",kpi_type="RRU.PrbUsedDl"} 48.93
kpimon_kpi_value{cell_id="cell_001",kpi_type="RRU.PrbUsedUl"} 61.17
kpimon_kpi_value{cell_id="cell_001",kpi_type="UE.RSRP"} -80.09
```

**數據更新頻率**: 每 5 秒（隨 E2 Simulator 迭代）

**數據保留時間**:
- **Redis**: 60 秒（熱數據）
- **Prometheus**: 15 天（時間序列）

### 4.4 KPI 數據訂閱機制

**當前策略**: Redis Pub/Sub (規劃中)

**未來實現**:
```python
# 發布端 (KPIMON)
redis_client.publish('kpi:updates', json.dumps(kpi_data))

# 訂閱端 (其他 xApps)
pubsub = redis_client.pubsub()
pubsub.subscribe('kpi:updates')

for message in pubsub.listen():
    if message['type'] == 'message':
        kpi_data = json.loads(message['data'])
        process_kpi_update(kpi_data)
```

---

## 5. Metrics 收集策略

### 5.1 整體架構

```
┌──────────────────────────────────────────────────────────┐
│                    xApps Layer                            │
│                                                           │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │
│  │ KPIMON  │  │ Traffic │  │   QoE   │  │   RC    │    │
│  │ :8080   │  │  :8081  │  │  :8090  │  │  :8100  │    │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘    │
│       │            │             │            │          │
│       │ /ric/v1/metrics (每個 xApp 暴露)                 │
│       │            │             │            │          │
└───────┼────────────┼─────────────┼────────────┼──────────┘
        │            │             │            │
        │            │             │            │
        ↓            ↓             ↓            ↓
┌──────────────────────────────────────────────────────────┐
│              Prometheus (自動服務發現)                    │
│                                                           │
│  Scrape Config:                                          │
│    - job_name: kubernetes-pods                           │
│    - scrape_interval: 15s                                │
│    - selector: prometheus.io/scrape=true                 │
│                                                           │
│  儲存策略:                                                │
│    - Retention: 15 days                                  │
│    - Time series DB                                      │
└───────────────────────┬──────────────────────────────────┘
                        │
                        │ PromQL API
                        ↓
┌──────────────────────────────────────────────────────────┐
│                     Grafana                               │
│                                                           │
│  - 視覺化儀表板                                           │
│  - 告警規則                                              │
│  - 數據探索                                              │
└──────────────────────────────────────────────────────────┘
```

### 5.2 Metrics 分類策略

#### 5.2.1 業務 Metrics (O-RAN 特定)

**來源**: xApp 應用邏輯

**範例**:

**A. Federated Learning Metrics**:
```prometheus
# 模型更新統計
fl_model_updates_received_total           # Counter
fl_gradient_updates_received_total        # Counter

# 訓練性能
fl_client_update_duration_seconds         # Histogram
  - sum: 總耗時
  - count: 更新次數
  - bucket: 延遲分佈

# 計算資源
fl_training_memory_bytes                  # Gauge
fl_gpu_utilization_percent               # Gauge (GPU 版本)
```

**B. KPIMON Metrics**:
```prometheus
# 消息統計
kpimon_messages_received_total            # Counter
kpimon_messages_processed_total           # Counter

# KPI 值
kpimon_kpi_value{cell_id, kpi_type}      # Gauge
  # Labels:
  #   - cell_id: cell_001, cell_002, cell_003
  #   - kpi_type: DRB.PacketLossDl, DRB.UEThpDl, 等
```

**C. Traffic Steering Metrics** (規劃):
```prometheus
traffic_handovers_requested_total         # Counter
traffic_handovers_successful_total        # Counter
traffic_handovers_failed_total            # Counter
traffic_handover_duration_seconds         # Histogram
```

**D. QoE Predictor Metrics** (規劃):
```prometheus
qoe_predictions_total                     # Counter
qoe_prediction_accuracy                   # Gauge
qoe_model_inference_duration_seconds      # Histogram
```

#### 5.2.2 應用性能 Metrics

**來源**: Python 應用程式（自動暴露）

```prometheus
# Python 運行時
python_gc_objects_collected_total{generation}
python_gc_collections_total{generation}
python_info{implementation, major, minor, patchlevel, version}

# 進程資源使用
process_resident_memory_bytes             # 常駐記憶體
process_virtual_memory_bytes              # 虛擬記憶體
process_cpu_seconds_total                 # CPU 時間
process_start_time_seconds                # 啟動時間
```

#### 5.2.3 健康狀態 Metrics

**來源**: Kubernetes + Prometheus

```prometheus
# 服務存活
up{job, kubernetes_pod_name, kubernetes_namespace}
  # 值: 1 = UP, 0 = DOWN

# Pod 狀態
kube_pod_status_phase{pod, namespace, phase}
kube_pod_container_status_restarts_total
kube_pod_container_resource_requests{resource}
kube_pod_container_resource_limits{resource}
```

### 5.3 自動服務發現策略

**機制**: Kubernetes Service Discovery

**配置方式**: Pod Annotations

**範例** (Federated Learning):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: federated-learning
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"        # 啟用抓取
        prometheus.io/port: "8110"          # Metrics 端口
        prometheus.io/path: "/ric/v1/metrics"  # Metrics 路徑
```

**Prometheus 自動發現邏輯**:
```yaml
scrape_configs:
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod

    relabel_configs:
      # 只抓取有 prometheus.io/scrape=true 的 Pods
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true

      # 使用 annotation 指定的路徑
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)

      # 使用 annotation 指定的端口
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
```

### 5.4 當前 Metrics 統計

**已配置的 xApps**:

| xApp | Port | Path | Status | Metrics 數量 |
|------|------|------|--------|-------------|
| **KPIMON** | 8080 | `/ric/v1/metrics` | ✅ | 15+ |
| **RAN Control** | 8100 | `/ric/v1/metrics` | ✅ | 12+ |
| **Traffic Steering** | 8081 | `/ric/v1/metrics` | ✅ | 10+ |
| **QoE Predictor** | 8090 | `/ric/v1/metrics` | ✅ | 10+ |
| **Federated Learning** | 8110 | `/ric/v1/metrics` | ✅ | 18+ |

**總計**:
- **業務 Metrics**: ~20 個
- **應用性能 Metrics**: ~10 個 (每個 xApp)
- **健康 Metrics**: ~5 個 (每個 xApp)
- **總 Metrics**: 65+ 個時間序列

### 5.5 Metrics 命名規範

**遵循 Prometheus 最佳實踐**:

```
<namespace>_<name>_<unit>_<type>

範例:
- kpimon_messages_received_total          (Counter)
- fl_client_update_duration_seconds       (Histogram)
- process_resident_memory_bytes           (Gauge)
```

**Label 策略**:
- 使用有意義的 label 區分維度
- 避免高基數 label (如 UE ID)
- 保持 label 命名一致性

**範例**:
```prometheus
kpimon_kpi_value{cell_id="cell_001", kpi_type="DRB.PacketLossDl"} 2.3

# Labels:
#   - cell_id: 低基數 (3 個 cells)
#   - kpi_type: 低基數 (10 種 KPI types)
# 總時間序列: 3 × 10 = 30 (可接受)
```

---

## 6. 數據流向圖

### 6.1 完整數據流

```
┌─────────────────────────────────────────────────────────────────┐
│                      E2 Simulator                                │
│                                                                  │
│  每 5 秒生成:                                                    │
│    - KPI 數據 (100%)                                            │
│    - Handover 事件 (30%)                                        │
│    - QoE Metrics (100%)                                         │
│    - Control 事件 (20%)                                         │
└───────┬─────────────┬────────────┬────────────┬─────────────────┘
        │             │            │            │
        │ HTTP POST   │            │            │
        ↓             ↓            ↓            ↓
  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │ KPIMON   │  │ Traffic  │  │   QoE    │  │    RC    │
  │  :8080   │  │ Steering │  │Predictor │  │  :8100   │
  │          │  │  :8081   │  │  :8090   │  │          │
  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
       │             │             │             │
       │ 1. 接收數據│             │             │
       │ 2. 處理邏輯│             │             │
       │ 3. 更新 Metrics         │             │
       │             │             │             │
       ├─────────────┼─────────────┼─────────────┤
       │             │             │             │
       │ 暴露 /ric/v1/metrics                     │
       │             │             │             │
       ↓             ↓             ↓             ↓
┌──────────────────────────────────────────────────────────┐
│               Prometheus (每 15 秒抓取)                   │
│                                                           │
│  收集所有 xApps 的 Metrics:                               │
│    - 業務指標 (KPI, FL 訓練進度, 等)                     │
│    - 性能指標 (CPU, Memory, 等)                          │
│    - 健康指標 (up, restarts, 等)                         │
│                                                           │
│  儲存策略:                                                │
│    - 時間序列資料庫                                       │
│    - 保留 15 天                                          │
└───────────────────────┬──────────────────────────────────┘
                        │
                        │ PromQL API
                        ↓
┌──────────────────────────────────────────────────────────┐
│                    Grafana Dashboard                      │
│                                                           │
│  面板 1: xApps 健康狀態                                   │
│    Query: up{kubernetes_pod_name=~".*xapp.*|federated.*"}│
│                                                           │
│  面板 2: FL 訓練進度                                      │
│    Query: rate(fl_model_updates_received_total[5m])     │
│                                                           │
│  面板 3: KPI 監控                                         │
│    Query: kpimon_kpi_value{kpi_type="DRB.UEThpDl"}       │
│                                                           │
│  面板 4: 資源使用                                         │
│    Query: process_resident_memory_bytes / 1024^2        │
└──────────────────────────────────────────────────────────┘
                        │
                        ↓
                   ┌─────────┐
                   │  用戶   │
                   │  監控   │
                   └─────────┘
```

### 6.2 E2 消息流 (詳細)

```
時間軸 →

T=0s
┌──────────┐
│E2 Sim    │ 生成 KPI (cell_001/ue_015)
└────┬─────┘
     │ POST /e2/indication
     ↓
┌──────────┐
│KPIMON    │ 接收 → 驗證 → 處理
└────┬─────┘
     │ 1. 更新 Redis: kpi:cell_001:ue_015
     │ 2. 更新 Metrics: kpimon_kpi_value{cell_id="cell_001",...}
     ↓

T=0.5s
┌──────────┐
│E2 Sim    │ 觸發 Handover (30% 機率)
└────┬─────┘
     │ POST /e2/indication
     ↓
┌──────────┐
│Traffic   │ 接收 → 分析 → 決策
│Steering  │
└──────────┘

T=1s
┌──────────┐
│E2 Sim    │ 生成 QoE (ue_009, score=57.1)
└────┬─────┘
     │ POST /e2/indication
     ↓
┌──────────┐
│QoE Pred. │ 接收 → 預測 → 更新
└──────────┘

T=1.5s
┌──────────┐
│E2 Sim    │ 觸發 Control 事件 (20% 機率)
└────┬─────┘
     │ POST /e2/indication
     ↓
┌──────────┐
│RC xApp   │ 接收 → 優化算法 → 控制動作
└──────────┘

T=15s
┌──────────┐
│Prometheus│ 自動抓取所有 xApps 的 /ric/v1/metrics
└────┬─────┘
     │ 儲存時間序列數據
     ↓
┌──────────┐
│Time      │
│Series DB │
└──────────┘

T=5s (下一個迭代)
循環重複...
```

---

## 7. 未來規劃

### 7.1 短期增強 (1-2 個月)

#### E2 Simulator 增強
- [ ] **增加切片數據生成**
  - 模擬 3 種切片類型 (eMBB, URLLC, mMTC)
  - 生成切片級別的 KPI
  - 模擬切片資源競爭場景

- [ ] **增加數據多樣性**
  - 模擬不同時段的流量模式
  - 增加異常場景 (高負載、干擾、故障)
  - 模擬 UE 移動軌跡

- [ ] **配置化**
  - 支援外部配置檔案
  - 可調整 Cell/UE 數量
  - 可調整數據生成頻率

#### Metrics 增強
- [ ] **xApp 業務 Metrics 補全**
  - Traffic Steering: 切換成功率、延遲
  - QoE Predictor: 預測準確度、模型性能
  - RAN Control: 控制動作統計

- [ ] **Dashboard 模板**
  - 創建預設 Grafana Dashboards
  - 自動匯入到 Grafana
  - 包含所有 xApps 的監控面板

#### 數據持久化
- [ ] **長期儲存**
  - 接入 InfluxDB 或 VictoriaMetrics
  - 保留 90 天以上數據
  - 支援歷史數據分析

### 7.2 中期規劃 (3-6 個月)

#### 切片編排
- [ ] **切片生命週期管理**
  - 切片創建、修改、刪除 API
  - 切片模板管理
  - 切片監控與告警

- [ ] **切片資源調度**
  - 跨 Cell 資源協調
  - 動態資源重分配
  - SLA 保證機制

#### 智能化
- [ ] **AI/ML 增強**
  - QoE 預測模型訓練
  - 異常檢測
  - 資源需求預測

- [ ] **自動化控制**
  - 閉環控制
  - 自動故障恢復
  - 自適應優化

### 7.3 長期願景 (6-12 個月)

#### 真實 RAN 整合
- [ ] **E2 接口對接**
  - 接入真實 gNodeB
  - E2AP 協議棧實現
  - E2SM 服務模型完整支援

- [ ] **多廠商互通**
  - 支援不同廠商設備
  - 符合 O-RAN 標準
  - 互操作性測試

#### 端到端編排
- [ ] **與核心網整合**
  - 5GC 切片對接
  - 端到端 SLA 保證
  - 跨域資源協調

- [ ] **Non-RT RIC 整合**
  - A1 接口完整實現
  - 策略管理
  - rApp 開發框架

---

## 8. 總結

### 8.1 當前策略總覽表

| 類別 | 項目 | 當前狀態 | 策略 |
|------|------|---------|------|
| **E2 Simulator** | 數據生成 | ✅ 運行中 | 每 5 秒生成 KPI、Handover、QoE、Control 事件 |
| | Cell 配置 | ✅ 3 Cells | cell_001, cell_002, cell_003 |
| | UE 配置 | ✅ 20 UEs | ue_001 ~ ue_020 |
| **切片** | 控制邏輯 | ✅ 已實現 | RC xApp 支援 SLICE_CONTROL |
| | 數據生成 | ⚠️ 規劃中 | E2 Simulator 尚未生成切片數據 |
| | SLA 監控 | ⚠️ 規劃中 | 閾值已定義，待數據輸入 |
| **KPM 數據** | 回傳方式 | ✅ HTTP POST | E2 Simulator → KPIMON |
| | 數據儲存 | ✅ Redis | 60 秒熱數據 |
| | 數據暴露 | ✅ Prometheus | 15 天時間序列 |
| **Metrics** | 收集方式 | ✅ 自動發現 | Kubernetes Service Discovery |
| | 抓取頻率 | ✅ 15 秒 | Prometheus scrape_interval |
| | 保留時間 | ✅ 15 天 | Prometheus retention |
| | 視覺化 | ✅ Grafana | 可創建自定義 Dashboard |

### 8.2 關鍵數字

| 指標 | 數值 | 說明 |
|------|------|------|
| **E2 迭代週期** | 5 秒 | E2 Simulator 生成數據頻率 |
| **Cell 數量** | 3 | 模擬的基站數量 |
| **UE 數量** | 20 | 模擬的用戶設備數量 |
| **KPI 類型** | 10 種 | 每次迭代生成的 KPI 指標數 |
| **Handover 機率** | 30% | 每次迭代觸發切換事件的機率 |
| **Control 事件機率** | 20% | 每次迭代觸發控制事件的機率 |
| **Metrics 抓取間隔** | 15 秒 | Prometheus 抓取 xApps metrics 頻率 |
| **Metrics 保留期** | 15 天 | Prometheus 數據保留時間 |
| **Redis 數據 TTL** | 60 秒 | KPI 數據在 Redis 中的存活時間 |
| **總 Metrics 數** | 65+ | 所有 xApps 暴露的 metrics 總數 |
| **當前迭代** | 870+ | E2 Simulator 已執行的迭代次數 |

### 8.3 重要文件位置

```
oran-ric-platform/
├── simulator/
│   └── e2-simulator/
│       └── src/
│           └── e2_simulator.py          # E2 Simulator 主程式
│
├── xapps/
│   ├── kpimon-go-xapp/                  # KPIMON xApp (KPI 數據處理)
│   ├── traffic-steering/                # Traffic Steering (Handover)
│   ├── qoe-predictor/                   # QoE Predictor
│   ├── rc-xapp/                         # RAN Control (含切片控制)
│   │   └── README.md                    # 包含 5 種優化算法說明
│   └── federated-learning/              # Federated Learning (GPU 支援)
│
├── GRAFANA_PROMETHEUS_SETUP_GUIDE.md    # Grafana & Prometheus 設置指南
├── CURRENT_STRATEGY_AND_ARCHITECTURE.md # 本文件
└── GPU_SETUP_SUCCESS_RECORD.md          # GPU 設置記錄
```

---

**文檔版本**: 1.0.0
**最後更新**: 2025-11-18
**維護者**: 蔡秀吉 (thc1006)

**相關文檔**:
- [Grafana & Prometheus 設置指南](./GRAFANA_PROMETHEUS_SETUP_GUIDE.md)
- [GPU 智能檢測實現](./SMART_GPU_DETECTION_IMPLEMENTATION.md)
- [RAN Control xApp README](./xapps/rc-xapp/README.md)
