#!/bin/bash
#
# O-RAN RIC xApps Prometheus Metrics 更新部署腳本
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-15
#
# 用途: 重新構建並部署所有修改了 Prometheus metrics 端點的 xApps
#

set -e

# 動態解析專案根目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 驗證專案根目錄
if [ ! -f "$PROJECT_ROOT/README.md" ]; then
    echo "[ERROR] Cannot locate project root" >&2
    echo "Expected README.md at: $PROJECT_ROOT/README.md" >&2
    exit 1
fi

# 載入驗證函數庫
source "${PROJECT_ROOT}/scripts/lib/validation.sh"

# KUBECONFIG 標準化設定
if ! setup_kubeconfig; then
    exit 1
fi

echo "=================================================="
echo "   O-RAN RIC xApps Prometheus Metrics 更新部署"
echo "   作者: 蔡秀吉 (thc1006)"
echo "   日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
echo

# 函數：日誌輸出（使用 validation.sh 的函數）
log_step() {
    log_info "$1"
}

# xApp 列表
XAPPS=(
    "rc-xapp:ran-control:8100"
    "qoe-predictor:qoe-predictor:8090"
    "federated-learning:federated-learning:8110"
    "traffic-steering:traffic-steering:8080"
)

REGISTRY="localhost:5000"

# 統計變數
TOTAL=0
SUCCESS=0
FAILED=0

# 函數：構建並推送 Docker 映像
build_and_push() {
    local xapp_dir=$1
    local image_name=$2

    log_step "處理 $image_name..."

    cd "$PROJECT_ROOT/xapps/$xapp_dir"

    # 構建映像
    log_info "構建 Docker 映像..."
    if docker build -t $REGISTRY/xapp-$image_name:1.0.0 -t $REGISTRY/xapp-$image_name:latest -f Dockerfile . 2>&1 | tail -20; then
        log_info "✓ Docker 映像構建成功"
    else
        log_error "✗ Docker 映像構建失敗"
        return 1
    fi

    # 推送映像
    log_info "推送映像到本地 registry..."
    if docker push $REGISTRY/xapp-$image_name:1.0.0 && docker push $REGISTRY/xapp-$image_name:latest; then
        log_info "✓ Docker 映像推送成功"
    else
        log_error "✗ Docker 映像推送失敗"
        return 1
    fi

    echo
    return 0
}

# 函數：重新部署 xApp
redeploy_xapp() {
    local xapp_dir=$1
    local app_label=$2

    log_step "重新部署 $app_label..."

    # 刪除現有 Pod
    log_info "刪除現有 Pod..."
    if kubectl delete pod -n ricxapp -l app=$app_label --ignore-not-found=true; then
        log_info "✓ Pod 已刪除"
    else
        log_warn "⚠ Pod 刪除可能失敗，繼續執行"
    fi

    # 應用新的 deployment
    log_info "應用新的 deployment..."
    if kubectl apply -f "$PROJECT_ROOT/xapps/$xapp_dir/deploy/deployment.yaml"; then
        log_info "✓ Deployment 已更新"
    else
        log_error "✗ Deployment 更新失敗"
        return 1
    fi

    # 等待 Pod 就緒
    log_info "等待 Pod 就緒..."
    if kubectl wait --for=condition=ready pod -l app=$app_label -n ricxapp --timeout=120s; then
        log_info "✓ Pod 已就緒"
    else
        log_error "✗ Pod 未能在 120 秒內就緒"
        return 1
    fi

    echo
    return 0
}

