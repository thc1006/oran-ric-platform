# 所有 xApp 部署與健康檢查實作指南

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-15
**版本**: 1.0

---

## 1. 概述

本文件記錄了在 O-RAN RIC Platform J Release 上完整部署所有 5 個 xApp 的過程，並實作了健康檢查機制。部署過程中遇到多個關鍵問題，本文詳細記錄每個問題的排查與解決過程。

### 1.1 部署的 xApps

| xApp 名稱 | 功能 | HTTP Port | RMR Port | 健康檢查路徑 |
|---------|------|-----------|----------|------------|
| KPIMON | KPI 監控 | 8081 | 4560 | /health/alive, /health/ready |
| RC (RAN Control) | RAN 控制 | 8100 | 4560 | /health/alive, /health/ready |
| QoE Predictor | QoE 預測 | 8090 | 4570-4571 | /health/alive, /health/ready |
| Traffic Steering | 流量導向 | 8080 | 4560 | /ric/v1/health/alive, /ric/v1/health/ready |
| Federated Learning | 聯邦學習 | 8110 | 4590-4591 | /health/alive, /health/ready |

### 1.2 部署環境

- **Kubernetes**: k3s v1.28.5+k3s1
- **節點數量**: 單節點（本地測試環境）
- **RIC Platform**: J Release，8 個核心組件運行中
- **Container Runtime**: Docker with local registry (localhost:5000)

---

## 2. 核心問題與解決方案

### 2.1 問題一：Kubernetes SecurityContext fsGroup 配置錯誤

#### 問題描述

部署 QoE Predictor 和 Federated Learning xApp 時遇到以下錯誤：

```
Error from server (BadRequest): error when creating "deployment.yaml":
Deployment in version "v1" cannot be handled as a Deployment:
strict decoding error: unknown field "spec.template.spec.containers[0].securityContext.fsGroup"
```

#### 根本原因

`fsGroup` 是 Pod 級別的 SecurityContext 欄位，而非 Container 級別。錯誤地將其放在 `spec.template.spec.containers[0].securityContext` 中會導致 Kubernetes API 驗證失敗。

#### 錯誤配置範例

```yaml
# ❌ 錯誤：fsGroup 放在 container 級別
spec:
  template:
    spec:
      serviceAccountName: qoe-predictor-sa
      containers:
      - name: qoe-predictor
        image: localhost:5000/xapp-qoe-predictor:1.0.0
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          fsGroup: 1000  # ❌ 錯誤位置
          allowPrivilegeEscalation: false
```

#### 正確配置

```yaml
# ✅ 正確：fsGroup 在 pod 級別，其他安全選項在 container 級別
spec:
  template:
    spec:
      serviceAccountName: qoe-predictor-sa
      securityContext:
        fsGroup: 1000  # ✅ Pod 級別 SecurityContext
      containers:
      - name: qoe-predictor
        image: localhost:5000/xapp-qoe-predictor:1.0.0
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: false
```

#### 解決步驟

1. 編輯 `deployment.yaml`:
```bash
vim xapps/qoe-predictor/deploy/deployment.yaml
```

2. 將 `fsGroup: 1000` 從 container 級別的 `securityContext` 移動到 pod 級別

3. 重新部署：
```bash
kubectl delete -f xapps/qoe-predictor/deploy/ --ignore-not-found
kubectl apply -f xapps/qoe-predictor/deploy/
```

#### 影響範圍

此問題影響以下 xApps：
- QoE Predictor (deployment.yaml)
- Federated Learning (deployment.yaml, deployment-gpu.yaml)

### 2.2 問題二：Logger 模組導入錯誤

#### 問題描述

QoE Predictor 和 Federated Learning xApp Pod 啟動後立即崩潰，查看日誌發現以下錯誤：

```python
Traceback (most recent call last):
  File "/app/src/qoe_predictor.py", line 26, in <module>
    from ricxappframe.mdclogger import Logger
ModuleNotFoundError: No module named 'ricxappframe.mdclogger'
```

#### 根本原因

O-RAN xApp Framework 3.2.2 版本中，MDC Logger 是一個獨立的套件 `mdclogpy`，而不是 `ricxappframe` 的子模組。錯誤的導入路徑會導致 ModuleNotFoundError。

