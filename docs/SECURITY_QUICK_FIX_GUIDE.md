# O-RAN RIC Platform 安全快速修復指南

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-17
**適用版本**: v1.0.0

> 本指南提供立即可執行的安全修復步驟，對應安全稽核報告中的 CRITICAL 和 HIGH 優先級問題

---

## Phase 1: Critical 漏洞修復 (1 週內完成)

### C-001: Grafana 密碼安全化

#### Step 1: 建立 Kubernetes Secret

```bash
# 生成強密碼
GRAFANA_PASSWORD=$(openssl rand -base64 32)

# 建立 Secret
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-password="${GRAFANA_PASSWORD}" \
  -n ricplt

# 儲存密碼到安全位置
echo "Grafana Admin Password: ${GRAFANA_PASSWORD}" >> ~/.oran-ric-secrets
chmod 600 ~/.oran-ric-secrets
```

#### Step 2: 更新 Grafana Values

編輯 `config/grafana-values.yaml`:

```yaml
# 移除這些行
# adminUser: admin
# adminPassword: oran-ric-admin

# 加入這些行
admin:
  existingSecret: grafana-admin-secret
  userKey: admin-user
  passwordKey: admin-password
```

#### Step 3: 重新部署 Grafana

```bash
helm upgrade oran-grafana grafana/grafana \
  -n ricplt \
  -f ./config/grafana-values.yaml
```

---

### C-002: VES Manager 密碼更新

#### Step 1: 生成新密碼

```bash
# 生成隨機使用者名稱和密碼
VES_USER=$(openssl rand -hex 8)
VES_PASSWORD=$(openssl rand -base64 24)

# Base64 編碼
VES_USER_B64=$(echo -n "${VES_USER}" | base64)
VES_PASSWORD_B64=$(echo -n "${VES_PASSWORD}" | base64)

echo "VES User: ${VES_USER}"
echo "VES Password: ${VES_PASSWORD}"
```

#### Step 2: 更新 Secret Template

建立 `ric-dep/helm/vespamgr/templates/secret-override.yaml`:

```yaml
{{- if .Values.vespamgr.auth.createSecret }}
apiVersion: v1
kind: Secret
metadata:
  name: vespa-secrets
type: Opaque
data:
  VESMGR_PRICOLLECTOR_USER: {{ .Values.vespamgr.auth.username | b64enc | quote }}
  VESMGR_PRICOLLECTOR_PASSWORD: {{ .Values.vespamgr.auth.password | b64enc | quote }}
{{- end }}
```

#### Step 3: 更新 Values

在 `ric-dep/helm/vespamgr/values.yaml` 加入:

```yaml
vespamgr:
  auth:
    createSecret: true
    # 在部署時透過 --set 提供，不要寫入 Git
    username: ""
    password: ""
```

#### Step 4: 部署時傳入密碼

```bash
helm install vespamgr ./ric-dep/helm/vespamgr \
  --set vespamgr.auth.username="${VES_USER}" \
  --set vespamgr.auth.password="${VES_PASSWORD}"
```

---

### C-003: 從 Git 移除明文密碼

#### Step 1: 安裝 Sealed Secrets

```bash
# 安裝 Sealed Secrets Controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# 安裝 kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

#### Step 2: 轉換現有 Secret

```bash
# 為 Grafana 建立 Sealed Secret
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-password="${GRAFANA_PASSWORD}" \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > config/grafana-admin-sealed.yaml

# 為 VES Manager 建立 Sealed Secret
kubectl create secret generic vespa-secrets \
  --from-literal=VESMGR_PRICOLLECTOR_USER="${VES_USER}" \
  --from-literal=VESMGR_PRICOLLECTOR_PASSWORD="${VES_PASSWORD}" \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > ric-dep/helm/vespamgr/templates/secret-sealed.yaml
```

#### Step 3: 清理 Git 歷史

```bash
# 從 Git 歷史移除敏感資訊
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch config/grafana-values.yaml" \
  --prune-empty --tag-name-filter cat -- --all

# 或使用 BFG Repo-Cleaner (更快)
java -jar bfg.jar --replace-text passwords.txt .git
git reflog expire --expire=now --all && git gc --prune=now --aggressive

# 強制推送 (警告: 需與團隊協調)
git push origin --force --all
```

#### Step 4: 更新 .gitignore

```bash
cat >> .gitignore << 'EOF'

