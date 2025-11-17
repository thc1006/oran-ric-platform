#!/bin/bash
#
# O-RAN RIC xApps 健康檢查驗證腳本
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-15
#
# 用途: 驗證所有 xApp 的健康狀態
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
echo "   O-RAN RIC xApps 健康檢查驗證"
echo "   作者: 蔡秀吉 (thc1006)"
echo "   日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
echo

# 檢查 kubectl 命令
if ! validate_command_exists "kubectl" "kubectl" "sudo snap install kubectl --classic"; then
    exit 1
fi

echo "=== 1. 檢查所有 xApp Pod 狀態 ==="
echo
kubectl get pods -n ricxapp
echo

echo "=== 2. 測試各 xApp 健康檢查端點 ==="
echo

# 函數：測試健康檢查
test_health() {
    local app_name=$1
    local app_label=$2
    local port=$3
    local alive_path=$4
    local ready_path=$5

    echo "----------------------------------------"
    echo -e "${YELLOW}測試 $app_name (port $port)${NC}"

    # 獲取 Pod 名稱
    POD=$(kubectl get pod -n ricxapp -l app=$app_label -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$POD" ]; then
        echo -e "${RED}✗ 錯誤: 找不到 Pod (label: app=$app_label)${NC}"
        return 1
    fi

    echo "Pod: $POD"

    # 測試 alive 端點
    echo -n "測試 $alive_path ... "
    ALIVE_RESULT=$(kubectl exec -n ricxapp $POD -- curl -s http://localhost:$port$alive_path 2>/dev/null || echo "ERROR")

    if echo "$ALIVE_RESULT" | grep -q '"status":"alive"'; then
        echo -e "${GREEN}✓ OK${NC}"
        echo "  回應: $ALIVE_RESULT"
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo "  回應: $ALIVE_RESULT"
        return 1
    fi

    # 測試 ready 端點
    echo -n "測試 $ready_path ... "
    READY_RESULT=$(kubectl exec -n ricxapp $POD -- curl -s http://localhost:$port$ready_path 2>/dev/null || echo "ERROR")

    if echo "$READY_RESULT" | grep -q '"status":"ready"'; then
        echo -e "${GREEN}✓ OK${NC}"
        echo "  回應: $READY_RESULT"
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo "  回應: $READY_RESULT"
        return 1
    fi

    echo -e "${GREEN}✓ $app_name 健康檢查通過${NC}"
    echo
}

# 測試結果統計
TOTAL=0
PASSED=0
FAILED=0

# 測試 KPIMON xApp
TOTAL=$((TOTAL+1))
if test_health "KPIMON xApp" "kpimon" "8081" "/health/alive" "/health/ready"; then
    PASSED=$((PASSED+1))
else
    FAILED=$((FAILED+1))
fi

# 測試 RC xApp
TOTAL=$((TOTAL+1))
if test_health "RC (RAN Control) xApp" "ran-control" "8100" "/health/alive" "/health/ready"; then
    PASSED=$((PASSED+1))
else
    FAILED=$((FAILED+1))
fi

# 測試 QoE Predictor xApp
TOTAL=$((TOTAL+1))
if test_health "QoE Predictor xApp" "qoe-predictor" "8090" "/health/alive" "/health/ready"; then
    PASSED=$((PASSED+1))
else
    FAILED=$((FAILED+1))
fi

# 測試 Traffic Steering xApp (不同的路徑)
TOTAL=$((TOTAL+1))
if test_health "Traffic Steering xApp" "traffic-steering" "8080" "/ric/v1/health/alive" "/ric/v1/health/ready"; then
    PASSED=$((PASSED+1))
else
    FAILED=$((FAILED+1))
fi

# 測試 Federated Learning xApp
TOTAL=$((TOTAL+1))
if test_health "Federated Learning xApp" "federated-learning" "8110" "/health/alive" "/health/ready"; then
    PASSED=$((PASSED+1))
else
    FAILED=$((FAILED+1))
fi

echo "=================================================="
echo "   驗證結果總結"
echo "=================================================="
echo "總計: $TOTAL 個 xApp"
echo -e "${GREEN}通過: $PASSED 個${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}失敗: $FAILED 個${NC}"
else
    echo "失敗: 0 個"
fi
echo

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有 xApp 健康檢查通過！${NC}"
    exit 0
else
    echo -e "${RED}✗ 部分 xApp 健康檢查失敗，請檢查日誌${NC}"
    echo
    echo "建議排查步驟:"
    echo "1. 檢查失敗的 Pod 日誌: kubectl logs -n ricxapp <pod-name>"
    echo "2. 檢查 Pod 狀態: kubectl describe pod -n ricxapp <pod-name>"
    echo "3. 檢查 Pod 事件: kubectl get events -n ricxapp --sort-by='.lastTimestamp'"
    exit 1
fi
