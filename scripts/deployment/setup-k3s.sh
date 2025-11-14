#!/bin/bash
# Setup k3s for O-RAN RIC Platform Development
# Compatible with Ubuntu 20.04/22.04/24.04

set -e

echo "=== O-RAN RIC Platform - k3s Setup Script ==="
echo "Version: J Release (April 2025)"
echo "============================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration variables
K3S_VERSION="v1.28.5+k3s1"
CLUSTER_DOMAIN="cluster.local"
METALLB_VERSION="v0.13.12"
CILIUM_VERSION="1.14.5"
NGINX_VERSION="1.9.5"

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    # Check resources
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_MEM -lt 8 ]]; then
        log_warn "System has less than 8GB RAM. RIC platform may not run optimally."
    fi
    
    TOTAL_CORES=$(nproc)
    if [[ $TOTAL_CORES -lt 4 ]]; then
        log_warn "System has less than 4 CPU cores. Performance may be impacted."
    fi
    
    # Check if k3s already installed
    if command -v k3s &> /dev/null; then
        log_warn "k3s is already installed. Proceeding with configuration..."
    fi
}

# Install k3s
install_k3s() {
    log_info "Installing k3s ${K3S_VERSION}..."
    
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION sh -s - server \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --disable servicelb \
        --flannel-backend=none \
        --disable-network-policy \
        --cluster-domain=$CLUSTER_DOMAIN \
        --kube-apiserver-arg=max-requests-inflight=400 \
        --kube-apiserver-arg=max-mutating-requests-inflight=200
    
    # Wait for k3s to be ready
    log_info "Waiting for k3s to be ready..."
    sleep 10
    
    # Setup kubeconfig
    mkdir -p $HOME/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
    sudo chown $USER:$USER $HOME/.kube/config
    
    # Export KUBECONFIG
    export KUBECONFIG=$HOME/.kube/config
    echo "export KUBECONFIG=$HOME/.kube/config" >> $HOME/.bashrc
    
    # Wait for nodes to be ready (may timeout without CNI, continue anyway)
    kubectl wait --for=condition=ready node --all --timeout=300s || true

    log_info "k3s installation completed"
}

# Install Cilium CNI
install_cilium() {
    log_info "Installing Cilium CNI ${CILIUM_VERSION}..."
    
    # Install Cilium CLI
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/master/stable.txt)
    CLI_ARCH=amd64
    if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
    curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
    sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
    sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
    rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
    
    # Install Cilium
    cilium install --version ${CILIUM_VERSION} \
        --set operator.replicas=1 \
        --set ipam.mode=kubernetes \
        --set kubeProxyReplacement=partial \
        --set hostServices.enabled=false \
        --set externalIPs.enabled=true \
        --set nodePort.enabled=true \
        --set hostPort.enabled=true \
        --set bpf.masquerade=false \
        --set image.pullPolicy=IfNotPresent
    
    # Wait for Cilium to be ready
    cilium status --wait
    
    log_info "Cilium installation completed"
}

# Install MetalLB for LoadBalancer services
install_metallb() {
    log_info "Installing MetalLB ${METALLB_VERSION}..."
    
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml
    
    # Wait for MetalLB to be ready
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb \
        --timeout=300s
    
    # Configure MetalLB address pool
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.20.0.100-172.20.0.200
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF
    
    log_info "MetalLB installation completed"
}

# Install NGINX Ingress Controller
install_nginx_ingress() {
    log_info "Installing NGINX Ingress Controller ${NGINX_VERSION}..."
    
    # Add Helm repo
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    
    # Install NGINX Ingress
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --version ${NGINX_VERSION} \
        --set controller.service.type=LoadBalancer \
        --set controller.metrics.enabled=true \
        --set controller.podAnnotations."prometheus\.io/scrape"=true \
        --set controller.podAnnotations."prometheus\.io/port"="10254"
    
    # Wait for ingress controller to be ready
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
    
    log_info "NGINX Ingress installation completed"
}

# Setup local Docker registry
setup_local_registry() {
    log_info "Setting up local Docker registry..."
    
    # Check if registry already running
    if docker ps | grep -q registry:2; then
        log_warn "Local registry already running"
    else
        docker run -d \
            --restart=always \
            --name registry \
            -p 5000:5000 \
            -v /var/lib/registry:/var/lib/registry \
            registry:2
    fi
    
    # Configure k3s to use local registry
    cat <<EOF | sudo tee /etc/rancher/k3s/registries.yaml
mirrors:
  localhost:5000:
    endpoint:
      - "http://localhost:5000"
EOF
    
    # Restart k3s to apply registry config
    sudo systemctl restart k3s
    
    log_info "Local registry setup completed"
}

# Create namespaces for RIC
create_namespaces() {
    log_info "Creating RIC namespaces..."
    
    kubectl create namespace ricplt --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace ricxapp --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace ricobs --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespaces for Cilium
    kubectl label namespace ricplt name=ricplt --overwrite
    kubectl label namespace ricxapp name=ricxapp --overwrite
    kubectl label namespace ricobs name=ricobs --overwrite
    
    # Annotate for Linkerd injection (prepared for later)
    kubectl annotate namespace ricplt linkerd.io/inject=enabled --overwrite
    kubectl annotate namespace ricxapp linkerd.io/inject=enabled --overwrite
    
    log_info "Namespaces created"
}

# Setup persistent storage
setup_storage() {
    log_info "Setting up persistent storage..."
    
    # Install local-path-provisioner
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
    
    # Wait for provisioner to be ready
    kubectl wait --namespace local-path-storage \
        --for=condition=ready pod \
        --selector=app=local-path-provisioner \
        --timeout=300s
    
    # Set as default storage class
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    
    log_info "Storage setup completed"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    echo ""
    echo "=== Cluster Information ==="
    kubectl cluster-info
    
    echo ""
    echo "=== Nodes ==="
    kubectl get nodes -o wide
    
    echo ""
    echo "=== Storage Classes ==="
    kubectl get storageclass
    
    echo ""
    echo "=== Namespaces ==="
    kubectl get namespaces
    
    echo ""
    echo "=== Pods in kube-system ==="
    kubectl get pods -n kube-system
    
    echo ""
    echo "=== Pods in metallb-system ==="
    kubectl get pods -n metallb-system
    
    echo ""
    log_info "Installation verification completed"
}

# Main execution
main() {
    echo ""
    check_prerequisites
    
    echo ""
    install_k3s
    
    echo ""
    install_cilium
    
    echo ""
    install_metallb
    
    echo ""
    install_nginx_ingress
    
    echo ""
    setup_local_registry
    
    echo ""
    create_namespaces
    
    echo ""
    setup_storage
    
    echo ""
    verify_installation
    
    echo ""
    echo "=========================================="
    echo -e "${GREEN}k3s setup completed successfully!${NC}"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. Run: source ~/.bashrc"
    echo "2. Deploy RIC platform: ./deploy-ric-platform.sh"
    echo "3. Deploy xApps: ./deploy-xapps.sh"
    echo ""
    echo "Access cluster with: kubectl get nodes"
    echo ""
}

# Run main function
main
