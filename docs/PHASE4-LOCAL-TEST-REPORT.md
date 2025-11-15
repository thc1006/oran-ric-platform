# Phase 4 本地測試報告

**作者：蔡秀吉 (thc1006)**
**日期：2025-11-15**
**測試環境：Windows 11 + WSL2 + Docker Desktop**

---

## 1. 執行摘要

本報告記錄了 Phase 4（ML xApps - QoE Predictor + Federated Learning）的本地測試過程。Phase 4 的主要代碼重構工作已完成，包括依賴版本修正和 RMR API 組合模式實現。本次測試專注於驗證代碼正確性和 Docker 構建可行性。

### 關鍵發現

✅ **已完成**：
- QoE Predictor 和 Federated Learning xApp 的依賴版本已正確修正
- RMR API 使用已成功從繼承模式重構為組合模式
- 代碼結構符合 Phase 3 Traffic Steering 的最佳實踐
- 完整的配置文件和文檔已就位

⚠️ **待解決**：
- Docker 構建需要完整的編譯環境（gcc、g++、cmake 等）
- ML 庫（TensorFlow、PyTorch）的安裝時間較長，建議使用預構建鏡像
- 本地測試環境需要額外配置 Redis 和 RMR 路由

---

## 2. 測試環境

### 2.1 硬件配置

- **操作系統**：Windows 11
- **WSL版本**：WSL 2（Kernel 6.6.87.2-microsoft-standard-WSL2）
- **Docker**：Docker Desktop 28.5.1
- **CPU**：12 cores
- **內存**：7.68 GiB
- **GPU**：支持 NVIDIA runtime（`docker.com/gpu=webgpu`）

### 2.2 軟件環境

- **Docker Engine**：28.5.1
- **Python**：3.11（基礎鏡像）
- **Runtimes**：`nvidia`, `runc`（支持 GPU）

---

## 3. Phase 4 代碼審查結果

### 3.1 QoE Predictor xApp

**檢查項目**：

✅ **依賴配置**（`requirements.txt`）：
```txt
# ✅ 正確的依賴順序
ricsdl==3.0.2        # MUST be first
redis==4.1.1          # ricsdl 指定版本
hiredis==2.0.0        # Redis 加速
ricxappframe==3.2.2
mdclogpy==1.1.4
protobuf==3.20.3      # 正確版本（非 4.25.1）
tensorflow==2.15.0
```

✅ **RMR API 組合模式**（`src/qoe_predictor.py`）：
```python
# ✅ 正確的組合模式實現
class QoEPredictor:
    def __init__(self, config_path: str = "/app/config/config.json"):
        self.xapp = None  # 組合，非繼承
        # ...

    def start(self):
        # 在 start() 中初始化 RMRXapp
        self.xapp = RMRXapp(self._handle_message,
                            rmr_port=self.config['rmr_port'],
                            use_fake_sdl=False)
        self.xapp.run()  # 阻塞調用

    def _send_message(self, msg_type: int, payload: str):
        if self.xapp:
            success = self.xapp.rmr_send(payload.encode(), msg_type)
```

**關鍵亮點**：
- ✅ 第 8-9 行包含清晰的註釋說明使用組合模式
- ✅ 第 54 行：`self.xapp = None`（組合）
- ✅ 第 275-277 行：正確的 RMRXapp 初始化
- ✅ 第 586 行：透過組合的 xapp 實例發送消息

### 3.2 Federated Learning xApp

**檢查項目**：

✅ **依賴配置**（`requirements.txt`）：
```txt
# ✅ 正確的依賴順序
ricsdl==3.0.2         # MUST be first
redis==4.1.1
hiredis==2.0.0
ricxappframe==3.2.2
protobuf==3.20.3

# ML 依賴
tensorflow==2.15.0
torch==2.1.2
torchvision==0.16.2
flwr==1.5.0           # Flower 聯邦學習框架
```

✅ **RMR API 組合模式**（`src/federated_learning.py`）：
```python
# ✅ 正確的組合模式實現
class FederatedLearning:
    def __init__(self, config_path: str = "/app/config/config.json"):
        self.xapp = None  # 組合，非繼承
        # ...

    def start(self):
        # 第 338-340 行：正確的註釋和實現
        # Initialize RMR xApp (CRITICAL: Use composition pattern, not inheritance)
        # This follows the proven pattern from Traffic Steering xApp
        self.xapp = RMRXapp(self._handle_message,
                            rmr_port=self.config['rmr_port'],
                            use_fake_sdl=False)
        self.xapp.run()
```

