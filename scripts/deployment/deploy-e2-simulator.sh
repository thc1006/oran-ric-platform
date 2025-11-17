#!/bin/bash
#
# E2 Simulator 部署腳本
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-15
#
# 用途: 構建並部署 E2 Simulator 來生成測試流量
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

SIMULATOR_DIR="${PROJECT_ROOT}/simulator/e2-simulator"
REGISTRY="localhost:5000"

echo "=================================================="
echo "   E2 Simulator 部署"
echo "   作者: 蔡秀吉 (thc1006)"
echo "   日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
echo

# Step 1: 重新構建 KPIMON (添加了 HTTP endpoint)
echo -e "${BLUE}[STEP 1]${NC} 重新構建 KPIMON (添加 HTTP endpoint)..."
cd "${PROJECT_ROOT}/xapps/kpimon-go-xapp"

docker build -t ${REGISTRY}/xapp-kpimon:1.0.1 -f Dockerfile .
docker tag ${REGISTRY}/xapp-kpimon:1.0.1 ${REGISTRY}/xapp-kpimon:latest
docker push ${REGISTRY}/xapp-kpimon:1.0.1
docker push ${REGISTRY}/xapp-kpimon:latest

echo -e "${GREEN}[SUCCESS]${NC} KPIMON 映像已更新"
echo

# Step 2: 構建 E2 Simulator
echo -e "${BLUE}[STEP 2]${NC} 構建 E2 Simulator Docker 映像..."
cd "${SIMULATOR_DIR}"

docker build -t ${REGISTRY}/e2-simulator:1.0.0 -f Dockerfile .
docker tag ${REGISTRY}/e2-simulator:1.0.0 ${REGISTRY}/e2-simulator:latest
docker push ${REGISTRY}/e2-simulator:1.0.0
docker push ${REGISTRY}/e2-simulator:latest

echo -e "${GREEN}[SUCCESS]${NC} E2 Simulator 映像已構建並推送"
echo

# Step 3: 重啟 KPIMON
echo -e "${BLUE}[STEP 3]${NC} 重啟 KPIMON xApp..."

# Delete old pod
kubectl delete pod -n ricxapp -l app=kpimon --ignore-not-found=true

# Update deployment with new image
kubectl set image deployment/kpimon -n ricxapp \
  kpimon=${REGISTRY}/xapp-kpimon:1.0.1

# Wait for pod to be ready
echo "等待 KPIMON Pod 就緒..."
kubectl wait --for=condition=ready pod -l app=kpimon -n ricxapp --timeout=120s

KPIMON_POD=$(kubectl get pod -n ricxapp -l app=kpimon -o jsonpath='{.items[0].metadata.name}')
echo -e "${GREEN}[SUCCESS]${NC} KPIMON Pod 已就緒: ${KPIMON_POD}"
echo

# Step 4: 部署 E2 Simulator
echo -e "${BLUE}[STEP 4]${NC} 部署 E2 Simulator..."

# 先刪除已有的 deployment (如果存在)
kubectl delete deployment e2-simulator -n ricxapp --ignore-not-found=true
sleep 2

# 應用新的 deployment
kubectl apply -f "${SIMULATOR_DIR}/deploy/deployment.yaml"

echo "等待 E2 Simulator Pod 就緒..."
kubectl wait --for=condition=ready pod -l app=e2-simulator -n ricxapp --timeout=60s

E2SIM_POD=$(kubectl get pod -n ricxapp -l app=e2-simulator -o jsonpath='{.items[0].metadata.name}')
echo -e "${GREEN}[SUCCESS]${NC} E2 Simulator Pod 已就緒: ${E2SIM_POD}"
echo

# Step 5: 驗證部署
echo -e "${BLUE}[STEP 5]${NC} 驗證部署..."
echo

echo "KPIMON 狀態:"
kubectl get pod -n ricxapp -l app=kpimon
echo

echo "E2 Simulator 狀態:"
kubectl get pod -n ricxapp -l app=e2-simulator
echo

# Step 6: 查看 Simulator 日誌
echo -e "${BLUE}[STEP 6]${NC} 查看 E2 Simulator 初始日誌..."
echo
kubectl logs -n ricxapp ${E2SIM_POD} --tail=20
echo

echo "=================================================="
echo "   部署完成！"
echo "=================================================="
echo
echo "後續步驟:"
echo "  1. 監控 E2 Simulator 日誌:"
echo "     kubectl logs -f -n ricxapp ${E2SIM_POD}"
echo
echo "  2. 查看 KPIMON metrics 是否開始增長:"
echo "     kubectl exec -n ricxapp ${KPIMON_POD} -- python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:8080/ric/v1/metrics').read().decode())\" | grep kpimon_messages"
echo
echo "  3. 查詢 Prometheus 驗證 metrics:"
echo "     curl -s 'http://localhost:9090/api/v1/query?query=kpimon_messages_received_total'"
echo
echo "  4. 訪問 Grafana 查看 Dashboard:"
echo "     http://localhost:3000/d/978278f4/kpimon-xapp"
echo

exit 0
