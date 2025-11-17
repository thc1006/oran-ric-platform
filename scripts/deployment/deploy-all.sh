#!/bin/bash
#
# O-RAN RIC Platform 一鍵部署腳本
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-16
#
# 功能：
# - 自動檢查系統前提條件
# - 完整部署 RIC Platform、xApps 和監控系統
# - 智慧超時控制和錯誤處理
# - 即時進度顯示和驗證
#
# 使用方式：
#   sudo bash scripts/deployment/deploy-all.sh
#

set -e

# ============================================================================
# 顏色定義
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# 超時設定（秒）
# ============================================================================
TIMEOUT_POD_READY=180           # Pod 就緒超時：3分鐘
TIMEOUT_HELM_INSTALL=300        # Helm 安裝超時：5分鐘
TIMEOUT_REGISTRY_START=30       # Registry 啟動超時：30秒
TIMEOUT_NAMESPACE_CREATE=10     # Namespace 創建超時：10秒
TIMEOUT_DASHBOARD_IMPORT=60     # 儀表板匯入超時：1分鐘

# ============================================================================
# 全域變數
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="/tmp/oran-ric-deploy-$(date +%Y%m%d-%H%M%S).log"
START_TIME=$(date +%s)

# 載入驗證函數庫（用於 KUBECONFIG 標準化）
source "${PROJECT_ROOT}/scripts/lib/validation.sh"

# ============================================================================
# 日誌函數
# ============================================================================
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

info() {
    log "${BLUE}[資訊]${NC} $1"
}

success() {
    log "${GREEN}[成功]${NC} $1"
}

warn() {
    log "${YELLOW}[警告]${NC} $1"
}

error() {
    log "${RED}[錯誤]${NC} $1"
}

step() {
    local step_num=$1
    local step_desc=$2
    log ""
    log "${BLUE}========================================${NC}"
    log "${BLUE}步驟 ${step_num}: ${step_desc}${NC}"
    log "${BLUE}========================================${NC}"
}

# ============================================================================
# 時間計算
# ============================================================================
elapsed_time() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    echo "${minutes}分${seconds}秒"
}

# ============================================================================
# 系統檢查
# ============================================================================
check_prerequisites() {
    step "0" "檢查系統前提條件"

    local errors=0

    # 檢查 OS
    info "檢查作業系統..."
    if ! command -v lsb_release &> /dev/null; then
        error "無法偵測作業系統版本"
        ((errors++))
    else
        local os_name=$(lsb_release -is)
        local os_version=$(lsb_release -rs)
        success "作業系統: $os_name $os_version"
    fi

    # 檢查 CPU
    info "檢查 CPU 核心數..."
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 8 ]; then
        warn "CPU 核心數不足 8 核（目前: ${cpu_cores}），建議至少 8 核"
    else
        success "CPU: ${cpu_cores} 核心"
    fi

    # 檢查記憶體
    info "檢查記憶體..."
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$mem_gb" -lt 16 ]; then
        warn "記憶體不足 16GB（目前: ${mem_gb}GB），建議至少 16GB"
    else
        success "記憶體: ${mem_gb}GB"
    fi

    # 檢查磁碟空間
    info "檢查磁碟空間..."
    local disk_avail=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$disk_avail" -lt 100 ]; then
        warn "可用磁碟空間不足 100GB（目前: ${disk_avail}GB）"
    else
        success "磁碟可用: ${disk_avail}GB"
    fi

    # 檢查 Docker
    info "檢查 Docker..."
    if ! command -v docker &> /dev/null; then
        error "Docker 未安裝，請先安裝 Docker"
        ((errors++))
    else
        local docker_version=$(docker --version)
        success "Docker 已安裝: $docker_version"
    fi

    # 檢查 Helm
    info "檢查 Helm..."
    if ! command -v helm &> /dev/null; then
        error "Helm 未安裝，請先安裝 Helm"
        ((errors++))
    else
        local helm_version=$(helm version --short)
        success "Helm 已安裝: $helm_version"
    fi

    # 檢查 kubectl
    info "檢查 kubectl..."
    if ! command -v kubectl &> /dev/null; then
        error "kubectl 未安裝，請先安裝 k3s"
        ((errors++))
    else
        local kubectl_version=$(kubectl version --client --short 2>/dev/null || echo "kubectl installed")
        success "kubectl 已安裝"
    fi

    if [ $errors -gt 0 ]; then
        error "前提條件檢查失敗，請解決上述問題後重試"
        exit 1
    fi

    success "所有前提條件檢查通過"
}

# ============================================================================
# KUBECONFIG 設定
# ============================================================================
configure_kubeconfig() {
    step "1" "設定 kubectl 存取"

    info "設定 KUBECONFIG..."

    # 先嘗試使用標準化方法（尊重現有環境變數）
    if setup_kubeconfig 2>/dev/null; then
        info "使用現有 KUBECONFIG: $KUBECONFIG"
    else
        # 如果標準方法失敗，嘗試設置 k3s 配置
        info "未找到現有配置，設定 k3s KUBECONFIG..."

        if [ ! -f "/etc/rancher/k3s/k3s.yaml" ]; then
            error "k3s 設定檔不存在，請先執行 setup-k3s.sh"
            exit 1
        fi

        mkdir -p $HOME/.kube
        sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
        sudo chown $USER:$USER $HOME/.kube/config

        export KUBECONFIG=$HOME/.kube/config
        info "已設定 KUBECONFIG: $KUBECONFIG"
    fi

    # 驗證
    if kubectl cluster-info &> /dev/null; then
        success "kubectl 設定成功"
    else
        error "kubectl 設定失敗"
        exit 1
    fi
}

# ============================================================================
# 建立 Namespaces
# ============================================================================
create_namespaces() {
    step "2" "建立 RIC Namespaces"

    local namespaces=("ricplt" "ricxapp" "ricobs")

    for ns in "${namespaces[@]}"; do
        info "建立 namespace: $ns"

        if kubectl get namespace "$ns" &> /dev/null; then
            warn "Namespace $ns 已存在，跳過"
        else
            if timeout $TIMEOUT_NAMESPACE_CREATE kubectl create namespace "$ns"; then
                success "Namespace $ns 建立成功"
            else
                error "建立 namespace $ns 失敗"
                exit 1
            fi
        fi
    done

    success "所有 namespaces 建立完成"
}

# ============================================================================
# 啟動 Docker Registry
# ============================================================================
start_registry() {
    step "3" "啟動本地 Docker Registry"

    info "檢查 Docker Registry 狀態..."

    if docker ps | grep -q "registry.*5000"; then
        warn "Docker Registry 已在執行，跳過啟動"
        return 0
    fi

    # 檢查是否有停止的 registry 容器
    if docker ps -a | grep -q "registry"; then
        info "刪除舊的 registry 容器..."
        docker rm -f registry 2>/dev/null || true
    fi

    info "啟動 Docker Registry..."
    docker run -d --restart=always --name registry \
        -p 5000:5000 \
        -v /var/lib/registry:/var/lib/registry \
        registry:2 &> /dev/null

    # 等待 registry 啟動
    local timeout=$TIMEOUT_REGISTRY_START
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if curl -s http://localhost:5000/v2/_catalog &> /dev/null; then
            success "Docker Registry 啟動成功"
            return 0
        fi
        sleep 2
        ((elapsed+=2))
    done

    error "Docker Registry 啟動超時"
    exit 1
}

# ============================================================================
# 部署 Prometheus
# ============================================================================
deploy_prometheus() {
    step "4" "部署 Prometheus"

    info "檢查 Prometheus 是否已部署..."
    if helm list -n ricplt | grep -q "r4-infrastructure-prometheus"; then
        warn "Prometheus 已部署，跳過"
        return 0
    fi

    info "部署 Prometheus..."
    cd "$PROJECT_ROOT"

    if ! timeout $TIMEOUT_HELM_INSTALL helm install r4-infrastructure-prometheus \
        ./ric-dep/helm/infrastructure/subcharts/prometheus \
        --namespace ricplt \
        --values ./config/prometheus-values.yaml; then
        error "Prometheus 部署失敗"
        exit 1
    fi

    info "等待 Prometheus Pod 就緒..."
    if ! timeout $TIMEOUT_POD_READY kubectl wait --for=condition=ready pod \
        -l app=prometheus,component=server \
        -n ricplt \
        --timeout=${TIMEOUT_POD_READY}s; then
        error "Prometheus Pod 啟動超時"
        kubectl get pods -n ricplt -l app=prometheus
        exit 1
    fi

    success "Prometheus 部署完成"
}

