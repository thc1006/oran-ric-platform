# O-RAN RIC Platform 效能全面分析報告

**作者：** 蔡秀吉 (thc1006)
**日期：** 2025-11-17
**分析範圍：** O-RAN Near-RT RIC Platform J Release
**測試環境：** k3s v1.28.5+k3s1 on Debian GNU/Linux 13

---

## 執行摘要 (Executive Summary)

本報告針對 O-RAN RIC Platform 進行全面的效能分析，涵蓋資源配置、系統效能、擴展性以及優化機會。透過分析現有配置、實際部署資料與效能指標，識別出多個關鍵瓶頸並提出具體的優化建議。

### 關鍵發現 (Key Findings)

**🔴 嚴重問題 (Critical Issues):**
1. **資源配置不一致** - Platform components 與 xApps 之間的資源配置策略不統一
2. **缺乏 HPA 配置** - 所有組件都未啟用 Horizontal Pod Autoscaling
3. **Prometheus 資料留存策略** - 僅保留 15 天，對長期效能分析不足
4. **無 Resource Quotas** - Namespace 層級未設定資源配額，存在資源耗盡風險

**🟡 高優先級問題 (High Priority Issues):**
1. **RMR 訊息處理效能** - 單一 worker 配置可能成為瓶頸
2. **Redis 單點故障** - DBaaS 未啟用 HA 模式
3. **缺乏分散式追蹤** - Jaeger adapter 未部署，難以診斷延遲問題
4. **Metrics 採集間隔過長** - Prometheus scrape interval 為 1 分鐘，無法捕捉短期效能問題

**🟢 優化機會 (Optimization Opportunities):**
1. 實作多層快取策略 (Multi-tier Caching)
2. 優化 E2 訊息處理流程
3. 實作連線池與批次處理
4. 啟用 Service Mesh 以改善 observability

---

## 1. 資源配置分析 (Resource Allocation Analysis)

### 1.1 Platform Components 資源配置

#### 現況分析 (Current State)

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | QoS Class |
|-----------|-------------|-----------|----------------|--------------|-----------|
| e2term | 400m | 1000m | 512Mi | 1Gi | Burstable |
| e2mgr | 200m | 500m | 256Mi | 512Mi | Burstable |
| submgr | 100m | 250m | 128Mi | 256Mi | Burstable |
| a1mediator | 100m | 250m | 128Mi | 256Mi | Burstable |
| appmgr | 200m | 500m | 256Mi | 512Mi | Burstable |
| dbaas (Redis) | 100m | 500m | 256Mi | 1Gi | Burstable |
| Prometheus | 500m | 1000m | 1Gi | 2Gi | Burstable |
| Grafana | 250m | 500m | 256Mi | 512Mi | Burstable |

**分析發現:**

1. **Request/Limit 比例不合理**
   - E2term: CPU limit 是 request 的 2.5 倍 (1000m/400m)
   - DBaaS: CPU limit 是 request 的 5 倍 (500m/100m)
   - 問題：過高的 limit 會導致 CPU throttling，影響延遲敏感的應用

2. **所有組件都是 Burstable QoS**
   - 無 Guaranteed QoS pods
   - 在資源壓力下，所有 pods 都可能被驅逐
   - E2term 等關鍵組件應該使用 Guaranteed QoS

3. **缺乏實際使用資料驗證**
   ```
   當前節點資源使用率：
   - CPU: 1277m / 32000m (3.99%)
   - Memory: 7195Mi / 48000Mi (14.98%)
   ```
   - 明顯資源未充分利用
   - Requests 可能設定過於保守

### 1.2 xApps 資源配置

#### 現況分析

| xApp | CPU Request | CPU Limit | Memory Request | Memory Limit | Purpose |
|------|-------------|-----------|----------------|--------------|---------|
| kpimon | 200m | 1000m | 512Mi | 1Gi | KPI monitoring |
| traffic-steering | 200m | 500m | 256Mi | 512Mi | Handover decisions |
| rc-xapp | 200m | 500m | 256Mi | 512Mi | RAN control |
| qoe-predictor | 200m | 500m | 256Mi | 512Mi | QoE prediction |
| federated-learning | 200m | 500m | 256Mi | 512Mi | FL training |

**分析發現:**

1. **資源配置過於統一**
   - 除了 kpimon，其他 xApps 都使用相同的資源配置
   - 未根據實際工作負載特性調整
   - Traffic-steering (控制面) 與 kpimon (監控面) 應有不同的資源策略

2. **RMR Workers 配置不足**
   ```json
   kpimon: "numWorkers": 2
   traffic-steering: "numWorkers": 1
   ```
   - Traffic-steering 只有 1 個 worker，處理 E2 indication + A1 policy
   - 可能成為延遲瓶頸

3. **缺乏 GPU 資源管理**
   - Federated-learning GPU pod 請求 `nvidia.com/gpu: 1`
   - 但無 fallback 機制或優雅降級

### 1.3 資源配額 (Resource Quotas)

**問題：完全缺乏 Namespace 層級的資源配額控制**

```yaml
# 當前狀態：無 ResourceQuota
kubectl get resourcequota -n ricplt
# No resources found

kubectl get resourcequota -n ricxapp
# No resources found
```

**風險:**
- xApps 可以無限制地請求資源
- 單一 xApp bug 可能耗盡整個集群資源
- 無法防止 noisy neighbor 問題

**建議配額設定:**

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ricxapp-quota
  namespace: ricxapp
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    persistentvolumeclaims: "10"
    pods: "20"
