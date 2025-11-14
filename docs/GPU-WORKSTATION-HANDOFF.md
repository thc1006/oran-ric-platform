# GPU 工作站 ML xApp 部署交接文檔

**作者**：蔡秀吉（thc1006）
**文檔版本**：1.0.0
**創建日期**：2025-11-14
**目標讀者**：GPU 工作站上的部署團隊

---

## 文檔目的

本文檔提供完整的專案背景、當前狀態、技術經驗以及 ML xApp 部署指南，讓 GPU 工作站上的團隊能夠：

1. 快速了解專案進展和技術架構
2. 繼承已驗證的最佳實踐和經驗教訓
3. 獨立完成 ML xApp 的開發、測試和部署
4. 避免重複遇到已知問題

---

## 目錄

1. [專案背景與當前狀態](#專案背景與當前狀態)
2. [已完成工作總結](#已完成工作總結)
3. [待完成的 ML xApp](#待完成的-ml-xapp)
4. [GPU 環境要求](#gpu-環境要求)
5. [關鍵技術經驗](#關鍵技術經驗)
6. [ML xApp 部署策略](#ml-xapp-部署策略)
7. [已知問題與解決方案](#已知問題與解決方案)
8. [參考文檔](#參考文檔)

---

## 專案背景與當前狀態

### 專案概述

**專案名稱**：O-RAN Near-RT RIC Platform (J Release) 生產級部署
**平台版本**：O-RAN SC J Release (November 2025)
**Kubernetes**：k3s v1.28.5
**部署位置**：Debian 13 (trixie) 本地工作站（無 GPU）

### 當前進度

| Phase | 狀態 | 完成時間 | 內容 |
|-------|------|---------|------|
| **Phase 1** | ✅ 完成 | 2025-11-13 | KPIMON + RC xApp 部署 |
| **Phase 2** | ✅ 完成 | 2025-11-14 | 專案重組與結構優化 |
| **Phase 3** | ✅ 完成 | 2025-11-14 | Traffic Steering xApp 部署 |
| **Phase 4** | 🚧 待處理 | - | ML xApp 部署（需要 GPU） |

### 當前運行的 xApp

```bash
kubectl get pods -n ricxapp
```

輸出：
```
NAME                                READY   STATUS    RESTARTS   AGE
kpimon-95f9b956d-59qwm              1/1     Running   0          73m
ran-control-7c6f4cb6b7-fx6j5        1/1     Running   0          73m
traffic-steering-754fc58fdc-27p9x   1/1     Running   0          36m
```

**所有 xApp 均為生產就緒狀態**。

---

## 已完成工作總結

### Phase 1: 基礎 xApp 部署 ✅

**完成內容**：
- ✅ KPIMON xApp（KPI 監控與異常檢測）
- ✅ RAN Control xApp（RAN 控制與優化）

**關鍵成就**：
- 解決 ricsdl 3.0.2 + redis 4.1.1 版本兼容性問題
- 建立標準化的部署流程
- 完成 RMR 消息路由配置

**詳細文檔**：
- [docs/deployment-guide-complete.md](deployment-guide-complete.md)
- [docs/QUICK-START.md](QUICK-START.md)

### Phase 2: 專案重組 ✅

**完成內容**：
- 統一 legacy 資料夾結構
- 清理專案目錄
- 建立一致的命名規範

**詳細文檔**：
- [docs/PROJECT-REORGANIZATION-PLAN.md](PROJECT-REORGANIZATION-PLAN.md)

### Phase 3: Traffic Steering xApp 部署 ✅

**完成內容**：
- ✅ 完整實現 Traffic Steering xApp
- ✅ 解決 RMR API 使用問題（重大技術突破）
- ✅ 建立標準化的 xApp 開發模式

**關鍵技術突破**：

1. **RMR API 正確使用方式**
   - ❌ 錯誤：繼承 `RMRXapp` 並使用 `rmr_alloc()`
   - ✅ 正確：組合模式 + 直接使用 `rmr_send()`

2. **依賴版本驗證**
   - ricxappframe==3.2.2
   - ricsdl==3.0.2
   - redis==4.1.1
   - hiredis==2.0.0

3. **Docker 構建最佳實踐**
   - 先安裝 ricsdl，再安裝其他依賴
   - 代碼修改後使用 `--no-cache` 重建

**詳細文檔**：
- [docs/traffic-steering-deployment.md](traffic-steering-deployment.md)

---

## 待完成的 ML xApp

### 1. QoE Predictor xApp 🚧

#### 功能描述
使用機器學習預測用戶體驗質量（Quality of Experience），為 Traffic Steering 提供智能決策支持。

#### 依賴需求分析

**主要依賴**（來自 `xapps/qoe-predictor/requirements.txt`）：

```python
# O-RAN Framework
ricxappframe==3.2.2
mdclogpy==1.1.4

# Machine Learning
tensorflow==2.15.0          # ~500MB，需要 GPU 加速
scikit-learn==1.3.2
numpy==1.24.3
pandas==2.0.3
joblib==1.3.2

# Data Storage
redis==5.0.1                # ⚠️ 需要修正為 4.1.1

# REST API
flask==3.0.0
flask-restful==0.3.10
flask-cors==4.0.0

# Monitoring
prometheus-client==0.19.0
```

#### ⚠️ 已知需要修正的問題

**問題 1：Redis 版本不兼容**
```python
# 當前（錯誤）
redis==5.0.1

# 需要修正為（已驗證）
ricsdl==3.0.2      # 必須先安裝
redis==4.1.1       # ricsdl 3.0.2 requires redis==4.1.1
hiredis==2.0.0
```

**問題 2：可能的 RMR API 使用錯誤**
- 檢查源代碼是否使用 `rmr_alloc()`
- 如果有，需要按照 Traffic Steering 的模式重構（組合模式 + `rmr_send()`）

#### 預估工作量
- 依賴修正：30 分鐘
- 代碼審查和可能的重構：2-4 小時
- Docker 構建和測試：1-2 小時
- 部署和驗證：1 小時

**總計**：約 4-8 小時

---

### 2. Federated Learning xApp 🚧

#### 功能描述
實現聯邦學習框架，支持分布式模型訓練而無需共享原始數據。

#### 依賴需求分析

**主要依賴**（來自 `xapps/federated-learning/requirements.txt`）：

```python
# O-RAN Framework
ricxappframe==3.2.2
mdclogpy==1.1.4

# Machine Learning - TensorFlow
tensorflow==2.15.0          # ~500MB
tensorflow-privacy==0.9.0
tensorflow-federated==0.75.0

# Machine Learning - PyTorch
torch==2.1.2                # ~800MB
torchvision==0.16.2         # ~200MB

# Federated Learning
flwr==1.5.0                 # Flower framework

# Security & Cryptography
cryptography==41.0.7
pycryptodome==3.19.0

# Data Storage
redis==5.0.1                # ⚠️ 需要修正為 4.1.1
h5py==3.10.0

# Monitoring
tensorboard==2.15.1
```

#### ⚠️ 已知需要修正的問題

與 QoE Predictor 相同：
1. Redis 版本需要修正為 4.1.1
2. 添加 ricsdl==3.0.2（在 redis 之前安裝）
3. 檢查 RMR API 使用方式

#### 額外考慮

**依賴大小**：
- TensorFlow 2.15.0: ~500MB
- PyTorch 2.1.2: ~800MB
- TorchVision 0.16.2: ~200MB
- **總計**: ~1.5GB

**GPU 要求更高**，建議：
- CUDA 11.8+
- cuDNN 8.6+
- NVIDIA GPU with Compute Capability 7.0+
- 至少 8GB GPU 記憶體

#### 預估工作量
- 依賴修正：30 分鐘
- 代碼審查和可能的重構：4-8 小時（更複雜）
- Docker 構建和測試：2-3 小時
- 部署和驗證：1-2 小時

**總計**：約 8-14 小時

---

## GPU 環境要求

### 硬體需求

#### 最低要求
- **GPU**: NVIDIA GPU with Compute Capability 7.0+
- **GPU 記憶體**: 8GB（QoE Predictor）/ 12GB（Federated Learning）
- **系統記憶體**: 16GB
- **磁碟空間**: 200GB（ML 模型和依賴）
- **CPU**: 8 核心

#### 推薦配置
- **GPU**: NVIDIA RTX 3090 / A5000 或更高
- **GPU 記憶體**: 16GB+
- **系統記憶體**: 32GB+
- **磁碟空間**: 500GB SSD

### 軟體需求

#### 作業系統
- Ubuntu 22.04 LTS 或 Debian 12/13
- Linux Kernel 5.15+

#### NVIDIA 驅動與 CUDA
```bash
# NVIDIA Driver
nvidia-driver-535 或更新

# CUDA Toolkit
CUDA 11.8 或 12.x

# cuDNN
cuDNN 8.6+

# 驗證安裝
nvidia-smi
nvcc --version
```

#### Docker GPU 支持
```bash
# 安裝 NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
    sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker

# 測試 GPU 訪問
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

#### Kubernetes GPU 支持
```bash
# 安裝 NVIDIA Device Plugin for Kubernetes
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml

# 驗證
kubectl get nodes -o json | jq '.items[].status.capacity'
# 應該看到 "nvidia.com/gpu": "1" 或更多
```

---

## 關鍵技術經驗

### 1. ricxappframe 3.2.2 正確使用模式

這是 **Phase 3 最重要的技術突破**，必須遵循！

#### ❌ 錯誤方式（會導致 `AttributeError: 'MyXapp' object has no attribute 'rmr_alloc'`）

```python
from ricxappframe.xapp_frame import RMRXapp

class MyXapp(RMRXapp):  # 繼承
    def __init__(self):
        super().__init__(...)

    def send_message(self):
        sbuf = self.rmr_alloc()  # 這個方法不存在！
        sbuf.contents.mtype = msg_type
        sbuf.contents.payload = data.encode()
        self.rmr_send(sbuf, retry=True)
```

#### ✅ 正確方式（已在 3 個 xApp 中驗證）

```python
from ricxappframe.xapp_frame import RMRXapp

class MyXapp:  # 不繼承
    def __init__(self):
        self.xapp = None  # 組合
        self.running = False

    def _send_message(self, msg_type: int, payload: str):
        """簡單輔助方法"""
        if self.xapp:
            success = self.xapp.rmr_send(payload.encode(), msg_type)
            if not success:
                logger.error(f"Failed to send message type {msg_type}")

    def start(self):
        # 初始化 RMRXapp
        self.xapp = RMRXapp(self._handle_message,
                            rmr_port=4560,
                            use_fake_sdl=False)
        # 啟動消息循環
        self.xapp.run()
```

**關鍵點**：
1. 使用**組合**（composition）而非繼承（inheritance）
2. 不使用 `rmr_alloc()`，直接調用 `rmr_send()`
3. 創建簡單的 `_send_message()` 輔助方法

### 2. Python 依賴版本管理

#### 已驗證的兼容組合（Phase 1-3）

```python
# O-RAN xApp Framework
ricxappframe==3.2.2
ricsdl==3.0.2       # 必須在 redis 之前安裝
mdclogpy==1.1.4

# Data Storage
redis==4.1.1        # ricsdl 3.0.2 requires redis==4.1.1
hiredis==2.0.0

# REST API Framework
flask==3.0.0
flask-restful==0.3.10
werkzeug==3.0.1
```

#### Dockerfile 安裝順序（關鍵！）

```dockerfile
# 安裝 Python 依賴
# 重要：先安裝 ricsdl 3.0.2 以確保 redis 4.x 兼容性
COPY requirements.txt .
RUN pip install --no-cache-dir ricsdl==3.0.2 && \
    pip install --no-cache-dir -r requirements.txt
```

**為什麼順序重要**：
- ricsdl 3.0.2 明確要求 redis 4.1.1
- 如果先安裝其他依賴，可能會拉入不兼容的 redis 版本
- 先安裝 ricsdl 可以鎖定正確的 redis 版本

### 3. Docker 構建最佳實踐

#### 代碼修改後的構建

```bash
# 首次構建或代碼修改後，務必使用 --no-cache
docker build --no-cache -t localhost:5000/my-xapp:1.0.0 .

# 驗證映像已更新
docker images | grep my-xapp
```

**原因**：Docker 可能緩存舊的源代碼層，導致運行舊代碼。

#### 構建失敗時的調試

```bash
# 逐層構建以找出問題
docker build --progress=plain --no-cache -t my-xapp:debug .

# 檢查中間層
docker run --rm -it <intermediate-image-id> /bin/bash
```

### 4. Kubernetes 健康檢查

#### 標準實現（Flask）

```python
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/ric/v1/health/alive', methods=['GET'])
def health_alive():
    return jsonify({"status": "alive"}), 200

@app.route('/ric/v1/health/ready', methods=['GET'])
def health_ready():
    return jsonify({"status": "ready"}), 200

# 在獨立線程中運行
flask_thread = Thread(target=lambda: app.run(host='0.0.0.0', port=8080))
flask_thread.daemon = True
flask_thread.start()
```

#### Deployment YAML 配置

```yaml
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
```

### 5. RMR 路由配置

#### ConfigMap 模板

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-xapp-config
  namespace: ricxapp
data:
  rmr-routes.txt: |
    newrt|start
    # RIC Subscription Messages
    rte|12010|service-ricplt-e2term-rmr-alpha.ricplt:4560
    rte|12011|my-xapp.ricxapp:4560
    # RIC Indication Messages
    rte|12050|my-xapp.ricxapp:4560
    # RIC Control Messages
    rte|12040|service-ricplt-e2term-rmr-alpha.ricplt:4560
    rte|12041|my-xapp.ricxapp:4560
    # A1 Policy Messages (如需要)
    rte|20010|my-xapp.ricxapp:4560
    rte|20011|service-ricplt-a1mediator-rmr.ricplt:4562
    newrt|end
```

---

## ML xApp 部署策略

### 建議順序

1. **QoE Predictor xApp** (先部署)
   - 依賴較少（只有 TensorFlow）
   - 複雜度較低
   - 可以先驗證 GPU 環境和基本 ML 功能

2. **Federated Learning xApp** (後部署)
   - 依賴較多（TensorFlow + PyTorch + Flower）
   - 複雜度較高
   - 可以利用 QoE Predictor 的經驗

### 部署檢查清單

#### 準備階段
- [ ] GPU 驅動和 CUDA 已正確安裝
- [ ] Docker GPU 支持已配置
- [ ] Kubernetes GPU 插件已部署
- [ ] 克隆本專案到 GPU 工作站
- [ ] 設置 `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`

#### QoE Predictor 部署
- [ ] 修正 `requirements.txt` 中的 redis 版本為 4.1.1
- [ ] 添加 `ricsdl==3.0.2` 到 requirements.txt
- [ ] 審查源代碼中的 RMR API 使用
- [ ] 如果使用繼承模式，重構為組合模式
- [ ] 創建 Dockerfile（參考 Traffic Steering）
- [ ] 創建 Kubernetes 部署清單
- [ ] 構建 Docker 映像（使用 `--no-cache`）
- [ ] 推送到本地 registry
- [ ] 部署到 Kubernetes
- [ ] 驗證 Pod 狀態和日誌
- [ ] 測試健康檢查端點
- [ ] 撰寫部署文檔

#### Federated Learning 部署
- [ ] 同 QoE Predictor 的檢查清單
- [ ] 額外：驗證 Flower framework 配置
- [ ] 額外：測試多個 FL clients 協作

---

## 已知問題與解決方案

### 問題 1: Pod 持續重啟 - `rmr_alloc` 錯誤

**症狀**：
```
AttributeError: 'MyXapp' object has no attribute 'rmr_alloc'
```

**原因**：使用了繼承模式和不存在的 `rmr_alloc()` API

**解決方案**：
參考 [關鍵技術經驗 #1](#1-ricxappframe-322-正確使用模式) 重構代碼

### 問題 2: Redis 版本不兼容

**症狀**：
```
ModuleNotFoundError: No module named 'redis._compat'
```

**原因**：ricsdl 3.0.2 與 redis 5.0.1 不兼容

**解決方案**：
1. 修改 `requirements.txt`：
   ```python
   ricsdl==3.0.2
   redis==4.1.1
   hiredis==2.0.0
   ```

2. 修改 `Dockerfile`：
   ```dockerfile
   RUN pip install --no-cache-dir ricsdl==3.0.2 && \
       pip install --no-cache-dir -r requirements.txt
   ```

### 問題 3: Docker 緩存導致舊代碼運行

**症狀**：修改代碼後重建，但運行的仍是舊代碼

**解決方案**：
```bash
docker build --no-cache -t localhost:5000/my-xapp:1.0.0 .
```

### 問題 4: GPU 不可用於 Docker 容器

**症狀**：
```
RuntimeError: CUDA error: no CUDA-capable device is detected
```

**解決方案**：
1. 確認 `nvidia-container-toolkit` 已安裝
2. Deployment YAML 中添加 GPU 資源請求：
   ```yaml
   resources:
     limits:
       nvidia.com/gpu: 1
   ```

### 問題 5: TensorFlow GPU 版本問題

**症狀**：TensorFlow 無法檢測到 GPU

**解決方案**：
1. 確認 CUDA 和 cuDNN 版本兼容：
   - TensorFlow 2.15.0 需要 CUDA 11.8
   - 需要 cuDNN 8.6+

2. 在容器中驗證：
   ```python
   import tensorflow as tf
   print(tf.config.list_physical_devices('GPU'))
   ```

---

## 參考文檔

### 本專案文檔

1. **部署指南**
   - [QUICK-START.md](QUICK-START.md) - 快速部署指南
   - [deployment-guide-complete.md](deployment-guide-complete.md) - 完整部署指南
   - [traffic-steering-deployment.md](traffic-steering-deployment.md) - Traffic Steering 詳細部署

2. **專案管理**
   - [PROJECT-REORGANIZATION-PLAN.md](PROJECT-REORGANIZATION-PLAN.md) - 專案重組計畫
   - [../README.md](../README.md) - 專案總覽

3. **xApp 文檔**
   - [../xapps/kpimon-go-xapp/README.md](../xapps/kpimon-go-xapp/README.md) - KPIMON xApp
   - [../xapps/rc-xapp/README.md](../xapps/rc-xapp/README.md) - RAN Control xApp

### O-RAN 官方文檔

1. **E2 Service Models**
   - E2SM-KPM v3.0: O-RAN.WG3.E2SM-KPM-v03.00
   - E2SM-RC v2.0: O-RAN.WG3.E2SM-RC-v02.00

2. **xApp 開發**
   - ricxappframe Python: https://gerrit.o-ran-sc.org/r/ric-plt/xapp-frame-py
   - ricsdl: https://gerrit.o-ran-sc.org/r/ric-plt/sdlpy

### TensorFlow & PyTorch 文檔

1. **TensorFlow 2.15.0**
   - 官方文檔: https://www.tensorflow.org/versions/r2.15/api_docs
   - GPU 支持: https://www.tensorflow.org/install/gpu

2. **PyTorch 2.1.2**
   - 官方文檔: https://pytorch.org/docs/2.1/
   - CUDA 支持: https://pytorch.org/get-started/locally/

3. **Flower (Federated Learning)**
   - 官方文檔: https://flower.dev/docs/
   - 快速開始: https://flower.dev/docs/framework/tutorial-quickstart-pytorch.html

---

## 部署完成後

### 驗證清單

- [ ] 所有 ML xApp Pod 狀態為 Running (1/1)
- [ ] 健康檢查通過（liveness 和 readiness）
- [ ] GPU 資源被正確分配和使用
- [ ] TensorFlow/PyTorch 可以檢測到 GPU
- [ ] 日誌中無 ERROR（除了預期的連接錯誤）
- [ ] 與其他 xApp 的 RMR 消息路由正常

### 文檔更新

請在完成 ML xApp 部署後，創建類似的詳細部署文檔：

1. **QoE Predictor 部署文檔**
   - 遇到的問題和解決方案
   - GPU 配置細節
   - 性能測試結果

2. **Federated Learning 部署文檔**
   - 同上
   - Flower framework 配置
   - 多 client 測試結果

3. **更新 README.md**
   - 將 Phase 4 標記為完成
   - 添加 ML xApp 到已部署列表

---

## 聯繫與支持

如有任何問題或需要協助，請：

1. 參考本文檔的「已知問題與解決方案」章節
2. 查閱相關的參考文檔
3. 檢查 GitHub Issues

**專案作者**：蔡秀吉（thc1006）

---

**祝部署順利！記得詳實記錄每個步驟和遇到的問題，為未來的部署者提供寶貴的經驗。**

---

**更新記錄**：
- 2025-11-14：初始版本，基於 Phase 1-3 的經驗創建
