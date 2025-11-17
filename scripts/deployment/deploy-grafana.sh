#!/bin/bash
#
# O-RAN RIC Grafana 部署腳本
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-15
#
# Small CL #7: 部署 Grafana 到 Kubernetes
#

set -e

# 動態解析專案根目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

echo "======================================"
echo "   O-RAN RIC Grafana 部署"
echo "   作者: 蔡秀吉 (thc1006)"
echo "   日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================"
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
log_step "檢查前置條件..."

# 檢查 kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl 未安裝"
    exit 1
fi
log_info "✓ kubectl 已安裝"

# 檢查 helm
if ! command -v helm &> /dev/null; then
    log_error "helm 未安裝"
    exit 1
fi
log_info "✓ helm 已安裝"

# 檢查 Kubernetes 叢集
if ! kubectl cluster-info &> /dev/null; then
    log_error "無法連接到 Kubernetes 叢集"
    exit 1
fi
log_info "✓ Kubernetes 叢集可訪問"

# 檢查 Prometheus 是否運行
PROM_POD=$(kubectl get pod -n ricplt -l app=prometheus,component=server -o name 2>/dev/null | head -1)
if [ -z "$PROM_POD" ]; then
    log_error "Prometheus Server 未運行，請先部署 Prometheus"
    exit 1
fi
log_info "✓ Prometheus Server 正在運行"

echo

# 添加 Grafana Helm repository
log_step "添加 Grafana Helm repository..."
if helm repo list | grep -q "^grafana"; then
    log_info "Grafana repository 已存在，更新中..."
    helm repo update grafana
else
    log_info "添加 Grafana repository..."
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
fi
log_info "✓ Grafana Helm repository 已準備"

echo

# 檢查是否已部署
log_step "檢查現有部署..."
if helm list -n ricplt | grep -q "^oran-grafana"; then
    log_warn "Grafana 已部署，是否要升級？(y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log_info "升級現有 Grafana..."
        helm upgrade oran-grafana grafana/grafana \
            -n ricplt \
            -f "${PROJECT_ROOT}/config/grafana-values.yaml" \
            --wait
        log_info "✓ Grafana 升級完成"
    else
        log_info "跳過部署"
        exit 0
    fi
else
    # 部署 Grafana
    log_step "部署 Grafana..."
    helm install oran-grafana grafana/grafana \
        -n ricplt \
        -f "${PROJECT_ROOT}/config/grafana-values.yaml" \
        --wait \
        --timeout 5m
    log_info "✓ Grafana 部署完成"
fi

echo

# 等待 Pod 就緒
log_step "等待 Grafana Pod 就緒..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=grafana \
    -n ricplt \
    --timeout=300s

log_info "✓ Grafana Pod 已就緒"

echo

# 獲取 Grafana 資訊
log_step "獲取 Grafana 資訊..."

POD_NAME=$(kubectl get pods -n ricplt -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
log_info "Pod 名稱: $POD_NAME"

# 獲取管理員密碼
ADMIN_PASSWORD=$(kubectl get secret -n ricplt oran-grafana -o jsonpath='{.data.admin-password}' | base64 --decode)
log_info "管理員帳號: admin"
log_info "管理員密碼: $ADMIN_PASSWORD"

echo

# 驗證部署
log_step "驗證 Grafana 部署..."

# 檢查 Pod 狀態
POD_STATUS=$(kubectl get pod -n ricplt -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.phase}')
if [ "$POD_STATUS" == "Running" ]; then
    log_info "✓ Grafana Pod 狀態: Running"
else
    log_error "✗ Grafana Pod 狀態: $POD_STATUS"
    exit 1
fi

# 檢查 Service
SERVICE_NAME=$(kubectl get svc -n ricplt -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
SERVICE_PORT=$(kubectl get svc -n ricplt -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].spec.ports[0].port}')
log_info "✓ Grafana Service: $SERVICE_NAME:$SERVICE_PORT"

# 測試 Grafana API
log_info "測試 Grafana API..."
sleep 5
if kubectl exec -n ricplt $POD_NAME -- wget -qO- http://localhost:3000/api/health 2>/dev/null | grep -q "ok"; then
    log_info "✓ Grafana API 正常回應"
else
    log_warn "⚠ Grafana API 可能尚未就緒，請稍後再試"
fi

# 測試 Prometheus 數據源
log_info "測試 Prometheus 數據源連接..."
sleep 2
if kubectl exec -n ricplt $POD_NAME -- wget -qO- http://r4-infrastructure-prometheus-server.ricplt:80/api/v1/status/config 2>/dev/null | grep -q "status"; then
    log_info "✓ Prometheus 數據源可訪問"
else
    log_warn "⚠ Prometheus 數據源連接可能有問題"
fi

echo

# 顯示訪問資訊
log_info "========== Grafana 部署成功 =========="
echo
echo "訪問 Grafana UI:"
echo "  1. 啟動 Port-Forward:"
echo "     kubectl port-forward -n ricplt svc/$SERVICE_NAME 3000:80"
echo
echo "  2. 在瀏覽器訪問:"
echo "     http://localhost:3000"
echo
echo "  3. 登入資訊:"
echo "     帳號: admin"
echo "     密碼: $ADMIN_PASSWORD"
echo
echo "下一步:"
echo "  - Small CL #8: 創建 Grafana Dashboard"
echo "  - 執行: kubectl port-forward -n ricplt svc/$SERVICE_NAME 3000:80"
echo
echo "======================================"

exit 0
