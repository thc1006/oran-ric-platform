# O-RAN RIC Platform - 生產級部署

[![O-RAN SC J Release](https://img.shields.io/badge/O--RAN%20SC-J%20Release-blue)](https://o-ran-sc.org)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-326ce5)](https://kubernetes.io)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)

## 專案簡介

本專案提供生產級的 O-RAN Near-RT RIC Platform (J Release) 部署方案，包含已驗證的 xApp 實現。

**作者**：蔡秀吉（thc1006）

---

## 當前狀態與進度

### Phase 1：已部署 xApp 驗證 ✅ 完成

**狀態**：生產就緒
**版本標籤**：`v1.0.0-phase1`

已成功部署並驗證的 xApp：
- **KPIMON xApp** - KPI 監控與異常檢測
- **RAN Control xApp** - RAN 控制與優化

### Phase 2：完整專案重組 🚧 規劃中

**目標**：
- 統一 legacy 資料夾位置
- 清理專案結構
- 統一命名規範

詳細計畫請參考：[docs/PROJECT-REORGANIZATION-PLAN.md](docs/PROJECT-REORGANIZATION-PLAN.md)

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
│   └── deployment-guide-complete.md  # 完整部署指南
├── ric-dep/                   # RIC Platform Helm charts
├── xapps/                     # xApp 實現
│   ├── kpimon-go-xapp/        # KPI 監控 xApp
│   │   ├── deploy/            # Kubernetes 部署清單
│   │   ├── src/               # 源代碼
│   │   └── README.md          # xApp 說明
│   └── rc-xapp/               # RAN Control xApp
│       ├── deploy/            # Kubernetes 部署清單
│       ├── src/               # 源代碼
│       └── README.md          # xApp 說明
└── scripts/                   # 自動化腳本
```

---

## 已部署並驗證的 xApp

### KPIMON xApp
- **功能**：KPI 監控與異常檢測
- **E2 Service Model**：E2SM-KPM v3.0
- **監控指標**：20 種 KPI 類型
- **詳細說明**：[xapps/kpimon-go-xapp/README.md](xapps/kpimon-go-xapp/README.md)

### RAN Control xApp
- **功能**：RAN 控制與優化
- **E2 Service Model**：E2SM-RC v2.0
- **優化算法**：5 種（切換、資源、負載均衡、切片、功率）
- **詳細說明**：[xapps/rc-xapp/README.md](xapps/rc-xapp/README.md)

---

## 部署流程

### Step 1: Clone 專案

```bash
git clone https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform
```

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
```

### Step 5: 驗證部署

```bash
# 檢查 Pod 狀態
kubectl get pods -n ricplt
kubectl get pods -n ricxapp

# 查看 xApp 日誌
kubectl logs -n ricxapp -l app=kpimon
kubectl logs -n ricxapp -l app=ran-control
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
