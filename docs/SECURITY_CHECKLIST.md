# O-RAN RIC Platform 安全檢查清單

**作者**: 蔡秀吉 (thc1006)
**日期**: 2025-11-17
**版本**: 1.0.0

> 此檢查清單用於定期審查系統安全狀態，建議每月執行一次

---

## 使用說明

- ☐ 未完成
- ✓ 已完成
- ⚠️ 需要注意
- ❌ 不適用

---

## 1. 設定安全 (Configuration Security)

### 1.1 Secret 管理

- [ ] 所有密碼使用 Kubernetes Secret 儲存
- [ ] 無明文密碼存在於 Git 儲存庫
- [ ] 已實施 Sealed Secrets 或 External Secrets Operator
- [ ] Secret 已啟用 encryption at rest
- [ ] 密碼符合強度要求 (最少 16 字元，包含大小寫、數字、特殊符號)
- [ ] 已建立密碼輪替政策 (至少每 90 天)
- [ ] 已執行最近一次密碼輪替 (日期: ______)
- [ ] 密碼備份儲存在安全位置

### 1.2 TLS/憑證管理

- [ ] 所有對外服務使用 TLS 1.2+
- [ ] TLS 憑證有效期限 > 30 天
- [ ] 已設定憑證過期告警
- [ ] 使用強加密套件 (禁用 RC4, DES, 3DES)
- [ ] 已實施憑證輪替政策

### 1.3 設定檔審查

- [ ] 無硬編碼 IP 地址
- [ ] 無測試/開發用憑證
- [ ] 已移除所有註解中的敏感資訊
- [ ] 環境變數未包含敏感資料

---

## 2. 存取控制 (Access Control)

### 2.1 RBAC

- [ ] 每個 xApp 有專屬 ServiceAccount
- [ ] 無 Deployment 使用 default ServiceAccount
- [ ] Role/RoleBinding 遵循最小權限原則
- [ ] 無不必要的 ClusterRole
- [ ] 無使用 wildcards (*) 權限
- [ ] 定期審查並移除不使用的 ServiceAccount

### 2.2 API 存取

- [ ] Kubernetes API Server 已啟用 RBAC
- [ ] 已禁用匿名認證
- [ ] 已設定 API rate limiting
- [ ] 已啟用 audit logging

### 2.3 使用者管理

- [ ] 已建立使用者存取清單
- [ ] 定期審查使用者權限 (每季)
- [ ] 已移除離職人員帳號
- [ ] 已實施多因素認證 (MFA)

---

## 3. 容器安全 (Container Security)

### 3.1 SecurityContext

**Platform Components:**
- [ ] appmgr 設定 SecurityContext
- [ ] e2mgr 設定 SecurityContext
- [ ] e2term 設定 SecurityContext (無特權模式)
- [ ] a1mediator 設定 SecurityContext
- [ ] submgr 設定 SecurityContext

**xApps:**
- [ ] traffic-steering 設定 SecurityContext
- [ ] kpimon 設定 SecurityContext
- [ ] ran-control 設定 SecurityContext
- [ ] qoe-predictor 設定 SecurityContext
- [ ] federated-learning 設定 SecurityContext

**SecurityContext 必須包含:**
- [ ] `runAsNonRoot: true`
- [ ] `runAsUser: 1000` (非 root UID)
- [ ] `allowPrivilegeEscalation: false`
- [ ] `capabilities.drop: [ALL]`
- [ ] `readOnlyRootFilesystem: true` (或使用 emptyDir)

### 3.2 Image 安全

- [ ] 所有 image 來自可信來源
- [ ] 已實施 image 掃描 (Trivy/Grype)
- [ ] 無 HIGH/CRITICAL 漏洞的 image
- [ ] 使用特定 tag (非 :latest)
- [ ] 已實施 image 簽署 (Cosign)
- [ ] 已設定 imagePullPolicy (IfNotPresent with digest)
- [ ] 定期更新基礎 image

### 3.3 容器執行時安全

- [ ] 無特權容器 (`privileged: false`)
- [ ] 無使用 hostNetwork
- [ ] 無使用 hostPID
- [ ] 無使用 hostIPC
- [ ] 無掛載敏感主機路徑

---

## 4. 網路安全 (Network Security)

### 4.1 Network Policy

