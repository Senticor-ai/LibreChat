#!/bin/bash

# LibreChat Logs Viewer
# Quick access to logs from different components

NAMESPACE="librechat"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LibreChat Logs Viewer${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo "Select logs to view:"
echo "  1. LibreChat application"
echo "  2. MongoDB"
echo "  3. MeiliSearch"
echo "  4. All pods (combined)"
echo "  5. Previous pod logs (for crashed pods)"
echo ""
read -p "Select option (1-5): " -r OPTION
echo ""

case $OPTION in
    1)
        echo -e "${YELLOW}Viewing LibreChat logs (Ctrl+C to exit)...${NC}"
        kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=librechat -f --tail=100
        ;;
    2)
        echo -e "${YELLOW}Viewing MongoDB logs (Ctrl+C to exit)...${NC}"
        kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=mongodb -f --tail=100
        ;;
    3)
        echo -e "${YELLOW}Viewing MeiliSearch logs (Ctrl+C to exit)...${NC}"
        kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=meilisearch -f --tail=100
        ;;
    4)
        echo -e "${YELLOW}Viewing all pod logs (Ctrl+C to exit)...${NC}"
        kubectl logs -n $NAMESPACE --all-containers=true -f --tail=50
        ;;
    5)
        echo -e "${YELLOW}Available pods:${NC}"
        kubectl get pods -n $NAMESPACE
        echo ""
        read -p "Enter pod name: " -r POD_NAME
        echo -e "${YELLOW}Viewing previous logs for $POD_NAME...${NC}"
        kubectl logs -n $NAMESPACE $POD_NAME --previous
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac
