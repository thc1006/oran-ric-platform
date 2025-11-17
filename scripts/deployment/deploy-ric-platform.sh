#!/bin/bash
# Deploy O-RAN Near-RT RIC Platform (J Release) - Complete Platform
#
# Status: EXPERIMENTAL - Not tested with current deployment
# Use deploy-all.sh for standard lightweight deployment
#
# This script deploys the full RIC Platform including:
# - AppMgr, E2Mgr, E2Term, SubMgr, A1 Mediator
# - Redis (Shared Data Layer)
# - RMR routing configuration
# - Network policies
#
# Author: 蔡秀吉 (thc1006)

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
RIC_VERSION="j-release"
HELM_TIMEOUT="600s"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# 載入驗證函數庫
source "${PROJECT_ROOT}/scripts/lib/validation.sh"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # KUBECONFIG 標準化設定
    log_info "設定 KUBECONFIG..."
    if ! setup_kubeconfig; then
        log_error "KUBECONFIG not configured. Please run setup-k3s.sh first."
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install helm first."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster."
        log_error "KUBECONFIG: $KUBECONFIG"
        log_error "Please verify your Kubernetes setup."
        exit 1
    fi

    log_info "Prerequisites check passed"
    log_info "Using KUBECONFIG: $KUBECONFIG"
}

# Add O-RAN SC Helm repository
add_helm_repos() {
    log_info "Adding O-RAN SC Helm repositories..."
    
    # Add official O-RAN SC repo
    helm repo add oran-sc https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep/helm-charts
    
    # Add auxiliary repos
    helm repo add stable https://charts.helm.sh/stable
    helm repo add bitnami https://charts.bitnami.com/bitnami
    
    helm repo update
    
    log_info "Helm repositories added"
}

# Deploy Redis for SDL
deploy_redis() {
    log_info "Deploying Redis for SDL..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: ricplt
data:
  redis.conf: |
    maxmemory 2gb
    maxmemory-policy allkeys-lru
    save 900 1
    save 300 10
    save 60 10000
    appendonly yes
    appendfsync everysec
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: ricplt
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        volumeMounts:
        - name: redis-storage
          mountPath: /data
        - name: redis-config
          mountPath: /usr/local/etc/redis
        command:
        - redis-server
        - /usr/local/etc/redis/redis.conf
        readinessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 30
          periodSeconds: 30
      volumes:
      - name: redis-storage
        persistentVolumeClaim:
          claimName: redis-pvc
      - name: redis-config
        configMap:
          name: redis-config
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ricplt
spec:
  selector:
    app: redis
  ports:
  - protocol: TCP
    port: 6379
    targetPort: 6379
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-pvc
  namespace: ricplt
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: local-path
EOF
    
    kubectl wait --namespace ricplt \
        --for=condition=ready pod \
        --selector=app=redis \
        --timeout=120s
    
    log_info "Redis deployed successfully"
}

# Deploy RIC Platform components
deploy_ric_platform() {
    log_info "Deploying RIC Platform components..."
    
    # Create values file for local deployment
    cat > /tmp/ric-platform-values.yaml <<EOF
global:
  namespace:
    platform: ricplt
    xapp: ricxapp
  persistence:
    enabled: true
    storageClassName: local-path
  registry: localhost:5000
  imagePullPolicy: Always

redis:
  enabled: false  # We deployed Redis separately
  
appmgr:
  enabled: true
  image:
    repository: nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-appmgr
    tag: 0.5.4
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "500m"
  service:
    http:
      type: LoadBalancer
      port: 8080
    rmr:
      data:
        port: 4560
      route:
        port: 4561

e2mgr:
  enabled: true
  image:
    repository: nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-e2mgr
    tag: 5.4.19
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "500m"
  env:
    RIC_ID: "RIC001"
  service:
    http:
      type: LoadBalancer
      port: 3800
    rmr:
      data:
        port: 3801
      route:
        port: 4561

e2term:
  enabled: true
  image:
    repository: nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-e2
    tag: 5.5.0
  resources:
    requests:
      memory: "512Mi"
      cpu: "400m"
    limits:
      memory: "1Gi"
      cpu: "1000m"
  replicas: 1
  service:
    sctp:
      type: NodePort
      port: 36422
      nodePort: 36422
    rmr:
      data:
        port: 38000
      route:
        port: 4561

submgr:
  enabled: true
  image:
    repository: nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-submgr
    tag: 0.9.0
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "500m"
  service:
    rmr:
      data:
        port: 4560
      route:
        port: 4561
    http:
      port: 8088

a1mediator:
  enabled: true
  image:
    repository: nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-a1
    tag: 2.6.0
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "500m"
  service:
    rmr:
      data:
        port: 4562
      route:
        port: 4563
    http:
      type: LoadBalancer
      port: 10000

rtmgr:
  enabled: false  # Disabled for local dev - using static routing

vespamgr:
  enabled: false  # Optional component

jaegeradapter:
  enabled: false  # Will deploy separately with observability stack

influxdb:
  enabled: false  # Will use separate deployment

prometheus:
  enabled: false  # Will deploy separately
EOF
    
    # Deploy RIC Platform Helm chart
    helm upgrade --install ric-platform ${PROJECT_ROOT}/platform/helm/charts/ric-platform \
        --namespace ricplt \
        --values /tmp/ric-platform-values.yaml \
        --timeout ${HELM_TIMEOUT} \
        --wait \
        --debug
    
    log_info "RIC Platform deployment initiated"
}

