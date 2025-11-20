#!/bin/bash

# LibreChat Secret Generation Helper
# This script helps generate secure random values for your secrets

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LibreChat Secret Generation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo "This script will generate secure random values for your LibreChat deployment."
echo ""

# Generate values
CREDS_KEY=$(openssl rand -hex 32)
CREDS_IV=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)
MEILI_MASTER_KEY=$(openssl rand -hex 32)

echo -e "${GREEN}Generated secure values:${NC}"
echo ""
echo -e "${YELLOW}Copy these values to your manifests/secret.yaml file:${NC}"
echo ""
echo "CREDS_KEY=$CREDS_KEY"
echo "CREDS_IV=$CREDS_IV"
echo "JWT_SECRET=$JWT_SECRET"
echo "JWT_REFRESH_SECRET=$JWT_REFRESH_SECRET"
echo "MEILI_MASTER_KEY=$MEILI_MASTER_KEY"
echo ""

# Optionally save to a file
read -p "Save these values to secrets.txt? (yes/no): " -r
echo ""

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    cat > secrets.txt <<EOF
# LibreChat Generated Secrets
# Generated on: $(date)
# IMPORTANT: Keep this file secure and never commit it to version control!

CREDS_KEY=$CREDS_KEY
CREDS_IV=$CREDS_IV
JWT_SECRET=$JWT_SECRET
JWT_REFRESH_SECRET=$JWT_REFRESH_SECRET
MEILI_MASTER_KEY=$MEILI_MASTER_KEY

# Add your API keys below:
# OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...
# GOOGLE_API_KEY=...
EOF
    echo -e "${GREEN}✓ Saved to secrets.txt${NC}"
    echo ""
    echo -e "${YELLOW}Remember to:${NC}"
    echo "1. Add your LLM API keys to secrets.txt"
    echo "2. Copy values from secrets.txt to manifests/secret.yaml"
    echo "3. Delete or secure secrets.txt after use"
else
    echo "Values not saved. Copy them from above."
fi

echo ""
echo -e "${GREEN}Done!${NC}"
