# Shell 腳本質量改進行動計劃

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-17
**狀態**: 待執行

---

## 執行摘要

基於 [BATS-TESTING-EVALUATION.md](./BATS-TESTING-EVALUATION.md) 的評估結果，**不建議引入 BATS 測試框架**。

取而代之，我們採用**輕量級、高投資回報率**的改進策略：

1. **ShellCheck 靜態分析** - 投資 1-2 小時，防止 20% 的語法錯誤
2. **Smoke Test 腳本** - 投資 4-6 小時，驗證 60% 的集成問題
3. **驗證函數庫** - 投資 2-3 小時，強化腳本健壯性
4. **持續文檔驅動測試** - 零額外投資，已發現 3 個關鍵 bug

**總投資**: 7-11 小時（約 1 個工作日）
**預期收益**: 防止 80% 的實際問題（vs BATS 的 20%）

---

## 立即行動項目（本週內完成）

### 優先級 P0 - 立即（今天）

#### ✓ 已完成

- [x] 評估 BATS 必要性
- [x] 創建評估報告
- [x] 創建 Smoke Test 腳本
- [x] 創建驗證函數庫
- [x] 創建 ShellCheck 配置
- [x] 創建 Git Hook 範例
- [x] 創建質量保證指南

#### ⏳ 待執行（預計 1-2 小時）

```bash
# 任務 1: 安裝 ShellCheck
sudo apt install shellcheck

# 任務 2: 啟用 Git Hook
cp scripts/hooks/pre-commit.sample .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# 任務 3: 測試 Smoke Test
sudo bash scripts/smoke-test.sh

# 任務 4: 驗證關鍵腳本語法
shellcheck scripts/deployment/setup-k3s.sh
shellcheck scripts/deployment/deploy-all.sh
shellcheck scripts/deployment/deploy-ric-platform.sh
```

---

## 短期改進（本週內）

### 任務 1: 為關鍵腳本添加嚴格模式（2-3 小時）

**目標**: 為 3 個關鍵部署腳本添加 `set -euo pipefail`

**檔案**:
- `scripts/deployment/setup-k3s.sh` ✓ (已有 `set -e`)
- `scripts/deployment/deploy-all.sh` ✓ (已有 `set -e`)
- `scripts/deployment/deploy-ric-platform.sh` ✓ (已有 `set -e`)

**檢查清單**:
```bash
# 對每個腳本執行
cd /home/thc1006/oran-ric-platform

# 1. 檢查當前狀態
grep "set -" scripts/deployment/setup-k3s.sh

# 2. 如果只有 set -e，升級為:
# set -euo pipefail

# 3. 測試是否有未定義變量
bash -n scripts/deployment/setup-k3s.sh

# 4. 運行 shellcheck
shellcheck scripts/deployment/setup-k3s.sh

# 5. 修復警告
# ...

# 6. 功能測試（在測試環境）
# sudo bash scripts/deployment/setup-k3s.sh
```

**預期結果**:
- 所有關鍵腳本使用 `set -euo pipefail`
- 無 shellcheck 警告
- 功能測試通過

---

### 任務 2: 集成 Smoke Test 到部署流程（1 小時）

**目標**: 在 `deploy-all.sh` 最後自動執行 smoke test

**修改位置**: `/home/thc1006/oran-ric-platform/scripts/deployment/deploy-all.sh`

**修改內容**:
```bash
# 在 main() 函數最後，show_access_info 之前添加

    # 執行 Smoke Test
    step "10" "執行系統健康檢查"

    info "執行 Smoke Test..."
    if bash "$PROJECT_ROOT/scripts/smoke-test.sh"; then
        success "系統健康檢查通過"
    else
        warn "部分檢查失敗，但部署已完成"
        warn "請檢查日誌: $LOG_FILE"
    fi
```

**測試**:
```bash
# 完整部署測試（在測試環境）
sudo bash scripts/deployment/deploy-all.sh

# 應該看到新的步驟 "執行系統健康檢查"
```

---

### 任務 3: 為常用腳本添加前置檢查（2 小時）

**目標**: 使用驗證函數庫強化腳本

**檔案**:
1. `scripts/redeploy-xapps-with-metrics.sh`
2. `scripts/deploy-ml-xapps.sh`

**修改範例**:
```bash
# 在腳本開頭添加
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 載入驗證函數
source "$PROJECT_ROOT/scripts/lib/validation.sh"

# 在 main() 開頭添加
main() {
    log_info "檢查前置條件..."

    # 使用驗證函數
    if ! check_deployment_prerequisites; then
        log_error "前置條件檢查失敗，請解決上述問題後重試"
        exit 1
    fi

    # 驗證關鍵目錄
    validate_directory_exists "$PROJECT_ROOT/xapps" "xApps 目錄" || exit 1

    # 原有邏輯
    # ...
}
```