#### 錯誤代碼

```python
# ❌ 錯誤的導入路徑
from ricxappframe.mdclogger import Logger
```

#### 正確代碼

```python
# ✅ 正確的導入路徑
from mdclogpy import Logger
```

#### 解決步驟

1. 修改 QoE Predictor 源代碼：
```bash
vim xapps/qoe-predictor/src/qoe_predictor.py
```

修改第 26 行：
```python
from mdclogpy import Logger
```

2. 修改 Federated Learning 源代碼：
```bash
vim xapps/federated-learning/src/federated_learning.py
```

修改第 27 行：
```python
from mdclogpy import Logger
```

3. 重新構建 Docker 映像：
```bash
# QoE Predictor
cd xapps/qoe-predictor
docker build -t localhost:5000/xapp-qoe-predictor:1.0.0 .
docker push localhost:5000/xapp-qoe-predictor:1.0.0

# Federated Learning
cd xapps/federated-learning
docker build -t localhost:5000/xapp-federated-learning:1.0.0 .
docker push localhost:5000/xapp-federated-learning:1.0.0
```

#### 依賴版本確認

requirements.txt 中的正確配置：
```txt
ricxappframe==3.2.2
mdclogpy==1.1.4  # 獨立套件
```

### 2.3 問題三：Docker 映像未更新

#### 問題描述

修正代碼並重新構建映像後，Pod 仍然使用舊映像並報告相同的錯誤。

#### 根本原因

Deployment 配置中使用 `imagePullPolicy: IfNotPresent`，Kubernetes 在本地已有該映像時不會重新拉取。這在開發過程中頻繁更新映像時會造成問題。

#### 錯誤配置

```yaml
containers:
- name: qoe-predictor
  image: localhost:5000/xapp-qoe-predictor:1.0.0
  imagePullPolicy: IfNotPresent  # ❌ 開發環境不建議
```

#### 正確配置

```yaml
containers:
- name: qoe-predictor
  image: localhost:5000/xapp-qoe-predictor:1.0.0
  imagePullPolicy: Always  # ✅ 總是拉取最新映像
```

#### 解決步驟

1. 修改 deployment.yaml：
```bash
vim xapps/qoe-predictor/deploy/deployment.yaml
```

將 `imagePullPolicy` 改為 `Always`。

2. 重新部署：
```bash
kubectl delete deployment qoe-predictor -n ricxapp
kubectl apply -f xapps/qoe-predictor/deploy/deployment.yaml
```

#### 最佳實務建議

- **開發環境**：使用 `imagePullPolicy: Always` 確保總是使用最新映像
- **生產環境**：使用 `imagePullPolicy: IfNotPresent` 並搭配明確的版本標籤（如 `v1.0.1`, `v1.0.2`）

---

## 3. 完整部署流程

### 3.1 前置條件檢查

```bash
# 確認 k3s 運行正常
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes

# 確認 RIC Platform 所有組件運行
kubectl get pods -n ricplt

# 確認 local registry 可用
curl http://localhost:5000/v2/_catalog
```

預期輸出：
```
NAME      STATUS   ROLES                  AGE   VERSION
thc1006   Ready    control-plane,master   2d    v1.28.5+k3s1

# RIC Platform 應有 8 個 pod 運行（所有狀態為 Running 1/1）
```

### 3.2 部署 KPIMON xApp

KPIMON 是最簡單的 xApp，已經正確實作健康檢查。

#### 構建映像

```bash
cd /home/thc1006/oran-ric-platform/xapps/kpimon-go-xapp
docker build -t localhost:5000/xapp-kpimon:1.0.0 -f Dockerfile .
docker push localhost:5000/xapp-kpimon:1.0.0
```

#### 部署到 Kubernetes

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl apply -f deploy/
```

#### 驗證部署

```bash
# 檢查 Pod 狀態
kubectl get pods -n ricxapp -l app=kpimon

