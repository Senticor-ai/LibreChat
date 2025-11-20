# Migration Guide: Helm 4 + Infisical Integration

This guide walks you through migrating your LibreChat k3s deployment to use **Helm 4** and **Infisical** for secrets management.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Migration Path](#migration-path)
- [Step 1: Upgrade to Helm 4](#step-1-upgrade-to-helm-4)
- [Step 2: Set Up Infisical](#step-2-set-up-infisical)
- [Step 3: Install Infisical Operator](#step-3-install-infisical-operator)
- [Step 4: Migrate Secrets to Infisical](#step-4-migrate-secrets-to-infisical)
- [Step 5: Update Deployment](#step-5-update-deployment)
- [Step 6: Verify and Clean Up](#step-6-verify-and-clean-up)
- [Rollback Plan](#rollback-plan)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Why Migrate?

**Helm 4 Benefits:**
- ✅ **Server-Side Apply (SSA)**: Better conflict resolution for multi-tool management
- ✅ **WebAssembly Plugins**: Enhanced security and portability
- ✅ **60% Performance Boost**: Faster dependency resolution and chart caching
- ✅ **Improved OCI Support**: Better OAuth and token handling for private registries
- ✅ **kstatus Watcher**: Improved resource status monitoring

**Infisical Benefits:**
- 🔐 **Centralized Secrets Management**: Single source of truth for all environments
- 🔄 **Automatic Rotation**: Update secrets without redeploying
- 👥 **Team Collaboration**: Built-in access controls and audit logs
- 📦 **Version Control**: Track secret changes over time
- 🔗 **GitOps Friendly**: Secrets managed separately from Git
- 🚀 **Auto-Reload**: Automatically restart pods when secrets change

### Migration Complexity

- **Estimated Time**: 30-60 minutes
- **Downtime Required**: None (rolling update)
- **Risk Level**: Low (Helm 3 compatibility maintained, easy rollback)

---

## Prerequisites

### Required

- [ ] **Existing LibreChat deployment** on k3s with Helm 3
- [ ] **kubectl access** to your k3s cluster
- [ ] **Cluster admin permissions**
- [ ] **Backup of current secrets**: `kubectl get secret librechat-credentials-env -n librechat -o yaml > backup-secrets.yaml`

### Optional but Recommended

- [ ] **Infisical account** (Cloud or self-hosted)
- [ ] **Infisical organization** created
- [ ] **Test environment** to validate migration before production

---

## Migration Path

You have two migration options:

### Option A: Helm 4 + Infisical (Recommended)
Full migration to both Helm 4 and Infisical for maximum benefits.

### Option B: Helm 4 Only
Upgrade to Helm 4 while keeping existing Kubernetes secrets.

This guide covers **Option A**. For Option B, skip the Infisical steps.

---

## Step 1: Upgrade to Helm 4

### 1.1 Check Current Helm Version

```bash
helm version --short
```

Expected output: `v3.x.x`

### 1.2 Backup Current Helm Release

```bash
# Backup Helm release configuration
helm get values librechat -n librechat > backup-helm-values.yaml

# Backup all manifests
helm get manifest librechat -n librechat > backup-helm-manifest.yaml
```

### 1.3 Install Helm 4

**Important**: Helm 4 can coexist with Helm 3 temporarily for testing.

```bash
# Download and install Helm 4
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

# Verify installation
helm version --short
```

Expected output: `v4.x.x`

### 1.4 Test Helm 4 Compatibility

Helm 4 maintains backward compatibility with Helm 3 charts and releases.

```bash
# List existing releases (should work without issues)
helm list -n librechat

# Test dry-run upgrade (doesn't actually deploy)
helm upgrade librechat oci://ghcr.io/danny-avila/librechat-chart/librechat \
  --namespace librechat \
  --values librechat-values.yaml \
  --dry-run
```

### 1.5 Breaking Changes to Address

Update any automation or scripts that use deprecated flags:

| **Helm 3 Flag** | **Helm 4 Flag** | **Used in LibreChat?** |
|-----------------|-----------------|------------------------|
| `--atomic` | `--rollback-on-failure` | No (not in default config) |
| `--force` | `--force-replace` | No (not in default config) |
| `helm registry login <full-url>` | `helm registry login <domain>` | Yes (if using private registry) |

**Action Required**: If you use private OCI registries, update login commands:

```bash
# Old (Helm 3):
helm registry login ghcr.io/danny-avila

# New (Helm 4):
helm registry login ghcr.io
```

---

## Step 2: Set Up Infisical

### 2.1 Create Infisical Account

**Option A: Cloud (Easiest)**
1. Go to [https://app.infisical.com](https://app.infisical.com)
2. Sign up for a free account
3. Create an organization

**Option B: Self-Hosted**
1. Deploy Infisical to your infrastructure
2. Follow the [self-hosting guide](https://infisical.com/docs/self-hosting/overview)

### 2.2 Create Infisical Project

1. Log in to Infisical dashboard
2. Click **"Create Project"**
3. Name: `librechat`
4. Select your organization
5. Click **"Create"**

### 2.3 Create Environments

Create environments matching your deployment strategy:

- `dev` (optional)
- `staging` (optional)
- `prod` (required for this guide)

### 2.4 Add Secrets to Infisical

#### Get Current Secrets from Kubernetes

```bash
# Extract current secrets
kubectl get secret librechat-credentials-env -n librechat -o json | \
  jq -r '.data | to_entries[] | "\(.key)=\(.value | @base64d)"' > current-secrets.env
```

#### Import to Infisical

**Via Web UI** (Recommended for first-time):
1. Go to your `librechat` project
2. Select `prod` environment
3. Click **"Add Secret"** for each secret
4. Paste values from `current-secrets.env`

**Via Infisical CLI** (Advanced):
```bash
# Install Infisical CLI
brew install infisical/get-cli/infisical  # macOS
# Or download from: https://infisical.com/docs/cli/overview

# Login
infisical login

# Import secrets
infisical secrets set --env=prod --path=/ --from-file=current-secrets.env
```

#### Required Secrets Checklist

Ensure these are added to Infisical:

**Security (Required):**
- [ ] `CREDS_KEY`
- [ ] `CREDS_IV`
- [ ] `JWT_SECRET`
- [ ] `JWT_REFRESH_SECRET`
- [ ] `MEILI_MASTER_KEY`

**LLM Providers (At least one required):**
- [ ] `OPENAI_API_KEY`
- [ ] `ANTHROPIC_API_KEY` (optional)
- [ ] `GOOGLE_API_KEY` (optional)
- [ ] `AZURE_API_KEY` (optional)

**Optional:**
- [ ] Social login credentials (`GOOGLE_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, etc.)
- [ ] S3 credentials (`S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, etc.)
- [ ] Email credentials (`EMAIL_USERNAME`, `EMAIL_PASSWORD`, etc.)

### 2.5 Create Machine Identity

Machine Identities are service accounts for programmatic access.

1. Go to **Organization Settings** → **Access Control** → **Machine Identities**
2. Click **"Create identity"**
3. Name: `k3s-librechat-operator`
4. Description: `Kubernetes operator for LibreChat secrets`
5. Click **"Create"**

### 2.6 Configure Universal Auth

1. In the Machine Identity, click **"Add authentication method"**
2. Select **"Universal Auth"**
3. **Client ID** and **Client Secret** will be generated
4. **Save these credentials securely** - you'll need them for Kubernetes

**Example:**
```
Client ID: 01234567-89ab-cdef-0123-456789abcdef
Client Secret: st.abc123def456...xyz
```

### 2.7 Grant Project Access

1. Go to your `librechat` project
2. Click **"Settings"** → **"Access Control"**
3. Click **"Add member"**
4. Select the `k3s-librechat-operator` machine identity
5. Role: **"Developer"** or **"Admin"**
6. Click **"Add"**

---

## Step 3: Install Infisical Operator

### 3.1 Run Installation Script

```bash
cd k3s-librechat-deployment/scripts
./install-infisical-operator.sh
```

This script will:
- ✅ Check Helm and kubectl
- ✅ Add Infisical Helm repository
- ✅ Install the operator (cluster-wide or namespace-scoped)
- ✅ Wait for operator to be ready

**Choose installation mode when prompted:**
- **Cluster-wide**: Operator manages all namespaces (easier)
- **Namespace-scoped**: Operator only manages `librechat` namespace (more secure)

Recommended: **Namespace-scoped** for production

### 3.2 Verify Operator Installation

```bash
# Check operator pods
kubectl get pods -n infisical-operator-system

# Expected output:
# NAME                                                      READY   STATUS
# infisical-operator-controller-manager-xxxx                2/2     Running

# Check operator logs
kubectl logs -n infisical-operator-system \
  -l control-plane=controller-manager \
  --tail=50
```

---

## Step 4: Migrate Secrets to Infisical

### 4.1 Create Authentication Secret

Store the Machine Identity credentials in Kubernetes:

```bash
kubectl create secret generic infisical-universal-auth \
  --from-literal=clientId="<YOUR_CLIENT_ID>" \
  --from-literal=clientSecret="<YOUR_CLIENT_SECRET>" \
  --namespace librechat
```

**Replace `<YOUR_CLIENT_ID>` and `<YOUR_CLIENT_SECRET>`** with values from Step 2.6.

### 4.2 Update InfisicalSecret CRD

Edit the InfisicalSecret manifest:

```bash
nano manifests/infisical-secret-crd.yaml
```

**Update these fields:**

```yaml
secretsScope:
  projectSlug: "librechat"  # Your Infisical project slug
  envSlug: "prod"           # Your environment (dev/staging/prod)
  secretsPath: "/"          # Root path (or customize)
```

**For self-hosted Infisical**, also add:

```yaml
hostAPI: "https://your-infisical-domain.com/api"
```

### 4.3 Apply InfisicalSecret CRD

```bash
kubectl apply -f manifests/infisical-secret-crd.yaml
```

### 4.4 Verify Secret Sync

```bash
# Check InfisicalSecret status
kubectl get infisicalsecret -n librechat

# Expected output:
# NAME                    AGE
# librechat-credentials   10s

# Describe for detailed status
kubectl describe infisicalsecret librechat-credentials -n librechat

# Verify managed secret was created
kubectl get secret librechat-credentials-env -n librechat

# Compare with original secret
kubectl get secret librechat-credentials-env -n librechat -o jsonpath='{.data.OPENAI_API_KEY}' | base64 -d
```

**Expected**: The `librechat-credentials-env` secret should now be managed by Infisical and contain the same values.

---

## Step 5: Update Deployment

### 5.1 Update Helm Values

The `librechat-values.yaml` already includes auto-reload annotation for Infisical:

```yaml
podAnnotations:
  secrets.infisical.com/auto-reload: "true"
```

This enables automatic pod restarts when secrets change.

### 5.2 Deploy with New Configuration

```bash
cd scripts
./deploy.sh
```

When prompted:
- **Use Infisical for secrets management?**: `Y`

The script will:
- ✅ Detect Infisical operator
- ✅ Verify InfisicalSecret sync
- ✅ Deploy LibreChat with Helm 4
- ✅ Wait for pods to be ready

### 5.3 Monitor Deployment

```bash
# Watch pod rollout
kubectl rollout status deployment/librechat -n librechat

# View logs
kubectl logs -n librechat -l app.kubernetes.io/name=librechat -f

# Check all resources
kubectl get all -n librechat
```

---

## Step 6: Verify and Clean Up

### 6.1 Verify Application Health

```bash
# Check health endpoint
DOMAIN=$(kubectl get ingress -n librechat -o jsonpath='{.items[0].spec.rules[0].host}')
curl -k https://$DOMAIN/health

# Expected: {"status":"ok"}
```

### 6.2 Test Secret Updates

Test the auto-reload functionality:

1. **Update a secret in Infisical** (e.g., add a test variable `TEST_VAR=hello`)
2. **Wait 60 seconds** (default resync interval)
3. **Check if pod restarted**:

```bash
kubectl get pods -n librechat -w
```

Expected: Pods should restart automatically.

### 6.3 Clean Up Old Secrets (Optional)

**Only after verifying everything works!**

If you created the secret manually (not using Infisical):

```bash
# Backup first
kubectl get secret librechat-credentials-env -n librechat -o yaml > backup-old-secret.yaml

# Delete old manually-created secret (if you want Infisical to be the only source)
# WARNING: Only do this if you're 100% confident Infisical sync is working
# kubectl delete secret librechat-credentials-env -n librechat

# Infisical will recreate it automatically
```

**Note**: The InfisicalSecret CRD with `creationPolicy: Orphan` means the managed secret will persist even if you delete the CRD.

### 6.4 Remove Backup Files

```bash
# Securely delete backup files containing secrets
shred -u current-secrets.env backup-secrets.yaml
# Or on macOS:
rm -P current-secrets.env backup-secrets.yaml
```

---

## Rollback Plan

If anything goes wrong, you can quickly rollback.

### Rollback Infisical to Traditional Secrets

```bash
# 1. Restore original secret
kubectl apply -f backup-secrets.yaml

# 2. Remove InfisicalSecret CRD (secret will persist due to Orphan policy)
kubectl delete infisicalsecret librechat-credentials -n librechat

# 3. Restart pods to use original secret
kubectl rollout restart deployment/librechat -n librechat
```

### Rollback Helm 4 to Helm 3

```bash
# Install Helm 3 (can coexist with Helm 4)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Use Helm 3 explicitly
/usr/local/bin/helm3 upgrade librechat ...
```

### Full Rollback

```bash
# 1. Restore secrets
kubectl apply -f backup-secrets.yaml

# 2. Restore Helm release to previous state
helm rollback librechat 0 -n librechat  # Rollback to previous revision

# 3. Verify
kubectl get pods -n librechat
```

---

## Troubleshooting

### Issue: InfisicalSecret not syncing

**Symptoms:**
- `kubectl get infisicalsecret` shows no resources
- Managed secret not created

**Solution:**

```bash
# Check operator logs
kubectl logs -n infisical-operator-system \
  -l control-plane=controller-manager \
  --tail=100

# Check InfisicalSecret status
kubectl describe infisicalsecret librechat-credentials -n librechat

# Common issues:
# - Invalid Client ID/Secret: Verify authentication secret
# - Wrong project slug: Check Infisical project settings
# - Network issues: Ensure cluster can reach Infisical API
```

### Issue: Secrets not updating in pods

**Symptoms:**
- Secrets updated in Infisical but pods not restarting
- Old values still in environment variables

**Solution:**

```bash
# Check auto-reload annotation
kubectl get deployment librechat -n librechat -o jsonpath='{.spec.template.metadata.annotations}'

# Should include: "secrets.infisical.com/auto-reload":"true"

# Manual restart if needed
kubectl rollout restart deployment/librechat -n librechat

# Reduce resync interval (in infisical-secret-crd.yaml)
# resyncInterval: 30  # Check every 30 seconds instead of 60
```

### Issue: Helm 4 upgrade fails

**Symptoms:**
- `helm upgrade` fails with compatibility errors
- Unknown flags or changed behavior

**Solution:**

```bash
# Check Helm version
helm version

# Use --debug for detailed output
helm upgrade librechat oci://ghcr.io/danny-avila/librechat-chart/librechat \
  --namespace librechat \
  --values librechat-values.yaml \
  --debug

# If post-renderer issues, convert to plugin (see Helm 4 docs)
```

### Issue: Pods in CrashLoopBackOff

**Symptoms:**
- Pods repeatedly crashing after migration
- Application errors in logs

**Solution:**

```bash
# Check pod logs
kubectl logs -n librechat <pod-name>

# Common causes:
# 1. Missing secrets: Verify all required secrets are in Infisical
# 2. Malformed secret values: Check for special characters, newlines
# 3. MongoDB connection: Verify MONGO_URI is correct

# Verify secret contents
kubectl get secret librechat-credentials-env -n librechat -o json | \
  jq -r '.data | keys'

# Should show all expected keys
```

### Issue: Certificate errors with self-hosted Infisical

**Symptoms:**
- `x509: certificate signed by unknown authority`
- Operator can't connect to self-hosted Infisical

**Solution:**

```bash
# Create CA certificate secret
kubectl create secret generic infisical-ca-cert \
  --from-file=ca.crt=/path/to/ca.crt \
  --namespace librechat

# Update infisical-secret-crd.yaml
# tls:
#   caRef:
#     secretName: infisical-ca-cert
#     secretNamespace: librechat
#     key: ca.crt
```

### Getting Help

- **Infisical Documentation**: https://infisical.com/docs
- **Infisical Slack**: https://infisical.com/slack
- **Helm 4 Documentation**: https://helm.sh/docs/
- **LibreChat Discord**: https://discord.librechat.ai

---

## Post-Migration Checklist

- [ ] Application is accessible and functional
- [ ] All LLM providers working (OpenAI, Claude, etc.)
- [ ] User authentication working
- [ ] File uploads working
- [ ] Search functionality working (MeiliSearch)
- [ ] Secrets auto-sync tested (update a secret in Infisical and verify pod restart)
- [ ] SSL certificates valid
- [ ] Backup files securely deleted
- [ ] Team has access to Infisical dashboard
- [ ] Documentation updated with new workflow

---

## Benefits Realized

After successful migration:

✅ **Secrets managed centrally** in Infisical
✅ **Zero-downtime secret updates** with auto-reload
✅ **Audit trail** of all secret changes
✅ **Team collaboration** with granular access controls
✅ **Helm 4 performance improvements** (60% faster)
✅ **Server-Side Apply** for better GitOps workflows
✅ **Future-proof** with WebAssembly plugin support

**Congratulations!** 🎉 Your LibreChat deployment is now running on Helm 4 with Infisical secrets management.
