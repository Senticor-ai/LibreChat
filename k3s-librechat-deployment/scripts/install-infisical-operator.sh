#!/bin/bash

# ============================================================================
# Infisical Operator Installation Script for LibreChat
# ============================================================================
# This script installs the Infisical Kubernetes Operator for managing secrets
# Documentation: https://infisical.com/docs/integrations/platforms/kubernetes
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$(dirname "$SCRIPT_DIR")/manifests"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

print_header "Pre-flight Checks"

# Check required commands
check_command kubectl
check_command helm

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi
print_success "Connected to Kubernetes cluster"

# Verify Helm version (should be 4.x for this deployment)
HELM_VERSION=$(helm version --short 2>/dev/null | grep -oP 'v\d+' || echo "v3")
if [[ "$HELM_VERSION" == "v4" ]]; then
    print_success "Helm 4 detected"
elif [[ "$HELM_VERSION" == "v3" ]]; then
    print_warning "Helm 3 detected. Consider upgrading to Helm 4 for latest features."
else
    print_error "Unsupported Helm version: $HELM_VERSION"
    exit 1
fi

# ============================================================================
# Add Infisical Helm Repository
# ============================================================================

print_header "Adding Infisical Helm Repository"

if helm repo list | grep -q "infisical-helm-charts"; then
    print_info "Infisical Helm repository already exists, updating..."
    helm repo update infisical-helm-charts
else
    print_info "Adding Infisical Helm repository..."
    helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/'
    helm repo update
fi
print_success "Helm repository configured"

# ============================================================================
# Create Operator Namespace
# ============================================================================

print_header "Creating Operator Namespace"

OPERATOR_NAMESPACE="infisical-operator-system"

if kubectl get namespace "$OPERATOR_NAMESPACE" &> /dev/null; then
    print_info "Namespace $OPERATOR_NAMESPACE already exists"
else
    kubectl create namespace "$OPERATOR_NAMESPACE"
    print_success "Created namespace: $OPERATOR_NAMESPACE"
fi

# ============================================================================
# Installation Mode Selection
# ============================================================================

print_header "Installation Mode Selection"

echo "Select installation mode:"
echo "  1) Cluster-wide (operator manages all namespaces)"
echo "  2) Namespace-scoped (operator only manages librechat namespace)"
echo ""
read -p "Enter choice [1-2]: " INSTALL_MODE

INSTALL_ARGS=""
case $INSTALL_MODE in
    1)
        print_info "Installing in cluster-wide mode..."
        INSTALL_ARGS=""
        ;;
    2)
        print_info "Installing in namespace-scoped mode for librechat..."
        INSTALL_ARGS="--set scopedNamespace=librechat --set scopedRBAC=true"
        ;;
    *)
        print_error "Invalid choice. Exiting."
        exit 1
        ;;
esac

# ============================================================================
# Install Infisical Operator
# ============================================================================

print_header "Installing Infisical Operator"

# Check if operator is already installed
if helm list -n "$OPERATOR_NAMESPACE" | grep -q "infisical-operator"; then
    print_warning "Infisical operator is already installed"
    read -p "Do you want to upgrade it? [y/N]: " UPGRADE
    if [[ "$UPGRADE" =~ ^[Yy]$ ]]; then
        helm upgrade infisical-operator infisical-helm-charts/secrets-operator \
            --namespace "$OPERATOR_NAMESPACE" \
            -f "$MANIFESTS_DIR/infisical-operator-values.yaml" \
            $INSTALL_ARGS
        print_success "Operator upgraded successfully"
    else
        print_info "Skipping operator installation"
    fi
else
    # Install the operator
    helm install infisical-operator infisical-helm-charts/secrets-operator \
        --namespace "$OPERATOR_NAMESPACE" \
        --create-namespace \
        -f "$MANIFESTS_DIR/infisical-operator-values.yaml" \
        $INSTALL_ARGS

    print_success "Infisical operator installed successfully"
fi

# ============================================================================
# Wait for Operator to be Ready
# ============================================================================

print_header "Waiting for Operator to be Ready"

print_info "Waiting for operator pods to be ready (timeout: 120s)..."
if kubectl wait --for=condition=ready pod \
    -l control-plane=controller-manager \
    -n "$OPERATOR_NAMESPACE" \
    --timeout=120s; then
    print_success "Operator is ready"
else
    print_error "Operator failed to become ready"
    print_info "Check operator logs with: kubectl logs -n $OPERATOR_NAMESPACE -l control-plane=controller-manager"
    exit 1
fi

# ============================================================================
# Next Steps
# ============================================================================

print_header "Installation Complete!"

print_success "Infisical Operator has been installed successfully"

echo ""
print_info "Next steps:"
echo ""
echo "1. Create a Machine Identity in Infisical:"
echo "   - Go to Organization Settings > Access Control > Machine Identities"
echo "   - Click 'Create identity' and configure Universal Auth"
echo "   - Note the Client ID and Client Secret"
echo ""
echo "2. Create the authentication secret in Kubernetes:"
echo "   kubectl create secret generic infisical-universal-auth \\"
echo "     --from-literal=clientId=\"<your-client-id>\" \\"
echo "     --from-literal=clientSecret=\"<your-client-secret>\" \\"
echo "     --namespace librechat"
echo ""
echo "3. Create your Infisical project and secrets:"
echo "   - Create a project in Infisical (e.g., 'librechat')"
echo "   - Add your secrets (OPENAI_API_KEY, JWT_SECRET, etc.)"
echo "   - Note the project slug and environment (dev/staging/prod)"
echo ""
echo "4. Update the InfisicalSecret CRD:"
echo "   - Edit: $MANIFESTS_DIR/infisical-secret-crd.yaml"
echo "   - Set the correct projectSlug and envSlug"
echo "   - Apply: kubectl apply -f $MANIFESTS_DIR/infisical-secret-crd.yaml"
echo ""
echo "5. Verify the secret sync:"
echo "   kubectl get infisicalsecret -n librechat"
echo "   kubectl describe infisicalsecret librechat-credentials -n librechat"
echo "   kubectl get secret librechat-credentials-env -n librechat"
echo ""

print_info "For troubleshooting, check the operator logs:"
echo "kubectl logs -n $OPERATOR_NAMESPACE -l control-plane=controller-manager -f"
echo ""