# ============================================================================
# 部署 Grafana
# ============================================================================
deploy_grafana() {
    step "5" "部署 Grafana"

    info "檢查 Grafana 是否已部署..."
    if helm list -n ricplt | grep -q "oran-grafana"; then
        warn "Grafana 已部署，跳過"
        return 0
    fi

    info "新增 Grafana Helm 儲存庫..."
    helm repo add grafana https://grafana.github.io/helm-charts &> /dev/null || true
    helm repo update &> /dev/null

    info "部署 Grafana..."
    cd "$PROJECT_ROOT"

    if ! timeout $TIMEOUT_HELM_INSTALL helm install oran-grafana \
        grafana/grafana \
        -n ricplt \
        -f ./config/grafana-values.yaml; then
        error "Grafana 部署失敗"
        exit 1
    fi

    info "等待 Grafana Pod 就緒..."
    if ! timeout $TIMEOUT_POD_READY kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=grafana \
        -n ricplt \
        --timeout=${TIMEOUT_POD_READY}s; then
        error "Grafana Pod 啟動超時"
        kubectl get pods -n ricplt -l app.kubernetes.io/name=grafana
        exit 1
    fi

    success "Grafana 部署完成"

    # 取得 admin 密碼
    local admin_pass=$(kubectl get secret -n ricplt oran-grafana \
        -o jsonpath="{.data.admin-password}" | base64 -d)
    info "Grafana 管理員密碼: $admin_pass"
}

# ============================================================================
# 部署 xApps
# ============================================================================
deploy_xapps() {
    step "6" "部署所有 xApps"

    cd "$PROJECT_ROOT"

    local xapps=(
        "kpimon-go-xapp:kpimon"
        "traffic-steering:traffic-steering"
        "rc-xapp:ran-control"
        "qoe-predictor:qoe-predictor"
        "federated-learning:federated-learning"
    )

    for xapp_info in "${xapps[@]}"; do
        local xapp_dir="${xapp_info%%:*}"
        local xapp_name="${xapp_info##*:}"

        info "部署 $xapp_name xApp..."

        # 檢查是否已部署
        if kubectl get deployment -n ricxapp "$xapp_name" &> /dev/null 2>&1 || \
           kubectl get deployment -n ricxapp "${xapp_name}-gpu" &> /dev/null 2>&1; then
            warn "$xapp_name 已部署，跳過"
            continue
        fi

        if ! kubectl apply -f "./xapps/$xapp_dir/deploy/" -n ricxapp; then
            error "$xapp_name 部署失敗"
            exit 1
        fi

        # 等待 Pod 就緒（federated-learning 特殊處理）
        if [ "$xapp_name" = "federated-learning" ]; then
            info "等待 $xapp_name Pod 就緒（CPU 版本）..."
            if ! timeout $TIMEOUT_POD_READY kubectl wait --for=condition=ready pod \
                -l app=federated-learning \
                -n ricxapp \
                --timeout=${TIMEOUT_POD_READY}s 2>/dev/null; then
                warn "$xapp_name CPU 版本啟動超時，繼續下一步"
            else
                success "$xapp_name CPU 版本啟動成功"
            fi
        else
            info "等待 $xapp_name Pod 就緒..."
            if ! timeout $TIMEOUT_POD_READY kubectl wait --for=condition=ready pod \
                -l app="$xapp_name" \
                -n ricxapp \
                --timeout=${TIMEOUT_POD_READY}s; then
                error "$xapp_name Pod 啟動超時"
                kubectl get pods -n ricxapp -l app="$xapp_name"
                exit 1
            fi
            success "$xapp_name 部署完成"
        fi
    done

    success "所有 xApps 部署完成"
}

# ============================================================================
# 部署 E2 Simulator
# ============================================================================
deploy_e2_simulator() {
    step "7" "部署 E2 Simulator"

    cd "$PROJECT_ROOT"

    info "檢查 E2 Simulator 是否已部署..."
    if kubectl get deployment -n ricxapp e2-simulator &> /dev/null; then
        warn "E2 Simulator 已部署，跳過"
        return 0
    fi

    info "部署 E2 Simulator..."
    if ! kubectl apply -f ./simulator/e2-simulator/deploy/deployment.yaml -n ricxapp; then
        error "E2 Simulator 部署失敗"
        exit 1
    fi

    info "等待 E2 Simulator Pod 就緒..."
    if ! timeout $TIMEOUT_POD_READY kubectl wait --for=condition=ready pod \
        -l app=e2-simulator \
        -n ricxapp \
        --timeout=${TIMEOUT_POD_READY}s; then
        error "E2 Simulator Pod 啟動超時"
        kubectl get pods -n ricxapp -l app=e2-simulator
        exit 1
    fi

    success "E2 Simulator 部署完成"
}

# ============================================================================
# 匯入 Grafana 儀表板
# ============================================================================
import_dashboards() {
    step "8" "匯入 Grafana 儀表板"

    cd "$PROJECT_ROOT"

    info "啟動 port-forward..."
    kubectl port-forward -n ricplt svc/oran-grafana 3000:80 &> /dev/null &
    local pfwd_pid=$!

    sleep 5

    info "匯入儀表板..."
    if ! timeout $TIMEOUT_DASHBOARD_IMPORT bash ./scripts/deployment/import-dashboards.sh &>> "$LOG_FILE"; then
        error "儀表板匯入失敗"
        kill $pfwd_pid 2>/dev/null || true
        exit 1
    fi

    kill $pfwd_pid 2>/dev/null || true
    success "儀表板匯入完成"
}

