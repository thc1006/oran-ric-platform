#!/bin/bash
#
# Shell 腳本驗證函數庫
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-17
#
# 用途: 提供通用的驗證函數，增強腳本健壯性
# 使用方式: source scripts/lib/validation.sh
#

# ============================================================================
# 顏色定義（如果尚未定義）
# ============================================================================
if [ -z "$RED" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# ============================================================================
# 日誌函數（如果尚未定義）
# ============================================================================
if ! type log_error &> /dev/null; then
    log_error() {
        echo -e "${RED}[錯誤]${NC} $1" >&2
    }
fi

if ! type log_warn &> /dev/null; then
    log_warn() {
        echo -e "${YELLOW}[警告]${NC} $1"
    }
fi

if ! type log_info &> /dev/null; then
    log_info() {
        echo -e "${BLUE}[資訊]${NC} $1"
    }
fi

# ============================================================================
# 路徑驗證函數
# ============================================================================

# 驗證文件是否存在
# 參數:
#   $1: 文件路徑
#   $2: 描述（用於錯誤訊息）
# 返回: 0=存在, 1=不存在
validate_file_exists() {
    local file_path=$1
    local description=${2:-"檔案"}

    if [ ! -f "$file_path" ]; then
        log_error "$description 不存在: $file_path"
        return 1
    fi
    return 0
}

# 驗證目錄是否存在
# 參數:
#   $1: 目錄路徑
#   $2: 描述（用於錯誤訊息）
# 返回: 0=存在, 1=不存在
validate_directory_exists() {
    local dir_path=$1
    local description=${2:-"目錄"}

    if [ ! -d "$dir_path" ]; then
        log_error "$description 不存在: $dir_path"
        return 1
    fi
    return 0
}

# 驗證路徑存在（文件或目錄）
# 參數:
#   $1: 路徑
#   $2: 描述（用於錯誤訊息）
# 返回: 0=存在, 1=不存在
validate_path_exists() {
    local path=$1
    local description=${2:-"路徑"}

    if [ ! -e "$path" ]; then
        log_error "$description 不存在: $path"
        return 1
    fi
    return 0
}

# 驗證文件可讀
# 參數:
#   $1: 文件路徑
#   $2: 描述（用於錯誤訊息）
# 返回: 0=可讀, 1=不可讀
validate_file_readable() {
    local file_path=$1
    local description=${2:-"檔案"}

    if [ ! -r "$file_path" ]; then
        log_error "$description 不可讀: $file_path"
        return 1
    fi
    return 0
}

# 驗證文件可執行
# 參數:
#   $1: 文件路徑
#   $2: 描述（用於錯誤訊息）
# 返回: 0=可執行, 1=不可執行
validate_file_executable() {
    local file_path=$1
    local description=${2:-"檔案"}

    if [ ! -x "$file_path" ]; then
        log_error "$description 不可執行: $file_path"
        return 1
    fi
    return 0
}

# ============================================================================
# 環境變量驗證
# ============================================================================

# 驗證環境變量已設置
# 參數:
#   $1: 環境變量名稱
#   $2: 描述（用於錯誤訊息）
# 返回: 0=已設置, 1=未設置
validate_env_var_set() {
    local var_name=$1
    local description=${2:-"環境變數"}

    if [ -z "${!var_name}" ]; then
        log_error "$description ($var_name) 未設置"
        return 1
    fi
    return 0
}

# 驗證環境變量非空
# 參數:
#   $1: 環境變量名稱
#   $2: 描述（用於錯誤訊息）
# 返回: 0=非空, 1=空值
validate_env_var_not_empty() {
    local var_name=$1
    local description=${2:-"環境變數"}

    if [ -z "${!var_name}" ]; then
        log_error "$description ($var_name) 不能為空"
        return 1
    fi
    return 0
}

# ============================================================================
# 命令驗證
# ============================================================================

# 驗證命令是否存在
# 參數:
#   $1: 命令名稱
#   $2: 描述（用於錯誤訊息）
#   $3: 安裝建議（可選）
# 返回: 0=存在, 1=不存在
validate_command_exists() {
    local command_name=$1
    local description=${2:-"命令"}
    local install_hint=$3

    if ! command -v "$command_name" &> /dev/null; then
        log_error "$description ($command_name) 未安裝"
        if [ -n "$install_hint" ]; then
            log_info "安裝建議: $install_hint"
        fi
        return 1
    fi
    return 0
}

# 驗證多個命令是否存在
# 參數:
#   $@: 命令名稱列表
# 返回: 0=全部存在, 1=有缺失
validate_commands_exist() {
    local missing_commands=0

    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "必要命令未安裝: $cmd"
            ((missing_commands++))
        fi
    done

    if [ $missing_commands -gt 0 ]; then
        log_error "缺少 $missing_commands 個必要命令"
        return 1
    fi
    return 0
}

# ============================================================================
# Kubernetes 驗證
# ============================================================================

# KUBECONFIG 標準化設定
# 優先級: 1. 現有環境變數 2. ~/.kube/config 3. k3s 預設路徑
# 返回: 0=成功設定, 1=無法找到有效配置
setup_kubeconfig() {
    # 1. 如果已設定且檔案存在，直接使用
    if [ -n "$KUBECONFIG" ] && [ -f "$KUBECONFIG" ]; then
        log_info "使用現有 KUBECONFIG: $KUBECONFIG"
        return 0
    fi

    # 2. 檢查標準位置 ~/.kube/config
    if [ -f "$HOME/.kube/config" ]; then
        export KUBECONFIG="$HOME/.kube/config"
        log_info "使用標準 KUBECONFIG: $KUBECONFIG"
        return 0
    fi

    # 3. k3s 預設位置（回退選項）
    if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
        export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
        log_warn "使用 k3s 預設 KUBECONFIG: $KUBECONFIG"
        log_warn "建議複製到標準位置: mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown \$USER ~/.kube/config"
        return 0
    fi

    # 4. 無法找到有效配置
    log_error "無法找到有效的 KUBECONFIG"
    log_error "請執行以下任一操作:"
    log_error "  1. 設定環境變數: export KUBECONFIG=/path/to/kubeconfig"
    log_error "  2. 複製到標準位置: mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config"
    log_error "  3. 確認 k3s 已安裝: sudo systemctl status k3s"
    return 1
}

# 驗證 kubectl 可用
# 返回: 0=可用, 1=不可用
validate_kubectl_available() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安裝"
        return 1
    fi
    return 0
}