# Create RMR route configuration
create_rmr_routes() {
    log_info "Creating RMR route configuration..."
    
    kubectl create configmap rmr-routes -n ricplt --from-file=${PROJECT_ROOT}/platform/config/rmr-routes.txt \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "RMR routes configured"
}

# Apply network policies
apply_network_policies() {
    log_info "Applying network policies..."
    
    kubectl apply -f ${PROJECT_ROOT}/infrastructure/k8s/network-policies/
    
    log_info "Network policies applied"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying RIC Platform deployment..."
    
    echo ""
    echo "=== RIC Platform Pods ==="
    kubectl get pods -n ricplt -o wide
    
    echo ""
    echo "=== RIC Platform Services ==="
    kubectl get svc -n ricplt
    
    echo ""
    echo "=== Checking Component Health ==="
    
    # Check AppMgr
    APPMGR_IP=$(kubectl get svc -n ricplt appmgr-http -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    if [[ "$APPMGR_IP" != "pending" ]]; then
        curl -s http://${APPMGR_IP}:8080/ric/v1/health/ready && echo " - AppMgr: Ready" || echo " - AppMgr: Not Ready"
    else
        echo " - AppMgr: LoadBalancer IP pending"
    fi
    
    # Check E2Mgr
    E2MGR_IP=$(kubectl get svc -n ricplt e2mgr-http -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    if [[ "$E2MGR_IP" != "pending" ]]; then
        curl -s http://${E2MGR_IP}:3800/v1/nodeb/states && echo " - E2Mgr: Ready" || echo " - E2Mgr: Not Ready"
    else
        echo " - E2Mgr: LoadBalancer IP pending"
    fi
    
    # Check A1 Mediator
    A1MED_IP=$(kubectl get svc -n ricplt a1mediator-http -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    if [[ "$A1MED_IP" != "pending" ]]; then
        curl -s http://${A1MED_IP}:10000/a1-p/healthcheck && echo " - A1 Mediator: Ready" || echo " - A1 Mediator: Not Ready"
    else
        echo " - A1 Mediator: LoadBalancer IP pending"
    fi
    
    echo ""
    log_info "Deployment verification completed"
}

# Print access information
print_access_info() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}RIC Platform deployed successfully!${NC}"
    echo "=========================================="
    echo ""
    echo "Access Information:"
    echo "-------------------"
    
    APPMGR_IP=$(kubectl get svc -n ricplt appmgr-http -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    E2MGR_IP=$(kubectl get svc -n ricplt e2mgr-http -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    A1MED_IP=$(kubectl get svc -n ricplt a1mediator-http -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    E2TERM_PORT=$(kubectl get svc -n ricplt e2term-sctp -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "36422")
    
    echo "AppMgr API: http://${APPMGR_IP}:8080"
    echo "E2Mgr API: http://${E2MGR_IP}:3800"
    echo "A1 Mediator API: http://${A1MED_IP}:10000"
    echo "E2 Term SCTP: <node-ip>:${E2TERM_PORT}"
    echo ""
    echo "Redis CLI: kubectl exec -it -n ricplt deployment/redis -- redis-cli"
    echo ""
    echo "Next steps:"
    echo "1. Deploy observability stack: ./deploy-observability.sh"
    echo "2. Deploy xApps: ./deploy-xapps.sh"
    echo "3. Connect E2 nodes to E2Term on port ${E2TERM_PORT}"
    echo ""
}

# Main execution
main() {
    log_info "Starting O-RAN RIC Platform deployment..."
    
    check_prerequisites
    add_helm_repos
    deploy_redis
    deploy_ric_platform
    create_rmr_routes
    apply_network_policies
    
    # Wait for deployments to be ready
    log_info "Waiting for all deployments to be ready..."
    kubectl wait --namespace ricplt \
        --for=condition=available deployment \
        --all \
        --timeout=300s || log_warn "Some deployments are not ready yet"
    
    verify_deployment
    print_access_info
}

# Execute main function
main
