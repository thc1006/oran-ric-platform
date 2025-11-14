# KPIMON xApp

KPI 監控與異常檢測 xApp，基於 E2SM-KPM v3.0。

## 功能

- ✅ 自動訂閱 E2 KPI（20 種指標）
- ✅ 實時異常檢測（5 種閾值）
- ✅ 雙重數據存儲（Redis + InfluxDB）
- ✅ Prometheus 指標暴露（port 8080）

## 快速部署

### 前提條件

- RIC Platform 已部署（包括 RTMgr 和 InfluxDB）
- ricxapp 命名空間已創建
- Docker registry 運行在 localhost:5000

### 構建鏡像

```bash
cd xapps/kpimon-go-xapp
docker build -t localhost:5000/xapp-kpimon:1.0.0 .
docker push localhost:5000/xapp-kpimon:1.0.0
```

### 部署

```bash
kubectl apply -f deploy/
```

### 驗證

```bash
# 檢查 Pod 狀態
kubectl get pods -n ricxapp -l app=kpimon

# 查看日誌
kubectl logs -n ricxapp -l app=kpimon --tail=50

# 測試 Prometheus 指標
kubectl port-forward -n ricxapp svc/kpimon 8080:8080
curl http://localhost:8080/metrics | grep kpimon_
```

**預期日誌輸出**：
```json
{"msg": "KPIMON xApp initialized"}
{"msg": "Redis connection established"}
{"msg": "InfluxDB connection established"}
{"msg": "KPIMON xApp started successfully"}
{"msg": "Sent subscription request: kpimon_xxx"}
```

## 配置

主要配置在 `config/config.json`：

- `rmr_port`: RMR 數據端口（默認 4560）
- `http_port`: Prometheus 指標端口（默認 8080）
- `redis`: Redis 連接配置
- `influxdb`: InfluxDB 連接配置

配置會自動掛載到 Pod 的 `/app/config/` 目錄。

## 依賴版本

- ricxappframe: 3.2.2
- ricsdl: 3.0.2（經實際部署驗證）
- redis: 4.1.1（ricsdl 3.0.2 指定版本）
- protobuf: 3.20.3
- influxdb-client: 1.36.1
- prometheus-client: 0.19.0

## 支持的 KPI

| KPI 名稱 | 類型 | 單位 | 說明 |
|----------|------|------|------|
| DRB.UEThpDl | throughput | Mbps | 下行吞吐量 |
| DRB.UEThpUl | throughput | Mbps | 上行吞吐量 |
| RRU.PrbUsedDl | resource | % | 下行 PRB 使用率 |
| RRU.PrbUsedUl | resource | % | 上行 PRB 使用率 |
| UE.RSRP | signal | dBm | 參考信號接收功率 |
| ... | ... | ... | 共 20 種 KPI |

完整列表請參考：[deployment-guide-complete.md](../../docs/deployment-guide-complete.md#82-e2sm-kpm-支持的-kpi-列表)

## 異常檢測閾值

- Packet Loss > 5%
- PRB Usage > 90%
- RSRP < -110 dBm
- RSRQ < -15 dB
- RRC Success Rate < 95%

檢測到異常時會記錄到 Redis (`alarms:*` 鍵)。

## Prometheus 指標

```
kpimon_messages_received_total    # 接收訊息總數
kpimon_messages_processed_total   # 處理訊息總數
kpimon_kpi_value{kpi_type,cell_id} # KPI 值（Gauge）
kpimon_processing_time_seconds    # 處理時間（Histogram）
```

## 問題排查

### 訂閱請求發送失敗

```
{"msg": "Failed to send message type 12010"}
```

**原因**：沒有實際的 E2 節點連接
**解決**：這是正常情況，代碼邏輯正常執行，只是缺少接收者

### InfluxDB 連接失敗

```
{"msg": "Failed to connect to InfluxDB"}
```

**檢查**：
```bash
kubectl get pods -n ricplt | grep influxdb
kubectl get svc -n ricplt | grep influxdb
```

### Redis 連接失敗

**檢查**：
```bash
kubectl get pods -n ricplt | grep dbaas
```

## 完整文檔

查看詳細部署指南：[deployment-guide-complete.md](../../docs/deployment-guide-complete.md#4-kpimon-xapp-部署)

## 作者

蔡秀吉（thc1006）
