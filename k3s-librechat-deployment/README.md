# LibreChat k3s Deployment Guide

This directory contains everything you need to deploy LibreChat on a k3s Kubernetes cluster with automatic SSL certificates, persistent storage, and production-ready configuration.

## Table of Contents

- [Deployment Options](#deployment-options)
  - [Option 1: Automated Bootstrap (Recommended)](#option-1-automated-bootstrap-recommended)
  - [Option 2: Manual Setup](#option-2-manual-setup)
- [Local Testing with k3d](#local-testing-with-k3d)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Secrets Management](#secrets-management-with-self-hosted-infisical)
- [Detailed Setup](#detailed-setup)
- [Configuration](#configuration)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)
- [Migration Guide](#migration-guide)

## Deployment Options

Choose the deployment method that works best for you:

### Option 1: Automated Bootstrap (Recommended)

**For most users** - One-command deployment with interactive prompts.

#### Local Testing (k3d)

Test the complete stack on your laptop before deploying to production:

```bash
# Create k3d cluster
k3d cluster create librechat-test --agents 1 -p "30080:30080@loadbalancer"

# Run automated bootstrap
cd scripts
./bootstrap-local.sh

# Access at http://chat.127.0.0.1.nip.io:30080
```

**Deploys**: Self-hosted Infisical + LibreChat + all dependencies
**Time**: 10-15 minutes
**Requires**: Docker, k3d, kubectl
**See**: [TESTING.md](TESTING.md) for detailed guide

#### Production Deployment (Linux Server)

Deploy to your production server with automated configuration:

```bash
# SSH into your server, clone repo
git clone <your-repo-url>
cd LibreChat/k3s-librechat-deployment/scripts

# Run production bootstrap
./bootstrap-production.sh

# Follow interactive prompts for:
# - Domain names (infisical.example.com, chat.example.com)
# - SSL certificate email
# - API keys (OpenAI, Anthropic, etc.)
# - Infisical setup (guided through web UI)

# Access at https://chat.yourdomain.com
```

**What it does**:
- ✅ Installs k3s (if not present)
- ✅ Installs Helm 4
- ✅ Deploys nginx-ingress and cert-manager
- ✅ Deploys self-hosted Infisical with SSL
- ✅ Installs Infisical Operator
- ✅ Deploys LibreChat with auto-secret sync
- ✅ Configures Let's Encrypt SSL certificates
- ✅ Auto-generates all secrets

**Time**: 20-30 minutes
**Requires**: Linux server, 2 domains, sudo access

### Option 2: Manual Setup

**For advanced users** who want full control over each step.

See [Detailed Setup](#detailed-setup) below for step-by-step manual configuration.

---

## Local Testing with k3d

**Before deploying to production**, test locally with k3d (k3s in Docker):

```bash
# 1. Install k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# 2. Create test cluster
k3d cluster create librechat-test --agents 1 -p "30080:30080@loadbalancer"

# 3. Run bootstrap
cd k3s-librechat-deployment/scripts
./bootstrap-local.sh

# 4. Test at http://chat.127.0.0.1.nip.io:30080
```

**Full testing guide**: [TESTING.md](TESTING.md)

**Benefits**:
- Test complete deployment flow
- Validate configuration before production
- Learn the system safely
- No cloud costs
- Deploy/test/iterate in minutes

---

## Prerequisites

### Required

- **k3s cluster** running and accessible via `kubectl`
  - k3s installation: `curl -sfL https://get.k3s.io | sh -`
  - Verify: `kubectl get nodes`

- **Helm 4** installed
  - Install: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash`
  - Verify: `helm version`
  - Should show v4.x.x

- **Domain name** pointing to your k3s cluster's external IP
  - Required for SSL/TLS certificates via Let's Encrypt

- **At least one LLM API key** (OpenAI, Anthropic, Google, etc.)

- **Domain names** for Infisical and LibreChat
  - Example: `infisical.yourdomain.com` and `chat.yourdomain.com`
  - Both should point to your k3s cluster's external IP

### Optional

- **kubectl** autocomplete for easier management
  ```bash
  source <(kubectl completion bash)
  echo "source <(kubectl completion bash)" >> ~/.bashrc
  ```

## Quick Start

If you're familiar with Kubernetes and just want to get started quickly:

```bash
cd k3s-librechat-deployment

# 1. Configure Infisical secrets and deployment
vim manifests/infisical-standalone-secret.yaml    # Set AUTH_SECRET, ENCRYPTION_KEY, SITE_URL
vim manifests/infisical-standalone-values.yaml    # Set host, PostgreSQL/Redis passwords

# 2. Deploy Infisical to k3s
cd scripts
./install-infisical.sh

# 3. Set up Infisical (see detailed instructions in QUICKSTART.md)
#    - Access https://infisical.yourdomain.com
#    - Create account and organization
#    - Create project "librechat" with "prod" environment
#    - Add all required secrets (OPENAI_API_KEY, JWT_SECRET, etc.)
#    - Create Machine Identity with Universal Auth
#    - Copy Client ID and Client Secret

# 4. Install Infisical Operator
./install-infisical-operator.sh

# 5. Create Kubernetes authentication secret
kubectl create secret generic infisical-universal-auth \
  --from-literal=clientId="<your-client-id>" \
  --from-literal=clientSecret="<your-client-secret>" \
  --namespace librechat

# 6. Configure InfisicalSecret CRD
vim ../manifests/infisical-secret-crd.yaml  # Set projectSlug and envSlug
kubectl apply -f ../manifests/infisical-secret-crd.yaml

# 7. Configure domain
vim ../librechat-values.yaml  # Replace chat.example.com with your domain

# 8. Deploy LibreChat!
./deploy.sh
```

Your Infisical instance will be available at `https://infisical.yourdomain.com` in ~10 minutes.
Your LibreChat instance will be available at `https://chat.yourdomain.com` in ~10 minutes.

## Secrets Management with Self-Hosted Infisical

This deployment uses **Infisical** self-hosted on your k3s cluster for production-grade secrets management. All sensitive credentials (API keys, JWT secrets, etc.) are managed through Infisical.

### Why Self-Hosted Infisical?

- ✅ **Centralized secrets management** across environments
- ✅ **Auto-rotation** with automatic pod restarts
- ✅ **Audit logs** of all secret changes
- ✅ **Team collaboration** with granular access controls
- ✅ **Version control** for secrets
- ✅ **Zero-downtime updates**
- ✅ **Fully private** - no cloud dependencies
- ✅ **Single k3s cluster** - everything in one place

### Architecture

```
k3s Cluster
├── Infisical (namespace: infisical)
│   ├── Infisical App (secrets management UI/API)
│   ├── PostgreSQL (secrets database)
│   └── Redis (caching)
├── Infisical Operator (namespace: infisical-operator-system)
│   └── Syncs secrets from Infisical to Kubernetes
└── LibreChat (namespace: librechat)
    ├── LibreChat App (uses synced secrets)
    ├── MongoDB
    └── MeiliSearch
```

### Quick Setup

```bash
cd scripts

# 1. Deploy Infisical to k3s
./install-infisical.sh

# 2. Access Infisical web UI and:
#    - Create your account
#    - Create organization
#    - Create project named "librechat"
#    - Add secrets in "prod" environment
#    - Create Machine Identity with Universal Auth

# 3. Install Infisical Operator for secret sync
./install-infisical-operator.sh

# 4. Create Kubernetes auth secret
kubectl create secret generic infisical-universal-auth \
  --from-literal=clientId="<your-client-id>" \
  --from-literal=clientSecret="<your-client-secret>" \
  --namespace librechat

# 5. Configure and apply InfisicalSecret CRD
vim ../manifests/infisical-secret-crd.yaml
kubectl apply -f ../manifests/infisical-secret-crd.yaml

# 6. Deploy LibreChat
./deploy.sh
```

**Documentation:**
- Self-Hosting Guide: https://infisical.com/docs/self-hosting/deployment-options/kubernetes-helm

## Detailed Setup

### Step 1: Deploy Self-Hosted Infisical

1. **Configure Infisical Secrets**:

   Edit the Infisical secrets file:
   ```bash
   vim manifests/infisical-standalone-secret.yaml
   ```

   Generate and update these required values:
   ```bash
   # Generate AUTH_SECRET
   openssl rand -base64 32

   # Generate ENCRYPTION_KEY
   openssl rand -hex 16
   ```

   Update in `infisical-standalone-secret.yaml`:
   - `AUTH_SECRET` - Use the base64 value generated above
   - `ENCRYPTION_KEY` - Use the hex value generated above
   - `SITE_URL` - Set to your Infisical domain (e.g., `https://infisical.yourdomain.com`)

2. **Configure Infisical Deployment**:

   Edit the Infisical values file:
   ```bash
   vim manifests/infisical-standalone-values.yaml
   ```

   Update these fields:
   - Line 38: `host: infisical.yourdomain.com` (your Infisical domain)
   - Line 51: `password:` Generate with `openssl rand -base64 32` (PostgreSQL password)
   - Line 73: `password:` Generate with `openssl rand -base64 32` (Redis password)

3. **Deploy Infisical to k3s**:

   Run the installation script:
   ```bash
   cd scripts
   ./install-infisical.sh
   ```

   The script will:
   - Check prerequisites (Helm 4, kubectl)
   - Add Infisical Helm repository
   - Create `infisical` namespace
   - Deploy Infisical with PostgreSQL and Redis
   - Wait for pods to be ready
   - Display access information

   **Deployment time:** ~5 minutes
   **SSL provisioning:** Additional 5-10 minutes for Let's Encrypt

4. **Access Infisical Web UI**:

   Once deployed, access your Infisical instance at `https://infisical.yourdomain.com`

   Check certificate status:
   ```bash
   kubectl get certificate -n infisical
   ```

5. **Create Infisical Account & Project**:

   - **Create account**: Open `https://infisical.yourdomain.com` and sign up
   - **Create organization**: Follow the setup wizard
   - **Create project**: Name it `librechat`
   - The `prod` environment is created by default

6. **Add LibreChat Secrets in Infisical**:

   Generate secure values for LibreChat:
   ```bash
   # Security credentials
   openssl rand -hex 32  # Use for CREDS_KEY
   openssl rand -hex 16  # Use for CREDS_IV
   openssl rand -hex 32  # Use for JWT_SECRET
   openssl rand -hex 32  # Use for JWT_REFRESH_SECRET
   openssl rand -hex 32  # Use for MEILI_MASTER_KEY
   ```

   In the Infisical web UI (prod environment), add these secrets:
   - `CREDS_KEY` - Encryption key (generated above)
   - `CREDS_IV` - Initialization vector (generated above)
   - `JWT_SECRET` - JWT signing secret (generated above)
   - `JWT_REFRESH_SECRET` - JWT refresh secret (generated above)
   - `MEILI_MASTER_KEY` - MeiliSearch master key (generated above)
   - `OPENAI_API_KEY` - Your OpenAI API key (sk-...)
   - Optional: `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, etc.

7. **Create Machine Identity**:
   - Go to Organization Settings → Access Control → Machine Identities
   - Click "Create identity"
   - Name: `k3s-librechat-operator`
   - Description: "Kubernetes operator for LibreChat secrets"
   - Click "Create"

8. **Configure Universal Auth**:
   - In the Machine Identity, click "Add authentication method"
   - Select "Universal Auth"
   - **Save the Client ID and Client Secret** - you'll need these in Step 3

9. **Grant Project Access**:
   - Go to your `librechat` project
   - Click Settings → Access Control
   - Click "Add member"
   - Select the `k3s-librechat-operator` machine identity
   - Role: "Developer" or "Admin"
   - Click "Add"

### Step 2: Install Infisical Operator

Run the installation script:

```bash
cd scripts
./install-infisical-operator.sh
```

When prompted, choose **namespace-scoped** mode (recommended for production).

The script will:
- Check prerequisites (Helm 4, kubectl)
- Add Infisical Helm repository
- Install the operator
- Wait for operator to be ready

### Step 3: Connect Kubernetes to Infisical

Create the authentication secret with your Machine Identity credentials:

```bash
kubectl create secret generic infisical-universal-auth \
  --from-literal=clientId="<your-client-id>" \
  --from-literal=clientSecret="<your-client-secret>" \
  --namespace librechat
```

### Step 4: Configure InfisicalSecret CRD

Edit the InfisicalSecret manifest:

```bash
vim manifests/infisical-secret-crd.yaml
```

Update these fields:
```yaml
secretsScope:
  projectSlug: "librechat"  # Your Infisical project slug
  envSlug: "prod"           # Your environment (dev/staging/prod)
  secretsPath: "/"          # Root path
```

Apply the configuration:
```bash
kubectl apply -f manifests/infisical-secret-crd.yaml
```

Verify secrets are syncing:
```bash
# Check InfisicalSecret status
kubectl get infisicalsecret -n librechat
kubectl describe infisicalsecret librechat-credentials -n librechat

# Verify managed secret was created
kubectl get secret librechat-credentials-env -n librechat
```

### Step 5: Configure Your Deployment

Edit `librechat-values.yaml` and update:

1. **Domain Configuration**:
   ```yaml
   # Find and replace all instances of chat.example.com
   DOMAIN_CLIENT: "https://chat.yourdomain.com"
   DOMAIN_SERVER: "https://chat.yourdomain.com"
   ```

2. **SSL Certificate Email** (in `manifests/cert-issuer.yaml`):
   ```yaml
   email: admin@yourdomain.com  # For Let's Encrypt notifications
   ```

3. **MongoDB Password** (optional, line 206):
   ```yaml
   mongodb:
     auth:
       rootPassword: "your-secure-mongodb-password"
   ```

4. **Optional Customizations:**
   - Adjust resource limits (CPU, memory)
   - Enable autoscaling
   - Configure additional LLM endpoints
   - Add MCP server configurations
   - Configure file storage (S3, Firebase)

### Step 6: Deploy

Run the deployment script:

```bash
cd scripts
./deploy.sh
```

The script will:
1. ✓ Check cluster connectivity
2. ✓ Install nginx ingress controller (if not present)
3. ✓ Install cert-manager (if not present)
4. ✓ Create namespace
5. ✓ Configure SSL certificate issuer
6. ✓ Create secrets
7. ✓ Deploy LibreChat with Helm
8. ✓ Wait for all pods to be ready
9. ✓ Display access information

**Expected deployment time:** 5-10 minutes

### Step 7: Verify Deployment

Check that all components are running:

```bash
# View all resources
kubectl get all -n librechat

# Check pods status (should all be Running)
kubectl get pods -n librechat

# Check ingress and certificates
kubectl get ingress,certificate -n librechat

# View logs
kubectl logs -n librechat -l app.kubernetes.io/name=librechat -f
```

### Step 8: Access LibreChat

Once deployed, access your instance at `https://your-domain.com`

**First-time setup:**
1. Click "Sign up" to create your admin account
2. After creating the first account, consider setting `ALLOW_REGISTRATION: "false"` in `librechat-values.yaml` to disable public registration
3. Configure your preferred LLM models in the UI

## Configuration

### Environment Variables

All environment variables are managed through **Infisical** and automatically synced to Kubernetes. See [examples/.env.example](examples/.env.example) for a complete list of available options.

**Key variables (set in Infisical):**
- `CREDS_KEY`, `CREDS_IV` - Encryption keys
- `JWT_SECRET`, `JWT_REFRESH_SECRET` - Authentication
- `MEILI_MASTER_KEY` - MeiliSearch authentication
- `OPENAI_API_KEY` - OpenAI access
- `ANTHROPIC_API_KEY` - Anthropic Claude access
- `GOOGLE_API_KEY` - Google Gemini access

To add or update variables:
1. Go to your Infisical web UI (`https://infisical.yourdomain.com`)
2. Navigate to `librechat` project → `prod` environment
3. Add/update secrets
4. Save - changes sync automatically within 60 seconds

### LibreChat Configuration

Advanced configuration is done via the `configYamlContent` section in `librechat-values.yaml`.

See [examples/librechat-config.example.yaml](examples/librechat-config.example.yaml) for examples of:
- Custom endpoint configurations
- MCP server setup
- File storage strategies
- Rate limiting
- Social authentication
- UI customization

Full documentation: https://www.librechat.ai/docs/configuration/librechat_yaml

### Resource Allocation

Default resource requests/limits in `librechat-values.yaml`:

**LibreChat:**
- Requests: 500m CPU, 1Gi memory
- Limits: 2000m CPU, 4Gi memory

**MongoDB:**
- Requests: 500m CPU, 1Gi memory
- Limits: 2000m CPU, 2Gi memory

**MeiliSearch:**
- Requests: 250m CPU, 512Mi memory
- Limits: 1000m CPU, 1Gi memory

Adjust based on your usage patterns and available resources.

### Persistent Storage

k3s uses local-path storage by default. Data is stored in:
- MongoDB: 50Gi persistent volume
- MeiliSearch: 20Gi persistent volume
- Images/Files: 50Gi persistent volume

**To use a different storage class:**
```yaml
librechat:
  imageVolume:
    storageClassName: "your-storage-class"

mongodb:
  persistence:
    storageClass: "your-storage-class"

meilisearch:
  persistence:
    storageClass: "your-storage-class"
```

## Maintenance

### Upgrading LibreChat

To upgrade to the latest version:

```bash
cd scripts
./upgrade.sh
```

Options:
1. Upgrade to latest chart version
2. Upgrade to specific chart version
3. Apply configuration changes only

### Viewing Logs

```bash
# All LibreChat logs
kubectl logs -n librechat -l app.kubernetes.io/name=librechat -f

# Specific pod
kubectl logs -n librechat <pod-name> -f

# MongoDB logs
kubectl logs -n librechat -l app.kubernetes.io/name=mongodb -f

# MeiliSearch logs
kubectl logs -n librechat -l app.kubernetes.io/name=meilisearch -f
```

### Backing Up Data

**MongoDB backup:**
```bash
kubectl exec -n librechat <mongodb-pod-name> -- mongodump --archive > backup.archive
```

**Restore:**
```bash
kubectl exec -i -n librechat <mongodb-pod-name> -- mongorestore --archive < backup.archive
```

**Files backup:**
```bash
kubectl cp librechat/<librechat-pod-name>:/app/client/public/images ./images-backup
```

### Scaling

**Manual scaling:**
```yaml
# In librechat-values.yaml
replicaCount: 3
```

**Autoscaling:**
```yaml
# In librechat-values.yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 80
```

Then run:
```bash
./upgrade.sh
```

### Updating Secrets

With Infisical, secrets are automatically synced and pods auto-restart on changes:

1. **Update secrets in Infisical Web UI**:
   - Access your Infisical instance at `https://infisical.yourdomain.com`
   - Navigate to your `librechat` project → `prod` environment
   - Add, update, or delete secrets as needed
   - Click "Save changes"

2. **Automatic synchronization**:
   - The Infisical Operator syncs secrets every 60 seconds (configurable)
   - LibreChat pods automatically restart when secrets change (thanks to `auto-reload` annotation)
   - **No manual kubectl commands needed!**

3. **Verify secret sync**:
   ```bash
   # Check InfisicalSecret status
   kubectl get infisicalsecret -n librechat
   kubectl describe infisicalsecret librechat-credentials -n librechat

   # View synced Kubernetes secret (base64 encoded)
   kubectl get secret librechat-credentials-env -n librechat -o yaml

   # Check pod restart status
   kubectl get pods -n librechat -l app.kubernetes.io/name=librechat
   ```

4. **Manual sync (if needed)**:
   ```bash
   # Force immediate secret sync by deleting the managed secret
   kubectl delete secret librechat-credentials-env -n librechat
   # Infisical Operator will recreate it immediately
   ```

### SSL Certificate Renewal

Let's Encrypt certificates auto-renew via cert-manager. No action required!

**Check certificate status:**
```bash
kubectl describe certificate -n librechat
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status and events
kubectl describe pod -n librechat <pod-name>

# View recent events
kubectl get events -n librechat --sort-by='.lastTimestamp'
```

Common issues:
- **ImagePullBackOff:** Network issues or image not available
- **CrashLoopBackOff:** Configuration error, check logs
- **Pending:** Resource constraints or PV issues

### Certificate Issues

```bash
# Check certificate status
kubectl describe certificate -n librechat

# Check certificate request
kubectl describe certificaterequest -n librechat

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f
```

Common issues:
- DNS not pointing to cluster IP
- Firewall blocking port 80 (required for HTTP-01 challenge)
- Rate limiting from Let's Encrypt (use staging issuer for testing)

### Connection Issues

```bash
# Check ingress
kubectl describe ingress -n librechat

# Check service
kubectl get svc -n librechat

# Test internal connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -n librechat -- wget -O- http://librechat:3080/health
```

### Database Issues

```bash
# Check MongoDB logs
kubectl logs -n librechat -l app.kubernetes.io/name=mongodb

# Connect to MongoDB
kubectl exec -it -n librechat <mongodb-pod-name> -- mongosh

# Check database
use LibreChat
db.stats()
```

### Performance Issues

```bash
# Check resource usage
kubectl top pods -n librechat

# Check node resources
kubectl top nodes

# View detailed pod metrics
kubectl describe pod -n librechat <pod-name> | grep -A 5 "Limits\|Requests"
```

## Advanced Topics

### Using External MongoDB

To use an external MongoDB instance instead of the bundled one:

1. In `librechat-values.yaml`:
   ```yaml
   mongodb:
     enabled: false

   librechat:
     configEnv:
       MONGO_URI: "mongodb://user:password@external-mongo:27017/LibreChat?authSource=admin"
   ```

2. Update secret with MongoDB credentials if needed

### Using External Redis

For improved performance with multiple replicas:

1. Add to your secret:
   ```yaml
   REDIS_URI: "redis://redis.example.com:6379"
   ```

2. In `librechat-values.yaml`:
   ```yaml
   librechat:
     configEnv:
       # Redis will be automatically used if REDIS_URI is set
   ```

### Custom MCP Backend

To add your own MCP (Model Context Protocol) server:

1. Deploy your MCP server to k3s
2. In `librechat-values.yaml`:
   ```yaml
   librechat:
     configYamlContent: |
       mcpServers:
         my-backend:
           url: "http://mcp-service.mcp-namespace.svc.cluster.local:8080"
           name: "My Backend"
           description: "Custom MCP backend"
   ```

### S3 File Storage

To use S3 for file storage:

1. Add S3 credentials to `manifests/secret.yaml`:
   ```yaml
   S3_ENDPOINT: "s3.amazonaws.com"
   S3_REGION: "us-east-1"
   S3_ACCESS_KEY_ID: "your-access-key"
   S3_SECRET_ACCESS_KEY: "your-secret-key"
   S3_BUCKET: "librechat-files"
   ```

2. In `librechat-values.yaml`:
   ```yaml
   librechat:
     configYamlContent: |
       fileStrategy:
         avatar: "s3"
         image: "s3"
         document: "s3"
   ```

### High Availability Setup

For production HA deployment:

```yaml
# In librechat-values.yaml
replicaCount: 3

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

# Use external managed services
mongodb:
  enabled: false  # Use MongoDB Atlas or managed MongoDB

librechat:
  configEnv:
    MONGO_URI: "mongodb+srv://user:pass@cluster.mongodb.net/LibreChat"
    REDIS_URI: "redis://managed-redis:6379"

# Enable pod anti-affinity
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - librechat
          topologyKey: kubernetes.io/hostname
```

### Monitoring

To add Prometheus monitoring:

```yaml
# In librechat-values.yaml
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "3080"
  prometheus.io/path: "/metrics"
```

### Custom Domain for Each User

For multi-tenant setups with custom domains:

1. Use a wildcard certificate:
   ```yaml
   # In manifests/cert-issuer.yaml
   spec:
     dnsNames:
       - "*.yourdomain.com"
   ```

2. Configure ingress for wildcard:
   ```yaml
   # In librechat-values.yaml
   ingress:
     hosts:
       - host: "*.yourdomain.com"
   ```

## Cleanup

To completely remove LibreChat from your cluster:

```bash
cd scripts
./cleanup.sh
```

This will:
1. Remove Helm release
2. Delete secrets
3. Optionally delete persistent volumes (asks for confirmation)
4. Optionally delete namespace
5. Optionally remove prerequisites (nginx, cert-manager)

## Migration Guide

### Migrating to Helm 4 + Infisical

If you have an existing LibreChat deployment and want to:
- **Upgrade to Helm 4** for performance improvements and modern features
- **Migrate to Infisical** for centralized secrets management

See our comprehensive **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)** for step-by-step instructions.

**Key Benefits:**
- 🚀 **60% faster** chart operations with Helm 4
- 🔐 **Zero-downtime secret updates** with Infisical auto-reload
- 📊 **Full audit trail** of all secret changes
- 👥 **Team collaboration** with granular access controls
- 🔄 **Automatic secret rotation** without manual pod restarts

**Estimated Migration Time**: 30-60 minutes with zero downtime

### Helm 4 Features

Helm 4 (released November 2025) brings significant improvements:

- **Server-Side Apply (SSA)**: Better conflict resolution when multiple tools manage resources
- **WebAssembly Plugins**: Enhanced security with sandboxed plugin execution
- **Performance**: 60% faster dependency resolution and chart caching
- **OCI Enhancements**: Improved OAuth and token support for private registries
- **kstatus Watcher**: Better resource health monitoring

**Key Changes from Helm 3:**
- CLI flags renamed: `--atomic` → `--rollback-on-failure`, `--force` → `--force-replace`
- Registry login requires domain only: `helm registry login ghcr.io` (not full URL)
- Post-renderers must be plugins (not direct executables)
- All existing Helm 3 charts work seamlessly - zero conversion required

## Support

- **Documentation:** https://docs.librechat.ai
- **GitHub Issues:** https://github.com/danny-avila/LibreChat/issues
- **Discord:** https://discord.librechat.ai

## Directory Structure

```
k3s-librechat-deployment/
├── README.md                               # This file
├── MIGRATION_GUIDE.md                      # Helm 4 + Infisical migration guide
├── librechat-values.yaml                   # Helm values configuration
├── manifests/
│   ├── namespace.yaml                      # Kubernetes namespace
│   ├── cert-issuer.yaml                    # Let's Encrypt SSL issuer
│   ├── secret-template.yaml                # Kubernetes secret template
│   ├── secret.yaml                         # Your actual secrets (git-ignored)
│   ├── infisical-operator-values.yaml      # Infisical operator Helm values
│   └── infisical-secret-crd.yaml           # InfisicalSecret CRD for secret sync
├── scripts/
│   ├── deploy.sh                           # Deployment script (Helm 4 compatible)
│   ├── upgrade.sh                          # Upgrade script
│   ├── cleanup.sh                          # Cleanup script
│   ├── install-infisical-operator.sh       # Infisical operator installation
│   ├── generate-secrets.sh                 # Secret generation helper
│   ├── logs.sh                             # Log viewing helper
│   └── status.sh                           # Status checking helper
└── examples/
    ├── .env.example                        # Environment variables reference
    └── librechat-config.example.yaml       # Advanced config examples
```

## License

This deployment configuration is part of the LibreChat project.
See the main repository for license information.