# ============================================================================
# 最終驗證
# ============================================================================
verify_deployment() {
    step "9" "驗證部署狀態"

    info "檢查所有 Pods 狀態..."
    echo ""
    kubectl get pods -n ricplt | grep -E 'grafana|prometheus'
    echo ""
    kubectl get pods -n ricxapp
    echo ""

    # 檢查關鍵 Pods
    local critical_pods=(
        "ricplt:app=prometheus,component=server"
        "ricplt:app.kubernetes.io/name=grafana"
        "ricxapp:app=kpimon"
        "ricxapp:app=traffic-steering"
        "ricxapp:app=ran-control"
        "ricxapp:app=e2-simulator"
    )

    local failed=0
    for pod_info in "${critical_pods[@]}"; do
        local namespace="${pod_info%%:*}"
        local selector="${pod_info##*:}"

        if ! kubectl get pods -n "$namespace" -l "$selector" 2>/dev/null | grep -q "Running"; then
            error "關鍵 Pod 未執行: $namespace/$selector"
            ((failed++))
        fi
    done

    if [ $failed -gt 0 ]; then
        error "部署驗證失敗，有 $failed 個關鍵元件未正常執行"
        exit 1
    fi

    success "所有關鍵元件執行正常"

    # 檢查 E2 Simulator 日誌
    info "檢查 E2 Simulator 執行狀態..."
    local e2_log=$(kubectl logs -n ricxapp -l app=e2-simulator --tail=5 2>/dev/null | grep -i "iteration" | tail -1)
    if [ -n "$e2_log" ]; then
        success "E2 Simulator 正在產生資料"
        echo "  最新: $e2_log"
    else
        warn "無法取得 E2 Simulator 日誌"
    fi
}

# ============================================================================
# 顯示存取資訊
# ============================================================================
show_access_info() {
    step "10" "部署完成"

    local admin_pass=$(kubectl get secret -n ricplt oran-grafana \
        -o jsonpath="{.data.admin-password}" | base64 -d 2>/dev/null || echo "無法取得")

    log ""
    log "${GREEN}========================================${NC}"
    log "${GREEN}  O-RAN RIC Platform 部署成功！${NC}"
    log "${GREEN}========================================${NC}"
    log ""
    log "總耗時: $(elapsed_time)"
    log ""
    log "${BLUE}存取 Grafana:${NC}"
    log "  1. 啟動 port-forward:"
    log "     ${YELLOW}kubectl port-forward -n ricplt svc/oran-grafana 3000:80${NC}"
    log ""
    log "  2. 瀏覽器開啟: ${YELLOW}http://localhost:3000${NC}"
    log ""
    log "  3. 登入資訊:"
    log "     使用者名稱: ${YELLOW}admin${NC}"
    log "     密碼:       ${YELLOW}$admin_pass${NC}"
    log ""
    log "${BLUE}驗證指標:${NC}"
    log "  查看 KPIMON 指標:"
    log "     ${YELLOW}kubectl logs -n ricxapp -l app=kpimon --tail=20${NC}"
    log ""
    log "  查看 E2 Simulator 日誌:"
    log "     ${YELLOW}kubectl logs -n ricxapp -l app=e2-simulator -f${NC}"
    log ""
    log "${BLUE}部署日誌:${NC} $LOG_FILE"
    log ""
    log "${GREEN}========================================${NC}"
}

# ============================================================================
# 主函數
# ============================================================================
main() {
    log ""
    log "${BLUE}========================================${NC}"
    log "${BLUE}  O-RAN RIC Platform 一鍵部署腳本${NC}"
    log "${BLUE}  作者: 蔡秀吉 (thc1006)${NC}"
    log "${BLUE}  時間: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    log "${BLUE}========================================${NC}"
    log ""

    # 檢查是否以 root 或 sudo 執行
    if [ "$EUID" -eq 0 ]; then
        warn "偵測到以 root 使用者執行，某些步驟可能需要非 root 權限"
    fi

    check_prerequisites
    configure_kubeconfig
    create_namespaces
    start_registry
    deploy_prometheus
    deploy_grafana
    deploy_xapps
    deploy_e2_simulator
    import_dashboards
    verify_deployment
    show_access_info

    log ""
    log "${GREEN}部署腳本執行成功！${NC}"
    log ""
}

# ============================================================================
# 錯誤處理
# ============================================================================
trap 'error "腳本執行失敗，請檢查日誌: $LOG_FILE"; exit 1' ERR

# 執行主函數
main "$@"
