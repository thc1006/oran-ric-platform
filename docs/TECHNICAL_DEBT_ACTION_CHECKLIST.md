# 技術債務修復行動檢查清單

**作者**: 蔡秀吉 (thc1006)
**建立日期**: 2025-11-17
**參考文檔**: [TECHNICAL_DEBT_ANALYSIS.md](./TECHNICAL_DEBT_ANALYSIS.md)

---

## 🔥 緊急行動項目 (本週完成)

### TD-015: 移除硬編碼密碼 ⚠️ CRITICAL
- [ ] **檢查所有配置檔案中的硬編碼密碼**
  ```bash
  grep -r "password\|passwd\|secret" config/ --include="*.yaml" --include="*.yml"
  ```
- [ ] **建立 Grafana Secret**
  ```bash
  kubectl create secret generic grafana-admin-secret \
    --from-literal=admin-user=admin \
    --from-literal=admin-password=$(openssl rand -base64 32) \
    -n ricplt
  ```
- [ ] **更新 config/grafana-values.yaml**
  ```yaml
  admin:
    existingSecret: grafana-admin-secret
    userKey: admin-user
    passwordKey: admin-password
  ```
- [ ] **測試 Grafana 登入功能**
- [ ] **記錄密碼檢索方法到 README.md**

**預估時間**: 4 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-002: 修復 xApp 配置不一致 ⚠️ CRITICAL
- [ ] **建立配置驗證腳本**
  ```bash
  # scripts/validate-xapp-configs.sh
  #!/bin/bash
  # 驗證 config.json 與 deployment.yaml 的 port 一致性
  ```
- [ ] **修復 KPIMON xApp**
  - [ ] 統一 config.json 中定義 health check port
  - [ ] 更新 deployment.yaml 使用 ConfigMap 環境變數
- [ ] **修復 Traffic Steering xApp**
  - [ ] 統一 port 號碼 (8080 或 8081)
  - [ ] 更新 livenessProbe 路徑
- [ ] **修復其他 xApp**
  - [ ] QoE Predictor
  - [ ] Federated Learning
- [ ] **在 CI/CD 中整合驗證腳本**
- [ ] **測試所有 xApp 健康檢查**

**預估時間**: 6 小時
**負責人**: ___________
**完成日期**: ___________

---

## 📋 Sprint 1 (Week 1-2)

### TD-001: 配置檔案結構重構
- [ ] **建立新的配置結構**
  ```
  platform/values/
  ├── base.yaml
  ├── environments/
  │   ├── dev.yaml
  │   ├── staging.yaml
  │   └── prod.yaml
  └── components/
      ├── e2mgr.yaml
      ├── e2term.yaml
      └── ...
  ```
- [ ] **遷移現有 local.yaml 內容到 base.yaml**
- [ ] **提取環境特定設定**
- [ ] **更新部署腳本支援 `-f` 環境參數**
- [ ] **測試多環境部署**
- [ ] **更新文檔**

**預估時間**: 10 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-004: 統一 SDL 配置
- [ ] **確定標準 Redis Service 名稱**
  - [ ] 選擇: `service-ricplt-dbaas-tcp.ricplt` (官方) 或 `redis-service.ricplt` (自定義)
- [ ] **建立 SDL ConfigMap**
  ```yaml
  # config/sdl-config.yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: ric-sdl-config
    namespace: ricplt
  data:
    SDL_HOST: "service-ricplt-dbaas-tcp.ricplt"
    SDL_PORT: "6379"
  ```
- [ ] **更新所有 xApp config.json**
  - [ ] KPIMON (db: 0)
  - [ ] Traffic Steering (db: 1)
  - [ ] RC xApp (db: 2)
  - [ ] Federated Learning (db: 3)
- [ ] **記錄 DB index 分配策略**
- [ ] **測試 SDL 連接**

**預估時間**: 6 小時
**負責人**: ___________
**完成日期**: ___________

---

## 📋 Sprint 2 (Week 3-4)

### TD-005: 修復完整 RIC Platform 部署
- [ ] **修正 deploy-ric-platform.sh 路徑引用**
  - [ ] Line 321: 使用正確的 ric-dep/helm/ 路徑
  - [ ] Line 335: 建立缺少的 rmr-routes.txt
  - [ ] Line 345: 建立缺少的 network-policies/
- [ ] **測試完整平台部署**
  - [ ] E2Mgr
  - [ ] E2Term
  - [ ] SubMgr
  - [ ] A1 Mediator
  - [ ] AppMgr
- [ ] **建立部署驗證測試**
- [ ] **更新 README.md 說明兩種部署模式**

