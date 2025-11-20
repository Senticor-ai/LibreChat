#!/bin/bash

# LibreChat Status Checker
# Quick overview of deployment status

NAMESPACE="librechat"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LibreChat Deployment Status${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "${RED}Error: Namespace '$NAMESPACE' does not exist${NC}"
    echo "LibreChat is not deployed. Run ./deploy.sh to deploy."
    exit 1
fi

# Helm release status
echo -e "${YELLOW}Helm Release:${NC}"
helm list -n $NAMESPACE
echo ""

# Pods
echo -e "${YELLOW}Pods:${NC}"
kubectl get pods -n $NAMESPACE
echo ""

# Services
echo -e "${YELLOW}Services:${NC}"
kubectl get svc -n $NAMESPACE
echo ""

# Ingress
echo -e "${YELLOW}Ingress:${NC}"
kubectl get ingress -n $NAMESPACE
echo ""

# Certificates
echo -e "${YELLOW}SSL Certificates:${NC}"
if kubectl get certificate -n $NAMESPACE &> /dev/null; then
    kubectl get certificate -n $NAMESPACE
else
    echo "No certificates found (will be created automatically)"
fi
echo ""

# PVCs
echo -e "${YELLOW}Persistent Volume Claims:${NC}"
kubectl get pvc -n $NAMESPACE
echo ""

# Resource usage (if metrics-server is installed)
if kubectl top pods -n $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}Resource Usage:${NC}"
    kubectl top pods -n $NAMESPACE
    echo ""
fi

# Recent events
echo -e "${YELLOW}Recent Events (last 10):${NC}"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10
echo ""

# Access URL
DOMAIN=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null)
if [ ! -z "$DOMAIN" ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Access URL:${NC} https://$DOMAIN"
    echo -e "${GREEN}========================================${NC}"
fi
