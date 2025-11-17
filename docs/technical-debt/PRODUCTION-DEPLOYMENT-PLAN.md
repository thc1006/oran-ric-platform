# 生產環境部署實施計劃

**制定日期**: 2025-11-17（周日）
**上線日期**: 2025-11-20（周三）
**剩餘時間**: 3 天
**作者**: 蔡秀吉 (thc1006)

---

## 執行原則

### 核心要求

1. **測試驅動開發 (TDD)**
   - 每次修復必須先寫測試
   - 測試通過才算完成
   - 不接受「看起來沒問題」的修復

2. **實際環境驗證**
   - 每次修改都要在本地 K8s 部署測試
   - 使用真實的 kubectl、docker、helm 命令
   - 記錄完整的測試日誌

3. **文檔完整性**
   - 修改前：記錄當前狀態和問題
   - 修改中：記錄每個步驟
   - 修改後：記錄測試結果和遇到的問題
   - 格式：問題 → 解決方案 → 測試 → 結果

4. **回滾準備**
   - 每個修改都要有回滾計劃
   - 測試失敗立即回滾
   - 記錄回滾步驟

---

## 時間表（3天衝刺）

### Day 1 - 周日（今天）

**目標**: 完成 PR #9 KUBECONFIG 標準化 + 實際測試

```
08:00-09:00  □ 檢查當前系統狀態
09:00-10:00  □ 修改 validation.sh
10:00-11:00  □ 修改 9 個腳本（第一批 3 個）
11:00-12:00  □ 實際部署測試（第一批）

12:00-13:00  午休

13:00-14:00  □ 修改剩餘 6 個腳本
14:00-15:00  □ 完整部署測試
15:00-16:00  □ 記錄文檔和遇到的問題
16:00-17:00  □ 修復發現的問題
17:00-18:00  □ 最終驗證和 PR 提交

目標: PR #9 完成並驗證通過
```

### Day 2 - 周一

**目標**: 完成 PR #A ShellCheck + PR #B Trap + 集成測試

```
08:00-09:00  □ PR #A: ShellCheck Git Hook
09:00-10:00  □ 測試 ShellCheck 自動檢查
10:00-11:00  □ PR #B: 修改 validation.sh trap 函數
11:00-12:00  □ PR #B: 修改 5 個關鍵腳本

12:00-13:00  午休

13:00-14:00  □ 測試 Trap 錯誤處理
14:00-15:00  □ 完整集成測試（所有修改一起）
15:00-17:00  □ 記錄文檔
17:00-18:00  □ 修復發現的問題

目標: 所有 PR 完成並通過集成測試
```

### Day 3 - 周二

**目標**: 完整系統驗證 + 上線準備

```
08:00-10:00  □ 完整系統部署測試（從零開始）
10:00-12:00  □ 壓力測試和穩定性驗證

12:00-13:00  午休

13:00-15:00  □ 文檔整理和檢查清單
15:00-17:00  □ 預演上線流程
17:00-18:00  □ 準備回滾方案

目標: 系統就緒，周三可以上線
```

### Day 4 - 周三（上線日）

**目標**: 生產環境部署

```
08:00-09:00  □ 最後檢查
09:00-12:00  □ 生產環境部署
12:00-14:00  □ 監控和驗證
14:00-18:00  □ 問題修復和穩定化

目標: 系統成功上線並穩定運行
```

---

## PR #9: KUBECONFIG 標準化（詳細步驟）

### Step 1: 檢查當前狀態（30分鐘）

**任務清單**:
```bash
□ 確認 K8s 集群運行正常
□ 記錄當前所有腳本的 KUBECONFIG 處理方式
□ 測試當前系統在不同 KUBECONFIG 配置下的行為
□ 建立基準測試結果
```

**執行命令**:
```bash
# 1. 檢查集群健康
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# 2. 記錄當前 KUBECONFIG 處理
grep -n "KUBECONFIG" scripts/deployment/*.sh scripts/*.sh > /tmp/kubeconfig-before.txt

# 3. 測試場景 1: 現有環境變數
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
bash scripts/deployment/deploy-prometheus.sh --dry-run 2>&1 | tee /tmp/test-scenario-1.log

# 4. 測試場景 2: 無環境變數
unset KUBECONFIG
bash scripts/deployment/deploy-prometheus.sh --dry-run 2>&1 | tee /tmp/test-scenario-2.log

# 5. 測試場景 3: 自定義路徑
export KUBECONFIG=/custom/path
bash scripts/deployment/deploy-prometheus.sh --dry-run 2>&1 | tee /tmp/test-scenario-3.log
```

**記錄格式** (`docs/testing/PR9-BASELINE-TEST.md`):
```markdown
# PR #9 基準測試

## 測試環境
- 日期: 2025-11-17
- K8s 版本: $(kubectl version --short)
- 節點數: $(kubectl get nodes --no-headers | wc -l)

## 當前 KUBECONFIG 處理方式

### 腳本列表
1. deploy-prometheus.sh: 硬編碼 /etc/rancher/k3s/k3s.yaml
2. ...

## 測試結果

### 場景 1: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
- 結果: [成功/失敗]
- 日誌: /tmp/test-scenario-1.log
- 問題: [如有]

### 場景 2: unset KUBECONFIG
- 結果: [成功/失敗]
- 問題: [如有]

### 場景 3: export KUBECONFIG=/custom/path
- 結果: [成功/失敗]
- 問題: [如有]
```

### Step 2: 修改 validation.sh（30分鐘）

**修改內容**:
```bash
cd /home/thc1006/oran-ric-platform

# 備份原始檔案
cp scripts/lib/validation.sh scripts/lib/validation.sh.backup

# 編輯 validation.sh
vi scripts/lib/validation.sh
```

**新增函數** (在 validation.sh 中):
```bash
# KUBECONFIG 標準化設定
# 優先級: 1. 現有環境變數 2. ~/.kube/config 3. k3s 預設路徑
setup_kubeconfig() {
    # 1. 如果已設定且檔案存在，直接使用
    if [ -n "$KUBECONFIG" ] && [ -f "$KUBECONFIG" ]; then
        log_info "使用現有 KUBECONFIG: $KUBECONFIG"
        return 0
    fi

    # 2. 檢查標準位置
    if [ -f "$HOME/.kube/config" ]; then
        export KUBECONFIG="$HOME/.kube/config"
        log_info "使用標準 KUBECONFIG: $KUBECONFIG"
        return 0
    fi

    # 3. k3s 預設位置（回退選項）
    if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
        export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
        log_warn "使用 k3s 預設 KUBECONFIG: $KUBECONFIG"
        return 0
    fi

    # 4. 無法找到有效配置
    log_error "無法找到有效的 KUBECONFIG"
    log_error "請設定環境變數或將配置複製到 ~/.kube/config"
    return 1
}
```

**測試 validation.sh**:
```bash
# 語法檢查
bash -n scripts/lib/validation.sh

# 功能測試
source scripts/lib/validation.sh

# 測試場景 1
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
setup_kubeconfig
echo "結果: $KUBECONFIG"

# 測試場景 2
unset KUBECONFIG
setup_kubeconfig
echo "結果: $KUBECONFIG"

# 測試場景 3（應該失敗）
unset KUBECONFIG
rm ~/.kube/config
sudo rm /etc/rancher/k3s/k3s.yaml
setup_kubeconfig
echo "預期失敗，返回碼: $?"
```

**記錄** (`docs/testing/PR9-VALIDATION-TEST.md`):
```markdown
# validation.sh 修改測試

## 修改內容
- 新增函數: setup_kubeconfig()
- 優先級: 環境變數 > ~/.kube/config > k3s

## 測試結果

### 功能測試
- 場景 1 (現有環境變數): [通過/失敗]
- 場景 2 (標準位置): [通過/失敗]
- 場景 3 (k3s 回退): [通過/失敗]
- 場景 4 (無配置): [正確失敗/錯誤]

### 發現的問題
1. [如有問題描述]
2. [解決方案]
```

### Step 3: 修改第一批 3 個腳本（30分鐘）

**第一批**（較簡單的腳本）:
1. `scripts/deployment/deploy-prometheus.sh`
2. `scripts/deployment/deploy-grafana.sh`
3. `scripts/deployment/deploy-e2-simulator.sh`

**修改模式**:
```bash
# 對每個腳本執行以下修改

# 1. 在腳本開頭添加（set -e 之後）
source "${SCRIPT_DIR}/../lib/validation.sh"
setup_kubeconfig || {
    log_error "KUBECONFIG 設定失敗"
    exit 1
}

# 2. 移除原有的硬編碼
# 刪除: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

**實際操作**:
```bash
# deploy-prometheus.sh
git checkout -b fix/kubeconfig-standardization
vi scripts/deployment/deploy-prometheus.sh

# 找到並修改
# 原本: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# 改為:
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/validation.sh"
setup_kubeconfig || exit 1
```

### Step 4: 實際部署測試（第一批）（60分鐘）

**完整部署測試流程**:

```bash
#!/bin/bash
# 測試腳本: test-pr9-batch1.sh

echo "=========================================="
echo "PR #9 第一批腳本部署測試"
echo "時間: $(date)"
echo "=========================================="

# 清理環境
echo "1. 清理測試環境..."
kubectl delete namespace test-pr9 --ignore-not-found=true

# 測試場景 1: 現有環境變數
echo ""
echo "2. 測試場景 1: 現有 KUBECONFIG 環境變數"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
bash scripts/deployment/deploy-prometheus.sh 2>&1 | tee /tmp/pr9-test1-prometheus.log

# 檢查部署狀態
kubectl get pods -n ricplt -l app=prometheus
if [ $? -eq 0 ]; then
    echo "✓ Prometheus 部署成功（場景 1）"
else
    echo "✗ Prometheus 部署失敗（場景 1）"
    exit 1
fi

# 清理
kubectl delete -f scripts/deployment/deploy-prometheus.sh || true

# 測試場景 2: 標準位置
echo ""
echo "3. 測試場景 2: 使用 ~/.kube/config"
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
unset KUBECONFIG
bash scripts/deployment/deploy-grafana.sh 2>&1 | tee /tmp/pr9-test2-grafana.log

kubectl get pods -n ricplt -l app=grafana
if [ $? -eq 0 ]; then
    echo "✓ Grafana 部署成功（場景 2）"
else
    echo "✗ Grafana 部署失敗（場景 2）"
    exit 1
fi

# 測試場景 3: E2 Simulator
echo ""
echo "4. 測試場景 3: E2 Simulator"
bash scripts/deployment/deploy-e2-simulator.sh 2>&1 | tee /tmp/pr9-test3-e2sim.log

kubectl get pods -n ricxapp -l app=e2-simulator
if [ $? -eq 0 ]; then
    echo "✓ E2 Simulator 部署成功（場景 3）"
else
    echo "✗ E2 Simulator 部署失敗（場景 3）"
    exit 1
fi

echo ""
echo "=========================================="
echo "第一批測試完成！"
echo "日誌位置: /tmp/pr9-test*.log"
echo "=========================================="
```

**執行測試**:
```bash
chmod +x test-pr9-batch1.sh
./test-pr9-batch1.sh 2>&1 | tee /tmp/pr9-batch1-full.log
```

**記錄測試結果** (`docs/testing/PR9-BATCH1-DEPLOYMENT-TEST.md`):
```markdown
# PR #9 第一批部署測試

## 測試時間
- 開始: $(date)
- 完成: $(date)

## 測試腳本
1. deploy-prometheus.sh
2. deploy-grafana.sh
3. deploy-e2-simulator.sh

## 測試場景

### 場景 1: 現有 KUBECONFIG 環境變數
- 配置: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
- deploy-prometheus.sh: [成功/失敗]
- 日誌: /tmp/pr9-test1-prometheus.log
- Pod 狀態: $(kubectl get pods -n ricplt -l app=prometheus)
- 遇到的問題: [如有]
- 解決方案: [如有]

### 場景 2: 標準 ~/.kube/config
- 配置: unset KUBECONFIG，使用 ~/.kube/config
- deploy-grafana.sh: [成功/失敗]
- 日誌: /tmp/pr9-test2-grafana.log
- Pod 狀態: $(kubectl get pods -n ricplt -l app=grafana)
- 遇到的問題: [如有]
- 解決方案: [如有]

