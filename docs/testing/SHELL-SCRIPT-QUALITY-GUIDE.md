# Shell 腳本質量保證指南

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-17
**狀態**: 實施指南

---

## 概述

本指南說明如何在 O-RAN RIC Platform 項目中維護高質量的 shell 腳本，基於 [BATS-TESTING-EVALUATION.md](./BATS-TESTING-EVALUATION.md) 的評估結果。

**核心理念**: 使用**輕量級**、**高 ROI** 的方法保證腳本質量，避免過度工程。

---

## 快速開始

### 1. 安裝 ShellCheck (1 分鐘)

```bash
# Ubuntu/Debian
sudo apt install shellcheck

# macOS
brew install shellcheck

# 驗證安裝
shellcheck --version
```

### 2. 設置 Git Hook (2 分鐘)

```bash
# 複製 pre-commit hook
cp scripts/hooks/pre-commit.sample .git/hooks/pre-commit

# 設置執行權限
chmod +x .git/hooks/pre-commit

# 測試
git add scripts/deployment/deploy-all.sh
git commit -m "test: 測試 pre-commit hook" --dry-run
```

### 3. 執行 Smoke Test (30 秒)

```bash
# 部署後快速驗證
sudo bash scripts/smoke-test.sh
```

---

## 開發工作流程

### 新增或修改腳本時

1. **編寫腳本** - 使用標準模板
2. **本地檢查** - 運行 shellcheck
3. **功能測試** - 在測試環境執行
4. **Commit** - Git hook 自動檢查
5. **部署驗證** - 執行 smoke-test.sh

```bash
# 1. 編寫腳本
vim scripts/deployment/my-script.sh

# 2. 本地檢查
shellcheck scripts/deployment/my-script.sh

# 3. 功能測試
bash scripts/deployment/my-script.sh

# 4. Commit（自動檢查）
git add scripts/deployment/my-script.sh
git commit -m "feat: add my-script.sh"

# 5. 部署後驗證
sudo bash scripts/smoke-test.sh
```

---

## Shell 腳本模板

### 標準腳本頭部

```bash
#!/bin/bash
#
# 腳本名稱與用途描述
# 作者: 蔡秀吉 (thc1006)
# 日期: YYYY-MM-DD
#
# 用途: 詳細說明腳本功能
# 使用方式: sudo bash scripts/path/to/script.sh [options]
#

# 嚴格模式
set -euo pipefail

# 載入驗證函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 如果需要使用驗證函數
source "$PROJECT_ROOT/scripts/lib/validation.sh"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日誌函數
log_info() {
    echo -e "${BLUE}[資訊]${NC} $1"
}

log_error() {
    echo -e "${RED}[錯誤]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

# 主函數
main() {
    log_info "開始執行 <腳本名稱>..."

    # 前置條件檢查
    if ! check_deployment_prerequisites; then
        log_error "前置條件檢查失敗"
        exit 1
    fi

    # 主要邏輯
    # ...

    log_success "執行完成"
}

# 錯誤處理
trap 'log_error "腳本執行失敗於第 $LINENO 行"; exit 1' ERR

# 執行主函數
main "$@"
```

### 使用驗證函數庫的範例

```bash
#!/bin/bash
set -euo pipefail

# 載入驗證函數
source "$(dirname "$0")/../lib/validation.sh"

main() {
    # 檢查文件存在
    if ! validate_file_exists "/path/to/config.yaml" "配置檔案"; then
        exit 1
    fi

    # 檢查命令存在
    if ! validate_command_exists "kubectl" "kubectl"; then
        exit 1
    fi

    # 檢查 K8s 集群
    if ! validate_k8s_cluster_reachable; then
        exit 1
    fi

    # 檢查 namespace
    if ! validate_k8s_namespace_exists "ricplt"; then
        log_info "建立 namespace ricplt..."
        kubectl create namespace ricplt
    fi

    # 業務邏輯
    log_info "開始部署..."
    # ...
}

main "$@"
```

---

## 最佳實踐清單

### ✓ 必須遵守

