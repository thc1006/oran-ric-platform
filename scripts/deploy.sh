#!/bin/bash

# O-RAN RIC Platform Deployment Script
# 作者：蔡秀吉（thc1006）

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLUSTER_TYPE="k3s"
ENVIRONMENT="local"
NAMESPACE_PLATFORM="ricplt"
NAMESPACE_XAPP="ricxapp"
K3S_VERSION="v1.28.5+k3s1"

# Functions
print_header() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===============================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check system resources
    CPUS=$(nproc)
    MEM=$(free -g | awk '/^Mem:/{print $2}')
    
    if [ $CPUS -lt 4 ]; then
        print_warning "CPU cores: $CPUS (recommended: 8+)"
    else
        print_success "CPU cores: $CPUS"
    fi
    
    if [ $MEM -lt 8 ]; then
        print_warning "Memory: ${MEM}GB (recommended: 16GB+)"
    else
        print_success "Memory: ${MEM}GB"
    fi
    
    # Check required tools
    TOOLS=("docker" "kubectl" "helm" "git" "jq")
    for tool in "${TOOLS[@]}"; do
        if command -v $tool &> /dev/null; then
            print_success "$tool is installed"
        else
            print_error "$tool is not installed"
            exit 1
        fi
    done
}

install_k3s() {
    print_header "Installing k3s Cluster"
    
    if command -v k3s &> /dev/null; then
        print_success "k3s is already installed"
        return
    fi
    
    print_warning "Installing k3s ${K3S_VERSION}..."
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION sh -s - server \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --disable servicelb \
        --kube-apiserver-arg=max-requests-inflight=400
    
    # Wait for k3s to be ready
    sleep 10
    
    # Export kubeconfig
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    
    # Wait for nodes to be ready
    kubectl wait --for=condition=ready node --all --timeout=60s
    print_success "k3s cluster installed and ready"
}

install_cilium() {
    print_header "Installing Cilium CNI"
    
    if kubectl get namespace kube-system -o json | jq '.metadata.labels."cilium.io/version"' | grep -q "1.14"; then
        print_success "Cilium is already installed"
        return
    fi
    
    # Install Cilium CLI
    if ! command -v cilium &> /dev/null; then
        CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/master/stable.txt)
        curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
        sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
        rm cilium-linux-amd64.tar.gz
    fi
    
    # Install Cilium
    cilium install --version 1.14.5
    cilium status --wait
    print_success "Cilium CNI installed"
}

install_metallb() {
    print_header "Installing MetalLB Load Balancer"
    
    if kubectl get namespace metallb-system &> /dev/null; then
        print_success "MetalLB is already installed"
        return
    fi
    
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
    
    # Wait for MetalLB to be ready
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb \
        --timeout=90s
    
    # Configure IP address pool
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - 172.20.0.100-172.20.0.200
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
EOF
    
    print_success "MetalLB installed and configured"
}

install_cert_manager() {
    print_header "Installing cert-manager"
    
    if kubectl get namespace cert-manager &> /dev/null; then
        print_success "cert-manager is already installed"
        return
    fi
    
    # Install cert-manager
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
    
    # Wait for cert-manager to be ready
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=webhook \
        --timeout=90s
    
    print_success "cert-manager installed"
}

deploy_ric_platform() {
    print_header "Deploying O-RAN RIC Platform"
    
    # Create namespaces
    kubectl create namespace $NAMESPACE_PLATFORM --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace $NAMESPACE_XAPP --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespaces for Linkerd injection
    kubectl label namespace $NAMESPACE_PLATFORM linkerd.io/inject=enabled --overwrite
    kubectl label namespace $NAMESPACE_XAPP linkerd.io/inject=enabled --overwrite
    
    # Add O-RAN SC Helm repository
    helm repo add ric https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep || true
    helm repo update
    
    # Deploy RIC Platform
    print_warning "Deploying RIC Platform components..."
    helm upgrade --install ric-platform ric/ric-platform \
        --namespace $NAMESPACE_PLATFORM \
        --values $PROJECT_ROOT/platform/values/local.yaml \
        --timeout 10m \
        --wait
    
    # Wait for all pods to be ready
    kubectl wait --namespace $NAMESPACE_PLATFORM \
        --for=condition=ready pod \
        --all \
        --timeout=300s
    
    print_success "RIC Platform deployed successfully"
}

deploy_observability() {
    print_header "Deploying Observability Stack"
    
    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Install kube-prometheus-stack
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set grafana.adminPassword=admin \
        --wait
    
    # Install Jaeger
    kubectl create namespace tracing --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n tracing -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.53.0/jaeger-operator.yaml
    
    print_success "Observability stack deployed"
}

setup_local_registry() {
    print_header "Setting up Local Docker Registry"
    
    if docker ps | grep -q registry:2; then
        print_success "Local registry is already running"
        return
    fi
    
    docker run -d -p 5000:5000 --restart=always --name registry registry:2
    
    # Configure k3s to use insecure registry
    cat <<EOF | sudo tee /etc/rancher/k3s/registries.yaml
mirrors:
  localhost:5000:
    endpoint:
      - "http://localhost:5000"
EOF
    
    sudo systemctl restart k3s
    print_success "Local Docker registry configured"
}

deploy_sample_xapp() {
    print_header "Deploying Sample xApp (Hello World)"
    
    # Build and push sample xApp
    cd $PROJECT_ROOT/xapps/hello-world
    docker build -t localhost:5000/xapp-hello:latest .
    docker push localhost:5000/xapp-hello:latest
    
    # Deploy using Helm
    helm upgrade --install xapp-hello ./helm \
        --namespace $NAMESPACE_XAPP \
        --wait
    
    print_success "Sample xApp deployed"
}

print_status() {
    print_header "Deployment Status"
    
    echo -e "\n${BLUE}RIC Platform Components:${NC}"
    kubectl get pods -n $NAMESPACE_PLATFORM
    
    echo -e "\n${BLUE}xApps:${NC}"
    kubectl get pods -n $NAMESPACE_XAPP
    
    echo -e "\n${BLUE}Services:${NC}"
    kubectl get svc -n $NAMESPACE_PLATFORM
    
    echo -e "\n${BLUE}Access Information:${NC}"
    echo "Grafana: http://localhost:3000 (admin/admin)"
    echo "Prometheus: http://localhost:9090"
    echo "Jaeger: http://localhost:16686"
    
    print_success "Deployment completed successfully!"
}

cleanup() {
    print_header "Cleaning up deployment"
    
    helm uninstall ric-platform -n $NAMESPACE_PLATFORM || true
    kubectl delete namespace $NAMESPACE_PLATFORM --wait || true
    kubectl delete namespace $NAMESPACE_XAPP --wait || true
    kubectl delete namespace monitoring --wait || true
    kubectl delete namespace tracing --wait || true
    
    print_success "Cleanup completed"
}

# Main execution
main() {
    case "${1:-}" in
        --cleanup)
            cleanup
            ;;
        --status)
            print_status
            ;;
        *)
            check_prerequisites
            install_k3s
            install_cilium
            install_metallb
            install_cert_manager
            setup_local_registry
            deploy_ric_platform
            deploy_observability
            deploy_sample_xapp
            print_status
            ;;
    esac
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --cluster)
            CLUSTER_TYPE="$2"
            shift 2
            ;;
        --cleanup)
            main --cleanup
            exit 0
            ;;
        --status)
            main --status
            exit 0
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --env ENV        Environment (local|staging|production)"
            echo "  --cluster TYPE   Cluster type (k3s|minikube|kind)"
            echo "  --cleanup        Remove all deployments"
            echo "  --status         Show deployment status"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main