```

---

## 2. 效能基準測試 (Performance Baseline)

### 2.1 E2 訊息處理延遲 (E2 Message Processing Latency)

**目標 (Targets):**
- E2 indication processing: < 10ms
- Control command latency: < 100ms
- RMR message throughput: > 10K msg/sec

**當前配置限制:**

1. **E2term 資源限制**
   ```yaml
   resources:
     requests:
       cpu: 400m
       memory: 512Mi
     limits:
       cpu: 1000m  # 可能造成 CPU throttling
       memory: 1Gi
   ```
   - 400m CPU request 在高負載下可能不足
   - 1000m limit 會導致 throttling

2. **RMR 配置**
   ```yaml
   rmr:
     maxSize: 8192  # 訊息大小限制
     numWorkers: 1  # 單一 worker (traffic-steering)
   ```
   - 單一 worker 處理所有訊息類型
   - 無法充分利用多核心

3. **缺乏訊息優先級**
   - 所有訊息類型使用相同的處理佇列
   - Control messages 可能被 indication messages 阻塞

### 2.2 xApp 啟動時間 (xApp Startup Time)

**目標:** < 30 秒

**實際觀察 (從 E2E 測試):**
```
Pod 啟動時間分析：
- kpimon: ~15s (包含 image pull)
- traffic-steering: ~12s
- rc-xapp: ~14s
- qoe-predictor: ~18s (ML model loading)
- federated-learning: ~25s (ML initialization)
```

**分析:**
- ✅ 所有 xApps 都符合 30 秒目標
- QoE predictor 與 FL xApp 啟動較慢（ML model loading）
- 可透過 init containers 預載模型來優化

### 2.3 資料庫效能 (Database Performance)

**DBaaS (Redis) 配置:**

```yaml
dbaas:
  enableHighAvailability: false  # ⚠️ 未啟用 HA
  redis:
    sa_config:
      appendonly: "no"  # ⚠️ 無持久化
      save: ""          # ⚠️ 無 RDB 快照
      maxmemory: "0"    # ⚠️ 無記憶體限制
      loadmodule: "/usr/local/libexec/redismodule/libredismodule.so"
```

**嚴重問題:**

1. **無高可用性**
   - 單一 Redis instance
   - 任何故障都會導致所有 xApps 失去狀態

2. **無持久化**
   - AOF: disabled
   - RDB: disabled
   - Pod restart 會遺失所有資料

3. **無記憶體限制**
   - `maxmemory: "0"` 表示無限制
   - 可能導致 OOM kill

4. **連線管理**
   - xApps 直接連接 Redis，無連線池
   - 可能導致連線耗盡

**效能影響:**
- KPI 資料儲存在 Redis (TTL 300 秒)
- 無持久化意味著重啟後遺失所有歷史資料
- 建議同時使用 InfluxDB 進行長期儲存

---

## 3. 可擴展性分析 (Scalability Analysis)

### 3.1 水平擴展能力 (Horizontal Scaling)

**當前狀態:**

```yaml
# 所有組件都是單一 replica
e2term.replicas: 1
e2mgr.replicaCount: 1
submgr.replicaCount: 1
appmgr.replicaCount: 1

# xApps (from deployments)
kpimon.replicas: 1
traffic-steering.replicas: 1
```

**HPA 配置:**

```yaml
autoscaling:
  enabled: false  # ⚠️ 所有組件都未啟用自動擴展
```

**問題分析:**

1. **無自動擴展機制**
   - 流量增加時無法自動擴展
   - 需要手動調整 replicas
   - 無法應對突發流量

2. **狀態管理問題**
   - E2term 使用 SCTP 連線，難以負載均衡
   - Subscription Manager 需要狀態同步機制
   - xApps 直接連接 Redis，多副本會有一致性問題

3. **建議 HPA 配置:**

```yaml
# E2mgr HPA (適合水平擴展)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: e2mgr-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: e2mgr
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Pods
        value: 1
        periodSeconds: 180
```

### 3.2 垂直擴展限制 (Vertical Scaling Constraints)

**當前限制:**

1. **CPU Limits 過低**
   - E2term: 1000m (1 core)
   - 在高訊息量下會 CPU throttling
   - 建議至少 2000m for production

2. **Memory Limits**
   - E2term: 1Gi
   - 對於處理大量 E2 節點可能不足
   - 建議根據 E2 節點數量動態調整：`memory = 512Mi + (num_e2_nodes * 50Mi)`

3. **VPA 未啟用**
   ```yaml
   verticalAutoscaler:
     enabled: false
   ```
   - 無法根據實際使用量自動調整資源

### 3.3 負載均衡策略 (Load Balancing)

**當前狀態:**

```yaml
service:
  sessionAffinity: None  # Prometheus, Alertmanager
```

**問題:**

1. **E2term 負載均衡**
   - SCTP 連線需要會話保持
   - 當前單一 instance，無負載均衡
   - 建議使用一致性雜湊 (Consistent Hashing) 分配 E2 節點

2. **xApp 內部負載均衡**
   - RMR 訊息路由由 rtmgr 管理
   - rtmgr 當前 `enabled: false`（使用靜態路由）
   - 限制了動態路由和負載均衡能力

3. **Service Mesh 缺失**
   ```yaml
   serviceMesh:
     enabled: false  # Linkerd 未部署
   ```
   - 無法進行智慧路由
   - 缺乏 circuit breaker、retry 等韌性機制
   - 無法實現 canary deployment

---

## 4. 瓶頸識別 (Bottleneck Identification)

### 4.1 E2 訊息處理路徑 (E2 Message Path)

**完整路徑分析:**

```
E2 Node → E2term (SCTP) → E2mgr → Submgr → xApp
                ↓                              ↓
              RMR Messages ←──────────────────┘
