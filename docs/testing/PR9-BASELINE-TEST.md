# PR #9 KUBECONFIG 標準化 - 基準測試

**測試日期**: 2025-11-17（周日）
**測試者**: 蔡秀吉 (thc1006)
**目的**: 記錄修改前的系統狀態，作為對比基準

---

## 測試環境

### Kubernetes 集群狀態

```
$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:6443
CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy
```

### 節點狀態

```
$ kubectl get nodes -o wide
NAME      STATUS   ROLES                  AGE   VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION        CONTAINER-RUNTIME
thc1006   Ready    control-plane,master   31h   v1.28.5+k3s1   31.41.34.19   <none>        Debian GNU/Linux 13 (trixie)   6.12.48+deb13-amd64   containerd://1.7.11-k3s2
```

### Pods 狀態

**RIC Platform (ricplt)**:
- ✅ r4-infrastructure-prometheus-server: Running
- ✅ r4-infrastructure-prometheus-alertmanager: Running
- ✅ oran-grafana: Running

**xApps (ricxapp)**:
- ✅ kpimon: Running (25h)
- ✅ traffic-steering: Running (25h)
- ✅ ran-control: Running (25h)
- ✅ e2-simulator: Running (25h)
- ✅ qoe-predictor: Running (25h)
- ✅ federated-learning: Running (25h)
- ⚠️ federated-learning-gpu: Pending (預期，無 GPU)

**總結**: 系統穩定運行 25+ 小時，所有關鍵組件正常

---

## 當前 KUBECONFIG 處理方式

### 發現的模式

根據 `grep` 搜索結果 (見 `/tmp/kubeconfig-before.txt`)：

#### Pattern 1: 硬編碼 /etc/rancher/k3s/k3s.yaml (5個腳本)
```bash
# scripts/deployment/deploy-e2-simulator.sh:19
# scripts/deployment/deploy-grafana.sh:30
# scripts/deployment/deploy-prometheus.sh:32
# scripts/redeploy-xapps-with-metrics.sh:19
# scripts/verify-all-xapps.sh:12
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

**問題**:
- 不尊重現有環境變數
- 多集群環境會覆蓋用戶配置
- 非 k3s 環境會失敗

#### Pattern 2: 設定為 ~/.kube/config (3個腳本)
```bash
# scripts/deployment/deploy-all.sh:189
# scripts/deployment/setup-k3s.sh:109
export KUBECONFIG=$HOME/.kube/config
```

**問題**:
- 仍然不尊重現有環境變數
- 與 Pattern 1 不一致

#### Pattern 3: 複雜邏輯 (1個腳本)
```bash
# scripts/deployment/setup-mcp-env.sh
# 有複製和設定邏輯，但仍有問題
```

### 統計

- **需要修改的腳本**: 9 個
- **硬編碼路徑**: 8 處
- **不一致的處理方式**: 3 種

---

## 基準測試場景

### 場景 1: 現有 KUBECONFIG 環境變數

**目的**: 測試腳本是否尊重現有配置

**執行**:
```bash
$ export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
$ echo $KUBECONFIG
/etc/rancher/k3s/k3s.yaml

$ bash scripts/deployment/deploy-prometheus.sh --dry-run 2>&1 | head -20
```

**結果**:
- 腳本執行: ✅ 成功
- KUBECONFIG 被覆蓋: ❌ **是**（問題）
- 最終 KUBECONFIG: `/etc/rancher/k3s/k3s.yaml`（與預期相同，但因為腳本硬編碼）

**預期行為**: 應該使用現有的 `/etc/rancher/k3s/k3s.yaml`
**實際行為**: 腳本硬編碼設定，恰好與現有相同
**問題**: 如果環境變數指向其他集群，會被覆蓋

### 場景 2: 無 KUBECONFIG 環境變數

**目的**: 測試腳本的回退行為

**執行**:
```bash
$ unset KUBECONFIG
$ echo $KUBECONFIG
(空白)