# 測試健康檢查端點
KPIMON_POD=$(kubectl get pod -n ricxapp -l app=kpimon -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $KPIMON_POD -- curl -s http://localhost:8081/health/alive
kubectl exec -n ricxapp $KPIMON_POD -- curl -s http://localhost:8081/health/ready
```

預期輸出：
```json
{"status":"alive"}
{"status":"ready"}
```

### 3.3 部署 RC (RAN Control) xApp

RC xApp 已在前一階段部署並運行正常。

#### 驗證狀態

```bash
kubectl get pods -n ricxapp -l app=ran-control

# 測試健康檢查
RC_POD=$(kubectl get pod -n ricxapp -l app=ran-control -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $RC_POD -- curl -s http://localhost:8100/health/alive
kubectl exec -n ricxapp $RC_POD -- curl -s http://localhost:8100/health/ready
```

### 3.4 部署 QoE Predictor xApp

這是部署過程中遇到最多問題的 xApp。

#### 步驟 1：修正源代碼

編輯 `xapps/qoe-predictor/src/qoe_predictor.py`，修改第 26 行：

```python
# 修改前
from ricxappframe.mdclogger import Logger

# 修改後
from mdclogpy import Logger
```

#### 步驟 2：修正 Deployment 配置

編輯 `xapps/qoe-predictor/deploy/deployment.yaml`：

```yaml
# 添加 Pod 級別 SecurityContext（約第 23 行）
spec:
  template:
    spec:
      serviceAccountName: qoe-predictor-sa
      securityContext:
        fsGroup: 1000  # 新增這兩行

# 修改 Container SecurityContext（約第 82-89 行）
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          # fsGroup: 1000  # 刪除這行
          allowPrivilegeEscalation: false

# 修改 imagePullPolicy（約第 28 行）
        imagePullPolicy: Always  # 改為 Always
```

#### 步驟 3：構建並推送映像

```bash
cd /home/thc1006/oran-ric-platform/xapps/qoe-predictor

# 構建映像
docker build -t localhost:5000/xapp-qoe-predictor:1.0.0 \
             -t localhost:5000/xapp-qoe-predictor:latest \
             -f Dockerfile .

# 推送到 local registry
docker push localhost:5000/xapp-qoe-predictor:1.0.0
docker push localhost:5000/xapp-qoe-predictor:latest
```

構建過程約需 3-5 分鐘，因為包含 TensorFlow 2.15.0 等大型依賴。

#### 步驟 4：部署到 Kubernetes

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 先刪除舊部署（如果存在）
kubectl delete -f deploy/ --ignore-not-found

# 應用新配置
kubectl apply -f deploy/
```

#### 步驟 5：等待 Pod Ready

```bash
# 監控 Pod 狀態
kubectl get pods -n ricxapp -l app=qoe-predictor -w

# 檢查日誌
kubectl logs -n ricxapp -l app=qoe-predictor --tail=50
```

Pod 啟動時間約 30-60 秒，因為有 `initialDelaySeconds: 30` 的健康檢查設定。

#### 步驟 6：驗證部署

```bash
QOE_POD=$(kubectl get pod -n ricxapp -l app=qoe-predictor -o jsonpath='{.items[0].metadata.name}')

# 測試健康檢查
kubectl exec -n ricxapp $QOE_POD -- curl -s http://localhost:8090/health/alive
kubectl exec -n ricxapp $QOE_POD -- curl -s http://localhost:8090/health/ready

# 檢查日誌確認無錯誤
kubectl logs -n ricxapp $QOE_POD --tail=20
```

預期輸出：
```json
{"status":"alive"}
{"status":"ready"}
```

日誌中應看到：
```
{"ts": ..., "crit": "INFO", "id": "QOE_PREDICTOR", "msg": "QoE Predictor xApp started successfully"}
 * Running on http://127.0.0.1:8090
```

### 3.5 部署 Traffic Steering xApp

Traffic Steering 已在前一階段部署，使用不同的健康檢查路徑。

#### 驗證狀態

```bash
kubectl get pods -n ricxapp -l app=traffic-steering

# 測試健康檢查（注意路徑差異）
TS_POD=$(kubectl get pod -n ricxapp -l app=traffic-steering -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $TS_POD -- curl -s http://localhost:8080/ric/v1/health/alive
kubectl exec -n ricxapp $TS_POD -- curl -s http://localhost:8080/ric/v1/health/ready
```

**注意**：Traffic Steering 使用 `/ric/v1/health/*` 路徑，而非 `/health/*`。

### 3.6 部署 Federated Learning xApp

Federated Learning 的部署過程與 QoE Predictor 類似，因為遇到相同的問題。

#### 步驟 1：修正源代碼

編輯 `xapps/federated-learning/src/federated_learning.py`，修改第 27 行：

```python
# 修改前
from ricxappframe.mdclogger import Logger

# 修改後
from mdclogpy import Logger
```

#### 步驟 2：修正 Deployment 配置

需要修正兩個檔案：`deployment.yaml` 和 `deployment-gpu.yaml`。

**deployment.yaml**:
```yaml
# 添加 Pod 級別 SecurityContext
spec:
  template:
    spec:
      serviceAccountName: federated-learning-sa
      securityContext:
        fsGroup: 1000  # 新增

# 修改 Container SecurityContext
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          # fsGroup: 1000  # 刪除
          allowPrivilegeEscalation: false

# 修改 imagePullPolicy
        imagePullPolicy: Always  # 改為 Always
```

**deployment-gpu.yaml**（相同修改）:
```yaml
spec:
  template:
    spec:
      serviceAccountName: federated-learning-sa
      securityContext:
        fsGroup: 1000  # 新增
      # Node selector for GPU nodes
      nodeSelector:
        nvidia.com/gpu: "true"
```

#### 步驟 3：構建並推送映像

```bash
cd /home/thc1006/oran-ric-platform/xapps/federated-learning

# 構建映像（包含 TensorFlow 和 PyTorch）
docker build -t localhost:5000/xapp-federated-learning:1.0.0 \
             -t localhost:5000/xapp-federated-learning:latest \
             -f Dockerfile .

# 推送到 local registry
docker push localhost:5000/xapp-federated-learning:1.0.0
docker push localhost:5000/xapp-federated-learning:latest
```

Federated Learning 映像構建時間約 5-8 分鐘，因為包含 TensorFlow 和 PyTorch 兩個框架。

#### 步驟 4：部署到 Kubernetes

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 只部署 CPU 版本（因為沒有 GPU 節點）
kubectl apply -f deploy/configmap.yaml \
              -f deploy/pvc.yaml \
              -f deploy/service.yaml \
              -f deploy/serviceaccount.yaml \
              -f deploy/deployment.yaml
```

**注意**：不要使用 `kubectl apply -f deploy/` 因為會包含 `deployment-gpu.yaml`，會因找不到 GPU 節點而失敗。

#### 步驟 5：監控部署

```bash
# 監控 Pod 創建過程
kubectl get pods -n ricxapp -l app=federated-learning -w

# 檢查事件（如果 Pod 長時間 Pending）
kubectl describe pod -n ricxapp -l app=federated-learning
```

FL Pod 啟動時間較長（60-90 秒），因為：
- 映像較大（~3GB）
- `initialDelaySeconds: 60` 的健康檢查設定
- 需要初始化 TensorFlow 和 PyTorch

#### 步驟 6：驗證部署

```bash
FL_POD=$(kubectl get pod -n ricxapp -l app=federated-learning -o jsonpath='{.items[0].metadata.name}')

# 測試健康檢查
kubectl exec -n ricxapp $FL_POD -- curl -s http://localhost:8110/health/alive
kubectl exec -n ricxapp $FL_POD -- curl -s http://localhost:8110/health/ready

# 檢查日誌
kubectl logs -n ricxapp $FL_POD --tail=30
```

預期輸出：
```json
{"status":"alive"}
{"status":"ready"}
```

日誌中應看到：
```
{"ts": ..., "crit": "INFO", "id": "FEDERATED_LEARNING", "msg": "Federated Learning xApp started successfully"}
 * Running on http://127.0.0.1:8110
1763197210963 1/RMR [INFO] ric message routing library on SI95 p=4590
```

---

## 4. 最終驗證

### 4.1 檢查所有 xApp Pod 狀態

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pods -n ricxapp
```

預期輸出（所有 Pod 應為 Running 1/1）：
```
NAME                                  READY   STATUS    RESTARTS   AGE
ran-control-7c6f4cb6b7-fx6j5          1/1     Running   0          25h
traffic-steering-754fc58fdc-27p9x     1/1     Running   0          24h
kpimon-797bbd666c-b2q29               1/1     Running   0          17m
qoe-predictor-68597b4cc5-9rmw4        1/1     Running   0          8m
federated-learning-685d857b4c-8crzq   1/1     Running   0          4m
```

### 4.2 測試所有健康檢查端點

創建驗證腳本 `verify-all-xapps.sh`：

```bash
#!/bin/bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== 驗證所有 xApp 健康狀態 ==="
echo

# KPIMON
echo "1. KPIMON xApp (port 8081)"
KPIMON_POD=$(kubectl get pod -n ricxapp -l app=kpimon -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $KPIMON_POD -- curl -s http://localhost:8081/health/alive
echo
kubectl exec -n ricxapp $KPIMON_POD -- curl -s http://localhost:8081/health/ready
echo -e "\n"

# RC
echo "2. RC xApp (port 8100)"
RC_POD=$(kubectl get pod -n ricxapp -l app=ran-control -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $RC_POD -- curl -s http://localhost:8100/health/alive
echo
kubectl exec -n ricxapp $RC_POD -- curl -s http://localhost:8100/health/ready
echo -e "\n"

# QoE Predictor
echo "3. QoE Predictor xApp (port 8090)"
QOE_POD=$(kubectl get pod -n ricxapp -l app=qoe-predictor -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $QOE_POD -- curl -s http://localhost:8090/health/alive
echo
kubectl exec -n ricxapp $QOE_POD -- curl -s http://localhost:8090/health/ready
echo -e "\n"

# Traffic Steering (不同路徑)
echo "4. Traffic Steering xApp (port 8080, /ric/v1/health/*)"
TS_POD=$(kubectl get pod -n ricxapp -l app=traffic-steering -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $TS_POD -- curl -s http://localhost:8080/ric/v1/health/alive
echo
kubectl exec -n ricxapp $TS_POD -- curl -s http://localhost:8080/ric/v1/health/ready
echo -e "\n"

# Federated Learning
echo "5. Federated Learning xApp (port 8110)"
FL_POD=$(kubectl get pod -n ricxapp -l app=federated-learning -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $FL_POD -- curl -s http://localhost:8110/health/alive
echo
kubectl exec -n ricxapp $FL_POD -- curl -s http://localhost:8110/health/ready
echo -e "\n"

echo "=== 驗證完成 ==="
```

執行驗證：
```bash
chmod +x verify-all-xapps.sh
./verify-all-xapps.sh
```

所有健康檢查應返回 `{"status":"alive"}` 和 `{"status":"ready"}`。

### 4.3 檢查 RMR 連接狀態

```bash
# 檢查各 xApp 的 RMR 連接日誌
for app in kpimon ran-control qoe-predictor traffic-steering federated-learning; do
  echo "=== $app RMR Status ==="
  kubectl logs -n ricxapp -l app=$app --tail=10 | grep -E "RMR|rmr|sends:"
  echo
done
```

應該看到各 xApp 定期嘗試連接到 E2Term 和其他 RIC 組件。

---

## 5. 常見問題排查

### 5.1 Pod CrashLoopBackOff

**症狀**:
```bash
kubectl get pods -n ricxapp
NAME                             READY   STATUS             RESTARTS   AGE
qoe-predictor-xxx                0/1     CrashLoopBackOff   5          3m
```

**排查步驟**:

1. 查看 Pod 日誌：
```bash
kubectl logs -n ricxapp qoe-predictor-xxx --previous
```

2. 常見原因：
   - ModuleNotFoundError: 檢查 logger 導入路徑
   - Redis 連接失敗: 確認 Redis service 存在於 ricplt namespace
   - 映像拉取失敗: 確認 local registry 運行正常

### 5.2 Pod Pending 狀態

**症狀**:
```bash
NAME                             READY   STATUS    RESTARTS   AGE
federated-learning-xxx           0/1     Pending   0          2m
```

**排查步驟**:

1. 查看 Pod 事件：
```bash
kubectl describe pod -n ricxapp federated-learning-xxx | grep -A 10 "Events:"
```

2. 常見原因：
   - 資源不足: 檢查 node 的 CPU/Memory
   - PVC 綁定失敗: 檢查 PersistentVolumeClaim 狀態
   - Node selector 不匹配: 確認沒有錯誤使用 GPU deployment

### 5.3 健康檢查失敗

**症狀**:
```bash
kubectl exec -n ricxapp qoe-predictor-xxx -- curl http://localhost:8090/health/alive
curl: (7) Failed to connect to localhost port 8090
```

**排查步驟**:

1. 檢查 Pod 內的進程：
```bash
kubectl exec -n ricxapp qoe-predictor-xxx -- ps aux
```

2. 確認 Flask 應用是否啟動：
```bash
kubectl logs -n ricxapp qoe-predictor-xxx | grep "Running on"
```

3. 檢查端口監聽：
```bash
kubectl exec -n ricxapp qoe-predictor-xxx -- netstat -tuln | grep 8090
```

### 5.4 映像構建失敗

**症狀**:
```
ERROR: failed to compute cache key: "/models": not found
```

**解決方案**:
```bash
# 確保必要目錄存在
mkdir -p models config data
echo "# Models directory" > models/README.md

# 重新構建
docker build --no-cache -t localhost:5000/xapp-qoe-predictor:1.0.0 .
```

---

## 6. 效能與資源使用

### 6.1 資源使用情況

檢查各 xApp 的實際資源使用：

```bash
kubectl top pods -n ricxapp
```

典型輸出：
```
NAME                                  CPU(cores)   MEMORY(bytes)
kpimon-xxx                            50m          150Mi
ran-control-xxx                       80m          200Mi
qoe-predictor-xxx                     200m         1500Mi
traffic-steering-xxx                  100m         250Mi
federated-learning-xxx                400m         3000Mi
```

### 6.2 資源配置建議

基於實際運行經驗，推薦以下資源配置：

| xApp | CPU Request | CPU Limit | Memory Request | Memory Limit |
|------|------------|-----------|----------------|--------------|
| KPIMON | 100m | 500m | 256Mi | 512Mi |
| RC | 100m | 1000m | 256Mi | 1Gi |
| QoE Predictor | 500m | 2000m | 1Gi | 2Gi |
| Traffic Steering | 200m | 1000m | 512Mi | 1Gi |
| Federated Learning | 1000m | 4000m | 2Gi | 4Gi |

---

## 7. 總結與建議

### 7.1 關鍵要點

1. **SecurityContext 配置**：`fsGroup` 必須在 Pod 級別，不能在 Container 級別
2. **Logger 導入**：使用 `from mdclogpy import Logger`，而非 `from ricxappframe.mdclogger import Logger`
3. **映像拉取策略**：開發環境使用 `imagePullPolicy: Always` 確保使用最新映像
4. **健康檢查路徑**：大部分 xApp 使用 `/health/*`，但 Traffic Steering 使用 `/ric/v1/health/*`
5. **部署順序**：先確保 RIC Platform 所有組件正常運行，再部署 xApps

### 7.2 下一步工作

1. **E2 連接測試**：配置真實的 E2 節點進行端到端測試
2. **A1 策略測試**：通過 A1 Mediator 發送策略更新
3. **性能測試**：使用 traffic generator 測試各 xApp 的處理能力
4. **監控配置**：設置 Prometheus + Grafana 監控 xApp 指標
5. **日誌聚合**：配置 EFK (Elasticsearch + Fluentd + Kibana) 收集日誌

### 7.3 生產環境建議

部署到生產環境前，需要考慮以下事項：

1. **高可用性**：增加 replicas 數量（至少 2 個副本）
2. **資源限制**：根據實際負載調整 CPU/Memory 限制
3. **持久化存儲**：為 ML 模型配置 PersistentVolume
4. **安全性**：啟用 Pod Security Policy，限制容器權限
5. **網路策略**：配置 NetworkPolicy 限制 Pod 間通信
6. **備份策略**：定期備份 Redis 數據和 ML 模型

---

**部署完成日期**: 2025-11-15
**作者**: 蔡秀吉 (thc1006)
**狀態**: 所有 5 個 xApp 部署成功並通過健康檢查驗證