# 驗證 K8s 集群連通性
# 返回: 0=可連通, 1=不可連通
validate_k8s_cluster_reachable() {
    if ! validate_kubectl_available; then
        return 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "無法連接到 Kubernetes 集群"
        log_info "請檢查:"
        log_info "  1. k3s 服務是否運行: sudo systemctl status k3s"
        log_info "  2. KUBECONFIG 環境變量: echo \$KUBECONFIG"
        log_info "  3. kubeconfig 文件: ls -l /etc/rancher/k3s/k3s.yaml"
        return 1
    fi
    return 0
}

# 驗證 K8s namespace 是否存在
# 參數:
#   $1: namespace 名稱
# 返回: 0=存在, 1=不存在
validate_k8s_namespace_exists() {
    local namespace=$1

    if ! kubectl get namespace "$namespace" &> /dev/null; then
        log_error "Kubernetes namespace 不存在: $namespace"
        return 1
    fi
    return 0
}

# 驗證 K8s 資源是否存在
# 參數:
#   $1: 資源類型 (pod, service, deployment, etc.)
#   $2: 資源名稱
#   $3: namespace (可選，默認: default)
# 返回: 0=存在, 1=不存在
validate_k8s_resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-default}

    if ! kubectl get "$resource_type" "$resource_name" -n "$namespace" &> /dev/null; then
        log_error "Kubernetes $resource_type 不存在: $resource_name (namespace: $namespace)"
        return 1
    fi
    return 0
}

# ============================================================================
# 數值驗證
# ============================================================================

# 驗證是否為正整數
# 參數:
#   $1: 數值
#   $2: 描述（用於錯誤訊息）
# 返回: 0=是正整數, 1=不是
validate_positive_integer() {
    local value=$1
    local description=${2:-"數值"}

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        log_error "$description 必須是正整數: $value"
        return 1
    fi
    return 0
}

# 驗證數值範圍
# 參數:
#   $1: 數值
#   $2: 最小值
#   $3: 最大值
#   $4: 描述（用於錯誤訊息）
# 返回: 0=在範圍內, 1=超出範圍
validate_number_range() {
    local value=$1
    local min=$2
    local max=$3
    local description=${4:-"數值"}

    if ! validate_positive_integer "$value" "$description"; then
        return 1
    fi

    if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
        log_error "$description 超出範圍 ($min-$max): $value"
        return 1
    fi
    return 0
}

# ============================================================================
# 綜合前置條件檢查
# ============================================================================

# 檢查部署腳本的標準前置條件
# 返回: 0=全部通過, 1=有失敗
check_deployment_prerequisites() {
    local errors=0

    log_info "檢查部署前置條件..."

    # 檢查必要命令
    local required_commands=("kubectl" "helm" "docker")
    for cmd in "${required_commands[@]}"; do
        if ! validate_command_exists "$cmd"; then
            ((errors++))
        fi
    done

    # 設定 KUBECONFIG（標準化處理）
    if ! setup_kubeconfig; then
        ((errors++))
    fi

    # 檢查 K8s 集群
    if ! validate_k8s_cluster_reachable; then
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        log_error "前置條件檢查失敗 ($errors 個問題)"
        return 1
    fi

    log_info "前置條件檢查通過"
    return 0
}

# ============================================================================
# 使用範例（註解）
# ============================================================================

# 範例 1: 驗證文件存在
# if ! validate_file_exists "/path/to/config.yaml" "配置檔案"; then
#     exit 1
# fi

# 範例 2: 驗證命令存在
# if ! validate_command_exists "kubectl" "kubectl" "sudo snap install kubectl --classic"; then
#     exit 1
# fi

# 範例 3: 驗證 K8s namespace
# if ! validate_k8s_namespace_exists "ricplt"; then
#     log_info "建立 namespace..."
#     kubectl create namespace ricplt
# fi

# 範例 4: 綜合前置條件檢查
# if ! check_deployment_prerequisites; then
#     log_error "請解決上述問題後重試"
#     exit 1
# fi
