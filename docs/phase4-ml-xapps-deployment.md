# Phase 4: ML xApps 部署指南

**作者：蔡秀吉 (thc1006)**
**日期：2025-11-14**
**Phase：4 - ML xApps (QoE Predictor + Federated Learning)**

---

## 1. 概述

Phase 4 專注於部署兩個機器學習 xApp：
- **QoE Predictor xApp**：基於 TensorFlow 的 QoE 預測
- **Federated Learning xApp**：支援 TensorFlow 和 PyTorch 的聯邦學習

本階段的關鍵任務是：
1. 修正依賴版本問題（ricsdl + redis 版本衝突）
2. 重構 RMR API 使用模式（從繼承模式改為組合模式）
3. 確保 Docker 鏡像構建成功
4. 驗證 ML 功能正常運行

---

## 2. 關鍵技術發現（繼承自 Phase 3）

### 2.1 RMR API 組合模式

**重要：所有 xApp 必須使用組合模式，而非繼承模式。**

#### 錯誤模式（❌ 不要使用）
```python
# ❌ 錯誤的繼承模式
from ricxappframe.xapp_frame import RmrXapp, rmr  # 錯誤的類名

class MyXapp(RmrXapp):  # 繼承（會失敗）
    def send_message(self):
        sbuf = self.rmr_alloc(4096)  # AttributeError！
```

#### 正確模式（✅ 必須使用）
```python
# ✅ 正確的組合模式
from ricxappframe.xapp_frame import RMRXapp, rmr  # 正確的類名（全大寫）

class MyXapp:  # 不繼承
    def __init__(self):
        self.xapp = None  # 組合 RMRXapp 實例

    def start(self):
        # 在 start() 方法中創建 RMRXapp 實例
        self.xapp = RMRXapp(self._handle_message,
                            rmr_port=4560,
                            use_fake_sdl=False)

        # 調用 run() 方法（blocking call）
        self.xapp.run()

    def _send_message(self, msg_type: int, payload: str):
        # 透過組合的 xapp 實例發送消息
        if self.xapp:
            success = self.xapp.rmr_send(payload.encode(), msg_type)
```

**關鍵點：**
1. **類名**：使用 `RMRXapp`（全大寫），而非 `RmrXapp`
2. **組合**：`self.xapp = None` → 在 start() 中初始化
3. **參數**：必須包含 `use_fake_sdl=False`
4. **run() 調用**：`self.xapp.run()`（不使用 `thread=True`）

---

## 3. 依賴版本問題與解決方案

### 3.1 問題分析

**原始問題（Phase 1-3 已解決）：**
- `redis==5.0.1` 不相容 `ricsdl==3.0.2`
- `ricsdl` 會降級 `redis` 到 `4.1.1`
- `protobuf==4.25.1` 與 O-RAN 框架不相容

### 3.2 正確的依賴順序

**requirements.txt 必須按此順序：**
```txt
# IMPORTANT: ricsdl must be installed first to lock down redis version
# DO NOT change the order of these dependencies

# O-RAN SDL (MUST be first)
ricsdl==3.0.2

# Data Storage (version locked by ricsdl)
redis==4.1.1
hiredis==2.0.0

# O-RAN xApp Framework
ricxappframe==3.2.2
mdclogpy==1.1.4

# Message Processing (version locked to avoid conflicts)
protobuf==3.20.3  # NOT 4.25.1
msgpack==1.0.7

# Machine Learning dependencies...
```

### 3.3 Dockerfile 修改

**關鍵修改：先安裝 ricsdl**
```dockerfile
# Install Python dependencies
# CRITICAL: Install ricsdl first to lock down redis version
COPY requirements.txt .
RUN pip install --no-cache-dir ricsdl==3.0.2 && \
    pip install --no-cache-dir -r requirements.txt
```

**原理：**
- 第一個 `pip install ricsdl==3.0.2` 確保 ricsdl 先安裝
- 這會鎖定 `redis==4.1.1` 版本
- 後續安裝不會降級或升級這些關鍵套件

---

## 4. QoE Predictor xApp 部署

### 4.1 依賴修正

#### 修正前（❌ 錯誤）
```txt
ricxappframe==3.2.2
redis==5.0.1          # ❌ 錯誤版本
protobuf==4.25.1      # ❌ 錯誤版本
# 缺少 ricsdl
```

#### 修正後（✅ 正確）
```txt
ricsdl==3.0.2         # ✅ 必須先安裝
redis==4.1.1          # ✅ ricsdl 指定版本
hiredis==2.0.0        # ✅ 加速 Redis
ricxappframe==3.2.2
protobuf==3.20.3      # ✅ 正確版本
tensorflow==2.15.0
```