**ricplt namespace:**
- [ ] 已部署 default-deny-all NetworkPolicy
- [ ] 已定義 Ingress 規則
- [ ] 已定義 Egress 規則
- [ ] 允許 Prometheus 抓取 metrics

**ricxapp namespace:**
- [ ] 已部署 default-deny-all NetworkPolicy
- [ ] xApp 僅可訪問必要的 Platform 服務
- [ ] xApp 之間隔離 (除非有明確需求)
- [ ] 允許訪問 DNS

### 4.2 Service Mesh

- [ ] 已部署 Service Mesh (Linkerd/Istio)
- [ ] 已啟用 mTLS
- [ ] 已設定流量策略
- [ ] 已啟用 telemetry

### 4.3 Ingress/Egress

- [ ] 僅必要的服務對外暴露
- [ ] E2Term LoadBalancer 已保護 (VPN/IP 白名單)
- [ ] 已設定 rate limiting
- [ ] 已啟用 WAF (Web Application Firewall)

---

## 5. Pod Security Standards

### 5.1 Namespace 標籤

**ricplt:**
- [ ] `pod-security.kubernetes.io/enforce: baseline`
- [ ] `pod-security.kubernetes.io/audit: restricted`
- [ ] `pod-security.kubernetes.io/warn: restricted`

**ricxapp:**
- [ ] `pod-security.kubernetes.io/enforce: baseline`
- [ ] `pod-security.kubernetes.io/audit: restricted`
- [ ] `pod-security.kubernetes.io/warn: restricted`

### 5.2 Admission Control

- [ ] 已部署 OPA Gatekeeper 或 Kyverno
- [ ] 已設定 image 掃描政策
- [ ] 已設定 SecurityContext 強制政策
- [ ] 已設定 resource limits 政策

---

## 6. 資料保護 (Data Protection)

### 6.1 傳輸中加密

- [ ] Redis 啟用 TLS
- [ ] E2 介面啟用加密 (IPsec/DTLS)
- [ ] A1 介面啟用 TLS
- [ ] O1 介面啟用 SSH/TLS
- [ ] RMR 通訊加密 (如果支援)
- [ ] Service Mesh mTLS 啟用

### 6.2 靜態資料加密

- [ ] PersistentVolume 啟用加密
- [ ] Kubernetes Secret 啟用 encryption at rest
- [ ] 資料庫備份加密
- [ ] 日誌檔案加密 (如包含敏感資訊)

---

## 7. 監控與稽核 (Monitoring & Auditing)

### 7.1 日誌管理

- [ ] 已部署集中式日誌系統 (EFK/ELK)
- [ ] 所有元件日誌集中收集
- [ ] 日誌保留期限 >= 90 天
- [ ] 已設定敏感資訊遮罩
- [ ] 日誌儲存加密

### 7.2 安全監控

- [ ] Prometheus 監控正常運作
- [ ] 已設定安全告警規則:
  - [ ] 未授權 API 存取
  - [ ] 特權 Pod 建立
  - [ ] 異常網路流量
  - [ ] 資源異常使用
  - [ ] 認證失敗
- [ ] 告警通知正常運作

### 7.3 Runtime Security

- [ ] 已部署 Falco 或類似工具
- [ ] 已設定異常行為偵測規則
- [ ] 已設定自動回應機制

### 7.4 Audit Logging

- [ ] Kubernetes audit logging 啟用
- [ ] Audit policy 正確配置
- [ ] Audit logs 集中儲存
- [ ] 定期審查 audit logs

---

## 8. DevSecOps

### 8.1 CI/CD Security

- [ ] CI/CD pipeline 包含 SAST
- [ ] CI/CD pipeline 包含 DAST
- [ ] CI/CD pipeline 包含容器掃描
- [ ] CI/CD pipeline 包含 secret 掃描
- [ ] CI/CD pipeline 包含依賴掃描
- [ ] 已實施 branch protection
- [ ] 需要 code review 才能合併

### 8.2 供應鏈安全

- [ ] 已產生 SBOM (Software Bill of Materials)
- [ ] 定期掃描依賴漏洞
- [ ] 使用 dependabot 或類似工具
- [ ] 已實施 image 簽署驗證
- [ ] 符合 SLSA Level 2+

### 8.3 部署安全

- [ ] 使用 GitOps (ArgoCD/Flux)
- [ ] Deployment manifests 經過審查
- [ ] 生產部署需要人工核准
- [ ] 已實施 canary/blue-green deployment
- [ ] 已建立 rollback 程序