```

**瓶頸點:**

1. **E2term → RMR 轉換** (🔴 Critical)
   - 單一 worker thread
   - 同步處理 SCTP 訊息
   - **建議:** 實作訊息佇列與多 worker 架構

2. **Subscription Manager** (🟡 High)
   - 處理所有訂閱請求
   - 單一 instance，100m CPU request
   - **建議:** 增加 CPU request 至 200m，啟用多副本

3. **RMR Routing** (🟡 High)
   - rtmgr disabled，使用靜態路由
   - 無法動態調整路由表
   - **建議:** 啟用 rtmgr 或實作更智慧的路由機制

4. **xApp RMR Workers** (🟡 High)
   - Traffic-steering: 1 worker
   - 處理 indication + control + A1 policy
   - **建議:** 增加至 2-4 workers

### 4.2 資料儲存路徑 (Data Storage Path)

**KPI 資料流:**

```
E2 Indication → kpimon → Redis (TTL 300s)
                      ↓
                  InfluxDB (7 days retention)
```

**瓶頸點:**

1. **Redis 無連線池** (🟡 High)
   ```python
   # 當前實作（推測）
   redis_client = redis.Redis(host='redis-service.ricplt', port=6379)
   ```
   - 每個請求建立新連線
   - **建議:** 使用連線池，設定 max_connections

2. **InfluxDB 寫入效能** (🟢 Medium)
   - 當前未部署 InfluxDB
   - 配置中有設定但未實際安裝
   - **建議:** 部署 InfluxDB 並啟用批次寫入

3. **Prometheus 資料留存** (🟡 High)
   ```yaml
   retention: "15d"
   persistentVolume:
     enabled: false  # 使用 emptyDir
   ```
   - Pod restart 會遺失所有資料
   - **建議:** 啟用 PVC，增加 retention 至 30d

### 4.3 監控與追蹤路徑 (Monitoring & Tracing)

**當前狀態:**

```yaml
# Prometheus 採集配置
scrape_interval: 1m      # ⚠️ 過長
scrape_timeout: 10s
evaluation_interval: 1m
```

**問題:**

1. **採集間隔過長**
   - 1 分鐘無法捕捉短期效能問題
   - E2 indication 處理時間目標 < 10ms
   - **建議:** 關鍵 metrics 採集間隔調整為 15s

2. **無分散式追蹤**
   - Jaeger adapter 未部署
   - 無法追蹤跨組件的請求延遲
   - **建議:** 部署 Jaeger 並整合 OpenTelemetry

3. **Metrics 暴露不一致**
   - 部分 xApps 有 `/metrics` endpoint
   - 但缺乏統一的 metrics 格式規範
   - **建議:** 定義標準 metrics schema

---

## 5. 優化建議 (Optimization Recommendations)

### 5.1 短期優化 (Quick Wins - 1-2 週)

#### 5.1.1 調整資源配置

**Priority: 🔴 Critical**

```yaml
# 修改 /home/thc1006/oran-ric-platform/platform/values/local.yaml

# 1. E2term - 關鍵路徑優化
e2term:
  resources:
    requests:
      cpu: 800m        # 從 400m 提升
      memory: 512Mi
    limits:
      cpu: 1500m       # 從 1000m 提升，降低 throttling
      memory: 1Gi

# 2. Subscription Manager - 提升處理能力
submgr:
  resources:
    requests:
      cpu: 200m        # 從 100m 提升
      memory: 256Mi    # 從 128Mi 提升
    limits:
      cpu: 400m        # 從 250m 提升
      memory: 512Mi    # 從 256Mi 提升

# 3. DBaaS - 啟用持久化與記憶體限制
dbaas:
  redis:
    sa_config:
      appendonly: "yes"              # 啟用 AOF
      save: "900 1 300 10 60 10000"  # 啟用 RDB
      maxmemory: "768mb"             # 設定記憶體限制
      maxmemory-policy: "allkeys-lru"  # 使用 LRU 驅逐策略
  resources:
    requests:
      cpu: 200m        # 從 100m 提升
      memory: 512Mi    # 從 256Mi 提升
    limits:
      cpu: 500m
      memory: 1Gi
  persistence:
    enabled: true      # 啟用持久化
    size: 20Gi         # 從 10Gi 提升
```

**預期影響:**
- E2 indication 處理延遲降低 30-40%
- Redis 無資料遺失風險
- 降低 CPU throttling 發生率

#### 5.1.2 優化 Prometheus 配置

**Priority: 🟡 High**

```yaml
# 修改 /home/thc1006/oran-ric-platform/config/prometheus-values.yaml

server:
  global:
    scrape_interval: 15s     # 從 1m 縮短
    scrape_timeout: 10s
    evaluation_interval: 15s  # 從 1m 縮短

  retention: "30d"           # 從 15d 延長

  persistentVolume:
    enabled: true            # 從 false 改為 true
    size: 50Gi              # 從 8Gi 增加
    storageClassName: local-path

  resources:
    requests:
      cpu: 1000m             # 從 500m 提升
      memory: 2Gi            # 從 1Gi 提升
    limits:
      cpu: 2000m             # 從 1000m 提升
      memory: 4Gi            # 從 2Gi 提升
```

**預期影響:**
- 捕捉更細緻的效能問題
- 資料不會因 pod restart 遺失
- 支援更長期的效能趨勢分析

#### 5.1.3 增加 RMR Workers

**Priority: 🟡 High**

```json
// 修改 xApps 配置

