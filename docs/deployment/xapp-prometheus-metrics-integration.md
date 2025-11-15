# O-RAN RIC xApps Prometheus Metrics 整合部署指南

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-15
**版本**: 1.0.0

## 概述

本文檔記錄了為 O-RAN RIC Platform 上的 xApps 整合 Prometheus metrics 監控系統的完整部署過程。這是一個循序漸進的實作，包含了所有遇到的技術挑戰、除錯過程，以及最終的解決方案。

### 目標

1. 為所有 xApps 添加 HTTP endpoints 以接收 E2 Simulator 測試流量
2. 整合 Prometheus metrics 並確保 Grafana 能夠顯示動態數據
3. 建立完整的監控和告警規則
4. 確保自動化測試基礎設施正常運作

### 架構概覽

```
E2 Simulator → xApps (HTTP/RMR) → Prometheus → Grafana
```

## 階段一：KPIMON Service 配置暴露端口 8081

### 背景

KPIMON xApp 需要透過 HTTP endpoint 接收來自 E2 Simulator 的測試數據。最初的 Service 配置只暴露了 RMR 數據端口 (4560) 和 Prometheus metrics 端口 (8080)，缺少 Flask HTTP API 端口。

### 實作步驟

1. **檢查現有配置**

```bash
kubectl get svc -n ricxapp kpimon -o yaml
```

2. **更新 Service 配置**

編輯檔案：`/home/thc1006/oran-ric-platform/xapps/kpimon-go-xapp/deploy/service.yaml`

添加端口 8081：

```yaml
ports:
- name: rmr-data
  port: 4560
  targetPort: 4560
  protocol: TCP
- name: http-metrics
  port: 8080
  targetPort: 8080
  protocol: TCP
- name: http-api           # 新增
  port: 8081
  targetPort: 8081
  protocol: TCP
```

3. **應用配置**

```bash
kubectl apply -f xapps/kpimon-go-xapp/deploy/service.yaml
```

4. **驗證**

```bash
kubectl get svc -n ricxapp kpimon
# 應該顯示: 4560/TCP,8080/TCP,8081/TCP
```

### 測試

從 E2 Simulator 測試連接：

```bash
kubectl exec -n ricxapp e2-simulator-xxx -- curl -X POST http://kpimon.ricxapp.svc.cluster.local:8081/e2/indication
```

✅ **結果**: HTTP 200 OK

## 階段二：為其他 xApps 添加 HTTP Endpoints

### Traffic Steering xApp

#### 遇到的問題與解決

**問題 1: SDL Wrapper API 錯誤**

```
SDLWrapper.set() missing 1 required positional argument: 'value'
```

**原因分析**:
在 `/e2/indication` endpoint 中，SDL API 調用方式不正確，導致 Pod 不斷重啟。

**解決方案**:

在 `traffic_steering.py` 中添加 try-except 錯誤處理：

```python
# 文件位置: xapps/traffic-steering/src/traffic_steering.py:275-282

try:
    self.sdl.set(
        self.namespace,
        {f"ue_metrics:{ue_metrics.ue_id}": json.dumps(data)}
    )
except Exception as sdl_err:
    logger.debug(f"SDL storage failed (non-critical): {sdl_err}")
```

**問題 2: Readiness Probe 失敗**

```
Readiness probe failed: dial tcp 10.42.0.x:8080: connect: connection refused
```

**原因分析**:
Flask 應用已經遷移到端口 8081，但 deployment.yaml 中的 readiness probe 仍然檢查端口 8080。

**解決方案**:

更新 `deployment.yaml` 配置：

```yaml
# 文件位置: xapps/traffic-steering/deploy/deployment.yaml

annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8081"      # 從 8080 改為 8081
  prometheus.io/path: "/ric/v1/metrics"

ports:
- name: http-api
  containerPort: 8081              # 從 8080 改為 8081

livenessProbe:
  httpGet:
    path: /ric/v1/health/alive
    port: 8081                     # 從 8080 改為 8081

readinessProbe:
  httpGet:
    path: /ric/v1/health/ready
    port: 8081                     # 從 8080 改為 8081
```

**版本管理**:
- v1.0.0: 初始版本
- v1.0.1: 添加 SDL 錯誤處理
- v1.0.2: 修復端口配置問題（最終穩定版本）

### QoE Predictor xApp

實作相對順利，只需添加 `/e2/indication` endpoint。

```python
# 文件位置: xapps/qoe-predictor/src/qoe_predictor.py

@self.app.route('/e2/indication', methods=['POST'])
def e2_indication():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No data provided"}), 400

        self._handle_qoe_metrics(data)

        return jsonify({
            "status": "success",
            "message": "QoE metrics processed"
        }), 200
    except Exception as e:
        logger.error(f"Error processing QoE metrics: {e}")
        return jsonify({"error": str(e)}), 500
```

- Port: 8090
- 版本: v1.0.1

### RAN Control (RC) xApp

同樣添加 `/e2/indication` endpoint。

- Port: 8100
- 版本: v1.0.1

## 階段三：驗證 Grafana Dashboards 顯示動態數據