### 場景 3: E2 Simulator
- deploy-e2-simulator.sh: [成功/失敗]
- 日誌: /tmp/pr9-test3-e2sim.log
- Pod 狀態: $(kubectl get pods -n ricxapp -l app=e2-simulator)

## 總結
- 成功: X/3
- 失敗: Y/3
- 需要修復的問題: [列表]
```

### Step 5: 修改剩餘 6 個腳本（60分鐘）

**第二批**（較複雜的腳本）:
1. `scripts/verify-all-xapps.sh`
2. `scripts/redeploy-xapps-with-metrics.sh`
3. `scripts/deploy-ml-xapps.sh`
4. `scripts/deployment/setup-k3s.sh` ⚠️ 特殊處理
5. `scripts/deployment/deploy-all.sh` ⚠️ 特殊處理
6. `scripts/deployment/deploy-ric-platform.sh`

**特殊處理 - setup-k3s.sh**:
```bash
# setup-k3s.sh 需要特殊邏輯
# 它是初始化腳本，需要「創建」KUBECONFIG 而非「使用」

# 在 setup-k3s.sh 中保留複製邏輯
mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $USER:$USER $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config

# 然後在最後添加
log_info "KUBECONFIG 已設定為: $KUBECONFIG"
log_info "請執行: source ~/.bashrc 或重新登入"
```

### Step 6: 完整部署測試（90分鐘）

**完整系統測試腳本**:
```bash
#!/bin/bash
# 完整測試: test-pr9-full-system.sh

echo "=========================================="
echo "PR #9 完整系統部署測試"
echo "=========================================="

# 0. 完全清理環境
echo "0. 清理環境..."
kubectl delete namespace ricplt ricxapp ricobs --ignore-not-found=true
sleep 10

# 1. 從零開始部署
echo ""
echo "1. 執行 setup-k3s.sh..."
sudo bash scripts/deployment/setup-k3s.sh 2>&1 | tee /tmp/pr9-full-setup-k3s.log

# 2. 部署 RIC Platform
echo ""
echo "2. 部署 RIC Platform..."
bash scripts/deployment/deploy-ric-platform.sh 2>&1 | tee /tmp/pr9-full-ric-platform.log

# 3. 部署監控
echo ""
echo "3. 部署 Prometheus..."
bash scripts/deployment/deploy-prometheus.sh 2>&1 | tee /tmp/pr9-full-prometheus.log

echo ""
echo "4. 部署 Grafana..."
bash scripts/deployment/deploy-grafana.sh 2>&1 | tee /tmp/pr9-full-grafana.log

# 4. 部署 xApps
echo ""
echo "5. 部署 ML xApps..."
bash scripts/deploy-ml-xapps.sh deploy 2>&1 | tee /tmp/pr9-full-ml-xapps.log

# 5. 驗證所有組件
echo ""
echo "6. 驗證所有 xApps..."
bash scripts/verify-all-xapps.sh 2>&1 | tee /tmp/pr9-full-verify.log

# 6. 檢查所有 Pod 狀態
echo ""
echo "=========================================="
echo "最終狀態檢查"
echo "=========================================="

echo ""
echo "RIC Platform Pods:"
kubectl get pods -n ricplt

echo ""
echo "xApps Pods:"
kubectl get pods -n ricxapp

echo ""
echo "所有服務:"
kubectl get svc -A

# 7. 健康檢查
echo ""
echo "=========================================="
echo "健康檢查"
echo "=========================================="

FAILED=0

# Prometheus
if kubectl get pod -n ricplt -l app=prometheus | grep -q Running; then
    echo "✓ Prometheus: Running"
else
    echo "✗ Prometheus: Failed"
    FAILED=$((FAILED + 1))
fi

# Grafana
if kubectl get pod -n ricplt -l app=grafana | grep -q Running; then
    echo "✓ Grafana: Running"
else
    echo "✗ Grafana: Failed"
    FAILED=$((FAILED + 1))
fi

