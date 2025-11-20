#!/bin/bash

# LibreChat k3s Deployment Script
# This script deploys LibreChat to a k3s cluster using Helm 4
# Requires: Helm 4, kubectl, k3s cluster
# Optional: Infisical for secrets management

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="librechat"
RELEASE_NAME="librechat"
CHART_REPO="oci://ghcr.io/danny-avila/librechat-chart/librechat"
VALUES_FILE="../librechat-values.yaml"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LibreChat k3s Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm is not installed or not in PATH${NC}"
    echo "Install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

# Check Helm version
HELM_VERSION=$(helm version --short 2>/dev/null | grep -oP 'v\d+' || echo "unknown")
if [[ "$HELM_VERSION" == "v4" ]]; then
    echo -e "${GREEN}✓ Helm 4 detected${NC}"
elif [[ "$HELM_VERSION" == "v3" ]]; then
    echo -e "${RED}Error: Helm 3 detected. This deployment requires Helm 4.${NC}"
    echo -e "${YELLOW}Please upgrade to Helm 4:${NC}"
    echo -e "${YELLOW}  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash${NC}"
    echo ""
    echo -e "${YELLOW}Note: Your existing Helm 3 releases will work fine with Helm 4 (backward compatible)${NC}"
    exit 1
else
    echo -e "${RED}Error: Unsupported Helm version: $HELM_VERSION${NC}"
    echo -e "${YELLOW}Please install Helm 4:${NC}"
    echo -e "${YELLOW}  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash${NC}"
    exit 1
fi

# Check if cluster is accessible
echo -e "${YELLOW}Checking cluster connectivity...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    echo "Make sure k3s is running and kubectl is configured"
    exit 1
fi
echo -e "${GREEN}✓ Cluster is accessible${NC}"
echo ""

# Step 1: Install prerequisites
echo -e "${YELLOW}Step 1: Checking and installing prerequisites...${NC}"

# Check if nginx ingress controller is installed
if ! kubectl get ingressclass nginx &> /dev/null; then
    echo -e "${YELLOW}Installing nginx ingress controller...${NC}"
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/cloud/deploy.yaml
    echo -e "${GREEN}✓ Nginx ingress controller installed${NC}"
    echo -e "${YELLOW}Waiting for ingress controller to be ready...${NC}"
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=90s
else
    echo -e "${GREEN}✓ Nginx ingress controller already installed${NC}"
fi

# Check if cert-manager is installed
if ! kubectl get namespace cert-manager &> /dev/null; then
    echo -e "${YELLOW}Installing cert-manager...${NC}"
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
    echo -e "${GREEN}✓ cert-manager installed${NC}"
    echo -e "${YELLOW}Waiting for cert-manager to be ready...${NC}"
    kubectl wait --namespace cert-manager \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/instance=cert-manager \
      --timeout=90s
else
    echo -e "${GREEN}✓ cert-manager already installed${NC}"
fi
echo ""

# Step 2: Create namespace
echo -e "${YELLOW}Step 2: Creating namespace...${NC}"
kubectl apply -f ../manifests/namespace.yaml
echo -e "${GREEN}✓ Namespace created${NC}"
echo ""

# Step 3: Apply cert-manager ClusterIssuer
echo -e "${YELLOW}Step 3: Configuring SSL certificate issuer...${NC}"
echo -e "${YELLOW}IMPORTANT: Edit manifests/cert-issuer.yaml to set your email address${NC}"
read -p "Press Enter to continue after editing cert-issuer.yaml, or Ctrl+C to cancel..."
kubectl apply -f ../manifests/cert-issuer.yaml
echo -e "${GREEN}✓ Certificate issuer configured${NC}"
echo ""

# Step 4: Verify Infisical secrets management
echo -e "${YELLOW}Step 4: Verifying Infisical secrets management...${NC}"

# Check if Infisical operator is installed
if ! kubectl get deployment -n infisical-operator-system infisical-operator-controller-manager &> /dev/null; then
    echo -e "${RED}Error: Infisical operator not found${NC}"
    echo ""
    echo -e "${YELLOW}Please install Infisical operator first:${NC}"
    echo "  cd scripts"
    echo "  ./install-infisical-operator.sh"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ Infisical operator detected${NC}"

