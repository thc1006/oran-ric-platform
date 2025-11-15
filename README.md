# O-RAN Near-RT RIC Platform with Production-Ready xApps

<div align="center">

[![Version](https://img.shields.io/badge/version-v2.0.0-blue)](https://github.com/thc1006/oran-ric-platform/releases/tag/v2.0.0)
[![O-RAN SC](https://img.shields.io/badge/O--RAN%20SC-J%20Release-orange)](https://o-ran-sc.org)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-326ce5?logo=kubernetes)](https://kubernetes.io)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)
[![Prometheus](https://img.shields.io/badge/Monitoring-Prometheus-e6522c?logo=prometheus)](https://prometheus.io)
[![Grafana](https://img.shields.io/badge/Dashboards-Grafana-f46800?logo=grafana)](https://grafana.com)

*Production-ready O-RAN Near-RT RIC Platform with comprehensive xApps, Prometheus metrics integration, and E2 interface testing capabilities*

[Quick Start](docs/deployment/QUICKSTART.md) • [Documentation](docs/deployment/) • [Release Notes](https://github.com/thc1006/oran-ric-platform/releases/tag/v2.0.0) • [E2 Node Simulator](https://github.com/thc1006/oran-e2-node)

</div>

---

## 📖 Table of Contents

- [Overview](#-overview)
- [What's New in v2.0.0](#-whats-new-in-v200)
- [Architecture](#-architecture)
- [Quick Start](#-quick-start)
- [xApps](#-xapps)
- [Monitoring & Observability](#-monitoring--observability)
- [Testing](#-testing)
- [Documentation](#-documentation)
- [Technical Stack](#-technical-stack)
- [Project Structure](#-project-structure)
- [Contributing](#-contributing)
- [Credits](#-credits)

---

## 🎯 Overview

This repository provides a **production-grade deployment** of the O-RAN Software Community's Near-RT RIC Platform (J Release) with five fully-functional xApps, complete Prometheus metrics integration, Grafana dashboards, and comprehensive testing infrastructure.

### Key Features

✅ **5 Production-Ready xApps** - KPIMON, Traffic Steering, QoE Predictor, RAN Control, Federated Learning
✅ **Prometheus Metrics** - Complete observability with 8 alert rule categories
✅ **Grafana Dashboards** - Real-time visualization of xApp performance
✅ **E2 Simulator** - HTTP-based E2 interface traffic generator ([oran-e2-node](https://github.com/thc1006/oran-e2-node))
✅ **Automated Testing** - Playwright E2E test suite
✅ **Comprehensive Documentation** - Quick start, troubleshooting, and deployment guides
✅ **Kubernetes-Native** - Optimized for k3s with Helm charts

### Use Cases

- **5G RAN Testing** - Validate xApp logic without physical RAN equipment
- **Performance Benchmarking** - Measure E2 indication processing latency
- **Observability Development** - Build custom Grafana dashboards and alerts
- **Educational Platform** - Learn O-RAN architecture and xApp development
- **CI/CD Integration** - Automated deployment and testing pipelines

---

## ✨ What's New in v2.0.0

### 🏗️ Architecture Refactoring

**E2 Node Extraction** - Major Breaking Change

The E2 Node Simulator has been extracted to an independent repository: **[oran-e2-node](https://github.com/thc1006/oran-e2-node)**

```bash
# Migration: Initialize submodule after pulling
git submodule update --init --recursive
```

**Benefits:**
- Independent development cycle for E2 Node
- Cleaner repository structure
- Enables community contributions to E2 simulator

### 📊 Prometheus Metrics Integration (Complete)

**All xApps now expose metrics:**

| xApp | Metrics Endpoint | Port | Key Metrics |
|------|------------------|------|-------------|
| KPIMON | `/ric/v1/metrics` | 8080 | `kpimon_messages_received_total`, `kpimon_messages_processed_total` |
| Traffic Steering | `/ric/v1/metrics` | 8080 | Message counters, processing time |
| QoE Predictor | `/ric/v1/metrics` | 8080 | Prediction accuracy, latency |
| RAN Control | `/ric/v1/metrics` | 8080 | Control actions, success rate |
| Federated Learning | `/ric/v1/metrics` | 8080 | Training rounds, model accuracy |

**Prometheus Features:**
- Automatic scraping via annotations
- 8 comprehensive alert rule categories
- Custom recording rules for complex queries
- Integration with Grafana dashboards

### 📈 Grafana Dashboards

**Verified Dashboards:**
- xApp Performance Overview
- E2 Interface Metrics
- Resource Utilization
- Alert Status

**Automated Testing:**
- Playwright E2E tests verify dashboard data
- All 6 dashboard tests passing

### 🧪 E2 Interface Testing

**E2 Simulator Features:**
- Supports 5 xApps simultaneously
- Realistic KPI data generation (PRB, RSRP, RSRQ, CQI, MCS)
- Configurable simulation parameters (interval, cell ID)
- Kubernetes-native deployment

**Repository:** [github.com/thc1006/oran-e2-node](https://github.com/thc1006/oran-e2-node)

### 📚 Complete Documentation

**New Documentation:**
- [QUICKSTART.md](docs/deployment/QUICKSTART.md) - 10-minute deployment guide
- [TROUBLESHOOTING.md](docs/deployment/TROUBLESHOOTING.md) - Common issues & solutions
- [xapp-prometheus-metrics-integration.md](docs/deployment/xapp-prometheus-metrics-integration.md) - Complete deployment walkthrough (15,000+ words)

### 🐛 Bug Fixes

1. **Traffic Steering SDL Error** - Added error handling to prevent Pod restarts
2. **Port Configuration** - Unified Service, Deployment, Prometheus annotations
3. **E2 Simulator Ports** - Fixed QoE (8090) and RC (8100) port configuration
4. **KPIMON Metrics** - Added counter increment logic in /e2/indication endpoint
5. **Playwright Tests** - Updated to new headless mode (`--headless=new`)

### 🧹 Repository Cleanup

- Removed 10,000+ lines of archived HackMD documentation
- Updated `.gitignore` to exclude development artifacts
- Reduced repository size significantly
- Cleaner git history

---

## 🏗️ Architecture

### System Overview

```
┌─────────────────┐
│  E2 Simulator   │ (oran-e2-node)
│  (Submodule)    │
└────────┬────────┘
         │ HTTP POST /e2/indication
         ├──────────────────┬──────────────┬─────────────┬─────────────┐
         ↓                  ↓              ↓             ↓             ↓
┌─────────────┐  ┌──────────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│   KPIMON    │  │   Traffic    │  │   QoE    │  │    RC    │  │    FL    │
│   :8081     │  │   Steering   │  │ Predictor│  │   :8100  │  │   :8110  │
│   :8080*    │  │   :8081      │  │   :8090  │  │   :8080* │  │   :8080* │
└──────┬──────┘  └──────┬───────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
       │                │                │             │             │
       │          Prometheus Scraping (:8080)          │             │
       └────────────────┴────────────────┴─────────────┴─────────────┘
                        │
                 ┌──────▼──────┐
                 │  Prometheus │
                 │   :9090     │
                 └──────┬──────┘
                        │
                 ┌──────▼──────┐
                 │   Grafana   │
                 │   :3000     │
                 └─────────────┘
```

*Port 8080: Prometheus metrics HTTP server
*Port 8081/8090/8100/8110: xApp business logic API

### Component Versions

| Component | Version | Status |
|-----------|---------|--------|
| O-RAN SC | J Release | Stable |
| Kubernetes | 1.28+ | Stable |
| KPIMON | v1.0.1 | ✅ Production |
| Traffic Steering | v1.0.2 | ✅ Production |
| QoE Predictor | v1.0.1 | ✅ Production |
| RAN Control | v1.0.1 | ✅ Production |
| Federated Learning | v1.0.0 | ✅ Production |
| E2 Simulator | v1.0.0 | ✅ Independent Repo |
| Prometheus | Latest | ✅ Integrated |
| Grafana | Latest | ✅ Integrated |

---

## 🚀 Quick Start

### Prerequisites

- **Kubernetes**: k3s v1.28+ or equivalent
- **Helm**: 3.x
- **Docker**: Latest version
- **System Resources**: 8+ CPU cores, 16GB+ RAM, 100GB+ disk

### 1. Clone Repository (with Submodules)

```bash
git clone --recurse-submodules https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform
```

**Existing clones:** Run `git submodule update --init --recursive`

### 2. Deploy All xApps (Automated)

```bash
sudo bash scripts/redeploy-xapps-with-metrics.sh
```

This script automatically:
- Builds all xApp Docker images
- Pushes to local registry (localhost:5000)
- Deploys to `ricxapp` namespace
- Verifies metrics endpoints

### 3. Deploy E2 Simulator

```bash
sudo bash scripts/deployment/deploy-e2-simulator.sh
```

### 4. Configure Prometheus Alerts

```bash
kubectl create configmap r4-infrastructure-prometheus-server \
  --from-file=alerting_rules.yml=monitoring/prometheus/alerts/xapp-alerts.yml \
  --from-file=prometheus.yml=monitoring/prometheus/prometheus.yml \
  --dry-run=client -o yaml | kubectl apply -n ricplt -f -

# Restart Prometheus to load alerts
kubectl delete pod -n ricplt -l app=prometheus,component=server
```

### 5. Access Monitoring UIs

**Prometheus:**
```bash
kubectl port-forward -n ricplt svc/r4-infrastructure-prometheus-server 9090:80
# Open: http://localhost:9090
```

**Grafana:**
```bash
kubectl port-forward -n ricplt svc/r4-infrastructure-grafana 3000:80
# Open: http://localhost:3000
# Username: admin
# Password: oran-ric-admin
```

### 6. Verify Deployment

```bash
# Check all xApp Pods
kubectl get pods -n ricxapp

# Expected output (all 1/1 Running):
# kpimon-xxx              1/1     Running
# traffic-steering-xxx    1/1     Running
# qoe-predictor-xxx       1/1     Running
# ran-control-xxx         1/1     Running
# federated-learning-xxx  1/1     Running
# e2-simulator-xxx        1/1     Running

# Verify metrics
kubectl exec -n ricxapp $(kubectl get pod -n ricxapp -l app=kpimon -o jsonpath='{.items[0].metadata.name}') -- \
  curl -s http://localhost:8080/ric/v1/metrics | grep kpimon_messages
```

**🎉 Deployment Complete!** See [QUICKSTART.md](docs/deployment/QUICKSTART.md) for more details.

---

## 📦 xApps

### KPIMON xApp

**Purpose:** KPI monitoring and anomaly detection

**Features:**
- E2SM-KPM v3.0 support
- 20+ KPI types monitoring
- Real-time metrics streaming
- HTTP endpoint for E2 indications (port 8081)

**Metrics:**
```promql
kpimon_messages_received_total
kpimon_messages_processed_total
kpimon_processing_time_seconds
kpimon_active_subscriptions
kpimon_kpi_value{type="prb_usage_dl"}
```

**Documentation:** [xapps/kpimon-go-xapp/README.md](xapps/kpimon-go-xapp/README.md)

---

### Traffic Steering xApp

**Purpose:** Policy-driven handover decision making

**Features:**
- E2SM-KPM + E2SM-RC integration
- A1 policy management
- Dynamic handover decisions
- SDL error handling

**Endpoints:**
- `/e2/indication` (8081) - Receive E2 messages
- `/ric/v1/health/alive` (8080) - Liveness check
- `/ric/v1/health/ready` (8080) - Readiness check
- `/ric/v1/metrics` (8080) - Prometheus metrics

**Documentation:** [docs/traffic-steering-deployment.md](docs/traffic-steering-deployment.md)

---

### QoE Predictor xApp

**Purpose:** ML-based QoE prediction and optimization

**Features:**
- Machine learning model for QoE prediction
- Collaboration with Traffic Steering
- Real-time prediction API
- HTTP endpoint (port 8090)

**Dependencies:**
- TensorFlow 2.15.0 (optional GPU acceleration)

---

### RAN Control xApp

**Purpose:** RAN control and optimization

**Features:**
- E2SM-RC v2.0 support
- 5 optimization algorithms
- Control action execution
- HTTP endpoint (port 8100)

**Optimization Algorithms:**
1. Handover optimization
2. Resource allocation
3. Load balancing
4. Network slicing
5. Power control

---

### Federated Learning xApp

**Purpose:** Distributed federated learning framework

**Features:**
- Multi-model support (TensorFlow + PyTorch)
- Privacy-preserving training
- Aggregation algorithms
- HTTP endpoint (port 8110)

**Use Cases:**
- RAN parameter optimization
- Traffic prediction
- Anomaly detection

---

## 📊 Monitoring & Observability

### Prometheus Integration

**Scraping Configuration:**

All xApps are auto-discovered via Pod annotations:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/ric/v1/metrics"
```

**Available Metrics:**

```promql
# Message Counters
kpimon_messages_received_total
kpimon_messages_processed_total

# Performance Metrics
kpimon_processing_time_seconds_bucket
kpimon_processing_time_seconds_sum
kpimon_processing_time_seconds_count

# Business Metrics
kpimon_active_subscriptions
kpimon_kpi_value{type="prb_usage_dl"}
kpimon_kpi_value{type="active_ue_count"}
```

### Alert Rules

**8 Alert Categories:**

1. **xApp Availability** - Pod down, restart loops
2. **Message Processing** - Stalled processing, high latency
3. **Resource Usage** - CPU/memory limits
4. **E2 Interface** - Connection failures
5. **Business Logic** - PRB usage, signal quality
6. **Prometheus Self-Monitoring** - Scrape failures
7. **Network** - Service unreachable
8. **Data Quality** - Missing metrics, stale data

**Example Alert:**

```yaml
- alert: KPIMONMessageProcessingStalled
  expr: rate(kpimon_messages_received_total[5m]) == 0 and kpimon_messages_received_total > 0
  for: 5m
  labels:
    severity: critical
    component: kpimon
  annotations:
    summary: "KPIMON message processing has stalled"
```

### Grafana Dashboards

**Included Dashboards:**

- **xApp Performance** - Message rates, processing time, error rates
- **E2 Interface** - Indication counts, latency, connection status
- **Resource Utilization** - CPU, memory, network I/O
- **Alert Overview** - Active alerts, alert history

**Access:** http://localhost:3000 (after port-forward)

---

## 🧪 Testing

### E2E Testing with Playwright

**Test Suite:** 6 tests covering all Grafana dashboards

```bash
# Install dependencies (first time)
npm install

# Run tests
npm run test:grafana
```

**Test Coverage:**
- ✅ Dashboard accessibility
- ✅ Metrics data presence
- ✅ Panel rendering
- ✅ Query execution
- ✅ Alert rule verification
- ✅ Time range functionality

**Configuration:** [playwright.config.js](playwright.config.js)

### E2 Simulator Testing

**Continuous Traffic Generation:**

```bash
# View E2 Simulator logs
kubectl logs -n ricxapp -l app=e2-simulator -f

# Expected output:
# Simulation Iteration 120
# Successfully sent to kpimon (200)
# Successfully sent to traffic-steering (200)
# ...
```

**Manual Testing:**

```bash
# Test KPIMON endpoint
kubectl exec -n ricxapp e2-simulator-xxx -- \
  curl -X POST http://kpimon.ricxapp.svc.cluster.local:8081/e2/indication \
  -H "Content-Type: application/json" \
  -d '{"cell_id": 1234567, "prb_usage_dl": 45.5}'
```

### Performance Testing

**Targets:**
- E2 indication processing: < 10ms
- Control command latency: < 100ms
- xApp startup time: < 30s
- Prometheus scraping: < 5s

**Benchmark:**

```bash
# Measure processing latency
kubectl logs -n ricxapp -l app=kpimon | grep "Processing time:"
```

---

## 📚 Documentation

### Deployment Guides

| Document | Description | Target Audience |
|----------|-------------|-----------------|
| [QUICKSTART.md](docs/deployment/QUICKSTART.md) | 10-minute deployment | Experienced users |
| [xapp-prometheus-metrics-integration.md](docs/deployment/xapp-prometheus-metrics-integration.md) | Complete walkthrough (15k words) | First-time deployers |
| [TROUBLESHOOTING.md](docs/deployment/TROUBLESHOOTING.md) | Common issues & solutions | All users |
| [README.md](docs/deployment/README.md) | Documentation index | All users |

### Technical Documentation

- **xApp Implementation:** Each xApp directory contains detailed README
- **RIC Platform Config:** [docs/RIC-DEP-CUSTOMIZATION.md](docs/RIC-DEP-CUSTOMIZATION.md)
- **Project Structure:** [docs/PROJECT-REORGANIZATION-PLAN.md](docs/PROJECT-REORGANIZATION-PLAN.md)

### API Documentation

**Health Check Endpoints:**

```bash
# Liveness (is xApp running?)
GET /ric/v1/health/alive

# Readiness (is xApp ready to serve?)
GET /ric/v1/health/ready

# Metrics (Prometheus format)
GET /ric/v1/metrics
```

**E2 Indication Endpoint:**

```bash
POST /e2/indication
Content-Type: application/json

{
  "cell_id": 1234567,
  "prb_usage_dl": 45.5,
  "prb_usage_ul": 32.8,
  "active_ue_count": 25
}
```

---

## 🛠️ Technical Stack

### Core Technologies

- **O-RAN SC**: J Release (April 2025)
- **Kubernetes**: v1.28.5 (k3s)
- **Helm**: 3.x
- **Docker**: Latest

### Programming Languages

- **Python**: 3.11+ (xApps)
- **Go**: 1.19+ (RMR library)
- **JavaScript**: ES6+ (Testing)

### Libraries & Frameworks

- **ricxappframe**: 3.2.2 (Python xApp framework)
- **RMR**: 4.9.4 (RIC Message Router)
- **ricsdl**: 3.0.2 (Shared Data Layer)
- **Prometheus Client**: Latest
- **Playwright**: Latest (E2E testing)

### Infrastructure

- **Container Registry**: localhost:5000 (Docker registry)
- **Service Mesh**: Native Kubernetes
- **Storage**: Redis (SDL backend)
- **Monitoring**: Prometheus + Grafana

---

## 📁 Project Structure

```
oran-ric-platform/
├── docs/                           # Documentation
│   ├── deployment/                 # Deployment guides (NEW in v2.0.0)
│   │   ├── README.md               # Documentation index
│   │   ├── QUICKSTART.md           # 10-minute deployment
│   │   ├── TROUBLESHOOTING.md      # Common issues
│   │   └── xapp-prometheus-metrics-integration.md  # Complete guide
│   ├── RIC-DEP-CUSTOMIZATION.md    # Platform configuration
│   └── PROJECT-REORGANIZATION-PLAN.md  # Project history
│
├── xapps/                          # xApp implementations
│   ├── kpimon-go-xapp/             # KPIMON v1.0.1
│   ├── traffic-steering/           # Traffic Steering v1.0.2
│   ├── qoe-predictor/              # QoE Predictor v1.0.1
│   ├── ran-control/                # RAN Control v1.0.1
│   └── federated-learning/         # Federated Learning v1.0.0
│
├── monitoring/                     # Monitoring configuration (NEW)
│   ├── prometheus/
│   │   ├── alerts/
│   │   │   └── xapp-alerts.yml     # 8 alert categories
│   │   └── prometheus.yml          # Scraping config
│   └── grafana/
│       └── dashboards/             # Grafana dashboards
│
├── simulator/                      # E2 interface testing
│   └── e2-simulator/               # Git submodule → oran-e2-node
│
├── scripts/                        # Automation scripts
│   ├── redeploy-xapps-with-metrics.sh  # One-click deployment
│   └── deployment/
│       └── deploy-e2-simulator.sh  # E2 Simulator deployment
│
├── tests/                          # Automated tests (NEW)
│   └── grafana/
│       └── dashboards.spec.js      # Playwright E2E tests
│
├── ric-dep/                        # RIC Platform Helm charts
│   ├── helm/
│   │   └── infrastructure/         # Platform components
│   └── bin/                        # Installation scripts
│
├── legacy/                         # Reference implementations
│
├── .gitignore                      # Git exclusions
├── .gitmodules                     # Git submodule config (NEW)
├── package.json                    # Node.js dependencies (testing)
├── playwright.config.js            # Playwright configuration
└── README.md                       # This file
```

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

**Coding Standards:**
- Follow Python PEP 8
- Add comprehensive docstrings
- Write tests for new features
- Update documentation

---

## 🙏 Credits

### Author

**蔡秀吉 (thc1006)**

### Related Projects

- [oran-e2-node](https://github.com/thc1006/oran-e2-node) - E2 Node Simulator (Independent Repository)

### Built With

- [O-RAN Software Community](https://o-ran-sc.org/) - O-RAN SC J Release
- [Kubernetes](https://kubernetes.io/) - Container Orchestration
- [Prometheus](https://prometheus.io/) - Monitoring & Alerting
- [Grafana](https://grafana.com/) - Visualization
- [Playwright](https://playwright.dev/) - E2E Testing

---

## 📝 Changelog

### v2.0.0 (2025-11-15)

**Architecture:**
- Extracted E2 Node to independent repository ([oran-e2-node](https://github.com/thc1006/oran-e2-node))
- Removed 10,000+ lines of archived documentation
- Updated `.gitignore` for cleaner repository

**Features:**
- Complete Prometheus metrics integration for all xApps
- 8 comprehensive Prometheus alert rule categories
- Grafana dashboards with automated E2E testing
- HTTP endpoints for all xApps (8081/8090/8100/8110)
- E2 Simulator with realistic KPI generation

**Bug Fixes:**
- Fixed Traffic Steering SDL error handling
- Unified port configuration across all components
- Fixed KPIMON metrics increment logic
- Updated Playwright to new headless mode

**Documentation:**
- Added QUICKSTART.md (10-minute deployment)
- Added TROUBLESHOOTING.md (comprehensive debugging)
- Added 15,000-word complete deployment guide
- Updated all xApp README files

### Earlier Versions

- **v1.0.0-phase4** (2025-11-15) - ML xApps deployment
- **v1.0.0-phase3** (2025-11-14) - Traffic Steering deployment
- **v1.0.0-phase2** (2025-11-13) - Project reorganization
- **v1.0.0-phase1** (2025-11-12) - Initial KPIMON + RC deployment

---

## 📄 License

Apache License 2.0 - See [LICENSE](LICENSE) for details.

---

## 🔗 Links

- **GitHub Repository**: https://github.com/thc1006/oran-ric-platform
- **E2 Node Simulator**: https://github.com/thc1006/oran-e2-node
- **Issues**: https://github.com/thc1006/oran-ric-platform/issues
- **Releases**: https://github.com/thc1006/oran-ric-platform/releases
- **O-RAN SC Wiki**: https://wiki.o-ran-sc.org/

---

<div align="center">

**Made with ❤️ by 蔡秀吉 (thc1006)**

*Advancing O-RAN deployment with production-ready xApps and comprehensive observability*

[⬆ Back to Top](#o-ran-near-rt-ric-platform-with-production-ready-xapps)

</div>