# Security - Never commit these files
*-secrets.yaml
*.env
.oran-ric-secrets
values-production.yaml
*-override.yaml
EOF
```

---

## Phase 2: High 優先級修復 (2 週內完成)

### H-001: AppManager 移除預設密碼

編輯 `ric-dep/helm/appmgr/values.yaml`:

```yaml
appmgr:
  # 移除預設值，強制使用者提供
  repoUserName: ""
  repoPassword: ""
```

更新 `ric-dep/helm/appmgr/templates/secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "common.secretname.appmgr" . }}
type: Opaque
data:
  {{- if not .Values.appmgr.repoUserName }}
  {{ fail "appmgr.repoUserName is required" }}
  {{- end }}
  {{- if not .Values.appmgr.repoPassword }}
  {{ fail "appmgr.repoPassword is required" }}
  {{- end }}
  helm_repo_username: {{ .Values.appmgr.repoUserName | b64enc | quote }}
  helm_repo_password: {{ .Values.appmgr.repoPassword | b64enc | quote }}
```

---

### H-005/H-006/H-007: xApp SecurityContext 修復

#### 建立統一的 SecurityContext Template

建立 `xapps/templates/security-context.yaml`:

```yaml
# Pod-level SecurityContext
podSecurityContext: &podSecurityContext
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

# Container-level SecurityContext
containerSecurityContext: &containerSecurityContext
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  seccompProfile:
    type: RuntimeDefault
```

#### 更新 Traffic Steering

編輯 `xapps/traffic-steering/deploy/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traffic-steering
  namespace: ricxapp
spec:
  template:
    spec:
      # 加入 Pod SecurityContext
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault

      containers:
      - name: traffic-steering
        image: localhost:5000/xapp-traffic-steering:1.0.2

        # 加入 Container SecurityContext
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          runAsUser: 1000
          runAsGroup: 1000
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: false  # 暫時設為 false，等實施 emptyDir 後改為 true

        # 如果需要寫入，使用 emptyDir
        volumeMounts:
        - name: config-volume
          mountPath: /app/config
          readOnly: true
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /app/.cache

      volumes:
      - name: config-volume
        configMap:
          name: traffic-steering-config
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}
```

#### 批量更新腳本

建立 `scripts/security/apply-security-context.sh`:

```bash
#!/bin/bash
# 批量為所有 xApp 加入 SecurityContext

XAPPS=("traffic-steering" "kpimon-go-xapp" "rc-xapp" "qoe-predictor")

for xapp in "${XAPPS[@]}"; do
  echo "Updating $xapp..."

  # 使用 yq 修改 YAML (需安裝 yq)
  yq eval -i '
    .spec.template.spec.securityContext.runAsNonRoot = true |
    .spec.template.spec.securityContext.runAsUser = 1000 |
    .spec.template.spec.securityContext.fsGroup = 1000 |
    .spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation = false |
    .spec.template.spec.containers[0].securityContext.runAsNonRoot = true |
    .spec.template.spec.containers[0].securityContext.runAsUser = 1000 |
    .spec.template.spec.containers[0].securityContext.capabilities.drop = ["ALL"]
  ' "xapps/${xapp}/deploy/deployment.yaml"

  echo "✓ $xapp updated"
done

echo "All xApps updated with SecurityContext"
```

---

### H-008: 移除 E2Term 特權模式

編輯 `ric-dep/helm/e2term/templates/deployment.yaml`:

```yaml
# 移除這幾行
# securityContext:
#   privileged: {{ .privilegedmode }}
# hostNetwork: {{ .hostnetworkmode }}

# 替換為安全設定
securityContext:
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop:
    - ALL
    add:
    - NET_BIND_SERVICE  # 僅保留必要的 capability

# 使用正常網路模式
hostNetwork: false
dnsPolicy: ClusterFirst
```

---

### H-009: 實施 xApp Network Policy

建立 `xapps/network-policies/default-deny-all.yaml`:

```yaml
# 預設拒絕所有流量
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
```

建立 `xapps/network-policies/allow-xapp-to-platform.yaml`:

```yaml
# 允許 xApp 訪問 Platform 服務
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-xapp-to-platform
  namespace: ricxapp
