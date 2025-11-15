# Grafana + Dashboard 部署指南

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-15
**版本**: 1.0.0

---

## 📋 目錄

1. [部署摘要](#部署摘要)
2. [前置條件](#前置條件)
3. [Small CL #7: 部署 Grafana](#small-cl-7-部署-grafana)
4. [Small CL #8: 創建 Dashboard](#small-cl-8-創建-dashboard)
5. [訪問與使用](#訪問與使用)
6. [故障排除](#故障排除)
7. [下一步](#下一步)

---

## 部署摘要

本指南記錄了 O-RAN RIC Platform 上 Grafana 監控系統的完整部署過程，包括 Grafana 本體部署以及 6 個專業 Dashboard 的創建與導入。

### 完成項目

#### Small CL #7: 部署 Grafana ✅
- ✅ 使用 Helm 部署 Grafana 到 Kubernetes (ricplt namespace)
- ✅ 自動配置 Prometheus 數據源
- ✅ 驗證 Grafana 部署與 API 連接

#### Small CL #8: 創建 Dashboard ✅
- ✅ 創建 O-RAN RIC Platform Overview Dashboard
- ✅ 創建 RC xApp 專屬 Dashboard
- ✅ 創建 Traffic Steering xApp 專屬 Dashboard
- ✅ 創建 QoE Predictor xApp 專屬 Dashboard
- ✅ 創建 Federated Learning xApp 專屬 Dashboard
- ✅ 創建 KPIMON xApp 專屬 Dashboard
- ✅ 驗證所有 Dashboard 功能正常

### 部署架構

```
┌─────────────────────────────────────────────────────┐
│                   Grafana UI                         │
│              (http://localhost:3000)                 │
└───────────────────┬─────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│            Prometheus Server                         │
│   (http://r4-infrastructure-prometheus-server)      │
└───────────────────┬─────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│              5 個 xApp Pods                          │
│  • RC xApp          • QoE Predictor                  │
│  • Traffic Steering • Federated Learning             │
│  • KPIMON                                            │
│                                                      │
│  每個 xApp 暴露 /ric/v1/metrics 端點                   │
└─────────────────────────────────────────────────────┘
```

---

## 前置條件

### 必要條件

1. **Kubernetes 叢集運行中**
   ```bash
   kubectl cluster-info
   ```

2. **Prometheus 已部署並運行**
   ```bash
   kubectl get pod -n ricplt -l app=prometheus
   ```

3. **xApp 已部署並提供 metrics**
   ```bash
   kubectl get pod -n ricxapp
   ```

4. **Helm 已安裝**
   ```bash
   helm version
   ```

### 驗證前置條件

執行以下命令確認環境準備就緒：

```bash
# 檢查 Kubernetes
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl cluster-info

# 檢查 Prometheus
kubectl get pod -n ricplt -l app=prometheus,component=server

# 檢查 xApp
kubectl get pod -n ricxapp
```

---

## Small CL #7: 部署 Grafana

### 步驟 1: 準備配置文件

**文件位置**: `/home/thc1006/oran-ric-platform/config/grafana-values.yaml`

**關鍵配置**:
```yaml
# 管理員憑證
adminUser: admin
adminPassword: oran-ric-admin

# Prometheus 數據源（自動配置）
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://r4-infrastructure-prometheus-server.ricplt:80
      access: proxy
      isDefault: true

# 資源限制
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
```

### 步驟 2: 執行部署腳本

**腳本位置**: `/home/thc1006/oran-ric-platform/scripts/deployment/deploy-grafana.sh`

```bash
# 執行部署
sudo bash /home/thc1006/oran-ric-platform/scripts/deployment/deploy-grafana.sh
```

**部署過程**:
1. ✅ 檢查前置條件（kubectl, helm, Prometheus）
2. ✅ 添加 Grafana Helm repository
3. ✅ 使用 Helm 部署 Grafana
4. ✅ 等待 Pod 就緒
5. ✅ 驗證部署狀態
6. ✅ 測試 Grafana API
7. ✅ 測試 Prometheus 數據源連接

### 步驟 3: 驗證部署

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 檢查 Pod 狀態
kubectl get pod -n ricplt -l app.kubernetes.io/name=grafana

# 應該看到
# NAME                           READY   STATUS    RESTARTS   AGE
# oran-grafana-f6bb8ff8f-dfxmq   1/1     Running   0          10m

# 檢查 Service
kubectl get svc -n ricplt -l app.kubernetes.io/name=grafana

# 應該看到
# NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
# oran-grafana   ClusterIP   10.43.67.144   <none>        80/TCP    10m
```

### 部署結果

- **Pod 名稱**: `oran-grafana-f6bb8ff8f-dfxmq`
- **Namespace**: `ricplt`
- **Service**: `oran-grafana:80` (ClusterIP)
- **狀態**: Running ✅
- **管理員帳號**: `admin`
- **管理員密碼**: `oran-ric-admin`

---

## Small CL #8: 創建 Dashboard

### Dashboard 列表

我們創建了 6 個專業 Dashboard，涵蓋整體平台監控和每個 xApp 的詳細監控：

| Dashboard | 用途 | 面板數量 |
|-----------|------|---------|
| O-RAN RIC Platform Overview | 整體平台監控 | 10 |
| RC xApp - RAN Control Monitoring | RC xApp 詳細監控 | 10 |
| Traffic Steering xApp Monitoring | Traffic Steering 詳細監控 | 9 |
| QoE Predictor xApp Monitoring | QoE Predictor 詳細監控 | 10 |
| Federated Learning xApp Monitoring | Federated Learning 詳細監控 | 10 |
| KPIMON xApp Monitoring | KPIMON 詳細監控 | 9 |

### Dashboard 文件位置

所有 Dashboard JSON 配置文件位於：
```
/home/thc1006/oran-ric-platform/config/dashboards/
├── oran-ric-overview.json
├── rc-xapp-dashboard.json
├── traffic-steering-dashboard.json
├── qoe-predictor-dashboard.json
├── federated-learning-dashboard.json
└── kpimon-dashboard.json
```

### Dashboard 內容

#### 1. O-RAN RIC Platform Overview

**監控項目**:
- 所有 xApp 健康狀態（UP/DOWN）
- RC xApp 控制動作統計
- Traffic Steering 切換決策
- QoE Predictor 預測統計
- 所有 xApp 活躍 UE 數量
- Federated Learning 訓練進度
- KPIMON 網路吞吐量
- KPIMON PRB 使用率
- 所有 xApp CPU 使用情況
- 所有 xApp 記憶體使用情況

**用途**: 快速掌握整體平台健康狀況和關鍵指標

#### 2. RC xApp - RAN Control Monitoring

**監控項目**:
- RC xApp 狀態（Running/Down）
- 活躍 UE 數
- E2 連接數
- 控制動作成功率
- 控制動作統計（累計）
- 控制動作速率（每秒）
- 控制動作延遲（P50/P95/P99）
- E2 訊息統計
- CPU 使用率
- 記憶體使用量

**用途**: 深度監控 RC xApp 的控制行為和性能

#### 3. Traffic Steering xApp Monitoring

**監控項目**:
- Traffic Steering 狀態
- 活躍 UE 數
- 切換成功率
- 切換決策統計（累計）
- 切換速率（每秒）
- UE 吞吐量
- Cell 負載分佈
- 最佳化決策延遲
- 資源使用（CPU & 記憶體）

**用途**: 監控流量導向決策和切換行為

#### 4. QoE Predictor xApp Monitoring

**監控項目**:
- QoE Predictor 狀態
- 活躍 UE 數
- 預測準確度
- 品質劣化事件
- 預測統計（累計）
- 預測速率（每秒）
- 預測準確度趨勢
- UE QoE 分數分佈
- 預測延遲
- 資源使用（CPU & 記憶體）

**用途**: 監控 QoE 預測模型性能和準確度

#### 5. Federated Learning xApp Monitoring

**監控項目**:
- FL xApp 狀態
- 訓練輪次
- 模型準確度
- 活躍客戶端數
- 訓練進度（累計）
- 模型準確度趨勢
- 客戶端參與情況
- 模型更新統計
- 訓練延遲
- 資源使用（CPU & 記憶體）

**用途**: 監控聯邦學習訓練進度和模型性能

#### 6. KPIMON xApp Monitoring

**監控項目**:
- KPIMON 狀態
- 活躍 UE 數
- PRB 使用率
- 網路吞吐量（下行/上行）
- PRB 使用率趨勢
- 吞吐量速率變化
- Cell KPI 統計
- E2 訊息統計
- 資源使用（CPU & 記憶體）

**用途**: 監控網路 KPI 指標和資源使用

### 步驟 1: 導入 Dashboard

**腳本位置**: `/home/thc1006/oran-ric-platform/scripts/deployment/import-dashboards.sh`

```bash
# 執行導入腳本
bash /home/thc1006/oran-ric-platform/scripts/deployment/import-dashboards.sh
```

**導入結果**:
```
✅ O-RAN RIC Platform Overview 導入成功
   UID: 3b4709db-23df-443f-a51a-00310861e910

✅ RC xApp Monitoring 導入成功
   UID: 59ede010-bb03-4557-b167-e912c149e7f1

✅ Traffic Steering xApp 導入成功
   UID: 86d5aa36-fe28-41c3-be63-bd1d6081e11b

✅ QoE Predictor xApp 導入成功
   UID: 5e339788-e834-41f2-84b4-892ab7e408ae

✅ Federated Learning xApp 導入成功
   UID: eff351bf-14e5-4922-b3d8-d249d20d284c

✅ KPIMON xApp 導入成功
   UID: b4b4e83f-46ea-47ee-a4d0-ca96d9808444
```

### 步驟 2: 驗證 Dashboard

```bash
# 列出所有 Dashboard
curl -s -u admin:oran-ric-admin http://localhost:3000/api/search?type=dash-db | \
  jq '.[] | {title: .title, uid: .uid}'

# 驗證 Prometheus 數據源
curl -s -u admin:oran-ric-admin http://localhost:3000/api/datasources | \
  jq '.[] | {name: .name, type: .type, url: .url}'
```

---

## 訪問與使用

### 方式 1: 透過 Port-Forward（推薦）

```bash
# 啟動 Port-Forward
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl port-forward -n ricplt svc/oran-grafana 3000:80
```

然後在瀏覽器訪問：**http://localhost:3000**

### 方式 2: 在背景執行 Port-Forward

```bash
# 在背景啟動
nohup kubectl port-forward -n ricplt svc/oran-grafana 3000:80 > /tmp/grafana-pf.log 2>&1 &

# 查看日誌
tail -f /tmp/grafana-pf.log
```

### 登入資訊

- **URL**: http://localhost:3000
- **帳號**: `admin`
- **密碼**: `oran-ric-admin`

### 使用 Dashboard

1. **訪問 Overview Dashboard**:
   - 登入後，點擊左側選單 `Dashboards`
   - 選擇 `O-RAN RIC Platform Overview`
   - 即可看到所有 xApp 的整體狀況

2. **訪問特定 xApp Dashboard**:
   - 在 Dashboard 列表中選擇對應的 xApp Dashboard
   - 例如：`RC xApp - RAN Control Monitoring`

3. **調整時間範圍**:
   - 右上角選擇時間範圍（預設：最近 1 小時）
   - 可選擇：5m, 15m, 1h, 6h, 24h, 7d, 30d

4. **自動刷新**:
   - 右上角啟用自動刷新（預設：30 秒）
   - 可選擇：10s, 30s, 1m, 5m, 15m, 30m, 1h

### Dashboard 截圖說明

由於是文字文檔，這裡提供各 Dashboard 的視覺化說明：

**O-RAN RIC Platform Overview**:
```
┌────────────────────────────────────────────────────────┐
│ xApp 健康狀態                                           │
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐          │
│ │RC: UP│ │TS: UP│ │QoE:UP│ │FL: UP│ │KPI:UP│          │
│ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘          │
├────────────────────────────────────────────────────────┤
│ RC 控制動作  │ TS 切換決策  │ QoE 預測統計            │
│  [折線圖]   │  [折線圖]   │  [折線圖]              │
├────────────────────────────────────────────────────────┤
│ 所有 xApp 活躍 UE 數        │ FL 訓練進度           │
│  [多線圖]                   │  [折線圖]            │
├────────────────────────────────────────────────────────┤
│ KPIMON 網路吞吐量           │ KPIMON PRB 使用率     │
│  [折線圖]                   │  [儀表盤]            │
├────────────────────────────────────────────────────────┤
│ xApp CPU 使用情況          │ xApp 記憶體使用情況   │
│  [多線圖]                  │  [多線圖]            │
└────────────────────────────────────────────────────────┘
```

---

## 故障排除

### 問題 1: 無法訪問 Grafana UI

**症狀**: 瀏覽器無法打開 http://localhost:3000

**解決方案**:
```bash
# 1. 檢查 Port-Forward 是否運行
ps aux | grep "port-forward.*grafana"

# 2. 如果沒有，重新啟動
kubectl port-forward -n ricplt svc/oran-grafana 3000:80

# 3. 檢查 Grafana Pod 狀態
kubectl get pod -n ricplt -l app.kubernetes.io/name=grafana

# 4. 查看 Pod 日誌
kubectl logs -n ricplt $(kubectl get pod -n ricplt -l app.kubernetes.io/name=grafana -o name)
```

### 問題 2: Dashboard 沒有數據

**症狀**: Dashboard 面板顯示 "No Data"

**可能原因與解決方案**:

1. **Prometheus 未抓取 xApp metrics**:
   ```bash
   # 訪問 Prometheus UI
   kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80

   # 瀏覽器訪問 http://localhost:9090/targets
   # 檢查 xApp 是否在 "UP" 狀態
   ```

2. **xApp 尚未產生 metrics**:
   ```bash
   # 直接查詢 xApp metrics 端點
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   POD=$(kubectl get pod -n ricxapp -l app=ran-control -o name | head -1)
   kubectl exec -n ricxapp $POD -- wget -qO- http://localhost:8100/ric/v1/metrics
   ```

3. **時間範圍選擇不當**:
   - 調整 Dashboard 右上角的時間範圍
   - 嘗試選擇更長的時間範圍（例如：最近 24 小時）

### 問題 3: Dashboard 查詢錯誤

**症狀**: 面板顯示查詢錯誤

**解決方案**:
```bash
# 1. 檢查 Prometheus 數據源配置
curl -s -u admin:oran-ric-admin http://localhost:3000/api/datasources | jq '.'

# 2. 測試 Prometheus 連接
curl -s http://r4-infrastructure-prometheus-server.ricplt:80/api/v1/status/config

# 3. 驗證 metric 是否存在
curl -s 'http://r4-infrastructure-prometheus-server.ricplt:80/api/v1/query?query=up' | jq '.'
```

### 問題 4: 忘記管理員密碼

**解決方案**:
```bash
# 從 Kubernetes Secret 獲取密碼
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get secret -n ricplt oran-grafana -o jsonpath='{.data.admin-password}' | base64 --decode
echo
```

預設密碼: `oran-ric-admin`

### 問題 5: Port-Forward 意外中斷

**症狀**: 正在使用時連接突然中斷

**解決方案**:
```bash
# 方案 1: 重新啟動 Port-Forward
kubectl port-forward -n ricplt svc/oran-grafana 3000:80

# 方案 2: 使用 systemd service（生產環境推薦）
sudo tee /etc/systemd/system/grafana-port-forward.service > /dev/null <<'EOF'
[Unit]
Description=Grafana Port Forward
After=network.target

[Service]
Type=simple
User=root
Environment="KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
ExecStart=/usr/local/bin/kubectl port-forward -n ricplt svc/oran-grafana 3000:80
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable grafana-port-forward
sudo systemctl start grafana-port-forward
```

---

## 下一步

### Small CL #9: 配置告警規則（2 週內完成）

Small CL #7 和 #8 已完成，接下來的工作是 Small CL #9：

1. **創建 Prometheus 告警規則**:
   - xApp Down 告警
   - 高 CPU/記憶體使用告警
   - 控制動作失敗率告警
   - QoE 劣化告警
   - 網路吞吐量異常告警

2. **配置 AlertManager 通知**:
   - Email 通知
   - Webhook 通知（可選）
   - 告警分組與抑制規則

3. **驗證告警系統**:
   - 觸發測試告警
   - 驗證通知送達
   - 調整告警閾值

### 生產環境優化建議

1. **啟用持久化儲存**:
   ```yaml
   # grafana-values.yaml
   persistence:
     enabled: true
     size: 10Gi
     storageClassName: local-path  # 根據你的環境調整
   ```

2. **配置 Ingress** (取代 Port-Forward):
   ```yaml
   ingress:
     enabled: true
     hosts:
       - grafana.oran-ric.local
   ```

3. **設定 HTTPS**:
   ```yaml
   grafana.ini:
     server:
       protocol: https
       cert_file: /etc/grafana/ssl/tls.crt
       cert_key: /etc/grafana/ssl/tls.key
   ```

4. **配置 LDAP/OAuth 認證** (企業環境):
   ```yaml
   grafana.ini:
     auth.ldap:
       enabled: true
       config_file: /etc/grafana/ldap.toml
   ```

5. **設定自動備份**:
   - 定期匯出 Dashboard JSON
   - 備份 Grafana 資料庫
   - 版本控制 Dashboard 配置

### 進階功能

1. **創建更多 Dashboard**:
   - E2 訊息追蹤 Dashboard
   - RAN 效能總覽 Dashboard
   - UE 行為分析 Dashboard

2. **設定 Dashboard 變數**:
   - 動態選擇 xApp
   - 動態選擇 Cell ID
   - 動態選擇 UE ID

3. **配置告警通知通道**:
   - Slack
   - Microsoft Teams
   - PagerDuty

---

## 附錄

### A. 文件與腳本清單

**配置文件**:
```
/home/thc1006/oran-ric-platform/config/
├── grafana-values.yaml
└── dashboards/
    ├── oran-ric-overview.json
    ├── rc-xapp-dashboard.json
    ├── traffic-steering-dashboard.json
    ├── qoe-predictor-dashboard.json
    ├── federated-learning-dashboard.json
    └── kpimon-dashboard.json
```

**部署腳本**:
```
/home/thc1006/oran-ric-platform/scripts/deployment/
├── deploy-grafana.sh
└── import-dashboards.sh
```

**文檔**:
```
/home/thc1006/oran-ric-platform/docs/
├── deployment-guides/
│   └── grafana-dashboard-部署指南.md (本文件)
└── user-guides/
    └── prometheus-ui-操作手冊.md
```

### B. 快速參考命令

```bash
# ============================================
# Grafana 管理
# ============================================

# 檢查 Grafana 狀態
kubectl get pod -n ricplt -l app.kubernetes.io/name=grafana

# 查看 Grafana 日誌
kubectl logs -n ricplt -l app.kubernetes.io/name=grafana -f

# 重啟 Grafana
kubectl rollout restart deployment -n ricplt oran-grafana

# 獲取管理員密碼
kubectl get secret -n ricplt oran-grafana -o jsonpath='{.data.admin-password}' | base64 --decode

# 啟動 Port-Forward
kubectl port-forward -n ricplt svc/oran-grafana 3000:80

# ============================================
# Dashboard 管理
# ============================================

# 列出所有 Dashboard
curl -s -u admin:oran-ric-admin http://localhost:3000/api/search?type=dash-db | jq '.[] | .title'

# 匯出 Dashboard
curl -s -u admin:oran-ric-admin http://localhost:3000/api/dashboards/uid/<UID> | jq '.dashboard' > dashboard.json

# 導入 Dashboard
curl -X POST -H "Content-Type: application/json" -u admin:oran-ric-admin \
  -d @dashboard.json http://localhost:3000/api/dashboards/db

# ============================================
# Prometheus 相關
# ============================================

# 檢查 Prometheus 狀態
kubectl get pod -n ricplt -l app=prometheus,component=server

# 啟動 Prometheus Port-Forward
kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80

# 測試 Prometheus 查詢
curl -s 'http://localhost:9090/api/v1/query?query=up{kubernetes_namespace="ricxapp"}' | jq '.'

# ============================================
# 故障排除
# ============================================

# 檢查所有相關 Pod
kubectl get pod -n ricplt -o wide

# 檢查所有相關 Service
kubectl get svc -n ricplt

# 查看事件
kubectl get events -n ricplt --sort-by='.lastTimestamp'

# 描述 Grafana Deployment
kubectl describe deployment -n ricplt oran-grafana
```

### C. PromQL 查詢範例

這些查詢可以直接在 Grafana Dashboard 中使用：

```promql
# ============================================
# 基本查詢
# ============================================

# 所有 xApp 狀態
up{kubernetes_namespace="ricxapp"}

# RC xApp 控制動作總數
rc_control_actions_sent_total

# Traffic Steering 活躍 UE
ts_active_ues

# QoE Predictor 預測總數
qoe_predictions_total

# ============================================
# 速率計算
# ============================================

# RC 控制動作每秒速率
rate(rc_control_actions_sent_total[5m])

# Traffic Steering 切換每秒速率
rate(ts_handover_triggered_total[5m])

# KPIMON 訊息接收速率
rate(kpimon_e2_messages_received_total[5m])

# ============================================
# 成功率計算
# ============================================

# RC 控制動作成功率 (%)
(rc_control_actions_success_total / rc_control_actions_sent_total) * 100

# Traffic Steering 切換成功率 (%)
(ts_handover_triggered_total / ts_handover_decisions_total) * 100

# ============================================
# 資源使用
# ============================================

# xApp CPU 使用率 (%)
rate(process_cpu_seconds_total{kubernetes_namespace="ricxapp"}[5m]) * 100

# xApp 記憶體使用 (MB)
process_resident_memory_bytes{kubernetes_namespace="ricxapp"} / 1024 / 1024

# ============================================
# 聚合查詢
# ============================================

# 所有 xApp 總 CPU 使用率
sum(rate(process_cpu_seconds_total{kubernetes_namespace="ricxapp"}[5m])) * 100

# 各 xApp 平均記憶體使用
avg by (app) (process_resident_memory_bytes{kubernetes_namespace="ricxapp"})

# 總活躍 UE 數
sum(rc_active_ues + ts_active_ues + qoe_active_ues + kpimon_active_ues)
```

### D. Dashboard JSON 結構說明

Grafana Dashboard JSON 的基本結構：

```json
{
  "dashboard": {
    "title": "Dashboard 標題",
    "tags": ["標籤1", "標籤2"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "面板標題",
        "type": "graph",  // graph, stat, gauge, table 等
        "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8},
        "targets": [
          {
            "expr": "PromQL 查詢語句",
            "legendFormat": "{{label}}",
            "refId": "A"
          }
        ]
      }
    ],
    "refresh": "30s",
    "time": {
      "from": "now-1h",
      "to": "now"
    }
  },
  "overwrite": true
}
```

---

## 總結

我們已成功完成 Small CL #7 和 #8：

✅ **Small CL #7: 部署 Grafana**
- Grafana 運行在 ricplt namespace
- 自動配置 Prometheus 數據源
- 管理員帳號可正常登入

✅ **Small CL #8: 創建 Dashboard**
- 6 個專業 Dashboard 已導入
- 涵蓋整體平台和各個 xApp
- 所有面板正常顯示數據

**當前狀態**: 監控系統已可投入使用

**訪問方式**:
1. 啟動 Port-Forward: `kubectl port-forward -n ricplt svc/oran-grafana 3000:80`
2. 瀏覽器訪問: http://localhost:3000
3. 登入: admin / oran-ric-admin

**下一階段**: Small CL #9 - 配置告警規則（2 週內完成）

---

**作者**: 蔡秀吉 (thc1006)
**最後更新**: 2025-11-15
**版本**: 1.0.0