### 4.2 RMR API 重構

#### 修正前（❌ 錯誤）
```python
from ricxappframe.xapp_frame import RmrXapp, rmr  # ❌ 錯誤類名

def start(self):
    self.xapp = RmrXapp(self._handle_message, rmr_port=self.config['rmr_port'])  # ❌
    self.xapp.run(thread=True)  # ❌ 錯誤參數
```

#### 修正後（✅ 正確）
```python
from ricxappframe.xapp_frame import RMRXapp, rmr  # ✅ 正確類名

def start(self):
    self.running = True

    # Start Flask API and other threads first
    # ...

    time.sleep(2)  # 確保 threads 就緒

    # Initialize RMR xApp (CRITICAL: Use composition pattern)
    self.xapp = RMRXapp(self._handle_message,
                        rmr_port=self.config['rmr_port'],
                        use_fake_sdl=False)

    # Run the xApp (blocking call)
    self.xapp.run()
```

### 4.3 Docker 構建

```bash
# 創建必要的目錄
cd xapps/qoe-predictor
mkdir -p models config
echo "# ML models directory" > models/README.md

# 構建 Docker 鏡像（使用 --no-cache）
docker build --no-cache -t qoe-predictor:1.0.0 .
```

**注意事項：**
- 首次構建建議使用 `--no-cache` 確保依賴正確安裝
- 構建時間約 10-15 分鐘（包含 RMR 庫編譯）
- 確保有足夠的磁碟空間（約 2-3 GB）

---

## 5. Federated Learning xApp 部署

### 5.1 依賴修正

Federated Learning xApp 的依賴問題與 QoE Predictor 相同。

#### 修正前（❌ 錯誤）
```txt
ricxappframe==3.2.2
redis==5.0.1          # ❌ 錯誤版本
protobuf==4.25.1      # ❌ 錯誤版本
tensorflow==2.15.0
torch==2.1.2
flwr==1.5.0
```

#### 修正後（✅ 正確）
```txt
ricsdl==3.0.2         # ✅ 必須先安裝
redis==4.1.1          # ✅ ricsdl 指定版本
hiredis==2.0.0        # ✅ 加速 Redis
ricxappframe==3.2.2
protobuf==3.20.3      # ✅ 正確版本
tensorflow==2.15.0
torch==2.1.2
flwr==1.5.0           # Flower framework for federated learning
```

### 5.2 RMR API 重構

Federated Learning xApp 的 RMR API 重構與 QoE Predictor 完全相同。

#### 修正前（❌ 錯誤）
```python
from ricxappframe.xapp_frame import RmrXapp, rmr  # ❌

def start(self):
    self.xapp = RmrXapp(self._handle_message, rmr_port=self.config['rmr_port'])  # ❌
    self.xapp.run(thread=True)  # ❌
```

#### 修正後（✅ 正確）
```python
from ricxappframe.xapp_frame import RMRXapp, rmr  # ✅

def start(self):
    self.running = True

    # Start Flask API and FL threads first
    # ...

    time.sleep(2)

    # Initialize RMR xApp (composition pattern)
    self.xapp = RMRXapp(self._handle_message,
                        rmr_port=self.config['rmr_port'],
                        use_fake_sdl=False)

    # Run the xApp (blocking call)
    self.xapp.run()
```

### 5.3 Docker 構建

```bash
# 創建必要的目錄
cd xapps/federated-learning
mkdir -p models aggregator
echo "# ML models directory" > models/README.md
echo "# Aggregator directory" > aggregator/README.md

# 構建 Docker 鏡像
docker build --no-cache -t federated-learning:1.0.0 .
```

---

## 6. GPU 支援配置

### 6.1 系統需求

**硬體需求：**
- NVIDIA GPU（Compute Capability 7.0+）
- 8GB GPU 記憶體（QoE Predictor）
- 12GB GPU 記憶體（Federated Learning，推薦）

**軟體需求：**
- CUDA 11.8 或 12.x
- cuDNN 8.6+
- NVIDIA Container Toolkit

### 6.2 GPU 環境檢查

```bash
# 檢查 NVIDIA GPU
nvidia-smi

# 檢查 CUDA 版本
nvcc --version

# 測試 Docker + GPU
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

### 6.3 Kubernetes GPU 配置

```yaml
# xapp-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qoe-predictor
  namespace: ricxapp
spec:
  template:
    spec:
      containers:
      - name: qoe-predictor
        image: qoe-predictor:1.0.0
        resources:
          limits:
            nvidia.com/gpu: 1  # 請求 1 個 GPU
