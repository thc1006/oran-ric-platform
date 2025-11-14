# RAN Control xApp

RAN 控制與優化 xApp，基於 E2SM-RC v2.0。

## 功能

- ✅ 5 種優化算法（切換、資源、負載均衡、切片、功率）
- ✅ A1 策略執行
- ✅ E2 控制請求（10 種控制動作）
- ✅ REST API（6 個端點）
- ✅ 控制動作追蹤與重試機制

## 快速部署

### 前提條件

- RIC Platform 已部署
- ricxapp 命名空間已創建
- Docker registry 運行在 localhost:5000

### 構建鏡像

```bash
cd xapps/rc-xapp
docker build -t localhost:5000/xapp-ran-control:1.0.0 .
docker push localhost:5000/xapp-ran-control:1.0.0
```

### 部署

```bash
kubectl apply -f deploy/
```

### 驗證

```bash
# 檢查 Pod 狀態
kubectl get pods -n ricxapp -l app=ran-control

# 查看日誌
kubectl logs -n ricxapp -l app=ran-control --tail=50

# 測試健康檢查
RC_POD=$(kubectl get pod -n ricxapp -l app=ran-control -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $RC_POD -- curl http://localhost:8100/health/alive

# 查看指標
kubectl exec -n ricxapp $RC_POD -- curl http://localhost:8100/metrics
```

**預期日誌輸出**：
```json
{"msg": "Redis connection established"}
{"msg": "RAN Control xApp initialized"}
{"msg": "Starting RAN Control xApp..."}
{"msg": "RAN Control xApp started successfully"}
```

```
* Running on http://0.0.0.0:8100
```

## REST API

### 健康檢查

```bash
GET /health/alive   # 存活檢查
GET /health/ready   # 就緒檢查
```

### 控制操作

```bash
POST /control/trigger
# Body: {
#   "action_type": "handover",
#   "ue_id": "ue-001",
#   "cell_id": "cell-001",
#   "parameters": {...}
# }

GET /control/status/<action_id>
# Response: 控制動作狀態
```

### 監控

```bash
GET /metrics         # 性能指標
GET /network/state   # 網路狀態
```

## 5 種優化算法

### 1. 切換優化 (Handover Optimization)
```python
# 基於 RSRP 比較服務小區與鄰區
# 考慮滯後值（hysteresis）避免乒乓效應
# 自動觸發 X2 切換
```

**閾值**：
- RSRP threshold: -100 dBm
- RSRQ threshold: -15 dB
- Hysteresis: 3 dB

### 2. 資源分配優化 (Resource Allocation)
```python
# 監控 PRB 使用率
# 高負載時調整調度算法
```

**閾值**：
- PRB threshold high: 80%
- PRB threshold low: 20%

### 3. 負載均衡 (Load Balancing)
```python
# 計算小區負載差異
# 重新分配 UE 到低負載小區
```

**閾值**：
- Load threshold: 0.7 (70%)
- Min UE count: 5

### 4. 切片控制 (Network Slice Control)
```python
# 監控 SLA 達標率
# 違規時動態調整資源份額
```

**閾值**：
- SLA violation threshold: 0.95 (95%)
- Resource efficiency target: 0.8 (80%)

### 5. 功率控制 (Power Control)
```python
# 調整發射功率達到目標 SINR
# 閉環控制機制
```

**閾值**：
- Target SINR: 15 dB
- Max TX power: 43 dBm
- Min TX power: -20 dBm

## E2SM-RC 控制動作

| 動作類型 | ID | 控制風格 | 說明 |
|----------|----|----|------|
| HANDOVER | 1 | 1 | UE 切換控制 |
| RESOURCE_ALLOCATION | 2 | 2 | 資源分配調整 |
| BEARER_CONTROL | 3 | 3 | 承載控制 |
| LOAD_BALANCING | 4 | 2 | 負載均衡 |
| SLICE_CONTROL | 5 | 4 | 網路切片資源分配 |
| POWER_CONTROL | 6 | 5 | 傳輸功率控制 |
| MOBILITY_CONTROL | 7 | 1 | 移動性管理 |
| QOS_CONTROL | 8 | 3 | QoS 參數調整 |
| PDCP_DUPLICATION | 9 | 3 | PDCP 重複傳輸 |
| DRX_CONTROL | 10 | 6 | 不連續接收參數調整 |

## A1 策略支持

支持的策略類型：
- `handover_policy`: 切換參數調整
- `resource_policy`: 資源分配參數
- `slice_policy`: 切片管理參數
- `mobility_policy`: 移動性管理
- `qos_policy`: QoS 參數

**示例**：更新切換滯後值
```bash
curl -X POST http://ran-control:8100/api/policy \
  -H 'Content-Type: application/json' \
  -d '{
    "policy_type": "handover_policy",
    "parameters": {
      "hysteresis": 5
    }
  }'
```

## 配置

主要配置在 `config/config.json`：

```json
{
  "rmr_port": 4580,
  "http_port": 8100,
  "control": {
    "max_queue_size": 1000,
    "processing_interval": 100,
    "timeout_default": 5000,
    "retry_attempts": 3
  },
  "optimization": {
    "handover": {...},
    "resource": {...},
    "load_balancing": {...},
    "slice": {...},
    "power": {...}
  }
}
```

## 依賴版本

與 KPIMON 共享相同的依賴版本：
- ricxappframe: 3.2.2
- ricsdl: 3.0.2（經實際部署驗證）
- redis: 4.1.1（ricsdl 3.0.2 指定版本）
- protobuf: 3.20.3

額外依賴：
- flask: 3.0.0
- numpy: 1.24.3

## 性能指標

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

## 問題排查

### Flask API 未啟動

**檢查日誌**：
```bash
kubectl logs -n ricxapp -l app=ran-control | grep Flask
```

**預期輸出**：
```
* Running on http://0.0.0.0:8100
```

### RMR 路由配置

**檢查 RMR 連接**：
```bash
kubectl logs -n ricxapp -l app=ran-control | grep RMR
```

**預期輸出**：
```
src=ran-control:4580 target=service-ricplt-e2term-rmr-alpha.ricplt:38000
src=ran-control:4580 target=service-ricplt-a1mediator-rmr.ricplt:4562
```

### 控制動作未執行

**原因**：沒有實際的 E2 節點
**驗證**：檢查優化算法是否運行
```bash
kubectl logs -n ricxapp -l app=ran-control | grep optimization
```

## 完整文檔

查看詳細部署指南：[deployment-guide-complete.md](../../docs/deployment-guide-complete.md#5-ran-control-xapp-部署)

## 作者

蔡秀吉（thc1006）