spec:
  podSelector:
    matchLabels:
      type: xapp
  policyTypes:
  - Egress
  egress:
  # 允許訪問 DNS
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53

  # 允許訪問 Platform 服務
  - to:
    - namespaceSelector:
        matchLabels:
          name: ricplt
    ports:
    - protocol: TCP
      port: 4560  # RMR data
    - protocol: TCP
      port: 4561  # RMR route
    - protocol: TCP
      port: 6379  # Redis
    - protocol: TCP
      port: 8086  # InfluxDB
```

建立 `xapps/network-policies/allow-prometheus-scrape.yaml`:

```yaml
# 允許 Prometheus 抓取 metrics
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: ricxapp
spec:
  podSelector:
    matchLabels:
      type: xapp
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ricplt
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 8080  # metrics port
    - protocol: TCP
      port: 8081
    - protocol: TCP
      port: 8090
    - protocol: TCP
      port: 8110
```

部署 Network Policies:

```bash
kubectl apply -f xapps/network-policies/
```

---

## Phase 3: 自動化工具

### 安全掃描腳本

建立 `scripts/security/security-scan.sh`:

```bash
#!/bin/bash
set -e

echo "=== O-RAN RIC Security Scan ==="
echo "作者: 蔡秀吉 (thc1006)"
echo "時間: $(date)"
echo ""

# 1. 掃描明文密碼
echo "[1/6] Scanning for plaintext secrets..."
git grep -i -E '(password|api.?key|token|secret).?[:=].?["\047][^"\047]+["\047]' \
  -- '*.yaml' '*.yml' '*.json' || echo "  ✓ No plaintext secrets found"

# 2. 檢查 SecurityContext
echo ""
echo "[2/6] Checking SecurityContext configuration..."
MISSING_SC=0
for deployment in $(kubectl get deploy -n ricxapp -o name); do
  if ! kubectl get "$deployment" -n ricxapp -o json | \
       jq -e '.spec.template.spec.containers[0].securityContext.runAsNonRoot' &>/dev/null; then
    echo "  ⚠️  Missing SecurityContext: $deployment"
    ((MISSING_SC++))
  fi
done
[ $MISSING_SC -eq 0 ] && echo "  ✓ All deployments have SecurityContext"

# 3. 檢查特權容器
echo ""
echo "[3/6] Checking for privileged containers..."
kubectl get pods -A -o json | jq -r '
  .items[] |
  select(.spec.containers[]?.securityContext?.privileged == true) |
  "\(.metadata.namespace)/\(.metadata.name)"
' | while read pod; do
  echo "  ⚠️  Privileged pod: $pod"
done || echo "  ✓ No privileged containers"

# 4. 檢查 Network Policy
echo ""
echo "[4/6] Checking Network Policies..."
if kubectl get networkpolicy -n ricxapp | grep -q default-deny-all; then
  echo "  ✓ Default deny policy exists"
else
  echo "  ⚠️  Missing default deny NetworkPolicy"
fi

# 5. 掃描容器映像漏洞
echo ""
echo "[5/6] Scanning container images for vulnerabilities..."
for img in $(kubectl get pods -n ricxapp -o jsonpath="{.items[*].spec.containers[*].image}" | tr ' ' '\n' | sort -u); do
  echo "  Scanning: $img"
  trivy image --severity HIGH,CRITICAL --quiet --no-progress "$img" || true
done

# 6. 檢查 RBAC
echo ""
echo "[6/6] Checking RBAC configuration..."
for sa in $(kubectl get sa -n ricxapp -o name); do
  SA_NAME=$(echo "$sa" | cut -d/ -f2)
  if [ "$SA_NAME" != "default" ]; then
    echo "  ✓ Custom ServiceAccount: $SA_NAME"
  fi
done

# 生成報告
REPORT_FILE="/tmp/security-scan-$(date +%Y%m%d-%H%M%S).txt"
{
  echo "O-RAN RIC Security Scan Report"
  echo "Generated: $(date)"
  echo ""
  echo "Summary:"
  echo "- Missing SecurityContext: $MISSING_SC"
  echo ""
  echo "Recommendations:"
  echo "1. Review all findings above"
  echo "2. Apply fixes from SECURITY_QUICK_FIX_GUIDE.md"
  echo "3. Re-run this scan after fixes"
} > "$REPORT_FILE"

echo ""
echo "Report saved to: $REPORT_FILE"
echo "=== Scan Complete ==="
```

### 密碼輪替腳本

建立 `scripts/security/rotate-secrets.sh`:

```bash
#!/bin/bash
# 定期輪替所有密碼