- [ ] 使用 `set -e` (錯誤自動退出)
- [ ] 使用 `set -u` (未定義變量報錯)
- [ ] 使用 `set -o pipefail` (管道錯誤檢測)
- [ ] 提供清晰的註解和使用說明
- [ ] 使用顏色輸出區分資訊/警告/錯誤
- [ ] 驗證前置條件（工具、文件、集群連通性）
- [ ] 使用函數組織代碼
- [ ] 提供錯誤處理 (trap)

### ✓ 強烈建議

- [ ] 使用 `"${variable}"` 而非 `$variable` (防止路徑空格問題)
- [ ] 檢查命令返回值
- [ ] 提供冪等性（重複執行不會造成錯誤）
- [ ] 記錄日誌到文件
- [ ] 使用超時機制 (timeout 命令)
- [ ] 提供進度提示

### ✓ 建議

- [ ] 使用驗證函數庫
- [ ] 提供 `--help` 參數
- [ ] 支持 `--dry-run` 模式
- [ ] 記錄執行時間

---

## 常見問題與解決方案

### 問題 1: 路徑包含空格導致錯誤

**錯誤範例**:
```bash
cd $PROJECT_ROOT  # 如果路徑有空格會失敗
```

**正確寫法**:
```bash
cd "$PROJECT_ROOT"  # 使用引號
cd "${PROJECT_ROOT}"  # 更佳：使用大括號
```

### 問題 2: 未檢查命令是否存在

**錯誤範例**:
```bash
kubectl get pods  # 如果 kubectl 未安裝會報錯
```

**正確寫法**:
```bash
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl 未安裝"
    exit 1
fi
kubectl get pods
```

**或使用驗證函數**:
```bash
validate_command_exists "kubectl" "kubectl" || exit 1
kubectl get pods
```

### 問題 3: 未驗證文件存在

**錯誤範例**:
```bash
source /path/to/config.sh  # 如果文件不存在會失敗
```

**正確寫法**:
```bash
if [ ! -f "/path/to/config.sh" ]; then
    log_error "配置檔案不存在"
    exit 1
fi
source /path/to/config.sh
```

**或使用驗證函數**:
```bash
validate_file_exists "/path/to/config.sh" "配置檔案" || exit 1
source /path/to/config.sh
```

### 問題 4: 未檢查 K8s 集群連通性

**錯誤範例**:
```bash
kubectl create namespace ricplt  # 如果集群不可達會掛起或失敗
```

**正確寫法**:
```bash
if ! kubectl cluster-info &> /dev/null; then
    log_error "無法連接到 Kubernetes 集群"
    exit 1
fi
kubectl create namespace ricplt
```

**或使用驗證函數**:
```bash
validate_k8s_cluster_reachable || exit 1
kubectl create namespace ricplt
```

### 問題 5: 硬編碼路徑

**錯誤範例**:
```bash
cd /home/thc1006/oran-ric-platform  # 不可移植
```

**正確寫法**:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"
```

---

## ShellCheck 使用指南

### 本地檢查

```bash
# 檢查單個腳本
shellcheck scripts/deployment/deploy-all.sh

# 檢查所有腳本
find scripts/ -name "*.sh" -exec shellcheck {} +

# 使用項目配置檔案
shellcheck --config .shellcheckrc scripts/deployment/deploy-all.sh
```

### 忽略特定警告

```bash
# 在腳本中忽略特定規則
# shellcheck disable=SC2086
variable_with_spaces=$1

# 忽略單行
echo $unquoted_variable  # shellcheck disable=SC2086
```

### 常見 ShellCheck 警告

| 代碼 | 說明 | 解決方案 |
|------|------|---------|
| SC2086 | 未引用變量 | 使用 `"$variable"` |
| SC2068 | 未引用數組 | 使用 `"${array[@]}"` |
| SC2154 | 引用未賦值變量 | 先賦值或使用 `${variable:-default}` |
| SC2046 | 未引用命令替換 | 使用 `"$(command)"` |
| SC2181 | 間接檢查 $? | 使用 `if mycmd; then` |

---

## Smoke Test 使用指南

### 基本使用

```bash
# 部署後執行
sudo bash scripts/smoke-test.sh

# 查看詳細輸出
sudo bash scripts/smoke-test.sh | tee smoke-test-result.log
```

### 集成到部署腳本

```bash
# 在 deploy-all.sh 最後添加
echo ""
log_info "執行 Smoke Test..."
if bash "$PROJECT_ROOT/scripts/smoke-test.sh"; then
    log_success "Smoke Test 通過"
