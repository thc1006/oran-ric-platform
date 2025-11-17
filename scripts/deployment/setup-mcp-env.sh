#!/bin/bash
# MCP 環境設定腳本
# 作者: 蔡秀吉 (thc1006)
# 日期: 2025-11-14
# 用途: 配置 MCP 伺服器所需的環境變數和依賴

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

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日誌函數
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 檢查必要的命令
check_commands() {
    log_info "檢查必要的命令..."

    local commands=("node" "npm" "npx" "kubectl" "docker")
    local missing=()

    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
            log_error "未找到命令: $cmd"
        else
            log_info "✓ $cmd: $(command -v $cmd)"
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "缺少以下必要命令: ${missing[*]}"
        exit 1
    fi

    log_info "所有必要命令已安裝"
}

# 設定 KUBECONFIG
setup_kubeconfig() {
    log_info "設定 KUBECONFIG..."

    # 檢查 k3s config 是否存在
    if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
        log_info "找到 k3s 配置檔"

        # 建立 .kube 目錄
        mkdir -p ~/.kube

        # 複製配置檔
        if sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config; then
            sudo chown $USER:$USER ~/.kube/config
            chmod 600 ~/.kube/config
            log_info "✓ KUBECONFIG 已設定為 ~/.kube/config"
        else
            log_error "無法複製 k3s 配置檔"
            exit 1
        fi
    else
        log_warn "未找到 k3s 配置檔，請確保 k3s 已安裝"
    fi

    # 添加環境變數到 .bashrc
    if ! grep -q "export KUBECONFIG=" ~/.bashrc; then
        echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
        log_info "✓ 已添加 KUBECONFIG 到 .bashrc"
    else
        log_info "KUBECONFIG 環境變數已存在於 .bashrc"
    fi
}

# 設定 GITHUB_TOKEN
setup_github_token() {
    log_info "檢查 GITHUB_TOKEN..."

    if [ -z "$GITHUB_TOKEN" ]; then
        log_warn "GITHUB_TOKEN 未設定"
        log_info "請前往 https://github.com/settings/tokens 建立 Personal Access Token"
        log_info "然後執行: echo 'export GITHUB_TOKEN=your_token_here' >> ~/.bashrc"
    else
        log_info "✓ GITHUB_TOKEN 已設定 (長度: ${#GITHUB_TOKEN})"

        # 確保環境變數持久化
        if ! grep -q "export GITHUB_TOKEN=" ~/.bashrc; then
            echo "export GITHUB_TOKEN=$GITHUB_TOKEN" >> ~/.bashrc
            log_info "✓ 已添加 GITHUB_TOKEN 到 .bashrc"
        fi
    fi
}

# 安裝 MCP 伺服器
install_mcp_servers() {
    log_info "安裝 MCP 伺服器..."

    # 檢查已安裝的 MCP 伺服器
    log_info "檢查已安裝的 MCP 伺服器..."
    npm list -g 2>&1 | grep -E '@modelcontextprotocol|playwright|mcp' || true

    # 安裝 Playwright MCP Server (如果未安裝)
    if ! npm list -g playwright-mcp-server &> /dev/null; then
        log_info "安裝 Playwright MCP Server..."
        npm install -g playwright-mcp-server
    else
        log_info "✓ Playwright MCP Server 已安裝"
    fi

    # 安裝 Kubernetes MCP Server (如果未安裝)
    if ! npm list -g @strowk/mcp-k8s-linux-x64 &> /dev/null; then
        log_info "安裝 Kubernetes MCP Server..."
        npm install -g @strowk/mcp-k8s-linux-x64
    else
        log_info "✓ Kubernetes MCP Server 已安裝"
    fi

    log_info "MCP 伺服器安裝完成"
}

# 安裝建議的額外 MCP 伺服器
install_recommended_mcp_servers() {
    log_info "是否安裝建議的額外 MCP 伺服器？(Docker, Prometheus)"
    read -p "繼續安裝? [y/N] " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 注意: 這些套件可能尚未發布到 npm
        # 以下指令僅作為示範

        log_info "安裝 Docker MCP Server..."
        npx -y @modelcontextprotocol/server-docker --version 2>&1 || \
            log_warn "Docker MCP Server 可能尚未發布，將在使用時自動下載"

        log_info "安裝 Prometheus MCP Server..."
        npx -y @modelcontextprotocol/server-prometheus --version 2>&1 || \
            log_warn "Prometheus MCP Server 可能尚未發布，將在使用時自動下載"
    else
        log_info "跳過額外 MCP 伺服器安裝"
    fi
}

