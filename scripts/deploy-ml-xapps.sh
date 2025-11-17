#!/bin/bash
# Deploy ML xApps (QoE Predictor + Federated Learning) to Kubernetes
# Author: 蔡秀吉 (thc1006)
# Date: 2025-11-15

set -e  # Exit on error
set -u  # Exit on undefined variable

# 動態解析專案根目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 驗證專案根目錄
if [ ! -f "$PROJECT_ROOT/README.md" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m Cannot locate project root" >&2
    echo "Expected README.md at: $PROJECT_ROOT/README.md" >&2
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="ricxapp"
REGISTRY="localhost:5000"
QOE_IMAGE="${REGISTRY}/xapp-qoe-predictor:1.0.0"
FL_IMAGE="${REGISTRY}/xapp-federated-learning:1.0.0"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster."
        exit 1
    fi

    # Check namespace
    if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
        log_warning "Namespace ${NAMESPACE} not found. Creating..."
        kubectl create namespace ${NAMESPACE}
    fi

    log_success "Prerequisites check passed"
}

build_images() {
    log_info "Building Docker images..."

    # Build QoE Predictor
    log_info "Building QoE Predictor image..."
    if [ -f "${PROJECT_ROOT}/xapps/qoe-predictor/Dockerfile.optimized" ]; then
        docker build -f "${PROJECT_ROOT}/xapps/qoe-predictor/Dockerfile.optimized" -t ${QOE_IMAGE} "${PROJECT_ROOT}/xapps/qoe-predictor"
    else
        docker build -t ${QOE_IMAGE} "${PROJECT_ROOT}/xapps/qoe-predictor"
    fi
    docker push ${QOE_IMAGE}

    # Build Federated Learning
    log_info "Building Federated Learning image..."
    if [ -f "${PROJECT_ROOT}/xapps/federated-learning/Dockerfile.optimized" ]; then
        docker build -f "${PROJECT_ROOT}/xapps/federated-learning/Dockerfile.optimized" -t ${FL_IMAGE} "${PROJECT_ROOT}/xapps/federated-learning"
    else
        docker build -t ${FL_IMAGE} "${PROJECT_ROOT}/xapps/federated-learning"
    fi
    docker push ${FL_IMAGE}

    log_success "Docker images built and pushed"
}

deploy_qoe_predictor() {
    log_info "Deploying QoE Predictor xApp..."

    local DEPLOY_DIR="${PROJECT_ROOT}/xapps/qoe-predictor/deploy"

    # Apply configurations
    kubectl apply -f "${DEPLOY_DIR}/serviceaccount.yaml"
    kubectl apply -f "${DEPLOY_DIR}/configmap.yaml"
    kubectl apply -f "${DEPLOY_DIR}/service.yaml"
    kubectl apply -f "${DEPLOY_DIR}/deployment.yaml"

    log_success "QoE Predictor deployed"
}

deploy_federated_learning() {
    log_info "Deploying Federated Learning xApp..."

    local DEPLOY_DIR="${PROJECT_ROOT}/xapps/federated-learning/deploy"

    # Apply configurations
    kubectl apply -f "${DEPLOY_DIR}/pvc.yaml"
    kubectl apply -f "${DEPLOY_DIR}/serviceaccount.yaml"
    kubectl apply -f "${DEPLOY_DIR}/configmap.yaml"
    kubectl apply -f "${DEPLOY_DIR}/service.yaml"
    kubectl apply -f "${DEPLOY_DIR}/deployment.yaml"

    log_success "Federated Learning deployed"
}

wait_for_deployment() {
    local deployment=$1
    log_info "Waiting for ${deployment} to be ready..."

    kubectl wait --for=condition=available --timeout=300s \
        deployment/${deployment} -n ${NAMESPACE} || {
        log_error "${deployment} failed to become ready"
        return 1
    }

    log_success "${deployment} is ready"
}

verify_deployment() {
    log_info "Verifying deployments..."

    echo ""
    echo "=== Pods Status ==="
    kubectl get pods -n ${NAMESPACE} -l app=qoe-predictor
    kubectl get pods -n ${NAMESPACE} -l app=federated-learning

    echo ""
    echo "=== Services ==="
    kubectl get svc -n ${NAMESPACE} -l xapp

    echo ""
    echo "=== Health Checks ==="

    # Check QoE Predictor health
    local qoe_pod=$(kubectl get pod -n ${NAMESPACE} -l app=qoe-predictor -o jsonpath='{.items[0].metadata.name}')
    if [ -n "${qoe_pod}" ]; then
        log_info "Checking QoE Predictor health..."
        kubectl exec -n ${NAMESPACE} ${qoe_pod} -- curl -s http://localhost:8090/health/alive || log_warning "QoE Predictor health check failed"
    fi

    # Check FL health
    local fl_pod=$(kubectl get pod -n ${NAMESPACE} -l app=federated-learning -o jsonpath='{.items[0].metadata.name}')
    if [ -n "${fl_pod}" ]; then
        log_info "Checking Federated Learning health..."
        kubectl exec -n ${NAMESPACE} ${fl_pod} -- curl -s http://localhost:8110/health/alive || log_warning "Federated Learning health check failed"
    fi
}

show_logs() {
    log_info "Showing recent logs..."

    echo ""
    echo "=== QoE Predictor Logs ==="
    kubectl logs -n ${NAMESPACE} -l app=qoe-predictor --tail=20 || true

    echo ""
    echo "=== Federated Learning Logs ==="
    kubectl logs -n ${NAMESPACE} -l app=federated-learning --tail=20 || true
}

cleanup() {
    log_warning "Cleaning up existing deployments..."

    kubectl delete deployment qoe-predictor -n ${NAMESPACE} --ignore-not-found=true
    kubectl delete deployment federated-learning -n ${NAMESPACE} --ignore-not-found=true
    kubectl delete svc qoe-predictor -n ${NAMESPACE} --ignore-not-found=true
    kubectl delete svc federated-learning -n ${NAMESPACE} --ignore-not-found=true

    log_info "Cleanup completed"
}

# Main execution
main() {
    local action=${1:-"deploy"}

    echo ""
    log_info "================================================"
    log_info "ML xApps Deployment Script"
    log_info "Action: ${action}"
    log_info "================================================"
    echo ""

    case ${action} in
        deploy)
            check_prerequisites
            build_images
            deploy_qoe_predictor
            deploy_federated_learning

            # Wait for deployments
            wait_for_deployment "qoe-predictor"
            wait_for_deployment "federated-learning"

            verify_deployment
            show_logs

            echo ""
            log_success "================================================"
            log_success "ML xApps deployment completed successfully!"
            log_success "================================================"
            ;;

        build)
            build_images
            ;;

        cleanup)
            cleanup
            ;;

        verify)
            verify_deployment
            ;;

        logs)
            show_logs
            ;;

        *)
            echo "Usage: $0 {deploy|build|cleanup|verify|logs}"
            echo ""
            echo "Commands:"
            echo "  deploy   - Build images and deploy xApps (default)"
            echo "  build    - Build and push Docker images only"
            echo "  cleanup  - Remove existing deployments"
            echo "  verify   - Verify deployment status"
            echo "  logs     - Show recent logs"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