**測試**:
```bash
# 測試前置檢查（故意破壞環境）
unset KUBECONFIG
bash scripts/redeploy-xapps-with-metrics.sh
# 應該報錯並退出

# 恢復環境後測試
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
bash scripts/redeploy-xapps-with-metrics.sh
# 應該正常執行
```

---

## 中期改進（2 週內）

### 任務 4: ShellCheck 零警告（4-6 小時）

**目標**: 所有關鍵腳本通過 shellcheck 且無警告

**檔案清單**:
- [x] `scripts/deployment/setup-k3s.sh`
- [ ] `scripts/deployment/deploy-all.sh`
- [ ] `scripts/deployment/deploy-ric-platform.sh`
- [ ] `scripts/redeploy-xapps-with-metrics.sh`
- [ ] `scripts/deploy-ml-xapps.sh`

**執行步驟**:
```bash
# 1. 檢查當前狀態
shellcheck scripts/deployment/deploy-all.sh > shellcheck-report.txt

# 2. 分類警告
# - SC2086: 未引用變量 → 添加引號
# - SC2181: 檢查 $? → 改用 if mycmd
# - SC2154: 未賦值變量 → 添加賦值或使用 ${var:-default}

# 3. 逐一修復

# 4. 再次檢查
shellcheck scripts/deployment/deploy-all.sh

# 5. 功能測試
```

**允許的例外**:
- SC2086: kubectl 命令中有意需要 word splitting 的變量
- SC1090: 動態 source 的文件

---

### 任務 5: 文檔更新（2-3 小時）

**目標**: 更新所有部署文檔，說明新的質量保證流程

**檔案**:
1. `README.md` - 添加 "開發者指南" 章節
2. `docs/deployment/QUICKSTART.md` - 添加 smoke test 步驟
3. `docs/deployment/README.md` - 鏈接到質量保證指南

**新增章節範例** (README.md):
```markdown
## 開發者指南

### 修改部署腳本

1. **安裝 ShellCheck**:
   ```bash
   sudo apt install shellcheck
   ```

2. **使用腳本模板**: 參考 [Shell 腳本質量保證指南](docs/testing/SHELL-SCRIPT-QUALITY-GUIDE.md)

3. **本地檢查**:
   ```bash
   shellcheck scripts/deployment/my-script.sh
   ```

4. **功能測試**: 在測試環境執行腳本

5. **提交**: Git hook 會自動檢查語法

### 驗證部署結果

部署完成後，執行 smoke test:
```bash
sudo bash scripts/smoke-test.sh
```
```

---

## 長期改進（1 個月內）

### 任務 6: 路徑硬編碼檢測工具（3-4 小時）

**目標**: 自動檢測腳本中的硬編碼路徑

**實作方式**:
```bash
#!/bin/bash
# scripts/tools/detect-hardcoded-paths.sh
# 檢測腳本中的硬編碼路徑

find scripts/ -name "*.sh" -exec grep -H "/home/" {} \; | \
    grep -v "# Example" | \
    grep -v "# 示例"

# 輸出格式:
# scripts/deployment/script.sh:42:cd /home/user/project
```

**集成到 CI**:
```yaml
# .github/workflows/check-scripts.yml
- name: Check for hardcoded paths
  run: |
    if bash scripts/tools/detect-hardcoded-paths.sh | grep -q "/home/"; then
      echo "Found hardcoded paths"
      exit 1
    fi
```

---

### 任務 7: 配置模板驗證（2-3 小時）

**目標**: 驗證 Helm values 和 YAML 配置的完整性

**實作方式**:
```bash
#!/bin/bash
# scripts/tools/validate-configs.sh

# 檢查所有 YAML 文件語法
find config/ -name "*.yaml" -exec yamllint {} \;

# 檢查必要欄位
for file in config/*.yaml; do
    if ! grep -q "namespace:" "$file"; then
        echo "Missing 'namespace:' in $file"
    fi
done
```

---

### 任務 8: 定期回顧機制（持續）

**目標**: 建立定期回顧和改進機制

**回顧清單**:

#### 每週回顧（15 分鐘）
- [ ] 檢查本週的腳本相關 commit
- [ ] 記錄新發現的問題到 TROUBLESHOOTING.md
- [ ] 更新 smoke-test.sh（如有新增服務）

