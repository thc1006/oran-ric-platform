#!/bin/bash
#
# O-RAN RIC Platform 密碼輪替腳本
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-17
#
# 功能：
# - 定期輪替所有系統密碼
# - 安全儲存新密碼
# - 記錄輪替歷史
# - 自動重啟受影響的服務
#

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 設定
SECRETS_FILE="$HOME/.oran-ric-secrets"
ROTATION_LOG="/var/log/oran-ric-secret-rotation.log"
BACKUP_DIR="$HOME/.oran-ric-secrets-backup"

# 確保目錄存在
mkdir -p "$BACKUP_DIR"
touch "$SECRETS_FILE"
chmod 600 "$SECRETS_FILE"

# 日誌函數
log() {
    echo -e "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ROTATION_LOG" 2>/dev/null || true
}

info() {
    log "${BLUE}[INFO]${NC} $1"
}

success() {
    log "${GREEN}[✓]${NC} $1"
}

error() {
    log "${RED}[✗]${NC} $1"
}

# 生成強密碼
generate_password() {
    local length=${1:-32}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# 備份現有 Secrets
backup_secrets() {
    info "Backing up existing secrets..."

    local backup_file="$BACKUP_DIR/secrets-backup-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "# O-RAN RIC Secrets Backup"
        echo "# Date: $(date)"
        echo ""

        # 備份 Grafana Secret
        if kubectl get secret grafana-admin-secret -n ricplt &>/dev/null; then
            echo "# Grafana Admin Secret"
            kubectl get secret grafana-admin-secret -n ricplt -o yaml >> "$backup_file"
        fi

        # 備份 VES Manager Secret
        if kubectl get secret vespa-secrets -n ricplt &>/dev/null; then
            echo "# VES Manager Secret"
            kubectl get secret vespa-secrets -n ricplt -o yaml >> "$backup_file"
        fi

    } 2>/dev/null

    chmod 600 "$backup_file"
    success "Secrets backed up to: $backup_file"
}

# 輪替 Grafana 密碼
rotate_grafana_password() {
    info "[1/4] Rotating Grafana admin password..."

    local new_password=$(generate_password 32)

    # 建立或更新 Secret
    kubectl create secret generic grafana-admin-secret \
        --from-literal=admin-user=admin \
        --from-literal=admin-password="${new_password}" \
        -n ricplt \
        --dry-run=client -o yaml | kubectl apply -f -

    # 重啟 Grafana
    if kubectl get deployment oran-grafana -n ricplt &>/dev/null; then
        kubectl rollout restart deployment/oran-grafana -n ricplt
        kubectl rollout status deployment/oran-grafana -n ricplt --timeout=120s
    fi

    # 儲存密碼
    {
        echo "# Grafana Admin Password (Rotated: $(date))"
        echo "GRAFANA_USER=admin"
        echo "GRAFANA_PASSWORD=${new_password}"
        echo ""
    } >> "$SECRETS_FILE"

    success "Grafana password rotated successfully"
    info "New password saved to: $SECRETS_FILE"
}

# 輪替 VES Manager 密碼
rotate_vesmgr_password() {
    info "[2/4] Rotating VES Manager password..."

    local new_user="vesmgr-$(openssl rand -hex 4)"
    local new_password=$(generate_password 24)

    # 建立或更新 Secret
    kubectl create secret generic vespa-secrets \
        --from-literal=VESMGR_PRICOLLECTOR_USER="${new_user}" \
        --from-literal=VESMGR_PRICOLLECTOR_PASSWORD="${new_password}" \
        -n ricplt \
        --dry-run=client -o yaml | kubectl apply -f -

    # 重啟 VES Manager (如果部署)
    if kubectl get deployment vespamgr -n ricplt &>/dev/null; then
        kubectl rollout restart deployment/vespamgr -n ricplt
        kubectl rollout status deployment/vespamgr -n ricplt --timeout=120s || true
    fi

    # 儲存密碼
    {
        echo "# VES Manager Credentials (Rotated: $(date))"
        echo "VESMGR_USER=${new_user}"
        echo "VESMGR_PASSWORD=${new_password}"
        echo ""
    } >> "$SECRETS_FILE"

    success "VES Manager credentials rotated successfully"
}

# 輪替 AppManager Helm Repo 密碼
rotate_appmgr_password() {
    info "[3/4] Rotating AppManager Helm repo password..."

    local new_user="helm-$(openssl rand -hex 4)"
    local new_password=$(generate_password 24)

    # 建立或更新 Secret
    if kubectl get secret -n ricplt | grep -q appmgr; then
        local secret_name=$(kubectl get secret -n ricplt -o name | grep appmgr | head -1 | cut -d/ -f2)

        kubectl create secret generic "$secret_name" \
            --from-literal=helm_repo_username="${new_user}" \
            --from-literal=helm_repo_password="${new_password}" \
            -n ricplt \
            --dry-run=client -o yaml | kubectl apply -f -

        # 重啟 AppManager
        if kubectl get deployment appmgr -n ricplt &>/dev/null; then
            kubectl rollout restart deployment/appmgr -n ricplt
            kubectl rollout status deployment/appmgr -n ricplt --timeout=120s || true
        fi

        # 儲存密碼
        {
            echo "# AppManager Helm Repo Credentials (Rotated: $(date))"
            echo "APPMGR_HELM_USER=${new_user}"
            echo "APPMGR_HELM_PASSWORD=${new_password}"
            echo ""
        } >> "$SECRETS_FILE"

        success "AppManager credentials rotated successfully"
    else
        info "AppManager secret not found, skipping..."
    fi
}

