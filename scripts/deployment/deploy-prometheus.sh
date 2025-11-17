#!/bin/bash
#
# O-RAN RIC Prometheus 監控部署腳本
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-15
#
# 用途: 部署 Prometheus Server 到 RIC Platform 用於 xApp 監控
#
# 參考: O-RAN SC 官方監控架構標準
# - Prometheus Server: 抓取 xApp metrics (Prometheus 格式)
# - 端點要求: /ric/v1/metrics
# - Annotations: prometheus.io/scrape, prometheus.io/port, prometheus.io/path
#

set -e

# 配置變數
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROMETHEUS_CHART_DIR="${PROJECT_ROOT}/ric-dep/helm/infrastructure/subcharts/prometheus"
VALUES_FILE="${PROJECT_ROOT}/config/prometheus-values.yaml"
RELEASE_NAME="r4-infrastructure-prometheus"
NAMESPACE="ricplt"

# 載入驗證函數庫
source "${PROJECT_ROOT}/scripts/lib/validation.sh"

# KUBECONFIG 標準化設定
if ! setup_kubeconfig; then
    exit 1
fi

echo "=================================================="
echo "   O-RAN RIC Prometheus 監控部署"
echo "   作者: 蔡秀吉 (thc1006)"
echo "   日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
echo

# 函數：日誌輸出
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 檢查前置條件
check_prerequisites() {
    log_info "檢查前置條件..."

    # 檢查 kubectl
    if ! validate_command_exists "kubectl" "kubectl" "sudo snap install kubectl --classic"; then
        exit 1
    fi

    # 檢查 helm
    if ! validate_command_exists "helm" "Helm" "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"; then
        exit 1
    fi

    # 檢查 Kubernetes 連接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "無法連接到 Kubernetes 叢集"
        exit 1
    fi

    # 檢查 Prometheus chart
    if [ ! -d "$PROMETHEUS_CHART_DIR" ]; then
        log_error "Prometheus Helm chart 不存在: $PROMETHEUS_CHART_DIR"
        exit 1
    fi

    # 檢查 values 文件
    if [ ! -f "$VALUES_FILE" ]; then
        log_error "Prometheus values 檔案不存在: $VALUES_FILE"
        exit 1
    fi

    log_info "✓ 前置條件檢查通過"
    echo
}

# 檢查現有部署
check_existing_deployment() {
    log_step "檢查是否已部署 Prometheus..."

    if helm list -n $NAMESPACE | grep -q "$RELEASE_NAME"; then
        log_warn "Prometheus 已經部署 (release: $RELEASE_NAME)"
        echo -n "是否要升級現有部署？(y/N) "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "取消部署"
            exit 0
        fi
        UPGRADE_MODE=true
    else
        log_info "✓ 未檢測到現有部署，將進行全新安裝"
        UPGRADE_MODE=false
    fi
    echo
}

# 顯示配置摘要
show_configuration() {
    log_step "部署配置摘要"
    echo "  Prometheus Chart: $PROMETHEUS_CHART_DIR"
    echo "  Values File: $VALUES_FILE"
    echo "  Release Name: $RELEASE_NAME"
    echo "  Namespace: $NAMESPACE"
    echo "  Mode: $([ "$UPGRADE_MODE" = true ] && echo "Upgrade" || echo "Install")"
    echo
}

# 部署 Prometheus
deploy_prometheus() {
    log_step "部署 Prometheus Server..."

    if [ "$UPGRADE_MODE" = true ]; then
        log_info "執行 Helm upgrade..."
        helm upgrade $RELEASE_NAME $PROMETHEUS_CHART_DIR \
            --namespace $NAMESPACE \
            --values $VALUES_FILE \
            --wait \
            --timeout 600s
    else
        log_info "執行 Helm install..."
        helm install $RELEASE_NAME $PROMETHEUS_CHART_DIR \
            --namespace $NAMESPACE \
            --create-namespace \
            --values $VALUES_FILE \
            --wait \
            --timeout 600s
    fi

    if [ $? -eq 0 ]; then
        log_info "✓ Prometheus 部署成功"
    else
        log_error "✗ Prometheus 部署失敗"
        exit 1
    fi
    echo
}

# 驗證部署
verify_deployment() {
    log_step "驗證 Prometheus 部署..."

    # 等待 Pod 就緒
    log_info "等待 Prometheus Server Pod 就緒..."
    kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=prometheus,app.kubernetes.io/instance=$RELEASE_NAME" \
        -n $NAMESPACE \
        --timeout=300s

    if [ $? -eq 0 ]; then
        log_info "✓ Prometheus Server Pod 已就緒"
    else
        log_error "✗ Prometheus Server Pod 未能就緒"
        exit 1
    fi

    # 顯示 Pod 狀態
    echo
    log_info "Prometheus Pods 狀態:"
    kubectl get pods -n $NAMESPACE -l "app.kubernetes.io/instance=$RELEASE_NAME"
    echo

    # 顯示 Service 狀態
    log_info "Prometheus Services 狀態:"
    kubectl get svc -n $NAMESPACE -l "app.kubernetes.io/instance=$RELEASE_NAME"
    echo
}

# 測試 Prometheus API
test_prometheus_api() {
    log_step "測試 Prometheus API..."

    # 獲取 Prometheus Server Service
    PROM_SERVICE=$(kubectl get svc -n $NAMESPACE -l "app.kubernetes.io/name=prometheus-server,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
    PROM_CLUSTER_IP=$(kubectl get svc -n $NAMESPACE $PROM_SERVICE -o jsonpath='{.spec.clusterIP}')
    PROM_PORT=$(kubectl get svc -n $NAMESPACE $PROM_SERVICE -o jsonpath='{.spec.ports[0].port}')

    log_info "Prometheus Server: http://${PROM_CLUSTER_IP}:${PROM_PORT}"

    # 測試健康檢查
    log_info "測試 Prometheus 健康檢查..."
    HEALTH_CHECK=$(kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -- \
        curl -s "http://${PROM_CLUSTER_IP}:${PROM_PORT}/-/healthy" 2>/dev/null || echo "FAILED")

    if echo "$HEALTH_CHECK" | grep -q "Prometheus is Healthy"; then
        log_info "✓ Prometheus 健康檢查通過"
    else
        log_warn "⚠ Prometheus 健康檢查未返回預期結果"
        echo "  回應: $HEALTH_CHECK"
    fi
    echo
}

# 顯示訪問資訊
show_access_info() {
    log_step "Prometheus 訪問資訊"

    PROM_SERVICE=$(kubectl get svc -n $NAMESPACE -l "app.kubernetes.io/name=prometheus-server,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
    PROM_CLUSTER_IP=$(kubectl get svc -n $NAMESPACE $PROM_SERVICE -o jsonpath='{.spec.clusterIP}')
    PROM_PORT=$(kubectl get svc -n $NAMESPACE $PROM_SERVICE -o jsonpath='{.spec.ports[0].port}')

    echo
    echo "=================================================="
    echo "   Prometheus 部署完成"
    echo "=================================================="
    echo
    echo "Cluster 內部訪問:"
    echo "  URL: http://${PROM_CLUSTER_IP}:${PROM_PORT}"
    echo "  Service: ${PROM_SERVICE}.${NAMESPACE}.svc.cluster.local"
    echo
    echo "本機訪問 (需要執行 port-forward):"
    echo "  kubectl port-forward -n ${NAMESPACE} svc/${PROM_SERVICE} 9090:${PROM_PORT}"
    echo "  然後訪問: http://localhost:9090"
    echo
    echo "下一步操作:"
    echo "  1. 為 xApp 添加 Prometheus annotations (prometheus.io/scrape, prometheus.io/port, prometheus.io/path)"
    echo "  2. 確保 xApp 實作 /ric/v1/metrics 端點 (Prometheus 格式)"
    echo "  3. 重新部署 xApp 使 annotations 生效"
    echo "  4. 在 Prometheus UI 檢查 Targets 狀態"
    echo
}

# 主函數
main() {
    check_prerequisites
    check_existing_deployment
    show_configuration

    # 確認部署
    echo -n "確認執行部署？(y/N) "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "取消部署"
        exit 0
    fi
    echo

    deploy_prometheus
    verify_deployment
    test_prometheus_api
    show_access_info

    log_info "✓ Prometheus 監控系統部署完成"
}

# 執行主函數
main