# 驗證 MCP 配置
verify_mcp_config() {
    log_info "驗證 MCP 配置..."

    # 檢查 .mcp.json 是否存在
    if [ ! -f "${PROJECT_ROOT}/.mcp.json" ]; then
        log_error ".mcp.json 不存在於 ${PROJECT_ROOT}/.mcp.json"
        exit 1
    fi

    log_info "✓ .mcp.json 存在"

    # 驗證 Kubernetes 連線
    if kubectl cluster-info &> /dev/null; then
        log_info "✓ Kubernetes 叢集連線正常"
        kubectl get nodes
    else
        log_warn "無法連線到 Kubernetes 叢集"
    fi

    # 驗證 Docker
    if docker ps &> /dev/null; then
        log_info "✓ Docker 服務正常"
    else
        log_warn "Docker 服務可能未運行或權限不足"
    fi
}

# 顯示環境變數摘要
show_env_summary() {
    log_info "================================"
    log_info "環境變數摘要"
    log_info "================================"
    echo "GITHUB_TOKEN: ${GITHUB_TOKEN:0:10}... (長度: ${#GITHUB_TOKEN})"
    echo "KUBECONFIG: ${KUBECONFIG:-未設定}"
    echo "NODE_VERSION: $(node --version)"
    echo "NPM_VERSION: $(npm --version)"
    echo "KUBECTL_VERSION: $(kubectl version --client --short 2>/dev/null || echo '未安裝')"
    echo "DOCKER_VERSION: $(docker --version 2>/dev/null || echo '未安裝')"
    log_info "================================"
}

# 建立測試腳本
create_test_script() {
    log_info "建立 MCP 測試腳本..."

    cat > /tmp/test-mcp.sh << 'EOF'
#!/bin/bash
# MCP 伺服器測試腳本

echo "測試 Filesystem MCP Server..."
npx -y @modelcontextprotocol/server-filesystem --version 2>&1 | head -5

echo ""
echo "測試 GitHub MCP Server..."
npx -y @modelcontextprotocol/server-github --version 2>&1 | head -5

echo ""
echo "測試 Playwright MCP Server..."
npx -y playwright-mcp-server --version 2>&1 | head -5

echo ""
echo "測試 Kubernetes MCP Server..."
# 動態查找 mcp-k8s-go 二進制文件
MCP_K8S_BIN="\$(find \$HOME/.nvm/versions/node/*/lib/node_modules/@strowk/mcp-k8s-linux-x64/bin/mcp-k8s-go 2>/dev/null | head -1)"
if [ -n "\$MCP_K8S_BIN" ] && [ -f "\$MCP_K8S_BIN" ]; then
    \$MCP_K8S_BIN --version 2>&1 | head -5
else
    echo "Kubernetes MCP Server 未安裝 (在 \$HOME/.nvm/versions/node/*/lib/node_modules/@strowk/mcp-k8s-linux-x64/bin/ 下找不到)"
fi

echo ""
echo "所有 MCP 伺服器測試完成"
EOF

    chmod +x /tmp/test-mcp.sh
    log_info "✓ 測試腳本已建立: /tmp/test-mcp.sh"
}

# 主函數
main() {
    log_info "開始設定 MCP 環境..."
    log_info "================================"

    check_commands
    echo ""

    setup_kubeconfig
    echo ""

    setup_github_token
    echo ""

    install_mcp_servers
    echo ""

    install_recommended_mcp_servers
    echo ""

    verify_mcp_config
    echo ""

    create_test_script
    echo ""

    show_env_summary

    log_info "================================"
    log_info "MCP 環境設定完成！"
    log_info "================================"
    log_info "請執行以下命令重新載入環境變數:"
    log_info "  source ~/.bashrc"
    log_info ""
    log_info "執行測試腳本驗證 MCP 伺服器:"
    log_info "  bash /tmp/test-mcp.sh"
    log_info ""
    log_info "查看完整文檔:"
    log_info "  cat ${PROJECT_ROOT}/docs/deployment-guides/01-mcp-server-configuration.md"
}

# 執行主函數
main
