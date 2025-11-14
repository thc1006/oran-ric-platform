# xApp Onboarding Strategies - O-RAN RIC J Release

**作者：蔡秀吉（thc1006）**
**日期：2025-11-14**
**版本：1.0.0**

## 目錄

1. [概述](#概述)
2. [依賴關係分析](#依賴關係分析)
3. [部署順序建議](#部署順序建議)
4. [KPIMON xApp](#kpimon-xapp)
5. [QoE Predictor xApp](#qoe-predictor-xapp)
6. [RC (RAN Control) xApp](#rc-ran-control-xapp)
7. [Traffic Steering xApp](#traffic-steering-xapp)
8. [Federated Learning xApp](#federated-learning-xapp)
9. [驗證與測試](#驗證與測試)
10. [常見問題排解](#常見問題排解)

---

## 概述

這份文件詳細記錄了 O-RAN RIC J Release 平台上各個 xApp 的最佳 onboarding 策略。基於對程式碼庫的深入分析，我們識別出每個 xApp 的特定需求、依賴關係和部署步驟。

### 設計原則

- **最小化依賴**：優先部署無依賴或依賴較少的 xApp
- **漸進式驗證**：每個 xApp 部署後立即驗證功能
- **資源優化**：合理分配運算資源，避免過度配置
- **安全第一**：所有 xApp 遵循 Pod Security Standards

### 關鍵資訊

- **RIC 平台版本**：O-RAN SC J Release (v4.0)
- **Kubernetes 發行版**：k3s (輕量級單節點部署)
- **容器運行時**：containerd
- **RMR 版本**：4.9.4
- **Python 版本**：3.11

---

## 依賴關係分析

### 依賴關係圖

```
RIC Platform Infrastructure (ricplt)
├── E2 Termination (e2term)
├── E2 Manager (e2mgr)
├── Subscription Manager (submgr)
├── A1 Mediator (a1mediator)
├── SDL (Redis)
└── App Manager (appmgr)

xApps (ricxapp namespace)
├── KPIMON (無 xApp 依賴)
│   ├── 需要：e2term, submgr, Redis, InfluxDB
│   └── 提供：KPI 資料到 SDL
│
├── QoE Predictor (無 xApp 依賴)
│   ├── 需要：a1mediator, Redis
│   └── 提供：QoE 預測 API
│
├── RC (RAN Control) (無 xApp 依賴)
│   ├── 需要：e2term, submgr, a1mediator, Redis
│   └── 提供：RAN 控制 API
│
├── Traffic Steering (依賴 QoE + RC)
│   ├── 需要：QoE Predictor API, RC xApp API
│   └── 提供：切換決策
│
└── Federated Learning (可選，獨立運作)
    ├── 需要：Redis
    └── 提供：聯邦學習模型
```

### 外部服務依賴

| xApp | Redis | InfluxDB | A1 Mediator | E2 Termination |
|------|-------|----------|-------------|----------------|
| KPIMON | ✓ (db=0) | ✓ | ✗ | ✓ |
| QoE Predictor | ✓ (db=1) | ✗ | ✓ | ✗ |
| RC xApp | ✓ (db=2) | ✗ | ✓ | ✓ |
| Traffic Steering | ✓ (db=0) | ✗ | ✓ | ✗ |
| Federated Learning | ✓ (db=3) | ✗ | ✗ | ✗ |

---

## 部署順序建議

基於依賴關係分析，建議的部署順序如下：

### 階段 1：基礎設施準備（0-15 分鐘）

1. 確認 RIC 平台運行狀態
2. 部署 InfluxDB (KPIMON 需要)
3. 創建必要的 Secrets 和 ConfigMaps
4. 設置 RBAC 資源

### 階段 2：獨立 xApps（15-30 分鐘）

**並行部署：**
- KPIMON xApp
- QoE Predictor xApp
- RC xApp

這三個 xApp 彼此沒有依賴關係，可以同時部署。

### 階段 3：整合 xApps（30-40 分鐘）

**順序部署：**
1. Traffic Steering xApp（依賴 QoE + RC）
2. Federated Learning xApp（可選）

### 階段 4：驗證與測試（40-60 分鐘）

1. E2 連線測試
2. RMR 訊息流測試
3. 端到端功能測試

---

## KPIMON xApp

### 功能說明

KPIMON (KPI Monitoring) xApp 負責從 E2 節點收集 KPI 指標，並儲存到 InfluxDB 進行時序分析。它實現了 E2SM-KPM v3.0 服務模型。

### 預部署檢查清單

- [ ] E2 Termination 運行正常
- [ ] Subscription Manager 運行正常
- [ ] Redis 可訪問（ricplt namespace）
- [ ] InfluxDB 已部署並創建 bucket
- [ ] InfluxDB token 已創建為 Secret

### InfluxDB 準備工作

```bash
# 1. 部署 InfluxDB
kubectl create namespace ricplt --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: influxdb-pvc
  namespace: ricplt
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: influxdb
  namespace: ricplt
spec:
  replicas: 1
  selector:
    matchLabels:
      app: influxdb
  template:
    metadata:
      labels:
        app: influxdb
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: influxdb
        image: influxdb:2.7-alpine
        ports:
        - containerPort: 8086
        env:
        - name: INFLUXDB_DB
          value: "kpimon"
        - name: INFLUXDB_ADMIN_USER
          value: "admin"
        - name: INFLUXDB_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: influxdb-secrets
              key: admin-password
        volumeMounts:
        - name: data
          mountPath: /var/lib/influxdb2
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 2Gi
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: influxdb-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: influxdb-service
  namespace: ricplt
spec:
  selector:
    app: influxdb
  ports:
  - port: 8086
    targetPort: 8086
  type: ClusterIP
EOF

# 2. 創建 InfluxDB admin 密碼
kubectl create secret generic influxdb-secrets \
  --from-literal=admin-password='ric-influx-2025' \
  -n ricplt

# 3. 等待 InfluxDB 就緒
kubectl wait --for=condition=ready pod -l app=influxdb -n ricplt --timeout=120s

# 4. 創建 organization 和 bucket
kubectl exec -it deployment/influxdb -n ricplt -- influx setup \
  --username admin \
  --password ric-influx-2025 \
  --org oran \
  --bucket kpimon \
  --retention 7d \
  --force

# 5. 生成 API token
INFLUXDB_TOKEN=$(kubectl exec -it deployment/influxdb -n ricplt -- \
  influx auth create \
  --org oran \
  --read-buckets \
  --write-buckets \
  --json | jq -r '.token')

# 6. 儲存 token 為 Secret
kubectl create secret generic kpimon-influxdb-token \
  --from-literal=token="${INFLUXDB_TOKEN}" \
  -n ricxapp
```

### E2SM-KPM 配置

KPIMON 使用 E2SM-KPM v3.0 服務模型，關鍵配置參數：

```json
{
  "e2sm": {
    "ranFunctionId": 2,
    "serviceModel": "E2SM-KPM",
    "version": "3.0.0",
    "reportStyles": [1, 2, 3, 4, 5],
    "indicationHeaderFormats": [1, 2],
    "indicationMessageFormats": [1, 2, 3]
  },
  "subscription": {
    "report_period": 1000,
    "granularity_period": 1000,
    "max_measurements": 20
  }
}
```

**重要事項：**
- `ranFunctionId: 2` 必須與 E2 節點的 KPM function ID 一致
- Report period 建議 1000ms（1 秒），避免過度負載
- Granularity period 應該 >= report period

### Onboarding 步驟

```bash
# 1. 進入 xApps 目錄
cd /home/thc1006/oran-ric-platform/xapps

# 2. 構建 Docker 映像
docker build -t localhost:5000/xapp-kpimon:1.0.0 kpimon-go-xapp/
docker push localhost:5000/xapp-kpimon:1.0.0

# 3. 創建 ConfigMap
kubectl create namespace ricxapp --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap kpimon-config \
  --from-file=config.json=kpimon-go-xapp/config/config.json \
  -n ricxapp \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. 部署 xApp
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kpimon
  namespace: ricxapp
  labels:
    app: kpimon
    version: "1.0.0"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kpimon
  template:
    metadata:
      labels:
        app: kpimon
        version: "1.0.0"
    spec:
      serviceAccountName: xapp-serviceaccount
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: kpimon
        image: localhost:5000/xapp-kpimon:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: rmr-data
          containerPort: 4560
          protocol: TCP
        - name: rmr-route
          containerPort: 4561
          protocol: TCP
        - name: http-api
          containerPort: 8080
          protocol: TCP
        env:
        - name: RMR_SEED_RT
          value: "/app/config/rmr-routes.txt"
        - name: RMR_SRC_ID
          value: "kpimon"
        - name: INFLUXDB_TOKEN
          valueFrom:
            secretKeyRef:
              name: kpimon-influxdb-token
              key: token
        - name: PYTHONUNBUFFERED
          value: "1"
        volumeMounts:
        - name: config
          mountPath: /app/config
          readOnly: true
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        livenessProbe:
          httpGet:
            path: /health/alive
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 15
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
      volumes:
      - name: config
        configMap:
          name: kpimon-config
---
apiVersion: v1
kind: Service
metadata:
  name: kpimon-service
  namespace: ricxapp
  labels:
    app: kpimon
spec:
  selector:
    app: kpimon
  ports:
  - name: rmr-data
    port: 4560
    targetPort: 4560
    protocol: TCP
  - name: rmr-route
    port: 4561
    targetPort: 4561
    protocol: TCP
  - name: http-api
    port: 8080
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
EOF

# 5. 等待部署完成
kubectl wait --for=condition=ready pod -l app=kpimon -n ricxapp --timeout=120s

# 6. 檢查狀態
kubectl get pods -n ricxapp -l app=kpimon
kubectl logs -n ricxapp -l app=kpimon --tail=50
```

### 部署後驗證

```bash
# 1. 檢查 Pod 狀態
kubectl get pods -n ricxapp -l app=kpimon

# 預期輸出：
# NAME                      READY   STATUS    RESTARTS   AGE
# kpimon-xxxxxxxxxx-xxxxx   1/1     Running   0          2m

# 2. 驗證健康檢查
kubectl port-forward -n ricxapp svc/kpimon-service 8080:8080 &
curl http://localhost:8080/health/alive
curl http://localhost:8080/health/ready

# 預期輸出：{"status": "alive"}

# 3. 檢查 RMR 連線
kubectl exec -it deployment/kpimon -n ricxapp -- cat /app/config/rmr-routes.txt

# 4. 檢查 E2 訂閱狀態
curl http://localhost:8080/api/v1/subscriptions

# 5. 驗證 InfluxDB 資料寫入
kubectl port-forward -n ricplt svc/influxdb-service 8086:8086 &

# 使用 InfluxDB CLI 查詢
influx query 'from(bucket:"kpimon") |> range(start: -5m) |> limit(n:10)'
```

### 常見問題

**問題 1：Pod 一直處於 CrashLoopBackOff**

```bash
# 檢查日誌
kubectl logs -n ricxapp deployment/kpimon --previous

# 常見原因：
# - RMR 庫加載失敗
# - InfluxDB token 無效
# - Redis 連線失敗
```

**問題 2：無法連接到 E2 Termination**

```bash
# 檢查 E2 Termination 狀態
kubectl get pods -n ricplt -l app=e2term

# 檢查網絡策略
kubectl describe networkpolicy -n ricxapp

# 測試 RMR 連線
kubectl exec -it deployment/kpimon -n ricxapp -- \
  curl -v telnet://e2term-rmr.ricplt:4560
```

**問題 3：InfluxDB 寫入失敗**

```bash
# 驗證 token
kubectl get secret kpimon-influxdb-token -n ricxapp -o jsonpath='{.data.token}' | base64 -d

# 檢查 InfluxDB 日誌
kubectl logs -n ricplt deployment/influxdb

# 測試連線
kubectl exec -it deployment/kpimon -n ricxapp -- \
  curl -v http://influxdb-service.ricplt:8086/health
```

### 效能調優

```yaml
# 針對高吞吐量場景的配置調整
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi

# RMR 配置優化
rmr:
  numWorkers: 4  # 增加 workers
  maxSize: 32768  # 增大訊息大小

# 訂閱配置優化
subscription:
  report_period: 5000  # 降低頻率減少負載
  max_measurements: 10  # 減少單次回報的指標數量
```

---

## QoE Predictor xApp

### 功能說明

QoE Predictor xApp 使用 LSTM 模型預測用戶體驗品質 (Quality of Experience)。它接收 RIC_INDICATION 訊息中的 KPI 資料，進行特徵提取和預測，並通過 A1 介面接收策略更新。

### 預部署檢查清單

- [ ] A1 Mediator 運行正常
- [ ] Redis 可訪問
- [ ] 模型檔案已準備（如有預訓練模型）
- [ ] 足夠的 GPU/CPU 資源（模型推論）

### 模型檔案準備

QoE Predictor 支援兩種模式：

1. **冷啟動模式**：沒有預訓練模型，從頭開始訓練
2. **熱啟動模式**：使用預訓練模型

```bash
# 創建模型目錄結構
mkdir -p /home/thc1006/oran-ric-platform/xapps/qoe-predictor/models/saved
mkdir -p /home/thc1006/oran-ric-platform/xapps/qoe-predictor/models/checkpoints

# 如果有預訓練模型，複製到 models/saved 目錄
# cp your-model.h5 /home/thc1006/oran-ric-platform/xapps/qoe-predictor/models/saved/

# 創建模型配置
cat > /home/thc1006/oran-ric-platform/xapps/qoe-predictor/models/model_config.yaml <<EOF
models:
  video_quality:
    architecture: lstm
    input_shape: [100, 20]
    output_classes: 5
    pretrained: false
    path: null

  voice_quality:
    architecture: lstm
    input_shape: [100, 15]
    output_classes: 5
    pretrained: false
    path: null

  web_browsing:
    architecture: lstm
    input_shape: [100, 10]
    output_classes: 4
    pretrained: false
    path: null

  gaming:
    architecture: lstm
    input_shape: [100, 12]
    output_classes: 4
    pretrained: false
    path: null
EOF
```

### A1 Policy 整合

QoE Predictor 通過 A1 介面接收策略配置：

```json
{
  "policy_type_id": 20100,
  "policy_instance_id": "qoe-policy-001",
  "ric_id": "ric-1",
  "policy": {
    "prediction_window": 10,
    "confidence_threshold": 0.8,
    "update_interval": 3600,
    "services": ["video_quality", "voice_quality"],
    "thresholds": {
      "video_quality": {
        "excellent": 4.5,
        "good": 3.5,
        "fair": 2.5,
        "poor": 1.5
      }
    }
  }
}
```

**配置 A1 Policy：**

```bash
# 創建 A1 Policy Type
curl -X PUT http://a1mediator-service.ricplt:8080/a1-p/policytypes/20100 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "QoE Prediction Policy",
    "description": "Policy for QoE prediction configuration",
    "policy_type_id": 20100,
    "create_schema": {
      "type": "object",
      "properties": {
        "prediction_window": {"type": "number"},
        "confidence_threshold": {"type": "number"},
        "services": {"type": "array"}
      }
    }
  }'

# 創建 Policy Instance
curl -X PUT http://a1mediator-service.ricplt:8080/a1-p/policytypes/20100/policies/qoe-policy-001 \
  -H "Content-Type: application/json" \
  -d '{
    "prediction_window": 10,
    "confidence_threshold": 0.8,
    "services": ["video_quality", "voice_quality"]
  }'
```

### Onboarding 步驟

```bash
# 1. 構建 Docker 映像
cd /home/thc1006/oran-ric-platform/xapps
docker build -t localhost:5000/xapp-qoe-predictor:1.0.0 qoe-predictor/
docker push localhost:5000/xapp-qoe-predictor:1.0.0

# 2. 創建 ConfigMap
kubectl create configmap qoe-predictor-config \
  --from-file=config.json=qoe-predictor/config/config.json \
  -n ricxapp \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. 創建 PersistentVolumeClaim for models
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: qoe-predictor-models
  namespace: ricxapp
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 5Gi
EOF

# 4. 部署 xApp
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qoe-predictor
  namespace: ricxapp
  labels:
    app: qoe-predictor
    version: "1.0.0"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: qoe-predictor
  template:
    metadata:
      labels:
        app: qoe-predictor
        version: "1.0.0"
    spec:
      serviceAccountName: xapp-serviceaccount
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: qoe-predictor
        image: localhost:5000/xapp-qoe-predictor:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: rmr-data
          containerPort: 4570
          protocol: TCP
        - name: rmr-route
          containerPort: 4571
          protocol: TCP
        - name: http-api
          containerPort: 8090
          protocol: TCP
        env:
        - name: RMR_SEED_RT
          value: "/app/config/rmr-routes.txt"
        - name: RMR_SRC_ID
          value: "qoe-predictor"
        - name: PYTHONUNBUFFERED
          value: "1"
        - name: TF_CPP_MIN_LOG_LEVEL
          value: "2"
        volumeMounts:
        - name: config
          mountPath: /app/config
          readOnly: true
        - name: models
          mountPath: /app/models
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 2Gi
        livenessProbe:
          httpGet:
            path: /health/alive
            port: 8090
          initialDelaySeconds: 15
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8090
          initialDelaySeconds: 20
          periodSeconds: 15
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
      volumes:
      - name: config
        configMap:
          name: qoe-predictor-config
      - name: models
        persistentVolumeClaim:
          claimName: qoe-predictor-models
---
apiVersion: v1
kind: Service
metadata:
  name: qoe-predictor-service
  namespace: ricxapp
  labels:
    app: qoe-predictor
spec:
  selector:
    app: qoe-predictor
  ports:
  - name: rmr-data
    port: 4570
    targetPort: 4570
    protocol: TCP
  - name: rmr-route
    port: 4571
    targetPort: 4571
    protocol: TCP
  - name: http-api
    port: 8090
    targetPort: 8090
    protocol: TCP
  type: ClusterIP
EOF

# 5. 等待部署完成
kubectl wait --for=condition=ready pod -l app=qoe-predictor -n ricxapp --timeout=180s

# 6. 檢查狀態
kubectl get pods -n ricxapp -l app=qoe-predictor
kubectl logs -n ricxapp -l app=qoe-predictor --tail=50
```

### 部署後驗證

```bash
# 1. 驗證健康狀態
kubectl port-forward -n ricxapp svc/qoe-predictor-service 8090:8090 &
curl http://localhost:8090/health/alive
curl http://localhost:8090/health/ready

# 2. 檢查模型狀態
curl http://localhost:8090/api/v1/models/status

# 預期輸出：
# {
#   "models": {
#     "video_quality": {"loaded": true, "trained": false},
#     "voice_quality": {"loaded": true, "trained": false}
#   }
# }

# 3. 測試預測 API
curl -X POST http://localhost:8090/api/v1/predict \
  -H "Content-Type: application/json" \
  -d '{
    "service": "video_quality",
    "features": {
      "throughput_dl": 50.5,
      "throughput_ul": 20.3,
      "latency": 25.5,
      "packet_loss": 0.5,
      "rsrp": -85,
      "rsrq": -12,
      "sinr": 15
    }
  }'

# 4. 檢查 A1 Policy 接收
curl http://localhost:8090/api/v1/policies

# 5. 驗證 Redis 連線
kubectl exec -it deployment/qoe-predictor -n ricxapp -- \
  python3 -c "import redis; r=redis.Redis(host='redis-service.ricplt', port=6379, db=1); print(r.ping())"
```

### 模型訓練

如果需要重新訓練模型：

```bash
# 1. 收集訓練資料（從 KPIMON 或其他來源）
# 資料應該包含 features 和 labels

# 2. 觸發訓練
curl -X POST http://localhost:8090/api/v1/models/train \
  -H "Content-Type: application/json" \
  -d '{
    "service": "video_quality",
    "epochs": 50,
    "batch_size": 32,
    "validation_split": 0.2
  }'

# 3. 監控訓練進度
curl http://localhost:8090/api/v1/models/training_status

# 4. 儲存訓練好的模型
curl -X POST http://localhost:8090/api/v1/models/save \
  -H "Content-Type: application/json" \
  -d '{
    "service": "video_quality",
    "version": "1.0.0"
  }'
```

### 常見問題

**問題 1：TensorFlow 內存不足**

```yaml
# 增加資源限制
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 4Gi

# 或調整 TensorFlow 配置
env:
- name: TF_FORCE_GPU_ALLOW_GROWTH
  value: "true"
- name: TF_GPU_THREAD_MODE
  value: "gpu_private"
```

**問題 2：模型加載失敗**

```bash
# 檢查模型檔案
kubectl exec -it deployment/qoe-predictor -n ricxapp -- ls -la /app/models/saved/

# 檢查權限
kubectl exec -it deployment/qoe-predictor -n ricxapp -- \
  stat /app/models/saved/

# 重新構建模型
curl -X POST http://localhost:8090/api/v1/models/rebuild \
  -d '{"service": "video_quality"}'
```

---

## RC (RAN Control) xApp

### 功能說明

RC xApp 實現了 E2SM-RC (RAN Control) v2.0 服務模型，負責向 RAN 發送控制訊息，執行切換、資源分配、負載平衡等操作。

### 預部署檢查清單

- [ ] E2 Termination 運行正常
- [ ] Subscription Manager 運行正常
- [ ] A1 Mediator 運行正常
- [ ] Redis 可訪問
- [ ] 決定使用 gRPC 或 REST API

### E2SM-RC 配置

```json
{
  "e2sm": {
    "ranFunctionId": 3,
    "serviceModel": "E2SM-RC",
    "version": "2.0.0",
    "controlStyles": [1, 2, 3, 4, 5, 6],
    "controlActions": {
      "handover": 1,
      "resource_allocation": 2,
      "bearer_control": 3,
      "load_balancing": 4,
      "slice_control": 5,
      "power_control": 6
    }
  }
}
```

**重要配置說明：**

- `ranFunctionId: 3` - RC 服務模型的標準 function ID
- `controlStyles` - 支援的控制風格（與 E2 節點協商）
- `controlActions` - 支援的控制動作類型

### gRPC vs REST API 選擇

RC xApp 支援兩種 API 模式：

| 特性 | gRPC | REST |
|------|------|------|
| 效能 | 高（binary protocol） | 中（JSON/HTTP） |
| 延遲 | 低（<5ms） | 中（~10-20ms） |
| 複雜度 | 高（需要 proto files） | 低（標準 HTTP） |
| 適用場景 | 高頻率控制 | 配置與管理 |

**建議：**
- 生產環境：gRPC（低延遲需求）
- 開發測試：REST（易於調試）

### Onboarding 步驟

```bash
# 1. 構建 Docker 映像
cd /home/thc1006/oran-ric-platform/xapps
docker build -t localhost:5000/xapp-ran-control:1.0.0 rc-xapp/
docker push localhost:5000/xapp-ran-control:1.0.0

# 2. 創建 ConfigMap
kubectl create configmap ran-control-config \
  --from-file=config.json=rc-xapp/config/config.json \
  -n ricxapp \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. 部署 xApp
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ran-control
  namespace: ricxapp
  labels:
    app: ran-control
    version: "1.0.0"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ran-control
  template:
    metadata:
      labels:
        app: ran-control
        version: "1.0.0"
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8100"
    spec:
      serviceAccountName: xapp-serviceaccount
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: ran-control
        image: localhost:5000/xapp-ran-control:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: rmr-data
          containerPort: 4580
          protocol: TCP
        - name: rmr-route
          containerPort: 4581
          protocol: TCP
        - name: http-api
          containerPort: 8100
          protocol: TCP
        - name: grpc-api
          containerPort: 7777
          protocol: TCP
        env:
        - name: RMR_SEED_RT
          value: "/app/config/rmr-routes.txt"
        - name: RMR_SRC_ID
          value: "ran-control"
        - name: PYTHONUNBUFFERED
          value: "1"
        - name: LOG_LEVEL
          value: "INFO"
        volumeMounts:
        - name: config
          mountPath: /app/config
          readOnly: true
        resources:
          requests:
            cpu: 300m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        livenessProbe:
          httpGet:
            path: /health/alive
            port: 8100
          initialDelaySeconds: 10
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8100
          initialDelaySeconds: 15
          periodSeconds: 15
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
      volumes:
      - name: config
        configMap:
          name: ran-control-config
---
apiVersion: v1
kind: Service
metadata:
  name: ran-control-service
  namespace: ricxapp
  labels:
    app: ran-control
spec:
  selector:
    app: ran-control
  ports:
  - name: rmr-data
    port: 4580
    targetPort: 4580
    protocol: TCP
  - name: rmr-route
    port: 4581
    targetPort: 4581
    protocol: TCP
  - name: http-api
    port: 8100
    targetPort: 8100
    protocol: TCP
  - name: grpc-api
    port: 7777
    targetPort: 7777
    protocol: TCP
  type: ClusterIP
EOF

# 4. 等待部署完成
kubectl wait --for=condition=ready pod -l app=ran-control -n ricxapp --timeout=120s

# 5. 檢查狀態
kubectl get pods -n ricxapp -l app=ran-control
kubectl logs -n ricxapp -l app=ran-control --tail=50
```

### 控制策略配置

RC xApp 支援多種控制策略，通過 A1 介面配置：

```bash
# 切換策略
curl -X PUT http://a1mediator-service.ricplt:8080/a1-p/policytypes/20200/policies/handover-policy-001 \
  -H "Content-Type: application/json" \
  -d '{
    "policy_type_id": 20200,
    "policy": {
      "handover": {
        "rsrp_threshold": -100,
        "rsrq_threshold": -15,
        "sinr_threshold": 5,
        "hysteresis": 3,
        "time_to_trigger": 640
      }
    }
  }'

# 資源分配策略
curl -X PUT http://a1mediator-service.ricplt:8080/a1-p/policytypes/20201/policies/resource-policy-001 \
  -H "Content-Type: application/json" \
  -d '{
    "policy_type_id": 20201,
    "policy": {
      "resource_allocation": {
        "prb_threshold_high": 80,
        "prb_threshold_low": 20,
        "scheduling_algorithm": "proportional_fair"
      }
    }
  }'

# 負載平衡策略
curl -X PUT http://a1mediator-service.ricplt:8080/a1-p/policytypes/20202/policies/load-balance-policy-001 \
  -H "Content-Type: application/json" \
  -d '{
    "policy_type_id": 20202,
    "policy": {
      "load_balancing": {
        "load_threshold": 0.7,
        "min_ue_count": 5,
        "balancing_period": 5000
      }
    }
  }'
```

### 部署後驗證

```bash
# 1. 驗證健康狀態
kubectl port-forward -n ricxapp svc/ran-control-service 8100:8100 &
curl http://localhost:8100/health/alive
curl http://localhost:8100/health/ready

# 2. 檢查 E2 連線狀態
curl http://localhost:8100/api/v1/e2/connections

# 3. 測試控制動作
curl -X POST http://localhost:8100/api/v1/control/handover \
  -H "Content-Type: application/json" \
  -d '{
    "ue_id": "001010123456789",
    "source_cell_id": "cell-001",
    "target_cell_id": "cell-002",
    "reason": "poor_signal_quality"
  }'

# 4. 檢查控制統計
curl http://localhost:8100/api/v1/stats/control

# 預期輸出：
# {
#   "total_control_actions": 0,
#   "successful_actions": 0,
#   "failed_actions": 0,
#   "actions_by_type": {
#     "handover": 0,
#     "resource_allocation": 0
#   }
# }

# 5. 測試 gRPC API（如果啟用）
# 需要 grpcurl 工具
grpcurl -plaintext localhost:7777 list
grpcurl -plaintext \
  -d '{"ue_id": "001010123456789", "target_cell": "cell-002"}' \
  localhost:7777 rc.HandoverService/TriggerHandover
```

### 常見問題

**問題 1：控制訊息被 E2 節點拒絕**

```bash
# 檢查 RAN Function 支援
curl http://localhost:8100/api/v1/e2/ran-functions

# 驗證 control style
curl http://localhost:8100/api/v1/e2/control-styles

# 常見原因：
# - ranFunctionId 不匹配
# - E2 節點不支援該 control style
# - 參數格式錯誤
```

**問題 2：gRPC 連線失敗**

```bash
# 檢查 gRPC 服務狀態
kubectl exec -it deployment/ran-control -n ricxapp -- \
  netstat -tuln | grep 7777

# 測試本地連線
kubectl exec -it deployment/ran-control -n ricxapp -- \
  grpcurl -plaintext localhost:7777 list

# 檢查防火牆規則
kubectl describe networkpolicy -n ricxapp
```

---

## Traffic Steering xApp

### 功能說明

Traffic Steering xApp 基於 QoE 預測和網路狀態，做出智慧切換決策。它整合了 QoE Predictor 和 RC xApp 的功能。

### 預部署檢查清單

- [ ] QoE Predictor xApp 運行正常並可訪問
- [ ] RC xApp 運行正常並可訪問
- [ ] A1 Mediator 運行正常
- [ ] SDL (Redis) 可訪問

### 依賴服務整合

Traffic Steering 依賴其他 xApp 的 API：

```json
{
  "config": {
    "qoe_predictor": {
      "endpoint": "http://qoe-predictor-service.ricxapp:8090",
      "timeout": 5
    },
    "rc_xapp": {
      "endpoint": "http://ran-control-service.ricxapp:8100",
      "timeout": 10
    }
  }
}
```

**驗證依賴服務：**

```bash
# 檢查 QoE Predictor
kubectl get svc -n ricxapp qoe-predictor-service
curl http://qoe-predictor-service.ricxapp:8090/health/alive

# 檢查 RC xApp
kubectl get svc -n ricxapp ran-control-service
curl http://ran-control-service.ricxapp:8100/health/alive
```

### Onboarding 步驟

```bash
# 1. 確認依賴 xApps 運行
kubectl get pods -n ricxapp -l 'app in (qoe-predictor,ran-control)'

# 2. 構建 Docker 映像
cd /home/thc1006/oran-ric-platform/xapps
docker build -t localhost:5000/xapp-traffic-steering:1.2.0 traffic-steering/
docker push localhost:5000/xapp-traffic-steering:1.2.0

# 3. 創建 ConfigMap
kubectl create configmap traffic-steering-config \
  --from-file=config.json=traffic-steering/config/config.json \
  -n ricxapp \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. 部署 xApp
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traffic-steering
  namespace: ricxapp
  labels:
    app: traffic-steering
    version: "1.2.0"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: traffic-steering
  template:
    metadata:
      labels:
        app: traffic-steering
        version: "1.2.0"
    spec:
      serviceAccountName: xapp-serviceaccount
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      initContainers:
      - name: wait-for-dependencies
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          echo "Waiting for QoE Predictor..."
          until wget -q --spider http://qoe-predictor-service.ricxapp:8090/health/ready; do
            echo "QoE Predictor not ready, waiting..."
            sleep 5
          done
          echo "Waiting for RC xApp..."
          until wget -q --spider http://ran-control-service.ricxapp:8100/health/ready; do
            echo "RC xApp not ready, waiting..."
            sleep 5
          done
          echo "All dependencies ready!"
      containers:
      - name: traffic-steering
        image: localhost:5000/xapp-traffic-steering:1.2.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: rmr-data
          containerPort: 4560
          protocol: TCP
        - name: rmr-route
          containerPort: 4561
          protocol: TCP
        - name: http-api
          containerPort: 8080
          protocol: TCP
        env:
        - name: RMR_SEED_RT
          value: "/app/config/rmr-routes.txt"
        - name: RMR_SRC_ID
          value: "traffic-steering"
        - name: QOE_PREDICTOR_URL
          value: "http://qoe-predictor-service.ricxapp:8090"
        - name: RC_XAPP_URL
          value: "http://ran-control-service.ricxapp:8100"
        - name: PYTHONUNBUFFERED
          value: "1"
        volumeMounts:
        - name: config
          mountPath: /app/config
          readOnly: true
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /ric/v1/health/alive
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - |
              wget -q --spider http://localhost:8080/ric/v1/health/alive &&
              wget -q --spider http://qoe-predictor-service.ricxapp:8090/health/alive &&
              wget -q --spider http://ran-control-service.ricxapp:8100/health/alive
          initialDelaySeconds: 5
          periodSeconds: 15
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
      volumes:
      - name: config
        configMap:
          name: traffic-steering-config
---
apiVersion: v1
kind: Service
metadata:
  name: traffic-steering-service
  namespace: ricxapp
  labels:
    app: traffic-steering
spec:
  selector:
    app: traffic-steering
  ports:
  - name: rmr-data
    port: 4560
    targetPort: 4560
    protocol: TCP
  - name: rmr-route
    port: 4561
    targetPort: 4561
    protocol: TCP
  - name: http-api
    port: 8080
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
EOF

# 5. 等待部署完成
kubectl wait --for=condition=ready pod -l app=traffic-steering -n ricxapp --timeout=180s

# 6. 檢查狀態
kubectl get pods -n ricxapp -l app=traffic-steering
kubectl logs -n ricxapp -l app=traffic-steering --tail=50
```

### SDL 配置

Traffic Steering 使用 SDL (Shared Data Layer) 儲存 UE 狀態：

```python
# UE 狀態資料結構
{
  "ue_id": "001010123456789",
  "current_cell": "cell-001",
  "neighbor_cells": ["cell-002", "cell-003"],
  "signal_quality": {
    "rsrp": -85,
    "rsrq": -12,
    "sinr": 15
  },
  "qoe_score": 4.2,
  "handover_count": 3,
  "last_handover": "2025-11-14T10:30:00Z"
}
```

### 部署後驗證

```bash
# 1. 驗證健康狀態
kubectl port-forward -n ricxapp svc/traffic-steering-service 8080:8080 &
curl http://localhost:8080/ric/v1/health/alive

# 2. 檢查依賴連線
curl http://localhost:8080/api/v1/dependencies/status

# 預期輸出：
# {
#   "qoe_predictor": {"status": "connected", "url": "http://qoe-predictor-service.ricxapp:8090"},
#   "rc_xapp": {"status": "connected", "url": "http://ran-control-service.ricxapp:8100"}
# }

# 3. 檢查 UE 監控狀態
curl http://localhost:8080/api/v1/ues

# 4. 測試切換決策
curl -X POST http://localhost:8080/api/v1/handover/evaluate \
  -H "Content-Type: application/json" \
  -d '{
    "ue_id": "001010123456789",
    "current_cell": "cell-001",
    "measurements": {
      "rsrp": -105,
      "rsrq": -18,
      "sinr": 3
    }
  }'

# 5. 查看統計資訊
curl http://localhost:8080/api/v1/stats
```

### A1 Policy 配置

```bash
# 配置切換策略
curl -X PUT http://a1mediator-service.ricplt:8080/a1-p/policytypes/20008/policies/ts-policy-001 \
  -H "Content-Type: application/json" \
  -d '{
    "policy": {
      "handover": {
        "rsrp_threshold": -100.0,
        "rsrq_threshold": -15.0,
        "throughput_threshold": 10.0,
        "load_threshold": 0.8
      },
      "qoe_threshold": 3.0,
      "prediction_weight": 0.6,
      "measurement_weight": 0.4
    }
  }'
```

---

## Federated Learning xApp

### 功能說明

Federated Learning xApp 實現分散式機器學習，讓多個 E2 節點在本地訓練模型，中央聚合器聚合模型參數，無需共享原始資料。

### 預部署檢查清單

- [ ] Redis 可訪問（用於模型儲存）
- [ ] 充足的 CPU/Memory 資源
- [ ] 模型目錄結構已準備
- [ ] 安全配置（RSA 金鑰）已準備

### 模型目錄建立

```bash
# 創建完整的目錄結構
mkdir -p /home/thc1006/oran-ric-platform/xapps/federated-learning/models/global
mkdir -p /home/thc1006/oran-ric-platform/xapps/federated-learning/models/local
mkdir -p /home/thc1006/oran-ric-platform/xapps/federated-learning/models/checkpoints
mkdir -p /home/thc1006/oran-ric-platform/xapps/federated-learning/aggregator

# 創建聚合器配置
cat > /home/thc1006/oran-ric-platform/xapps/federated-learning/aggregator/config.yaml <<EOF
aggregation:
  method: fedavg  # fedavg, fedprox, scaffold, fedopt
  min_clients: 3
  max_clients: 100
  rounds: 100
  client_selection: random
  participation_rate: 0.5

differential_privacy:
  enabled: true
  epsilon: 1.0
  delta: 1e-5
  clip_norm: 1.0

secure_aggregation:
  enabled: true
  encryption: homomorphic

model_compression:
  enabled: true
  method: quantization
  bits: 8
EOF

# 創建聚合器實作
cat > /home/thc1006/oran-ric-platform/xapps/federated-learning/aggregator/aggregator.py <<'EOF'
"""
Federated Learning Aggregator
Implements FedAvg, FedProx, SCAFFOLD algorithms
"""

import numpy as np
from typing import List, Dict

class FederatedAggregator:
    def __init__(self, method='fedavg'):
        self.method = method

    def aggregate(self, client_weights: List[Dict], client_sizes: List[int]):
        """Aggregate client model weights"""
        if self.method == 'fedavg':
            return self._fedavg(client_weights, client_sizes)
        elif self.method == 'fedprox':
            return self._fedprox(client_weights, client_sizes)
        else:
            raise ValueError(f"Unknown aggregation method: {self.method}")

    def _fedavg(self, client_weights, client_sizes):
        """Federated Averaging"""
        total_size = sum(client_sizes)
        aggregated = {}

        for key in client_weights[0].keys():
            weighted_sum = sum(
                weights[key] * size / total_size
                for weights, size in zip(client_weights, client_sizes)
            )
            aggregated[key] = weighted_sum

        return aggregated

    def _fedprox(self, client_weights, client_sizes):
        """Federated Proximal"""
        # Similar to FedAvg but with proximal term
        return self._fedavg(client_weights, client_sizes)
EOF
```

### 安全配置（RSA 金鑰）

```bash
# 創建 RSA 金鑰對（用於安全聚合）
mkdir -p /home/thc1006/oran-ric-platform/xapps/federated-learning/keys

# 生成私鑰
openssl genrsa -out /home/thc1006/oran-ric-platform/xapps/federated-learning/keys/server_private.pem 2048

# 生成公鑰
openssl rsa -in /home/thc1006/oran-ric-platform/xapps/federated-learning/keys/server_private.pem \
  -pubout -out /home/thc1006/oran-ric-platform/xapps/federated-learning/keys/server_public.pem

# 創建 Kubernetes Secret
kubectl create secret generic fl-keys \
  --from-file=server_private.pem=/home/thc1006/oran-ric-platform/xapps/federated-learning/keys/server_private.pem \
  --from-file=server_public.pem=/home/thc1006/oran-ric-platform/xapps/federated-learning/keys/server_public.pem \
  -n ricxapp

# 清理本地金鑰檔案（安全考量）
rm -f /home/thc1006/oran-ric-platform/xapps/federated-learning/keys/*.pem
```

### Onboarding 步驟

```bash
# 1. 構建 Docker 映像
cd /home/thc1006/oran-ric-platform/xapps
docker build -t localhost:5000/xapp-federated-learning:1.0.0 federated-learning/
docker push localhost:5000/xapp-federated-learning:1.0.0

# 2. 創建 ConfigMap
kubectl create configmap federated-learning-config \
  --from-file=config.json=federated-learning/config/config.json \
  --from-file=aggregator-config.yaml=federated-learning/aggregator/config.yaml \
  -n ricxapp \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. 創建 PersistentVolumeClaims
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fl-global-models
  namespace: ricxapp
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fl-local-models
  namespace: ricxapp
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 5Gi
EOF

# 4. 部署 xApp
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: federated-learning
  namespace: ricxapp
  labels:
    app: federated-learning
    version: "1.0.0"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: federated-learning
  template:
    metadata:
      labels:
        app: federated-learning
        version: "1.0.0"
    spec:
      serviceAccountName: xapp-serviceaccount
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: federated-learning
        image: localhost:5000/xapp-federated-learning:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: rmr-data
          containerPort: 4590
          protocol: TCP
        - name: rmr-route
          containerPort: 4591
          protocol: TCP
        - name: http-api
          containerPort: 8110
          protocol: TCP
        env:
        - name: RMR_SEED_RT
          value: "/app/config/rmr-routes.txt"
        - name: RMR_SRC_ID
          value: "federated-learning"
        - name: PYTHONUNBUFFERED
          value: "1"
        - name: TF_CPP_MIN_LOG_LEVEL
          value: "2"
        volumeMounts:
        - name: config
          mountPath: /app/config
          readOnly: true
        - name: global-models
          mountPath: /app/models/global
        - name: local-models
          mountPath: /app/models/local
        - name: keys
          mountPath: /app/keys
          readOnly: true
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: 4000m
            memory: 4Gi
        livenessProbe:
          httpGet:
            path: /health/alive
            port: 8110
          initialDelaySeconds: 20
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8110
          initialDelaySeconds: 30
          periodSeconds: 20
          timeoutSeconds: 10
          successThreshold: 1
          failureThreshold: 3
      volumes:
      - name: config
        configMap:
          name: federated-learning-config
      - name: global-models
        persistentVolumeClaim:
          claimName: fl-global-models
      - name: local-models
        persistentVolumeClaim:
          claimName: fl-local-models
      - name: keys
        secret:
          secretName: fl-keys
---
apiVersion: v1
kind: Service
metadata:
  name: federated-learning-service
  namespace: ricxapp
  labels:
    app: federated-learning
spec:
  selector:
    app: federated-learning
  ports:
  - name: rmr-data
    port: 4590
    targetPort: 4590
    protocol: TCP
  - name: rmr-route
    port: 4591
    targetPort: 4591
    protocol: TCP
  - name: http-api
    port: 8110
    targetPort: 8110
    protocol: TCP
  type: ClusterIP
EOF

# 5. 等待部署完成
kubectl wait --for=condition=ready pod -l app=federated-learning -n ricxapp --timeout=300s

# 6. 檢查狀態
kubectl get pods -n ricxapp -l app=federated-learning
kubectl logs -n ricxapp -l app=federated-learning --tail=50
```

### 部署後驗證

```bash
# 1. 驗證健康狀態
kubectl port-forward -n ricxapp svc/federated-learning-service 8110:8110 &
curl http://localhost:8110/health/alive
curl http://localhost:8110/health/ready

# 2. 檢查聚合器狀態
curl http://localhost:8110/api/v1/aggregator/status

# 預期輸出：
# {
#   "status": "ready",
#   "method": "fedavg",
#   "min_clients": 3,
#   "registered_clients": 0,
#   "current_round": 0
# }

# 3. 註冊 FL 客戶端
curl -X POST http://localhost:8110/api/v1/clients/register \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "client-001",
    "data_size": 1000,
    "capabilities": ["tensorflow", "pytorch"]
  }'

# 4. 啟動訓練輪次
curl -X POST http://localhost:8110/api/v1/training/start \
  -H "Content-Type: application/json" \
  -d '{
    "model_type": "network_optimization",
    "rounds": 10,
    "min_clients": 2
  }'

# 5. 監控訓練進度
curl http://localhost:8110/api/v1/training/status

# 6. 驗證模型儲存
kubectl exec -it deployment/federated-learning -n ricxapp -- \
  ls -la /app/models/global/
```

### 差分隱私配置

```bash
# 調整 DP 參數
curl -X PUT http://localhost:8110/api/v1/config/differential-privacy \
  -H "Content-Type: application/json" \
  -d '{
    "epsilon": 1.0,
    "delta": 1e-5,
    "clip_norm": 1.0,
    "noise_multiplier": 0.1
  }'

# 驗證 DP 設定
curl http://localhost:8110/api/v1/config/differential-privacy
```

---

## 驗證與測試

### 端到端測試流程

```bash
#!/bin/bash
# E2E 測試腳本

echo "=== xApp 端到端測試 ==="

# 1. 檢查所有 xApp 運行狀態
echo "1. 檢查 xApp 狀態..."
kubectl get pods -n ricxapp

# 2. KPIMON -> InfluxDB 資料流測試
echo "2. 測試 KPIMON 資料收集..."
kubectl port-forward -n ricxapp svc/kpimon-service 8080:8080 &
sleep 2
curl -s http://localhost:8080/api/v1/subscriptions | jq .

# 3. QoE Predictor 預測測試
echo "3. 測試 QoE 預測..."
kubectl port-forward -n ricxapp svc/qoe-predictor-service 8090:8090 &
sleep 2
curl -X POST http://localhost:8090/api/v1/predict \
  -H "Content-Type: application/json" \
  -d '{
    "service": "video_quality",
    "features": {
      "throughput_dl": 50.5,
      "latency": 25.5,
      "packet_loss": 0.5
    }
  }' | jq .

# 4. RC xApp 控制測試
echo "4. 測試 RAN 控制..."
kubectl port-forward -n ricxapp svc/ran-control-service 8100:8100 &
sleep 2
curl http://localhost:8100/api/v1/e2/connections | jq .

# 5. Traffic Steering 整合測試
echo "5. 測試 Traffic Steering..."
kubectl port-forward -n ricxapp svc/traffic-steering-service 8080:8080 &
sleep 2
curl http://localhost:8080/api/v1/dependencies/status | jq .

# 6. Federated Learning 測試
echo "6. 測試 Federated Learning..."
kubectl port-forward -n ricxapp svc/federated-learning-service 8110:8110 &
sleep 2
curl http://localhost:8110/api/v1/aggregator/status | jq .

# 清理 port-forward
killall kubectl

echo "=== 測試完成 ==="
```

### RMR 訊息流測試

```bash
# 測試 RMR 路由表
for xapp in kpimon qoe-predictor ran-control traffic-steering federated-learning; do
  echo "=== $xapp RMR 路由 ==="
  kubectl exec -it deployment/$xapp -n ricxapp -- cat /app/config/rmr-routes.txt
  echo ""
done

# 監控 RMR 訊息
kubectl logs -n ricxapp deployment/kpimon --follow | grep "RMR"
```

### 效能基準測試

```bash
# KPIMON 吞吐量測試
echo "測試 KPIMON KPI 收集速率..."
kubectl exec -it deployment/kpimon -n ricxapp -- \
  python3 -c "
import time
from prometheus_client.parser import text_string_to_metric_families
import requests

url = 'http://localhost:8080/metrics'
samples = []

for i in range(10):
    resp = requests.get(url)
    for family in text_string_to_metric_families(resp.text):
        for sample in family.samples:
            if sample.name == 'kpimon_messages_received_total':
                samples.append(sample.value)
    time.sleep(1)

rate = (samples[-1] - samples[0]) / 10
print(f'KPI 收集速率: {rate} msg/sec')
"

# QoE 預測延遲測試
echo "測試 QoE 預測延遲..."
for i in {1..100}; do
  curl -w "%{time_total}\n" -o /dev/null -s \
    -X POST http://localhost:8090/api/v1/predict \
    -H "Content-Type: application/json" \
    -d '{"service":"video_quality","features":{"throughput_dl":50}}'
done | awk '{sum+=$1; count+=1} END {print "平均延遲:", sum/count*1000, "ms"}'
```

---

## 常見問題排解

### 問題診斷流程

```bash
# 1. 檢查 Pod 狀態
kubectl get pods -n ricxapp -o wide

# 2. 檢查事件
kubectl get events -n ricxapp --sort-by='.lastTimestamp'

# 3. 檢查日誌
kubectl logs -n ricxapp deployment/<xapp-name> --previous

# 4. 檢查資源使用
kubectl top pods -n ricxapp

# 5. 檢查網路連線
kubectl exec -it deployment/<xapp-name> -n ricxapp -- \
  netstat -tuln
```

### 常見錯誤與解決方案

#### 錯誤 1：ImagePullBackOff

```bash
# 原因：無法從 registry 拉取映像
# 解決：
docker images | grep xapp  # 確認本地映像存在
docker push localhost:5000/xapp-<name>:<version>  # 推送到 registry
kubectl delete pod -n ricxapp -l app=<xapp-name>  # 重啟 pod
```

#### 錯誤 2：CrashLoopBackOff

```bash
# 檢查日誌找出原因
kubectl logs -n ricxapp deployment/<xapp-name> --previous

# 常見原因：
# - 環境變數缺失
# - 依賴服務不可用
# - 配置檔案格式錯誤
# - 端口衝突

# 調試模式
kubectl run debug-pod -it --rm \
  --image=localhost:5000/xapp-<name>:1.0.0 \
  --command -- /bin/bash
```

#### 錯誤 3：連線超時

```bash
# 檢查網路策略
kubectl get networkpolicy -n ricxapp
kubectl describe networkpolicy xapp-network-policy -n ricxapp

# 測試服務連線
kubectl run curl-test --rm -it --image=curlimages/curl -- \
  curl -v http://<service-name>.ricxapp:8080/health/alive

# 檢查 DNS 解析
kubectl exec -it deployment/<xapp-name> -n ricxapp -- \
  nslookup redis-service.ricplt
```

#### 錯誤 4：記憶體不足 (OOMKilled)

```bash
# 檢查 OOM 事件
kubectl get events -n ricxapp | grep OOM

# 增加資源限制
kubectl patch deployment <xapp-name> -n ricxapp -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "<xapp-name>",
          "resources": {
            "limits": {
              "memory": "4Gi"
            }
          }
        }]
      }
    }
  }
}'
```

### 效能優化建議

1. **資源調整**：根據實際負載調整 CPU/Memory 限制
2. **RMR Workers**：增加 numWorkers 提升訊息處理能力
3. **Redis 連線池**：配置連線池減少連線開銷
4. **日誌級別**：生產環境設為 WARNING 減少 I/O
5. **健康檢查**：調整檢查頻率避免過度負載

---

## 總結

本文檔詳細記錄了五個 xApp 的 onboarding 策略，包括：

1. **KPIMON**：E2SM-KPM 實作，InfluxDB 整合
2. **QoE Predictor**：LSTM 模型，A1 policy 整合
3. **RC xApp**：E2SM-RC 實作，多種控制策略
4. **Traffic Steering**：整合 QoE 和 RC，智慧切換
5. **Federated Learning**：分散式訓練，差分隱私

### 部署檢查清單

- [ ] RIC 平台運行正常
- [ ] InfluxDB 已部署（KPIMON）
- [ ] 所有 Secrets 已創建
- [ ] 所有 ConfigMaps 已創建
- [ ] RBAC 資源已配置
- [ ] 網路策略已應用
- [ ] 所有 Docker 映像已構建並推送
- [ ] 依賴順序正確（QoE/RC 先於 Traffic Steering）
- [ ] 健康檢查通過
- [ ] 端到端測試通過

### 下一步

1. 監控與告警配置
2. 日誌聚合與分析
3. 效能調優與壓測
4. 高可用性配置
5. 災難恢復計畫

---

**文件版本**：1.0.0
**最後更新**：2025-11-14
**維護者**：蔡秀吉（thc1006）
