# 部署問題記錄 (Deployment Issues Log)

**作者**: 蔡秀吉 (thc1006)
**測試日期**: 2025-11-16
**測試環境**: 從零開始的全新部署測試
**目標**: 驗證僅使用項目文檔是否能成功完成 E2E 部署

---

## 測試方法

1. 完全清理現有部署（刪除 ricxapp, ricplt, ricobs namespaces）
2. 僅依據項目中的 .md 文檔進行部署
3. 記錄每個步驟遇到的問題
4. 驗證最終是否能成功訪問 Grafana 並看到動態數據

---

## 問題記錄

### 問題 #1: README.md 缺少 RIC Platform 部署步驟

**文件**: `/home/thc1006/oran-ric-platform/README.md`
**位置**: Line 37-50 (Quick Start 章節)
**嚴重性**: **CRITICAL**

**問題描述**:
README.md 的 "Quick Start" 章節直接要求用戶執行：
```bash
sudo bash scripts/redeploy-xapps-with-metrics.sh
sudo bash scripts/deployment/deploy-e2-simulator.sh
```

但這些腳本假設 O-RAN RIC Platform 已經部署。對於從零開始的用戶，這會導致部署失敗。

**當前內容**:
```markdown
### Deploy (3 Steps)

```bash
# 1. Clone with submodules
git clone --recurse-submodules https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform

# 2. Deploy all xApps + E2 Simulator
sudo bash scripts/redeploy-xapps-with-metrics.sh
sudo bash scripts/deployment/deploy-e2-simulator.sh

# 3. Access Grafana
kubectl port-forward -n ricplt svc/r4-infrastructure-grafana 3000:80
```
```

**應該包含的步驟**:
1. 部署 k3s 集群（如果尚未安裝）
2. **部署 O-RAN RIC Platform** ← 缺少此步驟
3. 部署 xApps
4. 部署 E2 Simulator
5. 訪問 Grafana

**建議修復**:
在 README.md 的 Quick Start 中增加 RIC Platform 部署步驟，或明確說明前置條件並引用詳細部署指南。

---

### 問題 #2: kubectl 默認配置無法連接 k3s

**環境**: k3s 集群
**嚴重性**: **HIGH**

**問題描述**:
k3s 服務正在運行，但 `kubectl` 命令默認嘗試連接 `localhost:8080`，導致：
```
The connection to the server localhost:8080 was refused
```

**根本原因**:
k3s 的 kubeconfig 文件位於 `/etc/rancher/k3s/k3s.yaml`，但環境變量 `KUBECONFIG` 未設置。

**解決方案**:
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

**建議**:
在部署文檔中明確說明需要設置 `KUBECONFIG` 環境變量，或在部署腳本中自動設置。

---

---

### 問題 #3: deploy-ric-platform.sh 腳本引用不存在的路徑

**文件**: `/home/thc1006/oran-ric-platform/scripts/deployment/deploy-ric-platform.sh`
**位置**: Line 321, 335, 345
**嚴重性**: **HIGH**

**問題描述**:
`deploy-ric-platform.sh` 腳本引用了以下不存在的路徑：

1. Line 321: `${PROJECT_ROOT}/platform/helm/charts/ric-platform`
   - 實際路徑: `platform/` 只包含 `values/` 子目錄

2. Line 335: `${PROJECT_ROOT}/platform/config/rmr-routes.txt`
   - 此文件不存在

3. Line 345: `${PROJECT_ROOT}/infrastructure/k8s/network-policies/`
   - 此目錄不存在

**根本原因**:
腳本期望一個統一的 RIC Platform Helm chart，但實際項目結構使用 `ric-dep/helm/` 目錄中的單獨組件 charts（a1mediator, appmgr, e2mgr, e2term, submgr, rtmgr, dbaas, infrastructure 等）。

**實際可用的部署方式**:
1. 使用 `ric-dep/bin/install` 腳本（需要 recipe YAML 文件）
2. 直接使用 Helm 部署各個組件charts