# xApps
for xapp in kpimon traffic-steering ran-control qoe-predictor federated-learning; do
    if kubectl get pod -n ricxapp -l app=$xapp 2>/dev/null | grep -q Running; then
        echo "✓ $xapp: Running"
    else
        echo "✗ $xapp: Failed"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo "✓ 所有組件部署成功！"
    echo "=========================================="
    exit 0
else
    echo "✗ 有 $FAILED 個組件失敗"
    echo "請檢查日誌: /tmp/pr9-full-*.log"
    echo "=========================================="
    exit 1
fi
```

### Step 7: 文檔記錄（60分鐘）

**創建完整的部署測試報告** (`docs/testing/PR9-FINAL-TEST-REPORT.md`):

```markdown
# PR #9: KUBECONFIG 標準化 - 最終測試報告

## 執行摘要

- **測試日期**: 2025-11-17
- **測試者**: 蔡秀吉 (thc1006)
- **修改腳本數**: 9 個
- **測試場景數**: 3 個
- **測試總時長**: X 小時

## 修改清單

### 1. validation.sh
- **修改內容**: 新增 setup_kubeconfig() 函數
- **程式碼變更**: +30 行
- **測試狀態**: ✓ 通過

### 2-10. 各個腳本
[詳細列表...]

## 測試結果

### 完整部署測試

#### 環境配置
```
K8s 版本: $(kubectl version --short)
節點: $(kubectl get nodes)
命名空間: ricplt, ricxapp, ricobs
```

#### 部署步驟

1. **setup-k3s.sh**
   - 執行時間: X 分鐘
   - 結果: [成功/失敗]
   - 日誌: /tmp/pr9-full-setup-k3s.log
   - KUBECONFIG: $HOME/.kube/config

2. **deploy-ric-platform.sh**
   - 執行時間: X 分鐘
   - 結果: [成功/失敗]
   - 日誌: /tmp/pr9-full-ric-platform.log
   - Pod 狀態: $(kubectl get pods -n ricplt)

[繼續...]

### 問題和解決方案

#### 問題 1: [描述]
- **發現時間**: XX:XX
- **現象**: [詳細描述]
- **根本原因**: [分析]
- **解決方案**: [修復步驟]
- **驗證**: [如何確認修復]

#### 問題 2: [如有]
...

### 最終狀態

```
$ kubectl get pods -A
[實際輸出]

$ kubectl get svc -A
[實際輸出]

$ bash scripts/verify-all-xapps.sh
[實際輸出]
```

## 性能測試

### 部署時間對比
- **修改前**: [如有記錄]
- **修改後**: X 分鐘
- **變化**: [改善/惡化]

### 穩定性測試
- **運行時長**: 2 小時
- **Pod 重啟次數**: 0
- **內存使用**: [數據]
- **CPU 使用**: [數據]

## 回歸測試

### 場景 1: 預設配置（最常見）
```bash
unset KUBECONFIG
# 預期: 使用 ~/.kube/config
結果: [通過/失敗]
```

### 場景 2: 多集群切換
```bash
export KUBECONFIG=/path/to/cluster2
# 預期: 使用指定配置
結果: [通過/失敗]
```

### 場景 3: k3s 環境
```bash
rm ~/.kube/config
# 預期: 回退到 k3s
結果: [通過/失敗]
```

## 結論

### 達成目標
- ✓ 所有 9 個腳本已修改
- ✓ 完整系統部署測試通過
- ✓ 多場景測試通過
- ✓ 無回歸問題

### 風險評估
- **部署風險**: 低
- **回滾難度**: 低（有備份）
- **生產就緒**: 是

### 後續建議
1. 監控生產環境 KUBECONFIG 使用情況
2. 收集用戶反饋
3. [其他建議]

## 附錄

### A. 測試日誌位置
- /tmp/pr9-full-setup-k3s.log
- /tmp/pr9-full-ric-platform.log
- ...

### B. 備份文件
- scripts/lib/validation.sh.backup
- [其他備份]