**預估時間**: 16 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-017: 實施 NetworkPolicy
- [ ] **為每個 xApp 建立 NetworkPolicy**
  ```yaml
  # 範例: xapps/kpimon-go-xapp/deploy/networkpolicy.yaml
  ```
  - [ ] KPIMON
  - [ ] Traffic Steering
  - [ ] RC xApp
  - [ ] QoE Predictor
  - [ ] Federated Learning
- [ ] **限制 Ingress (只允許 E2Term/監控)**
- [ ] **限制 Egress (DNS + SDL + InfluxDB)**
- [ ] **測試網路隔離**
- [ ] **記錄 NetworkPolicy 設計決策 (ADR)**

**預估時間**: 8 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-028: 整合依賴漏洞掃描
- [ ] **選擇掃描工具** (Snyk / Trivy / Grype)
- [ ] **建立 CI/CD Job**
  ```yaml
  # .gitlab-ci.yml
  security:scan:
    stage: security
    script:
      - trivy image localhost:5000/xapp-kpimon:latest
  ```
- [ ] **設定掃描閾值** (High/Critical 必須修復)
- [ ] **建立漏洞修復流程**
- [ ] **每週自動掃描排程**

**預估時間**: 8 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-007: RMR 路由外部化
- [ ] **為每個 xApp 建立 RMR ConfigMap**
  ```yaml
  # xapps/kpimon-go-xapp/deploy/rmr-routes-configmap.yaml
  ```
- [ ] **移除 Dockerfile 中的硬編碼路由**
- [ ] **更新 deployment.yaml volume mount**
- [ ] **重建所有 xApp 映像**
- [ ] **測試 RMR 訊息路由**

**預估時間**: 8 小時
**負責人**: ___________
**完成日期**: ___________

---

## 📋 Sprint 3 (Week 5-6)

### TD-013: Dockerfile 優化 (Multi-stage build)
- [ ] **為每個 xApp 重寫 Dockerfile**
  - [ ] KPIMON
  - [ ] Traffic Steering
  - [ ] RC xApp
  - [ ] QoE Predictor
  - [ ] Federated Learning
- [ ] **建立共用 Builder stage**
- [ ] **移除運行時映像中的構建工具**
- [ ] **測試映像功能完整性**
- [ ] **測量映像大小減少比例**

**預估時間**: 16 小時
**負責人**: ___________
**完成日期**: ___________

**目標**: 映像大小減少 > 40%

---

### TD-016: 實施 RBAC
- [ ] **為每個 xApp 建立 RBAC 資源**
  ```yaml
  # xapps/kpimon-go-xapp/deploy/rbac.yaml
  # - ServiceAccount
  # - Role
  # - RoleBinding
  ```
- [ ] **定義最小權限集**
  - [ ] ConfigMap: get, list, watch
  - [ ] Secret: get (特定資源)
  - [ ] Pod: get, list (自己的 namespace)
- [ ] **測試權限限制**
- [ ] **記錄 RBAC 策略文檔**

**預估時間**: 12 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-011 (Part 1): 建立單元測試框架
- [ ] **為每個 xApp 建立測試目錄結構**
  ```
  xapps/kpimon-go-xapp/
  ├── tests/
  │   ├── __init__.py
  │   ├── test_kpimon.py
  │   ├── test_integration.py
  │   └── fixtures/
  ├── pytest.ini
  └── .coveragerc
  ```
- [ ] **編寫核心邏輯單元測試**
  - [ ] KPIMON: KPI 處理邏輯
  - [ ] Traffic Steering: Handover 決策邏輯
  - [ ] RC xApp: 控制邏輯
- [ ] **設定 pytest 和 coverage**
- [ ] **整合到 CI/CD**
- [ ] **目標覆蓋率: 50%**

**預估時間**: 20 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-022: 實施備份策略
- [ ] **Redis RDB 備份配置**
  ```yaml
  # platform/values/base.yaml
  dbaas:
    backup:
      enabled: true
      schedule: "0 2 * * *"
      retention: 7
  ```
- [ ] **InfluxDB 備份 CronJob**
  ```yaml
  # config/influxdb-backup-cronjob.yaml
  ```
- [ ] **建立 MinIO/S3 儲存桶**
- [ ] **測試備份恢復流程**
- [ ] **記錄備份 SOP**

**預估時間**: 16 小時
**負責人**: ___________
**完成日期**: ___________

---

## 📋 Sprint 4 (Week 7-8)

### TD-011 (Part 2): 提升測試覆蓋率
- [ ] **增加邊界條件測試**
- [ ] **增加錯誤處理測試**
- [ ] **增加整合測試**
- [ ] **目標覆蓋率: 70%**
- [ ] **生成測試報告**
- [ ] **修復發現的 Bug**

