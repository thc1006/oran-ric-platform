#!/bin/bash
#
# O-RAN RIC Platform 安全掃描腳本
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-17
#
# 功能：
# - 掃描明文密碼和敏感資訊
# - 檢查 SecurityContext 設定
# - 驗證 RBAC 配置
# - 檢查 Network Policy
# - 掃描容器漏洞
#

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 計數器
CRITICAL_ISSUES=0
HIGH_ISSUES=0
MEDIUM_ISSUES=0
LOW_ISSUES=0

# 報告檔案
REPORT_FILE="/tmp/security-scan-$(date +%Y%m%d-%H%M%S).txt"

# 日誌函數
info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$REPORT_FILE"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$REPORT_FILE"
}

warning() {
    echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$REPORT_FILE"
}

error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$REPORT_FILE"
}

critical() {
    echo -e "${RED}[CRITICAL]${NC} $1" | tee -a "$REPORT_FILE"
    ((CRITICAL_ISSUES++))
}

high() {
    echo -e "${RED}[HIGH]${NC} $1" | tee -a "$REPORT_FILE"
    ((HIGH_ISSUES++))
}

medium() {
    echo -e "${YELLOW}[MEDIUM]${NC} $1" | tee -a "$REPORT_FILE"
    ((MEDIUM_ISSUES++))
}

low() {
    echo -e "${BLUE}[LOW]${NC} $1" | tee -a "$REPORT_FILE"
    ((LOW_ISSUES++))
}

# 初始化報告
init_report() {
    {
        echo "========================================"
        echo "  O-RAN RIC Platform Security Scan"
        echo "========================================"
        echo "作者: 蔡秀吉 (thc1006)"
        echo "時間: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================"
        echo ""
    } > "$REPORT_FILE"
}

# 1. 掃描 Git 儲存庫中的明文密碼
scan_plaintext_secrets() {
    info "[1/10] Scanning for plaintext secrets in Git repository..."
    echo ""

    local found=0

    # 掃描常見的密碼模式
    if git rev-parse --git-dir > /dev/null 2>&1; then
        # 掃描 YAML/JSON 檔案
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                critical "Found potential secret: $line"
                ((found++))
            fi
        done < <(git grep -i -n -E '(password|apikey|api.?key|token|secret).?[:=].?["\047][^"\047]{8,}["\047]' -- '*.yaml' '*.yml' '*.json' 2>/dev/null || true)

        # 掃描 Base64 編碼的密碼 (常見於 Kubernetes Secrets)
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                warning "Found base64 encoded data (may be secret): $line"
                ((found++))
            fi
        done < <(git grep -n -E '^[[:space:]]+[A-Za-z_]+: [A-Za-z0-9+/]{20,}={0,2}$' -- '*.yaml' '*.yml' 2>/dev/null | grep -v 'ca-bundle\|certificate\|tls.crt' || true)
    fi

    if [ $found -eq 0 ]; then
        success "No plaintext secrets found in Git repository"
    else
        error "Found $found potential secrets in Git repository"
    fi
    echo ""
}

# 2. 檢查 Kubernetes Secrets
check_kubernetes_secrets() {
    info "[2/10] Checking Kubernetes Secrets configuration..."
    echo ""

    # 檢查是否有未加密的 Secrets
    if kubectl get secrets -A -o json | jq -e '.items[] | select(.metadata.name | test("grafana|vespa|appmgr"))' &>/dev/null; then
        info "Found the following sensitive secrets:"
        kubectl get secrets -A | grep -E 'grafana|vespa|appmgr' | while read -r line; do
            echo "  $line"
        done

        # 檢查 Sealed Secrets Controller
        if kubectl get pods -n kube-system | grep -q sealed-secrets; then
            success "Sealed Secrets Controller is installed"
        else
            high "Sealed Secrets Controller not found - secrets are not encrypted in Git"
        fi
    fi
    echo ""
}

