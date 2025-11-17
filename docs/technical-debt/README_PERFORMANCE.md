# O-RAN RIC Platform 效能優化指南

**作者：** 蔡秀吉 (thc1006)
**最後更新：** 2025-11-17

---

## 📚 文檔概覽

本目錄包含 O-RAN RIC Platform 的完整效能分析與優化指南：

### 主要文檔

1. **[PERFORMANCE_ANALYSIS.md](./PERFORMANCE_ANALYSIS.md)** - 完整效能分析報告
   - 資源配置分析
   - 效能基準測試
   - 瓶頸識別
   - 優化建議（短期、中期、長期）
   - 容量規劃
   - 成本效益分析

2. **[/config/optimized-values.yaml](/home/thc1006/oran-ric-platform/config/optimized-values.yaml)** - 優化後的配置檔案
   - 實作 Quick Wins 優化
   - 可直接用於部署

3. **[/scripts/performance-test.sh](/home/thc1006/oran-ric-platform/scripts/performance-test.sh)** - 效能測試腳本
   - 自動化效能測試
   - 生成詳細報告

---

## 🚀 快速開始

### 1. 查看效能分析報告

```bash
cd /home/thc1006/oran-ric-platform/docs/technical-debt
cat PERFORMANCE_ANALYSIS.md
```

報告包含：
- ✅ 10 個關鍵效能問題識別
- ✅ 3 個優先級別的優化建議（🔴 Critical, 🟡 High, 🟢 Medium）
- ✅ 具體的配置修改範例
- ✅ 預期效能提升指標
- ✅ 30 天實施計畫

### 2. 執行效能測試（當前狀態基準）

在套用優化前，先建立效能基準：

```bash
cd /home/thc1006/oran-ric-platform

# 執行效能測試
./scripts/performance-test.sh

# 查看報告
ls -lt performance-test-reports/
cat performance-test-reports/performance-test-<timestamp>.md
```

測試項目：
- ✅ 資源使用率分析（CPU, Memory）
- ✅ Pod 健康狀態檢查
- ✅ Redis 效能測試
- ✅ Prometheus metrics 驗證
- ✅ 網路效能
- ✅ 儲存效能

### 3. 套用優化配置

#### 方案 A: 完整優化（建議）

```bash
# 備份當前配置
cp platform/values/local.yaml platform/values/local.yaml.backup

# 套用優化配置
helm upgrade ric-platform ./ric-dep/helm/ric-platform \
  -n ricplt \
  -f config/optimized-values.yaml

# 重啟 platform components
kubectl rollout restart deployment -n ricplt

# 等待 pods 就緒
kubectl wait --for=condition=ready pod -l app=e2term -n ricplt --timeout=300s
kubectl wait --for=condition=ready pod -l app=e2mgr -n ricplt --timeout=300s
```

#### 方案 B: 逐步優化（保守）

**Step 1: 調整關鍵資源配置（Week 1）**

```bash
# 只修改 E2term 和 submgr 資源
kubectl patch deployment e2term -n ricplt -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "e2term",
          "resources": {
            "requests": {"cpu": "800m", "memory": "1Gi"},
            "limits": {"cpu": "1500m", "memory": "2Gi"}
          }
        }]
      }
    }
  }
}'

kubectl patch deployment submgr -n ricplt -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "submgr",
          "resources": {
            "requests": {"cpu": "200m", "memory": "256Mi"},
            "limits": {"cpu": "400m", "memory": "512Mi"}
          }
        }]
      }
    }
  }
}'
```

**Step 2: 啟用 Redis HA（Week 2）**

```bash
# 修改 DBaaS 配置
helm upgrade dbaas ./ric-dep/helm/dbaas \
  -n ricplt \
  --set enableHighAvailability=true \
  --set haReplicas=3 \
  --set redis.ha_config.appendonly=yes \
  --set redis.ha_config.maxmemory=768mb
```

**Step 3: 優化 Prometheus（Week 3）**