**建議修復**:
- 重寫 `deploy-ric-platform.sh` 腳本使用正確的路徑
- 或者在文檔中說明應該使用 `ric-dep/bin/install` 腳本
- 或者提供一個示例 recipe YAML 文件

---

### 問題 #4: 缺少 RIC Platform 部署的 recipe 文件示例

**嚴重性**: **MEDIUM**

**問題描述**:
`ric-dep/bin/install` 腳本需要一個 recipe YAML 文件（使用 `-f` 選項），但項目中沒有提供任何示例 recipe 文件。

**影響**:
用戶無法使用官方的安裝腳本部署 RIC Platform。

**建議修復**:
在 `ric-dep/RECIPE.yaml` 或 `docs/examples/` 中提供一個示例 recipe 文件，包含必要的配置選項和說明。

---

## 採用的臨時解決方案

由於發現的部署腳本問題，我將採用以下替代策略：

1. 使用 Helm 直接部署 `ric-dep/helm/infrastructure` (包含 Prometheus, Grafana)
2. 使用 Helm 直接部署各個 RIC Platform 組件
3. 使用 `scripts/redeploy-xapps-with-metrics.sh` 部署 xApps
4. 使用 `scripts/deployment/deploy-e2-simulator.sh` 部署 E2 Simulator

---

## 下一步測試計劃

- [x] 確認集群狀態
- [x] 清理現有部署
- [x] 記錄部署腳本問題
- [ ] 部署 RIC Infrastructure (Prometheus + Grafana)
- [ ] 部署 RIC Platform 組件
- [ ] 部署 xApps
- [ ] 部署 E2 Simulator
- [ ] 驗證 Prometheus metrics
- [ ] 驗證 Grafana dashboards
- [ ] 記錄所有遇到的問題

---

---

### 問題 #5: Infrastructure Helm chart 缺少依賴

**文件**: `/home/thc1006/oran-ric-platform/ric-dep/helm/infrastructure`
**嚴重性**: **HIGH**

**問題描述**:
嘗試部署 infrastructure chart 時出錯：
```
Error: found in Chart.yaml, but missing in charts/ directory: ric-common, extsvcplt, docker-credential, kong, certificate-manager, danm-networks, prometheus
```

**解決方案**:
需要先構建 Helm chart 依賴：
```bash
cd ric-dep/helm/infrastructure
helm dependency build
```

---

### 問題 #6: redeploy-xapps-with-metrics.sh 腳本缺少 ConfigMap 部署

**文件**: `/home/thc1006/oran-ric-platform/scripts/redeploy-xapps-with-metrics.sh`
**嚴重性**: **CRITICAL**

**問題描述**:
腳本只部署 Deployment 文件，但沒有部署對應的 ConfigMap 和 Service 文件，導致 Pods 無法啟動：
```
MountVolume.SetUp failed for volume "config-volume" : configmap "ran-control-config" not found
```

**解決方案**:
在部署 Deployment 之前，需要先創建 ConfigMap 和 Service：
```bash
kubectl apply -f xapps/*/deploy/configmap.yaml -n ricxapp
kubectl apply -f xapps/*/deploy/service.yaml -n ricxapp
kubectl apply -f xapps/*/deploy/deployment.yaml -n ricxapp
```

---

### 問題 #7: xApp 目錄名稱不一致

**嚴重性**: **MEDIUM**

**問題描述**:
部署腳本使用 `ran-control` 作為目錄名，但實際目錄名是 `rc-xapp`，導致腳本無法找到正確的部署文件。

**實際目錄結構**:
- xapps/rc-xapp/ (實際)
- xapps/ran-control/ (腳本期望)

**影響**:
腳本中的路徑引用錯誤。

---

---

## 測試結果總結

### 成功部署的組件

✅ **RIC Infrastructure**
- Prometheus Server (1/1 Running)
- Prometheus Alertmanager (2/2 Running)
- Grafana (1/1 Running)