# 輪替 Redis 密碼 (如果啟用認證)
rotate_redis_password() {
    info "[4/4] Checking Redis authentication..."

    # 檢查 Redis 是否配置了認證
    if kubectl get configmap -n ricplt | grep -q redis-config; then
        info "Redis authentication configuration found"

        local new_password=$(generate_password 32)

        # 這裡需要根據實際的 Redis 部署方式調整
        # 如果使用 Bitnami Redis Helm chart:
        if kubectl get secret -n ricplt | grep -q redis; then
            kubectl create secret generic redis \
                --from-literal=redis-password="${new_password}" \
                -n ricplt \
                --dry-run=client -o yaml | kubectl apply -f -

            # 重啟 Redis
            if kubectl get statefulset redis-master -n ricplt &>/dev/null; then
                kubectl rollout restart statefulset/redis-master -n ricplt || true
            fi

            # 儲存密碼
            {
                echo "# Redis Password (Rotated: $(date))"
                echo "REDIS_PASSWORD=${new_password}"
                echo ""
            } >> "$SECRETS_FILE"

            success "Redis password rotated successfully"

            # 重啟所有使用 Redis 的 xApps
            info "Restarting xApps that use Redis..."
            for deployment in $(kubectl get deploy -n ricxapp -o name); do
                kubectl rollout restart "$deployment" -n ricxapp || true
            done
        else
            info "Redis secret not found, authentication may not be enabled"
        fi
    else
        info "Redis authentication not configured, skipping..."
    fi
}

# 驗證輪替
verify_rotation() {
    info "Verifying secret rotation..."

    local failed=0

    # 檢查 Grafana
    if kubectl get secret grafana-admin-secret -n ricplt &>/dev/null; then
        success "Grafana secret exists"
    else
        error "Grafana secret not found"
        ((failed++))
    fi

    # 檢查 VES Manager
    if kubectl get secret vespa-secrets -n ricplt &>/dev/null; then
        success "VES Manager secret exists"
    else
        error "VES Manager secret not found"
        ((failed++))
    fi

    # 檢查所有 Pods 是否正常
    info "Checking pod status..."
    local not_ready=$(kubectl get pods -n ricplt --no-headers | grep -v Running | wc -l)
    if [ "$not_ready" -gt 0 ]; then
        error "$not_ready pods not running in ricplt namespace"
        kubectl get pods -n ricplt | grep -v Running || true
        ((failed++))
    else
        success "All pods running in ricplt namespace"
    fi

    if [ $failed -gt 0 ]; then
        error "Verification failed with $failed issue(s)"
        return 1
    else
        success "All verifications passed"
        return 0
    fi
}

# 顯示新密碼
show_credentials() {
    echo ""
    echo "========================================"
    echo "  New Credentials"
    echo "========================================"
    echo ""
    echo "⚠️  These credentials are also saved in:"
    echo "   $SECRETS_FILE"
    echo ""
    echo "To view Grafana password:"
    echo "  grep GRAFANA_PASSWORD $SECRETS_FILE | tail -1"
    echo ""
    echo "To view VES Manager credentials:"
    echo "  grep VESMGR_ $SECRETS_FILE | tail -2"
    echo ""
    echo "========================================"
    echo ""
}

# 清理舊備份 (保留最近 10 個)
cleanup_old_backups() {
    info "Cleaning up old backups (keeping last 10)..."

    if [ -d "$BACKUP_DIR" ]; then
        local count=$(ls -t "$BACKUP_DIR"/secrets-backup-*.txt 2>/dev/null | wc -l)
        if [ "$count" -gt 10 ]; then
            ls -t "$BACKUP_DIR"/secrets-backup-*.txt | tail -n +11 | xargs rm -f
            success "Cleaned up $((count - 10)) old backup(s)"
        fi
    fi
}

# 記錄輪替
log_rotation() {
    {
        echo ""
        echo "========================================"
        echo "Secret Rotation Completed"
        echo "Date: $(date)"
        echo "Rotated by: $(whoami)"
        echo "========================================"
        echo ""
    } >> "$ROTATION_LOG" 2>/dev/null || true

    # 如果日誌檔案過大，輪替日誌
    if [ -f "$ROTATION_LOG" ]; then
        local size=$(wc -c < "$ROTATION_LOG")
        if [ "$size" -gt 1048576 ]; then  # 1MB
            mv "$ROTATION_LOG" "${ROTATION_LOG}.old"
            touch "$ROTATION_LOG"
            chmod 644 "$ROTATION_LOG" 2>/dev/null || true
        fi
    fi
}

# 主函數
main() {
    echo ""
    echo "========================================"
    echo "  O-RAN RIC Secret Rotation"
    echo "========================================"
    echo "作者: 蔡秀吉 (thc1006)"
    echo "時間: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================"
    echo ""

    # 確認執行
    read -p "This will rotate all platform secrets. Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "Secret rotation cancelled"
        exit 1
    fi

    # 執行輪替
    backup_secrets
    rotate_grafana_password
    rotate_vesmgr_password
    rotate_appmgr_password
    rotate_redis_password

    # 驗證
    if verify_rotation; then
        cleanup_old_backups
        log_rotation
        show_credentials
        success "Secret rotation completed successfully!"
    else
        error "Secret rotation completed with errors"
        error "Please check the logs and verify manually"
        exit 1
    fi
}

# 錯誤處理
trap 'error "Secret rotation failed! Check logs: $ROTATION_LOG"; exit 1' ERR

# 執行
main "$@"