---

## 9. O-RAN SC 標準符合度

### 9.1 介面安全

**E2 Interface:**
- [ ] 支援加密傳輸 (IPsec/DTLS)
- [ ] 實施雙向認證
- [ ] 符合 O-RAN.WG3.E2AP 安全要求

**A1 Interface:**
- [ ] 實施 OAuth 2.0 認證
- [ ] 使用 HTTPS (TLS 1.2+)
- [ ] 符合 O-RAN.WG2.A1AP 安全要求

**O1 Interface:**
- [ ] 使用 NETCONF over SSH
- [ ] 實施憑證管理
- [ ] 符合 O-RAN O1 安全要求

### 9.2 安全管理

- [ ] 符合 O-RAN Security Focus Group 建議
- [ ] 已實施 zero-trust 原則
- [ ] 已建立安全事件回應計畫

---

## 10. 合規性 (Compliance)

### 10.1 CIS Kubernetes Benchmark

- [ ] 已執行 kube-bench
- [ ] Control Plane 通過 CIS Benchmark
- [ ] Worker Nodes 通過 CIS Benchmark
- [ ] 已修復所有 FAIL 項目

### 10.2 NIST Cybersecurity Framework

- [ ] Identify: 已識別所有資產和風險
- [ ] Protect: 已實施保護措施
- [ ] Detect: 已部署偵測機制
- [ ] Respond: 已建立回應計畫
- [ ] Recover: 已建立恢復程序

---

## 11. 備份與災難恢復

### 11.1 備份

- [ ] 定期備份 etcd (每日)
- [ ] 定期備份 PersistentVolume (每週)
- [ ] 備份已加密
- [ ] 備份儲存在異地
- [ ] 定期測試備份恢復 (每季)

### 11.2 災難恢復

- [ ] 已建立 DR (Disaster Recovery) 計畫
- [ ] RTO (Recovery Time Objective) < 4 小時
- [ ] RPO (Recovery Point Objective) < 1 小時
- [ ] 已測試 DR 程序 (每年)
- [ ] 已記錄恢復步驟

---

## 12. 文件與流程

### 12.1 安全文件

- [ ] 安全政策文件完整
- [ ] 操作手冊更新至最新版本
- [ ] 已記錄所有安全設定
- [ ] 已建立 runbook

### 12.2 安全流程

- [ ] 已建立漏洞管理流程
- [ ] 已建立 patch 管理流程
- [ ] 已建立變更管理流程
- [ ] 已建立事件回應流程
- [ ] 定期進行安全訓練

---

## 13. 定期審查

### 13.1 每週

- [ ] 檢查安全告警
- [ ] 審查異常日誌
- [ ] 檢查憑證到期時間

### 13.2 每月

- [ ] 執行安全掃描腳本
- [ ] 審查 RBAC 配置
- [ ] 審查 Network Policy
- [ ] 檢查容器漏洞

### 13.3 每季

- [ ] 執行滲透測試
- [ ] 審查並更新安全政策
- [ ] 進行災難恢復演練
- [ ] 審查使用者存取權限

### 13.4 每年

- [ ] 完整安全稽核
- [ ] 第三方安全評估
- [ ] 更新威脅模型
- [ ] 審查並更新 DR 計畫

---

## 檢查清單使用記錄

| 日期 | 檢查人員 | 完成度 | 重大發現 | 備註 |
|------|---------|--------|---------|------|
| 2025-11-17 | 蔡秀吉 | 60% | 多個 Critical 漏洞 | 初次審查 |
|  |  |  |  |  |
|  |  |  |  |  |

---

## 快速檢查腳本

執行以下命令進行自動檢查:

```bash
# 1. 執行安全掃描
bash scripts/security/security-scan.sh

# 2. 執行 CIS Benchmark
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench

# 3. 檢查 Pod Security
kubectl get pods -A -o json | jq '.items[] | select(.spec.securityContext.runAsNonRoot != true)'

# 4. 檢查 Network Policy
kubectl get networkpolicy -A

# 5. 檢查 Secrets
kubectl get secrets -A | grep -E 'grafana|vespa|appmgr'
```

---

**維護者**: 蔡秀吉 (thc1006)
**最後更新**: 2025-11-17
**下次檢查**: 2025-12-17
