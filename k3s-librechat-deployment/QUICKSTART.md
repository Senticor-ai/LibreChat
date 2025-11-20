# LibreChat k3s Quick Start Guide

Get LibreChat running on your k3s cluster in under 10 minutes!

## Prerequisites Checklist

- [ ] k3s cluster running: `kubectl get nodes`
- [ ] **Helm 4** installed: `helm version` (should show v4.x.x)
  - Install: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash`
- [ ] **Two domains** pointing to your cluster IP:
  - `infisical.yourdomain.com` for self-hosted Infisical
  - `chat.yourdomain.com` for LibreChat
- [ ] At least one LLM API key (OpenRouter, Anthropic, etc.)

## Deployment with Self-Hosted Infisical

### 1. Configure Infisical Deployment (2 minutes)

**Edit Infisical secrets:**
```bash
vim manifests/infisical-standalone-secret.yaml
```

Generate and set these values:
```bash
# Generate AUTH_SECRET
openssl rand -base64 32

# Generate ENCRYPTION_KEY
openssl rand -hex 16
```

Update in `infisical-standalone-secret.yaml`:
- `AUTH_SECRET` - paste the base64 value
- `ENCRYPTION_KEY` - paste the hex value
- `SITE_URL` - set to `https://infisical.yourdomain.com`

**Edit Infisical values:**
```bash
vim manifests/infisical-standalone-values.yaml
```

Update these fields:
- Line 38: `host: infisical.yourdomain.com`
- Line 51: `password:` (generate with `openssl rand -base64 32`)
- Line 73: `password:` (generate with `openssl rand -base64 32`)

### 2. Deploy Infisical to k3s (5 minutes)

```bash
cd scripts
./install-infisical.sh
```

Wait for SSL certificate to be provisioned (~5-10 minutes):
```bash
kubectl get certificate -n infisical
# Wait for READY = True
```

### 3. Set Up Infisical Project (3 minutes)

1. **Create account**: Go to `https://infisical.yourdomain.com`
2. **Create organization**: Follow the setup wizard
3. **Create project**: Name it `librechat`
4. **Add secrets** in `prod` environment:
   ```bash
   # Generate these values
   openssl rand -hex 32  # CREDS_KEY
   openssl rand -hex 16  # CREDS_IV
   openssl rand -hex 32  # JWT_SECRET
   openssl rand -hex 32  # JWT_REFRESH_SECRET
   openssl rand -hex 32  # MEILI_MASTER_KEY
   ```

   Add in Infisical web UI:
   - `CREDS_KEY` - encryption key (from above)
   - `CREDS_IV` - initialization vector (from above)
   - `JWT_SECRET` - JWT signing secret (from above)
   - `JWT_REFRESH_SECRET` - JWT refresh secret (from above)
   - `MEILI_MASTER_KEY` - MeiliSearch key (from above)
   - `OPENROUTER_API_KEY` - your OpenRouter key (sk-or-...)

5. **Create Machine Identity**:
   - Go to Organization Settings → Access Control → Machine Identities
   - Create identity: `k3s-librechat-operator`
   - Configure Universal Auth
   - **Save Client ID and Client Secret**

6. **Grant Project Access**:
   - Go to `librechat` project → Settings → Access Control
   - Add the `k3s-librechat-operator` identity as Developer/Admin

### 4. Install Infisical Operator (2 minutes)

```bash
./install-infisical-operator.sh
```

Choose **namespace-scoped** mode when prompted (recommended for production).

### 5. Connect Kubernetes to Infisical (1 minute)

```bash
kubectl create secret generic infisical-universal-auth \
  --from-literal=clientId="<your-client-id>" \
  --from-literal=clientSecret="<your-client-secret>" \
  --namespace librechat
```

### 6. Update InfisicalSecret CRD (1 minute)

```bash
vim manifests/infisical-secret-crd.yaml
```

Update these fields:
```yaml
secretsScope:
  projectSlug: "librechat"  # Your project slug
  envSlug: "prod"           # Your environment
```

Apply:
```bash
kubectl apply -f manifests/infisical-secret-crd.yaml
```

