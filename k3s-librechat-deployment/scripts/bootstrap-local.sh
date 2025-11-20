#!/bin/bash

# ============================================================================
# LibreChat Local k3d Bootstrap Script
# ============================================================================
# This script deploys LibreChat with self-hosted Infisical to your local k3d cluster
# Perfect for testing before production deployment
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="$PROJECT_ROOT/manifests"

# Configuration - using nip.io for local DNS
CLUSTER_IP="127.0.0.1"
INFISICAL_DOMAIN="infisical.${CLUSTER_IP}.nip.io"
CHAT_DOMAIN="chat.${CLUSTER_IP}.nip.io"
NAMESPACE="librechat"
INFISICAL_NAMESPACE="infisical"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}\n"
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
        print_error "$1 is not installed"
        return 1
    fi
    return 0
}

# ============================================================================
# Welcome Banner
# ============================================================================

clear
print_header "LibreChat Local k3d Bootstrap"

echo -e "${GREEN}This script will deploy LibreChat with self-hosted Infisical to your k3d cluster.${NC}\n"
echo -e "${BLUE}What will be deployed:${NC}"
echo "  • Self-hosted Infisical (secrets management)"
echo "  • Infisical Kubernetes Operator"
echo "  • LibreChat with MongoDB and MeiliSearch"
echo ""
echo -e "${BLUE}Local domains (using nip.io):${NC}"
echo "  • Infisical: http://${INFISICAL_DOMAIN}"
echo "  • LibreChat: http://${CHAT_DOMAIN}"
echo ""
echo -e "${YELLOW}Note: This uses HTTP (no SSL) for local testing${NC}"
echo -e "${YELLOW}Estimated time: 10-15 minutes${NC}"
echo ""

read -p "Press Enter to continue, or Ctrl+C to cancel..."

# ============================================================================
# Pre-flight Checks
# ============================================================================

print_header "Pre-flight Checks"

# Check required commands
for cmd in kubectl helm; do
    if check_command "$cmd"; then
        print_success "$cmd is installed"
    else
        print_error "$cmd is required but not installed"
        exit 1
    fi
done

# Check Helm version (macOS compatible)
HELM_VERSION=$(helm version --short 2>/dev/null | sed -n 's/.*\(v[0-9]\).*/\1/p')
if [[ "$HELM_VERSION" == "v4" ]]; then
    print_success "Helm 4 detected"
elif [[ "$HELM_VERSION" == "v3" ]]; then
    print_warning "Helm 3 detected, upgrading to Helm 4..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
    print_success "Helm 4 installed"
elif [[ -n "$HELM_VERSION" ]]; then
    print_error "Unsupported Helm version: $HELM_VERSION"
    print_info "Installing Helm 4..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
    print_success "Helm 4 installed"
else
    print_info "Helm not found or version cannot be determined, installing Helm 4..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
    print_success "Helm 4 installed"
fi

# Check k3d cluster
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    print_info "Make sure your k3d cluster is running: k3d cluster list"
    exit 1
fi

CURRENT_CONTEXT=$(kubectl config current-context)
if [[ ! "$CURRENT_CONTEXT" =~ k3d ]]; then
    print_warning "Current context is: $CURRENT_CONTEXT"
    print_warning "This doesn't look like a k3d cluster!"
    read -p "Continue anyway? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_success "Connected to k3d cluster: $CURRENT_CONTEXT"
fi

# ============================================================================
# Gather User Input
# ============================================================================

print_header "Configuration"

# API Keys (optional for testing)
read -p "Enter OpenRouter API key (or press Enter to skip): " OPENROUTER_API_KEY
read -p "Enter Anthropic API key (or press Enter to skip): " ANTHROPIC_API_KEY

# Generate all required secrets automatically
print_info "Generating secure random secrets..."
CREDS_KEY=$(openssl rand -hex 32)
CREDS_IV=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)
MEILI_MASTER_KEY=$(openssl rand -hex 32)
INFISICAL_AUTH_SECRET=$(openssl rand -base64 32)
INFISICAL_ENCRYPTION_KEY=$(openssl rand -hex 16)
INFISICAL_DB_PASSWORD=$(openssl rand -base64 32)
INFISICAL_REDIS_PASSWORD=$(openssl rand -base64 32)
MONGODB_ROOT_PASSWORD=$(openssl rand -base64 32)

print_success "All secrets generated"

# ============================================================================
# Install Prerequisites
# ============================================================================

print_header "Installing Prerequisites"

# Create namespaces
for ns in ingress-nginx cert-manager $INFISICAL_NAMESPACE infisical-operator-system $NAMESPACE; do
    if kubectl get namespace "$ns" &> /dev/null; then
        print_info "Namespace $ns already exists"
    else
        kubectl create namespace "$ns"
        print_success "Created namespace: $ns"
    fi
