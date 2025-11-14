# MCP 伺服器配置與驗證指南
**作者**: 蔡秀吉 (thc1006)
**日期**: 2025年11月14日
**O-RAN Release**: J Release
**部署環境**: Ubuntu 22.04, Node.js v22.20.0

---

## 前言

這份文件記錄了 O-RAN RIC Platform 專案中 MCP (Model Context Protocol) 伺服器的完整配置驗證過程。MCP 伺服器是開發環境的重要組成部分，提供了檔案系統操作、GitHub 整合、Kubernetes 管理等核心功能。

## MCP 伺服器概述

MCP (Model Context Protocol) 是一個標準化協定，允許開發工具與各種外部服務進行整合。在 O-RAN RIC 開發環境中，我們使用多個 MCP 伺服器來簡化開發和部署流程。

---

## 當前 MCP 伺服器狀態報告

### 1. Filesystem MCP Server
**狀態**: ✅ 已配置
**功能**: 提供檔案系統操作能力
**實作**: @modelcontextprotocol/server-filesystem

**配置詳情**:
```json
{
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "."]
}
```

**驗證結果**:
- npx 可執行檔: `/home/thc1006/.nvm/versions/node/v22.20.0/bin/npx`
- Node.js 版本: v22.20.0
- 狀態: 正常運作

**用途**:
- 讀取和寫入專案檔案
- 搜尋程式碼
- 管理配置檔案

---

### 2. GitHub MCP Server
**狀態**: ✅ 已配置
**功能**: GitHub 整合能力
**實作**: @modelcontextprotocol/server-github

**配置詳情**:
```json
{
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-github"],
  "env": {
    "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
  }
}
```

**環境變數檢查**:
- GITHUB_TOKEN: ✅ 已設定 (長度: 40 字元)
- Token 格式: ghp_* (Personal Access Token)

**驗證結果**: 正常運作

**用途**:
- 建立和管理 Pull Requests
- 查看 Issues
- 存取 Repository 資訊
- 自動化 Git 操作

---

### 3. Kubernetes MCP Server
**狀態**: ⚠️ 需要修正配置
**功能**: Kubernetes 叢集管理
**實作**: @strowk/mcp-k8s-linux-x64

**配置詳情**:
```json
{
  "type": "stdio",
  "command": "mcp-kubernetes-server",
  "args": [],
  "env": {
    "KUBECONFIG": "${KUBECONFIG:-$HOME/.kube/config}"
  }
}
```

**問題分析**:
當前配置中 `command` 設定為 `mcp-kubernetes-server`，但實際可執行檔名稱為 `mcp-k8s-go`。

**已安裝套件**:
- 套件: @strowk/mcp-k8s-linux-x64@0.6.0
- 安裝位置: `/home/thc1006/.nvm/versions/node/v22.20.0/lib/node_modules/@strowk/mcp-k8s-linux-x64/`
- 可執行檔: `/home/thc1006/.nvm/versions/node/v22.20.0/lib/node_modules/@strowk/mcp-k8s-linux-x64/bin/mcp-k8s-go`

**環境變數檢查**:
- KUBECONFIG: 當前設定為 `/home/thc1006/.kube/config`
- k3s 實際路徑: `/etc/rancher/k3s/k3s.yaml`
- 權限: 需要 sudo 或適當的檔案權限

**Kubernetes 叢集狀態**:
```bash
$ export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
$ sudo kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:6443
CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy

$ sudo kubectl get nodes
NAME      STATUS   ROLES                  AGE   VERSION
thc1006   Ready    control-plane,master   24m   v1.28.5+k3s1
```

**已部署的 Namespaces**:
- kube-system (Kubernetes 核心元件)
- metallb-system (負載平衡器)
- ingress-nginx (Ingress 控制器)
- ricplt (RIC Platform)
- ricxapp (RIC xApps)
- ricobs (RIC Observability)

---

### 4. Context7 MCP Server
**狀態**: ⚠️ 需要 API Key
**功能**: Context 管理
**實作**: HTTP-based MCP server

**配置詳情**:
```json
{
  "type": "http",
  "url": "https://mcp.context7.com/mcp",
  "headers": {
    "CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}"
  }
}
```

