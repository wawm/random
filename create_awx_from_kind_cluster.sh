#!/bin/bash
#Prereq : Kind, kubectl, docker
set -e
CLUSTER_NAME="awx-cluster"
AWX_NAMESPACE="awx"
AWX_INSTANCE_NAME="awx-demo"

usage() {
    echo "Usage: $0 [install|uninstall|reinstall|status|destroy]"
    echo ""
    echo "Commands:"
    echo "  install     - Install AWX on Kind cluster"
    echo "  uninstall   - Uninstall AWX from cluster (keeps cluster)"
    echo "  reinstall   - Uninstall and reinstall AWX"
    echo "  destroy     - Delete entire Kind cluster"
    echo "  status      - Check AWX installation status"
    echo ""
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 uninstall"
    echo "  $0 status"
    exit 1
}

check_prerequisites() {
    command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed. Aborting." >&2; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting." >&2; exit 1; }
    command -v kind >/dev/null 2>&1 || { echo "Kind is required but not installed. Aborting." >&2; exit 1; }
}

check_status() {
    echo "==================================="
    echo "AWX Status Check"
    echo "==================================="
    echo ""
    
    if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        echo "Kind cluster '${CLUSTER_NAME}' does not exist"
        echo ""
        echo "Run '$0 install' to create it"
        exit 0
    fi
    
    echo "Kind cluster '${CLUSTER_NAME}' exists"
    echo ""
    
    if ! kubectl get namespace ${AWX_NAMESPACE} >/dev/null 2>&1; then
        echo "AWX namespace '${AWX_NAMESPACE}' does not exist"
        echo ""
        echo "Run '$0 install' to create AWX"
        exit 0
    fi
    
    echo "✓ AWX namespace exists"
    echo ""
    
    echo "AWX Operator Status:"
    kubectl get deployment awx-operator-controller-manager -n ${AWX_NAMESPACE} 2>/dev/null || echo "  Not installed"
    echo ""

    echo "AWX Instance Status:"
    kubectl get awx ${AWX_INSTANCE_NAME} -n ${AWX_NAMESPACE} 2>/dev/null || echo "  Not installed"
    echo ""
    
    echo "AWX Pods:"
    kubectl get pods -n ${AWX_NAMESPACE}
    echo ""
    
    echo "AWX Services:"
    kubectl get svc -n ${AWX_NAMESPACE}
    echo ""
    
    if kubectl get svc ${AWX_INSTANCE_NAME}-service -n ${AWX_NAMESPACE} >/dev/null 2>&1; then
        echo "==================================="
        echo "Access Information:"
        echo "-------------------"
        echo "AWX URL: http://localhost:30080"
        echo "Username: admin"
        echo ""
        echo "Get password with:"
        echo "kubectl get secret ${AWX_INSTANCE_NAME}-admin-password -n ${AWX_NAMESPACE} -o jsonpath='{.data.password}' | base64 --decode"
        echo ""
    fi
}

uninstall_awx() {
    echo "==================================="
    echo "Uninstalling AWX from Cluster"
    echo "==================================="
    echo ""
    
    if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        echo "Kind cluster '${CLUSTER_NAME}' does not exist. Nothing to uninstall."
        exit 0
    fi
    
    kubectl config use-context kind-${CLUSTER_NAME} >/dev/null 2>&1

    if ! kubectl get namespace ${AWX_NAMESPACE} >/dev/null 2>&1; then
        echo "AWX namespace does not exist. Nothing to uninstall."
        exit 0
    fi
    
    echo "Step 1: Deleting AWX instance..."
    kubectl delete awx ${AWX_INSTANCE_NAME} -n ${AWX_NAMESPACE} --ignore-not-found=true
    
    echo ""
    echo "Step 2: Waiting for AWX pods to terminate..."
    kubectl wait --for=delete pod -l app.kubernetes.io/name=${AWX_INSTANCE_NAME} -n ${AWX_NAMESPACE} --timeout=120s 2>/dev/null || true
    
    echo ""
    echo "Step 3: Deleting AWX Operator resources..."
    kubectl delete deployment awx-operator-controller-manager -n ${AWX_NAMESPACE} --ignore-not-found=true
    kubectl delete serviceaccount awx-operator-controller-manager -n ${AWX_NAMESPACE} --ignore-not-found=true
    kubectl delete role awx-operator-awx-manager-role -n ${AWX_NAMESPACE} --ignore-not-found=true
    kubectl delete rolebinding awx-operator-awx-manager-rolebinding -n ${AWX_NAMESPACE} --ignore-not-found=true
    
    echo ""
    echo "Step 4: Deleting PVCs..."
    kubectl delete pvc --all -n ${AWX_NAMESPACE} --ignore-not-found=true
    
    echo ""
    echo "Step 5: Deleting secrets..."
    kubectl delete secret ${AWX_INSTANCE_NAME}-admin-password -n ${AWX_NAMESPACE} --ignore-not-found=true
    
    echo ""
    echo "Step 6: Deleting CRDs..."
    kubectl delete crd awxbackups.awx.ansible.com --ignore-not-found=true
    kubectl delete crd awxrestores.awx.ansible.com --ignore-not-found=true
    kubectl delete crd awxs.awx.ansible.com --ignore-not-found=true
    
    echo ""
    echo "Step 7: Deleting namespace..."
    kubectl delete namespace ${AWX_NAMESPACE} --ignore-not-found=true
    
    echo ""
    echo "==================================="
    echo "AWX Uninstalled Successfully!"
    echo "==================================="
    echo ""
    echo "The Kind cluster '${CLUSTER_NAME}' is still running."
    echo ""
    echo "To completely remove the cluster, run:"
    echo "  $0 destroy"
    echo ""
}