**預估時間**: 20 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-030: 建立完整 CI/CD Pipeline
- [ ] **定義 Pipeline stages**
  ```yaml
  stages:
    - lint
    - test
    - security
    - build
    - deploy
  ```
- [ ] **Lint stage**
  - [ ] shellcheck
  - [ ] pylint
  - [ ] yamllint
- [ ] **Test stage**
  - [ ] pytest with coverage
  - [ ] E2E tests
- [ ] **Security stage**
  - [ ] Dependency scan
  - [ ] Image scan
- [ ] **Build stage**
  - [ ] Docker build
  - [ ] Push to registry
- [ ] **Deploy stage**
  - [ ] Deploy to staging
  - [ ] Smoke tests

**預估時間**: 24 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-010: 統一錯誤處理
- [ ] **建立錯誤處理模式文檔**
  ```python
  # 標準模式
  def handler():
      try:
          return _handler_impl()
      except Exception as e:
          logger.exception(f"Error: {e}")
          return error_response()

  def _handler_impl():
      # 業務邏輯
  ```
- [ ] **重構所有 xApp handler**
  - [ ] KPIMON
  - [ ] Traffic Steering
  - [ ] RC xApp
  - [ ] QoE Predictor
  - [ ] Federated Learning
- [ ] **建立自定義異常類別**
- [ ] **統一日誌格式**

**預估時間**: 12 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-020: 標準化 Prometheus Metrics
- [ ] **審查所有 Metrics 命名**
- [ ] **修正不符合規範的命名**
  ```python
  # Before
  KPI_VALUES = Gauge('kpimon_kpi_value', ...)

  # After
  KPI_VALUES = Gauge('kpimon_kpi_value_current', ...)
  ```
- [ ] **添加單位到 Metrics 名稱**
  - [ ] `_seconds` (時間)
  - [ ] `_bytes` (容量)
  - [ ] `_total` (Counter)
- [ ] **更新 Grafana Dashboards**
- [ ] **記錄 Metrics 目錄**

**預估時間**: 4 小時
**負責人**: ___________
**完成日期**: ___________

---

## 📋 Sprint 5-6 (Week 9-12)

### TD-014: 建立共用基礎映像
- [ ] **建立 xapp-base Dockerfile**
  ```dockerfile
  # xapps/base-image/Dockerfile
  FROM python:3.11-slim
  # 安裝 RMR library
  # 安裝共用依賴
  ```
- [ ] **構建並推送基礎映像**
- [ ] **更新所有 xApp Dockerfile 使用 base image**
- [ ] **測試所有 xApp**
- [ ] **記錄基礎映像版本管理策略**

**預估時間**: 8 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-021: 整合 Jaeger Tracing
- [ ] **在 xApp 中添加 OpenTelemetry SDK**
  ```python
  from opentelemetry import trace
  from opentelemetry.exporter.jaeger.thrift import JaegerExporter
  ```
- [ ] **配置 Jaeger Exporter**
- [ ] **為關鍵路徑添加 Span**
  - [ ] RMR 訊息處理
  - [ ] HTTP API 請求
  - [ ] SDL 操作
- [ ] **部署 Jaeger UI**
- [ ] **測試追蹤功能**
- [ ] **記錄使用文檔**

**預估時間**: 16 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-023: 完成 API 文檔
- [ ] **為每個 xApp 建立 OpenAPI spec**
  ```yaml
  # xapps/kpimon-go-xapp/api/openapi.yaml
  openapi: 3.0.0
  info:
    title: KPIMON xApp API
    version: 1.0.0
  paths:
    /health/alive:
      get:
        summary: Liveness probe
  ```
- [ ] **使用 Swagger UI 部署文檔**
- [ ] **自動化 API 文檔生成**
- [ ] **在 README 中添加 API 文檔鏈接**

**預估時間**: 12 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-024: 建立 ADR 文檔體系
- [ ] **建立 ADR 目錄結構**
  ```
  docs/architecture/decisions/
  ├── 0001-use-python-for-xapps.md
  ├── 0002-lightweight-vs-full-deployment.md
  ├── 0003-prometheus-for-metrics.md
  ├── 0004-rmr-routing-strategy.md
  └── template.md
  ```
- [ ] **撰寫關鍵 ADR**
  - [ ] 為什麼選擇 Python 而非 Go
  - [ ] 為什麼使用輕量級部署模式
  - [ ] NetworkPolicy 設計決策
  - [ ] SDL 配置策略