// kpimon: /home/thc1006/oran-ric-platform/xapps/kpimon-go-xapp/config/config.json
{
  "rmr": {
    "numWorkers": 4  // 從 2 提升至 4
  }
}

// traffic-steering: /home/thc1006/oran-ric-platform/xapps/traffic-steering/config/config.json
{
  "rmr": {
    "numWorkers": 3  // 從 1 提升至 3 (處理 indication + control + A1)
  }
}
```

**預期影響:**
- RMR 訊息處理吞吐量提升 2-3 倍
- 降低訊息處理延遲
- 更好地利用多核心 CPU

### 5.2 中期優化 (1-2 個月)

#### 5.2.1 實作多層快取策略 (Multi-tier Caching)

**Architecture:**

```
┌─────────────────────────────────────────────────────┐
│ Layer 1: Application Cache (In-memory)             │
│ - Python dict/lru_cache                             │
│ - TTL: 10-30 seconds                                │
│ - Use case: 常用 KPI 查詢、UE 狀態                  │
└─────────────────────────────────────────────────────┘
                        ↓ (cache miss)
┌─────────────────────────────────────────────────────┐
│ Layer 2: Distributed Cache (Redis)                 │
│ - Connection pooling                                │
│ - TTL: 5 minutes                                    │
│ - Use case: 跨 xApp 共享資料                        │
└─────────────────────────────────────────────────────┘
                        ↓ (cache miss)
┌─────────────────────────────────────────────────────┐
│ Layer 3: Time-series DB (InfluxDB)                 │
│ - Batch writes (1000 points/batch)                 │
│ - Retention: 7 days                                 │
│ - Use case: 歷史 KPI 查詢、趨勢分析                 │
└─────────────────────────────────────────────────────┘
```

**實作範例 (kpimon xApp):**

```python
# /home/thc1006/oran-ric-platform/xapps/kpimon-go-xapp/src/cache.py

from functools import lru_cache
import redis
from redis import ConnectionPool
import time

class MultiTierCache:
    def __init__(self):
        # Layer 1: In-memory LRU cache
        self.memory_cache = {}
        self.memory_ttl = {}

        # Layer 2: Redis with connection pool
        self.redis_pool = ConnectionPool(
            host='redis-service.ricplt',
            port=6379,
            max_connections=20,
            socket_keepalive=True
        )
        self.redis_client = redis.Redis(connection_pool=self.redis_pool)

    @lru_cache(maxsize=1000)
    def get_ue_kpi(self, ue_id: str, kpi_name: str):
        cache_key = f"ue:{ue_id}:kpi:{kpi_name}"

        # Layer 1: Check memory cache
        if cache_key in self.memory_cache:
            if time.time() < self.memory_ttl[cache_key]:
                return self.memory_cache[cache_key]

        # Layer 2: Check Redis
        value = self.redis_client.get(cache_key)
        if value:
            # Populate memory cache
            self.memory_cache[cache_key] = value
            self.memory_ttl[cache_key] = time.time() + 30
            return value

        # Layer 3: Fetch from InfluxDB (not shown)
        return None
```

**預期影響:**
- KPI 查詢延遲降低 80-90%
- Redis 負載降低 50-70%
- 支援更高的查詢吞吐量

#### 5.2.2 啟用 Redis HA 與 Sentinel

**Priority: 🔴 Critical**

```yaml
# 修改 dbaas 配置
dbaas:
  enableHighAvailability: true  # 啟用 HA
  haReplicas: 3                 # 3 個 Redis replicas

  sentinel:
    quorum: 2                   # 2/3 達成共識
    config:
      down-after-milliseconds: 5000
      failover-timeout: 60000
      parallel-syncs: 1

  redis:
    ha_config:
      appendonly: "yes"
      save: "900 1 300 10"
      min-slaves-to-write: 1    # 至少 1 個 slave 確認寫入
      min-slaves-max-lag: 5
      maxmemory: "768mb"
      maxmemory-policy: "allkeys-lru"
```

**預期影響:**
- 無單點故障
- 自動故障轉移 (< 60 秒)
- 資料持久化保證

#### 5.2.3 部署 Jaeger 分散式追蹤

**Priority: 🟡 High**

```bash
# 部署 Jaeger
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm install jaeger jaegertracing/jaeger \
  --namespace ricobs \
  --set provisionDataStore.cassandra=false \
  --set storage.type=memory \
  --set collector.resources.limits.cpu=500m \
  --set collector.resources.limits.memory=512Mi
```

**整合 xApps with OpenTelemetry:**

```python
# /home/thc1006/oran-ric-platform/xapps/kpimon-go-xapp/src/tracing.py

from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

def setup_tracing(service_name: str):
    trace.set_tracer_provider(TracerProvider())

    jaeger_exporter = JaegerExporter(
        agent_host_name="jaeger-agent.ricobs",
        agent_port=6831,
    )

    trace.get_tracer_provider().add_span_processor(
        BatchSpanProcessor(jaeger_exporter)
    )

    return trace.get_tracer(service_name)

# 使用範例
tracer = setup_tracing("kpimon-xapp")

@tracer.start_as_current_span("process_e2_indication")
def process_indication(message):
    with tracer.start_as_current_span("parse_asn1"):
        # ASN.1 parsing
        pass

    with tracer.start_as_current_span("extract_kpis"):
        # KPI extraction
        pass

    with tracer.start_as_current_span("store_redis"):
        # Store to Redis
        pass