# 函數：驗證 metrics 端點
verify_metrics() {
    local app_label=$1
    local port=$2

    log_step "驗證 $app_label metrics 端點..."

    # 獲取 Pod 名稱
    POD=$(kubectl get pod -n ricxapp -l app=$app_label -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$POD" ]; then
        log_error "✗ 找不到 Pod (label: app=$app_label)"
        return 1
    fi

    log_info "Pod: $POD"

    # 測試 /ric/v1/metrics 端點
    log_info "測試 /ric/v1/metrics 端點..."
    RESULT=$(kubectl exec -n ricxapp $POD -- curl -s http://localhost:$port/ric/v1/metrics 2>/dev/null | head -5 || echo "ERROR")

    if echo "$RESULT" | grep -q "# HELP"; then
        log_info "✓ Prometheus metrics 端點正常"
        echo "  前 5 行輸出:"
        echo "$RESULT" | sed 's/^/    /'
    else
        log_error "✗ Prometheus metrics 端點異常"
        echo "  回應: $RESULT"
        return 1
    fi

    # 檢查 annotations
    log_info "檢查 Prometheus annotations..."
    ANNOTATIONS=$(kubectl get pod -n ricxapp $POD -o jsonpath='{.metadata.annotations}' 2>/dev/null)

    if echo "$ANNOTATIONS" | grep -q "prometheus.io/scrape"; then
        log_info "✓ Prometheus annotations 已設定"
    else
        log_warn "⚠ Prometheus annotations 可能未設定"
    fi

    echo
    return 0
}

# 主流程
main() {
    log_step "開始處理 ${#XAPPS[@]} 個 xApps"
    echo

    # 階段 1: 構建並推送所有映像
    log_info "========== 階段 1: 構建 Docker 映像 =========="
    echo

    for xapp_info in "${XAPPS[@]}"; do
        IFS=':' read -r xapp_dir image_name port <<< "$xapp_info"
        TOTAL=$((TOTAL+1))

        if build_and_push "$xapp_dir" "$image_name"; then
            SUCCESS=$((SUCCESS+1))
        else
            FAILED=$((FAILED+1))
            log_error "xApp $image_name 構建失敗，但繼續處理其他 xApps"
        fi
    done

    echo
    log_info "========== 階段 2: 重新部署 xApps =========="
    echo

    # 重置統計
    TOTAL=0
    SUCCESS=0
    FAILED=0

    for xapp_info in "${XAPPS[@]}"; do
        IFS=':' read -r xapp_dir image_name port <<< "$xapp_info"
        TOTAL=$((TOTAL+1))

        if redeploy_xapp "$xapp_dir" "$image_name"; then
            SUCCESS=$((SUCCESS+1))
        else
            FAILED=$((FAILED+1))
            log_error "xApp $image_name 部署失敗，但繼續處理其他 xApps"
        fi
    done

    echo
    log_info "========== 階段 3: 驗證 Metrics 端點 =========="
    echo

    # 重置統計
    TOTAL=0
    SUCCESS=0
    FAILED=0

    for xapp_info in "${XAPPS[@]}"; do
        IFS=':' read -r xapp_dir image_name port <<< "$xapp_info"
        TOTAL=$((TOTAL+1))

        if verify_metrics "$image_name" "$port"; then
            SUCCESS=$((SUCCESS+1))
        else
            FAILED=$((FAILED+1))
        fi
    done

    # 最終統計
    echo
    echo "=================================================="
    echo "   部署結果總結"
    echo "=================================================="
    echo "總計: $TOTAL 個 xApps"
    echo -e "${GREEN}成功: $SUCCESS 個${NC}"
    if [ $FAILED -gt 0 ]; then
        echo -e "${RED}失敗: $FAILED 個${NC}"
    else
        echo "失敗: 0 個"
    fi
    echo

    if [ $FAILED -eq 0 ]; then
        log_info "✓ 所有 xApps 部署和驗證成功！"

        echo
        log_info "後續步驟:"
        echo "  1. 檢查 Prometheus Targets:"
        echo "     kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80"
        echo "     訪問: http://localhost:9090/targets"
        echo
        echo "  2. 查詢 xApp metrics:"
        echo "     在 Prometheus UI 中查詢: ts_handover_decisions_total, rc_control_actions_sent_total 等"
        echo

        exit 0
    else
        log_error "✗ 部分 xApps 部署或驗證失敗"
        echo
        echo "建議排查步驟:"
        echo "1. 檢查失敗的 xApp Pod 日誌: kubectl logs -n ricxapp <pod-name>"
        echo "2. 檢查 Pod 狀態: kubectl describe pod -n ricxapp <pod-name>"
        echo "3. 檢查 Docker 映像: docker images | grep xapp"

        exit 1
    fi
}

# 執行主函數
main
