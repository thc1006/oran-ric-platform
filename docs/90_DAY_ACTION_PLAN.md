# O-RAN RIC Platform 90 天行動計劃

**作者**: 蔡秀吉 (thc1006)
**開始日期**: 2025-11-18（週一）
**結束日期**: 2026-02-16（週日）
**總工時**: 214.5 小時
**團隊規模**: 2 FTE (Full-Time Engineers)

---

## 📋 目錄

- [Phase 0: 緊急修復](#phase-0-緊急修復-week-0)
- [Phase 1: 安全強化](#phase-1-安全強化-week-1-4)
- [Phase 2: 高可用性與效能](#phase-2-高可用性與效能-week-5-8)
- [Phase 3: 測試與 CI/CD](#phase-3-測試與-cicd-week-9-12)
- [附錄: 驗收標準](#附錄驗收標準)

---

## Phase 0: 緊急修復 (Week 0)

### 📅 時程：2025-11-18 ~ 2025-11-20 (3 天)

### 🎯 目標
- 消除所有 Critical 資料丟失風險
- 修復最嚴重的安全漏洞
- 建立基本備份機制

### 📊 成功指標
- ✅ Redis 資料持久化啟用
- ✅ InfluxDB 磁碟使用量 < 10 Gi
- ✅ 無明文密碼存在於配置檔案
- ✅ 每日備份成功執行

---

### 任務 1: 啟用 Redis AOF 持久化 🔴

**負責人**: DevOps Engineer
**工時**: 2 小時
**優先級**: P0

#### 執行步驟

```bash
# Step 1: 備份當前配置
kubectl get configmap dbaas-config -n ricplt -o yaml > /tmp/dbaas-config-backup.yaml

# Step 2: 編輯 ConfigMap
kubectl edit configmap dbaas-config -n ricplt

# 修改以下參數:
#   appendonly: "yes"          # 啟用 AOF
#   appendfsync: "everysec"    # 每秒同步
#   save: "900 1 300 10 60 10000"  # RDB 快照策略

# Step 3: 重啟 Redis Pod
kubectl rollout restart deployment/dbaas -n ricplt

# Step 4: 驗證 AOF 檔案生成
kubectl exec -it dbaas-xxxxx -n ricplt -- ls -lh /data/
# 應該看到 appendonly.aof 檔案

# Step 5: 驗證持久化配置
kubectl exec -it dbaas-xxxxx -n ricplt -- redis-cli CONFIG GET appendonly
# 應回傳 appendonly: yes
```

#### 驗收標準
- [ ] `appendonly.aof` 檔案存在於 `/data/` 目錄
- [ ] AOF 檔案大小 > 0 bytes
- [ ] Redis INFO 顯示 `aof_enabled:1`
- [ ] 執行 `BGREWRITEAOF` 成功

#### 潛在問題
- **AOF 重寫阻塞**: 解決方案 - `auto-aof-rewrite-min-size 64mb`
- **磁碟空間不足**: 確認 PVC 有足夠空間 (至少 5Gi 可用)

---

### 任務 2: 設定 InfluxDB Retention Policy 🔴

**負責人**: DevOps Engineer
**工時**: 1 小時
**優先級**: P0

#### 執行步驟

```bash
# Step 1: 進入 InfluxDB Pod
kubectl exec -it influxdb-0 -n ricplt -- sh

# Step 2: 查看當前 bucket 配置
influx bucket list

# Step 3: 更新 Retention Policy (90 天)
influx bucket update \
  --id <bucket-id> \
  --retention 90d \
  --shard-group-duration 1d

# Step 4: 驗證設定
influx bucket list
# retention 應顯示 2160h0m0s (90 天)

# Step 5: 強制執行舊資料清理
influx task create \
  --name cleanup-old-data \
  --every 1d \
  --flux '
    from(bucket: "ricplt")
      |> range(start: -91d, stop: -90d)
      |> filter(fn: (r) => true)
      |> drop()
  '
```

#### 驗收標準
- [ ] Retention Policy 設定為 90 天
- [ ] Shard group duration 為 1 天
- [ ] 執行 `influx bucket list` 顯示正確配置
- [ ] 磁碟使用量開始下降

#### 監控
```bash
# 每日檢查磁碟使用量
kubectl exec -it influxdb-0 -n ricplt -- du -sh /var/lib/influxdb2
```

---

### 任務 3: 移除 Grafana 明文密碼 🔴

**負責人**: Security Engineer
**工時**: 2 小時
**優先級**: P0

#### 執行步驟

```bash
# Step 1: 生成強密碼
GRAFANA_PASSWORD=$(openssl rand -base64 32)
echo "New Grafana password: $GRAFANA_PASSWORD"
# ⚠️ 妥善保存此密碼

# Step 2: 創建 Kubernetes Secret
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=$GRAFANA_PASSWORD \
  -n ricplt

# Step 3: 更新 Helm values
cat > /tmp/grafana-values-patch.yaml <<EOF
admin:
  existingSecret: grafana-admin-secret
  userKey: admin-user
  passwordKey: admin-password
EOF

# Step 4: 升級 Grafana
helm upgrade oran-grafana ric/grafana \
  -n ricplt \
  -f config/grafana-values.yaml \
  -f /tmp/grafana-values-patch.yaml

# Step 5: 從 Git 移除明文密碼
cd /home/thc1006/oran-ric-platform
git checkout config/grafana-values.yaml
# 編輯檔案移除 adminPassword 行
git add config/grafana-values.yaml
git commit -m "security: Remove hardcoded Grafana password"
```

#### 驗收標準
- [ ] Grafana Pod 成功重啟
- [ ] 可用新密碼登入 Grafana UI
- [ ] `config/grafana-values.yaml` 無明文密碼
- [ ] Secret 存在: `kubectl get secret grafana-admin-secret -n ricplt`

---

### 任務 4: Redis 啟用密碼認證 🔴

**負責人**: DevOps Engineer
**工時**: 3 小時
**優先級**: P0

#### 執行步驟

```bash
# Step 1: 生成 Redis 密碼
REDIS_PASSWORD=$(openssl rand -base64 32)
echo "Redis password: $REDIS_PASSWORD"

# Step 2: 創建 Secret
kubectl create secret generic redis-auth \
  --from-literal=password=$REDIS_PASSWORD \
  -n ricplt

# Step 3: 更新 Redis ConfigMap
kubectl edit configmap dbaas-config -n ricplt

# 添加:
#   requirepass: "${REDIS_PASSWORD}"  # 從 Secret 讀取
#   protected-mode: "yes"
#   bind: "127.0.0.1"  # 僅監聽 localhost

# Step 4: 更新 DBaaS Deployment 掛載 Secret
kubectl edit deployment dbaas -n ricplt

# 添加環境變數:
# env:
# - name: REDIS_PASSWORD
#   valueFrom:
#     secretKeyRef:
#       name: redis-auth
#       key: password

# Step 5: 重啟 Redis
kubectl rollout restart deployment/dbaas -n ricplt

# Step 6: 更新所有 xApp 的 Redis 連線配置
# (KPIMON, Traffic Steering, QoE Predictor, RAN Control, FL)
```

#### xApp 配置更新範例

```yaml
# 每個 xApp deployment.yaml
env:
- name: SDL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: redis-auth
      key: password
```

#### 驗收標準
- [ ] Redis 需要密碼才能連線
- [ ] 所有 xApp Pods 成功連線 Redis
- [ ] 測試無密碼連線被拒絕: `redis-cli PING` 回傳 `NOAUTH`

---

### 任務 5: E2 Simulator 添加 FL 配置 🟠

**負責人**: Developer
**工時**: 30 分鐘
**優先級**: P0

#### 執行步驟

```bash
# Step 1: 編輯 E2 Simulator 代碼
vim simulator/e2-simulator/src/e2_simulator.py

# 在 Line 54 添加:
'federated-learning': {
    'host': 'federated-learning.ricxapp.svc.cluster.local',
    'port': 8110,
    'endpoint': '/e2/indication'
}

# Step 2: 重建 Docker 映像
cd simulator/e2-simulator
docker build -t localhost:5000/e2-simulator:1.0.1 .
docker push localhost:5000/e2-simulator:1.0.1

# Step 3: 更新 deployment.yaml
vim deploy/deployment.yaml
# 修改 image tag: 1.0.0 → 1.0.1

# Step 4: 重新部署
kubectl apply -f deploy/deployment.yaml -n ricxapp
```

#### 驗收標準
- [ ] E2 Simulator 日誌顯示向 FL 發送流量
- [ ] FL xApp 接收到 E2 indications
- [ ] `kubectl logs -n ricxapp -l app=e2-simulator | grep federated`

---

### 任務 6: 建立備份 CronJob 🟠

**負責人**: DevOps Engineer
**工時**: 2 小時
**優先級**: P0

#### 執行步驟

```bash
# Step 1: 創建備份腳本 ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: backup-scripts
  namespace: ricplt
data:
  backup-redis.sh: |
    #!/bin/bash
    DATE=\$(date +%Y%m%d-%H%M%S)
    kubectl exec -n ricplt dbaas-xxxxx -- redis-cli BGSAVE
    sleep 10
    kubectl cp ricplt/dbaas-xxxxx:/data/dump.rdb /backup/redis-\$DATE.rdb
    find /backup/redis-*.rdb -mtime +7 -delete

  backup-influxdb.sh: |
    #!/bin/bash
    DATE=\$(date +%Y%m%d-%H%M%S)
    kubectl exec -n ricplt influxdb-0 -- \
      influx backup /tmp/backup-\$DATE
    kubectl cp ricplt/influxdb-0:/tmp/backup-\$DATE /backup/influxdb-\$DATE
    find /backup/influxdb-* -mtime +7 -delete
EOF

# Step 2: 創建 CronJob
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-databases
  namespace: ricplt
spec:
  schedule: "0 2 * * *"  # 每天凌晨 2:00
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              /scripts/backup-redis.sh
              /scripts/backup-influxdb.sh
            volumeMounts:
            - name: backup-scripts
              mountPath: /scripts
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-scripts
            configMap:
              name: backup-scripts
              defaultMode: 0755
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
EOF

# Step 3: 創建備份 PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-pvc
  namespace: ricplt
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: local-path
EOF
```

#### 驗收標準
- [ ] CronJob 已創建: `kubectl get cronjob -n ricplt`
- [ ] PVC 已綁定: `kubectl get pvc backup-pvc -n ricplt`
- [ ] 手動觸發測試: `kubectl create job --from=cronjob/backup-databases test-backup -n ricplt`
- [ ] 備份檔案存在於 `/backup` 目錄

---

### Week 0 Checklist

- [ ] 所有 6 個任務完成
- [ ] 驗收標準全部通過
- [ ] 更新文檔記錄變更
- [ ] 向團隊展示成果
- [ ] 準備 Week 1 Sprint Planning

---

## Phase 1: 安全強化 (Week 1-4)

### Sprint 1: 密碼與密鑰管理 (Week 1-2)

#### 📅 時程：2025-11-21 ~ 2025-12-04 (2 週)

#### 🎯 Sprint 目標
- 實施 Sealed Secrets Operator
- 輪替所有服務密碼
- 清理 Git 歷史中的敏感資訊
- 整合映像漏洞掃描

---

### 任務 7: 安裝 Sealed Secrets Operator

**負責人**: DevOps Engineer
**工時**: 4 小時
**優先級**: P1

#### 執行步驟

```bash
# Step 1: 添加 Helm repo
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

# Step 2: 安裝 Sealed Secrets Controller
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set-string fullnameOverride=sealed-secrets-controller

# Step 3: 安裝 kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.24.0-linux-amd64.tar.gz
sudo mv kubeseal /usr/local/bin/
kubeseal --version

# Step 4: 測試 Sealed Secrets
kubectl create secret generic test-secret \
  --from-literal=foo=bar \
  --dry-run=client \
  -o yaml | \
  kubeseal -o yaml > test-sealed-secret.yaml

kubectl apply -f test-sealed-secret.yaml
kubectl get secret test-secret  # 應該存在
```

#### 驗收標準
- [ ] Sealed Secrets Controller Pod 運行中
- [ ] kubeseal CLI 可用
- [ ] 測試 SealedSecret 成功解密為 Secret

---

### 任務 8: 輪替所有服務密碼

**負責人**: Security Engineer
**工時**: 4 小時
**優先級**: P1

#### 服務清單

| 服務 | 當前密碼 | 新密碼位置 |
|------|---------|-----------|
| Grafana | oran-ric-admin | grafana-admin-secret (已完成) |
| VES Manager | sample1 | vesmgr-auth-secret |
| AppManager Helm Repo | helm/helm | appmgr-helm-secret |
| InfluxDB | admin/admin | influxdb-auth-secret |
| Redis | (無) | redis-auth (已完成) |

#### 執行步驟

```bash
# 使用自動化腳本
cd /home/thc1006/oran-ric-platform
bash scripts/security/rotate-secrets.sh

# 腳本會自動:
# 1. 生成新密碼
# 2. 創建 Sealed Secrets
# 3. 更新所有相關 Deployments
# 4. 滾動重啟受影響的 Pods
# 5. 驗證服務正常運行
```

#### 驗收標準
- [ ] 所有服務使用新密碼
- [ ] 沒有 Pod 處於 CrashLoopBackOff
- [ ] 新密碼記錄在密碼管理器（1Password/Vault）
- [ ] 舊密碼已失效

---

### 任務 9: Git 歷史清理

**負責人**: DevOps Engineer
**工時**: 2 小時
**優先級**: P1

#### 執行步驟

```bash
# ⚠️ 警告: 此操作會改寫 Git 歷史，需團隊協調

# Step 1: 備份倉庫
cd /home/thc1006/oran-ric-platform
git clone --mirror . ../oran-ric-platform-backup.git

# Step 2: 安裝 BFG Repo-Cleaner
wget https://repo1.maven.org/maven2/com/madgag/bfg/1.14.0/bfg-1.14.0.jar
alias bfg='java -jar bfg-1.14.0.jar'

# Step 3: 刪除敏感檔案
bfg --delete-files grafana-values.yaml
bfg --delete-files '*secret*.yaml'
bfg --replace-text passwords.txt  # 包含要移除的密碼列表

# Step 4: 清理 reflog 並 GC
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# Step 5: 強制推送 (需團隊通知)
git push --force
```

#### passwords.txt 範例

```
oran-ric-admin==>***REMOVED***
sample1==>***REMOVED***
helm==>***REMOVED***
```

#### 驗收標準
- [ ] Git 歷史中無明文密碼
- [ ] 使用 `git log --all -- config/grafana-values.yaml` 無結果
- [ ] 團隊成員重新 clone 倉庫

---

### 任務 10: 整合 Trivy 映像掃描

**負責人**: DevOps Engineer
**工時**: 6 小時
**優先級**: P1

#### 執行步驟

```bash
# Step 1: 安裝 Trivy
wget https://github.com/aquasecurity/trivy/releases/download/v0.47.0/trivy_0.47.0_Linux-64bit.tar.gz
tar -xzf trivy_0.47.0_Linux-64bit.tar.gz
sudo mv trivy /usr/local/bin/

# Step 2: 掃描當前所有映像
trivy image localhost:5000/xapp-kpimon:1.0.1
trivy image localhost:5000/xapp-traffic-steering:1.0.2
trivy image localhost:5000/xapp-qoe-predictor:1.0.1
trivy image localhost:5000/xapp-ran-control:1.0.1
trivy image localhost:5000/xapp-federated-learning:1.0.0
trivy image localhost:5000/e2-simulator:1.0.1

# Step 3: 生成報告
trivy image --format json --output trivy-report.json \
  localhost:5000/xapp-kpimon:1.0.1

# Step 4: 創建 GitHub Actions workflow
cat > .github/workflows/security-scan.yml <<EOF
name: Security Scan

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  trivy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: 'localhost:5000/xapp-kpimon:latest'
        format: 'sarif'
        output: 'trivy-results.sarif'
        severity: 'CRITICAL,HIGH'
        exit-code: '1'  # 發現 Critical/High 漏洞時失敗

    - name: Upload Trivy results to GitHub Security tab
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'
EOF

git add .github/workflows/security-scan.yml
git commit -m "ci: Add Trivy security scanning"
git push
```

#### 驗收標準
- [ ] Trivy 成功掃描所有映像
- [ ] GitHub Actions workflow 運行成功
- [ ] Security tab 顯示掃描結果
- [ ] 所有 Critical 漏洞已修復或記錄

---

### 任務 11: 實施 Pod Security Standards

**負責人**: Security Engineer
**工時**: 8 小時
**優先級**: P1

#### 執行步驟

```bash
# Step 1: 為 ricxapp namespace 啟用 PSS
kubectl label namespace ricxapp \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted

# Step 2: 更新所有 xApp Deployments
# (traffic-steering, kpimon, ran-control)

cat > /tmp/security-context-patch.yaml <<EOF
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: xapp
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
EOF

# Step 3: 應用 patch (每個 xApp)
kubectl patch deployment traffic-steering -n ricxapp --patch-file /tmp/security-context-patch.yaml
kubectl patch deployment kpimon -n ricxapp --patch-file /tmp/security-context-patch.yaml
kubectl patch deployment ran-control -n ricxapp --patch-file /tmp/security-context-patch.yaml

# Step 4: 驗證 Pods 重啟成功
kubectl get pods -n ricxapp -w
```

#### 驗收標準
- [ ] 所有 xApp Pods 以非 root 用戶運行
- [ ] `kubectl get pod <pod-name> -n ricxapp -o jsonpath='{.spec.securityContext.runAsNonRoot}'` 回傳 `true`
- [ ] 無 PSS 違規警告

---

### Sprint 1 Review & Retrospective

**時間**: 2025-12-04 (週三) 14:00-16:00

**檢視項目**:
- [ ] 所有 Critical 密碼已輪替
- [ ] Sealed Secrets 可正常使用
- [ ] Trivy 掃描整合到 CI/CD
- [ ] Git 歷史中無敏感資訊
- [ ] Pod Security Standards 實施

**回顧問題**:
1. 遇到的最大挑戰？
2. 哪些任務比預估時間長？
3. 下個 Sprint 需要改進的地方？

---

### Sprint 2: 網路與存取控制 (Week 3-4)

#### 📅 時程：2025-12-05 ~ 2025-12-18 (2 週)

#### 🎯 Sprint 目標
- 實施 Network Policy (Zero Trust)
- 為所有 xApps 建立專屬 ServiceAccount
- RBAC 最小權限審查
- 啟用 Service Mesh mTLS

---

### 任務 12: 實施 Network Policy

**負責人**: Network Engineer
**工時**: 8 小時
**優先級**: P1

#### 執行步驟

```bash
# Step 1: 實施 default-deny policy
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ricxapp
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Step 2: 為每個 xApp 創建 allow policy
# 範例: KPIMON
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kpimon-allow
  namespace: ricxapp
spec:
  podSelector:
    matchLabels:
      app: kpimon
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: e2-simulator
    - namespaceSelector:
        matchLabels:
          name: ricplt
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 8080  # Metrics
    - protocol: TCP
      port: 8081  # API
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: ricplt
      podSelector:
        matchLabels:
          app: dbaas  # Redis SDL
    ports:
    - protocol: TCP
      port: 6379
  - to:
    - namespaceSelector:
        matchLabels:
          name: ricplt
      podSelector:
        matchLabels:
          app: influxdb
    ports:
    - protocol: TCP
      port: 8086
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
EOF

# 為其他 xApps 重複相同流程
```

#### 驗收標準
- [ ] default-deny policy 已套用
- [ ] 每個 xApp 有專屬的 allow policy
- [ ] xApps 可正常通訊（E2 Simulator → xApps → Redis → InfluxDB）
- [ ] xApps 之間無法直接通訊（除非明確允許）

---

### 任務 13: 建立專屬 ServiceAccount

**負責人**: DevOps Engineer
**工時**: 6 小時
**優先級**: P1

#### 執行步驟

```bash
# Step 1: 為每個 xApp 創建 ServiceAccount
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kpimon-sa
  namespace: ricxapp
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traffic-steering-sa
  namespace: ricxapp
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ran-control-sa
  namespace: ricxapp
EOF

# Step 2: 創建最小權限 Role
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: xapp-basic-role
  namespace: ricxapp
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
  resourceNames: ["redis-auth"]  # 僅允許讀取 Redis 密碼
EOF

# Step 3: 綁定 Role 到 ServiceAccount
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kpimon-binding
  namespace: ricxapp
subjects:
- kind: ServiceAccount
  name: kpimon-sa
roleRef:
  kind: Role
  name: xapp-basic-role
  apiGroup: rbac.authorization.k8s.io
EOF

# Step 4: 更新 Deployments 使用新的 ServiceAccount
kubectl patch deployment kpimon -n ricxapp -p '{"spec":{"template":{"spec":{"serviceAccountName":"kpimon-sa"}}}}'
```

#### 驗收標準
- [ ] 每個 xApp 有專屬 ServiceAccount
- [ ] ServiceAccount 綁定到最小權限 Role
- [ ] xApps 可正常運行
- [ ] 無法執行未授權操作（測試: `kubectl auth can-i --as=system:serviceaccount:ricxapp:kpimon-sa delete pods -n ricxapp`）

---

### 任務 14: RBAC 最小權限審查

**負責人**: Security Engineer
**工時**: 6 小時
**優先級**: P1

#### 執行步驟

```bash
# Step 1: 審查所有 ClusterRoles
kubectl get clusterroles -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp | grep oran

# Step 2: 檢查 Prometheus ClusterRole 權限
kubectl get clusterrole prometheus-server -o yaml

# Step 3: 縮減權限（移除不必要的 resources）
kubectl edit clusterrole prometheus-server

# 移除:
# - apiGroups: ["apps"]
#   resources: ["deployments"]
#
# 保留:
# - apiGroups: [""]
#   resources: ["nodes", "services", "endpoints", "pods"]
#   verbs: ["get", "list", "watch"]

# Step 4: 審查所有 RoleBindings
kubectl get rolebindings -n ricxapp -o yaml > /tmp/ricxapp-rolebindings.yaml

# Step 5: 生成 RBAC 審計報告
kubectl rbac-audit -n ricxapp > /tmp/rbac-audit-report.txt
```

#### 驗收標準
- [ ] 所有 ClusterRoles 遵循最小權限原則
- [ ] 沒有不必要的 `*` 權限
- [ ] RBAC 審計報告無高危發現
- [ ] 文檔記錄所有權限變更

---

### 任務 15: 啟用 Service Mesh mTLS

**負責人**: Platform Engineer
**工時**: 12 小時
**優先級**: P1

#### 執行步驟

```bash
# Step 1: 安裝 Linkerd CLI
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# Step 2: 檢查集群相容性
linkerd check --pre

# Step 3: 安裝 Linkerd Control Plane
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -

# Step 4: 驗證安裝
linkerd check

# Step 5: 為 ricxapp namespace 啟用 auto-injection
kubectl annotate namespace ricxapp linkerd.io/inject=enabled

# Step 6: 重啟所有 xApp Pods 以注入 sidecar
kubectl rollout restart deployment -n ricxapp

# Step 7: 驗證 mTLS
linkerd viz stat deploy -n ricxapp
# MESHED 欄位應顯示 1/1

# Step 8: 檢查 mTLS 狀態
linkerd viz tap deploy/kpimon -n ricxapp
# 應看到 "tls=true"
```

#### 驗收標準
- [ ] Linkerd Control Plane 運行正常
- [ ] 所有 xApp Pods 已注入 Linkerd sidecar
- [ ] xApps 之間的通訊使用 mTLS
- [ ] Linkerd dashboard 可視化流量拓撲

---

### Sprint 2 Review & Retrospective

**時間**: 2025-12-18 (週三) 14:00-16:00

**檢視項目**:
- [ ] Zero Trust 網路模型已實施
- [ ] 所有 xApps 使用專屬 ServiceAccount
- [ ] RBAC 權限已收緊
- [ ] Service Mesh mTLS 啟用

**里程碑**:
🎉 **Phase 1 完成！安全成熟度 5/10 → 7/10**

---

## Phase 2: 高可用性與效能 (Week 5-8)

### Sprint 3: 資料層高可用性 (Week 5-6)

#### 📅 時程：2025-12-19 ~ 2026-01-01 (2 週)

#### 🎯 Sprint 目標
- 升級 Redis 至 Sentinel HA
- 配置 InfluxDB Clustering
- 實施 PostgreSQL HA

---

### 任務 16: 升級 Redis 至 Sentinel

**負責人**: Database Engineer
**工時**: 16 小時
**優先級**: P2

#### 架構設計

```
┌─────────────────────────────────────┐
│      Linkerd Service Mesh          │
│                                     │
│  ┌───────────┐   ┌───────────┐    │
│  │ Redis M   │◄──┤ Redis S1  │    │
│  │ (Master)  │   │ (Slave)   │    │
│  └─────┬─────┘   └───────────┘    │
│        │                           │
│        └──────┬────────────────────│
│               ▼                    │
│         ┌───────────┐              │
│         │ Redis S2  │              │
│         │ (Slave)   │              │
│         └───────────┘              │
│                                     │
│  ┌─────────┐ ┌─────────┐ ┌───────┐│
│  │Sentinel │ │Sentinel │ │Sent..││
│  │   1     │ │   2     │ │  3   ││
│  └─────────┘ └─────────┘ └───────┘│
└─────────────────────────────────────┘
```

#### 執行步驟

```bash
# Step 1: 備份當前 Redis 資料
kubectl exec -it dbaas-xxxxx -n ricplt -- redis-cli BGSAVE
kubectl cp ricplt/dbaas-xxxxx:/data/dump.rdb /backup/redis-pre-ha.rdb

# Step 2: 部署 Redis HA Helm Chart
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install redis-ha bitnami/redis \
  --namespace ricplt \
  --set architecture=replication \
  --set sentinel.enabled=true \
  --set master.persistence.enabled=true \
  --set master.persistence.size=20Gi \
  --set replica.replicaCount=2 \
  --set replica.persistence.enabled=true \
  --set replica.persistence.size=20Gi \
  --set sentinel.quorum=2 \
  --set master.resources.requests.memory=512Mi \
  --set master.resources.requests.cpu=250m \
  --set auth.enabled=true \
  --set auth.password="${REDIS_PASSWORD}"

# Step 3: 等待所有 Pods 就緒
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=redis \
  -n ricplt \
  --timeout=300s

# Step 4: 驗證 Sentinel 配置
kubectl exec -it redis-ha-master-0 -n ricplt -- redis-cli -a $REDIS_PASSWORD INFO replication
# role:master
# connected_slaves:2

# Step 5: 測試故障切換
kubectl delete pod redis-ha-master-0 -n ricplt
# Sentinel 應自動選舉新 Master
sleep 30
kubectl exec -it redis-ha-master-0 -n ricplt -- redis-cli -a $REDIS_PASSWORD ROLE
# 應顯示 master 或 slave

# Step 6: 更新 xApps 連線至 Sentinel
# 修改 xApps ConfigMap:
# REDIS_MASTER_SERVICE_HOST=redis-ha.ricplt.svc.cluster.local
# REDIS_SENTINEL_SERVICE_HOST=redis-ha.ricplt.svc.cluster.local
# REDIS_SENTINEL_PORT=26379

# Step 7: 滾動重啟 xApps
kubectl rollout restart deployment -n ricxapp

# Step 8: 遷移資料 (如果需要)
# 使用 redis-cli --rdb 從舊 Redis 同步到新 Redis
```

#### 驗收標準
- [ ] Redis Master + 2 Replicas 運行中
- [ ] 3 個 Sentinel 實例運行中
- [ ] 手動刪除 Master Pod 後自動故障切換
- [ ] 所有 xApps 成功連線新 Redis
- [ ] RTO < 30 秒, RPO < 1 秒

---

### 任務 17: 配置 InfluxDB Clustering

**負責人**: Database Engineer
**工時**: 12 小時
**優先級**: P2

**注意**: InfluxDB 2.x OSS 版本不支援 clustering。需要考慮以下方案：

#### 方案選擇

**方案 A: 升級至 InfluxDB Enterprise（推薦）**
- 成本: $$$
- 優點: 原生 clustering、自動 sharding
- 缺點: 商業授權

**方案 B: 使用 InfluxDB Relay + HAProxy**
- 成本: $
- 優點: 開源方案
- 缺點: 雙寫可能資料不一致

**方案 C: 保持單節點 + 強化備份**
- 成本: 低
- 優點: 簡單
- 缺點: 仍有單點故障

#### 執行步驟（方案 B）

```bash
# Step 1: 部署第二個 InfluxDB 實例
helm install influxdb-2 influxdata/influxdb2 \
  --namespace ricplt \
  --set persistence.enabled=true \
  --set persistence.size=100Gi \
  --set resources.requests.memory=2Gi

# Step 2: 部署 InfluxDB Relay
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: influxdb-relay
  namespace: ricplt
spec:
  replicas: 2
  selector:
    matchLabels:
      app: influxdb-relay
  template:
    metadata:
      labels:
        app: influxdb-relay
    spec:
      containers:
      - name: relay
        image: influxdata/influxdb-relay:latest
        ports:
        - containerPort: 9096
        volumeMounts:
        - name: config
          mountPath: /etc/influxdb-relay
      volumes:
      - name: config
        configMap:
          name: influxdb-relay-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: influxdb-relay-config
  namespace: ricplt
data:
  relay.toml: |
    [[http]]
    name = "ric-relay"
    bind-addr = "0.0.0.0:9096"
    output = [
      { name="influxdb1", location="http://influxdb-0.ricplt.svc:8086/write" },
      { name="influxdb2", location="http://influxdb-2-0.ricplt.svc:8086/write" }
    ]
EOF

# Step 3: 更新 xApps 連線至 Relay
# INFLUXDB_URL=http://influxdb-relay.ricplt.svc:9096
```

#### 驗收標準
- [ ] 兩個 InfluxDB 實例運行中
- [ ] InfluxDB Relay 雙寫成功
- [ ] 手動刪除一個 InfluxDB 後寫入仍成功
- [ ] 資料同步驗證（查詢兩個實例資料一致）

---

### 任務 18: 實施 PostgreSQL HA

**負責人**: Database Engineer
**工時**: 8 小時
**優先級**: P2

#### 執行步驟

```bash
# Step 1: 部署 PostgreSQL HA (使用 Patroni)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgresql-ha bitnami/postgresql-ha \
  --namespace ricplt \
  --set postgresql.replicaCount=3 \
  --set postgresql.persistence.enabled=true \
  --set postgresql.persistence.size=20Gi \
  --set postgresql.auth.password="${POSTGRES_PASSWORD}"

# Step 2: 驗證 Patroni 集群
kubectl exec -it postgresql-ha-postgresql-0 -n ricplt -- patronictl list
# 應顯示 Leader + 2 Replicas

# Step 3: 遷移 Kong 資料至新 PostgreSQL
# (Kong 是唯一使用 PostgreSQL 的組件)

# Backup 舊資料
kubectl exec -it kong-postgresql-0 -n ricplt -- \
  pg_dump -U kong kong > /tmp/kong-backup.sql

# Restore 到新 PostgreSQL
kubectl exec -it postgresql-ha-postgresql-0 -n ricplt -- \
  psql -U postgres -d kong -f /tmp/kong-backup.sql

# Step 4: 更新 Kong 連線
helm upgrade kong kong/kong \
  --namespace ricplt \
  --set postgresql.enabled=false \
  --set env.database=postgres \
  --set env.pg_host=postgresql-ha-postgresql.ricplt.svc \
  --set env.pg_port=5432 \
  --set env.pg_user=postgres \
  --set env.pg_password="${POSTGRES_PASSWORD}"

# Step 5: 測試故障切換
kubectl delete pod postgresql-ha-postgresql-0 -n ricplt
# Patroni 應自動選舉新 Leader
```

#### 驗收標準
- [ ] 3 節點 PostgreSQL 集群運行中
- [ ] Patroni 自動故障切換成功
- [ ] Kong 成功連線新 PostgreSQL
- [ ] 資料完整性驗證

---

### Sprint 3 Review

**時間**: 2026-01-01 (週三) 14:00-16:00

**檢視項目**:
- [ ] Redis Sentinel HA 運行中
- [ ] InfluxDB 雙寫機制運行中
- [ ] PostgreSQL HA 運行中
- [ ] RTO < 5 分鐘, RPO < 1 分鐘

---

### Sprint 4: 效能調校與擴展 (Week 7-8)

#### 📅 時程：2026-01-02 ~ 2026-01-15 (2 週)

#### 🎯 Sprint 目標
- 優化資源配置
- 實施 HPA
- 部署 Jaeger 分散式追蹤
- E2 indication batching 優化

---

### 任務 19: 優化資源配置

**負責人**: Performance Engineer
**工時**: 4 小時
**優先級**: P2

#### 執行步驟

```bash
# Step 1: 應用優化配置
cp config/optimized-values.yaml /tmp/optimized-values.yaml

# Step 2: 逐一升級組件
# Prometheus
helm upgrade r4-infrastructure-prometheus prometheus-community/prometheus \
  -n ricplt \
  -f /tmp/optimized-values.yaml

# Grafana
helm upgrade oran-grafana grafana/grafana \
  -n ricplt \
  -f /tmp/optimized-values.yaml

# 所有 xApps
for xapp in kpimon traffic-steering qoe-predictor ran-control federated-learning; do
  kubectl set resources deployment/$xapp -n ricxapp \
    --requests=cpu=50m,memory=128Mi \
    --limits=cpu=200m,memory=512Mi
done

# Step 3: 監控資源使用率（7 天）
kubectl top pods -n ricplt
kubectl top pods -n ricxapp
```

#### 驗收標準
- [ ] CPU 使用率 30-70%
- [ ] Memory 使用率 40-80%
- [ ] 無 CPU throttling 事件
- [ ] 無 OOMKilled Pods

---

### 任務 20: 實施 HPA

**負責人**: Platform Engineer
**工時**: 12 小時
**優先級**: P2

#### 執行步驟

```bash
# Step 1: 安裝 Metrics Server (如果尚未安裝)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Step 2: 為 E2Term 創建 HPA
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: e2term-hpa
  namespace: ricplt
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: e2term
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 30
      selectPolicy: Max
EOF

# Step 3: 為 KPIMON 創建 HPA
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: kpimon-hpa
  namespace: ricxapp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: kpimon
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Pods
    pods:
      metric:
        name: kpimon_messages_received_total
      target:
        type: AverageValue
        averageValue: "1000"  # 每個 Pod 處理 1000 msg/s
EOF

# Step 4: 負載測試驗證 HPA
# 增加 E2 Simulator 流量
kubectl scale deployment e2-simulator -n ricxapp --replicas=5
# 觀察 E2Term 和 KPIMON 自動擴展
watch kubectl get hpa -n ricplt
watch kubectl get hpa -n ricxapp
```

#### 驗收標準
- [ ] HPA 成功創建
- [ ] 負載增加時自動擴展
- [ ] 負載降低時自動縮減
- [ ] 擴展延遲 < 2 分鐘

---

### 任務 21: 部署 Jaeger 分散式追蹤

**負責人**: Observability Engineer
**工時**: 8 小時
**優先級**: P2

#### 執行步驟

```bash
# Step 1: 安裝 Jaeger Operator
kubectl create namespace observability
kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.50.0/jaeger-operator.yaml -n observability

# Step 2: 部署 Jaeger 實例
cat <<EOF | kubectl apply -f -
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: jaeger
  namespace: observability
spec:
  strategy: production
  storage:
    type: elasticsearch
    options:
      es:
        server-urls: http://elasticsearch:9200
  ingress:
    enabled: true
  query:
    serviceType: LoadBalancer
EOF

# Step 3: 為 xApps 啟用 tracing
# 修改 xApp 代碼添加 OpenTelemetry instrumentation
# (範例: KPIMON)

# requirements.txt 添加:
# opentelemetry-api
# opentelemetry-sdk
# opentelemetry-instrumentation-flask
# opentelemetry-exporter-jaeger

# kpimon.py 添加:
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.jaeger.thrift import JaegerExporter

tracer_provider = TracerProvider()
jaeger_exporter = JaegerExporter(
    agent_host_name="jaeger-agent.observability.svc",
    agent_port=6831,
)
tracer_provider.add_span_processor(BatchSpanProcessor(jaeger_exporter))
trace.set_tracer_provider(tracer_provider)
tracer = trace.get_tracer(__name__)

# 在關鍵函數添加 span
@tracer.start_as_current_span("process_kpi_indication")
def process_kpi_indication(indication):
    # ...

# Step 4: 重建並部署所有 xApps
```

#### 驗收標準
- [ ] Jaeger UI 可訪問
- [ ] 可看到 xApps 的 traces
- [ ] 可追蹤完整請求鏈路（E2 Sim → KPIMON → Redis → InfluxDB）
- [ ] P99 延遲 < 50ms

---

### 任務 22: E2 Indication Batching 優化

**負責人**: Performance Engineer
**工時**: 8 小時
**優先級**: P2

#### 執行步驟

```python
# Step 1: 修改 E2 Simulator 支援 batching
# simulator/e2-simulator/src/e2_simulator.py

class E2Simulator:
    def __init__(self):
        self.batch_size = int(os.getenv('BATCH_SIZE', '10'))
        self.batch_interval = int(os.getenv('BATCH_INTERVAL', '1'))  # 秒
        self.indication_buffer = []

    def generate_batched_indications(self) -> List[Dict]:
        """生成批次 indications"""
        indications = []
        for _ in range(self.batch_size):
            indications.append(self.generate_kpi_indication())
        return indications

    def send_batched_indications(self, xapp_name: str):
        """批次發送 indications"""
        batch = self.generate_batched_indications()

        url = f"http://{self.config['xapps'][xapp_name]['host']}:" \
              f"{self.config['xapps'][xapp_name]['port']}" \
              f"{self.config['xapps'][xapp_name]['endpoint']}/batch"

        try:
            response = requests.post(url, json=batch, timeout=5)
            if response.status_code == 200:
                self.BATCHES_SENT.labels(xapp=xapp_name).inc()
                logger.info(f"Sent batch of {len(batch)} indications to {xapp_name}")
        except Exception as e:
            logger.error(f"Failed to send batch to {xapp_name}: {e}")

# Step 2: 修改 KPIMON 支援 batch processing
# xapps/kpimon/src/kpimon.py

@app.route('/e2/indication/batch', methods=['POST'])
def handle_batch_indication():
    """處理批次 E2 indications"""
    indications = request.json

    with tracer.start_as_current_span("process_batch") as span:
        span.set_attribute("batch_size", len(indications))

        # 並行處理 indications
        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = [executor.submit(process_single_indication, ind)
                      for ind in indications]
            results = [f.result() for f in futures]

        # 批次寫入 Redis
        pipe = sdl.redis_client.pipeline()
        for ind in indications:
            pipe.set(f"kpi:{ind['cell_id']}:{ind['timestamp']}",
                    json.dumps(ind))
        pipe.execute()

        # 批次寫入 InfluxDB
        points = [
            Point("kpi")
            .tag("cell_id", ind["cell_id"])
            .field("prb_usage", ind["kpi_value"])
            .time(ind["timestamp"])
            for ind in indications
        ]
        influx_write_api.write(bucket="ricplt", record=points)

    return jsonify({"status": "success", "processed": len(indications)})

# Step 3: 效能測試
# 測試不同 batch size 的吞吐量與延遲
```

#### 驗收標準
- [ ] Batch size = 10 時吞吐量提升 5x
- [ ] P99 延遲 < 20ms
- [ ] CPU 使用率降低 30%
- [ ] Redis/InfluxDB 寫入次數減少 10x

---

### Sprint 4 Review

**時間**: 2026-01-15 (週三) 14:00-16:00

**檢視項目**:
- [ ] 資源配置優化完成
- [ ] HPA 運行正常
- [ ] Jaeger tracing 可視化完整請求鏈路
- [ ] E2 batching 吞吐量提升 5x

**里程碑**:
🎉 **Phase 2 完成！系統可支援 50+ E2 nodes**

---

## Phase 3: 測試與 CI/CD (Week 9-12)

### Sprint 5: 測試基礎設施 (Week 9-10)

#### 📅 時程：2026-01-16 ~ 2026-01-29 (2 週)

#### 🎯 Sprint 目標
- 建立 pytest 測試框架
- Mock SDL/RMR/Prometheus 客戶端
- KPIMON + Traffic Steering 單元測試覆蓋率 60%

---

### 任務 23: 建立 pytest 框架

**負責人**: QA Engineer
**工時**: 8 小時
**優先級**: P3

#### 執行步驟

```bash
# Step 1: 安裝測試依賴
cd /home/thc1006/oran-ric-platform/xapps/kpimon

cat > requirements-dev.txt <<EOF
pytest==7.4.3
pytest-cov==4.1.0
pytest-mock==3.12.0
pytest-asyncio==0.21.1
pytest-xdist==3.5.0  # 並行測試
pytest-benchmark==4.0.0
fakeredis==2.20.0
EOF

pip install -r requirements-dev.txt

# Step 2: 創建測試目錄結構
mkdir -p tests/{unit,integration,fixtures}
touch tests/__init__.py
touch tests/conftest.py

# Step 3: 創建 conftest.py (共用 fixtures)
cat > tests/conftest.py <<EOF
import pytest
from unittest.mock import MagicMock
from fakeredis import FakeRedis

@pytest.fixture
def mock_sdl():
    """Mock SDL client"""
    mock = MagicMock()
    mock.redis_client = FakeRedis()
    return mock

@pytest.fixture
def mock_rmr():
    """Mock RMR client"""
    mock = MagicMock()
    mock.send_message = MagicMock(return_value=True)
    return mock

@pytest.fixture
def mock_metrics():
    """Mock Prometheus metrics"""
    mock = MagicMock()
    return mock

@pytest.fixture
def sample_kpi_indication():
    """Sample KPI indication"""
    return {
        "cell_id": "cell_001",
        "ue_id": "ue_001",
        "kpi_type": "RRU.PrbUsedDl",
        "kpi_value": 45.5,
        "timestamp": "2025-01-16T10:00:00Z"
    }
EOF

# Step 4: 創建 pytest.ini
cat > pytest.ini <<EOF
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts =
    -v
    --cov=src
    --cov-report=html
    --cov-report=term-missing
    --cov-fail-under=60
    -n auto  # 並行測試
markers =
    unit: Unit tests
    integration: Integration tests
    slow: Slow tests
EOF
```

#### 驗收標準
- [ ] pytest 框架配置完成
- [ ] 執行 `pytest` 成功
- [ ] Coverage 報告生成
- [ ] 並行測試運行成功

---

### 任務 24: Mock 框架開發

**負責人**: Developer
**工時**: 8 小時
**優先級**: P3

#### 執行步驟

```python
# Step 1: 創建 MockSDL
# tests/fixtures/mock_sdl.py

class MockSDL:
    """Mock Shared Data Layer"""

    def __init__(self):
        self.data = {}
        self.call_count = {}

    def set(self, key: str, value: str) -> bool:
        self.data[key] = value
        self._increment_call('set')
        return True

    def get(self, key: str) -> Optional[str]:
        self._increment_call('get')
        return self.data.get(key)

    def delete(self, key: str) -> bool:
        if key in self.data:
            del self.data[key]
            self._increment_call('delete')
            return True
        return False

    def _increment_call(self, method: str):
        self.call_count[method] = self.call_count.get(method, 0) + 1

    def reset(self):
        self.data.clear()
        self.call_count.clear()

# Step 2: 創建 MockRMR
# tests/fixtures/mock_rmr.py

class MockRMR:
    """Mock RIC Message Router"""

    def __init__(self):
        self.sent_messages = []
        self.received_messages = []

    def send(self, msg_type: int, payload: bytes,
             meid: str = None) -> bool:
        self.sent_messages.append({
            'type': msg_type,
            'payload': payload,
            'meid': meid,
            'timestamp': time.time()
        })
        return True

    def receive(self, timeout: int = 1000) -> Optional[Dict]:
        if self.received_messages:
            return self.received_messages.pop(0)
        return None

    def inject_message(self, msg_type: int, payload: bytes):
        """測試用：注入接收訊息"""
        self.received_messages.append({
            'type': msg_type,
            'payload': payload
        })

# Step 3: 創建 MockMetrics
# tests/fixtures/mock_metrics.py

class MockMetricsCollector:
    """Mock Prometheus Metrics Collector"""

    def __init__(self):
        self.counters = {}
        self.gauges = {}
        self.histograms = {}

    def counter(self, name: str) -> MockCounter:
        if name not in self.counters:
            self.counters[name] = MockCounter(name)
        return self.counters[name]

    def gauge(self, name: str) -> MockGauge:
        if name not in self.gauges:
            self.gauges[name] = MockGauge(name)
        return self.gauges[name]

    def histogram(self, name: str) -> MockHistogram:
        if name not in self.histograms:
            self.histograms[name] = MockHistogram(name)
        return self.histograms[name]

class MockCounter:
    def __init__(self, name: str):
        self.name = name
        self.value = 0
        self.labels_dict = {}

    def labels(self, **kwargs):
        key = tuple(sorted(kwargs.items()))
        if key not in self.labels_dict:
            self.labels_dict[key] = MockCounter(f"{self.name}_{key}")
        return self.labels_dict[key]

    def inc(self, amount: int = 1):
        self.value += amount
```

#### 驗收標準
- [ ] MockSDL 通過所有 SDL 測試
- [ ] MockRMR 通過所有 RMR 測試
- [ ] MockMetrics 記錄所有 metrics 操作
- [ ] Mock 物件可完全替代真實物件

---

### 任務 25: KPIMON 單元測試

**負責人**: Developer
**工時**: 8 小時
**優先級**: P3

#### 執行步驟

```python
# tests/unit/test_kpimon_processor.py

import pytest
from src.kpimon import KPIProcessor

class TestKPIProcessor:

    @pytest.fixture
    def processor(self, mock_sdl, mock_rmr, mock_metrics):
        return KPIProcessor(
            sdl=mock_sdl,
            rmr=mock_rmr,
            metrics=mock_metrics
        )

    def test_process_valid_indication(self, processor, sample_kpi_indication):
        """測試處理有效的 KPI indication"""
        result = processor.process_indication(sample_kpi_indication)

        assert result is True
        assert processor.sdl.get(f"kpi:{sample_kpi_indication['cell_id']}") is not None
        assert processor.metrics.counters['kpimon_messages_received_total'].value == 1

    def test_process_invalid_indication(self, processor):
        """測試處理無效的 indication"""
        invalid_indication = {"invalid": "data"}

        result = processor.process_indication(invalid_indication)

        assert result is False
        assert processor.metrics.counters['kpimon_errors_total'].value == 1

    def test_high_prb_usage_alert(self, processor):
        """測試 PRB 使用率過高告警"""
        high_prb_indication = {
            "cell_id": "cell_001",
            "kpi_type": "RRU.PrbUsedDl",
            "kpi_value": 95.0  # 超過閾值 85%
        }

        processor.process_indication(high_prb_indication)

        # 驗證告警訊息已發送
        sent_messages = processor.rmr.sent_messages
        assert len(sent_messages) == 1
        assert sent_messages[0]['type'] == 12050  # RIC_INDICATION

    @pytest.mark.parametrize("kpi_value,expected_alarm", [
        (50.0, False),
        (85.0, False),
        (85.1, True),
        (100.0, True),
    ])
    def test_prb_threshold(self, processor, kpi_value, expected_alarm):
        """測試不同 PRB 值的告警行為"""
        indication = {
            "cell_id": "cell_001",
            "kpi_type": "RRU.PrbUsedDl",
            "kpi_value": kpi_value
        }

        processor.process_indication(indication)

        if expected_alarm:
            assert len(processor.rmr.sent_messages) > 0
        else:
            assert len(processor.rmr.sent_messages) == 0

# tests/unit/test_kpimon_subscription.py

class TestSubscriptionManager:

    def test_create_subscription(self, processor):
        """測試創建訂閱"""
        sub_req = {
            "subscription_id": "sub_001",
            "cell_id": "cell_001",
            "kpi_types": ["RRU.PrbUsedDl", "RRU.PrbUsedUl"]
        }

        result = processor.create_subscription(sub_req)

        assert result is True
        assert processor.sdl.get("subscription:sub_001") is not None

    def test_duplicate_subscription(self, processor):
        """測試重複訂閱"""
        sub_req = {"subscription_id": "sub_001"}

        processor.create_subscription(sub_req)
        result = processor.create_subscription(sub_req)

        assert result is False
        assert processor.metrics.counters['kpimon_subscription_failures_total'].value == 1

# 執行測試
# pytest tests/unit/ -v --cov=src --cov-report=html
```

#### 驗收標準
- [ ] 單元測試覆蓋率 60%+
- [ ] 所有測試通過
- [ ] 測試執行時間 < 10 秒
- [ ] Coverage 報告生成於 `htmlcov/`

---

### 任務 26: Traffic Steering 單元測試

**負責人**: Developer
**工時**: 8 小時
**優先級**: P3

#### 執行步驟

```python
# tests/unit/test_ts_algorithm.py

import pytest
from src.traffic_steering import LoadBalancingAlgorithm

class TestLoadBalancingAlgorithm:

    @pytest.fixture
    def algorithm(self):
        return LoadBalancingAlgorithm()

    def test_select_target_cell_round_robin(self, algorithm):
        """測試 Round Robin 負載均衡"""
        cells = ["cell_001", "cell_002", "cell_003"]

        # 連續 6 次請求應依序選擇 cell
        results = [algorithm.select_target_cell(cells) for _ in range(6)]

        assert results == ["cell_001", "cell_002", "cell_003",
                          "cell_001", "cell_002", "cell_003"]

    def test_select_target_cell_load_based(self, algorithm, mock_sdl):
        """測試基於負載的選擇"""
        # 模擬不同 cell 的負載
        mock_sdl.set("load:cell_001", "90")  # 高負載
        mock_sdl.set("load:cell_002", "50")  # 中負載
        mock_sdl.set("load:cell_003", "30")  # 低負載

        cells = ["cell_001", "cell_002", "cell_003"]

        # 應選擇負載最低的 cell_003
        result = algorithm.select_target_cell(cells, strategy="load_based")

        assert result == "cell_003"

    @pytest.mark.benchmark
    def test_algorithm_performance(self, algorithm, benchmark):
        """效能測試：1000 次決策應 < 100ms"""
        cells = ["cell_001", "cell_002", "cell_003"]

        def run_decisions():
            for _ in range(1000):
                algorithm.select_target_cell(cells)

        result = benchmark(run_decisions)

        assert result.stats.mean < 0.0001  # < 0.1ms per decision

# tests/unit/test_ts_handover.py

class TestHandoverManager:

    def test_initiate_handover(self, manager, mock_rmr):
        """測試發起切換"""
        handover_req = {
            "ue_id": "ue_001",
            "source_cell": "cell_001",
            "target_cell": "cell_002"
        }

        result = manager.initiate_handover(handover_req)

        assert result is True
        # 驗證 RMR 訊息已發送
        assert len(mock_rmr.sent_messages) == 1
        assert mock_rmr.sent_messages[0]['type'] == 12030  # RIC_CONTROL_REQ

    def test_handover_failure_handling(self, manager):
        """測試切換失敗處理"""
        handover_req = {
            "ue_id": "ue_001",
            "source_cell": "cell_001",
            "target_cell": "nonexistent_cell"  # 不存在的 cell
        }

        result = manager.initiate_handover(handover_req)

        assert result is False
        assert manager.metrics.counters['ts_handover_failures_total'].value == 1

# 執行測試
# pytest tests/unit/ --benchmark-only
```

#### 驗收標準
- [ ] 單元測試覆蓋率 60%+
- [ ] 所有測試通過
- [ ] 效能測試達標（1000 decisions < 100ms）
- [ ] 邊界條件測試完整

---

### Sprint 5 Review

**時間**: 2026-01-29 (週三) 14:00-16:00

**檢視項目**:
- [ ] pytest 框架建立完成
- [ ] Mock 框架可完全替代真實組件
- [ ] KPIMON 單元測試覆蓋率 60%+
- [ ] Traffic Steering 單元測試覆蓋率 60%+

---

### Sprint 6: CI/CD Pipeline (Week 11-12)

#### 📅 時程：2026-01-30 ~ 2026-02-12 (2 週)

#### 🎯 Sprint 目標
- 建立 GitHub Actions CI/CD workflow
- 整合測試、linting、安全掃描
- Helm chart 自動化測試
- E2E 測試自動化

---

### 任務 27: 建立 GitHub Actions CI

**負責人**: DevOps Engineer
**工時**: 8 小時
**優先級**: P3

#### 執行步驟

```yaml
# .github/workflows/ci.yml

name: CI Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'

    - name: Install dependencies
      run: |
        pip install flake8 black pylint

    - name: Run flake8
      run: flake8 xapps/ --max-line-length=120

    - name: Run black
      run: black --check xapps/

    - name: Run pylint
      run: pylint xapps/ --fail-under=8.0

  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        xapp: [kpimon, traffic-steering, qoe-predictor, ran-control]
    steps:
    - uses: actions/checkout@v3

    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'

    - name: Install dependencies
      run: |
        cd xapps/${{ matrix.xapp }}
        pip install -r requirements.txt
        pip install -r requirements-dev.txt

    - name: Run tests
      run: |
        cd xapps/${{ matrix.xapp }}
        pytest tests/ -v --cov=src --cov-report=xml

    - name: Upload coverage
      uses: codecov/codecov-action@v3
      with:
        file: ./xapps/${{ matrix.xapp }}/coverage.xml
        flags: ${{ matrix.xapp }}

  security:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'trivy-results.sarif'
        severity: 'CRITICAL,HIGH'

    - name: Upload Trivy results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'

  build:
    needs: [lint, test, security]
    runs-on: ubuntu-latest
    strategy:
      matrix:
        xapp: [kpimon, traffic-steering, qoe-predictor, ran-control, federated-learning]
    steps:
    - uses: actions/checkout@v3

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2

    - name: Build xApp image
      uses: docker/build-push-action@v4
      with:
        context: xapps/${{ matrix.xapp }}
        push: false
        tags: localhost:5000/xapp-${{ matrix.xapp }}:${{ github.sha }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

git add .github/workflows/ci.yml
git commit -m "ci: Add comprehensive CI pipeline"
git push
```

#### 驗收標準
- [ ] CI pipeline 在每次 push 時自動執行
- [ ] 所有 jobs 成功通過
- [ ] Coverage 報告上傳到 Codecov
- [ ] 安全掃描結果顯示在 Security tab

---

### 任務 28: Helm Chart 自動化測試

**負責人**: DevOps Engineer
**工時**: 8 小時
**優先級**: P3

#### 執行步驟

```bash
# Step 1: 為每個 Helm chart 創建測試
# xapps/kpimon/chart/templates/tests/test-connection.yaml

apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "kpimon.fullname" . }}-test-connection"
  labels:
    {{- include "kpimon.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
spec:
  containers:
  - name: wget
    image: busybox
    command: ['wget']
    args: ['{{ include "kpimon.fullname" . }}:8080/ric/v1/health/ready']
  restartPolicy: Never

# Step 2: 添加 Helm lint 到 CI
# .github/workflows/helm-test.yml

name: Helm Tests

on: [push, pull_request]

jobs:
  helm-lint:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Install Helm
      uses: azure/setup-helm@v3
      with:
        version: '3.13.0'

    - name: Lint Helm charts
      run: |
        for chart in xapps/*/chart; do
          echo "Linting $chart"
          helm lint $chart
        done

  helm-test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Create k3s cluster
      uses: debianmaster/actions-k3s@master
      with:
        version: 'v1.28.5-k3s1'

    - name: Install Helm charts
      run: |
        for chart in xapps/kpimon/chart xapps/traffic-steering/chart; do
          helm install $(basename $(dirname $chart)) $chart \
            --wait --timeout 5m
        done

    - name: Run Helm tests
      run: |
        helm test kpimon
        helm test traffic-steering

# Step 3: Chart version bump automation
# scripts/bump-chart-version.sh

#!/bin/bash
set -e

CHART_PATH=$1
VERSION_TYPE=$2  # major, minor, patch

current_version=$(grep '^version:' $CHART_PATH/Chart.yaml | awk '{print $2}')

IFS='.' read -ra ADDR <<< "$current_version"
major=${ADDR[0]}
minor=${ADDR[1]}
patch=${ADDR[2]}

case $VERSION_TYPE in
  major) ((major++)); minor=0; patch=0 ;;
  minor) ((minor++)); patch=0 ;;
  patch) ((patch++)) ;;
esac

new_version="$major.$minor.$patch"

sed -i "s/^version: .*/version: $new_version/" $CHART_PATH/Chart.yaml
echo "Bumped version from $current_version to $new_version"
```

#### 驗收標準
- [ ] 所有 Helm charts 通過 lint
- [ ] Helm test hooks 自動執行
- [ ] Chart version bump 腳本可用
- [ ] CI 自動測試 chart 部署

---

### 任務 29: E2E 測試自動化

**負責人**: QA Engineer
**工時**: 12 小時
**優先級**: P3

#### 執行步驟

```python
# tests/e2e/test_complete_flow.py

import pytest
import requests
import time
from kubernetes import client, config

class TestCompleteE2EFlow:

    @pytest.fixture(scope="class")
    def k8s_client(self):
        """Kubernetes client"""
        config.load_kube_config()
        return client.CoreV1Api()

    def test_01_all_pods_running(self, k8s_client):
        """測試 1: 所有 Pods 運行中"""
        # Check ricplt namespace
        ricplt_pods = k8s_client.list_namespaced_pod(namespace="ricplt")
        for pod in ricplt_pods.items:
            assert pod.status.phase == "Running", \
                f"Pod {pod.metadata.name} not running: {pod.status.phase}"

        # Check ricxapp namespace
        ricxapp_pods = k8s_client.list_namespaced_pod(namespace="ricxapp")
        for pod in ricxapp_pods.items:
            assert pod.status.phase == "Running", \
                f"Pod {pod.metadata.name} not running: {pod.status.phase}"

    def test_02_e2_simulator_sends_indications(self, k8s_client):
        """測試 2: E2 Simulator 發送 indications"""
        # 取得 E2 Simulator logs
        logs = k8s_client.read_namespaced_pod_log(
            name="e2-simulator-xxxxx",
            namespace="ricxapp",
            tail_lines=100
        )

        # 驗證向所有 xApps 發送
        assert "Sent indication to kpimon" in logs
        assert "Sent indication to traffic-steering" in logs
        assert "Sent indication to qoe-predictor" in logs
        assert "Sent indication to ran-control" in logs
        assert "Sent indication to federated-learning" in logs

    def test_03_kpimon_processes_indications(self):
        """測試 3: KPIMON 處理 indications"""
        # 查詢 Prometheus metrics
        response = requests.get(
            "http://prometheus-server.ricplt.svc:80/api/v1/query",
            params={"query": "kpimon_messages_received_total"}
        )

        assert response.status_code == 200
        data = response.json()['data']['result']
        assert len(data) > 0

        # 驗證 counter 有增加
        value = float(data[0]['value'][1])
        assert value > 0

    def test_04_data_written_to_redis(self, k8s_client):
        """測試 4: 資料寫入 Redis"""
        # 進入 Redis Pod 執行查詢
        exec_command = [
            '/bin/sh',
            '-c',
            'redis-cli -a $REDIS_PASSWORD KEYS "kpi:*" | wc -l'
        ]

        resp = stream(
            k8s_client.connect_get_namespaced_pod_exec,
            "redis-ha-master-0",
            "ricplt",
            command=exec_command,
            stderr=True, stdin=False,
            stdout=True, tty=False
        )

        key_count = int(resp.strip())
        assert key_count > 0, "No KPI data in Redis"

    def test_05_data_written_to_influxdb(self):
        """測試 5: 資料寫入 InfluxDB"""
        response = requests.post(
            "http://influxdb.ricplt.svc:8086/api/v2/query",
            headers={
                "Authorization": f"Token {INFLUXDB_TOKEN}",
                "Content-Type": "application/json"
            },
            json={
                "query": """
                    from(bucket: "ricplt")
                      |> range(start: -5m)
                      |> filter(fn: (r) => r["_measurement"] == "kpi")
                      |> count()
                """,
                "type": "flux"
            }
        )

        assert response.status_code == 200
        # 驗證有資料點
        # ...

    def test_06_grafana_dashboards_accessible(self):
        """測試 6: Grafana dashboard 可訪問"""
        response = requests.get(
            "http://oran-grafana.ricplt.svc/api/dashboards/uid/oran-ric-overview",
            auth=("admin", GRAFANA_PASSWORD)
        )

        assert response.status_code == 200

    def test_07_alertmanager_receives_alerts(self):
        """測試 7: AlertManager 接收告警"""
        response = requests.get(
            "http://alertmanager.ricplt.svc:9093/api/v2/alerts"
        )

        assert response.status_code == 200
        # 驗證告警規則已載入
        # ...

# 執行 E2E 測試
# pytest tests/e2e/ -v --maxfail=1
```

#### 驗收標準
- [ ] 7 個 E2E 測試全部通過
- [ ] 測試執行時間 < 5 分鐘
- [ ] CI 自動執行 E2E 測試
- [ ] 測試失敗時提供詳細日誌

---

### Sprint 6 Review & Retrospective

**時間**: 2026-02-12 (週三) 14:00-16:00

**檢視項目**:
- [ ] GitHub Actions CI/CD pipeline 完整
- [ ] 所有 jobs 自動執行
- [ ] Helm charts 通過自動化測試
- [ ] E2E 測試覆蓋完整流程

**里程碑**:
🎉 **Phase 3 完成！單元測試覆蓋率 70%，CI/CD 完全自動化**

---

## 🎉 90 天計劃完成慶祝

**最終回顧會議**: 2026-02-16 (週日) 10:00-12:00

### 成果總結

| 指標 | 初始值 | 目標值 | 實際值 | 達成率 |
|------|--------|--------|--------|--------|
| 可用性 | 99.9% | 99.99% | ? | ? |
| 部署成功率 | 85% | 99% | ? | ? |
| 單元測試覆蓋率 | 0% | 70% | ? | ? |
| 安全成熟度 | 5/10 | 8/10 | ? | ? |
| 技術債務負擔 | Medium | Low | ? | ? |

### 下一階段規劃

1. **持續改進**
   - 每月技術債務審查
   - 季度安全稽核
   - 每週效能監控

2. **新功能開發**
   - 遵循 TDD 原則
   - 所有新 PR 需通過 CI/CD
   - Code coverage 不得降低

3. **知識分享**
   - 內部技術分享會
   - 文檔持續更新
   - 最佳實踐總結

---

## 附錄：驗收標準

### Phase 0 驗收標準

- [ ] Redis AOF/RDB 持久化啟用
- [ ] InfluxDB Retention Policy 90 天
- [ ] 無明文密碼存在於 Git
- [ ] Redis 需密碼認證
- [ ] E2 Simulator 向 5 個 xApps 發送流量
- [ ] 每日備份成功執行

### Phase 1 驗收標準

- [ ] 所有密碼儲存於 Sealed Secrets
- [ ] Git 歷史無敏感資訊
- [ ] Trivy 掃描整合到 CI/CD
- [ ] 所有 xApps 有 SecurityContext
- [ ] Pod Security Standards 實施
- [ ] Network Policy default-deny
- [ ] 所有 xApps 有專屬 ServiceAccount
- [ ] RBAC 遵循最小權限
- [ ] Service Mesh mTLS 啟用

### Phase 2 驗收標準

- [ ] Redis Sentinel HA 運行
- [ ] InfluxDB 雙寫機制運行
- [ ] PostgreSQL HA 運行
- [ ] RTO < 5 分鐘
- [ ] RPO < 1 分鐘
- [ ] 資源配置優化完成
- [ ] HPA 自動擴展成功
- [ ] Jaeger 追蹤完整鏈路
- [ ] E2 batching 吞吐量提升 5x

### Phase 3 驗收標準

- [ ] pytest 框架建立
- [ ] Mock 框架完整
- [ ] KPIMON 單元測試覆蓋率 60%+
- [ ] Traffic Steering 單元測試覆蓋率 60%+
- [ ] GitHub Actions CI 運行正常
- [ ] Helm charts 通過自動化測試
- [ ] E2E 測試完整

---

**作者**: 蔡秀吉 (thc1006)
**創建日期**: 2025-11-17
**最後更新**: 2025-11-17
**追蹤**: 每週一更新進度