**關鍵亮點**：
- ✅ 第 8-9 行包含清晰的註釋說明使用組合模式
- ✅ 第 86 行：`self.xapp = None`（組合）
- ✅ 第 338-342 行：正確的 RMRXapp 初始化，包含詳細註釋
- ✅ 支持多種 ML 框架（TensorFlow + PyTorch）
- ✅ 包含完整的配置文件（`config/config.json`，235 行）

### 3.3 配置文件

✅ **Federated Learning config.json**：
- 完整的 RMR 消息類型定義
- 詳細的 FL 配置（min_clients、rounds、aggregation_method 等）
- 多個 ML 模型配置（network_optimization, anomaly_detection, traffic_prediction, resource_allocation）
- 安全配置（加密、認證、差分隱私）
- 健康檢查配置（liveness + readiness probe）

✅ **Dockerfile**：
- 正確的依賴安裝順序（先安裝 ricsdl）
- RMR 庫安裝（Release J 版本 4.9.4）
- 非 root 用戶配置
- 健康檢查腳本

---

## 4. Docker 構建測試

### 4.1 完整構建測試（失敗）

**測試命令**：
```bash
cd xapps/federated-learning
docker build -t fl-xapp:test .
```

**結果**：❌ 失敗

**失敗原因**：
1. **依賴數量龐大**：需要安裝 326 個系統包（約 1.5 GB）
2. **下載時間過長**：需要下載 299 MB 的套件
3. **編譯 RMR 庫**：從源代碼編譯 RMR 庫需要 gcc、g++、cmake 等完整編譯環境
4. **ML 庫較大**：TensorFlow 和 PyTorch 下載和安裝耗時

**構建進度**：
- ✅ Step 1-7：基礎鏡像和工作目錄設置
- ✅ Step 8（部分）：開始下載系統依賴
- ❌ Step 8（中斷）：在安裝大量 Boost、HDF5、OpenMPI 等庫時中斷

### 4.2 簡化構建測試（失敗）

為加快測試，創建了簡化版 Dockerfile（`Dockerfile.test`）：
- 移除 RMR 庫編譯
- 跳過 TensorFlow、PyTorch 等重型 ML 庫
- 僅安裝核心 O-RAN 依賴

**測試命令**：
```bash
cd xapps/federated-learning
docker build -f Dockerfile.test -t fl-xapp:test-light .
```

**結果**：❌ 失敗

**失敗原因**：
```
error: command 'gcc' failed: No such file or directory
```

**問題分析**：
- `hiredis==2.0.0` 是一個 C 擴展包，需要從源代碼編譯
- 簡化版 Dockerfile 為加快構建，移除了 `gcc` 編譯器
- 即使是"簡化"版本，仍需要完整的編譯環境來構建 Python C 擴展

### 4.3 測試配置文件創建

✅ 創建了 `docker-compose-fl-test.yml` 用於本地測試：
- 包含 Redis 服務（FL xApp 依賴）
- 包含 FL xApp 服務配置
- 支持環境變量覆蓋（Redis 連接）
- 包含數據卷持久化（models、logs）
- 預留 GPU 配置（已註釋）

---

## 5. 驗證的內容

### 5.1 代碼結構 ✅

- ✅ QoE Predictor 和 Federated Learning 的 `src/` 代碼已仔細審查
- ✅ 兩個 xApp 都正確使用了組合模式，與 Traffic Steering 一致
- ✅ 代碼註釋清晰，說明了關鍵設計決策
- ✅ 包含完整的錯誤處理和日誌記錄

### 5.2 依賴配置 ✅

- ✅ `requirements.txt` 中的依賴順序正確（ricsdl 在最前）
- ✅ Redis 版本已修正（4.1.1 而非 5.0.1）
- ✅ Protobuf 版本正確（3.20.3 而非 4.25.1）
- ✅ Dockerfile 中的安裝順序正確（先 ricsdl，再其他）

### 5.3 RMR API 使用 ✅

- ✅ **組合模式**：兩個 xApp 都使用 `self.xapp = None`，然後在 `start()` 中初始化
- ✅ **類名正確**：使用 `RMRXapp`（全大寫），而非 `RmrXapp`
- ✅ **參數完整**：包含 `use_fake_sdl=False` 參數
- ✅ **阻塞調用**：使用 `self.xapp.run()`（不使用 `thread=True`）
- ✅ **消息發送**：透過 `self.xapp.rmr_send()` 發送消息

### 5.4 文檔完整性 ✅

- ✅ Phase 4 部署指南（`docs/phase4-ml-xapps-deployment.md`，471 行）
- ✅ Phase 4 完成總結（`docs/PHASE4-SUMMARY.md`，479 行）
- ✅ 詳細的依賴修正說明和 RMR API 組合模式指南

---

## 6. 發現的問題與解決方案

### 6.1 Docker 構建問題

**問題 1：構建時間過長**