### 子階段 3.1: E2 Simulator 配置錯誤

**問題發現**:
KPIMON metrics 一直顯示 0，即使 E2 Simulator 已經運行超過 1800 次迭代。

**troubleshooting 過程**:

1. 檢查 E2 Simulator 日誌
2. 檢查 xApp Service 配置
3. 檢查端口映射

**根本原因**:
E2 Simulator 配置檔案中的端口設定錯誤：

```python
# 錯誤配置 (e2_simulator.py:44-53)
'qoe-predictor': {
    'port': 8091,  # 應該是 8090
}
'ran-control': {
    'port': 8101,  # 應該是 8100
}
```

**解決方案**:

修正端口配置：

```python
'qoe-predictor': {
    'host': 'qoe-predictor.ricxapp.svc.cluster.local',
    'port': 8090,  # 正確
    'endpoint': '/e2/indication'
},
'ran-control': {
    'host': 'ran-control.ricxapp.svc.cluster.local',
    'port': 8100,  # 正確
    'endpoint': '/e2/indication'
}
```

### 子階段 3.2: KPIMON Metrics 不遞增

**問題發現**:
雖然 E2 Simulator 成功發送數據到 KPIMON（日誌顯示 processing），但 Prometheus counters 保持在 0。

**根本原因**:
`/e2/indication` endpoint 沒有遞增 Prometheus counters。

**解決方案**:

在 `kpimon.py` 的 `/e2/indication` handler 中添加 counter 遞增：

```python
# 文件位置: xapps/kpimon-go-xapp/src/kpimon.py:162-186

@self.flask_app.route('/e2/indication', methods=['POST'])
def e2_indication():
    try:
        # 遞增接收計數器
        MESSAGES_RECEIVED.inc()

        data = request.get_json()
        if not data:
            return jsonify({"error": "No data provided"}), 400

        # 處理數據
        self._handle_indication(json.dumps(data))

        # 遞增處理計數器
        MESSAGES_PROCESSED.inc()

        return jsonify({
            "status": "success",
            "message": "Indication processed"
        }), 200
    except Exception as e:
        logger.error(f"Error processing E2 indication: {e}")
        return jsonify({"error": str(e)}), 500
```

**驗證**:

```bash
# 檢查 metrics
kubectl exec -n ricxapp kpimon-xxx -- curl http://localhost:8080/ric/v1/metrics | grep kpimon_messages

# 結果:
kpimon_messages_received_total 54.0
kpimon_messages_processed_total 54.0
```

✅ **Metrics 開始正常遞增**

### 子階段 3.3: Prometheus Scraping 驗證

訪問 Prometheus UI 驗證 targets：

```bash
kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80
```

訪問 http://localhost:9090/targets

✅ **確認所有 xApp targets 狀態為 UP**

### 子階段 3.4: Grafana Dashboard 驗證

通過 Prometheus UI 手動查詢確認數據正確：

```promql
kpimon_messages_received_total
kpimon_messages_processed_total
rate(kpimon_messages_received_total[5m])
```

✅ **確認 Grafana 能夠成功查詢 Prometheus metrics**

## 階段四：創建 Prometheus 告警規則

創建全面的告警規則檔案。

### 實作

文件位置：`/home/thc1006/oran-ric-platform/monitoring/prometheus/alerts/xapp-alerts.yml`

告警規則涵蓋 8 個類別：

1. **xApp Availability** - xApp 可用性監控
2. **KPIMON Alerts** - KPIMON 專屬告警
3. **Traffic Steering Alerts** - Traffic Steering 告警
4. **QoE Predictor Alerts** - QoE 預測告警
5. **RAN Control Alerts** - RAN 控制告警
6. **xApp Resource Usage** - 資源使用告警
7. **E2 Interface Alerts** - E2 介面告警
8. **Federated Learning Alerts** - 聯邦學習告警

### 告警規則範例

```yaml
groups:
  - name: kpimon_alerts
    interval: 30s
    rules:
      - alert: KPIMONMessageProcessingStalled
        expr: rate(kpimon_messages_received_total[5m]) == 0 and kpimon_messages_received_total > 0
        for: 5m
        labels:
          severity: critical
          component: kpimon
        annotations:
          summary: "KPIMON message processing has stalled"
          description: "KPIMON has not received any new messages in the last 5 minutes, but has received messages before. This may indicate E2 connection issues."
```

### 部署步驟

1. 備份現有 Prometheus ConfigMap

```bash
kubectl get configmap r4-infrastructure-prometheus-server -n ricplt -o yaml > monitoring/prometheus/prometheus-server-configmap-backup.yaml
```

2. 更新 Prometheus ConfigMap

```bash
kubectl create configmap r4-infrastructure-prometheus-server \
  --from-file=alerting_rules.yml=monitoring/prometheus/alerts/xapp-alerts.yml \
  --from-file=prometheus.yml=monitoring/prometheus/prometheus.yml \
  --dry-run=client -o yaml | kubectl apply -n ricplt -f -
```

3. 重啟 Prometheus Pod

```bash
kubectl delete pod -n ricplt -l app=prometheus,component=server
```