### C. 回滾步驟
```bash
# 如需回滾
git revert <commit-hash>
cp scripts/lib/validation.sh.backup scripts/lib/validation.sh
```
```

---

## PR #A 和 PR #B 的類似流程

（簡化版，參考 PR #9 的詳細流程）

### PR #A: ShellCheck Git Hook

**Step 1**: 安裝 ShellCheck
**Step 2**: 創建 pre-commit hook
**Step 3**: 測試自動檢查
**Step 4**: 故意引入錯誤測試
**Step 5**: 記錄文檔

### PR #B: Trap 錯誤處理

**Step 1**: 修改 validation.sh
**Step 2**: 修改 5 個腳本
**Step 3**: 測試錯誤捕獲
**Step 4**: 測試中斷處理
**Step 5**: 記錄文檔

---

## 最終集成測試（Day 2 晚上）

### 完整從零部署

```bash
#!/bin/bash
# final-integration-test.sh

echo "=========================================="
echo "最終集成測試 - 完整從零部署"
echo "時間: $(date)"
echo "=========================================="

# 1. 完全清理
echo "1. 完全清理環境..."
kubectl delete namespace ricplt ricxapp ricobs --ignore-not-found=true
sleep 30

# 2. 從零開始
echo "2. 執行 setup-k3s.sh..."
sudo bash scripts/deployment/setup-k3s.sh

# 3. 部署所有組件
echo "3. 執行 deploy-all.sh..."
sudo bash scripts/deployment/deploy-all.sh

# 4. 等待所有 Pod 就緒
echo "4. 等待所有 Pod 就緒..."
kubectl wait --for=condition=ready pod --all -n ricplt --timeout=600s
kubectl wait --for=condition=ready pod --all -n ricxapp --timeout=600s

# 5. 驗證
echo "5. 執行完整驗證..."
bash scripts/verify-all-xapps.sh

# 6. 壓力測試（運行 4 小時）
echo "6. 開始 4 小時穩定性測試..."
for i in {1..240}; do
    echo "[$i/240] $(date) - 檢查系統狀態..."

    # 檢查所有 Pod
    FAILED=$(kubectl get pods -A | grep -v Running | grep -v Completed | wc -l)

    if [ $FAILED -gt 1 ]; then  # 1 是標題行
        echo "⚠️ 發現失敗的 Pod:"
        kubectl get pods -A | grep -v Running | grep -v Completed
    fi

    # 檢查資源使用
    kubectl top nodes
    kubectl top pods -n ricplt
    kubectl top pods -n ricxapp

    sleep 60  # 每分鐘檢查一次
done

echo "=========================================="
echo "4 小時穩定性測試完成"
echo "=========================================="
```

---

## 文檔清單

### 必須產出的文檔

1. **`PR9-BASELINE-TEST.md`**
   - 修改前的基準測試

2. **`PR9-VALIDATION-TEST.md`**
   - validation.sh 功能測試

3. **`PR9-BATCH1-DEPLOYMENT-TEST.md`**
   - 第一批腳本部署測試

4. **`PR9-FINAL-TEST-REPORT.md`**
   - 完整測試報告

5. **`PR-A-SHELLCHECK-TEST.md`**
   - ShellCheck 測試報告

6. **`PR-B-TRAP-TEST.md`**
   - Trap 錯誤處理測試

7. **`FINAL-INTEGRATION-TEST-REPORT.md`**
   - 最終集成測試報告（4 小時穩定性）

8. **`PRODUCTION-DEPLOYMENT-CHECKLIST.md`**
   - 周三上線檢查清單

---

## 上線檢查清單（周三早上）

```markdown
# 生產環境部署檢查清單

## 部署前檢查

### 系統準備
- [ ] 生產環境 K8s 集群健康
- [ ] 所有節點正常
- [ ] 足夠的資源（CPU、內存、磁碟）
- [ ] 網路連接正常

### 程式碼準備
- [ ] 所有 PR 已合併到 main
- [ ] Git tag 已創建 (v1.0.0-production)
- [ ] 測試報告已審閱
- [ ] 回滾計劃已準備

### 備份
- [ ] 當前配置已備份
- [ ] 資料庫已備份（如有）
- [ ] 持久化數據已備份

### 文檔
- [ ] 部署步驟文檔完整
- [ ] 故障排除指南準備好
- [ ] 聯絡人列表更新

