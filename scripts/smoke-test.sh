#!/bin/bash
#
# O-RAN RIC Platform Smoke Test
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-17
#
# 用途: 快速驗證部署後的系統健康狀態
# 使用方式: sudo bash scripts/smoke-test.sh
#

set -eo pipefail

# 動態解析專案根目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 載入驗證函數庫
source "${PROJECT_ROOT}/scripts/lib/validation.sh"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 統計變數
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# ============================================================================
# 檢查函數
# ============================================================================
check() {
    local name=$1
    local command=$2
    local is_critical=${3:-true}  # 預設為關鍵檢查

    ((TOTAL_CHECKS++))

    echo -n "檢查 $name ... "
    if eval "$command" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED_CHECKS++))
        return 0
    else
        if [ "$is_critical" = "true" ]; then
            echo -e "${RED}✗ (關鍵)${NC}"
        else
            echo -e "${YELLOW}✗ (非關鍵)${NC}"
        fi
        ((FAILED_CHECKS++))
        return 1
    fi
}

# ============================================================================
# 測試套件
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  O-RAN RIC Platform Smoke Test${NC}"
echo -e "${BLUE}  作者: 蔡秀吉 (thc1006)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 0. KUBECONFIG 設定檢查
echo -e "${YELLOW}[0/7] KUBECONFIG 設定檢查${NC}"
echo -n "檢查 KUBECONFIG 設定 ... "
if setup_kubeconfig &> /dev/null; then
    echo -e "${GREEN}✓${NC}"
    echo "  使用: $KUBECONFIG"
    ((PASSED_CHECKS++))
else
    echo -e "${RED}✗ (關鍵)${NC}"
    echo "  錯誤: 無法設定 KUBECONFIG"
    echo "  請檢查: 1) kubectl 已安裝 2) Kubernetes 集群運行中 3) 配置檔案存在"
    ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))
echo ""

# 1. 基礎工具檢查
echo -e "${YELLOW}[1/7] 基礎工具檢查${NC}"
check "kubectl 可用" "command -v kubectl"
check "helm 可用" "command -v helm"
check "docker 可用" "command -v docker"
echo ""

# 2. K8s 集群連通性
echo -e "${YELLOW}[2/7] Kubernetes 集群檢查${NC}"
check "集群連通" "kubectl cluster-info"
check "節點就緒" "kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
echo ""

# 3. 命名空間檢查
echo -e "${YELLOW}[3/7] RIC Namespaces 檢查${NC}"
check "ricplt namespace 存在" "kubectl get namespace ricplt"
check "ricxapp namespace 存在" "kubectl get namespace ricxapp"
check "ricobs namespace 存在" "kubectl get namespace ricobs" false  # 非關鍵
echo ""

# 4. 監控系統檢查
echo -e "${YELLOW}[4/7] 監控系統檢查${NC}"
check "Prometheus Pod Running" "kubectl get pod -n ricplt -l app=prometheus,component=server -o jsonpath='{.items[0].status.phase}' | grep -q Running"
check "Grafana Pod Running" "kubectl get pod -n ricplt -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.phase}' | grep -q Running"
check "Prometheus Service 存在" "kubectl get service -n ricplt -l app=prometheus"
check "Grafana Service 存在" "kubectl get service -n ricplt oran-grafana"
echo ""

# 5. xApps 檢查
echo -e "${YELLOW}[5/7] xApps 檢查${NC}"
check "KPIMON Pod Running" "kubectl get pod -n ricxapp -l app=kpimon -o jsonpath='{.items[0].status.phase}' | grep -q Running"
check "Traffic Steering Pod Running" "kubectl get pod -n ricxapp -l app=traffic-steering -o jsonpath='{.items[0].status.phase}' | grep -q Running"
check "RC xApp Pod Running" "kubectl get pod -n ricxapp -l app=ran-control -o jsonpath='{.items[0].status.phase}' | grep -q Running"
check "QoE Predictor Pod Running" "kubectl get pod -n ricxapp -l app=qoe-predictor -o jsonpath='{.items[0].status.phase}' | grep -q Running" false
check "Federated Learning Pod Running" "kubectl get pod -n ricxapp -l app=federated-learning -o jsonpath='{.items[0].status.phase}' | grep -q Running" false
echo ""

# 6. E2 Simulator 檢查
echo -e "${YELLOW}[6/7] E2 Simulator 檢查${NC}"
check "E2 Simulator Pod Running" "kubectl get pod -n ricxapp -l app=e2-simulator -o jsonpath='{.items[0].status.phase}' | grep -q Running" false
if kubectl get pod -n ricxapp -l app=e2-simulator &> /dev/null; then
    check "E2 Simulator 產生數據" "kubectl logs -n ricxapp -l app=e2-simulator --tail=10 | grep -q 'Iteration'" false
fi
echo ""

# ============================================================================
# 結果報告
# ============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  測試結果${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "總檢查數: $TOTAL_CHECKS"
echo -e "${GREEN}通過: $PASSED_CHECKS${NC}"
echo -e "${RED}失敗: $FAILED_CHECKS${NC}"
echo ""

# 計算成功率
SUCCESS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}✓ 所有檢查通過！系統運行正常。${NC}"
    exit 0
elif [ $SUCCESS_RATE -ge 80 ]; then
    echo -e "${YELLOW}⚠ 部分非關鍵檢查失敗，系統基本可用。${NC}"
    echo ""
    echo "建議："
    echo "1. 檢查失敗項目的 Pod 日誌: kubectl logs -n ricxapp <pod-name>"
    echo "2. 查看詳細故障排除指南: docs/deployment/TROUBLESHOOTING.md"
    exit 0
else
    echo -e "${RED}✗ 多個關鍵檢查失敗，系統可能不可用。${NC}"
    echo ""
    echo "故障排除步驟："
    echo "1. 檢查所有 Pod 狀態:"
    echo "   kubectl get pods -n ricplt"
    echo "   kubectl get pods -n ricxapp"
    echo ""
    echo "2. 查看失敗 Pod 的日誌:"
    echo "   kubectl logs -n <namespace> <pod-name>"
    echo ""
    echo "3. 查看 Pod 事件:"
    echo "   kubectl describe pod -n <namespace> <pod-name>"
    echo ""
    echo "4. 參考故障排除指南:"
    echo "   docs/deployment/TROUBLESHOOTING.md"
    exit 1
fi
