# O-RAN RIC Platform 項目重組方案
**作者**：蔡秀吉（thc1006）
**日期**：2025-11-14
**目標**：確保任何人 clone 後都能成功部署

---

## 📋 目錄

1. [當前問題分析](#當前問題分析)
2. [重組目標](#重組目標)
3. [目標結構](#目標結構)
4. [分階段執行計劃](#分階段執行計劃)
5. [Phase 1: 緊急 - 已部署 xApp 優先](#phase-1-緊急---已部署-xapp-優先)
6. [Phase 2: 完整重組](#phase-2-完整重組)
7. [部署腳本說明](#部署腳本說明)
8. [驗證與測試](#驗證與測試)
9. [回滾方案](#回滾方案)

---

## 當前問題分析

### 發現的問題

#### 1. Legacy 代碼散落各處
```
xapps/kpimon-go-xapp/legacy-kpimon-go-xapp/
xapps/rc-xapp/legacy-rc-xapp/
xapps/traffic-steering/legacy-traffic-steering/
xapps/kpm-xapp/legacy-kpm-xapp/
```
**影響**：新用戶不知道哪個是最新版本，容易誤用舊代碼。

#### 2. 不應提交的文件
```
xapps/kpimon-go-xapp/venv/          # Python 虛擬環境（780MB）
```
**影響**：
- 增加 clone 時間
- 佔用 GitHub 儲存空間
- 違反 .gitignore 規範

#### 3. 參考文檔混亂
```
xapps/kpimon-go-xapp/[Rel-G] Demo of KPIMON-GO...html
xapps/kpimon-go-xapp/【G Release】KPIMON-GO...html
xapps/rc-xapp/RC xApp (For Slice) User Guide.md
```
**影響**：源代碼目錄混雜 HTML 文件，不專業。

#### 4. 文件重複
```
xapps/kpimon-go-xapp/kpimon.py          # 根目錄
xapps/kpimon-go-xapp/src/kpimon.py      # src 目錄
```
**影響**：容易修改錯誤的文件。

#### 5. 缺少部署腳本
**影響**：新用戶需要手動執行多個步驟，容易出錯。

#### 6. 命名不一致
```
xapps/kpimon-go-xapp/    # 有 -go-xapp 後綴
xapps/rc-xapp/           # 有 rc- 前綴
xapps/qoe-predictor/     # 標準命名
```
**影響**：不統一，不專業。

---

## 重組目標

### 核心目標

1. ✅ **任何人 clone 後都能成功部署**
2. ✅ **清晰的目錄結構**：一眼看出哪些可用、哪些是參考
3. ✅ **一鍵部署**：最小化手動步驟
4. ✅ **完整文檔**：從環境準備到驗證的全流程
5. ✅ **易於維護**：遵循最佳實踐

### 設計原則

- **Small CLs**：小步驟、增量修改
- **可回滾**：每步都可以撤銷
- **向後兼容**：保留 Legacy 代碼作為參考
- **文檔優先**：代碼與文檔同步更新

---

## 目標結構

```
oran-ric-platform/
│
├── README.md                           # 項目總覽（含快速開始）
├── LICENSE
├── .gitignore                          # 更新：忽略 venv、*.pyc 等
│
├── docs/                               # 📚 統一文檔目錄
│   ├── deployment-guide-complete.md   # ✅ 完整部署指南（已完成）
│   ├── QUICK-START.md                 # 🆕 快速開始指南
│   ├── troubleshooting.md             # 🆕 問題排查指南
│   ├── PROJECT-REORGANIZATION-PLAN.md # 🆕 本文檔
│   ├── references/                    # 🆕 參考文檔（HTML、舊版 MD）
│   │   ├── README.md
│   │   ├── kpimon-rel-g-demo.html
│   │   ├── rc-xapp-user-guide.md
│   │   └── traffic-steering-integration.md
│   └── architecture/                  # 架構圖與設計文檔
│       └── ric-platform-architecture.md
│
├── scripts/                           # 🛠️ 統一部署與工具腳本
│   ├── setup/
│   │   ├── check-prerequisites.sh    # 🆕 環境檢查
│   │   ├── setup-k3s.sh              # ✅ 已存在
│   │   └── setup-registry.sh         # 🆕 Docker registry 設置
│   ├── deployment/
│   │   ├── deploy-ric-platform.sh    # 🆕 部署 RIC Platform
│   │   ├── deploy-xapp.sh            # 🆕 通用 xApp 部署腳本
│   │   └── verify-deployment.sh      # 🆕 部署驗證
│   └── cleanup/
│       ├── cleanup-all.sh            # 🆕 清理所有組件
│       └── reset-cluster.sh          # 🆕 重置集群
│
├── ric-dep/                          # RIC Platform Helm charts（submodule）
│   └── (保持現狀)
│
├── xapps/                            # 🚀 xApp 源代碼
│   ├── README.md                     # xApp 總覽
│   ├── QUICK_START.md                # 快速開始
│   │
│   ├── kpimon/                       # ✅ 已部署（重命名自 kpimon-go-xapp）
│   │   ├── README.md                 # 🆕 KPIMON 詳細說明
│   │   ├── CHANGELOG.md              # 🆕 版本變更記錄
│   │   ├── Dockerfile                # ✅ 已修復（ricsdl 3.1.3）
│   │   ├── requirements.txt          # ✅ 已修復
│   │   ├── src/
│   │   │   └── kpimon.py            # ✅ 主程式（451 行）
│   │   ├── config/
│   │   │   └── config.json          # ✅ 配置文件
│   │   ├── tests/                    # 🆕 單元測試
│   │   │   ├── test_kpimon.py
│   │   │   └── test_integration.py
│   │   └── deploy/                   # 🆕 Kubernetes manifests
│   │       ├── configmap.yaml
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   │
│   ├── ran-control/                  # ✅ 已部署（重命名自 rc-xapp）
│   │   ├── README.md                 # 🆕
│   │   ├── CHANGELOG.md              # 🆕
│   │   ├── Dockerfile                # ✅ 已修復
│   │   ├── requirements.txt          # ✅ 已修復
│   │   ├── src/
│   │   │   └── ran_control.py       # ✅ 主程式（796 行）
│   │   ├── config/
│   │   │   └── config.json          # ✅ 配置文件
│   │   ├── tests/                    # 🆕
│   │   └── deploy/                   # 🆕
│   │       ├── configmap.yaml
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   │
│   ├── qoe-predictor/                # ⏳ 待部署
│   │   ├── README.md
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   ├── src/
│   │   │   └── qoe_predictor.py
│   │   └── config/
│   │
│   ├── traffic-steering/             # ⏳ 待部署
│   │   ├── README.md
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   ├── src/
│   │   └── config/
│   │
│   ├── kpm/                          # ⏳ 待部署（重命名自 kpm-xapp）
│   │   └── ...
│   │
│   └── scripts/                      # xApp 共享腳本
│       ├── build-xapp.sh             # 🆕 通用構建腳本
│       ├── push-xapp.sh              # 🆕 推送鏡像
│       └── test-xapp.sh              # 🆕 測試腳本
│
└── legacy/                           # 🗄️ Legacy 代碼存檔（僅供參考）
    ├── README.md                     # 🆕 說明這些僅供參考，不要部署
    ├── kpimon-go-xapp/              # 從 xapps/kpimon-go-xapp/legacy-*/ 移過來
    ├── rc-xapp/
    ├── traffic-steering/
    └── kpm-xapp/
```

---

## 分階段執行計劃

### 為何分階段？

1. **降低風險**：每階段可獨立驗證和回滾
2. **支持緊急需求**：優先處理已部署的 xApp
3. **遵循 Small CLs**：小步驟修改，易於 code review
4. **增量交付**：早期階段就能讓夥伴使用

### 階段劃分

| 階段 | 優先級 | 預計時間 | 依賴 |
|------|--------|----------|------|
| Phase 1 | 🔥 緊急 | 30 分鐘 | 無 |
| Phase 2 | 🔶 重要 | 1-2 小時 | Phase 1 完成 |

---

## Phase 1: 緊急 - 已部署 xApp 優先

**目標**：讓您的夥伴能夠立即部署已成功的 KPIMON 和 RC xApp。

### 1.1 範圍

僅處理已部署並驗證成功的 xApp：
- ✅ KPIMON xApp
- ✅ RAN Control xApp

### 1.2 執行步驟

#### Step 1.1.1: 創建部署配置目錄

```bash
cd /home/thc1006/oran-ric-platform

# 為已部署的 xApp 創建 deploy 目錄
mkdir -p xapps/kpimon-go-xapp/deploy
mkdir -p xapps/rc-xapp/deploy
```

#### Step 1.1.2: 創建 KPIMON Kubernetes Manifests

**文件 1: `xapps/kpimon-go-xapp/deploy/configmap.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kpimon-config
  namespace: ricxapp
  labels:
    app: kpimon
    xapp: kpimon
data:
  config.json: |
    {
      "xapp_name": "kpimon",
      "version": "1.0.0",
      "rmr_port": 4560,
      "http_port": 8080,
      "redis": {
        "host": "service-ricplt-dbaas-tcp.ricplt",
        "port": 6379,
        "db": 0
      },
      "influxdb": {
        "url": "http://r4-influxdb-influxdb2.ricplt:8086",
        "org": "oran",
        "bucket": "kpimon",
        "token": ""
      },
      "subscription": {
        "report_period": 1000,
        "granularity_period": 1000,
        "max_measurements": 20
      }
    }
```

**文件 2: `xapps/kpimon-go-xapp/deploy/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kpimon
  namespace: ricxapp
  labels:
    app: kpimon
    xapp: kpimon
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kpimon
  template:
    metadata:
      labels:
        app: kpimon
        xapp: kpimon
    spec:
      containers:
      - name: kpimon
        image: localhost:5000/xapp-kpimon:1.0.0
        imagePullPolicy: Always
        env:
        - name: RMR_SEED_RT
          value: "/app/config/rmr-routes.txt"
        - name: RMR_SRC_ID
          value: "kpimon"
        - name: RMR_RTG_SVC
          value: "service-ricplt-rtmgr-rmr.ricplt:4561"
        - name: INFLUXDB_URL
          value: "http://r4-influxdb-influxdb2.ricplt:8086"
        - name: INFLUXDB_ORG
          value: "oran"
        - name: INFLUXDB_BUCKET
          value: "kpimon"
        ports:
        - name: rmr-data
          containerPort: 4560
          protocol: TCP
        - name: http-metrics
          containerPort: 8080
          protocol: TCP
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        volumeMounts:
        - name: config-volume
          mountPath: /app/config
      volumes:
      - name: config-volume
        configMap:
          name: kpimon-config
```

**文件 3: `xapps/kpimon-go-xapp/deploy/service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kpimon
  namespace: ricxapp
  labels:
    app: kpimon
    xapp: kpimon
spec:
  type: ClusterIP
  selector:
    app: kpimon
  ports:
  - name: rmr-data
    port: 4560
    targetPort: 4560
    protocol: TCP
  - name: http-metrics
    port: 8080
    targetPort: 8080
    protocol: TCP
```

#### Step 1.1.3: 創建 RC xApp Kubernetes Manifests

**文件 1: `xapps/rc-xapp/deploy/configmap.yaml`**

（內容已在之前的部署中創建於 /tmp/rc-xapp-configmap.yaml）

```bash
# 複製現有的 ConfigMap
cp /tmp/rc-xapp-configmap.yaml xapps/rc-xapp/deploy/configmap.yaml
```

**文件 2 & 3: Deployment 和 Service**

```bash
# 複製現有的 manifests
cp /tmp/rc-xapp-deployment.yaml xapps/rc-xapp/deploy/deployment.yaml
cp /tmp/rc-xapp-service.yaml xapps/rc-xapp/deploy/service.yaml
```

#### Step 1.1.4: 創建 KPIMON README

**文件: `xapps/kpimon-go-xapp/README.md`**

```markdown
# KPIMON xApp

KPI 監控與異常檢測 xApp，基於 E2SM-KPM v3.0。

## 功能

- ✅ 自動訂閱 E2 KPI（20 種指標）
- ✅ 實時異常檢測（5 種閾值）
- ✅ 雙重數據存儲（Redis + InfluxDB）
- ✅ Prometheus 指標暴露

## 快速部署

### 前提條件

- RIC Platform 已部署（包括 RTMgr 和 InfluxDB）
- ricxapp 命名空間已創建

### 構建鏡像

\`\`\`bash
cd xapps/kpimon-go-xapp
docker build -t localhost:5000/xapp-kpimon:1.0.0 .
docker push localhost:5000/xapp-kpimon:1.0.0
\`\`\`

### 部署

\`\`\`bash
kubectl apply -f deploy/
\`\`\`

### 驗證

\`\`\`bash
# 檢查 Pod 狀態
kubectl get pods -n ricxapp -l app=kpimon

# 查看日誌
kubectl logs -n ricxapp -l app=kpimon --tail=50

# 測試 Prometheus 指標
kubectl port-forward -n ricxapp svc/kpimon 8080:8080
curl http://localhost:8080/metrics | grep kpimon_
\`\`\`

## 配置

主要配置在 `config/config.json`：

- `rmr_port`: RMR 數據端口（默認 4560）
- `http_port`: Prometheus 指標端口（默認 8080）
- `redis`: Redis 連接配置
- `influxdb`: InfluxDB 連接配置

## 依賴版本

- ricxappframe: 3.2.2
- ricsdl: 3.1.3
- redis: 4.3.6
- protobuf: 3.20.3

## 問題排查

查看完整文檔：[部署指南](../../docs/deployment-guide-complete.md#4-kpimon-xapp-部署)
```

#### Step 1.1.5: 創建 RC xApp README

**文件: `xapps/rc-xapp/README.md`**

```markdown
# RAN Control xApp

RAN 控制與優化 xApp，基於 E2SM-RC v2.0。

## 功能

- ✅ 5 種優化算法（切換、資源、負載均衡、切片、功率）
- ✅ A1 策略執行
- ✅ E2 控制請求（10 種控制動作）
- ✅ REST API（6 個端點）

## 快速部署

### 前提條件

- RIC Platform 已部署
- ricxapp 命名空間已創建

### 構建鏡像

\`\`\`bash
cd xapps/rc-xapp
docker build -t localhost:5000/xapp-ran-control:1.0.0 .
docker push localhost:5000/xapp-ran-control:1.0.0
\`\`\`

### 部署

\`\`\`bash
kubectl apply -f deploy/
\`\`\`

### 驗證

\`\`\`bash
# 檢查 Pod 狀態
kubectl get pods -n ricxapp -l app=ran-control

# 測試健康檢查
kubectl exec -n ricxapp <pod-name> -- curl http://localhost:8100/health/alive

# 查看指標
kubectl exec -n ricxapp <pod-name> -- curl http://localhost:8100/metrics
\`\`\`

## REST API

- `/health/alive` - 存活檢查
- `/health/ready` - 就緒檢查
- `/control/trigger` - 觸發控制動作
- `/control/status/<id>` - 查詢控制狀態
- `/metrics` - 性能指標
- `/network/state` - 網路狀態

## 依賴版本

同 KPIMON（共享相同的依賴版本）

## 問題排查

查看完整文檔：[部署指南](../../docs/deployment-guide-complete.md#5-ran-control-xapp-部署)
```

#### Step 1.1.6: 創建快速部署指南

**文件: `docs/QUICK-START.md`**

```markdown
# O-RAN RIC Platform 快速開始指南
**作者**：蔡秀吉（thc1006）
**適用對象**：希望快速部署已驗證 xApp 的用戶

---

## 🚀 5 分鐘快速部署

本指南幫助您快速部署已經驗證成功的 KPIMON 和 RAN Control xApp。

### 前提條件

確保以下組件已安裝：
- Kubernetes (k3s v1.28+)
- Helm 3.x
- Docker

### Step 1: 檢查環境

\`\`\`bash
# Clone 專案
git clone https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform

# 設置 kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 檢查集群
kubectl get nodes
\`\`\`

### Step 2: 部署 RIC Platform

如果尚未部署 RIC Platform：

\`\`\`bash
# 創建命名空間
kubectl create namespace ricplt
kubectl create namespace ricxapp

# 部署基礎組件（Redis、E2Term、A1 Mediator、RTMgr、InfluxDB）
# 詳見：docs/deployment-guide-complete.md#2-ric-platform-部署
\`\`\`

**或使用自動腳本**（如果可用）：

\`\`\`bash
./scripts/deployment/deploy-ric-platform.sh
\`\`\`

### Step 3: 部署 KPIMON xApp

\`\`\`bash
cd xapps/kpimon-go-xapp

# 構建鏡像
docker build -t localhost:5000/xapp-kpimon:1.0.0 .
docker push localhost:5000/xapp-kpimon:1.0.0

# 部署
kubectl apply -f deploy/

# 驗證
kubectl get pods -n ricxapp -l app=kpimon
kubectl logs -n ricxapp -l app=kpimon --tail=20
\`\`\`

**預期輸出**：
```
{"msg": "KPIMON xApp initialized"}
{"msg": "Redis connection established"}
{"msg": "InfluxDB connection established"}
{"msg": "KPIMON xApp started successfully"}
{"msg": "Sent subscription request: kpimon_xxx"}
```

### Step 4: 部署 RAN Control xApp

\`\`\`bash
cd xapps/rc-xapp

# 構建鏡像
docker build -t localhost:5000/xapp-ran-control:1.0.0 .
docker push localhost:5000/xapp-ran-control:1.0.0

# 部署
kubectl apply -f deploy/

# 驗證
kubectl get pods -n ricxapp -l app=ran-control
kubectl logs -n ricxapp -l app=ran-control --tail=20
\`\`\`

**預期輸出**：
```
{"msg": "Redis connection established"}
{"msg": "RAN Control xApp initialized"}
{"msg": "RAN Control xApp started successfully"}
* Running on http://0.0.0.0:8100
```

### Step 5: 驗證部署

\`\`\`bash
# 檢查所有 Pod
kubectl get pods -n ricxapp

# 預期輸出
NAME                           READY   STATUS    RESTARTS   AGE
kpimon-xxx                     1/1     Running   0          2m
ran-control-xxx                1/1     Running   0          1m

# 測試 KPIMON Prometheus 指標
KPIMON_POD=$(kubectl get pod -n ricxapp -l app=kpimon -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $KPIMON_POD -- curl -s http://localhost:8080/metrics | grep kpimon_

# 測試 RC xApp API
RC_POD=$(kubectl get pod -n ricxapp -l app=ran-control -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ricxapp $RC_POD -- curl http://localhost:8100/health/alive
\`\`\`

---

## 🎯 部署完成！

現在您已經成功部署了：
- ✅ KPIMON xApp - KPI 監控與異常檢測
- ✅ RAN Control xApp - RAN 控制與優化

### 下一步

- 查看完整文檔：[deployment-guide-complete.md](deployment-guide-complete.md)
- 問題排查：[troubleshooting.md](troubleshooting.md)
- xApp 詳細說明：
  - [KPIMON README](../xapps/kpimon-go-xapp/README.md)
  - [RC xApp README](../xapps/rc-xapp/README.md)

### 需要幫助？

如遇到問題，請查看：
1. Pod 日誌：`kubectl logs -n ricxapp <pod-name>`
2. 問題排查指南：`docs/troubleshooting.md`
3. GitHub Issues：https://github.com/thc1006/oran-ric-platform/issues
```

### 1.3 提交 Phase 1

```bash
cd /home/thc1006/oran-ric-platform

# 創建部署配置
# （執行上面的步驟）

# 檢查變更
git status

# 提交
git add xapps/kpimon-go-xapp/deploy/
git add xapps/rc-xapp/deploy/
git add xapps/kpimon-go-xapp/README.md
git add xapps/rc-xapp/README.md
git add docs/QUICK-START.md
git add docs/PROJECT-REORGANIZATION-PLAN.md

git commit -m "Phase 1: Add deployment configs for KPIMON and RC xApp

- Add Kubernetes manifests (ConfigMap, Deployment, Service)
- Add README for each xApp
- Add Quick Start guide for fast deployment
- Enable partners to deploy immediately

Deployed xApps:
- KPIMON xApp (E2SM-KPM v3.0)
- RAN Control xApp (E2SM-RC v2.0)

Author: 蔡秀吉 (thc1006)"

# 創建 tag
git tag -a v1.0.0-phase1 -m "Phase 1: Deployment-ready for KPIMON and RC xApp"
```

### 1.4 Phase 1 完成後

您的夥伴現在可以：

```bash
# 1. Clone 專案
git clone https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform

# 2. 按照 Quick Start 指南部署
cat docs/QUICK-START.md

# 3. 一鍵部署 KPIMON
cd xapps/kpimon-go-xapp
docker build -t localhost:5000/xapp-kpimon:1.0.0 .
docker push localhost:5000/xapp-kpimon:1.0.0
kubectl apply -f deploy/

# 4. 一鍵部署 RC xApp
cd ../rc-xapp
docker build -t localhost:5000/xapp-ran-control:1.0.0 .
docker push localhost:5000/xapp-ran-control:1.0.0
kubectl apply -f deploy/
```

---

## Phase 2: 完整重組

**目標**：完整重組項目結構，處理所有 xApp 和 Legacy 代碼。

**預計執行時間**：Phase 1 完成後，根據實際需求再執行。

### 2.1 範圍

- 移動所有 Legacy 代碼到 `legacy/`
- 移動所有參考文檔到 `docs/references/`
- 重命名 xApp 目錄（統一命名規範）
- 刪除不必要的文件（venv、重複文件）
- 創建完整的部署腳本
- 更新 .gitignore

### 2.2 執行步驟

詳細步驟請參考自動化腳本：`/tmp/reorganize-project.sh`

主要包括：
1. 創建目錄結構
2. 移動 Legacy 代碼
3. 移動參考文檔
4. 刪除不必要文件
5. 重命名目錄
6. 更新 .gitignore
7. 創建部署腳本

---

## 部署腳本說明

### 環境檢查腳本

**文件**：`scripts/setup/check-prerequisites.sh`

**功能**：
- 檢查 kubectl、helm、docker、k3s、python3
- 檢查系統資源
- 驗證 Kubernetes 集群連接
- 檢查必要的命名空間

**使用**：
```bash
./scripts/setup/check-prerequisites.sh
```

### xApp 部署腳本

**文件**：`scripts/deployment/deploy-xapp.sh`

**功能**：
- 自動構建 Docker 鏡像
- 推送到 registry
- 部署到 Kubernetes
- 等待 Pod 就緒
- 顯示部署狀態

**使用**：
```bash
./scripts/deployment/deploy-xapp.sh kpimon
./scripts/deployment/deploy-xapp.sh ran-control
```

### 驗證腳本

**文件**：`scripts/deployment/verify-deployment.sh`

**功能**：
- 檢查所有 RIC Platform 組件
- 檢查所有 xApp
- 顯示服務狀態

**使用**：
```bash
./scripts/deployment/verify-deployment.sh
```

---

## 驗證與測試

### Phase 1 驗證清單

- [ ] KPIMON deploy/ 目錄包含 3 個 YAML 文件
- [ ] RC xApp deploy/ 目錄包含 3 個 YAML 文件
- [ ] 每個 xApp 有 README.md
- [ ] docs/QUICK-START.md 存在且完整
- [ ] Git commit 成功
- [ ] Tag v1.0.0-phase1 創建成功
- [ ] 夥伴能夠 clone 並成功部署

### 功能驗證

```bash
# KPIMON 功能驗證
kubectl logs -n ricxapp -l app=kpimon | grep "subscription request"
kubectl exec -n ricxapp <kpimon-pod> -- curl http://localhost:8080/metrics

# RC xApp 功能驗證
kubectl exec -n ricxapp <rc-pod> -- curl http://localhost:8100/health/alive
kubectl exec -n ricxapp <rc-pod> -- curl http://localhost:8100/metrics
```

---

## 回滾方案

### Phase 1 回滾

如果 Phase 1 出現問題：

```bash
# 回滾到 Phase 1 之前
git reset --hard HEAD~1

# 或使用 tag
git reset --hard v1.0.0  # 假設之前有 tag
```

### 完整重置

如果需要完全重置：

```bash
# 刪除所有新增的文件
git clean -fd

# 重置到初始狀態
git reset --hard origin/main
```

### 保留工作

如果想保留未提交的工作：

```bash
# 暫存當前工作
git stash

# 切換到安全版本
git checkout v1.0.0-phase1

# 恢復工作
git stash pop
```

---

## 總結

### Phase 1（緊急）

**時間**：30 分鐘
**成果**：夥伴可以立即部署 KPIMON 和 RC xApp
**文件**：
- `xapps/kpimon-go-xapp/deploy/` (3 個 YAML)
- `xapps/rc-xapp/deploy/` (3 個 YAML)
- `xapps/kpimon-go-xapp/README.md`
- `xapps/rc-xapp/README.md`
- `docs/QUICK-START.md`
- `docs/PROJECT-REORGANIZATION-PLAN.md` (本文檔)

### Phase 2（後續）

**時間**：1-2 小時
**成果**：完整、專業的項目結構
**執行時機**：Phase 1 驗證成功後

---

**文檔結束**

如有問題，請聯繫：蔡秀吉（thc1006）
