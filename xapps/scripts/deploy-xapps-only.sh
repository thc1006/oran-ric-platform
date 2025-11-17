#!/bin/bash
# Deploy xApps Only (不包含 RIC Platform)
# 作者: 蔡秀吉 (thc1006)
# Version: 1.0.0
#
# 注意: 此腳本僅部署 xApps，不包含 RIC Platform 基礎設施
# 如需完整部署，請使用: scripts/deployment/deploy-all.sh

set -e

# Configuration
APPMGR_URL="${APPMGR_URL:-http://service-ricplt-appmgr-http.ricplt:8080}"
NAMESPACE="${NAMESPACE:-ricxapp}"
REPLICAS="${REPLICAS:-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}O-RAN xApp Deployment Script${NC}"
echo "AppMgr URL: $APPMGR_URL"
echo "Namespace: $NAMESPACE"
echo "Replicas: $REPLICAS"
echo ""

# Function to deploy xApp via AppMgr
deploy_xapp_appmgr() {
    local xapp_name=$1
    
    echo -e "${YELLOW}Deploying $xapp_name via AppMgr...${NC}"
    
    # Deploy xApp
    response=$(curl -X POST \
        ${APPMGR_URL}/ric/v1/xapps/${xapp_name}/instances \
        -H "Content-Type: application/json" \
        -d "{\"instances\": $REPLICAS}" \
        2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $xapp_name deployment initiated${NC}"
        echo "Response: $response"
    else
        echo -e "${RED}✗ Failed to deploy $xapp_name${NC}"
        return 1
    fi
    echo ""
}

# Function to deploy xApp via kubectl
deploy_xapp_kubectl() {
    local xapp_name=$1
    local port=$2
    
    echo -e "${YELLOW}Deploying $xapp_name via kubectl...${NC}"
    
    # Create deployment manifest
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${xapp_name}
  namespace: ${NAMESPACE}
  labels:
    app: ${xapp_name}
    version: "1.0.0"
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      app: ${xapp_name}
  template:
    metadata:
      labels:
        app: ${xapp_name}
        version: "1.0.0"
    spec:
      serviceAccountName: xapp-serviceaccount
      containers:
      - name: ${xapp_name}
        image: localhost:5000/xapp-${xapp_name}:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: rmr-data
          containerPort: ${port}
          protocol: TCP
        - name: rmr-route
          containerPort: $((port+1))
          protocol: TCP
        - name: http-api
          containerPort: $((port+510))
          protocol: TCP
        env:
        - name: RMR_SEED_RT
          value: "/app/config/rmr-routes.txt"
        - name: RMR_SRC_ID
          value: "${xapp_name}"
        - name: PYTHONUNBUFFERED
          value: "1"
        volumeMounts:
        - name: config
          mountPath: /app/config
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health/alive
            port: $((port+510))
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health/ready
            port: $((port+510))
          initialDelaySeconds: 15
          periodSeconds: 15
      volumes:
      - name: config
        configMap:
          name: ${xapp_name}-config
---
apiVersion: v1
kind: Service
metadata:
  name: ${xapp_name}-service
  namespace: ${NAMESPACE}
  labels:
    app: ${xapp_name}
spec:
  selector:
    app: ${xapp_name}
  ports:
  - name: rmr-data
    port: ${port}
    targetPort: ${port}
    protocol: TCP
  - name: rmr-route
    port: $((port+1))
    targetPort: $((port+1))
    protocol: TCP
  - name: http-api
    port: $((port+510))
    targetPort: $((port+510))
    protocol: TCP
  type: ClusterIP
EOF
    
    echo -e "${GREEN}✓ $xapp_name deployed${NC}\n"
}

# Function to check deployment status
check_deployment_status() {
    echo -e "${YELLOW}Checking deployment status...${NC}"
    
    # Wait for deployments to be ready
    for xapp in kpimon qoe-predictor ran-control federated-learning; do
        echo -n "Waiting for $xapp to be ready..."
        
        # Wait up to 60 seconds
        for i in {1..60}; do
            ready=$(kubectl get deployment ${xapp} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            if [ "$ready" == "$REPLICAS" ]; then
                echo -e " ${GREEN}Ready!${NC}"
                break
            fi
            echo -n "."
            sleep 1
        done
        
        if [ "$ready" != "$REPLICAS" ]; then
            echo -e " ${RED}Timeout!${NC}"
        fi
    done
    echo ""
}

# Function to display deployment info
display_deployment_info() {
    echo -e "${BLUE}Deployment Information:${NC}"
    echo "========================"
    
    # Get pod status
    echo -e "\n${YELLOW}Pod Status:${NC}"
    kubectl get pods -n ${NAMESPACE} -l 'app in (kpimon,qoe-predictor,ran-control,federated-learning)'
    
    # Get service info
    echo -e "\n${YELLOW}Services:${NC}"
    kubectl get services -n ${NAMESPACE} -l 'app in (kpimon,qoe-predictor,ran-control,federated-learning)'
    
    # Get deployment info
    echo -e "\n${YELLOW}Deployments:${NC}"
    kubectl get deployments -n ${NAMESPACE} -l 'app in (kpimon,qoe-predictor,ran-control,federated-learning)'
    
    echo ""
}

# Function to create network policies
create_network_policies() {
    echo -e "${YELLOW}Creating network policies...${NC}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: xapp-network-policy
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ricplt
    - namespaceSelector:
        matchLabels:
          name: ${NAMESPACE}
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: ricplt
    - namespaceSelector:
        matchLabels:
          name: ${NAMESPACE}
  - to:
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 6379  # Redis
    - protocol: TCP
      port: 8086  # InfluxDB
EOF
    
    echo -e "${GREEN}✓ Network policies created${NC}\n"
}

# Main function
main() {
    echo "Starting xApp deployment..."
    echo "============================"
    echo ""
    
    # Check if namespace exists
    kubectl get namespace ${NAMESPACE} > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Namespace ${NAMESPACE} does not exist. Run onboard-xapps.sh first.${NC}"
        exit 1
    fi
    
    # Create network policies
    create_network_policies
    
    # Deploy each xApp
    deploy_xapp_kubectl "kpimon" 4560
    deploy_xapp_kubectl "qoe-predictor" 4570
    deploy_xapp_kubectl "ran-control" 4580
    deploy_xapp_kubectl "federated-learning" 4590
    
    # Check deployment status
    check_deployment_status
    
    # Display deployment info
    display_deployment_info
    
    echo "============================"
    echo -e "${GREEN}Deployment completed!${NC}"
    echo ""
    echo "Useful commands:"
    echo "- Check logs: kubectl logs -n ${NAMESPACE} <pod-name>"
    echo "- Port forward: kubectl port-forward -n ${NAMESPACE} <pod-name> 8080:8080"
    echo "- Exec into pod: kubectl exec -it -n ${NAMESPACE} <pod-name> -- /bin/bash"
    echo "- Scale deployment: kubectl scale deployment <xapp-name> -n ${NAMESPACE} --replicas=2"
    echo ""
    echo "xApp REST API endpoints (use port-forward to access):"
    echo "- KPIMON: http://localhost:8080"
    echo "- QoE Predictor: http://localhost:8090"
    echo "- RAN Control: http://localhost:8100"
    echo "- Federated Learning: http://localhost:8110"
}

# Run main function
main