# 3. 檢查 SecurityContext
check_security_context() {
    info "[3/10] Checking SecurityContext configuration..."
    echo ""

    local missing_pod_sc=0
    local missing_container_sc=0

    # 檢查所有 namespace
    for ns in ricplt ricxapp; do
        if ! kubectl get namespace "$ns" &>/dev/null; then
            warning "Namespace $ns not found, skipping..."
            continue
        fi

        info "Checking namespace: $ns"

        # 檢查 Deployments
        for deployment in $(kubectl get deploy -n "$ns" -o name 2>/dev/null || true); do
            local dep_name=$(echo "$deployment" | cut -d/ -f2)

            # 檢查 Pod SecurityContext
            if ! kubectl get "$deployment" -n "$ns" -o json | \
                 jq -e '.spec.template.spec.securityContext.runAsNonRoot' &>/dev/null; then
                high "Missing Pod SecurityContext: $ns/$dep_name"
                ((missing_pod_sc++))
            fi

            # 檢查 Container SecurityContext
            if ! kubectl get "$deployment" -n "$ns" -o json | \
                 jq -e '.spec.template.spec.containers[0].securityContext.runAsNonRoot' &>/dev/null; then
                high "Missing Container SecurityContext: $ns/$dep_name"
                ((missing_container_sc++))
            fi

            # 檢查 allowPrivilegeEscalation
            if kubectl get "$deployment" -n "$ns" -o json | \
               jq -e '.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation == true' &>/dev/null; then
                high "allowPrivilegeEscalation=true in $ns/$dep_name"
            fi

            # 檢查 capabilities
            if ! kubectl get "$deployment" -n "$ns" -o json | \
                 jq -e '.spec.template.spec.containers[0].securityContext.capabilities.drop[]? | select(. == "ALL")' &>/dev/null; then
                medium "Capabilities not dropped in $ns/$dep_name"
            fi
        done
    done

    if [ $missing_pod_sc -eq 0 ] && [ $missing_container_sc -eq 0 ]; then
        success "All deployments have proper SecurityContext"
    else
        error "Found $missing_pod_sc deployments missing Pod SecurityContext"
        error "Found $missing_container_sc deployments missing Container SecurityContext"
    fi
    echo ""
}

