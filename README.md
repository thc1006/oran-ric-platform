# O-RAN RIC Platform - 生產級部署

[![O-RAN SC J Release](https://img.shields.io/badge/O--RAN%20SC-J%20Release-blue)](https://o-ran-sc.org)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-326ce5)](https://kubernetes.io)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)

## 專案簡介

本專案提供生產級的 O-RAN Near-RT RIC Platform (J Release) 部署方案，包含已驗證的 xApp 實現。

**作者**：蔡秀吉（thc1006）

---

## 當前狀態與進度

### Phase 1：基礎 xApp 部署 ✅ 完成

**狀態**：生產就緒
**版本標籤**：`v1.0.0-phase1`

已成功部署並驗證的 xApp：
- **KPIMON xApp** - KPI 監控與異常檢測
- **RAN Control xApp** - RAN 控制與優化

### Phase 2：專案重組 ✅ 完成

**狀態**：已完成
**版本標籤**：`v1.0.0-phase2`

完成項目：
- 統一 legacy 資料夾位置
- 清理專案結構
- 統一命名規範

詳細記錄：[docs/PROJECT-REORGANIZATION-PLAN.md](docs/PROJECT-REORGANIZATION-PLAN.md)

### Phase 3：Traffic Steering xApp 部署 ✅ 完成

**狀態**：生產就緒
**版本標籤**：`v1.0.0-phase3`
**部署日期**：2025-11-14

新增部署的 xApp：
- **Traffic Steering xApp** - 策略導向的切換決策

**重要技術突破**：
- 解決 ricxappframe 3.2.2 的 RMR API 使用問題
- 建立標準化的 xApp 開發模式（組合優於繼承）
- 完成依賴版本驗證（ricsdl 3.0.2 + redis 4.1.1）

詳細部署指南：[docs/traffic-steering-deployment.md](docs/traffic-steering-deployment.md)

### Phase 4：ML xApp 部署 🚧 待 GPU 工作站

**狀態**：準備中
**需求**：GPU 加速運算環境

待部署的 ML xApp：
- **QoE Predictor xApp** - QoE 預測與優化（需要 TensorFlow 2.15.0）
- **Federated Learning xApp** - 聯邦學習框架（需要 TensorFlow + PyTorch）

**交接文檔**：[docs/GPU-WORKSTATION-HANDOFF.md](docs/GPU-WORKSTATION-HANDOFF.md)

---

## 📦 RIC Platform 配置 (ric-dep)

本專案包含來自 **O-RAN SC J Release** 的完整部署配置，並已針對生產環境進行驗證和客製化。

**重要修正**：
- ✅ RTMgr 版本已修正為 0.9.6（原始版本 0.3.8 會導致部署失敗）
- ✅ 包含所有 Helm chart 依賴，開箱即用

**詳細說明**：[docs/RIC-DEP-CUSTOMIZATION.md](docs/RIC-DEP-CUSTOMIZATION.md)

---

## 📦 RIC Platform 配置 (ric-dep)

本專案包含來自 **O-RAN SC J Release** 的完整部署配置，並已針對生產環境進行驗證和客製化。

**重要修正**：
- ✅ RTMgr 版本已修正為 0.9.6（原始版本 0.3.8 會導致部署失敗）
- ✅ 包含所有 Helm chart 依賴，開箱即用

**詳細說明**：[docs/RIC-DEP-CUSTOMIZATION.md](docs/RIC-DEP-CUSTOMIZATION.md)

---

## 快速開始 (5 分鐘部署)

請參考：**[docs/QUICK-START.md](docs/QUICK-START.md)**

此指南幫助您快速部署已經驗證成功的 KPIMON 和 RAN Control xApp。

---

## 完整部署指南

需要詳細步驟？請參考：**[docs/deployment-guide-complete.md](docs/deployment-guide-complete.md)**

包含：
- 環境準備
- RIC Platform 完整部署
- xApp 部署與驗證
- 問題排查與解決方案

---

## 系統需求

### 必要組件
- Kubernetes (k3s): v1.28+
- Helm: 3.x
- Docker: 最新版本
- Python: 3.11+

### 系統資源
- CPU: 8 核心以上
- 記憶體: 16GB 以上
- 磁碟: 100GB 以上

---

## 專案結構

```
oran-ric-platform/
├── docs/                      # 部署指南與文檔
│   ├── QUICK-START.md         # 5 分鐘快速部署
│   ├── deployment-guide-complete.md  # 完整部署指南
│   ├── traffic-steering-deployment.md  # Traffic Steering 部署指南
│   ├── GPU-WORKSTATION-HANDOFF.md    # GPU 工作站交接文檔
│   ├── RIC-DEP-CUSTOMIZATION.md  # ric-dep 客製化說明
│   └── PROJECT-REORGANIZATION-PLAN.md # 專案重組計畫
├── ric-dep/                   # RIC Platform Helm charts (O-RAN SC J Release + 客製化)
├── xapps/                     # xApp 實現
│   ├── kpimon-go-xapp/        # ✅ KPI 監控 xApp (已部署)
│   │   ├── deploy/            # Kubernetes 部署清單
│   │   ├── src/               # 源代碼
│   │   └── README.md          # xApp 說明
│   ├── rc-xapp/               # ✅ RAN Control xApp (已部署)
│   │   ├── deploy/            # Kubernetes 部署清單
│   │   ├── src/               # 源代碼
│   │   └── README.md          # xApp 說明
│   ├── traffic-steering/      # ✅ Traffic Steering xApp (已部署)
│   │   ├── deploy/            # Kubernetes 部署清單
│   │   ├── src/               # 源代碼
│   │   ├── Dockerfile         # Docker 構建文件
│   │   └── requirements.txt   # Python 依賴
│   ├── qoe-predictor/         # 🚧 QoE Predictor xApp (待 GPU)
│   │   └── requirements.txt   # 需要 TensorFlow 2.15.0
│   └── federated-learning/    # 🚧 Federated Learning xApp (待 GPU)
│       └── requirements.txt   # 需要 TensorFlow + PyTorch
├── legacy/                    # 參考實現（不部署）
└── scripts/                   # 自動化腳本
```

---

## 已部署並驗證的 xApp

### KPIMON xApp ✅
- **功能**：KPI 監控與異常檢測
- **E2 Service Model**：E2SM-KPM v3.0
- **監控指標**：20 種 KPI 類型
- **狀態**：生產就緒
- **詳細說明**：[xapps/kpimon-go-xapp/README.md](xapps/kpimon-go-xapp/README.md)

### RAN Control xApp ✅
- **功能**：RAN 控制與優化
- **E2 Service Model**：E2SM-RC v2.0
- **優化算法**：5 種（切換、資源、負載均衡、切片、功率）
- **狀態**：生產就緒
- **詳細說明**：[xapps/rc-xapp/README.md](xapps/rc-xapp/README.md)

### Traffic Steering xApp ✅
- **功能**：策略導向的切換決策
- **E2 Service Model**：E2SM-KPM v3.0 + E2SM-RC v2.0
- **整合**：與 QoE Predictor 和 RC xApp 協作
- **特性**：
  - UE 性能指標監控（RSRP、RSRQ、吞吐量）
  - A1 策略管理
  - 動態切換決策
  - RESTful 健康檢查 API
- **狀態**：生產就緒
- **部署日期**：2025-11-14
- **詳細說明**：[docs/traffic-steering-deployment.md](docs/traffic-steering-deployment.md)

### 待部署 xApp（需要 GPU）

#### QoE Predictor xApp 🚧
- **功能**：QoE 預測與優化
- **依賴**：TensorFlow 2.15.0 (~500MB)
- **需求**：GPU 加速運算
- **狀態**：待 GPU 工作站部署

#### Federated Learning xApp 🚧
- **功能**：聯邦學習框架
- **依賴**：TensorFlow + PyTorch (~1.5GB)
- **需求**：GPU 加速運算
- **狀態**：待 GPU 工作站部署

---

## 部署流程

### Step 1: Clone 專案

```bash
git clone https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform
```

**就這麼簡單！** 所有配置已包含在專案中，無需額外步驟。

### Step 2: 設置環境變數

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### Step 3: 部署 RIC Platform

參考 [docs/QUICK-START.md](docs/QUICK-START.md) 或 [docs/deployment-guide-complete.md](docs/deployment-guide-complete.md)

### Step 4: 部署 xApp

```bash
# KPIMON xApp
cd xapps/kpimon-go-xapp
docker build -t localhost:5000/xapp-kpimon:1.0.0 .
docker push localhost:5000/xapp-kpimon:1.0.0
kubectl apply -f deploy/

# RAN Control xApp
cd ../rc-xapp
docker build -t localhost:5000/xapp-ran-control:1.0.0 .
docker push localhost:5000/xapp-ran-control:1.0.0
kubectl apply -f deploy/

# Traffic Steering xApp
cd ../traffic-steering
docker build --no-cache -t localhost:5000/xapp-traffic-steering:1.0.0 .
docker push localhost:5000/xapp-traffic-steering:1.0.0
kubectl apply -f deploy/
```

**注意**：Traffic Steering xApp 首次構建時建議使用 `--no-cache` 選項。

### Step 5: 驗證部署

```bash
# 檢查 Pod 狀態
kubectl get pods -n ricplt
kubectl get pods -n ricxapp

# 預期輸出（所有 Pod 應為 Running 1/1）
NAME                                READY   STATUS    RESTARTS   AGE
kpimon-xxxx                         1/1     Running   0          XXm
ran-control-xxxx                    1/1     Running   0          XXm
traffic-steering-xxxx               1/1     Running   0          XXm

# 查看 xApp 日誌
kubectl logs -n ricxapp -l app=kpimon
kubectl logs -n ricxapp -l app=ran-control
kubectl logs -n ricxapp -l app=traffic-steering

# 測試健康檢查端點
kubectl get svc -n ricxapp
# 使用 kubectl port-forward 測試 API
kubectl port-forward -n ricxapp svc/traffic-steering 8080:8080
curl http://localhost:8080/ric/v1/health/alive
curl http://localhost:8080/ric/v1/health/ready
```

---

## RIC Platform 組件

部署成功後包含以下組件：

- **Redis (dbaas)**: 分布式存儲
- **E2 Termination**: E2 接口終端
- **A1 Mediator**: A1 接口調解器
- **RTMgr**: 路由管理器
- **InfluxDB**: 時間序列數據庫

---

## 版本資訊

- **O-RAN SC Release**: J (April 2025)
- **Kubernetes**: v1.28.5
- **RMR Library**: 4.9.4
- **Python xApp Framework**: ricxappframe 3.2.2

---

## 問題排查

遇到問題？請參考：

1. **快速開始指南的常見問題區**：[docs/QUICK-START.md#常見問題](docs/QUICK-START.md#常見問題)
2. **完整部署指南的問題排查章節**：[docs/deployment-guide-complete.md#常見問題與解決方案](docs/deployment-guide-complete.md#常見問題與解決方案)

---

## 技術支援

- **GitHub Issues**: https://github.com/thc1006/oran-ric-platform/issues
- **作者**: 蔡秀吉（thc1006）

---

## 授權

Apache License 2.0 - 參見 [LICENSE](LICENSE)

---

**部署指引優先級**：
1. 快速部署：[docs/QUICK-START.md](docs/QUICK-START.md)
2. 完整指南：[docs/deployment-guide-complete.md](docs/deployment-guide-complete.md)
3. xApp 文檔：各 xApp 目錄下的 README.md
