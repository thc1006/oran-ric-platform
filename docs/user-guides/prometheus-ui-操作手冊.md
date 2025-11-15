# Prometheus UI 操作手冊

**作者**: 蔡秀吉 (thc1006)
**版本**: 1.0
**日期**: 2025年11月15日
**適用對象**: O-RAN RIC Platform 運維人員

---

## 目錄

1. [快速開始](#快速開始)
2. [Prometheus UI 介面說明](#prometheus-ui-介面說明)
3. [查看 xApp 監控狀態](#查看-xapp-監控狀態)
4. [查詢 xApp Metrics](#查詢-xapp-metrics)
5. [常用查詢範例](#常用查詢範例)
6. [進階操作](#進階操作)
7. [故障排查](#故障排查)

---

## 快速開始

### 前置條件

1. **確認 Prometheus Server 正在運行**:
```bash
kubectl get pods -n ricplt | grep prometheus-server
# 應該看到: r4-infrastructure-prometheus-server-xxxxx   1/1     Running
```

2. **啟動 Port-Forward**:
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80
```

3. **訪問 Prometheus UI**:
```
瀏覽器打開: http://localhost:9090
```

### 如果透過 SSH 連線

在你的**本地電腦**執行：
```bash
ssh -L 9090:localhost:9090 thc1006@<伺服器IP>
```

然後在本地瀏覽器訪問: http://localhost:9090

---

## Prometheus UI 介面說明

### 主要頁面

| 頁面 | URL | 功能 | 使用頻率 |
|------|-----|------|----------|
| **Graph** | /graph | 查詢和視覺化 metrics | ★★★★★ |
| **Targets** | /targets | 查看抓取目標狀態 | ★★★★☆ |
| **Alerts** | /alerts | 查看告警規則 | ★★★☆☆ |
| **Status** | /status | 查看 Prometheus 配置 | ★★☆☆☆ |

### 介面佈局說明

```
┌─────────────────────────────────────────────────────────┐
│  Prometheus                                        [?]  │ ← 頂部導航欄
├─────────────────────────────────────────────────────────┤
│  [Graph] [Alerts] [Status]                              │ ← 頁籤
├─────────────────────────────────────────────────────────┤
│                                                          │
│  查詢輸入框: [________________________]  [Execute]      │ ← 輸入 PromQL 查詢
│                                                          │
│  時間範圍: [1h ▼] [now -1h] to [now]  [Evaluation time] │ ← 時間選擇器
│                                                          │
│  □ Console   ☑ Graph                                    │ ← 顯示模式
│                                                          │
│  ┌──────────────────────────────────────────────┐      │
│  │          📈 圖表顯示區域                      │      │ ← 結果顯示
│  │                                               │      │
│  │   [折線圖會顯示在這裡]                        │      │
│  └──────────────────────────────────────────────┘      │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## 查看 xApp 監控狀態

### 方法 1: 使用 Targets 頁面（推薦初學者）

**步驟 1**: 訪問 Targets 頁面
```
http://localhost:9090/targets
```

**步驟 2**: 找到 "kubernetes-pods" 區塊

你會看到類似這樣的表格：

```
Job: kubernetes-pods

State   Endpoint                              Labels
───────────────────────────────────────────────────────────────
UP      http://10.42.0.75:8100/ric/v1/metrics
        app="ran-control"
        kubernetes_namespace="ricxapp"
        kubernetes_pod_name="ran-control-5448ff8945-5tmk7"

UP      http://10.42.0.XX:8080/ric/v1/metrics
        app="traffic-steering"
        kubernetes_namespace="ricxapp"
        ...
```

**解讀結果**:

| State | 意義 | 應對措施 |
|-------|------|----------|
| **UP** (綠色) | xApp 正常被抓取 | ✅ 正常 |
| **DOWN** (紅色) | xApp 無法訪問 | ⚠️ 檢查 Pod 狀態 |
| **UNKNOWN** (黃色) | 尚未抓取 | ⏳ 等待幾秒重新整理 |

**步驟 3**: 點擊 Endpoint 查看原始 metrics

點擊任一 Endpoint URL，會在新頁籤打開該 xApp 的原始 metrics 輸出：

```
# HELP rc_control_actions_sent_total Total number of control actions sent
# TYPE rc_control_actions_sent_total counter
rc_control_actions_sent_total 0.0

# HELP rc_handovers_triggered_total Total number of handovers triggered
# TYPE rc_handovers_triggered_total counter
rc_handovers_triggered_total 0.0
...
```

### 方法 2: 使用 Graph 查詢（推薦進階用戶）

**訪問 Graph 頁面**:
```
http://localhost:9090/graph
```

**查詢所有 xApp 狀態**:

在查詢框輸入:
```promql
up{job="kubernetes-pods", app!=""}
```

點擊 **[Execute]** 按鈕

**結果解讀**:

**Console 模式** (表格):
```
up{app="ran-control", ...} = 1
up{app="traffic-steering", ...} = 1
up{app="qoe-predictor", ...} = 1
up{app="federated-learning", ...} = 1
up{app="kpimon", ...} = 1
```

- `1` = xApp 正常運行
- `0` = xApp 停止或無法訪問

**Graph 模式** (圖表):
- 會顯示每個 xApp 的時間線
- 線條在 1 = 運行中
- 線條在 0 = 停止

---

## 查詢 xApp Metrics

### 基本查詢語法

**格式**:
```promql
metric_name{label1="value1", label2="value2"}
```

**範例**:
```promql
# 查詢 RC xApp 的控制動作總數
rc_control_actions_sent_total

# 查詢特定 Pod 的控制動作
rc_control_actions_sent_total{kubernetes_pod_name="ran-control-5448ff8945-5tmk7"}

# 查詢所有 ricxapp namespace 的 metrics
{kubernetes_namespace="ricxapp"}
```

### 查詢步驟示範

**步驟 1**: 訪問 Graph 頁面
```
http://localhost:9090/graph
```

**步驟 2**: 輸入查詢

在 "Expression" 輸入框輸入：
```promql
rc_control_actions_sent_total
```

**步驟 3**: 執行查詢

點擊藍色 **[Execute]** 按鈕

**步驟 4**: 查看結果

**Console 模式**（表格視圖）:
```
Element                                          Value
rc_control_actions_sent_total{app="ran-control",
  instance="10.42.0.75:8100",
  job="kubernetes-pods", ...}                    0
```

**Graph 模式**（圖表視圖）:
- 顯示時間序列折線圖
- X 軸: 時間
- Y 軸: metric 值

**步驟 5**: 調整時間範圍

使用頂部的時間選擇器：
- 下拉選單選擇預設範圍: `5m`, `15m`, `1h`, `6h`, `1d`, `7d`
- 或手動輸入時間範圍

### 時間範圍選擇器說明

```
┌──────────────────────────────────────────────┐
│  [1h ▼]  [Evaluation time: now -1h] to [now] │
│           ↑                          ↑        │
│        開始時間                    結束時間    │
└──────────────────────────────────────────────┘
```

**預設選項**:
- `5m` = 最近 5 分鐘
- `15m` = 最近 15 分鐘
- `1h` = 最近 1 小時（預設）
- `6h` = 最近 6 小時
- `1d` = 最近 1 天
- `7d` = 最近 7 天

**自訂時間**:
- 點擊時間輸入框可手動輸入
- 格式範例: `2025-11-15T10:00:00`, `now - 3h`

---

## 常用查詢範例

### 1. RC xApp (RAN Control) 監控

#### 控制動作相關

```promql
# 控制動作發送總數
rc_control_actions_sent_total

# 成功的控制動作
rc_control_actions_success_total

# 失敗的控制動作
rc_control_actions_failed_total

# 控制成功率 (百分比)
(rc_control_actions_success_total / rc_control_actions_sent_total) * 100
```

#### 切換相關

```promql
# 觸發的切換總數
rc_handovers_triggered_total

# 最近 5 分鐘的切換速率（每秒）
rate(rc_handovers_triggered_total[5m])
```

#### 狀態監控

```promql
# 當前活躍的控制動作數量
rc_active_controls

# 監控的網路小區數量
rc_network_cells

# 控制佇列大小
rc_control_queue_size
```

### 2. Traffic Steering xApp 監控

```promql
# 切換決策評估總數
ts_handover_decisions_total

# 實際觸發的切換
ts_handover_triggered_total

# 當前活躍 UE 數量
ts_active_ues

# A1 policy 更新次數
ts_policy_updates_total

# E2 indications 接收總數
ts_e2_indications_received_total

# 切換觸發率（最近 5 分鐘）
rate(ts_handover_triggered_total[5m])
```

### 3. QoE Predictor xApp 監控

```promql
# QoE 預測總數
qoe_predictions_total

# 按類型分組的預測（如果有 labels）
qoe_predictions_total{metric_type="throughput"}

# 活躍 UE 數量
qoe_active_ues

# QoE 降級事件
qoe_degradation_events_total

# 模型更新次數
qoe_model_updates_total

# 預測延遲（histogram）
qoe_prediction_latency_seconds
```

### 4. Federated Learning xApp 監控

```promql
# FL 訓練輪次總數
fl_rounds_total

# 註冊的客戶端總數
fl_clients_registered_total

# 接收的模型更新
fl_model_updates_received_total

# 當前訓練輪次
fl_current_round

# 活躍客戶端數量
fl_active_clients

# 全局模型準確率
fl_global_accuracy

# 模型聚合耗時
fl_aggregation_duration_seconds
```

### 5. KPIMON xApp 監控

```promql
# Python 垃圾回收統計
python_gc_objects_collected_total

# 進程記憶體使用
process_virtual_memory_bytes
process_resident_memory_bytes

# CPU 使用時間
process_cpu_seconds_total

# CPU 使用率（最近 5 分鐘）
rate(process_cpu_seconds_total[5m])
```

### 6. 綜合查詢

#### 查看所有 xApp 是否在線

```promql
up{job="kubernetes-pods", namespace="ricxapp"}
```

#### 查看所有 xApp 的 CPU 使用

```promql
process_cpu_seconds_total{kubernetes_namespace="ricxapp"}
```

#### 查看所有 xApp 的記憶體使用

```promql
process_resident_memory_bytes{kubernetes_namespace="ricxapp"}
```

#### 比較多個 xApp 的某個 metric

```promql
{__name__=~".*_total", kubernetes_namespace="ricxapp"}
```

---

## 進階操作

### 使用函數計算

#### rate() - 計算速率

```promql
# RC xApp 每秒控制動作發送率（最近 5 分鐘平均）
rate(rc_control_actions_sent_total[5m])

# Traffic Steering 每秒切換觸發率
rate(ts_handover_triggered_total[5m])
```

**說明**: `rate()` 計算時間範圍內的每秒平均增長率

#### increase() - 計算增量

```promql
# RC xApp 最近 1 小時的控制動作增量
increase(rc_control_actions_sent_total[1h])

# QoE Predictor 最近 1 天的預測次數
increase(qoe_predictions_total[1d])
```

**說明**: `increase()` 計算時間範圍內的總增量

#### sum() - 求和

```promql
# 所有 xApp 的總 CPU 使用時間
sum(process_cpu_seconds_total{kubernetes_namespace="ricxapp"})

# 所有 xApp 的總記憶體使用
sum(process_resident_memory_bytes{kubernetes_namespace="ricxapp"})
```

#### avg() - 平均值

```promql
# 所有 xApp 的平均記憶體使用
avg(process_resident_memory_bytes{kubernetes_namespace="ricxapp"})
```

#### max() / min() - 最大值 / 最小值

```promql
# 記憶體使用最高的 xApp
max(process_resident_memory_bytes{kubernetes_namespace="ricxapp"})

# 記憶體使用最低的 xApp
min(process_resident_memory_bytes{kubernetes_namespace="ricxapp"})
```

### 計算百分比和比率

```promql
# RC xApp 控制成功率
(rc_control_actions_success_total / rc_control_actions_sent_total) * 100

# Traffic Steering 切換觸發率（觸發/決策）
(ts_handover_triggered_total / ts_handover_decisions_total) * 100
```

### 使用 by 進行分組

```promql
# 按 xApp 分組的 CPU 使用
sum by (app) (rate(process_cpu_seconds_total{kubernetes_namespace="ricxapp"}[5m]))

# 按 Pod 分組的記憶體使用
sum by (kubernetes_pod_name) (process_resident_memory_bytes{kubernetes_namespace="ricxapp"})
```

### 查詢時間點數據

**即時查詢** (Instant query):
- 預設模式
- 查詢最新的值

**範圍查詢** (Range query):
- 使用 `[時間範圍]` 語法
- 範例: `rc_control_actions_sent_total[5m]`
- 返回時間序列數據

---

## 故障排查

### 問題 1: 無法訪問 Prometheus UI

**症狀**: 瀏覽器顯示 "無法連線到 localhost:9090"

**檢查步驟**:

1. **確認 port-forward 正在運行**:
```bash
ps aux | grep "port-forward.*prometheus"
```

如果沒有輸出，重新啟動:
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80
```

2. **確認 Prometheus Server Pod 正常**:
```bash
kubectl get pods -n ricplt | grep prometheus-server
```

應該看到 `Running` 狀態

3. **查看 Pod 日誌**:
```bash
kubectl logs -n ricplt -l app=prometheus,component=server
```

### 問題 2: 找不到 xApp metrics

**症狀**: 查詢 `rc_control_actions_sent_total` 返回空結果

**檢查步驟**:

1. **確認 xApp 在 Targets 中**:
```
訪問: http://localhost:9090/targets
搜尋: ran-control
```

如果找不到，檢查 xApp deployment annotations:
```bash
kubectl get pod -n ricxapp -l app=ran-control -o yaml | grep -A 3 annotations
```

應該有:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8100"
  prometheus.io/path: "/ric/v1/metrics"
```

2. **直接訪問 xApp metrics 端點**:
```bash
POD=$(kubectl get pod -n ricxapp -l app=ran-control -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $POD -- curl -s http://localhost:8100/ric/v1/metrics | head -20
```

應該看到 Prometheus 格式的輸出

3. **檢查 Prometheus 配置**:
```
訪問: http://localhost:9090/status
點擊: Configuration
搜尋: kubernetes-pods
```

### 問題 3: 查詢返回 "no data"

**可能原因**:

1. **時間範圍太早**: xApp 最近才部署，沒有歷史數據
   - **解決**: 選擇 "5m" 或 "15m" 時間範圍

2. **Metric 名稱拼寫錯誤**
   - **解決**: 複製本手冊的範例查詢

3. **xApp 剛重啟**: 數據還未被抓取
   - **解決**: 等待 15-30 秒（Prometheus 每 15 秒抓取一次）

### 問題 4: Graph 顯示不正常

**症狀**: 圖表是空的或顯示 "No data"

**檢查**:

1. 切換到 **Console** 模式查看是否有數據
2. 如果 Console 有數據但 Graph 沒有，調整 Y 軸範圍
3. 檢查時間範圍是否合理

---

## 快速參考卡

### 常用 URL

```
Prometheus UI 首頁:  http://localhost:9090
Graph 頁面:          http://localhost:9090/graph
Targets 頁面:        http://localhost:9090/targets
Alerts 頁面:         http://localhost:9090/alerts
```

### 常用查詢速查

| 需求 | 查詢 |
|------|------|
| 所有 xApp 狀態 | `up{job="kubernetes-pods", namespace="ricxapp"}` |
| RC 控制動作 | `rc_control_actions_sent_total` |
| TS 切換決策 | `ts_handover_decisions_total` |
| QoE 預測次數 | `qoe_predictions_total` |
| FL 訓練輪次 | `fl_rounds_total` |
| CPU 使用率 | `rate(process_cpu_seconds_total[5m])` |
| 記憶體使用 | `process_resident_memory_bytes` |

### 常用函數

| 函數 | 用途 | 範例 |
|------|------|------|
| `rate()` | 計算每秒速率 | `rate(rc_control_actions_sent_total[5m])` |
| `increase()` | 計算增量 | `increase(ts_handover_triggered_total[1h])` |
| `sum()` | 求和 | `sum(process_resident_memory_bytes)` |
| `avg()` | 平均值 | `avg(process_cpu_seconds_total)` |
| `max()` | 最大值 | `max(ts_active_ues)` |
| `by()` | 分組 | `sum by (app) (...)` |

---

## 下一步學習

### 推薦閱讀

1. **PromQL 查詢語言官方文檔**:
   - https://prometheus.io/docs/prometheus/latest/querying/basics/

2. **Prometheus 函數參考**:
   - https://prometheus.io/docs/prometheus/latest/querying/functions/

3. **部署 Grafana** (強烈推薦):
   - Grafana 提供更豐富的視覺化功能
   - 可創建持久化 Dashboard
   - 更適合日常監控

### 常見問題

**Q: Prometheus UI 和 Grafana 有什麼區別？**
- Prometheus UI: 臨時查詢和調試
- Grafana: 專業視覺化和監控

**Q: 數據保留多久？**
- 預設保留 15 天
- 可在 Prometheus 配置中調整

**Q: 如何導出數據？**
- 使用 Prometheus API
- 或使用 Grafana 導出功能

---

## 聯絡資訊

如有問題，請參考：
- 專案文檔: `/home/thc1006/oran-ric-platform/docs/`
- 部署指南: `docs/deployment-guides/08-prometheus-monitoring-deployment.md`
- 作者: 蔡秀吉 (thc1006)

---

**版本歷史**:
- v1.0 (2025-11-15): 初始版本，涵蓋所有 5 個 xApps 的監控
