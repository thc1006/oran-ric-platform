# Traffic Steering xApp 部署指南

作者：蔡秀吉（thc1006）
日期：2025-11-14
版本：1.0.0

## 概述

本文檔記錄了 Traffic Steering xApp 在 O-RAN Near-RT RIC J Release 平台上的完整部署過程，包括遇到的問題、troubleshooting 步驟以及解決方案。

## 環境資訊

- **平台**: O-RAN Near-RT RIC J Release
- **Kubernetes**: k3s v1.28.5
- **Python**: 3.11
- **ricxappframe**: 3.2.2
- **ricsdl**: 3.0.2
- **Redis**: 4.1.1

## Traffic Steering xApp 功能

Traffic Steering xApp 實現了基於策略的切換決策功能，主要特性包括：

- 從 E2SM-KPM 接收 UE 性能指標（RSRP、RSRQ、吞吐量等）
- 根據 A1 策略評估切換條件
- 與 QoE Predictor 協作選擇目標小區
- 通過 RC xApp 發送切換命令
- 支持動態策略更新
- 提供 RESTful 健康檢查接口

## 部署前置條件

1. k3s 集群正常運行
2. RIC 平台基礎組件已部署（E2 Term、A1 Mediator、Route Manager等）
3. 本地 Docker registry 運行在 `localhost:5000`
4. kubectl 配置正確（KUBECONFIG=/etc/rancher/k3s/k3s.yaml）

## 部署步驟

### 第一階段：依賴版本修正

#### 問題發現
初始的 `requirements.txt` 使用了不兼容的依賴版本：
```python
ricxappframe==3.2.1  # 過時版本
redis==5.0.1         # 與 ricsdl 不兼容
hiredis==2.3.2
```

#### 解決方案
根據 Phase 1（KPIMON 和 RC xApp）的成功經驗，更新為兼容版本：

修改 `xapps/traffic-steering/requirements.txt`:
```python
# O-RAN xApp Framework
ricxappframe==3.2.2
ricsdl==3.0.2       # 使用 ricsdl 3.0.2 搭配其指定的 redis 4.1.1
mdclogpy==1.1.4

# Data Storage
redis==4.1.1        # ricsdl 3.0.2 requires redis==4.1.1
hiredis==2.0.0
```

**重點**：ricsdl 3.0.2 版本與 redis 4.1.1 版本相容，這是在 Phase 1 中驗證過的組合。

### 第二階段：Dockerfile 優化

#### 問題發現
Dockerfile 未明確安裝 ricsdl，導致可能的依賴衝突。

#### 解決方案
修改 `xapps/traffic-steering/Dockerfile`，在安裝其他依賴前先安裝 ricsdl：

```dockerfile
# Install Python dependencies
# Install ricsdl 3.0.2 first to ensure compatibility with redis 4.x
COPY requirements.txt .
RUN pip install --no-cache-dir ricsdl==3.0.2 && \
    pip install --no-cache-dir -r requirements.txt
```

同時移除不需要的 health_check.sh 引用：
```dockerfile
# 移除這些行（健康檢查由 Kubernetes 處理）
# COPY --chown=xapp:xapp health_check.sh /usr/local/bin/
# RUN chmod +x /usr/local/bin/health_check.sh
```

### 第三階段：Kubernetes 部署清單

#### 創建 ConfigMap

文件：`xapps/traffic-steering/deploy/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: traffic-steering-config
  namespace: ricxapp
data:
  rmr-routes.txt: |
    # RMR Routing Table for Traffic Steering xApp
    newrt|start
    # RIC Subscription Messages
    rte|12010|service-ricplt-e2term-rmr-alpha.ricplt:4560
    rte|12011|traffic-steering.ricxapp:4560
    rte|12012|service-ricplt-e2term-rmr-alpha.ricplt:4560
    rte|12013|traffic-steering.ricxapp:4560
    # RIC Indication Messages
    rte|12050|traffic-steering.ricxapp:4560
    # RIC Control Messages
    rte|12040|service-ricplt-e2term-rmr-alpha.ricplt:4560
    rte|12041|traffic-steering.ricxapp:4560
    # A1 Policy Messages
    rte|20010|traffic-steering.ricxapp:4560
    rte|20011|service-ricplt-a1mediator-rmr.ricplt:4562
    newrt|end

  config.json: |
    {
      "xapp_name": "traffic-steering",
      "version": "1.0.0",
      "handover": {
        "rsrp_threshold": -100.0,
        "rsrq_threshold": -15.0,
        "throughput_threshold": 10.0,
        "load_threshold": 0.8
      },
      "logging": {
        "level": "INFO"
      }
    }
```

