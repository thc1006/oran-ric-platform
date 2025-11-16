# O-RAN Near-RT RIC Platform with Production xApps

<div align="center">

[![Version](https://img.shields.io/badge/version-v2.0.0-blue)](https://github.com/thc1006/oran-ric-platform/releases/tag/v2.0.0)
[![O-RAN SC](https://img.shields.io/badge/O--RAN%20SC-J%20Release-orange)](https://o-ran-sc.org)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-326ce5?logo=kubernetes)](https://kubernetes.io)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)

[Quick Start](#quick-start) • [Documentation](docs/deployment/) • [E2 Simulator](https://github.com/thc1006/oran-e2-node)

</div>

---

## TLDR

**What**: Production-ready O-RAN Near-RT RIC Platform (J Release) with 5 functional xApps and complete observability stack.

**Includes**: KPIMON, Traffic Steering, QoE Predictor, RAN Control, Federated Learning xApps + Prometheus metrics + Grafana dashboards + E2 traffic simulator.

**For**: 5G RAN testing without physical equipment, xApp development, performance benchmarking, educational deployments, CI/CD integration.

**Deploy**: Clone → Run deployment script → Access Grafana (10 minutes).

**New in v2.0.0**: E2 Node extracted to [separate repo](https://github.com/thc1006/oran-e2-node), complete metrics integration, 8 alert rule categories, automated testing.

---

## Quick Start

### System Requirements
- **OS**: Ubuntu 20.04/22.04/24.04 LTS (recommended)
- **Resources**: 8+ CPU cores, 16GB+ RAM, 100GB+ disk
- **Network**: Internet access for package downloads

### Installation (One-Time Setup)

#### Option A: Automated Setup (Recommended)

```bash
# 1. Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# 2. Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 3. Install k3s and setup cluster (includes CNI, MetalLB, namespaces)
git clone https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform
sudo bash scripts/deployment/setup-k3s.sh

# 4. Reload shell to apply KUBECONFIG
source ~/.bashrc
```

**Verification:**
```bash
docker --version    # Should show Docker 27.x+
helm version        # Should show v3.x+
kubectl get nodes   # Should show Ready node
```

#### Option B: Manual Step-by-Step

```bash
# 1. Install Docker
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker

# 2. Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 3. Install k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.5+k3s1 sh -s - server \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb

# 4. Setup KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc
source ~/.bashrc

# 5. Create namespaces
kubectl create namespace ricplt
kubectl create namespace ricxapp
kubectl create namespace ricobs
```

### Deploy (5 Steps)

```bash
# 1. Clone repository (if not already cloned)
git clone https://github.com/thc1006/oran-ric-platform.git
cd oran-ric-platform

# 2. Deploy Prometheus
helm install r4-infrastructure-prometheus ./ric-dep/helm/infrastructure/subcharts/prometheus \
  --namespace ricplt --values ./config/prometheus-values.yaml

# 3. Deploy Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install oran-grafana grafana/grafana -n ricplt -f ./config/grafana-values.yaml

# 4. Deploy xApps
kubectl apply -f ./xapps/kpimon-go-xapp/deploy/ -n ricxapp
kubectl apply -f ./xapps/traffic-steering/deploy/ -n ricxapp
kubectl apply -f ./xapps/rc-xapp/deploy/ -n ricxapp

# 5. Deploy E2 Simulator
bash ./scripts/deployment/deploy-e2-simulator.sh
```

**Access Grafana:**
```bash
# Get admin password
kubectl get secret --namespace ricplt oran-grafana -o jsonpath="{.data.admin-password}" | base64 --decode && echo

# Setup port-forward
kubectl port-forward -n ricplt svc/oran-grafana 3000:80

# Open http://localhost:3000 (username: admin, password: from above command)
```

**Verification:**
```bash
kubectl get pods -n ricxapp  # All pods should be Running (1/1)
kubectl get pods -n ricplt   # Prometheus and Grafana should be Running
```

**Detailed guide:** [WORKING_DEPLOYMENT_GUIDE.md](docs/deployment/WORKING_DEPLOYMENT_GUIDE.md) | **Troubleshooting:** [TROUBLESHOOTING.md](docs/deployment/TROUBLESHOOTING.md)

---

## Architecture

```
┌─────────────────┐
│  E2 Simulator   │ ← Generates realistic E2 traffic
└────────┬────────┘
         │ HTTP POST /e2/indication
         ├──────────────────┬──────────────┬─────────────┬─────────────┐
         ↓                  ↓              ↓             ↓             ↓
     KPIMON          Traffic Steering   QoE Predictor   RAN Control   Fed Learning
     :8081/:8080     :8081/:8080        :8090/:8080     :8100/:8080   :8110/:8080
         │                  │                │             │             │
         └──────────────────┴────────────────┴─────────────┴─────────────┘
                            │
                     Prometheus :9090  ← Scrapes metrics every 30s
                            │
                      Grafana :3000    ← Visualizes metrics
```

**Port Convention:**
- `8081/8090/8100/8110`: xApp business logic (E2 indications)
- `8080`: Prometheus metrics endpoint (all xApps)

---

## xApps

| xApp | Version | Purpose | Key Features |
|------|---------|---------|--------------|
| **KPIMON** | v1.0.1 | KPI monitoring | E2SM-KPM v3.0, 20+ KPI types, real-time streaming |
| **Traffic Steering** | v1.0.2 | Handover decisions | E2SM-KPM+RC, A1 policy, SDL integration |
| **QoE Predictor** | v1.0.1 | QoE prediction | ML-based, TensorFlow 2.15, real-time API |
| **RAN Control** | v1.0.1 | RAN optimization | E2SM-RC v2.0, 5 optimization algorithms |
| **Federated Learning** | v1.0.0 | Distributed ML | TensorFlow+PyTorch, privacy-preserving |

**Common Endpoints** (all xApps on port 8080):
- `GET /ric/v1/health/alive` - Liveness probe
- `GET /ric/v1/health/ready` - Readiness probe
- `GET /ric/v1/metrics` - Prometheus metrics

**Documentation:** Each xApp has detailed README in `xapps/<name>/`

---

## Monitoring & Observability

### Prometheus Metrics

**Auto-discovery via annotations:**
```yaml
prometheus.io/scrape: "true"
prometheus.io/port: "8080"
prometheus.io/path: "/ric/v1/metrics"
```

**Example Metrics:**
```promql
kpimon_messages_received_total          # Total messages received
kpimon_messages_processed_total         # Total messages processed
kpimon_processing_time_seconds          # Processing latency histogram
kpimon_active_subscriptions             # Active E2 subscriptions
kpimon_kpi_value{type="prb_usage_dl"}   # PRB utilization
```

### Alert Rules (8 Categories)

| Category | Alerts | Examples |
|----------|--------|----------|
| xApp Availability | Pod down, restart loops | `KPIMONDown`, `HighRestartRate` |
| Message Processing | Stalled, high latency | `MessageProcessingStalled` |
| Resource Usage | CPU/memory limits | `HighCPUUsage`, `HighMemoryUsage` |
| E2 Interface | Connection failures | `E2ConnectionLost` |
| Business Logic | PRB, signal quality | `HighPRBUsage`, `LowRSRP` |
| Prometheus | Scrape failures | `PrometheusScrapeFailure` |
| Network | Service unreachable | `ServiceDown` |
| Data Quality | Missing/stale metrics | `MetricsMissing` |

**Configuration:** [monitoring/prometheus/alerts/xapp-alerts.yml](monitoring/prometheus/alerts/xapp-alerts.yml)

### Grafana Dashboards

**Access:** http://localhost:3000 (after port-forward)

**Dashboards:**
- xApp Performance (message rates, latency, errors)
- E2 Interface Metrics (indication counts, processing time)
- Resource Utilization (CPU, memory, network)
- Alert Overview (active/historical alerts)

**Automated Testing:** 6 Playwright E2E tests verify dashboard functionality

---

## Testing

### E2E Testing (Playwright)

```bash
npm install              # First time only
npm run test:grafana     # Run 6 dashboard tests
```

**Coverage:** Dashboard accessibility, metrics presence, panel rendering, query execution, alert verification.

### E2 Simulator

**Continuous Traffic Generation:**
```bash
kubectl logs -n ricxapp -l app=e2-simulator -f
# Output: Simulation Iteration 120 → Successfully sent to kpimon (200) → ...
```

**Manual Test:**
```bash
kubectl exec -n ricxapp e2-simulator-xxx -- \
  curl -X POST http://kpimon.ricxapp.svc.cluster.local:8081/e2/indication \
  -H "Content-Type: application/json" \
  -d '{"cell_id": 1234567, "prb_usage_dl": 45.5}'
```

**Performance Targets:**
- E2 indication processing: < 10ms
- Control command latency: < 100ms
- xApp startup: < 30s

---

## Documentation

| Document | Description | Audience |
|----------|-------------|----------|
| [QUICKSTART.md](docs/deployment/QUICKSTART.md) | 10-minute deployment | Experienced users |
| [xapp-prometheus-metrics-integration.md](docs/deployment/xapp-prometheus-metrics-integration.md) | Complete walkthrough (15k words) | First-time deployers |
| [TROUBLESHOOTING.md](docs/deployment/TROUBLESHOOTING.md) | Common issues & solutions | All users |
| xApps README files | Implementation details | Developers |

**RIC Platform Configuration:** [RIC-DEP-CUSTOMIZATION.md](docs/RIC-DEP-CUSTOMIZATION.md)

---

## What's New in v2.0.0

### Major Changes

**E2 Node Extraction (BREAKING)**
- E2 Simulator moved to [oran-e2-node](https://github.com/thc1006/oran-e2-node) repository
- Now a git submodule: `git submodule update --init --recursive`
- Benefits: Independent development, cleaner structure, community contributions

**Complete Metrics Integration**
- All 5 xApps now expose Prometheus metrics on port 8080
- 8 comprehensive alert rule categories
- Grafana dashboards with automated E2E testing

**Repository Cleanup**
- Removed 10,000+ lines of archived documentation
- Updated `.gitignore` for development artifacts
- Significantly reduced repository size

### Bug Fixes

1. Traffic Steering SDL error handling
2. Unified port configuration (Service/Deployment/Prometheus)
3. E2 Simulator port fixes (QoE: 8090, RC: 8100)
4. KPIMON metrics increment logic
5. Playwright headless mode update

**Full changelog:** [Releases](https://github.com/thc1006/oran-ric-platform/releases)

---

## Project Structure

```
oran-ric-platform/
├── xapps/                    # 5 production xApps
│   ├── kpimon-go-xapp/       # v1.0.1
│   ├── traffic-steering/     # v1.0.2
│   ├── qoe-predictor/        # v1.0.1
│   ├── ran-control/          # v1.0.1
│   └── federated-learning/   # v1.0.0
├── monitoring/               # Prometheus + Grafana configs
│   ├── prometheus/
│   │   ├── alerts/xapp-alerts.yml
│   │   └── prometheus.yml
│   └── grafana/dashboards/
├── simulator/e2-simulator/   # Git submodule → oran-e2-node
├── scripts/
│   ├── redeploy-xapps-with-metrics.sh
│   └── deployment/deploy-e2-simulator.sh
├── tests/grafana/            # Playwright E2E tests
├── docs/deployment/          # Comprehensive guides
└── ric-dep/                  # RIC Platform Helm charts
```

---

## Technical Stack

**Core:** O-RAN SC J Release, Kubernetes 1.28+ (k3s), Helm 3.x, Docker

**Languages:** Python 3.11+ (xApps), Go 1.19+ (RMR), JavaScript ES6+ (testing)

**Key Libraries:**
- ricxappframe 3.2.2 (Python xApp framework)
- RMR 4.9.4 (RIC Message Router)
- ricsdl 3.0.2 (Shared Data Layer)
- Prometheus Client, Playwright

**Infrastructure:** localhost:5000 registry, Redis (SDL), Prometheus, Grafana

---

## Contributing

1. Fork repository
2. Create feature branch: `git checkout -b feature/name`
3. Commit: `git commit -m 'Add feature'`
4. Push: `git push origin feature/name`
5. Open Pull Request

**Standards:** Python PEP 8, comprehensive docstrings, tests for new features, documentation updates.

---

## Credits

**Author:** 蔡秀吉 (thc1006)

**Related Projects:**
- [oran-e2-node](https://github.com/thc1006/oran-e2-node) - E2 Node Simulator

**Built With:**
- [O-RAN Software Community](https://o-ran-sc.org/) - J Release
- [Kubernetes](https://kubernetes.io/), [Prometheus](https://prometheus.io/), [Grafana](https://grafana.com/), [Playwright](https://playwright.dev/)

---

## License

Apache License 2.0 - See [LICENSE](LICENSE)

---

## Links

- **Repository:** https://github.com/thc1006/oran-ric-platform
- **E2 Simulator:** https://github.com/thc1006/oran-e2-node
- **Issues:** https://github.com/thc1006/oran-ric-platform/issues
- **Releases:** https://github.com/thc1006/oran-ric-platform/releases
- **O-RAN SC:** https://wiki.o-ran-sc.org/

---

<div align="center">

**Made by 蔡秀吉 (thc1006)**

*Production-ready O-RAN deployment with comprehensive observability*

[Back to Top](#o-ran-near-rt-ric-platform-with-production-xapps)

</div>