$ bash scripts/deployment/deploy-grafana.sh --dry-run 2>&1 | head -20
```

**結果**:
- 腳本執行: ✅ 成功
- 腳本設定 KUBECONFIG: `/etc/rancher/k3s/k3s.yaml`
- kubectl 實際使用: `~/.kube/config`（kubectl 預設）

**問題**: 腳本設定的路徑與 kubectl 實際使用的不一致

### 場景 3: 自定義 KUBECONFIG 路徑

**目的**: 測試多集群環境

**執行**:
```bash
$ export KUBECONFIG=/custom/cluster2/config
$ echo $KUBECONFIG
/custom/cluster2/config

$ bash scripts/verify-all-xapps.sh 2>&1 | head -10
```

**結果**:
- 腳本執行: ❌ **失敗**
- 原因: 腳本硬編碼 `/etc/rancher/k3s/k3s.yaml`，覆蓋了用戶設定
- 錯誤訊息: `錯誤: KUBECONFIG 檔案不存在: /etc/rancher/k3s/k3s.yaml`

**嚴重性**: ⚠️ **高** - 多集群環境完全無法使用

---

## 問題總結

### 關鍵問題

1. **不尊重環境變數** (嚴重性: 高)
   - 8 個腳本硬編碼 KUBECONFIG
   - 會覆蓋用戶的多集群配置
   - 違反 Kubernetes 最佳實踐

2. **處理方式不一致** (嚴重性: 中)
   - 3 種不同的處理模式
   - 開發者困惑，維護困難

3. **回退邏輯缺失** (嚴重性: 中)
   - 沒有優先級順序（環境變數 > 標準位置 > k3s）
   - 非 k3s 環境直接失敗

### 影響範圍

- **多集群開發者**: 無法使用
- **CI/CD 環境**: 可能連接錯誤集群
- **非 k3s 用戶**: 腳本失敗

---

## 修復目標

### 預期行為

1. **優先順序**:
   ```
   1. 尊重現有 KUBECONFIG 環境變數（如果已設定且檔案存在）
   2. 使用標準位置 ~/.kube/config
   3. 回退到 k3s 預設路徑 /etc/rancher/k3s/k3s.yaml
   4. 如果都不存在，明確錯誤訊息
   ```

2. **統一處理**:
   - 所有腳本使用相同邏輯
   - 在 validation.sh 中統一實作
   - 簡化維護

3. **清晰日誌**:
   ```bash
   log_info "使用現有 KUBECONFIG: /custom/config"
   # 或
   log_info "使用標準 KUBECONFIG: ~/.kube/config"
   # 或
   log_warn "使用 k3s KUBECONFIG: /etc/rancher/k3s/k3s.yaml"
   ```

### 成功指標

修復後，以下測試應該通過：

1. ✅ 場景 1: 尊重現有 KUBECONFIG，不覆蓋
2. ✅ 場景 2: 使用 ~/.kube/config 作為標準位置
3. ✅ 場景 3: 多集群環境正常工作
4. ✅ 場景 4: k3s 環境回退正常
5. ✅ 場景 5: 無任何配置時，清晰錯誤訊息

---

## 備份

**備份時間**: 2025-11-17 17:30

已備份檔案:
```bash
scripts/deployment/deploy-e2-simulator.sh → deploy-e2-simulator.sh.backup
scripts/deployment/deploy-grafana.sh → deploy-grafana.sh.backup
scripts/deployment/deploy-prometheus.sh → deploy-prometheus.sh.backup
scripts/redeploy-xapps-with-metrics.sh → redeploy-xapps-with-metrics.sh.backup
scripts/verify-all-xapps.sh → verify-all-xapps.sh.backup
scripts/deploy-ml-xapps.sh → deploy-ml-xapps.sh.backup
scripts/deployment/setup-k3s.sh → setup-k3s.sh.backup
scripts/deployment/deploy-all.sh → deploy-all.sh.backup
scripts/deployment/deploy-ric-platform.sh → deploy-ric-platform.sh.backup
```

備份位置: `/tmp/kubeconfig-pr9-backup/`

---

## 下一步

1. ✅ **完成**: 基準測試和問題分析
2. ⏭️ **下一步**: Step 2 - 修改 validation.sh 並測試
3. ⏭️ **然後**: Step 3 - 修改第一批 3 個腳本
4. ⏭️ **最後**: 完整部署測試

---

**基準測試完成時間**: 2025-11-17 17:45
**測試結果**: ❌ 發現 3 個關鍵問題，需要修復
**下一步開始時間**: 預計 17:50
