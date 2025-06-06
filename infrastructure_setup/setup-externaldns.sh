#!/bin/bash
set -e

# Navigate to script directory
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
cd "$SCRIPT_DIR"

# Source environment variables
if [[ -f "../load-env.sh" ]]; then
  source ../load-env.sh
fi

echo "Setting up ExternalDNS..."

# Create externaldns namespace
kubectl create namespace externaldns --dry-run=client -o yaml | kubectl apply -f -

# Setup Cloudflare API token secret for ExternalDNS
if [[ -n "${CLOUDFLARE_API_TOKEN}" ]]; then
  echo "Creating Cloudflare API token secret..."
  kubectl create secret generic cloudflare-api-token \
    --namespace externaldns \
    --from-literal=api-token="${CLOUDFLARE_API_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "Error: CLOUDFLARE_API_TOKEN not set. ExternalDNS will not work correctly."
  exit 1
fi

# Apply common RBAC resources
echo "Deploying ExternalDNS RBAC resources..."
cat ${SCRIPT_DIR}/externaldns/externaldns-rbac.yaml | envsubst | kubectl apply -f -

# Apply ExternalDNS manifests with environment variables
echo "Deploying ExternalDNS for external DNS (Cloudflare)..."
cat ${SCRIPT_DIR}/externaldns/externaldns-cloudflare.yaml | envsubst | kubectl apply -f -

# Wait for ExternalDNS to be ready
echo "Waiting for Cloudflare ExternalDNS to be ready..."
kubectl rollout status deployment/external-dns -n externaldns --timeout=60s

# echo "Waiting for CoreDNS ExternalDNS to be ready..."
# kubectl rollout status deployment/external-dns-coredns -n externaldns --timeout=60s

echo "ExternalDNS setup complete!"
echo ""
echo "To verify the installation:"
echo "  kubectl get pods -n externaldns"
echo "  kubectl logs -n externaldns -l app=external-dns -f"
echo "  kubectl logs -n externaldns -l app=external-dns-coredns -f"