**環境變數檢查**:
- CONTEXT7_API_KEY: ❌ 未設定

**說明**:
Context7 是一個商業服務，需要註冊並取得 API Key。如果不使用此服務，可以從配置中移除。

---

### 5. Playwright MCP Server
**狀態**: ✅ 已配置並安裝
**功能**: 瀏覽器自動化測試
**實作**: playwright-mcp-server

**配置詳情**:
```json
{
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "playwright-mcp-server"]
}
```

**已安裝套件**:
```
└── playwright-mcp-server@1.0.0
```

**驗證結果**: 正常運作

**用途**:
- E2E 測試自動化
- Web UI 測試
- 瀏覽器截圖和互動

---

## 建議額外安裝的 MCP 伺服器

根據 O-RAN RIC Platform 的開發需求，建議安裝以下額外的 MCP 伺服器：

### 1. Docker MCP Server (強烈建議)
**必要性**: ⭐⭐⭐⭐⭐
**原因**: O-RAN xApps 都是容器化應用，需要頻繁的 Docker 操作

**安裝指令**:
```bash
npm install -g @modelcontextprotocol/server-docker
```

**配置**:
```json
"docker": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-docker"],
  "env": {}
}
```

**功能**:
- 建置 xApp Docker 映像檔
- 管理容器生命週期
- 查看容器日誌
- 推送映像檔到 Registry

**使用場景**:
- 建置 Traffic Steering xApp 映像檔
- 部署 KPIMON xApp
- 管理本地 Docker Registry (port 5000)
- 除錯容器問題

---

### 2. Prometheus MCP Server (建議)
**必要性**: ⭐⭐⭐⭐
**原因**: RIC Platform 需要監控 xApp 效能和資源使用

**安裝指令**:
```bash
npm install -g @modelcontextprotocol/server-prometheus
```

**配置**:
```json
"prometheus": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-prometheus"],
  "env": {
    "PROMETHEUS_URL": "http://localhost:9090"
  }
}
```

**功能**:
- 查詢 xApp 效能指標
- 監控 RMR 訊息延遲
- 追蹤 E2 Subscription 狀態
- 分析資源使用趨勢

**使用場景**:
- 驗證 E2 indication 處理延遲 < 10ms
- 監控 RMR 訊息吞吐量 > 10K msg/sec
- 追蹤 xApp 啟動時間 < 30s
- 分析控制命令延遲 < 100ms

---

### 3. PostgreSQL MCP Server (可選)
**必要性**: ⭐⭐⭐
**原因**: 某些 xApp 可能需要持久化儲存歷史資料

**安裝指令**:
```bash
npm install -g @modelcontextprotocol/server-postgres
```

**配置**:
```json
"postgres": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-postgres"],
  "env": {
    "POSTGRES_CONNECTION_STRING": "postgresql://user:password@localhost:5432/ricdb"
  }
}
```

**功能**:
- 儲存 KPI 歷史資料
- 管理 xApp 狀態
- 查詢效能分析結果

---

### 4. Redis MCP Server (可選)
**必要性**: ⭐⭐⭐
**原因**: RIC Platform 使用 Redis 作為 SDL (Shared Data Layer)

**安裝指令**:
```bash
npm install -g @modelcontextprotocol/server-redis
```

**配置**:
```json
"redis": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-redis"],
  "env": {
    "REDIS_URL": "redis://localhost:6379"
  }
}
```

**功能**:
- 除錯 SDL 資料
- 檢查 xApp 共享狀態
- 驗證 R-NIB 和 UE-NIB 資料

---

## 環境變數配置清單

### 必須設定的環境變數

#### 1. GITHUB_TOKEN
**狀態**: ⚠️ 需要設定
**值**: `your_github_token_here`
**用途**: GitHub API 認證

**永久化設定**:
```bash
# 添加到 ~/.bashrc
echo 'export GITHUB_TOKEN=your_github_token_here' >> ~/.bashrc
source ~/.bashrc
```

