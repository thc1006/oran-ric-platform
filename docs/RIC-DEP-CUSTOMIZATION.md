# RIC Platform Deployment (ric-dep) 客製化說明

作者：蔡秀吉（thc1006）
最後更新：2025-11-14

---

## 概述

本專案的 `ric-dep/` 目錄來自 **O-RAN Software Community** 的官方部署配置，並針對 **J Release** 進行了客製化和驗證。

### 來源資訊

- **上游 Repository**: https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep
- **基礎版本**: J Release (commit `505e5efb5f40706adccdfdc7a5289456cd01fe8a`)
- **分支**: `j-release`
- **納入時間**: 2025-11-14

---

## 為什麼完整納入而非使用 Git Submodule？

我們選擇將 ric-dep 完整納入專案（vendoring），而非使用 Git Submodule，原因如下：

### 1. 確保部署可重現性

```bash
# 協作者只需一個指令
git clone https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform

# 所有配置已就緒，無需額外步驟
helm install r4-rtmgr ric-dep/helm/infrastructure/rtmgr -n ricplt
```

**優勢**：
- ✅ 不依賴外部服務（gerrit.o-ran-sc.org）的可用性
- ✅ 10 年後依然可以完整重現構建
- ✅ 符合業界最佳實踐（Kubernetes、Docker 都採用 vendoring）

### 2. 包含關鍵客製化

本專案對 ric-dep 進行了**必要的修改**（詳見下節），這些修改是部署成功的關鍵。如果使用 Submodule，協作者會得到原始（錯誤）的配置。

### 3. 固定版本策略

專案定位為 **O-RAN J Release 生產級部署**，不需要持續追蹤上游更新。完整納入提供了：
- 明確的版本固定
- 穩定的依賴關係
- 可預測的行為

---

## 客製化內容清單

### 1. RTMgr 版本修正（關鍵修改）

**檔案**: `ric-dep/helm/rtmgr/values.yaml:21`

**修改內容**:
```yaml
# 原始版本（upstream）
rtmgr:
  image:
    name: ric-plt-rtmgr
    tag: 0.3.8  ❌ 錯誤版本，會導致 ImagePullBackOff

# 修正版本（本專案）
rtmgr:
  image:
    name: ric-plt-rtmgr
    tag: 0.9.6  ✅ J Release 正確版本
```