## 部署步驟

### Phase 1: 基礎設施 (30分鐘)
- [ ] Step 1: setup-k3s.sh
  - 執行時間: ___
  - 結果: 成功/失敗
  - 問題: ___

- [ ] Step 2: 驗證 K8s 集群
  - kubectl get nodes: ___
  - kubectl get pods -A: ___

### Phase 2: RIC Platform (60分鐘)
- [ ] Step 3: deploy-ric-platform.sh
  - 執行時間: ___
  - 結果: 成功/失敗
  - Pod 狀態: ___

### Phase 3: 監控系統 (30分鐘)
- [ ] Step 4: deploy-prometheus.sh
- [ ] Step 5: deploy-grafana.sh

### Phase 4: xApps (60分鐘)
- [ ] Step 6: deploy-ml-xapps.sh

### Phase 5: 驗證 (30分鐘)
- [ ] Step 7: verify-all-xapps.sh
- [ ] Step 8: 手動測試

## 部署後驗證

### 健康檢查
- [ ] 所有 Pod Running
- [ ] 所有 Service 正常
- [ ] Prometheus 收集 metrics
- [ ] Grafana dashboard 顯示數據

### 功能測試
- [ ] E2 連接正常
- [ ] RAN Control 正常
- [ ] KPI 收集正常
- [ ] Traffic Steering 正常

### 性能測試
- [ ] CPU 使用 < 80%
- [ ] 內存使用 < 80%
- [ ] 網路延遲 < 10ms
- [ ] Pod 重啟次數 = 0

## 監控（部署後 4 小時）

### 每 30 分鐘檢查
- [ ] 10:00 - Pod 狀態: ___
- [ ] 10:30 - 資源使用: ___
- [ ] 11:00 - 日誌檢查: ___
- [ ] 11:30 - 性能指標: ___
- [ ] 12:00 - 功能驗證: ___
- [ ] 12:30 - 穩定性確認: ___
- [ ] 13:00 - 最終確認: ___

## 問題處理

### 如遇到問題
1. 記錄詳細錯誤訊息
2. 檢查日誌: kubectl logs
3. 檢查事件: kubectl describe
4. 參考故障排除指南
5. 如需回滾，執行回滾計劃

## 簽核

- [ ] 技術負責人: ___________  日期: _____
- [ ] 測試負責人: ___________  日期: _____
- [ ] 項目經理: _____________  日期: _____
```

---

## 成功標準

### PR #9 成功標準
- ✅ 9 個腳本全部修改完成
- ✅ 3 個測試場景全部通過
- ✅ 完整系統部署成功
- ✅ 無回歸問題
- ✅ 文檔完整

### PR #A 成功標準
- ✅ pre-commit hook 正常工作
- ✅ 自動檢查語法錯誤
- ✅ 測試通過

### PR #B 成功標準
- ✅ 5 個腳本添加 trap
- ✅ 錯誤捕獲正常
- ✅ 中斷處理正確
- ✅ 測試通過

### 周三上線成功標準
- ✅ 所有組件部署成功
- ✅ 系統運行 4 小時無故障
- ✅ 性能指標正常
- ✅ 功能驗證通過

---

## 風險與應對

### 風險 1: 測試中發現嚴重問題
- **機率**: 中
- **影響**: 高
- **應對**: 立即停止，修復問題，重新測試
- **回滾**: 使用備份文件恢復

### 風險 2: 部署時間超過預期
- **機率**: 中
- **影響**: 中
- **應對**: 優先完成 PR #9，其他可延後
- **調整**: 周三只部署核心功能

### 風險 3: 生產環境問題
- **機率**: 低
- **影響**: 高
- **應對**: 立即執行回滾計劃
- **準備**: 回滾腳本預先測試

---

## 總結

這個計劃強調：

1. **測試驅動**: 每次修改都要實際部署測試
2. **文檔完整**: 記錄每個步驟和問題
3. **風險控制**: 有備份、有回滾、有驗證
4. **時間明確**: 3 天衝刺，周三上線

**下一步**: 開始執行 PR #9 的 Step 1 - 檢查當前系統狀態
