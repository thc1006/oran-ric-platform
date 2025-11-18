#!/bin/bash
#
# 構建剩餘的 xApp 映像
# 作者：蔡秀吉 (thc1006)
#

set -e

cd /home/thc1006/oran-ric-platform

echo "=== 構建剩餘映像 ==="
echo ""

# QoE Predictor (如果還沒完成)
echo "1. 檢查 QoE Predictor..."
if ! curl -s http://localhost:5000/v2/xapp-qoe-predictor/tags/list | grep -q "1.0.0"; then
    echo "   構建 QoE Predictor..."
    cd xapps/qoe-predictor
    docker build -t localhost:5000/xapp-qoe-predictor:1.0.0 .
    docker push localhost:5000/xapp-qoe-predictor:1.0.0
    cd ../..
else
    echo "   ✅ QoE Predictor 已存在"
fi

# Federated Learning
echo "2. 構建 Federated Learning..."
cd xapps/federated-learning
docker build -t localhost:5000/xapp-federated-learning:1.0.0 .
docker push localhost:5000/xapp-federated-learning:1.0.0
cd ../..
echo "   ✅ Federated Learning 完成"

# E2 Simulator
echo "3. 構建 E2 Simulator..."
cd simulator/e2-simulator
docker build -t localhost:5000/e2-simulator:1.0.0 .
docker push localhost:5000/e2-simulator:1.0.0
cd ../..
echo "   ✅ E2 Simulator 完成"

echo ""
echo "=== 驗證所有映像 ==="
curl -s http://localhost:5000/v2/_catalog | python3 -m json.tool

echo ""
echo "✅ 所有映像構建完成！"
echo ""
echo "下一步：執行 Wednesday 部署"
echo "  sudo bash scripts/wednesday-safe-deploy.sh"