4. 驗證規則已載入

```bash
# 檢查 Pod 日誌
kubectl logs -n ricplt -l app=prometheus,component=server | grep -i "rule"

# 訪問 Prometheus UI
# http://localhost:9090/alerts
```

✅ **告警規則成功載入並生效**

## 階段五：修復 Grafana 自動化測試

### 問題描述

Playwright E2E 測試失敗，錯誤訊息：

```
Missing X server or $DISPLAY

Looks like you launched a headed browser without having a XServer running.
Set either 'headless: true' or use 'xvfb-run <your-playwright-app>' before running Playwright.
```

### 問題分析

雖然 `playwright.config.js` 已經設定 `headless: true`，但 Chromium 仍然嘗試初始化 X11 平台：

```
ERROR:ui/ozone/platform/x11/ozone_platform_x11.cc:249] Missing X server or $DISPLAY
ERROR:ui/aura/env.cc:257] The platform failed to initialize.  Exiting.
```

**根本原因**:
Chromium 的舊版 headless 模式仍然需要 X11 平台初始化，但測試環境是無圖形介面的 Linux 伺服器。

### 解決方案

使用 Chromium 的**新版 headless 模式**（完全不需要 X server）。

更新 `playwright.config.js` 配置：

```javascript
// 文件位置: playwright.config.js:56-75

projects: [
  {
    name: 'chromium',
    use: {
      ...devices['Desktop Chrome'],
      viewport: { width: 1920, height: 1080 },
      // 添加 launch options
      launchOptions: {
        args: [
          '--headless=new',  // 使用新的 headless 模式
          '--no-sandbox',
          '--disable-setuid-sandbox',
          '--disable-dev-shm-usage',
          '--disable-gpu'
        ]
      }
    },
  },
]
```

### 測試結果

```bash
npm run test:grafana
```

輸出：

```
Running 6 tests using 1 worker

Testing dashboard: O-RAN RIC Platform Overview
Screenshot saved: test-results/screenshots/f7bd02b0-2c34-427c-988c-db6364ef6cc9-full.png
...

✓  6 passed (1.0m)
```

✅ **所有 6 個 dashboard 測試全部通過**

### 測試報告

自動生成的測試報告位於：
- JSON: `test-results/reports/grafana-metrics-verification-*.json`
- Markdown: `test-results/reports/grafana-metrics-summary-*.md`
- 截圖: `test-results/screenshots/*.png`

## 部署總結

### 成功部署的組件

| 組件 | 版本 | 狀態 | 端口 |
|------|------|------|------|
| KPIMON | v1.0.1 | ✅ Running | 8080, 8081 |
| Traffic Steering | v1.0.2 | ✅ Running | 8081 |
| QoE Predictor | v1.0.1 | ✅ Running | 8090 |
| RAN Control | v1.0.1 | ✅ Running | 8100 |
| Federated Learning | v1.0.0 | ✅ Running | 8110 |
| E2 Simulator | v1.0.0 | ✅ Running | - |

### Metrics Pipeline 驗證

```
E2 Simulator → xApps → Prometheus → Grafana
     ✅           ✅        ✅         ✅
```

### 關鍵學習

1. **端口配置一致性至關重要**
   Service、Deployment、Prometheus annotations 必須使用相同端口。

2. **錯誤處理必須完善**
   特別是 SDL 等外部服務調用，要用 try-except 包裹避免 Pod 重啟。

3. **版本管理很重要**
   每次變更都應該更新版本號，方便追蹤和回滾。

4. **測試自動化需要適配環境**
   無圖形介面環境必須使用新版 headless 模式。

5. **Prometheus Counter 必須明確遞增**
   不會自動遞增，必須在代碼中顯式調用 `.inc()`。

## 後續維護建議

### 監控

定期檢查：
- Prometheus Targets: `http://localhost:9090/targets`
- Alert Rules: `http://localhost:9090/alerts`
- Grafana Dashboards: `http://localhost:3000`

### 日誌

查看 xApp 日誌：

```bash
kubectl logs -f -n ricxapp <pod-name>
```

### 擴展

添加新的 metrics：

1. 在 xApp 中定義 Prometheus metric
2. 在業務邏輯中遞增/設定 metric
3. 更新 Grafana dashboard
4. 添加對應的 alert rules

## 故障排除

### 常見問題

**問題**: Metrics 顯示 0

**檢查清單**:
- [ ] E2 Simulator 是否運行？
- [ ] xApp Service 端口配置是否正確？
- [ ] xApp 代碼是否遞增 counter？
- [ ] Prometheus 是否成功 scrape？

**問題**: Pod 不斷重啟

**檢查清單**:
- [ ] Readiness probe 端口是否正確？
- [ ] 是否有未捕獲的異常？
- [ ] 資源限制是否足夠？

## 參考資料

- Prometheus 文檔: https://prometheus.io/docs/
- Playwright 文檔: https://playwright.dev/
- O-RAN SC RIC Platform: https://wiki.o-ran-sc.org/

---

**文檔版本**: 1.0.0
**最後更新**: 2025-11-15
**維護者**: 蔡秀吉 (thc1006)