- [ ] **建立 ADR 審查流程**

**預估時間**: 8 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-026: 清理 Legacy 代碼
- [ ] **建立 legacy/README.md 說明用途**
  ```markdown
  # Legacy xApp 實作

  ⚠️ **警告**: 此目錄僅供參考，請勿部署。

  這些是舊版本的 xApp 實作，保留作為：
  - 設計參考
  - 遷移對照
  - 歷史記錄

  當前生產版本位於 `/xapps` 目錄。
  ```
- [ ] **評估是否保留或刪除**
  - [ ] 如保留: 移至獨立分支
  - [ ] 如刪除: 確認無依賴後移除
- [ ] **更新 .gitignore**

**預估時間**: 4 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-009: 自動化程式碼格式化
- [ ] **安裝 isort 和 black**
  ```bash
  pip install isort black
  ```
- [ ] **建立配置檔案**
  ```ini
  # pyproject.toml
  [tool.black]
  line-length = 100

  [tool.isort]
  profile = "black"
  ```
- [ ] **格式化所有 Python 檔案**
  ```bash
  isort xapps/*/src/*.py
  black xapps/*/src/*.py
  ```
- [ ] **整合到 CI/CD (pre-commit hook)**
- [ ] **更新 CONTRIBUTING.md**

**預估時間**: 2 小時
**負責人**: ___________
**完成日期**: ___________

---

### TD-003: 調整資源配置
- [ ] **執行負載測試**
  ```bash
  # 使用 locust 或 k6
  locust -f tests/load/kpimon_load_test.py
  ```
- [ ] **收集資源使用數據**
  - [ ] CPU 使用率
  - [ ] Memory 使用率
  - [ ] 請求延遲
- [ ] **調整資源限制**
  - [ ] 統一 request/limit 比例為 1:2
  - [ ] 為關鍵 xApp 設定 Guaranteed QoS
- [ ] **測試調整後性能**
- [ ] **記錄資源配置決策**

**預估時間**: 8 小時
**負責人**: ___________
**完成日期**: ___________

---

## ✅ 驗收標準

### Phase 1 完成標準
- [ ] 部署成功率 ≥ 95%
- [ ] 無硬編碼密碼 (安全掃描通過)
- [ ] NetworkPolicy 覆蓋 100% xApps
- [ ] 配置一致性檢查通過

### Phase 2 完成標準
- [ ] 單元測試覆蓋率 ≥ 70%
- [ ] CI/CD Pipeline 通過率 ≥ 90%
- [ ] 映像大小減少 ≥ 40%
- [ ] 自動備份每日運行

### Phase 3 完成標準
- [ ] Jaeger UI 可追蹤請求
- [ ] API 文檔自動生成
- [ ] 所有 ADR 完成並審查
- [ ] Legacy 代碼完全隔離

---

## 📊 進度追蹤

### 完成統計
- [ ] P0 問題: 0/2 (0%)
- [ ] P1 問題: 0/9 (0%)
- [ ] P2 問題: 0/11 (0%)
- [ ] P3 問題: 0/8 (0%)
- [ ] 總計: 0/30 (0%)

### 工時追蹤
- 計劃工時: 222 小時
- 實際工時: _______ 小時
- 差異: _______ 小時

### 里程碑
- [ ] Sprint 1 完成 (Week 2)
- [ ] Sprint 2 完成 (Week 4)
- [ ] Sprint 3 完成 (Week 6)
- [ ] Sprint 4 完成 (Week 8)
- [ ] Sprint 5-6 完成 (Week 12)

---

## 📝 會議與審查

### 每週站會
- 時間: 每週一 10:00 AM
- 議程:
  - 上週完成項目
  - 本週計劃
  - 阻礙討論

### 雙週 Sprint Review
- 時間: 每兩週五 3:00 PM
- 議程:
  - Demo 完成功能
  - 驗收標準檢查
  - 下一 Sprint 規劃

### 季度技術債務審查
- 時間: 每季度第一週
- 議程:
  - 新增債務評估
  - 修復進度回顧
  - 策略調整

---

## 🔗 相關資源

- [完整技術債務分析](./TECHNICAL_DEBT_ANALYSIS.md)
- [執行摘要](./TECHNICAL_DEBT_EXECUTIVE_SUMMARY.md)
- [CLAUDE.md 開發規範](/home/thc1006/oran-ric-platform/CLAUDE.md)
- [部署問題記錄](/home/thc1006/oran-ric-platform/DEPLOYMENT_ISSUES_LOG.md)

---

**最後更新**: 2025-11-17
**維護者**: 蔡秀吉 (thc1006)
