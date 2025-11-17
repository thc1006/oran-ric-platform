#!/bin/bash
#
# O-RAN RIC Grafana Dashboard 匯入腳本
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-15
#
# Small CL #8: 匯入 Grafana Dashboard
#

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 動態解析專案根目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 驗證專案根目錄
if [ ! -f "$PROJECT_ROOT/README.md" ]; then
    echo -e "${RED}[ERROR]${NC} Cannot locate project root" >&2
    echo "Expected README.md at: $PROJECT_ROOT/README.md" >&2
    exit 1
fi

GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="oran-ric-admin"
DASHBOARD_DIR="${PROJECT_ROOT}/config/dashboards"

echo "======================================"
echo "   Grafana Dashboard 匯入"
echo "   作者: 蔡秀吉 (thc1006)"
echo "   日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================"
echo

# 匯入 Dashboard
import_dashboard() {
    local file=$1
    local name=$2

    echo -e "${BLUE}[資訊]${NC} 匯入 ${name}..."

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
        -d @"${file}" \
        "${GRAFANA_URL}/api/dashboards/db")

    status=$(echo "$response" | jq -r '.status // "error"')

    if [ "$status" = "success" ]; then
        uid=$(echo "$response" | jq -r '.uid')
        url=$(echo "$response" | jq -r '.url')
        echo -e "${GREEN}[成功]${NC} ${name} 匯入成功"
        echo "         UID: ${uid}"
        echo "         URL: ${GRAFANA_URL}${url}"
        echo
        return 0
    else
        echo -e "\033[0;31m[錯誤]\033[0m ${name} 匯入失敗"
        echo "$response" | jq '.'
        echo
        return 1
    fi
}

# 匯入所有 Dashboard
echo "開始匯入 Dashboard..."
echo

import_dashboard "${DASHBOARD_DIR}/oran-ric-overview.json" "O-RAN RIC Platform Overview"
import_dashboard "${DASHBOARD_DIR}/rc-xapp-dashboard.json" "RC xApp Monitoring"
import_dashboard "${DASHBOARD_DIR}/traffic-steering-dashboard.json" "Traffic Steering xApp"
import_dashboard "${DASHBOARD_DIR}/qoe-predictor-dashboard.json" "QoE Predictor xApp"
import_dashboard "${DASHBOARD_DIR}/federated-learning-dashboard.json" "Federated Learning xApp"
import_dashboard "${DASHBOARD_DIR}/kpimon-dashboard.json" "KPIMON xApp"

echo "======================================"
echo "所有 Dashboard 匯入完成！"
echo
echo "存取 Grafana:"
echo "  http://localhost:3000"
echo
echo "登入資訊:"
echo "  帳號: admin"
echo "  密碼: oran-ric-admin"
echo "======================================"

exit 0