done

# Install nginx ingress controller
if kubectl get deployment -n ingress-nginx ingress-nginx-controller &> /dev/null; then
    print_info "Nginx ingress controller already installed"
else
    print_info "Installing nginx ingress controller..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
    helm repo update ingress-nginx
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --set controller.service.type=NodePort \
        --set controller.service.nodePorts.http=30080 \
        --set controller.service.nodePorts.https=30443 \
        --wait \
        --timeout 5m
    print_success "Nginx ingress controller installed"
fi

# Install cert-manager (even though we won't use real certs, some charts may need CRDs)
if kubectl get deployment -n cert-manager cert-manager &> /dev/null; then
    print_info "Cert-manager already installed"
else
    print_info "Installing cert-manager..."
    helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
    helm repo update jetstack
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --set crds.enabled=true \
        --wait \
        --timeout 5m
    print_success "Cert-manager installed"
fi

# ============================================================================
# Deploy Self-Hosted Infisical
# ============================================================================

print_header "Deploying Self-Hosted Infisical"

# Create Infisical secrets
print_info "Creating Infisical configuration secrets..."
cat > /tmp/infisical-secrets.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: infisical-secrets
  namespace: $INFISICAL_NAMESPACE
type: Opaque
stringData:
  AUTH_SECRET: "$INFISICAL_AUTH_SECRET"
  ENCRYPTION_KEY: "$INFISICAL_ENCRYPTION_KEY"
  SITE_URL: "http://$INFISICAL_DOMAIN"
  TELEMETRY_ENABLED: "false"
EOF

kubectl apply -f /tmp/infisical-secrets.yaml
rm /tmp/infisical-secrets.yaml
print_success "Infisical secrets created"

# Create Infisical values file for local deployment
print_info "Creating Infisical Helm values..."
cat > /tmp/infisical-values.yaml <<EOF
infisical:
  image:
    repository: infisical/infisical
    tag: "v0.46.2-postgres"
    pullPolicy: IfNotPresent

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

ingress:
  nginx:
    enabled: true
    ingressClassName: nginx
    annotations: {}
    host: $INFISICAL_DOMAIN
    tls:
      enabled: false  # No SSL for local testing

# Disable nginx-ingress sub-chart (we already have it installed)
ingress-nginx:
  enabled: false

nginx-ingress:
  enabled: false

postgresql:
  enabled: true
  auth:
    username: infisical
    password: "$INFISICAL_DB_PASSWORD"
    database: infisical
  primary:
    persistence:
      enabled: true
      size: 5Gi
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

redis:
  enabled: true
  auth:
    enabled: true
    password: "$INFISICAL_REDIS_PASSWORD"
  master:
    persistence:
      enabled: true
      size: 2Gi
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 250m
        memory: 256Mi
EOF

# Add Infisical Helm repository
print_info "Adding Infisical Helm repository..."
if helm repo list | grep -q "infisical-helm-charts"; then
    helm repo update infisical-helm-charts
else
    helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/'
    helm repo update
fi
print_success "Helm repository configured"

# Check for existing Infisical installation
if helm list -n "$INFISICAL_NAMESPACE" | grep -q "infisical"; then
    print_warning "Existing Infisical installation found"
    read -p "Do you want to upgrade it? [y/N]: " UPGRADE_INFISICAL
    if [[ ! "$UPGRADE_INFISICAL" =~ ^[Yy]$ ]]; then
        print_info "Skipping Infisical installation"
        rm /tmp/infisical-values.yaml
    else
        print_info "Upgrading Infisical (this may take 3-5 minutes)..."
        helm upgrade infisical infisical-helm-charts/infisical-standalone \
            --namespace "$INFISICAL_NAMESPACE" \
            --values /tmp/infisical-values.yaml \
            --wait \
            --timeout 10m
        rm /tmp/infisical-values.yaml
        print_success "Infisical upgraded"
    fi
else
    # Deploy Infisical
    print_info "Deploying Infisical (this may take 3-5 minutes)..."
    helm upgrade --install infisical infisical-helm-charts/infisical-standalone \
        --namespace "$INFISICAL_NAMESPACE" \
        --values /tmp/infisical-values.yaml \
        --wait \
        --timeout 10m
    rm /tmp/infisical-values.yaml
    print_success "Infisical deployed"
fi

# Wait for Infisical to be ready
print_info "Waiting for Infisical to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=infisical \
    -n "$INFISICAL_NAMESPACE" \
    --timeout=180s 2>/dev/null || true
print_success "Infisical is ready"

# ============================================================================
# Setup Infisical Project
# ============================================================================

print_header "Infisical Setup Instructions"