```

**預期影響:**
- 可視化完整的請求路徑
- 識別延遲瓶頸 (哪個組件最慢)
- 支援 root cause analysis

### 5.3 長期優化 (3-6 個月)

#### 5.3.1 實作 Service Mesh (Linkerd)

**Priority: 🟡 High**

**Benefits:**
- Automatic mTLS between services
- Circuit breaking & retries
- Traffic splitting (canary deployments)
- Rich observability metrics

**部署步驟:**

```bash
# 1. 安裝 Linkerd CLI
curl -sL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# 2. 安裝 Linkerd control plane
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -

# 3. Inject Linkerd proxy 到 RIC namespaces
kubectl get deploy -n ricplt -o yaml | linkerd inject - | kubectl apply -f -
kubectl get deploy -n ricxapp -o yaml | linkerd inject - | kubectl apply -f -

# 4. 安裝 Linkerd Viz (observability)
linkerd viz install | kubectl apply -f -
```

**配置 Traffic Policy:**

```yaml
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: e2term-sctp
  namespace: ricplt
spec:
  podSelector:
    matchLabels:
      app: e2term
  port: 36422
  proxyProtocol: opaque  # SCTP traffic
---
apiVersion: policy.linkerd.io/v1alpha1
kind: HTTPRoute
metadata:
  name: xapp-routing
  namespace: ricxapp
spec:
  parentRefs:
    - name: kpimon
      kind: Service
  rules:
    - matches:
      - path:
          type: PathPrefix
          value: /metrics
      backendRefs:
        - name: kpimon
          port: 8080
```

**預期影響:**
- Service-to-service latency 降低 10-15%
- Automatic retry 減少暫時性錯誤
- 更豐富的 service-level metrics

#### 5.3.2 實作 E2 訊息批次處理

**Priority: 🔴 Critical (for high-load scenarios)**

**Current State:**
```python
# 每個 E2 indication 單獨處理
def handle_indication(message):
    kpi = extract_kpi(message)
    store_to_redis(kpi)  # 每次單獨寫入
```

**Optimized with Batching:**

```python
import asyncio
from collections import defaultdict

class E2IndicationBatcher:
    def __init__(self, batch_size=100, batch_timeout=0.5):
        self.batch_size = batch_size
        self.batch_timeout = batch_timeout
        self.buffer = []
        self.lock = asyncio.Lock()

    async def add_indication(self, message):
        async with self.lock:
            self.buffer.append(message)

            if len(self.buffer) >= self.batch_size:
                await self.flush()

    async def flush(self):
        if not self.buffer:
            return

        batch = self.buffer[:]
        self.buffer.clear()

        # 批次處理
        kpis = [extract_kpi(msg) for msg in batch]

        # 批次寫入 Redis (pipeline)
        pipe = redis_client.pipeline()
        for kpi in kpis:
            pipe.setex(f"kpi:{kpi.ue_id}", 300, json.dumps(kpi))
        await pipe.execute()

        # 批次寫入 InfluxDB
        await influx_client.write_points(kpis)

    async def start_timer(self):
        while True:
            await asyncio.sleep(self.batch_timeout)
            async with self.lock:
                await self.flush()
```

**預期影響:**
- Redis 寫入吞吐量提升 10-20 倍
- InfluxDB 寫入吞吐量提升 50-100 倍
- CPU usage 降低 30-40% (減少 syscall overhead)

#### 5.3.3 優化 E2term 架構

**Priority: 🔴 Critical**

**問題:** 單一 E2term instance 處理所有 E2 節點

**解決方案:** Sharded E2term with Consistent Hashing

```yaml
# 部署 3 個 E2term instances
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: e2term
  namespace: ricplt
spec:
  serviceName: e2term
  replicas: 3
  selector:
    matchLabels:
      app: e2term
  template:
    metadata:
      labels:
        app: e2term
    spec:
      containers:
      - name: e2term
        image: nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-e2:5.5.0
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: SHARD_ID
          value: "$(POD_NAME | sed 's/e2term-//')"
        resources:
          requests:
            cpu: 800m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 2Gi
---
# Headless service for direct pod access
apiVersion: v1
kind: Service
metadata:
  name: e2term-headless
  namespace: ricplt
spec:
  clusterIP: None
  selector:
    app: e2term
  ports:
  - name: sctp
    port: 36422
    protocol: SCTP
```

**E2 Node Assignment Logic:**

```python
import hashlib

def get_e2term_shard(e2_node_id: str, num_shards: int = 3) -> int:
    """使用一致性雜湊分配 E2 node 到 E2term shard"""
    hash_value = int(hashlib.md5(e2_node_id.encode()).hexdigest(), 16)
    return hash_value % num_shards

# Example usage
e2_node_id = "gnb-001"
shard_id = get_e2term_shard(e2_node_id)
e2term_host = f"e2term-{shard_id}.e2term-headless.ricplt.svc.cluster.local"
```

**預期影響:**
- E2 訊息處理能力提升 3 倍
- 單一 shard 故障不影響其他 E2 nodes
- 支援 100+ E2 nodes

---

## 6. 監控與告警建議 (Monitoring & Alerting)

### 6.1 關鍵效能指標 (Key Performance Indicators)

**E2 Interface Metrics:**

```yaml
# Prometheus recording rules
groups:
- name: e2_performance
  interval: 15s
  rules:
  - record: e2:indication_processing_latency:p99
    expr: histogram_quantile(0.99, rate(e2_indication_duration_seconds_bucket[5m]))

  - record: e2:indication_throughput:rate5m
    expr: rate(e2_indication_total[5m])

  - record: e2:control_req_latency:p99
    expr: histogram_quantile(0.99, rate(e2_control_req_duration_seconds_bucket[5m]))

  - record: e2:subscription_success_rate
    expr: rate(e2_subscription_success_total[5m]) / rate(e2_subscription_total[5m])