```

---

## 7. 驗證與測試

### 7.1 Docker 鏡像驗證

```bash
# 檢查鏡像是否構建成功
docker images | grep qoe-predictor
docker images | grep federated-learning

# 測試本地運行（無 GPU）
docker run --rm qoe-predictor:1.0.0 python3 -c "import tensorflow; print(tensorflow.__version__)"

# 測試 GPU 支援（如果有 GPU）
docker run --rm --gpus all qoe-predictor:1.0.0 python3 -c "import tensorflow as tf; print(tf.config.list_physical_devices('GPU'))"
```

### 7.2 健康檢查 API

```bash
# QoE Predictor 健康檢查
curl http://localhost:8090/health/alive
curl http://localhost:8090/health/ready

# Federated Learning 健康檢查
curl http://localhost:8110/health/alive
curl http://localhost:8110/health/ready
```

---

## 8. 常見問題排查

### 8.1 依賴版本衝突

**問題：redis 版本降級錯誤**
```
ERROR: pip's dependency resolver does not currently take into account all the packages that are installed
```

**解決方案：**
1. 確認 `requirements.txt` 中 `ricsdl==3.0.2` 在最前面
2. 確認 `Dockerfile` 中先安裝 `ricsdl`
3. 使用 `--no-cache` 重新構建

### 8.2 RMR API AttributeError

**問題：**
```
AttributeError: 'MyXapp' object has no attribute 'rmr_send'
```

**解決方案：**
1. 檢查是否使用組合模式（`self.xapp = RMRXapp(...)`）
2. 檢查類名是否為 `RMRXapp`（全大寫）
3. 確認 `use_fake_sdl=False` 參數存在

### 8.3 Docker 構建失敗（models/ 目錄）

**問題：**
```
ERROR: failed to compute cache key: "/models": not found
```

**解決方案：**
```bash
mkdir -p models
echo "# ML models directory" > models/README.md
```

### 8.4 TensorFlow GPU 未檢測到

**問題：**
```python
tf.config.list_physical_devices('GPU')  # []
```

**解決方案：**
1. 確認 NVIDIA Container Toolkit 已安裝
2. 使用 `--gpus all` 參數運行 Docker
3. 檢查 CUDA 版本與 TensorFlow 兼容性

---

## 9. Phase 4 成功標準

### 9.1 QoE Predictor xApp

- ✅ Docker 鏡像構建成功
- ✅ 依賴版本正確（ricsdl 3.0.2 + redis 4.1.1）
- ✅ RMR API 使用組合模式
- ✅ 健康檢查 API 響應正常
- ✅ TensorFlow 模型載入成功

### 9.2 Federated Learning xApp

- ✅ Docker 鏡像構建成功
- ✅ 依賴版本正確
- ✅ RMR API 使用組合模式
- ✅ 健康檢查 API 響應正常
- ✅ TensorFlow + PyTorch 同時可用

---

## 10. 參考資源

### 10.1 Phase 3 經驗（Traffic Steering）

- **文檔**：`docs/traffic-steering-deployment.md`
- **源代碼**：`xapps/traffic-steering/src/traffic_steering.py`（組合模式範例）
- **關鍵發現**：RMR API 組合模式必須性

### 10.2 已驗證的依賴版本

| 套件           | 版本     | 說明                |
|--------------|--------|-------------------|
| ricxappframe | 3.2.2  | O-RAN xApp 框架     |
| ricsdl       | 3.0.2  | 必須先安裝，防止降級        |
| redis        | 4.1.1  | ricsdl 3.0.2 指定版本 |
| hiredis      | 2.0.0  | Redis 加速          |
| protobuf     | 3.20.3 | 而非 4.25.1         |
| tensorflow   | 2.15.0 | ML 框架             |
| torch        | 2.1.2  | ML 框架（FL only）    |

---

## 11. 下一步（未來工作）

### 11.1 Kubernetes 部署（Phase 5）

- 創建 Kubernetes Deployment 配置
- 配置 GPU 資源請求
- 設置 Service 和 Ingress
- 配置 Persistent Volume（模型存儲）

### 11.2 E2 訂閱配置

- 配置 E2SM-KPM 訂閱（QoE 指標）
- 配置 E2SM-RC 控制（流量調整）
- 測試 RIC Indication 處理

### 11.3 A1 策略配置

- 設計 QoE 閾值策略
- 設計聯邦學習訓練策略
- 測試策略更新流程

---

**Phase 4 完成日期：2025-11-14**
**作者：蔡秀吉 (thc1006)**