- **原因**：需要安裝大量系統依賴（326 個包）和大型 ML 庫
- **影響**：完整構建可能需要 30-60 分鐘
- **解決方案**：
  - 選項 A：使用多階段構建，將編譯環境和運行環境分離
  - 選項 B：使用預構建的基礎鏡像（如 `tensorflow/tensorflow:2.15.0-gpu`）
  - 選項 C：在 CI/CD 環境中構建，本地使用預構建鏡像

**問題 2：簡化版仍需編譯工具**

- **原因**：Python C 擴展（如 hiredis）需要 gcc 編譯
- **影響**：無法創建真正"輕量級"的測試鏡像
- **解決方案**：
  - 選項 A：使用預編譯的 wheel 包（`--only-binary :all:`）
  - 選項 B：移除 hiredis（非必需，僅加速 Redis 訪問）
  - 選項 C：保留 gcc，但使用 `--no-install-recommends` 減少依賴

**問題 3：網絡下載穩定性**

- **原因**：需要從 Debian 倉庫下載大量套件
- **影響**：構建可能因網絡中斷而失敗
- **解決方案**：
  - 使用鏡像源（如中國大陸的阿里雲鏡像）
  - 使用 `--retry` 參數重試下載
  - 在穩定網絡環境中構建

### 6.2 建議的 Dockerfile 優化

**優化版 Dockerfile**（推薦用於生產）：

```dockerfile
# Multi-stage build for Federated Learning xApp
# Stage 1: Build dependencies
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc g++ make cmake git curl \
    libboost-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels ricsdl==3.0.2 && \
    pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

WORKDIR /app

# Install only runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy pre-built wheels from builder
COPY --from=builder /wheels /wheels

# Install Python packages from wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels \
    ricsdl redis hiredis ricxappframe mdclogpy protobuf msgpack \
    flask flask-restful flask-cors pyyaml jsonschema \
    cryptography prometheus-client numpy && \
    rm -rf /wheels

# Copy application code
COPY src/ ./src/
COPY config/ ./config/
COPY models/ ./models/
COPY aggregator/ ./aggregator/

# Create directories and health check
RUN mkdir -p /app/models/global /app/models/local /app/logs /app/data && \
    echo '#!/bin/bash\ncurl -f http://localhost:8110/health/alive || exit 1' > /usr/local/bin/health_check.sh && \
    chmod +x /usr/local/bin/health_check.sh

# Security: non-root user
RUN useradd -m -u 1000 xapp && chown -R xapp:xapp /app
USER xapp

# Environment
ENV PYTHONUNBUFFERED=1 \
    RMR_SRC_ID=federated-learning

EXPOSE 4590 4591 8110

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD /usr/local/bin/health_check.sh

CMD ["python3", "/app/src/federated_learning.py"]
```

**關鍵優化點**：
1. **多階段構建**：將編譯環境和運行環境分離，減小最終鏡像大小
2. **預構建 wheels**：第一階段構建所有 wheel 包，第二階段直接安裝
3. **最小運行時依賴**：運行階段只安裝必需的庫（curl、libgomp1）
4. **移除不必要的工具**：gcc、g++、cmake 等僅在構建階段存在

---

## 7. 後續步驟建議

### 7.1 立即可行的步驟

1. **使用優化的 Dockerfile**
   - 採用上述多階段構建方案
   - 預期構建時間：15-30 分鐘（初次）、5-10 分鐘（緩存後）

2. **在 Linux 環境中構建**
   - WSL2 的 I/O 性能不如原生 Linux
   - 建議在 Ubuntu 20.04/22.04 或 Debian 11/12 上構建

3. **使用 Docker Compose 進行本地測試**
   - 使用已創建的 `docker-compose-fl-test.yml`
   - 先測試基本功能（健康檢查、API 端點），再測試 ML 功能

### 7.2 中期步驟

1. **創建 GPU 支持的 Dockerfile**
   - 基於 `nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04`
   - 包含 TensorFlow GPU 和 PyTorch GPU 支持
   - 確保 GPU 資源在 Kubernetes 中正確分配

2. **Kubernetes 部署配置**
   - 創建 `deploy/` 目錄，包含：
     - `deployment.yaml`：Pod 定義
     - `service.yaml`：Service 定義
     - `configmap.yaml`：配置文件
     - `secret.yaml`：敏感信息（如果需要）
   - 配置 GPU 資源請求（`nvidia.com/gpu: 1`）

3. **集成測試**
   - 在 K3s 集群中部署
   - 驗證與 E2Term、A1 Mediator 的連接
   - 測試 RMR 消息收發
   - 驗證 ML 模型初始化和推理

### 7.3 長期步驟

1. **性能優化**
   - 模型量化（減小模型大小）
   - 推理優化（使用 ONNX Runtime 或 TensorRT）
   - 批處理優化（提高吞吐量）