**原因**:
- O-RAN SC upstream 的 `j-release` 分支中 RTMgr tag 標註錯誤
- 根據 [O-RAN SC Release J 文檔](https://docs.o-ran-sc.org/)，正確版本應為 `0.9.6`
- 使用 `0.3.8` 會導致鏡像拉取失敗（nexus3.o-ran-sc.org 上不存在該版本）

**影響範圍**: RTMgr (Routing Manager) 部署

**驗證記錄**:
- `docs/deployment-guide-complete.md` 第 152-183 行
- `docs/QUICK-START.md` 第 98-105 行

---

### 2. Helm Chart 依賴打包

**目錄**: `ric-dep/helm/rtmgr/charts/ric-common/`

**背景**:
O-RAN SC 的 Helm charts 使用 `requirements.yaml` 宣告依賴，但上游並未預先打包這些依賴。這會導致部署 E2Term、E2Mgr 等組件時出現 "dependency not found" 錯誤。

**解決方案**:
我們手動打包了 `ric-common` Helm chart 並放置於各組件的 `charts/` 目錄：

```bash
# 打包流程（已完成，記錄於此供參考）
cd ric-dep/ric-common/Common-Template/helm/ric-common
helm package . -d /tmp/

# 複製到需要的位置
mkdir -p ric-dep/helm/rtmgr/charts
cp /tmp/ric-common-3.3.2.tgz ric-dep/helm/rtmgr/charts/
```

**包含的依賴**:
- `ric-dep/helm/rtmgr/charts/ric-common/` (已解壓縮)

**影響範圍**:
- RTMgr
- E2Term
- E2Mgr

**驗證記錄**:
- `docs/deployment-guides/01-ric-platform-deployment.md` 第 899-930 行

---

### 3. 其他配置

目前沒有其他修改。所有其他 Helm charts 和配置文件均使用 O-RAN SC upstream 的原始版本。

---

## 版本追蹤

### 當前版本資訊

| 組件 | Upstream 版本 | 本專案版本 | 修改狀態 |
|------|-------------|-----------|---------|
| RTMgr | 0.3.8 (錯誤) | 0.9.6 (修正) | ✅ 已修改 |
| E2Term | 5.5.5 | 5.5.5 | 未修改 |
| E2Mgr | 5.5.7 | 5.5.7 | 未修改 |
| DBaaS (Redis) | 4.1.1 | 4.1.1 | 未修改 |
| A1 Mediator | 2.5.0 | 2.5.0 | 未修改 |
| InfluxDB | 2.0.0 | 2.0.0 | 未修改 |

### Git 歷史參考

如果需要查看 ric-dep 的 Git 歷史：

```bash
# ric-dep/.git/ 目錄已保留（僅供參考，不會推送到 GitHub）
cd ric-dep
git log --oneline
git remote -v  # 查看 upstream URL
```

---

## 未來升級指南

### 升級到 K Release（或更新版本）

如果未來需要升級 RIC Platform 到更新的 release：

#### 步驟 1: 獲取上游更新

```bash
# 在專案根目錄
cd ric-dep

# 添加 upstream remote（如果尚未添加）
git remote add upstream https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep

# Fetch 新版本
git fetch upstream k-release  # 或其他 release 分支
```

#### 步驟 2: 審查變更

```bash
# 查看差異
git diff HEAD..upstream/k-release

# 特別注意：
# - RTMgr 版本是否有更新
# - Helm chart 結構是否有變化
# - 依賴版本是否有更新
```

#### 步驟 3: 選擇性合併

```bash
# 創建升級分支
git checkout -b upgrade-k-release

# 合併（可能有衝突）
git merge upstream/k-release --no-commit

# 手動解決衝突，確保保留：
# - RTMgr 的正確版本號
# - ric-common 依賴打包
# - 其他客製化內容
```

#### 步驟 4: 測試驗證

```bash
# 在測試環境部署新版本
# 執行完整的部署測試
# 驗證所有組件正常運作
```

#### 步驟 5: 更新文檔

```bash
# 更新本文檔的版本資訊
# 更新 deployment guides 中的版本號
# 記錄新發現的問題和解決方案
```

---

## 對比：Submodule vs Vendoring

### 如果使用 Git Submodule 會發生什麼？

```bash
# 協作者 clone
git clone --recurse-submodules https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform/ric-dep

# 檢查 RTMgr 版本
cat helm/rtmgr/values.yaml | grep tag
    tag: 0.3.8  ❌ 錯誤！

# 嘗試部署
helm install r4-rtmgr helm/infrastructure/rtmgr -n ricplt
kubectl get pods -n ricplt
# ricplt-rtmgr-xxx  0/1  ImagePullBackOff  ❌

# 協作者困惑：
# "為什麼文檔說是 0.9.6，實際是 0.3.8？"
# "我需要手動修改 submodule 嗎？"
# "如何提交我的修改？"
```

### 使用 Vendoring 的體驗

```bash
# 協作者 clone
git clone https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform/ric-dep

# 檢查 RTMgr 版本
cat helm/rtmgr/values.yaml | grep tag
    tag: 0.9.6  ✅ 正確！

# 部署
helm install r4-rtmgr helm/infrastructure/rtmgr -n ricplt
kubectl get pods -n ricplt
# ricplt-rtmgr-xxx  1/1  Running  ✅

# 成功！無需額外步驟
```

---

## 技術細節

### 目錄結構

```
ric-dep/
├── bin/                    # 工具腳本
├── ci/                     # CI 配置
├── depRicKubernetesOperator/  # Kubernetes Operator
├── docs/                   # 上游文檔
├── helm/                   # Helm charts（主要使用）
│   ├── dbaas/              # Redis
│   ├── e2term/             # E2 Termination
│   ├── e2mgr/              # E2 Manager
│   ├── a1mediator/         # A1 Mediator
│   ├── rtmgr/              # Routing Manager ⭐ 已客製化
│   │   ├── charts/         # ⭐ 手動添加的依賴
│   │   │   └── ric-common/
│   │   ├── templates/
│   │   └── values.yaml     # ⭐ RTMgr 版本已修正為 0.9.6
│   └── influxdb/           # InfluxDB
├── new-installer/          # 新安裝器（實驗性）
├── ric-common/             # 共用 Helm templates
│   └── Common-Template/
│       └── helm/
│           └── ric-common/ # ric-common chart 源碼
├── INFO.yaml
├── LICENSE
└── RECIPE_EXAMPLE
```

### 大小與儲存

```bash
$ du -sh ric-dep/
6.9M    ric-dep/

# GitHub repository 大小影響：
# - 總增加：6.9MB
# - 佔用率：< 1% (GitHub 免費方案限制 1GB)
# - 結論：可忽略不計
```

---

## 相關文檔

- [完整部署指南](deployment-guide-complete.md) - RTMgr 版本問題的詳細記錄
- [快速開始指南](QUICK-START.md) - RTMgr 部署步驟
- [01-RIC Platform 部署](deployment-guides/01-ric-platform-deployment.md) - Helm chart 依賴打包流程

---

## 常見問題

### Q1: 為什麼不直接使用 O-RAN SC 的 Helm repository？

**A**: O-RAN SC 提供的 Helm repository (https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep) 存在以下問題：
1. RTMgr 版本標註錯誤（0.3.8 vs 0.9.6）
2. Helm chart 依賴未預先打包
3. 需要手動調整才能成功部署

為了提供「開箱即用」的體驗，我們選擇完整納入並修正這些問題。

### Q2: 如果上游修復了 RTMgr 版本問題，我們需要更新嗎？

**A**: 不一定。本專案定位為 **J Release 穩定版本**，除非有重大安全漏洞或功能需求，否則建議保持當前版本以確保穩定性。

### Q3: 可以貢獻修正回 O-RAN SC upstream 嗎？

**A**: 可以！如果你發現 upstream 的問題並有修正方案，歡迎：
1. 在 O-RAN SC Gerrit 上提交 patch
2. 參與 O-RAN SC 社群討論
3. 幫助改進上游品質

但對於本專案，我們依然建議使用已驗證的固定版本。

### Q4: ric-dep/.git/ 目錄為什麼還存在？

**A**: 我們保留了 `.git/` 目錄作為歷史參考，但它不會被推送到 GitHub（已加入 .gitignore）。這允許本地開發者：
- 查看上游 Git 歷史
- 使用 `git diff` 比對上游變更
- 理解客製化的來龍去脈

---

**維護者**: 蔡秀吉（thc1006）
**問題回報**: https://github.com/thc1006/oran-ric-platform/issues
