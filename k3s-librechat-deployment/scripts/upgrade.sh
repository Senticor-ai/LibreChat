#!/bin/bash

# LibreChat k3s Upgrade Script
# This script upgrades an existing LibreChat deployment

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="librechat"
RELEASE_NAME="librechat"
CHART_REPO="oci://ghcr.io/danny-avila/librechat-chart/librechat"
VALUES_FILE="../librechat-values.yaml"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LibreChat k3s Upgrade${NC}"
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
    exit 1
fi

# Check if release exists
if ! helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    echo -e "${RED}Error: Release '$RELEASE_NAME' not found in namespace '$NAMESPACE'${NC}"
    echo "Run ./deploy.sh to create a new deployment"
    exit 1
fi

# Display current version
echo -e "${YELLOW}Current deployment:${NC}"
helm list -n "$NAMESPACE" -o yaml | grep -E "name:|chart:|app_version:" | head -6
echo ""

# Upgrade options
echo "Upgrade options:"
echo "  1. Upgrade to latest chart version"
echo "  2. Upgrade to specific chart version"
echo "  3. Apply configuration changes only (no chart upgrade)"
echo ""
read -p "Select option (1-3): " -r OPTION
echo ""

case $OPTION in
    1)
        echo -e "${YELLOW}Upgrading to latest chart version...${NC}"
        helm upgrade "$RELEASE_NAME" "$CHART_REPO" \
          --namespace "$NAMESPACE" \
          --values "$VALUES_FILE" \
          --wait \
          --timeout 10m
        ;;
    2)
        read -p "Enter chart version (e.g., 1.0.0): " -r VERSION
        echo -e "${YELLOW}Upgrading to chart version $VERSION...${NC}"
        helm upgrade "$RELEASE_NAME" "$CHART_REPO" \
          --version "$VERSION" \
          --namespace "$NAMESPACE" \
          --values "$VALUES_FILE" \
          --wait \
          --timeout 10m
        ;;
    3)
        echo -e "${YELLOW}Applying configuration changes...${NC}"
        helm upgrade "$RELEASE_NAME" "$CHART_REPO" \
          --namespace "$NAMESPACE" \
          --values "$VALUES_FILE" \
          --reuse-values \
          --wait \
          --timeout 10m
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}✓ Upgrade complete!${NC}"
echo ""

# Display updated deployment info
echo -e "${YELLOW}Updated deployment:${NC}"
helm list -n "$NAMESPACE" -o yaml | grep -E "name:|chart:|app_version:" | head -6
echo ""

# Check pod status
echo -e "${YELLOW}Pod status:${NC}"
kubectl get pods -n "$NAMESPACE"
echo ""

# Display rollout status
echo -e "${YELLOW}Checking rollout status...${NC}"
kubectl rollout status deployment -n "$NAMESPACE" -l app.kubernetes.io/name=librechat --timeout=5m
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Upgrade Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}LibreChat has been upgraded successfully!${NC}"
echo ""

# Useful commands
echo -e "${YELLOW}Useful commands:${NC}"
echo ""
echo "View logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=librechat -f"
echo ""
echo "Rollback to previous version:"
echo "  helm rollback $RELEASE_NAME -n $NAMESPACE"
echo ""
echo "View release history:"
echo "  helm history $RELEASE_NAME -n $NAMESPACE"
echo ""
