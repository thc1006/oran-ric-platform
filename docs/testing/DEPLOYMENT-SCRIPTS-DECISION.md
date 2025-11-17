# 部署腳本更新決策報告

**日期**: 2025-11-17
**作者**: 蔡秀吉 (thc1006)
**目的**: 確定最適當的 KUBECONFIG 標準化方案

---

## 執行摘要

經過深入分析，發現當前部署架構分為**兩層**：

### 第一層：輕量級部署（當前系統）
- **腳本**: `scripts/deployment/deploy-all.sh` ⭐
- **組件**: Prometheus + Grafana + xApps + E2 Simulator
- **用途**: 開發環境、測試環境、功能演示
- **狀態**: ✅ **已完成 KUBECONFIG 標準化 (PR #11)**

### 第二層：完整 RIC Platform（未部署）
- **腳本**: `scripts/deployment/deploy-ric-platform.sh`
- **組件**: AppMgr, E2Mgr, E2Term, SubMgr, A1 Mediator, Redis等
- **用途**: 生產環境、真實 E2 連接
- **狀態**: ⚠️ **未使用，但應該保留並更新**

---

## 腳本詳細分析

### 1. `deploy-all.sh` - 一鍵部署主腳本 ⭐

**部署流程**:
```
Step 1: check_prerequisites()
Step 2: configure_kubeconfig()      ← 已標準化 ✅
Step 3: create_namespaces()
Step 4: start_registry()
Step 5: deploy_prometheus()         ← 已標準化 ✅
Step 6: deploy_grafana()            ← 已標準化 ✅
Step 7: deploy_xapps()              ← 已標準化 ✅
Step 8: deploy_e2_simulator()       ← 已標準化 ✅
Step 9: import_dashboards()
Step 10: verify_deployment()
Step 11: show_access_info()
```

**部署的 xApps**:
- KPIMON
- Traffic Steering
- RAN Control
- QoE Predictor
- Federated Learning

**特點**:
- ✅ 智慧雙檢查 KUBECONFIG 機制
- ✅ 完整錯誤處理
- ✅ 支援多叢集環境
- ✅ 自動驗證部署狀態
- ✅ 提供 Grafana 存取資訊

**結論**: 🎯 **這就是當前的「一鍵到底」部署腳本**

---

### 2. `deploy-ml-xapps.sh` - ML xApps 獨立部署

**功能**:
- 獨立部署 QoE Predictor + Federated Learning
- 包含 Docker 映像建置
- 支援多種操作模式：deploy, build, cleanup, verify, logs

**使用場景**:
- 只需要 ML xApps
- 更新 ML xApps 映像
- 獨立測試 ML 功能

**當前問題**:
- ❌ 未載入 validation.sh
- ❌ 直接使用 kubectl（依賴隱式 KUBECONFIG）
- ❌ 多叢集環境可能失敗

**優先級**: 🔴 **高** - 確實有使用場景

---

### 3. `deploy-ric-platform.sh` - RIC Platform 核心部署

**功能**:
- 部署完整的 Near-RT RIC Platform
- 包含：AppMgr, E2Mgr, E2Term, SubMgr, A1 Mediator
- 部署 Redis（SDL 儲存）
- 配置 RMR 路由
- 應用網路策略

**組件清單**:
```yaml
- redis: 7-alpine (Shared Data Layer)
- appmgr: 0.5.4 (xApp Manager)
- e2mgr: 5.4.19 (E2 Connection Manager)
- e2term: 5.5.0 (E2 Termination)
- submgr: 0.9.0 (Subscription Manager)
- a1mediator: 2.6.0 (A1 Interface)
```

**當前狀態**:
- ❌ 未在 README.md 中提到
- ❌ 當前系統沒有運行這些組件
- ❌ 未經測試（可能需要調整配置）
- ⚠️ 但是程式碼看起來完整

**用途分析**:
- 🎯 **生產環境**: 真實 E2 節點連接
- 🎯 **完整測試**: A1 Policy, E2 Subscription
- 🎯 **RMR 測試**: xApp 間訊息路由
- 🎯 **未來擴展**: 完整 O-RAN 架構

**優先級**: 🟡 **中** - 未來可能需要，應該保留並標準化

---

### 4. `smoke-test.sh` - 冒煙測試腳本

**功能**:
- 快速驗證部署後系統健康
- 檢查 6 大類別：基礎工具、K8s、Namespaces、監控、xApps、E2 Simulator
- 總共 20+ 檢查項目

**當前問題**:
- ❌ 未載入 validation.sh
- ❌ 可能測試錯誤的叢集
- ❌ 多叢集環境結果誤導

**優先級**: 🟡 **中** - 測試腳本，應該標準化

---

## 決策：最適當解決方案

### ✅ 推薦方案：**全面標準化 (100%)**

**更新清單**:
1. ✅ `deploy-ml-xapps.sh` - 高優先級
2. ✅ `deploy-ric-platform.sh` - 中優先級（標記為 experimental）
3. ✅ `smoke-test.sh` - 中優先級

**理由**:
1. **完整性**: 達成 100% 標準化
2. **未來保障**: deploy-ric-platform.sh 未來可能需要
3. **一致性**: 所有腳本使用相同模式
4. **可維護性**: 單一標準，易於維護
5. **低風險**: 修改模式已在 PR #11 驗證

**不選擇移除 deploy-ric-platform.sh 的原因**:
- ❌ 不應該刪除完整的 RIC Platform 部署能力
- ✅ 應該保留並標記為 "Advanced/Experimental"
- ✅ README 中可以明確說明兩種部署模式的差異

---

## 實施計劃

### Phase 1: 更新 3 個腳本

#### 1.1 `deploy-ml-xapps.sh`

**修改內容**:
```bash
# Line 12 後添加
source "${PROJECT_ROOT}/scripts/lib/validation.sh"

# Line 50 check_prerequisites() 開頭添加
log_info "設定 KUBECONFIG..."
if ! setup_kubeconfig; then
    exit 1
fi
```

**移除**: 無

**預期結果**:
- 支援多叢集環境
- 清晰的 KUBECONFIG 錯誤訊息
- 與其他部署腳本一致

---

#### 1.2 `deploy-ric-platform.sh`

**修改內容**:
```bash
# Line 17 後添加
source "${PROJECT_ROOT}/scripts/lib/validation.sh"

# Line 23 check_prerequisites() 開頭添加
log_info "設定 KUBECONFIG..."
if ! setup_kubeconfig; then
    log_error "KUBECONFIG not configured. Please run setup-k3s.sh first."
    exit 1
fi
```

**添加標註**:
```bash
# Line 1-2 修改為
#!/bin/bash
# Deploy O-RAN Near-RT RIC Platform (J Release) - Complete Platform
# Status: EXPERIMENTAL - Not tested with current deployment
# Use deploy-all.sh for standard lightweight deployment
```

**預期結果**:
- 為未來生產部署做準備
- 清楚標明實驗性質
- KUBECONFIG 標準化

---

#### 1.3 `smoke-test.sh`

**修改內容**:
```bash
# Line 12 後添加
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/validation.sh"

# Line 62 基礎工具檢查後添加新區塊
echo -e "${YELLOW}[0/6] KUBECONFIG 檢查${NC}"
echo -n "檢查 KUBECONFIG 設定 ... "
if setup_kubeconfig &> /dev/null; then
    echo -e "${GREEN}✓${NC}"
    echo "  使用: $KUBECONFIG"
    ((PASSED_CHECKS++))
else
    echo -e "${RED}✗ (關鍵)${NC}"
    echo "  錯誤: 無法設定 KUBECONFIG"
    ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))
echo ""
```

**預期結果**:
- 確保測試正確的叢集
- 顯示使用的 KUBECONFIG
- 測試結果更可靠

---

### Phase 2: 測試驗證

#### 測試 1: deploy-ml-xapps.sh
```bash
# 語法檢查
bash -n scripts/deploy-ml-xapps.sh

# 場景測試
unset KUBECONFIG
bash scripts/deploy-ml-xapps.sh verify
```

#### 測試 2: smoke-test.sh
```bash
# 語法檢查
bash -n scripts/smoke-test.sh

# 實際執行
bash scripts/smoke-test.sh
```

#### 測試 3: deploy-ric-platform.sh
```bash
# 語法檢查（不實際執行）
bash -n scripts/deployment/deploy-ric-platform.sh

# 檢查 KUBECONFIG 邏輯
unset KUBECONFIG
bash -c 'source scripts/lib/validation.sh && setup_kubeconfig && echo "OK"'
```

---

### Phase 3: README.md 更新

#### 添加「部署模式」章節

**位置**: 在 "Quick Start" 之前

**內容**:
```markdown
## 部署模式選擇

本專案提供兩種部署模式：

### 🚀 模式 1: 輕量級部署（推薦）

**腳本**: `scripts/deployment/deploy-all.sh`

**組件**:
- Prometheus（監控系統）
- Grafana（儀表板）
- 5 個 xApps（KPIMON, Traffic Steering, RAN Control, QoE Predictor, Federated Learning）
- E2 Simulator（測試流量產生器）

**適用場景**:
- ✅ 開發環境
- ✅ 功能測試
- ✅ xApp 開發
- ✅ CI/CD 測試
- ✅ 教學與展示

**優點**:
- 快速部署（~15 分鐘）
- 資源需求低（8核/16GB 即可）
- 獨立運行，不依賴外部 E2 節點
- 完整監控與可視化

**執行方式**:
```bash
bash scripts/deployment/deploy-all.sh
```

---

### 🏭 模式 2: 完整 RIC Platform（實驗性）

**腳本**: `scripts/deployment/deploy-ric-platform.sh`

**組件**:
- 所有輕量級模式組件
- AppMgr（xApp 管理器）
- E2Mgr（E2 連接管理器）
- E2Term（E2 終端）
- SubMgr（訂閱管理器）
- A1 Mediator（A1 介面）
- Redis（共享資料層）

**適用場景**:
- 🏭 生產環境
- 🔗 真實 E2 節點連接
- 🧪 A1 Policy 測試
- 📡 RMR 訊息路由測試
- 🎯 完整 O-RAN 架構驗證

**資源需求**:
- CPU: 16+ 核心
- RAM: 32GB+
- 磁碟: 100GB+

**注意事項**:
⚠️ **實驗性功能** - 需要額外配置，未包含在標準部署流程中

**執行方式**:
```bash
bash scripts/deployment/deploy-ric-platform.sh
```
```

---

## 預期成果

### 完成後狀態

```
✅ 100% KUBECONFIG 標準化 (10/10 腳本)
✅ 兩種部署模式清楚定義
✅ README.md 明確說明部署選項
✅ 所有腳本一致的錯誤處理
✅ 完整的多叢集支援
```

### 文件完整性

```
✅ SCRIPTS-KUBECONFIG-ANALYSIS.md - 分析報告
✅ DEPLOYMENT-SCRIPTS-DECISION.md - 決策報告 (本文件)
✅ README.md - 用戶指南更新
✅ Phase 2 測試報告（待完成）
```

---

## 總結

### 決策

✅ **採用全面標準化方案**

**理由**:
1. ✅ 保留所有部署能力（輕量級 + 完整平台）
2. ✅ 達成 100% 標準化
3. ✅ 為未來擴展做準備
4. ✅ 清楚標記各腳本的用途和狀態
5. ✅ 工作量合理（~1 小時）

### 不採用的方案

❌ **移除 deploy-ric-platform.sh**
- 理由: 完整 RIC Platform 能力對未來可能重要

❌ **只更新部分腳本（70%）**
- 理由: 維護兩種模式，增加複雜度

---

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-17
**版本**: v2.0.1 Phase 2