else
    log_error "Smoke Test 失敗，請檢查日誌"
    exit 1
fi
```

### 自定義檢查項目

編輯 `scripts/smoke-test.sh`，添加新的檢查：

```bash
# 添加自定義檢查
echo -e "${YELLOW}[7/7] 自定義檢查${NC}"
check "自定義服務 Running" "kubectl get pod -n ricxapp -l app=my-service -o jsonpath='{.items[0].status.phase}' | grep -q Running"
```

---

## CI/CD 集成（未來）

當項目需要 CI/CD 時，可以添加：

```yaml
# .github/workflows/shell-lint.yml
name: Shell Script Linting

on: [push, pull_request]

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run ShellCheck
        uses: ludeeus/action-shellcheck@master
        with:
          scandir: './scripts'
          severity: warning

  smoke-test:
    runs-on: ubuntu-latest
    needs: shellcheck
    steps:
      - uses: actions/checkout@v3
      - name: Setup k3s
        run: sudo bash scripts/deployment/setup-k3s.sh
      - name: Deploy Platform
        run: sudo bash scripts/deployment/deploy-all.sh
      - name: Run Smoke Test
        run: sudo bash scripts/smoke-test.sh
```

---

## 改進現有腳本

### 優先級

**P0 (立即)**: 關鍵部署腳本
- `scripts/deployment/setup-k3s.sh`
- `scripts/deployment/deploy-all.sh`
- `scripts/deployment/deploy-ric-platform.sh`

**P1 (本週)**: 高頻使用腳本
- `scripts/redeploy-xapps-with-metrics.sh`
- `scripts/deploy-ml-xapps.sh`

**P2 (本月)**: 工具腳本
- `scripts/verify-all-xapps.sh`
- `scripts/deployment/import-dashboards.sh`

### 改進檢查清單

對於每個腳本：

```bash
# 1. 添加嚴格模式
set -euo pipefail

# 2. 使用驗證函數
source "$(dirname "$0")/../lib/validation.sh"

# 3. 添加前置條件檢查
if ! check_deployment_prerequisites; then
    exit 1
fi

# 4. 驗證關鍵路徑
validate_file_exists "$KUBECONFIG" "KUBECONFIG 檔案" || exit 1

# 5. 添加冪等性檢查
if kubectl get namespace ricplt &> /dev/null; then
    log_warn "Namespace ricplt 已存在，跳過"
else
    kubectl create namespace ricplt
fi

# 6. 運行 shellcheck
shellcheck scripts/deployment/my-script.sh

# 7. 功能測試
bash scripts/deployment/my-script.sh

# 8. 更新文檔
```

---

## 維護與回顧

### 每週

- [ ] 檢查新增或修改的腳本是否通過 shellcheck
- [ ] 執行 smoke-test 驗證部署

### 每月

- [ ] 回顧 Git commit 中的腳本修復
- [ ] 更新 TROUBLESHOOTING.md 記錄新問題
- [ ] 評估驗證函數庫是否需要擴充

### 每季

- [ ] 回顧 shell 腳本質量指標
- [ ] 評估是否需要引入新工具
- [ ] 更新最佳實踐文檔

---

## 質量指標

追蹤以下指標來評估改進效果：

| 指標 | 目標 | 當前 | 追蹤方式 |
|------|------|------|---------|
| ShellCheck 零警告腳本比例 | 80% | TBD | `find scripts/ -name "*.sh" -exec shellcheck {} +` |
| 部署成功率 | 95% | TBD | 記錄每次部署結果 |
| 腳本相關 bug 修復次數 | <2/月 | TBD | Git log 統計 |
| Smoke Test 通過率 | 100% | TBD | 每次部署後記錄 |

---

## 參考資料

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [Bash Strict Mode](http://redsymbol.net/articles/unofficial-bash-strict-mode/)
- [BATS Testing Evaluation](./BATS-TESTING-EVALUATION.md)

---

## 變更歷史

| 日期 | 版本 | 變更內容 | 作者 |
|------|------|---------|------|
| 2025-11-17 | 1.0 | 初始版本 | 蔡秀吉 |

---

**維護者**: 蔡秀吉 (thc1006)
**最後更新**: 2025-11-17