set -e

echo "=== Secret Rotation Script ==="

# 1. 輪替 Grafana 密碼
echo "[1/3] Rotating Grafana admin password..."
NEW_GRAFANA_PASS=$(openssl rand -base64 32)
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-password="${NEW_GRAFANA_PASS}" \
  -n ricplt \
  --dry-run=client -o yaml | kubectl apply -f -

# 重啟 Grafana
kubectl rollout restart deployment/oran-grafana -n ricplt

# 2. 輪替 VES Manager 密碼
echo "[2/3] Rotating VES Manager password..."
NEW_VES_PASS=$(openssl rand -base64 24)
kubectl create secret generic vespa-secrets \
  --from-literal=VESMGR_PRICOLLECTOR_PASSWORD="${NEW_VES_PASS}" \
  -n ricplt \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. 輪替 Redis 密碼 (如果啟用認證)
echo "[3/3] Rotating Redis password..."
# 此步驟需根據實際配置調整

# 記錄輪替
echo "Secret rotation completed at $(date)" >> /var/log/oran-ric-secret-rotation.log

# 儲存新密碼到安全位置
{
  echo "# Secret Rotation $(date)"
  echo "Grafana Password: ${NEW_GRAFANA_PASS}"
  echo "VES Password: ${NEW_VES_PASS}"
} >> ~/.oran-ric-secrets

chmod 600 ~/.oran-ric-secrets

echo "=== Rotation Complete ==="
echo "New secrets saved to ~/.oran-ric-secrets"
```

---

## 驗證清單

修復完成後，執行以下檢查:

```bash
# 1. 執行安全掃描
bash scripts/security/security-scan.sh

# 2. 驗證所有 Pods 正常運行
kubectl get pods -n ricplt
kubectl get pods -n ricxapp

# 3. 檢查 Network Policy
kubectl get networkpolicy -A

# 4. 驗證 SecurityContext
kubectl get pods -n ricxapp -o json | \
  jq '.items[].spec.containers[0].securityContext'

# 5. 確認無特權容器
kubectl get pods -A -o json | \
  jq '.items[] | select(.spec.containers[]?.securityContext?.privileged == true)'

# 6. 檢查 Secrets
kubectl get secrets -A | grep -E 'grafana|vespa|appmgr'
```

---

## 常見問題

### Q1: 密碼輪替後服務無法啟動?

**A**: 確保所有引用 Secret 的 Pod 已重啟:
```bash
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

### Q2: Network Policy 導致服務無法通訊?

**A**: 檢查政策並測試連線:
```bash
# 檢查政策
kubectl describe networkpolicy <policy-name> -n ricxapp

# 測試連線
kubectl run -it --rm debug --image=nicolaka/netshoot -n ricxapp -- /bin/bash
# 在 Pod 內測試
curl http://redis-service.ricplt:6379
```

### Q3: SecurityContext 導致 Pod 無法寫入?

**A**: 使用 emptyDir 提供可寫目錄:
```yaml
volumeMounts:
- name: tmp
  mountPath: /tmp
volumes:
- name: tmp
  emptyDir: {}
```

### Q4: 如何回滾修復?

**A**: 使用 Git 和 Helm:
```bash
# Git 回滾
git revert <commit-hash>

# Helm 回滾
helm rollback <release-name> -n <namespace>
```

---

## 緊急回應

如果發現安全事件:

1. **立即隔離**: 刪除受影響的 Pod
   ```bash
   kubectl delete pod <pod-name> -n <namespace>
   ```

2. **檢查日誌**: 收集證據
   ```bash
   kubectl logs <pod-name> -n <namespace> --previous > incident-log.txt
   ```

3. **輪替密碼**: 執行 `rotate-secrets.sh`

4. **更新 Network Policy**: 暫時封鎖受影響服務
   ```bash
   kubectl patch networkpolicy <policy-name> -n <namespace> \
     -p '{"spec":{"podSelector":{"matchLabels":{"app":"<affected-app>"}},"policyTypes":["Ingress","Egress"],"ingress":[],"egress":[]}}'
   ```

5. **通知團隊**: 發送安全通知

---

**維護者**: 蔡秀吉 (thc1006)
**最後更新**: 2025-11-17
**下次審查**: 2025-12-17
