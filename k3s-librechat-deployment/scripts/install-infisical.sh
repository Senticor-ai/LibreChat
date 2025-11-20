#!/bin/bash

# ============================================================================
# Infisical Self-Hosted Installation Script for LibreChat k3s Deployment
# ============================================================================
# This script installs Infisical standalone on your k3s cluster
# Documentation: https://infisical.com/docs/self-hosting/deployment-options/kubernetes-helm
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

# Configuration
INFISICAL_NAMESPACE="infisical"
INFISICAL_VALUES="$MANIFESTS_DIR/infisical-standalone-values.yaml"
INFISICAL_SECRET="$MANIFESTS_DIR/infisical-standalone-secret.yaml"

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

# Check Helm version
HELM_VERSION=$(helm version --short 2>/dev/null | grep -oP 'v\d+' || echo "unknown")
if [[ "$HELM_VERSION" == "v4" ]]; then
    print_success "Helm 4 detected"
else
    print_error "Helm 4 is required. Please install Helm 4."
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
# Create Infisical Namespace
# ============================================================================

print_header "Creating Infisical Namespace"

if kubectl get namespace "$INFISICAL_NAMESPACE" &> /dev/null; then
    print_info "Namespace $INFISICAL_NAMESPACE already exists"
else
    kubectl create namespace "$INFISICAL_NAMESPACE"
    print_success "Created namespace: $INFISICAL_NAMESPACE"
fi

# ============================================================================
# Configure Infisical Secrets
# ============================================================================

print_header "Configuring Infisical Secrets"

if [ ! -f "$INFISICAL_SECRET" ]; then
    print_error "Infisical secret file not found: $INFISICAL_SECRET"
    print_info "Please create it from the template and configure:"
    echo "  1. Generate AUTH_SECRET: openssl rand -base64 32"
    echo "  2. Generate ENCRYPTION_KEY: openssl rand -hex 16"
    echo "  3. Set SITE_URL to your Infisical domain"
    echo "  4. Update PostgreSQL and Redis passwords in values file"
    exit 1
fi

# Generate secrets if needed
print_info "Checking secret configuration..."
if grep -q "CHANGE_ME" "$INFISICAL_SECRET"; then
    print_warning "Found CHANGE_ME values in secret file"
    echo ""
    echo "Please update the following in $INFISICAL_SECRET:"
    echo "  - AUTH_SECRET (generate with: openssl rand -base64 32)"
    echo "  - ENCRYPTION_KEY (generate with: openssl rand -hex 16)"
    echo "  - SITE_URL (your Infisical domain)"
    echo ""
    read -p "Press Enter after updating secrets, or Ctrl+C to cancel..."
fi

kubectl apply -f "$INFISICAL_SECRET"
print_success "Infisical secrets configured"

# ============================================================================
# Configure Values File
# ============================================================================

print_header "Configuring Deployment Values"

if [ ! -f "$INFISICAL_VALUES" ]; then
    print_error "Infisical values file not found: $INFISICAL_VALUES"
    exit 1
fi

# Check for placeholder values
if grep -q "example.com" "$INFISICAL_VALUES"; then
    print_warning "Found example.com in values file"
    echo ""
    echo "Please update the following in $INFISICAL_VALUES:"
    echo "  - ingress.nginx.host (line ~35): Set to your Infisical domain"
    echo "  - postgresql.auth.password (line ~50): Set secure password"
    echo "  - redis.auth.password (line ~64): Set secure password"
    echo ""
    read -p "Press Enter after updating values, or Ctrl+C to cancel..."
fi

# ============================================================================
# Deploy Infisical
# ============================================================================

print_header "Deploying Infisical"

# Check if already installed
if helm list -n "$INFISICAL_NAMESPACE" | grep -q "infisical"; then
    print_warning "Infisical is already installed"
    read -p "Do you want to upgrade it? [y/N]: " UPGRADE
    if [[ "$UPGRADE" =~ ^[Yy]$ ]]; then
        helm upgrade infisical infisical-helm-charts/infisical-standalone \
            --namespace "$INFISICAL_NAMESPACE" \
            -f "$INFISICAL_VALUES" \
            --wait \
            --timeout 10m
        print_success "Infisical upgraded successfully"
    else
        print_info "Skipping Infisical installation"
    fi
else
    # Install Infisical
    helm install infisical infisical-helm-charts/infisical-standalone \
        --namespace "$INFISICAL_NAMESPACE" \
        --create-namespace \
        -f "$INFISICAL_VALUES" \
        --wait \
        --timeout 10m

    print_success "Infisical deployed successfully"
fi

# ============================================================================
# Wait for Infisical to be Ready
# ============================================================================

print_header "Waiting for Infisical to be Ready"

print_info "Waiting for pods to be ready (timeout: 180s)..."
if kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=infisical \
    -n "$INFISICAL_NAMESPACE" \
    --timeout=180s 2>/dev/null; then
    print_success "Infisical is ready"
else
    print_warning "Pods may still be starting. Check status with:"
    echo "  kubectl get pods -n $INFISICAL_NAMESPACE"
fi

# ============================================================================
# Display Access Information
# ============================================================================

print_header "Installation Complete!"

print_success "Infisical has been deployed successfully"

echo ""
print_info "Access Information:"
echo ""

# Get ingress information
INGRESS_HOST=$(kubectl get ingress -n "$INFISICAL_NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "Not configured")
echo "  Infisical URL: https://$INGRESS_HOST"
echo ""

print_info "Next steps:"
echo ""
echo "1. Wait for SSL certificate to be provisioned (may take 5-10 minutes):"
echo "   kubectl get certificate -n $INFISICAL_NAMESPACE"
echo ""
echo "2. Access Infisical and create your account:"
echo "   https://$INGRESS_HOST"
echo ""
echo "3. Create an organization and project named 'librechat'"
echo ""
echo "4. Add your secrets to the 'prod' environment"
echo ""
echo "5. Install the Infisical Operator for secret sync:"
echo "   ./install-infisical-operator.sh"
echo ""
echo "6. Continue with LibreChat deployment (see QUICKSTART.md)"
echo ""

print_info "Useful commands:"
echo "  Check pods:        kubectl get pods -n $INFISICAL_NAMESPACE"
echo "  View logs:         kubectl logs -n $INFISICAL_NAMESPACE -l app.kubernetes.io/name=infisical"
echo "  Check ingress:     kubectl get ingress -n $INFISICAL_NAMESPACE"
echo "  Check certificate: kubectl get certificate -n $INFISICAL_NAMESPACE"
echo ""