### 7. Configure Domain & Deploy (2 minutes)

```bash
# Update domain
vim librechat-values.yaml
# Replace: chat.example.com → your-domain.com

# Deploy
cd scripts
./deploy.sh
```

🎉 **Done!** Your secrets auto-sync every 60 seconds and pods auto-restart on changes.

## Access LibreChat

Open `https://chat.yourdomain.com` in your browser!

**First steps:**
1. Click "Sign up" to create your account
2. Start chatting!
3. **Important**: After creating your account, add `ALLOW_REGISTRATION: "false"` in your Infisical dashboard to disable public registration

## Useful Commands

```bash
# Check deployment status
./status.sh

# View logs
./logs.sh

# Upgrade to latest version
./upgrade.sh

# Remove deployment
./cleanup.sh
```

## Common Issues

### Infisical not accessible
- **Check certificate**: `kubectl get certificate -n infisical` (wait for READY = True)
- **Check pods**: `kubectl get pods -n infisical`
- **Check ingress**: `kubectl get ingress -n infisical`
- **View logs**: `kubectl logs -n infisical -l app.kubernetes.io/name=infisical -f`
- **DNS**: Ensure `infisical.yourdomain.com` points to your cluster IP

### Secrets not syncing to LibreChat
- **Check operator**: `kubectl get pods -n infisical-operator-system`
- **Check InfisicalSecret**: `kubectl get infisicalsecret -n librechat`
- **Check description**: `kubectl describe infisicalsecret librechat-credentials -n librechat`
- **Check auth secret**: `kubectl get secret infisical-universal-auth -n librechat`
- **Verify synced secret**: `kubectl get secret librechat-credentials-env -n librechat`

### Pods stuck in "Pending"
- Check: `kubectl describe pod -n librechat <pod-name>`
- Usually: Insufficient resources or storage issues

### Certificate not provisioning
- Check DNS is pointing to cluster IP (both domains!)
- Ensure port 80 is accessible (required for Let's Encrypt)
- View logs: `kubectl logs -n cert-manager -l app=cert-manager -f`

### Can't access LibreChat
- Check ingress: `kubectl get ingress -n librechat`
- Check nginx controller: `kubectl get pods -n ingress-nginx`
- View nginx logs: `kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller`

## Next Steps

- [ ] **Security**: Set `ALLOW_REGISTRATION: "false"` in Infisical after creating your account
- [ ] **Test auto-reload**: Update a secret in Infisical dashboard and watch pods restart automatically
- [ ] **Add LLM providers**: Add more API keys in Infisical (ANTHROPIC_API_KEY, GOOGLE_API_KEY, etc.)
- [ ] **Set up backups**: Configure regular backups (see README.md)
- [ ] **Configure autoscaling**: For production use (see README.md)
- [ ] **Add MCP servers**: For custom tools and integrations

## Why Helm 4?

Helm 4 (released November 2025) brings significant improvements:

- 🚀 **60% faster** chart operations
- 🔧 **Server-Side Apply** for better GitOps workflows
- 🔐 **WebAssembly plugins** for enhanced security
- 📦 **Improved OCI** registry support with better OAuth
- 🔍 **kstatus watcher** for better resource health monitoring

This deployment requires Helm 4 to take advantage of these modern features.

## Need Help?

- Full documentation: [README.md](README.md)
- LibreChat docs: https://docs.librechat.ai
- Discord: https://discord.librechat.ai

## Key Configuration Files

```
k3s-librechat-deployment/
├── librechat-values.yaml                  ← Main Helm configuration (domain, resources)
├── manifests/
│   ├── infisical-secret-crd.yaml         ← Infisical secret sync config
│   └── cert-issuer.yaml                   ← SSL configuration
└── scripts/
    ├── install-infisical-operator.sh      ← Install Infisical operator
    ├── deploy.sh                          ← Deploy LibreChat
    ├── upgrade.sh                         ← Upgrade deployment
    ├── status.sh                          ← Check status
    └── logs.sh                            ← View logs
```

**Namespace**: All resources are deployed to the `librechat` namespace

That's it! Happy chatting! 🚀