# Check if InfisicalSecret CRD exists
if ! kubectl get infisicalsecret -n "$NAMESPACE" librechat-credentials &> /dev/null; then
    echo -e "${RED}Error: InfisicalSecret CRD not found${NC}"
    echo ""
    echo -e "${YELLOW}Please complete Infisical setup:${NC}"
    echo ""
    echo "1. Create authentication secret:"
    echo "   kubectl create secret generic infisical-universal-auth \\"
    echo "     --from-literal=clientId=\"<your-client-id>\" \\"
    echo "     --from-literal=clientSecret=\"<your-client-secret>\" \\"
    echo "     --namespace $NAMESPACE"
    echo ""
    echo "2. Update InfisicalSecret CRD:"
    echo "   vim manifests/infisical-secret-crd.yaml"
    echo "   # Set: projectSlug and envSlug"
    echo ""
    echo "3. Apply InfisicalSecret CRD:"
    echo "   kubectl apply -f ../manifests/infisical-secret-crd.yaml"
    echo ""
    echo "See QUICKSTART.md for detailed instructions"
    exit 1
fi
echo -e "${GREEN}✓ InfisicalSecret CRD found${NC}"

# Verify the managed secret is created
echo -e "${YELLOW}Waiting for Infisical to sync secrets (timeout: 60s)...${NC}"
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if kubectl get secret librechat-credentials-env -n "$NAMESPACE" &> /dev/null; then
        echo -e "${GREEN}✓ Secrets synced from Infisical${NC}"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${RED}Error: Secrets not synced from Infisical${NC}"
    echo ""
    echo -e "${YELLOW}Check InfisicalSecret status:${NC}"
    echo "  kubectl describe infisicalsecret librechat-credentials -n $NAMESPACE"
    echo ""
    echo -e "${YELLOW}Common issues:${NC}"
    echo "  - Invalid Client ID/Secret in authentication secret"
    echo "  - Wrong projectSlug or envSlug in InfisicalSecret CRD"
    echo "  - Machine Identity doesn't have access to the project"
    echo "  - Network connectivity issues to Infisical API"
    exit 1
fi
echo ""

# Step 5: Update values file
echo -e "${YELLOW}Step 5: Validating configuration...${NC}"
echo -e "${YELLOW}IMPORTANT: Make sure you've edited librechat-values.yaml with:${NC}"
echo "  - Your domain name (chat.example.com)"
echo "  - MongoDB root password"
echo "  - Any custom endpoint configurations"
echo ""
read -p "Press Enter to continue after editing librechat-values.yaml, or Ctrl+C to cancel..."
echo ""

# Step 6: Add Helm repository
echo -e "${YELLOW}Step 6: Preparing Helm chart...${NC}"
echo -e "${GREEN}✓ Using OCI registry: $CHART_REPO${NC}"
echo ""

# Step 7: Deploy LibreChat
echo -e "${YELLOW}Step 7: Deploying LibreChat...${NC}"
echo "This may take a few minutes..."
echo ""

# Deploy with Helm 4
helm upgrade --install "$RELEASE_NAME" "$CHART_REPO" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  --wait \
  --timeout 10m

echo -e "${GREEN}✓ LibreChat deployed successfully!${NC}"
echo ""

# Step 8: Display status and access information
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get pod status
echo -e "${YELLOW}Pod Status:${NC}"
kubectl get pods -n "$NAMESPACE"
echo ""

# Get service status
echo -e "${YELLOW}Service Status:${NC}"
kubectl get svc -n "$NAMESPACE"
echo ""

# Get ingress status
echo -e "${YELLOW}Ingress Status:${NC}"
kubectl get ingress -n "$NAMESPACE"
echo ""

# Get certificate status
echo -e "${YELLOW}Certificate Status:${NC}"
kubectl get certificate -n "$NAMESPACE" 2>/dev/null || echo "Certificates will be created automatically by cert-manager"
echo ""

# Display access information
DOMAIN=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}')
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Access Information${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}LibreChat URL:${NC} https://$DOMAIN"
echo ""
echo -e "${YELLOW}Note: SSL certificate provisioning may take a few minutes.${NC}"
echo -e "${YELLOW}Check certificate status with:${NC}"
echo "  kubectl describe certificate -n $NAMESPACE"
echo ""

# Display useful commands
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Useful Commands${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "View logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=librechat -f"
echo ""
echo "Check deployment status:"
echo "  kubectl get all -n $NAMESPACE"
echo ""
echo "Update deployment:"
echo "  ./upgrade.sh"
echo ""
echo "Delete deployment:"
echo "  ./cleanup.sh"
echo ""

echo -e "${GREEN}Deployment complete!${NC}"