#### 每月回顧（1 小時）
- [ ] 統計腳本相關 bug 修復次數
- [ ] 評估 smoke test 覆蓋率
- [ ] 檢查 shellcheck 警告趨勢
- [ ] 更新驗證函數庫（如有共用邏輯）

#### 每季回顧（2 小時）
- [ ] 評估質量改進效果
- [ ] 決定是否需要引入新工具
- [ ] 更新最佳實踐文檔
- [ ] 培訓團隊成員（如有新人）

---

## 成功指標

### 關鍵績效指標 (KPI)

| 指標 | 基線 | 目標（1個月） | 目標（3個月） |
|------|------|--------------|--------------|
| ShellCheck 零警告腳本比例 | 0% | 60% | 80% |
| 部署成功率 | TBD | 90% | 95% |
| 腳本相關 bug 修復次數/月 | ~4 | <2 | <1 |
| Smoke Test 通過率 | N/A | 100% | 100% |
| 文檔驅動測試成功率 | TBD | 80% | 95% |

### 追蹤方式

**每週記錄**:
```bash
# 創建追蹤文件
cat > /tmp/quality-metrics-$(date +%Y%m%d).txt <<EOF
日期: $(date)
ShellCheck 警告數: $(find scripts/ -name "*.sh" -exec shellcheck {} + 2>&1 | grep -c "^In ")
部署測試結果: [通過/失敗]
新發現問題: [數量]
EOF
```

**每月分析**:
```bash
# 統計本月 bug 修復
git log --since="1 month ago" --oneline --all-match \
    --grep="fix" --grep="script" | wc -l
```

---

## 風險與緩解

### 風險 1: set -u 導致現有腳本失敗

**可能性**: 中
**影響**: 高
**緩解措施**:
- 逐步引入，從新腳本開始
- 充分測試再應用到關鍵腳本
- 使用 `${var:-default}` 處理可選變量

### 風險 2: Smoke Test 偽陰性（誤報失敗）

**可能性**: 低
**影響**: 中
**緩解措施**:
- 添加重試邏輯（對於時間敏感的檢查）
- 區分關鍵和非關鍵檢查
- 記錄詳細日誌便於診斷

### 風險 3: ShellCheck 誤報

**可能性**: 低
**影響**: 低
**緩解措施**:
- 使用 `.shellcheckrc` 配置合理的排除規則
- 允許特定行的 `# shellcheck disable=SCxxxx`
- 定期回顧排除規則的必要性

---

## 資源需求

### 人力

- **本週**: 1 人日（蔡秀吉）
- **2 週內**: 0.5 人日
- **1 個月內**: 0.5 人日
- **持續**: 每週 0.25 人時（回顧）

### 工具

- ShellCheck: 免費，開源
- Git Hooks: 內建
- Smoke Test: 自行開發，已完成

### 基礎設施

- 測試環境: 需要一個可以重複部署的 k3s 集群
- 文檔平台: 現有 Git repo

---

## 下一步行動

### 今天（2025-11-17）

1. [ ] 安裝 ShellCheck
2. [ ] 啟用 Git Hook
3. [ ] 測試 Smoke Test
4. [ ] 檢查 3 個關鍵腳本的 shellcheck 警告

### 明天（2025-11-18）

1. [ ] 修復關鍵腳本的 shellcheck 警告
2. [ ] 集成 Smoke Test 到 deploy-all.sh
3. [ ] 測試完整部署流程

### 本週內（2025-11-19 至 2025-11-23）

1. [ ] 為 redeploy-xapps-with-metrics.sh 添加前置檢查
2. [ ] 為 deploy-ml-xapps.sh 添加前置檢查
3. [ ] 更新 README.md 開發者指南
4. [ ] 首次週回顧

### 2 週內（2025-11-24 至 2025-12-01）

1. [ ] 完成所有關鍵腳本的 shellcheck 零警告
2. [ ] 更新所有部署文檔
3. [ ] 執行完整的文檔驅動測試

---

## 成功標準

本行動計劃視為成功，如果在 **1 個月內** 達成：

✓ 所有關鍵腳本通過 shellcheck 無警告
✓ Smoke Test 集成到部署流程
✓ 至少 2 個腳本使用驗證函數庫
✓ 部署成功率 ≥ 90%
✓ 腳本相關 bug < 2 個/月
✓ 團隊成員熟悉質量保證流程

---

## 批准與簽署

| 角色 | 姓名 | 簽名 | 日期 |
|------|------|------|------|
| 主要開發者 | 蔡秀吉 | ✓ | 2025-11-17 |
| 項目負責人 | TBD | | |

---

**文件狀態**: 待執行
**下次更新**: 2025-11-24 (1 週後)
**維護者**: 蔡秀吉 (thc1006)