```bash
helm upgrade r4-infrastructure-prometheus \
  ./ric-dep/helm/infrastructure/subcharts/prometheus \
  -n ricplt \
  --set server.global.scrape_interval=15s \
  --set server.retention=30d \
  --set server.persistentVolume.enabled=true \
  --set server.persistentVolume.size=50Gi
```

### 4. 驗證優化效果

```bash
# 執行效能測試（優化後）
./scripts/performance-test.sh

# 比較優化前後的報告
diff performance-test-reports/performance-test-<before>.md \
     performance-test-reports/performance-test-<after>.md
```

**預期改善：**
- E2 indication 延遲降低：30-40%
- CPU throttling 事件降低：50-70%
- Redis 可用性：99.9% (HA 模式)
- Metrics 解析度提升：4x (15s vs 1m)

---

## 📊 效能指標監控

### 關鍵效能指標 (KPIs)

使用 Prometheus 查詢以下指標：

```promql
# E2 indication 處理延遲 (P99)
histogram_quantile(0.99,
  rate(e2_indication_duration_seconds_bucket[5m])
)

# CPU throttling 事件
rate(container_cpu_cfs_throttled_seconds_total{
  namespace=~"ricplt|ricxapp"
}[5m])

# Memory 使用率
container_memory_working_set_bytes{namespace=~"ricplt|ricxapp"} /
container_spec_memory_limit_bytes * 100

# Pod restart 次數
kube_pod_container_status_restarts_total{
  namespace=~"ricplt|ricxapp"
}
```

### Grafana Dashboards

建立以下 dashboards 來監控效能：

1. **RIC Platform Overview**
   - 整體健康狀態
   - 資源使用率
   - 關鍵 metrics

2. **E2 Interface Performance**
   - Indication 處理延遲
   - Control 命令延遲
   - 訊息吞吐量

3. **xApp Performance**
   - CPU/Memory 使用率
   - RMR 訊息處理
   - 錯誤率

---

## 🔧 進階優化

### 實作多層快取（Month 2）

參考 [PERFORMANCE_ANALYSIS.md](./PERFORMANCE_ANALYSIS.md) 第 5.2.1 節：

1. Layer 1: Application Cache (In-memory)
2. Layer 2: Distributed Cache (Redis)
3. Layer 3: Time-series DB (InfluxDB)

### 部署 Jaeger 分散式追蹤（Month 2）

```bash
# 安裝 Jaeger
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm install jaeger jaegertracing/jaeger \
  --namespace ricobs --create-namespace \
  --set provisionDataStore.cassandra=false \
  --set storage.type=memory

# Port-forward 存取 Jaeger UI
kubectl port-forward -n ricobs svc/jaeger-query 16686:16686

# 開啟瀏覽器
# http://localhost:16686
```

### 啟用 Service Mesh (Month 3-6)

```bash
# 安裝 Linkerd
curl -sL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# 安裝 control plane
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -

# Inject Linkerd proxy
kubectl get deploy -n ricplt -o yaml | linkerd inject - | kubectl apply -f -
kubectl get deploy -n ricxapp -o yaml | linkerd inject - | kubectl apply -f -

# 驗證
linkerd check
```

---

## 📈 容量規劃

### 支援 50 個 E2 Nodes 的資源需求

根據分析報告第 7 節，以下是建議配置：

**E2term:**
```yaml
replicas: 2
resources:
  requests:
    cpu: 1500m
    memory: 1.5Gi
  limits:
    cpu: 3000m
    memory: 3Gi
```

**KPIMON xApp:**
```yaml
replicas: 2
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi
```

**Redis (HA):**
```yaml
replicas: 3
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 1Gi
persistence:
  size: 20Gi
```

**InfluxDB:**
```yaml
persistence:
  size: 2Ti  # 7 days retention for 50 E2 nodes
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 4Gi
```

### 硬體需求估算