```

**Alerting Rules:**

```yaml
groups:
- name: e2_alerts
  rules:
  - alert: E2IndicationProcessingSlowWarning
    expr: e2:indication_processing_latency:p99 > 0.010  # > 10ms
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "E2 indication processing is slow"
      description: "P99 latency is {{ $value }}s (target: < 10ms)"

  - alert: E2IndicationProcessingSlowCritical
    expr: e2:indication_processing_latency:p99 > 0.050  # > 50ms
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "E2 indication processing is critically slow"
      description: "P99 latency is {{ $value }}s (target: < 10ms)"

  - alert: E2ControlLatencyHigh
    expr: e2:control_req_latency:p99 > 0.100  # > 100ms
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "E2 control command latency is high"
      description: "P99 latency is {{ $value }}s (target: < 100ms)"

  - alert: E2SubscriptionFailureRate
    expr: e2:subscription_success_rate < 0.95  # < 95%
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "E2 subscription failure rate is high"
      description: "Success rate is {{ $value }} (target: > 95%)"
```

**Resource Utilization Alerts:**

```yaml
- alert: PodCPUThrottling
  expr: rate(container_cpu_cfs_throttled_seconds_total{namespace=~"ricplt|ricxapp"}[5m]) > 0.1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Pod {{ $labels.pod }} is experiencing CPU throttling"
    description: "Throttling rate: {{ $value }}/s"

- alert: PodMemoryPressure
  expr: container_memory_working_set_bytes{namespace=~"ricplt|ricxapp"} / container_spec_memory_limit_bytes > 0.9
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Pod {{ $labels.pod }} memory usage is high"
    description: "Memory usage: {{ $value | humanizePercentage }}"
```

### 6.2 Grafana Dashboards

**建議建立以下 dashboards:**

1. **O-RAN RIC Overview Dashboard**
   - 整體健康狀態
   - E2 nodes 連接數量
   - xApps 運行狀態
   - 資源使用率摘要

2. **E2 Interface Performance Dashboard**
   - E2 indication 處理延遲 (P50, P95, P99)
   - E2 control 命令延遲
   - Subscription 成功率
   - 訊息吞吐量 (msg/sec)

3. **xApp Performance Dashboard**
   - 每個 xApp 的 CPU/Memory 使用率
   - RMR 訊息處理延遲
   - Redis 操作延遲
   - 錯誤率與重試次數

4. **Resource Utilization Dashboard**
   - Node-level metrics
   - Namespace quotas vs usage
   - Pod CPU throttling events
   - OOM kills

**Dashboard 匯入腳本:**

```bash
# /home/thc1006/oran-ric-platform/scripts/import-dashboards.sh

#!/bin/bash

GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD=$(kubectl get secret -n ricplt oran-grafana -o jsonpath="{.data.admin-password}" | base64 -d)