2. **監控和日誌**
   - Prometheus 指標採集
   - Grafana 儀表板
   - ELK/EFK 日誌聚合

3. **CI/CD 集成**
   - GitHub Actions 或 GitLab CI 自動構建
   - 自動化測試（單元測試、集成測試）
   - 自動部署到測試環境

---

## 8. 結論

### 8.1 Phase 4 完成度評估

| 項目 | 狀態 | 完成度 | 備註 |
|------|------|--------|------|
| 依賴版本修正 | ✅ 完成 | 100% | ricsdl、redis、protobuf 已正確配置 |
| RMR API 重構 | ✅ 完成 | 100% | 已改為組合模式，與 Phase 3 一致 |
| 代碼結構優化 | ✅ 完成 | 100% | 清晰的註釋和錯誤處理 |
| 配置文件 | ✅ 完成 | 100% | 詳細的 config.json 和 Dockerfile |
| 文檔 | ✅ 完成 | 100% | 部署指南和總結文檔齊全 |
| Docker 構建 | ⏳ 進行中 | 50% | 需要優化構建流程 |
| 本地測試 | ⏳ 進行中 | 30% | 需要成功構建鏡像後進行 |
| K8s 部署 | ⏳ 待開始 | 0% | 待創建 deploy/ 配置 |

**總體完成度**：約 70-75%

### 8.2 主要成就

1. **代碼質量高**：QoE Predictor 和 Federated Learning xApp 的代碼結構清晰，遵循最佳實踐
2. **完整的文檔**：包含 950+ 行的部署指南和總結文檔
3. **正確的模式**：RMR API 組合模式實現正確，避免了 Phase 1-2 的錯誤
4. **依賴管理**：正確處理了 ricsdl、redis、protobuf 的版本衝突

### 8.3 待改進項

1. **Docker 構建效率**：需要優化構建流程，縮短構建時間
2. **測試覆蓋**：需要增加單元測試和集成測試
3. **GPU 支持**：需要創建 GPU 版本的 Dockerfile 和測試
4. **K8s 配置**：需要創建完整的 Kubernetes 部署配置

### 8.4 建議的下一步

**優先級 P0（立即執行）**：
1. 使用優化的多階段 Dockerfile 重新構建
2. 在 Linux 環境（非 WSL）中進行構建測試
3. 驗證基本功能（健康檢查、API 端點）

**優先級 P1（本週內）**：
1. 創建 Kubernetes 部署配置
2. 部署到 K3s 集群並進行集成測試
3. 驗證與 RIC 平台其他組件的集成

**優先級 P2（下週）**：
1. 創建 GPU 支持版本
2. 性能測試和優化
3. 完善監控和日誌

---

## 9. 附錄

### 9.1 測試環境詳情

```bash
# Docker 版本
Docker version 28.5.1, build e180ab8

# Docker 信息
Server Version: 28.5.1
Storage Driver: overlayfs
Cgroup Driver: cgroupfs
Runtimes: io.containerd.runc.v2 nvidia runc
CPUs: 12
Total Memory: 7.681GiB
Kernel Version: 6.6.87.2-microsoft-standard-WSL2
```

### 9.2 相關文件清單

**代碼文件**：
- `xapps/qoe-predictor/src/qoe_predictor.py`（640 行）
- `xapps/qoe-predictor/requirements.txt`（48 行）
- `xapps/qoe-predictor/Dockerfile`（88 行）
- `xapps/federated-learning/src/federated_learning.py`（800+ 行）
- `xapps/federated-learning/requirements.txt`（66 行）
- `xapps/federated-learning/Dockerfile`（100 行）
- `xapps/federated-learning/config/config.json`（236 行）

**文檔文件**：
- `docs/phase4-ml-xapps-deployment.md`（471 行）
- `docs/PHASE4-SUMMARY.md`（479 行）
- `docs/PHASE4-LOCAL-TEST-REPORT.md`（本文件）

**測試配置**：
- `docker-compose-fl-test.yml`（71 行）
- `xapps/federated-learning/Dockerfile.test`（87 行，簡化測試版）

### 9.3 參考資源

- O-RAN SC RIC Platform: https://docs.o-ran-sc.org/en/latest/projects.html
- RMR 庫文檔: https://gerrit.o-ran-sc.org/r/ric-plt/lib/rmr
- ricxappframe 文檔: https://gerrit.o-ran-sc.org/r/ric-plt/xapp-frame-py
- TensorFlow 文檔: https://www.tensorflow.org/install/docker
- PyTorch 文檔: https://pytorch.org/get-started/locally/

---

**報告結束**

作者：蔡秀吉 (thc1006)
日期：2025-11-15
版本：1.0
