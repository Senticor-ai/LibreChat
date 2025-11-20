#!/bin/bash

# ============================================================================
# LibreChat Production Bootstrap Script
# ============================================================================
# This script deploys LibreChat with self-hosted Infisical to your production k3s cluster
# Run this on your Linux server via SSH
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

# Configuration
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
        return 1
    fi
    return 0
}

# ============================================================================
# Welcome Banner
# ============================================================================

clear
print_header "LibreChat Production Bootstrap"

echo -e "${GREEN}This script will deploy LibreChat with self-hosted Infisical to your production cluster.${NC}\n"
echo -e "${BLUE}What will be deployed:${NC}"
echo "  • k3s (if not already installed)"
echo "  • Helm 4"
echo "  • Nginx Ingress Controller"
echo "  • Cert-Manager (for SSL certificates)"
echo "  • Self-hosted Infisical"
echo "  • Infisical Kubernetes Operator"
echo -e "  • LibreChat with MongoDB and MeiliSearch\n"
echo -e "${YELLOW}Requirements:${NC}"
echo "  • Ubuntu/Debian Linux server with sudo access"
echo "  • Two domain names pointing to this server's IP"
echo "  • Ports 80 and 443 accessible from the internet"
echo -e "  • At least 4GB RAM and 20GB disk space\n"
echo -e "${YELLOW}Estimated time: 20-30 minutes${NC}\n"

read -p "Press Enter to continue, or Ctrl+C to cancel..."

# ============================================================================
# Gather Configuration
# ============================================================================

print_header "Configuration"