**測試環境（5-10 E2 nodes）:**
- 1x c5.xlarge: 4 vCPU, 8 GB RAM
- 成本：~$100/month

**開發環境（20-30 E2 nodes）:**
- 2x c5.2xlarge: 8 vCPU, 16 GB RAM each
- 成本：~$400/month

**生產環境（50+ E2 nodes）:**
- 1x c5.2xlarge (master): $200/month
- 2x c5.4xlarge (workers): $800/month
- 1x r5.xlarge (observability): $250/month
- **總計：$1,250/month**

---

## ⚠️  常見問題 (Troubleshooting)

### Q1: 套用優化配置後 pods 無法啟動

**症狀：** Pods stuck in Pending state

**解決方式：**
```bash
# 檢查資源不足
kubectl describe pod <pod-name> -n ricplt

# 檢查節點資源
kubectl top nodes

# 如果資源不足，降低 resource requests
kubectl edit deployment <deployment-name> -n ricplt
```

### Q2: Redis failover 時間過長

**症狀：** Sentinel 偵測到 master down 但未自動切換

**解決方式：**
```bash
# 檢查 Sentinel 配置
kubectl exec -n ricplt <redis-sentinel-pod> -- redis-cli -p 26379 SENTINEL masters

# 調整 down-after-milliseconds
kubectl exec -n ricplt <redis-sentinel-pod> -- \
  redis-cli -p 26379 SENTINEL SET dbaasmaster down-after-milliseconds 3000
```

### Q3: Prometheus 佔用過多儲存空間

**症狀：** PVC 容量不足

**解決方式：**
```bash
# 檢查當前使用量
kubectl exec -n ricplt <prometheus-pod> -- df -h /data

# 縮短 retention
kubectl exec -n ricplt <prometheus-pod> -- \
  wget --post-data='' http://localhost:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~".+"}

# 或擴展 PVC
kubectl patch pvc <pvc-name> -n ricplt -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

### Q4: CPU throttling 仍然嚴重

**症狀：** 高 throttling rate 即使提升了 limits

**解決方式：**
```bash
# 檢查實際 CPU 使用量
kubectl top pod <pod-name> -n ricplt

# 如果使用量接近 limit，表示需要更多 CPU
# 將 limits 設定為 requests 的 1.5-2 倍（而非 2.5-5 倍）

# Example:
requests.cpu: 800m
limits.cpu: 1200m  # 1.5x（而非 2000m）
```

---

## 📝 30 天實施計畫

完整的實施計畫請參考 [PERFORMANCE_ANALYSIS.md](./PERFORMANCE_ANALYSIS.md) 第 10.2 節。

**簡要版本：**

- **Week 1:** 資源配置調整 + RMR workers 優化
- **Week 2:** Redis HA + 持久化
- **Week 3:** Prometheus 優化 + Jaeger 部署
- **Week 4:** 測試與驗證
- **Month 2+:** Multi-tier caching, E2 batching, Service Mesh

---

## 📞 支援與貢獻

如有問題或建議，請聯繫：

- **作者：** 蔡秀吉 (thc1006)
- **專案：** O-RAN RIC Platform
- **文檔版本：** 1.0

---

## 📚 延伸閱讀

### O-RAN Specifications
- [O-RAN.WG3.E2AP-v03.00](https://www.o-ran.org/specifications) - E2 Application Protocol
- [O-RAN.WG3.E2SM-KPM-v03.00](https://www.o-ran.org/specifications) - KPM Service Model

### Kubernetes Performance
- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Configure Quality of Service](https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/)
- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

### Redis
- [Redis High Availability](https://redis.io/docs/management/sentinel/)
- [Redis Persistence](https://redis.io/docs/management/persistence/)
- [Redis Performance Tuning](https://redis.io/docs/management/optimization/)

### Observability
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [OpenTelemetry](https://opentelemetry.io/docs/)
- [Jaeger Tracing](https://www.jaegertracing.io/docs/)

---

**Last Updated:** 2025-11-17