destroy_cluster() {
    echo "==================================="
    echo "Destroying Kind Cluster"
    echo "==================================="
    echo ""
    
    if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        echo "Kind cluster '${CLUSTER_NAME}' does not exist."
        exit 0
    fi
    
    read -p "Are you sure you want to delete the entire cluster '${CLUSTER_NAME}'? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled."
        exit 0
    fi
    
    echo "Deleting Kind cluster '${CLUSTER_NAME}'..."
    kind delete cluster --name ${CLUSTER_NAME}
    
    echo ""
    echo "==================================="
    echo "Cluster Destroyed Successfully!"
    echo "==================================="
    echo ""
}

install_awx() {
    echo "==================================="
    echo "AWX on Kind Cluster Setup"
    echo "==================================="
    
    check_prerequisites
    
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        echo ""
        echo "⚠ Kind cluster '${CLUSTER_NAME}' already exists!"
        read -p "Do you want to use the existing cluster? (yes/no): " use_existing
        if [ "$use_existing" != "yes" ]; then
            echo "Cancelled. Run '$0 destroy' to delete the existing cluster first."
            exit 0
        fi
        kubectl config use-context kind-${CLUSTER_NAME}
    else
        echo ""
        echo "Step 1: Creating Kind cluster..."
        cat <<EOF | kind create cluster --name ${CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
  - containerPort: 30443
    hostPort: 30443
    protocol: TCP
EOF
    fi

    echo ""
    echo "Step 2: Setting kubectl context..."
    kubectl cluster-info --context kind-${CLUSTER_NAME}

    echo ""
    echo "Step 3: Creating AWX namespace..."
    kubectl create namespace ${AWX_NAMESPACE} 2>/dev/null || echo "Namespace already exists"

    echo ""
    echo "Step 4: Installing AWX Operator using Kustomize..."

    AWX_OPERATOR_VERSION=$(curl -s https://api.github.com/repos/ansible/awx-operator/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    echo "Installing AWX Operator version: ${AWX_OPERATOR_VERSION}"
    
    KUSTOMIZE_DIR=$(mktemp -d)
    
    cat > ${KUSTOMIZE_DIR}/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=${AWX_OPERATOR_VERSION}

images:
  - name: quay.io/ansible/awx-operator
    newTag: ${AWX_OPERATOR_VERSION}

namespace: ${AWX_NAMESPACE}
EOF

    kubectl apply -k ${KUSTOMIZE_DIR} --server-side
    rm -rf ${KUSTOMIZE_DIR}

    echo ""
    echo "Step 5: Waiting for AWX Operator to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/awx-operator-controller-manager -n ${AWX_NAMESPACE}

    echo ""
    echo "Step 6: Creating admin password secret..."
    kubectl create secret generic ${AWX_INSTANCE_NAME}-admin-password \
      --from-literal=password='admin123' \
      -n ${AWX_NAMESPACE} 2>/dev/null || echo "Secret already exists"

    echo ""
    echo "Step 7: Creating AWX instance..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${AWX_INSTANCE_NAME}-projects-claim
  namespace: ${AWX_NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_INSTANCE_NAME}
  namespace: ${AWX_NAMESPACE}
spec:
  service_type: NodePort
  nodeport_port: 30080
  projects_persistence: true
  projects_existing_claim: ${AWX_INSTANCE_NAME}-projects-claim
  admin_user: admin
  admin_password_secret: ${AWX_INSTANCE_NAME}-admin-password
EOF

    echo ""
    echo "==================================="
    echo "Installation in progress..."
    echo "==================================="
    echo ""
    echo "Monitoring AWX deployment (this may take 5-10 minutes)..."
    echo "Press Ctrl+C to stop monitoring (deployment will continue)"
    echo ""

    kubectl get pods -n ${AWX_NAMESPACE} -w &
    WATCH_PID=$!

    echo ""
    echo "Waiting for AWX instance to be ready..."
    kubectl wait --for=condition=Running --timeout=600s pods -l app.kubernetes.io/name=${AWX_INSTANCE_NAME} -n ${AWX_NAMESPACE} 2>/dev/null || true

    kill $WATCH_PID 2>/dev/null || true

    echo ""
    echo "==================================="
    echo "Installation Complete!"
    echo "==================================="
    echo ""
    echo "Access Information:"
    echo "-------------------"
    echo "AWX URL: http://localhost:30080"
    echo "Username: admin"
    echo "Password: admin123"
    echo ""
    echo "Useful Commands:"
    echo "-------------------"
    echo "# Check AWX status:"
    echo "$0 status"
    echo ""
    echo "# Check AWX pods:"
    echo "kubectl get pods -n ${AWX_NAMESPACE}"
    echo ""
    echo "# View AWX logs:"
    echo "kubectl logs -f deployment/${AWX_INSTANCE_NAME}-web -n ${AWX_NAMESPACE}"
    echo ""
    echo "# Get admin password:"
    echo "kubectl get secret ${AWX_INSTANCE_NAME}-admin-password -n ${AWX_NAMESPACE} -o jsonpath='{.data.password}' | base64 --decode"
    echo ""
    echo "# Uninstall AWX:"
    echo "$0 uninstall"
    echo ""
    echo "# Delete entire cluster:"
    echo "$0 destroy"
    echo ""
    echo "==================================="
}

case "${1:-}" in
    install)
        install_awx
        ;;
    uninstall)
        uninstall_awx
        ;;
    reinstall)
        uninstall_awx
        echo ""
        sleep 3
        install_awx
        ;;
    destroy)
        destroy_cluster
        ;;
    status)
        check_status
        ;;
    *)
        usage
        ;;
esac