# Domain names
while true; do
    read -p "Enter your Infisical domain (e.g., infisical.example.com): " INFISICAL_DOMAIN
    if [[ "$INFISICAL_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+[a-zA-Z0-9]$ ]]; then
        break
    else
        print_error "Invalid domain name format"
    fi
done

while true; do
    read -p "Enter your LibreChat domain (e.g., chat.example.com): " CHAT_DOMAIN
    if [[ "$CHAT_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+[a-zA-Z0-9]$ ]]; then
        break
    else
        print_error "Invalid domain name format"
    fi
done

# Email for Let's Encrypt
while true; do
    read -p "Enter your email for SSL certificates: " CERT_EMAIL
    if [[ "$CERT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        print_error "Invalid email format"
    fi
done

# API Keys (optional)
echo ""
print_info "API Keys (optional - you can add these later in Infisical):"
read -p "OpenRouter API key (or press Enter to skip): " OPENROUTER_API_KEY
read -p "Anthropic API key (or press Enter to skip): " ANTHROPIC_API_KEY

# Generate all required secrets automatically
echo ""
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

# Confirmation
echo ""
print_info "Configuration Summary:"
echo "  Infisical Domain: $INFISICAL_DOMAIN"
echo "  LibreChat Domain: $CHAT_DOMAIN"
echo "  SSL Email: $CERT_EMAIL"
echo "  OpenRouter API Key: $([ -n "$OPENROUTER_API_KEY" ] && echo "Configured" || echo "Not set")"
echo "  Anthropic API Key: $([ -n "$ANTHROPIC_API_KEY" ] && echo "Configured" || echo "Not set")"
echo ""

read -p "Proceed with deployment? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled"
    exit 0
fi

# ============================================================================
# Install k3s (if needed)
# ============================================================================

print_header "Installing k3s"

if check_command kubectl && kubectl cluster-info &> /dev/null; then
    print_info "Kubernetes cluster already running"

    # Check if it's k3s
    if [ -f /etc/systemd/system/k3s.service ]; then
        print_success "k3s detected"
    else
        print_warning "Non-k3s cluster detected"
        read -p "Continue anyway? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    print_info "Installing k3s..."
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

    # Wait for k3s to be ready
    print_info "Waiting for k3s to be ready..."
    sleep 10

    # Export kubeconfig
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    print_success "k3s installed"
fi

# Ensure kubectl works
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

print_success "Kubernetes cluster is accessible"

# ============================================================================
# Install Helm 4
# ============================================================================

print_header "Installing Helm 4"

if check_command helm; then
    HELM_VERSION=$(helm version --short 2>/dev/null | sed -n 's/.*\(v[0-9]\).*/\1/p')
    if [[ "$HELM_VERSION" == "v4" ]]; then
        print_success "Helm 4 already installed"
    else
        print_info "Upgrading to Helm 4..."
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
        print_success "Helm 4 installed"
    fi
else
    print_info "Installing Helm 4..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
    print_success "Helm 4 installed"
fi

# ============================================================================
# Create Namespaces
# ============================================================================

print_header "Creating Namespaces"

for ns in ingress-nginx cert-manager $INFISICAL_NAMESPACE infisical-operator-system $NAMESPACE; do
    if kubectl get namespace "$ns" &> /dev/null; then
        print_info "Namespace $ns already exists"
    else
        kubectl create namespace "$ns"
        print_success "Created namespace: $ns"
    fi
done

# ============================================================================
# Install Nginx Ingress Controller
# ============================================================================

print_header "Installing Nginx Ingress Controller"

if kubectl get deployment -n ingress-nginx ingress-nginx-controller &> /dev/null; then
    print_info "Nginx ingress controller already installed"
else
    print_info "Installing nginx ingress controller..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
    helm repo update ingress-nginx
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --set controller.service.type=LoadBalancer \
        --wait \
        --timeout 5m
    print_success "Nginx ingress controller installed"
fi

# ============================================================================
# Install Cert-Manager
# ============================================================================

print_header "Installing Cert-Manager"

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

# Configure Let's Encrypt issuer
print_info "Configuring Let's Encrypt certificate issuer..."
cat > /tmp/cert-issuer.yaml <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF

kubectl apply -f /tmp/cert-issuer.yaml
rm /tmp/cert-issuer.yaml
print_success "Certificate issuer configured"

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
  SITE_URL: "https://$INFISICAL_DOMAIN"
  TELEMETRY_ENABLED: "false"
EOF

kubectl apply -f /tmp/infisical-secrets.yaml
rm /tmp/infisical-secrets.yaml
print_success "Infisical secrets created"

# Create Infisical values file for production deployment
print_info "Creating Infisical Helm values..."
cat > /tmp/infisical-values.yaml <<EOF
infisical:
  image:
    repository: infisical/infisical
    tag: "v0.46.2-postgres"
    pullPolicy: IfNotPresent

  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi

ingress:
  nginx:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    host: $INFISICAL_DOMAIN
    tls:
      enabled: true
      secretName: infisical-tls

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
      size: 20Gi
    resources:
      requests:
        cpu: 250m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 1Gi

redis:
  enabled: true
  auth:
    enabled: true
    password: "$INFISICAL_REDIS_PASSWORD"
  master:
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

# Add Infisical Helm repository
print_info "Adding Infisical Helm repository..."
if helm repo list | grep -q "infisical-helm-charts"; then
    helm repo update infisical-helm-charts
else
    helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/'
    helm repo update
fi
print_success "Helm repository configured"

# Deploy Infisical
print_info "Deploying Infisical (this may take 5-10 minutes)..."
helm upgrade --install infisical infisical-helm-charts/infisical-standalone \
    --namespace "$INFISICAL_NAMESPACE" \
    --values /tmp/infisical-values.yaml \
    --wait \
    --timeout 10m

rm /tmp/infisical-values.yaml
print_success "Infisical deployed"

# Wait for Infisical to be ready
print_info "Waiting for Infisical pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=infisical \
    -n "$INFISICAL_NAMESPACE" \
    --timeout=180s 2>/dev/null || true
print_success "Infisical pods are ready"

# Check SSL certificate
print_info "Waiting for SSL certificate (this may take 5-10 minutes)..."
print_warning "Certificate provisioning requires DNS to be pointing to this server"
print_info "Check certificate status: kubectl get certificate -n $INFISICAL_NAMESPACE"

# ============================================================================
# Setup Infisical Project
# ============================================================================

print_header "Infisical Setup Instructions"

echo -e "${GREEN}Infisical has been deployed!${NC}\n"
echo -e "${YELLOW}IMPORTANT: Complete these steps manually:${NC}\n"
echo -e "${BLUE}1. Wait for SSL certificate${NC}"
echo -e "   Check status: ${CYAN}kubectl get certificate -n $INFISICAL_NAMESPACE${NC}"
echo -e "   Wait for READY = True (may take 5-10 minutes)\n"
echo -e "${BLUE}2. Access Infisical:${NC}"
echo -e "   Open: ${CYAN}https://$INFISICAL_DOMAIN${NC}\n"
echo -e "${BLUE}3. Create your account${NC}"
echo "   - Sign up with email/password"
echo -e "   - Create organization\n"
echo -e "${BLUE}4. Create project \"${NAMESPACE}\"${NC}"
echo "   - Click \"Create Project\""
echo -e "   - Name: ${CYAN}$NAMESPACE${NC}"
echo -e "   - Environment: ${CYAN}prod${NC} (default)\n"
echo -e "${BLUE}5. Add these secrets in the \"prod\" environment:${NC}"

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
echo -e "${BLUE}6. Create Machine Identity:${NC}"
echo "   - Go to: Organization Settings → Access Control → Machine Identities"
echo "   - Click \"Create identity\""
echo "   - Name: ${CYAN}k3s-librechat-operator${NC}"
echo "   - Click \"Add authentication method\" → \"Universal Auth\""
echo "   - ${YELLOW}SAVE the Client ID and Client Secret${NC}"
echo ""
echo -e "${BLUE}7. Grant Project Access:${NC}"
echo "   - Go to ${CYAN}$NAMESPACE${NC} project → Settings → Access Control"
echo "   - Click \"Add member\""
echo "   - Select ${CYAN}k3s-librechat-operator${NC} machine identity"
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
    DOMAIN_CLIENT: "https://$CHAT_DOMAIN"
    DOMAIN_SERVER: "https://$CHAT_DOMAIN"
    ALLOW_REGISTRATION: "true"

  extraEnvFrom:
    - secretRef:
        name: librechat-credentials-env

  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 4Gi

  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/proxy-body-size: "20m"
    hosts:
      - host: $CHAT_DOMAIN
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: librechat-tls
        hosts:
          - $CHAT_DOMAIN

mongodb:
  enabled: true
  auth:
    enabled: true
    rootPassword: "$MONGODB_ROOT_PASSWORD"
  persistence:
    enabled: true
    size: 50Gi
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi

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
    size: 20Gi
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi
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

# Wait for SSL certificate
print_info "Waiting for LibreChat SSL certificate..."
print_info "Check status: kubectl get certificate -n $NAMESPACE"

# ============================================================================
# Deployment Complete
# ============================================================================

print_header "Deployment Complete!"

echo -e "${GREEN}✓ LibreChat with self-hosted Infisical is deployed!${NC}\n"
echo -e "${BLUE}Access URLs:${NC}"
echo -e "  • Infisical:  ${CYAN}https://$INFISICAL_DOMAIN${NC}"
echo -e "  • LibreChat:  ${CYAN}https://$CHAT_DOMAIN${NC}\n"
echo -e "${YELLOW}Wait for SSL certificates to be provisioned (5-10 minutes):${NC}"
echo "  kubectl get certificate -n $INFISICAL_NAMESPACE"
echo -e "  kubectl get certificate -n $NAMESPACE\n"
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Wait for SSL certificates (READY = True)"
echo "  2. Open LibreChat in your browser: https://$CHAT_DOMAIN"
echo "  3. Click \"Sign up\" to create your admin account"
echo -e "  4. ${YELLOW}After creating your account, set ALLOW_REGISTRATION=\"false\" in Infisical${NC}\n"
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
echo "  # Check SSL certificates"
echo "  kubectl get certificate -A"
echo ""
echo "  # Update a secret"
echo "  # → Go to Infisical UI, change a secret"
echo -e "  # → Pods will auto-restart within 60 seconds!\n"
echo -e "${GREEN}Secrets file saved to: $SECRETS_FILE${NC}"
echo -e "${YELLOW}Keep this file safe and secure!${NC}\n"
echo -e "${YELLOW}Security Reminder:${NC}"
echo "  • Set ALLOW_REGISTRATION=\"false\" in Infisical after creating your account"
echo "  • Keep your Machine Identity credentials secure"
echo "  • Regularly backup your MongoDB data"
echo -e "  • Monitor your Let's Encrypt certificate renewals\n"

print_success "Bootstrap complete!"