# 4. 檢查特權容器
check_privileged_containers() {
    info "[4/10] Checking for privileged containers..."
    echo ""

    local found=0
    while IFS= read -r pod; do
        if [ -n "$pod" ]; then
            critical "Privileged container found: $pod"
            ((found++))
        fi
    done < <(kubectl get pods -A -o json | jq -r '
        .items[] |
        select(.spec.containers[]?.securityContext?.privileged == true) |
        "\(.metadata.namespace)/\(.metadata.name)"
    ' 2>/dev/null || true)

    if [ $found -eq 0 ]; then
        success "No privileged containers found"
    else
        error "Found $found privileged container(s)"
    fi
    echo ""
}

# 5. 檢查 hostNetwork 和 hostPID
check_host_namespaces() {
    info "[5/10] Checking for hostNetwork and hostPID usage..."
    echo ""

    local found=0
    while IFS= read -r pod; do
        if [ -n "$pod" ]; then
            high "Pod using hostNetwork: $pod"
            ((found++))
        fi
    done < <(kubectl get pods -A -o json | jq -r '
        .items[] |
        select(.spec.hostNetwork == true) |
        "\(.metadata.namespace)/\(.metadata.name)"
    ' 2>/dev/null || true)

    while IFS= read -r pod; do
        if [ -n "$pod" ]; then
            high "Pod using hostPID: $pod"
            ((found++))
        fi
    done < <(kubectl get pods -A -o json | jq -r '
        .items[] |
        select(.spec.hostPID == true) |
        "\(.metadata.namespace)/\(.metadata.name)"
    ' 2>/dev/null || true)

    if [ $found -eq 0 ]; then
        success "No pods using hostNetwork or hostPID"
    fi
    echo ""
}

# 6. 檢查 Network Policy
check_network_policies() {
    info "[6/10] Checking Network Policies..."
    echo ""

    for ns in ricplt ricxapp; do
        if ! kubectl get namespace "$ns" &>/dev/null; then
            continue
        fi

        info "Checking namespace: $ns"

        # 檢查是否有 default-deny 政策
        if kubectl get networkpolicy -n "$ns" 2>/dev/null | grep -q default-deny; then
            success "Default deny NetworkPolicy exists in $ns"
        else
            high "Missing default deny NetworkPolicy in $ns"
        fi

        # 列出所有 Network Policies
        local policies=$(kubectl get networkpolicy -n "$ns" -o name 2>/dev/null | wc -l)
        if [ "$policies" -eq 0 ]; then
            high "No NetworkPolicies found in $ns"
        else
            info "Found $policies NetworkPolicy(ies) in $ns"
        fi
    done
    echo ""
}

# 7. 檢查 RBAC
check_rbac() {
    info "[7/10] Checking RBAC configuration..."
    echo ""

    # 檢查 default ServiceAccount 使用
    for ns in ricplt ricxapp; do
        if ! kubectl get namespace "$ns" &>/dev/null; then
            continue
        fi

        info "Checking namespace: $ns"

        local using_default=0
        for deployment in $(kubectl get deploy -n "$ns" -o name 2>/dev/null || true); do
            local sa=$(kubectl get "$deployment" -n "$ns" -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null)
            if [ -z "$sa" ] || [ "$sa" == "default" ]; then
                medium "Deployment using default ServiceAccount: $deployment"
                ((using_default++))
            fi
        done

        if [ $using_default -eq 0 ]; then
            success "No deployments using default ServiceAccount in $ns"
        fi
    done

    # 檢查 ClusterRole 權限
    info "Checking ClusterRoles for overly permissive rules..."
    for role in $(kubectl get clusterrole -o name | grep -v 'system:' || true); do
        # 檢查是否有 * 權限
        if kubectl get "$role" -o json | jq -e '.rules[]? | select(.verbs[]? == "*")' &>/dev/null; then
            medium "ClusterRole with wildcard permissions: $role"
        fi
    done
    echo ""
}

# 8. 檢查 Image 安全
check_image_security() {
    info "[8/10] Checking container image configuration..."
    echo ""

    for ns in ricplt ricxapp; do
        if ! kubectl get namespace "$ns" &>/dev/null; then
            continue
        fi

        # 檢查 imagePullPolicy
        for deployment in $(kubectl get deploy -n "$ns" -o name 2>/dev/null || true); do
            local policy=$(kubectl get "$deployment" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}')
            local image=$(kubectl get "$deployment" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].image}')

            if [ "$policy" == "Always" ]; then
                if [[ "$image" == *":latest" ]]; then
                    medium "Using 'Always' with ':latest' tag in $deployment"
                fi
            fi

            # 檢查是否使用 latest tag
            if [[ "$image" == *":latest" ]]; then
                medium "Using ':latest' tag in $deployment: $image"
            fi
        done
    done
    echo ""
}

# 9. 掃描容器映像漏洞 (需要 Trivy)
scan_image_vulnerabilities() {
    info "[9/10] Scanning container images for vulnerabilities..."
    echo ""

    if ! command -v trivy &> /dev/null; then
        warning "Trivy not installed, skipping image vulnerability scan"
        warning "Install: https://aquasecurity.github.io/trivy/"
        echo ""
        return
    fi

    local images=$(kubectl get pods -A -o jsonpath="{.items[*].spec.containers[*].image}" | tr ' ' '\n' | sort -u)

    while IFS= read -r image; do
        if [ -z "$image" ]; then
            continue
        fi

        info "Scanning: $image"
        local output=$(trivy image --severity HIGH,CRITICAL --quiet --format json "$image" 2>/dev/null || echo '{}')

        local vulns=$(echo "$output" | jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH" or .Severity == "CRITICAL") | .VulnerabilityID' 2>/dev/null | wc -l)

        if [ "$vulns" -gt 0 ]; then
            high "Found $vulns HIGH/CRITICAL vulnerabilities in $image"
        else
            success "No HIGH/CRITICAL vulnerabilities in $image"
        fi
    done <<< "$images"
    echo ""
}

# 10. 檢查 Pod Security Standards
check_pod_security_standards() {
    info "[10/10] Checking Pod Security Standards..."
    echo ""

    for ns in ricplt ricxapp; do
        if ! kubectl get namespace "$ns" &>/dev/null; then
            continue
        fi

        info "Checking namespace: $ns"

        # 檢查 Pod Security labels
        local enforce=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
        local audit=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/audit}' 2>/dev/null)
        local warn=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/warn}' 2>/dev/null)

        if [ -z "$enforce" ]; then
            medium "Pod Security Standard not enforced in $ns"
        else
            success "Pod Security Standard '$enforce' enforced in $ns"
        fi
    done
    echo ""
}

# 生成摘要報告
generate_summary() {
    {
        echo ""
        echo "========================================"
        echo "  Security Scan Summary"
        echo "========================================"
        echo ""
        echo "Issue Count:"
        echo "  Critical: $CRITICAL_ISSUES"
        echo "  High:     $HIGH_ISSUES"
        echo "  Medium:   $MEDIUM_ISSUES"
        echo "  Low:      $LOW_ISSUES"
        echo ""

        if [ $CRITICAL_ISSUES -gt 0 ]; then
            echo "⚠️  CRITICAL issues found! Immediate action required."
        elif [ $HIGH_ISSUES -gt 0 ]; then
            echo "⚠️  HIGH severity issues found. Please review and fix."
        elif [ $MEDIUM_ISSUES -gt 0 ]; then
            echo "ℹ️  MEDIUM severity issues found. Review recommended."
        else
            echo "✓ No critical or high severity issues found!"
        fi

        echo ""
        echo "Recommendations:"
        echo "1. Review all findings in this report"
        echo "2. Refer to docs/SECURITY_QUICK_FIX_GUIDE.md for fixes"
        echo "3. Apply fixes based on priority (Critical → High → Medium → Low)"
        echo "4. Re-run this scan after applying fixes"
        echo ""
        echo "Full report saved to: $REPORT_FILE"
        echo "========================================"
    } | tee -a "$REPORT_FILE"
}

# 主函數
main() {
    init_report
    scan_plaintext_secrets
    check_kubernetes_secrets
    check_security_context
    check_privileged_containers
    check_host_namespaces
    check_network_policies
    check_rbac
    check_image_security
    scan_image_vulnerabilities
    check_pod_security_standards
    generate_summary

    # 根據嚴重性設定 exit code
    if [ $CRITICAL_ISSUES -gt 0 ]; then
        exit 2
    elif [ $HIGH_ISSUES -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# 執行
main "$@"