#### 創建 Service

文件：`xapps/traffic-steering/deploy/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: traffic-steering
  namespace: ricxapp
  labels:
    app: traffic-steering
    xapp: traffic-steering
spec:
  type: ClusterIP
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
  selector:
    app: traffic-steering
```

#### 創建 Deployment

文件：`xapps/traffic-steering/deploy/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traffic-steering
  namespace: ricxapp
  labels:
    app: traffic-steering
    xapp: traffic-steering
spec:
  replicas: 1
  selector:
    matchLabels:
      app: traffic-steering
  template:
    metadata:
      labels:
        app: traffic-steering
        xapp: traffic-steering
    spec:
      containers:
      - name: traffic-steering
        image: localhost:5000/xapp-traffic-steering:1.0.0
        imagePullPolicy: Always
        env:
        - name: RMR_SEED_RT
          value: "/app/config/rmr-routes.txt"
        - name: RMR_SRC_ID
          value: "traffic-steering"
        - name: RMR_RTG_SVC
          value: "service-ricplt-rtmgr-rmr.ricplt:4561"
        - name: SDL_NAMESPACE
          value: "traffic-steering"
        - name: LOG_LEVEL
          value: "INFO"
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
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        volumeMounts:
        - name: config-volume
          mountPath: /app/config
        livenessProbe:
          httpGet:
            path: /ric/v1/health/alive
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ric/v1/health/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 15
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
      volumes:
      - name: config-volume
        configMap:
          name: traffic-steering-config
```

### 第四階段：RMR API 重構（關鍵問題）

#### 問題發現

初次部署後，pod 不斷重啟，日誌顯示：

```
AttributeError: 'TrafficSteeringXapp' object has no attribute 'rmr_alloc'
```

在 `create_subscriptions()` 方法中調用 `self.rmr_alloc()` 失敗。

#### 根本原因分析

原始代碼使用了**繼承模式**和**過時的 RMR API**：
```python
class TrafficSteeringXapp(RMRXapp):  # 繼承
    def create_subscriptions(self):
        sbuf = self.rmr_alloc()  # 此方法不存在！
```

對比成功運行的 KPIMON xApp (Phase 1)，發現其使用**組合模式**：
```python
class KPIMonitor:  # 不繼承 RMRXapp
    def __init__(self):
        self.xapp = RMRXapp(...)  # 組合

    def _send_message(self, msg_type: int, payload: str):
        self.xapp.rmr_send(payload.encode(), msg_type)  # 直接發送
```

**關鍵差異**：
1. KPIMON 使用組合（composition）而非繼承（inheritance）
2. KPIMON 不使用 `rmr_alloc()`，直接調用 `rmr_send()`
3. KPIMON 實現了簡單的 `_send_message()` 輔助方法

#### 解決方案

完全重構 `xapps/traffic-steering/src/traffic_steering.py`：

**變更 1：從繼承改為組合**
```python
# 之前（錯誤）
class TrafficSteeringXapp(RMRXapp):
    def __init__(self):
        super().__init__(...)

# 之後（正確）
class TrafficSteeringXapp:
    def __init__(self):
        self.xapp = None  # 將在 start() 中初始化
```

**變更 2：添加 _send_message() 輔助方法**
```python
def _send_message(self, msg_type: int, payload: str):
    """Send RMR message"""
    if self.xapp:
        success = self.xapp.rmr_send(payload.encode(), msg_type)
        if not success:
            logger.error(f"Failed to send message type {msg_type}")
```

**變更 3：替換所有 rmr_alloc() 調用**
```python
# 之前（錯誤）
def create_subscriptions(self):
    sbuf = self.rmr_alloc()
    sbuf.contents.mtype = RIC_SUB_REQ
    sbuf.contents.payload = json.dumps(kpm_subscription).encode()
    sbuf.contents.len = len(sbuf.contents.payload)
    sbuf = self.rmr_send(sbuf, retry=True)

# 之後（正確）
def create_subscriptions(self):
    kpm_subscription = {...}
    self._send_message(RIC_SUB_REQ, json.dumps(kpm_subscription))
```

