#!/bin/bash

# LibreChat k3s Cleanup Script
# This script removes LibreChat from a k3s cluster

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="librechat"
RELEASE_NAME="librechat"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}LibreChat k3s Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

echo -e "${RED}WARNING: This will delete the LibreChat deployment and all associated data!${NC}"
echo -e "${RED}This includes:${NC}"
echo "  - All conversations and messages"
echo "  - All uploaded files"
echo "  - All user accounts"
echo "  - Database data (unless using external database)"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm is not installed or not in PATH${NC}"
    exit 1
fi

# Step 1: Uninstall Helm release
echo -e "${YELLOW}Step 1: Uninstalling Helm release...${NC}"
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
    echo -e "${GREEN}✓ Helm release uninstalled${NC}"
else
    echo -e "${YELLOW}Helm release not found, skipping...${NC}"
fi
echo ""

# Step 2: Delete secrets
echo -e "${YELLOW}Step 2: Deleting secrets...${NC}"
kubectl delete secret librechat-credentials-env -n "$NAMESPACE" --ignore-not-found=true
echo -e "${GREEN}✓ Secrets deleted${NC}"
echo ""

# Step 3: Delete PVCs (optional)
echo -e "${YELLOW}Step 3: Checking for persistent volume claims...${NC}"
if kubectl get pvc -n "$NAMESPACE" 2>/dev/null | grep -q .; then
    echo -e "${YELLOW}Found PVCs in namespace $NAMESPACE:${NC}"
    kubectl get pvc -n "$NAMESPACE"
    echo ""
    read -p "Do you want to delete persistent volume claims (this will delete all data)? (yes/no): " -r
    echo ""
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        kubectl delete pvc --all -n "$NAMESPACE"
        echo -e "${GREEN}✓ PVCs deleted${NC}"
    else
        echo -e "${YELLOW}Keeping PVCs (data preserved)${NC}"
    fi
else
    echo -e "${GREEN}✓ No PVCs found${NC}"
fi
echo ""

# Step 4: Delete namespace
echo -e "${YELLOW}Step 4: Deleting namespace...${NC}"
read -p "Do you want to delete the namespace '$NAMESPACE'? (yes/no): " -r
echo ""
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
    echo -e "${GREEN}✓ Namespace deleted${NC}"
else
    echo -e "${YELLOW}Keeping namespace${NC}"
fi
echo ""

# Step 5: Optional cleanup of prerequisites
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Optional: Cleanup Prerequisites${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "The following components may be used by other applications:"
echo "  - nginx ingress controller"
echo "  - cert-manager"
echo "  - Certificate issuers"
echo ""
read -p "Do you want to remove these components? (yes/no): " -r
echo ""

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Removing certificate issuers...${NC}"
    kubectl delete clusterissuer letsencrypt-staging letsencrypt-prod --ignore-not-found=true

    echo -e "${YELLOW}Removing cert-manager...${NC}"
    kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml --ignore-not-found=true

    echo -e "${YELLOW}Removing nginx ingress controller...${NC}"
    kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/cloud/deploy.yaml --ignore-not-found=true

    echo -e "${GREEN}✓ Prerequisites removed${NC}"
else
    echo -e "${YELLOW}Keeping prerequisites${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "LibreChat has been removed from your cluster."
echo ""
echo "To redeploy, run: ./deploy.sh"
