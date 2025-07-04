#!/bin/bash
set -e

if [ -z "${WC_HOME}" ]; then
    echo "Please source the wildcloud environment first. (e.g., \`source ./env.sh\`)"
    exit 1
fi

CLUSTER_SETUP_DIR="${WC_HOME}/setup/cluster"
KUBERNETES_DASHBOARD_DIR="${CLUSTER_SETUP_DIR}/kubernetes-dashboard"

echo "Setting up Kubernetes Dashboard..."

# Process templates with wild-compile-template-dir
echo "Processing Dashboard templates..."
wild-compile-template-dir --clean ${KUBERNETES_DASHBOARD_DIR}/kustomize.template ${KUBERNETES_DASHBOARD_DIR}/kustomize

NAMESPACE="kubernetes-dashboard"

# Apply the official dashboard installation 
echo "Installing Kubernetes Dashboard core components..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Wait for cert-manager certificates to be ready
echo "Waiting for cert-manager certificates to be ready..."
kubectl wait --for=condition=Ready certificate wildcard-internal-wild-cloud -n cert-manager --timeout=300s || echo "Warning: Internal wildcard certificate not ready yet"
kubectl wait --for=condition=Ready certificate wildcard-wild-cloud -n cert-manager --timeout=300s || echo "Warning: Wildcard certificate not ready yet"

# Copying cert-manager secrets to the dashboard namespace (if available)
echo "Copying cert-manager secrets to dashboard namespace..."
if kubectl get secret wildcard-internal-wild-cloud-tls -n cert-manager >/dev/null 2>&1; then
    copy-secret cert-manager:wildcard-internal-wild-cloud-tls $NAMESPACE
else
    echo "Warning: wildcard-internal-wild-cloud-tls secret not yet available"
fi

if kubectl get secret wildcard-wild-cloud-tls -n cert-manager >/dev/null 2>&1; then
    copy-secret cert-manager:wildcard-wild-cloud-tls $NAMESPACE
else
    echo "Warning: wildcard-wild-cloud-tls secret not yet available"
fi

# Apply dashboard customizations using kustomize
echo "Applying dashboard customizations..."
kubectl apply -k "${KUBERNETES_DASHBOARD_DIR}/kustomize"

# Restart CoreDNS to pick up the changes
kubectl delete pods -n kube-system -l k8s-app=kube-dns
echo "Restarted CoreDNS to pick up DNS changes"

# Wait for dashboard to be ready
echo "Waiting for Kubernetes Dashboard to be ready..."
kubectl rollout status deployment/kubernetes-dashboard -n $NAMESPACE --timeout=60s

echo "Kubernetes Dashboard setup complete!"
INTERNAL_DOMAIN=$(wild-config cloud.internalDomain) || exit 1
echo "Access the dashboard at: https://dashboard.${INTERNAL_DOMAIN}"
echo ""
echo "To get the authentication token, run:"
echo "wild-dashboard-token"