echo -e "${GREEN}Infisical has been deployed!${NC}\n"
echo -e "${YELLOW}IMPORTANT: Complete these steps manually:${NC}\n"
echo -e "${BLUE}1. Access Infisical:${NC}"
echo -e "   Open: ${CYAN}http://$INFISICAL_DOMAIN:30080${NC}\n"
echo -e "${BLUE}2. Create your account${NC}"
echo "   - Sign up with email/password"
echo -e "   - Create organization\n"
echo -e "${BLUE}3. Create project \"${NAMESPACE}\"${NC}"
echo "   - Click \"Create Project\""
echo -e "   - Name: ${CYAN}$NAMESPACE${NC}"
echo -e "   - Environment: ${CYAN}prod${NC} (default)\n"
echo -e "${BLUE}4. Add these secrets in the \"prod\" environment:${NC}"

# Create a secrets file for easy copy-paste
SECRETS_FILE="/tmp/librechat-secrets-$(date +%s).txt"
cat > "$SECRETS_FILE" <<EOF
CREDS_KEY=$CREDS_KEY
CREDS_IV=$CREDS_IV
JWT_SECRET=$JWT_SECRET
JWT_REFRESH_SECRET=$JWT_REFRESH_SECRET
MEILI_MASTER_KEY=$MEILI_MASTER_KEY
EOF

if [ -n "$OPENROUTER_API_KEY" ]; then
    echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" >> "$SECRETS_FILE"
fi

if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" >> "$SECRETS_FILE"
fi

cat "$SECRETS_FILE"

echo ""
echo -e "${GREEN}Secrets saved to: $SECRETS_FILE${NC}"
echo -e "${YELLOW}Copy-paste these into Infisical web UI (one per line)${NC}"
echo ""
echo -e "${BLUE}5. Create Machine Identity:${NC}"
echo "   - Go to: Organization Settings → Access Control → Machine Identities"
echo "   - Click \"Create identity\""
echo "   - Name: ${CYAN}k3d-librechat-operator${NC}"
echo "   - Click \"Add authentication method\" → \"Universal Auth\""
echo "   - ${YELLOW}SAVE the Client ID and Client Secret${NC}"
echo ""
echo -e "${BLUE}6. Grant Project Access:${NC}"
echo "   - Go to ${CYAN}$NAMESPACE${NC} project → Settings → Access Control"
echo "   - Click \"Add member\""
echo "   - Select ${CYAN}k3d-librechat-operator${NC} machine identity"
echo "   - Role: Developer or Admin"
echo ""

read -p "Press Enter after completing Infisical setup..."

# ============================================================================
# Get Infisical Credentials
# ============================================================================

print_header "Infisical Credentials"

echo -e "${YELLOW}Enter the Machine Identity credentials you created:${NC}"
read -p "Client ID: " INFISICAL_CLIENT_ID
read -sp "Client Secret: " INFISICAL_CLIENT_SECRET
echo ""

if [ -z "$INFISICAL_CLIENT_ID" ] || [ -z "$INFISICAL_CLIENT_SECRET" ]; then
    print_error "Client ID and Secret are required"
    exit 1
fi

# ============================================================================
# Install Infisical Operator
# ============================================================================

print_header "Installing Infisical Operator"

# Add Infisical Helm repo if not already added
helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/' 2>/dev/null || true
helm repo update infisical-helm-charts

# Install operator (namespace-scoped)
print_info "Installing Infisical Operator (namespace-scoped)..."
cat > /tmp/operator-values.yaml <<EOF
scopedNamespace: "$NAMESPACE"
scopedRBAC: true
controllerManager:
  serviceAccount:
    create: true
EOF

helm upgrade --install infisical-operator infisical-helm-charts/infisical-kubernetes-operator \
    --namespace infisical-operator-system \
    --values /tmp/operator-values.yaml \
    --wait \
    --timeout 5m

rm /tmp/operator-values.yaml
print_success "Infisical Operator installed"

# ============================================================================
# Configure Infisical Secret Sync
# ============================================================================

print_header "Configuring Secret Synchronization"

# Create authentication secret
print_info "Creating Infisical authentication secret..."
kubectl create secret generic infisical-universal-auth \
    --from-literal=clientId="$INFISICAL_CLIENT_ID" \
    --from-literal=clientSecret="$INFISICAL_CLIENT_SECRET" \
    --namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

print_success "Authentication secret created"

# Create InfisicalSecret CRD
print_info "Creating InfisicalSecret CRD..."
cat > /tmp/infisical-secret-crd.yaml <<EOF
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: librechat-credentials
  namespace: $NAMESPACE
