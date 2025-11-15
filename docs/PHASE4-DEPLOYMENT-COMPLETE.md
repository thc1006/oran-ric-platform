# Phase 4 完整部署指南

**作者：蔡秀吉 (thc1006)**
**日期：2025-11-15**
**版本：v1.0.0-phase4**

---

## 目錄

1. [概述](#概述)
2. [環境準備](#環境準備)
3. [構建 Docker 鏡像](#構建-docker-鏡像)
4. [Kubernetes 部署](#kubernetes-部署)
5. [驗證與測試](#驗證與測試)
6. [GPU 部署](#gpu-部署)
7. [故障排除](#故障排除)
8. [附錄](#附錄)

---

## 概述

Phase 4 部署兩個機器學習 xApp：
- **QoE Predictor xApp**：基於 ML 的 QoE 預測
- **Federated Learning xApp**：分散式聯邦學習

### 關鍵改進

✅ **優化的多階段 Dockerfile**：
- 構建時間減少 60-70%
- 最終鏡像大小減少 40-50%
- 分離編譯環境和運行環境

✅ **完整的 Kubernetes 配置**：
- Deployment、Service、ConfigMap、ServiceAccount
- 健康檢查和資源限制
- CPU 和 GPU 兩種部署模式

✅ **自動化部署腳本**：
- 一鍵部署
- 自動驗證
- 日誌查看

---

## 環境準備

### 最低要求

| 組件 | CPU 版本 | GPU 版本 |
|------|----------|----------|
| CPU | 4 cores | 8 cores |
| Memory | 8 GB | 16 GB |
| Storage | 50 GB | 100 GB |
| GPU | N/A | NVIDIA GPU (Compute Capability 7.0+) |
| Kubernetes | 1.28+ | 1.28+ with NVIDIA Device Plugin |

### 軟件要求

```bash
# 必需工具
docker --version    # >= 20.10
kubectl version     # >= 1.28
helm version        # >= 3.10

# GPU 版本額外要求
nvidia-smi          # NVIDIA Driver
nvidia-container-toolkit  # Docker GPU support
```

### 檢查環境

```bash
# 檢查 Kubernetes 集群
kubectl cluster-info
kubectl get nodes

# 檢查 namespace
kubectl get namespace ricxapp || kubectl create namespace ricxapp

# 檢查 GPU 資源（如果使用 GPU）
kubectl describe node | grep -A 5 "nvidia.com/gpu"
```

---

## 構建 Docker 鏡像

### 方法 1：使用部署腳本（推薦）

```bash
cd /path/to/oran-ric-platform

# 僅構建鏡像
./scripts/deploy-ml-xapps.sh build
```

### 方法 2：手動構建

#### QoE Predictor（CPU 版本）

```bash
cd xapps/qoe-predictor

# 使用優化的 Dockerfile
docker build -f Dockerfile.optimized \
    -t localhost:5000/xapp-qoe-predictor:1.0.0 .

# 推送到本地 registry
docker push localhost:5000/xapp-qoe-predictor:1.0.0
```

#### Federated Learning（CPU 版本）

```bash
cd xapps/federated-learning

# 使用優化的 Dockerfile
docker build -f Dockerfile.optimized \
    -t localhost:5000/xapp-federated-learning:1.0.0 .

# 推送到本地 registry
docker push localhost:5000/xapp-federated-learning:1.0.0
```

#### Federated Learning（GPU 版本）

```bash
cd xapps/federated-learning

# 使用 GPU Dockerfile
docker build -f Dockerfile.gpu \
    -t localhost:5000/xapp-federated-learning:1.0.0-gpu .

# 推送到本地 registry
docker push localhost:5000/xapp-federated-learning:1.0.0-gpu
```

### 構建時間預估

| xApp | Dockerfile | 初次構建 | 緩存後 |
|------|-----------|----------|--------|
| QoE Predictor | Dockerfile.optimized | 10-15 分鐘 | 2-5 分鐘 |
| Federated Learning (CPU) | Dockerfile.optimized | 15-20 分鐘 | 3-7 分鐘 |
| Federated Learning (GPU) | Dockerfile.gpu | 20-30 分鐘 | 5-10 分鐘 |

---

## Kubernetes 部署

### 方法 1：使用部署腳本（推薦）

```bash
# 完整部署（構建 + 部署 + 驗證）
./scripts/deploy-ml-xapps.sh deploy

# 部署過程會顯示：
# [INFO] Building Docker images...
# [INFO] Deploying QoE Predictor xApp...
# [INFO] Deploying Federated Learning xApp...
# [SUCCESS] ML xApps deployment completed!
```

### 方法 2：手動部署

#### 部署 QoE Predictor

```bash
cd xapps/qoe-predictor/deploy

# 按順序應用配置
kubectl apply -f serviceaccount.yaml
kubectl apply -f configmap.yaml
kubectl apply -f service.yaml
kubectl apply -f deployment.yaml
```

#### 部署 Federated Learning（CPU）

```bash
cd xapps/federated-learning/deploy

# 按順序應用配置
kubectl apply -f pvc.yaml
kubectl apply -f serviceaccount.yaml
kubectl apply -f configmap.yaml
kubectl apply -f service.yaml
kubectl apply -f deployment.yaml
```

#### 部署 Federated Learning（GPU）

```bash
cd xapps/federated-learning/deploy

# 使用 GPU 部署配置
kubectl apply -f pvc.yaml
kubectl apply -f serviceaccount.yaml
kubectl apply -f configmap.yaml
kubectl apply -f service.yaml
kubectl apply -f deployment-gpu.yaml  # 注意使用 GPU 版本
```

---

## 驗證與測試

### 檢查 Pod 狀態

```bash
# 查看所有 ML xApp Pods
kubectl get pods -n ricxapp -l xapp

# 預期輸出：
# NAME                                  READY   STATUS    RESTARTS   AGE
# qoe-predictor-xxx                     1/1     Running   0          2m
# federated-learning-xxx                1/1     Running   0          2m
```

### 檢查服務

```bash
# 查看服務
kubectl get svc -n ricxapp -l xapp

# 預期輸出：
# NAME                 TYPE        CLUSTER-IP       PORT(S)
# qoe-predictor        ClusterIP   10.43.x.x        4570,4571,8090
# federated-learning   ClusterIP   10.43.x.x        4590,4591,8110
```

### 健康檢查

```bash
# QoE Predictor
kubectl exec -n ricxapp \
    $(kubectl get pod -n ricxapp -l app=qoe-predictor -o jsonpath='{.items[0].metadata.name}') \
    -- curl -s http://localhost:8090/health/alive

# 預期輸出：{"status":"alive"}

# Federated Learning
kubectl exec -n ricxapp \
    $(kubectl get pod -n ricxapp -l app=federated-learning -o jsonpath='{.items[0].metadata.name}') \
    -- curl -s http://localhost:8110/health/alive

# 預期輸出：{"status":"alive"}
```

### 查看日誌

```bash
# QoE Predictor 日誌
kubectl logs -n ricxapp -l app=qoe-predictor --tail=50 -f

# Federated Learning 日誌
kubectl logs -n ricxapp -l app=federated-learning --tail=50 -f

# 應該看到：
# [INFO] QoE Predictor xApp initialized
# [INFO] ML models initialized successfully
# [INFO] Redis connection established
# [INFO] QoE Predictor xApp started successfully
```

### GPU 驗證（僅限 GPU 版本）

```bash
# 檢查 GPU 分配
kubectl exec -n ricxapp \
    $(kubectl get pod -n ricxapp -l app=federated-learning,version=v1.0.0-gpu -o jsonpath='{.items[0].metadata.name}') \
    -- nvidia-smi

# 檢查 TensorFlow 和 PyTorch GPU 支持
kubectl exec -n ricxapp \
    $(kubectl get pod -n ricxapp -l app=federated-learning,version=v1.0.0-gpu -o jsonpath='{.items[0].metadata.name}') \
    -- /usr/local/bin/check_gpu.py

# 預期輸出：
# TensorFlow GPUs: 1
# PyTorch CUDA: True
```

### API 測試

```bash
# 端口轉發
kubectl port-forward -n ricxapp svc/qoe-predictor 8090:8090 &
kubectl port-forward -n ricxapp svc/federated-learning 8110:8110 &

# 測試 QoE Predictor API
curl http://localhost:8090/health/alive
curl http://localhost:8090/metrics

# 測試 Federated Learning API
curl http://localhost:8110/health/alive
curl http://localhost:8110/metrics
```

---

## GPU 部署

### GPU 節點準備

1. **安裝 NVIDIA Driver**

```bash
# 檢查 GPU
nvidia-smi

# 預期看到 GPU 信息
```

2. **安裝 NVIDIA Container Toolkit**

```bash
# Ubuntu/Debian
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
    sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

3. **安裝 NVIDIA Device Plugin for Kubernetes**

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml

# 驗證
kubectl get pods -n kube-system | grep nvidia
```

### GPU 節點標記

```bash
# 標記 GPU 節點
kubectl label nodes <node-name> nvidia.com/gpu=true

# 驗證
kubectl describe node <node-name> | grep nvidia.com/gpu
```

### 部署 GPU 版本

```bash
# 構建 GPU 鏡像
cd xapps/federated-learning
docker build -f Dockerfile.gpu \
    -t localhost:5000/xapp-federated-learning:1.0.0-gpu .
docker push localhost:5000/xapp-federated-learning:1.0.0-gpu

# 部署
cd deploy
kubectl apply -f deployment-gpu.yaml
```

---

## 故障排除

### Pod 無法啟動

**症狀**：Pod 狀態為 `CrashLoopBackOff` 或 `Error`

**檢查步驟**：

```bash
# 查看 Pod 狀態
kubectl get pods -n ricxapp

# 查看詳細信息
kubectl describe pod -n ricxapp <pod-name>

# 查看日誌
kubectl logs -n ricxapp <pod-name>
kubectl logs -n ricxapp <pod-name> --previous  # 查看上次運行的日誌
```

**常見問題**：

1. **鏡像拉取失敗**
   ```bash
   # 檢查鏡像是否存在
   docker images | grep xapp

   # 檢查 registry
   docker pull localhost:5000/xapp-qoe-predictor:1.0.0
   ```

2. **健康檢查失敗**
   ```bash
   # 延長啟動時間
   # 在 deployment.yaml 中調整：
   # initialDelaySeconds: 60  # 增加到 90
   ```

3. **資源不足**
   ```bash
   # 檢查節點資源
   kubectl describe nodes

   # 調整資源請求
   # 在 deployment.yaml 中降低 requests
   ```

### GPU 不可用

**症狀**：Pod 運行但無法使用 GPU

**檢查步驟**：

```bash
# 檢查 NVIDIA Device Plugin
kubectl get pods -n kube-system | grep nvidia

# 檢查節點 GPU 資源
kubectl describe node | grep -A 10 "Capacity:"

# 檢查 Pod GPU 分配
kubectl describe pod -n ricxapp <pod-name> | grep -A 5 "Limits:"

# 進入 Pod 測試
kubectl exec -n ricxapp <pod-name> -- nvidia-smi
```

**解決方案**：

1. 確保 NVIDIA Device Plugin 運行正常
2. 確保節點有可用的 GPU 資源
3. 確保 Pod 請求了 GPU 資源（`nvidia.com/gpu: "1"`）

### 性能問題

**症狀**：推理速度慢或內存不足

**優化建議**：

1. **調整資源限制**
   ```yaml
   resources:
     requests:
       cpu: "2000m"      # 增加 CPU
       memory: "4Gi"     # 增加 Memory
     limits:
       cpu: "8000m"
       memory: "12Gi"
   ```

2. **使用 GPU**
   - 部署 GPU 版本可顯著提升性能

3. **調整批處理大小**
   - 在 ConfigMap 中調整 `batch_size`

---

## 附錄

### A. 文件清單

**Dockerfile**：
- `xapps/qoe-predictor/Dockerfile.optimized`（優化版）
- `xapps/federated-learning/Dockerfile.optimized`（CPU 優化版）
- `xapps/federated-learning/Dockerfile.gpu`（GPU 版）

**Kubernetes 配置**：

QoE Predictor：
- `xapps/qoe-predictor/deploy/deployment.yaml`
- `xapps/qoe-predictor/deploy/service.yaml`
- `xapps/qoe-predictor/deploy/configmap.yaml`
- `xapps/qoe-predictor/deploy/serviceaccount.yaml`

Federated Learning：
- `xapps/federated-learning/deploy/deployment.yaml`（CPU）
- `xapps/federated-learning/deploy/deployment-gpu.yaml`（GPU）
- `xapps/federated-learning/deploy/service.yaml`
- `xapps/federated-learning/deploy/configmap.yaml`
- `xapps/federated-learning/deploy/serviceaccount.yaml`
- `xapps/federated-learning/deploy/pvc.yaml`

**腳本**：
- `scripts/deploy-ml-xapps.sh`（自動化部署腳本）

### B. 部署腳本使用

```bash
# 查看幫助
./scripts/deploy-ml-xapps.sh

# 可用命令：
./scripts/deploy-ml-xapps.sh deploy    # 完整部署
./scripts/deploy-ml-xapps.sh build     # 僅構建鏡像
./scripts/deploy-ml-xapps.sh cleanup   # 清理部署
./scripts/deploy-ml-xapps.sh verify    # 驗證部署
./scripts/deploy-ml-xapps.sh logs      # 查看日誌
```

### C. 資源配額建議

| xApp | 場景 | CPU Request | CPU Limit | Memory Request | Memory Limit | GPU |
|------|------|-------------|-----------|----------------|--------------|-----|
| QoE Predictor | 測試 | 500m | 1000m | 512Mi | 1Gi | 0 |
| QoE Predictor | 生產 | 500m | 2000m | 1Gi | 2Gi | 0 |
| FL (CPU) | 測試 | 1000m | 2000m | 1Gi | 2Gi | 0 |
| FL (CPU) | 生產 | 1000m | 4000m | 2Gi | 4Gi | 0 |
| FL (GPU) | 生產 | 2000m | 8000m | 4Gi | 12Gi | 1 |

### D. 端口分配

| xApp | RMR Data | RMR Route | HTTP API |
|------|----------|-----------|----------|
| QoE Predictor | 4570 | 4571 | 8090 |
| Federated Learning | 4590 | 4591 | 8110 |

### E. 相關文檔

- [Phase 4 部署指南](phase4-ml-xapps-deployment.md)
- [Phase 4 本地測試報告](PHASE4-LOCAL-TEST-REPORT.md)
- [Phase 4 完成總結](PHASE4-SUMMARY.md)
- [GPU 工作站交接文檔](GPU-WORKSTATION-HANDOFF.md)

---

**部署完成！**

如有問題，請參考 [故障排除](#故障排除) 或查閱 [Phase 4 本地測試報告](PHASE4-LOCAL-TEST-REPORT.md)。

作者：蔡秀吉 (thc1006)
日期：2025-11-15
版本：v1.0.0-phase4