**變更 4：在 start() 中初始化 RMRXapp**
```python
def start(self):
    logger.info("Starting Traffic Steering xApp")
    self.running = True

    # Start Flask health check server
    flask_thread = Thread(target=lambda: self.app.run(host='0.0.0.0', port=8080))
    flask_thread.daemon = True
    flask_thread.start()

    # Initialize RMR xApp
    self.xapp = RMRXapp(self._handle_message,
                        rmr_port=4560,
                        use_fake_sdl=False)

    # Start health check thread
    health_thread = Thread(target=self._health_check_loop)
    health_thread.daemon = True
    health_thread.start()

    time.sleep(2)  # Ensure RMR is ready

    # Create E2 subscriptions
    self.create_subscriptions()

    # Start RMR message loop
    self.xapp.run()
```

**變更 5：添加 Flask 健康檢查端點**
```python
def _setup_routes(self):
    """Setup Flask routes for health checks"""
    @self.app.route('/ric/v1/health/alive', methods=['GET'])
    def health_alive():
        return jsonify({"status": "alive"}), 200

    @self.app.route('/ric/v1/health/ready', methods=['GET'])
    def health_ready():
        return jsonify({"status": "ready"}), 200
```

### 第五階段：構建和部署

#### 構建 Docker 映像

重要：初次構建使用 `--no-cache` 以確保使用最新代碼：

```bash
cd /home/thc1006/oran-ric-platform/xapps/traffic-steering
docker build --no-cache -t localhost:5000/xapp-traffic-steering:1.0.0 .
```

#### 推送到本地 registry

```bash
docker push localhost:5000/xapp-traffic-steering:1.0.0
```

#### 部署到 Kubernetes

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl apply -f /home/thc1006/oran-ric-platform/xapps/traffic-steering/deploy/
```

#### 驗證部署

```bash
# 檢查 pod 狀態
kubectl get pods -n ricxapp -l app=traffic-steering

# 檢查日誌
kubectl logs -n ricxapp -l app=traffic-steering --tail=50

# 檢查服務
kubectl get svc -n ricxapp traffic-steering
```

**預期輸出**：
```
NAME                                READY   STATUS    RESTARTS   AGE
traffic-steering-754fc58fdc-27p9x   1/1     Running   0          2m

NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
traffic-steering   ClusterIP   10.43.213.53   <none>        4560/TCP,4561/TCP,8080/TCP   10m
```

## 故障排除指南

### 問題 1：pod 持續重啟

**症狀**：
```
NAME                                READY   STATUS             RESTARTS   AGE
traffic-steering-xxxx               0/1     CrashLoopBackOff   3          2m
```

**檢查日誌**：
```bash
kubectl logs -n ricxapp <pod-name> --tail=100
```

**可能原因和解決方案**：

1. **rmr_alloc 錯誤**（本次遇到的問題）
   - 錯誤訊息：`AttributeError: 'TrafficSteeringXapp' object has no attribute 'rmr_alloc'`
   - 解決：按照第四階段重構代碼

2. **依賴版本不兼容**
   - 錯誤訊息：`ModuleNotFoundError: No module named 'redis._compat'`
   - 解決：檢查 ricsdl 和 redis 版本（使用 3.0.2 和 4.1.1）

3. **ConfigMap 未掛載**
   - 錯誤訊息：`FileNotFoundError: /app/config/config.json`
   - 解決：檢查 deployment.yaml 中的 volumeMounts 配置

### 問題 2：健康檢查失敗

**症狀**：
```
Readiness probe failed: Get "http://10.42.0.223:8080/ric/v1/health/ready": dial tcp 10.42.0.223:8080: connect: connection refused
```

**可能原因**：
1. Flask 未正確啟動
2. 埠號配置錯誤
3. xApp 初始化失敗

**解決方案**：
1. 確認 Flask 在 start() 方法中啟動
2. 確認埠號為 8080
3. 檢查日誌確認 xApp 初始化成功

### 問題 3：Docker 緩存導致舊代碼

**症狀**：
修改代碼後重建映像，但運行的仍是舊代碼。

**解決方案**：
```bash
# 使用 --no-cache 強制重建
docker build --no-cache -t localhost:5000/xapp-traffic-steering:1.0.0 .