spec:
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: $NAMESPACE
  hostAPI: http://infisical-backend.$INFISICAL_NAMESPACE.svc.cluster.local
  secretsScope:
    projectSlug: "$NAMESPACE"
    envSlug: "prod"
    secretsPath: "/"
  managedKubeSecretReferences:
    - secretName: librechat-credentials-env
      secretNamespace: $NAMESPACE
      creationPolicy: "Orphan"
  resyncInterval: 60
EOF

kubectl apply -f /tmp/infisical-secret-crd.yaml
rm /tmp/infisical-secret-crd.yaml
print_success "InfisicalSecret CRD created"

# Wait for secret sync
print_info "Waiting for secrets to sync (timeout: 90s)..."
TIMEOUT=90
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if kubectl get secret librechat-credentials-env -n "$NAMESPACE" &> /dev/null; then
        print_success "Secrets synced from Infisical"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    print_warning "Secret sync timeout - check InfisicalSecret status:"
    echo "  kubectl describe infisicalsecret librechat-credentials -n $NAMESPACE"
    read -p "Continue anyway? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ============================================================================
# Deploy LibreChat
# ============================================================================

print_header "Deploying LibreChat"

# Create cert-issuer (self-signed for local)
print_info "Creating certificate issuer..."
cat > /tmp/cert-issuer.yaml <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

kubectl apply -f /tmp/cert-issuer.yaml
rm /tmp/cert-issuer.yaml
print_success "Certificate issuer created"

# Create LibreChat values file
print_info "Creating LibreChat Helm values..."
cat > /tmp/librechat-values.yaml <<EOF
librechat:
  image:
    repository: ghcr.io/danny-avila/librechat
    tag: latest
    pullPolicy: Always

  podAnnotations:
    secrets.infisical.com/auto-reload: "true"

  extraEnv:
    DOMAIN_CLIENT: "http://$CHAT_DOMAIN:30080"
    DOMAIN_SERVER: "http://$CHAT_DOMAIN:30080"
    ALLOW_REGISTRATION: "true"

  extraEnvFrom:
    - secretRef:
        name: librechat-credentials-env

  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 2Gi

  ingress:
    enabled: true
    className: nginx
    annotations: {}
    hosts:
      - host: $CHAT_DOMAIN
        paths:
          - path: /
            pathType: Prefix
    tls: []

mongodb:
  enabled: true
  auth:
    enabled: true
    rootPassword: "$MONGODB_ROOT_PASSWORD"
  persistence:
    enabled: true
    size: 10Gi
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi

meilisearch:
  enabled: true
  environment:
    MEILI_MASTER_KEY:
      valueFrom:
        secretKeyRef:
          name: librechat-credentials-env
          key: MEILI_MASTER_KEY
  persistence:
    enabled: true
    size: 5Gi
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
EOF

# Deploy LibreChat
print_info "Deploying LibreChat (this may take 5-10 minutes)..."
helm upgrade --install librechat oci://ghcr.io/danny-avila/librechat-chart/librechat \
    --namespace "$NAMESPACE" \
    --values /tmp/librechat-values.yaml \
    --wait \
    --timeout 15m

rm /tmp/librechat-values.yaml
print_success "LibreChat deployed"

# ============================================================================
# Deployment Complete
# ============================================================================

print_header "Deployment Complete!"

echo -e "${GREEN}✓ LibreChat with self-hosted Infisical is ready!${NC}\n"
echo -e "${BLUE}Access URLs:${NC}"
echo -e "  • Infisical:  ${CYAN}http://$INFISICAL_DOMAIN:30080${NC}"
echo -e "  • LibreChat:  ${CYAN}http://$CHAT_DOMAIN:30080${NC}\n"
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Open LibreChat in your browser"
echo "  2. Click \"Sign up\" to create your account"
echo -e "  3. Start chatting!\n"
echo -e "${BLUE}Useful commands:${NC}"
echo "  # Check all pods"
echo "  kubectl get pods -n $NAMESPACE"
echo ""
echo "  # View LibreChat logs"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=librechat -f"
echo ""
echo "  # Check Infisical sync status"
echo "  kubectl describe infisicalsecret librechat-credentials -n $NAMESPACE"
echo ""
echo "  # Update a secret in Infisical"
echo -e "  # → Pods will auto-restart within 60 seconds!\n"
echo -e "${YELLOW}Testing secret auto-reload:${NC}"
echo "  1. Go to Infisical → $NAMESPACE project → prod environment"
echo "  2. Update any secret (e.g., add a new one)"
echo -e "  3. Watch pods restart: ${CYAN}kubectl get pods -n $NAMESPACE -w${NC}\n"
echo -e "${GREEN}Secrets file saved to: $SECRETS_FILE${NC}"
echo -e "${YELLOW}Keep this file safe for reference!${NC}\n"

print_success "Bootstrap complete!"