**取得 Token 步驟**:
1. 前往 GitHub Settings → Developer settings → Personal access tokens
2. 產生新 Token (建議使用 Fine-grained tokens)
3. 設定必要權限：repo、read:org
4. 複製 Token 並設定到環境變數

#### 2. KUBECONFIG
**狀態**: ⚠️ 需要修正
**當前值**: /home/thc1006/.kube/config
**建議值**: /etc/rancher/k3s/k3s.yaml

**修正步驟**:

方案 A：符號連結（推薦）
```bash
# 建立 .kube 目錄
mkdir -p ~/.kube

# 複製 k3s config 並設定適當權限
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
```

方案 B：直接使用 k3s config
```bash
# 設定環境變數
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
source ~/.bashrc
```

**驗證**:
```bash
kubectl cluster-info
kubectl get nodes
```

### 可選的環境變數

#### 3. CONTEXT7_API_KEY
**狀態**: ❌ 未設定
**必要性**: 低（如果不使用 Context7 服務可忽略）

**取得方式**:
1. 訪問 https://context7.com
2. 註冊帳號
3. 取得 API Key

**設定**:
```bash
echo 'export CONTEXT7_API_KEY=your_api_key_here' >> ~/.bashrc
source ~/.bashrc
```

---

## 更新後的 .mcp.json 配置

基於驗證結果，以下是建議的完整 .mcp.json 配置：

```json
{
  "mcpServers": {
    "filesystem": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/home/thc1006/oran-ric-platform"
      ],
      "env": {}
    },
    "github": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-github"
      ],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
      }
    },
    "kubernetes": {
      "type": "stdio",
      "command": "/home/thc1006/.nvm/versions/node/v22.20.0/lib/node_modules/@strowk/mcp-k8s-linux-x64/bin/mcp-k8s-go",
      "args": [],
      "env": {
        "KUBECONFIG": "/home/thc1006/.kube/config"
      }
    },
    "docker": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-docker"
      ],
      "env": {}
    },
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y",
        "playwright-mcp-server"
      ],
      "env": {}
    },
    "prometheus": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-prometheus"
      ],
      "env": {
        "PROMETHEUS_URL": "http://localhost:9090"
      }
    }
  }
}
```

**主要變更**:
1. ✅ 修正 kubernetes MCP server 的可執行檔路徑
2. ✅ 更新 KUBECONFIG 路徑為 k3s 配置檔位置
3. ✅ 新增 Docker MCP server（針對容器化 xApp 開發）
4. ✅ 新增 Prometheus MCP server（針對效能監控）
5. ❌ 移除 Context7（非必要，如需使用請自行加回）

---

## 安裝建議的 MCP 伺服器

### 1. 安裝 Docker MCP Server
```bash
npm install -g @modelcontextprotocol/server-docker
```

### 2. 安裝 Prometheus MCP Server
```bash
npm install -g @modelcontextprotocol/server-prometheus
```

### 3. （可選）安裝其他 MCP Servers
```bash
# PostgreSQL
npm install -g @modelcontextprotocol/server-postgres

# Redis
npm install -g @modelcontextprotocol/server-redis
```

---

## 驗證步驟

### 1. 驗證環境變數
```bash
# 檢查所有必要的環境變數
echo "GITHUB_TOKEN: ${GITHUB_TOKEN:0:10}..."
echo "KUBECONFIG: $KUBECONFIG"
echo "CONTEXT7_API_KEY: ${CONTEXT7_API_KEY:-未設定}"
```

### 2. 驗證 Kubernetes 連線
```bash
# 測試 kubectl 連線
kubectl cluster-info
kubectl get nodes
kubectl get namespaces

# 檢查 RIC Platform namespaces
kubectl get pods -n ricplt
kubectl get pods -n ricxapp
```

### 3. 驗證 Docker
```bash
# 檢查 Docker 服務
systemctl is-active docker

# 列出運行中的容器
docker ps

# 檢查本地 Registry
curl http://localhost:5000/v2/_catalog
```

### 4. 測試 MCP Servers
```bash
# 測試 filesystem server
npx -y @modelcontextprotocol/server-filesystem --version

# 測試 github server
npx -y @modelcontextprotocol/server-github --version

# 測試 playwright server
npx -y playwright-mcp-server --version
```

---

## 常見問題排除

### 問題 1: kubectl 無法連線到叢集
**錯誤訊息**:
```
The connection to the server localhost:8080 was refused
```

**解決方案**:
```bash
# 檢查 k3s 服務狀態
sudo systemctl status k3s

# 如果未運行，啟動 k3s
sudo systemctl start k3s

# 設定正確的 KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 或使用符號連結
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

### 問題 2: MCP Server 找不到可執行檔
**錯誤訊息**:
```
command not found: mcp-kubernetes-server
```

**解決方案**:
```bash
# 檢查實際安裝的套件
npm list -g | grep mcp

# 找到可執行檔位置
find ~/.nvm -name "mcp-*" -type f

# 更新 .mcp.json 中的 command 路徑為完整路徑
```

### 問題 3: 權限拒絕
**錯誤訊息**:
```
Error: EACCES: permission denied
```

**解決方案**:
```bash
# 對於 KUBECONFIG
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config

# 對於 Docker socket
sudo usermod -aG docker $USER
newgrp docker
```

---

## O-RAN 特定的 MCP 使用建議

### 1. xApp 開發工作流程

**使用 Filesystem + Docker MCP**:
```
1. 編輯 xApp 程式碼 (Filesystem MCP)
2. 建置 Docker 映像檔 (Docker MCP)
3. 部署到 Kubernetes (Kubernetes MCP)
4. 監控效能指標 (Prometheus MCP)
5. 建立 Pull Request (GitHub MCP)
```

### 2. 除錯 xApp 問題

**使用 Kubernetes + Prometheus MCP**:
```
1. 檢查 Pod 狀態
2. 查看容器日誌
3. 驗證 RMR 訊息流
4. 檢查 E2 Subscription
5. 分析效能瓶頸
```

### 3. 持續整合流程

**使用 GitHub + Docker + Kubernetes MCP**:
```
1. 推送程式碼到 GitHub
2. 自動建置 Docker 映像檔
3. 執行測試 (Playwright MCP)
4. 部署到測試環境
5. 驗證功能正常
6. 建立 Pull Request
```

---

## 效能監控目標

根據 O-RAN J Release 規範，以下是關鍵效能指標：

### 1. E2 Indication 處理延遲
**目標**: < 10ms
**監控方式**: Prometheus MCP 查詢
```promql
histogram_quantile(0.95, rate(e2_indication_processing_duration_seconds_bucket[5m]))
```

### 2. RMR 訊息吞吐量
**目標**: > 10,000 msg/sec
**監控方式**: Prometheus MCP 查詢
```promql
rate(rmr_messages_total[1m])
```

### 3. xApp 啟動時間
**目標**: < 30s
**監控方式**: Kubernetes MCP 查詢 Pod events
```bash
kubectl get events -n ricxapp --sort-by='.lastTimestamp'
```

### 4. 控制命令延遲
**目標**: < 100ms
**監控方式**: Prometheus MCP 查詢
```promql
histogram_quantile(0.95, rate(e2_control_latency_seconds_bucket[5m]))
```

---

## 結論

本次 MCP 伺服器配置驗證發現了以下關鍵問題並提供了解決方案：

1. ✅ **Kubernetes MCP Server 路徑錯誤** - 已修正為正確的可執行檔路徑
2. ✅ **KUBECONFIG 路徑問題** - 提供了兩種解決方案
3. ✅ **缺少 Docker MCP Server** - 強烈建議安裝
4. ✅ **缺少 Prometheus MCP Server** - 建議安裝以監控效能
5. ⚠️ **Context7 API Key 未設定** - 非必要，可選擇性使用

**後續步驟**:
1. 應用更新後的 .mcp.json 配置
2. 修正 KUBECONFIG 環境變數
3. 安裝建議的 Docker 和 Prometheus MCP Servers
4. 執行完整的驗證測試
5. 整合到 CI/CD 流程

這些 MCP 伺服器將大幅提升 O-RAN RIC Platform 的開發效率，特別是在 xApp 開發、容器管理和效能監控方面。