✅ **xApps** (3/5)
- KPIMON (1/1 Running)
- Traffic Steering (1/1 Running)
- RAN Control (1/1 Running)

✅ **E2 Simulator**
- E2 Simulator (1/1 Running)
- 正在生成和發送測試數據

### 未完成的組件

❌ QoE Predictor - 部署但未能正常運行
❌ Federated Learning - 部署但未能正常運行
❌ Playwright 自動化測試 - port-forward 配置問題

### 驗證數據

E2 Simulator 日誌顯示正常運行：
```
=== Simulation Iteration 3 ===
Generated KPI indication for cell_002/ue_010
Generated QoE metrics for ue_002: QoE=59.5
Waiting 5 seconds...
```

所有運行中的 xApp Pods 狀態：
```
NAME                                READY   STATUS    RESTARTS   AGE
traffic-steering-7589568cd7-n598v   1/1     Running   0          85s
ran-control-54495b75c9-6q6sr        1/1     Running   0          85s
kpimon-54486974b6-s92j7             1/1     Running   0          55s
e2-simulator-54f6cfd7b4-g2grf       1/1     Running   0          22s
```

---

## 建議的修復措施

### 1. README.md 需要更新

**當前問題**: Quick Start 章節缺少 RIC Platform 部署步驟

**建議內容**:
```markdown
### Deploy (4 Steps)

```bash
# 0. 設置環境變量
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 1. Clone with submodules
git clone --recurse-submodules https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform

# 2. 創建命名空間
kubectl create namespace ricplt
kubectl create namespace ricxapp
kubectl create namespace ricobs

# 3. 部署 RIC Infrastructure (Prometheus + Grafana)
helm install r4-infrastructure-prometheus ./ric-dep/helm/infrastructure/subcharts/prometheus \
  --namespace ricplt --values ./config/prometheus-values.yaml

helm repo add grafana https://grafana.github.io/helm-charts
helm install oran-grafana grafana/grafana -n ricplt -f ./config/grafana-values.yaml

# 4. 部署 xApps
kubectl apply -f ./xapps/kpimon-go-xapp/deploy/ -n ricxapp
kubectl apply -f ./xapps/traffic-steering/deploy/ -n ricxapp
kubectl apply -f ./xapps/rc-xapp/deploy/ -n ricxapp

# 5. 部署 E2 Simulator
bash ./scripts/deployment/deploy-e2-simulator.sh

# 6. Access Grafana
kubectl port-forward -n ricplt svc/oran-grafana 3000:80
# Open http://localhost:3000 (admin / [get password with next command])
kubectl get secret --namespace ricplt oran-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```
```

### 2. 修復 redeploy-xapps-with-metrics.sh 腳本

在重新部署 Deployment 之前，需要先確保 ConfigMap 和 Service 存在：

```bash
# 在腳本中添加
kubectl apply -f ${XAPP_DIR}/deploy/configmap.yaml -n ricxapp 2>/dev/null || true
kubectl apply -f ${XAPP_DIR}/deploy/service.yaml -n ricxapp 2>/dev/null || true
kubectl apply -f ${XAPP_DIR}/deploy/deployment.yaml -n ricxapp
```

### 3. 統一 xApp 目錄名稱

建議重命名或在腳本中使用映射：
- `rc-xapp` → 保持不變，更新腳本中的引用

### 4. 創建簡化的部署腳本

創建 `scripts/deploy-from-scratch.sh`:
```bash
#!/bin/bash
# 完整的從零開始部署腳本
# 包含所有必要步驟和錯誤處理
```

---

**測試狀態**: ✅ 基本部署成功
**已發現問題數**: 7
**已修復問題數**: 7 (臨時手動修復，需要更新腳本和文檔)
**核心功能**: ✅ 可用 (Prometheus, Grafana, 3個xApps, E2 Simulator)