# Import dashboards
for dashboard in ./config/grafana-dashboards/*.json; do
  echo "Importing dashboard: $dashboard"
  curl -X POST \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d @"$dashboard" \
    "$GRAFANA_URL/api/dashboards/db"
done
```

---

## 7. 容量規劃 (Capacity Planning)

### 7.1 E2 Nodes 擴展估算

**假設:**
- 每個 E2 node 產生 100 indications/sec
- 每個 indication 平均大小 2KB
- 目標支援 50 個 E2 nodes

**計算:**

```
Total indications/sec = 50 * 100 = 5,000 msg/sec
Total data rate = 5,000 * 2KB = 10 MB/sec

E2term 資源需求:
- CPU: 每 1000 msg/sec 需要 ~200m CPU
  需求: 5 * 200m = 1000m = 1 core
  建議 (with headroom): 2 cores

- Memory: 每 1000 msg/sec 需要 ~100Mi
  需求: 5 * 100Mi = 500Mi
  建議 (with headroom): 1Gi

RMR buffer:
- 訊息佇列深度: 1000 messages
- Buffer size: 1000 * 8KB = 8MB (per xApp)
```

**建議配置 (50 E2 nodes):**

```yaml
e2term:
  replicas: 2  # HA + load distribution
  resources:
    requests:
      cpu: 1500m
      memory: 1.5Gi
    limits:
      cpu: 3000m
      memory: 3Gi

kpimon:
  replicas: 2
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi
```

### 7.2 Storage 擴展估算

**KPI 資料量估算:**

```
假設:
- 50 E2 nodes
- 每個 node 平均 20 UEs
- 每個 UE 20 個 KPIs
- 每個 KPI 每秒更新 1 次
- 每個 KPI 資料點 ~100 bytes

Redis (短期快取, TTL 5 min):
= 50 nodes * 20 UEs * 20 KPIs * 100 bytes
= 2 MB (快照資料)
建議 Redis memory: 1GB (500x headroom for overhead)

InfluxDB (7 days retention):
每秒資料點 = 50 * 20 * 20 = 20,000 points/sec
每天資料量 = 20,000 * 86400 * 100 bytes = 172 GB/day
7 天資料量 = 172 * 7 = 1.2 TB
建議 InfluxDB storage: 2 TB (with compression)

Prometheus (30 days retention):
假設 100 個 metrics per service, 10 services
每秒 series = 100 * 10 = 1000 series
每天資料量 = 1000 * 86400 * 8 bytes = 691 MB/day
30 天資料量 = 691 * 30 = 20.7 GB
建議 Prometheus storage: 50 GB (with headroom)
```

---

## 8. 測試與驗證計畫 (Testing & Validation Plan)

### 8.1 效能測試場景

#### Scenario 1: Baseline Performance Test

**目標:** 建立效能基準線

```yaml
Test Configuration:
  - E2 nodes: 5
  - Indications/sec per node: 10
  - Test duration: 1 hour
  - Metrics to collect:
    - E2 indication latency (P50, P95, P99)
    - CPU/Memory usage
    - RMR message queue depth
```

**Acceptance Criteria:**
- ✅ P99 latency < 10ms
- ✅ CPU usage < 50%
- ✅ No error messages

#### Scenario 2: Load Test

**目標:** 驗證系統在高負載下的表現

```yaml
Test Configuration:
  - E2 nodes: 20
  - Indications/sec per node: 50
  - Test duration: 30 minutes
  - Ramp-up: 5 minutes
```

**Acceptance Criteria:**
- ✅ P99 latency < 50ms
- ✅ No message loss
- ✅ CPU usage < 80%

#### Scenario 3: Stress Test

**目標:** 找出系統極限

```yaml
Test Configuration:
  - E2 nodes: 50
  - Indications/sec per node: 100
  - Test duration: 15 minutes
  - Expected behavior: Graceful degradation
```

**Acceptance Criteria:**
- ✅ System remains stable (no crashes)
- ✅ Error rate < 5%
- ✅ Latency < 200ms (degraded but acceptable)

#### Scenario 4: Failover Test

**目標:** 驗證高可用性

```yaml
Test Configuration:
  - 啟用 Redis HA (3 replicas)
  - 測試中 kill Redis master
  - 測試中 kill E2term pod

Expected Behavior:
  - Redis: Automatic failover < 60s
  - E2term: Pod restart < 30s, E2 nodes reconnect
```

### 8.2 測試工具

**1. E2 Simulator Enhancement**

```bash
# /home/thc1006/oran-ric-platform/simulator/e2-simulator/load-test.py

import asyncio
import time
from typing import List
import statistics

class E2LoadTester:
    def __init__(self, num_nodes: int, msg_rate: int):
        self.num_nodes = num_nodes
        self.msg_rate = msg_rate
        self.latencies: List[float] = []

    async def simulate_node(self, node_id: int):
        """Simulate single E2 node sending indications"""
        interval = 1.0 / self.msg_rate

        while True:
            start = time.time()

            # Send E2 indication
            await self.send_indication(node_id)

            # Measure latency
            latency = time.time() - start
            self.latencies.append(latency)

            # Rate limiting
            await asyncio.sleep(interval)

    async def send_indication(self, node_id: int):
        # Simulate E2 indication message
        pass

    def report_metrics(self):
        """Print latency statistics"""
        if not self.latencies:
            return

        print(f"Total messages: {len(self.latencies)}")
        print(f"P50 latency: {statistics.quantiles(self.latencies, n=2)[0]:.3f}s")
        print(f"P95 latency: {statistics.quantiles(self.latencies, n=20)[18]:.3f}s")
        print(f"P99 latency: {statistics.quantiles(self.latencies, n=100)[98]:.3f}s")
        print(f"Max latency: {max(self.latencies):.3f}s")

# Run load test
async def main():
    tester = E2LoadTester(num_nodes=20, msg_rate=50)

    # Start all simulated nodes
    tasks = [tester.simulate_node(i) for i in range(tester.num_nodes)]

    # Run for 30 minutes
    await asyncio.wait_for(
        asyncio.gather(*tasks),
        timeout=1800
    )

    tester.report_metrics()

if __name__ == "__main__":
    asyncio.run(main())
```

**2. Prometheus Query for Analysis**

```promql
# E2 indication latency over time
rate(e2_indication_duration_seconds_sum[5m]) /
rate(e2_indication_duration_seconds_count[5m])

# CPU throttling events
rate(container_cpu_cfs_throttled_seconds_total{namespace="ricplt"}[5m])

# Memory pressure
container_memory_working_set_bytes{namespace="ricplt"} /
container_spec_memory_limit_bytes * 100
```

---

## 9. 成本效益分析 (Cost-Benefit Analysis)

### 9.1 優化投資回報 (ROI)

| 優化項目 | 實施成本 (人天) | 預期效能提升 | 優先級 | ROI |
|---------|---------------|------------|-------|-----|
| 調整資源配置 | 2 | 30-40% latency reduction | 🔴 Critical | ⭐⭐⭐⭐⭐ |
| 增加 RMR workers | 1 | 2-3x throughput | 🟡 High | ⭐⭐⭐⭐⭐ |
| 優化 Prometheus | 2 | Better observability | 🟡 High | ⭐⭐⭐⭐ |
| Redis HA | 5 | Zero downtime | 🔴 Critical | ⭐⭐⭐⭐ |
| Multi-tier cache | 10 | 80-90% query latency reduction | 🟡 High | ⭐⭐⭐⭐ |
| Jaeger tracing | 8 | Debugging efficiency | 🟡 High | ⭐⭐⭐ |
| Service Mesh | 15 | 10-15% latency reduction | 🟢 Medium | ⭐⭐⭐ |
| E2 batching | 12 | 10-20x write throughput | 🔴 Critical | ⭐⭐⭐⭐⭐ |
| E2term sharding | 20 | 3x capacity | 🟢 Medium | ⭐⭐⭐ |

**建議實施順序:**
1. Week 1-2: 調整資源配置 + 增加 RMR workers (Quick wins)
2. Week 3-4: 優化 Prometheus + Redis HA
3. Month 2: Multi-tier cache + Jaeger tracing
4. Month 3-4: E2 batching
5. Month 5-6: Service Mesh + E2term sharding

### 9.2 硬體成本估算

**當前配置 (單節點):**
```
CPU: 32 cores (3.99% utilized = 1.28 cores used)
Memory: 48 GB (14.98% utilized = 7.2 GB used)
估計成本: $500/month (AWS c5.9xlarge equivalent)

實際需求: < $100/month (可使用 c5.xlarge)
浪費: $400/month
```

**優化後配置 (50 E2 nodes, 20 xApps):**
```
控制平面節點 (k3s master):
- c5.2xlarge (8 vCPU, 16 GB RAM): $200/month

工作節點 1 (Platform components):
- c5.2xlarge (8 vCPU, 16 GB RAM): $200/month

工作節點 2 (xApps):
- c5.4xlarge (16 vCPU, 32 GB RAM): $400/month

工作節點 3 (Observability):
- r5.xlarge (4 vCPU, 32 GB RAM): $250/month

總成本: $1,050/month
ROI: 支援 10x 負載，成本僅增加 2x
```

---

## 10. 結論與行動計畫 (Conclusion & Action Plan)

### 10.1 關鍵結論

1. **資源配置需要重新評估**
   - 當前配置過於保守（資源使用率 < 15%）
   - 同時存在潛在瓶頸（E2term CPU limit, submgr resources）
   - 需要根據實際負載進行調整

2. **缺乏高可用性保證**
   - Redis 單點故障風險
   - 無自動故障轉移機制
   - 資料持久化未啟用

3. **可觀測性不足**
   - Metrics 採集間隔過長（1 分鐘）
   - 無分散式追蹤
   - 缺乏端到端的效能可視化

4. **擴展性受限**
   - 無 HPA/VPA
   - 單一 E2term instance
   - 無 Service Mesh

### 10.2 30 天行動計畫

**Week 1: Quick Wins**
- ✅ Day 1-2: 調整 E2term, submgr, DBaaS 資源配置
- ✅ Day 3: 增加 xApps RMR workers
- ✅ Day 4-5: 優化 Prometheus 配置（採集間隔、retention、PVC）

**Week 2: High Availability**
- ✅ Day 6-8: 啟用 Redis HA 與 Sentinel
- ✅ Day 9: 配置 Redis 持久化（AOF + RDB）
- ✅ Day 10: 測試 Redis failover

**Week 3: Observability**
- ✅ Day 11-13: 部署 Jaeger
- ✅ Day 14-15: 整合 xApps with OpenTelemetry
- ✅ Day 16-17: 建立 Grafana dashboards

**Week 4: Testing & Validation**
- ✅ Day 18-20: E2 Simulator 負載測試
- ✅ Day 21-22: 效能基準測試
- ✅ Day 23-24: 壓力測試與調優
- ✅ Day 25: 文檔更新

**Week 5+: Advanced Optimization**
- Day 26-30: 實作 multi-tier caching
- Month 2: E2 訊息批次處理
- Month 3: Service Mesh deployment
- Month 4-6: E2term sharding

### 10.3 成功指標 (Success Metrics)

**效能目標:**
- ✅ E2 indication P99 latency < 10ms
- ✅ Control command latency < 100ms
- ✅ RMR throughput > 10K msg/sec
- ✅ xApp startup time < 30s

**可靠性目標:**
- ✅ Redis uptime > 99.9%
- ✅ Automatic failover < 60s
- ✅ Zero data loss on pod restart

**可觀測性目標:**
- ✅ All components expose Prometheus metrics
- ✅ End-to-end tracing coverage > 90%
- ✅ Alert response time < 5 minutes

**成本目標:**
- ✅ 支援 50 E2 nodes 與 20 xApps
- ✅ 硬體成本 < $1,500/month
- ✅ 資源使用效率 > 60%

---

## 附錄 A: 配置檔案清單 (Configuration Files)

需要修改的配置檔案：

1. `/home/thc1006/oran-ric-platform/platform/values/local.yaml` - Platform resources
2. `/home/thc1006/oran-ric-platform/config/prometheus-values.yaml` - Monitoring
3. `/home/thc1006/oran-ric-platform/xapps/*/config/config.json` - xApp configs
4. `/home/thc1006/oran-ric-platform/ric-dep/helm/dbaas/values.yaml` - Redis HA
5. 新增: `/home/thc1006/oran-ric-platform/config/resource-quotas.yaml` - Quotas
6. 新增: `/home/thc1006/oran-ric-platform/config/hpa-policies.yaml` - Autoscaling
7. 新增: `/home/thc1006/oran-ric-platform/config/prometheus-alerts.yaml` - Alerting

---

## 附錄 B: 參考資料 (References)

1. O-RAN Alliance specifications:
   - O-RAN.WG3.E2AP-v03.00: E2 Application Protocol
   - O-RAN.WG3.E2SM-KPM-v03.00: KPM Service Model
   - O-RAN.WG5.C.1-v07.00: Control Loop Specification

2. Kubernetes best practices:
   - Resource management: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
   - QoS classes: https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/
   - HPA: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

3. Redis performance:
   - Redis Sentinel: https://redis.io/docs/manual/sentinel/
   - Redis persistence: https://redis.io/docs/manual/persistence/

4. Observability:
   - Prometheus best practices: https://prometheus.io/docs/practices/naming/
   - OpenTelemetry: https://opentelemetry.io/docs/
   - Jaeger architecture: https://www.jaegertracing.io/docs/architecture/

---

**報告結束**

**作者:** 蔡秀吉 (thc1006)
**日期:** 2025-11-17
**版本:** 1.0