# 或刪除舊映像後重建
docker rmi localhost:5000/xapp-traffic-steering:1.0.0
docker build -t localhost:5000/xapp-traffic-steering:1.0.0 .
```

### 問題 4：kubectl 無法連接 API server

**症狀**：
```
error validating data: failed to download openapi: Get "http://localhost:8080/openapi/v2?timeout=32s": dial tcp [::1]:8080: connect: connection refused
```

**解決方案**：
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# 在每個 kubectl 命令前添加 export
```

## 重要經驗總結

### 1. ricxappframe 3.2.2 正確使用方式

**不要**使用繼承和 buffer 分配：
```python
# 錯誤方式
class MyXapp(RMRXapp):
    def send_msg(self):
        sbuf = self.rmr_alloc()  # 這個方法不存在！
```

**應該**使用組合和直接發送：
```python
# 正確方式
class MyXapp:
    def __init__(self):
        self.xapp = RMRXapp(self._handle_message, rmr_port=4560, use_fake_sdl=False)

    def _send_message(self, msg_type: int, payload: str):
        self.xapp.rmr_send(payload.encode(), msg_type)
```

### 2. 依賴版本管理

關鍵依賴組合（已驗證）：
- ricxappframe==3.2.2
- ricsdl==3.0.2
- redis==4.1.1
- hiredis==2.0.0

不要隨意更新這些版本，除非經過完整測試。

### 3. 健康檢查實現

Kubernetes 健康檢查需要：
1. `/ric/v1/health/alive`：liveness probe
2. `/ric/v1/health/ready`：readiness probe
3. 使用 Flask 而非外部腳本
4. 在獨立線程中運行

### 4. Docker 構建最佳實踐

1. 安裝依賴順序很重要：先安裝 ricsdl，再安裝其他依賴
2. 代碼修改後使用 `--no-cache` 重建
3. 每次修改後驗證映像已更新：`docker images | grep traffic-steering`

### 5. RMR 路由配置

確保路由表中包含所有必要的消息類型：
- 12010/12011：訂閱請求/響應
- 12050：指示消息
- 12040/12041：控制請求/響應
- 20010/20011：A1 策略請求/響應

## 部署後驗證清單

- [ ] pod 狀態為 Running (1/1)
- [ ] 健康檢查通過（readiness 和 liveness）
- [ ] 日誌中無 ERROR（除了預期的 "Failed to send" 當無 E2 Term 時）
- [ ] Service endpoints 可訪問
- [ ] ConfigMap 正確掛載
- [ ] RMR 路由表加載成功

## 與 KPIMON/RC xApp 的對比

| 特性 | KPIMON/RC xApp | Traffic Steering xApp |
|------|----------------|----------------------|
| 架構模式 | 組合（composition） | 組合（composition）- 修正後 |
| RMR 發送 | `self.xapp.rmr_send()` | `self.xapp.rmr_send()` |
| 健康檢查 | Flask routes | Flask routes |
| ricsdl 版本 | 3.0.2 | 3.0.2 |
| redis 版本 | 4.1.1 | 4.1.1 |

## 後續工作建議

1. **E2 集成測試**：連接實際的 E2 Term 和 RAN 進行端到端測試
2. **A1 策略測試**：驗證動態策略更新功能
3. **性能測試**：測試高負載下的切換決策性能
4. **日誌增強**：添加更詳細的 metrics 和 tracing
5. **錯誤處理**：增強異常情況處理和恢復機制

## 參考資料

- O-RAN SC ricxappframe: https://gerrit.o-ran-sc.org/r/ric-plt/xapp-frame-py
- E2SM-KPM v3.0: O-RAN.WG3.E2SM-KPM-v03.00
- E2SM-RC v2.0: O-RAN.WG3.E2SM-RC-v02.00
- Phase 1 部署文檔：KPIMON 和 RC xApp 部署經驗

---

**更新記錄**：
- 2025-11-14：初始版本，記錄完整部署過程和 RMR API 重構

**維護者**：蔡秀吉（thc1006）
